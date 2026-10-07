// lib/screens/shared/charts/kute_chart_trade_lines.dart
//
// The trade lines layer of the chart stack: the user's own position
// (entry, liquidation) and working orders (limits, take profit, stop
// loss) drawn as horizontal price lines with a right-edge tag, the way
// the venue's own chart shows them. Editable lines carry a grip on the
// tag and can be dragged to a new price; the host decides what a drop
// means (a modify order flow with its own review and step-up).
//
// Layering contract: a Positioned.fill sibling above the data painter
// and drawings, below the crosshair, inside its own RepaintBoundary.
// Lines live in price only; the host passes the SAME geometry resolver
// the drawings layer uses, so every line lands exactly on the scale.
// A line outside the visible window is not hidden: its tag is pinned to
// the nearest edge of the price area (never over a volume strip under
// it) with an arrow so the trader knows it is there.
//
// Tags are laid out by the one rule every chart shares
// (kute_chart_tag_layout.dart): they never cover each other, nor the
// latest price's own tag and point ([KuteChartTradeLinesPainter.latestTags]);
// an entry at the latest price is written "Entry ≈" beside it.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:kute/screens/shared/charts/kute_chart_drawings.dart';
import 'package:kute/screens/shared/charts/kute_chart_core.dart';
import 'package:kute/screens/shared/charts/kute_chart_tag_layout.dart';

enum ChartTradeLineKind { entry, liquidation, limit, takeProfit, stopLoss }

/// One horizontal trade line. [id] identifies the order (or the position)
/// so a drag can be reported back; [price] is where it sits; [editable]
/// lines get a grip and accept drags.
class ChartTradeLine {
  const ChartTradeLine({
    required this.id,
    required this.kind,
    required this.price,
    required this.label,
    this.detail,
    this.isBuy = true,
    this.editable = false,
  });

  final String id;
  final ChartTradeLineKind kind;
  final double price;

  /// Short tag text, e.g. "Entry", "Liq", "Buy 0.5", "TP", "SL".
  final String label;

  /// Optional second line in the tag, e.g. the size or the trigger.
  final String? detail;
  final bool isBuy;
  final bool editable;

  ChartTradeLine withPrice(double p) => ChartTradeLine(
        id: id,
        kind: kind,
        price: p,
        label: label,
        detail: detail,
        isBuy: isBuy,
        editable: editable,
      );
}

/// Colours the host resolves from its theme once per build.
class ChartTradeLinePalette {
  const ChartTradeLinePalette({
    required this.up,
    required this.down,
    required this.warning,
    required this.neutral,
    required this.tagBackground,
    required this.tagText,
  });
  final Color up, down, warning, neutral, tagBackground, tagText;
}

/// Where a line's tag was painted last frame, for hit-testing drags.
class ChartTradeLineHit {
  const ChartTradeLineHit(this.id, this.rect, this.y);
  final String id;
  final Rect rect;
  final double y;
}

/// Tag width the layout reserves on the right so a drag can start on it.
const double kuteTradeTagGrip = 14;

/// Where trade-line tags sit so that none covers another: the shared rule
/// ([kuteLayoutTags]) with nothing fixed. Returns the tops in the order
/// given.
List<double> spreadTradeTags(
  List<KuteTagSlot> tags, {
  required double maxBottom,
  double gap = 2,
}) =>
    kuteLayoutTags(tags, maxBottom: maxBottom, gap: gap);

/// The latest price's own tag on a chart: the y of its line and the slot
/// it is drawn in at the right edge (it never moves; trade tags keep off
/// it).
typedef KuteLatestTag = ({double y, double top, double height});

class KuteChartTradeLinesPainter extends CustomPainter {
  KuteChartTradeLinesPainter({
    required this.lines,
    required this.dragging,
    required this.palette,
    required this.resolveGeometry,
    required this.repaintKey,
    required this.hits,
    this.formatPrice,
    this.latestTags,
  });

  final List<ChartTradeLine> lines;

  /// The line being dragged, already at the finger's price; painted in
  /// place of its original with a stronger stroke and a live price.
  final ChartTradeLine? dragging;
  final ChartTradeLinePalette palette;
  final KuteDrawingGeometry? Function(Size size) resolveGeometry;
  final Object? repaintKey;

  /// Filled during paint with each tag's rect so the host's gesture
  /// handler can hit-test without re-laying out text. Shared list,
  /// cleared and refilled every paint.
  final List<ChartTradeLineHit> hits;
  final String Function(double price)? formatPrice;

  /// The latest price's own tags for this canvas (the Investing live
  /// price, each Predictions line's value), from the same geometry: no
  /// trade tag is laid over them, and an entry at one of their prices is
  /// written "Entry ≈" beside it.
  final List<KuteLatestTag> Function(Size size, KuteDrawingGeometry geom)?
      latestTags;

  Color _colorOf(ChartTradeLine l) {
    switch (l.kind) {
      case ChartTradeLineKind.entry:
        return l.isBuy ? palette.up : palette.down;
      case ChartTradeLineKind.liquidation:
        return palette.warning;
      case ChartTradeLineKind.limit:
        return l.isBuy ? palette.up : palette.down;
      case ChartTradeLineKind.takeProfit:
        return palette.up;
      case ChartTradeLineKind.stopLoss:
        return palette.down;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    hits.clear();
    if (lines.isEmpty && dragging == null) return;
    final geom = resolveGeometry(size);
    if (geom == null) return;
    final w = size.width;
    final priceH = geom.priceH;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, w, priceH));

