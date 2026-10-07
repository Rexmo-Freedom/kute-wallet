// lib/services/hyperliquid/hyperliquid_websocket.dart
//
// Direct connection to Hyperliquid's public WebSocket. Lifecycle is a
// deliberate mirror of polymarket_clob_websocket.dart (idempotent
// connect(), _intentionalClose/_disposed flags, capped-backoff reconnect,
// resubscribe-on-reconnect from the retained subscription set) — that
// client has survived production; don't diverge without a reason.
//
// Wire format differences from the Polymarket CLOB socket:
//
//   subscribe   → {"method":"subscribe","subscription":{...}}
//   unsubscribe → {"method":"unsubscribe","subscription":{...}}
//   ping        → {"method":"ping"} every 50 s (server disconnects idle
//                 sockets after 60 s); server replies {"channel":"pong"}
//   incoming    → {"channel":"allMids"|"l2Book"|"trades"|"candle"|
//                  "orderUpdates"|"userFills"|"subscriptionResponse"|
//                  "pong"|"error", "data":…}
//
// The user channels (orderUpdates/userFills) are address-keyed with NO
// auth — unlike Polymarket's HMAC-gated user channel.
//
// Coin strings on every subscription must be the WIRE coin
// (HlMarket.wireCoin): perp name, or '@<index>'/canonical pair name for
// spot. Passing a spot display symbol ('TSLA') silently yields no frames.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:kute/constants/hyperliquid_constants.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Debug-only tap into the HL WS. Flip [_kHlWsDebug] on and filter the
/// console on `[HL-WS]` while diagnosing subscription issues.
const bool _kHlWsDebug = false;
void _wsLog(String msg) {
  if (kDebugMode && _kHlWsDebug) debugPrint('[HL-WS] $msg');
}

// ───────────────────────────── messages ─────────────────────────────

/// Base type for every decoded frame surfaced to consumers.
abstract class HlWsMessage {
  const HlWsMessage();
}

/// `allMids` — mid price for every market, keyed by wire coin (perps by
/// name, spot pairs by `@<index>`). Wraps the RAW decoded `mids` object
/// (~400+ entries, ticking several times a second) with NO per-frame
/// copy; consumers look up only their watch-set via [mid], so unwatched
/// coins are never touched, let alone parsed.
class HlAllMidsMessage extends HlWsMessage {
  final Map<String, dynamic> _rawMids;
  const HlAllMidsMessage({required Map<String, dynamic> rawMids})
      : _rawMids = rawMids;

  /// Wire-string mid for [wireCoin] ('BTC', '@142'), or null when the
  /// frame doesn't carry it.
  String? mid(String wireCoin) {
    final v = _rawMids[wireCoin];
    if (v == null) return null;
    return v is String ? v : v.toString();
  }
}

/// `bbo` — the best bid and ask for one subscribed coin, pushed on
/// every change (many times a second on a busy market). Either side can
/// be null on an empty book.
class HlBboMessage extends HlWsMessage {
  final String coin;
  final int time;
  final double? bid;
  final double? ask;
  const HlBboMessage(
      {required this.coin, required this.time, this.bid, this.ask});

  /// Mid of the two sides, or whichever side exists.
  double? get mid {
    final b = bid, a = ask;
    if (b != null && a != null) return (b + a) / 2;
    return b ?? a;
  }

  static HlBboMessage? fromJson(Map<String, dynamic> data) {
    final coin = data['coin'];
    final sides = data['bbo'];
    if (coin is! String || sides is! List || sides.length < 2) return null;
    double? px(Object? side) => side is Map<String, dynamic>
        ? double.tryParse(side['px']?.toString() ?? '')
        : null;
    return HlBboMessage(
      coin: coin,
      time: (data['time'] as num?)?.toInt() ?? 0,
      bid: px(sides[0]),
      ask: px(sides[1]),
    );
  }
}

/// `l2Book` — full book snapshot for one subscribed coin.
class HlL2BookMessage extends HlWsMessage {
  final HlL2Book book;
  const HlL2BookMessage({required this.book});

  String get coin => book.coin;
  List<HlL2Level> get bids => book.bids;
  List<HlL2Level> get asks => book.asks;
  int get time => book.time;
}

/// One public trade from the `trades` channel.
class HlTrade {
  final String coin;
  final String side; // 'B' | 'A'
  final double px;
  final double sz;
  final int time;
  final String hash;

