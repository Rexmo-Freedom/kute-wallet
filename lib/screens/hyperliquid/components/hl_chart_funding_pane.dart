// lib/screens/hyperliquid/components/hl_chart_funding_pane.dart
//
// The Investing chart's Funding pane (perps only), under the price like
// RSI or MACD and on the same bars, so pan, zoom, the crosshair and the
// interval are the chart's:
//
//   * Columns: the funding each bar carried (hl_chart_indicator_series.dart
//     [hlFundingPerBar]: an hour or more sums its hours, under an hour holds
//     its hour's rate), in the market's up colour where longs paid shorts
//     and its down colour where shorts paid longs, about a dotted zero line,
//     on their own percent axis in the tag column. Columns rather than a
//     line: each bar is a separate payment, the sign reads per column in a
//     pane 76 high, and the running sum is then the only line.
//   * The running sum over the bars on screen: what a constant 1-dollar
//     long paid from the first bar in view, a neutral line on its own
//     scale, its latest value tagged in the tag column.
//   * The legend: "Funding 4h", then the current hourly rate, its
//     annualised figure and the minutes to the next settlement (funding
//     settles on the hour), and the running sum; under the crosshair the
//     bar's funding and the running sum there.
//   * Loading, nothing for these dates, and a failed read say so in the
//     pane; the price chart never waits for it.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_model.dart' show HyperliquidCandle;
import 'package:kute/providers/hyperliquid_funding_history_provider.dart'
    show HlFundingLoad;
import 'package:kute/screens/hyperliquid/components/hl_chart_indicator_frame.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_indicator_series.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_intervals.dart';
import 'package:kute/screens/hyperliquid/components/hl_charts.dart'
    show hlPlotWidth, kHlIndicatorStroke;
import 'package:kute/screens/polymarket/components/poly_chart_tags.dart'
    show kPolyTagLead;
import 'package:kute/screens/shared/charts/kute_chart_core.dart'
    show kuteChartFontFamily;
import 'package:kute/theme/app_theme.dart';

/// What the chart host hands the Funding pane: the market's hourly
/// history (oldest first), where its reading stands, and the venue's
/// current hourly rate (activeAssetCtx `funding`; null: not known).
class HlFundingFeed {
  const HlFundingFeed({
    required this.points,
    required this.load,
    this.busy = false,
    this.hourlyNow,
  });

  final List<HlFundingHourly> points;
  final HlFundingLoad load;
  final bool busy;
  final double? hourlyNow;
}

/// A funding figure in percent, signed: "+0.0013%", "−0.012%", "+1.25%".
String hlFundingPct(double fraction) {
  final pct = fraction * 100;
  final a = pct.abs();
  final digits = a >= 1
      ? 2
      : a >= 0.1
          ? 3
          : 4;
  final sign = pct > 0 ? '+' : (pct < 0 ? '−' : '');
  return '$sign${a.toStringAsFixed(digits)}%';
}

/// A year of a rate, as the market page writes it: one decimal, "+11.0%".
String _annualPct(double fraction) {
  final pct = fraction * 100;
  final sign = pct > 0 ? '+' : (pct < 0 ? '−' : '');
  return '$sign${pct.abs().toStringAsFixed(1)}%';
}

/// An axis label: two significant figures, "0.0013%", "−0.12%".
String _axisPct(double fraction) {
  final pct = fraction * 100;
  if (pct == 0) return '0%';
  final a = pct.abs();
  final digits =
      math.max(0, math.min(6, 1 - (math.log(a) / math.ln10).floor()));
  final text = a.toStringAsFixed(digits);
  return '${pct < 0 ? '−' : ''}$text%';
}

/// The period one column covers, as the interval row writes it: the
/// bar's own ("4h", "1D") from an hour up, an hour below it.
String hlFundingPeriodLabel(int barMinutes) {
  if (barMinutes < 60) return '1h';
  for (final iv in kHlCandleIntervals) {
    if (iv.minutes == barMinutes) return iv.label;
  }
  return barMinutes % 1440 == 0
      ? '${barMinutes ~/ 1440}D'
      : '${(barMinutes / 60).round()}h';
}

