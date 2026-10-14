// lib/screens/portfolio/components/portfolio_pnl_chart.dart
//
// The profit and loss chart that leads the Portfolio screen (a Ledger's
// Statistics tab): on the spending account one chart for Investing and
// Predictions
// together (their series added, [PortfolioPerformance.combine]), on a
// Ledger the venue's own. Laid out as a brokerage P&L view:
//
//   * the caption, then the P&L as the hero figure (the balance type,
//     [AppTextStyles.balance], as animated_balance.dart draws a balance,
//     rolling), in the up / down colour. The line is the whole history,
//     so the headline already is its change: the row under it stays
//     empty until a finger is on the line;
//   * the shared [KuteLineChart] (the balance charts' line: monotone
//     curve, no fill, endpoint dot, no scale, the time axis under the
//     plot), coloured by the sign of the history's change, with a dashed
//     hairline at its starting value, zero ([PnlBaselinePainter]), when
//     the line moves;
//   * there is no range row: the chart always opens on the whole history
//     and zooms like the market charts (MarketChart, HlCandlestickChart,
//     through the shared KuteChartGestures): two fingers pinch the time
//     window (anchored to the newest point while the window reaches it;
//     sliding both fingers pans), one finger dragging sideways pans once
//     zoomed in, and the time axis follows the window. Switching the
//     series (the toggle) starts on the whole history again. The first
//     zoomable chart a person ever sees plays the one-time zoom nudge
//     (kute_chart_zoom_hint.dart; never under Reduce Motion);
//   * a long press scrubs: the hairline and dot ride the line and the
//     header writes the point under the finger (its P&L, its change from
//     the line's start and its date) and snaps back on release. The
//     chart draws no scrub card of its own: the header is the card;
//   * an optional [PortfolioPnlChart.selector] at the top of the card
//     (the spending account's All · Investing · Predictions toggle: the
//     same chart, another series) and an optional
//     [PortfolioPnlChart.footer] under the plot.
//
// The line is the cumulative P&L series ([PortfolioPerformance.points]:
// realised plus open), from zero ([PortfolioPerformance.rangeView] over
// all time). Nothing is interpolated: every point is a published
// observation (or, for Predictions, the current figures rebuilt from the
// positions). A series with no movement is never drawn here: the
// Statistics tab shows its quiet line instead.
//
// Analytics: `portfolio_performance_chart_scrubbed` {venue}, once per
// scrub gesture; venue is the chart's [PortfolioPnlChart.eventVenue] when
// given (the spending account's toggle: `all`, `hyperliquid` or
// `polymarket`), else `trading`, `predictions`, or `all` for a combined
// chart. Zoom and pan send nothing, as on the market charts.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/portfolio_performance.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/analytics/components/chart.dart'
    show ChartChangeText;
import 'package:kute/screens/shared/charts/kute_chart_core.dart'
    show kuteSameSeries;
import 'package:kute/screens/shared/charts/kute_chart_format.dart';
import 'package:kute/screens/shared/charts/kute_chart_viewport.dart'
    show KuteIndexWindow;
