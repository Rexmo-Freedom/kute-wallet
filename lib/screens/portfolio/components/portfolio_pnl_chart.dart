// lib/screens/portfolio/components/portfolio_pnl_chart.dart
//
// The profit and loss chart that leads the Portfolio screen ("P&L
// charts"; a Ledger's Statistics tab): on the spending account one chart
// for Investing and Predictions together (their series added,
// [PortfolioPerformance.combine]) or one of them under the All ·
// Investing · Predictions toggle, on a Ledger the venue's own. It reads
// as the Balance charts do (balance_history_chart.dart), a brokerage
// app's P&L view:
//
//   * the caption, then the P&L now as the hero figure (the balance type,
//     [AppTextStyles.balance]) in the up / down colour;
//   * a range row under the plot (1W 1M 3M 1Y ALL, the app's range
//     pills), 1M to start and remembered for the session; a range shows
//     its stretch ending now, never reaching back past a short lead-in
//     before the first trade (see [pnlSeries]), and tapping a range (the
//     selected one too) puts a pinched or panned view back on it;
//   * the line is the closing P&L of each bucket the window on screen
//     calls for (a quarter hour to a week), its last point the P&L now, so
//     a swing inside a bucket never spikes it; the monotone curve in the
//     neutral chart colour, never red or green by direction;
//   * no scale and no gridlines: a faint dotted baseline at zero, the P&L's
//     own reference, always on the scale, and a soft fill between the line
//     and it, green above zero and red below;
//   * above the plot one quiet line: the change over the window
//     ("+$12.40 past month"), only the amount coloured; never a percent (a
//     P&L series has no base to take one of). While a finger scrubs (long
//     press, then slide) the line says the P&L under it and when
//     ("−$6.38 · Oct 16 14:00"); after a pinch or pan, the change since
//     the window's first day or between its dates;
//   * a range where the P&L is zero throughout (nothing traded or
//     predicted yet) draws a calm flat line with one quiet sentence;
//   * pinch (around the fingers, 4 hours to the whole history) and pan
//     move inside the whole history, re-bucketing as they go, with the
//     time axis under the plot and the one-time zoom nudge; another series
//     (the toggle) or another range opens afresh;
//   * an optional [PortfolioPnlChart.selector] at the top of the card
//     (the spending account's toggle) and an optional
//     [PortfolioPnlChart.footer] under the range row.
//
// With balances hidden the figures are dots, as on the home header.
//
// Analytics: `portfolio_performance_chart_scrubbed` {venue}, once per
// scrub gesture; venue is the chart's [PortfolioPnlChart.eventVenue] when
// given (the spending account's toggle: `all`, `hyperliquid` or
// `polymarket`), else `trading`, `predictions`, or `all` for a combined
// chart. Ranges, zoom and pan send nothing, as on the Balance charts.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart' show DateFormat;

import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/balance_history.dart';
import 'package:kute/models/portfolio_performance.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/charts/kute_chart_format.dart';
import 'package:kute/screens/shared/charts/kute_chart_range_pills.dart';
import 'package:kute/screens/shared/charts/kute_chart_viewport.dart'
    show KuteIndexWindow;
import 'package:kute/screens/shared/charts/kute_line_chart.dart';
import 'package:kute/screens/shared/portfolio_position_card.dart'
    show portfolioCardCaptionStyle;
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// The height of the chart: the quiet line above the plot, the plot and
/// its time axis. Fixed, so a tall hero (large text) never squeezes the
/// line: the card grows instead.
const double kPnlChartPlotHeight = 252;

/// The range the P&L chart shows, for the rest of the session: the past
/// month to start. One choice for every series (the toggle keeps it).
final pnlChartRangeProvider =
    StateProvider<BalanceRange>((ref) => BalanceRange.month);

class PortfolioPnlChart extends ConsumerStatefulWidget {
  const PortfolioPnlChart({
    super.key,
    required this.venue,
    required this.data,
    this.now,
    this.footer,
    this.selector,
    this.eventVenue,
  });

  /// The venue charted; null for Investing and Predictions together (the
  /// spending account's Statistics tab), `all` in the events.
  final PortfolioPerformanceVenue? venue;

  /// The P&L series. With no observations (or none off zero) the chart is
  /// its empty state.
  final PortfolioPerformance data;

  /// The moment the line ends on; now unless a test pins it.
  final DateTime? now;

  /// Laid out on the card under the range row.
  final Widget? footer;

  /// Laid out at the top of the card, over the caption: which series the
  /// chart draws (the spending account's venue toggle).
  final Widget? selector;

  /// The `venue` the scrub event sends; [venue]'s name (or `all`) when
  /// null.
  final String? eventVenue;

  @override
  ConsumerState<PortfolioPnlChart> createState() => _PortfolioPnlChartState();
}

class _PortfolioPnlChartState extends ConsumerState<PortfolioPnlChart> {
  /// Bumped by a range tap, so the same range tapped again also puts a
  /// pinched or panned view back on it.
  int _rangeTaps = 0;

  /// The placeholder the change line is written around, so the amount
  /// alone takes the colour whatever the language puts around it.
  static const String _slot = '\u0001';

