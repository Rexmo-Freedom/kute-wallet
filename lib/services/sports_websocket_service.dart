// lib/services/sports_websocket_service.dart
//
// Custom WebSocket client for Polymarket's Sports API.
// Broadcasts live scores, periods, and elapsed time for active games.
// URL: wss://sports-api.polymarket.com/ws

import 'dart:async';
import 'dart:convert';
import 'package:kute/services/polymarket/live_game/feed_score_order.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const _kSportsWsUrl = 'wss://sports-api.polymarket.com/ws';

/// Live data for a single sports match.
///
/// The Polymarket sports WS sends FLAT fields, not nested envelopes, and the
/// scoreline is a single string ("1-1", or tennis "6-3, 3-6, 2-6") — never
/// separate integer home/away scores. The previous parser expected
/// `gameStatus`/`scores` objects + int scores, so every score parsed to null
/// and the banner showed "Team 0 - 0 Team". `gameId` is the stable numeric
/// join key to a Gamma event; `slug` is the fallback.
///
/// Cricket sends no `gameId` and no teams: it sends `metadataGameId`, which
/// matches the Gamma event's `eventMetadata.gameId` (a string).
class SportsMatchUpdate {
  final String slug;
  final int? gameId;

  /// Cricket's join key (Gamma `eventMetadata.gameId`), e.g.
  /// "id2705074469517978". Null for the sports that send [gameId].
  final String? metadataGameId;

  /// Feed status, e.g. "running", "InProgress", "Final".
  final String? status;

  /// League short code from the feed ("nfl", "cs2", "val").
  final String? leagueAbbreviation;

  /// NFL possession: the abbreviation of the team with the ball.
  final String? turn;

  /// When the game finished, from `finished_timestamp`.
  final DateTime? finishedAt;
  final bool live;
  final bool ended;
  final String? homeTeam;
  final String? awayTeam;

  /// The scoreline, home first, e.g. "1-1". The feed writes the North
  /// American leagues away first; [SportsMatchUpdate.fromJson] turns those
  /// round (feed_score_order.dart). Kept as a string because tennis/sets
  /// send "6-3, 3-6, 2-6" — splitting into ints loses data.
  final String? score;
  final String? period;
  final String? elapsed;

  /// Scheduled kickoff time from the feed (`gameStartTime`), when present.
  /// Used to reject a pre-kickoff game that is sitting on a stale 0-0 seed:
  /// a game whose start time is still in the future is NOT live yet, even if
  /// the bare `live` flag fires early.
  final DateTime? gameStartTime;
  final DateTime updatedAt;

  const SportsMatchUpdate({
    required this.slug,
    this.gameId,
    this.metadataGameId,
    this.status,
    this.leagueAbbreviation,
    this.turn,
    this.finishedAt,
    required this.live,
    required this.ended,
    this.homeTeam,
    this.awayTeam,
    this.score,
    this.period,
    this.elapsed,
    this.gameStartTime,
    required this.updatedAt,
  });

  bool get hasScore => score != null && score!.trim().isNotEmpty;

  /// True when this game has actually kicked off and is still running: not
  /// ended, a live score or period is present, and (when a start time is
  /// known) the scheduled start has passed. This is the authoritative LIVE
  /// predicate for cards/sorting — never trust the bare `live` flag alone,
  /// which Polymarket fires pre-kickoff.
  bool get isInPlay {
    if (!live || ended) return false;
    final startKnown = gameStartTime != null;
    if (startKnown && gameStartTime!.isAfter(DateTime.now())) return false;
    final p = period?.trim().toUpperCase() ?? '';
    if (_kNotInPlayPeriods.contains(p)) return false;
    final hasPeriod = p.isNotEmpty;
    return hasScore || hasPeriod;
  }

  /// Periods for games that are not running (mirrors the Gamma-side set in
  /// polymarket_model.dart; kept here so this service stays free of the
  /// model).
  static const _kNotInPlayPeriods = {
    'NS', 'FT', 'VFT', 'AET', 'AP', 'CAN', 'CANC', 'PST', 'POST', 'ABD',
    'AWD', 'FINAL', 'F', 'END', 'ENDED',
  };

