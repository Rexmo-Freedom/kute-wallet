// The grid behind every trend chart (balance_history.dart, _grid) is laid
// on integer microseconds with its times made only when read (founder, 2
// November 2026: the P&L chart was "super slow", most of a frame laying
// 20,000 DateTimes). The series must be the very one the DateTime loop
// laid: [_referenceGrid] is that loop as it was, compared point for point
// over quarter-hour, hourly and daily grids, clock changes included.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/balance_history.dart';

/// The grid as the DateTime loop laid it (before 2 November 2026).
({List<DateTime> times, List<double> values, int cell, int phase})
    _referenceGrid(DateTime first, DateTime now, double opening,
        List<(DateTime, double)> changes, double current, bool floorAtZero) {
  double floor(double v) => floorAtZero && v < 0 ? 0.0 : v;
  if (first.isAfter(now)) first = now;
  final totalMinutes = now.difference(first).inMinutes;
  final cell = kBalanceCellMinutes.firstWhere(
      (m) => totalMinutes / m <= kBalanceMaxCells,
      orElse: () => kBalanceCellMinutes.last);
  final dayMinutes = first.hour * 60 + first.minute;
  final origin = DateTime(first.year, first.month, first.day, 0,
      dayMinutes - dayMinutes % cell);
  final phase = ((first.weekday - 1) * 1440 + dayMinutes) ~/ cell;
  DateTime at(int i) => cell >= 1440
      ? DateTime(origin.year, origin.month, origin.day + i)
      : origin.add(Duration(minutes: i * cell));
  final times = <DateTime>[];
  final values = <double>[];
  var j = 0;
  for (var i = 0;; i++) {
    final t = at(i);
    if (i > 0 && !t.isBefore(now)) break;
    final moment = i == 0 ? first : t;
    while (j < changes.length && !changes[j].$1.isAfter(moment)) {
      j++;
    }
    final held =
        changes.isEmpty ? current : (j == 0 ? opening : changes[j - 1].$2);
    times.add(i == 0 ? first : t);
    values.add(floor(held));
  }
  times.add(now);
  values.add(floor(current));
  return (times: times, values: values, cell: cell, phase: phase);
}

/// The range's first point as the linear scan found it.
int _referenceStart(List<DateTime> times, BalanceRange range) {
  final n = times.length;
  final back = range.duration;
  if (n < 2 || back == null) return 0;
  final from = times.last.subtract(back);
  var start = 0;
  while (start < n - 1 && times[start].isBefore(from)) {
    start++;
  }
  return start;
}

void main() {
  test('the grid is the DateTime loop\'s, point for point', () {
    final rnd = math.Random(7);
    final now = DateTime(2026, 11, 2, 14, 37, 12, 345);
    // Spans that land on each cell, across both clock changes of the
    // year, and a first moment after now.
    final spans = [
      const Duration(hours: 3),
      const Duration(days: 2),
      const Duration(days: 40),
      const Duration(days: 180),
      const Duration(days: 220),
      const Duration(days: 400),
      const Duration(days: 900),
      const Duration(days: 1500),
      const Duration(minutes: -5),
    ];
    for (final span in spans) {
      for (var run = 0; run < 6; run++) {
        final first = now.subtract(span).add(Duration(
            seconds: rnd.nextInt(3600), microseconds: rnd.nextInt(999)));
        final count = rnd.nextInt(300);
        final total = span.inSeconds.abs() + 7200;
        final changes = [
          for (final s
              in List.generate(count, (_) => rnd.nextInt(total))..sort())
            (
              now.subtract(span).add(Duration(seconds: s)),
              (rnd.nextDouble() - 0.4) * 100
            )
        ];
        final floorAtZero = run.isOdd;
        final opening = run % 3 == 0 ? 0.0 : 5.5;
        const current = 12.25;
        final expected = _referenceGrid(
            first, now, opening, changes, current, floorAtZero);
        final got = stepGridSeries(
            first: first,
            now: now,
            opening: opening,
            changes: changes,
            current: current,
            floorAtZero: floorAtZero);
        final label = 'span $span run $run';
        expect(got.cellMinutes, expected.cell, reason: label);
        expect(got.phase, expected.phase, reason: label);
        expect(got.length, expected.values.length, reason: label);
        expect(got.values, orderedEquals(expected.values), reason: label);
        for (var i = 0; i < got.length; i++) {
          final a = got.times[i], b = expected.times[i];
          expect(a, b, reason: '$label time $i');
          expect(a.isUtc, b.isUtc, reason: '$label time $i');
        }
        for (final range in BalanceRange.values) {
          final start = _referenceStart(expected.times, range);
          final n = expected.values.length;
          final span = n < 2 || range.duration == null
              ? (n - 1).toDouble()
              : math
                  .max((n - 1) - start, got.minSpan)
                  .clamp(0.0, (n - 1).toDouble())
                  .toDouble();
          expect(got.spanFor(range), span, reason: '$label $range');
        }
      }
    }
  });

  test('the grid\'s lists cannot be changed', () {
    final now = DateTime(2026, 11, 2, 14);
    final s = stepGridSeries(
        first: now.subtract(const Duration(days: 3)),
        now: now,
        opening: 0,
        changes: const [],
        current: 1);
    expect(() => s.times[1] = now, throwsUnsupportedError);
    expect(() => s.times.add(now), throwsUnsupportedError);
    expect(() => s.values[1] = 2, throwsUnsupportedError);
    expect(() => s.times[s.length], throwsRangeError);
  });
}
