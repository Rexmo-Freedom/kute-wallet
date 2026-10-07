// A game's timeline: the changes the Kute backend recorded
// (`GET /api/v1/pm/games/:gameId/timeline`) merged with the ones this
// phone saw on the live feed, each change once.
//
// The backend's answer also says what the game looks like now (teams,
// score, period, status, live): [PolyGameTimeline.feed]. Polymarket's
// sports feed sends nothing about a game until it changes, which can take
// from half a second to twenty, so screens read the game from this until
// the feed has spoken ([PolyGameTimeline.liveOr]). Its scheduled start
// (`start_time`) fixes the game's kickoff from the first answer, so the
// momentum read is not rekeyed when the feed's own start time arrives.
//
// The backend is read when the game opens and every [_kPollLive] while it
// is in play; a failed read is tried again soon ([gameTimelineRetryDelay]:
// 5 s, 15 s, then every minute). When the endpoint is missing (a backend
// that does not have it yet) or fails, the timeline is simply what this
// phone saw: nothing is ever made up from prices.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:kute/services/polymarket/live_game/game_timeline.dart';
import 'package:kute/services/polymarket/live_game/local_game_events.dart';
import 'package:kute/services/sports_websocket_service.dart';

const _kPollLive = Duration(seconds: 20);

/// How long one read of the backend may take before it counts as failed.
const kGameTimelineFetchTimeout = Duration(seconds: 4);

/// The wait before the next read after [failures] failed reads in a row
/// (1 for the first): 5 s, 15 s, then a minute each time. A game opens
/// with its markers missing until a read answers, so the first retries
/// come soon.
Duration gameTimelineRetryDelay(int failures) => switch (failures) {
      <= 1 => const Duration(seconds: 5),
      2 => const Duration(seconds: 15),
      _ => const Duration(seconds: 60),
    };

class PolyGameTimeline {
  /// Backend and local events merged, oldest first.
  final List<GameEvent> events;

  /// From when [events] is known to be complete (epoch ms): the earlier of
  /// the backend's first sighting and this phone's. Null when neither has
  /// seen the game.
  final int? knownSinceMs;

  /// The backend answered and knows this game.
  final bool fromBackend;
  final bool ended;

  /// When the game was seen to end (epoch ms).
  final int? endedAtMs;

  /// The feed's league code, when the backend knows it.
  final String? league;

  /// The game as the backend last saw it on the feed, in the live feed's
  /// own shape; null until the backend has answered about a game it knows.
  final SportsMatchUpdate? feed;

  const PolyGameTimeline({
    this.events = const [],
    this.knownSinceMs,
    this.fromBackend = false,
    this.ended = false,
    this.endedAtMs,
    this.league,
    this.feed,
  });

  static const empty = PolyGameTimeline();

  /// [live], this phone's own feed update for the game, when there is one;
  /// else the backend's view of it ([feed]).
  SportsMatchUpdate? liveOr(SportsMatchUpdate? live) => live ?? feed;

  /// Analytics value: where the events came from.
  String get source => fromBackend
      ? 'backend'
      : events.isNotEmpty
          ? 'local'
          : 'none';
}

/// Reads one game's timeline from the backend. Null when there is no
/// backend, the endpoint is missing, or the read fails. Replaceable in
/// tests.
typedef GameTimelineFetch = Future<GameTimelineSnapshot?> Function(String id);

GameTimelineFetch gameTimelineFetch = _fetchFromBackend;

Future<GameTimelineSnapshot?> _fetchFromBackend(String id) async {
  String backend;
  try {
    backend = (dotenv.env['BACKEND']?.trim() ?? '')
        .replaceFirst(RegExp(r'/+$'), '');
  } catch (_) {
    return null;
  }
  if (backend.isEmpty) return null;
  try {
    final resp = await http
        .get(Uri.parse(
            '$backend/api/v1/pm/games/${Uri.encodeComponent(id)}/timeline'))
        .timeout(kGameTimelineFetchTimeout);
    if (resp.statusCode != 200) return null;
    return GameTimelineSnapshot.fromJson(jsonDecode(resp.body));
  } catch (_) {
    return null;
  }
}

