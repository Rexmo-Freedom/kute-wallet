// lib/services/one_balance/committed_funds.dart
//
// "This money is spoken for." What an order the person has ACCEPTED (Face
// ID) is about to move from Dollars, from the spending bitcoin or from a
// venue's cash, from the accept until the money has left (or the order is
// over). A second order accepted at nearly the same time, on the other
// venue, sizes and checks against what is left, so two orders can never
// both count the same dollars: the second is refused before anything of
// it moves (the Dollars door), never funded half way.
//
// One commitment per source and order venue (one funded order per venue
// at a time: the slips refuse a second accept while one is in flight).
// It is bound to its funded order's record (`fundedOrdersProvider`) when
// it has one, and stops counting the moment that record is no longer
// live: placed, failed, stopped, replaced. Its Dollars stop counting once
// they have left AND the Dollars reading shows it (until then the reading
// still counts them; never both, never neither for long). Bitcoin and
// venue cash stop counting the moment their leg is sent: the bitcoin
// balance's own send hold, and the venue's own read, show it from there.
// Nothing outlives [CommittedFundsNotifier.maxAge].
//
// Memory only: a restart starts empty. Nothing a previous process
// accepted is waiting to leave Dollars after a restart (its approval
// lived in memory; legs already on a rail are in flight from their rows).
//
// Reads that size a NEW order use the net figures ([orderDollarsProvider]
// and the puller's venue cash, the spendable providers built on them);
// the one-balance header shows held Dollars as money into an order
// (in flight, Invested), never as Available. The controller
// (`order_funding.dart`) checks a move against Dollars less what OTHER
// orders hold, claims its own share in the same synchronous step, and
// marks it sent or releases it on every end.
//
// Privacy: local only, nothing here is tracked.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/money_steps.dart' show MoneyPlace;
import 'package:kute/services/one_balance/one_balance_state.dart';

/// Money an accepted order has spoken for.
@immutable
class FundsCommitment {
  const FundsCommitment({
    required this.from,
    required this.venue,
    required this.usd,
    required this.at,
    this.runId,
    this.sentAt,
    this.sentFromUsd,
  });

  /// The balance it comes out of.
  final MoneyPlace from;

  /// The venue of the order it is for.
  final OneBalanceVenue venue;

  /// What it holds, in dollars.
  final double usd;

  /// When it was committed.
  final DateTime at;

  /// The funded order's record (`FundedOrderRecord.id`), when it has one:
  /// the commitment ends with that record's life.
  final String? runId;

  /// Dollars only: when they left, and the Dollars reading the move was
  /// checked against just before (what the reading drops from).
  final DateTime? sentAt;
  final double? sentFromUsd;

  bool get sent => sentAt != null;

  FundsCommitment copyWith({
    double? usd,
    String? runId,
    DateTime? sentAt,
    double? sentFromUsd,
  }) =>
      FundsCommitment(
        from: from,
        venue: venue,
        usd: usd ?? this.usd,
        at: at,
        runId: runId ?? this.runId,
        sentAt: sentAt ?? this.sentAt,
        sentFromUsd: sentFromUsd ?? this.sentFromUsd,
      );

  @override
  String toString() => 'FundsCommitment(${from.name} → ${venue.name}, $usd'
      '${sent ? ', sent' : ''})';
}

double _clean(double v) => v.isFinite && v > 0 ? v : 0;

/// Whether [c] still holds its money at [now]. [dollarsUsd]: the Dollars
/// reading a check (or the shown balance) uses; a sent Dollars
/// commitment counts only while that reading has not dropped by it yet,
/// and never past [CommittedFundsNotifier.sentHold]. [runLive]: whether
/// a funded order's record is still live (null: not looked at). Pure.
bool commitmentHolds(
  FundsCommitment c, {
  required DateTime now,
  double? dollarsUsd,
  bool Function(String runId)? runLive,
}) {
  if (now.difference(c.at) >= CommittedFundsNotifier.maxAge) return false;
  final sentAt = c.sentAt;
  if (sentAt != null) {
    if (now.difference(sentAt) >= CommittedFundsNotifier.sentHold) {
      return false;
    }
    final from = c.sentFromUsd;
    final reading = dollarsUsd;
    // The reading shows the debit (it fell by at least half of it):
    // counted there now, not here.
    if (from != null && reading != null && reading <= from - c.usd / 2) {
      return false;
    }
    return true;
  }
  final run = c.runId;
  if (run != null && runLive != null && !runLive(run)) return false;
  return true;
}

