// What a Predictions list card shows: which of its three shapes, the teams
// in the title's order, who leads, the draw of a three-way, and how a
// chance is written at the two ends.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/screens/polymarket/components/price_format.dart';
import 'package:kute/services/polymarket/live_game/game_sides.dart';
import 'package:kute/services/polymarket/market_card_shape.dart';

PolymarketOutcome _side(String name, double price, {String? token}) =>
    PolymarketOutcome(name: name, price: price, tokenId: token);

/// One market of an event with several (it has its own Yes and No).
PolymarketOutcome _market(String name, double yes, {String token = 't'}) =>
    PolymarketOutcome(
        name: name, price: yes, tokenId: token, noTokenId: '$token-no');

void main() {
  group('the teams a title names', () {
    test('without the league, the tail or the series length', () {
      expect(titleTeams('Broncos vs. 49ers'), ('Broncos', '49ers'));
      expect(titleTeams('LoL: T1 vs Gen.G (BO3)'), ('T1', 'Gen.G'));
      expect(titleTeams('Arsenal vs Chelsea - More Markets'),
          ('Arsenal', 'Chelsea'));
    });

    test('a question that mentions a match is not a match', () {
      expect(titleTeams('Will Portugal win the World Cup?'), isNull);
      expect(
          titleTeams(
              'What will the announcers say during Scotland vs Brazil?'),
          isNull);
    });
  });

  group('which shape', () {
    test('a Yes/No market', () {
      final outcomes = [_side('Yes', 0.24), _side('No', 0.76)];
      final game = polyCardGame('Will it rain in Lisbon?', outcomes);
      expect(game, isNull);
      expect(polyCardShape(game, outcomes), PolyCardShape.yesNo);
    });

    test('an event with many outcomes', () {
      final outcomes = [
        _market('Portugal', 0.16),
        _market('Spain', 0.84),
        _market('France', 0.05),
      ];
      final game = polyCardGame('World Cup winner', outcomes);
      expect(polyCardShape(game, outcomes), PolyCardShape.outcomes);
      expect(polyCardTopOutcomes(outcomes).map((o) => o.name),
          ['Spain', 'Portugal']);
    });

    test('a game whose moneyline the feed did not carry is not a game', () {
      final outcomes = [
        _market('Spread: Padres (-1.5)', 0.58),
        _market('Padres vs. Brewers: O/U 5.5', 0.43),
        _market('Padres Team Total: O/U 3.5', 0.5),
      ];
      final game = polyCardGame('Padres vs. Brewers', outcomes);
      expect(game, isNull);
      expect(polyCardShape(game, outcomes), PolyCardShape.outcomes);
    });

    test('a Yes/No prop about a match is a Yes/No market', () {
      final outcomes = [_side('Yes', 0.6), _side('No', 0.4)];
      final game = polyCardGame('Arsenal vs Chelsea', outcomes);
      expect(game, isNull);
      expect(polyCardShape(game, outcomes), PolyCardShape.yesNo);
    });
  });

  group('a game', () {
    test('two team outcomes follow the title, not the market', () {
      final game = polyCardGame('Broncos vs. 49ers', [
        _side('49ers', 0.64),
        _side('Broncos', 0.36),
      ])!;
      expect((game.nameA, game.nameB), ('Broncos', '49ers'));
      expect((game.chanceA, game.chanceB), (0.36, 0.64));
      expect(game.draw, isNull);
    });

    test('a live price replaces the feed price', () {
      final game = polyCardGame(
        'Lakers vs Warriors',
        [_side('Lakers', 0.5, token: 'a'), _side('Warriors', 0.5, token: 'b')],
        live: const {'a': 0.7, 'b': 0.3},
      )!;
      expect((game.chanceA, game.chanceB), (0.7, 0.3));
    });

    test('a football three-way keeps the draw apart', () {
      final game = polyCardGame('Arsenal vs Chelsea', [
        _market('Will Chelsea win on 2026-10-04?', 0.21),
        _market('Draw (Arsenal vs Chelsea)', 0.27),
        _market('Will Arsenal win on 2026-10-04?', 0.52),
      ])!;
      expect((game.nameA, game.nameB), ('Arsenal', 'Chelsea'));
      expect((game.chanceA, game.chanceB), (0.52, 0.21));
      expect(game.draw, 0.27);
    });

    test('among many markets the one named for the match is the moneyline',
        () {
      final game = polyCardGame('Padres vs. Brewers', [
        _market('Spread: Padres (-1.5)', 0.58, token: 's'),
        _market('Padres vs. Brewers', 0.765, token: 'm'),
        _market('Padres vs. Brewers: O/U 5.5', 0.43, token: 'o'),
      ])!;
      expect(game.chanceA, 0.765);
      expect(game.chanceB, closeTo(0.235, 1e-9));
    });

    test('a moneyline named the other way round is turned', () {
      final game = polyCardGame('Padres vs. Brewers', [
        _market('Brewers vs. Padres', 0.3),
        _market('Spread: Padres (-1.5)', 0.58, token: 's'),
        _market('Padres vs. Brewers: O/U 5.5', 0.43, token: 'o'),
      ])!;
      expect(game.chanceA, closeTo(0.7, 1e-9));
      expect(game.chanceB, 0.3);
    });
  });

  group('the score per side', () {
    test('turns round when the title names the away team first', () {
      final s = polyCardScore('3-0', firstIsHome: false)!;
      expect((s.a, s.b), (0, 3));
      expect(polyCardScore('21-26', firstIsHome: true)!.a, 21);
      expect(polyCardScore('2-1', firstIsHome: null)!.a, 2);
    });

    test('tennis counts sets and names the set in play', () {
      final s = polyCardScore('6-3, 3-4', period: 'S2', firstIsHome: true)!;
      expect((s.a, s.b), (1, 0));
      expect(s.setGames, '3–4');
      final first = polyCardScore('3-4', period: 'S1', firstIsHome: false)!;
      expect((first.a, first.b), (0, 0));
      expect(first.setGames, '4–3');
      final over = polyCardScore('6-3, 6-4', period: 'S2', firstIsHome: true)!;
      expect((over.a, over.b), (2, 0));
      expect(over.setGames, isNull);
    });

    test('an esports series score is a plain pair', () {
      final s = polyCardScore('1-2', period: '4/5', firstIsHome: true)!;
      expect((s.a, s.b), (1, 2));
      expect(s.setGames, isNull);
    });

    test('text that is not a pair has no score', () {
      expect(polyCardScore('145/3 (20)', firstIsHome: true), isNull);
      expect(polyCardScore('', firstIsHome: true), isNull);
    });
  });

  group('who leads', () {
    test('the score once there is one, else the odds', () {
      expect(
          polyCardLeader(
              score: const PolyCardScore(a: 0, b: 3),
              chanceA: 0.9,
              chanceB: 0.1),
          -1);
      expect(
          polyCardLeader(
              score: const PolyCardScore(a: 1, b: 1),
              chanceA: 0.6,
              chanceB: 0.4),
          1);
      expect(polyCardLeader(chanceA: 0.36, chanceB: 0.64), -1);
      expect(polyCardLeader(chanceA: 0.5, chanceB: 0.5), 0);
    });
  });

  group('how a chance is written', () {
    test('one decimal at most, and the two ends', () {
      expect(polyCardChance(0.24), '24%');
      expect(polyCardChance(0.765), '76.5%');
      expect(polyCardChance(0.9345), '93.5%');
      expect(polyCardChance(0.62), '62%');
      expect(polyCardChance(0.01), '1%');
      expect(polyCardChance(0.99), '99%');
      expect(polyCardChance(0.004), '<1%');
      expect(polyCardChance(0.006), '<1%');
      expect(polyCardChance(0.994), '>99%');
      expect(polyCardChance(0.9955), '>99%');
      expect(polyCardChance(0), '0%');
      expect(polyCardChance(1), '100%');
      expect(polyCardChance(double.nan), '0%');
    });

    test('every Predictions surface writes it the same way', () {
      expect(formatPolyChance(0.9345), polyCardChance(0.9345));
      expect(formatPolyChanceFigure(0.9345), '93.5');
      expect(formatPolyChanceFigure(0.004), '<1');
      // Read against a scale, or about to be paid: the ends keep detail.
      expect(formatPolyChance(0.0045, fineEnds: true), '0.45%');
      expect(formatPolyChance(0.9955, fineEnds: true), '99.55%');
      expect(formatPolyChance(0.9345, fineEnds: true), '93.5%');
      expect(formatPolyChance(0.99999, fineEnds: true), '99.99%');
      expect(formatPolyChance(0.00001, fineEnds: true), '0.01%');
    });

    test('two sides written off one price add up to 100', () {
      expect(formatPolyChancePair(0.624), (first: '62.4%', second: '37.6%'));
      expect(formatPolyChancePair(0.6245), (first: '62.5%', second: '37.5%'));
      expect(formatPolyChancePair(0.5), (first: '50%', second: '50%'));
      expect(formatPolyChancePair(0.9955), (first: '>99%', second: '<1%'));
      expect(formatPolyChancePair(0.9955, fineEnds: true),
          (first: '99.55%', second: '0.45%'));
      expect(formatPolyChancePair(0.9896), (first: '99%', second: '1%'));
      expect(formatPolyChancePair(1), (first: '100%', second: '0%'));
      expect(formatPolyChancePair(0), (first: '0%', second: '100%'));
    });

    test('a move over a range: one decimal at most, signed', () {
      expect(formatPolyChanceMove(0.259), '+25.9');
      expect(formatPolyChanceMove(0.04), '+4');
      expect(formatPolyChanceMove(-0.0312), '−3.1');
      expect(formatPolyChanceMove(0.0002), isNull);
      expect(formatPolyPoints(4.04), '4');
      expect(formatPolyPoints(6.25), '6.3');
    });

    test('a price an order rests at keeps its precision', () {
      expect(formatPolyCents(0.395), '39.5%');
      expect(formatPolyCents(0.0045), '0.45%');
      expect(formatPolyCents(0.5), '50%');
    });

    test('the day\'s move in whole points, nothing when flat or unknown', () {
      expect(polyCardDayMove(0.06), '+6');
      expect(polyCardDayMove(-0.041), '−4');
      expect(polyCardDayMove(0.004), isNull);
      expect(polyCardDayMove(null), isNull);
    });
  });

  // Shape of brazil-presidential-election-first-round-winner on
  // 2026-10-05: one candidate at 99.85%, the others near zero, and
  // "Candidate A" to "Candidate Z" and "Other" switched off at Gamma's
  // default 50% with no volume. The card read "Candidate A 50%" second.
  group('fillers with no market behind them', () {
    const race = [
      PolymarketOutcome(
          name: 'Lula', price: 0.0005, tokenId: 'l', volume: 3207701),
      PolymarketOutcome(
          name: 'Flavio Bolsonaro', price: 0.9985, tokenId: 'f', volume: 2478836),
      PolymarketOutcome(
          name: 'Ronaldo Caiado', price: 0.0005, tokenId: 'r', volume: 5133),
      PolymarketOutcome(name: 'Candidate A', price: 0.5, tokenId: 'a', volume: 0),
      PolymarketOutcome(name: 'Candidate B', price: 0.5, tokenId: 'b', volume: 0),
      PolymarketOutcome(name: 'Other', price: 0.5, tokenId: 'o', volume: 0),
    ];

    test('are not a card\'s runner-up, and not counted as more', () {
      final top = polyCardTopOutcomes(race);
      expect(top.map((o) => o.name), ['Flavio Bolsonaro', 'Lula']);
      expect(polyRealOutcomes(race).length, 3);
    });

    test('a real outcome at 50% that has traded stays', () {
      const real = PolymarketOutcome(
          name: 'Tarcisio', price: 0.5, tokenId: 't', volume: 1200);
      expect(polyIsPlaceholderOutcome(real), isFalse);
      expect(polyCardTopOutcomes([...race, real]).last.name, 'Tarcisio');
    });

    test('an outcome at 50% whose volume is not known is not taken for '
        'one', () {
      const unknown = PolymarketOutcome(name: 'Ana', price: 0.5, tokenId: 'x');
      expect(polyIsPlaceholderOutcome(unknown), isFalse);
    });

    test('a live price tells too: a filler that starts trading is real',
        () {
      expect(polyIsPlaceholderOutcome(race[3], livePrice: 0.12), isFalse);
      expect(
          polyRealOutcomes(race, live: const {'a': 0.12})
              .any((o) => o.name == 'Candidate A'),
          isTrue);
    });

    test('a new two-sided market at 50/50 keeps both sides, and an event '
        'of nothing but fillers keeps them all', () {
      const pair = [
        PolymarketOutcome(name: 'Up', price: 0.5, tokenId: 'u', volume: 0),
        PolymarketOutcome(name: 'Down', price: 0.5, tokenId: 'd', volume: 0),
      ];
      expect(polyRealOutcomes(pair), pair);
      expect(polyCardTopOutcomes(pair).length, 2);
      final fillers = race.sublist(3);
      expect(polyRealOutcomes(fillers), fillers);
    });
  });
}
