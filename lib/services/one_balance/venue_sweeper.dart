// lib/services/one_balance/venue_sweeper.dart
//
// The swap-back sweeper: keeps the venues' idle cash at about zero by
// sending it home to Dollars, so the one balance stays true. Runs in
// the app (only the app holds the keys), signs nothing the user has not
// implicitly approved: a sweep is an Orchestra move whose recipient is
// the wallet's own Spark address, made only while the session is
// unlocked, under `SweepAuthorization.automatic` — the same trust level
// as auto-claim (`ClaimAutoFire`), whose shape this copies: one move per
// venue at a time, failures back off 2 → 30 min, a locked session waits.
//
// Everything that touches the app (balances, rails, Hive, analytics)
// goes through [VenueSweeperHost], so the state machine here is tested
// with a fake host and a fake clock. The Riverpod binding lives in
// `lib/providers/venue_sweeper_provider.dart`.
//
// Triggers (the pass runs the same rules whoever asks):
//   close | claim | cancel  — `VenueCashReleased` from the venue services;
//   resume                  — app resume and session unlock;
//   timer                   — the foreground heartbeat and a held batch
//                             coming due or being flushed on background;
//   rollout                 — the one-time migration of existing balances;
//   retry                   — a backoff ending.

import 'dart:async';

import 'package:flutter/foundation.dart'
    show immutable, mapEquals, setEquals, visibleForTesting;
import 'package:kute/models/orchestra_route_limits.dart'
    show RouteQuoteError, RouteQuoteErrorCode;
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/route_minimums.dart'
    show kOneBalanceMinimumUsd;
import 'package:kute/services/one_balance/sweep_rules.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/tracking_service.dart';

/// What the sweeper shows: `waiting` is what each venue still owes back
/// (below the minimum, batching, backing off), `sweeping` the venues a
/// move is running for right now.
@immutable
class VenueSweeperState {
  const VenueSweeperState({
    this.waiting = const <OneBalanceVenue, double>{},
    this.sweeping = const <OneBalanceVenue>{},
  });

  /// Idle venue cash not yet brought home, by venue.
  final Map<OneBalanceVenue, double> waiting;

  /// Venues with a sweep in progress.
  final Set<OneBalanceVenue> sweeping;

  VenueSweeperState copyWith({
    Map<OneBalanceVenue, double>? waiting,
    Set<OneBalanceVenue>? sweeping,
  }) =>
      VenueSweeperState(
        waiting: waiting ?? this.waiting,
        sweeping: sweeping ?? this.sweeping,
      );

  @override
  bool operator ==(Object other) =>
      other is VenueSweeperState &&
      mapEquals(other.waiting, waiting) &&
      setEquals(other.sweeping, sweeping);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(waiting.entries.map((e) => Object.hash(e.key, e.value))),
        Object.hashAllUnordered(sweeping),
      );

  @override
  String toString() =>
      'VenueSweeperState(waiting: $waiting, sweeping: $sweeping)';
}

/// A venue funder that can also bring idle cash home. Predictions binds
/// this; Investing goes through `HyperliquidMoveRail.withdrawToDollars`.
abstract interface class SweepableVenueFunder implements VenueFunder {
  /// Sends [usd] of idle venue cash back to Dollars under [auth].
  /// [purpose] is `sweep` or `rollout_sweep`; the rail derives the quote
  /// `flow` tag from it (`sweep_predictions`, `rollout_sweep_predictions`).
  Future<VenueMoveResult> sweepToDollars({
    required double usd,
    required MoveAuthorization auth,
    String purpose = 'sweep',
  });
}

/// Everything the sweeper needs from the app, behind one seam.
abstract class VenueSweeperHost {
  DateTime now();

  /// The session is unlocked and the lock overlay is down.
  bool get sessionUnlocked;

