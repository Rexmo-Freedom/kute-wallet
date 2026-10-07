// lib/services/polymarket/live_game/game_score.dart
//
// How each sport writes its score on Polymarket's sports WebSocket, and what
// a change of that score means. Formats sampled from the live feed
// (2026-10-04):
//
//   soccer            "1-1"              period 1H / HT / 2H, elapsed "47"
//   NFL               "21-26"            period Q4, elapsed "4:27"
//   basketball (WNBA) "77-82"            period Q4, elapsed "02:39"
//   tennis            "1-6, 3-4"         period S2, no elapsed; one "a-b"
//                                        per set, the last one in play
//   esports (CS2)     "000-000|1-2|Bo5"  period "4/5" (map 4 of 5)
//   esports (LoL)     "13-9|2-2|Bo5"     map score | series score | best of
//   cricket           no sample was live; it sends `metadataGameId` and no
//                     teams, and its score is kept as raw text.
//
// Pure Dart, no Flutter: unit tested in
// test/services/polymarket/live_game_score_test.dart.

enum GameSport {
  soccer,
  americanFootball,
  basketball,
  hockey,
  baseball,
  tennis,
  esports,
  cricket,
  other,
}

extension GameSportX on GameSport {
  /// Analytics value.
  String get key => switch (this) {
        GameSport.soccer => 'soccer',
        GameSport.americanFootball => 'american_football',
        GameSport.basketball => 'basketball',
        GameSport.hockey => 'hockey',
        GameSport.baseball => 'baseball',
        GameSport.tennis => 'tennis',
        GameSport.esports => 'esports',
        GameSport.cricket => 'cricket',
        GameSport.other => 'other',
      };

  /// Sports where every score is worth a marker on the chart. The others
  /// score too often (basketball, cricket runs) or are marked by set or
  /// map instead (tennis, esports).
  bool get marksEveryScore =>
      this == GameSport.soccer ||
      this == GameSport.americanFootball ||
      this == GameSport.hockey ||
      this == GameSport.baseball;
}

const _kFootballLeagues = {'nfl', 'cfb', 'ncaaf', 'ufl', 'cfl'};
const _kBasketballLeagues = {
  'nba', 'wnba', 'ncaab', 'cbb', 'cwbb', 'euroleague', 'nbl', 'gleague',
};
const _kHockeyLeagues = {'nhl', 'khl', 'ahl', 'shl'};
const _kBaseballLeagues = {'mlb', 'kbo', 'npb'};
const _kTennisLeagues = {'atp', 'wta', 'challenger', 'itf'};

/// The sport of a game, from the feed's league code when it is one we know
/// and otherwise from the shape of its score and period.
GameSport gameSportOf({
  String? league,
  String? score,
  String? period,
  bool cricket = false,
}) {
  final s = score?.trim() ?? '';
  if (s.contains('|')) return GameSport.esports;
  if (cricket) return GameSport.cricket;
  final l = league?.trim().toLowerCase() ?? '';
  if (_kFootballLeagues.contains(l)) return GameSport.americanFootball;
  if (_kBasketballLeagues.contains(l)) return GameSport.basketball;
  if (_kHockeyLeagues.contains(l)) return GameSport.hockey;
  if (_kBaseballLeagues.contains(l)) return GameSport.baseball;
  if (_kTennisLeagues.contains(l)) return GameSport.tennis;
  final p = period?.trim().toUpperCase() ?? '';
  if (s.contains(',') || RegExp(r'^S\d$').hasMatch(p)) return GameSport.tennis;
  if (const {'1H', '2H', 'HT', 'ET', 'ET1', 'ET2', 'PEN', 'FT', 'AET'}
      .contains(p)) {
    return GameSport.soccer;
  }
  if (RegExp(r'^P\d$').hasMatch(p)) return GameSport.hockey;
  return GameSport.other;
}

/// One score as the feed wrote it, split into what the sport means by it.
class GameScore {
  final String raw;

  /// The headline pair: goals, points, sets won (tennis) or maps won
  /// (esports). Null when the text is not a pair of numbers (cricket).
  final int? home;
  final int? away;

