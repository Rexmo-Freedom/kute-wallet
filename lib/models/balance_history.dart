// lib/models/balance_history.dart
//
// A balance over time, kept as the moments it changed, and how the
// Balance charts (Bitcoin wallets and Dollars) turn that into a line.
//
// The series is laid on an even grid in wall-clock time (a quarter
// hour, an hour or a day apart, the finest that keeps a long history
// under [kBalanceMaxCells] points), from the moment the account first
// held money to now; the last point is the balance now. Each grid point
// holds the balance at that moment, which is the closing balance of the
// stretch that ends there. The chart draws only every few points, as
// many as the window on screen calls for ([balanceBucketMinutes]: a
// quarter hour under a day, hourly under a week, daily, weekly past a
// year), so money that passes through within one bucket (in and out
// minutes later, a top-up routed on to Investments) never spikes the
// line or the scale, and a pinch re-buckets as it goes. Buckets close on
// the hour, at midnight and on Mondays, wherever the series starts.
//
// The chart opens on the last 30 days at most, and never on a stretch of
// zero before the account held money: it starts on the first bucket in
// that window that closes on a balance ([BalanceSeries.defaultSpan]).
// Pinch out reaches the whole history.

import 'dart:math' as math;

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

/// The grid a Balance chart's series can be laid on, finest first, in
/// minutes: a quarter hour, an hour, a day.
const List<int> kBalanceCellMinutes = [15, 60, 1440];

/// The most grid points a series is laid on: the finest grid that keeps
/// the history under this wins (a quarter hour for about 200 days, an
/// hour for about two years).
const int kBalanceMaxCells = 20000;

/// The share of the window spent before the first change when money was
/// already held before it (a history that starts mid-way): a short flat
/// lead-in, so the first change reads as a change and not as the edge.
const double kBalanceHistoryLeadIn = 1 / 12;

/// The longest window a Balance chart opens on, ending now.
const Duration kBalanceDefaultWindow = Duration(days: 30);

/// The closest a pinch gets: a few hours on screen.
const Duration kBalanceMinWindow = Duration(hours: 4);

/// The bucket a window [span] long is drawn in, in minutes: a quarter
/// hour under a day, an hour under a week, a day under about a year, a
/// week past that. Every bucket is a whole number of the finer ones.
int balanceBucketMinutes(Duration span) {
  if (span <= const Duration(days: 1)) return 15;
  if (span <= const Duration(days: 7)) return 60;
  if (span <= const Duration(days: 400)) return 1440;
  return 10080;
}

/// A balance laid on an even grid for the Balance chart (see the file
/// comment): [times] and [values] per point, oldest first, the last one
/// now and the balance now.
class BalanceSeries {
  final List<DateTime> times;
  final List<double> values;

  /// The grid step, in minutes (one of [kBalanceCellMinutes]).
  final int cellMinutes;

  /// Grid steps from the Monday midnight before the first point to it,
  /// so buckets close on the hour, at midnight and on Mondays.
  final int phase;

  const BalanceSeries({
    required this.times,
    required this.values,
    required this.cellMinutes,
    required this.phase,
  });

  int get length => values.length;

  /// The last index.
  double get extent => (values.length - 1).toDouble();

  /// The points between drawn points for a window [span] points wide.
  int strideFor(double span) {
    final minutes = (span * cellMinutes).round();
    final bucket = balanceBucketMinutes(Duration(minutes: minutes));
    return bucket <= cellMinutes ? 1 : bucket ~/ cellMinutes;
  }

  /// Whether point [i] is drawn at [stride]: a bucket's close, or the
  /// last point (the balance now). Before the first close the line holds
  /// that close's level, so the first point never shows on its own.
  bool isDrawn(int i, int stride) =>
      i == values.length - 1 || (i + phase) % stride == 0;