  /// The spending (hot) wallet's id while it is the active wallet; null
  /// for a Ledger, watch-only or missing wallet. Only this wallet's
  /// venues are ever swept.
  String? get spendingWalletId;

  /// What the app holds about [venue] right now, or null while the venue
  /// has not answered (nothing is decided on a guess).
  Future<VenueSnapshot?> readVenue(OneBalanceVenue venue);

  /// The route minimum for a sweep from [venue], floored.
  Future<double> minimumUsd(OneBalanceVenue venue);

  /// A quote refused [usd] as too small.
  void noteAmountTooSmall(OneBalanceVenue venue, double usd);

  /// Readies the rail for a move (a no-op for both rails today).
  Future<void> prepare(OneBalanceVenue venue);

  /// Sends [usd] from [venue] home. Throws [RouteUnavailable] when the
  /// rail cannot carry it, [RouteQuoteError] when the quote refuses it.
  Future<VenueMoveResult> send(
    OneBalanceVenue venue, {
    required double usd,
    required String purpose,
  });

  /// The one-time rollout flag for [walletId].
  bool rolloutDone(String walletId);
  void markRolloutDone(String walletId);

  /// Once per order and outcome (`claimOrderTerminalAnalytics`).
  bool claimTerminal(String orderId, {required bool success});

  void track(String event, Map<String, Object> params);
}

/// Longest a submitted sweep is watched for its terminal status.
const Duration kSweepWatchMax = Duration(minutes: 30);

/// How long a just-swept amount is subtracted from the venue's idle
/// figure, until the venue's own read catches up.
const Duration kSweepSettleLag = Duration(minutes: 2);

const Duration _kBackoffFirst = Duration(minutes: 2);
const Duration _kBackoffMax = Duration(minutes: 30);

/// The three event triggers the rate limit yields to.
const Set<String> kSweepEventTriggers = {'close', 'claim', 'cancel'};

class _VenueMemory {
  DateTime? backoffUntil;
  Duration? backoff;
  DateTime? lastSweepAt;
  DateTime? heldSince;
  double? waitingShownUsd;
  SweepSkipReason? lastSkip;
  bool failureReported = false;
  double recentlySweptUsd = 0;
  DateTime? recentlySweptAt;
}

class _OpenSweep {
  _OpenSweep({
    required this.venue,
    required this.usd,
    required this.trigger,
    required this.startedAt,
  });

  final OneBalanceVenue venue;
  final double usd;
  final String trigger;
  final DateTime startedAt;
}

class VenueSweeper {
  VenueSweeper(this._host, {void Function(VenueSweeperState)? onState})
      : _onState = onState;

  final VenueSweeperHost _host;
  final void Function(VenueSweeperState)? _onState;

  final Map<OneBalanceVenue, _VenueMemory> _memory = {
    for (final v in OneBalanceVenue.values) v: _VenueMemory(),
  };
  final Set<OneBalanceVenue> _inFlight = {};
  final Map<String, _OpenSweep> _openSweeps = {};
  final Map<OneBalanceVenue, double> _waiting = {};

  bool _passing = false;
  String? _rerunReason;
  OneBalanceVenue? _rerunVenue;
  bool _rerunFlush = false;
  bool _disposed = false;

  VenueSweeperState _state = const VenueSweeperState();

  VenueSweeperState get state => _state;

  /// Sweeps the sweeper itself may still be watching for completion.
  @visibleForTesting
  int get openSweepCount => _openSweeps.length;

  void dispose() {
    _disposed = true;
  }

