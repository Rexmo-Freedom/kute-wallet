// lib/services/one_balance/sweep_rules.dart
//
// The never-sweep rules, as one pure decision. The sweeper reads what
// the app already knows about a venue into a [VenueSnapshot], adds the
// session facts in a [SweepContext], and this file says what to do:
// sweep now, skip for a named reason, or hold the cash as "waiting".
// No I/O, no clocks, no Riverpod: every rule is a table test.
//
// Why each rule exists (from the plan's "Never sweep"):
//   - a deposit still in flight, or one that just landed for an order
//     about to be placed: the money is about to be used, not idle;
//   - cash reserved by open orders: Predictions sweeps `available`
//     (cash minus BUY reservations), Investing only the rail's
//     withdrawable amount;
//   - mid-claim: a redeem reads and moves the venue's balances;
//   - below the route minimum: the quote would refuse it. That cash is
//     dust ([SweepDust]): it stays the user's money in the total, but it
//     is never shown as waiting and never retried, because no pass can
//     move it until more cash joins it;
//   - batching: each sweep is an Orchestra order with a fee, so small
//     amounts wait a little for more.

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable;
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';

/// A pending Orchestra row older than this is a stuck order for Activity,
/// not money on a rail (the same cap the pool hero uses).
const Duration kVenueMoveMaxAge = Duration(minutes: 30);

/// The exchange-row network labels a venue's moves carry.
Set<String> venueNetworksOf(OneBalanceVenue venue) => switch (venue) {
      OneBalanceVenue.predictions => const {'POLYGON'},
      OneBalanceVenue.investing => const {'HYPERCORE'},
    };

bool _dollarCoin(String coin) {
  final c = coin.toUpperCase();
  return c == 'USDC' || c == 'USDC.E' || c == 'USDB';
}

bool _ownRow(SwapOrder row, String? walletId) =>
    walletId == null || row.walletId == null || row.walletId == walletId;

/// The venue [row] is an Orchestra deposit into (dollars on the venue's
/// network on the settle side), whatever its status, or null.
OneBalanceVenue? venueDepositRowOf(SwapOrder row, {required String? walletId}) {
  if (!row.isOrchestra || !_dollarCoin(row.coinTo) || !_ownRow(row, walletId)) {
    return null;
  }
  final network = row.networkTo.toUpperCase();
  for (final venue in OneBalanceVenue.values) {
    if (venueNetworksOf(venue).contains(network)) return venue;
  }
  return null;
}

/// The venue [row] is a withdrawal out of (dollars on the venue's network
/// on the deposit side), whatever its status, or null.
OneBalanceVenue? venueWithdrawalRowOf(SwapOrder row,
    {required String? walletId}) {
  if (!_dollarCoin(row.coinFrom) || !_ownRow(row, walletId)) return null;
  final network = row.networkFrom.toUpperCase();
  for (final venue in OneBalanceVenue.values) {
    if (venueNetworksOf(venue).contains(network)) return venue;
  }
  return null;
}

/// A pending, fresh venue move on [row]: the venue and its direction, or
/// null. The sweeper holds a venue while any such row exists; the header
/// shows it as in flight.
(OneBalanceVenue, InFlightKind)? pendingVenueMoveOf(
  SwapOrder row, {
  required String? walletId,
  required int nowMs,
}) {
  if (!row.isPending) return null;
  if (nowMs - row.timestamp > kVenueMoveMaxAge.inMilliseconds) return null;
  final deposit = venueDepositRowOf(row, walletId: walletId);
  if (deposit != null) return (deposit, InFlightKind.toVenue);
  final withdrawal = venueWithdrawalRowOf(row, walletId: walletId);
  if (withdrawal != null) return (withdrawal, InFlightKind.fromVenue);
  return null;
}

/// Idle cash at or above this sweeps at once.
const double kSweepBatchUsd = 5.0;

