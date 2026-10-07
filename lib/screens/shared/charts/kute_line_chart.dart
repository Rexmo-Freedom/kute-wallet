// lib/screens/shared/charts/kute_line_chart.dart
//
// The shared, engine-idiom line/area chart WIDGET. The analytics family
// (home Price tab line view, balance history, hourly value chart, the
// affiliate earnings graph) renders through this instead of fl_chart so
// every line chart in the app shares one visual language:
//
//   * monotone cubic smoothing (kuteMonotonePath — no rubber-band
//     overshoot), 2.0 round-cap stroke, the standard 0.14 gradient fill,
//     endpoint dot;
//   * data painter behind a RepaintBoundary; the scrub crosshair rides
//     the shared KuteChartCrosshair layer (hairline + dot + the one scrub
//     card: value, change since the start of the window, date) so scrub
//     frames never re-raster the line canvas;
//   * the venue charts' gestures (KuteChartGestures): a long press (then
//     slide) scrubs, two fingers pinch to zoom, a drag pans once zoomed;
//     the y scale autoscales to the points on screen with the venue
//     charts' rule (kuteAutoScaleDomain: a tenth of the plot free above
//     and below, a flat line centred);
//   * series changes morph (~280ms resample + lerp, the trading-chart
//     pattern; Duration.zero under reduce motion) instead of hard-
//     snapping — this also covers the old fl_chart grow-in entrance,
//     which is replaced by a light one-shot fade;
//   * optional per-index event markers (the price chart's received/sent
//     transaction dots), drawn like the HL fill markers with a
//     background halo;
//   * an optional projected tail ([KuteLineChart.projectedFrom]): the
//     part of the series that has not happened yet is dashed, dimmed,
//     carries no gradient fill and ends on a hollow ring, so a forecast
//     can never be read as history;
//   * scrub haptics throttled to ~10/s;
//   * an optional summary row above the plot ([KuteLineChart.summaryBuilder])
//     that follows the window on screen, as the venue charts' change row;
//   * an optional stepped line ([KuteLineChart.stepped]) for a balance:
//     each value holds flat until the next point, then jumps, so money
//     that arrived at once never reads as a ramp;
//   * an optional scale ([KuteLineChart.showScale] and
//     [KuteLineChart.scaleLabel]): two or three round levels as faint
//     hairlines across the plot, labelled in a strip on the left that the
//     plot starts after, so the line never runs through a label. The
//     labels are the market chart's (tertiary, 10.5, semibold, tabular).
//   * an optional time axis ([KuteLineChart.timeAxis]): when the window on
//     screen starts and ends, under the plot, following every pan and
//     pinch (kute_chart_time_axis.dart); its row comes out of the plot's
//     height, never the chart's;
//   * an optional one-time zoom nudge ([KuteLineChart.zoomHint],
//     kute_chart_zoom_hint.dart): the first zoomable chart a person ever
//     sees zooms in a little and back out, once.
//
// Painters here never read Theme — the widget resolves colors once per
// build and hands them down.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:kute/screens/shared/charts/kute_chart_autoscale.dart';
import 'package:kute/screens/shared/charts/kute_chart_core.dart';
import 'package:kute/screens/shared/charts/kute_chart_crosshair.dart';
import 'package:kute/screens/shared/charts/kute_chart_format.dart';
import 'package:kute/screens/shared/charts/kute_chart_time_axis.dart';
import 'package:kute/screens/shared/charts/kute_chart_viewport.dart';
import 'package:kute/screens/shared/charts/kute_chart_zoom_hint.dart';
import 'package:kute/theme/app_theme.dart';

/// One event marker on the line: a small dot at [index] in the series,
/// e.g. a received (up-color) or sent (down-color) transaction day.
class KuteLineMarker {
  final int index;
  final Color color;
  const KuteLineMarker(this.index, this.color);

  @override
  bool operator ==(Object other) =>
      other is KuteLineMarker && other.index == index && other.color == color;

  @override
  int get hashCode => Object.hash(index, color);
}

/// The time axis of a [KuteLineChart]: the moment of each index, the word
/// the end reads at the live edge, and whether the series' last point is
/// now.
class KuteLineTimeAxis {
  /// The moment of the point at index [i].
  final DateTime Function(int i) timeAt;

  /// What the end label reads while the window reaches the newest point
  /// ("Now").
  final String nowLabel;

  /// The newest point is now (a balance up to this moment).
  final bool live;

  /// The language the dates are written in (kuteChartLocale).
  final String? locale;

