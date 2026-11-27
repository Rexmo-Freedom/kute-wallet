/// Web: the colour Safari paints behind its own bars (founder, 27 November
/// 2026, on an iPhone: "red does not go full down": the No slip's red
/// stopped above Safari's bottom toolbar, a white strip under it).
///
/// What Safari (iOS 26 and later) does, measured in the simulator: the page
/// is drawn between the status bar and the floating toolbar only (a fixed
/// element taller than that, 100lvh included, is cut there), and the two
/// bands are painted in one solid colour each: a full-width fixed element
/// touching that edge lends its CSS background colour (not its pixels, so
/// never the canvas's), else the page's background. Flutter's view is a
/// transparent element over a canvas, so both bands showed the page's
/// white (or the system's black, whatever the app's own theme).
///
/// So the app tells the page, after the frames that change them, the
/// colour at its top and bottom edges: the body's background (the bottom
/// band) and a strip behind the view at the top (`#kute-edge-top`,
/// web/index.html). A sheet's colour then runs under the toolbar, the
/// app's background under it on a page. Nothing moves and nothing is
/// drawn over the app; desktop browsers have no such bands and show none
/// of it. The phones never call this.
library;

import 'dart:async';
import 'dart:ui' show Color, FlutterView;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart' show Theme;
import 'package:kute/screens/shared/kute_bar_context.dart'
    show KuteBarRouteObserver;
import 'package:flutter/widgets.dart';

import 'web_edge_colors_native.dart'
    if (dart.library.js_interop) 'web_edge_colors_web.dart' as impl;

/// The colour drawn at [position] in [view], read off what paints there:
/// the topmost opaque box (a decoration's colour, a Material's), with any
/// translucent layer over it (a sheet's dimming barrier) blended on;
/// [fallback] where nothing opaque is found (a plain coloured box, whose
/// colour the framework keeps private, is the app's background).
///
/// [dim] is the dimming of a sheet on top, whose barrier paints through a
/// box that keeps its colour private: blended over [fallback] when
/// nothing opaque is found (the band beside a sheet's top).
@visibleForTesting
Color webEdgeColorAt(FlutterView view, Offset position, Color fallback,
    {bool top = false, Color? dim}) {
  final result = HitTestResult();
  RendererBinding.instance.hitTestInView(result, position, view.viewId);
  final over = <Color>[];
  Color? base;
  for (final entry in result.path) {
    final target = entry.target;
    Color? c;
    if (target is RenderDecoratedBox) {
      final d = target.decoration;
      if (d is BoxDecoration) {
        c = d.color ??
            (d.gradient == null
                ? null
                : (top ? d.gradient!.colors.first : d.gradient!.colors.last));
      } else if (d is ShapeDecoration) {
        c = d.color;
      }
    } else if (target is RenderPhysicalModel) {
      c = target.color;
    } else if (target is RenderPhysicalShape) {
      c = target.color;
    }
    if (c == null || c.a == 0) continue;
    if (c.a >= 0.999) {
      base = c;
      break;
    }
    over.add(c);
  }
  var color = base ?? fallback;
  if (base == null && dim != null) color = Color.alphaBlend(dim, color);
  for (final layer in over.reversed) {
    color = Color.alphaBlend(layer, color);
  }
  return color.withValues(alpha: 1);
}

/// Keeps the page's top and bottom band colours in step with the app (see
/// the library comment). Web only; a no-op elsewhere.
class WebEdgeColors extends StatefulWidget {
  const WebEdgeColors({super.key, required this.child});

  final Widget child;

  @override
  State<WebEdgeColors> createState() => _WebEdgeColorsState();
}

class _WebEdgeColorsState extends State<WebEdgeColors> {
  Timer? _timer;
  bool _dirty = true;
  Color? _top;
  Color? _bottom;
  static bool _hooked = false;
  static _WebEdgeColorsState? _current;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) return;
    _current = this;
    if (!_hooked) {
      _hooked = true;
      // Every drawn frame marks the colours stale; they are read at most
      // five times a second, and not at all while nothing is drawn.
      SchedulerBinding.instance
          .addPersistentFrameCallback((_) => _current?._dirty = true);
    }
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (identical(_current, this)) _current = null;
    super.dispose();
  }

  void _tick() {
    if (!_dirty || !mounted) return;
    if (SchedulerBinding.instance.schedulerPhase != SchedulerPhase.idle) return;
    _dirty = false;
    final view = View.maybeOf(context);
    if (view == null) return;
    final size = view.physicalSize / view.devicePixelRatio;
    if (size.isEmpty) return;
    final fallback = Theme.of(context).scaffoldBackgroundColor;
    // Off the centre line, where the floating bar sits.
    final sheet = KuteBarRouteObserver.sheetOnTop();
    final dim = sheet is ModalRoute ? sheet.barrierColor : null;
    final top = webEdgeColorAt(view, const Offset(2, 1), fallback,
        top: true, dim: dim);
    final bottom =
        webEdgeColorAt(view, Offset(2, size.height - 1), fallback);
    if (top != _top || bottom != _bottom) {
      _top = top;
      _bottom = bottom;
      impl.setEdgeColors(top: _css(top), bottom: _css(bottom));
    }
  }

  static String _css(Color c) {
    int byte(double v) => (v * 255).round().clamp(0, 255);
    return 'rgb(${byte(c.r)}, ${byte(c.g)}, ${byte(c.b)})';
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
