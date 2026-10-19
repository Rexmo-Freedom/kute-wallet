import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/services/accumulation_address_cache.dart';
import 'package:kute/services/api/orchestra_api.dart'
    show StandingRequestException;
import 'package:kute/services/orchestra/orchestra_capability_requirements.dart';
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

/// One standing destination and nothing else: `spark:USDB`, the reusable
/// address of the Dollars receive and of the Bitcoin receive's "other
/// coins", tried first; where it cannot serve a coin the refusal says why
/// so the screen falls back to a one-time address. No legacy accumulation
/// address is ever created, reused or shown (any HTTP request fails these
/// tests), and nothing is ever registered into Bitcoin.
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
    StandingReceiveRefusal.clear();
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
    StandingReceiveRefusal.clear();
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

  Future<StandingUnavailableException> refusal(
      Future<Object?> Function() body) async {
    try {
      await body();
    } on StandingUnavailableException catch (e) {
      return e;
    }
    fail('expected the standing route to refuse');
  }

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

  group('Dollars (spark:USDB)', () {
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
        'a coin the standing rail cannot fund is unserved before anything is '
        'asked, and no legacy address is made', () async {
      // Tron carries USDT only on the standing rail.
      final refused = await refusal(
          () => resolve(sourceChain: 'tron', sourceAsset: 'USDC'));
      expect(refused.reason, StandingFallbackReason.standingUnserved);
      expect(refused.model, DepositAddressModel.standing);
      expect(TrackingService.errorCategory(refused), 'no_route');
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

      // With spark:USDB off the standing destinations, the coin is
      // unserved rather than handed the cached legacy address.
      destinations = {'bitcoin:BTC'};
      StandingDepositStore.forgetDestinations();
      await Hive.box<String>('standing_deposits_v1').clear();
      final refused = await refusal(resolve);
      expect(refused.reason, StandingFallbackReason.standingUnserved);
    });

    test(
        'an instruction with no address on the source chain is '
        'no_source_address, and that pair is remembered', () async {
      final refused = await refusal(
          () => resolve(sourceChain: 'arbitrum', sourceAsset: 'USDC'));
      expect(refused.reason, StandingFallbackReason.noSourceAddress);
      expect(
          ReceiveRouteAvailability.isUnavailable(
              sourceChain: 'arbitrum',
              sourceAsset: 'USDC',
              destinationAsset: 'USDB'),
          isTrue);
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

  group('the backend refuses standing (422 unsupported_route)', () {
    setUp(() => standingFailure =
        const StandingRequestException(422, 'unsupported_route'));

    test(
        'is standing_refused, remembered for the session so the next coin '
        'asks nothing, and never stored per pair', () async {
      final refused = await refusal(resolve);
      expect(refused.reason, StandingFallbackReason.standingRefused);
      expect(standingCalls.where((c) => c == 'register'), hasLength(1));
      expect(StandingReceiveRefusal.active(RuntimeCapabilitiesService.instance),
          isTrue);
      // Not a per-pair refusal on disk: switching standing back on brings
      // every coin back at once.
      expect(
          ReceiveRouteAvailability.isUnavailable(
              sourceChain: 'base',
              sourceAsset: 'USDC',
              destinationAsset: 'USDB'),
          isFalse);

      standingCalls.clear();
      for (final (chain, asset) in [('base', 'USDC'), ('solana', 'USDC')]) {
        final again = await refusal(
            () => resolve(sourceChain: chain, sourceAsset: asset));
        expect(again.reason, StandingFallbackReason.standingRefused);
      }
      expect(standingCalls, isEmpty, reason: 'the refusal is remembered');
      expect(standingReceiveFallback(sourceChain: 'base', sourceAsset: 'USDC'),
          StandingFallbackReason.standingRefused);
    });

    test('a new policy revision forgets it and standing is asked again',
        () async {
      var revision = 4;
      final policy = runtimePolicyFixture(revisionOf: () => revision);
      RuntimeCapabilitiesService.debugInstance?.dispose();
      RuntimeCapabilitiesService.debugInstance = policy;
      expect(await policy.refresh(), isTrue);
      await refusal(resolve);
      standingCalls.clear();
      await refusal(resolve);
      expect(standingCalls, isEmpty);

      // The operator switches standing back on: a new revision.
      revision = 5;
      expect(await policy.refresh(fresh: true), isTrue);
      expect(StandingReceiveRefusal.active(policy), isFalse);
      standingFailure = null;
      answer = (body) => {
            'enabled': true,
            'addresses': {'base': _standingEvm},
            'kuteFeePolicy': {'revision': 5, 'purpose': 'usdb_swap_deposit'},
          };
      final resolved = await resolve();
      expect(resolved.address, _standingEvm);
      expect(standingCalls, contains('register'));
    });

    test('and is forgotten after its time', () {
      final policy = RuntimeCapabilitiesService.instance;
      final at = DateTime(2026, 10, 19, 12);
      StandingReceiveRefusal.remember(policy, now: at);
      expect(
          StandingReceiveRefusal.active(policy,
              now: at.add(const Duration(minutes: 14))),
          isTrue);
      expect(
          StandingReceiveRefusal.active(policy,
              now: at.add(StandingReceiveRefusal.ttl)),
          isFalse);
    });
  });

  group('orchestra.standing_addresses', () {
    Future<void> usePolicy(RuntimeCapabilitiesService policy) async {
      RuntimeCapabilitiesService.debugInstance?.dispose();
      RuntimeCapabilitiesService.debugInstance = policy;
      expect(await policy.refresh(), isTrue);
    }

    test('denied by the policy: no standing request at all', () async {
      await usePolicy(runtimePolicyFixture(
          revision: 4,
          also: {kStandingAddressCapability},
          blocked: {kStandingAddressCapability}));
      expect(standingAddressPolicy(RuntimeCapabilitiesService.instance),
          StandingPolicy.denied);
      final refused = await refusal(resolve);
      expect(refused.reason, StandingFallbackReason.standingPolicyOff);
      expect(standingCalls, isEmpty);
    });

    test('allowed by the policy: registered', () async {
      await usePolicy(runtimePolicyFixture(
          revision: 4, also: {kStandingAddressCapability}));
      expect(standingAddressPolicy(RuntimeCapabilitiesService.instance),
          StandingPolicy.allowed);
      await resolve();
      expect(registered, hasLength(1));
    });

    test(
        'absent from the policy (an older backend): not a denial, the '
        'registration is tried', () async {
      // The default fixture does not name the switch.
      expect(
          RuntimeCapabilitiesService.instance
              .decision(kStandingAddressCapability)
              .allowed,
          isFalse);
      expect(standingAddressPolicy(RuntimeCapabilitiesService.instance),
          StandingPolicy.unknown);
      await resolve();
      expect(registered, hasLength(1));
    });

    test('with no readable policy it is unknown, never a denial', () async {
      final policy = RuntimeCapabilitiesService.forTesting(
        client: MockClient((_) async => http.Response('', 503)),
        baseUrl: () => 'https://policy.test',
        sessionToken: () => AffiliateService.sessionToken,
      );
      addTearDown(policy.dispose);
      expect(await policy.refresh(), isFalse);
      expect(standingAddressPolicy(policy), StandingPolicy.unknown);
    });

    test('crypto deposits off: the standing route is policy-off too', () async {
      await usePolicy(
          runtimePolicyFixture(revision: 4, blocked: {'crypto.deposit'}));
      expect(standingReceiveFallback(sourceChain: 'base', sourceAsset: 'USDC'),
          StandingFallbackReason.standingPolicyOff);
      await refusal(resolve);
      expect(standingCalls, isEmpty);
    });
  });

  test('a transient standing failure is retryable and refuses nothing',
      () async {
    standingFailure = const StandingRequestException(503, null);
    await expectLater(resolve(), throwsA(isA<StandingRequestException>()));
    expect(StandingReceiveRefusal.active(RuntimeCapabilitiesService.instance),
        isFalse);
    expect(
        ReceiveRouteAvailability.isUnavailable(
            sourceChain: 'base', sourceAsset: 'USDC', destinationAsset: 'USDB'),
        isFalse);
  });

  test('HyperCore is refused before anything is asked', () async {
    final refused = await refusal(
        () => resolve(sourceChain: 'hypercore', sourceAsset: 'USDC'));
    expect(refused.reason, StandingFallbackReason.standingUnserved);
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

  group('the coins offered', () {
    final catalog = OrchestraRoutesCatalog.fromJson(
      {
        'assets': [
          for (final (chain, asset, decimals) in [
            ('spark', 'BTC', 8),
            ('spark', 'USDB', 6),
            ('base', 'USDC', 6),
            ('tron', 'USDT', 6),
            ('tron', 'USDC', 6),
            ('solana', 'USDC', 6),
            ('hypercore', 'USDC', 8),
          ])
            {
              'id': '$chain:$asset',
              'chain': chain,
              'asset': asset,
              'decimals': decimals,
              'route': {'to': 'all', 'fixedTo': [], 'exactOutTo': []},
            },
        ],
      },
      source: OrchestraCatalogSource.live,
      fetchedAt: DateTime.now(),
    );
    Map<String, bool> rows(String destination, {Set<String>? standing}) => {
          for (final o in receiveOtherCoinOptions(catalog,
              destinationAsset: destination, standingDestinations: standing))
            '${o.chain}:${o.assetCode}': o.reusableAddress,
        };

    test(
        'standing where it may serve, one-time for the rest; never a venue '
        'rail', () {
      for (final destination in ['USDB', 'BTC']) {
        expect(rows(destination, standing: {'spark:USDB'}), {
          'base:USDC': true,
          'tron:USDT': true,
          'solana:USDC': true,
          // Tron carries USDT only on the standing rail.
          'tron:USDC': false,
        });
      }
      // Destinations not read yet: standing is still offered.
      expect(rows('USDB')['base:USDC'], isTrue);
      // spark:USDB not a standing destination: every coin one-time.
      expect(rows('USDB', standing: {'bitcoin:BTC'}).values,
          everyElement(isFalse));
    });

    test('standing denied by the policy: every coin one-time', () async {
      final policy = runtimePolicyFixture(
          revision: 4,
          also: {kStandingAddressCapability},
          blocked: {kStandingAddressCapability});
      RuntimeCapabilitiesService.debugInstance?.dispose();
      RuntimeCapabilitiesService.debugInstance = policy;
      expect(await policy.refresh(), isTrue);
      expect(
          rows('USDB', standing: {'spark:USDB'}).values, everyElement(isFalse));
      expect(rows('USDB', standing: {'spark:USDB'}), hasLength(4));
    });

    test('one-time off: only the standing coins remain', () async {
      final policy = runtimePolicyFixture(
          revision: 4, blocked: {kOneTimeAddressCapability});
      RuntimeCapabilitiesService.debugInstance?.dispose();
      RuntimeCapabilitiesService.debugInstance = policy;
      expect(await policy.refresh(), isTrue);
      expect(rows('BTC', standing: {'spark:USDB'}),
          {'base:USDC': true, 'tron:USDT': true, 'solana:USDC': true});
    });

    test('the fallback row is the one-time row into the destination', () {
      final base = receiveOtherCoinOptions(catalog,
              destinationAsset: 'BTC', standingDestinations: {'spark:USDB'})
          .firstWhere((o) => o.chain == 'base');
      expect(base.reusableAddress, isTrue);
      final oneTime =
          oneTimeFallbackOption(catalog, base, destinationAsset: 'BTC')!;
      expect(oneTime.reusableAddress, isFalse);
      expect('${oneTime.chain}:${oneTime.assetCode}', 'base:USDC');
    });
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
      final record = await offline(() =>
          StandingDepositStore.investingWithdrawalInstruction(
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
