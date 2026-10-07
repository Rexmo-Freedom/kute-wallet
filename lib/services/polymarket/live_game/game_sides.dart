// lib/services/polymarket/live_game/game_sides.dart
//
// Which side of a game a name is, and a score written in the order a
// market's title names its teams. The app holds every score home first
// ("3-0" is home 3, away 0; the feed's own order is turned to that where
// it enters, feed_score_order.dart), while a title may name the away team first
// ("Broncos vs. 49ers" played at the 49ers): shown beside that title the
// score must read "0 – 3".
//
// Pure Dart; unit tested in test/services/polymarket/game_sides_test.dart.

import 'package:kute/models/polymarket_model.dart'
    show PolymarketTeam, kPolyClubTags, polyLooksLikeTeamName;

/// Which side of the feed's score (home or away) a market side is, from
/// the event's teams and, failing that, the feed's own team names. Null
/// when neither says.
bool? gameSideIsHome(
  String? side, {
  required List<PolymarketTeam> teams,
  String? feedHome,
  String? feedAway,
}) {
  final a = side?.trim().toLowerCase() ?? '';
  if (a.isEmpty) return null;
  bool same(String? other) {
    final b = other?.trim().toLowerCase() ?? '';
    if (b.isEmpty) return false;
    return a == b ||
        a.contains(b) ||
        b.contains(a) ||
        a.split(' ').last == b.split(' ').last;
  }

  // Abbreviations are short enough to sit inside another name by accident:
  // they only count when they are the whole side.
  bool isAbbr(String? other) => a == (other?.trim().toLowerCase() ?? '');

  for (final t in teams) {
    final home = t.ordering == 'home', away = t.ordering == 'away';
    if (!home && !away) continue;
    if (same(t.name) || isAbbr(t.abbreviation)) return home;
  }
  if (same(feedHome)) return true;
  if (same(feedAway)) return false;
  return null;
}

/// Which side of the match [title] names [name] is: 0 for its first team,
/// 1 for its second, 2 for the draw of a three-way market; null when the
/// title is not a match or [name] is neither team. This is the one rule
/// the colours of a game's sides are keyed by (first team, first colour),
/// wherever the game is drawn.
int? gameSideIndex(String title, String? name) {
  final n = name?.trim().toLowerCase() ?? '';
  if (n.isEmpty) return null;
  if (n == 'draw' || n == 'tie' || n.startsWith('draw ')) return 2;
  final teams = titleTeams(title);
  if (teams == null) return null;
  bool same(String other) {
    final b = other.trim().toLowerCase();
    if (b.isEmpty) return false;
    return n == b ||
        n.contains(b) ||
        b.contains(n) ||
        n.split(' ').last == b.split(' ').last;
  }

  final first = same(teams.$1), second = same(teams.$2);
  if (first == second) {
    // Neither, or both by a shared word ("FC"): only an exact name says.
    if (n == teams.$1.trim().toLowerCase()) return 0;
    if (n == teams.$2.trim().toLowerCase()) return 1;
    return null;
  }
  return first ? 0 : 1;
}

/// The first team a match title names ("NBA: Lakers vs Warriors (BO5)" ->
/// "Lakers"), or null when the title is not "A vs B".
String? titleFirstTeam(String title) {
  final t = title.replaceFirst(RegExp(r'^[A-Za-z0-9\- ]+:\s+'), '');
  final m =
      RegExp(r'^(.+?)\s+vs\.?\s+(.+)$', caseSensitive: false).firstMatch(t);
  final first = m?.group(1)?.trim() ?? '';
  return first.isEmpty ? null : first;
}

/// The two teams a match title names, in its order, without the league
/// prefix, a " - More Markets" tail or a "(BO3)" suffix
/// ("LoL: T1 vs Gen.G (BO3)" -> ("T1", "Gen.G")). Null when the title is
/// not a plain "A vs B": a question that mentions a match is not one.
(String, String)? titleTeams(String title) {
  final t = title.replaceFirst(RegExp(r'^[A-Za-z0-9\- ]+:\s+'), '').trim();
  if (t.endsWith('?')) return null;
  final m =
      RegExp(r'^(.+?)\s+vs\.?\s+(.+)$', caseSensitive: false).firstMatch(t);
  if (m == null) return null;
  String clean(String s) => s
      .replaceFirst(RegExp(r'\s+-\s+.*$'), '')
      .replaceAll(RegExp(r'\s*\([^)]*\)\s*$'), '')
      .trim();
  final a = clean(m.group(1)!), b = clean(m.group(2)!);
  return polyLooksLikeTeamName(a) && polyLooksLikeTeamName(b) ? (a, b) : null;
}

