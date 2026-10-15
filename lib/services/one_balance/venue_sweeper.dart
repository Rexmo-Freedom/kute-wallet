// lib/services/one_balance/venue_sweeper.dart
//
// The swap-back sweeper: keeps the venues' idle cash at about zero by
// sending it home to Dollars, so the one balance stays true. Runs in
// the app (only the app holds the keys), signs nothing the user has not
// implicitly approved: a sweep is an Orchestra move whose recipient is
// the wallet's own Spark address, made only while the session is
// unlocked, under `SweepAuthorization.automatic` — the same trust level
// as auto-claim (`ClaimAutoFire`), whose shape this copies: one move per
// venue at a time, failures back off 2 → 30 min (a rail that cannot carry
// the move, `RouteUnavailable`, 2 → 10 min: it turns ready server-side,
// and its cash must not wait half an hour after), a locked session waits.
// Coming back to the foreground retries a backed-off venue at once (at
// most once a minute); an app restart starts the ladder afresh.
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
//   retry                   — a backoff ending;
//   manual_rebalance        — the Portfolio's Rebalance ([VenueSweeper.sweepNow]):
//                             every venue now, the idle wait set aside,
//                             every other rule kept.
//
// Automatic sweeping is OFF ([kVenueAutoSweepEnabled]; founder decision,
// 2026-10-15): venue cash stays where it is until the person taps
// Rebalance. Every trigger above but `manual_rebalance` then only reads
// and classifies the venues ([VenueSweeper.preview]), so the header and
// the Portfolio stay current; nothing is sent, nothing is reported.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show
        debugPrint,
        immutable,
        kDebugMode,
        mapEquals,
        setEquals,
        visibleForTesting;
import 'package:kute/models/orchestra_route_limits.dart'
    show RouteQuoteError, RouteQuoteErrorCode;
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/route_minimums.dart'
    show kOneBalanceMinimumUsd;
import 'package:kute/services/one_balance/sweep_rules.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/tracking_service.dart';

/// Whether the sweeper moves venue cash home on its own: the 24 h idle
/// sweep, the heartbeat, event and resume passes, backoff retries and the
/// first-boot rollout pass.
///
/// Off by founder decision (2026-10-15): "maybe we should not run this
/// 24 h sweep. just leave it, leave it manual i think. do not do it on
/// first boot also". Venue cash stays at the venue, Available, until the
/// person taps Rebalance ([VenueSweeper.sweepNow], which works as before).
/// With it off a trigger only reads and classifies the venues
/// ([VenueSweeper.preview]); nothing is ever shown as waiting for a pass
/// that will not run. The machinery stays: true brings it all back.
const bool kVenueAutoSweepEnabled = false;

/// What the sweeper shows: `waiting` is what each venue still owes back
/// (batching, backing off, a rail not ready), `dust` the venue cash below
/// the route minimum that no sweep can move (counted, never shown as
/// waiting), `sweeping` the venues a move is running for right now. A
/// venue is in at most one of `waiting` and `dust`.
@immutable
class VenueSweeperState {
  const VenueSweeperState({
    this.waiting = const <OneBalanceVenue, double>{},
    this.dust = const <OneBalanceVenue, double>{},
    this.sweeping = const <OneBalanceVenue>{},
    this.held = const <OneBalanceVenue, double>{},
    this.movable = const <OneBalanceVenue, double>{},
    this.belowMinimum = const <OneBalanceVenue, double>{},
  });

  /// What a Rebalance ([VenueSweeper.sweepNow]) would send home from each
  /// venue right now, as the last read of the venues saw it (a pass, or
  /// [VenueSweeper.preview] when the Portfolio opens): the rules with the
  /// idle wait set aside, at or above the route minimum. Empty when
  /// nothing could move.
  final Map<OneBalanceVenue, double> movable;

  /// Venue cash a Rebalance would leave where it is because it is below
  /// the route minimum, under the same rules as [movable]: the Portfolio
  /// says so instead of hiding its Rebalance without a word.
  final Map<OneBalanceVenue, double> belowMinimum;

  /// Idle venue cash a venue in use keeps (the idle rule, both venues):
  /// the person's Available money, drawn on by orders and sends, never
  /// "waiting" or "moving".
  final Map<OneBalanceVenue, double> held;

  /// Idle venue cash not yet brought home, by venue.
  final Map<OneBalanceVenue, double> waiting;

  /// Idle venue cash below the route minimum, by venue: still the user's
  /// money at the venue, but nothing is on its way.
  final Map<OneBalanceVenue, double> dust;

  /// Venues with a sweep in progress.
  final Set<OneBalanceVenue> sweeping;