  const HlTrade({
    required this.coin,
    required this.side,
    required this.px,
    required this.sz,
    required this.time,
    required this.hash,
  });

  bool get isBuy => side == 'B';

  factory HlTrade.fromJson(Map<String, dynamic> json) => HlTrade(
        coin: (json['coin'] as String?) ?? '',
        side: (json['side'] as String?) ?? '',
        px: double.tryParse(json['px']?.toString() ?? '') ?? 0,
        sz: double.tryParse(json['sz']?.toString() ?? '') ?? 0,
        time: (json['time'] as num?)?.toInt() ?? 0,
        hash: (json['hash'] as String?) ?? '',
      );
}

class HlTradesMessage extends HlWsMessage {
  final List<HlTrade> trades;
  const HlTradesMessage({required this.trades});
}

/// `candle` — one in-progress/closed candle update for a subscribed
/// coin+interval. Times are epoch ms.
class HlCandleMessage extends HlWsMessage {
  final String coin; // wire coin ('s' field)
  final String interval; // 'i' field
  final int openTime;
  final int closeTime;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;

  const HlCandleMessage({
    required this.coin,
    required this.interval,
    required this.openTime,
    required this.closeTime,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });

  factory HlCandleMessage.fromJson(Map<String, dynamic> json) =>
      HlCandleMessage(
        coin: (json['s'] as String?) ?? '',
        interval: (json['i'] as String?) ?? '',
        openTime: (json['t'] as num?)?.toInt() ?? 0,
        closeTime: (json['T'] as num?)?.toInt() ?? 0,
        open: double.tryParse(json['o']?.toString() ?? '') ?? 0,
        high: double.tryParse(json['h']?.toString() ?? '') ?? 0,
        low: double.tryParse(json['l']?.toString() ?? '') ?? 0,
        close: double.tryParse(json['c']?.toString() ?? '') ?? 0,
        volume: double.tryParse(json['v']?.toString() ?? '') ?? 0,
      );
}

/// One market's live context, as `activeAssetCtx` (and the REST
/// `metaAndAssetCtxs` ctx) carries it: mark, mid, previous-day price,
/// 24h notional volume and, for perps, funding and open interest.
class HlAssetCtx {
  final double markPx;
  final double? midPx;
  final double prevDayPx;
  final double dayNtlVlm;
  final double? funding;
  final double? openInterest;

  const HlAssetCtx({
    required this.markPx,
    required this.midPx,
    required this.prevDayPx,
    required this.dayNtlVlm,
    required this.funding,
    required this.openInterest,
  });

  static double? _d(Object? v) =>
      v == null ? null : double.tryParse(v.toString());

  factory HlAssetCtx.fromJson(Map<String, dynamic> json) => HlAssetCtx(
        markPx: _d(json['markPx']) ?? 0,
        midPx: _d(json['midPx']),
        prevDayPx: _d(json['prevDayPx']) ?? 0,
        dayNtlVlm: _d(json['dayNtlVlm']) ?? 0,
        funding: _d(json['funding']),
        openInterest: _d(json['openInterest']),
      );
}

/// `activeAssetCtx` — the live context of one subscribed market.
class HlActiveAssetCtxMessage extends HlWsMessage {
  final String coin; // wire coin
  final HlAssetCtx ctx;
  const HlActiveAssetCtxMessage({required this.coin, required this.ctx});
}

/// One lifecycle event for one of the user's own orders.
class HlOrderUpdate {
  /// 'open' | 'filled' | 'canceled' | 'rejected' | 'triggered' |
  /// 'marginCanceled' | ... — pass through verbatim.
  final String status;
  final int statusTimestamp;
  final String coin;
  final int oid;
  final bool isBuy;
  final double limitPx;
  final double sz; // remaining size
  final double origSz;
  final int timestamp;
  final String? cloid;

  const HlOrderUpdate({
    required this.status,
    required this.statusTimestamp,
    required this.coin,
    required this.oid,
    required this.isBuy,
    required this.limitPx,
    required this.sz,
    required this.origSz,
    required this.timestamp,
    required this.cloid,
  });

