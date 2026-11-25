// lib/models/chart_drawing.dart
//
// User-drawn chart annotations (the "Advanced" drawing tools on the
// Hyperliquid market detail chart): trendlines, horizontal levels, rays
// and rectangles. Every anchor point is stored in CHART coordinates —
// a (timestamp ms, price) pair — never in pixels, so a drawing survives
// timeframe switches, live ticks and re-layouts and always lands on the
// same market moment. Serialized as plain JSON maps (no Hive codegen);
// persisted per market coin by ChartDrawingsNotifier.
//
// ───────────────────────── How to add a drawing tool ─────────────────────────
//
// This file owns the tool list ([ChartDrawingTool]) and each tool's spec
// ([chartDrawingSpec]: how many anchors, how many the person taps, the
// anchors derived from the taps). Placement is generic
// (hl_drawing_placement.dart): a tool never needs gesture code of its own.
//
//  1. Here: an enum value, and its case in [chartDrawingSpec]. A tool the
//     person places point by point is `ChartDrawingSpec(points: n)`; one
//     with anchors it derives (a position's stop) sets `taps` below
//     `points` and a `derive`; a free-form one (a path) is
//     `ChartDrawingSpec.openEnded(min, max)` and finishes when the last
//     point is tapped again. The hint "Point k of n" comes for free.
//  2. Its painter and its hit test: a case in KuteChartDrawingsPainter's
//     switch and in kuteDrawingHit (kute_chart_drawings.dart); its bounds
//     in kuteDrawingBounds when not its anchors' box. The compiler lists
//     every switch that needs the new case.
//  3. Its place on the rail: its group and name in hl_drawing_rail.dart
//     (kHlToolGroups, hlToolName) and its glyph in hl_drawing_tools.dart
//     (HlRailGlyph, hlGlyphForTool).
//  4. Its name (and any label it paints) in every lib/l10n/app_*.arb, with
//     a translator description in app_en.arb; then `flutter gen-l10n`.
//  5. Tests: a round trip (test/models/chart_drawing_test.dart), its hit
//     and paint (chart_drawing_tools_test.dart), its placement
//     (hl_drawing_placement_test.dart).
//
// Analytics need nothing new: drawing_created / drawing_edited already
// carry the tool's name as `type`.

import 'package:flutter/foundation.dart' show visibleForTesting;
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

  /// One anchor; a price line (models/hl_price_line.dart). Only what the
  /// rail places and the chart paints: a line is stored with the price
  /// lines, never among the saved drawings.
  priceLine,
}

/// How a tool is placed and how many anchors it keeps.
class ChartDrawingSpec {
  /// [points] anchors, the first [taps] (all of them by default) placed by
  /// the person, one tap (or the end of one drag) each; [derive] fills the
  /// rest from them.
  const ChartDrawingSpec({required this.points, int? taps, this.derive})
      : taps = taps ?? points,
        openEnded = false,
        maxPoints = points;

  /// A free-form tool: point after point, at least [min] and at most
  /// [max]; tapping the last point again (a double tap) finishes it.
  const ChartDrawingSpec.openEnded(int min, int max)
      : points = min,
        taps = min,
        maxPoints = max,
        openEnded = true,
        derive = null;

  /// The anchors a stored drawing has (the least, for [openEnded]).
  final int points;

  /// The anchors the person places; the rest come from [derive].
  final int taps;

  /// Placed until finished rather than at a fixed count.
  final bool openEnded;

  /// The most anchors an [openEnded] tool takes.
  final int maxPoints;

  /// Fills the anchors after the first [placed] (the ones the person put
  /// down; the rest are copies of the last) for the preview while placing
  /// and for the drawing that lands. Pure chart coordinates, no pixels.
  final ChartDrawing Function(ChartDrawing draft, int placed)? derive;
}

/// Tests may give a tool another spec (a three-point tool, say) to drive
/// the generic placement; null in the app.
@visibleForTesting
ChartDrawingSpec? Function(ChartDrawingTool tool)? debugChartDrawingSpecOverride;

/// Each tool's spec. See "How to add a drawing tool" at the top.
ChartDrawingSpec chartDrawingSpec(ChartDrawingTool tool) {
  final override = debugChartDrawingSpecOverride?.call(tool);
  if (override != null) return override;
  switch (tool) {
    case ChartDrawingTool.level:
    case ChartDrawingTool.text:
    case ChartDrawingTool.horizontalRay:
    case ChartDrawingTool.verticalLine:
    case ChartDrawingTool.priceLine:
      return const ChartDrawingSpec(points: 1);
    case ChartDrawingTool.parallelChannel:
      // Base start, base end, then where the parallel rail runs.
      return const ChartDrawingSpec(points: 3, derive: _channelRail);
    case ChartDrawingTool.longPosition:
    case ChartDrawingTool.shortPosition:
      // Entry and target; the stop starts at 1:1 and has its handle.
      return const ChartDrawingSpec(points: 3, taps: 2, derive: _positionStop);
    case ChartDrawingTool.trendline:
    case ChartDrawingTool.ray:
    case ChartDrawingTool.rect:
    case ChartDrawingTool.fibonacci:
    case ChartDrawingTool.extendedLine:
    case ChartDrawingTool.priceRange:
    case ChartDrawingTool.dateRange:
    case ChartDrawingTool.dateAndPriceRange:
      return const ChartDrawingSpec(points: 2);
  }
}

