import 'dart:math' as math;

import 'package:kute/models/hyperliquid_market.dart';

/// Spendable cash on the native HyperCore account, regardless of which
/// clearinghouse received the deposit. Held spot USDC is never available.
double hypercoreAvailableUsdc(
        double perpAvailable, Iterable<HlSpotBalance> spot) =>
    perpAvailable +
    spot
        .where((balance) => balance.coin == 'USDC')
        .fold<double>(0, (sum, balance) => sum + balance.available);

/// A HyperCore USDC balance as exact eight-decimal base units.
///
/// The venue prints balances with at most eight decimals, and the double
/// one parses into can sit a hair under its decimal: 19.99 is
/// 19.9899999999999984... Flooring that counted 1998999999 units, one
/// fewer than the account holds, while the amount being sent (rounded,
/// see `hypercoreUsdcBaseUnits`) was 1999000000. A withdrawal of the whole
/// balance then came up one unit short of itself and was refused.
/// Rounding gives back the printed figure exactly. Zero for a read that is
/// not a finite positive number; callers reject those before asking.
BigInt hypercoreBalanceBaseUnits(double usd) =>
    usd.isFinite && usd > 0 ? BigInt.from((usd * 1e8).round()) : BigInt.zero;

/// The most a native withdrawal can send out of [perpAvailable] and the
/// unheld spot USDC: what Max sends. The usdSend and the spot-to-perpetuals
/// transfer that tops it up both move whole six-decimal units, so each pool
/// counts its whole micro-dollars, read exactly
/// ([hypercoreBalanceBaseUnits]). Only sub-micro dust stays behind. Never
/// more than [hypercoreAvailableUsdc] of the same balances.
double hypercoreSendableUsdc(
    double perpAvailable, Iterable<HlSpotBalance> spot) {
  final unit = BigInt.from(100);
  BigInt micros(double usd) => hypercoreBalanceBaseUnits(usd) ~/ unit;
  final units = (micros(perpAvailable) +
          micros(hypercoreAvailableUsdc(0, spot))) *
      unit;
  return units.toDouble() / 1e8;
}

/// USDC to move from spot before a reviewed perp action. Never moves more than
/// its shortfall or the unheld spot cash; the exchange remains authoritative
/// about margin requirements and may reject the eventual order.
double hypercorePerpFundingAmount({
  required double requiredUsd,
  required double perpAvailable,
  required Iterable<HlSpotBalance> spot,
}) {
  if (!requiredUsd.isFinite || requiredUsd <= 0 || !perpAvailable.isFinite) {
    return 0;
  }
  final shortfall = requiredUsd - perpAvailable;
  if (shortfall <= 0) return 0;
  final spotAvailable = hypercoreAvailableUsdc(0, spot);
  if (!spotAvailable.isFinite || spotAvailable <= 0) return 0;
  // Native class transfers use six decimal places. Round down so the move
  // never exceeds either the reviewed shortfall or the balance read.
  return (math.min(shortfall, spotAvailable) * 1e6).floorToDouble() / 1e6;
}

/// What an order's fees can add at most, as a share of notional: the
/// highest HyperCore taker rate (0.045%, doubled on a HIP-3 dex) plus the
/// largest builder fee a perp order may carry (0.1%). Sizing a "use it
/// all" order against it only ever leaves a little behind.
const double kHlOrderFeeCeiling = 0.0019;

/// The largest order amount (margin for a perp, dollars for a spot buy) a
/// "use everything" tap can ask for out of [availableUsd] and still be
/// funded: the order is signed with [slippagePct] of headroom on price and
/// pays taker plus builder fees on its notional (`margin × leverage`), all
/// out of the same cash (see `_fundPerpAction`). Floored to a cent, so it
/// never rounds up past the balance the way a two-decimal print did.
double hypercoreMaxOrderUsd({
  required double availableUsd,
  int leverage = 1,
  double slippagePct = 1.0,
  double feeCeiling = kHlOrderFeeCeiling,
}) {
  if (!availableUsd.isFinite || availableUsd <= 0) return 0;
  final slip = 1 + (slippagePct.isFinite && slippagePct > 0 ? slippagePct : 0) / 100;
  final lev = leverage < 1 ? 1 : leverage;
  final perDollar = slip * (1 + lev * feeCeiling);
  final max = availableUsd / perDollar;
  return (max * 100).floorToDouble() / 100;
}
