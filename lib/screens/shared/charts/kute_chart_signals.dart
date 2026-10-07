// lib/screens/shared/charts/kute_chart_signals.dart
//
// The market-signals layer of the chart stack: optional, quiet marks
// about the MARKET (never the user's own trades, which are the trade
// lines layer). All of it is off until the host hands something in:
//
//   * levels: a thin dotted line at a price with a small tag on the left
//     edge (Predictions odds at a strike). A level outside the visible
//     prices is pinned to the nearest edge with an arrow.
//   * dates: a dashed vertical line at a time with a small label (a
//     funding flip, a Fed decision). A date ahead of the newest bar can
//     be pinned to the right edge as a tag instead, since the plot ends
//     at the live bar.
//   * dots: a small ring at a time and price (an unusually large trade).
//   * caption: one line of text in the top left corner (open interest).
//
// Layering contract: a Positioned.fill sibling above the trade lines and
// below the crosshair, inside its own RepaintBoundary, mapped through the
// SAME geometry resolver the drawings and trade lines use. Everything is
// drawn in the host's neutral and up/down colours at low weight so the
// price stays the subject.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:kute/screens/shared/charts/kute_chart_drawings.dart';
import 'package:kute/screens/shared/charts/kute_chart_core.dart';
import 'package:kute/screens/shared/charts/kute_chart_trade_lines.dart'
    show spreadTradeTags;

/// A horizontal level. [id] comes back from a tap on its tag.
class ChartSignalLevel {
  const ChartSignalLevel({
    required this.id,
    required this.price,
    required this.label,
  });
  final String id;
  final double price;
  final String label;
}

/// A vertical date mark. [id] non-null makes its pinned tag tappable.
class ChartSignalDate {
  const ChartSignalDate({
    required this.timeMs,
    required this.label,
    this.id,
    this.pinWhenAhead = false,
  });
  final int timeMs;
  final String label;
  final String? id;

  /// Show as a right-edge tag while the date is ahead of the plot.
  final bool pinWhenAhead;
}

/// A ring at one trade.
class ChartSignalDot {
  const ChartSignalDot({
    required this.timeMs,
    required this.price,
    required this.isBuy,
  });
  final int timeMs;
  final double price;
  final bool isBuy;
}

/// Everything the layer draws. The host builds one and keeps its identity
/// until something in it changes: the painter repaints on identity.
class ChartSignals {
  const ChartSignals({
    this.levels = const [],
    this.dates = const [],
    this.dots = const [],
    this.caption,
  });
  final List<ChartSignalLevel> levels;
  final List<ChartSignalDate> dates;
  final List<ChartSignalDot> dots;
  final String? caption;

  bool get isEmpty =>
      levels.isEmpty && dates.isEmpty && dots.isEmpty && caption == null;

  static const none = ChartSignals();
}

/// Colours the host resolves from its theme once per build.
class ChartSignalPalette {
  const ChartSignalPalette({
    required this.neutral,
    required this.up,
    required this.down,
    required this.tagBackground,
  });
  final Color neutral, up, down, tagBackground;

  @override
  bool operator ==(Object other) =>
      other is ChartSignalPalette &&
      other.neutral == neutral &&
      other.up == up &&
      other.down == down &&
      other.tagBackground == tagBackground;

  @override
  int get hashCode => Object.hash(neutral, up, down, tagBackground);
}

/// Where a tappable tag was painted last frame.
class ChartSignalHit {
  const ChartSignalHit(this.id, this.rect);
  final String id;
  final Rect rect;
}

class KuteChartSignalsPainter extends CustomPainter {
  KuteChartSignalsPainter({
    required this.signals,
    required this.palette,
    required this.resolveGeometry,
    required this.repaintKey,
    required this.hits,
  });

  final ChartSignals signals;
  final ChartSignalPalette palette;
  final KuteDrawingGeometry? Function(Size size) resolveGeometry;
  final Object? repaintKey;

  /// Filled during paint with each tappable tag's rect. Shared list,
  /// cleared and refilled every paint.
  final List<ChartSignalHit> hits;

  static const double _tagFont = 9.5;
  static const double _tagStep = 17;

