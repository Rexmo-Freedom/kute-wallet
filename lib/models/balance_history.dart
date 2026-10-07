// lib/models/balance_history.dart
//
// A balance over time, kept as the moments it changed, and how the
// Balance charts (Bitcoin wallets and Dollars) turn that into a line.
//
// The Balance charts carry no range picker: they show the account's
// whole history, fitted to the width. The window opens a little before
// the first change (so the first step is visible, never glued to the
// left edge) and closes now. The series is sampled evenly in time across
// that window and drawn as steps, because a balance holds its value
// until money moves and then jumps: a sloped or smoothed line would say
// it grew gradually. A young account (one deposit today) gets the same
// treatment on its own short window: a short flat lead-in, the step,
// then flat to now, using the width.

/// A balance as the moments it changed: what was held before the first
/// change ([opening]), then each change as (when, held after), oldest
/// first. [current] is the balance now, which the line ends on.
class BalanceHistory {
  final double opening;
  final List<(DateTime, double)> changes;
  final double current;

  const BalanceHistory({
    required this.opening,
    required this.changes,
    required this.current,
  });

  /// What was held at [t]: the value after the last change at or before
  /// it, else the opening balance.
  double heldAt(DateTime t) {
    var lo = 0, hi = changes.length - 1, found = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (!changes[mid].$1.isAfter(t)) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return found < 0 ? opening : changes[found].$2;
  }
}

/// How many points a Balance chart is drawn from: enough that a step is
/// a step at phone width (about 1.5 px apart) and a pinch still finds
/// detail, few enough to paint cheaply.
const int kBalanceHistorySamples = 241;

/// The share of the window spent before the first change: a short flat
/// lead-in, so the first step reads as a step and not as the left edge.
const double kBalanceHistoryLeadIn = 1 / 12;

/// The window a Balance chart shows: from shortly before the first
/// change to [now]. With no change on record it is the last week, flat.
({DateTime start, DateTime end}) balanceHistoryWindow(
    BalanceHistory h, DateTime now) {
  if (h.changes.isEmpty) {
    return (start: now.subtract(const Duration(days: 7)), end: now);
  }
  final first = h.changes.first.$1;
  final last = h.changes.last.$1;
  var end = now.isBefore(last) ? last : now;
  // A change this very minute still gets a window to sit in.
  const minSpan = Duration(minutes: 1);
  if (end.difference(first) < minSpan) end = first.add(minSpan);
  final span = end.difference(first);
  final lead = Duration(
      microseconds: (span.inMicroseconds * kBalanceHistoryLeadIn).round());
  return (start: first.subtract(lead), end: end);
}

/// The balance sampled evenly across [balanceHistoryWindow]: (when, held)
/// per point, oldest first. The last point is [BalanceHistory.current],
/// so the line ends on the figure the header shows.
List<(DateTime, double)> sampleBalanceHistory(
  BalanceHistory h,
  DateTime now, {
  int samples = kBalanceHistorySamples,
}) {
  final w = balanceHistoryWindow(h, now);
  final n = samples < 2 ? 2 : samples;
  final total = w.end.difference(w.start).inMicroseconds;
  return List<(DateTime, double)>.generate(n, (i) {
    final t = i == n - 1
        ? w.end
        : w.start.add(Duration(microseconds: (total * i / (n - 1)).round()));
    // With nothing on record the balance as it stands is all we know.
    final held =
        i == n - 1 || h.changes.isEmpty ? h.current : h.heldAt(t);
    return (t, held < 0 ? 0.0 : held);
  }, growable: false);
}
