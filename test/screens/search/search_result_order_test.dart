// The order search results show in: the market the person named first.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/hyperliquid_search_provider.dart';
import 'package:kute/screens/search/search_result_order.dart';

HlMarketSearchResult _hl(String coin, {String? name}) => HlMarketSearchResult(
      coin: coin,
      wireCoin: coin,
      kind: HlMarketKind.perp,
      isStock: false,
      name: name,
      category: 'crypto',
      iconUrl: null,
      markPx: 1,
      dayChangePct: 0,
    );

PolymarketEvent _event(String title, {double volume = 0}) => PolymarketEvent(
      id: title,
      slug: title,
      title: title,
      volume: volume,
      liquidity: 5000,
      category: 'other',
      conditionId: title,
      outcomes: const [
        PolymarketOutcome(name: 'Yes', price: 0.5),
        PolymarketOutcome(name: 'No', price: 0.5),
      ],
    );

void main() {
  test('an exact ticker leads, then prefixes, venue order kept within', () {
    final ranked = rankInvestingResults('btc', [
      _hl('WBTC'),
      _hl('BTCDOM'),
      _hl('UBTC', name: 'Bitcoin'),
      _hl('BTC', name: 'Bitcoin'),
    ]);
    expect([for (final r in ranked) r.coin], ['BTC', 'BTCDOM', 'WBTC', 'UBTC']);
  });

  test('an exact friendly name leads too', () {
    final ranked =
        rankInvestingResults('gold', [_hl('PAXG'), _hl('GLD', name: 'Gold')]);
    expect(ranked.first.coin, 'GLD');
  });

  test('predictions: named title first, then in play, then most traded', () {
    final ranked = rankPredictionResults(
      'brazil',
      [
        _event('Who wins the Copa?', volume: 10),
        _event('Lula flips Bolsonaro for Brazil president?', volume: 900),
        _event('Brazil vs. Argentina', volume: 1),
        _event('Live game', volume: 5),
      ],
      (e) => e,
      isLive: (e) => e.title == 'Live game',
    );
    expect([for (final e in ranked) e.title], [
      'Brazil vs. Argentina',
      'Live game',
      'Lula flips Bolsonaro for Brazil president?',
      'Who wins the Copa?',
    ]);
  });

  test('a query naming a market is known on the device', () {
    expect(hlQueryNamesMarket('btc', const []), isTrue);
    expect(hlQueryNamesMarket('tesla', const []), isTrue);
    expect(hlQueryNamesMarket('bitc', const []), isTrue);
    expect(hlQueryNamesMarket('coffee receipt', const []), isFalse);
  });
}
