// Momentum bucketing, the totals picker and an esports series map by map.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/providers/polymarket_game_momentum_provider.dart';
import 'package:kute/services/polymarket/live_game/game_esports.dart';
import 'package:kute/services/polymarket/live_game/game_momentum.dart';
import 'package:kute/services/polymarket/live_game/game_score.dart';
import 'package:kute/services/polymarket/live_game/game_timeline.dart';

const min = 60000;

List<OddsPoint> pts(Map<int, double> byMinute) => [
      for (final e in byMinute.entries) (tMs: e.key * min, p: e.value),
    ];

GameEvent ev(int t, String before, String after,
        {String pb = '1/3', String p = '1/3', bool ended = false}) =>
    GameEvent(
        tMs: t,
        scoreBefore: before,
        score: after,
        periodBefore: pb,
        period: p,
        ended: ended);

void main() {
  group('momentumBucketMs', () {
    test('adapts to the length of the game', () {
      expect(momentumBucketMs(45 * min), 1 * min);
      expect(momentumBucketMs(115 * min), 1 * min); // a soccer match
      expect(momentumBucketMs(195 * min), 2 * min); // an NFL game
      expect(momentumBucketMs(5 * 60 * min), 3 * min);
      // Never coarser than five minutes, however long the game.
      expect(momentumBucketMs(8 * 60 * min), 4 * min);
      expect(momentumBucketMs(24 * 60 * min), 5 * min);
    });
  });

  test('resampleOdds carries the last price forward', () {
    final s = resampleOdds(pts({1: 0.4, 3: 0.5}), 0, min, 4);
    expect(s, [null, 0.4, 0.4, 0.5, 0.5]);
  });

  group('buildMomentum', () {
    test('two-way market: the bar is side A\'s own change', () {
      final strip = buildMomentum(
        a: pts({0: 0.50, 1: 0.53, 2: 0.53, 3: 0.49}),
        startMs: 0,
        endMs: 3 * min,
      );
      expect(strip.bucketMs, min);
      expect(strip.bars.length, 3);
      expect(strip.bars[0].swing, closeTo(0.03, 1e-9));
      expect(strip.bars[1].flat, isTrue);
      expect(strip.bars[2].swing, closeTo(-0.04, 1e-9));
      // Full height is the game's own biggest swing.
      expect(strip.scale, closeTo(0.04, 1e-9));
    });

    test('three-way market: half of A minus B, a draw move alone is flat',
        () {
      final strip = buildMomentum(
        a: pts({0: 0.40, 1: 0.46, 2: 0.44}),
        b: pts({0: 0.30, 1: 0.26, 2: 0.24}),
        startMs: 0,
        endMs: 2 * min,
      );
      // A +6, B -4 -> A gained 5 points of edge.
      expect(strip.bars[0].swing, closeTo(0.05, 1e-9));
      // Both fell 2 points (the draw rose): nobody gained on the other.
      expect(strip.bars[1].swing, closeTo(0, 1e-9));
      expect(strip.bars[1].flat, isTrue);
    });

    test('a big move sets the scale; the last bucket may be partial', () {
      final strip = buildMomentum(
        a: pts({0: 0.50, 1: 0.80}),
        startMs: 0,
        endMs: 90000,
      );
      expect(strip.bars.length, 2);
      expect(strip.bars.last.endMs, 90000);
      expect(strip.scale, closeTo(0.30, 1e-9));
    });

    test('buckets before the first price are empty, never invented', () {
      final strip = buildMomentum(
        a: pts({3: 0.50, 4: 0.52}),
        startMs: 0,
        endMs: 5 * min,
      );
      expect(strip.bars.take(2).every((b) => b.empty), isTrue);
      expect(strip.bars[3].swing, closeTo(0.02, 1e-9));
      expect(strip.isEmpty, isFalse);
      expect(
          buildMomentum(a: const [], startMs: 0, endMs: min).isEmpty, isTrue);
      expect(buildMomentum(a: pts({0: 0.5}), startMs: 5, endMs: 5).isEmpty,
          isTrue);
    });

    test('never more bars than the cap', () {
      final strip = buildMomentum(
        a: pts({for (var i = 0; i <= 400; i++) i: 0.5 + (i % 7) / 100}),
        startMs: 0,
        endMs: 400 * min,
      );
      expect(strip.bars.length, lessThanOrEqualTo(kMomentumMaxBars));
    });
  });

  group('scaling', () {
    test('a quiet game keeps the 1.5-point floor as full height', () {
      final strip = buildMomentum(
        a: pts({0: 0.500, 1: 0.508, 2: 0.508}),
        startMs: 0,
        endMs: 2 * min,
      );
      expect(strip.scale, kMomentumScaleFloor);
      // 0.8 of a point against the 1.5-point floor, on the square root.
      expect(momentumBarHeight(strip.bars[0].swing, strip.scale),
          closeTo(0.7303, 1e-3));
    });

    test('square-root easing: the biggest swing is full height, a quarter '
        'of it is half', () {
      expect(momentumBarHeight(0.20, 0.20), 1);
      expect(momentumBarHeight(-0.05, 0.20), closeTo(0.5, 1e-9));
      expect(momentumBarHeight(0.50, 0.20), 1); // capped
      expect(momentumBarHeight(0, 0.20), 0);
    });

    test('the wave is smoothed, signed and stretched to full height', () {
      final strip = buildMomentum(
        a: pts({0: 0.50, 1: 0.50, 2: 0.70, 3: 0.70, 4: 0.65, 5: 0.65}),
        startMs: 0,
        endMs: 5 * min,
      );
      final wave = momentumWave(strip);
      expect(wave.length, 5);
      // The jump (bucket 1) is the peak, at full height, and spills into
      // its neighbours; the later drop pulls the wave below the line.
      expect(wave[1], closeTo(1, 1e-9));
      expect(wave[0], greaterThan(0));
      expect(wave[3], lessThan(0));
      expect(wave.every((v) => v >= -1 && v <= 1), isTrue);
      // Nothing moved: nothing to draw.
      final still = buildMomentum(
          a: pts({0: 0.5, 9: 0.5}), startMs: 0, endMs: 9 * min);
      expect(momentumWave(still).every((v) => v == 0), isTrue);
      expect(still.readable, isFalse);
    });

    test('shown only once eight buckets of the game have a price', () {
      MomentumStrip played(int minutes) => buildMomentum(
            a: pts({for (var i = 0; i <= minutes; i++) i: 0.5 + (i % 3) / 50}),
            startMs: 0,
            endMs: minutes * min,
          );
      expect(played(5).readable, isFalse);
      expect(played(8).readable, isTrue);
    });
  });

  group('the game window', () {
    test('kickoff is the feed\'s, then Gamma\'s, then the first sighting',
        () {
      expect(
          gameKickoffMs(
              feedStartMs: 100,
              gammaStartMs: 90,
              firstSeenMs: 120,
              untilMs: 1000),
          100);
      expect(
          gameKickoffMs(gammaStartMs: 90, firstSeenMs: 120, untilMs: 1000),
          90);
      expect(gameKickoffMs(firstSeenMs: 120, untilMs: 1000), 120);
      // A start that is still ahead is not a kickoff.
      expect(gameKickoffMs(gammaStartMs: 2000, untilMs: 1000), isNull);
    });

    test('the market\'s opening date is not the kickoff', () {
      const hour = 3600000;
      // Gamma's event start date: the market opened six weeks ago.
      expect(
          gameKickoffMs(
              marketStartMs: 0, untilMs: 6 * 7 * 24 * hour),
          isNull);
      // Only when it is within a game's length of now.
      expect(gameKickoffMs(marketStartMs: hour, untilMs: 3 * hour), hour);
    });

    test('in play, a sport with a clock gets its usual length as the axis',
        () {
      final axis = momentumAxisMs(GameSport.soccer)!;
      final strip = buildMomentum(
        a: pts({for (var i = 0; i <= 20; i++) i: 0.5 + (i % 4) / 100}),
        startMs: 0,
        endMs: 20 * min,
        axisMs: axis,
      );
      // 20 minutes played, drawn on the whole game: the rest stays empty.
      expect(strip.endMs, 20 * min);
      expect(strip.axisEndMs, axis);
      expect(strip.bucketMs, min);
      expect(strip.bars.length, 20);
      // A finished game, and a sport with no clock, end where they end.
      expect(momentumAxisMs(GameSport.tennis), isNull);
      // Baseball has no clock: its graph fills the width as it is played.
      expect(momentumAxisMs(GameSport.baseball), isNull);
      final done = buildMomentum(
          a: pts({0: 0.5, 30: 0.6}), startMs: 0, endMs: 30 * min);
      expect(done.axisEndMs, 30 * min);
    });
  });

  group('pickOverToken', () {
    Map<String, dynamic> total(double line, double over, double spread,
            {bool closed = false}) =>
        {
          'sportsMarketType': 'totals',
          'line': line,
          'outcomes': '["Over", "Under"]',
          'outcomePrices': '["$over", "${1 - over}"]',
          'clobTokenIds': '["over$line", "under$line"]',
          'spread': spread,
          'closed': closed,
        };

    test('the most even line that is actually traded', () {
      // As sampled: dead lines sit at 0.495 with a 0.99 spread.
      expect(
          pickOverToken({
            'markets': [
              total(1.5, 0.10, 0.02),
              total(2.5, 0.42, 0.03),
              total(6.5, 0.495, 0.99),
              total(7.5, 0.495, 0.99),
              {'sportsMarketType': 'moneyline', 'spread': 0.01},
            ]
          }),
          'over2.5');
    });

    test('none when every line is dead, closed or decided', () {
      expect(
          pickOverToken({
            'markets': [
              total(6.5, 0.495, 0.99),
              total(2.5, 0.5, 0.02, closed: true),
              total(0.5, 0.9995, 0.001),
            ]
          }),
          isNull);
      expect(pickOverToken({}), isNull);
    });
  });

  group('esportsSeriesFrom', () {
    test('maps won, in order, and the map in play', () {
      final series = esportsSeriesFrom([
        ev(100, '13-9|0-0|Bo3', '000-000|1-0|Bo3'),
        ev(200, '5-13|1-0|Bo3', '000-000|1-1|Bo3', pb: '2/3', p: '3/3'),
      ], score: '4-2|1-1|Bo3', period: '3/3');
      expect((series.earlierHome, series.earlierAway), (0, 0));
      expect(series.bestOf, 3);
      expect(series.maps.map((m) => (m.number, m.winner, m.live)), [
        (1, 1, false),
        (2, -1, false),
        (3, null, true),
      ]);
      expect((series.maps.last.mapHome, series.maps.last.mapAway), (4, 2));
    });

    test('maps finished before anyone watched are only a count', () {
      // Opened at 1-2 in a best of five, as sampled live (CS2).
      final series = esportsSeriesFrom(const [],
          score: '000-000|1-2|Bo5', period: '4/5');
      expect((series.earlierHome, series.earlierAway), (1, 2));
      expect(series.maps.single.number, 4);
      expect(series.maps.single.live, isTrue);
    });

    test('a finished series has no map in play', () {
      final series = esportsSeriesFrom([
        ev(100, '14-10|2-2|Bo5', '000-000|3-2|Bo5',
            pb: '5/5', p: '5/5', ended: true),
      ], score: '000-000|3-2|Bo5', period: '5/5', ended: true);
      expect((series.earlierHome, series.earlierAway), (2, 2));
      // The message that ends the game is the final marker, not a map.
      expect(series.maps.where((m) => m.live), isEmpty);
    });
  });

  group('the names under the axis', () {
    ({double left, double right}) at(double left, double width) =>
        (left: left, right: left + width);

    test('names with room are all kept', () {
      final spans = [at(0, 14), at(120, 20), at(200, 20), at(330, 22)];
      expect(momentumAxisLabelsKept(spans, latest: 2), [0, 1, 2, 3]);
    });

    test('a name that would run into another is left out', () {
      // "Top 2nd", "Top 3rd", "Mid 4th", "Mid 5th" as the feed sent them:
      // each 52 wide, 40 apart.
      final spans = [at(60, 52), at(100, 52), at(140, 52), at(180, 52)];
      final kept = momentumAxisLabelsKept(spans, latest: 3);
      // The first and the latest stay; of the two between, the one that
      // clears both.
      expect(kept, [0, 3]);
      for (var i = 1; i < kept.length; i++) {
        expect(spans[kept[i]].left - spans[kept[i - 1]].right,
            greaterThanOrEqualTo(8));
      }
    });

    test('the latest period wins over the ones before it', () {
      final spans = [at(0, 14), at(150, 30), at(170, 30), at(190, 30)];
      // Index 3 is both the last and the latest: 1 fits before it, 2 does
      // not fit between.
      expect(momentumAxisLabelsKept(spans, latest: 3), [0, 1, 3]);
      // With an end of axis after it, the latest still beats its
      // neighbours.
      final ended = [...spans, at(340, 20)];
      expect(momentumAxisLabelsKept(ended, latest: 3), [0, 1, 3, 4]);
    });

    test('nothing to name', () {
      expect(momentumAxisLabelsKept(const []), isEmpty);
    });
  });
}
