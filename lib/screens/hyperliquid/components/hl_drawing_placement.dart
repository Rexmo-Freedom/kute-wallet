// lib/screens/hyperliquid/components/hl_drawing_placement.dart
//
// The Advanced chart's placement state machine: how taps and drags put a
// new drawing's anchors down, for every tool, from its spec alone
// (chartDrawingSpec in models/chart_drawing.dart). No tool has gesture
// code of its own; a tool with any number of anchors places here.
//
//   idle ──tap──▶ placed 1 ──tap──▶ placed 2 … ──last tap──▶ done
//     │              │
//     └──drag──▶ the next anchor follows the finger; lifting places it
//
// - A tap puts the next anchor down. A tap on the anchor just placed
//   (closer than [HlDrawingPlacement.nearPx]) adds nothing; on a
//   free-form tool it finishes the drawing (a double tap).
// - A drag from idle puts the first anchor at the touch and the second
//   under the finger (one-anchor tools: the only anchor follows it). A
//   drag while anchors are down moves the next one. Lifting places it;
//   a drag that ends on the anchor before it is undone.
// - When the anchors the person places are all down (spec.taps), the
//   spec derives the rest and the drawing is done.
//
// Pure Dart over chart coordinates: the chart (hl_charts.dart) turns
// touches into points (magnet included) and passes a pixel distance for
// the "same spot" rule, then paints [preview]. Mouse input arrives as the
// same taps and drags, so a pointer-specific front end (hover preview,
// click-click on the web) can drive this class without changing it.
//
// A mouse also hovers: [hover] makes the next anchor (and the ones after
// it) follow the pointer between clicks, and shows a one-anchor tool as
// [ghost] under it before anything is placed. A finger never hovers, so
// touch placement is untouched by it.

import 'package:kute/models/chart_drawing.dart';

class HlDrawingPlacement {
  HlDrawingPlacement({
    required this.tool,
    required this.newId,
    this.colorValue,
  });

  final ChartDrawingTool tool;

  /// A fresh id for the drawing being placed.
  final String Function() newId;

  /// The armed colour (null: the theme's neutral).
  final int? colorValue;

  /// Two anchors closer than this (pixels) are the same spot.
  static const double nearPx = 8;

  ChartDrawingSpec get spec => chartDrawingSpec(tool);

  /// The anchors so far: the placed ones, then copies of the last.
  ChartDrawing? _draft;

  /// Anchors put down by a tap or a finished drag.
  int _placed = 0;

  /// The anchor under a dragging finger, or null.
  int? _live;

  /// Where a hovering mouse is, or null (a finger never hovers).
  ChartDrawingPoint? _hover;

  /// The state before the drag began (a cancelled or too-short drag goes
  /// back to it).
  (ChartDrawing?, int)? _beforeDrag;

  /// Anchors put down so far (0: nothing yet).
  int get placed => _placed;

  /// A finger is moving an anchor.
  bool get dragging => _live != null;

  /// Something is on the chart: an anchor down or a drag under way.
  bool get active => _draft != null;

  /// What to paint while placing: the anchors so far, the rest derived as
  /// the spec would, or null when nothing is down.
  ChartDrawing? get preview {
    final draft = _draft;
    if (draft == null) return null;
    final count = _live != null
        ? _live! + 1
        : _hover != null
            ? _placed + 1
            : _placed;
    return _derived(draft, count);
  }

  /// A one-anchor tool shown whole under a hovering mouse before it is
  /// placed (never saved), or null.
  ChartDrawing? get ghost {
    final at = _hover;
    if (at == null || _draft != null || spec.taps != 1 || spec.openEnded) {
      return null;
    }
    return ChartDrawing(
      id: 'hover-ghost',
      tool: tool,
      points: [for (var i = 0; i < spec.points; i++) at],
      colorValue: colorValue,
    );
  }

  /// A mouse hovers at [point]: the next anchor follows it (nothing is
  /// placed). Ignored mid-drag.
  void hover(ChartDrawingPoint point) {
    if (_live != null) return;
    _hover = point;
    final draft = _draft;
    if (draft != null) _draft = _setFrom(draft, _placed, point);
  }

  /// The mouse left (or pressed): the anchors not placed go back to the
  /// last one placed.
  void clearHover() {
    if (_hover == null) return;
    _hover = null;
    final draft = _draft;
    if (draft == null || _live != null || _placed == 0) return;
    final last = draft.points[_placed - 1];
    if (spec.openEnded) {
      final keep = _placed > spec.points ? _placed : spec.points;
      final points = List<ChartDrawingPoint>.of(draft.points);
      if (points.length > keep) points.removeRange(keep, points.length);
      if (_placed < points.length) points[_placed] = last;
      _draft = draft.copyWith(points: points);
    } else {
      _draft = _setFrom(draft, _placed, last);
    }
  }

