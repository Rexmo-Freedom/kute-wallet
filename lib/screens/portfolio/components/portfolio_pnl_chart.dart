// lib/screens/portfolio/components/portfolio_pnl_chart.dart
//
// The profit and loss chart of the P&L charts section: on the spending
// account one chart for Investing and Predictions together (their series
// added, [PortfolioPerformance.combine]) or one venue's when its row is
// picked (portfolio_statistics.dart); on a Ledger the venue's own. It is
// drawn through the modern line chart ([KuteTrendChart], founder, 31
// October 2026: "make the graph modern"), as the Bitcoin and Dollars
// Balance charts are (balance_history_chart.dart):
//
//   * the caption ("Profit and loss"), then the P&L now as the figure
//     (the balance type, [AppTextStyles.balance]) in the up / down colour,
//     then one quiet change line: "▲ $31.84 · Past month", the arrow and
//     the amount in the change's colour, the period after a middle dot;
//     never a percent (a P&L series has no base to take one of); flat:
//     "No change · Past month";
//   * the plot: the closing P&L of each bucket the range calls for (a
//     quarter hour to a week), its last point the P&L now, so a swing
//     inside a bucket never spikes it; ONE line in the RESULT colour of
//     the range ([pnlResultColor]: red when the P&L fell over it, green
//     when it rose, the text colour when flat), its fill, a dashed
//     hairline at the range's first value; no axes, no grid, no labels;
//   * a range row 16 px under the plot (1W 1M 3M 1Y ALL, the small white
//     pill), 1M to start and remembered for the session; picking a range
//     morphs the line;
//   * SCRUB: a horizontal drag (or a long press, then slide) puts the P&L
//     under the finger in the figure and its change since the range's
//     start and its moment in the change line ("▼ $6.38 · Oct 16 14:00");
//     release puts the P&L now back;
//   * NO HISTORY (nothing traded or predicted yet, every point zero): no
//     chart and no range row, only the headline ($0.00) and one quiet
//     caption under it ("Your P&L shows up after your first position.");
//   * the spending account's card is ONE block (founder, 28 October 2026,
//     lighter: what is done only): with a [PortfolioPnlChart.footer] (the
//     venue lines, which pick the series) the caption and the REALISED
//     P&L ([PortfolioPnlChart.figureUsd]) lead in the result colour, no
//     change line; the plot directly under them, the range row, then a
//     hairline and the footer. While a finger scrubs, the figure is the
//     P&L under it and the caption says when ("Profit and loss · Oct 16
//     14:00"). Without a footer (a Ledger) the figure is the P&L now with
//     its change line;
//   * extra venue lines ([PortfolioPnlChart.venueLines]), when the host
//     asks for one line per venue: 1.5 px in the venue's colour, no fill,
//     on the same scale; the footer's rows are their legend.
//
// With balances hidden the figures are dots, as on the home header.
//
// Analytics: `portfolio_performance_chart_scrubbed` {venue}, once per
// scrub gesture; venue is the chart's [PortfolioPnlChart.eventVenue] when
// given (the spending account's series: `all`, `hyperliquid` or
// `polymarket`), else `trading`, `predictions`, or `all` for a combined
// chart. Ranges send nothing, as on the Balance charts.

import 'package:flutter/material.dart';
import 'package:kute/screens/shared/no_activity_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/balance_history.dart';
import 'package:kute/models/portfolio_performance.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/market_groups.dart' show marketGroupDivider;
import 'package:kute/screens/shared/charts/kute_chart_format.dart';
import 'package:kute/screens/shared/charts/kute_trend_chart.dart';
import 'package:kute/screens/shared/charts/kute_trend_window.dart';
import 'package:kute/screens/shared/portfolio_position_card.dart'
    show portfolioCardCaptionStyle;
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// The plot's height on the P&L card.
const double kPnlChartPlotHeight = kKuteTrendPlotHeight;