    final latest = latestTags?.call(size, geom) ?? const <KuteLatestTag>[];

    final drag = dragging;
    final toPaint = <ChartTradeLine>[
      for (final l in lines)
        if (drag == null || l.id != drag.id) l,
      if (drag != null) drag,
    ];

    final tags = <({
      ChartTradeLine line,
      bool isDrag,
      Color color,
      TextPainter text,
      double y,
      double width,
      double height,
      double top,
    })>[];
    for (final l in toPaint) {
      final isDrag = drag != null && identical(l, drag);
      final color = _colorOf(l);
      final rawY = geom.yForPrice(l.price);
      final offscreen = rawY < 0 || rawY > priceH;
      final y = rawY.clamp(0.0, priceH).toDouble();
      final alpha =
          isDrag ? 1.0 : (l.kind == ChartTradeLineKind.entry ? 0.55 : 0.8);
      final linePaint = Paint()
        ..color = color.withValues(alpha: alpha)
        ..strokeWidth = isDrag ? 1.6 : 1.0;

      if (!offscreen) {
        // Dashed for the position references, solid for working orders.
        if (l.kind == ChartTradeLineKind.entry ||
            l.kind == ChartTradeLineKind.liquidation) {
          for (double x = 0; x < w; x += 9) {
            canvas.drawLine(
                Offset(x, y), Offset(math.min(x + 4.5, w), y), linePaint);
          }
        } else {
          canvas.drawLine(Offset(0, y), Offset(w, y), linePaint);
        }
      }

      // Tag: label, optional detail, live price while dragging, a grip on
      // editable lines, an arrow when the line is off the visible window.
      final priceText =
          formatPrice?.call(l.price) ?? l.price.toStringAsPrecision(6);
      final arrow = offscreen ? (rawY < 0 ? '▲ ' : '▼ ') : '';
      // An entry (an average price) at the latest price is the same level
      // on screen: its tag says so beside the latest price's own tag
      // instead of writing a second figure that reads the same.
      final atLatest = !isDrag &&
          !offscreen &&
          l.kind == ChartTradeLineKind.entry &&
          latest.any((t) => (t.y - y).abs() <= kuteTagMergePx);
      final text = isDrag
          ? '$arrow${l.label} $priceText'
          : atLatest
              ? '${l.label} ≈'
              : '$arrow${l.label}${l.detail != null ? ' · ${l.detail}' : ''}';
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: kuteChartFontFamily,
            color: isDrag ? palette.tagText : color,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: w * 0.6);
      final grip = l.editable ? kuteTradeTagGrip : 0.0;
      final tagW = tp.width + 10 + grip;
      // Editable tags are tall enough to grab with a thumb.
      final tagH = math.max(tp.height + 5, l.editable ? 24.0 : 0.0);
      final tagY =
          (y - tagH / 2).clamp(0.0, math.max(0.0, priceH - tagH)).toDouble();
      tags.add((
        line: l,
        isDrag: isDrag,
        color: color,
        text: tp,
        y: y,
        width: tagW,
        height: tagH,
        top: tagY,
      ));
    }

    // The tags, once every line is down: two lines close in price (a stop
    // just over the liquidation price, a take-profit beside the entry, an
    // entry at the latest price) would otherwise write one tag over the
    // other or over the latest price's own tag.
    final tops = kuteLayoutTags(
      [for (final t in tags) (top: t.top, height: t.height)],
      fixed: [for (final t in latest) (top: t.top, height: t.height)],
      maxBottom: priceH,
    );
    for (var i = 0; i < tags.length; i++) {
      final t = tags[i];
      final l = t.line;
      final isDrag = t.isDrag;
      final color = t.color;
      final tp = t.text;
      final tagH = t.height;
      final tagY = tops[i];
      final rect = Rect.fromLTWH(w - t.width, tagY, t.width, tagH);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));
      canvas.drawRRect(
          rrect,
          Paint()
            ..color = isDrag
                ? color.withValues(alpha: 0.95)
                : palette.tagBackground.withValues(alpha: 0.88));
      canvas.drawRRect(
          rrect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = color.withValues(alpha: isDrag ? 1 : 0.7));
      tp.paint(canvas, Offset(rect.left + 5, tagY + 2.5));
      if (l.editable) {
        // Grip: three short vertical bars on the tag's right end.
        final gripPaint = Paint()
          ..color = (isDrag ? palette.tagText : color).withValues(alpha: 0.9)
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round;
        final gx = rect.right - kuteTradeTagGrip / 2;
        for (final dx in [-3.0, 0.0, 3.0]) {
          canvas.drawLine(Offset(gx + dx, tagY + 4),
              Offset(gx + dx, tagY + tagH - 4), gripPaint);
        }
      }
      hits.add(ChartTradeLineHit(l.id, rect, t.y));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant KuteChartTradeLinesPainter old) {
    if (lines.isEmpty &&
        dragging == null &&
        old.lines.isEmpty &&
        old.dragging == null) {
      return false;
    }
    return !identical(old.lines, lines) ||
        !identical(old.dragging, dragging) ||
        old.repaintKey != repaintKey ||
        old.palette != palette;
  }
}

/// Topmost editable line whose tag contains [pos], or null.
ChartTradeLineHit? kuteHitTestTradeTags(
    List<ChartTradeLineHit> hits, Offset pos,
    {double tolerance = 8}) {
  for (var i = hits.length - 1; i >= 0; i--) {
    if (hits[i].rect.inflate(tolerance).contains(pos)) return hits[i];
  }
  return null;
}
