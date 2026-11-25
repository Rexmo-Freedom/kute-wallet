// lib/services/platform/background_grace.dart
//
// A short stay of execution for a bet or trade that is still being placed
// when the person leaves the app. We say the bet is placed instantly and
// let them go do other things; the money move and the venue's answer
// still have to finish in the background.
//
// `hold(reason)` returns a token, `release(token)` gives it back. While at
// least one token is held the native side keeps the process running for a
// little while after the app leaves the screen:
//
//   * iOS (ios/Runner/BackgroundGracePlugin.swift): one
//     `UIApplication.beginBackgroundTask` per token, begun at hold time
//     (while the app is still in the foreground, as Apple recommends).
//     iOS grants roughly 30 seconds after the app leaves the screen, then
//     calls the expiration handler: the task is ended there and Dart is
//     told (`expired`), the token is dead, and the app is suspended. A
//     later `release` of a dead token does nothing. The binder re-holds
//     when the app comes back while an order is still in flight.
//   * Android (BackgroundGracePlugin.kt): a PARTIAL_WAKE_LOCK acquired when
//     the activity pauses while a token is held, released when it resumes
//     or when the last token is released, and timed out by the system at
//     about 30 seconds. It keeps the CPU awake for Dart during that
//     window; it does not stop the low-memory killer or an OEM's battery
//     policy (Xiaomi, Huawei, Samsung "sleeping apps") from killing or
//     freezing the process, and it is nothing like a foreground service.
//     On stock Android a just-backgrounded process keeps running anyway;
//     how long varies by vendor. Tokens never expire on Android; the lock
//     re-arms on the next background trip while the hold lives.
//   * Elsewhere (web, desktop, tests): a no-op that hands out tokens.
//
// Every call is fire-and-forget and never throws. A hold that is never
// released is a bug, so the [watchdog] releases it after a bounded time
// and reports it: nothing is ever held for good. The bound is the life of
// the longest legitimate wait in the app (a queued bet's 30 minutes).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One held grace, handed out by [BackgroundGrace.hold]. Opaque; compare by
/// identity. [reason] is a short fixed word for logs, never shown.
@immutable
class GraceToken {
  const GraceToken._(this.id, this.reason);

  final int id;
  final String reason;

  @override
  String toString() => 'GraceToken($id, $reason)';
}

abstract final class BackgroundGrace {
  static const MethodChannel channel = MethodChannel('kute/background_grace');

  /// A hold older than this is a leak: released and reported. The queued
  /// bet's own life ([PendingBetIntent.maxQueuedAge]) is the longest wait.
  static const Duration watchdog = Duration(minutes: 30);

  static int _nextId = 1;
  static final Map<int, GraceToken> _held = {};
  static final Map<int, Timer> _watchdogs = {};
  static bool _handlerInstalled = false;

  /// Tokens the native side ended on its own (iOS expiry) or the watchdog
  /// released, since the process started. Diagnostics and tests.
  static final ValueNotifier<int> expiredCount = ValueNotifier<int>(0);
  static final ValueNotifier<int> watchdogCount = ValueNotifier<int>(0);

  /// How many holds are live now.
  static int get activeCount => _held.length;

  /// Whether [token] still holds a grace (false once released, expired or
  /// cut by the watchdog).
  static bool isHeld(GraceToken token) => _held.containsKey(token.id);

  /// Whether this platform has a native backing. On the others every
  /// method is a no-op that still hands out and accepts tokens.
  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  /// Keep the process alive a little after backgrounding, for [reason]
  /// (a fixed short word, e.g. `order`). Returns at once; the native call
  /// is fire-and-forget. Pair with [release] on every exit path.
  static GraceToken hold(String reason) {
    final token = GraceToken._(_nextId++, reason);
    _held[token.id] = token;
    _watchdogs[token.id] = Timer(watchdog, () => _watchdogFired(token));
    if (isSupported) {
      _installHandler();
      unawaited(_invoke('hold', {'id': token.id, 'reason': reason}));
    }
    return token;
  }

  /// Give [token] back. Safe to call twice, or after an expiry.
  static void release(GraceToken token) {
    if (!_forget(token)) return;
    if (isSupported) unawaited(_invoke('release', {'id': token.id}));
  }

  /// Drops [token] from the live set; false when it was not live.
  static bool _forget(GraceToken token) {
    final was = _held.remove(token.id) != null;
    _watchdogs.remove(token.id)?.cancel();
    return was;
  }

  static void _watchdogFired(GraceToken token) {
    if (!_held.containsKey(token.id)) return;
    debugPrint('[BackgroundGrace] watchdog released $token after $watchdog');
    watchdogCount.value++;
    release(token);
  }

  /// The native side ended a task on its own (iOS expiration handler):
  /// the token is dead, nothing is sent back for it.
  static void _expired(int id) {
    final token = _held[id];
    if (token == null) return;
    _forget(token);
    debugPrint('[BackgroundGrace] $token expired natively');
    expiredCount.value++;
  }

  static void _installHandler() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'expired') {
        final args = call.arguments;
        final id = args is Map ? args['id'] : args;
        if (id is int) _expired(id);
      }
      return null;
    });
  }

  static Future<void> _invoke(String method, Map<String, Object?> args) async {
    try {
      await channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // A build without the native plugin: the Dart bookkeeping still
      // holds, the process gets whatever the OS gives it.
    } on PlatformException catch (e) {
      debugPrint('[BackgroundGrace] $method failed: ${e.code}');
    }
  }

  /// Tests: drop every hold and counter without touching the platform.
  @visibleForTesting
  static void debugReset() {
    for (final t in _watchdogs.values) {
      t.cancel();
    }
    _watchdogs.clear();
    _held.clear();
    _nextId = 1;
    expiredCount.value = 0;
    watchdogCount.value = 0;
    _handlerInstalled = false;
    channel.setMethodCallHandler(null);
  }

  /// Tests: what the native side does on expiry, without a platform.
  @visibleForTesting
  static void debugExpire(GraceToken token) => _expired(token.id);
}
