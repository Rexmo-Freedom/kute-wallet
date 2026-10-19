import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart' show l10nForLanguage;
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/screens/shared/coin_asset_grid.dart'
    show receiveCoinGroups;
import 'package:kute/services/api/orchestra_api.dart'
    show StandingRequestException;
import 'package:kute/services/orchestra/receive_route_availability.dart';
import 'package:kute/services/orchestra_routes.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

import '../../helpers/runtime_policy_fixture.dart';

Map<String, dynamic> _row(String chain, String asset, {int decimals = 6}) => {
      'id': '$chain:$asset',
      'chain': chain,
      'asset': asset,
      'decimals': decimals,
      'route': {'to': 'all', 'fixedTo': [], 'exactOutTo': []},
    };

OrchestraRoutesCatalog _catalog(List<Map<String, dynamic>> rows) =>
    OrchestraRoutesCatalog.fromJson(
      {
        'assets': [
          _row('spark', 'BTC', decimals: 8),
          _row('spark', 'USDB'),
          ...rows,
        ],
      },
      source: OrchestraCatalogSource.live,
      fetchedAt: DateTime(2026, 10, 12),
    );

void main() {
  setUp(() async {
    await ReceiveRouteAvailability.clear();
    setLiveOrchestraRouteCatalog(const OrchestraRouteCatalog(
      send: kOrchestraSendRoutes,
      receive: kOrchestraReceiveRoutes,
      usdReceive: kOrchestraUsdReceiveRoutes,
    ));
  });
  tearDown(() => ReceiveRouteAvailability.clear());

  group('refusal classification', () {
    test('the provider naming an unconfigured source is a refusal', () {
      expect(
          ReceiveRouteAvailability.refusalCategory(
              'Unsupported deposit source: tron:TRX',
              statusCode: 400),
          'unsupported_source');
      expect(
          ReceiveRouteAvailability.refusalCategory(
              'Unsupported source chain: bitcoin'),
          'unsupported_source');
      expect(
          ReceiveRouteAvailability.refusalCategory('Invalid request',
              statusCode: 400, errorCode: 'unsupported_route'),
          'unsupported_source');
      expect(
          ReceiveRouteAvailability.refusalCategory(
              'This swap route is no longer available.'),
          'no_route');
    });

    test('a 4xx the rails answer for the route is a refusal', () {
      for (final status in [400, 403, 404, 422]) {
        expect(
            ReceiveRouteAvailability.refusalCategory(
                const StandingRequestException(0, null).toString(),
                statusCode: status),
            'no_route',
            reason: '$status');
        expect(
            ReceiveRouteAvailability.refusalCategory(
                StandingRequestException(status, null)),
            'no_route',
            reason: 'standing $status');
      }
    });

    test('session, fee-terms, rate-limit and outage failures are retryable',
        () {
      for (final status in [401, 408, 409, 429, 500, 502, 503]) {
        expect(
            ReceiveRouteAvailability.refusalCategory('Request failed',
                statusCode: status),
            isNull,
            reason: '$status');
        expect(
            ReceiveRouteAvailability.refusalCategory(
                StandingRequestException(status, null)),
            isNull,
            reason: 'standing $status');
      }
      expect(ReceiveRouteAvailability.refusalCategory('Network error'), isNull);
      expect(
          ReceiveRouteAvailability.refusalCategory(
              'Deposit terms changed. Please try again.'),
          isNull);
      expect(ReceiveRouteAvailability.refusalCategory(null), isNull);
    });

    test('a policy denial is never read as a route refusal', () async {
      final policy = runtimePolicyFixture(blocked: {'crypto.deposit'});
      addTearDown(policy.dispose);
      expect(await policy.refresh(), isTrue);
      Object? denial;
      try {
        await policy.ensureAllAllowed(['crypto.deposit']);
      } catch (e) {
        denial = e;
      }
      expect(denial, isA<CapabilityUnavailableException>());
      expect(ReceiveRouteAvailability.refusalCategory(denial), isNull);
    });
  });

  group('availability memory', () {
    test('HyperCore is unavailable without ever being asked', () {
      expect(ReceiveRouteAvailability.isHyperCoreSource('hypercore'), isTrue);
      expect(ReceiveRouteAvailability.isHyperCoreSource('HyperCore'), isTrue);
      expect(ReceiveRouteAvailability.isHyperCoreSource('hyperevm'), isFalse);
      expect(
          ReceiveRouteAvailability.isUnavailable(
              sourceChain: 'hypercore',
              sourceAsset: 'USDC',
              destinationAsset: 'USDB'),
          isTrue);
      expect(orchestraCanAccumulatePair('hypercore', 'USDC', 'USDB'), isFalse);
      expect(orchestraCanAccumulatePair('hypercore', 'USDC', 'BTC'), isFalse);
      expect(kOrchestraAccumulationSourceChains, isNot(contains('hypercore')));
    });

    test('a marked pair is unavailable for its destination only, and expires',
        () async {
      final marked = DateTime(2026, 10, 12, 12);
      await ReceiveRouteAvailability.markUnavailable(
          sourceChain: 'Tron',
          sourceAsset: 'usdt',
          destinationAsset: 'usdb',
          now: marked);
      bool unavailable(String dest, DateTime now) =>
          ReceiveRouteAvailability.isUnavailable(
              sourceChain: 'tron',
              sourceAsset: 'USDT',
              destinationAsset: dest,
              now: now);
      expect(unavailable('USDB', marked), isTrue);
      expect(unavailable('BTC', marked), isFalse);
      expect(
          unavailable('USDB', marked.add(const Duration(hours: 23))), isTrue);
      expect(unavailable('USDB', marked.add(ReceiveRouteAvailability.ttl)),
          isFalse);
      // A clock that went backwards does not keep a refusal forever.
      expect(unavailable('USDB', marked.subtract(const Duration(days: 2))),
          isFalse);
    });
  });

  group('the picker', () {
    test('a refused pair stops being a reusable row and the lookup drops it',
        () async {
      final catalog = _catalog([_row('tron', 'USDT'), _row('base', 'USDC')]);
      OrchestraReceiveOption tron() => catalog
          .receiveOptions(destinationAsset: 'USDB')
          .singleWhere((o) => o.chain == 'tron');
      expect(tron().reusableAddress, isTrue);
      expect(
          orchestraReceiveChainForDestination('USDT', 'tron',
              destinationAsset: 'USDB'),
          'tron');

      await ReceiveRouteAvailability.markUnavailable(
          sourceChain: 'tron', sourceAsset: 'USDT', destinationAsset: 'USDB');

      // Tron can still take a one-time quoted address, so the row stays
      // as a one-time row rather than a reusable one that would fail.
      expect(tron().reusableAddress, isFalse);
      expect(
          orchestraReceiveChainForDestination('USDT', 'tron',
              destinationAsset: 'USDB'),
          isNull);
      // The bitcoin destination was not refused and keeps its row.
      expect(
          catalog
              .receiveOptions()
              .singleWhere((o) => o.chain == 'tron')
              .reusableAddress,
          isTrue);
      expect(
          orchestraReceiveChainForDestination('USDT', 'tron',
              destinationAsset: 'BTC'),
          'tron');
      // Base is untouched.
      expect(
          catalog
              .receiveOptions(destinationAsset: 'USDB')
              .singleWhere((o) => o.chain == 'base')
              .reusableAddress,
          isTrue);
    });

    test(
        'with every reusable pair refused and one-time off, the coin step '
        'has nothing to offer', () async {
      final catalog = _catalog([_row('tron', 'USDT'), _row('base', 'USDC')]);
      final policy =
          runtimePolicyFixture(blocked: {'orchestra.onetime_addresses'});
      addTearDown(policy.dispose);
      expect(await policy.refresh(), isTrue);
      final l10n = l10nForLanguage('en');
      List<String> coins() => receiveCoinGroups(catalog, l10n,
              standingDestinations: const {'spark:USDB'},
              destinationChain: kOrchestraUsdChain,
              destinationAsset: kOrchestraUsdAssetCode,
              policy: policy)
          .map((g) => g.key)
          .toList();
      expect(coins(), isNotEmpty);
      for (final (chain, asset) in [('tron', 'USDT'), ('base', 'USDC')]) {
        await ReceiveRouteAvailability.markUnavailable(
            sourceChain: chain, sourceAsset: asset, destinationAsset: 'USDB');
      }
      // Empty groups are what the dollars receive renders as
      // `usdReceiveCoinsUnavailable` once the catalogue has loaded.
      expect(coins(), isEmpty);
    });
  });
}
