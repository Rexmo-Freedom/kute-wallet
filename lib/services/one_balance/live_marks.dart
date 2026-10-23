// lib/services/one_balance/live_marks.dart
//
// Keeps the Investments header's total moving with what the user holds,
// between the venues' own reads. Pure rules, no I/O, no Riverpod (the
// binding lives in `lib/providers/one_balance_live_provider.dart`):
//
//   * mark-to-market: an open position's value at the live price, as a
//     DELTA on top of the value the venue's last read reported (so the
//     next read re-bases it and nothing is counted twice):
//       Predictions  size × (live price − the read's curPrice),
//       Investing    szi × (live mid − the read's mark), the mark being
//                    positionValue / |szi|;
//   * the reconciliation cadence (founder, 2026-10-13: "dynamic, driven
//     by what the user actually holds, not a flat poll"): nothing held →
//     no poll at all, only the event refreshes (fill, funding landing,
//     sweep landing, claim, sell); positions held while the header is on
//     screen in the foreground → a slow 45 s read to correct drift when a
//     live price stream marks them, 10 s when none does; 10 s for a
//     minute after an order or funding event either way.

import 'package:flutter/foundation.dart' show immutable;

/// The reconciliation read while positions are open and a live price
/// stream marks them.
const Duration kLiveMarksReconcileSlow = Duration(seconds: 45);

/// The read while positions are open and no stream marks them, and for
/// [kLiveMarksFastWindow] after an event.
const Duration kLiveMarksReconcileFast = Duration(seconds: 10);

/// How long an order or funding event keeps the fast read.
const Duration kLiveMarksFastWindow = Duration(minutes: 1);

/// The header takes at most one live-price update per this.
const Duration kLiveMarksThrottle = Duration(seconds: 1);

/// One Predictions position as its venue last read it.
@immutable
class HeldOutcome {
  const HeldOutcome(
      {required this.token, required this.size, required this.readPrice});

  /// The CLOB token id the market socket streams.
  final String token;
  final double size;

  /// The price the read valued it at (`curPrice`).
  final double readPrice;
}

/// One Investing perp as its venue last read it.
@immutable
class HeldPerp {
  const HeldPerp(
      {required this.coin, required this.szi, required this.positionValue});

  final String coin;

  /// Signed size: positive long, negative short.
  final double szi;

  /// |szi| × the mark at the read.
  final double positionValue;

  double? get readMark =>
      szi == 0 || !positionValue.isFinite ? null : positionValue / szi.abs();
}

bool _ok(double v) => v.isFinite;

/// Σ size × (live − read) over [held] with a live price. A token without
/// one adds nothing (its read value stands).
double predictionsMarkDelta(
    Iterable<HeldOutcome> held, Map<String, double> live) {
  var delta = 0.0;
  for (final h in held) {
    final price = live[h.token];
    if (price == null || !_ok(price) || price < 0 || price > 1) continue;
    if (!_ok(h.size) || h.size <= 0 || !_ok(h.readPrice)) continue;
    delta += h.size * (price - h.readPrice);
  }
  return delta;
}

/// Σ szi × (mid − read mark) over [held] with a live mid.
double investingMarkDelta(Iterable<HeldPerp> held, Map<String, double> mids) {
  var delta = 0.0;
  for (final h in held) {
    final mid = mids[h.coin];
    final mark = h.readMark;
    if (mid == null || mark == null || !_ok(mid) || mid <= 0) continue;
    if (!_ok(h.szi)) continue;
    delta += h.szi * (mid - mark);
  }
  return delta;
}

/// How often the venue is read again while the header is up, or null for
/// no periodic read at all (only events refresh it).
Duration? liveMarksReconcileInterval({
  required bool holds,
  required bool visible,
  required bool streamed,
  required DateTime now,
  DateTime? lastEventAt,
}) {
  if (!visible || !holds) return null;
  if (lastEventAt != null &&
      now.difference(lastEventAt) < kLiveMarksFastWindow) {
    return kLiveMarksReconcileFast;
  }
  return streamed ? kLiveMarksReconcileSlow : kLiveMarksReconcileFast;
}

/// The marks the header adds to the venues' last reads.
@immutable
class OneBalanceLiveMarks {
  const OneBalanceLiveMarks(
      {this.predictionsDeltaUsd = 0, this.investingDeltaUsd = 0});

  static const zero = OneBalanceLiveMarks();

  final double predictionsDeltaUsd;
  final double investingDeltaUsd;

  double get totalDeltaUsd => predictionsDeltaUsd + investingDeltaUsd;

  @override
  bool operator ==(Object other) =>
      other is OneBalanceLiveMarks &&
      other.predictionsDeltaUsd == predictionsDeltaUsd &&
      other.investingDeltaUsd == investingDeltaUsd;

  @override
  int get hashCode => Object.hash(predictionsDeltaUsd, investingDeltaUsd);

  @override
  String toString() => 'OneBalanceLiveMarks(predictions: $predictionsDeltaUsd, '
      'investing: $investingDeltaUsd)';
}
