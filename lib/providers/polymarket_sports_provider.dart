import 'dart:async';
import 'package:kute/services/polymarket/live_game/local_game_events.dart';
import 'package:kute/services/sports_websocket_service.dart';
export 'package:kute/services/sports_websocket_service.dart'
    show SportsMatchUpdate;
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SportsLiveNotifier
    extends AutoDisposeNotifier<Map<String, SportsMatchUpdate>> {
  SportsWebSocketService? _service;
  StreamSubscription? _sub;

  @override
  Map<String, SportsMatchUpdate> build() {
    ref.onDispose(_cleanup);
    return {};
  }

  void _cleanup() {
    _sub?.cancel();
    _service?.dispose();
    _service = null;
  }

  void connect() {
    if (_service != null) return;
    _service = SportsWebSocketService();
    _service!.connect();

    _sub = _service!.updates.listen((update) {
      // Every change this phone sees is noted for the chart's event
      // markers and the match moments.
      PolyLocalGameEvents.instance
          .observe(update, epoch: _service?.epoch ?? 0);
      final current = Map<String, SportsMatchUpdate>.from(state);
      // Index under BOTH keys so callers can look up by event slug (cards)
      // or by the stable numeric gameId (detail header) — the WS slug isn't
      // guaranteed to match Gamma's event slug, so gameId is the robust join.
      if (update.slug.isNotEmpty) current[update.slug] = update;
      if (update.gameId != null) current['game:${update.gameId}'] = update;
      // Cricket: no gameId, only Gamma's `eventMetadata.gameId`.
      if (update.metadataGameId != null) {
        current['meta:${update.metadataGameId}'] = update;
      }
      state = current;
    });
  }

  void disconnect() {
    _cleanup();
    state = {};
  }
}

/// The live update for a Gamma event: by slug, then the numeric [gameId],
/// then the cricket [metadataGameId] (`eventMetadata.gameId`).
SportsMatchUpdate? sportsUpdateFor(
  Map<String, SportsMatchUpdate> map, {
  String? slug,
  int? gameId,
  String? metadataGameId,
}) {
  if (map.isEmpty) return null;
  if (slug != null && slug.isNotEmpty) {
    final bySlug = map[slug];
    if (bySlug != null) return bySlug;
  }
  if (gameId != null) {
    final byGame = map['game:$gameId'];
    if (byGame != null) return byGame;
  }
  if (metadataGameId != null && metadataGameId.isNotEmpty) {
    return map['meta:$metadataGameId'];
  }
  return null;
}

final sportsLiveProvider = NotifierProvider.autoDispose<SportsLiveNotifier,
    Map<String, SportsMatchUpdate>>(
  SportsLiveNotifier.new,
);
