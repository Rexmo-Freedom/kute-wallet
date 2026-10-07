// lib/services/polymarket/live_game/local_game_events.dart
//
// The game changes this phone has seen on the live sports feed, kept for
// the session: the local half of a game's timeline (the backend serves the
// other half) and the source of the match moments. Fed by
// SportsLiveNotifier with every feed update.

import 'dart:async';

import 'package:kute/services/polymarket/live_game/game_timeline.dart';
import 'package:kute/services/sports_websocket_service.dart';

/// One change seen locally, with the update that carried it.
class LocalGameChange {
  final String gameId;
  final GameEvent event;
  final SportsMatchUpdate update;
  const LocalGameChange(this.gameId, this.event, this.update);
}

/// The id a game's timeline is kept and asked for under: the feed's
/// numeric gameId, or cricket's metadata id.
String? gameTimelineId({int? gameId, String? metadataGameId}) {
  if (gameId != null) return '$gameId';
  final meta = metadataGameId?.trim();
  return meta == null || meta.isEmpty ? null : meta;
}

class PolyLocalGameEvents {
  PolyLocalGameEvents({this.maxGames = 200, this.maxEventsPerGame = 200});

  static final PolyLocalGameEvents instance = PolyLocalGameEvents();

  final int maxGames;
  final int maxEventsPerGame;

  late final GameChangeDetector _detector =
      GameChangeDetector(maxGames: maxGames);
  final Map<String, List<GameEvent>> _events = {};
  final Map<String, int> _firstSeenMs = {};
  final StreamController<LocalGameChange> _changes =
      StreamController<LocalGameChange>.broadcast();

  /// Every change as it is seen, for every game on the feed.
  Stream<LocalGameChange> get changes => _changes.stream;

  /// The changes seen for [gameId], oldest first. The list is replaced,
  /// never mutated, so its identity can be memoized on.
  List<GameEvent> eventsFor(String gameId) => _events[gameId] ?? const [];

  /// When this phone first saw [gameId] on the feed (epoch ms): from then
  /// on [eventsFor] is complete, feed breaks aside.
  int? firstSeenMs(String gameId) => _firstSeenMs[gameId];

  void observe(SportsMatchUpdate update, {required int epoch, int? nowMs}) {
    final id = gameTimelineId(
        gameId: update.gameId, metadataGameId: update.metadataGameId);
    if (id == null) return;
    final now = nowMs ?? update.updatedAt.millisecondsSinceEpoch;
    if (!_firstSeenMs.containsKey(id)) {
      if (_firstSeenMs.length >= maxGames) {
        final oldest = _firstSeenMs.keys.first;
        _firstSeenMs.remove(oldest);
        _events.remove(oldest);
      }
      _firstSeenMs[id] = now;
    }
    final event = _detector.observe(
      id: id,
      score: update.score,
      period: update.period,
      elapsed: update.elapsed,
      status: update.status,
      ended: update.ended,
      nowMs: now,
      epoch: epoch,
    );
    if (event == null) return;
    final have = _events[id] ?? const <GameEvent>[];
    if (have.isNotEmpty && gameEventReverts(have.last, event)) {
      _events[id] = List.unmodifiable(have.sublist(0, have.length - 1));
      return;
    }
    final next = [...have, event];
    if (next.length > maxEventsPerGame) {
      next.removeRange(0, next.length - maxEventsPerGame);
    }
    _events[id] = List.unmodifiable(next);
    _changes.add(LocalGameChange(id, event, update));
  }
}