  VenueSweeperState copyWith({
    Map<OneBalanceVenue, double>? waiting,
    Map<OneBalanceVenue, double>? dust,
    Set<OneBalanceVenue>? sweeping,
    Map<OneBalanceVenue, double>? held,
    Map<OneBalanceVenue, double>? movable,
    Map<OneBalanceVenue, double>? belowMinimum,
  }) =>
      VenueSweeperState(
        waiting: waiting ?? this.waiting,
        dust: dust ?? this.dust,
        sweeping: sweeping ?? this.sweeping,
        held: held ?? this.held,
        movable: movable ?? this.movable,
        belowMinimum: belowMinimum ?? this.belowMinimum,
      );

  @override
  bool operator ==(Object other) =>
      other is VenueSweeperState &&
      mapEquals(other.waiting, waiting) &&
      mapEquals(other.dust, dust) &&
      mapEquals(other.held, held) &&
      mapEquals(other.movable, movable) &&
      mapEquals(other.belowMinimum, belowMinimum) &&
      setEquals(other.sweeping, sweeping);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(waiting.entries.map((e) => Object.hash(e.key, e.value))),
        Object.hashAll(dust.entries.map((e) => Object.hash(e.key, e.value))),
        Object.hashAll(held.entries.map((e) => Object.hash(e.key, e.value))),
        Object.hashAll(movable.entries.map((e) => Object.hash(e.key, e.value))),
        Object.hashAll(
            belowMinimum.entries.map((e) => Object.hash(e.key, e.value))),
        Object.hashAllUnordered(sweeping),
      );

  @override
  String toString() =>
      'VenueSweeperState(waiting: $waiting, dust: $dust, held: $held, '
      'movable: $movable, belowMinimum: $belowMinimum, sweeping: $sweeping)';
}

/// What a pass did with one venue, as the Portfolio's Rebalance reports it.
enum RebalanceOutcomeKind {
  /// A move home was submitted ([RebalanceOutcome.usd] sent).
  moving,

  /// A move from this venue was already on its way.
  alreadyMoving,

  /// No cash at the venue.
  nothing,

  /// Below the smallest move the route takes (dust).
  belowMinimum,

  /// A never-sweep rule holds it ([RebalanceOutcome.reason]).
  held,

  /// The rail could not take it now, or the move failed. With automatic
  /// sweeping on the sweeper retries on its own (its backoff); off, the
  /// cash stays Available at the venue until the next Rebalance.
  notNow,

  /// The venue has not answered yet.
  unknown,
}

/// One venue's [RebalanceOutcomeKind], with the amount sent or left.
@immutable
class RebalanceOutcome {
  const RebalanceOutcome(this.kind, {this.usd = 0, this.reason, this.ref});

  final RebalanceOutcomeKind kind;

  /// What was sent ([RebalanceOutcomeKind.moving]) or what stayed.
  final double usd;

  /// Why it stayed, for [RebalanceOutcomeKind.held].
  final SweepSkipReason? reason;

  /// The move's settlement operation (else its quote), which its Activity
  /// row carries, for a [RebalanceOutcomeKind.moving]: the Portfolio's
  /// step for the venue follows that row. Local only, never tracked; not
  /// part of the outcome's identity.
  final String? ref;

  @override
  bool operator ==(Object other) =>
      other is RebalanceOutcome &&
      other.kind == kind &&
      other.usd == usd &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(kind, usd, reason);

  @override
  String toString() => 'RebalanceOutcome(${kind.name}, $usd, ${reason?.name})';
}

/// The analytics trigger of the Portfolio's Rebalance.
const String kManualRebalanceTrigger = 'manual_rebalance';

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

  /// [readVenue] for a Rebalance, which sets the idle wait aside: what the
  /// held state leaves unknown and the idle rule used to stand guard over
  /// (an order resting at Investing) is read from the venue, an
  /// unreadable answer holding the cash.
  Future<VenueSnapshot?> readVenueForRebalance(OneBalanceVenue venue) =>
      readVenue(venue);

  /// The route minimum for a sweep from [venue], floored.
  Future<double> minimumUsd(OneBalanceVenue venue);

  /// [minimumUsd] for [VenueSweeper.preview], which must not wait on the
  /// network when the answer is already known: the last minimum read this
  /// session when there is one (refreshed behind it), else a read.
  Future<double> previewMinimumUsd(OneBalanceVenue venue) => minimumUsd(venue);

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

/// The longest wait after a `RouteUnavailable`: the rail (Orchestra's
/// route, the CCTP fallback's fee terms) turns ready on the server, so the
/// venue's cash retries at least this often until it moves.
const Duration kSweepRouteBackoffMax = Duration(minutes: 10);

