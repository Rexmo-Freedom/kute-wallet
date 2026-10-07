// lib/services/polymarket/live_game/feed_score_order.dart
//
// Which team a feed score's first number belongs to.
//
// Polymarket's sports feed (the live socket, Gamma's `score` on an event,
// and the Kute backend's game timeline, which keeps the feed's strings)
// writes a score as one string, "6-17". The message names `homeTeam` and
// `awayTeam` but does not say which number is whose. The order is the
// league's: Gamma's `/sports` gives every league an `ordering`, the side
// Polymarket lists first, and the score follows it. North American
// leagues are listed away first ("Broncos vs. 49ers" is played at the
// 49ers) and their score is away first; everything else is home first.
//
// Checked against ESPN's scoreboards on 2026-10-04 and 05:
//
//   league  feed (home, away, score)        ESPN                 first is
//   nfl     SF,  DEN, "6-17"                DEN 6  @ SF 17       away
//   nfl     LV,  KC,  "17-19"               KC 17  @ LV 19       away
//   nfl     SEA, LAC, "13-30"               LAC 13 @ SEA 30      away
//   nfl     PHI, LAR, "24-20" (final)       LAR 24 @ PHI 20      away
//   mlb     MIL, SD,  "3-2"                 SD 3   @ MIL 2       away
//   nhl     NYR, UTA, "0-1"                 UTA 0  @ NYR 1       away
//   nba     LAC, GS,  "38-47"               GS 38  @ LAC 47      away
//   nba     DEN, UTA, "46-39"               UTAH 46 @ DEN 41*    away
//   arg     Argentinos Jrs, Tigre, "2-1"    ARGJ 2, TIG 1        home
//   conl    Puerto Rico, Cayman, "1-0" (FT) PUR 1, CAY 0         home
//   conl    Trinidad, Curaçao, "1-1" (FT)   TRI 1, CUW 1         (level)
//   lol     Team Liquid, LYON, "2-1" maps   Liquid won maps 1, 2 home
//   (* a basket apart in time; the side each number is on is not in doubt)
//
// The rest of the app reads every score home first (the score types, the
// chart's markers, the Momentum graph, the pressure signal, the header and
// the cards, which turn it into the title's order). So the feed's string
// is turned home first once, where it enters: the socket message, the
// Gamma event and the backend timeline. Nothing downstream needs to know
// the league.
//
// Pure Dart, no imports: the socket service and the model both use it.

/// The leagues Gamma's `/sports` lists with `ordering: "away"` (read
/// 2026-10-05; the other 459 are `home`). nfl, nba, mlb and nhl are
/// checked against ESPN above; the others are taken on Gamma's word.
const Set<String> kAwayFirstScoreLeagues = {
  'nfl',
  'nba',
  'mlb',
  'nhl',
  'wnba',
  'cbb',
  'cfb',
  'cfl',
  'ufl',
  'ahl',
  'kbo',
  'darts',
  'pdcdarts',
  'modus',
};

/// Whether the feed writes [league]'s scores away first. [league] is the
/// feed's league code (`leagueAbbreviation`, the timeline's `league`, a
/// Gamma team's `league`); unknown and missing codes are home first, as
/// 459 of Gamma's 473 leagues are.
bool feedScoreIsAwayFirst(String? league) =>
    kAwayFirstScoreLeagues.contains(league?.trim().toLowerCase() ?? '');

/// The league code an event slug starts with ("nfl-den-sf-2026-10-04" ->
/// "nfl"), for a Gamma event that carries no teams. None of the
/// away-first codes holds a hyphen.
String? leagueOfEventSlug(String? slug) {
  final s = slug?.trim().toLowerCase() ?? '';
  final cut = s.indexOf('-');
  return cut <= 0 ? null : s.substring(0, cut);
}

final RegExp _kScorePair = RegExp(r'(\d+)(\s*-\s*)(\d+)');

/// [score] as the feed wrote it, home first: every "a-b" pair is turned
/// round when [league] is written away first, and the string is returned
/// as it is otherwise. A score with no pair (cricket's "182/4") is never
/// touched. Null stays null.
String? feedScoreHomeFirst(String? score, {required String? league}) {
  if (score == null || !feedScoreIsAwayFirst(league)) return score;
  return score.replaceAllMapped(
      _kScorePair, (m) => '${m[3]}${m[2]}${m[1]}');
}
