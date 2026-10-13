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
//               cash open BUY orders hold, plus venue dust (idle cash
//               below every route minimum, which no sweep can move: the
//               user's money at the venue, shown as invested, never as
//               waiting), plus the live marks of held positions while the
//               header is on screen (one_balance_live_provider.dart: the
//               positions at live prices between the venues' reads).
//               Never other idle cash: that is being swept and shows as
//               in flight or waiting;
//   in flight = pending Orchestra rows, by direction: Dollars → venue
//               (an order being funded), venue → Dollars (a sweep or a
//               withdrawal), and dollars arriving from anywhere else
//               (Bitcoin → Dollars, a receive, Cash App) — all under the
//               same 30-minute age cap as the pending pool rows;
//   waiting   = what the sweeper still owes back, from its own state;
//   venue cash = idle cash a venue keeps by design (Investing until it
//               sits idle 24 h), counted in Available, never waiting.
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
    show pendingVenueMoveOf;

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

/// The venues' invested figure with their dust added: cash below every
/// route minimum stays at the venue and counts as the venue's money (in
/// the total and the Invested line), never as waiting. Pure for the tests.
double investedWithDust(double investedUsd, Map<OneBalanceVenue, double> dust) {
  var sum = investedUsd.isFinite && investedUsd > 0 ? investedUsd : 0.0;
  for (final usd in dust.values) {
    if (usd.isFinite && usd > 0) sum += usd;
  }
  return sum;
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
  final waiting = ref.watch(venueSweeperProvider.select((s) => s.waiting));
  final dust = ref.watch(venueSweeperProvider.select((s) => s.dust));
  // Cash a venue keeps by design (Investing until idle): Available.
  final held = ref.watch(venueSweeperProvider.select((s) => s.held));
  // Held positions marked to market between the venues' reads, while the
  // header is on screen (zero otherwise).
  final marks = ref.watch(oneBalanceLiveProvider);
  final invested = investedWithDust(venues.investedUsd, dust) +
      marks.totalDeltaUsd;

  return OneBalanceState(
    dollarsUsd: dollars.isFinite && dollars > 0 ? dollars : 0,
    investedUsd: invested.isFinite && invested > 0 ? invested : 0,
    inFlight: inFlight,
    waiting: waiting,
    venueCash: held,
    investingKnown: venues.investingKnown,
    predictionsKnown: venues.predictionsKnown,
  );
});
