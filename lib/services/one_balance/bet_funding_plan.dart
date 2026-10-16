// lib/services/one_balance/bet_funding_plan.dart
//
// What a prediction moves from Dollars at its Confirm (founder rule,
// 2026-10): Predictions cash is used first and only the remainder moves.
// The need is the stake plus the venue's fees at the order's worst price
// (its tolerance) plus the rounding cent; what is missing moves, rounded
// up to the cent, grossed up by the route's fee, with a small buffer so
// the order surely fills, never under the Move minimum or the route's.
// Anything the order does not spend stays on Predictions as part of the
// one balance. "Add $X" shows only when Dollars cannot cover this move.
//
// Example: Predictions holds $2, a $3.50 minimum bet needs about $3.58
// with fees, so about $1.85 moves (not the whole $3.50).
//
// The landing target is the shared funding engine's
// ([OrderFundingEngine.targetUsd]: the shortfall plus 2%, at least $0.25,
// never under $1), the same rule an Investing order uses. Where the move
// comes from (Dollars first, then Investing cash pulled home) is the
// slip's, through the shared venue-cash planner.

import 'dart:math' as math;

import 'package:kute/services/funding/venue_shortfall.dart';
import 'package:kute/services/one_balance/order_funding.dart'
    show OrderFundingEngine, OrderFundingPlan;
import 'package:kute/services/one_balance/venue_funder.dart';

/// The buffer on a funding move: the shared engine's
/// ([OrderFundingEngine.bufferShare] of what is missing, at least
/// [OrderFundingEngine.bufferMinUsd]).
const double kBetFundingBufferPct = OrderFundingEngine.bufferShare;
const double kBetFundingBufferMinUsd = OrderFundingEngine.bufferMinUsd;

double _ceilCents(double usd) => ((usd * 100) - 1e-9).ceilToDouble() / 100;

/// The move for a bet needing [requiredUsd] of Predictions cash with
/// [readyUsd] spendable there (cash less what resting buys reserve), on a
/// route keeping [routeFee] of what is sent, whose smallest move is
/// [minUsd]. A zero `fundUsd` when the venue cash covers the bet.
OrderFundingPlan planBetFunding({
  required double requiredUsd,
  required double readyUsd,
  double routeFee = ShortfallRules.fallbackRouteFee,
  double minUsd = ShortfallRules.minTopUpUsd,
}) {
  final floor = minUsd.isFinite && minUsd > 0 ? minUsd : 0.0;
  final missing =
      ShortfallRules.shortfallUsd(requiredUsd: requiredUsd, readyUsd: readyUsd);
  if (missing <= 0) {
    return OrderFundingPlan(
        fundUsd: 0,
        arrivingUsd: 0,
        rule: ShortfallRules.ruleRemaining,
        minUsd: floor);
  }
  final keep = routeFee.isFinite && routeFee > 0 && routeFee < 1
      ? 1 - routeFee
      : 1.0;
  final target = OrderFundingEngine.targetUsd(shortfallUsd: missing);
  final fund = math.max(_ceilCents(target / keep),
      math.max(ShortfallRules.minTopUpUsd, _ceilCents(floor)));
  return OrderFundingPlan(
    fundUsd: fund,
    arrivingUsd: fund * keep,
    rule: ShortfallRules.ruleRemaining,
    minUsd: floor,
  );
}

/// [planBetFunding] with the route's fee and minimum read from the venue's
/// live estimate for the move; the fallback fee on an unusable estimate.
/// A failed read throws.
Future<OrderFundingPlan> readBetFunding(
  VenueFunder funder, {
  required double requiredUsd,
  required double readyUsd,
}) async {
  final missing =
      ShortfallRules.shortfallUsd(requiredUsd: requiredUsd, readyUsd: readyUsd);
  final base = math.max(missing, ShortfallRules.minTopUpUsd);
  final estimate = await funder.estimate(base);
  final fee = ShortfallRules.routeFeeFrom(
          sentUsd: base, arrivingUsd: estimate.arrivingUsd) ??
      ShortfallRules.fallbackRouteFee;
  return planBetFunding(
    requiredUsd: requiredUsd,
    readyUsd: readyUsd,
    routeFee: fee,
    minUsd: estimate.minUsd,
  );
}