  /// Formatted score line, e.g. "GER 1-1 CUR" (team abbreviations around the
  /// raw scoreline). Falls back to just the score when teams are absent.
  /// Esports pack the score as "mapScore|seriesScore|bestOf" — we surface the
  /// SERIES segment (the one that matters for the match), e.g. "2|1|5" → "1",
  /// matching the detail sheet's `_liveScoreText`.
  String get scoreLine {
    final s = hasScore ? _seriesSegment(score!.trim()) : '–';
    final home = homeTeam ?? '';
    final away = awayTeam ?? '';
    return '$home $s $away'.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// For pipe-packed esports scores ("mapScore|seriesScore|bestOf") returns the
  /// series segment; for normal scores ("1-1") returns the value unchanged.
  static String _seriesSegment(String raw) {
    if (!raw.contains('|')) return raw;
    final parts = raw.split('|');
    if (parts.length >= 2 && parts[1].trim().isNotEmpty) return parts[1].trim();
    return parts.first.trim();
  }

  /// Formatted status line, e.g. "1H 36'".
  String get statusLine {
    final parts = <String>[];
    if (period != null && period!.isNotEmpty) parts.add(period!);
    if (elapsed != null && elapsed!.isNotEmpty) parts.add(elapsed!);
    return parts.join(' ');
  }

  factory SportsMatchUpdate.fromJson(Map<String, dynamic> json) {
    // Flat schema (confirmed against the live WS + Gamma): score is a single
    // string; gameId/live/ended/period/elapsed/homeTeam/awayTeam are top-level.
    return SportsMatchUpdate(
      slug: json['slug'] as String? ?? json['eventSlug'] as String? ?? '',
      gameId: _parseInt(json['gameId']),
      metadataGameId: _nonEmpty(json['metadataGameId']),
      status: _nonEmpty(json['status']),
      leagueAbbreviation: _nonEmpty(json['leagueAbbreviation']),
      turn: _nonEmpty(json['turn']),
      finishedAt: _parseTime(json['finished_timestamp']),
      live: json['live'] as bool? ?? false,
      ended: json['ended'] as bool? ?? false,
      homeTeam: json['homeTeam'] as String? ?? json['homeTeamName'] as String?,
      awayTeam: json['awayTeam'] as String? ?? json['awayTeamName'] as String?,
      // Home first, whatever order the league's feed writes it in
      // (feed_score_order.dart).
      score: feedScoreHomeFirst(json['score']?.toString(),
          league: _nonEmpty(json['leagueAbbreviation'])),
      period: json['period']?.toString(),
      elapsed: json['elapsed']?.toString(),
      gameStartTime:
          DateTime.tryParse(json['gameStartTime']?.toString() ?? ''),
      updatedAt: DateTime.now(),
    );
  }

  static String? _nonEmpty(dynamic v) {
    final s = v?.toString().trim();
    return s == null || s.isEmpty ? null : s;
  }

  /// ISO string or epoch (seconds or milliseconds).
  static DateTime? _parseTime(dynamic v) {
    if (v is num) {
      final n = v.toInt();
      return DateTime.fromMillisecondsSinceEpoch(
          n < 100000000000 ? n * 1000 : n,
          isUtc: true);
    }
    return DateTime.tryParse(v?.toString() ?? '');
  }

  static int? _parseInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
}

/// WebSocket service for live sports data from Polymarket.
class SportsWebSocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  Timer? _pongTimer;
  bool _disposed = false;

  final _controller = StreamController<SportsMatchUpdate>.broadcast();

  Stream<SportsMatchUpdate> get updates => _controller.stream;

  /// Counts the stretches the feed was listened to without a break: it
  /// goes up on every (re)connect and after a silence longer than
  /// [_kFeedGap] (the server pings every 5 s, so that is a frozen app or a
  /// dead link). A change first seen in a new epoch may have happened at
  /// any time during the break.
  int get epoch => _epoch;
  int _epoch = 0;
  DateTime? _lastMessageAt;
  static const _kFeedGap = Duration(seconds: 20);

  void connect() {
    if (_disposed) return;
    _disconnect();
    _epoch++;
    _lastMessageAt = null;

    try {
      _channel = WebSocketChannel.connect(Uri.parse(_kSportsWsUrl));
      // web_socket_channel 3.x rejects `.ready` on a failed connect;
      // with no listener that rejection escapes the zone as a recorded
      // FATAL (one per reconnect attempt when offline). The stream
      // onError below owns recovery; `.ready` just needs a listener.
      _channel!.ready.ignore();

      _subscription = _channel!.stream.listen(
        _onMessage,
        onDone: _onDisconnect,
        onError: (_) => _onDisconnect(),
      );
    } catch (e) {
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic data) {
    // Reset pong timer on any message (server pings every 5s)
    _resetPongTimer();
    final now = DateTime.now();
    final last = _lastMessageAt;
    if (last != null && now.difference(last) > _kFeedGap) _epoch++;
    _lastMessageAt = now;

    if (data is! String) return;

    // Respond to ping
    if (data == 'ping' || data == '"ping"') {
      _channel?.sink.add('pong');
      return;
    }

    try {
      final json = jsonDecode(data);
      if (json is Map<String, dynamic>) {
        // Single update
        _emitUpdate(json);
      } else if (json is List) {
        // Batch of updates
        for (final item in json) {
          if (item is Map<String, dynamic>) _emitUpdate(item);
        }
      }
    } catch (_) {
      // Ignore unparseable messages
    }
  }

  void _emitUpdate(Map<String, dynamic> json) {
    try {
      final update = SportsMatchUpdate.fromJson(json);
      if (update.slug.isNotEmpty ||
          update.gameId != null ||
          update.metadataGameId != null) {
        _controller.add(update);
      }
    } catch (_) {}
  }

  void _resetPongTimer() {
    _pongTimer?.cancel();
    // If no message in 15s, assume disconnected
    _pongTimer = Timer(const Duration(seconds: 15), () {
      _onDisconnect();
    });
  }

  void _onDisconnect() {
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), connect);
  }

  void _disconnect() {
    _subscription?.cancel();
    _pongTimer?.cancel();
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    _disposed = true;
    _disconnect();
    _controller.close();
  }
}
