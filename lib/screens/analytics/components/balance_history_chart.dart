// lib/screens/analytics/components/balance_history_chart.dart
//
// The Balance chart of a Bitcoin wallet (spending, hardware, watch-only,
// Ledger) and of the Dollars account. No range picker: it opens on the
// last 30 days at most, from the first moment in them that held money,
// ending now, and pinch out reaches the whole history (see
// balance_history.dart). The line is the closing balance of each bucket
// the window on screen calls for (a quarter hour to a week), drawn as
// the other line charts draw theirs (the monotone curve and its fill),
// so money passing through within a bucket never spikes it. It is in the
// balance's own unit (sats or BTC per the app's setting, dollars), with
// a quiet scale on the left fitted to the line on screen so the height
// of the line means something. The scale's labels follow the balance
// privacy setting: with balances hidden only the hairlines stay. Pinch
// (around the fingers), pan and the long-press scrub card come from the
// shared [KuteLineChart], with the time axis under the plot (when the
// window on screen starts, and "Now" or when it ends) and the one-time
// zoom nudge. A rebuild never moves a window the user zoomed or panned:
// the series only grows at its newest end as time passes.
//
// The change above the plot is an amount, as the scrub card writes it
// ("+$12.30 (+1.2%)"), from the first point on screen. When that point
// is zero there is no change to report that the headline does not
// already say, so the row stays empty rather than claiming "+100.0%".

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/balance_history.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/analytics/components/chart.dart'
    show ChartChangeText;
import 'package:kute/screens/shared/charts/kute_chart_format.dart';
import 'package:kute/screens/shared/charts/kute_chart_viewport.dart';
import 'package:kute/screens/shared/charts/kute_line_chart.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

class BalanceHistoryChart extends ConsumerWidget {
  /// The balance as the moments it changed, in the unit it is drawn in
  /// (sats for bitcoin, dollars).
  final BalanceHistory history;

  /// Writes an amount ("17,520 sats", "$12.30"); also writes the change.
  final String Function(double value) format;

  /// Writes a level of the scale on the left ("10K sats", "$5"), given
  /// the step between levels.
  final String Function(double level, double step) scaleLabel;

  /// The least step between two levels of the scale (one sat for
  /// bitcoin); null steps freely (dollars down to cents).
  final double? scaleMinStep;

  /// A quiet line under the scrub card's value for the point at [t]
  /// holding [held] (a bitcoin balance's value that day); null for none.
  final String? Function(DateTime t, double held)? detailText;

  /// `analytics_chart_scrubbed`'s chart name, as the old chart sent it.
  final String trackingChart;

  /// The moment the line ends on; now unless a test pins it.
  final DateTime? now;

  const BalanceHistoryChart({
    super.key,
    required this.history,
    required this.format,
    required this.scaleLabel,
    required this.trackingChart,
    this.scaleMinStep,
    this.detailText,
    this.now,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final visible =
        ref.watch(settingsProvider.select((s) => s.balanceVisible));
    final series = balanceSeries(history, now ?? DateTime.now());
    final values = series.values;
    final times = series.times;
    final defaultSpan = series.defaultSpan;

    final buckets =
        KuteLineBuckets(strideFor: series.strideFor, phase: series.phase);

    // The direction over the window the chart opens on, as the other
    // balance charts colour theirs; a pinch never recolours the line.
    final opening = KuteIndexWindow(series.extent - defaultSpan, series.extent);
    final first = values[buckets
        .indicesFor(values.length, opening)
        .firstWhere((i) => i >= opening.start - 1e-6, orElse: () => 0)];
    final last = values.last;
    final lineColor = last > first
        ? AppColors.marketUp
        : (last < first ? AppColors.marketDown : c.accent);

    final locale = kuteChartLocale(context);
    // On a daily grid a point at midnight closes the day before; finer
    // grids say when in the day.
    final daily = series.cellMinutes >= 1440;
    DateTime dayOf(DateTime t) => daily && t.hour == 0 && t.minute == 0
        ? t.subtract(const Duration(minutes: 1))
        : t;
    String timeOf(DateTime t) => daily
        ? kuteChartDay(dayOf(t), locale)
        : kuteChartDayTime(t, locale);

    Widget changeRow(Widget child) => Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: EdgeInsets.only(right: 4.w, bottom: 4.h),
            child: child,
          ),
        );

    return Padding(
      padding: EdgeInsets.only(top: 4.h),
      child: KuteLineChart(
        values: values,
        lineColor: lineColor,
        showScale: true,
        buckets: buckets,
        // A balance that barely moved reads as barely moving: the scale
        // spans at least a fifth of the balance.
        minScaleShare: 0.2,
        scaleMinStep: scaleMinStep,
        defaultSpan: defaultSpan,
        minSpan: series.minSpan,
        zoomAroundFingers: true,
        // The series gains a point as time passes: the window stays where
        // the user left it. Another history (another wallet, older
        // history landing, a coarser grid) opens afresh.
        resetViewOnLengthChange: false,
        viewResetKey: (
          history.changes.isEmpty ? null : history.changes.first.$1,
          history.opening > 0,
          series.cellMinutes,
        ),
        // A morph would draw the whole history for a beat before the
        // window: new data lands in place instead.
        animateChanges: false,
        timeAxis: KuteLineTimeAxis(
          timeAt: (i) => times[i],
          nowLabel: context.l10n.betNow,
          locale: locale,
        ),
        zoomHint: true,
        scaleLabel: visible ? scaleLabel : null,
        summaryBuilder: (a, b) {
          final base = values[a];
          final delta = values[b] - base;
          // No change (a balance that sat still) writes nothing.
          final text = b > a && base != 0 && delta != 0
              ? kuteChangeText(delta: delta, base: base, magnitude: format)
              : null;
          // The row keeps its height when empty, so a pinch that brings
          // the change in never shifts the plot.
          return changeRow(text == null
              ? const Visibility(
                  visible: false,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: ChartChangeText.written('+0', direction: 0),
                )
              : ChartChangeText.written(text, direction: delta.sign.toInt()));
        },
        onScrubStart: () => TrackingService.analyticsChartScrubbed(
            chart: trackingChart, view: 'line'),
        valueTextBuilder: (i) =>
            i >= 0 && i < values.length ? format(values[i]) : null,
        changeFormatter: format,
        timeTextBuilder: (i) =>
            i >= 0 && i < times.length ? timeOf(times[i]) : null,
        detailTextBuilder: (i) {
          if (detailText == null || i < 0 || i >= times.length) {
            return const [];
          }
          final t = detailText!(dayOf(times[i]), values[i]);
          return t == null ? const [] : [t];
        },
      ),
    );
  }
}