  const KuteLineTimeAxis({
    required this.timeAt,
    required this.nowLabel,
    this.live = true,
    this.locale,
  });
}

class KuteLineChart extends StatefulWidget {
  /// The y series, in x order. Points are spread edge-to-edge across the
  /// canvas width (index space), matching the analytics charts.
  final List<double> values;

  final Color lineColor;

  /// Event markers (transaction dots). Skipped mid-morph — their x
  /// mapping is index-based and the morph resamples the index space.
  final List<KuteLineMarker> markers;

  final bool showFill;
  final bool showEndpointDot;
  final double strokeWidth;

  /// Draw the history as steps (hold, then jump at the next point)
  /// instead of the monotone curve. For a balance, which only moves when
  /// money does. Off by default: every price series stays a curve.
  final bool stepped;

  /// Faint hairlines at two or three round levels of the scale on
  /// screen. For a series of amounts held: levels under zero are left
  /// out. Off by default.
  final bool showScale;

  /// Writes a level of the scale for the label strip on the left
  /// ("10K sats", "$5"), given the step between levels. Null draws the
  /// hairlines without labels (balances hidden) and gives the plot the
  /// strip's width back. Only read when [showScale] is on.
  final String Function(double level, double step)? scaleLabel;

  /// Index in [values] where the series stops being history and starts
  /// being a projection. The point AT this index is the last real one,
  /// so the two halves share it and the curve never breaks. Everything
  /// after it is drawn dashed, dimmed, with no fill beneath it and a
  /// hollow ring instead of the solid endpoint dot. Null (the default)
  /// means the whole series happened, which is every other caller.
  final int? projectedFrom;

  /// Optional explicit y-domain (e.g. a live view's locked scale).
  /// When null the engine's price-domain fit is used.
  final double? lockedMinY;
  final double? lockedMaxY;

  /// Morph series changes over ~280ms. Leave true for range-pill /
  /// provider-refresh charts; turn off for per-tick streaming data.
  final bool animateChanges;

  /// Scrubbing. The chart takes touches when [valueTextBuilder] or
  /// [onScrub] is set; with neither it is a picture (the affiliate
  /// earnings graph). The builders feed the scrub card: the value (its
  /// main figure), the date, and quiet [detailTextBuilder] lines; the
  /// change since the start of the window on screen is worked out here
  /// and written with [changeFormatter].
  final void Function(int index)? onScrub;

  /// Runs once per scrub gesture, on the first index the finger lands on
  /// (never on the moves that follow). Analytics hook: one event per
  /// gesture, nothing about the value under the finger.
  final VoidCallback? onScrubStart;
  final VoidCallback? onScrubEnd;
  final String? Function(int index)? valueTextBuilder;
  final String? Function(int index)? timeTextBuilder;
  final List<String> Function(int index)? detailTextBuilder;

  /// Writes the size of a change in the series' unit ("$12.30",
  /// "12,000 sats"); the sign is added here. Null writes the percent
  /// alone.
  final String Function(double magnitude)? changeFormatter;

  /// Whether the change also says its percent of the window's first
  /// value. Off for a series that crosses zero (a profit and loss).
  final bool changePercent;

  /// Pinch to zoom and drag to pan (see [KuteChartGestures]). Only a
  /// chart that takes touches zooms.
  final bool zoomable;

  /// A row above the plot built for the window on screen, from its first
  /// to its last visible index (the venue charts' change row).
  final Widget? Function(int start, int end)? summaryBuilder;

  /// A new value puts the window back on the whole series (a range pill
  /// tapped again). A series of another length always does.
  final Object? viewResetKey;

  /// The time axis under the plot; null draws none.
  final KuteLineTimeAxis? timeAxis;

  /// May play the one-time zoom nudge (kute_chart_zoom_hint.dart) when the
  /// chart zooms and has enough points.
  final bool zoomHint;

  const KuteLineChart({
    super.key,
    required this.values,
    required this.lineColor,
    this.markers = const [],
    this.showFill = true,
    this.showEndpointDot = true,
    this.strokeWidth = 2.0,
    this.stepped = false,
    this.showScale = false,
    this.scaleLabel,
    this.projectedFrom,
    this.lockedMinY,
    this.lockedMaxY,
    this.animateChanges = true,
    this.onScrub,
    this.onScrubStart,
    this.onScrubEnd,
    this.valueTextBuilder,
    this.timeTextBuilder,
    this.detailTextBuilder,
    this.changeFormatter,
    this.changePercent = true,
    this.zoomable = true,
    this.summaryBuilder,
    this.viewResetKey,
    this.timeAxis,
    this.zoomHint = false,
  });