/// The line's colour: the result over the range, [change] being the P&L
/// at the range's end less its start. Red when it fell, green when it
/// rose, the text colour when it did not move.
Color pnlResultColor(AppColorsExtension c, double change) => change > 0
    ? AppColors.marketUp
    : change < 0
        ? AppColors.marketDown
        : c.textPrimary;

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
    this.figureUsd,
    this.eventVenue,
    this.venueLines = const [],
  });

  /// The venue charted; null for Investing and Predictions together (the
  /// spending account's Statistics tab), `all` in the events.
  final PortfolioPerformanceVenue? venue;

  /// The P&L series. With no observations (or none off zero) the chart is
  /// its no-history state.
  final PortfolioPerformance data;

  /// The moment the line ends on; now unless a test pins it.
  final DateTime? now;

  /// Under the range row, past a hairline (the venue lines, which pick
  /// the series drawn). With it the card is the spending account's one
  /// block: the caption and [figureUsd] over the plot, no change line.
  final Widget? footer;

  /// The block's figure at rest: the realised P&L of the series drawn
  /// (null: not known, a dash). Unused without a [footer].
  final double? figureUsd;

  /// The `venue` the scrub event sends; [venue]'s name (or `all`) when
  /// null.
  final String? eventVenue;

  /// One extra line per venue, in the venue's colour, over the same range.
  final List<(Color, PortfolioPerformance)> venueLines;

  @override
  ConsumerState<PortfolioPnlChart> createState() => _PortfolioPnlChartState();
}

class _PortfolioPnlChartState extends ConsumerState<PortfolioPnlChart> {
  /// The point under the finger; null at rest.
  KuteTrendPoint? _scrub;

  String get _venueName => widget.eventVenue ?? widget.venue?.name ?? 'all';

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final c = context.colors;
    final l10n = context.l10n;
    final range = ref.watch(pnlChartRangeProvider);
    final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
    String money(double value) =>
        !visible ? '••••••' : formatPolyAmount(ref, value.abs());
    String signed(double value) =>
        !visible ? '••••••' : '${kuteChangeSign(value)}${money(value)}';
    Color signColor(double v) => v > 0
        ? AppColors.marketUp
        : v < 0
            ? AppColors.marketDown
            : c.textPrimary;

    final now = widget.now ?? DateTime.now();
    final series = pnlSeries(data, now);
    final hasHistory = series.values.any((v) => v != 0);
    final span = series.spanFor(range);
    final shown = kuteTrendWindow(series, span);
    final values = shown.values;
    final times = shown.times;
    final block = widget.footer != null;
    final scrub = _scrub;
    final scrubbing = scrub != null && scrub.index < values.length;

    final locale = kuteChartLocale(context);
    // On daily (or coarser) buckets a point at midnight closes the day
    // before; finer buckets say when in the day.
    final daily = series.strideFor(span) * series.cellMinutes >= 1440;
    String timeOf(DateTime t) {
      final d = daily && t.hour == 0 && t.minute == 0
          ? t.subtract(const Duration(minutes: 1))
          : t;
      return daily ? kuteChartDay(d, locale) : kuteChartDayTime(t, locale);
    }

    // The result over the range: the line's colour.
    final lineColor = values.isEmpty
        ? c.textPrimary
        : pnlResultColor(c, values.last - values.first);

    // The hero: the P&L now (the line's last point), the P&L under the
    // finger while scrubbing, or the block's realised figure at rest.
    final double? restFigure = block ? widget.figureUsd : series.values.last;
    final double? headline = scrubbing ? scrub.value : restFigure;
    final headlineText = headline == null ? '—' : signed(headline);
    final headlineColor =
        headline == null || !visible ? c.textPrimary : signColor(headline);

