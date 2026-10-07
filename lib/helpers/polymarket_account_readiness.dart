import 'dart:async';

/// Readiness is earned by completing account setup, never by knowing the
/// deterministic deposit address. Concurrent callers share that setup.
class PolymarketAccountReadiness {
  String? _readyScope;
  String? _pendingScope;
  Future<void>? _pending;
  DateTime? _pendingSince;

  /// How long a running setup is shared with later callers. Every request
  /// in it is bounded, so one still running past this is stuck on
  /// something a fresh attempt may not be: the next caller starts its own
  /// instead of waiting on it forever. Setup is idempotent on chain.
  static const joinWindow = Duration(minutes: 5);

  /// Clock seam for tests.
  static DateTime Function() now = DateTime.now;

  /// Setup has completed for some account and none is running now. False
  /// means the next placement waits on (or starts) the one-time setup.
  bool get isReady => _readyScope != null && _pending == null;

  Future<void> ensure({
    required String scope,
    required bool Function() isCurrent,
    required Future<void> Function() initialize,
    bool force = false,
  }) {
    if (!isCurrent()) {
      return Future.error(StateError('Predictions account changed'));
    }
    if (_pendingScope == scope &&
        _pending != null &&
        now().difference(_pendingSince ?? now()) < joinWindow) {
      return _pending!;
    }
    if (!force && _readyScope == scope) return Future.value();
    _readyScope = null;
    _pendingScope = scope;
    late final Future<void> pending;
    pending = Future<void>.sync(initialize).then((_) {
      if (!isCurrent()) throw StateError('Predictions account changed');
      _readyScope = scope;
    }).whenComplete(() {
      if (identical(_pending, pending)) {
        _pending = null;
        _pendingScope = null;
      }
    });
    _pending = pending;
    _pendingSince = now();
    return pending;
  }
}
