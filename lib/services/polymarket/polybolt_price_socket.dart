// lib/services/polymarket/polybolt_price_socket.dart
//
// PolyBolt reference-price client: Polymarket's only live source of the
// Chainlink prices its crypto Up/Down markets resolve on. It replaced the
// price topics of Polymarket's previous live-data socket, which are
// removed in late October 2026; the app no longer talks to that socket.
//
// Topic mapping from the migration guide, for the record:
//   crypto_prices (Binance, btcusdt)        → price.crypto      {symbol: btcusd}
//   crypto_prices_chainlink (btc/usd)       → price.crypto      {symbol: btcusd}
//   crypto_prices_twap_sixty (btc/usd)      → price.crypto.twap {symbol: btcusd, window_seconds: 60}
//   crypto_prices_twap_thirty               → none
//   equity_prices (AAPL)                    → price.equity      {symbol: aapl}
// The app only ever used crypto_prices_twap_sixty, now price.crypto.twap.
//
// Endpoint: wss://ws-live-v2.polymarket.com/ws (AsyncAPI 2.0.0 at
// https://ws-live-v2.polymarket.com/asyncapi.json, migration guide at
// https://docs.polymarket.com/migrate/rtds-to-polybolt).
//
// Wire format (verified live Sep 2026 against the production socket —
// acks, error acks and the envelope shape; the gated price payload
// itself is taken from the AsyncAPI spec because it needs real CLOB
// credentials to observe):
//
//   auth       → {"op":"auth","rid":"a1","auth":{"apiKey":..,"secret":..,"passphrase":..}}
//              ← {"op":"authed","rid":"a1"}
//              ← {"op":"error","rid":"a1","code":"auth_invalid"}   (refused)
//   subscribe  → {"op":"subscribe","rid":"s1","subscriptions":[
//                  {"channel":"price.crypto.twap","filter":{"symbol":"btcusd","window_seconds":60}}]}
//              ← {"op":"subscribed","channel":"price.crypto.twap","rid":"s1"}
//              ← {"op":"error","channel":"price.crypto.twap","rid":"s1","code":"auth_required"}
//   ping       → {"op":"ping","rid":"p1"}   ← {"op":"pong","rid":"p1"}
//   price      ← {"v":1,"channel":"price.crypto.twap","seq":3,"ts":1788973002000,
//                  "payload":{"symbol":"btcusd","value":64120.7,
//                             "full_accuracy_value":"64120.70000000",
//                             "timestamp":1788973002000,"window_seconds":60,
//                             "source":"chainlink"}}
//   snapshot   ← same envelope with "snapshot":true and
//                  "payload":{"symbol","window_seconds","source","data":[{timestamp,value,full_accuracy_value},..]}
//
// The reference-price channels are gated: subscribing before a
// successful auth answers `auth_required` and the connection stays
// open. Symbols are lowercase `<coin>usd` (btcusd, not btc/usd or
// btcusdt). Close codes: 4001 auth failed, 4002 slow consumer, 4003
// server draining (reconnect after 0-10s), 4008 policy violation (do
// not reconnect blindly).

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:kute/services/polymarket/polymarket_price_source.dart'
    show PmReferencePriceFrame;
import 'package:web_socket_channel/web_socket_channel.dart';

const kPolyBoltWsUrl = 'wss://ws-live-v2.polymarket.com/ws';

/// Chainlink 60-second TWAP — the series Polymarket's crypto Up/Down
/// markets resolve on (AsyncAPI: "Chainlink time-weighted average prices
/// used by crypto up/down market resolution"). polymarket.com plots this
/// series on its Up/Down charts, so the app's Up/Down cards read it too.
const kPolyBoltCryptoTwapChannel = 'price.crypto.twap';

/// Spot, about one update per second per symbol, Chainlink by default.
/// The migration guide maps the old Chainlink and Binance spot topics
/// here. Not the series the Up/Down markets resolve on.
const kPolyBoltCryptoSpotChannel = 'price.crypto';

/// The only TWAP window PolyBolt carries data for today.
const kPolyBoltTwapWindowSeconds = 60;

