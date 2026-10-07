// The score beside a market's title reads in the title's team order.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/services/polymarket/live_game/game_sides.dart';

void main() {
  const teams = [
    PolymarketTeam(name: '49ers', abbreviation: 'sf', ordering: 'home'),
    PolymarketTeam(name: 'Broncos', abbreviation: 'den', ordering: 'away'),
  ];

  test('the first team of a title', () {
    expect(titleFirstTeam('Broncos vs. 49ers'), 'Broncos');
    expect(titleFirstTeam('NBA: Lakers vs Warriors (BO5)'), 'Lakers');
    expect(titleFirstTeam('Will Portugal win the World Cup?'), isNull);
  });

  test('home or away comes from the teams, then from the feed names', () {
    expect(titleFirstIsHome('Broncos vs. 49ers', teams: teams), isFalse);
    expect(titleFirstIsHome('49ers vs. Broncos', teams: teams), isTrue);
    expect(
        titleFirstIsHome('Portugal vs Norway',
            teams: const [], feedHome: 'Norway', feedAway: 'Portugal'),
        isFalse);
    expect(titleFirstIsHome('Portugal vs Norway', teams: const []), isNull);
    expect(titleFirstIsHome('Who wins the election?', teams: teams), isNull);
  });

  test('an away team named first turns the score round', () {
    // Feed: home (49ers) 3, away (Broncos) 0. Title: Broncos first.
    final away = titleFirstIsHome('Broncos vs. 49ers', teams: teams);
    expect(scoreInTitleOrder('3-0', firstIsHome: away), '0 – 3');
    final home = titleFirstIsHome('49ers vs. Broncos', teams: teams);
    expect(scoreInTitleOrder('3-0', firstIsHome: home), '3 – 0');
  });

  test('unknown order keeps the feed\'s; every pair of a set score turns',
      () {
    expect(scoreInTitleOrder('2-1', firstIsHome: null), '2 – 1');
    expect(scoreInTitleOrder('6-3, 2-1', firstIsHome: false), '3 – 6, 1 – 2');
    expect(scoreInTitleOrder(' 21 - 26 ', firstIsHome: false), '26 – 21');
  });

  test('text that is not a score is left alone', () {
    expect(scoreInTitleOrder('145/3 (20)', firstIsHome: false), '145/3 (20)');
    expect(scoreHasPair('145/3 (20)'), isFalse);
    expect(scoreHasPair('1-0'), isTrue);
  });

  group('which side of the title a name is', () {
    const title = 'NFL: 49ers vs. Broncos (Week 5)';
    test('first team 0, second team 1, by name or by its last word', () {
      expect(gameSideIndex(title, '49ers'), 0);
      expect(gameSideIndex(title, 'Broncos'), 1);
      expect(gameSideIndex(title, 'Denver Broncos'), 1);
      expect(gameSideIndex(title, ' san francisco 49ERS '), 0);
    });
    test('the draw of a three-way market is 2', () {
      expect(gameSideIndex('Porto vs. Benfica', 'Draw'), 2);
    });
    test('neither team, or not a match, is null', () {
      expect(gameSideIndex(title, 'Over 45.5'), isNull);
      expect(gameSideIndex(title, null), isNull);
      expect(gameSideIndex('Will the 49ers win?', '49ers'), isNull);
    });
    test('a word both teams share does not pick a side', () {
      expect(gameSideIndex('Porto FC vs. Braga FC', 'FC'), isNull);
      expect(gameSideIndex('Porto FC vs. Braga FC', 'Braga FC'), 1);
    });
  });
}