/// The bar of [candles] in minutes: the newest bar's close less its open
/// (the venue's close is a millisecond short of the next open), or the
/// gap between the last two opens.
int hlBarMinutes(List<HyperliquidCandle> candles) {
  if (candles.isEmpty) return 60;
  final k = candles.last;
  var ms = k.closeTime.difference(k.openTime).inMilliseconds;
  if (ms <= 0 && candles.length >= 2) {
    ms = k.openTime.difference(candles[candles.length - 2].openTime)
        .inMilliseconds;
  }
  final minutes = (ms / 60000).round();
  return minutes > 0 ? minutes : 60;
}

/// The least a Funding pane is high (logical pixels).
const double _kMinPaneHeight = 52;

final Expando<List<double>> _cumulative = Expando('hlFundingCumulative');

/// [settled]'s running sum, kept per list so a rebuild does not redo it.
List<double> _cumulativeOf(List<double> settled) =>
    _cumulative[settled] ??= hlFundingCumulative(settled);

class HlFundingPane extends StatelessWidget {
  const HlFundingPane({
    super.key,
    required this.series,
    required this.feed,
    required this.touchIndex,
    required this.gutterFor,
    required this.barMinutes,
    required this.hairlineColor,
  });

  /// The Funding series cut to the bars on screen.
  final HlIndSeries series;
  final HlFundingFeed feed;

  /// The crosshair's bar (on screen), null when none.
  final int? touchIndex;

  /// The price chart's tag column for a width.
  final double Function(double width) gutterFor;

  /// The chart's bar, in minutes.
  final int barMinutes;
  final Color hairlineColor;

  static double _finiteAt(List<double> v, int i) =>
      i >= 0 && i < v.length ? v[i] : double.nan;

  static double _newest(List<double> v) {
    for (var i = v.length - 1; i >= 0; i--) {
      if (v[i].isFinite) return v[i];
    }
    return double.nan;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final rate = series.histogram ?? const <double>[];
    final cum = _cumulativeOf(series.settled ?? const <double>[]);
    final neutral = c.textPrimary.withValues(alpha: 0.8);
    final hasData = rate.any((v) => v.isFinite);
    final ti = touchIndex;
    final scrubbing = ti != null && ti >= 0 && ti < rate.length;

    Color signed(double v) =>
        v >= 0 ? AppColors.marketUp : AppColors.marketDown;

    // The legend at rest (the latest) and under the crosshair (that bar).
    List<InlineSpan> legendAt(int? at) {
      final spans = <InlineSpan>[
        TextSpan(
          text: '${l10n.hlFunding} ${hlFundingPeriodLabel(barMinutes)}',
          style: TextStyle(color: c.textTertiary),
        ),
      ];
      if (at != null) {
        final r = _finiteAt(rate, at);
        spans.add(TextSpan(
          text: '  ${r.isFinite ? hlFundingPct(r) : '—'}',
          style: TextStyle(
            color: r.isFinite ? signed(r) : c.textTertiary,
            fontWeight: FontWeight.w600,
          ),
        ));
      } else if (feed.hourlyNow case final now?) {
        spans.add(TextSpan(
          text: '  ${l10n.chartFundingNow(
            hlFundingPct(now),
            _annualPct(now * 24 * 365),
            l10n.hlFundingIn(60 - DateTime.now().minute),
          )}',
          style: TextStyle(color: signed(now), fontWeight: FontWeight.w600),
        ));
      }
      final cumHere = at != null ? _finiteAt(cum, at) : _newest(cum);
      if (cumHere.isFinite) {
        spans.add(TextSpan(
          text: '  ${l10n.chartFundingCumulative(hlFundingPct(cumHere))}',
          style: TextStyle(color: neutral, fontWeight: FontWeight.w600),
        ));
      }
      return spans;
    }

    final atRest = legendAt(null);
    final spans = scrubbing ? legendAt(ti) : atRest;

    String? message;
    if (!hasData) {
      message = feed.load == HlFundingLoad.error
          ? l10n.chartFundingError
          : feed.load == HlFundingLoad.loading || feed.busy
              ? l10n.loading
              : l10n.chartFundingEmpty;
    }

    const tabular = [FontFeature.tabularFigures()];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 8.h),
        Container(
          key: const ValueKey('hl-chart-pane-hairline'),
          height: 0.5,
          color: c.border,
        ),
        SizedBox(
          key: const ValueKey('hl-chart-funding-pane'),
          // The other panes' height, but never so short (a phone on its
          // side) that the columns under the legend vanish.
          height: math.max(76.h, _kMinPaneHeight),
          width: double.infinity,
          child: LayoutBuilder(builder: (context, constraints) {
            final gutter = gutterFor(constraints.maxWidth);
            final plotW = hlPlotWidth(constraints.maxWidth, gutter);
            final legendStyle = TextStyle(
              fontSize: 11.sp,
              height: 1.2,
              fontFeatures: tabular,
            );
            // The legend's lines (one, or two where it wraps) stay clear
            // of the columns where the pane is tall enough; a short pane
            // draws under it, as the other panes do.
            // Measured at rest, so the columns hold still under a scrub.
            final legend = TextPainter(
              text: TextSpan(children: atRest, style: legendStyle),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
              maxLines: 2,
            )..layout(maxWidth: math.max(1.0, plotW - 4));
            // A second line only where the pane keeps room under it.
            final lineH = legend.preferredLineHeight;
            final lines = math.min(
                legend.computeLineMetrics().length,
                constraints.maxHeight - 2 * lineH >= 20 ? 2 : 1);
            final legendH = lines * lineH + 5;
            legend.dispose();
            final top =
                constraints.maxHeight - legendH >= 30 ? legendH : 0.0;
            return Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: HlFundingPanePainter(
                      rate: rate,
                      cumulative: cum,
                      up: AppColors.marketUp,
                      down: AppColors.marketDown,
                      neutral: neutral,
                      labelColor: c.textTertiary,
                      tagText: c.background,
                      hairlineColor: hairlineColor,
                      selectedIndex: scrubbing ? ti : null,
                      gutter: gutter,
                      top: top,
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 3,
                  child: IgnorePointer(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: plotW),
                      // A soft halo, as the other panes' labels have.
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: c.background.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text.rich(
                            TextSpan(children: spans),
                            key: const ValueKey('hl-chart-funding-legend'),
                            maxLines: lines,
                            overflow: TextOverflow.ellipsis,
                            style: legendStyle,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (message != null)
                  Positioned(
                    left: 0,
                    width: plotW,
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.only(top: 14.h),
                          child: Text(
                            message,
                            key: const ValueKey('hl-chart-funding-state'),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: c.textTertiary,
                              fontSize: 12.sp,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          }),
        ),
      ],
    );
  }
}