    final quiet = TextStyle(
      color: c.textSecondary,
      fontSize: 13.sp,
      fontWeight: FontWeight.w500,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    // The figure leads: the balance type, scaled down rather than cut on a
    // narrow phone or under large text.
    final figure = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: RollingNumberText(
        key: const ValueKey('statistics-pnl-headline'),
        text: headlineText,
        duration: Duration(milliseconds: scrubbing ? 120 : 350),
        dimColor: c.textTertiary,
        style: AppTextStyles.balance(context).copyWith(color: headlineColor),
      ),
    );

    // The change line: the change over the range (or to the finger) and
    // the period (or the moment under the finger). Never a percent.
    Widget changeLine() {
      if (values.length < 2) return const SizedBox.shrink();
      final to = scrubbing ? scrub.value : values.last;
      final delta = to - values.first;
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
            else
              TextSpan(
                // Hidden: dots alone, no arrow to read a direction from.
                text: visible
                    ? '${kuteTrendArrow(delta)}${money(delta)}'
                    : money(delta),
                style: TextStyle(
                    color: visible ? color : c.textPrimary,
                    fontWeight: FontWeight.w700),
              ),
            TextSpan(text: ' · $tail'),
          ]),
          key: const ValueKey('statistics-pnl-header'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: quiet,
        ),
      );
    }

    final captionText = block && scrubbing
        ? '${l10n.portfolioProfitLoss} · ${timeOf(scrub.time ?? times.last)}'
        : l10n.portfolioProfitLoss;
    final header = Padding(
      key: ValueKey(block ? 'statistics-pnl-lead' : 'statistics-pnl-head'),
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(captionText,
              key: const ValueKey('statistics-pnl-caption'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: portfolioCardCaptionStyle(c)),
          SizedBox(height: 4.h),
          figure,
          if (!block && hasHistory) changeLine(),
          if (!hasHistory)
            Padding(
              padding: EdgeInsets.only(top: 4.h),
              child: Text(
                l10n.pnlChartNoHistory,
                key: const ValueKey('statistics-pnl-empty'),
                style: TextStyle(
                  color: c.textSecondary,
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );

    final chart = KuteTrendChart(
      key: const ValueKey('statistics-pnl-chart'),
      values: hasHistory ? values : const [],
      times: hasHistory ? times : null,
      lineColor: lineColor,
      lines: [
        for (final (color, perf) in widget.venueLines)
          KuteTrendLine(
            values: kuteTrendWindow(pnlSeries(perf, now), span).values,
            color: color,
          ),
      ],
      height: kPnlChartPlotHeight.h,
      onScrub: (p) => setState(() => _scrub = p),
      // Once per scrub gesture.
      onScrubStart: () => TrackingService.track(
          'portfolio_performance_chart_scrubbed',
          params: {'venue': _venueName}),
      rangeLabels: [for (final r in BalanceRange.values) r.label],
      selectedRange: range.index,
      onRangeSelected: (i) {
        ref.read(pnlChartRangeProvider.notifier).state =
            BalanceRange.values[i];
      },
    );

    return Container(
      key: const ValueKey('statistics-pnl-card'),
      clipBehavior: Clip.antiAlias,
      decoration: AppDecorations.card(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // No P&L ever (founder, 31 October 2026): Sal, centred, "No P&L
          // yet" and the chart's own caption under it, instead of the
          // headline and an empty plot; the venue lines stay under.
          if (hasHistory)
            header
          else
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8.h),
              child: NoActivityState(
                key: const ValueKey('statistics-pnl-no-history'),
                title: l10n.pnlNoHistoryTitle,
                subtitle: l10n.pnlChartNoHistory,
                cycles: 3,
                compact: true,
              ),
            ),
          if (hasHistory) ...[
            SizedBox(height: 12.h),
            // The plot on the card's own insets, so the end dot and the
            // scrub hairline never meet the card's clip.
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: chart,
            ),
          ],
          SizedBox(height: 16.h),
          // The venue lines under a hairline, which pick the series.
          if (widget.footer case final lines?)
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 12.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [marketGroupDivider(context, 0), lines],
              ),
            ),
        ],
      ),
    );
  }
}
