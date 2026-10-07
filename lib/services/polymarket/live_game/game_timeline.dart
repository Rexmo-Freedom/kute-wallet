// lib/services/polymarket/live_game/game_timeline.dart
//
// What happened in a game, as a list of observed changes. Polymarket's
// sports WebSocket only says what a game looks like now, so an event exists
// only because the feed showed a different score, period or status than the
// time before: seen by this phone ([GameChangeDetector]) or by the Kute
// backend, which watches every game and serves its list
// (`GET /api/v1/pm/games/:gameId/timeline`). The two lists are merged and
// deduped ([mergeGameEvents]); nothing is ever inferred from prices.
//
// [gameMarkersFrom] turns the changes into the markers the odds chart
// draws: a goal, a touchdown, a set or a map won, a period change, the
// final score. Pure Dart; unit tested in
// test/services/polymarket/live_game_timeline_test.dart.

import 'package:kute/services/polymarket/live_game/feed_score_order.dart';
import 'package:kute/services/polymarket/live_game/game_score.dart';

/// One observed change of a game. The `*Before` fields are what the feed
/// said the time before.
class GameEvent {
  /// When the change was seen (epoch ms).
  final int tMs;
  final String scoreBefore;
  final String score;
  final String periodBefore;
  final String period;

  /// The game clock at the change, as the feed wrote it ("47", "4:27").
  final String elapsed;
  final String status;
  final bool ended;

  /// First seen after the feed had been away: it happened at or before
  /// [tMs].
  final bool approx;

  /// Seen by this phone rather than read from the backend.
  final bool local;

  const GameEvent({
    required this.tMs,
    required this.scoreBefore,
    required this.score,
    required this.periodBefore,
    required this.period,
    this.elapsed = '',
    this.status = '',
    this.ended = false,
    this.approx = false,
    this.local = false,
  });

  /// This change with its two scores rewritten (the feed's order turned
  /// home first).
  GameEvent withScores({required String scoreBefore, required String score}) =>
      GameEvent(
        tMs: tMs,
        scoreBefore: scoreBefore,
        score: score,
        periodBefore: periodBefore,
        period: period,
        elapsed: elapsed,
        status: status,
        ended: ended,
        approx: approx,
        local: local,
      );

  bool get scoreChanged => score != scoreBefore;
  bool get periodChanged => period != periodBefore;

  /// One row of the backend's `events` list; null when it is malformed.
  static GameEvent? fromJson(Object? json) {
    if (json is! Map) return null;
    final t = json['t'];
    if (t is! num || t <= 0) return null;
    String s(String key) => (json[key] ?? '').toString().trim();
    return GameEvent(
      tMs: t.toInt(),
      scoreBefore: s('score_before'),
      score: s('score'),
      periodBefore: s('period_before'),
      period: s('period'),
      elapsed: s('elapsed'),
      status: s('status'),
      ended: json['ended'] == true,
      approx: json['approx'] == true,
    );
  }

  @override
  String toString() =>
      'GameEvent($tMs $scoreBefore>$score $periodBefore>$period'
      '${ended ? ' ended' : ''}${approx ? ' ~' : ''}${local ? ' local' : ''})';
}

/// The backend's answer for one game.
class GameTimelineSnapshot {
  final List<GameEvent> events;

  /// From when the backend's list is complete (epoch ms); null when it has
  /// not seen the game.
  final int? observedSinceMs;
  final bool known;
  final bool ended;
  final bool truncated;
  final String? league;
  final String score;
  final String period;

  const GameTimelineSnapshot({
    this.events = const [],
    this.observedSinceMs,
    this.known = false,
    this.ended = false,
    this.truncated = false,
    this.league,
    this.score = '',
    this.period = '',
  });