  /// Asks for a pass now. [reason] is a `VenueCashReleased` label or one
  /// of the trigger names; [venue] narrows an event to the venue that
  /// released the cash (the other venue is read anyway, cheaply, so a
  /// held batch there can still come due).
  Future<void> trigger(String reason,
      {OneBalanceVenue? venue, bool flushHeld = false}) async {
    if (_disposed) return;
    final trigger = normalizeTrigger(reason);
    if (_passing) {
      // One pass at a time; remember the strongest ask for the rerun.
      _rerunReason = _mergeTrigger(_rerunReason, trigger);
      _rerunVenue = venue == _rerunVenue ? venue : null;
      _rerunFlush = _rerunFlush || flushHeld;
      return;
    }
    _passing = true;
    try {
      await _pass(trigger, venue: venue, flushHeld: flushHeld);
      while (_rerunReason != null && !_disposed) {
        final next = _rerunReason!;
        final nextVenue = _rerunVenue;
        final nextFlush = _rerunFlush;
        _rerunReason = null;
        _rerunVenue = null;
        _rerunFlush = false;
        await _pass(next, venue: nextVenue, flushHeld: nextFlush);
      }
    } finally {
      _passing = false;
    }
  }

  /// The app is leaving the foreground: held batches sweep now.
  Future<void> onAppPaused() => trigger('timer', flushHeld: true);

  /// The Orchestra rows moved: settle any sweep this instance submitted.
  void noteOrders(Iterable<SwapOrder> rows) {
    if (_openSweeps.isEmpty) return;
    final now = _host.now();
    for (final row in rows) {
      final open = _openSweeps[row.id];
      if (open == null) continue;
      if (row.isComplete) {
        _openSweeps.remove(row.id);
        if (_host.claimTerminal(row.id, success: true)) {
          _host.track('venue_sweep_completed', {
            'venue': open.venue.analyticsName,
            'amount_usd': _usd(open.usd),
            'duration_ms': now.difference(open.startedAt).inMilliseconds,
            'trigger': open.trigger,
          });
        }
      } else if (!row.isPending) {
        _openSweeps.remove(row.id);
        if (_host.claimTerminal(row.id, success: false)) {
          _host.track('venue_sweep_failed', {
            'venue': open.venue.analyticsName,
            'stage': 'settle',
            'error_category': row.status,
            'trigger': open.trigger,
          });
        }
      }
    }
    _openSweeps.removeWhere(
        (_, open) => now.difference(open.startedAt) > kSweepWatchMax);
  }

  /// When the next pass is due on its own (a backoff ending, a held batch
  /// coming due), or null when nothing is scheduled.
  Duration? nextDueIn() {
    final now = _host.now();
    Duration? best;
    void consider(DateTime? at) {
      if (at == null) return;
      final d = at.difference(now);
      final wait = d.isNegative ? Duration.zero : d;
      if (best == null || wait < best!) best = wait;
    }

    for (final m in _memory.values) {
      consider(m.backoffUntil);
      final held = m.heldSince;
      if (held != null) consider(held.add(kSweepHoldMax));
    }
    return best;
  }

  /// Whether the next due pass is a backoff retry (else a batch coming
  /// due): decides the trigger name the host uses for it.
  bool nextDueIsRetry() {
    final now = _host.now();
    DateTime? retryAt;
    DateTime? holdAt;
    for (final m in _memory.values) {
      final b = m.backoffUntil;
      if (b != null && (retryAt == null || b.isBefore(retryAt))) retryAt = b;
      final h = m.heldSince;
      if (h != null) {
        final due = h.add(kSweepHoldMax);
        if (holdAt == null || due.isBefore(holdAt)) holdAt = due;
      }
    }
    if (retryAt == null) return false;
    if (holdAt == null) return true;
    return !retryAt.isAfter(holdAt) || retryAt.isBefore(now);
  }

  // ───────────────────────────── passes ─────────────────────────────

  Future<void> _pass(String trigger,
      {OneBalanceVenue? venue, bool flushHeld = false}) async {
    final wallet = _host.spendingWalletId;
    final unlocked = _host.sessionUnlocked;
    if (wallet != null && unlocked && !_host.rolloutDone(wallet)) {
      await _rolloutPass(wallet);
      return;
    }
    final order = venue == null
        ? OneBalanceVenue.values
        : [venue, ...OneBalanceVenue.values.where((v) => v != venue)];
    for (final v in order) {
      if (_disposed) return;
      await _sweepVenue(v,
          trigger: trigger,
          eventDriven: kSweepEventTriggers.contains(trigger) && v == venue,
          flushHeld: flushHeld);
    }
  }

