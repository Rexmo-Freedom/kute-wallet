// lib/services/polymarket/live_game/game_line_rows.dart
//
// A game's "More markets" read for the screen. Polymarket writes every
// sub-market of a match as its own question, with the league and the teams
// in front of it: "Dota 2: Yellow Submarine vs GamerLegion - Game 2
// Winner", "Total Kills Over/Under 24.5 in Game 4?", "Game 1: Duration
// Over/Under 32:30 min?", "Arsenal FC vs. Hull City AFC: 1st Half O/U 1.5".
// Each market is read here into:
//
//   * its PERIOD ([GamePeriod]): the whole match, or the game, map or set
//     it is about (esports, tennis), a half, a quarter, a hockey period or
//     the first innings, from the question (and Gamma's
//     `sportsMarketType`: "first_half_totals", "q3_spreads");
//   * its TYPE ([GameLineType]): the winner, a handicap, a total (and of
//     what: games, sets, kills, rounds, the duration; one team's or one
//     player's number) or any other question;
//   * a short LABEL with the league, the teams, the period and the
//     "Over/Under" noise taken out: "24.5", "32:30", "GL -1.5", "Both
//     Teams Beat Roshan". A winner's is empty: its period and its kind say
//     it whole;
//   * its two SIDES as the buttons name them: Yes / No, Over / Under, or
//     the teams by a short name ("GL" and "YS" for GamerLegion and Yellow
//     Submarine, "Arsenal" and "Hull City"), in the market's own order (its
//     first token first).
//
// Pure Dart; unit tested in test/services/polymarket/game_line_rows_test.dart.

import 'package:kute/helpers/formatters/polymarket_side_labels.dart'
    show polymarketSideLabels;
import 'package:kute/models/polymarket_model.dart'
    show PolymarketOutcome, PolymarketTeam;
import 'package:kute/services/polymarket/live_game/game_sides.dart'
    show gameShortSideNames, gameTeamBareName, titleTeams;

/// What part of a game a market is about, in the order the period chips
/// list them.
enum GamePeriodUnit {
  match,
  game,
  map,
  set,
  half,
  quarter,
  period,
  firstFive,
  inning,
}

/// One period of a game: [unit] and its number (Game 2, Q3, the 1st half;
/// 0 for the whole match).
class GamePeriod implements Comparable<GamePeriod> {
  final GamePeriodUnit unit;
  final int index;
  const GamePeriod(this.unit, [this.index = 0]);

  /// The whole match.
  static const whole = GamePeriod(GamePeriodUnit.match);

  bool get isWhole => unit == GamePeriodUnit.match;

  /// Analytics value and a stable id: "match", "game2", "map1", "set1",
  /// "half1", "q3", "period2", "first5", "inning1".
  String get key => switch (unit) {
        GamePeriodUnit.match => 'match',
        GamePeriodUnit.game => 'game$index',
        GamePeriodUnit.map => 'map$index',
        GamePeriodUnit.set => 'set$index',
        GamePeriodUnit.half => 'half$index',
        GamePeriodUnit.quarter => 'q$index',
        GamePeriodUnit.period => 'period$index',
        GamePeriodUnit.firstFive => 'first5',
        GamePeriodUnit.inning => 'inning$index',
      };

  @override
  int compareTo(GamePeriod other) => unit.index != other.unit.index
      ? unit.index.compareTo(other.unit.index)
      : index.compareTo(other.index);

  @override
  bool operator ==(Object other) =>
      other is GamePeriod && other.unit == unit && other.index == index;

  @override
  int get hashCode => Object.hash(unit, index);

  @override
  String toString() => key;
}

/// A game market's kind, in the order "More markets" lists them.
enum GameLineType {
  winner,
  handicap,
  total,
  totalGames,
  totalSets,
  kills,
  rounds,
  duration,
  teamTotals,
  players,
  other,
}

extension GameLineTypeX on GameLineType {
  /// Analytics value (the type pills' `subcategory`). The four kinds the
  /// list had before keep their old values.
  String get key => switch (this) {
        GameLineType.winner => 'winner',
        GameLineType.handicap => 'spreads',
        GameLineType.total => 'totals',
        GameLineType.totalGames => 'total_games',
        GameLineType.totalSets => 'total_sets',
        GameLineType.kills => 'kills',
        GameLineType.rounds => 'rounds',
        GameLineType.duration => 'duration',
        GameLineType.teamTotals => 'team_totals',
        GameLineType.players => 'players',
        GameLineType.other => 'props',
      };

