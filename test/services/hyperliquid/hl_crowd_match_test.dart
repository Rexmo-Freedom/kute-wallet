// Which Polymarket markets the Investing chart reads for an asset, and
// that anything it is unsure about is left out. The fixtures copy the
// shapes Polymarket's recurring price and macro series have.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/services/hyperliquid/insights/hl_crowd_match.dart';

final _now = DateTime.utc(2026, 10, 4, 20);
const _btc = (tag: 'bitcoin', name: 'Bitcoin');

PolymarketEvent _event(
  String title,
  Map<String, double> outcomes, {
  required DateTime end,
  List<String> tags = const ['bitcoin', 'crypto', 'hit-price'],
  bool closed = false,
}) =>
    PolymarketEvent(
      id: title,
      slug: title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-'),
      title: title,
      volume: 0,
      liquidity: 100000,
      category: 'crypto',
      endDate: end,
      closed: closed,
      conditionId: '',
      tags: tags,
      outcomes: [
        for (final e in outcomes.entries)
          PolymarketOutcome(name: e.key, price: e.value),
      ],
    );

final _year = _event(
  'What price will Bitcoin hit in 2026?',
  {
    '↑ 1,000,000': 0.0025,
    '↑ 100,000': 0.355,
    '↑ 95,000': 0.525,
    '↑ 90,000': 0.755,
    '↑ 85,000': 1, // already hit: settled
    '↓ 70,000': 0.275,
    '↓ 60,000': 0.105,
  },
  end: DateTime.utc(2027, 1, 1, 5),
);

final _month = _event(
  'What price will Bitcoin hit in October?',
  {
    '↑ 150,000': 0.0025,
    '↑ 92,500': 0.365,
    '↑ 90,000': 0.555,
    '↑ 87,500': 0.775,
    '↓ 82,500': 0.705,
    '↓ 80,000': 0.485,
    '↓ 77,500': 0.305,
  },
  end: DateTime.utc(2026, 11, 1, 4),
);

final _above = _event(
  'Bitcoin above ___ on October 5?',
  {'82,000': 0.9845, '84,000': 0.885, '86,000': 0.295, '88,000': 0.036},
  end: DateTime.utc(2026, 10, 5, 16),
  tags: const ['bitcoin', 'crypto', 'multi-strikes'],
);

final _fed = _event(
  'Fed Decision in October?',
  {'25 bps decrease': 0.0045, 'No change': 0.825, '25 bps increase': 0.165},
  end: DateTime.utc(2026, 10, 29, 3, 59),
  tags: const ['fed', 'fed-rates', 'economy'],
);

final _fedDec = _event(
  'Fed Decision in December?',
  {'No change': 0.6, '25 bps increase': 0.4},
  end: DateTime.utc(2026, 12, 10, 4, 59),
  tags: const ['fed', 'fed-rates'],
);

final _cpi = _event(
  'September Inflation US - Annual',
  {'3.0%': 0.4, '3.1%': 0.6},
  end: DateTime.utc(2026, 10, 15, 3, 59),
  tags: const ['cpi', 'economy', 'inflation'],
);

HlCrowdView _view({
  List<PolymarketEvent>? asset,
  List<PolymarketEvent>? macro,
  double price = 85450,
  HlCrowdAsset? of = _btc,
}) =>
    hlCrowdView(
      asset: of,
      price: price,
      assetEvents: asset ?? [_month, _above, _year],
      macroEvents: macro ?? [_fed, _fedDec, _cpi],
      now: _now,
    );

HlMarket _market(String coin,
        {String dex = '', bool hip3 = false, String category = 'crypto'}) =>
    HlMarket(
      coin: coin,
      wireCoin: dex.isEmpty ? coin : '$dex:$coin',
      assetId: 0,
      kind: HlMarketKind.perp,
      szDecimals: 2,
      maxLeverage: 10,
      onlyIsolated: false,
      markPx: 1,
      midPx: 1,
      prevDayPx: 1,
      dayNtlVlm: 1,
      dex: dex,
      isHip3: hip3,
      category: category,
    );