  bool get interactive => onScrub != null || valueTextBuilder != null;

  @override
  State<KuteLineChart> createState() => _KuteLineChartState();
}

class _KuteLineChartState extends State<KuteLineChart>
    with TickerProviderStateMixin {
  int? _touchIndex;
  DateTime _lastHaptic = DateTime(0);

  /// True once [KuteLineChart.onScrubStart] ran for the press currently
  /// down: one long press is one scrub gesture.
  bool _scrubStartReported = false;
  bool _reduceMotion = false;

  /// The user's zoom and pan (the whole series by default).
  final KuteIndexViewport _viewport = KuteIndexViewport();

  /// The one-time zoom nudge, and the wait before it.
  late final KuteZoomNudge _nudge = KuteZoomNudge(this);
  Timer? _nudgeTimer;
  bool _nudgeScheduled = false;

  /// Fingers on the plot: the nudge never plays under one.
  int _pointers = 0;

  /// One-shot entrance fade — replaces the old fl_chart progressive
  /// line-draw reveal (the morph covers timeframe transitions).
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  bool _entranceStarted = false;

  /// Series morph: old values tween into the new series over 280ms
  /// easeOutCubic (the HlCandlestickChart timeframe-morph pattern).
  late final AnimationController _morph = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  late final Animation<double> _morphCurve =
      CurvedAnimation(parent: _morph, curve: Curves.easeOutCubic);
  List<double>? _morphFromRs;
  List<double>? _morphToRs;
  List<double>? _morphTargetRaw;

  bool get _morphActive => _morphFromRs != null && _morph.value < 1.0;

  double get _extent => (widget.values.length - 1).toDouble();

  @override
  void initState() {
    super.initState();
    _nudge.listenable.addListener(_onNudgeFrame);
    _morph.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _morphFromRs = null;
        _morphToRs = null;
        _morphTargetRaw = null;
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!_entranceStarted) {
      _entranceStarted = true;
      if (_reduceMotion) {
        _fade.value = 1.0;
      } else {
        _fade.forward();
      }
    }
  }

  @override
  void didUpdateWidget(covariant KuteLineChart old) {
    super.didUpdateWidget(old);
    // A shrinking series (range switch) could leave a stale scrub index.
    if (_touchIndex != null && _touchIndex! >= widget.values.length) {
      _touchIndex = null;
    }
    // Another range (or the same range picked again) starts on the whole
    // series.
    if (old.values.length != widget.values.length ||
        old.viewResetKey != widget.viewResetKey) {
      _viewport.reset();
    }
    if (kuteSameSeries(old.values, widget.values)) return;
    if (!widget.animateChanges ||
        _reduceMotion ||
        old.values.length < 2 ||
        widget.values.length < 2) {
      if (_morphActive) _morph.value = 1.0;
      return;
    }
    if (_morphActive && _morphTargetRaw != null) {
      // Data landed mid-morph: retarget the tween instead of fighting it.
      _morphToRs = kuteResampleSeries(widget.values, _morphToRs!.length);
      _morphTargetRaw = widget.values;
      return;
    }
    final n = kuteMorphSampleCount(old.values.length, widget.values.length);
    _morphFromRs = kuteResampleSeries(old.values, n);
    _morphToRs = kuteResampleSeries(widget.values, n);
    _morphTargetRaw = widget.values;
    _morph.forward(from: 0);
  }

  @override
  void dispose() {
    _nudgeTimer?.cancel();
    _nudge.listenable.removeListener(_onNudgeFrame);
    _nudge.dispose();
    _fade.dispose();
    _morph.dispose();
    super.dispose();
  }

  // ── zoom nudge ────────────────────────────────────────────────────

  void _onNudgeFrame() {
    if (mounted) setState(() {});
  }

  /// Schedules the nudge once the chart has drawn enough points.
  void _maybeScheduleNudge() {
    if (_nudgeScheduled ||
        !widget.zoomHint ||
        !widget.interactive ||
        !widget.zoomable ||
        widget.values.length < kKuteZoomNudgeMinPoints) {
      return;
    }
    _nudgeScheduled = true;
    if (KuteZoomHint.seen) return;
    _nudgeTimer = Timer(kKuteZoomNudgeDelay, () {
      if (!mounted ||
          _pointers > 0 ||
          _touchIndex != null ||
          !_viewport.isDefault) {
        return;
      }
      _nudge.tryStart(reduceMotion: _reduceMotion);
    });
  }

  void _onPointerDown(PointerDownEvent _) {
    _pointers++;
    _nudgeTimer?.cancel();
    _nudge.cancel();
  }

  void _onPointerUp(PointerEvent _) {
    if (_pointers > 0) _pointers--;
  }

  /// [window] with the nudge's zoom in it, anchored on its end.
  KuteIndexWindow _nudged(KuteIndexWindow window) {
    final amount = _nudge.amount;
    if (amount <= 0) return window;
    return KuteIndexWindow(
        window.end - window.span * (1 - amount), window.end);
  }

  /// The time axis labels for [window].
  ({String start, String end})? _axisTexts(KuteIndexWindow window) {
    final axis = widget.timeAxis;
    final n = widget.values.length;
    if (axis == null || n == 0) return null;
    DateTime at(double i) {
      final a = i.floor().clamp(0, n - 1).toInt();
      final b = i.ceil().clamp(0, n - 1).toInt();
      final ta = axis.timeAt(a), tb = axis.timeAt(b);
      if (a == b) return ta;
      final frac = (i - a).clamp(0.0, 1.0);
      return ta.add(Duration(
          microseconds: (tb.difference(ta).inMicroseconds * frac).round()));
    }

    return kuteTimeAxisTexts(
      start: at(window.start),
      end: at(window.end),
      live: axis.live && window.end >= _extent - 1e-6,
      nowLabel: axis.nowLabel,
      locale: axis.locale,
    );
  }

  // ── scrub handling ────────────────────────────────────────────────

  void _scrubTo(double dx, double width) {
    final n = widget.values.length;
    if (n == 0 || width <= 0) return;
    final window = _viewport.windowFor(_extent);
    final x = dx.clamp(0.0, width);
    final idx = n == 1
        ? 0
        : window.indexAt(x, width).round().clamp(0, n - 1).toInt();
    if (idx == _touchIndex) return;
    if (!_scrubStartReported) {
      _scrubStartReported = true;
      widget.onScrubStart?.call();
    }
    // Throttled to ~10/s — an un-throttled selectionClick per index
    // change buzzes continuously on a fast scrub across dense series.
    final now = DateTime.now();
    if (now.difference(_lastHaptic).inMilliseconds > 100) {
      HapticFeedback.selectionClick();
      _lastHaptic = now;
    }
    setState(() => _touchIndex = idx);
    widget.onScrub?.call(idx);
  }

  void _endScrub() {
    _scrubStartReported = false;
    if (_touchIndex == null) return;
    setState(() => _touchIndex = null);
    widget.onScrubEnd?.call();
  }

  /// First and last index inside [window].
  (int, int) _visibleRange(KuteIndexWindow window) {
    final n = widget.values.length;
    if (n == 0) return (0, 0);
    final first = (window.start - 1e-6).ceil().clamp(0, n - 1).toInt();
    final last = (window.end + 1e-6).floor().clamp(first, n - 1).toInt();
    return (first, last);
  }

  KuteCrosshairData? _crosshairData(
      Size size, int ti, KuteIndexWindow window) {
    final values = widget.values;
    if (ti < 0 || ti >= values.length) return null;
    final n = values.length;
    final x = n == 1 ? size.width : window.xOf(ti.toDouble(), size.width);
    final d = kuteLineDomain(values, window,
        lockedMinY: widget.lockedMinY, lockedMaxY: widget.lockedMaxY);
    final y = kuteLineY(values[ti], size.height, d);
    return KuteCrosshairData(
      x: x,
      dots: [KuteCrosshairDot(y: y, color: widget.lineColor)],
      card: _card(ti, window),
    );
  }

  /// The scrub card for index [ti]: its value, its change since the
  /// first point on screen, its date and any detail lines.
  KuteScrubCardData? _card(int ti, KuteIndexWindow window) {
    final value = widget.valueTextBuilder?.call(ti);
    if (value == null || value.isEmpty) return null;
    final values = widget.values;
    final (first, _) = _visibleRange(window);
    final base = values[first];
    final delta = values[ti] - base;
    return KuteScrubCardData(
      value: value,
      change: ti == first
          ? null
          : kuteChangeText(
              delta: delta,
              base: base,
              magnitude: widget.changeFormatter,
              percent: widget.changePercent,
            ),
      changeSign: widget.changeFormatter == null && base != 0
          ? kutePercentDirection(delta / base.abs() * 100)
          : delta.sign.toInt(),
      time: widget.timeTextBuilder?.call(ti),
      details: widget.detailTextBuilder?.call(ti) ?? const [],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDark = context.isDark;
    final values = widget.values;
    if (values.isEmpty) return const SizedBox.shrink();

    final window = _nudged(_viewport.windowFor(_extent));
    final ti = _touchIndex;
    final scrubbing =
        widget.interactive && ti != null && ti >= 0 && ti < values.length;
    if (widget.zoomHint && !_nudgeScheduled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeScheduleNudge();
      });
    }

    final chart = AnimatedBuilder(
      animation: _morph,
      builder: (context, _) {
        final morphSeries = _morphActive
            ? kuteLerpSeries(_morphFromRs!, _morphToRs!, _morphCurve.value)
            : null;
        return Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _KuteLinePainter(
                    values: values,
                    morphSeries: morphSeries,
                    window: window,
                    lineColor: widget.lineColor,
                    isDark: isDark,
                    markers: widget.markers,
                    showFill: widget.showFill,
                    showEndpointDot: widget.showEndpointDot,
                    strokeWidth: widget.strokeWidth,
                    stepped: widget.stepped,
                    showScale: widget.showScale,
                    projectedFrom: widget.projectedFrom,
                    lockedMinY: widget.lockedMinY,
                    lockedMaxY: widget.lockedMaxY,
                  ),
                ),
              ),
            ),
            if (widget.interactive)
              Positioned.fill(
                child: KuteChartCrosshair(
                  resolve: !scrubbing
                      ? null
                      : (size) => _crosshairData(size, ti, window),
                  repaintKey: (
                    ti,
                    values.length,
                    values.isNotEmpty ? values.last : 0.0,
                    window,
                    widget.lineColor,
                    isDark,
                  ),
                  isDark: isDark,
                  hairlineColor: c.border,
                ),
              ),
          ],
        );
      },
    );

    final summary = widget.summaryBuilder == null
        ? null
        : (() {
            final (first, last) = _visibleRange(window);
            return widget.summaryBuilder!(first, last);
          })();

    final gestures = !widget.interactive
        ? chart
        : Listener(
            onPointerDown: _onPointerDown,
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerUp,
            child: KuteChartGestures(
              viewport: _viewport,
              extent: _extent,
              zoomable: widget.zoomable,
              onViewChanged: () => setState(() {}),
              onScrub: _scrubTo,
              onScrubEnd: _endScrub,
              child: chart,
            ),
          );
    // The time axis under the plot, out of the plot's own height.
    final axis = _axisTexts(window);
    final plot = axis == null
        ? gestures
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: gestures),
              KuteTimeAxis(start: axis.start, end: axis.end),
            ],
          );

    final label = widget.showScale ? widget.scaleLabel : null;
    final Widget body;
    if (label == null) {
      body = plot;
    } else {
      // The strip is as wide as the labels of the whole series' scale, so
      // a pinch never moves the plot sideways.
      final whole = kuteLineDomain(values, KuteIndexWindow(0, _extent),
          lockedMinY: widget.lockedMinY, lockedMaxY: widget.lockedMaxY);
      final levels = kuteScaleLevels(whole.minY, whole.maxY);
      final step = levels.length > 1 ? levels[1] - levels[0] : 1.0;
      var stripW = 0.0;
      for (final l in levels) {
        stripW = math.max(stripW, _scaleTp(label(l, step), c.textTertiary).width);
      }
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: stripW + _kScaleGap,
            // Level with the plot: the time axis row is under the plot.
            child: Padding(
              padding: EdgeInsets.only(
                  bottom: axis == null ? 0 : kKuteTimeAxisHeight),
              child: AnimatedBuilder(
                animation: _morph,
                builder: (context, _) {
                  final morphSeries = _morphActive
                      ? kuteLerpSeries(
                          _morphFromRs!, _morphToRs!, _morphCurve.value)
                      : null;
                  final series = morphSeries ?? values;
                  final view = morphSeries != null
                      ? KuteIndexWindow(0, (series.length - 1).toDouble())
                      : window;
                  return CustomPaint(
                    painter: _KuteScaleLabelsPainter(
                      domain: kuteLineDomain(series, view,
                          lockedMinY: widget.lockedMinY,
                          lockedMaxY: widget.lockedMaxY),
                      label: label,
                      color: c.textTertiary,
                    ),
                  );
                },
              ),
            ),
          ),
          Expanded(child: plot),
        ],
      );
    }

    return FadeTransition(
      opacity: _fade,
      child: summary == null
          ? body
          : Column(
              children: [
                summary,
                Expanded(child: body),
              ],
            ),
    );
  }
}