  /// Parses the endpoint's body; null when it is not the expected shape.
  static GameTimelineSnapshot? fromJson(Object? json) {
    if (json is! Map || json['events'] is! List) return null;
    final events = <GameEvent>[
      for (final row in json['events'] as List)
        if (GameEvent.fromJson(row) case final e?) e,
    ]..sort((a, b) => a.tMs.compareTo(b.tMs));
    final since = json['observed_since'];
    final league = json['league']?.toString().trim();
    // The backend keeps the feed's own strings; the app reads scores home
    // first (feed_score_order.dart), as the changes this phone sees
    // already are, so the two lists merge change for change.
    if (feedScoreIsAwayFirst(league)) {
      for (var i = 0; i < events.length; i++) {
        events[i] = events[i].withScores(
          scoreBefore:
              feedScoreHomeFirst(events[i].scoreBefore, league: league)!,
          score: feedScoreHomeFirst(events[i].score, league: league)!,
        );
      }
    }
    return GameTimelineSnapshot(
      events: events,
      observedSinceMs: since is num && since > 0 ? since.toInt() : null,
      known: json['known'] == true,
      ended: json['ended'] == true,
      truncated: json['truncated'] == true,
      league: league == null || league.isEmpty ? null : league,
      score: feedScoreHomeFirst((json['score'] ?? '').toString().trim(),
          league: league)!,
      period: (json['period'] ?? '').toString().trim(),
    );
  }
}

class _Seen {
  String score;
  String period;
  String status;
  bool ended;
  int epoch;
  _Seen(this.score, this.period, this.status, this.ended, this.epoch);
}

/// Notes the changes this phone sees on the live feed, with the same rules
/// as the backend: the first sighting of a game makes no event, a message
/// that leaves a field out keeps the last value, and only a different
/// score, period or status (or the game ending) is a change.
class GameChangeDetector {
  GameChangeDetector({this.maxGames = 300});

  final int maxGames;
  final Map<String, _Seen> _games = {};

  /// Feeds one update for game [id]. [epoch] is the feed's connection
  /// count: a change first seen on a new connection is marked approximate.
  GameEvent? observe({
    required String id,
    String? score,
    String? period,
    String? elapsed,
    String? status,
    required bool ended,
    required int nowMs,
    int epoch = 0,
  }) {
    if (id.isEmpty) return null;
    final s = score?.trim() ?? '';
    final p = period?.trim() ?? '';
    final st = status?.trim() ?? '';
    final seen = _games.remove(id);
    if (seen == null) {
      if (_games.length >= maxGames) _games.remove(_games.keys.first);
      _games[id] = _Seen(s, p, st, ended, epoch);
      return null;
    }
    _games[id] = seen; // most recently seen last
    final newScore = s.isEmpty ? seen.score : s;
    final newPeriod = p.isEmpty ? seen.period : p;
    final newStatus = st.isEmpty ? seen.status : st;
    // A field the game had no value for yet is learned, not changed.
    final scoreChanged = seen.score.isNotEmpty && newScore != seen.score;
    final periodChanged = seen.period.isNotEmpty && newPeriod != seen.period;
    final statusChanged = seen.status.isNotEmpty &&
        newStatus.toLowerCase() != seen.status.toLowerCase();
    final endedNow = ended && !seen.ended;
    GameEvent? event;
    if (scoreChanged || periodChanged || statusChanged || endedNow) {
      event = GameEvent(
        tMs: nowMs,
        scoreBefore: seen.score,
        score: newScore,
        periodBefore: seen.period,
        period: newPeriod,
        elapsed: elapsed?.trim() ?? '',
        status: newStatus,
        ended: ended,
        approx: epoch != seen.epoch,
        local: true,
      );
    }
    seen
      ..score = newScore
      ..period = newPeriod
      ..status = newStatus
      ..ended = ended
      ..epoch = epoch;
    return event;
  }
}

/// A change the feed takes back within this is not a change (cricket
/// alternates between two states every few seconds).
const int kGameEventFlapWindowMs = 30000;

/// Whether [next] puts the game back exactly where [last] changed it from,
/// within [kGameEventFlapWindowMs]: the pair cancels out.
bool gameEventReverts(GameEvent last, GameEvent next) =>
    !last.ended &&
    !next.ended &&
    next.tMs - last.tMs <= kGameEventFlapWindowMs &&
    next.score == last.scoreBefore &&
    next.period == last.periodBefore;

