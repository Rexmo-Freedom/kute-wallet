// The names under a game's momentum axis: the period that starts at each
// tick, complete and the same for every game of the sport.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/polymarket/live_game/game_momentum.dart';
import 'package:kute/services/polymarket/live_game/game_score.dart';

void main() {
  test('quarters are named where they start, never "End …"', () {
    String? nfl(String p) => momentumPeriodLabel(GameSport.americanFootball, p);
    expect(nfl('Q1'), isNull); // the axis's own start
    expect(nfl('End Q1'), 'Q2');
    expect(nfl('Q2'), 'Q2');
    expect(nfl('End Q2'), 'HT');
    expect(nfl('Half'), 'HT');
    expect(nfl('Halftime'), 'HT');
    expect(nfl('Q3'), 'Q3');
    expect(nfl('End Q3'), 'Q4');
    expect(nfl('End of 3rd Quarter'), 'Q4');
    expect(nfl('Q4'), 'Q4');
    expect(nfl('End Q4'), isNull);
    expect(nfl('OT'), 'OT');
    expect(momentumPeriodLabel(GameSport.basketball, 'End Q1'), 'Q2');
    expect(momentumAxisStartLabel(GameSport.americanFootball), 'Q1');
    expect(momentumAxisStartLabel(GameSport.basketball), 'Q1');
  });

  test('a full game reads Q2 HT Q3 Q4, each once, at its start', () {
    const feed = [
      'End Q1', 'Q2', 'End Q2', 'Half', 'Q3', 'End Q3', 'Q4', 'End Q4', //
    ];
    final names = momentumLabelsOnce([
      for (final p in feed) momentumPeriodLabel(GameSport.americanFootball, p)
    ]);
    expect(names, [null, 'Q2', null, 'HT', 'Q3', null, 'Q4', null]);
  });

  test('a feed that only wrote the ends still names every quarter', () {
    final names = momentumLabelsOnce([
      for (final p in const ['End Q1', 'End Q2', 'Q3', 'End Q3'])
        momentumPeriodLabel(GameSport.americanFootball, p)
    ]);
    expect(names, ['Q2', 'HT', 'Q3', 'Q4']);
  });

  test('football: the break, between 0\' and 90\'', () {
    expect(momentumPeriodLabel(GameSport.soccer, '1H'), isNull);
    expect(momentumPeriodLabel(GameSport.soccer, 'HT'), 'HT');
    expect(momentumPeriodLabel(GameSport.soccer, '2H'), isNull);
    expect(momentumPeriodLabel(GameSport.soccer, 'ET'), 'ET');
    expect(momentumAxisStartLabel(GameSport.soccer), "0'");
  });

  test('hockey periods, and sports with their own words', () {
    expect(momentumPeriodLabel(GameSport.hockey, 'P1'), isNull);
    expect(momentumPeriodLabel(GameSport.hockey, 'End P1'), 'P2');
    expect(momentumPeriodLabel(GameSport.hockey, 'P3'), 'P3');
    expect(momentumPeriodLabel(GameSport.hockey, 'End P3'), isNull);
    expect(momentumAxisStartLabel(GameSport.hockey), 'P1');
    expect(momentumPeriodLabel(GameSport.tennis, ' S2 '), 'S2');
    expect(momentumPeriodLabel(GameSport.esports, ''), isNull);
    expect(momentumAxisStartLabel(GameSport.tennis), isNull);
  });
}
