// A game's chart tells who is winning: one line per team in its colour
// (and the draw of a three-way match), from the winner market alone,
// however many markets the game has.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_game_lines_provider.dart';
import 'package:kute/screens/polymarket/components/game_chart_section.dart';
import 'package:kute/screens/polymarket/components/game_header.dart';
import 'package:kute/screens/polymarket/components/game_winner_lines.dart';

const PolySportsTeams _nfl =
    (teamA: 'Chiefs', teamB: 'Raiders', imageA: null, imageB: null);

/// An NFL game as Gamma lists it: eighty Yes/No markets, the likeliest of
/// them an over/under at 99%.
PolymarketEvent _game({List<PolymarketOutcome>? outcomes, String? title}) =>
    PolymarketEvent(
      id: '1',
      slug: 'nfl-kc-lv-2026-10-04',
      title: title ?? 'Chiefs vs. Raiders',
      volume: 1,
      volume24hr: 1,
      liquidity: 1,
      category: 'sports',
      conditionId: 'c',
      gameId: 42,
      outcomes: outcomes ??
          [
            const PolymarketOutcome(
                name: 'Chiefs vs. Raiders: O/U 28.5',
                price: 0.99,
                tokenId: 'ou-28-yes',
                noTokenId: 'ou-28-no'),
            const PolymarketOutcome(
                name: 'Chiefs vs. Raiders',
                price: 0.625,
                tokenId: 'kc',
                noTokenId: 'lv'),
            for (var i = 0; i < 78; i++)
              PolymarketOutcome(
                  name: 'Spread: Chiefs (-${i + 1}.5)',
                  price: 0.9 - i / 100,
                  tokenId: 'sp-$i-yes',
                  noTokenId: 'sp-$i-no'),
          ],
    );

const _moneyline = PolyGameLine(
  kind: 'moneyline',
  question: 'Chiefs vs. Raiders',
  sideA: 'Chiefs',
  sideB: 'Raiders',
  priceA: 0.625,
  priceB: 0.375,
  tokenA: 'kc',
  tokenB: 'lv',
);

const _spread = PolyGameLine(
  kind: 'spreads',
  question: 'Spread: Chiefs (-4.5)',
  line: -4.5,
  sideA: 'Chiefs',
  sideB: 'Raiders',
  priceA: 0.5,
  priceB: 0.5,
  tokenA: 'sp-yes',
  tokenB: 'sp-no',
);

const _total = PolyGameLine(
  kind: 'totals',
  question: 'Chiefs vs. Raiders: O/U 44.5',
  line: 44.5,
  sideA: 'Over',
  sideB: 'Under',
  priceA: 0.52,
  priceB: 0.48,
  tokenA: 'over',
  tokenB: 'under',
);

void main() {
  test('a game with eighty markets charts its two winner lines', () {
    final lines = polyGameWinnerLines(
      event: _game(),
      sportsTeams: _nfl,
      lines: const PolyGameLines(
          moneyline: _moneyline, spread: _spread, total: _total),
      drawLabel: 'Draw',
    );
    expect([for (final l in lines) l.tokenId], ['kc', 'lv']);
    expect([for (final l in lines) l.label], ['Chiefs', 'Raiders']);
    // The title's first team the first colour, its second the second.
    expect([for (final l in lines) l.color],
        [kGameSideColors[0], kGameSideColors[1]]);
    expect(lines.first.price, 0.625);
    // The over/under at 99% is not on the chart.
    expect(lines.any((l) => l.tokenId.startsWith('ou-')), isFalse);
  });

  test('the moneyline the other way round keeps each team its colour', () {
    final lines = polyGameWinnerLines(
      event: _game(),
      sportsTeams: _nfl,
      lines: const PolyGameLines(
        moneyline: PolyGameLine(
          kind: 'moneyline',
          question: 'Raiders vs. Chiefs',
          sideA: 'Raiders',
          sideB: 'Chiefs',
          priceA: 0.375,
          priceB: 0.625,
          tokenA: 'lv',
          tokenB: 'kc',
        ),
      ),
      drawLabel: 'Draw',
    );
    expect({for (final l in lines) l.label: l.color}, {
      'Chiefs': kGameSideColors[0],
      'Raiders': kGameSideColors[1],
    });
  });

  test('a three-way match: team, draw, team', () {
    const teams = (
      teamA: 'Portugal',
      teamB: 'Norway',
      imageA: null,
      imageB: null,
    );
    final lines = polyGameWinnerLines(
      event: _game(
        title: 'Portugal vs. Norway',
        outcomes: const [
          PolymarketOutcome(
              name: 'Portugal', price: 0.5, tokenId: 'por', noTokenId: 'x'),
          PolymarketOutcome(
              name: 'Draw (Portugal vs. Norway)',
              price: 0.27,
              tokenId: 'draw',
              noTokenId: 'y'),
          PolymarketOutcome(
              name: 'Norway', price: 0.23, tokenId: 'nor', noTokenId: 'z'),
        ],
      ),
      sportsTeams: teams,
      lines: null,
      drawLabel: 'Draw',
    );
    expect([for (final l in lines) l.tokenId], ['por', 'draw', 'nor']);
    expect([for (final l in lines) l.label], ['Portugal', 'Draw', 'Norway']);
    expect([for (final l in lines) l.color],
        [kGameSideColors[0], kGameSideColors[2], kGameSideColors[1]]);
  });

  test('a two-sided event is its own pair', () {
    final lines = polyGameWinnerLines(
      event: _game(outcomes: const [
        PolymarketOutcome(name: 'Raiders', price: 0.4, tokenId: 'lv'),
        PolymarketOutcome(name: 'Chiefs', price: 0.6, tokenId: 'kc'),
      ]),
      sportsTeams: _nfl,
      lines: null,
      drawLabel: 'Draw',
    );
    expect({for (final l in lines) l.label: l.color}, {
      'Raiders': kGameSideColors[1],
      'Chiefs': kGameSideColors[0],
    });
  });

  test('no winner market: the row the board leads with, never the likeliest',
      () {
    final spreadOnly = polyGameWinnerLines(
      event: _game(),
      sportsTeams: _nfl,
      lines: const PolyGameLines(spread: _spread, total: _total),
      drawLabel: 'Draw',
    );
    expect([for (final l in spreadOnly) l.tokenId], ['sp-yes', 'sp-no']);
    final totalOnly = polyGameWinnerLines(
      event: _game(),
      sportsTeams: _nfl,
      lines: const PolyGameLines(total: _total),
      drawLabel: 'Draw',
    );
    expect([for (final l in totalOnly) l.label], ['Over', 'Under']);
  });

  test('until the game\'s lines are read there is nothing to chart', () {
    expect(
        polyGameWinnerLines(
            event: _game(), sportsTeams: _nfl, lines: null, drawLabel: 'Draw'),
        isEmpty);
    expect(
        polyGameWinnerLines(
            event: _game(),
            sportsTeams: _nfl,
            lines: PolyGameLines.empty,
            drawLabel: 'Draw'),
        isEmpty);
  });
}
