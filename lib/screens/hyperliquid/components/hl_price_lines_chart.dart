// lib/screens/hyperliquid/components/hl_price_lines_chart.dart
//
// The person's price lines on the chart. A line is a horizontal drawing:
// the chart hands [hlPriceLineDrawings] to the drawings' own painters, so
// it has the same stroke, the same neutral colour and the same price tag
// as a level, dashed. The only thing added is the small bell at the line's
// left end, away from the live price at the right, which becomes a check
// once the line is reached (and the line and its tag go to the quieter text
// colour).

import 'package:flutter/material.dart';

import 'package:kute/models/chart_drawing.dart';
import 'package:kute/models/hl_price_line.dart';
import 'package:kute/screens/hyperliquid/components/hl_drawing_tools.dart';
import 'package:kute/screens/shared/charts/kute_chart_drawings.dart';

/// [lines] as the drawings' painters take them; reached ones in [reached].
List<ChartDrawing> hlPriceLineDrawings(
  List<HlPriceLine> lines, {
  required Color reached,
}) =>
    [
      for (final line in lines)
        ChartDrawing(
          id: 'price-line-${line.id}',
          tool: ChartDrawingTool.priceLine,
          points: [
            ChartDrawingPoint(timeMs: line.createdAtMs, price: line.level),
          ],
          colorValue: line.isReached ? reached.toARGB32() : null,
          dashed: true,
        ),
    ];

/// The line under [pos] within [tolerance] (a level's own hit distance),
/// the nearest when several are.
HlPriceLine? hlPriceLineAt(
  List<HlPriceLine> lines,
  KuteDrawingGeometry geom,
  Offset pos, {
  double tolerance = 12,
}) {
  HlPriceLine? best;
  var bestGap = tolerance;
  for (final line in lines) {
    final gap = (geom.yForPrice(line.level) - pos.dy).abs();
    if (gap <= bestGap) {
      best = line;
      bestGap = gap;
    }
  }
  return best;
}

/// The bells (a check once reached) at the plot's left end of each line.
class HlPriceLineBellsPainter extends CustomPainter {
  HlPriceLineBellsPainter({
    required this.lines,
    required this.color,
    required this.reachedColor,
    required this.halo,
    required this.resolveGeometry,
    required this.repaintKey,
  });

  final List<HlPriceLine> lines;
  final Color color;
  final Color reachedColor;
  final Color halo;
  final KuteDrawingGeometry? Function(Size size) resolveGeometry;
  final Object? repaintKey;

  static const double _inset = 11;
  static const double _size = 14;

  @override
  void paint(Canvas canvas, Size size) {
    final geom = resolveGeometry(size);
    if (geom == null) return;
    final backdrop = Paint()..color = halo;
    for (final line in lines) {
      final y = geom.yForPrice(line.level);
      if (!y.isFinite || y < 0 || y > geom.priceH) continue;
      final center = Offset(_inset, y);
      canvas.drawCircle(center, _size / 2 + 1, backdrop);
      hlPaintPriceLineMark(canvas, center, _size,
          color: line.isReached ? reachedColor : color,
          reached: line.isReached);
    }
  }

  @override
  bool shouldRepaint(covariant HlPriceLineBellsPainter old) =>
      !identical(old.lines, lines) ||
      old.repaintKey != repaintKey ||
      old.color != color ||
      old.reachedColor != reachedColor ||
      old.halo != halo;
}