/// A `resume` (the app back in the foreground, the session unlocked)
/// retries a backed-off venue now, once its last failure is this old, so
/// quick app switches never hammer the rail.
const Duration kSweepResumeRetryAfter = Duration(minutes: 1);

/// The three event triggers the rate limit yields to.
const Set<String> kSweepEventTriggers = {'close', 'claim', 'cancel'};

class _VenueMemory {
  DateTime? backoffUntil;
  Duration? backoff;
  DateTime? lastFailureAt;
  DateTime? lastSweepAt;
  DateTime? heldSince;
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
  VenueSweeper(
    this._host, {
    void Function(VenueSweeperState)? onState,
    this.autoSweep = kVenueAutoSweepEnabled,
  }) : _onState = onState;

  final VenueSweeperHost _host;
  final void Function(VenueSweeperState)? _onState;

  /// Whether venue cash goes home on its own ([kVenueAutoSweepEnabled];
  /// a parameter so the tests can still drive the automatic machinery).
  final bool autoSweep;

  final Map<OneBalanceVenue, _VenueMemory> _memory = {
    for (final v in OneBalanceVenue.values) v: _VenueMemory(),
  };
  final Set<OneBalanceVenue> _inFlight = {};
  final Map<String, _OpenSweep> _openSweeps = {};
  final Map<OneBalanceVenue, double> _waiting = {};
  final Map<OneBalanceVenue, double> _dust = {};
  final Map<OneBalanceVenue, double> _held = {};
  final Map<OneBalanceVenue, double> _movable = {};
  final Map<OneBalanceVenue, double> _belowMinimum = {};

  /// Moves started per venue: a [preview] that read a venue before a move
  /// left it does not record what it read.
  final Map<OneBalanceVenue, int> _sends = {};

  /// When each held venue last saw activity: its idle window ends
  /// [kVenueIdleSweepAfter] later, a pass of its own ([nextDueIn]).
  final Map<OneBalanceVenue, DateTime> _activeAt = {};

