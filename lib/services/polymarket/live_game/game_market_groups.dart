// lib/services/polymarket/live_game/game_market_groups.dart
//
// The kinds of market a game carries beside its main lines, read from each
// market's own question ("1H Spread: Patriots (-1.5)", "Patriots vs.
// Bills: 1Q O/U 5.5", "Patriots Team Total: O/U 10.5"), so a game with
// hundreds of markets can be listed and filtered by kind.
//
// Pure Dart; unit tested in
// test/services/polymarket/game_market_groups_test.dart.

/// In the order a game's "More markets" lists them.
enum GameMarketGroup { winner, spreads, totals, halves, quarters, props }

extension GameMarketGroupX on GameMarketGroup {
  /// Analytics value.
  String get key => switch (this) {
        GameMarketGroup.winner => 'winner',
        GameMarketGroup.spreads => 'spreads',
        GameMarketGroup.totals => 'totals',
        GameMarketGroup.halves => 'halves',
        GameMarketGroup.quarters => 'quarters',
        GameMarketGroup.props => 'props',
      };
}

final RegExp _kHalf = RegExp(
    r'\b[12]h\b|\b(first|second|1st|2nd)[- ]half\b|\bhalf[- ]?time\b');
final RegExp _kQuarter = RegExp(
    r'\b[1-4]q\b|\b(first|second|third|fourth|1st|2nd|3rd|4th)[- ]quarter\b');
final RegExp _kSpread = RegExp(r'\bspread\b|\bhandicap\b|\([+-]\s*\d');
final RegExp _kOverUnder =
    RegExp(r'^(o\s*/\s*u|over\s*/\s*under)\s*\d');

/// The group of the market named [name]. A market about one half or one
/// quarter goes with its period whatever it prices; a spread or a total of
/// the whole game with its kind; a plain "A vs B" (or a moneyline) with
/// the winner; everything else (team totals, exact margins, both teams to
/// score, players) with the props.
GameMarketGroup gameMarketGroupOf(String name) {
  final n = name.toLowerCase().trim();
  if (_kQuarter.hasMatch(n)) return GameMarketGroup.quarters;
  if (_kHalf.hasMatch(n)) return GameMarketGroup.halves;
  if (_kSpread.hasMatch(n)) return GameMarketGroup.spreads;
  final colon = n.lastIndexOf(':');
  final before = colon < 0 ? '' : n.substring(0, colon);
  final after = (colon < 0 ? n : n.substring(colon + 1)).trim();
  // "A vs. B: O/U 47.5" is the game's total; "A Team Total: O/U 10.5" and
  // "A Total Touchdowns: O/U 2.5" are about one team.
  if (_kOverUnder.hasMatch(after) &&
      (before.isEmpty || before.contains(' vs'))) {
    return GameMarketGroup.totals;
  }
  if (colon < 0 && n.contains(' vs')) return GameMarketGroup.winner;
  if (after == 'moneyline' || n.endsWith(' moneyline')) {
    return GameMarketGroup.winner;
  }
  return GameMarketGroup.props;
}