/// The room between a scale label and the plot.
const double _kScaleGap = 6.0;

/// A scale label laid out in the market chart's style. Cached: the same
/// few labels are painted every frame of a pinch.
final Map<(String, int), TextPainter> _scaleTpCache = {};

TextPainter _scaleTp(String text, Color color) {
  if (_scaleTpCache.length > 64) _scaleTpCache.clear();
  return _scaleTpCache.putIfAbsent(
    (text, color.toARGB32()),
    () => TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: kuteChartFontFamily,
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(),
  );
}

/// Two or three round levels (1, 2 or 5 times a power of ten apart)
/// inside [lo]..[hi], lowest first, none under zero: the scale of a
/// series of amounts held.
List<double> kuteScaleLevels(double lo, double hi, {int maxLevels = 3}) {
  if (!(hi > lo) || !lo.isFinite || !hi.isFinite) return const [];
  double nice(double raw) {
    final mag = math
        .pow(10.0, (math.log(raw) / math.ln10).floor())
        .toDouble();
    final norm = raw / mag;
    final m = norm <= 1 ? 1 : (norm <= 2 ? 2 : (norm <= 5 ? 5 : 10));
    return m * mag;
  }

  List<double> levelsFor(double step) {
    final out = <double>[];
    final from = math.max(0.0, lo);
    var v = (from / step).ceil() * step;
    for (var guard = 0; v <= hi + step * 1e-9 && guard < 50; guard++) {
      out.add(v);
      v += step;
    }
    return out;
  }

  var step = nice((hi - lo) / maxLevels);
  var out = levelsFor(step);
  for (var guard = 0; out.length > maxLevels && guard < 8; guard++) {
    step = nice(step * 1.01);
    out = levelsFor(step);
  }
  return out;
}