  /// An over / under of some count: its sides are Over and Under.
  bool get isTotal => switch (this) {
        GameLineType.total ||
        GameLineType.totalGames ||
        GameLineType.totalSets ||
        GameLineType.kills ||
        GameLineType.rounds ||
        GameLineType.duration ||
        GameLineType.teamTotals =>
          true,
        _ => false,
      };
}

/// What a row's two buttons say: the words Yes / No or Over / Under
/// (written in the app's language), or names of their own ([GameLineRow.
/// sideA] / [GameLineRow.sideB]: teams, a team and its line, Odd / Even).
enum GameSideWords { yesNo, overUnder, named }

/// One market of a game as a "More markets" row.
class GameLineRow {
  final GamePeriod period;
  final GameLineType type;

  /// The short label, without the period: "24.5", "32:30", "GL -1.5",
  /// "Arsenal 1.5", "Stephen Curry: Points 25.5", "Both Teams Beat
  /// Roshan". Empty for a winner.
  final String label;

  final GameSideWords words;

  /// The buttons' own names when [words] is [GameSideWords.named], in the
  /// market's order: [sideA] buys its first token (Yes), [sideB] its
  /// second (No).
  final String sideA;
  final String sideB;

  /// For the order within a kind: the team or player a number is about
  /// ('' for none) and the line.
  final String subject;
  final double? line;

  const GameLineRow({
    required this.period,
    required this.type,
    required this.label,
    required this.words,
    this.sideA = '',
    this.sideB = '',
    this.subject = '',
    this.line,
  });
}

// ── Periods ────────────────────────────────────────────────────────────

const Map<String, int> _kOrdinals = {
  'first': 1,
  '1st': 1,
  'second': 2,
  '2nd': 2,
  'third': 3,
  '3rd': 3,
  'fourth': 4,
  '4th': 4,
};

final RegExp _kNumbered =
    RegExp(r'\b(game|map|set)\s*(\d{1,2})\b', caseSensitive: false);
final RegExp _kQuarter = RegExp(
    r'\b(?:([1-4])q|q([1-4])|(first|second|third|fourth|1st|2nd|3rd|4th)[- ]quarter)\b',
    caseSensitive: false);
final RegExp _kHalf = RegExp(
    r'\b(?:([12])h|(first|second|1st|2nd)[- ]half|(half[- ]?time))\b',
    caseSensitive: false);
final RegExp _kHockeyPeriod = RegExp(
    r'\b(first|second|third|1st|2nd|3rd)[- ]period\b',
    caseSensitive: false);
final RegExp _kFirstFive = RegExp(
    r'\b(?:first|1st)\s*(?:5|five)\s*innings?\b|\bf5\b',
    caseSensitive: false);
final RegExp _kFirstInning =
    RegExp(r'\b(?:first|1st)[- ]inning\b', caseSensitive: false);

/// The period [text] names and where it names it; null for none.
({GamePeriod period, int start, int end})? _periodIn(String text) {
  final n = _kNumbered.firstMatch(text);
  if (n != null) {
    final unit = switch (n.group(1)!.toLowerCase()) {
      'map' => GamePeriodUnit.map,
      'set' => GamePeriodUnit.set,
      _ => GamePeriodUnit.game,
    };
    final i = int.parse(n.group(2)!);
    if (i > 0) return (period: GamePeriod(unit, i), start: n.start, end: n.end);
  }
  final q = _kQuarter.firstMatch(text);
  if (q != null) {
    final i = int.tryParse(q.group(1) ?? q.group(2) ?? '') ??
        _kOrdinals[q.group(3)?.toLowerCase()] ??
        0;
    if (i > 0) {
      return (
        period: GamePeriod(GamePeriodUnit.quarter, i),
        start: q.start,
        end: q.end
      );
    }
  }
  final h = _kHalf.firstMatch(text);
  if (h != null) {
    final i = h.group(3) != null
        ? 1
        : int.tryParse(h.group(1) ?? '') ??
            _kOrdinals[h.group(2)?.toLowerCase()] ??
            0;
    if (i > 0) {
      return (
        period: GamePeriod(GamePeriodUnit.half, i),
        start: h.start,
        end: h.end
      );
    }
  }
  final p = _kHockeyPeriod.firstMatch(text);
  if (p != null) {
    final i = _kOrdinals[p.group(1)!.toLowerCase()] ?? 0;
    if (i > 0) {
      return (
        period: GamePeriod(GamePeriodUnit.period, i),
        start: p.start,
        end: p.end
      );
    }
  }
  final f = _kFirstFive.firstMatch(text);
  if (f != null) {
    return (
      period: const GamePeriod(GamePeriodUnit.firstFive, 5),
      start: f.start,
      end: f.end
    );
  }
  final i1 = _kFirstInning.firstMatch(text);
  if (i1 != null) {
    return (
      period: const GamePeriod(GamePeriodUnit.inning, 1),
      start: i1.start,
      end: i1.end
    );
  }
  return null;
}

