// lib/screens/shared/charts/kute_chart_drawings.dart
//
// The drawings layer of the shared chart stack: renders the user's saved
// annotations (ChartDrawing — trendlines, horizontal levels, rays,
// rectangles) plus hit-testing helpers for select/edit gestures.
//
// Layering contract (mirrors kute_chart_crosshair.dart): mounted as a
// Positioned.fill sibling ABOVE the data painter and BELOW the crosshair,
// inside its own RepaintBoundary. Drawings live in CHART coordinates
// (epoch ms, price); the hosting chart passes a [resolveGeometry] callback
// producing a [KuteDrawingGeometry] from the SAME price-domain computation
// its data painter uses, so annotations land exactly on the candles/line.
// Painters here never read Theme — colors come from the host.
//
// Performance: the painter draws a handful of primitives and repaints only
// when the drawing list identity, the draft/selection, or the geometry
// inputs change (the host folds its y-domain drivers into [repaintKey]).
// With no drawings and no draft it paints — and repaints — nothing.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:kute/models/chart_drawing.dart';
import 'package:kute/screens/shared/charts/kute_chart_core.dart';

// ───────────────────────────── geometry ─────────────────────────────

/// Maps chart coordinates (epoch ms, price) to canvas pixels for one
/// paint/hit-test pass. X follows the bar layout the HL painters use —
/// bar i's center sits at (i + 0.5) × slot — with time interpolated
/// BETWEEN neighbouring bar centers (never linear time→index arithmetic,
/// which breaks the moment a thin tape has gaps) and extrapolated past
/// either end using [bucketMs].
class KuteDrawingGeometry {
  /// Ascending bar open times, epoch ms. Must be non-empty.
  final List<int> timesMs;
  final double width;

  /// Price-area height (net of any volume strip) and fitted y-domain —
  /// straight from the host's shared geometry helper.
  final double priceH;
  final double loP;
  final double rangeP;

  /// Trailing bucket duration (ms) used to extrapolate x beyond the tape.
  final int bucketMs;

  const KuteDrawingGeometry({
    required this.timesMs,
    required this.width,
    required this.priceH,
    required this.loP,
    required this.rangeP,
    required this.bucketMs,
  });

  double get _slot => width / timesMs.length;

  double _centerX(int i) => (i + 0.5) * _slot;

  double xForTime(int timeMs) {
    final n = timesMs.length;
    final bucket = bucketMs > 0 ? bucketMs : 1;
    if (n == 1) {
      return _centerX(0) + (timeMs - timesMs[0]) / bucket * _slot;
    }
    if (timeMs <= timesMs.first) {
      return _centerX(0) - (timesMs.first - timeMs) / bucket * _slot;
    }
    if (timeMs >= timesMs.last) {
      return _centerX(n - 1) + (timeMs - timesMs.last) / bucket * _slot;
    }
    // Binary search: last bar with openTime <= timeMs.
    var lo = 0, hi = n - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (timesMs[mid] <= timeMs) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    final t0 = timesMs[lo], t1 = timesMs[lo + 1];
    final f = t1 > t0 ? (timeMs - t0) / (t1 - t0) : 0.0;
    return _centerX(lo) + f * (_centerX(lo + 1) - _centerX(lo));
  }

  /// Inverse of [xForTime] — for converting a touch position into a
  /// stored anchor time.
  int timeForX(double x) {
    final n = timesMs.length;
    final bucket = bucketMs > 0 ? bucketMs : 1;
    if (n == 1) {
      return timesMs[0] + ((x - _centerX(0)) / _slot * bucket).round();
    }
    if (x <= _centerX(0)) {
      return timesMs.first - ((_centerX(0) - x) / _slot * bucket).round();
    }
    if (x >= _centerX(n - 1)) {
      return timesMs.last + ((x - _centerX(n - 1)) / _slot * bucket).round();
    }
    final idx = (x / _slot - 0.5).floor().clamp(0, n - 2);
    final x0 = _centerX(idx), x1 = _centerX(idx + 1);
    final f = x1 > x0 ? ((x - x0) / (x1 - x0)).clamp(0.0, 1.0) : 0.0;
    return (timesMs[idx] + f * (timesMs[idx + 1] - timesMs[idx])).round();
  }

  double yForPrice(double price) => priceH * (1 - (price - loP) / rangeP);

  double priceForY(double y) => loP + (1 - y / priceH) * rangeP;

