// lib/services/hyperliquid/hyperliquid_rounding.dart
//
// Price/size wire formatting + validation for Hyperliquid orders.
//
// Exchange rules (docs → "Tick and lot size"):
//   * size  — at most `szDecimals` decimals (from meta/spotMeta);
//   * price — at most 5 significant figures AND at most
//              (6 - szDecimals) decimals for perps / (8 - szDecimals) for
//              spot; integer prices are always allowed;
//   * order notional must be ≥ $10.
//
// `floatToWire` mirrors the Python SDK's float_to_wire exactly (fixed-8
// format, 1e-12 drift guard, '-0' fix, trailing-zero strip) so the strings
// we sign are byte-identical to what the reference implementation signs.

import 'dart:math' as math;

import 'package:kute/constants/hyperliquid_constants.dart';

/// A float formatted for the Hyperliquid wire: plain decimal notation, no
/// trailing zeros, no exponent. Throws [ArgumentError] when fixed-8
/// formatting would materially round the value (>= 1e-12), mirroring the
/// Python SDK guard. Negative zero yields '-0' — byte-identical to the
/// reference float_to_wire; unreachable in practice because roundSize/
/// roundPrice reject non-positive values first.
String floatToWire(double x) {
  final fixed = x.toStringAsFixed(8);
  final parsed = double.parse(fixed);
  if ((parsed - x).abs() >= 1e-12) {
    throw ArgumentError('floatToWire causes rounding: $x');
  }
  var s = fixed;
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  }
  return s;
}

/// Order size floored to `szDecimals` decimals, as a wire string. Flooring
/// (not rounding) guarantees we never order more than the caller budgeted.
/// Throws when the size floors to zero.
String roundSize(double sz, int szDecimals) {
  final floored = flooredSize(sz, szDecimals);
  if (floored <= 0) {
    throw ArgumentError('size $sz rounds to zero at szDecimals=$szDecimals');
  }
  return floatToWire(floored);
}

/// Numeric variant of [roundSize] for previews/validation. The 1e-9 nudge
/// absorbs binary-float artifacts (0.29 * 100 == 28.999…996) without ever
/// crossing a real decimal boundary at Hyperliquid's precisions.
double flooredSize(double sz, int szDecimals) {
  final factor = math.pow(10, szDecimals).toDouble();
  return (sz * factor + 1e-9).floorToDouble() / factor;
}

/// Order price rounded to Hyperliquid's rule: 5 significant figures, then
/// clamped to the per-asset decimal cap. Integer results are always valid
/// (prices above 100k lose sub-dollar precision by construction).
String roundPrice(double px, {required int szDecimals, required bool isSpot}) {
  if (px <= 0) throw ArgumentError('price must be positive, got $px');
  // The venue accepts any integer price regardless of significant
  // figures, and its own client only applies the 5-figure rule to the
  // synthetic price of a market order. A limit, trigger or modified price
  // at 100,000 or more therefore keeps its dollars: 112,345.7 is placed at
  // 112,346, not 112,350.
  if (px >= 1e5) return floatToWire(px.roundToDouble());
  final fiveSig = double.parse(px.toStringAsPrecision(5));
  final maxDecimals = math.max(0, (isSpot ? 8 : 6) - szDecimals);
  final factor = math.pow(10, maxDecimals).toDouble();
  final clamped = (fiveSig * factor).roundToDouble() / factor;
  if (clamped <= 0) {
    throw ArgumentError('price $px rounds to zero at cap $maxDecimals');
  }
  return floatToWire(clamped);
}

/// "Market" orders on Hyperliquid are IOC limits priced through the book:
/// buy at ref*(1+slippage), sell at ref*(1-slippage), wire-rounded.
String slippagePrice({
  required double referencePx,
  required bool isBuy,
  double slippage = 0.01,
  required int szDecimals,
  required bool isSpot,
}) {
  final px = referencePx * (isBuy ? 1 + slippage : 1 - slippage);
  return roundPrice(px, szDecimals: szDecimals, isSpot: isSpot);
}

/// Size purchasable with [usd] at [px], floored to szDecimals.
double sizeFromUsd({
  required double usd,
  required double px,
  required int szDecimals,
}) {
  if (px <= 0) return 0;
  return flooredSize(usd / px, szDecimals);
}

/// The USD an order must be worth for its FLOORED size to still clear
/// the venue's minimum notional.
///
/// Size is floored to the market's step, and on a market whose step is
/// large next to the minimum that haircut is not small change: BTC
/// steps in 0.00001, which near 85,000 dollars is about 85 cents, so a
/// ten dollar order floors to a size worth about 9.33 and Hyperliquid
/// rejects it for being under ten. Asking for exactly the minimum can
/// therefore never work, and the app used to send it anyway and let
/// the venue say no.
///
/// Answers the smallest amount that survives the floor, so a screen can
/// say what would work instead of only what does not.
double minUsdForFlooredSize({
  required double px,
  required int szDecimals,
  required double minNotionalUsd,
}) {
  if (px <= 0 || minNotionalUsd <= 0) return minNotionalUsd;
  final step = math.pow(10, -szDecimals).toDouble();
  if (step <= 0) return minNotionalUsd;
  // The first whole step at or above the minimum, valued at this price.
  final steps = (minNotionalUsd / px / step).ceil();
  final usd = steps * step * px;
  return usd < minNotionalUsd ? usd + step * px : usd;
}