/// PolyBolt symbol for an asset ticker: lowercase, `usd` suffix
/// (`BTC` → `btcusd`). Older spellings such as `btc/usd` or `BTCUSDT`
/// normalise to the same thing, since PolyBolt refuses them.
String polyBoltSymbolForAsset(String asset) {
  var s = asset.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  if (s.endsWith('usdt')) s = s.substring(0, s.length - 4);
  if (s.endsWith('usd')) s = s.substring(0, s.length - 3);
  return '${s}usd';
}

/// The CLOB L2 API credential trio — the same credentials the CLOB user
/// WebSocket authenticates with (`ClobCredentials` in the AsyncAPI).
@immutable
class PolyBoltCredentials {
  final String apiKey;
  final String secret;
  final String passphrase;

  const PolyBoltCredentials({
    required this.apiKey,
    required this.secret,
    required this.passphrase,
  });

  bool get isComplete =>
      apiKey.isNotEmpty && secret.isNotEmpty && passphrase.isNotEmpty;
}

/// One decoded reference-price point.
@immutable
class PolyBoltPricePoint {
  /// Lowercase PolyBolt symbol, e.g. `btcusd`.
  final String symbol;
  final double price;

  /// Source event time, Unix milliseconds (null when the frame did not
  /// carry one).
  final int? timestampMs;

  /// Channel the frame arrived on (`price.crypto.twap` / `price.crypto`).
  final String channel;

  /// True for the one snapshot frame sent after each subscription.
  final bool isSnapshot;

  const PolyBoltPricePoint({
    required this.symbol,
    required this.price,
    required this.channel,
    this.timestampMs,
    this.isSnapshot = false,
  });

  @override
  String toString() =>
      'PolyBoltPricePoint($symbol=$price @$timestampMs on $channel'
      '${isSnapshot ? ', snapshot' : ''})';
}

/// The server refused or could not verify our credentials, or a gated
/// subscription was rejected. Not retried by the socket; the consumer
/// decides when to try again (see [PolyBoltPriceSocket.isHardFailure]).
class PolyBoltAuthException implements Exception {
  final String code;
  const PolyBoltAuthException(this.code);
  @override
  String toString() => 'PolyBoltAuthException($code)';
}

/// The socket could not be (re)established within the reconnect budget
/// or was closed with a code we must not blindly reconnect from.
class PolyBoltDisconnectedException implements Exception {
  final String reason;
  final int? closeCode;
  const PolyBoltDisconnectedException(this.reason, {this.closeCode});
  @override
  String toString() =>
      'PolyBoltDisconnectedException($reason'
      '${closeCode != null ? ', close=$closeCode' : ''})';
}

/// Minimal socket surface the client needs, so tests can inject a fake
/// without a real network. Production wraps a [WebSocketChannel].
abstract class PolyBoltTransport {
  Future<void> get ready;
  Stream<dynamic> get stream;
  int? get closeCode;
  void send(String frame);
  Future<void> close();
}

typedef PolyBoltTransportFactory = PolyBoltTransport Function(Uri url);

class _WebSocketChannelTransport implements PolyBoltTransport {
  final WebSocketChannel _channel;
  _WebSocketChannelTransport(Uri url) : _channel = WebSocketChannel.connect(url);

  @override
  Future<void> get ready => _channel.ready;
  @override
  Stream<dynamic> get stream => _channel.stream;
  @override
  int? get closeCode => _channel.closeCode;
  @override
  void send(String frame) => _channel.sink.add(frame);
  @override
  Future<void> close() => _channel.sink.close();
}

/// Authenticated PolyBolt reference-price stream over ONE socket.
///
/// [framesByAsset] emits [PmReferencePriceFrame]s keyed by the app's
/// asset, for `CryptoReferencePricesNotifier`. Reconnects with linear
/// backoff like `PolymarketClobWebSocket`, re-authenticating and
/// resubscribing every time; auth failures and an exhausted budget
/// surface as an error followed by stream close so the consumer can
/// schedule its own retry.
class PolyBoltPriceSocket {
  /// Re-read on every (re)connect so a rotated credential is picked up.
  final PolyBoltCredentials? Function() credentials;
  final String url;
  final String channel;
  final Duration pingInterval;
  final Duration reconnectBaseDelay;
  final Duration maxReconnectDelay;
  final int maxReconnectAttempts;
  final PolyBoltTransportFactory _transportFactory;