/// The Funding pane's columns, dotted zero line, percent axis, running
/// sum on its own scale with its tag, and the crosshair's hairline.
class HlFundingPanePainter extends CustomPainter {
  const HlFundingPanePainter({
    required this.rate,
    required this.cumulative,
    required this.up,
    required this.down,
    required this.neutral,
    required this.labelColor,
    required this.tagText,
    required this.hairlineColor,
    required this.selectedIndex,
    required this.gutter,
    required this.top,
  });

  final List<double> rate, cumulative;
  final Color up, down, neutral, labelColor, tagText, hairlineColor;
  final int? selectedIndex;
  final double gutter;

  /// Room kept above the plot for the legend's first line.
  final double top;

  static const double _bottomPad = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final n = rate.length;
    if (n == 0 || size.width <= 0) return;
    final plotW = hlPlotWidth(size.width, gutter);
    final slot = plotW / n;
    final y0 = math.min(top, size.height * 0.5);
    final y1 = size.height - _bottomPad;
    final h = math.max(1.0, y1 - y0);

    // ── The rate's scale: always holding zero.
    var lo = 0.0, hi = 0.0;
    var any = false;
    for (final v in rate) {
      if (!v.isFinite) continue;
      any = true;
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    final maxV = hi, minV = lo;
    if (hi - lo <= 0) {
      hi = 1e-6;
      lo = -1e-6;
    }
    final span = hi - lo;
    final rLo = lo - span * 0.06, rHi = hi + span * 0.06;
    double toY(double v) => y0 + h * (1 - (v - rLo) / (rHi - rLo));

    final zeroY = toY(0);
    // The dotted zero line (none while there is nothing to draw).
    final dot = Paint()
      ..color = labelColor.withValues(alpha: 0.55)
      ..strokeWidth = 0.8;
    for (var x = 0.0; any && x < plotW; x += 5) {
      canvas.drawLine(
          Offset(x, zeroY), Offset(math.min(x + 2, plotW), zeroY), dot);
    }

    // ── Columns.
    if (any) {
      final barW = math.max(1.0, slot * 0.62);
      final upPaint = Paint()..color = up.withValues(alpha: 0.75);
      final downPaint = Paint()..color = down.withValues(alpha: 0.75);
      for (var i = 0; i < n; i++) {
        final v = rate[i];
        if (!v.isFinite) continue;
        final y = toY(v);
        final cx = (i + 0.5) * slot;
        var r = Rect.fromLTRB(cx - barW / 2, math.min(y, zeroY), cx + barW / 2,
            math.max(y, zeroY));
        // A tiny rate still shows as a sliver on its side of the line.
        if (r.height < 1) {
          r = v >= 0
              ? Rect.fromLTRB(r.left, zeroY - 1, r.right, zeroY)
              : Rect.fromLTRB(r.left, zeroY, r.right, zeroY + 1);
        }
        canvas.drawRect(r, v >= 0 ? upPaint : downPaint);
      }
    }

    // ── The crosshair through the pane.
    final si = selectedIndex;
    if (si != null && si >= 0 && si < n) {
      final x = (si + 0.5) * slot;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = hairlineColor.withValues(alpha: 0.6)
          ..strokeWidth = 1,
      );
    }