/// The label strip: each level's label right-aligned against the plot,
/// centred on its hairline, kept inside the strip at the top and bottom.
class _KuteScaleLabelsPainter extends CustomPainter {
  final KuteYDomain domain;
  final String Function(double level, double step) label;
  final Color color;

  _KuteScaleLabelsPainter({
    required this.domain,
    required this.label,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final levels = kuteScaleLevels(domain.minY, domain.maxY);
    if (levels.isEmpty) return;
    final step = levels.length > 1 ? levels[1] - levels[0] : 1.0;
    for (final level in levels) {
      final tp = _scaleTp(label(level, step), color);
      final y = kuteLineY(level, size.height, domain);
      final top = (y - tp.height / 2)
          .clamp(0.0, math.max(0.0, size.height - tp.height))
          .toDouble();
      tp.paint(canvas,
          Offset(math.max(0.0, size.width - _kScaleGap - tp.width), top));
    }
  }

  @override
  bool shouldRepaint(covariant _KuteScaleLabelsPainter old) =>
      old.domain != domain || old.color != color || old.label != label;
}

/// The y-domain of a line over the points in [window]: the venue charts'
/// autoscale ([kuteAutoScaleDomain]: a tenth of the plot free above and
/// below the visible high and low, a flat line centred), unless the host
/// locks it.
KuteYDomain kuteLineDomain(
  List<double> series,
  KuteIndexWindow window, {
  double? lockedMinY,
  double? lockedMaxY,
}) {
  if (lockedMinY != null && lockedMaxY != null) {
    return (minY: lockedMinY, maxY: lockedMaxY);
  }
  final n = series.length;
  if (n == 0) return (minY: 0, maxY: 1);
  // The points on screen plus one either side, so the line entering and
  // leaving the window is on the scale too.
  final i0 = (window.start.floor()).clamp(0, n - 1).toInt();
  final i1 = (window.end.ceil()).clamp(i0, n - 1).toInt();
  var lo = series[i0], hi = series[i0];
  for (var i = i0; i <= i1; i++) {
    final v = series[i];
    if (v < lo) lo = v;
    if (v > hi) hi = v;
  }
  return kuteAutoScaleDomain(lo, hi);
}

/// Value → y inside a plot [h] px tall for domain [d]: the linear mapping
/// the venue charts use.
double kuteLineY(double v, double h, KuteYDomain d) {
  final span = d.maxY - d.minY;
  if (!(span > 0)) return h / 2;
  return h * (1 - ((v - d.minY) / span).clamp(0.0, 1.0));
}

/// Data layer: engine line + fill + endpoint dot + event markers.
class _KuteLinePainter extends CustomPainter {
  final List<double> values;
  final List<double>? morphSeries;
  final KuteIndexWindow window;
  final Color lineColor;
  final bool isDark;
  final List<KuteLineMarker> markers;
  final bool showFill;
  final bool showEndpointDot;
  final double strokeWidth;
  final bool stepped;
  final bool showScale;
  final int? projectedFrom;
  final double? lockedMinY;
  final double? lockedMaxY;