/// The period Gamma's `sportsMarketType` names ("first_half_totals",
/// "q3_spreads", "round_handicap_game_2", "tennis_first_set_winner").
GamePeriod? _periodOfKind(String kind) {
  final k = kind.toLowerCase();
  if (k.isEmpty) return null;
  if (k.contains('first_half')) return const GamePeriod(GamePeriodUnit.half, 1);
  if (k.contains('second_half')) {
    return const GamePeriod(GamePeriodUnit.half, 2);
  }
  final q = RegExp(r'(?:^|_)q([1-4])(?:_|$)').firstMatch(k);
  if (q != null) return GamePeriod(GamePeriodUnit.quarter, int.parse(q[1]!));
  final g = RegExp(r'_game_(\d+)$').firstMatch(k);
  if (g != null) return GamePeriod(GamePeriodUnit.game, int.parse(g[1]!));
  if (k.contains('first_set')) return const GamePeriod(GamePeriodUnit.set, 1);
  return null;
}

/// The period a market's question [text] is about (Gamma's [kind] when
/// the question does not say); the whole match when neither does.
GamePeriod gamePeriodOf(String text, {String kind = ''}) =>
    _periodIn(text)?.period ?? _periodOfKind(kind) ?? GamePeriod.whole;

// ── Words ──────────────────────────────────────────────────────────────

final RegExp _kSegmentSplit = RegExp(r'\s*:\s+|\s+[-–]\s+');
final RegExp _kVersus = RegExp(r'\svs\.?\s', caseSensitive: false);
final RegExp _kSignedLine = RegExp(r'\(\s*[+-]\s*\d');
final RegExp _kOverUnder = RegExp(
    r'\bo\s*/\s*u\b|\bover\s*/\s*under\b|\bover\b|\bunder\b',
    caseSensitive: false);
final RegExp _kOverUnderWords = RegExp(
    r'\bo\s*/\s*u\b|\bover\s*/\s*under\b',
    caseSensitive: false);
final RegExp _kNumber = RegExp(r'\d+(?:\.\d+)?');
final RegExp _kClock = RegExp(r'\b(\d{1,3}):(\d{2})\b');
final RegExp _kHandicapPair = RegExp(
    r'^(.+?)\s*\(\s*([+-]?\s*\d+(?:\.\d+)?)\s*\)\s+vs\.?\s+(.+?)\s*\(\s*([+-]?\s*\d+(?:\.\d+)?)\s*\)\s*$',
    caseSensitive: false);
final RegExp _kTeamOfLine =
    RegExp(r'^(.+?)\s*\(\s*([+-]?\s*\d+(?:\.\d+)?)\s*\)');

/// Words a total's kind already says, left out of its label.
final RegExp _kMeasureWords = RegExp(
    r'\b(?:totals?|kills?|rounds?|games?|maps?|sets?|duration|minutes?|mins?|team\s+totals?)\b',
    caseSensitive: false);