    // ── The running sum on its own scale.
    var cLo = double.infinity, cHi = double.negativeInfinity;
    for (final v in cumulative) {
      if (!v.isFinite) continue;
      if (v < cLo) cLo = v;
      if (v > cHi) cHi = v;
    }
    double? cumTagY;
    double? cumLast;
    if (cLo.isFinite) {
      if (cHi - cLo <= 0) {
        final pad = math.max(cHi.abs() * 0.1, 1e-6);
        cHi += pad;
        cLo -= pad;
      }
      final cs = cHi - cLo;
      final a = cLo - cs * 0.08, b = cHi + cs * 0.08;
      double toCy(double v) => y0 + h * (1 - (v - a) / (b - a));
      final path = Path();
      var connected = false;
      for (var i = 0; i < math.min(n, cumulative.length); i++) {
        final v = cumulative[i];
        if (!v.isFinite) continue;
        final p = Offset((i + 0.5) * slot, toCy(v));
        connected ? path.lineTo(p.dx, p.dy) : path.moveTo(p.dx, p.dy);
        connected = true;
        cumLast = v;
        cumTagY = p.dy;
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = neutral
          ..style = PaintingStyle.stroke
          ..strokeWidth = kHlIndicatorStroke
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // ── The tag column: the running sum's tag, then the rate's axis
    // (its extremes and zero) wherever they do not collide with it.
    final taken = <Rect>[];
    double labelLeft(double width) => math.max(
        0.0,
        math.min(gutter > 0 ? plotW + kPolyTagLead : size.width - width,
            size.width - width));
    TextPainter text(String s, Color color, {FontWeight? weight}) =>
        TextPainter(
          text: TextSpan(
            text: s,
            style: TextStyle(
              fontFamily: kuteChartFontFamily,
              color: color,
              fontSize: 10,
              fontWeight: weight,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();

    if (cumTagY != null && cumLast != null) {
      final tp = text(hlFundingPct(cumLast), tagText, weight: FontWeight.w700);
      final w = tp.width + 6, hh = tp.height + 2;
      final left = labelLeft(w);
      final t = (cumTagY - hh / 2)
          .clamp(0.0, math.max(0.0, size.height - hh))
          .toDouble();
      final r = Rect.fromLTWH(left, t, w, hh);
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)),
          Paint()..color = neutral);
      tp.paint(canvas, Offset(left + 3, t + 1));
      taken.add(r.inflate(1));
    }
    if (any) {
      for (final v in <double>[if (maxV > 0) maxV, if (minV < 0) minV, 0]) {
        final tp = text(_axisPct(v), labelColor);
        final y = toY(v);
        final t = (y - tp.height / 2)
            .clamp(0.0, math.max(0.0, size.height - tp.height))
            .toDouble();
        final r = Rect.fromLTWH(labelLeft(tp.width), t, tp.width, tp.height);
        if (taken.any((o) => o.overlaps(r))) continue;
        tp.paint(canvas, r.topLeft);
        taken.add(r.inflate(1));
      }
    }
  }

  @override
  bool shouldRepaint(covariant HlFundingPanePainter old) =>
      !identical(old.rate, rate) ||
      !identical(old.cumulative, cumulative) ||
      old.selectedIndex != selectedIndex ||
      old.up != up ||
      old.down != down ||
      old.neutral != neutral ||
      old.labelColor != labelColor ||
      old.tagText != tagText ||
      old.hairlineColor != hairlineColor ||
      old.gutter != gutter ||
      old.top != top;
}
