// lib/services/polymarket/funded_chain_watch.dart
//
// While an accepted, funded Predictions bet waits for its money, we read
// the deposit wallet's pUSD and USDC.e on chain ourselves instead of
// waiting for Orchestra's status, the 15 s autofire poll or the 30 s
// trading poll to notice it (founder, 11 November 2026: Dollars →
// Predictions measured ~35 s although Orchestra delivers in ~5 s).
//
// Cadence, counted from the bet's funding (its `queuedAt`):
//   * every 1 s for the first 30 s,
//   * every 4 s until 2 minutes,
//   * then nothing here: the autofire's own 15 s poll (today's) carries on.
//
// RPC safety (founder: "make sure we don't DDoS RPC and such"):
//   * ONE shared ticker per app, whatever number of bets, slips or screens
//     wait: every waiter is served by the same read.
//   * Exactly one read in flight: the next tick is scheduled only after the
//     read returns (a slow answer delays the next tick, nothing piles up),
//     and never sooner than [FundedChainWatch.minGap] after it.
//   * One tick = two `eth_call balanceOf` (pUSD, then USDC.e) one after the
//     other to ONE endpoint, never raced across endpoints: the Polygon read
//     client sends one call per request (no JSON-RPC batch, no Multicall in
//     the app). `PolymarketOnboardingService.readBalancesForPoll`: 3 s per
//     call; the endpoint is the healthiest in the read order; an error, a
//     429 / non-200, a timeout or a malformed answer cools it down for a
//     minute (shared with every other read) and the NEXT configured
//     endpoint is tried, two endpoints per tick at most, one after the
//     other. The answering endpoint's index and the failed attempts are
//     recorded on the funding events (`chain_rpc_endpoint`,
//     `chain_rpc_errors`).
//   * A tick no endpoint answered backs off 1 → 2 → 4 → 8 → 15 s (cap),
//     reset by the next good read. Never a silent "not yet": a failure is
//     counted and retried on the backoff, not left to the 15 s poll.
//   * At most [FundedChainWatch.maxReadsPerWaiter] (60) ticks per waiting
//     bet; past it the bet falls back to the 15 s poll.
//   * No read while [FundedChainWatch.canRead] says no: the app in the
//     background with no background grace held (`BackgroundGrace`, which
//     already keeps funding legs alive), or the session locked.
//
// Worst-case request rate, per waiting set (one at a time in the app):
//   * at most ONE HTTP request in flight at any moment, from this watch;
//   * typical (first endpoint answers): 2 requests/s for 30 s, then
//     0.5 requests/s until 2 min: ≈ 52 ticks, ≈ 104 requests per bet, all
//     to one provider;
//   * hard cap: 60 ticks per bet; a tick is at most 4 requests (2 calls ×
//     2 endpoints), so ≤ 240 requests per bet in the very worst case and
//     never more than 2 requests/s to any one provider (a tick's calls are
//     sequential and the next tick starts ≥ 1 s after the last started);
//   * an endpoint failing: ≤ 4 requests per tick, then 1, 2, 4, 8, 15 s
//     between ticks: a sustained outage costs ≤ 4 requests per 15 s.
//
// Nothing here moves money: it only reads, and tells the autofire what it
// read ([onRead]). No ids, addresses or keys leave this file.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;

/// The deposit wallet's pUSD and USDC.e, in micro-units, the index of the
/// read endpoint that answered (never its URL) and how many endpoints
/// failed before it.
typedef ChainCollateral = ({
  BigInt pusd,
  BigInt usdce,
  int endpoint,
  int rpcErrors
});

class _Waiter {
  _Waiter(this.since);
  final DateTime since;
  int reads = 0;
}

class FundedChainWatch {
  FundedChainWatch({
    required this.read,
    required this.onRead,
    bool Function()? canRead,
    DateTime Function()? clock,
    this.readTimeout = const Duration(seconds: 20),
    this.maxReads = maxReadsPerWaiter,
  })  : _canRead = canRead ?? _always,
        _clock = clock ?? DateTime.now;

  static bool _always() => true;

  /// The first stretch after funding, read every [fastEvery].
  static const Duration fastFor = Duration(seconds: 30);
  static const Duration fastEvery = Duration(seconds: 1);

  /// Until [slowUntil] after funding, read every [slowEvery]; past it the
  /// waiter is dropped (the autofire's 15 s poll carries on).
  static const Duration slowUntil = Duration(minutes: 2);
  static const Duration slowEvery = Duration(seconds: 4);

  /// Ticks one waiting bet may cost at most (the default of [maxReads]).
  static const int maxReadsPerWaiter = 60;

  /// Ticks one waiting bet may cost at most here.
  final int maxReads;

  /// The backoff after a failed read: 1 s, doubled per failure, capped.
  static const Duration backoffStart = Duration(seconds: 1);
  static const Duration backoffCap = Duration(seconds: 15);

  /// The least time between a read's answer and the next read.
  static const Duration minGap = Duration(milliseconds: 250);

