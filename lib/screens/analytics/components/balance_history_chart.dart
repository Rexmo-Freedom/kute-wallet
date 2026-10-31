// lib/screens/analytics/components/balance_history_chart.dart
//
// The Balance chart of a Bitcoin wallet (spending, hardware, watch-only,
// Ledger) and of the Dollars account, drawn through the modern line chart
// ([KuteTrendChart], founder, 31 October 2026: "make the graph modern"):
//
//   * a header the chart owns: the balance as the headline (the balance
//     now, or the balance under a scrubbing finger), an optional second
//     line under it ([BalanceHistoryChart.secondary]: the fiat worth of a
//     bitcoin balance), then one quiet change line "▲ ₿6,938 (12.4%) ·
//     Past month": the arrow, the amount and a small percent in the
//     change's colour (no percent from a start of zero or for a change of
//     100% or more), the period after a middle dot; while a finger scrubs
//     the change is to the point under it and the tail is its moment
//     ("Oct 16 14:00"); flat: "No change · Past month";
//   * the plot: the closing balance of each bucket the range calls for (a
//     quarter hour to a week), so money passing through within a bucket
//     never spikes it; ONE line in the result colour of the range (up,
//     down, the text colour when flat), its fill, a dashed hairline at
//     the range's first value; no axes, no grid, no labels;
//   * a range row 16 px under the plot (1W 1M 3M 1Y ALL, the small white
//     pill), 1M to start and remembered per chart for the session;
//     picking a range morphs the line;
//   * NO HISTORY (the account never held money): no chart and no range
//     row, the headline and one quiet caption under it ("Your balance
//     history starts with your first transaction.");
//   * with balances hidden the figures are dots, as on the home header.
//
// Analytics: `analytics_chart_scrubbed` {chart, view: line}, once per
// scrub gesture. Ranges send nothing.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/balance_history.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/charts/kute_chart_format.dart';
import 'package:kute/screens/shared/charts/kute_trend_chart.dart';
import 'package:kute/screens/shared/charts/kute_trend_window.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// The range each Balance chart shows, per chart ([BalanceHistoryChart.
/// rangeKey]), for the rest of the session: the past month to start.
final balanceChartRangeProvider =
    StateProvider.family<BalanceRange, String>((ref, key) => BalanceRange.month);

class BalanceHistoryChart extends ConsumerStatefulWidget {
  /// The balance as the moments it changed, in the unit it is drawn in
  /// (sats for bitcoin, dollars).
  final BalanceHistory history;

  /// Writes an amount without a sign ("₿17,520", "$12.30"): the headline,
  /// the scrubbed balance and the size of the change.
  final String Function(double value) format;

  /// Writes the second line under the headline for a balance (its fiat
  /// worth); null draws none.
  final String? Function(double value)? secondary;

  /// Which session range this chart remembers ('bitcoin', 'dollars').
  final String rangeKey;

  /// `analytics_chart_scrubbed`'s chart name, as the old chart sent it.
  final String trackingChart;

  /// The moment the line ends on; now unless a test pins it.
  final DateTime? now;

  const BalanceHistoryChart({
    super.key,
    required this.history,
    required this.format,
    required this.trackingChart,
    this.secondary,
    this.rangeKey = 'bitcoin',
    this.now,
  });

  @override
  ConsumerState<BalanceHistoryChart> createState() =>
      _BalanceHistoryChartState();
}

class _BalanceHistoryChartState extends ConsumerState<BalanceHistoryChart> {
  /// The point under the finger; null at rest.
  KuteTrendPoint? _scrub;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final range = ref.watch(balanceChartRangeProvider(widget.rangeKey));
    // With balances hidden the figures are dots, as on the home header,
    // and the change carries no percent.
    final visible =
        ref.watch(settingsProvider.select((s) => s.balanceVisible));
    String amount(double v) => visible ? widget.format(v) : '••••••';
    final history = widget.history;
    final hasHistory = history.changes.isNotEmpty || history.opening > 0;
    final series = balanceSeries(history, widget.now ?? DateTime.now());
    final span = series.spanFor(range);
    final shown = kuteTrendWindow(series, span);
    final values = shown.values;
    final times = shown.times;
    final scrub = _scrub;
    final scrubbing = scrub != null && scrub.index < values.length;