  Offset offsetFor(ChartDrawingPoint p) =>
      Offset(xForTime(p.timeMs), yForPrice(p.price));
}

// ───────────────────────────── hit-testing ─────────────────────────────

const kuteFibonacciLevels = [0.0, 0.236, 0.382, 0.5, 0.618, 0.786, 1.0];

TextPainter _noteText(String text, Color color) => TextPainter(
      text: TextSpan(text: text, style: TextStyle(
          fontFamily: kuteChartFontFamily, color: color, fontSize: 13)),
      textDirection: TextDirection.ltr,
      maxLines: 4,
      ellipsis: '…',
    )..layout(maxWidth: 180);

Rect _noteBounds(ChartDrawing drawing, KuteDrawingGeometry geom) {
  final label = _noteText(drawing.text ?? '', const Color(0xFFFFFFFF));
  final anchor = geom.offsetFor(drawing.points.first);
  return Rect.fromLTWH(
    anchor.dx.clamp(0.0, math.max(0, geom.width - label.width - 12)),
    anchor.dy.clamp(0.0, math.max(0, geom.priceH - label.height - 10)),
    label.width + 12,
    label.height + 10,
  );
}

double _distToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 <= 0) return (p - a).distance;
  final t =
      (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2).clamp(0.0, 1.0);
  return (p - Offset(a.dx + ab.dx * t, a.dy + ab.dy * t)).distance;
}

/// Extend a→b in the chosen direction. The price-area clip bounds vertical rays.
Offset _rayEnd(Offset a, Offset b, double width) {
  if ((b.dx - a.dx).abs() < 0.5) {
    return Offset(a.dx, b.dy < a.dy ? -1e6 : 1e6);
  }
  final slope = (b.dy - a.dy) / (b.dx - a.dx);
  final edge = b.dx > a.dx ? width : 0.0;
  return Offset(edge, a.dy + slope * (edge - a.dx));
}

/// A trend line's painted segment: a→b, or with [extend] from its
/// earlier point through its later one to the right edge.
(Offset, Offset) _trendSegment(Offset a, Offset b, double width, bool extend) {
  if (!extend) return (a, b);
  final (l, r) = a.dx <= b.dx ? (a, b) : (b, a);
  if ((r.dx - l.dx).abs() < 0.5) return (a, b);
  return (l, _rayEnd(l, r, width));
}

/// The part of segment a→b inside [r] (Liang–Barsky), or null.
(Offset, Offset)? kuteClipSegment(Offset a, Offset b, Rect r) {
  var t0 = 0.0, t1 = 1.0;
  final dx = b.dx - a.dx, dy = b.dy - a.dy;
  for (final (p, q) in [
    (-dx, a.dx - r.left),
    (dx, r.right - a.dx),
    (-dy, a.dy - r.top),
    (dy, r.bottom - a.dy),
  ]) {
    if (p == 0) {
      if (q < 0) return null;
      continue;
    }
    final t = q / p;
    if (p < 0) {
      if (t > t1) return null;
      if (t > t0) t0 = t;
    } else {
      if (t < t0) return null;
      if (t < t1) t1 = t;
    }
  }
  return (
    Offset(a.dx + dx * t0, a.dy + dy * t0),
    Offset(a.dx + dx * t1, a.dy + dy * t1),
  );
}

/// Both ends of the line through a and b, clipped to the plot's width so
/// an extended line reaches each edge without a wild coordinate.
(Offset, Offset) _extendedEnds(Offset a, Offset b, double width) {
  if ((b.dx - a.dx).abs() < 0.5) {
    return (Offset(a.dx, -1e6), Offset(a.dx, 1e6));
  }
  final slope = (b.dy - a.dy) / (b.dx - a.dx);
  return (
    Offset(0, a.dy + slope * (0 - a.dx)),
    Offset(width, a.dy + slope * (width - a.dx)),
  );
}

/// Parallel channel: the second rail is the base line a→b shifted by the
/// vertical offset of the third anchor from that line.
(Offset, Offset) _channelRail(Offset a, Offset b, Offset c) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  double dy;
  if (len2 <= 0) {
    dy = c.dy - a.dy;
  } else {
    final t = ((c.dx - a.dx) * ab.dx + (c.dy - a.dy) * ab.dy) / len2;
    dy = c.dy - (a.dy + ab.dy * t);
  }
  return (Offset(a.dx, a.dy + dy), Offset(b.dx, b.dy + dy));
}

