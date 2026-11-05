// A game's "More markets" read for the screen (game_line_rows.dart), from
// real Gamma events (test/fixtures/polymarket_games/): a LoL best-of-five
// (Dplus KIA vs Bilibili Gaming), a Dota 2 best-of-three (Yellow
// Submarine vs GamerLegion), a CS2 best-of-three (INOX Division vs
// Honvéd), a tennis match (Fils vs Fritz) and a football match's "More
// Markets" (Arsenal vs Hull City), plus questions sampled from an NFL and
// an NBA game.
//
//   * the period: Game N, Map N, Set N, a half, a quarter, else the match;
//   * the kind: winner, handicap, a total (games, sets, kills, rounds,
//     duration, a team's, a player's) or another question;
//   * the label without the league, the teams, the period and the
//     Over/Under noise;
//   * the sides by short names ("GL", "YS"; "Fils", "Fritz").

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/services/polymarket/live_game/game_line_rows.dart';

PolymarketEvent _fixture(String name) => PolymarketModel().parseEventsRaw([
      jsonDecode(File('test/fixtures/polymarket_games/$name.json')
          .readAsStringSync()) as Map<String, dynamic>,
    ]).single;

GameLineReader _reader(PolymarketEvent e) => GameLineReader(
    eventTitle: e.title,
    teams: e.teams,
    esports: e.tags.contains('esports'),
    outcomes: e.outcomes);

/// The row of [e]'s market whose question is [question].
GameLineRow _row(PolymarketEvent e, String question, [GameLineReader? reader]) {
  final o =
      e.outcomes.firstWhere((o) => GameLineReader.questionOf(o) == question);
  return (reader ?? _reader(e)).read(o);
}

/// A market read from its question and Gamma type alone.
GameLineRow _q(String title, String question,
    {String kind = '',
    List<String> sides = const [],
    double? line,
    List<PolymarketTeam> teams = const []}) {
  final o = PolymarketOutcome(
    name: question,
    price: 0.5,
    tokenId: 't',
    noTokenId: 'n',
    marketLine: PolymarketMarketLine(
        kind: kind, question: question, line: line, sides: sides),
  );
  return GameLineReader(eventTitle: title, teams: teams, outcomes: [o]).read(o);
}

