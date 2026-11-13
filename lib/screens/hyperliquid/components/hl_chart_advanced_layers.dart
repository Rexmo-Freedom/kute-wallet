// lib/screens/hyperliquid/components/hl_chart_advanced_layers.dart
//
// The Advanced chart's reading layers, TradingView style:
//
//   * [HlChartLegend]: at the plot's top left, the bar under the
//     crosshair (the newest bar otherwise) as O H L C, its change from the
//     bar before and its volume, then one row per indicator on the price
//     with its title and values in its colours.
//   * [HlVolumeProfilePainter]: the visible range's volume profile, rows
//     growing in from the plot's right edge, up and down volume in the
//     market's colours, the value area stronger, the point of control a
//     line across the plot.
//   * [HlLogScaleToggle]: the axis corner's "Log" switch.
//   * [hlPaintIchimokuCloud]: Ichimoku's two-coloured soft fill.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_indicator_frame.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_indicator_series.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/shared/charts/kute_chart_indicators.dart'
    show kuteLogPrice;
import 'package:kute/theme/app_theme.dart';

/// A volume as the legend writes it ("1.25k", "3.1M", "842").
String hlLegendVolume(double v) {
  if (!v.isFinite) return '—';
  final a = v.abs();
  if (a >= 1e9) return '${(a / 1e9).toStringAsFixed(2)}B';
  if (a >= 1e6) return '${(a / 1e6).toStringAsFixed(2)}M';
  if (a >= 1e3) return '${(a / 1e3).toStringAsFixed(2)}k';
  if (a >= 100) return a.toStringAsFixed(0);
  return a.toStringAsPrecision(3);
}

/// The legend at the Advanced plot's top left.
class HlChartLegend extends StatelessWidget {
  const HlChartLegend({
    super.key,
    required this.candles,
    required this.index,
    required this.price,
    required this.profile,
    required this.profileTitle,
    required this.formatPrice,
  });

  /// The bars on screen and the one the crosshair is on (null: the newest).
  final List<HyperliquidCandle> candles;
  final int? index;

  /// The indicators on the price, sliced to [candles].
  final List<HlIndSeries> price;

  /// Volume profile, when it is on, and its title ("VP 24").
  final HlVolumeProfile? profile;
  final String profileTitle;

  final String Function(double price) formatPrice;