String kuteFormatDrawingPrice(double v) {
  if (!v.isFinite) return '—';
  final a = v.abs();
  if (a >= 1000) return v.toStringAsFixed(1);
  if (a >= 1) return v.toStringAsFixed(2);
  return v.toStringAsPrecision(4);
}

String kuteFormatDrawingPct(double fraction) {
  if (!fraction.isFinite) return '—';
  final pct = fraction * 100;
  final sign = pct > 0 ? '+' : '';
  return '$sign${pct.toStringAsFixed(2)}%';
}

String kuteFormatDrawingDuration(int ms) {
  final d = Duration(milliseconds: ms.abs());
  if (d.inDays >= 1) {
    final h = d.inHours % 24;
    return h > 0 ? '${d.inDays}d ${h}h' : '${d.inDays}d';
  }
  if (d.inHours >= 1) {
    final m = d.inMinutes % 60;
    return m > 0 ? '${d.inHours}h ${m}m' : '${d.inHours}h';
  }
  return '${d.inMinutes}m';
}

/// Bars whose open time falls between two moments, inclusive.
int kuteBarsBetween(KuteDrawingGeometry geom, int t0, int t1) {
  final lo = math.min(t0, t1), hi = math.max(t0, t1);
  var n = 0;
  for (final t in geom.timesMs) {
    if (t >= lo && t <= hi) n++;
  }
  return n;
}

/// Does [pos] hit [drawing] within [tolerance] px? Rectangles hit on
/// their edges OR interior (a filled shape reads as tappable anywhere).
bool kuteDrawingHit(
  ChartDrawing drawing,
  KuteDrawingGeometry geom,
  Offset pos, {
  double tolerance = 12,
}) {
  switch (drawing.tool) {
    case ChartDrawingTool.level:
    case ChartDrawingTool.priceLine:
      final y = geom.yForPrice(drawing.points.first.price);
      return (pos.dy - y).abs() <= tolerance;
    case ChartDrawingTool.trendline:
      final (a, b) = _trendSegment(geom.offsetFor(drawing.points[0]),
          geom.offsetFor(drawing.points[1]), geom.width, drawing.extend);
      return _distToSegment(pos, a, b) <= tolerance;
    case ChartDrawingTool.ray:
      final a = geom.offsetFor(drawing.points[0]);
      final b = geom.offsetFor(drawing.points[1]);
      return _distToSegment(pos, a, _rayEnd(a, b, geom.width)) <= tolerance;
    case ChartDrawingTool.rect:
    case ChartDrawingTool.fibonacci:
      final a = geom.offsetFor(drawing.points[0]);
      final b = geom.offsetFor(drawing.points[1]);
      final r = Rect.fromPoints(a, b).inflate(tolerance);
      return r.contains(pos);
    case ChartDrawingTool.text:
      return _noteBounds(drawing, geom).inflate(tolerance).contains(pos);
    case ChartDrawingTool.horizontalRay:
      final a = geom.offsetFor(drawing.points.first);
      return pos.dx >= a.dx - tolerance && (pos.dy - a.dy).abs() <= tolerance;
    case ChartDrawingTool.verticalLine:
      final x = geom.xForTime(drawing.points.first.timeMs);
      return (pos.dx - x).abs() <= tolerance;
    case ChartDrawingTool.extendedLine:
      final a = geom.offsetFor(drawing.points[0]);
      final b = geom.offsetFor(drawing.points[1]);
      final (e0, e1) = _extendedEnds(a, b, geom.width);
      return _distToSegment(pos, e0, e1) <= tolerance;
    case ChartDrawingTool.parallelChannel:
      final a = geom.offsetFor(drawing.points[0]);
      final b = geom.offsetFor(drawing.points[1]);
      final (c0, c1) = _channelRail(a, b, geom.offsetFor(drawing.points[2]));
      if (_distToSegment(pos, a, b) <= tolerance ||
          _distToSegment(pos, c0, c1) <= tolerance) {
        return true;
      }
      // Inside the band: between the rails over the base's x extent.
      final left = math.min(a.dx, b.dx) - tolerance;
      final right = math.max(a.dx, b.dx) + tolerance;
      if (pos.dx < left || pos.dx > right) return false;
      final t = (b.dx - a.dx).abs() < 0.5
          ? 0.0
          : ((pos.dx - a.dx) / (b.dx - a.dx)).clamp(0.0, 1.0);
      final y0 = a.dy + (b.dy - a.dy) * t;
      final y1 = c0.dy + (c1.dy - c0.dy) * t;
      return pos.dy >= math.min(y0, y1) - tolerance &&
          pos.dy <= math.max(y0, y1) + tolerance;
    case ChartDrawingTool.longPosition:
    case ChartDrawingTool.shortPosition:
      final entry = geom.offsetFor(drawing.points[0]);
      final target = geom.offsetFor(drawing.points[1]);
      final stopY = geom.yForPrice(drawing.points[2].price);
      final left = math.min(entry.dx, target.dx);
      final right = math.max(entry.dx, target.dx);
      final top = math.min(math.min(entry.dy, target.dy), stopY);
      final bottom = math.max(math.max(entry.dy, target.dy), stopY);
      return Rect.fromLTRB(left, top, right, bottom)
          .inflate(tolerance)
          .contains(pos);
    case ChartDrawingTool.priceRange:
    case ChartDrawingTool.dateRange:
    case ChartDrawingTool.dateAndPriceRange:
      final a = geom.offsetFor(drawing.points[0]);
      final b = geom.offsetFor(drawing.points[1]);
      return Rect.fromPoints(a, b).inflate(tolerance).contains(pos);
  }
}