  /// First unlocked run after the update: both venues, open positions and
  /// orders untouched, under the same rules. Idempotent: the flag is set
  /// only once both venues have answered, so a restart mid-way runs it
  /// again and a second run finds nothing idle.
  Future<void> _rolloutPass(String walletId) async {
    var allKnown = true;
    for (final v in [OneBalanceVenue.investing, OneBalanceVenue.predictions]) {
      if (_disposed) return;
      final known = await _sweepVenue(v,
          trigger: 'rollout',
          eventDriven: true,
          flushHeld: true,
          rollout: true);
      allKnown = allKnown && known;
    }
    if (allKnown && !_disposed) _host.markRolloutDone(walletId);
  }

  /// Runs the rules for [venue] and acts on them. Returns whether the
  /// venue had answered (a snapshot existed).
  Future<bool> _sweepVenue(
    OneBalanceVenue venue, {
    required String trigger,
    required bool eventDriven,
    required bool flushHeld,
    bool rollout = false,
  }) async {
    if (_inFlight.contains(venue)) return true;
    final m = _memory[venue]!;
    final wallet = _host.spendingWalletId;
    final unlocked = _host.sessionUnlocked;

    // Reading is the app's own held state, safe at any lock state; the
    // rules decide. The minimum (a network read) waits for an unlocked
    // owner.
    final raw = await _host.readVenue(venue);
    if (raw == null) return false;
    final minimum = wallet != null && unlocked
        ? await _host.minimumUsd(venue)
        : kOneBalanceMinimumUsd;
    final snapshot = _discountRecentSweep(raw, m);

    final now = _host.now();
    final decision = decideSweep(
      snapshot,
      SweepContext(
        now: now,
        minimumUsd: minimum,
        sessionUnlocked: unlocked,
        spendingWalletActive: wallet != null,
        backoffUntil: m.backoffUntil,
        lastSweepAt: m.lastSweepAt,
        heldSince: m.heldSince,
        eventDriven: eventDriven || rollout,
        flushHeld: flushHeld,
      ),
    );

    switch (decision) {
      case SweepNothing():
        m.heldSince = null;
        m.lastSkip = null;
        _endWaitingEpisode(m);
        _setWaiting(venue, null);
      case SweepSkip(:final reason, :final idleUsd):
        _endWaitingEpisode(m);
        if (reason != SweepSkipReason.backoff) m.heldSince = null;
        // Backed-off cash stays visible: a failed swap-back never
        // vanishes into a hidden venue balance.
        _setWaiting(venue, reason == SweepSkipReason.backoff ? idleUsd : null);
        if (m.lastSkip != reason) {
          m.lastSkip = reason;
          _host.track('venue_sweep_skipped', {
            'venue': venue.analyticsName,
            'reason': reason.label,
            'idle_usd': _usd(idleUsd),
          });
        }
      case SweepWaiting(:final usd, :final cause):
        if (cause != SweepWaitingCause.belowMinimum) m.lastSkip = null;
        _setWaiting(venue, usd);
        if (cause == SweepWaitingCause.batching) {
          m.heldSince ??= now;
        } else {
          m.heldSince = null;
        }
        if (cause == SweepWaitingCause.belowMinimum) {
          if (m.waitingShownUsd == null) {
            m.waitingShownUsd = usd;
            _host.track('venue_cash_waiting_shown', {
              'venue': venue.analyticsName,
              'amount_usd': _usd(usd),
              'minimum_usd': _usd(minimum),
            });
          }
          if (m.lastSkip != SweepSkipReason.belowMinimum) {
            m.lastSkip = SweepSkipReason.belowMinimum;
            _host.track('venue_sweep_skipped', {
              'venue': venue.analyticsName,
              'reason': SweepSkipReason.belowMinimum.label,
              'idle_usd': _usd(snapshot.idleUsd),
            });
          }
        } else {
          _endWaitingEpisode(m);
        }
      case SweepNow(:final usd):
        m.lastSkip = null;
        m.heldSince = null;
        _endWaitingEpisode(m);
        await _execute(venue,
            usd: usd,
            idleUsd: snapshot.idleUsd,
            trigger: trigger,
            rollout: rollout);
    }
    return true;
  }