/// Cash between the minimum and [kSweepBatchUsd] waits this long for more
/// before it sweeps anyway.
const Duration kSweepHoldMax = Duration(minutes: 10);

/// No deposit may have settled into the venue within this window.
const Duration kSweepDepositGrace = Duration(seconds: 90);

/// At most one sweep per venue per window, unless an event (close,
/// claim, cancel) asks for one.
const Duration kSweepRateLimit = Duration(minutes: 10);

/// Idle below this is nothing at all: a residue the venue cannot even
/// report reliably. Cash between this and the route minimum is
/// [SweepDust].
const double kSweepDustUsd = 0.01;

/// Why a pass left a venue alone. The names are the analytics values.
enum SweepSkipReason {
  pendingDeposit('pending_deposit'),
  grace('grace'),
  openOrders('open_orders'),
  claiming('claiming'),
  belowMinimum('below_minimum'),
  locked('locked'),
  backoff('backoff'),

  /// The venue was used within [kVenueIdleSweepAfter] (or has open
  /// orders): its cash stays there, available, until it has been idle.
  active('venue_active'),

  /// A cross-margin position is open at Investing: its free cash is that
  /// position's margin buffer. Only a pass that sets aside the idle rule
  /// ([SweepContext.ignoreIdle]) reports it; the idle rule already keeps
  /// such an account's cash.
  crossPosition('cross_position');

  const SweepSkipReason(this.label);

  final String label;
}

/// Why idle cash is shown as waiting instead of swept. Cash under the
/// route minimum is not one of them: it is dust ([SweepDust]).
enum SweepWaitingCause {
  /// Between the minimum and the batch size, or inside the rate-limit
  /// window: waiting for more or for the window to pass.
  batching,

  /// The rail reports nothing withdrawable although nothing reserves the
  /// cash (a rail without a withdraw). Shown as waiting, never an error.
  routeUnavailable,

  /// A sweep failed and the venue is backing off; the cash stays visible.
  backoff,
}

/// What the app knows about one venue at the moment of a pass.
@immutable
class VenueSnapshot {
  const VenueSnapshot({
    required this.idleUsd,
    required this.sweepableUsd,
    this.hasReservations = false,
    this.hasPendingMove = false,
    this.lastDepositSettledAt,
    this.hasPendingIntent = false,
    this.isPlacing = false,
    this.hasOpenTwap = false,
    this.isClaiming = false,
    this.lastActivityAt,
    this.hasCrossPosition = false,
    this.hasUnreservedRestingOrders = false,
  });

  /// Venue cash not in a position: what the header would otherwise hide.
  final double idleUsd;

  /// The part of [idleUsd] a sweep may take: Predictions `available`
  /// (cash minus open BUY reservations), Investing the rail's
  /// withdrawable amount.
  final double sweepableUsd;

  /// Something at the venue reserves cash (open limit orders, margin in
  /// use). Tells a zero [sweepableUsd] apart from a rail that cannot
  /// withdraw.
  final bool hasReservations;

  /// A deposit or withdrawal for the venue is still non-terminal: a
  /// pending Orchestra row either way, or a settlement operation that
  /// has not reached a terminal stage.
  final bool hasPendingMove;

  /// When the last deposit into the venue turned success (or, for
  /// Predictions, when the deposit settled and its wrap ran). Null when
  /// none is known.
  final DateTime? lastDepositSettledAt;

  /// A bet or order intent for the venue is queued behind funds.
  final bool hasPendingIntent;

  /// An order is being placed right now (a placing tile is up).
  final bool isPlacing;

  /// A TWAP the app started is still running.
  final bool hasOpenTwap;

  /// A claim is redeemable, clearing or otherwise mid-settlement (a
  /// withdraw or sale in flight).
  final bool isClaiming;

  /// Set for a venue whose cash stays until it has been idle
  /// [kVenueIdleSweepAfter] (Predictions): when it was last used (an
  /// order, a sale, a claim, a cancel, a funded bet; now, while orders
  /// are open). Null leaves the venue under the plain rules.
  final DateTime? lastActivityAt;

