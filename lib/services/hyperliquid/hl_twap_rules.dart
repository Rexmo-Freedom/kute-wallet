// lib/services/hyperliquid/hl_twap_rules.dart
//
// Hyperliquid's TWAP bounds, in one place: the ticket checks them inline
// before Confirm, the trading notifier before any leverage write or funds
// move, and the exchange service again before it signs.
//
// Source (read 27 November 2026):
//   https://hyperliquid.gitbook.io/hyperliquid-docs/trading/order-types
//   "Running time can be set from 5 minutes to 7 days, with a $100 minimum
//   total order size." Suborders go out at a fixed interval worked out from
//   the size and running time, each capped at 3% slippage.
//   https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
//   (twapOrder: `m` is minutes; no cloid field).
//
// The documentation does not say at which price the $100 is valued, so the
// app takes the stricter side: the size as sent (floored to the market's
// step) valued at the live mid, and the ticket adds the usual 0.5% headroom
// for the price moving before it is sent ([hlMinNotionalBuffer]).

import 'package:kute/services/hyperliquid/hyperliquid_rounding.dart';

class HlTwapRules {
  HlTwapRules._();

  /// Shortest running time, in minutes.
  static const int minMinutes = 5;

  /// Longest running time, in minutes (7 days).
  static const int maxMinutes = 7 * 24 * 60;

  /// The documented minimum total order size, in dollars of notional.
  static const double minNotionalUsd = 100;

  static bool minutesValid(int? minutes) =>
      minutes != null && minutes >= minMinutes && minutes <= maxMinutes;

  /// Whether [size] coins (already floored as sent) at [referencePx] meet
  /// the TWAP minimum.
  static bool meetsMinimum({required double referencePx, required double size}) =>
      referencePx * size >= minNotionalUsd - 1e-9;

  /// The smallest amount the ticket's field takes (margin on a perp) whose
  /// TWAP, sized the way the submit path sizes it, clears [minNotionalUsd].
  static double minAmountUsd({
    required double referencePx,
    required int szDecimals,
    int leverage = 1,
  }) =>
      hlMinOrderAmountUsd(
        referencePx: referencePx,
        checkPx: referencePx,
        szDecimals: szDecimals,
        leverage: leverage,
        minNotionalUsd: minNotionalUsd,
      );
}