  _KuteLinePainter({
    required this.values,
    required this.morphSeries,
    required this.window,
    required this.lineColor,
    required this.isDark,
    required this.markers,
    required this.showFill,
    required this.showEndpointDot,
    required this.strokeWidth,
    required this.stepped,
    required this.showScale,
    required this.projectedFrom,
    required this.lockedMinY,
    required this.lockedMaxY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final series = morphSeries ?? values;
    final n = series.length;
    if (n == 0) return;
    final w = size.width;
    final h = size.height;
    // A morph runs over the whole series (a new range starts unzoomed),
    // in its own resampled index space.
    final view = morphSeries != null
        ? KuteIndexWindow(0, (n - 1).toDouble())
        : window;

    final d = kuteLineDomain(series, view,
        lockedMinY: lockedMinY, lockedMaxY: lockedMaxY);
    double toY(double v) => kuteLineY(v, h, d);
    double toX(int i) => n == 1 ? w : view.xOf(i.toDouble(), w);

    // The scale's hairlines sit under everything else.
    if (showScale) {
      final hairline = Paint()
        ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05)
        ..strokeWidth = 1.0;
      for (final level in kuteScaleLevels(d.minY, d.maxY)) {
        final y = toY(level);
        canvas.drawLine(Offset(0, y), Offset(w, y), hairline);
      }
    }

    // Single point: just the endpoint dot — nothing to connect yet.
    if (n == 1) {
      kuteDrawEndpointDot(canvas, Offset(w, toY(series.first)), lineColor,
          isDark: isDark);
      return;
    }

    // The points on screen plus one either side, so the line runs off
    // the edges of a zoomed window instead of stopping short of them.
    final i0 = view.start.floor().clamp(0, n - 1).toInt();
    final i1 = view.end.ceil().clamp(i0, n - 1).toInt();
    final pts = List<Offset>.generate(
        i1 - i0 + 1, (k) => Offset(toX(i0 + k), toY(series[i0 + k])),
        growable: false);

    // Where history ends. Mid-morph the index space is resampled, so the
    // split rides along proportionally instead of pointing at the wrong
    // sample.
    var split = projectedFrom;
    if (split != null && morphSeries != null && values.length > 1) {
      split = (split / (values.length - 1) * (n - 1)).round();
    }
    final historyEnd = split == null ? n - 1 : split.clamp(0, n - 1).toInt();
    // The same split inside the visible points.
    final localEnd = (historyEnd - i0).clamp(-1, pts.length - 1).toInt();
    final historyPts =
        localEnd < 0 ? const <Offset>[] : pts.sublist(0, localEnd + 1);
    final projectedPts = localEnd < pts.length - 1
        ? pts.sublist(math.max(0, localEnd))
        : null;

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(-6, -6, w + 12, h + 12));
    if (historyPts.length >= 2) {
      final path =
          stepped ? kuteStepPath(historyPts) : kuteMonotonePath(historyPts);
      if (showFill) {
        // The fill stops where the history does: shading under a
        // forecast would give it the weight of money that arrived.
        final fill = Path.from(path)
          ..lineTo(historyPts.last.dx, h)
          ..lineTo(historyPts.first.dx, h)
          ..close();
        canvas.drawPath(
            fill, Paint()..shader = kuteFillShader(w, h, lineColor));
      }
      canvas.drawPath(path, kuteStrokePaint(lineColor, width: strokeWidth));
    }

