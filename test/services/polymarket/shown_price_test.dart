// The chance a Predictions list shows: the midpoint, the last trade when
// the spread is wider than 10¢, and nothing for a wide book that never
// traded.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/services/polymarket/shown_price.dart';

import '../../screens/polymarket/exact_score_fixture.dart';

void main() {
  group('Polymarket\'s rule', () {
    test('a book 10¢ wide or less shows its midpoint', () {
      expect(polySpreadIsWide(0.06, 0.12), isFalse);
      expect(polySpreadIsWide(0.40, 0.50), isFalse);
      expect(polyShownPrice(bid: 0.06, ask: 0.12), closeTo(0.09, 1e-9));
    });

    test('wider shows the last trade, else nothing', () {
      // An ask alone at 74¢ (no bid counts as 0): not a 37% chance.
      expect(polySpreadIsWide(null, 0.74), isTrue);
      expect(polyShownPrice(ask: 0.74), isNull);
      expect(polyShownPrice(ask: 0.75, lastTrade: 0.01), 0.01);
      expect(polyShownPrice(bid: 0.06, ask: 0.78, lastTrade: 0.2), 0.2);
      // An empty book is wide.
      expect(polySpreadIsWide(null, null), isTrue);
    });
  });

  group('a Gamma market', () {
    Map<String, dynamic> m(Map<String, Object> quote) => quote;

    test('without a quote keeps Gamma\'s figure (the Kute feed)', () {
      final r = polyGammaShownPrice(m({}), 0.37);
      expect(r.price, 0.37);
      expect(r.unpriced, isFalse);
    });

    test('tight keeps Gamma\'s midpoint', () {
      final r = polyGammaShownPrice(
          m({'bestBid': 0.06, 'bestAsk': 0.12, 'spread': 0.06}), 0.09);
      expect(r.price, 0.09);
      expect(r.unpriced, isFalse);
    });

    test('wide with a trade shows the trade', () {
      final r = polyGammaShownPrice(
          m({'bestAsk': 0.75, 'spread': 0.75, 'lastTradePrice': 0.01}), 0.375);
      expect(r.price, 0.01);
      expect(r.unpriced, isFalse);
    });

    test('wide and never traded has no chance to show', () {
      final r = polyGammaShownPrice(m({'bestAsk': 0.74, 'spread': 0.74}), 0.37);
      expect(r.unpriced, isTrue);
      // Gamma's figure is kept for the slip's first paint only.
      expect(r.price, 0.37);
    });
  });

  test('the real Exact Score event: only the scores with a book are priced',
      () {
    final event =
        PolymarketModel().parseEventsRaw([exactScoreEventRaw()]).single;
    PolymarketOutcome named(String n) =>
        event.outcomes.firstWhere((o) => o.name == n);
    expect(
        named('Tottenham Hotspur FC 0 - 5 Coventry City FC').unpriced, isTrue);
    expect(named('Tottenham Hotspur FC 2 - 0 Coventry City FC').price, 0.1);
    expect(named('Any Other Score').price, 0.01);
    expect(named('Any Other Score').unpriced, isFalse);
    // Six scores with a two-sided book, three whose lone ask is 10¢ or
    // less (Polymarket's rule counts the missing bid as 0), the catch-all.
    expect(event.outcomes.where((o) => !o.unpriced).length, 10);
  });

  group('a list row\'s chance', () {
    const priced = PolymarketOutcome(name: 'a', price: 0.4, tokenId: 'a');
    const unpriced =
        PolymarketOutcome(name: 'b', price: 0.37, tokenId: 'b', unpriced: true);

    test('the live price wins, the feed\'s "no price" too', () {
      expect(polyShownChanceOf({'a': 0.5}, {}, priced), 0.5);
      expect(polyShownChanceOf({}, {}, priced), 0.4);
      expect(polyShownChanceOf({'a': 0.5}, {'a'}, priced), isNull);
      expect(polyShownChanceOf({}, {}, unpriced), isNull);
      expect(polyShownChanceOf({'b': 0.2}, {}, unpriced), 0.2);
    });

    test('most likely first, none last', () {
      final xs = <double?>[0.1, null, 0.3, null, 0.2]..sort(polyCompareShown);
      expect(xs, [0.3, 0.2, 0.1, null, null]);
    });
  });

  test('the live state: "no price" until a price is written', () {
    const start = LivePriceState(prices: {'a': 0.37});
    final wide = start.copyWithUnpriced({'a', 'b'});
    expect(wide.unpriced, {'a', 'b'});
    expect(identical(wide.copyWithUnpriced({'a'}), wide), isTrue);
    expect(wide.copyWithPrices({'a': 0.01}).unpriced, {'b'});
    expect(wide.copyWithPrice('b', 0.2).unpriced, {'a'});
  });
}
