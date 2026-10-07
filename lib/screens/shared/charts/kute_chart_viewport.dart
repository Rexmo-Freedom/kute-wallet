// lib/screens/shared/charts/kute_chart_viewport.dart
//
// Zoom and pan for the charts drawn over a series spaced by index (the
// balance, valuation, price and P&L charts), with the gestures of the
// venue charts (MarketChart, HlCandlestickChart):
//
//   * two fingers pinch to zoom, anchored to the newest point while the
//     window reaches it; sliding both fingers pans;
//   * one finger dragging sideways pans the window once it is zoomed in
//     (at the whole range there is nowhere to go, so the drag is left to
//     whatever scrolls around the chart);
//   * a long press (then slide) is the scrub crosshair, so a drag and a
//     pinch never fight it.
//
// The window lives in index units over [0, extent]: extent is the last
// index of a line (points sit on their index) or the bar count of a candle
// chart (bars fill their slot). The host keeps a [KuteIndexViewport],
// reads its [KuteIndexWindow] in build and paints through it; a range or
// series change resets it.

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The part of the series on screen, in index units.
@immutable
class KuteIndexWindow {
  final double start;
  final double end;

  const KuteIndexWindow(this.start, this.end);

  double get span => end - start;

  /// Index [i] → x inside a plot [width] px wide.
  double xOf(double i, double width) =>
      span > 0 ? (i - start) / span * width : width;

  /// x inside a plot [width] px wide → (fractional) index.
  double indexAt(double x, double width) =>
      width > 0 ? start + x / width * span : end;

  @override
  bool operator ==(Object other) =>
      other is KuteIndexWindow && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// The user's zoom and pan over one series. Null span and end are the
/// default view: the whole series, ending on its newest point.
class KuteIndexViewport {
  double? _span;
  double? _end;

  bool get isDefault => _span == null && _end == null;

  void reset() {
    _span = null;
    _end = null;
  }

  /// The smallest span a pinch can reach over [extent]: six points, or a
  /// fiftieth of a long series, never more than the whole.
  static double minSpanFor(double extent) =>
      math.min(extent, math.max(6.0, extent / 50));

  KuteIndexWindow windowFor(double extent) {
    if (extent <= 0) return const KuteIndexWindow(0, 0);
    final minSpan = minSpanFor(extent);
    final span = (_span ?? extent).clamp(minSpan, extent).toDouble();
    final end = (_end ?? extent).clamp(span, extent).toDouble();
    return KuteIndexWindow(end - span, end);
  }

  bool zoomedIn(double extent) => windowFor(extent).span < extent - 1e-9;

  /// Applies a new [span] and [end]; true when the window moved. A window
  /// that reaches the newest point keeps following it.
  bool setView(double span, double end, double extent) {
    if (extent <= 0) return false;
    final before = windowFor(extent);
    final s = span.clamp(minSpanFor(extent), extent).toDouble();
    final e = end.clamp(s, extent).toDouble();
    _span = s >= extent - 1e-9 ? null : s;
    _end = e >= extent - 1e-9 ? null : e;
    return windowFor(extent) != before;
  }
}

/// The venue charts' gestures over a [KuteIndexViewport]: pinch to zoom,
/// drag to pan once zoomed, long press (then slide) to scrub.
class KuteChartGestures extends StatefulWidget {
  const KuteChartGestures({
    super.key,
    required this.viewport,
    required this.extent,
    required this.onViewChanged,
    required this.child,
    this.zoomable = true,
    this.onScrub,
    this.onScrubEnd,
  });

  final KuteIndexViewport viewport;

  /// The series' extent in index units (see the file comment).
  final double extent;

  /// The window moved: the host rebuilds its plot.
  final VoidCallback onViewChanged;

  /// Off, the chart only scrubs.
  final bool zoomable;

  /// The finger at [dx] in a plot [width] px wide, while scrubbing.
  final void Function(double dx, double width)? onScrub;
  final VoidCallback? onScrubEnd;

