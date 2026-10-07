// lib/screens/polymarket/components/game_winner_lines.dart
//
// The lines a game's odds chart draws. A game has dozens of markets
// (totals, spreads, props); its chart tells one story, who is winning:
// one line per team in the team's colour, and the draw of a three-way
// match. Never the game's most likely markets, whatever they are.

import 'package:flutter/material.dart';

import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_game_lines_provider.dart';
import 'package:kute/screens/polymarket/components/game_chart_section.dart';
import 'package:kute/screens/polymarket/components/game_header.dart';
import 'package:kute/services/polymarket/live_game/game_sides.dart'
    show gameShortSideNames;

/// One line of a game's chart: the outcome's token, the side's name, its
/// colour and the price it opens on.
typedef PolyGameChartLine = ({
  String tokenId,
  String label,
  Color color,
  double price,
});

bool _yesNo(String s) {
  final v = s.trim().toLowerCase();
  return v == 'yes' || v == 'no';
}

/// The winner market of [event] as chart lines, each team in its colour
/// ([gameSideColors]: the title's first team the first colour):
///
///   1. a three-way match: team, draw (labelled [drawLabel]), team;
///   2. the moneyline of [lines]: its two sides;
///   3. a two-outcome event's own pair.
///
/// Each team's line is labelled by its short name, never the same as the
/// other team's ([gameShortSideNames]: "Leeds" / "Man Utd", not "United"
/// twice); [teams] give Gamma's own short names (the event's when null).
///
/// A game with none of them charts the market its board leads with (the
/// main spread, else the main total), its two sides. Empty when the game
/// has no such market, or while [lines] is still being read: the chart is
/// then left out rather than drawn from the most likely markets.
List<PolyGameChartLine> polyGameWinnerLines({
  required PolymarketEvent event,
  required PolySportsTeams? sportsTeams,
  required PolyGameLines? lines,
  required String drawLabel,
  List<PolymarketTeam>? teams,
}) {
  bool has(String? token) => token != null && token.isNotEmpty;
  final known = teams ?? event.teams;
  (String, String) short(String a, String b) =>
      gameShortSideNames(a, b, teams: known);

  final wdl = polyWdlOutcomes(event, sportsTeams);
  if (wdl != null) {
    final sides = gameSideColors(event.title, wdl.teamAName, wdl.teamBName);
    final names = short(wdl.teamAName, wdl.teamBName);
    final out = <PolyGameChartLine>[
      if (has(wdl.teamA.tokenId))
        (
          tokenId: wdl.teamA.tokenId!,
          label: names.$1,
          color: sides.$1,
          price: wdl.teamA.price,
        ),
      if (has(wdl.draw.tokenId))
        (
          tokenId: wdl.draw.tokenId!,
          label: drawLabel,
          color: kGameSideColors[2],
          price: wdl.draw.price,
        ),
      if (has(wdl.teamB.tokenId))
        (
          tokenId: wdl.teamB.tokenId!,
          label: names.$2,
          color: sides.$2,
          price: wdl.teamB.price,
        ),
    ];
    if (out.length >= 2) return out;
  }

  List<PolyGameChartLine> pair(PolyGameLine line, (Color, Color) colors,
      {bool teamSides = false}) {
    final names =
        teamSides ? short(line.sideA, line.sideB) : (line.sideA, line.sideB);
    return [
      if (has(line.tokenA))
        (
          tokenId: line.tokenA!,
          label: names.$1,
          color: colors.$1,
          price: line.priceA,
        ),
      if (has(line.tokenB))
        (
          tokenId: line.tokenB!,
          label: names.$2,
          color: colors.$2,
          price: line.priceB,
        ),
    ];
  }

  final moneyline = lines?.winner;
  if (moneyline != null &&
      has(moneyline.tokenA) &&
      !_yesNo(moneyline.sideA) &&
      !_yesNo(moneyline.sideB)) {
    return pair(moneyline,
        gameSideColors(event.title, moneyline.sideA, moneyline.sideB),
        teamSides: true);
  }

  final own = event.outcomes;
  if (own.length == 2 &&
      !_yesNo(own[0].name) &&
      !_yesNo(own[1].name) &&
      !own.any((o) => o.hasYesNo) &&
      has(own[0].tokenId)) {
    final sides = gameSideColors(event.title, own[0].name, own[1].name);
    final names = short(own[0].name, own[1].name);
    return [
      (
        tokenId: own[0].tokenId!,
        label: names.$1,
        color: sides.$1,
        price: own[0].price,
      ),
      if (has(own[1].tokenId))
        (
          tokenId: own[1].tokenId!,
          label: names.$2,
          color: sides.$2,
          price: own[1].price,
        ),
    ];
  }

  // No winner market: the board's first row, as it stands.
  for (final line in [lines?.spread, lines?.total]) {
    if (line != null && has(line.tokenA)) {
      return pair(line, (kGameSideColors[0], kGameSideColors[1]));
    }
  }
  return const [];
}