/// How many anchors a tool needs to be valid.
int chartDrawingPointCount(ChartDrawingTool tool) =>
    chartDrawingSpec(tool).points;

/// A channel's parallel rail before its third point is down: below the
/// base by about a third of the base's own move (1% of price on a flat
/// base), so the preview reads as a channel at once.
ChartDrawing _channelRail(ChartDrawing draft, int placed) {
  if (placed != 2 || draft.points.length < 3) return draft;
  final a = draft.points[0], b = draft.points[1];
  final move = (b.price - a.price).abs();
  final offset = move > 0 ? move * 0.35 : a.price * 0.01;
  return draft.withPoint(
      2, ChartDrawingPoint(timeMs: b.timeMs, price: b.price - offset));
}

/// A position's stop: the target mirrored through the entry (1:1).
ChartDrawing _positionStop(ChartDrawing draft, int placed) {
  if (placed < 2 || draft.points.length < 3) return draft;
  final a = draft.points[0], b = draft.points[1];
  final stop = a.price - (b.price - a.price);
  return draft.withPoint(
      2,
      ChartDrawingPoint(
          timeMs: a.timeMs, price: stop > 0 ? stop : a.price * 0.5));
}

/// The tool stored under [name], or null when this build does not know
/// it (a newer build's tool). Never a guess: a stored drawing whose tool
/// is unknown is kept as it was and skipped (ChartDrawingsNotifier writes
/// its raw JSON back unchanged), so an older build can never rewrite a
/// newer tool as a trend line.
ChartDrawingTool? chartDrawingToolFromName(Object? name) {
  for (final t in ChartDrawingTool.values) {
    if (t.name == name) return t;
  }
  return null;
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
/// (marketUp / marketDown / warning / blue); null means the neutral
/// default, resolved from the live theme at paint time so a theme change
/// re-skins old drawings too.
///
/// [dashed], [locked] and [extend] came later: absent in older records,
/// they read as false, and are only written when on.
///
/// Forward compatibility: keys this build does not know (a newer build's
/// settings) are kept in [extra] and written back as they were.
class ChartDrawing {
  final String id;
  final ChartDrawingTool tool;
  final List<ChartDrawingPoint> points;
  final int? colorValue;
  final String? text;

  /// Stroke drawn dashed instead of solid.
  final bool dashed;

  /// Locked against moving: no handles, no body drag. Still selectable
  /// (to unlock, recolour or delete it).
  final bool locked;

  /// A trend line carried on past its later point to the right edge.
  final bool extend;

  /// Stored keys this build does not read, written back unchanged.
  final Map<String, Object?> extra;

  const ChartDrawing({
    required this.id,
    required this.tool,
    required this.points,
    this.colorValue,
    this.text,
    this.dashed = false,
    this.locked = false,
    this.extend = false,
    this.extra = const {},
  });

  /// The keys [toJson] writes itself; anything else read is [extra].
  static const Set<String> _ownKeys = {
    'id',
    'tool',
    'points',
    'color',
    'text',
    'dash',
    'lock',
    'ext',
  };

  /// The picked color, or null for "use the theme neutral".
  Color? get color => colorValue == null ? null : Color(colorValue!);

  ChartDrawing copyWith({
    String? id,
    List<ChartDrawingPoint>? points,
    int? colorValue,
    bool clearColor = false,
    String? text,
    bool? dashed,
    bool? locked,
    bool? extend,
  }) =>
      ChartDrawing(
        id: id ?? this.id,
        tool: tool,
        points: points ?? this.points,
        colorValue: clearColor ? null : (colorValue ?? this.colorValue),
        text: text ?? this.text,
        dashed: dashed ?? this.dashed,
        locked: locked ?? this.locked,
        extend: extend ?? this.extend,
        extra: extra,
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
        if (dashed) 'dash': true,
        if (locked) 'lock': true,
        if (extend) 'ext': true,
        for (final e in extra.entries)
          if (!_ownKeys.contains(e.key)) e.key: e.value,
      };

  /// Throws a [FormatException] for a tool this build does not know
  /// ([chartDrawingToolFromName]); the store keeps such entries raw.
  factory ChartDrawing.fromJson(Map<String, dynamic> json) => ChartDrawing(
        id: json['id'] as String? ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        tool: chartDrawingToolFromName(json['tool']) ??
            (throw FormatException('unknown drawing tool', json['tool'])),
        points: [
          for (final p in (json['points'] as List? ?? const []))
            if (p is Map)
              ChartDrawingPoint.fromJson(Map<String, dynamic>.from(p)),
        ],
        colorValue: (json['color'] as num?)?.toInt(),
        text: json['text'] is String ? json['text'] as String : null,
        dashed: json['dash'] == true,
        locked: json['lock'] == true,
        extend: json['ext'] == true,
        extra: {
          for (final e in json.entries)
            if (!_ownKeys.contains(e.key)) e.key: e.value,
        },
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