/// Two sightings of one change land within this of each other (the phone
/// and the backend read the same feed, a network hop apart).
const int kGameEventSameWindowMs = 120000;

bool _sameChange(GameEvent a, GameEvent b) =>
    a.score == b.score &&
    a.period == b.period &&
    a.scoreBefore == b.scoreBefore &&
    a.periodBefore == b.periodBefore &&
    a.ended == b.ended;

/// The backend's events and the ones seen locally as one list, oldest
/// first, each change once.
///
/// A local event is dropped when the backend has the same change within
/// [kGameEventSameWindowMs] (the exact sighting wins over an approximate
/// one, else the backend's), and a local APPROXIMATE event is dropped when
/// the backend reached the same score and period at any time: the backend
/// watched the stretch the phone missed. Everything else is kept, so a
/// change only one side saw still shows.
List<GameEvent> mergeGameEvents(List<GameEvent> backend, List<GameEvent> local) {
  final out = [...backend];
  for (final l in local) {
    var duplicate = false;
    for (var i = 0; i < out.length; i++) {
      final b = out[i];
      if (b.local) continue;
      if (_sameChange(b, l) &&
          (b.tMs - l.tMs).abs() <= kGameEventSameWindowMs) {
        if (b.approx && !l.approx) out[i] = l;
        duplicate = true;
        break;
      }
      if (l.approx && b.score == l.score && b.period == l.period) {
        duplicate = true;
        break;
      }
    }
    if (!duplicate) out.add(l);
  }
  out.sort((a, b) => a.tMs.compareTo(b.tMs));
  return out;
}

enum GameMarkerKind {
  goal,
  touchdown,
  fieldGoal,
  score,
  correction,
  period,
  setWon,
  mapWon,
  mapStart,
  finalScore,
}

extension GameMarkerKindX on GameMarkerKind {
  /// Analytics value.
  String get key => switch (this) {
        GameMarkerKind.goal => 'goal',
        GameMarkerKind.touchdown => 'touchdown',
        GameMarkerKind.fieldGoal => 'field_goal',
        GameMarkerKind.score => 'score',
        GameMarkerKind.correction => 'score_corrected',
        GameMarkerKind.period => 'period',
        GameMarkerKind.setWon => 'set_won',
        GameMarkerKind.mapWon => 'map_won',
        GameMarkerKind.mapStart => 'map_start',
        GameMarkerKind.finalScore => 'final',
      };

  /// A side scored (or won a set or a map), as opposed to the clock moving.
  bool get isScoring => switch (this) {
        GameMarkerKind.goal ||
        GameMarkerKind.touchdown ||
        GameMarkerKind.fieldGoal ||
        GameMarkerKind.score ||
        GameMarkerKind.setWon ||
        GameMarkerKind.mapWon =>
          true,
        _ => false,
      };
}

/// One marker on the odds chart.
class GameMarker {
  final int tMs;
  final GameMarkerKind kind;

  /// 1 the home side, -1 the away side, 0 neither or unknown.
  final int side;

  /// The score to show: "1–0", a set's games "6–3", a series "2–1".
  final String scoreText;

  /// The game clock: "38'", "Q4 4:27", or empty.
  final String clock;

  /// The set or map number for [GameMarkerKind.setWon], mapWon, mapStart.
  final int? number;

  /// The period after the change, as the feed wrote it ("2H", "Q3").
  final String period;
  final bool approx;

  const GameMarker({
    required this.tMs,
    required this.kind,
    this.side = 0,
    this.scoreText = '',
    this.clock = '',
    this.number,
    this.period = '',
    this.approx = false,
  });
}

/// "38'" for a soccer minute, "Q4 4:27" for a period clock.
String gameClockText(GameSport sport, String period, String elapsed) {
  final e = elapsed.trim();
  if (e.isEmpty) return '';
  if (RegExp(r'^\d{1,3}(\+\d{1,2})?$').hasMatch(e)) return "$e'";
  final p = period.trim();
  return p.isEmpty ? e : '$p $e';
}

