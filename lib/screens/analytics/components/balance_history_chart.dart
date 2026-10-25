// lib/screens/analytics/components/balance_history_chart.dart
//
// The Balance chart of a Bitcoin wallet (spending, hardware, watch-only,
// Ledger) and of the Dollars account, in the style of a brokerage app's
// balance chart:
//
//   * a range row under the plot (1W 1M 3M 1Y ALL, the app's range
//     pills), 1M to start and remembered for the session; a range shows
//     its stretch ending now, never reaching back before the account
//     first held money (see balance_history.dart), and tapping a range
//     (the selected one too) puts a pinched or panned view back on it;
//   * the line is the closing balance of each bucket the window on screen
//     calls for (a quarter hour to a week), so money passing through
//     within a bucket never spikes it, drawn as the other line charts draw
//     theirs (the monotone curve, a soft fill of its own hue) in the
//     neutral chart colour, never red or green by direction;
//   * no scale and no gridlines: a faint dotted baseline at the first
//     value on screen says whether the line ended up or down;
//   * above the plot one quiet line: the change over the window
//     ("+₿6,938 past month (+12.4%)"), only the figures coloured, no
//     percent from a start of zero or for a change of 100% or more; while
//     a finger scrubs (long press, then slide) the line says the balance
//     under it and when ("₿28,104 · Oct 16 14:00"), and the hairline and
//     dot follow the finger;
//   * a range where the balance is zero throughout draws a calm flat line
//     with one quiet sentence above it, and nothing else;
//   * with balances hidden the figures are dots, as on the home header;
//   * pinch (around the fingers) and pan move inside the whole history,
//     with the time axis under the plot (when the window starts, and
//     "Now" or when it ends) and the one-time zoom nudge. A rebuild never
//     moves a window the user zoomed or panned: the series only grows at
//     its newest end as time passes.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart' show DateFormat;

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/balance_history.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/charts/kute_chart_format.dart';
import 'package:kute/screens/shared/charts/kute_chart_range_pills.dart';
import 'package:kute/screens/shared/charts/kute_chart_viewport.dart';
import 'package:kute/screens/shared/charts/kute_line_chart.dart';
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

  /// Writes an amount without a sign ("₿17,520", "$12.30"): the scrubbed
  /// balance and the size of the change.
  final String Function(double value) format;

  /// The sentence over a range where the balance is zero throughout.
  final String emptyMessage;

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
    required this.emptyMessage,
    required this.trackingChart,
    this.rangeKey = 'bitcoin',
    this.now,
  });

  @override
  ConsumerState<BalanceHistoryChart> createState() =>
      _BalanceHistoryChartState();
}

class _BalanceHistoryChartState extends ConsumerState<BalanceHistoryChart> {
  /// Bumped by a range tap, so the same range tapped again also puts a
  /// pinched or panned view back on it.
  int _rangeTaps = 0;

  /// The placeholder the change line is written around, so the amount
  /// alone takes the colour whatever the language puts around it.
  static const String _slot = '\u0001';

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
    final series = balanceSeries(widget.history, widget.now ?? DateTime.now());
    final values = series.values;
    final times = series.times;
    final span = series.spanFor(range);
    final buckets =
        KuteLineBuckets(strideFor: series.strideFor, phase: series.phase);

    /// The drawn values inside [w].
    List<double> drawnIn(KuteIndexWindow w) => [
          for (final i in buckets.indicesFor(values.length, w))
            if (i >= w.start - 1e-6 && i <= w.end + 1e-6) values[i]
        ];
    bool zeroIn(KuteIndexWindow w) => drawnIn(w).every((v) => v == 0);
    final empty =
        zeroIn(KuteIndexWindow(series.extent - span, series.extent));

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
    // A date inside a sentence: the year only when it is not this one.
    String dateOf(DateTime t) {
      final d = dayOf(t);
      return d.year == times.last.year
          ? DateFormat.MMMd(locale).format(d)
          : DateFormat.yMMMd(locale).format(d);
    }

