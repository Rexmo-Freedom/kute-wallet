// A game's timeline: the changes the Kute backend recorded
// (`GET /api/v1/pm/games/:gameId/timeline`) merged with the ones this
// phone saw on the live feed, each change once.
//
// The backend is read when the game opens and every [_kPollLive] while it
// is in play. When the endpoint is missing (a backend that does not have
// it yet) or fails, the timeline is simply what this phone saw: nothing is
// ever made up from prices.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:kute/services/polymarket/live_game/game_timeline.dart';
import 'package:kute/services/polymarket/live_game/local_game_events.dart';

const _kPollLive = Duration(seconds: 20);
const _kPollAfterFailure = Duration(seconds: 90);
const _kFetchTimeout = Duration(seconds: 8);

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

  const PolyGameTimeline({
    this.events = const [],
    this.knownSinceMs,
    this.fromBackend = false,
    this.ended = false,
    this.endedAtMs,
    this.league,
  });

  static const empty = PolyGameTimeline();

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
        .timeout(_kFetchTimeout);
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
      _backend = snapshot;
      state = _merged();
    }
    // A finished game's list no longer changes.
    if (snapshot != null && snapshot.known && snapshot.ended) return;
    _timer?.cancel();
    _timer = Timer(snapshot == null ? _kPollAfterFailure : _kPollLive, () {
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
    );
  }
}

/// The timeline of the game with [gameTimelineId] as its id.
final polyGameTimelineProvider = NotifierProvider.autoDispose
    .family<PolyGameTimelineNotifier, PolyGameTimeline, String>(
  PolyGameTimelineNotifier.new,
);