  /// Tennis: games per set, in order; the last set may be in play.
  final List<(int, int)> sets;

  /// Esports: the score inside the current map (rounds or kills).
  final int? mapHome;
  final int? mapAway;

  /// Esports: best of how many maps ("Bo5" -> 5).
  final int? bestOf;

  const GameScore({
    required this.raw,
    this.home,
    this.away,
    this.sets = const [],
    this.mapHome,
    this.mapAway,
    this.bestOf,
  });

  bool get hasPair => home != null && away != null;

  /// "2–1": the headline pair with an en dash, or the raw text.
  String get text => hasPair ? '$home–$away' : raw;

  /// Parses [raw] as [sport] writes it. Never throws; text it cannot read
  /// comes back with no pair.
  static GameScore parse(String? raw, GameSport sport) {
    final s = raw?.trim() ?? '';
    if (s.isEmpty) return const GameScore(raw: '');
    if (s.contains('|')) return _esports(s);
    if (sport == GameSport.tennis || s.contains(',')) return _tennis(s);
    final pair = _pair(s);
    return GameScore(raw: s, home: pair?.$1, away: pair?.$2);
  }

  static (int, int)? _pair(String s) {
    final m = RegExp(r'^\s*(\d{1,4})\s*[-–:]\s*(\d{1,4})\s*$').firstMatch(s);
    if (m == null) return null;
    return (int.parse(m.group(1)!), int.parse(m.group(2)!));
  }

  /// "13-9|2-2|Bo5": map score, series score, best of.
  static GameScore _esports(String s) {
    final parts = s.split('|').map((p) => p.trim()).toList();
    final map = _pair(parts[0]);
    final series = parts.length > 1 ? _pair(parts[1]) : null;
    int? bestOf;
    if (parts.length > 2) {
      bestOf = int.tryParse(parts[2].replaceAll(RegExp(r'[^0-9]'), ''));
    }
    return GameScore(
      raw: s,
      home: series?.$1,
      away: series?.$2,
      mapHome: map?.$1,
      mapAway: map?.$2,
      bestOf: bestOf,
    );
  }

  /// "6-3, 3-6, 2-1": every set but the last is finished; the last one
  /// counts as won only when its games say so (6 with a two-game lead, or
  /// 7). The headline pair is sets won.
  static GameScore _tennis(String s) {
    final sets = <(int, int)>[];
    for (final part in s.split(',')) {
      // A tie-break shows as "7-6(5)": the bracket is dropped.
      final p = _pair(part.replaceAll(RegExp(r'\([^)]*\)'), ''));
      if (p == null) return GameScore(raw: s);
      sets.add(p);
    }
    var home = 0, away = 0;
    for (var i = 0; i < sets.length; i++) {
      final (a, b) = sets[i];
      final finished = i < sets.length - 1 || _setWon(a, b);
      if (!finished) continue;
      if (a > b) home++;
      if (b > a) away++;
    }
    return GameScore(raw: s, home: home, away: away, sets: sets);
  }

  static bool _setWon(int a, int b) {
    final hi = a > b ? a : b, lo = a > b ? b : a;
    return (hi >= 6 && hi - lo >= 2) || hi == 7;
  }
}

/// The map being played, from an esports period like "4/5" (map 4 of 5).
int? esportsMapNumber(String? period) {
  final m = RegExp(r'^\s*(\d{1,2})\s*/\s*\d{1,2}\s*$').firstMatch(period ?? '');
  return m == null ? null : int.parse(m.group(1)!);
}

/// The set being played, from a tennis period like "S2".
int? tennisSetNumber(String? period) {
  final m = RegExp(r'^\s*S(\d)\s*$', caseSensitive: false)
      .firstMatch(period ?? '');
  return m == null ? null : int.parse(m.group(1)!);
}

/// The inning being played, from a baseball period like "Top 2nd",
/// "Mid 4th" or "B9".
int? baseballInning(String? period) {
  final m = RegExp(r'(\d{1,2})').firstMatch(period ?? '');
  return m == null ? null : int.parse(m.group(1)!);
}
