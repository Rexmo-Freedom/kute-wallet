// lib/screens/shared/charts/kute_chart_viewport.dart
//
// Zoom and pan for the charts drawn over a series spaced by index (the
// balance, valuation, price and P&L charts), with the gestures of the
// venue charts (MarketChart, HlCandlestickChart):
//
//   * two fingers pinch to zoom, anchored to the newest point while the
//     window reaches it, or (with [KuteChartGestures.zoomAroundFingers])
//     around the point under the fingers, which stays under them; sliding
//     both fingers pans. Each move is worked out from where the pinch
//     began, never compounded frame on frame, so nothing drifts; a finger
//     lifted or added starts a fresh pinch from the window on screen.
//     Two fingers down claim the touch, so the page around the chart
//     never scrolls under a pinch;
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
// series change resets it. A host can open on less than the whole series
// ([KuteIndexViewport.defaultSpan], ending on the newest point) and set
// how close a pinch gets ([KuteIndexViewport.minSpan]).

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
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
/// default view: [defaultSpan] (the whole series when null), ending on
/// its newest point.
class KuteIndexViewport {
  double? _span;
  double? _end;

  /// The span the window opens on, ending on the newest point; null opens
  /// on the whole series. Read while [isDefault], so a host can move it
  /// (data landing late) until the first pinch or pan.
  double? defaultSpan;

  /// The smallest span a pinch can reach; null uses [minSpanFor].
  double? minSpan;

  bool get isDefault => _span == null && _end == null;

  void reset() {
    _span = null;
    _end = null;
  }

  /// The smallest span a pinch can reach over [extent]: six points, or a
  /// fiftieth of a long series, never more than the whole.
  static double minSpanFor(double extent) =>
      math.min(extent, math.max(6.0, extent / 50));

  /// The smallest span over [extent] for this viewport: [minSpan] when
  /// set, never more than the whole.
  double minSpanOf(double extent) {
    final m = minSpan;
    if (m == null || !(m > 0)) return minSpanFor(extent);
    return math.min(extent, m);
  }

  KuteIndexWindow windowFor(double extent) {
    if (!(extent > 0)) return const KuteIndexWindow(0, 0);
    final minSpan = minSpanOf(extent);
    final span =
        (_span ?? defaultSpan ?? extent).clamp(minSpan, extent).toDouble();
    final end = (_end ?? extent).clamp(span, extent).toDouble();
    return KuteIndexWindow(end - span, end);
  }

  bool zoomedIn(double extent) => windowFor(extent).span < extent - 1e-9;

