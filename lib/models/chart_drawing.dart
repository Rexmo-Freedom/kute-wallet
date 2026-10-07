// lib/models/chart_drawing.dart
//
// User-drawn chart annotations (the "Advanced" drawing tools on the
// Hyperliquid market detail chart): trendlines, horizontal levels, rays
// and rectangles. Every anchor point is stored in CHART coordinates —
// a (timestamp ms, price) pair — never in pixels, so a drawing survives
// timeframe switches, live ticks and re-layouts and always lands on the
// same market moment. Serialized as plain JSON maps (no Hive codegen);
// persisted per market coin by ChartDrawingsNotifier.

import 'package:flutter/material.dart' show Color;

/// The v1 drawing tools.
enum ChartDrawingTool {
  /// Two anchor points, a straight segment between them.
  trendline,

  /// One anchor (price matters, time only positions the handle);
  /// rendered as a full-width horizontal line.
  level,

  /// Two anchor points; the segment extends past the second point to the
  /// right edge of the chart.
  ray,

  /// Two opposite corner points, rendered as a stroked + faintly filled
  /// rectangle.
  rect,

  /// Two anchors with the standard retracement levels between them.
  fibonacci,

  /// A local note attached to one chart coordinate.
  text,

  /// One anchor; a horizontal line from the anchor to the right edge.
  horizontalRay,

  /// One anchor; a full-height vertical line at the anchor's time.
  verticalLine,

  /// Two anchors; the line through both, extended to both edges.
  extendedLine,

  /// Three anchors: a base segment a→b and a third point that sets the
  /// parallel line's offset. The band between is faintly filled.
  parallelChannel,

  /// Three anchors: entry (time + price), target (end time + price) and
  /// stop (price). Profit zone above entry for a long, below for a short.
  longPosition,
  shortPosition,

  /// Two anchors; brackets the price difference between them.
  priceRange,

  /// Two anchors; brackets the time between them (bars and duration).
  dateRange,

  /// Two anchors; a box measuring both price and time.
  dateAndPriceRange,
}

/// How many anchors a tool needs to be valid.
int chartDrawingPointCount(ChartDrawingTool tool) {
  switch (tool) {
    case ChartDrawingTool.level:
    case ChartDrawingTool.text:
    case ChartDrawingTool.horizontalRay:
    case ChartDrawingTool.verticalLine:
      return 1;
    case ChartDrawingTool.parallelChannel:
    case ChartDrawingTool.longPosition:
    case ChartDrawingTool.shortPosition:
      return 3;
    case ChartDrawingTool.trendline:
    case ChartDrawingTool.ray:
    case ChartDrawingTool.rect:
    case ChartDrawingTool.fibonacci:
    case ChartDrawingTool.extendedLine:
    case ChartDrawingTool.priceRange:
    case ChartDrawingTool.dateRange:
    case ChartDrawingTool.dateAndPriceRange:
      return 2;
  }
}

ChartDrawingTool _toolFromName(String? name) {
  for (final t in ChartDrawingTool.values) {
    if (t.name == name) return t;
  }
  return ChartDrawingTool.trendline;
}

/// One anchor: a market moment (epoch ms) at a price.
class ChartDrawingPoint {
  final int timeMs;
  final double price;

  const ChartDrawingPoint({required this.timeMs, required this.price});

  Map<String, dynamic> toJson() => {'t': timeMs, 'p': price};

  factory ChartDrawingPoint.fromJson(Map<String, dynamic> json) =>
      ChartDrawingPoint(
        timeMs: (json['t'] as num?)?.toInt() ?? 0,
        price: (json['p'] as num?)?.toDouble() ?? 0,
      );
}

/// One saved drawing. [colorValue] is the ARGB of a user-picked accent
/// (marketUp / marketDown / warning); null means the neutral default,
/// resolved from the live theme at paint time so a theme change re-skins
/// old drawings too.
class ChartDrawing {
  final String id;
  final ChartDrawingTool tool;
  final List<ChartDrawingPoint> points;
  final int? colorValue;
  final String? text;

  const ChartDrawing({
    required this.id,
    required this.tool,
    required this.points,
    this.colorValue,
    this.text,
  });

  /// The picked color, or null for "use the theme neutral".
  Color? get color => colorValue == null ? null : Color(colorValue!);

  ChartDrawing copyWith({
    List<ChartDrawingPoint>? points,
    int? colorValue,
    bool clearColor = false,
    String? text,
  }) =>
      ChartDrawing(
        id: id,
        tool: tool,
        points: points ?? this.points,
        colorValue: clearColor ? null : (colorValue ?? this.colorValue),
        text: text ?? this.text,
      );

  /// Replace one anchor point (handle drag).
  ChartDrawing withPoint(int index, ChartDrawingPoint point) {
    if (index < 0 || index >= points.length) return this;
    final next = List<ChartDrawingPoint>.of(points);
    next[index] = point;
    return copyWith(points: next);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'tool': tool.name,
        'points': [for (final p in points) p.toJson()],
        if (colorValue != null) 'color': colorValue,
        if (text != null) 'text': text,
      };

  factory ChartDrawing.fromJson(Map<String, dynamic> json) => ChartDrawing(
        id: json['id'] as String? ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        tool: _toolFromName(json['tool'] as String?),
        points: [
          for (final p in (json['points'] as List? ?? const []))
            if (p is Map)
              ChartDrawingPoint.fromJson(Map<String, dynamic>.from(p)),
        ],
        colorValue: (json['color'] as num?)?.toInt(),
        text: json['text'] is String ? json['text'] as String : null,
      );

  /// Structurally usable — enough points for its tool and a real price on
  /// each. Corrupt persisted entries are dropped on load.
  bool get isValid {
    final need = chartDrawingPointCount(tool);
    if (tool == ChartDrawingTool.text &&
        (text == null || text!.trim().isEmpty || text!.length > 4096)) {
      return false;
    }
    if (points.length < need) return false;
    for (final p in points) {
      if (!p.price.isFinite || p.price <= 0) return false;
    }
    return true;
  }
}