    final quiet = TextStyle(
      color: c.textSecondary,
      fontSize: 13.sp,
      fontWeight: FontWeight.w500,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    Widget headerRow(InlineSpan span) => Padding(
          padding: EdgeInsets.only(left: 2.w, bottom: 8.h),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text.rich(span,
                key: const ValueKey('balance-chart-header'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: quiet),
          ),
        );

    Widget header(KuteLineView view) {
      final touched = view.touched;
      if (touched != null) {
        return headerRow(TextSpan(children: [
          TextSpan(
            text: amount(values[touched]),
            style:
                TextStyle(color: c.textPrimary, fontWeight: FontWeight.w700),
          ),
          TextSpan(text: ' · ${timeOf(times[touched])}'),
        ]));
      }
      // Nothing held on screen: the plot says so; the row keeps its
      // height so the plot never shifts.
      if (zeroIn(view.window)) return headerRow(const TextSpan(text: ' '));

      final base = values[view.first];
      final delta = values[view.last] - base;
      final live = view.window.end >= series.extent - 1e-6;
      final start = times[view.first];
      if (delta == 0) {
        final text = view.isDefault && range != BalanceRange.all
            ? switch (range) {
                BalanceRange.week => l10n.balanceNoChangePastWeek,
                BalanceRange.month => l10n.balanceNoChangePastMonth,
                BalanceRange.threeMonths => l10n.balanceNoChangePast3Months,
                _ => l10n.balanceNoChangePastYear,
              }
            : live
                ? l10n.balanceNoChangeSince(dateOf(start))
                : l10n.balanceNoChangeBetween(
                    dateOf(start), dateOf(times[view.last]));
        return headerRow(TextSpan(text: text));
      }

      final sentence = view.isDefault
          ? switch (range) {
              BalanceRange.week => l10n.balanceChangePastWeek(_slot),
              BalanceRange.month => l10n.balanceChangePastMonth(_slot),
              BalanceRange.threeMonths => l10n.balanceChangePast3Months(_slot),
              BalanceRange.year => l10n.balanceChangePastYear(_slot),
              BalanceRange.all => l10n.balanceChangeAllTime(_slot),
            }
          : live
              ? l10n.balanceChangeSince(_slot, dateOf(start))
              : l10n.balanceChangeBetween(
                  _slot, dateOf(start), dateOf(times[view.last]));
      final color = delta > 0 ? AppColors.marketUp : AppColors.marketDown;
      final percent = base != 0 ? delta / base.abs() * 100 : null;
      final parts = sentence.split(_slot);
      return headerRow(TextSpan(children: [
        TextSpan(text: parts.first),
        TextSpan(
          text: visible
              ? '${kuteChangeSign(delta)}${amount(delta.abs())}'
              : amount(delta.abs()),
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
        if (parts.length > 1) TextSpan(text: parts.sublist(1).join()),
        // A small percent after the sentence, only where it means
        // something: never from zero, never "-100.0%" for an account
        // emptied.
        if (visible && percent != null && percent.abs() < 100)
          TextSpan(
            text: ' (${kuteSignedPercent(percent)})',
            style: TextStyle(
                color: color, fontSize: 11.sp, fontWeight: FontWeight.w600),
          ),
      ]));
    }

    final chart = KuteLineChart(
      values: values,
      // The neutral chart colour: a balance is not a gain or a loss.
      lineColor: c.accent,
      showFill: !empty,
      startBaseline: true,
      buckets: buckets,
      // A balance that barely moved reads as barely moving.
      minScaleShare: 0.2,
      defaultSpan: span,
      minSpan: series.minSpan,
      zoomAroundFingers: true,
      // The series gains a point as time passes: the window stays where
      // the user left it. Another range, the range tapped again, or
      // another history (another wallet, older history landing, a coarser
      // grid) opens afresh.
      resetViewOnLengthChange: false,
      viewResetKey: (
        widget.history.changes.isEmpty
            ? null
            : widget.history.changes.first.$1,
        widget.history.opening > 0,
        series.cellMinutes,
        range,
        _rangeTaps,
      ),
      // A morph would draw the whole history for a beat before the
      // window: new data lands in place instead.
      animateChanges: false,
      timeAxis: KuteLineTimeAxis(
        timeAt: (i) => times[i],
        nowLabel: l10n.betNow,
        locale: locale,
      ),
      zoomHint: true,
      headerBuilder: header,
      plotOverlay: (window) => !zeroIn(window)
          ? const SizedBox.shrink()
          : Align(
              alignment: const Alignment(0, -0.4),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12.w),
                child: Text(
                  widget.emptyMessage,
                  key: const ValueKey('balance-chart-empty'),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(
                    color: c.textTertiary,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
      // The scrubbed point is written in the header, not on a card.
      onScrub: (_) {},
      onScrubStart: () => TrackingService.analyticsChartScrubbed(
          chart: widget.trackingChart, view: 'line'),
    );

    return Padding(
      padding: EdgeInsets.only(top: 4.h),
      child: Column(
        children: [
          Expanded(child: chart),
          SizedBox(height: 8.h),
          KuteRangePills(
            key: const ValueKey('balance-chart-ranges'),
            labels: [for (final r in BalanceRange.values) r.label],
            selectedIndex: range.index,
            onSelected: (i) {
              ref
                  .read(balanceChartRangeProvider(widget.rangeKey).notifier)
                  .state = BalanceRange.values[i];
              setState(() => _rangeTaps++);
            },
          ),
        ],
      ),
    );
  }
}