  ChartDrawing _derived(ChartDrawing draft, int count) =>
      spec.derive?.call(draft, count) ?? draft;

  /// Every anchor from [from] on set to [point] (an open-ended draft grows
  /// to hold it).
  ChartDrawing _setFrom(ChartDrawing draft, int from, ChartDrawingPoint point) {
    final points = List<ChartDrawingPoint>.of(draft.points);
    if (spec.openEnded) {
      if (from >= points.length) {
        points.add(point);
      } else {
        points[from] = point;
      }
    } else {
      for (var i = from; i < points.length; i++) {
        points[i] = point;
      }
    }
    return draft.copyWith(points: points);
  }

  ChartDrawing _start(ChartDrawingPoint point) => ChartDrawing(
        id: newId(),
        tool: tool,
        points: [for (var i = 0; i < spec.points; i++) point],
        colorValue: colorValue,
      );

  bool get _complete =>
      spec.openEnded ? _placed >= spec.maxPoints : _placed >= spec.taps;

  /// The finished drawing (null when not valid), and back to idle.
  ChartDrawing? _finish() {
    final draft = _draft;
    final count = _placed;
    reset();
    if (draft == null) return null;
    var done = _derived(draft, count);
    if (spec.openEnded && done.points.length > count) {
      done = done.copyWith(points: done.points.sublist(0, count));
    }
    return done.isValid ? done : null;
  }

  /// Back to idle: nothing placed.
  void reset() {
    _draft = null;
    _placed = 0;
    _live = null;
    _beforeDrag = null;
    _hover = null;
  }

  /// A tap at [point]. [distance] measures two chart points in pixels.
  /// Returns the drawing when this tap finished it.
  ChartDrawing? tap(
    ChartDrawingPoint point, {
    required double Function(ChartDrawingPoint a, ChartDrawingPoint b)
        distance,
  }) {
    _live = null;
    _beforeDrag = null;
    final draft = _draft;
    if (draft == null) {
      _draft = _start(point);
      _placed = 1;
      return _complete ? _finish() : null;
    }
    if (distance(draft.points[_placed - 1], point) < nearPx) {
      // The same spot again: a free-form tool with enough anchors is
      // done (a double tap); otherwise a second tap there is no anchor.
      if (spec.openEnded && _placed >= spec.points) return _finish();
      return null;
    }
    _draft = _setFrom(draft, _placed, point);
    _placed++;
    return _complete ? _finish() : null;
  }

  /// A drag starts at [point].
  void dragStart(ChartDrawingPoint point) {
    _hover = null;
    _beforeDrag = (_draft, _placed);
    final draft = _draft;
    if (draft == null) {
      _draft = _start(point);
      // A one-anchor tool's anchor rides the finger; otherwise the first
      // anchor stays at the touch and the second follows.
      if (spec.taps == 1 && !spec.openEnded) {
        _live = 0;
      } else {
        _placed = 1;
        _live = 1;
        _draft = _setFrom(_draft!, 1, point);
      }
      return;
    }
    _live = _placed;
    _draft = _setFrom(draft, _placed, point);
  }

  /// The finger at [point] mid-drag.
  void dragUpdate(ChartDrawingPoint point) {
    final live = _live, draft = _draft;
    if (live == null || draft == null) return;
    _draft = _setFrom(draft, live, point);
  }

  /// The finger lifts. Returns the drawing when this finished it.
  ChartDrawing? dragEnd({
    required double Function(ChartDrawingPoint a, ChartDrawingPoint b)
        distance,
  }) {
    final live = _live, draft = _draft;
    if (live == null || draft == null) return null;
    if (live > 0 &&
        distance(draft.points[live - 1], draft.points[live]) < nearPx) {
      // Lifted on the anchor before: no anchor from this drag.
      cancelDrag();
      return null;
    }
    _live = null;
    _beforeDrag = null;
    _placed = live + 1;
    return _complete ? _finish() : null;
  }

  /// The drag is called off (another gesture took over): as before it.
  void cancelDrag() {
    final before = _beforeDrag;
    _live = null;
    _beforeDrag = null;
    if (before == null) return;
    _draft = before.$1;
    _placed = before.$2;
  }
}
