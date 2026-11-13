// lib/screens/shared/charts/kute_trend_window.dart
//
// What the trend charts (the P&L chart, the Bitcoin and Dollars Balance
// charts) share around [KuteTrendChart]: the points a range draws out of
// a [BalanceSeries] (each bucket's close inside the range and the last
// point), the period a range names after the change ("Past month") and
// the arrow before a change.

import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/balance_history.dart';

/// The points of [series] a range [span] points wide ending now draws:
/// the range's first point, each bucket's close inside it and the last
/// point (the P&L or balance now), with their moments. Shared with the
/// Balance charts.
({List<double> values, List<DateTime> times}) kuteTrendWindow(
    BalanceSeries series, double span) {
  final n = series.length;
  if (n == 0) return (values: const [], times: const []);
  final start = (series.extent - span).ceil().clamp(0, n - 1).toInt();
  final stride = series.strideFor(span);
  final values = <double>[];
  final times = <DateTime>[];
  for (var i = start; i < n; i++) {
    if (i == start || series.isDrawn(i, stride)) {
      values.add(series.values[i]);
      times.add(series.times[i]);
    }
  }
  return (values: values, times: times);
}

/// The period a range names after the change ("Past month").
String kuteTrendPeriodLabel(AppLocalizations l10n, BalanceRange range) =>
    switch (range) {
      BalanceRange.week => l10n.chartPeriodPastWeek,
      BalanceRange.month => l10n.chartPeriodPastMonth,
      BalanceRange.threeMonths => l10n.chartPeriodPast3Months,
      BalanceRange.year => l10n.chartPeriodPastYear,
      BalanceRange.all => l10n.chartPeriodAllTime,
    };

/// The arrow before a change: up, down, or none when flat.
String kuteTrendArrow(double delta) => delta > 0
    ? '▲ '
    : delta < 0
        ? '▼ '
        : '';