/// Whether the first team [title] names is the home side; null when the
/// title is not a match or nothing says which side it is.
bool? titleFirstIsHome(
  String title, {
  required List<PolymarketTeam> teams,
  String? feedHome,
  String? feedAway,
}) =>
    gameSideIsHome(titleFirstTeam(title),
        teams: teams, feedHome: feedHome, feedAway: feedAway);

final RegExp _kPair = RegExp(r'(\d+)\s*-\s*(\d+)');

/// [score] (home first, as the app holds it) in the title's order and
/// spaced for reading: "3-0" with the away team named first is "0 – 3";
/// a tennis "6-3, 2-1" turns each set round. With [firstIsHome] unknown
/// the feed's order is kept. Text with no "a-b" pair comes back as it is.
String scoreInTitleOrder(String score, {required bool? firstIsHome}) =>
    score.trim().replaceAllMapped(
        _kPair,
        (m) =>
            firstIsHome == false ? '${m[2]} – ${m[1]}' : '${m[1]} – ${m[2]}');

/// Whether [score] holds at least one "a-b" pair.
bool scoreHasPair(String score) => _kPair.hasMatch(score);

/// Whether [name] is the draw of a three-way match: "Draw", "Tie", or the
/// draw market Gamma names after the match ("Draw (Leeds United FC vs.
/// Manchester United FC)").
bool gameIsDrawName(String name) =>
    RegExp(r'\b(draw|tie)\b', caseSensitive: false).hasMatch(name);

final RegExp _kWordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// The words of [name] that say which team it is: lower case, without
/// punctuation-only tokens ("&") and club tags ("FC", "AFC").
List<String> _teamWords(String name) => [
      for (final w in name.toLowerCase().split(RegExp(r'\s+')))
        if (_kWordChar.hasMatch(w) &&
            !kPolyClubTags.contains(w.replaceAll('.', '')))
          w.replaceAll(RegExp(r'[^\p{L}\p{N}\-]', unicode: true), ''),
    ];

/// [name] without a club tag at either end ("Leeds United FC" -> "Leeds
/// United", "AFC Bournemouth" -> "Bournemouth"). The name as given when
/// nothing would be left.
String gameTeamBareName(String name) {
  final words = name.trim().split(RegExp(r'\s+'));
  bool tag(String w) =>
      kPolyClubTags.contains(w.toLowerCase().replaceAll('.', ''));
  while (words.length > 1 && tag(words.last)) {
    words.removeLast();
  }
  while (words.length > 1 && tag(words.first)) {
    words.removeAt(0);
  }
  return words.join(' ');
}

/// How surely [name] names [team]: 2 for the same words, 1 for one's words
/// all inside the other's, 0 for neither. Club tags are not identity.
int _teamMatch(String name, String team) {
  final a = _teamWords(name), b = _teamWords(team);
  if (a.isEmpty || b.isEmpty) return 0;
  if (a.join(' ') == b.join(' ')) return 2;
  if (a.toSet().containsAll(b) || b.toSet().containsAll(a)) return 1;
  return 0;
}

/// The one team of [teams] that [name] names: by its name, alias or
/// abbreviation exactly, else the one team whose words hold [name]'s (or
/// the other way round). Null when none does, or more than one.
PolymarketTeam? gameTeamNamed(List<PolymarketTeam> teams, String name) {
  if (teams.isEmpty || name.trim().isEmpty) return null;
  final exact = [
    for (final t in teams)
      if ([t.name, t.alias ?? '', t.abbreviation ?? '']
          .any((n) => n.isNotEmpty && _teamMatch(name, n) == 2))
        t,
  ];
  if (exact.length == 1) return exact.single;
  if (exact.length > 1) return null;
  final loose = [
    for (final t in teams)
      if ([t.name, t.alias ?? '']
          .any((n) => n.isNotEmpty && _teamMatch(name, n) == 1))
        t,
  ];
  return loose.length == 1 ? loose.single : null;
}

