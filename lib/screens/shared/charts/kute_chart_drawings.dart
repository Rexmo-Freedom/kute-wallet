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
      final y = geom.yForPrice(drawing.points.first.price);
      return (pos.dy - y).abs() <= tolerance;
    case ChartDrawingTool.trendline:
      final a = geom.offsetFor(drawing.points[0]);
      final b = geom.offsetFor(drawing.points[1]);
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

  @override
  void paint(Canvas canvas, Size size) {
    if (drawings.isEmpty && draft == null) return;
    final geom = resolveGeometry(size);
    if (geom == null) return;

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
    final alpha = isDraft ? 0.55 : (selected ? 0.95 : 0.75);
    final stroke = Paint()
      ..color = color.withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 2.0 : 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (d.tool) {
      case ChartDrawingTool.level:
        final y = geom.yForPrice(d.points.first.price);
        canvas.drawLine(Offset(0, y), Offset(geom.width, y), stroke);
        break;
      case ChartDrawingTool.trendline:
        canvas.drawLine(
          geom.offsetFor(d.points[0]),
          geom.offsetFor(d.points[1]),
          stroke,
        );
        break;
      case ChartDrawingTool.ray:
        final a = geom.offsetFor(d.points[0]);
        final b = geom.offsetFor(d.points[1]);
        canvas.drawLine(a, _rayEnd(a, b, geom.width), stroke);
        break;
      case ChartDrawingTool.rect:
        final r = Rect.fromPoints(
          geom.offsetFor(d.points[0]),
          geom.offsetFor(d.points[1]),
        );
        canvas.drawRect(r, Paint()..color = color.withValues(alpha: 0.08));
        canvas.drawRect(r, stroke);
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
          canvas.drawLine(Offset(left, y), Offset(right, y), stroke);
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
        canvas.drawLine(a, Offset(geom.width, a.dy), stroke);
        break;
      case ChartDrawingTool.verticalLine:
        final x = geom.xForTime(d.points.first.timeMs);
        canvas.drawLine(Offset(x, 0), Offset(x, geom.priceH), stroke);
        break;
      case ChartDrawingTool.extendedLine:
        final (e0, e1) = _extendedEnds(geom.offsetFor(d.points[0]),
            geom.offsetFor(d.points[1]), geom.width);
        canvas.drawLine(e0, e1, stroke);
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
        canvas.drawLine(a, b, stroke);
        canvas.drawLine(c0, c1, stroke);
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

    if (selected) {
      for (final p in d.points) {
        final o = geom.offsetFor(p);
        // Handles read as grabbable on a phone: a wide soft halo, a
        // solid disc and a core in the background colour.
        canvas.drawCircle(
            o, 12.0, Paint()..color = color.withValues(alpha: 0.16));
        canvas.drawCircle(o, 7.0, Paint()..color = color);
        canvas.drawCircle(o, 3.5, Paint()..color = handleCore);
      }
    }
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
