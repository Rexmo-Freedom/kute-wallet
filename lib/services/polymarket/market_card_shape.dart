// lib/services/polymarket/market_card_shape.dart
//
// What a Predictions list card shows, worked out from the event the feed
// already gave it (no reads of its own):
//
//   * a game: the two teams in the title's order, each with its win chance
//     (the moneyline) and, once the game is on, its score;
//   * a single Yes/No market: the Yes chance and the day's move;
//   * an event with many outcomes: its two most likely outcomes.
//
// A game whose moneyline the feed did not carry is not a game here: it
// falls back to one of the other two shapes rather than show empty rows.
//
// Pure Dart; unit tested in
// test/services/polymarket/market_card_shape_test.dart.

import 'package:kute/models/polymarket_model.dart' show PolymarketOutcome;
import 'package:kute/screens/polymarket/components/price_format.dart';
import 'package:kute/services/polymarket/live_game/game_score.dart';
import 'package:kute/services/polymarket/live_game/game_sides.dart';

enum PolyCardShape { game, yesNo, outcomes }

/// The two sides of a game as the card lists them: the title's names in
/// the title's order, each side's chance of winning, and the chance of a
/// draw on a three-way (football) market.
class PolyCardGame {
  final String nameA;
  final String nameB;
  final double chanceA;
  final double chanceB;
  final double? draw;

  /// The outcome each side's chance was read from (its image is the
  /// crest's fallback). The same outcome twice on a single moneyline.
  final PolymarketOutcome outcomeA;
  final PolymarketOutcome outcomeB;

  const PolyCardGame({
    required this.nameA,
    required this.nameB,
    required this.chanceA,
    required this.chanceB,
    this.draw,
    required this.outcomeA,
    required this.outcomeB,
  });
}

bool _isYesOrNo(String name) {
  final n = name.trim().toLowerCase();
  return n == 'yes' || n == 'no';
}

/// Two names for the same team: equal, one inside the other, or sharing
/// their last word ("San Diego Padres" and "Padres").
bool _sameTeam(String a, String b) {
  final x = a.trim().toLowerCase(), y = b.trim().toLowerCase();
  if (x.isEmpty || y.isEmpty) return false;
  return x == y ||
      x.contains(y) ||
      y.contains(x) ||
      x.split(' ').last == y.split(' ').last;
}

double _price(PolymarketOutcome o, Map<String, double> live) =>
    (o.tokenId == null ? null : live[o.tokenId]) ?? o.price;

/// True for a literal Yes / No pair: the single-market shape.
bool polyCardIsYesNo(List<PolymarketOutcome> outcomes) =>
    outcomes.length == 2 &&
    outcomes.any((o) => o.name.trim().toLowerCase() == 'yes') &&
    outcomes.any((o) => o.name.trim().toLowerCase() == 'no');

/// The game on a card titled [title], or null when the title is not a
/// match or [outcomes] hold no winner market for it. [live] is the latest
/// price per token, where the feed has one.
///
/// The winner is read, in this order, from: a two-sided event whose
/// outcomes are the teams; a football three-way (team, draw, team); the
/// "A vs B" market among a game's many (its price is its first team's).
PolyCardGame? polyCardGame(
  String title,
  List<PolymarketOutcome> outcomes, {
  Map<String, double> live = const {},
}) {
  final teams = titleTeams(title);
  if (teams == null) return null;
  final (a, b) = teams;

  if (outcomes.length == 2 &&
      !outcomes.any((o) => _isYesOrNo(o.name) || o.hasYesNo)) {
    // The teams themselves; the title's order wins over the market's.
    final swapped = !_sameTeam(outcomes[0].name, a) &&
        !_sameTeam(outcomes[1].name, b) &&
        (_sameTeam(outcomes[0].name, b) || _sameTeam(outcomes[1].name, a));
    final oa = swapped ? outcomes[1] : outcomes[0];
    final ob = swapped ? outcomes[0] : outcomes[1];
    return PolyCardGame(
      nameA: a,
      nameB: b,
      chanceA: _price(oa, live),
      chanceB: _price(ob, live),
      outcomeA: oa,
      outcomeB: ob,
    );
  }

  if (gameThreeWaySides(a, b, [for (final o in outcomes) o.name])
      case final sides?) {
    final oa = outcomes[sides.a], ob = outcomes[sides.b];
    return PolyCardGame(
      nameA: a,
      nameB: b,
      chanceA: _price(oa, live),
      chanceB: _price(ob, live),
      draw: _price(outcomes[sides.draw], live),
      outcomeA: oa,
      outcomeB: ob,
    );
  }

  // A game with many markets: the one named for the match itself is the
  // moneyline, priced for the first team its own name gives.
  for (final o in outcomes) {
    if (!o.hasYesNo || o.name.contains(' - ')) continue;
    final named = titleTeams(o.name);
    // "A vs. B: O/U 5.5" names the match too, and is not its winner.
    if (named == null || named.$2.contains(':')) continue;
    final straight = _sameTeam(named.$1, a) && _sameTeam(named.$2, b);
    final turned = _sameTeam(named.$1, b) && _sameTeam(named.$2, a);
    if (!straight && !turned) continue;
    final first = _price(o, live).clamp(0.0, 1.0);
    final second =
        (live[o.noTokenId] ?? (1.0 - first)).clamp(0.0, 1.0).toDouble();
    return PolyCardGame(
      nameA: a,
      nameB: b,
      chanceA: straight ? first.toDouble() : second,
      chanceB: straight ? second : first.toDouble(),
      outcomeA: o,
      outcomeB: o,
    );
  }
  return null;
}