  /// A cross-margin position is open (Investing): its free cash is margin.
  final bool hasCrossPosition;

  /// Orders rest at the venue that reserve no cash for themselves
  /// (Investing: Hyperliquid checks margin only at the fill and cancels
  /// the order, `marginCanceled`, when the account no longer covers it).
  /// Predictions reserves a BUY's cash, so its orders are
  /// [hasReservations] instead and only the unreserved part may move.
  final bool hasUnreservedRestingOrders;
}

/// A venue under the idle rule ([VenueSnapshot.lastActivityAt]) keeps its
/// cash, counted as available, until it has been idle this long: no
/// orders, sells, claims or cancels and no open orders. Positions held do
/// not count; only the cash moves.
const Duration kVenueIdleSweepAfter = Duration(hours: 24);

/// Whether an idle venue's cash ever goes home on its own. False keeps it
/// at the venue for good (it then only leaves on demand). One line.
const bool kVenueIdleSweepEnabled = true;

/// Whether a venue under the idle rule, last used at [activeAt], still
/// keeps its cash at [now].
bool venueKeepsCash(DateTime? activeAt, DateTime now) =>
    activeAt != null &&
    (!kVenueIdleSweepEnabled ||
        now.difference(activeAt) < kVenueIdleSweepAfter);

/// The session facts a pass adds to the snapshot.
@immutable
class SweepContext {
  const SweepContext({
    required this.now,
    required this.minimumUsd,
    this.sessionUnlocked = true,
    this.spendingWalletActive = true,
    this.backoffUntil,
    this.lastSweepAt,
    this.heldSince,
    this.eventDriven = false,
    this.flushHeld = false,
    this.ignoreIdle = false,
  });

  final DateTime now;

  /// The larger of the live route minimum and the app floor.
  final double minimumUsd;

  /// The session is unlocked (the lock overlay is down).
  final bool sessionUnlocked;

  /// The active wallet is the spending account that owns the venues.
  final bool spendingWalletActive;

  /// Set after a failure: no attempt before this instant.
  final DateTime? backoffUntil;

  /// When this venue last swept, for the rate limit.
  final DateTime? lastSweepAt;

  /// When cash between the minimum and the batch size first held.
  final DateTime? heldSince;

  /// The pass was asked for by a close, claim or cancel: the rate limit
  /// does not apply.
  final bool eventDriven;

  /// The app is leaving the foreground: held cash sweeps now rather
  /// than waiting for more.
  final bool flushHeld;

  /// The person asked for the cash now (the Portfolio's Rebalance): the
  /// idle wait ([kVenueIdleSweepAfter]) does not apply, every other rule
  /// does, and the two things the idle rule stood guard over for Investing
  /// hold the cash instead: a cross position, an order resting there.
  final bool ignoreIdle;
}

sealed class SweepDecision {
  const SweepDecision();
}

/// Nothing idle at the venue.
final class SweepNothing extends SweepDecision {
  const SweepNothing();
}

/// Send [usd] home now.
final class SweepNow extends SweepDecision {
  const SweepNow(this.usd);

  final double usd;
}

/// Leave the venue alone for [reason]; nothing is shown.
final class SweepSkip extends SweepDecision {
  const SweepSkip(this.reason, {required this.idleUsd});

  final SweepSkipReason reason;
  final double idleUsd;
}

/// [usd] is below the smallest sweep the route takes: dust (the CCTP
/// reserve left on HyperCore, a few cents of Predictions cash). It stays
/// at the venue, counts in the total as venue money and is neither shown
/// as waiting nor retried; only more cash joining it changes the answer.
final class SweepDust extends SweepDecision {
  const SweepDust(this.usd);

  final double usd;
}

/// Keep [usd] at the venue and show it as waiting.
final class SweepWaiting extends SweepDecision {
  const SweepWaiting(this.usd, {required this.cause});

  final double usd;
  final SweepWaitingCause cause;
}