/// What [commitments] hold of [from] at [now], less the not-yet-sent
/// commitment on [exceptHeldOn] (the order asking: its own share is not
/// someone else's). Pure.
double committedUsd(
  Iterable<FundsCommitment> commitments,
  MoneyPlace from, {
  required DateTime now,
  double? dollarsUsd,
  bool Function(String runId)? runLive,
  OneBalanceVenue? exceptHeldOn,
}) {
  var sum = 0.0;
  for (final c in commitments) {
    if (c.from != from) continue;
    if (!c.sent && c.venue == exceptHeldOn) continue;
    if (!commitmentHolds(c,
        now: now, dollarsUsd: dollarsUsd, runLive: runLive)) {
      continue;
    }
    sum += _clean(c.usd);
  }
  return sum;
}

/// What the order-funding controller needs of the ledger: Dollars less
/// what OTHER orders hold, and its own share claimed, sent or released.
abstract interface class DollarsCommitments {
  /// [dollarsUsd] (a Dollars reading) less what orders other than the one
  /// on [venue] hold.
  double availableFor(OneBalanceVenue venue, {required double dollarsUsd});

  /// The order on [venue] holds [usd] of Dollars from now (its accept-time
  /// commitment resized to the move, or a new one). The caller checked
  /// [availableFor] in the same synchronous step.
  void claimDollars(OneBalanceVenue venue, double usd);

  /// The order on [venue]'s Dollars left, checked against [fromUsd]: they
  /// hold until the reading shows it.
  void dollarsSent(OneBalanceVenue venue, {required double fromUsd});

  /// The order on [venue] takes nothing (more) from Dollars.
  void releaseDollars(OneBalanceVenue venue);
}