void main() {
  group('periods', () {
    test('esports: Game N and Map N, wherever the question says it', () {
      for (final (q, key) in [
        ('LoL: Dplus KIA vs Bilibili Gaming - Game 1 Winner', 'game1'),
        ('Total Kills Over/Under 24.5 in Game 4?', 'game4'),
        ('Game 3: Duration Over/Under 32:30 min?', 'game3'),
        ('Game 5: Any Player Penta Kill?', 'game5'),
        ('Map 2 Total Rounds: Over/Under 18.5', 'map2'),
        (
          'Map 1 Rounds Handicap: INOX Division (-3.5) vs Honvéd (+3.5)',
          'map1'
        ),
        // The series: no period.
        ('Games Total: O/U 3.5', 'match'),
        ('Game Handicap: DK (-1.5) vs Bilibili Gaming (+1.5)', 'match'),
      ]) {
        expect(gamePeriodOf(q).key, key, reason: q);
      }
    });

    test('tennis sets, halves, quarters, hockey periods, innings', () {
      for (final (q, kind, key) in [
        ('Set 1 Winner: Arthur Fils vs Taylor Fritz', '', 'set1'),
        ('Fils vs. Fritz: Set 2 Games O/U 9.5', '', 'set2'),
        (
          'Set Handicap: Taylor Fritz (-1.5) vs Arthur Fils (+1.5)',
          '',
          'match'
        ),
        ('Arsenal FC vs. Hull City AFC: 1st Half O/U 1.5', '', 'half1'),
        (
          'Arsenal FC vs. Hull City AFC: Both Teams to Score in Second Half',
          '',
          'half2'
        ),
        ('1H Spread: Warriors (-3.5)', '', 'half1'),
        ('Jaguars vs. Ravens: 2H Moneyline', '', 'half2'),
        ('Will Portugal lead at half-time?', '', 'half1'),
        ('3Q Spread: Jaguars (-2.5)', '', 'q3'),
        ('Jaguars vs. Ravens: Both Teams to Score Points - 1Q', '', 'q1'),
        ('Ducks vs. Oilers: 2nd Period O/U 1.5', '', 'period2'),
        ('Yankees vs. Red Sox: First 5 Innings O/U 4.5', '', 'first5'),
        ('Yankees vs. Red Sox: Run in 1st inning?', '', 'inning1'),
        // Gamma's type when the question does not say.
        ('Arsenal FC 1H (-1.5)', 'first_half_spreads', 'half1'),
        ('Warriors O/U 60.5', 'q2_totals', 'q2'),
        ('Heat vs. Warriors: O/U 235.5', 'totals', 'match'),
      ]) {
        expect(gamePeriodOf(q, kind: kind).key, key, reason: q);
      }
    });

    test(
        'the chips of a best-of-five, a best-of-three and a football '
        'match', () {
      Set<String> periods(String name) {
        final e = _fixture(name);
        final r = _reader(e);
        return {for (final o in e.outcomes) r.read(o).period.key};
      }

      expect(periods('lol_dk_blg_bo5'),
          {'match', 'game1', 'game2', 'game3', 'game4', 'game5'});
      expect(periods('dota_yes_gl_bo3'), {'match', 'game1', 'game2', 'game3'});
      expect(periods('cs2_inox_honved_bo3'), {'match', 'map1', 'map2', 'map3'});
      expect(periods('arsenal_hull_more_markets'), {'match', 'half1', 'half2'});
      expect(periods('tennis_fils_fritz'), {'match', 'set1', 'set2'});
    });
  });

  group('LoL best-of-five', () {
    final e = _fixture('lol_dk_blg_bo5');
    final r = _reader(e);

    test(
        'a game\'s winner: no label, the teams by Polymarket\'s own short '
        'names', () {
      final row =
          _row(e, 'LoL: Dplus KIA vs Bilibili Gaming - Game 2 Winner', r);
      expect(row.period.key, 'game2');
      expect(row.type, GameLineType.winner);
      expect(row.label, '');
      expect(row.words, GameSideWords.named);
      // "Bilibili Gaming" is long: both sides by short name, "BLG" as the
      // handicap questions write it, "DK" likewise.
      expect((row.sideA, row.sideB), ('DK', 'BLG'));
    });

    test('kills and duration: the line alone, the period cut out', () {
      final kills = _row(e, 'Total Kills Over/Under 24.5 in Game 4?', r);
      expect((kills.period.key, kills.type, kills.label),
          ('game4', GameLineType.kills, '24.5'));
      expect(kills.words, GameSideWords.overUnder);
      final duration = _row(e, 'Game 1: Duration Over/Under 32:30 min?', r);
      expect((duration.period.key, duration.type, duration.label),
          ('game1', GameLineType.duration, '32:30'));
    });

    test('the series: total games and the handicap, by its team', () {
      final total = _row(e, 'Games Total: O/U 3.5', r);
      expect((total.period.isWhole, total.type, total.label),
          (true, GameLineType.totalGames, '3.5'));
      final h =
          _row(e, 'Game Handicap: DK (-1.5) vs Bilibili Gaming (+1.5)', r);
      expect((h.type, h.label, h.sideA, h.sideB),
          (GameLineType.handicap, 'DK -1.5', 'DK -1.5', 'BLG +1.5'));
      final other = _row(e, 'Game Handicap: BLG (-2.5) vs Dplus KIA (+2.5)', r);
      expect((other.label, other.sideA, other.sideB),
          ('BLG -2.5', 'BLG -2.5', 'DK +2.5'));
    });

    test('a game\'s yes / no question keeps its words, never its game', () {
      // The outcome's own name lost its game ("Both Teams Slay Baron
      // Nashor"): the question Gamma wrote is read instead.
      final o = e.outcomes.firstWhere((o) =>
          o.marketLine?.question == 'Game 3: Both Teams Slay Baron Nashor?');
      expect(o.name, 'Both Teams Slay Baron Nashor');
      final row = r.read(o);
      expect((
        row.period.key,
        row.type,
        row.label,
        row.words
      ), (
        'game3',
        GameLineType.other,
        'Both Teams Slay Baron Nashor',
        GameSideWords.yesNo
      ));
    });
  });

  group('Dota 2 best-of-three', () {
    final e = _fixture('dota_yes_gl_bo3');
    final r = _reader(e);

    test('"Yellow Submarine" reads YS, "GamerLegion" GL', () {
      final row =
          _row(e, 'Dota 2: Yellow Submarine vs GamerLegion - Game 2 Winner', r);
      expect((row.period.key, row.type, row.label),
          ('game2', GameLineType.winner, ''));
      expect((row.sideA, row.sideB), ('YS', 'GL'));
      final h =
          _row(e, 'Game Handicap: GL (-1.5) vs Yellow Submarine (+1.5)', r);
      expect((h.label, h.sideA, h.sideB), ('GL -1.5', 'GL -1.5', 'YS +1.5'));
    });

    test('a game\'s props: the words, the game cut out', () {
      final row = _row(e, 'Game 1: Both Teams Beat Roshan?', r);
      expect((row.period.key, row.type, row.label),
          ('game1', GameLineType.other, 'Both Teams Beat Roshan'));
      expect(_row(e, 'Game 2: Ends in Daytime?', r).label, 'Ends in Daytime');
    });
  });

  test('CS2: maps, rounds and the map handicap', () {
    final e = _fixture('cs2_inox_honved_bo3');
    final r = _reader(e);
    final w =
        _row(e, 'Counter-Strike: INOX Division vs Honvéd - Map 1 Winner', r);
    expect((w.period.key, w.type, w.sideA, w.sideB),
        ('map1', GameLineType.winner, 'INOX', 'Honvéd'));
    final rounds = _row(e, 'Map 1 Total Rounds: Over/Under 21.5', r);
    expect((rounds.period.key, rounds.type, rounds.label),
        ('map1', GameLineType.rounds, '21.5'));
    final h = _row(
        e, 'Map 2 Rounds Handicap: INOX Division (-6.5) vs Honvéd (+6.5)', r);
    expect((h.period.key, h.type, h.label, h.sideB),
        ('map2', GameLineType.handicap, 'INOX -6.5', 'Honvéd +6.5'));
  });

  test('tennis: surnames as Polymarket writes them, sets and games', () {
    final e = _fixture('tennis_fils_fritz');
    final r = _reader(e);
    final w = _row(e, 'Set 1 Winner: Arthur Fils vs Taylor Fritz', r);
    expect((w.period.key, w.type, w.sideA, w.sideB),
        ('set1', GameLineType.winner, 'Fils', 'Fritz'));
    final sets = _row(e, 'Arthur Fils vs. Taylor Fritz: Total Sets O/U 2.5', r);
    expect((sets.type, sets.label, sets.words),
        (GameLineType.totalSets, '2.5', GameSideWords.overUnder));
    final games = _row(e, 'Fils vs. Fritz: Set 2 Games O/U 9.5', r);
    expect((games.period.key, games.type, games.label),
        ('set2', GameLineType.totalGames, '9.5'));
    expect(_row(e, 'Fils vs. Fritz: Match O/U 22.5', r).type,
        GameLineType.totalGames);
    expect(
        _row(
                e,
                'Rolex Paris Masters: Completed Match: Arthur Fils vs Taylor '
                'Fritz',
                r)
            .label,
        'Completed Match');
    final h =
        _row(e, 'Set Handicap: Taylor Fritz (-1.5) vs Arthur Fils (+1.5)', r);
    // In sets, beside the handicap in games.
    expect(h.type, GameLineType.setHandicap);
    expect(
        _row(e, 'Game Spread: Arthur Fils (-0.5) vs Taylor Fritz (+0.5)', r)
            .type,
        GameLineType.handicap);
    expect((h.label, h.sideB), ('Fritz -1.5', 'Fils +1.5'));
  });

  group('football More Markets', () {
    final e = _fixture('arsenal_hull_more_markets');
    final r = _reader(e);

    test('spreads by the club\'s short name', () {
      final h = _row(e, 'Spread: Arsenal FC (-1.5)', r);
      expect((
        h.period.isWhole,
        h.type,
        h.label,
        h.sideA,
        h.sideB
      ), (
        true,
        GameLineType.handicap,
        'Arsenal -1.5',
        'Arsenal -1.5',
        'Hull City +1.5'
      ));
      final half = _row(e, '1st Half Spread: Hull City AFC (-2.5)', r);
      expect((half.period.key, half.label), ('half1', 'Hull City -2.5'));
    });

    test('goals, team goals and both teams to score', () {
      final t = _row(e, 'Arsenal FC vs. Hull City AFC: O/U 2.5', r);
      expect((t.type, t.label), (GameLineType.total, '2.5'));
      final h1 = _row(e, 'Arsenal FC vs. Hull City AFC: 1st Half O/U 1.5', r);
      expect((h1.period.key, h1.type, h1.label),
          ('half1', GameLineType.total, '1.5'));
      final team = _row(
          e, 'Arsenal FC vs. Hull City AFC: Hull City AFC 2nd Half O/U 1.5', r);
      expect((team.period.key, team.type, team.label),
          ('half2', GameLineType.teamTotals, 'Hull City 1.5'));
      final btts = _row(e,
          'Arsenal FC vs. Hull City AFC: Both Teams to Score in First Half', r);
      expect((
        btts.period.key,
        btts.type,
        btts.label,
        btts.words
      ), (
        'half1',
        GameLineType.other,
        'Both Teams to Score',
        GameSideWords.yesNo
      ));
    });
  });

  group('US sports questions', () {
    const nfl = 'Jaguars vs. Ravens';
    const nba = 'Heat vs. Warriors';

    test('quarters and halves of the lines', () {
      final q = _q(nfl, 'Jaguars vs. Ravens: 3Q O/U 5.5',
          kind: 'q3_totals', sides: ['Over', 'Under'], line: 5.5);
      expect(
          (q.period.key, q.type, q.label), ('q3', GameLineType.total, '5.5'));
      final ml = _q(nfl, 'Jaguars vs. Ravens: 1Q Moneyline',
          kind: 'q1_moneyline', sides: ['Jaguars', 'Ravens']);
      expect((ml.period.key, ml.type, ml.label, ml.sideA, ml.sideB),
          ('q1', GameLineType.winner, '', 'Jaguars', 'Ravens'));
      final s = _q(nfl, '2H Spread: Jaguars (-3.5)',
          kind: 'second_half_spreads',
          sides: ['Jaguars', 'Ravens'],
          line: -3.5);
      expect((s.period.key, s.label, s.sideB),
          ('half2', 'Jaguars -3.5', 'Ravens +3.5'));
    });

    test('a team\'s numbers and a player\'s', () {
      final team = _q(nfl, 'Jaguars Total Touchdowns: O/U 2.5',
          kind: 'team_touchdowns', sides: ['Over', 'Under'], line: 2.5);
      expect((team.type, team.label),
          (GameLineType.teamTotals, 'Jaguars Total Touchdowns 2.5'));
      final tt = _q(nba, 'Warriors 1H Team Total: O/U 62.5',
          kind: 'first_half_team_totals', sides: ['Over', 'Under'], line: 62.5);
      expect((tt.period.key, tt.type, tt.label),
          ('half1', GameLineType.teamTotals, 'Warriors 62.5'));
      // A player's line is a Yes / No market: Yes is the Over.
      final p = _q(nba, 'Stephen Curry: Points O/U 25.5',
          kind: 'points', sides: ['Yes', 'No'], line: 25.5);
      expect((
        p.type,
        p.label,
        p.words
      ), (
        GameLineType.players,
        'Stephen Curry: Points 25.5',
        GameSideWords.overUnder
      ));
    });

    test('other questions keep their words', () {
      final race = _q(nba, 'Heat vs. Warriors: Race to 10 Points',
          kind: 'basketball_game_race_to_points', sides: ['Heat', 'Warriors']);
      expect((race.type, race.label, race.sideA),
          (GameLineType.other, 'Race to 10 Points', 'Heat'));
      final ot = _q(nba, 'Heat vs. Warriors: Overtime?',
          kind: 'basketball_game_overtime', sides: ['Yes', 'No']);
      expect((ot.label, ot.words), ('Overtime', GameSideWords.yesNo));
      final margin = _q(nfl, 'Exact Margin: Jaguars by 25+',
          kind: 'exact_margin', sides: ['Yes', 'No']);
      expect(margin.label, 'Exact Margin: Jaguars by 25+');
      final odd = _q(nba, 'Heat vs. Warriors: Odd/Even Score',
          kind: 'basketball_odd_even', sides: ['Odd', 'Even']);
      expect((odd.words, odd.sideA, odd.sideB),
          (GameSideWords.named, 'Odd', 'Even'));
      final two = _q(
          nfl, 'Jaguars vs. Ravens: Total Two-Point Conversions O/U 0.5',
          kind: 'two_point_conversions', sides: ['Over', 'Under'], line: 0.5);
      expect((two.type, two.label),
          (GameLineType.total, 'Total Two-Point Conversions 0.5'));
    });
  });

  test('read without its line (no Gamma type): the name says it all', () {
    const o = PolymarketOutcome(
        name: 'Colts vs. Commanders: O/U 46.5', price: 0.5, tokenId: 't');
    final row = GameLineReader(eventTitle: 'Colts vs. Commanders').read(o);
    expect((row.period.isWhole, row.type, row.label, row.words),
        (true, GameLineType.total, '46.5', GameSideWords.overUnder));
  });
}