import 'package:kute/screens/shared/charts/kute_line_chart.dart';
import 'package:kute/screens/shared/portfolio_position_card.dart'
    show portfolioCardCaptionStyle;
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// The height of the plot. Fixed, so a tall header (large text) never
/// squeezes the line: the card grows instead.
const double kPnlChartPlotHeight = 220;

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

  /// The P&L series; nothing is drawn without points.
  final PortfolioPerformance data;

  /// This moment, for whether the series' last point is now; tests pin it.
  final DateTime? now;

  /// Laid out on the card under the plot.
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
  /// The index under the finger while scrubbing, in the line's points.
  int? _scrub;

  String get _venueName => widget.eventVenue ?? widget.venue?.name ?? 'all';

  @override
  void didUpdateWidget(covariant PortfolioPnlChart old) {
    super.didUpdateWidget(old);
    // Another series: no finger on it yet.
    if (old.venue != widget.venue || old.eventVenue != widget.eventVenue) {
      _scrub = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    if (data.points.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    final l10n = context.l10n;
    final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
    // The whole history, from zero; zooming happens in the chart.
    final view = data.rangeView(null);
    final points = view.points;
    final values = [for (final p in points) p.pnlUsd];
    final baseline = points.first.pnlUsd;
    final change = view.changeUsd ?? 0;
    final flat = values.every((v) => v == values.first);
    // The line's colour is the sign of the history's change, the balance
    // charts' rule (the accent when flat).
    final lineColor = change > 0
        ? AppColors.marketUp
        : change < 0
            ? AppColors.marketDown
            : c.accent;

    final scrub = _scrub;
    final scrubbing = scrub != null && scrub >= 0 && scrub < points.length;
    final shown = scrubbing ? points[scrub] : points.last;
    // The headline is the account's P&L (the series' last point); under
    // the finger, the point there.
    final headline =
        scrubbing ? shown.pnlUsd : (data.totalPnlUsd ?? points.last.pnlUsd);

    String amount(double value) => !visible
        ? '••••••'
        : '${kuteChangeSign(value)}${formatPolyAmount(ref, value.abs())}';
    final headlineColor = !visible || headline == 0
        ? c.textPrimary
        : (headline > 0 ? AppColors.marketUp : AppColors.marketDown);

    final locale = kuteChartLocale(context);
    // A day's line is hours long: the dates then say when in the day.
    final intraday = points.last.timestamp.difference(points.first.timestamp) <=
        const Duration(days: 2);
    String timeOf(DateTime t) => intraday
        ? kuteChartDayTime(t.toLocal(), locale)
        : kuteChartDay(t.toUtc(), locale);
    final now = widget.now ?? DateTime.now();
    final live =
        now.difference(points.last.timestamp).abs() <= const Duration(hours: 6);

    // Under the finger, what the line gained from its start to the point
    // there, with its date; at rest the headline is the change, so the
    // row is empty. Hidden balances leave it empty too; it keeps its
    // height either way, so the plot never shifts while scrubbing.
    Widget? changeRow;
    if (visible && scrubbing) {
      final delta = shown.pnlUsd - baseline;
      changeRow = Row(
        key: const ValueKey('statistics-pnl-scrub'),
        children: [
          ChartChangeText.written(amount(delta), direction: delta.sign.toInt()),
          SizedBox(width: 8.w),
          Flexible(
            child: Text(
              timeOf(shown.timestamp),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: portfolioCardCaptionStyle(c),
            ),
          ),
        ],
      );
    }

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
                    // Quick under the finger, settled otherwise.
                    duration: Duration(milliseconds: scrubbing ? 120 : 350),
                    dimColor: c.textTertiary,
                    style: AppTextStyles.balance(context)
                        .copyWith(color: headlineColor),
                  ),
                ),
                SizedBox(height: 4.h),
                Align(
                  alignment: Alignment.centerLeft,
                  child: changeRow ??
                      const Visibility(
                        visible: false,
                        maintainSize: true,
                        maintainAnimation: true,
                        maintainState: true,
                        child: ChartChangeText.written('+0', direction: 0),
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
            child: SizedBox(
              height: kPnlChartPlotHeight.h,
              child: KuteLineChart(
                key: const ValueKey('statistics-pnl-chart'),
                values: values,
                lineColor: lineColor,
                showFill: false,
                // Pinch and pan as on the market charts; another
                // series (the toggle) starts on the whole history.
                zoomable: true,
                zoomHint: true,
                viewResetKey: _venueName,
                timeAxis: KuteLineTimeAxis(
                  timeAt: (i) => points[i].timestamp.toLocal(),
                  nowLabel: l10n.betNow,
                  live: live,
                  locale: locale,
                ),
                // The line's starting value, dashed across the plot
                // on the scale of the window on screen; a line that
                // never moves needs none.
                plotOverlay: flat
                    ? null
                    : (window) => CustomPaint(
                          painter: PnlBaselinePainter(
                            values: values,
                            baseline: baseline,
                            color: c.border,
                            window: window,
                          ),
                        ),
                // Once per scrub gesture.
                onScrubStart: () => TrackingService.track(
                    'portfolio_performance_chart_scrubbed',
                    params: {'venue': _venueName}),
                onScrub: (i) => setState(() => _scrub = i),
                onScrubEnd: () => setState(() => _scrub = null),
              ),
            ),
          ),
          SizedBox(height: 12.h),
          if (widget.footer != null) widget.footer!,
        ],
      ),
    );
  }
}

/// A dashed hairline across the plot at [baseline], on the scale the
/// shared line chart draws [values] on for [window] ([kuteLineDomain]
/// over the points on screen; the whole series when null). Zoomed in where
/// the line never reaches [baseline], the hairline is off the plot and
/// not drawn. The dashes are the projected tail's (4 on, 4 off).
class PnlBaselinePainter extends CustomPainter {
  PnlBaselinePainter({
    required this.values,
    required this.baseline,
    required this.color,
    this.window,
  });

  final List<double> values;
  final double baseline;
  final Color color;

  /// The window on screen; null for the whole series.
  final KuteIndexWindow? window;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || size.isEmpty) return;
    final domain = kuteLineDomain(values,
        window ?? KuteIndexWindow(0, (values.length - 1).toDouble()));
    final y = kuteLineY(baseline, size.height, domain);
    if (y < 0 || y > size.height) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.butt;
    const dash = 4.0;
    const gap = 4.0;
    var x = 0.0;
    while (x < size.width) {
      final end = (x + dash).clamp(0.0, size.width);
      canvas.drawLine(Offset(x, y), Offset(end, y), paint);
      x = end + gap;
    }
  }

  @override
  bool shouldRepaint(covariant PnlBaselinePainter old) =>
      old.baseline != baseline ||
      old.color != color ||
      old.window != window ||
      !kuteSameSeries(old.values, values);
}