/// Topmost (most recently created) drawing under [pos], or null.
String? kuteHitTestDrawings(
  List<ChartDrawing> drawings,
  KuteDrawingGeometry geom,
  Offset pos, {
  double tolerance = 12,
}) {
  for (var i = drawings.length - 1; i >= 0; i--) {
    if (kuteDrawingHit(drawings[i], geom, pos, tolerance: tolerance)) {
      return drawings[i].id;
    }
  }
  return null;
}

/// Index of the anchor handle of [drawing] under [pos], or null. Handles
/// get a wider grab radius than line hits so they win the tie.
int? kuteHitTestHandle(
  ChartDrawing drawing,
  KuteDrawingGeometry geom,
  Offset pos, {
  double tolerance = 28,
}) {
  int? best;
  var bestD = tolerance;
  for (var i = 0; i < drawing.points.length; i++) {
    final d = (geom.offsetFor(drawing.points[i]) - pos).distance;
    if (d <= bestD) {
      bestD = d;
      best = i;
    }
  }
  return best;
}

/// The box a drawing occupies on the plot, for placing its floating
/// toolbar: its anchors' bounds (a level spans the plot's width at its
/// price; a note, its card).
Rect kuteDrawingBounds(ChartDrawing drawing, KuteDrawingGeometry geom) {
  if (drawing.points.isEmpty) return Rect.zero;
  if (drawing.tool == ChartDrawingTool.text && drawing.text != null) {
    return _noteBounds(drawing, geom);
  }
  var rect = Rect.fromCenter(
      center: geom.offsetFor(drawing.points.first), width: 0, height: 0);
  for (final p in drawing.points.skip(1)) {
    rect = rect.expandToInclude(
        Rect.fromCenter(center: geom.offsetFor(p), width: 0, height: 0));
  }
  return rect;
}

/// Whether a drawing's tool puts a price tag in the chart's tag column:
/// the price lines (a horizontal line, a horizontal ray).
bool kuteDrawingHasPriceTag(ChartDrawing drawing) =>
    drawing.tool == ChartDrawingTool.level ||
    drawing.tool == ChartDrawingTool.horizontalRay ||
    drawing.tool == ChartDrawingTool.priceLine;

/// The price tags of the horizontal drawings, in the chart's tag column:
/// the same small, fully rounded filled pill as the latest price's, in
/// the drawing's colour. Mounted full width over the chart; the geometry
/// maps across the plot only (the column starts at its right edge).
class KuteDrawingPriceTagsPainter extends CustomPainter {
  final List<ChartDrawing> drawings;
  final double tagColumn;
  final double tagLead;
  final Color neutralColor;
  final double fontSize;
  final double padH;
  final double padV;
  final String Function(double price) formatPrice;
  final KuteDrawingGeometry? Function(Size size) resolveGeometry;
  final Object? repaintKey;