double _clean(double v) => v.isFinite && v > 0 ? v : 0;

/// The one decision for a venue. See the file header for the rules.
SweepDecision decideSweep(VenueSnapshot venue, SweepContext ctx) {
  final idle = _clean(venue.idleUsd);
  if (idle < kSweepDustUsd) return const SweepNothing();

  // Below the route minimum the cash can never move on its own, whatever
  // else holds the venue: dust, before any skip or backoff could show it.
  // With reservations only the unreserved part is the venue's idle cash
  // (the reserved part is already counted as invested).
  final minimum = math.max(_clean(ctx.minimumUsd), kSweepDustUsd);
  if (idle + 1e-9 < minimum) {
    return SweepDust(venue.hasReservations
        ? math.min(_clean(venue.sweepableUsd), idle)
        : idle);
  }

  if (!ctx.spendingWalletActive || !ctx.sessionUnlocked) {
    return SweepSkip(SweepSkipReason.locked, idleUsd: idle);
  }

  if (ctx.ignoreIdle) {
    final unreserved = venue.hasReservations
        ? math.min(_clean(venue.sweepableUsd), idle)
        : idle;
    if (venue.hasCrossPosition) {
      return SweepSkip(SweepSkipReason.crossPosition, idleUsd: unreserved);
    }
    if (venue.hasUnreservedRestingOrders) {
      return SweepSkip(SweepSkipReason.openOrders, idleUsd: unreserved);
    }
  } else if (venueKeepsCash(venue.lastActivityAt, ctx.now)) {
    // The unreserved cash (what resting orders hold is already counted as
    // invested): the venue's money, counted in the total meanwhile.
    return SweepSkip(SweepSkipReason.active,
        idleUsd: venue.hasReservations
            ? math.min(_clean(venue.sweepableUsd), idle)
            : idle);
  }

  final backoffUntil = ctx.backoffUntil;
  if (backoffUntil != null && ctx.now.isBefore(backoffUntil)) {
    return SweepSkip(SweepSkipReason.backoff, idleUsd: idle);
  }

  if (venue.hasPendingMove) {
    return SweepSkip(SweepSkipReason.pendingDeposit, idleUsd: idle);
  }

  final settledAt = venue.lastDepositSettledAt;
  if (settledAt != null &&
      ctx.now.difference(settledAt).abs() < kSweepDepositGrace) {
    return SweepSkip(SweepSkipReason.grace, idleUsd: idle);
  }

  if (venue.isClaiming) {
    return SweepSkip(SweepSkipReason.claiming, idleUsd: idle);
  }

  if (venue.hasPendingIntent || venue.isPlacing || venue.hasOpenTwap) {
    return SweepSkip(SweepSkipReason.openOrders, idleUsd: idle);
  }

  final sweepable = math.min(_clean(venue.sweepableUsd), idle);
  if (sweepable < kSweepDustUsd) {
    if (venue.hasReservations) {
      return SweepSkip(SweepSkipReason.openOrders, idleUsd: idle);
    }
    return SweepWaiting(idle, cause: SweepWaitingCause.routeUnavailable);
  }

  if (sweepable + 1e-9 < minimum) return SweepDust(sweepable);

  final lastSweepAt = ctx.lastSweepAt;
  if (!ctx.eventDriven &&
      lastSweepAt != null &&
      ctx.now.difference(lastSweepAt) < kSweepRateLimit) {
    return SweepWaiting(sweepable, cause: SweepWaitingCause.batching);
  }

  if (sweepable + 1e-9 >= kSweepBatchUsd) return SweepNow(sweepable);

  if (ctx.flushHeld) return SweepNow(sweepable);
  final heldSince = ctx.heldSince;
  if (heldSince != null && ctx.now.difference(heldSince) >= kSweepHoldMax) {
    return SweepNow(sweepable);
  }
  return SweepWaiting(sweepable, cause: SweepWaitingCause.batching);
}
