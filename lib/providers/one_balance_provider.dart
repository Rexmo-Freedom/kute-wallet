// lib/providers/one_balance_provider.dart
//
// Fills `OneBalanceState` from the reads the app already keeps warm.
// Nothing new is polled: the spending account's dollar balance, the two
// venues' balances (through the unified venue split) and the Orchestra
// rows background sync maintains each have their own provider; this one
// only adds them up in the one-balance shape.
//
//   dollars   = the spending account's USDB balance;
//   invested  = Hyperliquid portfolio + Predictions positions and the
//               cash open BUY orders hold, plus the pending fills and
//               the live marks of held positions while the header is on
//               screen (one_balance_live_provider.dart: the positions at
//               live prices between the venues' reads). Never idle cash:
//               cash at a venue is Available (venue cash) or waiting;
//   in flight = pending Orchestra rows, by direction: Dollars → venue
//               (an order being funded), venue → Dollars (a sweep or a
//               withdrawal), and dollars arriving from anywhere else
//               (Bitcoin → Dollars, a receive, Cash App) — all under the
//               same 30-minute age cap as the pending pool rows;
//   waiting   = what the sweeper still owes back, from its own state;
//   venue cash = the venues' unreserved cash the sweeper is not moving:
//               cash a venue keeps by design (Investing until it sits
//               idle 24 h, a venue in use) AND dust (below every route
//               minimum, which the sweeper never moves). Spendable at the
//               venue and reachable by the engine, so always Available
//               (founder decision 13 October 2026: one balance), never
//               Invested. Dust only tells the sweeper to leave it alone.
//
// Waiting, dust and venue cash are the sweeper's classification from its
// last pass, each capped by the venue's live unreserved cash
// ([cappedVenueCash]): a bet paid from venue cash leaves Available at the
// fill, never stays there next to the position it bought. A buy the
// positions read has not listed yet counts at its fill price
// (`PolymarketTradingState.pendingFills`, in the venue's invested figure).
//
// Unknown venue reads count as zero with the matching `…Known` flag
// false, so the state never throws before the venues have answered.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/one_balance_live_provider.dart';
import 'package:kute/providers/pending_pool_deposits_provider.dart'
    show isPendingDollarsIncoming;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/unified_balances_provider.dart';
import 'package:kute/providers/usd_account_provider.dart';
import 'package:kute/providers/venue_sweeper_provider.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart'
    show InvestmentsProduct;
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/sweep_rules.dart'
    show kSweepDustUsd, pendingVenueMoveOf;

/// The venue a [OneBalanceVenue] reads its balances as.
InvestmentsProduct investmentsProductOf(OneBalanceVenue venue) =>
    switch (venue) {
      OneBalanceVenue.investing => InvestmentsProduct.trading,
      OneBalanceVenue.predictions => InvestmentsProduct.predictions,
    };

double _parse(String raw) {
  final v = double.tryParse(raw);
  return v != null && v.isFinite && v > 0 ? v : 0;
}

/// The in-flight rows from the exchange rows, one row per kind and venue
/// (the header reads one figure per direction). Pure for the tests.
List<InFlightMove> inFlightMovesFrom(
  Iterable<SwapOrder> rows, {
  required String? walletId,
  required int nowMs,
}) {
  final sums = <(InFlightKind, OneBalanceVenue?), double>{};
  for (final row in rows) {
    final move = pendingVenueMoveOf(row, walletId: walletId, nowMs: nowMs);
    if (move != null) {
      final (venue, kind) = move;
      // Dollars leaving show what left; dollars coming back show what the
      // quote said would arrive.
      final usd = kind == InFlightKind.toVenue
          ? _parse(row.depositAmount)
          : _parse(row.withdrawalAmount);
      if (usd > 0) sums[(kind, venue)] = (sums[(kind, venue)] ?? 0) + usd;
      continue;
    }
    if (isPendingDollarsIncoming(row, walletId: walletId, nowMs: nowMs)) {
      final usd = _parse(row.withdrawalAmount);
      if (usd > 0) {
        sums[(InFlightKind.incomingDollars, null)] =
            (sums[(InFlightKind.incomingDollars, null)] ?? 0) + usd;
      }
    }
  }
  const order = [
    InFlightKind.toVenue,
    InFlightKind.fromVenue,
    InFlightKind.incomingDollars,
  ];
  return [
    for (final kind in order)
      for (final venue in [...OneBalanceVenue.values, null])
        if (sums[(kind, venue)] case final usd?)
          InFlightMove(kind: kind, venue: venue, usd: usd),
  ];
}

double _clean(double v) => v.isFinite && v > 0 ? v : 0;