/// The commitments, newest last. See the file header.
class CommittedFundsNotifier extends Notifier<List<FundsCommitment>>
    implements DollarsCommitments {
  /// Test seam: the clock commitments are stamped with.
  static DateTime Function() clock = DateTime.now;

  /// No commitment outlives this (the longest any funding chain waits).
  static const Duration maxAge = Duration(minutes: 15);

  /// Dollars that left count at most this long before the reading shows
  /// them (a reading that never moves cannot keep them held).
  static const Duration sentHold = Duration(seconds: 30);

  Timer? _expiry;

  @override
  List<FundsCommitment> build() {
    ref.onDispose(() => _expiry?.cancel());
    return const [];
  }

  bool _runLive(String runId) {
    try {
      final runs = ref.read(fundedOrdersProvider);
      for (final r in runs) {
        if (r.id == runId) return r.stage.active;
      }
    } catch (_) {
      return true;
    }
    return false;
  }

  double _dollarsNow() {
    try {
      return ref.read(usdBalanceProvider);
    } catch (_) {
      return 0;
    }
  }

  /// Drops what no longer holds anything, and wakes the readers when the
  /// next one runs out on its own.
  void _set(List<FundsCommitment> next, {double? dollarsUsd}) {
    final now = clock();
    // The reading only matters to Dollars that already left.
    final reading = dollarsUsd ??
        (next.any((c) => c.sent && c.from == MoneyPlace.dollars)
            ? _dollarsNow()
            : null);
    final kept = [
      for (final c in next)
        if (commitmentHolds(c,
            now: now, dollarsUsd: reading, runLive: _runLive))
          c,
    ];
    state = kept;
    _expiry?.cancel();
    _expiry = null;
    if (kept.isEmpty) return;
    var soonest = maxAge;
    for (final c in kept) {
      final left = c.sent
          ? sentHold - now.difference(c.sentAt!)
          : maxAge - now.difference(c.at);
      if (left < soonest) soonest = left;
    }
    _expiry = Timer(
        soonest.isNegative
            ? Duration.zero
            : soonest + const Duration(milliseconds: 50),
        () => _set(state));
  }

  /// Re-reads the live records and the Dollars reading: what no longer
  /// holds goes. The readers recompute.
  void refresh() => _set(state);

  /// The not-yet-sent commitment of [from] for [venue], if any.
  FundsCommitment? heldOn(MoneyPlace from, OneBalanceVenue venue) {
    for (final c in state) {
      if (c.from == from && c.venue == venue && !c.sent) return c;
    }
    return null;
  }

  /// What [from] holds now against [dollarsUsd] (Dollars only).
  double heldUsd(MoneyPlace from,
          {double? dollarsUsd, OneBalanceVenue? exceptHeldOn}) =>
      committedUsd(state, from,
          now: clock(),
          dollarsUsd:
              dollarsUsd ?? (from == MoneyPlace.dollars ? _dollarsNow() : null),
          runLive: _runLive,
          exceptHeldOn: exceptHeldOn);

  /// The order on [venue], just accepted, takes [usd] of Dollars. Only
  /// when [dollarsUsd] (the Dollars reading; the balance when omitted)
  /// less what other orders hold covers it: then it is held from now and
  /// true; else nothing is held and false (the order is refused before
  /// anything moves). Replaces an earlier not-yet-sent commitment on
  /// [venue]. Synchronous: no other accept can slip between the check and
  /// the hold.
  bool commitDollars(OneBalanceVenue venue,
      {required double usd, double? dollarsUsd, String? runId}) {
    final want = _clean(usd);
    if (want < 0.005) return true;
    final reading = dollarsUsd ?? _dollarsNow();
    final available = availableFor(venue, dollarsUsd: reading);
    if (available + 1e-9 < want) return false;
    _put(MoneyPlace.dollars, venue, want, runId: runId, dollarsUsd: reading);
    return true;
  }

  /// What [usd] of Dollars lack for the order on [venue] once what other
  /// orders hold is taken off, to the cent; zero when covered.
  double dollarsShortUsd(OneBalanceVenue venue, double usd) {
    final short = _clean(usd) - availableFor(venue, dollarsUsd: _dollarsNow());
    return short <= 0 ? 0 : ((short * 100) - 1e-9).ceilToDouble() / 100;
  }

  /// The order on [venue], just accepted, takes [usd] from [from] (its
  /// bitcoin leg, or a venue's cash), sized on figures already net of
  /// every other commitment: held from now, until the leg is sent
  /// ([sourceSent]) or the order is over.
  void hold(MoneyPlace from, OneBalanceVenue venue,
      {required double usd, String? runId}) {
    assert(from != MoneyPlace.dollars, 'Dollars are committed with a check');
    final want = _clean(usd);
    if (want < 0.005) return;
    _put(from, venue, want, runId: runId);
  }

  void _put(MoneyPlace from, OneBalanceVenue venue, double usd,
      {String? runId, double? dollarsUsd}) {
    final now = clock();
    _set([
      for (final c in state)
        if (!(c.from == from && c.venue == venue && !c.sent)) c,
      FundsCommitment(
          from: from, venue: venue, usd: usd, at: now, runId: runId),
    ], dollarsUsd: dollarsUsd);
  }

  /// [from]'s leg was sent: its money shows where it went from now.
  void sourceSent(MoneyPlace from) {
    if (!state.any((c) => c.from == from && !c.sent)) return;
    _set([
      for (final c in state)
        if (!(c.from == from && !c.sent)) c,
    ]);
  }

  /// A leg from [venue]'s cash was sent: the venue's read shows it now.
  void venueCashSent(OneBalanceVenue venue) =>
      sourceSent(venueCashPlaceOf(venue));

  /// Everything the order [runId] holds is released (it is over).
  void releaseRun(String runId) {
    if (!state.any((c) => c.runId == runId && !c.sent)) return;
    _set([
      for (final c in state)
        if (!(c.runId == runId && !c.sent)) c,
    ]);
  }

  // ── DollarsCommitments (the controller) ──────────────────────────────

  @override
  double availableFor(OneBalanceVenue venue, {required double dollarsUsd}) =>
      _clean(dollarsUsd) -
      committedUsd(state, MoneyPlace.dollars,
          now: clock(),
          dollarsUsd: dollarsUsd,
          runLive: _runLive,
          exceptHeldOn: venue);

  @override
  void claimDollars(OneBalanceVenue venue, double usd) {
    final want = _clean(usd);
    final own = heldOn(MoneyPlace.dollars, venue);
    if (want < 0.005) {
      releaseDollars(venue);
      return;
    }
    _put(MoneyPlace.dollars, venue, want, runId: own?.runId);
  }

  @override
  void dollarsSent(OneBalanceVenue venue, {required double fromUsd}) {
    final own = heldOn(MoneyPlace.dollars, venue);
    if (own == null) return;
    final now = clock();
    _set([
      for (final c in state)
        if (identical(c, own))
          c.copyWith(sentAt: now, sentFromUsd: _clean(fromUsd))
        else
          c,
    ], dollarsUsd: fromUsd);
  }

  @override
  void releaseDollars(OneBalanceVenue venue) {
    if (heldOn(MoneyPlace.dollars, venue) == null) return;
    _set([
      for (final c in state)
        if (!(c.from == MoneyPlace.dollars && c.venue == venue && !c.sent)) c,
    ]);
  }

  @visibleForTesting
  static void resetClock() => clock = DateTime.now;
}