/// [text] without its edges' separators and with single spaces.
String _tidy(String text) => text
    .replaceAll('?', '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAllMapped(RegExp(r'\s+([:,])'), (m) => m[1]!)
    .replaceAll(RegExp(r'^[\s:,·\-–]+|[\s:,·\-–]+$'), '')
    .trim();

/// [text] without what [m] covers, and the " in " or " - " before it.
String _cut(String text, int start, int end) {
  final before = text.substring(0, start);
  final glue =
      RegExp(r'(?:\s+in(?:\s+the)?|\s*[-–])\s*$', caseSensitive: false)
          .firstMatch(before);
  final from = glue?.start ?? start;
  return '${text.substring(0, from)} ${text.substring(end)}';
}

/// A line as written: "2.5", "-1.5", "24".
String _number(double v) {
  final s = v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';
  return s;
}

String _signed(double v) => v > 0 ? '+${_number(v)}' : _number(v);

/// Minutes as a clock: 32.5 -> "32:30".
String _clock(double minutes) {
  final whole = minutes.floor();
  final secs = ((minutes - whole) * 60).round();
  return '$whole:${secs.toString().padLeft(2, '0')}';
}

List<String> _words(String s) => [
      for (final w in s.toLowerCase().split(RegExp(r'[^\p{L}\p{N}]+',
          unicode: true)))
        if (w.isNotEmpty) w,
    ];

// ── The reader ─────────────────────────────────────────────────────────

/// Reads the markets of one game ([GameLineReader.read]). Built once per
/// event: it learns the league in front of every question, the two
/// teams, and the short names Polymarket itself gives them in its
/// questions ("Game Handicap: GL (-1.5) vs Yellow Submarine (+1.5)",
/// "Fils vs. Fritz: Set 1 Games O/U 8.5").
class GameLineReader {
  /// The longest a team's name runs on a button before both sides take
  /// their short names.
  static const int maxSideName = 10;

  final String eventTitle;
  final List<PolymarketTeam> teams;

  /// Whether the game is an esports series: a long team name is written
  /// by its initials ("YS"), never by its last word ("Submarine").
  final bool esports;

  late final String _league;
  late final String _tail;
  late final (String, String)? _teams;
  final Map<String, String> _short = {};
  final Map<PolymarketOutcome, GameLineRow> _memo = Map.identity();

  GameLineReader({
    required this.eventTitle,
    this.teams = const [],
    bool esports = false,
    Iterable<PolymarketOutcome> outcomes = const [],
  }) : esports = esports ||
            outcomes.any((o) => const {'child_moneyline', 'map_handicap'}
                .contains(o.marketLine?.kind)) {
    final title = eventTitle.trim();
    final colon = title.indexOf(': ');
    _league = colon > 0 && !_kVersus.hasMatch(title.substring(0, colon))
        ? title.substring(0, colon).trim().toLowerCase()
        : '';
    final dash = title.lastIndexOf(' - ');
    final tail = dash > 0 ? title.substring(dash + 3).trim() : '';
    _tail = _kVersus.hasMatch(' $tail ') ? '' : tail.toLowerCase();
    _teams = titleTeams(title);
    for (final o in outcomes) {
      _learn(o);
    }
  }

  /// The question a row is read from: Gamma's question when the outcome
  /// carries its line (the outcome's own name may be a short title that
  /// lost its game: "Both Teams Slay Baron Nashor"), else its name.
  static String questionOf(PolymarketOutcome o) {
    final q = o.marketLine?.question.trim() ?? '';
    return q.isNotEmpty ? q : o.name.trim();
  }

  /// Short names Polymarket writes for the teams in its own questions.
  void _learn(PolymarketOutcome o) {
    final sides = o.marketLine?.sides ?? const <String>[];
    for (final seg in questionOf(o).split(_kSegmentSplit)) {
      final h = _kHandicapPair.firstMatch(seg.trim());
      final String a, b;
      if (h != null) {
        a = h.group(1)!.trim();
        b = h.group(3)!.trim();
      } else if (_kVersus.hasMatch(seg)) {
        final parts = seg.split(_kVersus);
        if (parts.length != 2) continue;
        a = parts[0].trim();
        b = parts[1].trim();
      } else {
        continue;
      }
      if (sides.length == 2 && h != null) {
        _remember(sides[0], a);
        _remember(sides[1], b);
      } else {
        for (final s in [a, b]) {
          final full = _teamFor(s);
          if (full != null) _remember(full, s);
        }
      }
    }
  }

  void _remember(String full, String short) {
    final f = full.trim(), s = short.trim();
    if (s.isEmpty || s.length >= f.length) return;
    if (s.toLowerCase() == f.toLowerCase()) return;
    final fw = _words(f), sw = _words(s);
    final plausible = (sw.isNotEmpty && fw.toSet().containsAll(sw)) ||
        (RegExp(r'^[\p{L}\p{N}.]{1,5}$', unicode: true).hasMatch(s) &&
            s[0].toLowerCase() == f[0].toLowerCase());
    if (!plausible) return;
    _short.putIfAbsent(f.toLowerCase(), () => s);
  }

  /// The team of the match [name] names: one of the title's two, by its
  /// whole name or all of its words; null for neither.
  String? _teamFor(String name) {
    final t = _teams;
    if (t == null) return null;
    final n = _words(gameTeamBareName(name));
    if (n.isEmpty) return null;
    String? hit;
    for (final team in [t.$1, t.$2]) {
      final w = _words(gameTeamBareName(team));
      if (w.join(' ') == n.join(' ') || w.toSet().containsAll(n)) {
        if (hit != null) return null;
        hit = team;
      }
    }
    return hit;
  }

  /// Which team (0 the title's first, 1 its second) [subject] is about:
  /// it holds that team's name, short name or alias; null for neither.
  int? _teamIn(String subject) {
    final t = _teams;
    if (t == null) return null;
    final s = ' ${_words(subject).join(' ')} ';
    int? hit;
    for (final (i, team) in [t.$1, t.$2].indexed) {
      final names = <String>{
        _words(gameTeamBareName(team)).join(' '),
        if (_short[team.toLowerCase()] case final short?)
          _words(short).join(' '),
        for (final pt in teams)
          if (_teamFor(pt.name) == team && (pt.alias ?? '').isNotEmpty)
            _words(pt.alias!).join(' '),
      }..removeWhere((n) => n.isEmpty);
      if (names.any((n) => s.contains(' $n '))) {
        if (hit != null) return null;
        hit = i;
      }
    }
    return hit;
  }

  /// [name]'s short name: the one Polymarket uses for it, else for an
  /// esports team its initials, else the short name a button writes for
  /// it ([gameShortSideNames]).
  String shortName(String name) {
    final full = _teamFor(name) ?? name.trim();
    final learned = _short[full.toLowerCase()];
    if (learned != null) return learned;
    final bare = gameTeamBareName(full);
    if (bare.length <= maxSideName) return bare;
    final words = bare
        .split(RegExp(r'\s+'))
        .where((w) => RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(w))
        .toList();
    if (esports) {
      if (words.length < 2) return bare;
      return words.map((w) => w.characters0.toUpperCase()).join();
    }
    final t = _teams;
    if (t != null) {
      final pair = gameShortSideNames(t.$1, t.$2, teams: teams);
      if (full == t.$1) return pair.$1;
      if (full == t.$2) return pair.$2;
    }
    return bare;
  }

  /// The two teams' names on a pair of buttons: whole while both are short,
  /// else both by their short names.
  (String, String) sidePair(String a, String b) {
    if (a.trim().length <= maxSideName && b.trim().length <= maxSideName) {
      return (a.trim(), b.trim());
    }
    return (shortName(a), shortName(b));
  }

  /// [question] without the league, the match ("A vs B") and the event's
  /// tail ("EPL Masters Playoffs") in it.
  String _bare(String question) {
    final segs = question.split(_kSegmentSplit);
    final kept = <String>[];
    for (final (i, raw) in segs.indexed) {
      final s = raw.trim();
      if (s.isEmpty) continue;
      final lower = s.toLowerCase();
      if (i == 0 && _league.isNotEmpty && lower == _league) continue;
      if (_tail.isNotEmpty && lower == _tail) continue;
      // "Yellow Submarine vs GamerLegion", "Fils vs. Fritz" go; a handicap
      // "GL (-1.5) vs Yellow Submarine (+1.5)" says something and stays.
      if (_kVersus.hasMatch(' $s ') && !_kSignedLine.hasMatch(s)) continue;
      kept.add(s);
    }
    return kept.join(': ');
  }

  /// The row for one market of the game.
  GameLineRow read(PolymarketOutcome o) => _memo[o] ??= _read(o);

  GameLineRow _read(PolymarketOutcome o) {
    final question = questionOf(o);
    final kind = (o.marketLine?.kind ?? '').toLowerCase();
    var text = _bare(question);
    // The period, cut out of the words.
    final found = _periodIn(text);
    final period = found?.period ??
        _periodIn(question)?.period ??
        _periodOfKind(kind) ??
        GamePeriod.whole;
    if (found != null) text = _cut(text, found.start, found.end);
    text = _tidy(text);
    // A tennis total of the whole match reads "Match O/U 21.5".
    text = text.replaceFirst(RegExp(r'^match\b\s*', caseSensitive: false), '');

    final rawSides = [
      for (final s in o.marketLine?.sides ?? const <String>[]) s.trim()
    ];
    if (rawSides.length != 2) {
      // Read without its line (a search result): the sides its name reads
      // as (polymarketSideLabels).
      final named = polymarketSideLabels(question);
      rawSides
        ..clear()
        ..addAll([named.pos, named.neg]);
    }
    final lowerSides = [for (final s in rawSides) s.toLowerCase()];
    final yesNo = lowerSides.length == 2 &&
        lowerSides.toSet().containsAll(const {'yes', 'no'});
    final overUnderSides = lowerSides.length == 2 &&
        lowerSides
            .every((s) => s.startsWith('over') || s.startsWith('under'));
    final lowerText = text.toLowerCase();
    final lowerQuestion = question.toLowerCase();
    final isOu = overUnderSides ||
        (_kOverUnder.hasMatch(lowerQuestion) &&
            _kNumber.hasMatch(lowerQuestion)) ||
        kind.contains('totals') ||
        kind.contains('over_under') ||
        kind.contains('duration');

    final type = _typeOf(
        kind: kind,
        text: lowerText,
        question: lowerQuestion,
        isOu: isOu,
        sidesAreTeams:
            rawSides.length == 2 && rawSides.every((s) => _teamFor(s) != null));

    final line = o.marketLine?.line ?? _lastNumber(text);

    // The sides.
    GameSideWords words;
    var sideA = '', sideB = '';
    if (yesNo && !(type.isTotal || type == GameLineType.players && isOu)) {
      words = GameSideWords.yesNo;
    } else if (overUnderSides || yesNo) {
      words = GameSideWords.overUnder;
    } else if (rawSides.length == 2) {
      words = GameSideWords.named;
      if (type == GameLineType.handicap && line != null) {
        sideA = '${shortName(rawSides[0])} ${_signed(line)}';
        sideB = '${shortName(rawSides[1])} ${_signed(-line)}';
      } else if (rawSides.every((s) => _teamFor(s) != null)) {
        (sideA, sideB) = sidePair(rawSides[0], rawSides[1]);
      } else {
        (sideA, sideB) = (rawSides[0], rawSides[1]);
      }
    } else {
      words = isOu ? GameSideWords.overUnder : GameSideWords.yesNo;
    }

    // The label and what it is about.
    var subject = '';
    String label;
    switch (type) {
      case GameLineType.winner:
        label = '';
      case GameLineType.handicap:
        final team = rawSides.isNotEmpty
            ? rawSides[0]
            : _kTeamOfLine.firstMatch(text.split(': ').last)?.group(1) ?? '';
        subject = team;
        label = team.isEmpty || line == null
            ? text
            : '${shortName(team)} ${_signed(line)}';
      case GameLineType.teamTotals:
        final ou = _kOverUnderWords.firstMatch(text);
        final head = ou == null ? text : text.substring(0, ou.start);
        final who = _teamIn(head);
        final pair = _teams;
        subject = who == null || pair == null
            ? _tidy(head)
            : (who == 0 ? pair.$1 : pair.$2);
        var rest = head;
        if (who != null && pair != null) {
          for (final n in [
            subject,
            gameTeamBareName(subject),
            _short[subject.toLowerCase()] ?? '',
            for (final pt in teams)
              if (_teamFor(pt.name) == subject) pt.alias ?? '',
          ]..sort((a, b) => b.length.compareTo(a.length))) {
            if (n.isEmpty) continue;
            rest = rest.replaceFirst(
                RegExp(RegExp.escape(n), caseSensitive: false), '');
          }
        }
        rest = _tidy(rest.replaceAll(
            RegExp(r'\bteam\s+totals?\b', caseSensitive: false), ''));
        label = _tidy([
          who == null ? _tidy(head) : shortName(subject),
          rest,
          if (line != null) _number(line),
        ].where((s) => s.trim().isNotEmpty).join(' '));
      case GameLineType.players:
        final ou = _kOverUnderWords.firstMatch(text);
        subject = _tidy(text.split(': ').first);
        label = isOu && ou != null
            ? _tidy('${text.substring(0, ou.start)} '
                '${line != null ? _number(line) : text.substring(ou.end)}')
            : text;
      case GameLineType.other:
        label = text;
      case GameLineType.total ||
            GameLineType.totalGames ||
            GameLineType.totalSets ||
            GameLineType.kills ||
            GameLineType.rounds ||
            GameLineType.duration:
        final clock = _kClock.firstMatch(text);
        final value = type == GameLineType.duration
            ? (clock != null
                ? '${clock[1]}:${clock[2]}'
                : (line != null ? _clock(line) : ''))
            : (line != null ? _number(line) : '');
        var rest = text
            .replaceAll(_kClock, ' ')
            .replaceAll(_kOverUnder, ' ')
            .replaceAll(_kNumber, ' ');
        if (type != GameLineType.total) {
          rest = rest.replaceAll(_kMeasureWords, ' ');
        } else {
          rest = rest.replaceAll(
              RegExp(r'^\s*total\s*$', caseSensitive: false), ' ');
        }
        rest = _tidy(rest);
        label = rest.isEmpty ? value : _tidy('$rest $value');
    }

    // Nothing left to say but the question: the question, tidied.
    if (label.isEmpty && type != GameLineType.winner) {
      label = _tidy(question);
    }
    return GameLineRow(
      period: period,
      type: type,
      label: label,
      words: words,
      sideA: sideA,
      sideB: sideB,
      subject: subject,
      line: line,
    );
  }

  GameLineType _typeOf({
    required String kind,
    required String text,
    required String question,
    required bool isOu,
    required bool sidesAreTeams,
  }) {
    if (kind == 'moneyline' ||
        kind.endsWith('_moneyline') ||
        kind.contains('set_winner')) {
      return GameLineType.winner;
    }
    if (kind.contains('spread') ||
        kind.contains('handicap') ||
        RegExp(r'\b(spread|handicap)\b').hasMatch(question) ||
        _kSignedLine.hasMatch(question)) {
      return GameLineType.handicap;
    }
    if (kind.contains('player') ||
        const {'points', 'rebounds', 'assists', 'threes', 'steals', 'blocks'}
            .contains(kind)) {
      return GameLineType.players;
    }
    if (isOu) {
      if (kind.contains('duration') || question.contains('duration')) {
        return GameLineType.duration;
      }
      if (RegExp(r'\bkills?\b').hasMatch(question)) return GameLineType.kills;
      if (RegExp(r'\brounds?\b').hasMatch(question)) {
        return GameLineType.rounds;
      }
      if (RegExp(r'\bsets\b').hasMatch(question)) return GameLineType.totalSets;
      if (RegExp(r'\b(games|maps)\b').hasMatch(question) ||
          const {
            'tennis_match_totals',
            'tennis_set_games_totals',
            'tennis_first_set_totals'
          }.contains(kind)) {
        return GameLineType.totalGames;
      }
      final ou = _kOverUnderWords.firstMatch(text);
      final head = _tidy(ou == null ? '' : text.substring(0, ou.start));
      if (kind.contains('team_total') ||
          (head.isNotEmpty && _teamIn(head) != null)) {
        return GameLineType.teamTotals;
      }
      if (head.isNotEmpty && text.contains(':')) return GameLineType.players;
      return GameLineType.total;
    }
    if (RegExp(r'\b(winner|moneyline)\b').hasMatch(text) ||
        (text.isEmpty && sidesAreTeams)) {
      return GameLineType.winner;
    }
    return GameLineType.other;
  }

  static double? _lastNumber(String text) {
    final all = _kNumber.allMatches(text).toList();
    return all.isEmpty ? null : double.tryParse(all.last.group(0)!);
  }
}

extension on String {
  /// The first character (a whole letter, never half a pair).
  String get characters0 => isEmpty ? '' : String.fromCharCode(runes.first);
}
