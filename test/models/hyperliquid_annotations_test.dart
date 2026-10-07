// perpConciseAnnotations names builder-dex coins dex-qualified (live:
// para:STX "stocks", flx:GAS "commodities", km:EUR "FX", para:AAOI
// "stock", para:10Y "rates"). Annotations are keyed by dex:symbol so they
// never reach the default dex's crypto perps of the same ticker, and the
// categories are normalised so every market lands on a pill.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';

const _annotations = [
  ['para:STX', {'category': 'stocks', 'keywords': ['seagate', 'storage']}],
  ['flx:GAS', {'category': 'commodities'}],
  ['km:EUR', {'category': 'FX'}],
  ['para:AAOI', {'category': 'stock'}],
  ['para:10Y', {'category': 'rates', 'keywords': ['treasury', 'yields']}],
  [
    'xyz:CL',
    {'category': 'commodities', 'displayName': 'WTIOIL', 'keywords': ['crude', 'cl']}
  ],
  [
    'xyz:XYZ100',
    {'category': 'indices', 'displayName': 'XYZ100', 'keywords': ['nasdaq', 'qqq']}
  ],
  [
    'io:OAI',
    {'category': 'preipo', 'displayName': 'OPENAI', 'keywords': ['openai', 'oai']}
  ],
  ['xyz:SPCX', {'category': 'stocks', 'keywords': ['spacex']}],
];

List<dynamic> _meta(List<String> names) => [
      {
        'universe': [
          for (final n in names) {'name': n, 'szDecimals': 2, 'maxLeverage': 10},
        ],
      },
      [
        for (final _ in names)
          {'markPx': '1.0', 'prevDayPx': '1.0', 'dayNtlVlm': '20000'},
      ],
    ];

void main() {
  final ann = HlPerpAnnotation.parseList(_annotations);

  test('keys by dex and symbol, normalises the category', () {
    expect(ann.keys, contains('para:STX'));
    expect(ann['km:EUR']!.category, 'fx');
    expect(ann['para:AAOI']!.category, 'stocks');
    expect(ann['para:10Y']!.category, 'rates');
    expect(ann['io:OAI']!.displayName, 'OPENAI');
  });

  test('a builder-dex annotation never reaches the default dex', () {
    final main = HlMarket.parsePerpList(_meta(['BTC', 'STX', 'GAS']),
        annotations: ann);
    expect({for (final m in main) m.coin: m.category},
        {'BTC': 'crypto', 'STX': 'crypto', 'GAS': 'crypto'});
    expect(main.every((m) => m.keywords.isEmpty), isTrue);

    final para = HlMarket.parsePerpList(_meta(['para:STX', 'para:10Y']),
        dex: 'para', dexIndex: 8, annotations: ann);
    expect({for (final m in para) m.coin: m.category},
        {'STX': 'stocks', '10Y': 'rates'});
    final flx = HlMarket.parsePerpList(_meta(['flx:GAS']),
        dex: 'flx', dexIndex: 2, annotations: ann);
    expect(flx.single.category, 'commodities');
  });

  test('stock and FX reach Tradfi and its sub-pills; rates stay in Perps',
      () {
    final km = HlMarket.parsePerpList(_meta(['km:EUR']),
        dex: 'km', dexIndex: 5, annotations: ann);
    final para = HlMarket.parsePerpList(_meta(['para:AAOI', 'para:10Y']),
        dex: 'para', dexIndex: 8, annotations: ann);
    final all = [...km, ...para];
    final tradfi = hlBrowseListForTab(HlBrowseTab.tradfi, all);
    expect(tradfi.map((m) => m.coin).toSet(), {'EUR', 'AAOI'});
    final fx =
        hlBrowseListForTab(HlBrowseTab.tradfi, all, sub: HlBrowseSub.fx);
    expect(fx.map((m) => m.coin).toSet(), {'EUR'});
    final stocks =
        hlBrowseListForTab(HlBrowseTab.tradfi, all, sub: HlBrowseSub.stocks);
    expect(stocks.map((m) => m.coin).toList(), ['AAOI']);
    // The site's Tradfi has no rates: they list under Perps and All.
    final perps = hlBrowseListForTab(HlBrowseTab.perps, all);
    expect(perps.map((m) => m.coin).toSet(), {'EUR', 'AAOI', '10Y'});
  });

  test('search uses the venue names and keywords', () {
    final xyz = HlMarket.parsePerpList(_meta(['xyz:CL', 'xyz:XYZ100']),
        dex: 'xyz', dexIndex: 1, annotations: ann);
    final io = HlMarket.parsePerpList(_meta(['io:OAI']),
        dex: 'io', dexIndex: 10, annotations: ann);
    final cl = xyz.firstWhere((m) => m.coin == 'CL');
    final nasdaq = xyz.firstWhere((m) => m.coin == 'XYZ100');
    expect(hlMarketMatchesQuery(cl, 'crude'), isTrue);
    expect(hlMarketMatchesQuery(cl, 'WTI oil'), isTrue);
    expect(hlMarketMatchesQuery(nasdaq, 'nasdaq'), isTrue);
    expect(hlMarketMatchesQuery(nasdaq, 'QQQ'), isTrue);
    expect(hlMarketMatchesQuery(io.single, 'openai'), isTrue);
    expect(hlMarketMatchesQuery(cl, 'nasdaq'), isFalse);
  });

  test('a spot token borrows what its builder-dex perps agree on', () {
    final perps = HlMarket.parsePerpList(_meta(['xyz:SPCX']),
        dex: 'xyz', dexIndex: 1, annotations: ann);
    const spot = HlMarket(
      coin: 'SPCX',
      wireCoin: '@590',
      assetId: 10590,
      kind: HlMarketKind.spot,
      szDecimals: 2,
      maxLeverage: 1,
      onlyIsolated: false,
      markPx: 1,
      midPx: 1,
      prevDayPx: 1,
      dayNtlVlm: 1,
    );
    final resolved = resolveHlBrowseUniverse(perps, [spot]);
    final s = resolved.firstWhere((m) => m.isSpot);
    expect(s.category, 'stocks');
    expect(s.keywords, ['spacex']);
  });

  test('the disk cache keeps names and keywords', () {
    final cl = HlMarket.parsePerpList(_meta(['xyz:CL']),
            dex: 'xyz', dexIndex: 1, annotations: ann)
        .single;
    final back = HlMarket.fromCacheJson(cl.toCacheJson())!;
    expect(back.annotatedName, 'WTIOIL');
    expect(back.keywords, ['crude', 'cl']);
    expect(back.category, 'commodities');
  });
}