/// The [MoneyPlace] of [venue]'s cash.
MoneyPlace venueCashPlaceOf(OneBalanceVenue venue) => switch (venue) {
      OneBalanceVenue.investing => MoneyPlace.investing,
      OneBalanceVenue.predictions => MoneyPlace.predictions,
    };

final committedFundsProvider =
    NotifierProvider<CommittedFundsNotifier, List<FundsCommitment>>(
        CommittedFundsNotifier.new);

/// Whether the funded record [runId] is still live in [runs].
bool _liveIn(List<FundedOrderRecord> runs, String runId) {
  for (final r in runs) {
    if (r.id == runId) return r.stage.active;
  }
  return false;
}

/// What accepted orders hold of [from] now, watched: recomputed when the
/// commitments, the records they are bound to or the Dollars reading
/// ([dollarsUsd]) move.
double watchCommittedUsd(Ref ref, MoneyPlace from, {double? dollarsUsd}) {
  final commitments = ref.watch(committedFundsProvider);
  if (!commitments.any((c) => c.from == from)) return 0;
  final runs = commitments.any((c) => c.runId != null)
      ? ref.watch(fundedOrdersProvider)
      : const <FundedOrderRecord>[];
  return committedUsd(commitments, from,
      now: CommittedFundsNotifier.clock(),
      dollarsUsd: dollarsUsd,
      runLive: (id) => _liveIn(runs, id));
}

/// Dollars a NEW order may draw on: the balance less what accepted orders
/// have committed and not yet seen leave. What the slips size and check
/// by before the approval, and what Investments' spendable figures start
/// from. Never what a send itself checks (the controller does that).
final orderDollarsProvider = Provider<double>((ref) {
  final dollars = ref.watch(usdBalanceProvider);
  final held = watchCommittedUsd(ref, MoneyPlace.dollars, dollarsUsd: dollars);
  return math.max(0.0, dollars - held);
});

/// Not-yet-sent commitments from Dollars as money on its way into each
/// order (the one-balance header counts them Invested, never Available),
/// named by the order's record when it has one.
List<InFlightMove> committedDollarsInFlight(
  Iterable<FundsCommitment> commitments, {
  required DateTime now,
  required List<FundedOrderRecord> runs,
}) =>
    [
      for (final c in commitments)
        if (c.from == MoneyPlace.dollars &&
            !c.sent &&
            commitmentHolds(c, now: now, runLive: (id) => _liveIn(runs, id)) &&
            _clean(c.usd) > 0)
          InFlightMove(
            kind: InFlightKind.toVenue,
            venue: c.venue,
            usd: _clean(c.usd),
            order: () {
              final id = c.runId;
              if (id == null) return null;
              for (final r in runs) {
                if (r.id == id) return r.toInFlightOrder();
              }
              return null;
            }(),
          ),
    ];
