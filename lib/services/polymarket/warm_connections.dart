// lib/services/polymarket/warm_connections.dart
//
// One connection to clob.polymarket.com kept open while a bet slip is
// up, so the reads the placement makes (a book the feed could not supply,
// the fee curve, the price increment) and the order's POST reuse it
// instead of paying a new TLS handshake each (two or three round trips,
// close to a second on a slow mobile link). The backend connection is
// warmed by the builder-code refresh the slip starts at the same time,
// through the resolver's own kept client.
//
// Reference counted: the first slip acquires, the last one releases; the
// pool is closed when nothing holds it. Under `http.runWithClient` (a
// test) the zone's client is used as it is, so fakes see every request.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

class PolymarketWarmConnections {
  PolymarketWarmConnections._();

  static const String clobHost = 'clob.polymarket.com';

  /// How long an idle connection is kept; the venue's own idle timeout
  /// is longer, and a slip rarely stays open past this.
  static const Duration idleFor = Duration(seconds: 90);

  /// A cheap read on the warm connection this often while held, so the
  /// socket is still open when the person taps.
  static const Duration pingEvery = Duration(seconds: 45);

  static http.Client? _held;
  static int _holds = 0;
  static Timer? _pinger;

  /// Pings made, for tests.
  @visibleForTesting
  static int pings = 0;

  /// The client for a venue read now: the warm one while a slip holds it,
  /// else a client for this call (zone-aware, so fakes still intercept).
  /// The caller closes what it did not borrow: see [borrowClob].
  static ({http.Client client, bool borrowed}) borrowClob() {
    final held = _held;
    if (held != null) return (client: held, borrowed: true);
    return (client: http.Client(), borrowed: false);
  }

  /// Runs [body] with a venue client, closing it after when it was not
  /// the warm one.
  static Future<T> withClob<T>(Future<T> Function(http.Client c) body) async {
    final (client: c, borrowed: borrowed) = borrowClob();
    try {
      return await body(c);
    } finally {
      if (!borrowed) c.close();
    }
  }

  static http.Client _newClient() {
    final zoned = http.Client();
    // Under runWithClient the factory returns the zone's client (a fake):
    // keep it. Otherwise build a pool that keeps idle sockets open.
    if (zoned is! IOClient) return zoned;
    zoned.close();
    return IOClient(HttpClient()
      ..idleTimeout = idleFor
      ..connectionTimeout = const Duration(seconds: 10));
  }

  /// A slip opened: open the venue connection and keep it warm.
  static void acquire() {
    _holds++;
    if (_held != null) return;
    _held = _newClient();
    unawaited(_ping());
    _pinger?.cancel();
    _pinger = Timer.periodic(pingEvery, (_) => unawaited(_ping()));
  }

  /// The slip closed: the last release closes the pool.
  static void release() {
    if (_holds == 0) return;
    if (--_holds > 0) return;
    _pinger?.cancel();
    _pinger = null;
    _held?.close();
    _held = null;
  }

  static Future<void> _ping() async {
    final c = _held;
    if (c == null) return;
    pings++;
    try {
      await c
          .get(Uri.https(clobHost, '/time'))
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // The next read opens a connection as it would have anyway.
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _pinger?.cancel();
    _pinger = null;
    _held?.close();
    _held = null;
    _holds = 0;
    pings = 0;
  }

  @visibleForTesting
  static bool get isHeld => _held != null;
}