/// The venue's idle cash as its own read says now (unreserved: what open
/// orders hold is in `investedUsd`), or null while the venue has not
/// answered.
double? _liveIdleCash(UnifiedVenueBalances venues, OneBalanceVenue venue) =>
    switch (venue) {
      OneBalanceVenue.investing =>
        venues.investingKnown ? _clean(venues.readyInInvestingUsd) : null,
      OneBalanceVenue.predictions =>
        venues.predictionsKnown ? _clean(venues.readyInPredictionsUsd) : null,
    };

/// The sweeper's buckets for the venue cash (waiting, dust, held), each
/// capped by what the venue's live read says is idle there now.
///
/// The sweeper classifies the cash on its passes (events, the 3-minute
/// heartbeat); the venues' reads move between them. A bet paid from
/// Predictions cash takes the cash off the live read at the fill, and the
/// position onto it, while the sweeper's `held` still said $3.55 until
/// its next pass: the spent cash stayed in Available next to the position
/// it bought. The live read can only lower a bucket here, never raise it
/// (cash a read shows that the sweeper has not classified yet can be a
/// sweep that left a moment ago and is counted in flight), and the sweeper
/// re-classifies on its next pass.
({
  Map<OneBalanceVenue, double> waiting,
  Map<OneBalanceVenue, double> dust,
  Map<OneBalanceVenue, double> held,
}) cappedVenueCash(UnifiedVenueBalances venues, VenueSweeperState sweeper) {
  final waiting = <OneBalanceVenue, double>{};
  final dust = <OneBalanceVenue, double>{};
  final held = <OneBalanceVenue, double>{};
  for (final venue in OneBalanceVenue.values) {
    var room = _liveIdleCash(venues, venue) ?? double.infinity;
    double take(double? usd) {
      final want = usd == null ? 0.0 : _clean(usd);
      final got = want < room ? want : room;
      room -= got;
      return got;
    }

    final w = take(sweeper.waiting[venue]);
    final d = take(sweeper.dust[venue]);
    final h = take(sweeper.held[venue]);
    if (w >= kSweepDustUsd) waiting[venue] = w;
    if (d >= kSweepDustUsd) dust[venue] = d;
    if (h >= kSweepDustUsd) held[venue] = h;
  }
  return (waiting: waiting, dust: dust, held: held);
}

/// The one-balance picture from its inputs. Pure for the tests.
///
///   total     = Dollars + venue positions (at the live marks) + venue
///               cash (held, dust, waiting) + in flight;
///   Available = Dollars + the venues' unreserved cash the sweeper is not
///               moving (held and dust alike: spendable at the venue,
///               reachable by the engine);
///   Invested  = positions, cash open orders reserve and pending fills
///               (`venues.investedUsd`), at the live marks.
///
/// Each venue dollar is in exactly one place: cash in the venue's read is
/// unreserved cash (held, dust or waiting, capped by the read), reserved
/// cash and positions are in `venues.investedUsd`.
OneBalanceState oneBalanceStateFrom({
  required double dollarsUsd,
  required UnifiedVenueBalances venues,
  required List<InFlightMove> inFlight,
  required VenueSweeperState sweeper,
  OneBalanceLiveMarks marks = OneBalanceLiveMarks.zero,
}) {
  final cash = cappedVenueCash(venues, sweeper);
  // Dust is venue cash like any other: the sweeper leaves it where it is,
  // and a bet or an order there spends it.
  final venueCash = <OneBalanceVenue, double>{};
  for (final venue in OneBalanceVenue.values) {
    final usd = (cash.held[venue] ?? 0) + (cash.dust[venue] ?? 0);
    if (usd >= kSweepDustUsd) venueCash[venue] = usd;
  }
  // The marks move the positions only.
  final marked = _clean(venues.investedUsd) + marks.totalDeltaUsd;
  return OneBalanceState(
    dollarsUsd: _clean(dollarsUsd),
    investedUsd: _clean(marked),
    inFlight: inFlight,
    waiting: cash.waiting,
    venueCash: venueCash,
    investingKnown: venues.investingKnown,
    predictionsKnown: venues.predictionsKnown,
  );
}

/// The one-balance picture, recomputed whenever any input moves.
final oneBalanceProvider = Provider<OneBalanceState>((ref) {
  final dollars = ref.watch(usdBalanceProvider);
  final venues = ref.watch(unifiedVenueBalancesProvider);
  final walletId = ref.watch(settingsProvider.select((s) => s.activeWalletId));
  final inFlight = inFlightMovesFrom(
    ref.watch(swapOrdersProvider),
    walletId: walletId,
    nowMs: DateTime.now().millisecondsSinceEpoch,
  );
  return oneBalanceStateFrom(
    dollarsUsd: dollars,
    venues: venues,
    inFlight: inFlight,
    // Waiting, and the cash a venue keeps or cannot move (dust), both
    // Available, from the sweeper's passes, capped by the venues' reads.
    sweeper: ref.watch(venueSweeperProvider),
    // Held positions marked to market between the venues' reads, while
    // the header is on screen (zero otherwise).
    marks: ref.watch(oneBalanceLiveProvider),
  );
});