    final locale = kuteChartLocale(context);
    // On a daily grid a point at midnight closes the day before; finer
    // grids say when in the day.
    final daily = series.cellMinutes >= 1440;
    String timeOf(DateTime t) {
      final d = daily && t.hour == 0 && t.minute == 0
          ? t.subtract(const Duration(minutes: 1))
          : t;
      return daily ? kuteChartDay(d, locale) : kuteChartDayTime(t, locale);
    }

    // The headline: the balance now, or under the finger.
    final headline = scrubbing
        ? scrub.value
        : (values.isNotEmpty ? values.last : history.current);
    final secondaryText = widget.secondary?.call(headline);

    final quiet = TextStyle(
      color: c.textSecondary,
      fontSize: 13.sp,
      fontWeight: FontWeight.w500,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    Widget changeLine() {
      if (values.length < 2) return const SizedBox.shrink();
      final base = values.first;
      final to = scrubbing ? scrub.value : values.last;
      final delta = to - base;
      final percent = base != 0 ? delta / base.abs() * 100 : null;
      final tail = scrubbing
          ? timeOf(scrub.time ?? times.last)
          : kuteTrendPeriodLabel(l10n, range);
      final color = delta > 0
          ? AppColors.marketUp
          : delta < 0
              ? AppColors.marketDown
              : c.textSecondary;
      return Padding(
        padding: EdgeInsets.only(top: 4.h),
        child: Text.rich(
          TextSpan(children: [
            if (delta == 0 && visible)
              TextSpan(text: l10n.chartNoChange)
            else ...[
              TextSpan(
                text: '${kuteTrendArrow(delta)}${amount(delta.abs())}',
                style: TextStyle(
                    color: visible ? color : c.textPrimary,
                    fontWeight: FontWeight.w700),
              ),
              // A small percent, only where it means something: never
              // from zero, never "-100.0%" for an account emptied.
              if (visible && percent != null && percent.abs() < 100)
                TextSpan(
                  text: ' (${kuteSignedPercent(percent)})',
                  style: TextStyle(
                      color: color,
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w600),
                ),
            ],
            TextSpan(text: ' · $tail'),
          ]),
          key: const ValueKey('balance-chart-header'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: quiet,
        ),
      );
    }

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        RollingNumberText(
          key: const ValueKey('balance-chart-headline'),
          text: amount(headline),
          duration: Duration(milliseconds: scrubbing ? 120 : 350),
          dimColor: c.textTertiary,
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 18.sp,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            height: 1.0,
          ),
        ),
        if (secondaryText != null) ...[
          SizedBox(height: 2.h),
          RollingNumberText(
            key: const ValueKey('balance-chart-secondary'),
            text: visible ? secondaryText : '••••••',
            duration: Duration(milliseconds: scrubbing ? 120 : 350),
            style: TextStyle(
              color: c.textTertiary,
              fontSize: 14.sp,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
        if (hasHistory) changeLine(),
        if (!hasHistory)
          Padding(
            padding: EdgeInsets.only(top: 4.h),
            child: Text(
              l10n.balanceChartNoHistory,
              key: const ValueKey('balance-chart-empty'),
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 12.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );

    final chart = KuteTrendChart(
      key: const ValueKey('balance-chart'),
      values: hasHistory ? values : const [],
      times: hasHistory ? times : null,
      height: kKuteTrendPlotHeight.h,
      onScrub: (p) => setState(() => _scrub = p),
      onScrubStart: () => TrackingService.analyticsChartScrubbed(
          chart: widget.trackingChart, view: 'line'),
      rangeLabels: [for (final r in BalanceRange.values) r.label],
      selectedRange: range.index,
      onRangeSelected: (i) {
        ref.read(balanceChartRangeProvider(widget.rangeKey).notifier).state =
            BalanceRange.values[i];
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        header,
        if (hasHistory) ...[SizedBox(height: 12.h), chart],
      ],
    );
  }
}
