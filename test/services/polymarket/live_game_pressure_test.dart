// The pressure signal's thresholds: minimum climb, minimum duration,
// steadiness, hysteresis, the time-decay guard and the totals input.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/polymarket/live_game/game_pressure.dart';

/// Eleven one-minute samples ending at [values].last.
List<double?> s(List<double> values) => [
      for (var i = 0; i < 11 - values.length; i++) values.first,
      ...values,
    ];

void main() {
  // 3.5 points over 5 minutes, every minute up.
  final steady = s([0.400, 0.407, 0.414, 0.421, 0.428, 0.435]);

  test('a steady climb with no score change is pressure', () {
    final p = detectPressure(a: steady, quietMinutes: 20, leader: 0)!;
    expect(p.side, PressureSide.a);
    expect(p.drift, greaterThanOrEqualTo(kPressureEnter));
    expect(p.minutes, inInclusiveRange(kPressureMinMinutes, kPressureMaxMinutes));
    expect(p.confirmedByTotals, isFalse);
  });

  test('side B is read as the mirror of a two-way market', () {
    final p = detectPressure(
        a: [for (final v in steady) 1 - v!], quietMinutes: 20, leader: 0)!;
    expect(p.side, PressureSide.b);
  });

  test('under the minimum climb: nothing', () {
    // 2.5 points, just as steady.
    expect(
        detectPressure(
            a: s([0.400, 0.405, 0.410, 0.415, 0.420, 0.425]),
            quietMinutes: 20,
            leader: 0),
        isNull);
  });

  test('a recent score change resets the clock', () {
    // 2 minutes to settle + 4 minutes minimum.
    expect(detectPressure(a: steady, quietMinutes: 5, leader: 0), isNull);
    expect(detectPressure(a: steady, quietMinutes: 6, leader: 0), isNull,
        reason: 'only 4 usable minutes, and the climb over 4 is under 3 pts');
    expect(detectPressure(a: steady, quietMinutes: 7, leader: 0), isNotNull);
  });

  test('a jump is not pressure', () {
    // +4 points in one minute, flat otherwise: something happened.
    expect(
        detectPressure(
            a: s([0.40, 0.40, 0.40, 0.44, 0.44, 0.44]),
            quietMinutes: 20,
            leader: 0),
        isNull);
  });

  test('chop is not pressure', () {
    // Ends 3 points up but went everywhere on the way.
    expect(
        detectPressure(
            a: s([0.40, 0.44, 0.39, 0.45, 0.40, 0.43]),
            quietMinutes: 20,
            leader: 0),
        isNull);
  });

  test('hysteresis: it holds above 1.5 points and drops under it', () {
    final on = detectPressure(a: steady, quietMinutes: 20, leader: 0)!;
    // The climb fades to 2 points over the window: not enough to turn on...
    final faded = s([0.415, 0.421, 0.428, 0.435, 0.437, 0.436, 0.436]);
    expect(detectPressure(a: faded, quietMinutes: 20, leader: 0), isNull);
    // ...but enough to stay on.
    final held = detectPressure(
        a: faded, quietMinutes: 20, leader: 0, previous: on);
    expect(held, isNotNull);
    expect(held!.side, PressureSide.a);
    // Flat for the whole window: off.
    expect(
        detectPressure(
            a: s([0.436, 0.436, 0.436, 0.436, 0.436, 0.436, 0.436, 0.436, 0.436]),
            quietMinutes: 20,
            leader: 0,
            previous: on),
        isNull);
    // A score change always drops it.
    expect(
        detectPressure(a: faded, quietMinutes: 1, leader: 0, previous: on),
        isNull);
  });

  test('the side ahead does not count on its own (the clock is on its side)',
      () {
    expect(detectPressure(a: steady, quietMinutes: 20, leader: 1), isNull);
    // Score unknown: a side above 50% is treated as ahead.
    final favourite = [for (final v in steady) v! + 0.3];
    expect(detectPressure(a: favourite, quietMinutes: 20), isNull);
    expect(detectPressure(a: steady, quietMinutes: 20), isNotNull);
    // Behind on the scoreboard and climbing: that is pressure.
    expect(detectPressure(a: steady, quietMinutes: 20, leader: -1), isNotNull);
  });

  group('totals', () {
    final overUp = s([0.50, 0.503, 0.506, 0.509, 0.512, 0.515]);
    final overDown = s([0.50, 0.495, 0.49, 0.485, 0.48, 0.475]);

    test('the Over rising too lowers the bar to 2 points', () {
      final small = s([0.400, 0.405, 0.410, 0.415, 0.420, 0.425]);
      expect(detectPressure(a: small, quietMinutes: 20, leader: 0), isNull);
      final p = detectPressure(
          a: small, over: overUp, quietMinutes: 20, leader: 0)!;
      expect(p.confirmedByTotals, isTrue);
      expect(
          detectPressure(a: small, over: overDown, quietMinutes: 20, leader: 0),
          isNull);
    });

    test('the side ahead counts when the Over rises with it', () {
      expect(
          detectPressure(a: steady, over: overUp, quietMinutes: 20, leader: 1),
          isNotNull);
      expect(
          detectPressure(
              a: steady, over: overDown, quietMinutes: 20, leader: 1),
          isNull);
    });

    test('a totals series of another length is ignored, not trusted', () {
      final p = detectPressure(
          a: steady, over: const [0.5, 0.6], quietMinutes: 20, leader: 0)!;
      expect(p.confirmedByTotals, isFalse);
    });
  });

  test('fails soft on thin data', () {
    expect(detectPressure(a: const [0.4, 0.5], leader: 0), isNull);
    expect(detectPressure(a: List<double?>.filled(11, null), leader: 0), isNull);
    expect(detectPressure(a: steady, leader: 0, inPlay: false), isNull);
    final gappy = [...steady]..[8] = null;
    expect(detectPressure(a: gappy, quietMinutes: 20, leader: 0), isNull);
  });
}