  KuteDrawingPriceTagsPainter({
    required this.drawings,
    required this.tagColumn,
    required this.tagLead,
    required this.neutralColor,
    required this.fontSize,
    required this.padH,
    required this.padV,
    required this.formatPrice,
    required this.resolveGeometry,
    required this.repaintKey,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (tagColumn <= 0) return;
    final geom = resolveGeometry(size);
    if (geom == null) return;
    final left = math.min(geom.width + tagLead, size.width);
    for (final d in drawings) {
      if (!kuteDrawingHasPriceTag(d) || !d.isValid) continue;
      final price = d.points.first.price;
      final y = geom.yForPrice(price);
      if (!y.isFinite || y < 0 || y > geom.priceH) continue;
      final color = d.color ?? neutralColor;
      final fg = color.computeLuminance() > 0.55
          ? const Color(0xFF000000)
          : const Color(0xFFFFFFFF);
      final tp = TextPainter(
        text: TextSpan(
          text: formatPrice(price),
          style: TextStyle(
            fontFamily: kuteChartFontFamily,
            color: fg,
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final w = tp.width + padH * 2, h = tp.height + padV * 2;
      final x = math.max(0.0, math.min(left, size.width - w));
      final top =
          (y - h / 2).clamp(0.0, math.max(0.0, geom.priceH - h)).toDouble();
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(x, top, w, h), Radius.circular(h / 2)),
          Paint()..color = color);
      tp.paint(canvas, Offset(x + padH, top + padV));
    }
  }

  @override
  bool shouldRepaint(covariant KuteDrawingPriceTagsPainter old) =>
      !identical(old.drawings, drawings) ||
      old.repaintKey != repaintKey ||
      old.tagColumn != tagColumn ||
      old.neutralColor != neutralColor ||
      old.fontSize != fontSize;
}

// ───────────────────────────── painter ─────────────────────────────

class KuteChartDrawingsPainter extends CustomPainter {
  final List<ChartDrawing> drawings;

  /// In-progress placement (tap-drag) — rendered like a normal drawing at
  /// reduced alpha, with handles, so the user sees exactly what lands.
  final ChartDrawing? draft;
  final String? selectedId;

  /// Default stroke for drawings with no picked color (theme neutral).
  final Color neutralColor;

  /// Handle core (theme background) so handles read on any stroke color.
  final Color handleCore;

  /// Same-geometry mapper as the data painter; returning null skips the
  /// paint entirely (e.g. mid-morph, when x space is resampled).
  final KuteDrawingGeometry? Function(Size size) resolveGeometry;

  /// Value-compared token folding in everything that moves the geometry
  /// (candle window identity, y-domain drivers, theme) — drives
  /// shouldRepaint alongside the drawing list/selection identity.
  final Object? repaintKey;

  KuteChartDrawingsPainter({
    required this.drawings,
    required this.draft,
    required this.selectedId,
    required this.neutralColor,
    required this.handleCore,
    required this.resolveGeometry,
    required this.repaintKey,
  });

  Color _colorOf(ChartDrawing d) => d.color ?? neutralColor;

  /// A small pill with [text] anchored at [at] (top-left), kept inside the
  /// plot. Used by the measuring and position tools.
  void _pill(Canvas canvas, KuteDrawingGeometry geom, Offset at, String text,
      Color color,
      {bool strong = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: kuteChartFontFamily,
          color: strong ? handleCore : color,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
    )..layout(maxWidth: 200);
    final w = tp.width + 10, h = tp.height + 6;
    // A label belongs to its drawing. When the anchor sits well outside
    // the plot (the drawing was made on another window and scrolled
    // away), the tag is not dragged into a corner where it reads as a
    // figure about the visible chart.
    if (at.dx + w < -8 ||
        at.dx > geom.width + 8 ||
        at.dy + h < -8 ||
        at.dy > geom.priceH + 8) {
      return;
    }
    final x = at.dx.clamp(0.0, math.max(0.0, geom.width - w)).toDouble();
    final y = at.dy.clamp(0.0, math.max(0.0, geom.priceH - h)).toDouble();
    final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, w, h), const Radius.circular(4));
    canvas.drawRRect(
        rect,
        Paint()
          ..color = strong
              ? color.withValues(alpha: 0.9)
              : handleCore.withValues(alpha: 0.9));
    if (!strong) {
      canvas.drawRRect(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = color.withValues(alpha: 0.6));
    }
    tp.paint(canvas, Offset(x + 5, y + 3));
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint paint,
      {double dash = 5, double gap = 4}) {
    final total = (b - a).distance;
    if (total <= 0) return;
    final dir = (b - a) / total;
    var t = 0.0;
    while (t < total) {
      final end = math.min(t + dash, total);
      canvas.drawLine(a + dir * t, a + dir * end, paint);
      t = end + gap;
    }
  }