/// The three outcomes of a three-way match among [names] (the outcome
/// names of a game's winner markets), by structure: one is the draw
/// ([gameIsDrawName]) and the other two are the teams, each matched to
/// the side of the title it names ([teamA] first). Two names that match
/// equally well keep the feed's order, which is the title's. Null unless
/// there are exactly three outcomes, one draw, and each team outcome names
/// a team of the title.
({int a, int draw, int b})? gameThreeWaySides(
    String teamA, String teamB, List<String> names) {
  if (names.length != 3) return null;
  final draws = [
    for (var i = 0; i < 3; i++)
      if (gameIsDrawName(names[i])) i
  ];
  if (draws.length != 1) return null;
  final draw = draws.single;
  final sides = [
    for (var i = 0; i < 3; i++)
      if (i != draw) i
  ];
  final i = sides[0], j = sides[1];
  final straight = (_teamMatch(names[i], teamA), _teamMatch(names[j], teamB));
  final turned = (_teamMatch(names[i], teamB), _teamMatch(names[j], teamA));
  final keep = straight.$1 + straight.$2 >= turned.$1 + turned.$2;
  final (sa, sb) = keep ? straight : turned;
  if (sa == 0 || sb == 0) return null;
  return keep ? (a: i, draw: draw, b: j) : (a: j, draw: draw, b: i);
}

/// The longest a short side name runs before it is cut further.
const int kGameShortNameMax = 12;

/// Trailing words a club's name shares with many others ("West Ham
/// United", "Brighton & Hove Albion"); the first to go when it is too long.
const Set<String> _kGenericClubWords = {
  'united',
  'city',
  'town',
  'athletic',
  'albion',
  'rovers',
  'wanderers',
  'hotspur',
  'county',
  'fc',
  'afc',
};

/// One side's short name without the other side in view: Gamma's own
/// short name for its team (its alias, "Man Utd") when shorter, else the
/// name without its club tag; a club name still longer than
/// [kGameShortNameMax] loses its generic tail and is cut before an "&"
/// ("Brighton & Hove Albion FC" -> "Brighton"), while any other long name
/// keeps its last word, which for a franchise is its nickname and for a
/// person the surname ("Los Angeles Lakers" -> "Lakers").
String _gameShortName(String name, List<PolymarketTeam> teams) {
  final bare = gameTeamBareName(name);
  final alias = gameTeamNamed(teams, name)?.alias?.trim() ?? '';
  if (alias.isNotEmpty && alias.length <= bare.length) return alias;
  if (bare.length <= kGameShortNameMax) return bare;
  final words = bare.split(RegExp(r'\s+'));
  if (words.length < 2) return bare;
  final club = bare != name.trim();
  if (!club) return words.last;
  while (words.length > 1 &&
      words.join(' ').length > kGameShortNameMax &&
      _kGenericClubWords.contains(words.last.toLowerCase())) {
    words.removeLast();
  }
  final out = <String>[];
  for (final w in words) {
    if (!_kWordChar.hasMatch(w) || w.toLowerCase() == 'and') break;
    final next = [...out, w].join(' ');
    if (out.isNotEmpty && next.length > kGameShortNameMax) break;
    out.add(w);
  }
  return out.isEmpty ? words.first : out.join(' ');
}

/// The two sides of a match ([a] and [b], as the title names them) as
/// short as a button, a chart tag or a toggle writes them, and never the
/// same: "Leeds United FC" / "Manchester United FC" read "Leeds" /
/// "Man Utd" with Gamma's teams, "Leeds United" / "Manchester" without.
/// Each side alone takes [_gameShortName]; two that would read alike (the
/// same, or one's words inside the other's: "United" beside "Leeds
/// United") each fall back to the first word the other side's name does
/// not have. [teams] are the event's teams, for their own short names.
(String, String) gameShortSideNames(String a, String b,
    {List<PolymarketTeam> teams = const []}) {
  final sa = _gameShortName(a, teams), sb = _gameShortName(b, teams);
  final wa = _teamWords(sa).toSet(), wb = _teamWords(sb).toSet();
  final clash =
      wa.isEmpty || wb.isEmpty || wa.containsAll(wb) || wb.containsAll(wa);
  if (!clash) return (sa, sb);
  final fa = _teamWords(gameTeamBareName(a)),
      fb = _teamWords(gameTeamBareName(b));
  String? firstOwn(String full, List<String> other) {
    final words = gameTeamBareName(full)
        .split(RegExp(r'\s+'))
        .where((w) => _kWordChar.hasMatch(w))
        .toList();
    for (final w in words) {
      final k = _teamWords(w);
      if (k.isNotEmpty && !other.contains(k.first)) return w;
    }
    return null;
  }

  final da = firstOwn(a, fb), db = firstOwn(b, fa);
  if (da == null || db == null || da.toLowerCase() == db.toLowerCase()) {
    final ba = gameTeamBareName(a), bb = gameTeamBareName(b);
    return ba.toLowerCase() == bb.toLowerCase()
        ? (a.trim(), b.trim())
        : (ba, bb);
  }
  return (da, db);
}