  Future<void> _execute(
    OneBalanceVenue venue, {
    required double usd,
    required double idleUsd,
    required String trigger,
    required bool rollout,
  }) async {
    final m = _memory[venue]!;
    _inFlight.add(venue);
    _publish();
    final startedAt = _host.now();
    _host.track('venue_sweep_started', {
      'venue': venue.analyticsName,
      'trigger': trigger,
      'amount_usd': _usd(usd),
      'idle_usd': _usd(idleUsd),
      'wallet_kind': 'hot',
    });
    var stage = 'fund';
    try {
      await _host.prepare(venue);
      // The lock may have dropped during the prepare: never send locked.
      if (!_host.sessionUnlocked || _host.spendingWalletId == null) {
        throw StateError('session locked during sweep');
      }
      final result = await _host.send(venue,
          usd: usd, purpose: rollout ? 'rollout_sweep' : 'sweep');
      final sentAt = _host.now();
      m.lastSweepAt = sentAt;
      m.backoff = null;
      m.backoffUntil = null;
      m.failureReported = false;
      m.recentlySweptUsd = result.sentUsd;
      m.recentlySweptAt = sentAt;
      _setWaiting(venue, _remaining(idleUsd, result.sentUsd));
      _host.track('venue_sweep_submitted', {
        'venue': venue.analyticsName,
        'amount_usd': _usd(result.sentUsd),
        'quote_id': TrackingService.orderRef(result.quoteId),
      });
      stage = 'settle';
      final orderId = result.orderId ?? await result.registration;
      if (orderId != null && orderId.isNotEmpty) {
        _openSweeps[orderId] = _OpenSweep(
            venue: venue,
            usd: result.sentUsd,
            trigger: trigger,
            startedAt: startedAt);
      }
    } on RouteQuoteError catch (e) {
      if (e.code == RouteQuoteErrorCode.amountTooSmall) {
        // The route's real floor is above what we tried: show it as
        // waiting and let the next pass compare against the raised
        // minimum. No backoff — more cash changes the answer.
        _host.noteAmountTooSmall(venue, usd);
        _setWaiting(venue, idleUsd);
        _fail(venue,
            stage: 'quote',
            category: e.code.code,
            trigger: trigger,
            backoff: false);
      } else {
        _setWaiting(venue, idleUsd);
        _fail(venue, stage: 'quote', category: e.code.code, trigger: trigger);
      }
    } on RouteUnavailable {
      // The rail cannot carry a withdraw right now (Orchestra refusing the
      // HyperCore-source route, a paused route): the cash is simply
      // waiting, shown as unavailable until balancing completes. No error
      // UI; a backoff keeps the passes from hammering the rail.
      _setWaiting(venue, idleUsd);
      _fail(venue,
          stage: stage, category: 'route_unavailable', trigger: trigger);
    } catch (e) {
      _setWaiting(venue, idleUsd);
      _fail(venue,
          stage: stage,
          category: TrackingService.errorCategory(e),
          trigger: trigger);
    } finally {
      _inFlight.remove(venue);
      _publish();
    }
  }

