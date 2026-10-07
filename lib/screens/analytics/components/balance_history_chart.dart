// lib/screens/analytics/components/balance_history_chart.dart
//
// The Balance chart of a Bitcoin wallet (spending, hardware, watch-only,
// Ledger) and of the Dollars account. No range picker: the account's
// whole history, from a short lead-in before its first change to now,
// fitted to the width (see balance_history.dart) and drawn in steps, in
// the balance's own unit (sats or BTC per the app's setting, dollars),
// with a quiet scale on the left so the height of the line means
// something. The scale's labels follow the balance privacy setting: with
// balances hidden only the hairlines stay. Pinch, pan and the long-press
// scrub card come from the shared [KuteLineChart] as on every other
// chart, with the time axis under the plot (when the window on screen
// starts, and "Now" or when it ends) and the one-time zoom nudge.
//
// The change above the plot is an amount, as the scrub card writes it
// ("+$12.30 (+1.2%)"), from the first point on screen. When that point
// is zero (the lead-in before the first deposit, which is what the
// chart opens on) there is no change to report that the headline does
// not already say, so the row stays empty rather than claiming
// "+100.0%".

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/balance_history.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/analytics/components/chart.dart'
    show ChartChangeText;
import 'package:kute/screens/shared/charts/kute_chart_format.dart';
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
    this.detailText,
    this.now,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final visible =
        ref.watch(settingsProvider.select((s) => s.balanceVisible));
    final samples = sampleBalanceHistory(history, now ?? DateTime.now());
    final values = <double>[for (final s in samples) s.$2];

    // Whole-series direction, as the other balance charts colour theirs.
    final first = values.first, last = values.last;
    final lineColor = last > first
        ? AppColors.marketUp
        : (last < first ? AppColors.marketDown : c.accent);

    final locale = kuteChartLocale(context);
    // A young account's window is hours long: the card then says when in
    // the day, not just which day.
    final intraday = samples.last.$1.difference(samples.first.$1) <=
        const Duration(days: 2);
    String timeOf(DateTime t) =>
        intraday ? kuteChartDayTime(t, locale) : kuteChartDay(t, locale);

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
        stepped: true,
        showScale: true,
        timeAxis: KuteLineTimeAxis(
          timeAt: (i) => samples[i].$1,
          nowLabel: context.l10n.betNow,
          locale: locale,
        ),
        zoomHint: true,
        scaleLabel: visible ? scaleLabel : null,
        summaryBuilder: (a, b) {
          final base = values[a];
          final delta = values[b] - base;
          final text = b > a && base != 0
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
            i >= 0 && i < samples.length ? timeOf(samples[i].$1) : null,
        detailTextBuilder: (i) {
          if (detailText == null || i < 0 || i >= samples.length) {
            return const [];
          }
          final t = detailText!(samples[i].$1, samples[i].$2);
          return t == null ? const [] : [t];
        },
      ),
    );
  }
}