  /// How often a waiter funded [sinceFunded] ago is read; null once past
  /// its window.
  static Duration? cadenceAt(Duration sinceFunded) {
    if (sinceFunded < fastFor) return fastEvery;
    if (sinceFunded < slowUntil) return slowEvery;
    return null;
  }

  /// Reads the wallet (two balances). Null when there is nothing to read
  /// yet (no account); throws when the read failed.
  final Future<ChainCollateral?> Function() read;

  /// Told every good read. It may [unwatch] (the money is there).
  final void Function(ChainCollateral collateral) onRead;

  /// Whether a read may go out now (foreground or grace, unlocked).
  final bool Function() _canRead;
  final DateTime Function() _clock;

  /// A read still unanswered after this lets the ticker back off, but the
  /// next read waits for that one to end all the same.
  final Duration readTimeout;

  final Map<Object, _Waiter> _waiters = {};
  Timer? _timer;
  bool _inFlight = false;
  bool _disposed = false;
  DateTime? _lastStart;
  DateTime? _lastEnd;
  Duration _backoff = Duration.zero;

  /// Ticks that went out, and how many failed (diagnostics, tests).
  int ticks = 0;
  int failures = 0;

  /// Whether [key] is being watched.
  bool isWatching(Object key) => _waiters.containsKey(key);

  /// Whether anything is being watched.
  bool get active => _waiters.isNotEmpty;

  /// Ticks spent on [key] so far.
  int readsFor(Object key) => _waiters[key]?.reads ?? 0;

  /// The current backoff (zero when the last read was good).
  @visibleForTesting
  Duration get backoff => _backoff;

  /// Watches [key], funded at [since]. A key already watched keeps its
  /// count and window.
  void watch(Object key, {required DateTime since}) {
    if (_disposed) return;
    _waiters.putIfAbsent(key, () => _Waiter(since));
    _schedule();
  }

  /// Stops watching [key] (covered, placed, failed, cancelled).
  void unwatch(Object key) {
    _waiters.remove(key);
    if (_waiters.isEmpty) _cancelTimer();
  }

  /// Stops watching every key but [key].
  void retainOnly(Object key) {
    _waiters.removeWhere((k, _) => k != key);
    if (_waiters.isEmpty) _cancelTimer();
  }

  void clear() {
    _waiters.clear();
    _cancelTimer();
  }

  void dispose() {
    _disposed = true;
    clear();
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// The shortest cadence among the waiters still in their window and
  /// under their cap; the others are dropped. Null: nobody to read for.
  Duration? _every(DateTime now) {
    _waiters.removeWhere((_, w) =>
        w.reads >= maxReads ||
        cadenceAt(now.difference(w.since)) == null);
    Duration? every;
    for (final w in _waiters.values) {
      final c = cadenceAt(now.difference(w.since))!;
      if (every == null || c < every) every = c;
    }
    return every;
  }

  void _schedule() {
    if (_disposed || _inFlight || _timer != null) return;
    final now = _clock();
    final every = _every(now);
    if (every == null) return;
    Duration delay;
    final lastEnd = _lastEnd;
    final lastStart = _lastStart;
    if (_backoff > Duration.zero && lastEnd != null) {
      delay = lastEnd.add(_backoff).difference(now);
    } else {
      final byCadence = lastStart == null
          ? Duration.zero
          : lastStart.add(every).difference(now);
      final byGap =
          lastEnd == null ? Duration.zero : lastEnd.add(minGap).difference(now);
      delay = byCadence > byGap ? byCadence : byGap;
    }
    if (delay < Duration.zero) delay = Duration.zero;
    _timer = Timer(delay, _tick);
  }

  Future<void> _tick() async {
    _timer = null;
    if (_disposed) return;
    final now = _clock();
    if (_every(now) == null) return;
    _lastStart = now;
    if (!_canReadNow()) {
      // Backgrounded without grace, or locked: no request, look again at
      // the next cadence step (a timer, no network).
      _schedule();
      return;
    }
    _inFlight = true;
    ticks++;
    for (final w in _waiters.values) {
      w.reads++;
    }
    final pending = read();
    var ended = true;
    try {
      final collateral = await pending.timeout(readTimeout);
      _backoff = Duration.zero;
      if (collateral != null && !_disposed) onRead(collateral);
    } on TimeoutException {
      _fail();
      // The read is still out: the next one waits for it to end.
      ended = false;
      pending.then((_) {}, onError: (Object _) {}).whenComplete(_ended);
    } catch (_) {
      _fail();
    } finally {
      if (ended) _ended();
    }
  }

  void _fail() {
    failures++;
    _backoff = _backoff == Duration.zero
        ? backoffStart
        : Duration(
            milliseconds: math.min(_backoff.inMilliseconds * 2,
                backoffCap.inMilliseconds));
  }

  void _ended() {
    _inFlight = false;
    _lastEnd = _clock();
    _schedule();
  }

  bool _canReadNow() {
    try {
      return _canRead();
    } catch (_) {
      return false;
    }
  }
}