  factory HlOrderUpdate.fromJson(Map<String, dynamic> json) {
    final order = (json['order'] is Map<String, dynamic>)
        ? json['order'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return HlOrderUpdate(
      status: (json['status'] as String?) ?? '',
      statusTimestamp: (json['statusTimestamp'] as num?)?.toInt() ?? 0,
      coin: (order['coin'] as String?) ?? '',
      oid: (order['oid'] as num?)?.toInt() ?? 0,
      isBuy: order['side'] == 'B',
      limitPx: double.tryParse(order['limitPx']?.toString() ?? '') ?? 0,
      sz: double.tryParse(order['sz']?.toString() ?? '') ?? 0,
      origSz: double.tryParse(order['origSz']?.toString() ?? '') ?? 0,
      timestamp: (order['timestamp'] as num?)?.toInt() ?? 0,
      cloid: order['cloid'] as String?,
    );
  }
}

class HlOrderUpdatesMessage extends HlWsMessage {
  final List<HlOrderUpdate> updates;
  const HlOrderUpdatesMessage({required this.updates});
}

/// `userFills` — [isSnapshot] is true on the initial backfill frame right
/// after subscribing; live fills arrive with isSnapshot false. Consumers
/// reacting to "a fill just happened" MUST ignore snapshot frames.
class HlUserFillsMessage extends HlWsMessage {
  final bool isSnapshot;
  final List<HlFill> fills;
  const HlUserFillsMessage({required this.isSnapshot, required this.fills});
}

enum HlWsState { disconnected, connecting, connected, reconnecting }

// ───────────────────────────── client ───────────────────────────────

/// Hyperliquid WS client. One instance manages one socket. `connect()` is
/// idempotent; `disconnect()` is best-effort safe to call before
/// `connect()`. Subscriptions registered before the socket opens are
/// buffered and issued once connected, and re-issued on every reconnect.
class HyperliquidWebSocket {
  final String url;
  final Duration heartbeatInterval;
  final Duration reconnectBaseDelay;
  final Duration maxReconnectDelay;
  final int maxReconnectAttempts;

  WebSocketChannel? _channel;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _disposed = false;
  bool _intentionalClose = false;
  StreamSubscription? _channelSub;

  /// Retained subscription payloads, keyed by a canonical string so
  /// duplicate subscribe calls are idempotent and reconnect can re-issue
  /// the full set.
  final Map<String, Map<String, dynamic>> _subscriptions = {};

  final _messages = StreamController<HlWsMessage>.broadcast();
  final _connectionState = StreamController<HlWsState>.broadcast();

  HyperliquidWebSocket({
    String? url,
    this.heartbeatInterval = const Duration(seconds: 50),
    this.reconnectBaseDelay = const Duration(seconds: 2),
    this.maxReconnectDelay = const Duration(seconds: 30),
    this.maxReconnectAttempts = 10,
  }) : url = url ?? HyperliquidConstants.wsUrl;

  /// Broadcast stream of decoded HL messages.
  ///
  /// NOTE: this stream can emit ERRORS as well as data — a mid-stream
  /// socket failure is forwarded here, and [_scheduleReconnect] adds a
  /// `StateError` when it gives up after [maxReconnectAttempts]. Every
  /// consumer MUST attach an `onError` handler: an unhandled error on a
  /// broadcast stream escapes to the `runZonedGuarded` handler in
  /// main.dart and is recorded as a FATAL crash ("max reconnect attempts
  /// exceeded"). Same contract as PolymarketClobWebSocket.messages.
  Stream<HlWsMessage> get messages => _messages.stream;
  Stream<HlWsState> get connectionState => _connectionState.stream;
  bool get isConnected => _channel != null && !_disposed;

  Future<void> connect() async {
    if (_disposed) {
      throw StateError('HyperliquidWebSocket disposed');
    }
    if (_channel != null) return;
    _intentionalClose = false;
    _connectionState.add(HlWsState.connecting);
    try {
      final ch = WebSocketChannel.connect(Uri.parse(url));
      await ch.ready;
      if (_disposed || _intentionalClose) {
        // dispose()/disconnect() landed during the handshake — close the
        // fresh channel instead of resurrecting a dead client. Matters
        // now that the live-prices notifier suspends (disposes) sockets
        // on pause, often mid-handshake.
        try {
          await ch.sink.close();
        } catch (_) {}
        return;
      }
      _channel = ch;
      _reconnectAttempts = 0;
      _connectionState.add(HlWsState.connected);
      _wsLog('connected → $url');
      _startHeartbeat();
      _channelSub = ch.stream.listen(
        _handleFrame,
        onError: (Object err, StackTrace st) {
          _messages.addError(err, st);
          _scheduleReconnect();
        },
        onDone: _handleDone,
      );
      // Re-issue every subscription registered before connect() resolved
      // (or held over from the previous connection on reconnect).
      for (final sub in _subscriptions.values) {
        _send({'method': 'subscribe', 'subscription': sub});
      }
    } catch (e) {
      _connectionState.add(HlWsState.disconnected);
      _scheduleReconnect();
      rethrow;
    }
  }