  TextPainter _text(String text, Color color, double maxWidth) => TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: kuteChartFontFamily,
            color: color,
            fontSize: _tagFont,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: maxWidth);

  /// A small bordered tag with its top-left at [at]; returns its rect.
  Rect _tag(Canvas canvas, TextPainter tp, Offset at) {
    final rect = Rect.fromLTWH(at.dx, at.dy, tp.width + 8, tp.height + 4);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));
    canvas.drawRRect(
        rrect, Paint()..color = palette.tagBackground.withValues(alpha: 0.85));
    canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = palette.neutral.withValues(alpha: 0.35));
    tp.paint(canvas, Offset(rect.left + 4, rect.top + 2));
    return rect;
  }

  @override
  void paint(Canvas canvas, Size size) {
    hits.clear();
    if (signals.isEmpty) return;
    final geom = resolveGeometry(size);
    if (geom == null) return;
    final w = size.width;
    final priceH = geom.priceH;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, w, priceH));
    final line = Paint()
      ..color = palette.neutral.withValues(alpha: 0.32)
      ..strokeWidth = 1;

    // Caption, top left: laid out here, drawn with the level tags below
    // so that none of them covers it.
    var topLeft = 4.0;
    final caption = signals.caption;
    final captionText =
        caption == null ? null : _text(caption, palette.neutral, w * 0.7);
    if (captionText != null) topLeft += _tagStep;

    // Dates: a dashed vertical in view, a right-edge tag when ahead.
    var topRight = 4.0;
    final dateLabels = <({TextPainter text, double left})>[];
    for (final d in signals.dates) {
      final x = geom.xForTime(d.timeMs);
      if (x < 0) continue;
      if (x > w) {
        if (!d.pinWhenAhead) continue;
        final tp = _text('${d.label} ›', palette.neutral, w * 0.5);
        final rect = _tag(canvas, tp, Offset(w - tp.width - 12, topRight));
        if (d.id != null) hits.add(ChartSignalHit(d.id!, rect));
        topRight += _tagStep;
        continue;
      }
      for (double y = 0; y < priceH; y += 7) {
        canvas.drawLine(Offset(x, y), Offset(x, math.min(y + 3, priceH)), line);
      }
      final tp = _text(d.label, palette.neutral, w * 0.4);
      final left = (x + 3).clamp(0.0, math.max(0.0, w - tp.width - 2));
      dateLabels.add((text: tp, left: left.toDouble()));
    }
    // The names of the dates in view, along the foot of the plot. Dates
    // close together (funding that flipped twice in a day on a 4h chart)
    // would be written through each other: the latest keeps its name and
    // one that would run into a name already written is left as its line.
    for (final i in signalDateLabelsKept(
        [for (final l in dateLabels) (left: l.left, width: l.text.width)])) {
      final label = dateLabels[i];
      label.text
          .paint(canvas, Offset(label.left, priceH - label.text.height - 2));
    }

    // Levels: a dotted line and a left tag; pinned when off the scale.
    // The tags are placed together once every line is down: a level near
    // the top of the scale sits where the pinned ones stack, and two
    // levels close in price share a few pixels.
    var pinnedBelow = 0.0;
    final tags = <({String? id, TextPainter text, double top})>[
      if (captionText != null) (id: null, text: captionText, top: 4.0),
    ];
    // The caption and the levels off the top of the scale have the top
    // of the plot; a level on the scale starts under them.
    var laneBottom = topLeft;
    for (final l in signals.levels) {
      final y = geom.yForPrice(l.price);
      if (y.isFinite && y < 0) laneBottom += _tagStep;
    }
    for (final l in signals.levels) {
      final rawY = geom.yForPrice(l.price);
      if (!rawY.isFinite) continue;
      final above = rawY < 0, below = rawY > priceH;
      final tp = _text(
          '${above ? '▲ ' : below ? '▼ ' : ''}${l.label}',
          palette.neutral,
          w * 0.6);
      final double top;
      if (above) {
        top = topLeft;
        topLeft += _tagStep;
      } else if (below) {
        // Under every level that is on the scale: wanted past the floor,
        // which the spread brings back to it.
        top = priceH + pinnedBelow;
        pinnedBelow += _tagStep;
      } else {
        for (double x = 0; x < w; x += 6) {
          canvas.drawLine(
              Offset(x, rawY), Offset(math.min(x + 2, w), rawY), line);
        }
        final floor = math.max(0.0, priceH - tp.height - 4);
        top = (rawY - (tp.height + 4) / 2)
            .clamp(math.min(laneBottom, floor), floor)
            .toDouble();
      }
      tags.add((id: l.id, text: tp, top: top));
    }
    final tops = spreadTradeTags(
      [for (final t in tags) (top: t.top, height: t.text.height + 4)],
      maxBottom: priceH - 3,
      gap: 1.5,
    );
    for (var i = 0; i < tags.length; i++) {
      final rect = _tag(canvas, tags[i].text, Offset(4, tops[i]));
      final id = tags[i].id;
      if (id != null) hits.add(ChartSignalHit(id, rect));
    }

    // Dots: a ring where a large trade printed.
    for (final d in signals.dots) {
      final x = geom.xForTime(d.timeMs);
      final y = geom.yForPrice(d.price);
      if (x < 0 || x > w || !y.isFinite || y < 0 || y > priceH) continue;
      final color = d.isBuy ? palette.up : palette.down;
      canvas.drawCircle(Offset(x, y), 4,
          Paint()..color = palette.tagBackground.withValues(alpha: 0.7));
      canvas.drawCircle(
          Offset(x, y),
          4,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.3
            ..color = color.withValues(alpha: 0.9));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant KuteChartSignalsPainter old) =>
      !identical(old.signals, signals) ||
      old.repaintKey != repaintKey ||
      old.palette != palette;
}

/// Which of the date names along the foot of the plot are written, as
/// indices into [labels]: taken from the right (the latest date first),
/// a name that would run into one already kept is left out.
List<int> signalDateLabelsKept(
  List<({double left, double width})> labels, {
  double gap = 4,
}) {
  final order = [for (var i = 0; i < labels.length; i++) i]
    ..sort((a, b) => labels[b].left.compareTo(labels[a].left));
  final kept = <int>[];
  double? nextLeft;
  for (final i in order) {
    if (nextLeft != null && labels[i].left + labels[i].width + gap > nextLeft) {
      continue;
    }
    kept.add(i);
    nextLeft = labels[i].left;
  }
  return kept;
}

/// The tappable tag containing [pos], topmost first, or null.
ChartSignalHit? kuteHitTestSignalTags(List<ChartSignalHit> hits, Offset pos,
    {double tolerance = 8}) {
  for (var i = hits.length - 1; i >= 0; i--) {
    if (hits[i].rect.inflate(tolerance).contains(pos)) return hits[i];
  }
  return null;
}
