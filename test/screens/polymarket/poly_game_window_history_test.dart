// A finished game's chart: its own window is drawn from one-minute points
// whatever range is on screen.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/screens/polymarket/components/poly_chart_history.dart';

const _min = 60000;
const _hour = 60 * _min;

PolymarketPricePoint _p(int ms, double price) => PolymarketPricePoint(
    timestamp: DateTime.fromMillisecondsSinceEpoch(ms), price: price);

void main() {
  group('the game minute by minute inside a coarser range', () {
    test('the range\'s points before and after, the minutes between', () {
      // 1D: a point every ten minutes for three hours.
      final coarse = [for (var i = 0; i <= 18; i++) _p(i * 10 * _min, 0.5)];
      // The game: minutes 60 to 120.
      final fine = [for (var m = 60; m <= 120; m++) _p(m * _min, 0.6)];
      final merged = mergeFineWindow(coarse, fine);
      // Six ten-minute points before, sixty-one minutes, six after.
      expect(merged.length, 6 + 61 + 6);
      expect(merged.take(6).every((p) => p.price == 0.5), isTrue);
      expect(merged.skip(6).take(61).every((p) => p.price == 0.6), isTrue);
      for (var i = 1; i < merged.length; i++) {
        expect(merged[i].timestamp.isAfter(merged[i - 1].timestamp), isTrue);
      }
    });

    test('with no minutes read the range is drawn as it is, and the other '
        'way round', () {
      final coarse = [_p(0, 0.5), _p(10 * _min, 0.6)];
      expect(mergeFineWindow(coarse, const []), same(coarse));
      expect(mergeFineWindow(const [], coarse), same(coarse));
    });
  });

  group('what can be read at one-minute grain', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1000 * 24 * _hour);
    final nowMs = now.millisecondsSinceEpoch;

    test('a three-hour game today, finished or in play', () {
      expect(
          PolyGameWindowHistory.canRead(nowMs - 6 * _hour, nowMs - 3 * _hour,
              now: now),
          isTrue);
      expect(PolyGameWindowHistory.canRead(nowMs - 2 * _hour, null, now: now),
          isTrue);
    });

    test('not a five-day cricket test, nor a game from three weeks ago', () {
      expect(
          PolyGameWindowHistory.canRead(nowMs - 30 * _hour, null, now: now),
          isFalse);
      expect(
          PolyGameWindowHistory.canRead(
              nowMs - 21 * 24 * _hour, nowMs - 21 * 24 * _hour + 3 * _hour,
              now: now),
          isFalse);
    });
  });
}
