// lib/screens/portfolio/components/portfolio_pnl_chart.dart
//
// The profit and loss chart that leads the Portfolio's Statistics tab:
// on the spending account one chart for Investing and Predictions
// together (their series added, [PortfolioPerformance.combine]), on a
// Ledger the venue's own. Laid out as a brokerage P&L view:
//
//   * the caption, then the P&L as the hero figure (the balance type,
//     [AppTextStyles.balance], as animated_balance.dart draws a balance,
//     rolling), in the up / down colour; under it what the range drawn
//     gained or lost ("+$20.00 past 1m"), in the up / down colour. On ALL
//     the headline already is the change, so the row is empty;
//   * the shared [KuteLineChart] (the balance charts' line: monotone
//     curve, no fill, endpoint dot, no scale, the time axis under the
//     plot), coloured by the sign of the range's change, with a dashed
//     hairline at the range's starting value ([PnlBaselinePainter]) when
//     the line moves over the range;
//   * a long press scrubs: the hairline and dot ride the line and the
//     header writes the point under the finger (its P&L, its change from
//     the range's start and its date) and snaps back on release. The
//     chart draws no scrub card of its own: the header is the card;
//   * the range pills every chart shares ([KuteRangePills]): 1D, 1W, 1M,
//     3M, YTD, 1Y, ALL, less those reaching back past the series' first
//     point (they would draw ALL again). The tab opens on 1M, or on ALL
//     when 1M already reaches back that far;
//   * an optional [PortfolioPnlChart.selector] at the top of the card
//     (the spending account's All · Investing · Predictions toggle: the
//     same chart, another series) and an optional
//     [PortfolioPnlChart.footer] under the range pills.
//
// The line is the cumulative P&L series ([PortfolioPerformance.points]:
// realised plus open), from the P&L the account had when the range began
// ([PortfolioPerformance.rangeView]). Nothing is interpolated: every point
// is a published observation (or, for Predictions, the current figures
// rebuilt from the positions). A series with no movement is never drawn
// here: the Statistics tab shows its quiet line instead.
//
// Analytics: `portfolio_performance_range_changed` {venue, from, to} and
// `portfolio_performance_chart_scrubbed` {venue, range}, once per scrub
// gesture; venue is the chart's [PortfolioPnlChart.eventVenue] when
// given (the spending account's toggle: `all`, `hyperliquid` or
// `polymarket`), else `trading`, `predictions`, or `all` for a combined
// chart.

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
import 'package:kute/screens/shared/charts/kute_chart_range_pills.dart';
import 'package:kute/screens/shared/charts/kute_chart_time_axis.dart'
    show kKuteTimeAxisHeight;
import 'package:kute/screens/shared/charts/kute_chart_viewport.dart'
    show KuteIndexWindow;
import 'package:kute/screens/shared/charts/kute_line_chart.dart';
import 'package:kute/screens/shared/portfolio_position_card.dart'
    show portfolioCardCaptionStyle;
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// The ranges of the Statistics P&L chart, in pill order.
enum PnlChartRange {
  d1('1D'),
  w1('1W'),
  m1('1M'),
  m3('3M'),
  ytd('YTD'),
  y1('1Y'),
  all('ALL');

  const PnlChartRange(this.label);

  /// The pill's label, as the analytics events name the range.
  final String label;

  /// How far back from [last] the line starts; null for all time. YTD
  /// reaches back to the first moment of [last]'s year (UTC, as the
  /// venues publish their series).
  Duration? spanEnding(DateTime last) {
    switch (this) {
      case PnlChartRange.d1:
        return const Duration(days: 1);
      case PnlChartRange.w1:
        return const Duration(days: 7);
      case PnlChartRange.m1:
        return const Duration(days: 30);
      case PnlChartRange.m3:
        return const Duration(days: 90);
      case PnlChartRange.y1:
        return const Duration(days: 365);
      case PnlChartRange.ytd:
        final utc = last.toUtc();
        final span = utc.difference(DateTime.utc(utc.year));
        return span > Duration.zero ? span : const Duration(days: 1);
      case PnlChartRange.all:
        return null;
    }
  }

  /// The words under the headline for the change over this range, as the
  /// venue charts write theirs ("+$20.00 past 1m"); YTD is the change
  /// alone, ALL none (the headline is the change).
  String? changeText(AppLocalizations l10n, String change) {
    switch (this) {
      case PnlChartRange.all:
        return null;
      case PnlChartRange.ytd:
        return change;
      default:
        return l10n.polyChartChangePast(change, label.toLowerCase());
    }
  }
}

/// The height of the plot. Fixed, so a tall header (large text) never
/// squeezes the line: the card grows instead.
const double kPnlChartPlotHeight = 220;

/// The chart's range when the tab opens.
const PnlChartRange kPnlChartDefaultRange = PnlChartRange.m1;

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

  /// Laid out on the card under the range pills.
  final Widget? footer;

  /// Laid out at the top of the card, over the caption: which series the
  /// chart draws (the spending account's venue toggle).
  final Widget? selector;

  /// The `venue` the range and scrub events send; [venue]'s name (or
  /// `all`) when null.
  final String? eventVenue;

  @override
  ConsumerState<PortfolioPnlChart> createState() => _PortfolioPnlChartState();
}