  void _fail(
    OneBalanceVenue venue, {
    required String stage,
    required String category,
    required String trigger,
    bool backoff = true,
  }) {
    final m = _memory[venue]!;
    if (backoff) {
      final cur = m.backoff ?? _kBackoffFirst;
      m.backoffUntil = _host.now().add(cur);
      final doubled = cur * 2;
      m.backoff = doubled > _kBackoffMax ? _kBackoffMax : doubled;
    }
    // A backoff retry is the same failure, not a new one: reported once
    // per episode, like auto-claim.
    if (m.failureReported) return;
    m.failureReported = true;
    _host.track('venue_sweep_failed', {
      'venue': venue.analyticsName,
      'stage': stage,
      'error_category': category,
      'trigger': trigger,
    });
  }

  // ───────────────────────────── helpers ─────────────────────────────

  /// Until the venue's own read reflects a sweep that just left, its
  /// idle figure still includes the money: subtract it so the header
  /// does not count it twice (waiting + coming back).
  VenueSnapshot _discountRecentSweep(VenueSnapshot s, _VenueMemory m) {
    final at = m.recentlySweptAt;
    if (at == null) return s;
    if (_host.now().difference(at) > kSweepSettleLag) {
      m.recentlySweptAt = null;
      m.recentlySweptUsd = 0;
      return s;
    }
    final idle = _remaining(s.idleUsd, m.recentlySweptUsd);
    final sweepable = _remaining(s.sweepableUsd, m.recentlySweptUsd);
    return VenueSnapshot(
      idleUsd: idle,
      sweepableUsd: sweepable,
      hasReservations: s.hasReservations,
      hasPendingMove: s.hasPendingMove,
      lastDepositSettledAt: s.lastDepositSettledAt,
      hasPendingIntent: s.hasPendingIntent,
      isPlacing: s.isPlacing,
      hasOpenTwap: s.hasOpenTwap,
      isClaiming: s.isClaiming,
    );
  }

  static double _remaining(double total, double taken) {
    final left = total - taken;
    return left.isFinite && left > kSweepDustUsd ? left : 0;
  }

  void _endWaitingEpisode(_VenueMemory m) {
    m.waitingShownUsd = null;
  }

  void _setWaiting(OneBalanceVenue venue, double? usd) {
    if (usd == null || !usd.isFinite || usd < kSweepDustUsd) {
      if (_waiting.remove(venue) != null) _publish();
      return;
    }
    if (_waiting[venue] == usd) return;
    _waiting[venue] = usd;
    _publish();
  }

  void _publish() {
    final next = VenueSweeperState(
      waiting: Map.unmodifiable(_waiting),
      sweeping: Set.unmodifiable(_inFlight),
    );
    if (next == _state) return;
    _state = next;
    if (!_disposed) _onState?.call(next);
  }

  static double _usd(double v) =>
      v.isFinite && v > 0 ? (v * 100).roundToDouble() / 100 : 0;

  static String _mergeTrigger(String? current, String next) {
    if (current == null) return next;
    // An event trigger outranks a heartbeat: it lifts the rate limit.
    if (kSweepEventTriggers.contains(current)) return current;
    return next;
  }

  /// Maps a `VenueCashReleased` reason (`position_closed`,
  /// `market_resolved`, `order_cancelled`, …) or a trigger name onto the
  /// analytics trigger set. Unknown names pass through.
  static String normalizeTrigger(String reason) {
    final r = reason.trim().toLowerCase();
    if (const {
      'close',
      'claim',
      'cancel',
      'resume',
      'timer',
      'rollout',
      'retry'
    }.contains(r)) {
      return r;
    }
    if (r.contains('cancel')) return 'cancel';
    if (r.contains('resolve') || r.contains('claim') || r.contains('redeem')) {
      return 'claim';
    }
    if (r.contains('close') || r.contains('sold') || r.contains('sell')) {
      return 'close';
    }
    if (r.contains('resume') || r.contains('unlock') || r == 'manual') {
      return 'resume';
    }
    return r;
  }
}