    if (projectedPts != null && projectedPts.length >= 2) {
      canvas.drawPath(
        _dashPath(kuteMonotonePath(projectedPts)),
        kuteStrokePaint(lineColor.withValues(alpha: 0.55), width: strokeWidth),
      );
    }

    // Event markers (transaction dots) — HL fill-marker grammar: a
    // background halo so the dot stays legible over the line, then the
    // colored core. Skipped mid-morph (resampled index space).
    if (markers.isNotEmpty && morphSeries == null) {
      final halo = Paint()..color = isDark ? Colors.black : Colors.white;
      for (final m in markers) {
        if (m.index < i0 || m.index > i1 || m.index >= values.length) {
          continue;
        }
        final o = Offset(toX(m.index), toY(values[m.index]));
        canvas.drawCircle(o, 5.0, halo);
        canvas.drawCircle(o, 3.5, Paint()..color = m.color);
      }
    }

    if (showEndpointDot) {
      // The solid dot stays on the last real point while it is on
      // screen; the projected end gets a hollow ring, which reads as
      // "has not arrived".
      if (historyPts.isNotEmpty && historyEnd <= i1) {
        kuteDrawEndpointDot(canvas, historyPts.last, lineColor,
            isDark: isDark);
      }
      if (projectedPts != null && projectedPts.length >= 2 && i1 == n - 1) {
        canvas.drawCircle(projectedPts.last, 4.0,
            Paint()..color = isDark ? Colors.black : Colors.white);
        canvas.drawCircle(
          projectedPts.last,
          3.25,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = lineColor.withValues(alpha: 0.55),
        );
      }
    }
    canvas.restore();
  }

