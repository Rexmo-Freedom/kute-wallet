import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/services/accumulation_address_cache.dart';
import 'package:kute/services/api/orchestra_api.dart'
    show StandingRequestException;
import 'package:kute/services/orchestra/receive_route_availability.dart';
import 'package:kute/services/orchestra/reusable_deposit_address.dart';
import 'package:kute/services/orchestra/standing_deposit_store.dart';
import 'package:kute/services/orchestra/standing_deposit_sweep.dart'
    show ReceiveAddressWatch;
import 'package:kute/services/orchestra_routes.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';

import '../../helpers/runtime_policy_fixture.dart';

const _spark =
    'sp1pgssy7d7vel0nh9m4326qc54e6rskpczn07dktww9rv4nu5ptvt0s9ucez8h3s';
const _standingEvm = '0x1111111111111111111111111111111111111111';
const _legacyEvm = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';

/// One standing destination and nothing else: `spark:USDB`, for the
/// Dollars receive and for the Bitcoin receive's "other coins" (which
/// opens the same Dollars sheet). No legacy accumulation address is ever
/// created, reused or shown, and nothing is ever registered into Bitcoin.
void main() {
  late Directory tmp;
  late List<String> standingCalls;
  late List<Map<String, dynamic>> registered;
  late List<String?> keys;
  late Set<String> destinations;
  late Object? standingFailure;
  late Map<String, dynamic> Function(Map<String, dynamic> body) answer;
  final events = <(String, Map<String, Object>?)>[];
  late Future<Map<String, dynamic>> Function(
      {required String operation,
      String? label,
      required bool Function() current,
      Map<String, dynamic>? body,
      String? idempotencyKey,
      int offset}) original;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('reusable_deposit_');
    Hive.init(tmp.path);
    await AccumulationAddressCache.init();
    await ReceiveRouteAvailability.clear();
    StandingDepositStore.forgetDestinations();
    setLiveOrchestraRouteCatalog(const OrchestraRouteCatalog(
      send: kOrchestraSendRoutes,
      receive: kOrchestraReceiveRoutes,
      usdReceive: kOrchestraUsdReceiveRoutes,
    ));
    dotenv.loadFromString(envString: 'BACKEND=https://backend.test');
    AffiliateService.debugSessionToken = 'test-session';
    final policy = runtimePolicyFixture(revision: 4);
    RuntimeCapabilitiesService.debugInstance = policy;
    expect(await policy.refresh(), isTrue);
    events.clear();
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));

    standingCalls = [];
    registered = [];
    keys = [];
    destinations = {'spark:USDB', 'bitcoin:BTC'};
    standingFailure = null;
    answer = (body) => {
          'enabled': true,
          'addresses': {'base': _standingEvm, 'tron': 'T'},
          'kuteFeePolicy': {'revision': 4, 'purpose': 'usdb_swap_deposit'},
        };
    original = StandingDepositStore.standingRequest;
    final provider = <String, Map<String, dynamic>>{};
    StandingDepositStore.standingRequest = (
        {required operation,
        label,
        required current,
        body,
        idempotencyKey,
        offset = 0}) async {
      standingCalls.add(operation);
      final failure = standingFailure;
      if (failure != null && operation == 'register') throw failure;
      switch (operation) {
        case 'destinations':
          return {
            'destinations': [
              for (final pair in destinations)
                {'chain': pair.split(':')[0], 'asset': pair.split(':')[1]}
            ]
          };
        case 'mine':
          return {'references': const []};
        case 'register':
          registered.add(body!);
          keys.add(idempotencyKey);
          return provider[label!] ??= {
            'standingAddressId': 'sda_$label',
            ...answer(body),
          };
        case 'read':
          final state = provider[label];
          if (state == null) throw const StandingRequestException(404, null);
          // A read answers without the instruction or the fee terms.
          return {
            'standingAddressId': state['standingAddressId'],
            'enabled': state['enabled'],
            'addresses': state['addresses'],
          };
      }
      throw StateError('unexpected $operation');
    };
  });

  tearDown(() async {
    StandingDepositStore.standingRequest = original;
    StandingDepositStore.forgetDestinations();
    RuntimeCapabilitiesService.debugInstance?.dispose();
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
    TrackingService.debugTrackObserver = null;
    await ReceiveRouteAvailability.clear();
    await Hive.deleteFromDisk();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Any HTTP request (the legacy accumulation endpoint among them) fails
  /// the test: the standing rail is reached only through the seam.
  Future<T> offline<T>(Future<T> Function() body) => http.runWithClient(
        body,
        () => MockClient((req) async {
          fail('unexpected network call to ${req.url}');
        }),
      );

  Future<ReusableDepositAddress> resolve({
    String destinationAsset = 'USDB',
    String sourceChain = 'base',
    String sourceAsset = 'USDC',
    void Function(DepositAddressModel)? onAttempt,
  }) =>
      offline(() => ReusableDepositAddressService.resolve(
          walletId: 'a',
          recipient: _spark,
          destinationAsset: destinationAsset,
          sourceChain: sourceChain,
          sourceAsset: sourceAsset,
          wanted: () => true,
          onAttempt: onAttempt));

  Future<void> seedLegacy(String destinationAsset) async {
    await Hive.box<String>('accumulation_addresses').put(
        'base:USDC:$destinationAsset:$_spark',
        jsonEncode({
          'accumulationAddressId': 'acc_cached',
          'sourceChain': 'base',
          'sourceAsset': 'USDC',
          'destinationAsset': destinationAsset,
          'recipientSparkAddress': _spark,
          'depositAddress': _legacyEvm,
          'enabled': true,
          'createdAt': '2026-07-01T00:00:00Z',
          'kuteFeePolicy': {'revision': 4, 'appFeeBps': 50},
        }));
  }

  group('Dollars (spark:USDB), unchanged', () {
    test('registers spark:USDB with the own Spark recipient, then reuses it',
        () async {
      final attempts = <DepositAddressModel>[];
      final resolved = await resolve(onAttempt: attempts.add);
      expect(resolved.model, DepositAddressModel.standing);
      expect(resolved.address, _standingEvm);
      expect(resolved.id, startsWith('sda_'));
      expect(attempts, [DepositAddressModel.standing]);
      final label = StandingDepositStore.labelFor(_spark, 'USDB', 4);
      expect(resolved.standing!.label, label);
      expect(resolved.standing!.chain, 'spark');
      expect(registered.single, {
        'destination': {'chain': 'spark', 'asset': 'USDB', 'address': _spark},
        'slippageBps': 50,
      });
      expect(keys.single, 'register-$label');
      final created = events
          .where((e) => e.$1 == 'reusable_deposit_address_created')
          .single
          .$2!;
      expect(created, {
        'source_chain': 'base',
        'source_asset': 'USDC',
        'destination_asset': 'USDB',
        'model': 'standing',
      });

      final again = await resolve();
      expect(again.address, _standingEvm);
      expect(registered, hasLength(1));
      expect(
          events
              .where((e) => e.$1 == 'reusable_deposit_address_reused')
              .single
              .$2,
          {
            'source_chain': 'base',
            'source_asset': 'USDC',
            'model': 'standing'
          });
    });

    test(
        'a coin the standing rail cannot fund is unavailable and no legacy '
        'address is made', () async {
      // Tron carries USDT only on the standing rail.
      Object? failure;
      try {
        await resolve(sourceChain: 'tron', sourceAsset: 'USDC');
      } catch (e) {
        failure = e;
      }
      final refused = failure as ReceiveRouteUnavailableException;
      expect(refused.model, DepositAddressModel.standing);
      expect(refused.category, 'no_route');
      expect(TrackingService.errorCategory(refused), 'no_route');
      expect(
          ReceiveRouteAvailability.isUnavailable(
              sourceChain: 'tron',
              sourceAsset: 'USDC',
              destinationAsset: 'USDB'),
          isTrue);
      expect(standingCalls, isEmpty);
      expect(AccumulationAddressCache.getAll(), isEmpty);
    });

    test('a cached legacy USDB address is never shown or reused', () async {
      await seedLegacy('USDB');
      final resolved = await resolve();
      expect(resolved.address, _standingEvm);
      expect(resolved.address, isNot(_legacyEvm));
      // Still there for the silent sweep, never offered.
      expect(AccumulationAddressCache.sweepTargets().single.depositAddress,
          _legacyEvm);

      // With no standing route, the coin is refused rather than handed
      // the cached legacy address.
      destinations = {'bitcoin:BTC'};
      StandingDepositStore.forgetDestinations();
      await Hive.box<String>('standing_deposits_v1').clear();
      await expectLater(
          resolve(), throwsA(isA<ReceiveRouteUnavailableException>()));
    });
  });

  test('a Bitcoin destination is never registered, standing or legacy',
      () async {
    await seedLegacy('BTC');
    destinations = {'spark:USDB', 'spark:BTC'};
    await expectLater(
        resolve(destinationAsset: 'BTC'), throwsA(isA<StateError>()));
    expect(registered, isEmpty);
    // The legacy address stays silently watched, never offered.
    expect(AccumulationAddressCache.sweepTargets().single.id, 'acc_cached');
  });

  test('a registration refused for the route marks it unavailable', () async {
    standingFailure = const StandingRequestException(400, 'unsupported_route');
    await expectLater(
        resolve(), throwsA(isA<ReceiveRouteUnavailableException>()));
    expect(
        ReceiveRouteAvailability.isUnavailable(
            sourceChain: 'base', sourceAsset: 'USDC', destinationAsset: 'USDB'),
        isTrue);
    standingCalls.clear();
    await expectLater(
        resolve(), throwsA(isA<ReceiveRouteUnavailableException>()));
    expect(standingCalls, isEmpty);
  });

  test('a transient standing failure is retryable and refuses nothing',
      () async {
    standingFailure = const StandingRequestException(503, null);
    await expectLater(resolve(), throwsA(isA<StandingRequestException>()));
    expect(
        ReceiveRouteAvailability.isUnavailable(
            sourceChain: 'base', sourceAsset: 'USDC', destinationAsset: 'USDB'),
        isFalse);
  });

  test('HyperCore is refused before anything is asked', () async {
    await expectLater(resolve(sourceChain: 'hypercore', sourceAsset: 'USDC'),
        throwsA(isA<ReceiveRouteUnavailableException>()));
    expect(standingCalls, isEmpty);
  });

  test('every address shown arms the watch on its deposits, on any screen',
      () async {
    ReceiveAddressWatch.reset();
    addTearDown(ReceiveAddressWatch.reset);
    standingFailure = const StandingRequestException(429, null);
    await expectLater(resolve(), throwsA(isA<StandingRequestException>()));
    expect(ReceiveAddressWatch.watching, isFalse);

    standingFailure = null;
    await resolve();
    expect(ReceiveAddressWatch.watching, isTrue);
  });

  test('standingReceiveOffered lists only coins that can get an address', () {
    bool offered(Set<String> d, String chain, String asset, String dest) =>
        standingReceiveOffered(
            destinations: d,
            sourceChain: chain,
            sourceAsset: asset,
            destinationAsset: dest);
    expect(offered({'spark:USDB'}, 'base', 'USDC', 'USDB'), isTrue);
    expect(offered({'bitcoin:BTC'}, 'base', 'USDC', 'USDB'), isFalse);
    expect(offered({'spark:USDB'}, 'tron', 'USDC', 'USDB'), isFalse);
    expect(offered(const {}, 'base', 'USDC', 'USDB'), isFalse);
  });

  test(
      'venue paths are untouched: the Investing withdrawal still registers '
      'its own routed spark:BTC and spark:USDB instructions', () async {
    const eoa = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';
    answer = (body) => {
          'enabled': true,
          'addresses': {'arbitrum': _standingEvm},
          'kuteFeePolicy': {'revision': 4, 'purpose': 'venue_withdrawal'},
        };
    for (final destination in [
      InvestingWithdrawalDestination.bitcoin,
      InvestingWithdrawalDestination.dollars,
    ]) {
      final record = await offline(
          () => StandingDepositStore.investingWithdrawalInstruction(
              walletId: 'a',
              recipient: _spark,
              refundAddress: eoa,
              wanted: () => true,
              destination: destination));
      expect(record.addressFor('arbitrum'), _standingEvm);
      expect(registered.last, {
        'destination': {
          'chain': 'spark',
          'asset': destination.asset,
          'address': _spark,
        },
        'slippageBps': 50,
        'refundAddresses': {'arbitrum': eoa.toLowerCase()},
        'kuteRoute': 'investing_withdrawal',
      });
    }
  });
}