  final Widget child;

  @override
  State<KuteChartGestures> createState() => _KuteChartGesturesState();
}

class _KuteChartGesturesState extends State<KuteChartGestures> {
  final Map<int, Offset> _pointers = {};
  bool _pinching = false;
  double _pinchStartDistance = 0;
  double _pinchStartFocalX = 0;
  KuteIndexWindow? _pinchStart;
  KuteIndexWindow? _panStart;
  double _panStartX = 0;
  double _width = 0;

  bool get _canZoom =>
      widget.zoomable &&
      KuteIndexViewport.minSpanFor(widget.extent) < widget.extent;

  void _onPointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 2 && _canZoom) {
      final p = _pointers.values.toList();
      _pinching = true;
      _panStart = null;
      _pinchStartDistance = (p[0] - p[1]).distance;
      _pinchStartFocalX = (p[0].dx + p[1].dx) / 2;
      _pinchStart = widget.viewport.windowFor(widget.extent);
      widget.onScrubEnd?.call();
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;
    final start = _pinchStart;
    if (!_pinching || _pointers.length < 2 || start == null || _width <= 0) {
      return;
    }
    if (_pinchStartDistance <= 0 || start.span <= 0) return;
    final p = _pointers.values.take(2).toList();
    final distance = (p[0] - p[1]).distance;
    final focalX = (p[0].dx + p[1].dx) / 2;
    // Fingers apart → a shorter span (zoom in); together → longer.
    final scale = (distance / _pinchStartDistance).clamp(0.05, 20.0);
    final span = start.span / scale;
    // Sliding both fingers pans the window.
    final pan = (focalX - _pinchStartFocalX) / _width * span;
    if (widget.viewport.setView(span, start.end - pan, widget.extent)) {
      widget.onViewChanged();
    }
  }

  void _onPointerUp(int pointer) {
    _pointers.remove(pointer);
    if (_pointers.isEmpty && _pinching) {
      _pinching = false;
      _pinchStart = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final zoomed = _canZoom && widget.viewport.zoomedIn(widget.extent);
    final scrub = widget.onScrub;
    return LayoutBuilder(builder: (context, constraints) {
      _width = constraints.maxWidth;
      final w = _width;
      return Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: (e) => _onPointerUp(e.pointer),
        onPointerCancel: (e) => _onPointerUp(e.pointer),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Panning only exists once zoomed in; at the whole range a
          // sideways drag is left to whatever scrolls around the chart.
          onHorizontalDragStart: !zoomed
              ? null
              : (d) {
                  if (_pinching) return;
                  _panStart = widget.viewport.windowFor(widget.extent);
                  _panStartX = d.localPosition.dx;
                },
          onHorizontalDragUpdate: !zoomed
              ? null
              : (d) {
                  final start = _panStart;
                  if (_pinching || start == null || w <= 0) return;
                  // Dragging right walks back in time.
                  final shift =
                      (d.localPosition.dx - _panStartX) / w * start.span;
                  if (widget.viewport
                      .setView(start.span, start.end - shift, widget.extent)) {
                    widget.onViewChanged();
                  }
                },
          onHorizontalDragEnd: !zoomed ? null : (_) => _panStart = null,
          onHorizontalDragCancel: !zoomed ? null : () => _panStart = null,
          onLongPressStart: scrub == null
              ? null
              : (d) {
                  if (_pinching) return;
                  scrub(d.localPosition.dx, w);
                },
          onLongPressMoveUpdate: scrub == null
              ? null
              : (d) {
                  if (_pinching) return;
                  scrub(d.localPosition.dx, w);
                },
          onLongPressEnd: scrub == null ? null : (_) => widget.onScrubEnd?.call(),
          onLongPressCancel: scrub == null ? null : widget.onScrubEnd,
          child: widget.child,
        ),
      );
    });
  }
}
