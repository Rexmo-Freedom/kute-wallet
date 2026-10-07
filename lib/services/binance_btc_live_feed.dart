// lib/services/binance_btc_live_feed.dart
//
// Singleton WebSocket subscription to Binance's BTCUSDT trade stream
// (`wss://stream.binance.com:9443/ws/btcusdt@trade`). One physical
// connection, many subscribers — the underlying socket stays open
// while any listener is attached, with a 30s idle-close grace so a
// quick navigation away/back doesn't churn the WS.
//
// Used by:
//   * `home_analytics_widget._LiveBalanceStream` — LIVE Balance tab
//     paints sats × price for a streaming fiat-balance sparkline
//   * `home_analytics_widget._LivePriceStream` — LIVE Price tab
//     builds 1-minute OHLC candles from the same tick stream
//   * `polymarket_provider.CryptoPredictNotifier` (BTC asset) — ONLY
//     while Polymarket's own Chainlink feed is silent: the Up/Down card
//     then switches its whole series to Binance until Chainlink returns.

import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

class BinanceBtcLiveFeed {
  static final BinanceBtcLiveFeed instance = BinanceBtcLiveFeed._();
  BinanceBtcLiveFeed._();

  WebSocketChannel? _channel;
  StreamSubscription? _wsSub;
  StreamController<double>? _controller;
  Timer? _idleClose;
  Timer? _reconnect;
  int _listeners = 0;
  double? _lastPrice;
  bool _hasReceivedTick = false;

  /// Last seen price — `null` until the first tick lands. Lets a new
  /// subscriber paint something instantly while waiting for the next
  /// real tick.
  double? get lastPrice => _lastPrice;

  /// True once we've seen at least one tick on the shared feed. Used
  /// by subscribers to skip a "Connecting…" placeholder when a
  /// previous tab has already warmed the feed.
  bool get hasReceivedTick => _hasReceivedTick;

  /// Eagerly opens the WS without registering a long-lived listener.
  /// Call on screens that will mount a subscriber shortly (e.g. the
  /// Predictions surface) so the first tick lands by the time the
  /// chart paints. Honours the same 30s idle-close grace.
  void prewarm() {
    _idleClose?.cancel();
    if (_controller == null || _controller!.isClosed) {
      _controller = StreamController<double>.broadcast();
      _connect();
    }
    if (_listeners == 0) {
      _idleClose?.cancel();
      _idleClose = Timer(const Duration(seconds: 30), _shutdown);
    }
  }

  Stream<double> subscribe() {
    _idleClose?.cancel();
    _listeners++;
    if (_controller == null || _controller!.isClosed) {
      _controller = StreamController<double>.broadcast();
      _connect();
    }
    return _controller!.stream;
  }

  void release() {
    _listeners = (_listeners - 1).clamp(0, 999);
    if (_listeners == 0) {
      // Don't close immediately — a tab flip transiently has 0
      // listeners as the old widget unmounts before the new one
      // subscribes. 30 seconds keeps the WS warm across navigation.
      _idleClose?.cancel();
      _idleClose = Timer(const Duration(seconds: 30), _shutdown);
    }
  }

  void _connect() {
    try {
      _channel = WebSocketChannel.connect(
        Uri.parse('wss://stream.binance.com:9443/ws/btcusdt@trade'),
      );
      // web_socket_channel 3.x rejects `.ready` on a failed connect;
      // with no listener that rejection escapes the zone as a recorded
      // FATAL (one per reconnect attempt when offline). The stream
      // onError below owns recovery; `.ready` just needs a listener.
      _channel!.ready.ignore();
      _wsSub = _channel!.stream.listen(
        (raw) {
          try {
            final map = jsonDecode(raw as String);
            if (map is! Map<String, dynamic>) return;
            final priceStr = map['p'] as String?;
            if (priceStr == null) return;
            final price = double.tryParse(priceStr);
            if (price == null || price <= 0) return;
            _lastPrice = price;
            _hasReceivedTick = true;
            _controller?.add(price);
          } catch (_) {}
        },
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _wsSub?.cancel();
    _channel?.sink.close();
    _reconnect?.cancel();
    if (_listeners > 0) {
      _reconnect = Timer(const Duration(seconds: 2), _connect);
    }
  }

  void _shutdown() {
    _wsSub?.cancel();
    _channel?.sink.close();
    _reconnect?.cancel();
    _controller?.close();
    _controller = null;
    _channel = null;
    _wsSub = null;
    _hasReceivedTick = false;
  }
}
