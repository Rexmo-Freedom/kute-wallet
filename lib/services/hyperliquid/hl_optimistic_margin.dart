// lib/services/hyperliquid/hl_optimistic_margin.dart
//
// Optimistic perp margin after a fill, reconciled on the next poll.
//
// When the exchange answers "filled", the clearinghouse snapshot the app
// shows is still the pre-fill one until the account poll next lands and
// the venue has indexed the fill. For those seconds the balances card
// shows margin and withdrawable that are already wrong. This helper
// moves them at once (open: margin locked, withdrawable down; close:
// margin released plus the realised PnL, withdrawable up) and says when
// a later snapshot should win: as soon as the venue's own margin figure
// has moved off the pre-fill baseline, or after a short safety TTL.
//
// Pure values, no Riverpod: the trading notifier owns one hold at a
// time and applies [withdrawable] / [totalMarginUsed] to its state
// while [reconciledBy] is false.

import 'dart:math' as math;

class HlOptimisticMargin {
  /// The venue's margin figure before the fill: a snapshot whose margin
  /// still equals it has not indexed the fill yet.
  final double marginBefore;

  /// The optimistic figures to show until reconciled.
  final double withdrawable;
  final double totalMarginUsed;
  final DateTime at;

  const HlOptimisticMargin({
    required this.marginBefore,
    required this.withdrawable,
    required this.totalMarginUsed,
    required this.at,
  });

  /// Longest a hold is applied before the next snapshot wins regardless.
  static const Duration ttl = Duration(seconds: 10);

  /// Margin tolerance below which the venue is considered not to have
  /// indexed the fill yet (the figures are USD with 6 decimals).
  static const double tolerance = 1e-6;

  /// After an OPEN fill of [marginUsd]: margin locked, withdrawable down.
  static HlOptimisticMargin afterOpen({
    required double withdrawable,
    required double totalMarginUsed,
    required double marginUsd,
    required DateTime at,
  }) {
    final delta = math.max(0.0, marginUsd);
    return HlOptimisticMargin(
      marginBefore: totalMarginUsed,
      withdrawable: math.max(0.0, withdrawable - delta),
      totalMarginUsed: totalMarginUsed + delta,
      at: at,
    );
  }

  /// After a CLOSE fill that released [marginReleasedUsd] and realised
  /// [realizedPnlUsd] (negative on a loss): margin down, withdrawable up
  /// by the margin and the PnL.
  static HlOptimisticMargin afterClose({
    required double withdrawable,
    required double totalMarginUsed,
    required double marginReleasedUsd,
    double realizedPnlUsd = 0,
    required DateTime at,
  }) {
    final released = math.max(0.0, marginReleasedUsd);
    return HlOptimisticMargin(
      marginBefore: totalMarginUsed,
      withdrawable: math.max(0.0, withdrawable + released + realizedPnlUsd),
      totalMarginUsed: math.max(0.0, totalMarginUsed - released),
      at: at,
    );
  }

  /// True once a snapshot with [snapshotMarginUsed] should replace the
  /// optimistic figures: the venue's margin moved off the pre-fill
  /// baseline (it indexed the fill), or the hold is older than [ttl].
  bool reconciledBy(double snapshotMarginUsed, {required DateTime now}) {
    if (now.difference(at) > ttl) return true;
    return (snapshotMarginUsed - marginBefore).abs() > tolerance;
  }
}