  /// The closest a pinch gets, in points: [kBalanceMinWindow], at least
  /// two points, never more than the whole.
  double get minSpan => math.min(
      extent, math.max(2.0, kBalanceMinWindow.inMinutes / cellMinutes));

  /// The window the chart opens on, in points, ending now: the last
  /// [kBalanceDefaultWindow] at most, starting on the first drawn point
  /// in it that holds money when the line would otherwise open on zero (a
  /// wallet funded yesterday opens on yesterday, not on weeks of nothing
  /// or on money that came and went within a bucket weeks ago).
  double get defaultSpan {
    final n = values.length;
    if (n < 2) return extent;
    final from = times.last.subtract(kBalanceDefaultWindow);
    var start = 0;
    while (start < n - 1 && times[start].isBefore(from)) {
      start++;
    }
    final stride = strideFor((n - 1 - start).toDouble());
    var first = start;
    while (!isDrawn(first, stride)) {
      first++;
    }
    if (values[first] <= 0) {
      for (var i = first + 1; i < n; i++) {
        if (isDrawn(i, stride) && values[i] > 0) {
          start = i;
          break;
        }
      }
    }
    return math.max(extent - start, minSpan).clamp(0.0, extent).toDouble();
  }
}

/// [h] laid on the grid up to [now] (see the file comment).
BalanceSeries balanceSeries(BalanceHistory h, DateTime now) {
  // Where the line starts: when money was first held, or (money held
  // before the first change on record) a short lead-in before it; with
  // nothing on record, the last week, flat.
  DateTime first;
  if (h.changes.isEmpty) {
    first = now.subtract(const Duration(days: 7));
  } else if (h.opening > 0) {
    final c0 = h.changes.first.$1;
    final span = (now.isAfter(c0) ? now : c0).difference(c0);
    first = c0.subtract(Duration(
        microseconds: (span.inMicroseconds * kBalanceHistoryLeadIn).round()));
  } else {
    first = h.changes
        .firstWhere((c) => c.$2 > 0, orElse: () => h.changes.first)
        .$1;
  }
  if (first.isAfter(now)) first = now;

  final totalMinutes = now.difference(first).inMinutes;
  final cell = kBalanceCellMinutes.firstWhere(
      (m) => totalMinutes / m <= kBalanceMaxCells,
      orElse: () => kBalanceCellMinutes.last);

  // The grid from the step at or before [first]: even steps of time, or
  // calendar days on a daily grid, so a day stays a day across a clock
  // change.
  final dayMinutes = first.hour * 60 + first.minute;
  final origin = DateTime(first.year, first.month, first.day, 0,
      dayMinutes - dayMinutes % cell);
  final phase = ((first.weekday - 1) * 1440 + dayMinutes) ~/ cell;
  DateTime at(int i) => cell >= 1440
      ? DateTime(origin.year, origin.month, origin.day + i)
      : origin.add(Duration(minutes: i * cell));

  final times = <DateTime>[];
  final values = <double>[];
  var j = 0; // changes at or before the point
  for (var i = 0;; i++) {
    final t = at(i);
    if (i > 0 && !t.isBefore(now)) break;
    // The first point is the moment the line starts, not the step before
    // it, so the line opens on the money first held, never on a zero.
    final moment = i == 0 ? first : t;
    while (j < h.changes.length && !h.changes[j].$1.isAfter(moment)) {
      j++;
    }
    // With nothing on record the balance as it stands is all we know.
    final held = h.changes.isEmpty
        ? h.current
        : (j == 0 ? h.opening : h.changes[j - 1].$2);
    times.add(i == 0 ? first : t);
    values.add(held < 0 ? 0.0 : held);
  }
  // The line ends on the balance now, the figure the header shows.
  times.add(now);
  values.add(h.current < 0 ? 0.0 : h.current);
  return BalanceSeries(
    times: List.unmodifiable(times),
    values: List.unmodifiable(values),
    cellMinutes: cell,
    phase: phase,
  );
}
