// How each sport's score on Polymarket's sports feed is read. The strings
// are the ones sampled from the live WebSocket on 2026-10-04.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/polymarket/live_game/game_score.dart';

void main() {
  group('gameSportOf', () {
    test('known league codes', () {
      expect(gameSportOf(league: 'nfl', score: '21-26', period: 'Q4'),
          GameSport.americanFootball);
      expect(gameSportOf(league: 'wnba', score: '77-82', period: 'Q4'),
          GameSport.basketball);
      expect(gameSportOf(league: 'challenger', score: '1-6, 3-4', period: 'S2'),
          GameSport.tennis);
      expect(gameSportOf(league: 'nhl', score: '2-1', period: 'P2'),
          GameSport.hockey);
      expect(gameSportOf(league: 'mlb', score: '3-2', period: 'T5'),
          GameSport.baseball);
    });

    test('soccer has no league list: its periods give it away', () {
      for (final league in ['unl', 'fif', 'conl', 'col1', 'es2']) {
        expect(gameSportOf(league: league, score: '1-1', period: '2H'),
            GameSport.soccer);
      }
      expect(gameSportOf(league: 'conl', score: '4-0', period: 'HT'),
          GameSport.soccer);
    });

    test('a piped score is esports whatever the league', () {
      expect(gameSportOf(league: 'cs2', score: '000-000|1-2|Bo5', period: '4/5'),
          GameSport.esports);
      expect(gameSportOf(league: 'lol', score: '13-9|2-2|Bo5', period: '5/5'),
          GameSport.esports);
    });

    test('cricket is the feed with only a metadata id', () {
      expect(
          gameSportOf(
              league: 'cricket', score: '4-162', period: 'Live', cricket: true),
          GameSport.cricket);
    });

    test('tennis by shape, hockey by period, else other', () {
      expect(gameSportOf(league: 'xyz', score: '6-3, 2-1', period: ''),
          GameSport.tennis);
      expect(gameSportOf(league: 'xyz', score: '1-0', period: 'S1'),
          GameSport.tennis);
      expect(gameSportOf(league: 'xyz', score: '1-0', period: 'P1'),
          GameSport.hockey);
      expect(gameSportOf(league: 'xyz', score: '10-7', period: 'Q2'),
          GameSport.other);
      expect(gameSportOf(), GameSport.other);
    });
  });

  group('GameScore.parse', () {
    test('soccer and NFL: one pair', () {
      final s = GameScore.parse('1-1', GameSport.soccer);
      expect((s.home, s.away), (1, 1));
      expect(s.text, '1–1');
      final n = GameScore.parse(' 21-26 ', GameSport.americanFootball);
      expect((n.home, n.away), (21, 26));
    });

    test('tennis: sets won, the set in play not counted', () {
      final s = GameScore.parse('1-6, 3-4', GameSport.tennis);
      expect(s.sets, [(1, 6), (3, 4)]);
      expect((s.home, s.away), (0, 1));
      final done = GameScore.parse('6-3, 3-6, 7-6(5)', GameSport.tennis);
      expect((done.home, done.away), (2, 1));
      final firstSet = GameScore.parse('5-4', GameSport.tennis);
      expect((firstSet.home, firstSet.away), (0, 0));
      expect(firstSet.sets, [(5, 4)]);
    });

    test('esports: map score, series score, best of', () {
      final lol = GameScore.parse('13-9|2-2|Bo5', GameSport.esports);
      expect((lol.home, lol.away), (2, 2));
      expect((lol.mapHome, lol.mapAway), (13, 9));
      expect(lol.bestOf, 5);
      expect(lol.text, '2–2');
      final cs = GameScore.parse('000-000|1-2|Bo5', GameSport.esports);
      expect((cs.home, cs.away), (1, 2));
      expect((cs.mapHome, cs.mapAway), (0, 0));
      final short = GameScore.parse('5-7|1-0', GameSport.esports);
      expect((short.home, short.away, short.bestOf), (1, 0, null));
    });

    test('text that is not a pair stays raw', () {
      final c = GameScore.parse('120/3', GameSport.cricket);
      expect(c.hasPair, isFalse);
      expect(c.text, '120/3');
      expect(GameScore.parse(null, GameSport.soccer).raw, '');
      expect(GameScore.parse('abc, def', GameSport.tennis).hasPair, isFalse);
    });
  });

  test('period numbers', () {
    expect(esportsMapNumber('4/5'), 4);
    expect(esportsMapNumber('2H'), isNull);
    expect(tennisSetNumber('S2'), 2);
    expect(tennisSetNumber('Q2'), isNull);
    expect(baseballInning('Top 2nd'), 2);
    expect(baseballInning('Mid 4th'), 4);
    expect(baseballInning('Bot 11th'), 11);
    expect(baseballInning('Final'), isNull);
  });
}