/// The chart markers for [events] (oldest first) of a [sport] game. Each
/// event gives at most one marker; sports that score every few seconds
/// (basketball, cricket) are marked by period only.
List<GameMarker> gameMarkersFrom(List<GameEvent> events, GameSport sport) {
  final out = <GameMarker>[];
  var wasEnded = false;
  for (final e in events) {
    final marker = _markerFor(e, sport, endsNow: e.ended && !wasEnded);
    if (e.ended) wasEnded = true;
    if (marker != null) out.add(marker);
  }
  return out;
}

GameMarker? _markerFor(GameEvent e, GameSport sport, {required bool endsNow}) {
  final before = GameScore.parse(e.scoreBefore, sport);
  final after = GameScore.parse(e.score, sport);
  final clock = gameClockText(sport, e.period, e.elapsed);
  GameMarker make(GameMarkerKind kind,
          {int side = 0, String? scoreText, int? number, String? clockText}) =>
      GameMarker(
        tMs: e.tMs,
        kind: kind,
        side: side,
        scoreText: scoreText ?? after.text,
        clock: clockText ?? clock,
        number: number,
        period: e.period,
        approx: e.approx,
      );

  if (endsNow) return make(GameMarkerKind.finalScore, clockText: '');

  final pairs = before.hasPair && after.hasPair;
  final dHome = pairs ? after.home! - before.home! : 0;
  final dAway = pairs ? after.away! - before.away! : 0;
  final side = dHome > 0 && dAway <= 0
      ? 1
      : dAway > 0 && dHome <= 0
          ? -1
          : 0;

  switch (sport) {
    case GameSport.cricket:
      // Sampled live, cricket's score and period flip between two states
      // every few seconds; only the end of the game is marked.
      return null;
    case GameSport.esports:
      // The headline pair is maps won; the map score inside it moves every
      // round or kill and is not marked.
      if (pairs && dHome + dAway > 0 && dHome >= 0 && dAway >= 0) {
        return make(GameMarkerKind.mapWon,
            side: side, number: after.home! + after.away!, clockText: '');
      }
      if (e.periodChanged) {
        final map = esportsMapNumber(e.period);
        if (map != null) {
          return make(GameMarkerKind.mapStart,
              number: map, clockText: '', scoreText: '');
        }
      }
      return null;
    case GameSport.tennis:
      // The headline pair is sets won; games inside a set are not marked.
      if (pairs && dHome + dAway > 0 && dHome >= 0 && dAway >= 0) {
        final n = after.home! + after.away!;
        final set = n >= 1 && n <= after.sets.length ? after.sets[n - 1] : null;
        return make(GameMarkerKind.setWon,
            side: side,
            number: n,
            clockText: '',
            scoreText: set == null ? '' : '${set.$1}–${set.$2}');
      }
      if (e.periodChanged && e.periodBefore.isNotEmpty) {
        return make(GameMarkerKind.period, clockText: '', scoreText: '');
      }
      return null;
    default:
      break;
  }

  if (e.scoreChanged && pairs) {
    if (dHome < 0 || dAway < 0) return make(GameMarkerKind.correction);
    if (sport.marksEveryScore ||
        (sport == GameSport.other && after.home! + after.away! <= 15)) {
      final kind = switch (sport) {
        GameSport.soccer || GameSport.hockey => GameMarkerKind.goal,
        GameSport.americanFootball => _footballKind(dHome, dAway),
        _ => GameMarkerKind.score,
      };
      return make(kind, side: side);
    }
  }
  if (e.periodChanged && e.periodBefore.isNotEmpty) {
    return make(GameMarkerKind.period, clockText: '', scoreText: '');
  }
  return null;
}

/// American football: one side's points going up by 6, 7 or 8 is a
/// touchdown (alone, or with the kick or the two-point try already in),
/// by 3 a field goal. Anything else is just a score.
GameMarkerKind _footballKind(int dHome, int dAway) {
  if (dHome > 0 && dAway > 0) return GameMarkerKind.score;
  final d = dHome > 0 ? dHome : dAway;
  if (d >= 6 && d <= 8) return GameMarkerKind.touchdown;
  if (d == 3) return GameMarkerKind.fieldGoal;
  return GameMarkerKind.score;
}
