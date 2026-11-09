// lib/services/polymarket/order_poll_gate.dart
//
// While a Predictions order is in flight, the app's background polling steps
// aside: on a weak link every poll competes with the one request that
// matters. Pollers that are safe to skip ask [OrderPollGate.paused] on their
// tick and skip it; their timers keep running, so they pick up by themselves
// when the order ends. Nothing here cancels or restarts anything, so a bug
// can only ever cost a skipped tick.
//
// It can never stay shut: [during] releases in a finally on every exit path,
// the app leaving the screen opens it, and a hold older than [maxHold] stops
// counting even if nothing released it.

import 'package:flutter/foundation.dart' show visibleForTesting;

abstract final class OrderPollGate {
  /// Longer than any order takes (the 60 s retry window per ladder rung),
  /// and the backstop if a hold is ever leaked.
  static const Duration maxHold = Duration(minutes: 3);

  static DateTime Function() _now = DateTime.now;
  static final Map<int, DateTime> _holds = {};
  static int _next = 0;

  /// Whether background polls should skip this tick.
  static bool get paused {
    final oldest = _now().subtract(maxHold);
    _holds.removeWhere((_, since) => since.isBefore(oldest));
    return _holds.isNotEmpty;
  }

  /// Polls step aside while [order] runs, however it ends.
  static Future<T> during<T>(Future<T> Function() order) async {
    final id = _next++;
    _holds[id] = _now();
    try {
      return await order();
    } finally {
      _holds.remove(id);
    }
  }

  /// The app left the screen: nothing stays paused behind it. An order still
  /// running does not pause polling again.
  static void appBackgrounded() => _holds.clear();

  @visibleForTesting
  static void debugSetClock(DateTime Function()? now) =>
      _now = now ?? DateTime.now;

  @visibleForTesting
  static void debugReset() {
    _holds.clear();
    _now = DateTime.now;
  }
}