  Future<void> disconnect() async {
    _intentionalClose = true;
    await _cleanup();
    _connectionState.add(HlWsState.disconnected);
  }

  void dispose() {
    _disposed = true;
    _cleanup();
    _messages.close();
    _connectionState.close();
  }

  // ─────────────────────────── subscriptions ────────────────────────

  /// Mid prices for EVERY market in one stream. Heavy — see
  /// [HlAllMidsMessage]; consumers must filter to a watch-set.
  /// [dex] scopes the stream to a HIP-3 builder dex ('xyz', …); null is
  /// the default frame (main perp dex + spot '@N' keys). Builder-dex
  /// assets never appear in the default frame, so each dex on screen
  /// needs its own subscription.
  void subscribeAllMids({String? dex}) =>
      _subscribe({'type': 'allMids', if (dex != null) 'dex': dex});
  void unsubscribeAllMids({String? dex}) =>
      _unsubscribe({'type': 'allMids', if (dex != null) 'dex': dex});

  /// Best bid/ask for one coin: the fast price feed for the market on
  /// screen. `allMids` is only refreshed every few seconds server side.
  void subscribeBbo(String wireCoin) =>
      _subscribe({'type': 'bbo', 'coin': wireCoin});
  void unsubscribeBbo(String wireCoin) =>
      _unsubscribe({'type': 'bbo', 'coin': wireCoin});

  void subscribeL2Book(String wireCoin) =>
      _subscribe({'type': 'l2Book', 'coin': wireCoin});
  void unsubscribeL2Book(String wireCoin) =>
      _unsubscribe({'type': 'l2Book', 'coin': wireCoin});

  void subscribeTrades(String wireCoin) =>
      _subscribe({'type': 'trades', 'coin': wireCoin});
  void unsubscribeTrades(String wireCoin) =>
      _unsubscribe({'type': 'trades', 'coin': wireCoin});

  /// [interval] ∈ {'1m','5m','15m','1h','4h','1d',…} per HL docs.
  void subscribeCandle(String wireCoin, String interval) =>
      _subscribe({'type': 'candle', 'coin': wireCoin, 'interval': interval});
  void unsubscribeCandle(String wireCoin, String interval) =>
      _unsubscribe({'type': 'candle', 'coin': wireCoin, 'interval': interval});

  /// Subscribes the user's own order lifecycle + fills (orderUpdates +
  /// userFills channels). Address-only — no auth needed.
  /// Live context (mark, 24h, volume, funding, open interest) of one
  /// market; the builder-dex lists otherwise refresh these only every few
  /// minutes.
  void subscribeActiveAssetCtx(String wireCoin) =>
      _subscribe({'type': 'activeAssetCtx', 'coin': wireCoin});
  void unsubscribeActiveAssetCtx(String wireCoin) =>
      _unsubscribe({'type': 'activeAssetCtx', 'coin': wireCoin});

  void subscribeUser(String address) {
    _subscribe({'type': 'orderUpdates', 'user': address});
    _subscribe({'type': 'userFills', 'user': address});
  }

  void unsubscribeUser(String address) {
    _unsubscribe({'type': 'orderUpdates', 'user': address});
    _unsubscribe({'type': 'userFills', 'user': address});
  }

  void _subscribe(Map<String, dynamic> sub) {
    _subscriptions[_subKey(sub)] = sub;
    if (_channel != null) {
      _wsLog('→ subscribe $sub');
      _send({'method': 'subscribe', 'subscription': sub});
    }
  }

  void _unsubscribe(Map<String, dynamic> sub) {
    _subscriptions.remove(_subKey(sub));
    if (_channel == null) return;
    _wsLog('→ unsubscribe $sub');
    _send({'method': 'unsubscribe', 'subscription': sub});
  }