  bool _passing = false;
  Completer<void>? _passDone;
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
    if (!autoSweep) {
      // No pass of its own (founder decision, 2026-10-15): the venues
      // are read and classified, as the Portfolio's preview does, so the
      // header follows them. Nothing is sent or reported, no backoff is
      // lifted, the rollout never runs.
      await preview();
      return;
    }
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
      await _runReruns();
    } finally {
      _endPass();
    }
  }

  Future<void> _runReruns() async {
    while (_rerunReason != null && !_disposed) {
      final next = _rerunReason!;
      final nextVenue = _rerunVenue;
      final nextFlush = _rerunFlush;
      _rerunReason = null;
      _rerunVenue = null;
      _rerunFlush = false;
      await _pass(next, venue: nextVenue, flushHeld: nextFlush);
    }
  }

  void _endPass() {
    _passing = false;
    final done = _passDone;
    _passDone = null;
    done?.complete();
  }

  /// The Portfolio's Rebalance: every venue's movable cash home now, under
  /// the same rules, rails, authorization (`SweepAuthorization.automatic`:
  /// the wallet's own Spark address only, unlocked session only) and
  /// events as any pass, named [trigger]. [ignoreIdle] sets aside the 24 h
  /// idle wait (an Investing cross position or resting order still holds
  /// the cash); [flushHeld] sends a small amount without waiting for more.
  /// A backoff at least a minute old is lifted, as on a resume.
  ///
  /// One pass at a time: a pass already running is waited for, and a move
  /// in flight is never doubled (that venue reports
  /// [RebalanceOutcomeKind.alreadyMoving]). Returns what happened at each
  /// venue.
  Future<Map<OneBalanceVenue, RebalanceOutcome>> sweepNow({
    String trigger = kManualRebalanceTrigger,
    bool flushHeld = true,
    bool ignoreIdle = true,
  }) async {
    while (_passing && !_disposed) {
      await (_passDone ??= Completer<void>()).future;
    }
    if (_disposed) return const {};
    _passing = true;
    try {
      _liftBackoffsOnResume();
      // Both venues at once: Investing's move (its CCTP leg can take
      // minutes) no longer holds Predictions' back. Nothing the two share
      // needs a lock: each venue's pass reads and writes only its own
      // entries (its memory, its in-flight mark, its send count, its
      // buckets), the host's reads and rails are per venue, and the one
      // pass at a time rule above still keeps every other pass out until
      // both are done.
      const venues = [OneBalanceVenue.investing, OneBalanceVenue.predictions];
      final results = await Future.wait([
        for (final v in venues)
          _sweepVenue(v,
              trigger: trigger,
              eventDriven: true,
              flushHeld: flushHeld,
              ignoreIdle: ignoreIdle,
              manual: true),
      ]);
      final out = <OneBalanceVenue, RebalanceOutcome>{
        for (var i = 0; i < venues.length; i++) venues[i]: results[i],
      };
      await _runReruns();
      return out;
    } finally {
      _endPass();
    }
  }

  /// The app is leaving the foreground: held batches sweep now (nothing
  /// while automatic sweeping is off: there are no held batches to flush).
  Future<void> onAppPaused() async {
    if (!autoSweep) return;
    await trigger('timer', flushHeld: true);
  }

  /// The venues as they are now, read and classified without a pass, for
  /// the Portfolio: it calls this as it opens and whenever a venue's
  /// figures move, so its balances and its Rebalance never wait on the
  /// sweeper's schedule (the 3-minute heartbeat, an event, a resume).
  ///
  /// The same reads (the Rebalance's: an Investing order resting at the
  /// venue is resolved there), the same minimum (the session's last read
  /// when there is one) and the same rules as a pass record the venue
  /// cash a pass would record (held, dust, waiting; cash a pass would send
  /// now counts as waiting until it does) and what a Rebalance would do
  /// ([VenueSweeperState.movable], [VenueSweeperState.belowMinimum]).
  /// Nothing is sent, nothing is reported, no pass is waited for, and the
  /// rules' memory (backoff, batching, rate limit, skips) is left as is. A venue with a move running, or one a move
  /// started for while it was read, is left to the pass. Venues are read
  /// side by side.
  Future<void> preview() async {
    if (_disposed) return;
    final wallet = _host.spendingWalletId;
    final unlocked = _host.sessionUnlocked;
    await Future.wait([
      for (final venue in OneBalanceVenue.values)
        _previewVenue(venue, wallet: wallet, unlocked: unlocked),
    ]);
  }

  Future<void> _previewVenue(OneBalanceVenue venue,
      {required String? wallet, required bool unlocked}) async {
    final sends = _sends[venue] ?? 0;
    bool moved() =>
        _disposed || _inFlight.contains(venue) || (_sends[venue] ?? 0) != sends;
    if (moved()) return;
    final VenueSnapshot? raw;
    final double minimum;
    try {
      (raw, minimum) = await (
        _host.readVenueForRebalance(venue),
        wallet != null && unlocked
            ? _host.previewMinimumUsd(venue)
            : Future.value(kOneBalanceMinimumUsd),
      ).wait;
    } catch (_) {
      return; // the next pass, or the next preview, reads it again
    }
    if (moved()) return;
    if (raw == null) {
      _setRebalancePreview(venue, null);
      return;
    }
    final m = _memory[venue]!;
    final snapshot = _discountRecentSweep(raw, m);
    final now = _host.now();
    SweepContext rules({required bool rebalance}) => _context(m,
        now: now,
        minimum: minimum,
        unlocked: unlocked,
        wallet: wallet,
        rebalance: rebalance,
        eventDriven: false,
        flushHeld: false,
        ignoreIdle: false,
        idleRule: snapshot.lastActivityAt != null);
    switch (decideSweep(snapshot, rules(rebalance: false))) {
      case SweepNothing():
        _setWaiting(venue, null);
      case SweepDust(:final usd):
        _setDust(venue, usd);
      case SweepSkip(:final reason, :final idleUsd):
        _recordSkip(venue, reason, idleUsd, snapshot);
      case SweepWaiting(:final usd):
        _setWaiting(venue, usd);
      case SweepNow(:final usd):
        // Owed back: the next pass sends it.
        _setWaiting(venue, usd);
    }
    _setRebalancePreview(venue, decideSweep(snapshot, rules(rebalance: true)));
  }

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
    // Nothing comes due on its own while automatic sweeping is off.
    if (!autoSweep) return null;
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
    // A held venue's idle window running out.
    if (kVenueIdleSweepEnabled) {
      for (final e in _activeAt.entries) {
        if (_held.containsKey(e.key)) {
          consider(e.value.add(kVenueIdleSweepAfter));
        }
      }
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
    if (trigger == 'resume') _liftBackoffsOnResume();
    if (wallet != null && unlocked && !_host.rolloutDone(wallet)) {
      await _rolloutPass(wallet);
      return;
    }
    if (_disposed) return;
    // Every venue at once, as a Rebalance: their passes share nothing.
    await Future.wait([
      for (final v in OneBalanceVenue.values)
        _sweepVenue(v,
            trigger: trigger,
            eventDriven: kSweepEventTriggers.contains(trigger) && v == venue,
            flushHeld: flushHeld),
    ]);
  }

  /// Back in the foreground: a venue backing off after a failure at least
  /// [kSweepResumeRetryAfter] old is tried again in this pass. The ladder
  /// is kept, so a failure again waits the next step.
  void _liftBackoffsOnResume() {
    final now = _host.now();
    for (final m in _memory.values) {
      final failedAt = m.lastFailureAt;
      if (m.backoffUntil == null || failedAt == null) continue;
      if (now.difference(failedAt) >= kSweepResumeRetryAfter) {
        m.backoffUntil = null;
      }
    }
  }

  /// First unlocked run after the update: both venues, open positions and
  /// orders untouched, under the same rules. Idempotent: the flag is set
  /// only once both venues have answered, so a restart mid-way runs it
  /// again and a second run finds nothing idle.
  Future<void> _rolloutPass(String walletId) async {
    if (_disposed) return;
    // Both venues at once, as a Rebalance: their passes share nothing.
    final outcomes = await Future.wait([
      for (final v in const [
        OneBalanceVenue.investing,
        OneBalanceVenue.predictions,
      ])
        _sweepVenue(v,
            trigger: 'rollout',
            eventDriven: true,
            flushHeld: true,
            rollout: true),
    ]);
    final allKnown =
        outcomes.every((o) => o.kind != RebalanceOutcomeKind.unknown);
    if (allKnown && !_disposed) _host.markRolloutDone(walletId);
  }

  /// Runs the rules for [venue] and acts on them. Returns what happened
  /// ([RebalanceOutcomeKind.unknown] when the venue had not answered).
  /// [manual] is the Portfolio's Rebalance: each venue's outcome is
  /// reported once per tap, with its trigger.
  Future<RebalanceOutcome> _sweepVenue(
    OneBalanceVenue venue, {
    required String trigger,
    required bool eventDriven,
    required bool flushHeld,
    bool rollout = false,
    bool ignoreIdle = false,
    bool manual = false,
  }) async {
    if (_inFlight.contains(venue)) {
      return const RebalanceOutcome(RebalanceOutcomeKind.alreadyMoving);
    }
    final m = _memory[venue]!;
    final wallet = _host.spendingWalletId;
    final unlocked = _host.sessionUnlocked;

    // Reading is the app's own held state, safe at any lock state; the
    // rules decide. The minimum (a network read) waits for an unlocked
    // owner.
    final raw = manual
        ? await _host.readVenueForRebalance(venue)
        : await _host.readVenue(venue);
    if (raw == null) {
      _setRebalancePreview(venue, null);
      return const RebalanceOutcome(RebalanceOutcomeKind.unknown);
    }
    final minimum = wallet != null && unlocked
        ? await _host.minimumUsd(venue)
        : kOneBalanceMinimumUsd;
    final snapshot = _discountRecentSweep(raw, m);

    final now = _host.now();
    // A venue under the idle rule (Predictions) only sweeps once it has
    // been idle a day: then all of its cash goes home in one move, named
    // for the rule, with no rate limit or batching wait.
    final idleRule = snapshot.lastActivityAt != null && !ignoreIdle;
    SweepContext rules({required bool rebalance}) => _context(m,
        now: now,
        minimum: minimum,
        unlocked: unlocked,
        wallet: wallet,
        rebalance: rebalance,
        eventDriven: eventDriven || rollout,
        flushHeld: flushHeld,
        ignoreIdle: ignoreIdle,
        idleRule: idleRule);
    final decision = decideSweep(snapshot, rules(rebalance: false));
    // What a Rebalance would do now, for the Portfolio's button: the same
    // read under the Rebalance's rules, no I/O.
    final preview =
        ignoreIdle ? decision : decideSweep(snapshot, rules(rebalance: true));
    _setRebalancePreview(venue, preview);

    // A pass of its own reports a skip once per episode; the Rebalance
    // reports each venue once per tap, with its trigger.
    void skipped(SweepSkipReason? reason, String label, double usd) {
      if (!manual) {
        if (m.lastSkip == reason) return;
        m.lastSkip = reason;
      }
      _host.track('venue_sweep_skipped', {
        'venue': venue.analyticsName,
        'reason': label,
        'idle_usd': _usd(usd),
        if (manual) 'trigger': trigger,
      });
    }

    switch (decision) {
      case SweepNothing():
        m.heldSince = null;
        m.lastSkip = null;
        _setWaiting(venue, null);
        return const RebalanceOutcome(RebalanceOutcomeKind.nothing);
      case SweepDust(:final usd):
        // Below every route minimum: counted as the venue's money, never
        // shown as waiting, never sent or retried. Reported once per
        // episode as a below-minimum skip.
        m.heldSince = null;
        _setDust(venue, usd);
        skipped(SweepSkipReason.belowMinimum,
            SweepSkipReason.belowMinimum.label, snapshot.idleUsd);
        return RebalanceOutcome(RebalanceOutcomeKind.belowMinimum, usd: usd);
      case SweepSkip(:final reason, :final idleUsd):
        if (reason != SweepSkipReason.backoff) m.heldSince = null;
        _recordSkip(venue, reason, idleUsd, snapshot);
        skipped(reason, reason.label, idleUsd);
        return switch (reason) {
          // A move already pending at the venue (a sweep its read still
          // shows, a deposit on its way).
          SweepSkipReason.pendingDeposit =>
            RebalanceOutcome(RebalanceOutcomeKind.alreadyMoving, usd: idleUsd),
          SweepSkipReason.openOrders ||
          SweepSkipReason.crossPosition ||
          SweepSkipReason.claiming ||
          SweepSkipReason.active ||
          SweepSkipReason.locked =>
            RebalanceOutcome(RebalanceOutcomeKind.held,
                usd: idleUsd, reason: reason),
          _ => RebalanceOutcome(RebalanceOutcomeKind.notNow,
              usd: idleUsd, reason: reason),
        };
      case SweepWaiting(:final usd, :final cause):
        m.lastSkip = null;
        _setWaiting(venue, usd);
        if (cause == SweepWaitingCause.batching) {
          m.heldSince ??= now;
        } else {
          m.heldSince = null;
        }
        if (manual) {
          skipped(
              null,
              cause == SweepWaitingCause.routeUnavailable
                  ? 'route_unavailable'
                  : 'waiting',
              usd);
        }
        return RebalanceOutcome(RebalanceOutcomeKind.notNow, usd: usd);
      case SweepNow(:final usd):
        m.lastSkip = null;
        m.heldSince = null;
        return _execute(venue,
            usd: usd,
            idleUsd: snapshot.idleUsd,
            minimumUsd: minimum,
            trigger: idleRule && !rollout ? '${venue.name}_idle_24h' : trigger,
            rollout: rollout,
            ignoreIdle: ignoreIdle);
    }
  }

  Future<RebalanceOutcome> _execute(
    OneBalanceVenue venue, {
    required double usd,
    required double idleUsd,
    required double minimumUsd,
    required String trigger,
    required bool rollout,
    bool ignoreIdle = false,
  }) async {
    final m = _memory[venue]!;
    // A bet may have been queued or started placing since the pass read
    // the venue (the minimum is a network read): read it again right
    // before the move and leave the cash where it is if anything now holds
    // it. Not a failure: no backoff, the next pass decides again.
    final again = ignoreIdle
        ? await _host.readVenueForRebalance(venue)
        : await _host.readVenue(venue);
    if (again == null) {
      return const RebalanceOutcome(RebalanceOutcomeKind.unknown);
    }
    if (again.hasPendingMove) {
      return RebalanceOutcome(RebalanceOutcomeKind.alreadyMoving, usd: usd);
    }
    final SweepSkipReason? holds = again.hasPendingIntent || again.isPlacing
        ? SweepSkipReason.openOrders
        : ignoreIdle
            ? (again.hasCrossPosition
                ? SweepSkipReason.crossPosition
                : again.hasUnreservedRestingOrders
                    ? SweepSkipReason.openOrders
                    : null)
            : venueKeepsCash(again.lastActivityAt, _host.now())
                ? SweepSkipReason.active
                : null;
    if (holds != null) {
      return RebalanceOutcome(RebalanceOutcomeKind.held,
          usd: usd, reason: holds);
    }
    _inFlight.add(venue);
    _sends[venue] = (_sends[venue] ?? 0) + 1;
    _setRebalancePreview(venue, null);
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
      m.lastFailureAt = null;
      m.failureReported = false;
      m.recentlySweptUsd = result.sentUsd;
      m.recentlySweptAt = sentAt;
      // What the move left behind (the CCTP fallback keeps a HyperCore
      // gas reserve back) is dust when no sweep could take it.
      final left = _remaining(idleUsd, result.sentUsd);
      if (left + 1e-9 < minimumUsd) {
        _setDust(venue, left);
      } else {
        _setWaiting(venue, left);
      }
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
      return RebalanceOutcome(RebalanceOutcomeKind.moving,
          usd: result.sentUsd, ref: result.operationId ?? result.quoteId);
    } on RouteQuoteError catch (e) {
      if (e.code == RouteQuoteErrorCode.amountTooSmall) {
        // The route's real floor is above what we tried: the cash is
        // dust until more joins it, and the next pass compares against
        // the raised minimum. No backoff, nothing shown as waiting.
        _host.noteAmountTooSmall(venue, usd);
        _setDust(venue, usd);
        _fail(venue,
            stage: 'quote',
            category: e.code.code,
            trigger: trigger,
            backoff: false);
        return RebalanceOutcome(RebalanceOutcomeKind.belowMinimum, usd: usd);
      }
      _setWaiting(venue, idleUsd);
      _fail(venue, stage: 'quote', category: e.code.code, trigger: trigger);
      return RebalanceOutcome(RebalanceOutcomeKind.notNow, usd: idleUsd);
    } on RouteUnavailable catch (e) {
      if (_isBelowMinimum(e)) {
        // The fallback rail's own floor (the CCTP minimum after its fee
        // and the HyperCore reserve) is above the amount: the same answer
        // as a quote refusing it. Dust, the minimum raised, no backoff (a
        // backoff here retried the same refused amount every 2–10 min).
        _host.noteAmountTooSmall(venue, usd);
        _setDust(venue, usd);
        _fail(venue,
            stage: stage,
            category: RouteQuoteErrorCode.amountTooSmall.code,
            trigger: trigger,
            backoff: false);
        return RebalanceOutcome(RebalanceOutcomeKind.belowMinimum, usd: usd);
      }
      // The rail cannot carry a withdraw right now (Orchestra refusing the
      // HyperCore-source route and the CCTP fallback unable to run, a
      // paused route): the cash is simply waiting, shown as unavailable
      // until balancing completes. No error UI; a short backoff keeps the
      // passes from hammering the rail and retries once it is ready.
      if (kDebugMode) {
        debugPrint('[venue-sweep] ${venue.analyticsName} route unavailable: '
            '${e.reason ?? 'unknown'}');
      }
      _setWaiting(venue, idleUsd);
      _fail(venue,
          stage: stage,
          category: 'route_unavailable',
          trigger: trigger,
          maxBackoff: kSweepRouteBackoffMax);
      return RebalanceOutcome(RebalanceOutcomeKind.notNow, usd: idleUsd);
    } catch (e) {
      _setWaiting(venue, idleUsd);
      _fail(venue,
          stage: stage,
          category: TrackingService.errorCategory(e),
          trigger: trigger);
      return RebalanceOutcome(RebalanceOutcomeKind.notNow, usd: idleUsd);
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
    Duration maxBackoff = _kBackoffMax,
  }) {
    final m = _memory[venue]!;
    if (backoff) {
      final now = _host.now();
      var cur = m.backoff ?? _kBackoffFirst;
      if (cur > maxBackoff) cur = maxBackoff;
      m.backoffUntil = now.add(cur);
      m.lastFailureAt = now;
      final doubled = cur * 2;
      m.backoff = doubled > maxBackoff ? maxBackoff : doubled;
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
      lastActivityAt: s.lastActivityAt,
      hasCrossPosition: s.hasCrossPosition,
      hasUnreservedRestingOrders: s.hasUnreservedRestingOrders,
    );
  }

  static double _remaining(double total, double taken) {
    final left = total - taken;
    return left.isFinite && left > kSweepDustUsd ? left : 0;
  }

  /// A rail answer meaning "below my minimum" (`cctp_below_minimum`).
  static bool _isBelowMinimum(RouteUnavailable e) =>
      e.reason?.endsWith('below_minimum') ?? false;

  /// Shows [usd] of [venue] as waiting (null clears it); the venue is no
  /// longer dust. With automatic sweeping off no pass will move it, so it
  /// is simply the venue's Available cash (held), never "waiting" or
  /// "unavailable until balancing completes": only what a Rebalance
  /// submitted is on its way, and that shows as in flight.
  void _setWaiting(OneBalanceVenue venue, double? usd) => autoSweep
      ? _setCash(venue, waiting: usd)
      : _setCash(venue, held: usd);

  /// Records [usd] of [venue] as dust; the venue no longer waits.
  void _setDust(OneBalanceVenue venue, double usd) =>
      _setCash(venue, dust: usd);

  /// Records what a Rebalance would do at [venue] under the Rebalance's
  /// rules ([decision]; null: the venue has not answered, or a move is
  /// running): the cash it would move ([VenueSweeperState.movable]), or
  /// the cash it would leave because it is below the route minimum
  /// ([VenueSweeperState.belowMinimum]).
  void _setRebalancePreview(OneBalanceVenue venue, SweepDecision? decision) {
    bool put(Map<OneBalanceVenue, double> map, double? usd) {
      final keep = usd != null && usd.isFinite && usd >= kSweepDustUsd;
      if (!keep) return map.remove(venue) != null;
      if (map[venue] == usd) return false;
      map[venue] = usd;
      return true;
    }

    final a = put(_movable, decision is SweepNow ? decision.usd : null);
    final b = put(_belowMinimum, decision is SweepDust ? decision.usd : null);
    if (a || b) _publish();
  }

  /// The venue cash a skip leaves where it is, as a pass records it.
  void _recordSkip(OneBalanceVenue venue, SweepSkipReason reason,
      double idleUsd, VenueSnapshot snapshot) {
    // Backed-off cash stays visible: a failed swap-back never vanishes
    // into a hidden venue balance. Cash a venue in use keeps (the idle
    // rule) is the venue's money, counted like dust: in the total, never
    // shown as waiting.
    switch (reason) {
      case SweepSkipReason.active:
        final at = snapshot.lastActivityAt;
        if (at != null) _activeAt[venue] = at;
        _setCash(venue, held: idleUsd);
      case SweepSkipReason.backoff:
        _setWaiting(venue, idleUsd);
      case SweepSkipReason.locked:
      case SweepSkipReason.pendingDeposit:
        // Nothing decided: the venue's cash stays counted as the last
        // pass left it (the header caps it by the venue's live read).
        // Clearing it dropped the cash from the total whenever a pass ran
        // locked or with a move pending. A move pending may be a sweep the
        // venue's read still shows, already counted in flight, so the
        // read's figure is not taken here.
        break;
      default:
        // Held back for a moment (the grace after a deposit, a claim or
        // sale settling, an order queued or placing): still the person's
        // money at the venue, usable by the order that holds it. Counted
        // in Available, never dropped from the total (it used to vanish
        // until the next pass). Only the unreserved part: what open orders
        // hold is invested.
        _setCash(venue,
            held: snapshot.hasReservations
                ? math.min(
                    snapshot.sweepableUsd.isFinite && snapshot.sweepableUsd > 0
                        ? snapshot.sweepableUsd
                        : 0.0,
                    idleUsd)
                : idleUsd);
    }
  }

  /// The rules' session facts for a decision at a venue with memory [m].
  /// [rebalance] is the Rebalance's own view: the idle wait set aside, no
  /// rate limit or batching wait, and a backoff a Rebalance would lift
  /// ([sweepNow] lifts one whose failure is [kSweepResumeRetryAfter] old)
  /// lifted, so "can a Rebalance move this?" answers what a tap would do.
  SweepContext _context(
    _VenueMemory m, {
    required DateTime now,
    required double minimum,
    required bool unlocked,
    required String? wallet,
    required bool rebalance,
    required bool eventDriven,
    required bool flushHeld,
    required bool ignoreIdle,
    required bool idleRule,
  }) {
    var backoffUntil = m.backoffUntil;
    final failedAt = m.lastFailureAt;
    if (rebalance &&
        backoffUntil != null &&
        failedAt != null &&
        now.difference(failedAt) >= kSweepResumeRetryAfter) {
      backoffUntil = null;
    }
    return SweepContext(
      now: now,
      minimumUsd: minimum,
      sessionUnlocked: unlocked,
      spendingWalletActive: wallet != null,
      backoffUntil: backoffUntil,
      lastSweepAt: m.lastSweepAt,
      heldSince: m.heldSince,
      eventDriven: rebalance || eventDriven || idleRule,
      flushHeld: rebalance || flushHeld || idleRule,
      ignoreIdle: rebalance || ignoreIdle,
    );
  }

  void _setCash(OneBalanceVenue venue,
      {double? waiting, double? dust, double? held}) {
    bool put(Map<OneBalanceVenue, double> map, double? usd) {
      if (usd == null || !usd.isFinite || usd < kSweepDustUsd) {
        return map.remove(venue) != null;
      }
      if (map[venue] == usd) return false;
      map[venue] = usd;
      return true;
    }

    final a = put(_waiting, waiting);
    final b = put(_dust, dust);
    final h = put(_held, held);
    if (a || b || h) _publish();
  }

  void _publish() {
    final next = VenueSweeperState(
      waiting: Map.unmodifiable(_waiting),
      dust: Map.unmodifiable(_dust),
      held: Map.unmodifiable(_held),
      movable: Map.unmodifiable(_movable),
      belowMinimum: Map.unmodifiable(_belowMinimum),
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
    if (r.contains('close') ||
        r.contains('sold') ||
        r.contains('sell') ||
        // A TP/SL or other reduce-only fill closes (part of) a position.
        r.contains('reduce')) {
      return 'close';
    }
    if (r.contains('resume') || r.contains('unlock') || r == 'manual') {
      return 'resume';
    }
    return r;
  }
}
