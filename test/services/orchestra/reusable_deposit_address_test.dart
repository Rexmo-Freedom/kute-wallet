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
import 'package:kute/services/orchestra_routes.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/security/address_history.dart';
import 'package:kute/services/tracking_service.dart';

import '../../helpers/runtime_policy_fixture.dart';

const _spark =
    'sp1pgssy7d7vel0nh9m4326qc54e6rskpczn07dktww9rv4nu5ptvt0s9ucez8h3s';
const _standingEvm = '0x1111111111111111111111111111111111111111';
const _legacyEvm = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';
const _legacyTron = 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t';

/// Standing first, legacy second: the rail choice both receive screens
/// share, exercised without the screens.
void main() {
  late Directory tmp;
  late List<String> standingCalls;
  late List<Map<String, dynamic>> legacyPosts;
  late Set<String> destinations;
  late Object? standingFailure;
  late http.Response Function(Map<String, dynamic> sent) legacyAnswer;
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
    await Hive.openBox<String>('accumulation_addresses');
    await AddressHistory.open();
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
    legacyPosts = [];
    destinations = {'spark:USDB'};
    standingFailure = null;
    legacyAnswer = (sent) => http.Response(
        jsonEncode({
          'accumulationAddressId': 'acc_minted',
          'sourceChain': sent['sourceChain'],
          'sourceAsset': sent['sourceAsset'],
          'destinationAsset': sent['destinationAsset'],
          'recipientSparkAddress': sent['recipientSparkAddress'],
          // The cache re-verifies the deposit format per chain.
          'depositAddress':
              sent['sourceChain'] == 'tron' ? _legacyTron : _legacyEvm,
          'enabled': true,
          'createdAt': '2026-10-12T12:00:00Z',
          'kuteFeePolicy': {
            'revision': 4,
            'appFeeBps': 50,
            'providerDefault': false
          },
        }),
        201);
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
          return provider[label!] ??= {
            'standingAddressId': 'sda_$label',
            'enabled': true,
            'addresses': {'base': _standingEvm, 'tron': 'T'},
            'kuteFeePolicy': {'revision': 4},
          };
        case 'read':
          final state = provider[label];
          if (state == null) throw const StandingRequestException(404, null);
          return state;
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

  Future<T> withLegacy<T>(Future<T> Function() body) => http.runWithClient(
        body,
        () => MockClient((req) async {
          expect(req.url.path, '/api/v1/orchestra/accumulation-addresses');
          final sent = jsonDecode(req.body) as Map<String, dynamic>;
          legacyPosts.add(sent);
          return legacyAnswer(sent);
        }),
      );

  Future<ReusableDepositAddress> resolve({
    String destinationAsset = 'USDB',
    String sourceChain = 'base',
    String sourceAsset = 'USDC',
    void Function(DepositAddressModel)? onAttempt,
  }) =>
      ReusableDepositAddressService.resolve(
          walletId: 'a',
          recipient: _spark,
          destinationAsset: destinationAsset,
          sourceChain: sourceChain,
          sourceAsset: sourceAsset,
          wanted: () => true,
          onAttempt: onAttempt);

  test('a standing destination is served by the standing rail alone', () async {
    final attempts = <DepositAddressModel>[];
    final resolved = await withLegacy(() => resolve(onAttempt: attempts.add));
    expect(resolved.model, DepositAddressModel.standing);
    expect(resolved.address, _standingEvm);
    expect(resolved.id, startsWith('sda_'));
    expect(resolved.standing, isNotNull);
    expect(attempts, [DepositAddressModel.standing]);
    expect(legacyPosts, isEmpty);
    expect(standingCalls, contains('register'));
    final created = events
        .where((e) => e.$1 == 'reusable_deposit_address_created')
        .single
        .$2!;
    expect(created['model'], 'standing');
    expect(created['source_chain'], 'base');
    expect(created['destination_asset'], 'USDB');
    expect(created.keys, isNot(contains('address')));

    // The second visit reuses the same standing address and says so.
    final again = await withLegacy(() => resolve());
    expect(again.address, _standingEvm);
    expect(
        events
            .where((e) => e.$1 == 'reusable_deposit_address_reused')
            .single
            .$2!['model'],
        'standing');
    expect(standingCalls.where((c) => c == 'register'), hasLength(1));
  });

  test(
      'a destination the provider has no standing address for falls back '
      'to the legacy rail (spark:BTC today)', () async {
    final attempts = <DepositAddressModel>[];
    final resolved = await withLegacy(
        () => resolve(destinationAsset: 'BTC', onAttempt: attempts.add));
    expect(resolved.model, DepositAddressModel.accumulation);
    expect(resolved.address, _legacyEvm);
    expect(resolved.id, 'acc_minted');
    expect(resolved.standing, isNull);
    expect(attempts,
        [DepositAddressModel.standing, DepositAddressModel.accumulation]);
    expect(standingCalls, contains('destinations'));
    expect(standingCalls, isNot(contains('register')));
    expect(legacyPosts.single['destinationAsset'], 'BTC');
    expect(
        events
            .where((e) => e.$1 == 'reusable_deposit_address_created')
            .single
            .$2!['model'],
        'accumulation');
  });

  test('the destination list is read once per quarter hour, not per pick',
      () async {
    await withLegacy(() => resolve(destinationAsset: 'BTC'));
    await withLegacy(() => resolve(destinationAsset: 'BTC'));
    expect(standingCalls.where((c) => c == 'destinations'), hasLength(1));
    // Once the provider lists spark:BTC, the bitcoin receive moves over.
    destinations = {'spark:USDB', 'spark:BTC'};
    StandingDepositStore.forgetDestinations();
    final moved = await withLegacy(() => resolve(destinationAsset: 'BTC'));
    expect(moved.model, DepositAddressModel.standing);
  });

  test('a source outside the standing rail uses the legacy rail', () async {
    // Tron carries USDT only on the standing rail; a Tron source asset the
    // rail does not fund goes straight to the legacy mint.
    setLiveOrchestraRouteCatalog(OrchestraRouteCatalog(
      send: kOrchestraSendRoutes,
      receive: {
        ...kOrchestraReceiveRoutes,
        'USDC': {'tron', 'base'}
      },
      usdReceive: {
        ...kOrchestraUsdReceiveRoutes,
        'USDC': {'tron', 'base'}
      },
    ));
    final resolved = await withLegacy(
        () => resolve(sourceChain: 'tron', sourceAsset: 'USDC'));
    expect(resolved.model, DepositAddressModel.accumulation);
    expect(standingCalls, isEmpty);
    expect(legacyPosts.single['sourceChain'], 'tron');
  });

  test('a legacy refusal marks the pair unavailable and refuses the receive',
      () async {
    legacyAnswer = (_) => http.Response(
        jsonEncode({
          'error': {
            'code': 'invalid_request',
            'message': 'Unsupported deposit source: tron:USDC'
          }
        }),
        400);
    setLiveOrchestraRouteCatalog(OrchestraRouteCatalog(
      send: kOrchestraSendRoutes,
      receive: {
        ...kOrchestraReceiveRoutes,
        'USDC': {'tron', 'base'}
      },
      usdReceive: {
        ...kOrchestraUsdReceiveRoutes,
        'USDC': {'tron', 'base'}
      },
    ));
    Object? failure;
    try {
      await withLegacy(() => resolve(sourceChain: 'tron', sourceAsset: 'USDC'));
    } catch (e) {
      failure = e;
    }
    expect(failure, isA<ReceiveRouteUnavailableException>());
    final refused = failure as ReceiveRouteUnavailableException;
    expect(refused.model, DepositAddressModel.accumulation);
    expect(refused.category, 'unsupported_source');
    expect(TrackingService.errorCategory(refused), 'unsupported_source');
    expect(
        ReceiveRouteAvailability.isUnavailable(
            sourceChain: 'tron', sourceAsset: 'USDC', destinationAsset: 'USDB'),
        isTrue);
    // The offering now drops it, and the next attempt is refused without
    // asking either rail again.
    expect(
        orchestraReceiveChainForDestination('USDC', 'tron',
            destinationAsset: 'USDB'),
        isNull);
    standingCalls.clear();
    legacyPosts.clear();
    await expectLater(
        withLegacy(() => resolve(sourceChain: 'tron', sourceAsset: 'USDC')),
        throwsA(isA<ReceiveRouteUnavailableException>()));
    expect(standingCalls, isEmpty);
    expect(legacyPosts, isEmpty);
    // No address, id or provider text in what gets tracked.
    expect(events.where((e) => e.$1 == 'reusable_deposit_address_created'),
        isEmpty);
  });

  test('a transient standing failure is retryable and never mints legacy',
      () async {
    standingFailure = const StandingRequestException(503, null);
    await expectLater(
        withLegacy(() => resolve()), throwsA(isA<StandingRequestException>()));
    expect(legacyPosts, isEmpty);
    expect(
        ReceiveRouteAvailability.isUnavailable(
            sourceChain: 'base', sourceAsset: 'USDC', destinationAsset: 'USDB'),
        isFalse);
  });

  test('a standing registration refused for the route tries the legacy rail',
      () async {
    standingFailure = const StandingRequestException(400, 'unsupported_route');
    final resolved = await withLegacy(() => resolve());
    expect(resolved.model, DepositAddressModel.accumulation);
    expect(legacyPosts, hasLength(1));
  });

  test('HyperCore is refused before any rail is asked', () async {
    await expectLater(
        withLegacy(
            () => resolve(sourceChain: 'hypercore', sourceAsset: 'USDC')),
        throwsA(isA<ReceiveRouteUnavailableException>()));
    expect(standingCalls, isEmpty);
    expect(legacyPosts, isEmpty);
    expect(AccumulationAddressCache.getAll(), isEmpty);
  });
}
