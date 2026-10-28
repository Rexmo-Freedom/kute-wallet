// lib/models/balance_history.dart
//
// A balance over time, kept as the moments it changed, and how the
// Balance charts (Bitcoin wallets and Dollars) turn that into a line.
//
// The series is laid on an even grid in wall-clock time (a quarter
// hour, an hour or a day apart, the finest that keeps a long history
// under [kBalanceMaxCells] points), from a short lead-in before the
// account first held money that stayed (money that came and went the same
// day does not start the history) to now; the last point is the balance
// now. The lead-in lets the line rise from what was held before, so the
// change over a range that reaches the start reads from there. Each grid point
// holds the balance at that moment, which is the closing balance of the
// stretch that ends there. The chart draws only every few points, as
// many as the window on screen calls for ([balanceBucketMinutes]: a
// quarter hour under a day, hourly under a week, daily, weekly past a
// year), and a balance held for less than [kBalanceSettle] is not drawn
// at all, so money that passes through (in and out minutes later, a
// top-up routed on to Investments) never spikes the line or the scale,
// and a pinch re-buckets as it goes. Buckets close on
// the hour, at midnight and on Mondays, wherever the series starts.
//
// The chart shows a range ([BalanceRange]: the past week, month, three
// months, year, or all of it) ending now, never reaching back past the
// lead-in ([BalanceSeries.spanFor]); pinch and pan move inside the whole
// history.

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

/// The share of the history spent on the lead-in before the first money
/// held (or before the first change, when money was already held before
/// it): a short flat stretch, so the first change reads as a change and
/// not as the edge.
const double kBalanceHistoryLeadIn = 1 / 12;

/// The shortest lead-in, so a deposit minutes old still rises from what
/// was held before it.
const Duration kBalanceMinLeadIn = Duration(hours: 1);

/// How long a balance must hold to be drawn at all: a balance that lasted
/// less (money in and straight on to Investments, a send moments after a
/// receive) is passing through, not held, whatever bucket boundary it
/// straddles. The balance now always counts.
const Duration kBalanceSettle = Duration(hours: 1);

/// The ranges a Balance chart offers under the plot, each ending now.
enum BalanceRange {
  week('1W', Duration(days: 7)),
  month('1M', Duration(days: 30)),
  threeMonths('3M', Duration(days: 91)),
  year('1Y', Duration(days: 365)),
  all('ALL', null);

  const BalanceRange(this.label, this.duration);

  /// The pill's label, as every range row in the app writes it.
  final String label;

  /// How far back it reaches; null is the whole history.
  final Duration? duration;
}

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

  /// The window [range] shows, in points, ending now: from the first
  /// point inside it (the whole history for [BalanceRange.all], or when
  /// the account is younger than the range), never under [minSpan].
  double spanFor(BalanceRange range) {
    final n = values.length;
    final back = range.duration;
    if (n < 2 || back == null) return extent;
    final from = times.last.subtract(back);
    var start = 0;
    while (start < n - 1 && times[start].isBefore(from)) {
      start++;
    }
    return math.max(extent - start, minSpan).clamp(0.0, extent).toDouble();
  }
}

/// [h] laid on the grid up to [now] (see the file comment).
BalanceSeries balanceSeries(BalanceHistory raw, DateTime now) {
  // Only balances that held for [kBalanceSettle] (or still hold now): a
  // chain of moves minutes apart reads as the balance it settled on.
  final settled = <(DateTime, double)>[
    for (var k = 0; k < raw.changes.length; k++)
      if (k == raw.changes.length - 1 ||
          raw.changes[k + 1].$1.difference(raw.changes[k].$1) >=
              kBalanceSettle)
        raw.changes[k]
  ];
  final h = BalanceHistory(
      opening: raw.opening, changes: settled, current: raw.current);
  // Where the history starts: the first money held that stayed past the
  // day it came in (a deposit routed straight on does not start it), or
  // with money held before the first change on record, that change; with
  // nothing on record, the last week, flat. The line starts a short
  // lead-in before it.
  DateTime first;
  if (h.changes.isEmpty) {
    first = now.subtract(const Duration(days: 7));
  } else {
    var start = h.changes.first.$1;
    if (h.opening <= 0) {
      DateTime? held, stayed;
      for (final c in h.changes) {
        if (c.$2 <= 0) continue;
        held ??= c.$1;
        final midnight = DateTime(c.$1.year, c.$1.month, c.$1.day + 1);
        if (h.heldAt(midnight.isBefore(now) ? midnight : now) > 0) {
          stayed = c.$1;
          break;
        }
      }
      start = stayed ?? held ?? start;
    }
    if (start.isAfter(now)) start = now;
    var lead = Duration(
        microseconds:
            (now.difference(start).inMicroseconds * kBalanceHistoryLeadIn)
                .round());
    if (lead < kBalanceMinLeadIn) lead = kBalanceMinLeadIn;
    first = start.subtract(lead);
  }
  return stepGridSeries(
    first: first,
    now: now,
    opening: h.opening,
    changes: h.changes,
    current: h.current,
    floorAtZero: true,
  );
}

/// A value that moves in steps ([opening] before the first of [changes],
/// each change as (when, value after), oldest first, [current] now) laid
/// on the Balance charts' even grid from [first] to [now] (see the file
/// comment): each grid point holds the value at that moment, the close of
/// the stretch ending there, and the last point is [current] at [now].
/// With no change on record every point is [current]. [floorAtZero] keeps
/// a balance from reading below nothing; a profit and loss
/// (portfolio_performance.dart's pnlSeries) goes below zero.
BalanceSeries stepGridSeries({
  required DateTime first,
  required DateTime now,
  required double opening,
  required List<(DateTime, double)> changes,
  required double current,
  bool floorAtZero = false,
}) {
  double floor(double v) => floorAtZero && v < 0 ? 0.0 : v;
  return _grid(first.isAfter(now) ? now : first, now, opening, changes,
      current, floor);
}

BalanceSeries _grid(DateTime first, DateTime now, double opening,
    List<(DateTime, double)> changes, double current,
    double Function(double) floor) {
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
    final moment = i == 0 ? first : t;
    while (j < changes.length && !changes[j].$1.isAfter(moment)) {
      j++;
    }
    // With nothing on record the value as it stands is all we know.
    final held =
        changes.isEmpty ? current : (j == 0 ? opening : changes[j - 1].$2);
    times.add(i == 0 ? first : t);
    values.add(floor(held));
  }
  // The line ends on the value now, the figure the header shows.
  times.add(now);
  values.add(floor(current));
  return BalanceSeries(
    times: List.unmodifiable(times),
    values: List.unmodifiable(values),
    cellMinutes: cell,
    phase: phase,
  );
}
