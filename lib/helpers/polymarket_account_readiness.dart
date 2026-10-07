import 'dart:async';

/// Readiness is earned by completing account setup, never by knowing the
/// deterministic deposit address. Concurrent callers share that setup.
///
/// A forced repair (an order refused for a missing approval) on an account
/// that is already set up is a separate, time-bounded operation: it used
/// to clear readiness and run as the account's setup, so every other bet
/// on the account showed "Setting up your Predictions wallet…" and joined
/// it for up to five minutes. Now the account stays ready while it runs,
/// its callers are released after [repairWindow] whatever it is doing,
/// and readiness is only withdrawn when the repair itself fails (the
/// account could not be proven set up, so the next placement runs setup).
class PolymarketAccountReadiness {
  String? _readyScope;
  String? _pendingScope;
  Future<void>? _pending;
  DateTime? _pendingSince;
  String? _repairScope;
  Future<void>? _repair;
  DateTime? _repairSince;

  /// How long a running setup is shared with later callers. Every request
  /// in it is bounded, so one still running past this is stuck on
  /// something a fresh attempt may not be: the next caller starts its own
  /// instead of waiting on it forever. Setup is idempotent on chain.
  static const joinWindow = Duration(minutes: 5);

  /// How long a forced repair of a ready account holds its callers (the
  /// placement's setup wait, PolymarketPlacementWaits.setup). Past it the
  /// callers get a TimeoutException; the repair keeps running on its own
  /// and a later forced repair starts afresh.
  static const repairWindow = Duration(seconds: 90);

  /// Clock seam for tests.
  static DateTime Function() now = DateTime.now;

  /// Setup has completed for some account and none is running now. False
  /// means the next placement waits on (or starts) the one-time setup. A
  /// forced repair running on a ready account leaves it true.
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
    if (_readyScope == scope) {
      if (!force) return Future.value();
      return _runRepair(scope, isCurrent, initialize);
    }
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

  Future<void> _runRepair(String scope, bool Function() isCurrent,
      Future<void> Function() initialize) {
    final at = now();
    final running = _repair;
    if (running == null ||
        _repairScope != scope ||
        at.difference(_repairSince ?? at) >= repairWindow) {
      late final Future<void> repair;
      repair = Future<void>.sync(initialize).then((_) {
        if (!isCurrent()) throw StateError('Predictions account changed');
      }, onError: (Object error, StackTrace stack) {
        // The repair could not finish: the account is no longer proven
        // set up, so the next placement runs setup (bounded) instead of
        // signing against it. A slow repair that is still running keeps
        // the account ready.
        if (_readyScope == scope) _readyScope = null;
        Error.throwWithStackTrace(error, stack);
      }).whenComplete(() {
        if (identical(_repair, repair)) {
          _repair = null;
          _repairScope = null;
          _repairSince = null;
        }
      });
      _repair = repair;
      _repairScope = scope;
      _repairSince = at;
    }
    final left = repairWindow - at.difference(_repairSince!);
    return _repair!.timeout(left.isNegative ? Duration.zero : left);
  }
}
