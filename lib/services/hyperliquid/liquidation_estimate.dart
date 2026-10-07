// lib/services/hyperliquid/liquidation_estimate.dart
//
// Client-side liquidation estimate for a perp order that has not executed
// yet. Hyperliquid documents the rule the venue applies:
//
//   liq_price = price - side * margin_available / position_size / (1 - l * side)
//
// where `side` is 1 for a long and -1 for a short, `l` is one over the
// maintenance leverage, and the maintenance margin is half of the initial
// margin at the market's maximum leverage, so `l = 1 / (2 * maxLeverage)`.
// `margin_available` is the margin backing the position minus the
// maintenance margin it requires: the isolated margin for an isolated
// position, or the whole account equity less every position's maintenance
// margin for cross.
//
// The venue's own figure can differ once large-position margin tiers,
// fees, funding and other open positions come into it, so every caller
// labels the result as an estimate.

import 'dart:math' as math;

class LiquidationEstimate {
  const LiquidationEstimate._();

  /// One over the maintenance leverage for a market: the maintenance margin
  /// fraction of notional.
  static double maintenanceFraction(int maxLeverage) =>
      1 / (2 * math.max(1, maxLeverage));

  /// The liquidation price for a position of [size] coins entered at
  /// [price], backed by [marginAvailable] dollars beyond the maintenance
  /// margin the position requires. Null when the inputs cannot describe a
  /// position or the result would be negative or above the entry for a
  /// long, below it for a short.
  static double? fromMargin({
    required double price,
    required double size,
    required bool isLong,
    required double marginAvailable,
    required int maxLeverage,
  }) {
    if (!(price > 0) || !(size > 0) || !price.isFinite || !size.isFinite) {
      return null;
    }
    final l = maintenanceFraction(maxLeverage);
    final side = isLong ? 1.0 : -1.0;
    final liq = price - side * marginAvailable / size / (1 - l * side);
    if (!liq.isFinite || liq <= 0) return null;
    if (isLong ? liq >= price : liq <= price) return null;
    return liq;
  }

  /// A new isolated position: [marginUsd] is the collateral put up for
  /// [size] coins at [price].
  static double? isolated({
    required double price,
    required double size,
    required bool isLong,
    required double marginUsd,
    required int maxLeverage,
  }) {
    final notional = price * size;
    final maintenance = notional * maintenanceFraction(maxLeverage);
    return fromMargin(
      price: price,
      size: size,
      isLong: isLong,
      marginAvailable: marginUsd - maintenance,
      maxLeverage: maxLeverage,
    );
  }

  /// A new cross position on an account with [accountValue] equity whose
  /// other positions already require [maintenanceMarginUsed]: the whole
  /// equity backs the position, less every position's maintenance margin.
  static double? cross({
    required double price,
    required double size,
    required bool isLong,
    required double accountValue,
    required double maintenanceMarginUsed,
    required int maxLeverage,
  }) {
    final notional = price * size;
    final maintenance = notional * maintenanceFraction(maxLeverage);
    return fromMargin(
      price: price,
      size: size,
      isLong: isLong,
      marginAvailable: accountValue - maintenanceMarginUsed - maintenance,
      maxLeverage: maxLeverage,
    );
  }
}
