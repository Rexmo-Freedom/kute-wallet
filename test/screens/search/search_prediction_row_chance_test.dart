// A Yes/No market's row shows Yes, even when No leads (founder, 8 November
// 2026: a row read 85% over a market page saying Yes 15.5%); a market of
// named outcomes shows its leader.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/screens/search/components/search_rows.dart';

PolymarketEvent _event(List<PolymarketOutcome> outcomes) => PolymarketEvent(
      id: 'e',
      slug: 'e',
      title: 'e',
      volume: 1200000,
      liquidity: 50000,
      category: 'other',
      tags: const [],
      endDate: DateTime(2027, 2, 7),
      conditionId: 'c',
      outcomes: outcomes,
    );

void main() {
  test('Yes when No leads', () {
    final event = _event([
      PolymarketOutcome(name: 'Yes', price: 0.155),
      PolymarketOutcome(name: 'No', price: 0.845),
    ]);
    expect(SearchPredictionRow.chanceFractionOf(event), 0.155);
    expect(SearchPredictionRow.chanceOf(event), '16%');
  });

  test('Yes when Yes leads, in any order', () {
    final event = _event([
      PolymarketOutcome(name: 'No', price: 0.3),
      PolymarketOutcome(name: 'Yes', price: 0.7),
    ]);
    expect(SearchPredictionRow.chanceFractionOf(event), 0.7);
  });

  test('named outcomes: the leader', () {
    final event = _event([
      PolymarketOutcome(name: 'Putin', price: 0.88),
      PolymarketOutcome(name: 'Lula', price: 0.4),
      PolymarketOutcome(name: 'Xi', price: 0.6),
    ]);
    expect(SearchPredictionRow.chanceFractionOf(event), 0.88);
  });

  test('no prices: no chance', () {
    expect(SearchPredictionRow.chanceFractionOf(_event(const [])), isNull);
  });
}