  // The dex is part of the identity: allMids for the main dex and allMids
  // for a builder dex are two subscriptions. Without it the second
  // overwrote the first and the main tape never arrived on that socket.
  static String _subKey(Map<String, dynamic> sub) =>
      '${sub['type']}|${sub['coin'] ?? ''}|${sub['user'] ?? ''}|${sub['interval'] ?? ''}|${sub['dex'] ?? ''}';

  // ────────────────────────────── wire ──────────────────────────────

  void _send(Map<String, dynamic> body) {
    final ch = _channel;
    if (ch == null) return;
    try {
      ch.sink.add(jsonEncode(body));
    } catch (_) {
      // Sink may be in the process of closing; the reconnect path
      // will resubscribe so dropping here is recoverable.
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      _send(const {'method': 'ping'});
    });
  }

  void _handleFrame(dynamic data) {
    if (data is! String) return;
    try {
      final decoded = jsonDecode(data);
      if (decoded is Map<String, dynamic>) _emit(decoded);
    } catch (_) {
      // Drop malformed frames.
    }
  }

  void _emit(Map<String, dynamic> json) {
    final channel = json['channel'] as String?;
    if (channel == null) return;
    _wsLog('← $channel');
    final data = json['data'];
    HlWsMessage? msg;
    switch (channel) {
      case 'pong':
      case 'subscriptionResponse':
        return;
      case 'error':
        _wsLog('server error: $data');
        return;
      case 'allMids':
        // Handed over as-is — re-keying/stringifying all ~400+ entries
        // per message burned CPU on coins nobody reads. jsonDecode
        // always yields Map<String, dynamic> for objects.
        final rawMids = (data is Map<String, dynamic>) ? data['mids'] : null;
        if (rawMids is! Map<String, dynamic>) return;
        msg = HlAllMidsMessage(rawMids: rawMids);
        break;
      case 'bbo':
        if (data is! Map<String, dynamic>) return;
        msg = HlBboMessage.fromJson(data);
        if (msg == null) return;
        break;
      case 'l2Book':
        if (data is! Map<String, dynamic>) return;
        msg = HlL2BookMessage(book: HlL2Book.fromJson(data));
        break;
      case 'trades':
        if (data is! List) return;
        msg = HlTradesMessage(
          trades: data
              .whereType<Map<String, dynamic>>()
              .map(HlTrade.fromJson)
              .toList(),
        );
        break;
      case 'candle':
        // Documented as a single candle object; be tolerant of a list.
        if (data is Map<String, dynamic>) {
          msg = HlCandleMessage.fromJson(data);
        } else if (data is List) {
          for (final c in data.whereType<Map<String, dynamic>>()) {
            _messages.add(HlCandleMessage.fromJson(c));
          }
          return;
        }
        break;
      case 'activeAssetCtx':
      case 'activeSpotAssetCtx':
        if (data is! Map<String, dynamic>) return;
        final ctx = data['ctx'];
        final coin = data['coin'];
        if (ctx is! Map<String, dynamic> || coin is! String) return;
        msg = HlActiveAssetCtxMessage(coin: coin, ctx: HlAssetCtx.fromJson(ctx));
        break;
      case 'orderUpdates':
        if (data is! List) return;
        msg = HlOrderUpdatesMessage(
          updates: data
              .whereType<Map<String, dynamic>>()
              .map(HlOrderUpdate.fromJson)
              .toList(),
        );
        break;
      case 'userFills':
        if (data is! Map<String, dynamic>) return;
        msg = HlUserFillsMessage(
          isSnapshot: data['isSnapshot'] == true,
          fills: ((data['fills'] as List?) ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(HlFill.fromJson)
              .toList(),
        );
        break;
    }
    if (msg != null) _messages.add(msg);
  }

  void _handleDone() {
    _connectionState.add(HlWsState.disconnected);
    if (_intentionalClose || _disposed) return;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || _intentionalClose) return;
    if (_reconnectAttempts >= maxReconnectAttempts) {
      _messages.addError(
          StateError('HyperliquidWebSocket: max reconnect attempts exceeded'));
      return;
    }
    _cleanup();
    _connectionState.add(HlWsState.reconnecting);
    final attempt = _reconnectAttempts + 1;
    final delayMs = (reconnectBaseDelay.inMilliseconds * attempt)
        .clamp(0, maxReconnectDelay.inMilliseconds);
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      _reconnectAttempts = attempt;
      connect().catchError((_) {});
    });
  }

  Future<void> _cleanup() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _channelSub?.cancel();
    _channelSub = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }
}
