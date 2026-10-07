import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/services/orchestra_routes.dart';
import 'package:kute/services/security/address_guard.dart';

Map<String, dynamic> _row(String chain, String asset,
        {Object? decimals = 6, Object to = 'all'}) =>
    {
      'id': '$chain:$asset',
      'chain': chain,
      'asset': asset,
      if (decimals != null) 'decimals': decimals,
      'route': {'to': to, 'fixedTo': [], 'exactOutTo': []},
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
      fetchedAt: DateTime(2026, 9, 27),
    );

void main() {
  test('known legacy rejections become quotes, never reusable candidates', () {
    final options = _catalog([
      _row('tron', 'TRX'),
      _row('ethereum', 'WBTC', decimals: 8),
      _row('base', 'cbBTC', decimals: 8),
    ]).receiveOptions(destinationAsset: 'USDB');
    expect(options.map((o) => '${o.chain}:${o.assetCode}'),
        unorderedEquals(['tron:TRX', 'ethereum:WBTC', 'base:cbBTC']));
    expect(options.every((o) => !o.reusableAddress), isTrue);
  });

  test('new EVM one-time sources retain exact source units and spelling', () {
    final options = _catalog([
      _row('arc', 'USDC'),
      _row('sei', 'USDC'),
      _row('sei', 'TokenCase', decimals: 18),
    ]).receiveOptions(destinationAsset: 'USDB');
    expect(options, hasLength(3));
    expect(options.every((o) => !o.reusableAddress), isTrue);
    final token = options.firstWhere((o) => o.assetCode == 'TokenCase');
    expect(token.assetCode, 'TokenCase');
    expect(token.decimals, 18);
  });

  test('quote eligibility never substitutes fixedTo for directed route.to', () {
    final row = _row('sei', 'TOKEN', decimals: 18, to: ['spark:USDB']);
    row['route'] = {
      'to': ['spark:USDB'],
      'fixedTo': ['spark:BTC'],
      'exactOutTo': ['spark:BTC'],
    };
    final catalog = _catalog([row]);
    expect(catalog.receiveOptions(), isEmpty);
    expect(catalog.receiveOptions(destinationAsset: 'USDB'), hasLength(1));
  });

  test('native BTC sources, sender-submitted Spark and unknown rails stay out',
      () {
    final catalog = _catalog([
      _row('bitcoin', 'BTC', decimals: 8),
      _row('lightning', 'BTC', decimals: 8),
      _row('newchain', 'USDC'),
    ]);
    expect(catalog.receiveOptions(), isEmpty);
    final dollars = catalog.receiveOptions(destinationAsset: 'USDB');
    expect(dollars, hasLength(1));
    expect(dollars.single.chain, 'bitcoin');
    expect(dollars.single.reusableAddress, isFalse);
  });

  test('validated TON, XRP, Litecoin and Zcash rails are one-time quotes only',
      () {
    // These rails have local checksum rules (address_guard.dart) and the
    // quote guard admits their deposit memo only on the receive surface
    // that displays it; none of them has a reusable deposit address.
    final catalog = _catalog([
      _row('ton', 'USDT'),
      _row('xrp', 'XRP'),
      _row('litecoin', 'LTC', decimals: 8),
      _row('zcash', 'ZEC', decimals: 8),
    ]);
    for (final options in [
      catalog.receiveOptions(),
      catalog.receiveOptions(destinationAsset: 'USDB'),
    ]) {
      expect(options.map((o) => '${o.chain}:${o.assetCode}'),
          unorderedEquals(['ton:USDT', 'xrp:XRP', 'litecoin:LTC', 'zcash:ZEC']));
      expect(options.every((o) => !o.reusableAddress), isTrue);
    }
  });

  test('every enabled quote chain has a deposit and refund format validator',
      () {
    for (final chain in kOrchestraQuoteReceiveChains) {
      expect(formatMatchesChain(chain, '', mainnet: true),
          AddressFormatMatch.mismatch,
          reason: chain);
    }
    for (final chain in ['spark', 'lightning', 'unknown']) {
      expect(orchestraCanQuoteReceiveOn(chain), isFalse, reason: chain);
    }
  });

  for (final decimals in <Object?>[null, -1, 19, 6.5, '6', double.infinity]) {
    test('unusable source decimals $decimals cannot authorize a receive', () {
      final catalog = _catalog([
        _row('sei', 'TOKEN', decimals: decimals),
      ]);
      expect(catalog.receiveOptions(destinationAsset: 'USDB'), isEmpty);
      expect(
        catalog
            .availability(
              RouteKey(
                fromChain: 'sei',
                fromAsset: 'TOKEN',
                toChain: 'spark',
                toAsset: 'USDB',
              ),
              req: RouteRequirement.live,
              now: DateTime(2026, 9, 27),
            )
            .reason,
        RouteUnavailableReason.decimalsMismatch,
      );
    });
  }

  test('pinned source decimals cannot be rescaled by the catalog', () {
    final catalog = _catalog([_row('bsc', 'USDC', decimals: 6)]);
    expect(catalog.receiveOptions(destinationAsset: 'USDB'), isEmpty);
  });

  test('static fallback cannot infer units for a one-time quote', () {
    final options = OrchestraRoutesCatalog.fromStatic()
        .receiveOptions(destinationAsset: 'USDB');
    expect(options.every((o) => o.reusableAddress), isTrue);
    expect(options.any((o) => o.chain == 'bitcoin'), isFalse);
  });
}