  String get _venueName => widget.eventVenue ?? widget.venue?.name ?? 'all';

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final c = context.colors;
    final l10n = context.l10n;
    final range = ref.watch(pnlChartRangeProvider);
    final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
    String amount(double value) => !visible
        ? '••••••'
        : '${kuteChangeSign(value)}${formatPolyAmount(ref, value.abs())}';
    Color signColor(double v) => v > 0
        ? AppColors.marketUp
        : v < 0
            ? AppColors.marketDown
            : c.textPrimary;

    final series = pnlSeries(data, widget.now ?? DateTime.now());
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
    final empty = zeroIn(KuteIndexWindow(series.extent - span, series.extent));

    // The hero: the P&L now, the line's last point.
    final headline = values.last;
    final headlineColor = !visible ? c.textPrimary : signColor(headline);

    final locale = kuteChartLocale(context);
    // On a daily grid a point at midnight closes the day before; finer
    // grids say when in the day.
    final daily = series.cellMinutes >= 1440;
    DateTime dayOf(DateTime t) => daily && t.hour == 0 && t.minute == 0
        ? t.subtract(const Duration(minutes: 1))
        : t;
    String timeOf(DateTime t) =>
        daily ? kuteChartDay(dayOf(t), locale) : kuteChartDayTime(t, locale);
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
                key: const ValueKey('statistics-pnl-header'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: quiet),
          ),
        );

    Widget header(KuteLineView view) {
      final touched = view.touched;
      if (touched != null) {
        final v = values[touched];
        return headerRow(TextSpan(children: [
          TextSpan(
            text: amount(v),
            style: TextStyle(
                color: visible ? signColor(v) : c.textPrimary,
                fontWeight: FontWeight.w700),
          ),
          TextSpan(text: ' · ${timeOf(times[touched])}'),
        ]));
      }
      // Nothing on screen but zero: the plot says so; the row keeps its
      // height so the plot never shifts.
      if (zeroIn(view.window)) return headerRow(const TextSpan(text: ' '));

      final delta = values[view.last] - values[view.first];
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
      final parts = sentence.split(_slot);
      // No percent: a change in P&L has no base to be a share of (the
      // P&L at the window's start can be zero, tiny or of either sign).
      return headerRow(TextSpan(children: [
        TextSpan(text: parts.first),
        TextSpan(
          text: amount(delta),
          style: TextStyle(
              color: delta > 0 ? AppColors.marketUp : AppColors.marketDown,
              fontWeight: FontWeight.w700),
        ),
        if (parts.length > 1) TextSpan(text: parts.sublist(1).join()),
      ]));
    }

    final chart = KuteLineChart(
      key: const ValueKey('statistics-pnl-chart'),
      values: values,
      // The neutral chart colour; the fill carries the sign.
      lineColor: c.accent,
      showFill: !empty,
      baselineAt: 0,
      fillAboveColor: AppColors.marketUp,
      fillBelowColor: AppColors.marketDown,
      buckets: buckets,
      defaultSpan: span,
      minSpan: series.minSpan,
      zoomAroundFingers: true,
      // The series gains a point as time passes: the window stays where
      // the user left it. Another series (the toggle), another range, the
      // range tapped again, or another history opens afresh.
      resetViewOnLengthChange: false,
      viewResetKey: (
        _venueName,
        times.first,
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
                  l10n.pnlChartEmpty,
                  key: const ValueKey('statistics-pnl-empty'),
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
      // Once per scrub gesture.
      onScrubStart: () => TrackingService.track(
          'portfolio_performance_chart_scrubbed',
          params: {'venue': _venueName}),
    );

    return Container(
      key: const ValueKey('statistics-pnl-card'),
      clipBehavior: Clip.antiAlias,
      decoration: AppDecorations.card(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.selector != null) ...[
                  widget.selector!,
                  SizedBox(height: 12.h),
                ],
                Text(l10n.portfolioProfitLoss,
                    style: portfolioCardCaptionStyle(c)),
                SizedBox(height: 4.h),
                // The figure leads: the balance type, scaled down rather
                // than cut on a narrow phone or under large text.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: RollingNumberText(
                    key: const ValueKey('statistics-pnl-headline'),
                    text: amount(headline),
                    duration: const Duration(milliseconds: 350),
                    dimColor: c.textTertiary,
                    style: AppTextStyles.balance(context)
                        .copyWith(color: headlineColor),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 12.h),
          // The plot on the card's own insets, so the endpoint dot and the
          // scrub hairline never meet the card's clip.
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: SizedBox(height: kPnlChartPlotHeight.h, child: chart),
          ),
          SizedBox(height: 8.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 14.w),
            child: KuteRangePills(
              key: const ValueKey('statistics-pnl-ranges'),
              labels: [for (final r in BalanceRange.values) r.label],
              selectedIndex: range.index,
              onSelected: (i) {
                ref.read(pnlChartRangeProvider.notifier).state =
                    BalanceRange.values[i];
                setState(() => _rangeTaps++);
              },
            ),
          ),
          SizedBox(height: 12.h),
          if (widget.footer != null) widget.footer!,
        ],
      ),
    );
  }
}
