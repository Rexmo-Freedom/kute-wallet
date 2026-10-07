// A game being played is not over for its chart or its Stats, although it
// is past the end date Gamma gives a match (its scheduled start); and the
// chart's probability scale never writes "-0%".

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/screens/polymarket/components/game_header.dart';
import 'package:kute/screens/polymarket/components/market_chart.dart';

final _now = DateTime.utc(2026, 10, 4, 23);

PolymarketEvent _game({
  DateTime? endDate,
  bool closed = false,
  bool active = true,
  bool ended = false,
  String? score = '6-17',
  String? period = 'Q4',
}) =>
    PolymarketEvent(
      id: 'e1',
      slug: 'nfl-den-sf-2026-10-04',
      title: 'Broncos vs. 49ers',
      volume: 1000,
      liquidity: 1000,
      category: 'sports',
      conditionId: 'c1',
      outcomes: const [
        PolymarketOutcome(name: 'Broncos', price: 0.085, tokenId: 'den'),
        PolymarketOutcome(name: '49ers', price: 0.915, tokenId: 'sf'),
      ],
      gameId: 19515,
      endDate: endDate ?? DateTime.utc(2026, 10, 4, 20, 25),
      closed: closed,
      active: active,
      ended: ended,
      score: score,
      period: period,
    );

void main() {
  group('whether an event is over', () {
    test('a game in its fourth quarter, hours past its end date, is not',
        () {
      final event = _game();
      expect(event.endDate!.isBefore(_now), isTrue);
      expect(polyEventIsOver(event, inPlay: true, now: _now), isFalse);
    });

    test('past its end date and not being played, it is', () {
      expect(polyEventIsOver(_game(), inPlay: false, now: _now), isTrue);
    });

    test('closed, switched off or ended, it is, whatever the feed says', () {
      for (final event in [
        _game(closed: true),
        _game(active: false),
        _game(ended: true),
      ]) {
        expect(polyEventIsOver(event, inPlay: true, now: _now), isTrue);
      }
    });

    test('before its end date it is not', () {
      final event = _game(endDate: DateTime.utc(2026, 10, 5));
      expect(polyEventIsOver(event, inPlay: false, now: _now), isFalse);
      expect(polyEventIsOver(event, inPlay: true, now: _now), isFalse);
    });
  });

  group('the labels of the probability scale', () {
    test('zero is "0%", also when the ladder hands back negative zero', () {
      expect(polyScaleLabel(0, 0), '0%');
      expect(polyScaleLabel(-0.0, 0), '0%');
      expect(polyScaleLabel(-0.0, 1), '0.0%');
    });

    test('other levels are written as they are', () {
      expect(polyScaleLabel(20, 0), '20%');
      expect(polyScaleLabel(0.5, 1), '0.5%');
      expect(polyScaleLabel(99.25, 2), '99.25%');
    });
  });
}