  @override
  Widget build(BuildContext context) {
    if (candles.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    final i = (index ?? candles.length - 1).clamp(0, candles.length - 1);
    final k = candles[i];
    final prev = i > 0 ? candles[i - 1].close : null;
    final tone = k.close >= k.open ? AppColors.marketUp : AppColors.marketDown;
    const tabular = [FontFeature.tabularFigures()];
    final base = TextStyle(
      fontSize: 11.sp,
      height: 1.25,
      fontFeatures: tabular,
      color: c.textTertiary,
    );
    final value = TextStyle(color: tone, fontWeight: FontWeight.w600);
    TextSpan pair(String label, String v, TextStyle style) => TextSpan(
          children: [
            TextSpan(text: '$label '),
            TextSpan(text: v, style: style),
            const TextSpan(text: '  '),
          ],
        );
    final change =
        prev == null || prev <= 0 ? null : (k.close - prev) / prev;
    final rows = <Widget>[
      Text.rich(
        TextSpan(children: [
          pair('O', formatPrice(k.open), value),
          pair('H', formatPrice(k.high), value),
          pair('L', formatPrice(k.low), value),
          pair('C', formatPrice(k.close), value),
          if (change != null)
            TextSpan(
              text: '${formatHlPct(change, decimals: 2)}  ',
              style: value,
            ),
          pair('Vol', hlLegendVolume(k.volume),
              TextStyle(color: c.textSecondary, fontWeight: FontWeight.w600)),
        ]),
        key: const ValueKey('hl-chart-ohlc'),
        maxLines: 2,
        style: base,
      ),
      for (final s in price)
        if (s.valuesAt(index) case final values when values.isNotEmpty)
          Text.rich(
            TextSpan(children: [
              TextSpan(text: s.title),
              for (final (v, color) in values)
                TextSpan(
                  text: '  ${formatPrice(v)}',
                  style: TextStyle(color: color, fontWeight: FontWeight.w600),
                ),
            ]),
            key: ValueKey('hl-chart-legend-${s.key}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: base,
          ),
      if (profile case final p?)
        Text.rich(
          TextSpan(children: [
            TextSpan(text: '$profileTitle  POC '),
            TextSpan(
              text: formatPrice(p.priceAt(p.poc)),
              style: const TextStyle(
                  color: kHlProfilePocColor, fontWeight: FontWeight.w600),
            ),
          ]),
          key: const ValueKey('hl-chart-legend-vp'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: base,
        ),
    ];
    return DecoratedBox(
      // A soft halo, so a line passing under it never cuts a figure.
      decoration: BoxDecoration(
        color: c.background.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(2, 1, 4, 1),
        child: Column(
          key: const ValueKey('hl-chart-overlay-legend'),
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: rows,
        ),
      ),
    );
  }
}

/// Soft fill of Ichimoku's cloud, in each side's colour.
const double kHlCloudFillAlpha = 0.14;

/// Paints [cloud] over bars [slot] wide: the fill between its spans in the
/// up colour where span A leads and the down colour where span B does,
/// the two meeting where the spans cross. [toY] may answer a non-finite y
/// for a value the axis has no place for, which gaps it.
void hlPaintIchimokuCloud(
  Canvas canvas,
  HlIndCloud cloud,
  double slot,
  double Function(double v) toY, {
  double alpha = kHlCloudFillAlpha,
  Color? tint,
}) {
  final a = cloud.spanA, b = cloud.spanB;
  final n = math.min(a.length, b.length);
  final top = <Offset>[];
  final bottom = <Offset>[];
  bool? above;
  void flush() {
    if (top.length >= 2) {
      final path = Path()..moveTo(top.first.dx, top.first.dy);
      for (final p in top.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      for (final p in bottom.reversed) {
        path.lineTo(p.dx, p.dy);
      }
      path.close();
      final color = tint ?? (above == true ? cloud.up : cloud.down);
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: alpha));
    }
    top.clear();
    bottom.clear();
  }

  for (var i = 0; i < n; i++) {
    final va = a[i], vb = b[i];
    final ya = va.isFinite ? toY(va) : double.nan;
    final yb = vb.isFinite ? toY(vb) : double.nan;
    if (!ya.isFinite || !yb.isFinite) {
      flush();
      above = null;
      continue;
    }
    final now = va >= vb;
    final x = (i + 0.5) * slot;
    if (above != null && now != above && top.isNotEmpty) {
      // The spans crossed since the last bar: both fills meet there.
      final d0 = top.last.dy - bottom.last.dy;
      final d1 = ya - yb;
      final t = d0 == d1 ? 0.0 : d0 / (d0 - d1);
      final cross = Offset(top.last.dx + t * slot,
          top.last.dy + t * (ya - top.last.dy));
      top.add(cross);
      bottom.add(cross);
      flush();
      top.add(cross);
      bottom.add(cross);
    }
    above = now;
    top.add(Offset(x, ya));
    bottom.add(Offset(x, yb));
  }
  flush();
}

/// The point of control's colour.
const Color kHlProfilePocColor = Color(0xFFF59E0B);

/// Share of the plot's width the busiest row reaches.
const double kHlProfileWidthShare = 0.25;

/// Paints [profile] over a price area [priceH] tall and [plotW] wide that
/// maps prices through the chart's domain ([lo]..[hi], ln-mapped when
/// [log]).
class HlVolumeProfilePainter extends CustomPainter {
  HlVolumeProfilePainter({
    required this.profile,
    required this.lo,
    required this.hi,
    required this.log,
    required this.priceH,
    required this.plotW,
    required this.up,
    required this.down,
  });

  final HlVolumeProfile profile;
  final double lo, hi;
  final bool log;
  final double priceH, plotW;
  final Color up, down;

  double _y(double price) {
    final v = log ? kuteLogPrice(price) : price;
    final range = hi - lo;
    return priceH * (1 - (v - lo) / (range > 0 ? range : 1));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final p = profile;
    final maxRow = p.maxRow;
    if (maxRow <= 0 || priceH <= 0 || plotW <= 0) return;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, plotW, priceH));
    final full = plotW * kHlProfileWidthShare;
    final upPaint = Paint();
    final downPaint = Paint();
    for (var r = 0; r < p.rows; r++) {
      final total = p.total(r);
      if (total <= 0) continue;
      final top = _y(p.lo + (r + 1) * p.rowHeight);
      final bottom = _y(p.lo + r * p.rowHeight);
      final h = (bottom - top).abs();
      final y0 = math.min(top, bottom) + math.min(1.0, h * 0.15);
      final y1 = math.max(top, bottom) - math.min(1.0, h * 0.15);
      if (y1 <= y0) continue;
      final inArea = r >= p.vaLow && r <= p.vaHigh;
      final alpha = inArea ? 0.26 : 0.12;
      upPaint.color = up.withValues(alpha: alpha);
      downPaint.color = down.withValues(alpha: alpha);
      final len = full * total / maxRow;
      final upLen = len * p.up[r] / total;
      // From the right edge in: up volume, then down volume.
      canvas.drawRect(
          Rect.fromLTRB(plotW - upLen, y0, plotW, y1), upPaint);
      canvas.drawRect(
          Rect.fromLTRB(plotW - len, y0, plotW - upLen, y1), downPaint);
    }
    final pocY = _y(p.priceAt(p.poc));
    canvas.drawLine(
      Offset(0, pocY),
      Offset(plotW, pocY),
      Paint()
        ..color = kHlProfilePocColor.withValues(alpha: 0.75)
        ..strokeWidth = 1,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant HlVolumeProfilePainter old) =>
      !identical(old.profile, profile) ||
      old.lo != lo ||
      old.hi != hi ||
      old.log != log ||
      old.priceH != priceH ||
      old.plotW != plotW ||
      old.up != up ||
      old.down != down;
}

/// The price axis' "Log" switch at the axes' corner (TradingView's), lit
/// while the axis is logarithmic.
class HlLogScaleToggle extends StatelessWidget {
  const HlLogScaleToggle({super.key, required this.on, required this.onChanged});

  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      toggled: on,
      label: context.l10n.chartLogScale,
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey('hl-chart-log-toggle'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onChanged(!on);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: on ? c.textPrimary : c.textPrimary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Log',
              style: TextStyle(
                color: on ? c.background : c.textSecondary,
                fontSize: 10.5.sp,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