void main() {
  test('only the venue\'s own market of a known asset is covered', () {
    expect(hlCrowdAssetFor(_market('BTC'))?.tag, 'bitcoin');
    expect(hlCrowdAssetFor(_market('ETH'))?.name, 'Ethereum');
    // A builder-dex market sharing the ticker, a stock, an unknown coin.
    expect(hlCrowdAssetFor(_market('BTC', dex: 'xyz', hip3: true)), isNull);
    expect(hlCrowdAssetFor(_market('BTC', category: 'stocks')), isNull);
    expect(hlCrowdAssetFor(_market('PEPE')), isNull);
  });

  test('strike labels', () {
    expect(hlCrowdParseStrike('↑ 100,000'), (mark: '↑', strike: 100000.0));
    expect(hlCrowdParseStrike('↓ 0.52'), (mark: '↓', strike: 0.52));
    expect(hlCrowdParseStrike('86,000'), (mark: null, strike: 86000.0));
    expect(hlCrowdParseStrike('74,000-76,000'), isNull);
    expect(hlCrowdParseStrike('<74,000'), isNull);
    expect(hlCrowdParseStrike('No change'), isNull);
  });

  test('chart levels: two strikes each side from the most traded series', () {
    final levels = _view().levels;
    expect(levels.map((l) => l.strike),
        unorderedEquals([87500, 90000, 82500, 80000]));
    expect(levels.every((l) => identical(l.event, _month)), isTrue);
    // Nearest to the price first.
    expect(levels.first.strike, 87500);
  });

  test('macro dates, soonest first', () {
    final dates = _view().dates;
    expect(dates.map((d) => d.kind), [
      HlMacroKind.usInflation,
      HlMacroKind.fedDecision,
      HlMacroKind.fedDecision,
    ]);
    expect(dates.first.day.day, 14);
  });

  test('a strike on the wrong side of the price is not a level', () {
    // At 91,000 the 90,000 and 87,500 "reach" strikes are behind us.
    final levels = _view(price: 91000).levels;
    expect(
        levels.where((l) => l.kind == HlCrowdKind.reach).map((l) => l.strike),
        [92500]);
  });

  test('look-alikes are ignored', () {
    final view = _view(asset: [
      // Another asset's series carrying the bitcoin tag.
      _event('What price will Ethereum hit in 2026?', {'↑ 100,000': 0.5},
          end: DateTime.utc(2027, 1, 1, 5)),
      // The right title without the asset's tag.
      _event('What price will Bitcoin hit in 2026?', {'↑ 100,000': 0.5},
          end: DateTime.utc(2027, 1, 1, 5), tags: const ['crypto']),
      // Bitcoin, but not a price series.
      _event('Will Satoshi move any Bitcoin in 2026?', {'Yes': 0.1, 'No': 0.9},
          end: DateTime.utc(2027, 1, 1, 5)),
      _event('Bitcoin price on October 5?', {'84,000-86,000': 0.585},
          end: DateTime.utc(2026, 10, 5, 16)),
      _event('Bitcoin Up or Down on October 5?', {'Up': 0.5, 'Down': 0.5},
          end: DateTime.utc(2026, 10, 5, 16)),
      // Closed, and already ended.
      _event('What price will Bitcoin hit in September?', {'↑ 100,000': 0.5},
          end: DateTime.utc(2026, 11, 1, 4), closed: true),
      _event('What price will Bitcoin hit October 1?', {'↑ 100,000': 0.5},
          end: DateTime.utc(2026, 10, 2, 4)),
    ], macro: [
      _event('How many Fed rate cuts in 2026?', {'0': 0.6, '1': 0.4},
          end: DateTime.utc(2027, 1, 1, 5), tags: const ['fed', 'fed-rates']),
      _event('September Inflation UK - Annual', {'3.0%': 0.5},
          end: DateTime.utc(2026, 10, 21, 12), tags: const ['cpi', 'uk']),
      // The Fed title without the Fed tag.
      _event('Fed Decision in October?', {'No change': 0.9, 'Cut': 0.1},
          end: DateTime.utc(2026, 10, 29, 4), tags: const ['economy']),
    ]);
    expect(view.levels, isEmpty);
    expect(view.dates, isEmpty);
  });

  test('settled and dead outcomes say nothing', () {
    final view = _view(asset: [
      _event('What price will Bitcoin hit in 2026?',
          {'↑ 90,000': 1, '↑ 500,000': 0.004, '↓ 20,000': 0.0125},
          end: DateTime.utc(2027, 1, 1, 5)),
    ], macro: const []);
    expect(view.levels, isEmpty);
  });

  test('a market the levels do not cover gets the macro dates only', () {
    final view = _view(of: null);
    expect(view.levels, isEmpty);
    expect(view.dates, hasLength(3));
  });
}