  PolyBoltPriceSocket({
    required this.credentials,
    this.url = kPolyBoltWsUrl,
    this.channel = kPolyBoltCryptoTwapChannel,
    this.pingInterval = const Duration(seconds: 30),
    this.reconnectBaseDelay = const Duration(seconds: 2),
    this.maxReconnectDelay = const Duration(seconds: 30),
    this.maxReconnectAttempts = 5,
    PolyBoltTransportFactory? transportFactory,
  }) : _transportFactory =
            transportFactory ?? ((Uri u) => _WebSocketChannelTransport(u));

  // ── Frame builders (pure, unit-tested) ────────────────────────────

  static Map<String, dynamic> authFrame(PolyBoltCredentials creds,
      {String rid = 'a1'}) {
    return {
      'op': 'auth',
      'rid': rid,
      'auth': {
        'apiKey': creds.apiKey,
        'secret': creds.secret,
        'passphrase': creds.passphrase,
      },
    };
  }

  static Map<String, dynamic> subscribeFrame(
    Iterable<String> symbols, {
    String channel = kPolyBoltCryptoTwapChannel,
    String rid = 's1',
  }) {
    final twap = channel.endsWith('.twap');
    return {
      'op': 'subscribe',
      'rid': rid,
      'subscriptions': [
        for (final s in symbols)
          {
            'channel': channel,
            'filter': {
              'symbol': s,
              if (twap) 'window_seconds': kPolyBoltTwapWindowSeconds,
            },
          },
      ],
    };
  }

  static Map<String, dynamic> pingFrame({String rid = 'p1'}) =>
      {'op': 'ping', 'rid': rid};

  // ── Frame parsing (pure, unit-tested) ─────────────────────────────

  static double? _toPrice(Object? raw) {
    if (raw == null) return null;
    final p = raw is num ? raw.toDouble() : double.tryParse(raw.toString());
    if (p == null || !p.isFinite || p <= 0) return null;
    return p;
  }