class PolyGameTimelineNotifier
    extends AutoDisposeFamilyNotifier<PolyGameTimeline, String> {
  GameTimelineSnapshot? _backend;
  Timer? _timer;
  bool _disposed = false;

  /// Failed reads in a row since the last answer.
  int _failures = 0;

  @override
  PolyGameTimeline build(String arg) {
    _disposed = false;
    final sub = PolyLocalGameEvents.instance.changes.listen((change) {
      if (change.gameId == arg) state = _merged();
    });
    ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
      sub.cancel();
    });
    if (arg.isNotEmpty) unawaited(_poll());
    return _merged();
  }

  Future<void> _poll() async {
    final snapshot = await gameTimelineFetch(arg);
    if (_disposed) return;
    if (snapshot != null) {
      _failures = 0;
      _backend = snapshot;
      state = _merged();
    } else {
      _failures++;
    }
    // A finished game's list no longer changes.
    if (snapshot != null && snapshot.known && snapshot.ended) return;
    _timer?.cancel();
    _timer = Timer(
        snapshot == null ? gameTimelineRetryDelay(_failures) : _kPollLive, () {
      unawaited(_poll());
    });
  }

  PolyGameTimeline _merged() {
    final backend = _backend;
    final local = PolyLocalGameEvents.instance.eventsFor(arg);
    final events = mergeGameEvents(backend?.events ?? const [], local);
    final localSince = PolyLocalGameEvents.instance.firstSeenMs(arg);
    final backendSince = backend?.observedSinceMs;
    final since = localSince == null
        ? backendSince
        : backendSince == null || localSince < backendSince
            ? localSince
            : backendSince;
    int? endedAt;
    for (final e in events) {
      if (e.ended) {
        endedAt = e.tMs;
        break;
      }
    }
    return PolyGameTimeline(
      events: events,
      knownSinceMs: since,
      fromBackend: backend != null && backend.known,
      ended: (backend?.ended ?? false) || endedAt != null,
      endedAtMs: endedAt,
      league: backend?.league,
      feed: backend == null ? null : gameFeedFromSnapshot(arg, backend),
    );
  }
}

/// The backend's view of game [id] ([snapshot]) as a live feed update,
/// for the screens to start from before the feed speaks. Null when the
/// backend does not know the game.
SportsMatchUpdate? gameFeedFromSnapshot(
    String id, GameTimelineSnapshot snapshot) {
  if (!snapshot.known) return null;
  String? text(String v) => v.isEmpty ? null : v;
  // The feed's numeric game id; cricket has only the metadata id.
  final gameId = int.tryParse(id);
  final updated = snapshot.updatedAtMs;
  final start = snapshot.startTimeMs;
  return SportsMatchUpdate(
    slug: '',
    gameId: gameId,
    metadataGameId: gameId == null ? id : null,
    status: text(snapshot.status),
    leagueAbbreviation: snapshot.league,
    live: snapshot.live,
    ended: snapshot.ended,
    homeTeam: text(snapshot.home),
    awayTeam: text(snapshot.away),
    score: text(snapshot.score),
    period: text(snapshot.period),
    elapsed: text(snapshot.elapsed),
    gameStartTime: start == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(start, isUtc: true),
    updatedAt: updated == null
        ? DateTime.now()
        : DateTime.fromMillisecondsSinceEpoch(updated),
  );
}

/// The timeline of the game with [gameTimelineId] as its id.
final polyGameTimelineProvider = NotifierProvider.autoDispose
    .family<PolyGameTimelineNotifier, PolyGameTimeline, String>(
  PolyGameTimelineNotifier.new,
);
