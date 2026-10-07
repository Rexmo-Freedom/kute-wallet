// What a Predictions chart shows after a range is picked: a game keeps
// its own window on every range that reaches back past kickoff, the
// probability scale fits the lines on screen (and fits again when the
// range changes), and the tags at the ends of the lines write a chance
// the way the caption does.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/polymarket/components/market_chart.dart';
import 'package:kute/screens/shared/charts/kute_chart_autoscale.dart';

const _min = 60000;
const _hour = 60 * _min;

void main() {
  group('a game\'s window inside a range', () {
    // Kickoff two hours ago.
    const now = 100 * _hour;
    const kickoff = now - 2 * _hour;

    test('6H of a game two hours old is the game, not four flat hours '
        'before it', () {
      final w = polyGameWindow(
          dataStartMs: now - 6 * _hour, dataEndMs: now, gameStartMs: kickoff)!;
      expect(w.end, now);
      // Two hours played and a ten-minute run-up (a twelfth of them).
      expect(w.start, kickoff - 10 * _min);
    });

    test('1D the same: the window does not depend on how far the range '
        'reaches back', () {
      final sixHours = polyGameWindow(
          dataStartMs: now - 6 * _hour, dataEndMs: now, gameStartMs: kickoff);
      final day = polyGameWindow(
          dataStartMs: now - 24 * _hour, dataEndMs: now, gameStartMs: kickoff);
      expect(day, sixHours);
    });

    test('1H of that game is exactly its last hour', () {
      final w = polyGameWindow(
          dataStartMs: now - _hour, dataEndMs: now, gameStartMs: kickoff)!;
      expect(w.start, now - _hour);
      expect(w.end, now);
    });

    test('a short game still gets five minutes of run-up', () {
      final w = polyGameWindow(
          dataStartMs: now - 6 * _hour,
          dataEndMs: now,
          gameStartMs: now - 12 * _min)!;
      expect(w.start, now - 17 * _min);
    });

    test('a finished game ends a little after its last whistle', () {
      // Played from five to two hours ago.
      final w = polyGameWindow(
        dataStartMs: now - 24 * _hour,
        dataEndMs: now,
        gameStartMs: now - 5 * _hour,
        gameEndMs: now - 2 * _hour,
      )!;
      expect(w.start, now - 5 * _hour - 15 * _min);
      expect(w.end, now - 2 * _hour + 15 * _min);
    });

    test('a finished game whose data stops at the whistle keeps its width',
        () {
      final w = polyGameWindow(
        dataStartMs: now - 24 * _hour,
        dataEndMs: now - 2 * _hour,
        gameStartMs: now - 5 * _hour,
        gameEndMs: now - 2 * _hour,
      )!;
      expect(w.end, now - 2 * _hour);
      expect(w.end - w.start, 3 * _hour + 30 * _min);
    });

    test('a game that has not started has no window of its own', () {
      expect(
          polyGameWindow(
              dataStartMs: now - 6 * _hour,
              dataEndMs: now,
              gameStartMs: now + _hour),
          isNull);
    });
  });

  group('the probability scale', () {
    test('fits the lines on screen with a tenth of their span to spare', () {
      final d = polyChartDomain(0.40, 0.60);
      expect(d.minY, closeTo(0.38, 1e-9));
      expect(d.maxY, closeTo(0.62, 1e-9));
    });

    test('a flat line is five points tall, centred, not noise filling the '
        'plot', () {
      final flat = polyChartDomain(0.50, 0.50);
      expect(flat.maxY - flat.minY, closeTo(kPolyChartMinSpan, 1e-9));
      expect((flat.minY + flat.maxY) / 2, closeTo(0.50, 1e-9));
      // Half a point of wobble is still drawn as half a point.
      final wobble = polyChartDomain(0.500, 0.505);
      expect(wobble.maxY - wobble.minY, closeTo(kPolyChartMinSpan, 1e-9));
    });

    test('stays inside 0% to 100% but for the sliver that keeps a line off '
        'the edge', () {
      final all = polyChartDomain(0.0, 1.0);
      expect(all.minY, greaterThanOrEqualTo(-0.04));
      expect(all.minY, lessThanOrEqualTo(0));
      expect(all.maxY, lessThanOrEqualTo(1.04));
      expect(all.maxY, greaterThanOrEqualTo(1));
      // A long shot at 0.4%: the scale does not dip to -2%.
      final low = polyChartDomain(0.004, 0.004);
      expect(low.minY, greaterThan(-0.005));
      expect(low.maxY - low.minY, closeTo(kPolyChartMinSpan, 1e-9));
      // A near certainty: not up to 102%.
      final high = polyChartDomain(0.997, 0.999);
      expect(high.maxY, lessThan(1.005));
      expect(high.maxY - high.minY, closeTo(kPolyChartMinSpan, 1e-9));
    });

    test('values out of range or the wrong way round are still a scale', () {
      final d = polyChartDomain(1.2, -0.3);
      expect(d.minY, lessThanOrEqualTo(0));
      expect(d.maxY, greaterThanOrEqualTo(1));
      expect(polyChartDomain(double.nan, 0.5), (minY: 0.0, maxY: 1.0));
    });
  });

  group('the lane a game\'s markers are drawn in', () {
    test('a line near 100% ends under it', () {
      // 380 pt of plot, 30 of them the markers'.
      const lane = 30 / 374;
      final d =
          polyChartHeadroom(polyChartDomain(0.30, 0.9875), 0.9875, lane);
      final fromTop = (d.maxY - 0.9875) / (d.maxY - d.minY);
      expect(fromTop, closeTo(lane, 1e-9));
    });

    test('a scale that already leaves the room is left alone', () {
      final d = polyChartDomain(0.30, 0.60);
      expect(polyChartHeadroom(d, 0.60, 0.05), d);
      expect(polyChartHeadroom(d, 0.60, 0), d);
    });
  });

  group('the scale after a change', () {
    test('another range fits afresh, tighter or wider', () {
      final tracker = KuteAutoScaleTracker();
      // ALL: the market's life ran from 5% to 95%.
      final all = tracker.fit(('max',), 0.05, 0.95, domain: polyChartDomain);
      expect(all.maxY - all.minY, greaterThan(0.9));
      // 1H: the last hour moved between 60% and 66%.
      final hour = tracker.fit(('1h',), 0.60, 0.66, domain: polyChartDomain);
      expect(hour.minY, closeTo(0.594, 1e-9));
      expect(hour.maxY, closeTo(0.666, 1e-9));
      // And back.
      expect(tracker.fit(('max',), 0.05, 0.95, domain: polyChartDomain), all);
    });

    test('live ticks inside the scale leave it still', () {
      final tracker = KuteAutoScaleTracker();
      final first = tracker.fit(('1h',), 0.40, 0.60, domain: polyChartDomain);
      expect(
          identical(
              tracker.fit(('1h',), 0.41, 0.60, domain: polyChartDomain),
              first),
          isTrue);
    });

    test('a line walking out of the scale moves it', () {
      final tracker = KuteAutoScaleTracker();
      tracker.fit(('1h',), 0.40, 0.60, domain: polyChartDomain);
      final next = tracker.fit(('1h',), 0.40, 0.70, domain: polyChartDomain);
      expect(next.maxY, closeTo(0.73, 1e-9));
    });

    test('a scale left loose around what is now on screen tightens (a '
        'line removed, a spike panned away)', () {
      final tracker = KuteAutoScaleTracker();
      final wide = tracker.fit(('1h',), 0.10, 0.90, domain: polyChartDomain);
      final tight = tracker.fit(('1h',), 0.48, 0.52, domain: polyChartDomain);
      expect(tight.maxY - tight.minY, lessThan((wide.maxY - wide.minY) / 4));
    });
  });

  group('a chance on a chart tag', () {
    test('one decimal at most, as the caption rounds it', () {
      expect(polyChartTagPct(0.9345), '93.5%');
      expect(polyChartTagPct(0.0655), '6.6%');
      expect(polyChartTagPct(0.62), '62%');
      expect(polyChartTagPct(0.215), '21.5%');
      expect(polyChartTagPct(0.5), '50%');
    });

    test('a long shot and a near certainty keep a second decimal', () {
      expect(polyChartTagPct(0.0045), '0.45%');
      expect(polyChartTagPct(0.9955), '99.55%');
      expect(polyChartTagPct(0.9975), '99.75%');
      expect(polyChartTagPct(0.005), '0.5%');
    });

    test('never 0% or 100% short of the real thing', () {
      expect(polyChartTagPct(0.99999), '99.99%');
      expect(polyChartTagPct(0.00001), '0.01%');
      expect(polyChartTagPct(1), '100%');
      expect(polyChartTagPct(0), '0%');
    });
  });
}
