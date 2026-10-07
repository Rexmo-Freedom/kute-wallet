// The range a Predictions chart opens on and keeps, with no range row to
// pick another: a game from its kickoff, a young market, a short round or
// a resolved one its whole life, anything else its last month.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/screens/polymarket/components/poly_chart_history.dart';

void main() {
  final now = DateTime.utc(2026, 10, 7, 12);
  DateTime ago(Duration d) => now.subtract(d);

  group('a game that has kicked off', () {
    test('opens on the shortest range that holds kickoff to now', () {
      for (final (age, range) in [
        (const Duration(minutes: 20), '1h'),
        (const Duration(hours: 2), '6h'),
        (const Duration(hours: 10), '1d'),
        (const Duration(days: 3), '1w'),
      ]) {
        expect(
            polyChartAutoRange(now: now, gameStart: ago(age), inPlay: true),
            range,
            reason: '$age');
      }
    });

    test('a finished game still opens on its own range', () {
      expect(
          polyChartAutoRange(
              now: now,
              gameStart: ago(const Duration(hours: 3)),
              resolved: true),
          '6h');
    });

    test('a week-old game opens on ALL', () {
      expect(
          polyChartAutoRange(now: now, gameStart: ago(const Duration(days: 8))),
          'max');
    });

    test('the kickoff wins over the market\'s age', () {
      expect(
          polyChartAutoRange(
              now: now,
              gameStart: ago(const Duration(minutes: 30)),
              openedAt: ago(const Duration(days: 60))),
          '1h');
    });
  });

  test('a game in play whose kickoff is unknown opens on 1D', () {
    expect(polyChartAutoRange(now: now, inPlay: true), '1d');
  });

  test('a game not started yet reads as any market', () {
    expect(
        polyChartAutoRange(
            now: now, gameStart: now.add(const Duration(hours: 2))),
        '1m');
    expect(
        polyChartAutoRange(
            now: now,
            gameStart: now.add(const Duration(hours: 2)),
            openedAt: ago(const Duration(days: 2))),
        'max');
  });

  group('a market opened', () {
    test('under a week ago shows its whole life', () {
      for (final age in [
        const Duration(hours: 3),
        const Duration(days: 6, hours: 23),
      ]) {
        expect(polyChartAutoRange(now: now, openedAt: ago(age)), 'max',
            reason: '$age');
      }
    });

    test('under a month ago shows its whole life (shorter than 1M)', () {
      expect(
          polyChartAutoRange(
              now: now, openedAt: ago(const Duration(days: 20))),
          'max');
    });

    test('a month ago or more shows its last month', () {
      for (final age in [kPolyMonthRange, const Duration(days: 400)]) {
        expect(polyChartAutoRange(now: now, openedAt: ago(age)), '1m',
            reason: '$age');
      }
    });

    test('at an unknown time shows its last month', () {
      expect(polyChartAutoRange(now: now), '1m');
    });
  });

  test('a 5 / 15 minute round shows its whole life', () {
    expect(
        polyChartAutoRange(
            now: now,
            shortMarket: true,
            openedAt: ago(const Duration(days: 90))),
        'max');
  });

  test('a resolved market shows its whole life', () {
    expect(
        polyChartAutoRange(
            now: now, resolved: true, openedAt: ago(const Duration(days: 90))),
        'max');
  });

  test('a game\'s start date is not taken for when its market opened', () {
    expect(
        polyChartOpenedAt(_event(gameId: 1, startDate: now)), isNull);
    expect(polyChartOpenedAt(_event(startDate: now)), now);
  });
}

PolymarketEvent _event({int? gameId, DateTime? startDate}) =>
    PolymarketEvent(
      id: 'e',
      slug: 'e',
      title: 'E',
      volume: 0,
      liquidity: 0,
      category: '',
      conditionId: 'c',
      outcomes: const [],
      gameId: gameId,
      startDate: startDate,
    );
