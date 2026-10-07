// lib/services/polymarket_clob_websocket.dart
//
// Direct connection to Polymarket's CLOB WebSocket — no polybrainz.
// Same wire protocol the polybrainz package targets, just with our
// own framing and message types. Used by
// `polymarket_live_prices_provider.dart` to push live odds into the
// UI without dragging in the polybrainz dependency for the WS layer.
//
// The remote endpoint at `wss://ws-subscriptions-clob.polymarket.com
// /ws/market` is fully public — no auth on the market channel. The
// user channel (order / trade for your own positions) requires HMAC
// auth headers, which we don't currently consume from this file
// (those subscriptions live in `user_channel_provider.dart` and
// still flow through polybrainz at the time of writing).
//
// Wire format (decoded from raw frames):
//
//   subscribe   → JSON: { "type": "market", "assets_ids": [<id>, ...] }
//   unsubscribe → JSON: { "type": "unsubscribe", "assets_ids": [...] }
//   ping        → bare string "ping"
//
//   incoming    → JSON object OR JSON array of objects, each with
//                 `event_type` ∈ {"book","price_change","last_trade_price"}
//                 Strings "pong" come back from heartbeats.

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Debug-only tap into the market WS. Flip [_kPmWsDebug] off (or just ship
/// in release — `kDebugMode` already gates it) to silence. Tag the console
/// filter on `[PM-WS]` while diagnosing why live trades aren't streaming.
const bool _kPmWsDebug = false;
void _wsLog(String msg) {
  if (kDebugMode && _kPmWsDebug) debugPrint('[PM-WS] $msg');
}

/// Public market WS endpoint. Polymarket has historically kept this
/// stable; if the URL ever changes, override via the constructor.
const String kPolymarketClobMarketWsUrl =
    'wss://ws-subscriptions-clob.polymarket.com/ws/market';

/// A single price level in the order book (one bid OR one ask).
class PolymarketOrderSummary {
  final double price;
  final double size;

  const PolymarketOrderSummary({required this.price, required this.size});

  factory PolymarketOrderSummary.fromJson(Map<String, dynamic> json) {
    return PolymarketOrderSummary(
      price: double.tryParse(json['price']?.toString() ?? '') ?? 0.0,
      size: double.tryParse(json['size']?.toString() ?? '') ?? 0.0,
    );
  }
}

/// Common header shared by every WS message we surface upward.
abstract class PolymarketWsMessage {
  final String? assetId;
  final String? market;
  final int? timestamp;
  const PolymarketWsMessage({this.assetId, this.market, this.timestamp});
}

/// Order book snapshot — bids[0] / asks[0] are the best (tightest)
/// levels. Our consumer averages them to produce the midpoint we
/// display as the canonical "live price".
class PolymarketBookMessage extends PolymarketWsMessage {
  final List<PolymarketOrderSummary> bids;
  final List<PolymarketOrderSummary> asks;
  final String hash;

  const PolymarketBookMessage({
    required super.assetId,
    required super.market,
    required super.timestamp,
    required this.bids,
    required this.asks,
    required this.hash,
  });

  /// Polymarket's CLOB sends levels price-ascending in both arrays.
  /// Best (most-aggressive) bid = highest price = `bids.last`.
  /// Best (most-aggressive) ask = lowest price = `asks.first`.
  /// Reading `bids.first` would yield the WORST bid (often 0.001) and
  /// pair it with the best ask, producing a mid near 0.5 for every
  /// thin market — which is what stranded every candidate row at
  /// "50.00¢" until this was fixed.
  double? get bestBid {
    if (bids.isEmpty) return null;
    var best = -1.0;
    for (final l in bids) {
      if (l.price > best) best = l.price;
    }
    return best > 0 ? best : null;
  }

  double? get bestAsk {
    if (asks.isEmpty) return null;
    var best = double.infinity;
    for (final l in asks) {
      if (l.price > 0 && l.price < best) best = l.price;
    }
    return best.isFinite ? best : null;
  }

  factory PolymarketBookMessage.fromJson(Map<String, dynamic> json) {
    return PolymarketBookMessage(
      assetId: json['asset_id'] as String?,
      market: json['market'] as String?,
      timestamp: _asInt(json['timestamp']),
      bids: (json['bids'] as List? ?? const [])
          .map((b) => PolymarketOrderSummary.fromJson(b as Map<String, dynamic>))
          .toList(),
      asks: (json['asks'] as List? ?? const [])
          .map((a) => PolymarketOrderSummary.fromJson(a as Map<String, dynamic>))
          .toList(),
      hash: json['hash'] as String? ?? '',
    );
  }
}

/// A single level mutation reported by the CLOB. Many can pack into
/// one `price_change` event — see [PolymarketPriceChangeMessage].
class PolymarketPriceChange {
  final String assetId;
  final double price;
  final double size;
  final String side;
  const PolymarketPriceChange({
    required this.assetId,
    required this.price,
    this.size = 0.0,
    this.side = '',
  });

  bool get isBid => side.toUpperCase() == 'BUY';

  factory PolymarketPriceChange.fromJson(Map<String, dynamic> json) {
    return PolymarketPriceChange(
      assetId: json['asset_id']?.toString() ?? '',
      price: double.tryParse(json['price']?.toString() ?? '') ?? 0.0,
      size: double.tryParse(json['size']?.toString() ?? '') ?? 0.0,
      side: json['side']?.toString() ?? '',
    );
  }
}

/// `price_change` event — emitted on every level mutation. Used as a
/// freshness signal for thin markets where book/last_trade frames are
/// sparse (the 5-min Up/Down feed especially).
class PolymarketPriceChangeMessage extends PolymarketWsMessage {
  final List<PolymarketPriceChange> priceChanges;

  const PolymarketPriceChangeMessage({
    required super.assetId,
    required super.market,
    required super.timestamp,
    required this.priceChanges,
  });

  factory PolymarketPriceChangeMessage.fromJson(Map<String, dynamic> json) {
    // Polymarket has shipped this event under both `price_changes` and
    // `changes`; each entry may omit `asset_id` (inheriting the frame's),
    // so backfill it from the envelope.
    final raw = (json['price_changes'] ?? json['changes']) as List? ?? const [];
    final envAsset = json['asset_id'];
    return PolymarketPriceChangeMessage(
      assetId: json['asset_id'] as String?,
      market: json['market'] as String?,
      timestamp: _asInt(json['timestamp']),
      priceChanges: raw
          .whereType<Map<String, dynamic>>()
          .map((p) => PolymarketPriceChange.fromJson({
                ...p,
                'asset_id': p['asset_id'] ?? envAsset,
              }))
          .toList(),
    );
  }
}

/// User-channel `order` event — fires on the user's own order lifecycle
/// (PLACEMENT / UPDATE / CANCELLATION). Only delivered while the user
/// channel is subscribed with valid HMAC auth headers.
class PolymarketOrderWsMessage extends PolymarketWsMessage {
  final String orderId;
  final String action;
  final String side;
  final double price;
  final double originalSize;
  final double sizeMatched;
  final String outcome;
  final String? type;

  const PolymarketOrderWsMessage({
    required super.assetId,
    required super.market,
    required super.timestamp,
    required this.orderId,
    required this.action,
    required this.side,
    required this.price,
    required this.originalSize,
    required this.sizeMatched,
    required this.outcome,
    this.type,
  });

  double get remainingSize => originalSize - sizeMatched;
  bool get isFilled => remainingSize <= 0;

  factory PolymarketOrderWsMessage.fromJson(Map<String, dynamic> json) {
    return PolymarketOrderWsMessage(
      assetId: json['asset_id'] as String?,
      market: json['market'] as String?,
      timestamp: _asInt(json['timestamp']),
      orderId: json['id']?.toString() ?? '',
      action: json['action']?.toString() ?? 'UPDATE',
      side: json['side']?.toString() ?? '',
      price: double.tryParse(json['price']?.toString() ?? '') ?? 0.0,
      originalSize:
          double.tryParse(json['original_size']?.toString() ?? '') ?? 0.0,
      sizeMatched:
          double.tryParse(json['size_matched']?.toString() ?? '') ?? 0.0,
      outcome: json['outcome']?.toString() ?? '',
      type: json['type']?.toString(),
    );
  }
}

/// User-channel `trade` event — fires when one of the user's orders
/// matches. Status moves through MINED / CONFIRMED / FAILED on the way
/// to settlement.
class PolymarketTradeWsMessage extends PolymarketWsMessage {
  final String tradeId;
  final String status;
  final String side;
  final double size;
  final double price;
  final String? transactionHash;
  final String outcome;

  const PolymarketTradeWsMessage({
    required super.assetId,
    required super.market,
    required super.timestamp,
    required this.tradeId,
    required this.status,
    required this.side,
    required this.size,
    required this.price,
    this.transactionHash,
    required this.outcome,
  });

  factory PolymarketTradeWsMessage.fromJson(Map<String, dynamic> json) {
    return PolymarketTradeWsMessage(
      assetId: json['asset_id'] as String?,
      market: json['market'] as String?,
      timestamp: _asInt(json['timestamp']),
      tradeId: json['id']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      side: json['side']?.toString() ?? '',
      size: double.tryParse(json['size']?.toString() ?? '') ?? 0.0,
      price: double.tryParse(json['price']?.toString() ?? '') ?? 0.0,
      transactionHash: json['transaction_hash']?.toString(),
      outcome: json['outcome']?.toString() ?? '',
    );
  }
}

/// `last_trade_price` event — fires immediately after a match.
class PolymarketLastTradePriceMessage extends PolymarketWsMessage {
  final double price;
  final String side;
  final double size;

  const PolymarketLastTradePriceMessage({
    required super.assetId,
    required super.market,
    required super.timestamp,
    required this.price,
    required this.side,
    required this.size,
  });

  factory PolymarketLastTradePriceMessage.fromJson(Map<String, dynamic> json) {
    return PolymarketLastTradePriceMessage(
      assetId: json['asset_id'] as String?,
      market: json['market'] as String?,
      timestamp: _asInt(json['timestamp']),
      price: double.tryParse(json['price']?.toString() ?? '') ?? 0.0,
      side: json['side'] as String? ?? '',
      size: double.tryParse(json['size']?.toString() ?? '') ?? 0.0,
    );
  }
}

int? _asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

/// CLOB market-channel WS client. One instance manages one socket.
/// `connect()` is idempotent; `disconnect()` is best-effort safe to
/// call before `connect()` (no-ops if no socket open).
///
/// Reconnect strategy is intentionally minimal — exponential backoff
/// capped at `maxReconnectDelay`. The consumer
/// (`polymarket_live_prices_provider.dart`) has its own resubscribe
/// logic, so this client's only contract on reconnect is to re-issue
/// the subscriptions it had at disconnect time. When the backoff
/// budget runs out the client parks in `disconnected` WITHOUT
/// erroring the `messages` stream (see `_scheduleReconnect`); the
/// next explicit `connect()` starts over with a fresh budget. A
/// `connectionState` stream is exposed but the consumer currently
/// ignores it — listen to it for diagnostics if needed.
class PolymarketClobWebSocket {
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

  final Set<String> _subscribed = <String>{};
  final Set<String> _userAssets = <String>{};
  Map<String, String> Function()? _userAuthHeadersFactory;
  final _messages = StreamController<PolymarketWsMessage>.broadcast();
  final _connectionState =
      StreamController<PolymarketClobWsState>.broadcast();

  PolymarketClobWebSocket({
    this.url = kPolymarketClobMarketWsUrl,
    this.heartbeatInterval = const Duration(seconds: 30),
    this.reconnectBaseDelay = const Duration(seconds: 2),
    this.maxReconnectDelay = const Duration(seconds: 30),
    this.maxReconnectAttempts = 10,
  });

  /// Broadcast stream of decoded CLOB messages.
  ///
  /// NOTE: this stream can emit ERRORS as well as data — a mid-stream
  /// socket failure is forwarded here, and [_scheduleReconnect] adds a
  /// `StateError` when it gives up after [maxReconnectAttempts]. Every
  /// consumer MUST attach an `onError` handler: an unhandled error on a
  /// broadcast stream escapes to the `runZonedGuarded` handler in
  /// main.dart and is recorded as a FATAL crash ("max reconnect attempts
  /// exceeded").
  Stream<PolymarketWsMessage> get messages => _messages.stream;
  Stream<PolymarketClobWsState> get connectionState =>
      _connectionState.stream;
  bool get isConnected => _channel != null && !_disposed;

  Future<void> connect() async {
    if (_disposed) {
      throw StateError('PolymarketClobWebSocket disposed');
    }
    if (_channel != null) return;
    _intentionalClose = false;
    _connectionState.add(PolymarketClobWsState.connecting);
    try {
      final ch = WebSocketChannel.connect(Uri.parse(url));
      await ch.ready;
      if (_disposed || _intentionalClose) {
        // dispose()/disconnect() raced the handshake — close the fresh
        // socket and bail before touching the (possibly already closed)
        // state controllers below.
        try {
          await ch.sink.close();
        } catch (_) {}
        return;
      }
      _channel = ch;
      _reconnectAttempts = 0;
      _connectionState.add(PolymarketClobWsState.connected);
      _wsLog('connected → $url');
      _startHeartbeat();
      _channelSub = ch.stream.listen(
        _handleFrame,
        onError: (Object err, StackTrace st) {
          if (!_messages.isClosed) _messages.addError(err, st);
          _scheduleReconnect();
        },
        onDone: _handleDone,
      );
      // Re-issue any subscriptions the consumer set before connect()
      // resolved (e.g. addTokens-during-connect race that earlier bit
      // us — see `_connectAndSubscribe` in the live-prices provider).
      if (_subscribed.isNotEmpty) {
        _sendSubscribe(_subscribed.toList());
      }
      // Re-issue the user-channel subscription if one was registered.
      // Auth headers are re-computed at re-subscribe time because the
      // POLY_TIMESTAMP / POLY_SIGNATURE bundle is short-lived.
      final userFactory = _userAuthHeadersFactory;
      if (userFactory != null && _userAssets.isNotEmpty) {
        _send({
          'type': 'user',
          'assets_ids': _userAssets.toList(),
          'auth': userFactory(),
        });
      }
    } catch (e) {
      if (!_connectionState.isClosed) {
        _connectionState.add(PolymarketClobWsState.disconnected);
      }
      _scheduleReconnect();
      rethrow;
    }
  }

  Future<void> disconnect() async {
    _intentionalClose = true;
    await _cleanup();
    if (!_connectionState.isClosed) {
      _connectionState.add(PolymarketClobWsState.disconnected);
    }
  }

  /// Subscribe to the market channel for the given token ids. Safe to
  /// call before `connect()`; the ids are buffered and re-issued
  /// once the socket is open.
  void subscribeToMarket(List<String> assetIds) {
    _subscribed.addAll(assetIds);
    if (_channel != null) _sendSubscribe(assetIds);
  }

  /// Subscribe to the **user channel** for the given token ids. Auth
  /// headers must be the L2 HMAC bundle (`POLY_ADDRESS`,
  /// `POLY_SIGNATURE`, `POLY_TIMESTAMP`, `POLY_API_KEY`,
  /// `POLY_PASSPHRASE`) computed by the caller — typically delegated
  /// to `PolymarketBackendService.userChannelAuthHeaders()` which
  /// shares the HMAC implementation used by REST. Without valid auth
  /// the server silently drops the subscription.
  ///
  /// On reconnect we re-issue the LAST `subscribeToUser` call
  /// automatically — the auth headers are re-fetched at that time
  /// via the [authHeadersFactory] callback (timestamps are short-
  /// lived so a stale snapshot won't work).
  void subscribeToUser({
    required List<String> assetIds,
    required Map<String, String> Function() authHeadersFactory,
  }) {
    _userAssets.addAll(assetIds);
    _userAuthHeadersFactory = authHeadersFactory;
    if (_channel != null) {
      _send({
        'type': 'user',
        'assets_ids': assetIds,
        'auth': authHeadersFactory(),
      });
    }
  }

  /// Drop a subscription. Server stops emitting frames for these ids;
  /// any cached state we hold for them is the consumer's problem.
  void unsubscribeFromMarket(List<String> assetIds) {
    _subscribed.removeAll(assetIds);
    if (_channel == null) return;
    _send({'type': 'unsubscribe', 'assets_ids': assetIds});
  }

  void dispose() {
    _disposed = true;
    _cleanup();
    _messages.close();
    _connectionState.close();
  }

  void _sendSubscribe(List<String> assetIds) {
    _wsLog('→ subscribe market assets_ids=$assetIds');
    _send({'type': 'market', 'assets_ids': assetIds});
  }

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
      final ch = _channel;
      if (ch == null) return;
      try {
        ch.sink.add('ping');
      } catch (_) {}
    });
  }

  /// Frames at least this large (a subscription's opening dump: one book
  /// per token, ~340 KB for a 311-market game) are decoded on another
  /// isolate. Every frame keeps its place in the stream: while one is
  /// being decoded there, the frames after it wait behind it.
  static const int _kOffThreadFrameBytes = 64 * 1024;
  Future<void>? _decodeTail;
  int _decoding = 0;

  void _handleFrame(dynamic data) {
    if (data == 'pong') return;
    if (data is! String) return;
    if (_decoding == 0 && data.length < _kOffThreadFrameBytes) {
      _emitAll(polymarketWsMessagesOf(data));
      return;
    }
    _decoding++;
    _decodeTail = (_decodeTail ?? Future<void>.value()).then((_) async {
      final messages = data.length < _kOffThreadFrameBytes
          ? polymarketWsMessagesOf(data)
          : await Isolate.run(() => polymarketWsMessagesOf(data));
      _emitAll(messages);
    }).catchError((_) {}).whenComplete(() {
      if (--_decoding == 0) _decodeTail = null;
    });
  }

  void _emitAll(List<PolymarketWsMessage> messages) {
    for (final msg in messages) {
      if (kDebugMode && _kPmWsDebug) _wsLog('← ${msg.runtimeType}');
      if (!_messages.isClosed) _messages.add(msg);
    }
  }

  void _handleDone() {
    if (!_connectionState.isClosed) {
      _connectionState.add(PolymarketClobWsState.disconnected);
    }
    if (_intentionalClose || _disposed) return;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || _intentionalClose) return;
    if (_reconnectAttempts >= maxReconnectAttempts) {
      // Give up QUIETLY. This used to `addError` a StateError into the
      // broadcast `messages` stream, but two of its three consumers
      // listen without an onError handler, so the error resurfaced as
      // an UNHANDLED zone error and took the whole app down (a flaky
      // network / device sleep is enough to burn all 10 attempts).
      // Instead: tear down, park in `disconnected`, and reset the
      // budget so the next explicit `connect()` — the consumers' own
      // retry paths all re-enter through it — can revive the socket.
      debugPrint('PolymarketClobWebSocket: max reconnect attempts '
          'exceeded — parked until next connect()');
      TrackingService.recordCrash(
          StateError(
              'PolymarketClobWebSocket: max reconnect attempts exceeded'),
          null,
          reason: 'polymarket_clob_ws_reconnect_exhausted');
      _cleanup();
      _reconnectAttempts = 0;
      if (!_connectionState.isClosed) {
        _connectionState.add(PolymarketClobWsState.disconnected);
      }
      return;
    }
    _cleanup();
    _connectionState.add(PolymarketClobWsState.reconnecting);
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

