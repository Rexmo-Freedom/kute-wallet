// lib/services/orchestra/arrival_target.dart
//
// Grossing a bitcoin leg up so the dollar figure the user typed is what
// arrives after Orchestra's spread. One price point (a send of `sats` gives
// `estimatedOut`) is enough to scale from, whether it came from the
// estimate the sheet already shows or from a quote.

import 'dart:math' as math;

/// How far below the typed figure a quote may land before it is asked
/// again: one cent.
const double kArrivalTargetTolerance = 0.01;

/// The share added on top of the measured shortfall, so a quote taken at
/// the scaled amount does not land a hair short.
const double kArrivalTargetBuffer = 1.003;

/// The largest scale ever applied (Orchestra's real spread is 1-3%). The
/// cap contains a decimals bug in an `estimatedOut`, which would otherwise
/// scale a typed $2 up to everything the wallet holds.
const double kArrivalTargetMaxScale = 1.1;

/// The sats to send so [targetUsd] arrives, scaled from a send of [sats]
/// that is estimated to deliver [estimatedOut], never above [maxSats] and
/// never below [sats]. Returns [sats] when it already delivers the target
/// or the price point is unusable.
int grossUpSatsForTarget({
  required int sats,
  required double estimatedOut,
  required double targetUsd,
  required int maxSats,
}) {
  if (sats <= 0 ||
      !estimatedOut.isFinite ||
      !targetUsd.isFinite ||
      estimatedOut <= 0 ||
      targetUsd <= 0 ||
      estimatedOut >= targetUsd) {
    return sats;
  }
  final scale = ((targetUsd / estimatedOut) * kArrivalTargetBuffer)
      .clamp(1.0, kArrivalTargetMaxScale);
  final scaled = (sats * scale).ceil();
  return math.max(sats, math.min(scaled, maxSats));
}

/// Whether a quote delivering [estimatedOut] falls short of [targetUsd] by
/// more than [kArrivalTargetTolerance], so it is worth asking again.
bool arrivalTargetShort(double estimatedOut, double targetUsd) =>
    estimatedOut > 0 &&
    targetUsd > 0 &&
    // A hair of slack so binary rounding of an exact cent never counts.
    targetUsd - estimatedOut > kArrivalTargetTolerance + 1e-9;