  static int? _toInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }

  /// Decodes a price envelope into the newest point it carries, or null
  /// for acks / errors / anything that is not a price frame.
  ///
  /// Handles the AsyncAPI envelope (`{v, channel, seq, ts, snapshot?,
  /// payload}`) for both live points and snapshot batches, and the
  /// `{topic, type, payload}` variant shown in the docs' realtime-data
  /// page. `full_accuracy_value` (exact decimal string) is preferred
  /// over the float `value`.
  static PolyBoltPricePoint? parsePriceFrame(Map<String, dynamic> json) {
    if (json['op'] != null) return null; // ack / error / pong
    final channel = (json['channel'] ?? json['topic'])?.toString();
    if (channel == null) return null;
    final payload = json['payload'];
    if (payload is! Map) return null;
    final symbol = payload['symbol']?.toString().toLowerCase();
    if (symbol == null || symbol.isEmpty) return null;
    final isSnapshot = json['snapshot'] == true;

    double? price;
    int? ts;
    final data = payload['data'];
    if (data is List) {
      // Snapshot batch: take the newest point by event time.
      for (final item in data) {
        if (item is! Map) continue;
        final p = _toPrice(item['full_accuracy_value']) ?? _toPrice(item['value']);
        if (p == null) continue;
        final t = _toInt(item['timestamp']);
        if (ts == null || (t != null && t >= ts)) {
          price = p;
          ts = t ?? ts;
        }
      }
    } else {
      price = _toPrice(payload['full_accuracy_value']) ?? _toPrice(payload['value']);
      ts = _toInt(payload['timestamp']) ?? _toInt(json['ts']) ?? _toInt(json['timestamp']);
    }
    if (price == null) return null;
    return PolyBoltPricePoint(
      symbol: symbol,
      price: price,
      channel: channel,
      timestampMs: ts,
      isSnapshot: isSnapshot,
    );
  }

  /// `full_accuracy_value` when it agrees with the float `value`, else
  /// `value`. The spec documents the exact field as a decimal string;
  /// the legacy TWAP frames carried an integer scaled by 1e18, so a
  /// scaled integer is guarded against and never reaches the screen.
  static double? _pointPrice(Map<dynamic, dynamic> point) {
    final value = _toPrice(point['value']);
    final exact = _toPrice(point['full_accuracy_value']);
    if (value == null) return exact;
    if (exact == null) return value;
    return (exact - value).abs() <= value * 0.01 ? exact : value;
  }

  /// Every point a price envelope carries, oldest first, in the
  /// source's event time: the whole history for a snapshot batch, one
  /// point for a live frame. Empty for anything that is not a price
  /// frame. A point without a timestamp is stamped with the arrival time.
  static List<({DateTime t, double p})> parsePricePoints(
      Map<String, dynamic> json) {
    if (json['op'] != null) return const [];
    final payload = json['payload'];
    if (payload is! Map) return const [];
    final out = <({DateTime t, double p})>[];
    DateTime at(int? ms) => ms != null
        ? DateTime.fromMillisecondsSinceEpoch(ms)
        : DateTime.now();
    final data = payload['data'];
    if (data is List) {
      for (final item in data) {
        if (item is! Map) continue;
        final p = _pointPrice(item);
        if (p == null) continue;
        out.add((t: at(_toInt(item['timestamp'])), p: p));
      }
      out.sort((a, b) => a.t.compareTo(b.t));
    } else {
      final p = _pointPrice(payload);
      if (p != null) {
        out.add((
          t: at(_toInt(payload['timestamp']) ??
              _toInt(json['ts']) ??
              _toInt(json['timestamp'])),
          p: p,
        ));
      }
    }
    return out;
  }

  /// True for a failure that retrying soon with the same credentials
  /// cannot fix: credentials refused (`auth_invalid`, `auth_expired`,
  /// `auth_required`, `auth_attempts`, close 4001) or a policy close
  /// (4008, a client bug). `auth_unavailable` (verifier unreachable),
  /// a missing credential and an exhausted reconnect budget are
  /// transient.
  static bool isHardFailure(Object error) {
    if (error is PolyBoltAuthException) {
      return error.code != 'auth_unavailable' &&
          error.code != 'no_credentials';
    }
    if (error is PolyBoltDisconnectedException) {
      return error.closeCode == 4008;
    }
    return false;
  }

  static bool _isAuthErrorCode(String code) =>
      code == 'auth_required' ||
      code == 'auth_invalid' ||
      code == 'auth_expired' ||
      code == 'auth_unavailable' ||
      code == 'auth_attempts';

  // ── Stream ────────────────────────────────────────────────────────

  /// `symbolByAsset` maps the consumer's asset key (e.g. `BTC`) to the
  /// PolyBolt symbol to subscribe (`btcusd`). Emits `{asset: price}` for
  /// every price frame whose symbol is subscribed (the newest point of a
  /// snapshot).
  Stream<Map<String, double>> pricesByAsset(Map<String, String> symbolByAsset) =>
      framesByAsset(symbolByAsset)
          .map((f) => <String, double>{f.asset: f.points.last.p});

  /// Same socket as [pricesByAsset], but every frame keeps its points
  /// with their event times, and a subscribe snapshot keeps its whole
  /// history, so a chart can be seeded from it.
  Stream<PmReferencePriceFrame> framesByAsset(
      Map<String, String> symbolByAsset) {
    late StreamController<PmReferencePriceFrame> controller;
    final assetBySymbol = <String, String>{
      for (final e in symbolByAsset.entries) e.value.toLowerCase(): e.key,
    };
    PolyBoltTransport? transport;
    StreamSubscription<dynamic>? sub;
    Timer? ping;
    Timer? reconnectTimer;
    var attempts = 0;
    var cancelled = false;

    void log(String msg) => debugPrint('[pm-prices] polybolt: $msg');

    Future<void> teardownSocket() async {
      ping?.cancel();
      ping = null;
      await sub?.cancel();
      sub = null;
      try {
        await transport?.close();
      } catch (_) {}
      transport = null;
    }

    void fail(Object error) {
      if (cancelled || controller.isClosed) return;
      cancelled = true;
      reconnectTimer?.cancel();
      log('giving up: $error');
      controller.addError(error);
      // Let the error propagate before closing so listeners see both.
      scheduleMicrotask(() {
        if (!controller.isClosed) controller.close();
      });
      // ignore: discarded_futures
      teardownSocket();
    }

    late Future<void> Function() connect;

    void scheduleReconnect(String why, {int? closeCode}) {
      if (cancelled || controller.isClosed) return;
      if (closeCode == 4001) {
        fail(const PolyBoltAuthException('close_4001'));
        return;
      }
      if (closeCode == 4008) {
        fail(PolyBoltDisconnectedException(why, closeCode: closeCode));
        return;
      }
      if (attempts >= maxReconnectAttempts) {
        fail(PolyBoltDisconnectedException(
            'reconnect budget exhausted ($why)',
            closeCode: closeCode));
        return;
      }
      attempts += 1;
      var delayMs = (reconnectBaseDelay.inMilliseconds * attempts)
          .clamp(0, maxReconnectDelay.inMilliseconds);
      if (closeCode == 4003) {
        // Server draining: reconnect once after a uniform 0-10s delay.
        delayMs = math.Random().nextInt(10000);
      }
      log('reconnect #$attempts in ${delayMs}ms ($why)');
      // ignore: discarded_futures
      teardownSocket();
      reconnectTimer = Timer(Duration(milliseconds: delayMs), () {
        if (cancelled || controller.isClosed) return;
        // ignore: discarded_futures
        connect();
      });
    }

    void send(Map<String, dynamic> frame) {
      final t = transport;
      if (t == null) return;
      try {
        t.send(jsonEncode(frame));
      } catch (_) {
        // Sink closing under us — the done/error path will reconnect.
      }
    }

    void handleFrame(dynamic data) {
      if (cancelled || controller.isClosed) return;
      if (data is! String) return;
      Object? decoded;
      try {
        decoded = jsonDecode(data);
      } catch (_) {
        return;
      }
      if (decoded is! Map<String, dynamic>) return;
      final op = decoded['op'];
      if (op is String) {
        switch (op) {
          case 'authed':
            attempts = 0;
            log('authenticated, subscribing $channel for '
                '${assetBySymbol.keys.join(',')}');
            send(subscribeFrame(assetBySymbol.keys, channel: channel));
            break;
          case 'subscribed':
            log('subscribed ${decoded['channel']}');
            break;
          case 'error':
            final code = decoded['code']?.toString() ?? 'unknown';
            if (_isAuthErrorCode(code)) {
              fail(PolyBoltAuthException(code));
            } else {
              log('error ack $code channel=${decoded['channel']}');
            }
            break;
          case 'pong':
          default:
            break;
        }
        return;
      }
      final point = parsePriceFrame(decoded);
      if (point == null) return;
      final asset = assetBySymbol[point.symbol];
      if (asset == null) return;
      final points = parsePricePoints(decoded);
      if (points.isEmpty) return;
      controller.add(PmReferencePriceFrame(
        asset: asset,
        points: points,
        isSnapshot: point.isSnapshot,
      ));
    }

    connect = () async {
      if (cancelled || controller.isClosed) return;
      final creds = credentials();
      if (creds == null || !creds.isComplete) {
        fail(const PolyBoltAuthException('no_credentials'));
        return;
      }
      PolyBoltTransport t;
      try {
        t = _transportFactory(Uri.parse(url));
        transport = t;
        await t.ready;
      } catch (e) {
        scheduleReconnect('connect failed: $e');
        return;
      }
      if (cancelled || controller.isClosed) {
        await teardownSocket();
        return;
      }
      sub = t.stream.listen(
        handleFrame,
        onError: (Object e, StackTrace st) {
          scheduleReconnect('socket error: $e', closeCode: t.closeCode);
        },
        onDone: () {
          if (transport != t) return; // already torn down
          scheduleReconnect('socket closed', closeCode: t.closeCode);
        },
        cancelOnError: false,
      );
      send(authFrame(creds));
      ping?.cancel();
      ping = Timer.periodic(pingInterval, (_) => send(pingFrame()));
    };

    controller = StreamController<PmReferencePriceFrame>(
      onListen: () {
        // ignore: discarded_futures
        connect();
      },
      onCancel: () async {
        cancelled = true;
        reconnectTimer?.cancel();
        await teardownSocket();
      },
    );
    return controller.stream;
  }
}