enum PolymarketClobWsState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

/// The messages in one market-socket frame (an object, or a list of
/// them); none for a heartbeat or a malformed frame. A top-level function
/// so a large frame can be read on another isolate.
List<PolymarketWsMessage> polymarketWsMessagesOf(String data) {
  final Object? decoded;
  try {
    decoded = jsonDecode(data);
  } catch (_) {
    // Drop malformed frames — the server has occasionally been
    // observed to send heartbeat-style payloads we don't model.
    return const [];
  }
  final out = <PolymarketWsMessage>[];
  void add(Object? item) {
    if (item is! Map<String, dynamic>) return;
    try {
      final msg = _messageOf(item);
      if (msg != null) out.add(msg);
    } catch (_) {}
  }

  if (decoded is List) {
    decoded.forEach(add);
  } else {
    add(decoded);
  }
  return out;
}

PolymarketWsMessage? _messageOf(Map<String, dynamic> json) {
  switch (json['event_type'] as String?) {
    case 'book':
      return PolymarketBookMessage.fromJson(json);
    case 'price_change':
      return PolymarketPriceChangeMessage.fromJson(json);
    case 'last_trade_price':
      return PolymarketLastTradePriceMessage.fromJson(json);
    case 'order':
      return PolymarketOrderWsMessage.fromJson(json);
    case 'trade':
      return PolymarketTradeWsMessage.fromJson(json);
  }
  return null;
}