  /// Applies a new [span] and [end]; true when the window moved. A window
  /// that reaches the newest point keeps following it, and one zoomed out
  /// to the whole series stays whole as the series grows.
  bool setView(double span, double end, double extent) {
    if (!(extent > 0) || !span.isFinite || !end.isFinite) return false;
    final before = windowFor(extent);
    final s = span.clamp(minSpanOf(extent), extent).toDouble();
    final e = end.clamp(s, extent).toDouble();
    final whole = s >= extent - 1e-9;
    // Without a default span the whole series is the default view.
    _span = whole ? (defaultSpan == null ? null : double.infinity) : s;
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
    this.zoomAroundFingers = false,
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

  /// A pinch keeps the point under the fingers under them (a photo's
  /// zoom). Off, a pinch is anchored to the newest point while the window
  /// reaches it, as the venue charts do.
  final bool zoomAroundFingers;

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

  /// The two fingers the pinch follows, and where it began: the window
  /// then, the fingers' distance and their midpoint.
  (int, int)? _pinchPair;
  double _pinchStartDistance = 0;
  double _pinchStartFocalX = 0;
  KuteIndexWindow? _pinchStart;
  KuteIndexWindow? _panStart;
  double _panStartX = 0;
  double _width = 0;

  bool get _canZoom =>
      widget.zoomable &&
      widget.viewport.minSpanOf(widget.extent) < widget.extent;

  /// Starts (or restarts) the pinch from the window on screen with the
  /// first two fingers down.
  void _beginPinch() {
    final ids = _pointers.keys.take(2).toList();
    final p0 = _pointers[ids[0]]!, p1 = _pointers[ids[1]]!;
    _pinching = true;
    _panStart = null;
    _pinchPair = (ids[0], ids[1]);
    _pinchStartDistance = (p0 - p1).distance;
    _pinchStartFocalX = (p0.dx + p1.dx) / 2;
    _pinchStart = widget.viewport.windowFor(widget.extent);
  }

  void _onPointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
    // A third finger changes nothing; a second one (again) pinches.
    if (_pointers.length >= 2 && _pinchPair == null && _canZoom) {
      _beginPinch();
      widget.onScrubEnd?.call();
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;
    final start = _pinchStart;
    final pair = _pinchPair;
    if (!_pinching || pair == null || start == null || _width <= 0) return;
    if (_pinchStartDistance <= 0 || start.span <= 0) return;
    final p0 = _pointers[pair.$1], p1 = _pointers[pair.$2];
    if (p0 == null || p1 == null) return;
    final distance = (p0 - p1).distance;
    final focalX = (p0.dx + p1.dx) / 2;
    // Fingers apart → a shorter span (zoom in); together → longer.
    final scale = (distance / _pinchStartDistance).clamp(0.05, 20.0);
    final extent = widget.extent;
    final double span;
    final double end;
    if (widget.zoomAroundFingers) {
      span = (start.span / scale)
          .clamp(widget.viewport.minSpanOf(extent), extent)
          .toDouble();
      // The point that was under the fingers when the pinch began stays
      // under them; sliding both fingers carries it along (a pan).
      final anchor = start.indexAt(_pinchStartFocalX, _width);
      end = anchor + (1 - focalX / _width) * span;
    } else {
      span = start.span / scale;
      // Sliding both fingers pans the window.
      end = start.end - (focalX - _pinchStartFocalX) / _width * span;
    }
    if (widget.viewport.setView(span, end, extent)) {
      widget.onViewChanged();
    }
  }

  void _onPointerUp(int pointer) {
    _pointers.remove(pointer);
    final pair = _pinchPair;
    if (pair != null && (pair.$1 == pointer || pair.$2 == pointer)) {
      // One of the pinching fingers left: two still down pinch afresh
      // from the window on screen (never from stale finger positions);
      // otherwise the pinch waits for a second finger.
      _pinchPair = null;
      _pinchStart = null;
      if (_pointers.length >= 2 && _canZoom) _beginPinch();
    }
    if (_pointers.isEmpty && _pinching) {
      _pinching = false;
      _pinchPair = null;
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
        child: RawGestureDetector(
          gestures: {
            _KutePinchClaim:
                GestureRecognizerFactoryWithHandlers<_KutePinchClaim>(
              () => _KutePinchClaim(debugOwner: this),
              (r) => r.canClaim = () => _canZoom,
            ),
          },
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
                    if (widget.viewport.setView(
                        start.span, start.end - shift, widget.extent)) {
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
            onLongPressEnd:
                scrub == null ? null : (_) => widget.onScrubEnd?.call(),
            onLongPressCancel: scrub == null ? null : widget.onScrubEnd,
            child: widget.child,
          ),
        ),
      );
    });
  }
}

/// Claims a touch on the chart once a second finger is down on it, so the
/// page or sheet around the chart cannot win the first finger mid-pinch
/// and scroll under it. One finger is never claimed: it steps aside
/// before it lifts, so a tap, a drag or a scroll goes where it would
/// have gone. The pinch itself is read off the raw pointers.
class _KutePinchClaim extends OneSequenceGestureRecognizer {
  _KutePinchClaim({super.debugOwner});

  bool Function() canClaim = () => false;
  final Set<int> _down = {};
  bool _claimed = false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _down.add(event.pointer);
    if (!_claimed && _down.length >= 2 && canClaim()) {
      _claimed = true;
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      // Unclaimed, step aside before the arena sweeps, so a lone tap is
      // never taken from whatever sits around the chart.
      if (!_claimed) resolve(GestureDisposition.rejected);
      _down.remove(event.pointer);
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _down.clear();
    _claimed = false;
  }

  @override
  String get debugDescription => 'kute pinch claim';
}
