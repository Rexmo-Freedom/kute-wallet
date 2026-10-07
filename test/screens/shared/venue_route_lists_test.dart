import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/screens/pay/components/confirm_send.dart'
    show debugSendDestinationIds;
import 'package:kute/screens/shared/coin_asset_grid.dart';
import 'package:kute/services/orchestra_routes.dart';
import 'package:kute/services/orchestra_usd_send_routes.dart';

Map<String, dynamic> _row(String chain, String asset, {int decimals = 6}) => {
      'id': '$chain:$asset',
      'chain': chain,
      'asset': asset,
      'decimals': decimals,
      'route': {'to': 'all', 'fixedTo': [], 'exactOutTo': []},
    };

OrchestraRoutesCatalog _catalog() => OrchestraRoutesCatalog.fromJson(
      {
        'assets': [
          _row('spark', 'BTC', decimals: 8),
          _row('spark', 'USDB'),
          _row('hypercore', 'USDC', decimals: 8),
          _row('polygon', 'USDC.e'),
          _row('polygon', 'pUSD'),
          _row('polygon', 'USDC'),
          _row('base', 'USDC'),
          _row('arbitrum', 'USDT'),
        ],
      },
      source: OrchestraCatalogSource.live,
      fetchedAt: DateTime(2026, 9, 30),
    );

bool _venue(String id) {
  final [chain, asset] = id.split(':');
  return isVenueInternalRoute(chain, asset);
}

void main() {
  final l10n = l10nForLanguage('en');

  test('venue rails are HyperCore and Polygon USDC.e / pUSD only', () {
    expect(isVenueInternalRoute('hypercore', 'USDC'), isTrue);
    expect(isVenueInternalRoute('HyperCore', 'anything'), isTrue);
    expect(isVenueInternalRoute('polygon', 'USDC.e'), isTrue);
    expect(isVenueInternalRoute('polygon', 'pUSD'), isTrue);
    expect(isVenueInternalRoute('polygon', 'USDC'), isFalse);
    expect(isVenueInternalRoute('hyperevm', 'USDC'), isFalse);
    expect(isVenueInternalRoute('base', 'USDC'), isFalse);
  });

  for (final destination in ['BTC', 'USDB']) {
    test('receive "also accepts" into $destination hides venue rails', () {
      final groups = receiveCoinGroups(_catalog(), l10n,
          destinationChain: 'spark', destinationAsset: destination);
      final ids = [
        for (final g in groups)
          for (final o in g.options) '${o.chain}:${o.assetCode}',
      ];
      expect(ids, isNotEmpty);
      expect(ids.where(_venue), isEmpty);
      expect(ids, contains('polygon:USDC'));
      expect(ids, contains('base:USDC'));
    });
  }

  test('send picker hides venue rails and never offers bridged USDC.e', () {
    final ids = debugSendDestinationIds(_catalog(), l10n);
    expect(ids.where(_venue), isEmpty);
    expect(ids, contains('polygon:USDC'));
    expect(ids, isNot(contains('polygon:USDC.e')));
  });

  test('dollar send destinations hide venue rails', () {
    final ids = usdSendDestinations(_catalog()).map((d) => d.id).toList();
    expect(ids.where(_venue), isEmpty);
    expect(ids, contains('polygon:USDC'));
  });

  test('venue flows still find their routes internally', () {
    final catalog = _catalog();
    for (final key in [
      RouteKey(
          fromChain: 'spark',
          fromAsset: 'BTC',
          toChain: 'hypercore',
          toAsset: 'USDC'),
      RouteKey(
          fromChain: 'hypercore',
          fromAsset: 'USDC',
          toChain: 'spark',
          toAsset: 'BTC'),
      RouteKey(
          fromChain: 'spark',
          fromAsset: 'BTC',
          toChain: 'polygon',
          toAsset: 'USDC.e'),
      RouteKey(
          fromChain: 'polygon',
          fromAsset: 'USDC.e',
          toChain: 'spark',
          toAsset: 'BTC'),
    ]) {
      expect(catalog.supports(key), isTrue, reason: key.label);
    }
    expect(
        catalog
            .receiveOptions()
            .any((o) => o.chain == 'hypercore' && o.assetCode == 'USDC'),
        isTrue);
  });
}