  /// Chop a path into even dashes. The projected tail only.
  static Path _dashPath(Path source) {
    const dash = 4.0;
    const gap = 4.0;
    final out = Path();
    for (final metric in source.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final end = (d + dash) > metric.length ? metric.length : d + dash;
        out.addPath(metric.extractPath(d, end), Offset.zero);
        d = end + gap;
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(covariant _KuteLinePainter old) =>
      !kuteSameSeries(old.values, values) ||
      !_sameMorph(old.morphSeries, morphSeries) ||
      old.lineColor != lineColor ||
      old.isDark != isDark ||
      !listEquals(old.markers, markers) ||
      old.showFill != showFill ||
      old.showEndpointDot != showEndpointDot ||
      old.strokeWidth != strokeWidth ||
      old.stepped != stepped ||
      old.showScale != showScale ||
      old.projectedFrom != projectedFrom ||
      old.lockedMinY != lockedMinY ||
      old.lockedMaxY != lockedMaxY ||
      old.window != window;

  static bool _sameMorph(List<double>? a, List<double>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    return kuteSameSeries(a, b);
  }
}

/// A stepped line through [pts]: flat from each point to the next one's
/// x, then straight up or down to it. A balance holds until money moves.
Path kuteStepPath(List<Offset> pts) {
  final path = Path();
  if (pts.isEmpty) return path;
  path.moveTo(pts.first.dx, pts.first.dy);
  for (var i = 1; i < pts.length; i++) {
    path.lineTo(pts[i].dx, pts[i - 1].dy);
    if (pts[i].dy != pts[i - 1].dy) path.lineTo(pts[i].dx, pts[i].dy);
  }
  return path;
}

/// Draw one full engine-style spark (monotone line + 0.14 fill + 2.0
/// stroke + endpoint dot) straight onto a canvas — for bespoke painters
/// (live streaming views) that own their geometry but should share the
/// engine's look. [lockedMin]/[lockedMax] pin the y-domain (live locked
/// scale); when null the series min-max is fitted with the engine pad.
void kutePaintLineSpark(
  Canvas canvas, {
  required List<double> values,
  required double width,
  required double height,
  required Color color,
  required bool isDark,
  double? lockedMin,
  double? lockedMax,
  bool showFill = true,
}) {
  final n = values.length;
  if (n == 0) return;
  double lo, hi;
  if (lockedMin != null && lockedMax != null) {
    lo = lockedMin;
    hi = lockedMax;
  } else {
    lo = values.first;
    hi = values.first;
    for (final v in values) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    final d = kuteFitPriceDomain(lo, hi);
    lo = d.minY;
    hi = d.maxY;
  }
  double toY(double v) => kuteValueToY(v, height, minY: lo, maxY: hi);
  if (n == 1) {
    kuteDrawEndpointDot(canvas, Offset(width, toY(values.first)), color,
        isDark: isDark);
    return;
  }
  final stepX = width / (n - 1);
  final pts = List<Offset>.generate(
      n, (i) => Offset(i * stepX, toY(values[i])),
      growable: false);
  final path = kuteMonotonePath(pts);
  if (showFill) {
    final fill = Path.from(path)
      ..lineTo(pts.last.dx, height)
      ..lineTo(pts.first.dx, height)
      ..close();
    canvas.drawPath(fill, Paint()..shader = kuteFillShader(width, height, color));
  }
  canvas.drawPath(path, kuteStrokePaint(color));
  kuteDrawEndpointDot(canvas, pts.last, color, isDark: isDark);
}