/// The price the venue values an order's notional at for its minimum
/// check: an IOC "market" order is a limit at the slippage price, so a
/// sell (or a short) is checked BELOW the reference and a buy above it.
/// The lower of the reference and the order's wire-rounded price is
/// returned: the slippage price for a sell, the reference for a buy.
/// A resting limit passes [slippage] 0 and its own price as reference.
double hlMinCheckPx({
  required double referencePx,
  required bool isBuy,
  required double slippage,
  required int szDecimals,
  required bool isSpot,
}) {
  if (referencePx <= 0) return 0;
  if (slippage <= 0) return referencePx;
  try {
    // A buy's wire price is above the reference unless the price cap
    // rounds it back under, which the min below also covers.
    final px = double.parse(slippagePrice(
      referencePx: referencePx,
      isBuy: isBuy,
      slippage: slippage,
      szDecimals: szDecimals,
      isSpot: isSpot,
    ));
    return math.min(px, referencePx);
  } catch (_) {
    return isBuy ? referencePx : referencePx * (1 - slippage);
  }
}

/// Head-room on top of the venue minimum for the price moving between
/// the slip showing a minimum and the order being built.
const double hlMinNotionalBuffer = 0.005;

/// The smallest amount the slip's field takes (margin on a perp, dollars
/// on spot) whose order, built the way the submit path builds it, clears
/// the venue minimum: size = floor(amount × [leverage] / [referencePx]) to
/// the market's step, valued at [checkPx] (see [hlMinCheckPx]), with
/// [buffer] on top of [minNotionalUsd]. Up to the cent. [baseSize] is
/// size the order needs on top of that (a flip first closes the held
/// position; only what it opens past it has to meet the minimum).
///
/// The slip used to size its minimum at the mid alone: a 1x short
/// prefilled 10.08, whose order valued at the 1% slippage price came to
/// 9.98, and the order was refused.
double hlMinOrderAmountUsd({
  required double referencePx,
  required double checkPx,
  required int szDecimals,
  int leverage = 1,
  double minNotionalUsd = HyperliquidConstants.minOrderNotionalUsd,
  double buffer = hlMinNotionalBuffer,
  double baseSize = 0,
}) {
  final lev = leverage < 1 ? 1 : leverage;
  final target = minNotionalUsd * (1 + buffer);
  if (referencePx <= 0 || checkPx <= 0) {
    return ((target + baseSize * math.max(referencePx, 0)) / lev * 100 - 1e-6)
            .ceilToDouble() /
        100;
  }
  final step = math.pow(10, -szDecimals).toDouble();
  // Whole steps whose value at the checked price reaches the target.
  final steps = math.max(1, (target / checkPx / step - 1e-9).ceil());
  final size = baseSize + steps * step;
  // The amount whose floored size is at least that many steps, still
  // after the reference rises by the buffer (a whole step can drop out).
  final sizingPx = referencePx * (1 + buffer);
  var cents = (size * sizingPx / lev * 100 - 1e-6).ceil();
  for (var i = 0; i < 1000; i++) {
    final sz = flooredSize(cents / 100 * lev / sizingPx, szDecimals);
    if (sz >= size - step / 2) break;
    cents++;
  }
  return cents / 100;
}

/// The notional the venue will check for an order of [amountUsd] at
/// [leverage]: the size the submit path builds ([referencePx], floored)
/// valued at [checkPx].
double hlCheckedNotionalUsd({
  required double amountUsd,
  required double referencePx,
  required double checkPx,
  required int szDecimals,
  int leverage = 1,
}) {
  final lev = leverage < 1 ? 1 : leverage;
  final size = sizeFromUsd(
      usd: amountUsd * lev, px: referencePx, szDecimals: szDecimals);
  return size * checkPx;
}

bool meetsMinNotional({required double px, required double sz}) {
  return px * sz >= HyperliquidConstants.minOrderNotionalUsd - 1e-9;
}

/// Perp order-wire asset id == index into the `meta` universe.
int perpAssetId(int universeIndex) => universeIndex;

/// Spot order-wire asset id == 10000 + the pair's `index` field from
/// spotMeta (NOT its position in the universe list — they usually agree,
/// but only `index` is authoritative).
int spotAssetId(int pairIndex) =>
    HyperliquidConstants.spotAssetIdOffset + pairIndex;