  /// The plot of the current paint pass (dashes are only laid along the
  /// stretch of a line that can be seen).
  Rect _visible = Rect.zero;

  /// A drawing's own stroke: solid, or dashed when the drawing says so.
  void _line(Canvas canvas, Offset a, Offset b, Paint paint, bool dashed) {
    if (!dashed) {
      canvas.drawLine(a, b, paint);
      return;
    }
    final seg = kuteClipSegment(a, b, _visible.inflate(8));
    if (seg == null) return;
    _dashed(canvas, seg.$1, seg.$2, paint, dash: 6, gap: 4);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (drawings.isEmpty && draft == null) return;
    final geom = resolveGeometry(size);
    if (geom == null) return;

    _visible = Rect.fromLTWH(0, 0, size.width, geom.priceH);
    canvas.save();
    // Clip to the price area — drawings never bleed into the volume strip.
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, geom.priceH));

    for (final d in drawings) {
      _paintDrawing(canvas, geom, d,
          selected: d.id == selectedId, isDraft: false);
    }
    final dr = draft;
    if (dr != null) {
      _paintDrawing(canvas, geom, dr, selected: true, isDraft: true);
    }
    canvas.restore();
  }

  void _paintDrawing(
    Canvas canvas,
    KuteDrawingGeometry geom,
    ChartDrawing d, {
    required bool selected,
    required bool isDraft,
  }) {
    if (!d.isValid) return;
    final color = _colorOf(d);
    final dash = d.dashed || d.tool == ChartDrawingTool.priceLine;
    // A placement whose second point is not down yet: just its anchor.
    if (isDraft &&
        d.points.every((p) =>
            p.timeMs == d.points.first.timeMs &&
            p.price == d.points.first.price)) {
      _handle(canvas, geom.offsetFor(d.points.first), color);
      return;
    }
    final alpha = isDraft ? 0.55 : (selected ? 0.95 : 0.75);
    final stroke = Paint()
      ..color = color.withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 2.0 : 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (d.tool) {
      case ChartDrawingTool.level:
      case ChartDrawingTool.priceLine:
        final y = geom.yForPrice(d.points.first.price);
        _line(canvas, Offset(0, y), Offset(geom.width, y), stroke, dash);
        break;
      case ChartDrawingTool.trendline:
        final (a, b) = _trendSegment(geom.offsetFor(d.points[0]),
            geom.offsetFor(d.points[1]), geom.width, d.extend);
        _line(canvas, a, b, stroke, dash);
        break;
      case ChartDrawingTool.ray:
        final a = geom.offsetFor(d.points[0]);
        final b = geom.offsetFor(d.points[1]);
        _line(canvas, a, _rayEnd(a, b, geom.width), stroke, dash);
        break;
      case ChartDrawingTool.rect:
        final r = Rect.fromPoints(
          geom.offsetFor(d.points[0]),
          geom.offsetFor(d.points[1]),
        );
        canvas.drawRect(r, Paint()..color = color.withValues(alpha: 0.08));
        if (dash) {
          _line(canvas, r.topLeft, r.topRight, stroke, true);
          _line(canvas, r.topRight, r.bottomRight, stroke, true);
          _line(canvas, r.bottomRight, r.bottomLeft, stroke, true);
          _line(canvas, r.bottomLeft, r.topLeft, stroke, true);
        } else {
          canvas.drawRect(r, stroke);
        }
        if (selected && !isDraft) {
          // Selected: the zone's height in price and per cent of its
          // lower edge, under it, in the measure tool's pill.
          final lo = math.min(d.points[0].price, d.points[1].price);
          final hi = math.max(d.points[0].price, d.points[1].price);
          _pill(
              canvas,
              geom,
              Offset(r.center.dx - 50, r.bottom + 4),
              '${kuteFormatDrawingPrice(hi - lo)} (${kuteFormatDrawingPct(lo > 0 ? (hi - lo) / lo : double.nan).replaceFirst('+', '')})',
              color,
              strong: true);
        }
        break;
      case ChartDrawingTool.fibonacci:
        final a = geom.offsetFor(d.points[0]);
        final b = geom.offsetFor(d.points[1]);
        final left = math.min(a.dx, b.dx);
        final right = math.max(a.dx, b.dx);
        for (final ratio in kuteFibonacciLevels) {
          final price = d.points[0].price +
              (d.points[1].price - d.points[0].price) * ratio;
          final y = geom.yForPrice(price);
          _line(canvas, Offset(left, y), Offset(right, y), stroke, dash);
          final label = TextPainter(
            text: TextSpan(
              text:
                  '${(ratio * 100).toStringAsFixed(ratio == 0 || ratio == 1 ? 0 : 1)}%  ${price.toStringAsPrecision(6)}',
              style: TextStyle(
                  fontFamily: kuteChartFontFamily,
                  color: color,
                  fontSize: 10),
            ),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: math.max(1, right - left));
          label.paint(canvas, Offset(left + 3, y - label.height - 2));
        }
        break;
      case ChartDrawingTool.horizontalRay:
        final a = geom.offsetFor(d.points.first);
        _line(canvas, a, Offset(geom.width, a.dy), stroke, dash);
        break;
      case ChartDrawingTool.verticalLine:
        final x = geom.xForTime(d.points.first.timeMs);
        _line(canvas, Offset(x, 0), Offset(x, geom.priceH), stroke, dash);
        break;
      case ChartDrawingTool.extendedLine:
        final (e0, e1) = _extendedEnds(geom.offsetFor(d.points[0]),
            geom.offsetFor(d.points[1]), geom.width);
        _line(canvas, e0, e1, stroke, dash);
        break;
      case ChartDrawingTool.parallelChannel:
        final a = geom.offsetFor(d.points[0]);
        final b = geom.offsetFor(d.points[1]);
        final (c0, c1) = _channelRail(a, b, geom.offsetFor(d.points[2]));
        canvas.drawPath(
            Path()
              ..moveTo(a.dx, a.dy)
              ..lineTo(b.dx, b.dy)
              ..lineTo(c1.dx, c1.dy)
              ..lineTo(c0.dx, c0.dy)
              ..close(),
            Paint()..color = color.withValues(alpha: 0.08));
        _line(canvas, a, b, stroke, dash);
        _line(canvas, c0, c1, stroke, dash);
        // The middle line, the way traders read a channel's centre.
        _dashed(
            canvas,
            Offset((a.dx + c0.dx) / 2, (a.dy + c0.dy) / 2),
            Offset((b.dx + c1.dx) / 2, (b.dy + c1.dy) / 2),
            Paint()
              ..color = color.withValues(alpha: alpha * 0.6)
              ..strokeWidth = 1);
        break;
      case ChartDrawingTool.longPosition:
      case ChartDrawingTool.shortPosition:
        final long = d.tool == ChartDrawingTool.longPosition;
        final entryPx = d.points[0].price;
        final targetPx = d.points[1].price;
        final stopPx = d.points[2].price;
        final entry = geom.offsetFor(d.points[0]);
        final target = geom.offsetFor(d.points[1]);
        final stopY = geom.yForPrice(stopPx);
        final left = math.min(entry.dx, target.dx);
        final right = math.max(entry.dx, target.dx);
        final profit = Rect.fromLTRB(left, math.min(entry.dy, target.dy), right,
            math.max(entry.dy, target.dy));
        final risk = Rect.fromLTRB(
            left, math.min(entry.dy, stopY), right, math.max(entry.dy, stopY));
        const up = Color(0xFF16A34A);
        const down = Color(0xFFDC2626);
        canvas.drawRect(profit, Paint()..color = up.withValues(alpha: 0.16));
        canvas.drawRect(risk, Paint()..color = down.withValues(alpha: 0.16));
        canvas.drawLine(
            Offset(left, entry.dy),
            Offset(right, entry.dy),
            Paint()
              ..color = color.withValues(alpha: alpha)
              ..strokeWidth = 1.4);
        canvas.drawLine(
            Offset(left, target.dy),
            Offset(right, target.dy),
            Paint()
              ..color = up
              ..strokeWidth = 1.2);
        canvas.drawLine(
            Offset(left, stopY),
            Offset(right, stopY),
            Paint()
              ..color = down
              ..strokeWidth = 1.2);
        final reward = (targetPx - entryPx).abs();
        final riskAmt = (stopPx - entryPx).abs();
        final rr = riskAmt > 0 ? reward / riskAmt : double.nan;
        final sign = long ? 1.0 : -1.0;
        _pill(
            canvas,
            geom,
            Offset(left + 4, math.min(entry.dy, target.dy) + 4),
            'Target ${kuteFormatDrawingPrice(targetPx)}  ${kuteFormatDrawingPct(sign * (targetPx - entryPx) / entryPx)}',
            up);
        _pill(
            canvas,
            geom,
            Offset(left + 4, math.max(entry.dy, stopY) - 26),
            'Stop ${kuteFormatDrawingPrice(stopPx)}  ${kuteFormatDrawingPct(sign * (stopPx - entryPx) / entryPx)}',
            down);
        _pill(
            canvas,
            geom,
            Offset(right - 96, entry.dy - 11),
            '${long ? 'Long' : 'Short'} ${kuteFormatDrawingPrice(entryPx)} · R/R ${rr.isFinite ? rr.toStringAsFixed(2) : '—'}',
            color,
            strong: true);
        break;
      case ChartDrawingTool.priceRange:
      case ChartDrawingTool.dateRange:
      case ChartDrawingTool.dateAndPriceRange:
        final a = geom.offsetFor(d.points[0]);
        final b = geom.offsetFor(d.points[1]);
        final r = Rect.fromPoints(a, b);
        final p0 = d.points[0].price, p1 = d.points[1].price;
        final t0 = d.points[0].timeMs, t1 = d.points[1].timeMs;
        final measuresPrice = d.tool != ChartDrawingTool.dateRange;
        final measuresTime = d.tool != ChartDrawingTool.priceRange;
        canvas.drawRect(r, Paint()..color = color.withValues(alpha: 0.10));
        if (measuresPrice) {
          final x = r.center.dx;
          canvas.drawLine(Offset(x, r.top), Offset(x, r.bottom), stroke);
          canvas.drawLine(
              Offset(r.left, r.top), Offset(r.right, r.top), stroke);
          canvas.drawLine(
              Offset(r.left, r.bottom), Offset(r.right, r.bottom), stroke);
        }
        if (measuresTime) {
          final y = r.center.dy;
          canvas.drawLine(Offset(r.left, y), Offset(r.right, y), stroke);
          canvas.drawLine(
              Offset(r.left, r.top), Offset(r.left, r.bottom), stroke);
          canvas.drawLine(
              Offset(r.right, r.top), Offset(r.right, r.bottom), stroke);
        }
        final parts = <String>[];
        if (measuresPrice) {
          parts.add(
              '${p1 - p0 >= 0 ? '+' : '−'}${kuteFormatDrawingPrice((p1 - p0).abs())} (${kuteFormatDrawingPct(p0 != 0 ? (p1 - p0) / p0 : double.nan)})');
        }
        if (measuresTime) {
          parts.add(
              '${kuteBarsBetween(geom, t0, t1)} bars · ${kuteFormatDrawingDuration(t1 - t0)}');
        }
        _pill(canvas, geom, Offset(r.center.dx - 50, r.bottom + 4),
            parts.join('\n'), color,
            strong: true);
        break;
      case ChartDrawingTool.text:
        final rect = _noteBounds(d, geom);
        canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(5)),
            Paint()..color = handleCore.withValues(alpha: 0.9));
        if (selected) {
          canvas.drawRRect(
              RRect.fromRectAndRadius(rect, const Radius.circular(5)), stroke);
        }
        _noteText(d.text!, color)
            .paint(canvas, rect.topLeft + const Offset(6, 5));
        break;
    }

    // A locked drawing shows no handles: nothing on it can be dragged.
    if (selected && !d.locked) {
      for (final p in d.points) {
        _handle(canvas, geom.offsetFor(p), color);
      }
    }
  }

  /// Handles read as grabbable on a phone: a wide soft halo, a solid
  /// disc and a core in the background colour.
  void _handle(Canvas canvas, Offset o, Color color) {
    canvas.drawCircle(o, 12.0, Paint()..color = color.withValues(alpha: 0.16));
    canvas.drawCircle(o, 7.0, Paint()..color = color);
    canvas.drawCircle(o, 3.5, Paint()..color = handleCore);
  }

  @override
  bool shouldRepaint(covariant KuteChartDrawingsPainter old) {
    // Fully idle layer (nothing drawn before or now): never re-raster.
    if (drawings.isEmpty &&
        draft == null &&
        old.drawings.isEmpty &&
        old.draft == null) {
      return false;
    }
    return !identical(old.drawings, drawings) ||
        !identical(old.draft, draft) ||
        old.selectedId != selectedId ||
        old.repaintKey != repaintKey ||
        old.neutralColor != neutralColor ||
        old.handleCore != handleCore;
  }
}