/// Which of the three shapes a card takes: [game] when there is one, else
/// by its outcomes.
PolyCardShape polyCardShape(
        PolyCardGame? game, List<PolymarketOutcome> outcomes) =>
    game != null
        ? PolyCardShape.game
        : polyCardIsYesNo(outcomes)
            ? PolyCardShape.yesNo
            : PolyCardShape.outcomes;

/// A filler Polymarket lists for an outcome that has no market yet
/// ("Candidate A" to "Candidate Z" and "Other" under an election, ready
/// to be renamed): Gamma keeps it switched off, at the no-liquidity
/// default price of exactly 50%, and it has never traded. Told by that
/// price together with a volume Gamma reports as zero (the Kute feed
/// keeps it): a real outcome that sits at 50% has traded, and one whose
/// volume is not known is never taken for a filler.
bool polyIsPlaceholderOutcome(PolymarketOutcome o, {double? livePrice}) {
  final volume = o.volume;
  return ((livePrice ?? o.price) - 0.5).abs() < 0.0005 &&
      volume != null &&
      volume <= 0;
}

/// [outcomes] without the fillers ([polyIsPlaceholderOutcome]), for a
/// card's rows and count and a chart's lines: "Candidate A 50%" is not
/// the runner-up of a race led at 99%. Only among three or more outcomes
/// and only while real ones remain: a new two-sided market at 50/50 with
/// no trade yet keeps both its sides.
List<PolymarketOutcome> polyRealOutcomes(
  List<PolymarketOutcome> outcomes, {
  Map<String, double> live = const {},
}) {
  if (outcomes.length < 3) return outcomes;
  final real = [
    for (final o in outcomes)
      if (!polyIsPlaceholderOutcome(o,
          livePrice: o.tokenId == null ? null : live[o.tokenId]))
        o,
  ];
  return real.isEmpty || real.length == outcomes.length ? outcomes : real;
}

/// The two most likely of [outcomes] (fewer when the event has fewer),
/// most likely first; equal chances keep the feed's order. Fillers with
/// no market behind them are passed over ([polyRealOutcomes]).
List<PolymarketOutcome> polyCardTopOutcomes(
  List<PolymarketOutcome> all, {
  Map<String, double> live = const {},
}) {
  final outcomes = polyRealOutcomes(all, live: live);
  final indexed = [for (var i = 0; i < outcomes.length; i++) i];
  indexed.sort((x, y) {
    final byPrice =
        _price(outcomes[y], live).compareTo(_price(outcomes[x], live));
    return byPrice != 0 ? byPrice : x.compareTo(y);
  });
  return [for (final i in indexed.take(2)) outcomes[i]];
}

/// A chance as the cards write it, which is how every Predictions surface
/// writes one ([formatPolyChance]): one decimal at most ("62.4%", "24%"),
/// "<1%" and ">99%" at the two ends, and a flat "0%" / "100%" only for a
/// settled price.
String polyCardChance(double price) => formatPolyChance(price);

/// The other side of a two-sided market as the cards write it: what the
/// leader's written chance leaves of 100, so the two always add up
/// ("50.5%" and "49.5%", never two prices rounded apart).
String polyCardOtherSideChance(double leaderPrice) =>
    formatPolyChancePair(leaderPrice).second;

/// The day's move in whole points with its sign ("+6", "−4"); null when
/// the feed did not carry it or it rounds to nothing.
String? polyCardDayMove(double? move) =>
    formatPolyChanceMove(move, whole: true);

/// A game's score split per side, in the title's order.
class PolyCardScore {
  /// Goals, points, sets won (tennis) or maps won (esports).
  final int a;
  final int b;

  /// Tennis: the games of the set being played ("3–4"), title order.
  final String? setGames;

  const PolyCardScore({required this.a, required this.b, this.setGames});
}

/// [score] as the app holds it (home first) split for the title's two
/// sides; null when it is not a pair of numbers (cricket). [period] tells
/// a tennis set in play ("S1" with "3-4") from a plain score.
PolyCardScore? polyCardScore(
  String score, {
  String? period,
  required bool? firstIsHome,
}) {
  final sport = gameSportOf(score: score, period: period);
  final parsed = GameScore.parse(score, sport);
  if (!parsed.hasPair) return null;
  final turn = firstIsHome == false;
  String? setGames;
  // Sets won fall short of the sets written while the last one is on.
  if (parsed.sets.isNotEmpty &&
      parsed.home! + parsed.away! < parsed.sets.length) {
    final (h, w) = parsed.sets.last;
    setGames = turn ? '$w–$h' : '$h–$w';
  }
  return PolyCardScore(
    a: turn ? parsed.away! : parsed.home!,
    b: turn ? parsed.home! : parsed.away!,
    setGames: setGames,
  );
}

/// Which side the card sets in the primary colour: the one ahead on the
/// score once there is one, else the likelier winner. 1 for the first
/// side, -1 for the second, 0 when nothing separates them.
int polyCardLeader({
  PolyCardScore? score,
  required double chanceA,
  required double chanceB,
}) {
  if (score != null && score.a != score.b) return score.a > score.b ? 1 : -1;
  if (chanceA == chanceB) return 0;
  return chanceA > chanceB ? 1 : -1;
}