/// Whether [range] reaches back to (or past) the first point of [data]:
/// it would draw ALL again.
bool pnlRangeRepeatsAll(PnlChartRange range, PortfolioPerformance data) {
  if (data.points.isEmpty) return range != PnlChartRange.all;
  final span = range.spanEnding(data.points.last.timestamp);
  if (span == null) return false;
  return !data.points.last.timestamp
      .subtract(span)
      .isAfter(data.points.first.timestamp);
}

class _PortfolioPnlChartState extends ConsumerState<PortfolioPnlChart> {
  /// The range picked; null until a pill is tapped (see [_range]).
  PnlChartRange? _picked;

  /// The range drawn: the one picked, else 1M, or ALL when 1M would draw
  /// it anyway. A pick the series now drawn does not reach back to (the
  /// toggle changed the series) draws as if nothing were picked.
  PnlChartRange get _range {
    final picked = _picked;
    if (picked != null && !pnlRangeRepeatsAll(picked, widget.data)) {
      return picked;
    }
    return pnlRangeRepeatsAll(kPnlChartDefaultRange, widget.data)
        ? PnlChartRange.all
        : kPnlChartDefaultRange;
  }

  /// The index under the finger while scrubbing, in the range's points.
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

  void _pick(int index) {
    final next = PnlChartRange.values[index];
    final current = _range;
    if (next == current) return;
    TrackingService.track('portfolio_performance_range_changed', params: {
      'venue': _venueName,
      'from': current.label,
      'to': next.label,
    });
    setState(() {
      _picked = next;
      _scrub = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    if (data.points.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    final l10n = context.l10n;
    final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
    final range = _range;
    final view = data.rangeView(range.spanEnding(data.points.last.timestamp));
    final points = view.points;
    final values = [for (final p in points) p.pnlUsd];
    final baseline = points.first.pnlUsd;
    final change = view.changeUsd ?? 0;
    final flat = values.every((v) => v == values.first);
    // The line's colour is the sign of the range's change, the balance
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

    // What the line gained from the range's start to its last point, or
    // to the point under the finger with its date. Hidden balances leave
    // the row empty; it keeps its height either way, so the plot never
    // shifts while scrubbing.
    final Widget? changeRow;
    if (!visible) {
      changeRow = null;
    } else if (scrubbing) {
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
    } else {
      final text = range.changeText(l10n, amount(change));
      changeRow = text == null
          ? null
          : ChartChangeText.written(text, direction: change.sign.toInt());
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
              child: Stack(
                children: [
                  Positioned.fill(
                    child: KuteLineChart(
                      key: ValueKey('statistics-pnl-chart-${range.name}'),
                      values: values,
                      lineColor: lineColor,
                      showFill: false,
                      // The ranges are the zoom; the baseline is drawn
                      // for the whole range.
                      zoomable: false,
                      timeAxis: KuteLineTimeAxis(
                        timeAt: (i) => points[i].timestamp.toLocal(),
                        nowLabel: l10n.betNow,
                        live: live,
                        locale: locale,
                      ),
                      // Once per scrub gesture.
                      onScrubStart: () => TrackingService.track(
                          'portfolio_performance_chart_scrubbed',
                          params: {
                            'venue': _venueName,
                            'range': range.label,
                          }),
                      onScrub: (i) => setState(() => _scrub = i),
                      onScrubEnd: () => setState(() => _scrub = null),
                    ),
                  ),
                  // The range's starting value, dashed across the plot
                  // (the time axis row is under the plot); a line that
                  // does not move over the range needs none.
                  if (!flat)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Padding(
                          padding: const EdgeInsets.only(
                              bottom: kKuteTimeAxisHeight),
                          child: CustomPaint(
                            painter: PnlBaselinePainter(
                              values: values,
                              baseline: baseline,
                              color: c.border,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 12.h),
            child: KuteRangePills(
              labels: [for (final r in PnlChartRange.values) r.label],
              selectedIndex: range.index,
              onSelected: _pick,
              isShown: (i) =>
                  !pnlRangeRepeatsAll(PnlChartRange.values[i], data),
            ),
          ),
          if (widget.footer != null) widget.footer!,
        ],
      ),
    );
  }
}

/// A dashed hairline across the plot at [baseline], on the scale the
/// shared line chart draws [values] on ([kuteLineDomain] over the whole
/// series: the chart is not zoomable here). The dashes are the projected
/// tail's (4 on, 4 off).
class PnlBaselinePainter extends CustomPainter {
  PnlBaselinePainter({
    required this.values,
    required this.baseline,
    required this.color,
  });

  final List<double> values;
  final double baseline;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || size.isEmpty) return;
    final domain = kuteLineDomain(
        values, KuteIndexWindow(0, (values.length - 1).toDouble()));
    final y = kuteLineY(baseline, size.height, domain);
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
      !kuteSameSeries(old.values, values);
}
