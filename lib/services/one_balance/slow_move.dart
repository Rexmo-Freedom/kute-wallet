// lib/services/one_balance/slow_move.dart
//
// When a money move counts as running longer than expected, so its
// journey says so in one calm line ("Taking longer than expected…",
// `MoneyStepsView.slow`): on the slip while an order's funding runs, and
// in a processing move's Activity detail.

/// How long a move without an estimate runs before it counts as slow.
const Duration kSlowMoveFallback = Duration(seconds: 90);

/// How long a move runs before it counts as slow: one and a half times
/// its route's [estimate] when there is one, else [kSlowMoveFallback].
Duration slowMoveAfter({Duration? estimate}) =>
    estimate == null || estimate <= Duration.zero
        ? kSlowMoveFallback
        : estimate * 1.5;

/// Whether a move that started at [startedAt] and is still running at
/// [now] counts as slow.
bool moveIsSlow(DateTime startedAt, DateTime now, {Duration? estimate}) =>
    !now.difference(startedAt).isNegative &&
    now.difference(startedAt) >= slowMoveAfter(estimate: estimate);
