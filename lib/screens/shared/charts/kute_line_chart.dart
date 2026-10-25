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
//     sees zooms in a little and back out, once;
//   * an optional overlay over the line ([KuteLineChart.plotOverlay]),
//     built for the window on screen, so a mark on the chart's scale
//     follows every pan and pinch;
//   * optional buckets ([KuteLineChart.buckets]) for a long series laid
//     evenly in time (the Balance charts): only each bucket's close is
//     drawn, scaled and scrubbed, the bucket sized for the window on
//     screen, so a pinch re-buckets and a blip inside a bucket never
//     reaches the line or the scale; and an optional opening window
//     ([KuteLineChart.defaultSpan]) narrower than the whole series;
//   * an optional header above the plot that also knows the point under
//     the finger ([KuteLineChart.headerBuilder]), so a chart can write the
//     scrubbed value there instead of on the floating card, and an
//     optional dotted baseline at the first value on screen
//     ([KuteLineChart.startBaseline]);
//   * an optional fixed baseline ([KuteLineChart.baselineAt], the P&L
//     chart's zero): dotted across the plot, always on the scale, and with
//     [KuteLineChart.fillAboveColor] / [KuteLineChart.fillBelowColor] the
//     fill runs between the line and it, tinted by the side it is on.
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

/// Buckets over a long series laid evenly in time: a window draws only
/// the points that close a bucket ([strideFor] points apart, counted
/// from [phase] before the first point) and the last point, so what
/// moved inside a bucket never shows. Before the first close the line
/// holds that close's level: the first bucket reads as its close too.
class KuteLineBuckets {
  /// The points per bucket for a window [span] points wide.
  final int Function(double span) strideFor;

  /// Points from a bucket boundary to the series' first point.
  final int phase;

  const KuteLineBuckets({required this.strideFor, this.phase = 0});

  /// The points drawn for [window] over [n] points, in order: each bucket
  /// close inside it, and the nearest drawn point beyond each edge so the
  /// line runs off the plot instead of stopping short.
  List<int> indicesFor(int n, KuteIndexWindow window) {
    if (n <= 0) return const [];
    if (n == 1) return const [0];
    final k = math.max(1, strideFor(window.span));
    // The last drawn point at or before [i] (none before the first
    // close), and the first at or after it.
    int? prev(int i) {
      if (i >= n - 1) return n - 1;
      final c = i - (i + phase) % k;
      return c >= 0 ? c : null;
    }

    int next(int i) {
      if (i >= n - 1) return n - 1;
      final r = (i + phase) % k;
      return math.min(n - 1, r == 0 ? i : i + k - r);
    }

    final out = <int>[];
    var i = prev(window.start.floor().clamp(0, n - 1).toInt()) ?? next(0);
    while (true) {
      out.add(i);
      if (i >= n - 1 || i >= window.end) break;
      i = next(i + 1);
    }
    return out;
  }
}

/// What a [KuteLineChart.headerBuilder] builds for: the first and last
/// points on screen, the point under the finger (null when nobody is
/// scrubbing), the window, and whether it is still the opening view (no
/// pinch or pan since the chart opened or was reset).
@immutable
class KuteLineView {
  final int first;
  final int last;
  final int? touched;
  final KuteIndexWindow window;
  final bool isDefault;

  const KuteLineView({
    required this.first,
    required this.last,
    required this.touched,
    required this.window,
    required this.isDefault,
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

  /// A row above the plot that also follows the finger (see
  /// [KuteLineView]); takes the place of [summaryBuilder]. Rebuilt with
  /// the chart on every scrub step, never through the host.
  final Widget Function(KuteLineView view)? headerBuilder;

  /// A faint dotted line across the plot at the first value on screen,
  /// so the line reads as up or down from where the window starts.
  final bool startBaseline;

  /// A faint dotted line across the plot at this fixed value (a P&L's
  /// zero), kept on the scale of every window so it always spans the
  /// width; takes the place of [startBaseline]. Null draws none.
  final double? baselineAt;

  /// With [baselineAt], the fill runs between the line and the baseline
  /// instead of down to the bottom of the plot: this colour (low alpha)
  /// where the line is above it, [fillBelowColor] where it is below.
  /// Null for both keeps the standard fill in [lineColor].
  final Color? fillAboveColor;
  final Color? fillBelowColor;

  /// A new value puts the window back on the whole series (a range pill
  /// tapped again). A series of another length also does, unless
  /// [resetViewOnLengthChange] is off.
  final Object? viewResetKey;

  /// Off, a series that grows (a balance gaining a point as time passes)
  /// keeps the window where the user left it; only [viewResetKey] puts it
  /// back.
  final bool resetViewOnLengthChange;

  /// The window the chart opens on, in points, ending on the newest one;
  /// null opens on the whole series. Followed until the first pinch or
  /// pan, so data landing late re-fits the opening view.
  final double? defaultSpan;

  /// The closest a pinch gets, in points; null keeps the shared rule
  /// ([KuteIndexViewport.minSpanFor]).
  final double? minSpan;

  /// A pinch keeps what is under the fingers under them (see
  /// [KuteChartGestures.zoomAroundFingers]).
  final bool zoomAroundFingers;

  /// Draw only each bucket's close (see [KuteLineBuckets]); null draws
  /// every point.
  final KuteLineBuckets? buckets;

  /// The least the scale on screen spans, as a share of the largest value
  /// on it: a balance that barely moved is drawn as barely moving, not
  /// magnified into a cliff with labels a few sats apart. Null fits the
  /// points exactly (prices).
  final double? minScaleShare;

  /// The least step between two levels of the scale, in the series' unit:
  /// one sat for a bitcoin balance, so a balance of a few sats is never
  /// labelled "0.5 sats" or a float artifact. Null steps freely (dollars
  /// down to cents, prices).
  final double? scaleMinStep;

  /// The time axis under the plot; null draws none.
  final KuteLineTimeAxis? timeAxis;

  /// May play the one-time zoom nudge (kute_chart_zoom_hint.dart) when the
  /// chart zooms and has enough points.
  final bool zoomHint;

  /// Drawn over the line (under the scrub crosshair, never taking touches)
  /// for the window on screen, so a mark on the chart's scale (the P&L
  /// chart's dashed baseline) follows every pan, pinch and the nudge.
  final Widget Function(KuteIndexWindow window)? plotOverlay;

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
    this.headerBuilder,
    this.startBaseline = false,
    this.baselineAt,
    this.fillAboveColor,
    this.fillBelowColor,
    this.viewResetKey,
    this.resetViewOnLengthChange = true,
    this.defaultSpan,
    this.minSpan,
    this.zoomAroundFingers = false,
    this.buckets,
    this.minScaleShare,
    this.scaleMinStep,
    this.timeAxis,
    this.zoomHint = false,
    this.plotOverlay,
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
    if ((widget.resetViewOnLengthChange &&
            old.values.length != widget.values.length) ||
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
    final at = window.indexAt(x, width);
    final drawn = _drawn(window);
    var idx = n == 1 ? 0 : at.round().clamp(0, n - 1).toInt();
    if (drawn != null && n > 1) {
      // On a bucketed line the finger lands on the nearest drawn point on
      // screen: the card reads the line, never a blip between its points.
      var best = -1;
      for (final i in drawn) {
        final onScreen = i >= window.start - 1e-6 && i <= window.end + 1e-6;
        if (!onScreen) continue;
        if (best < 0 || (i - at).abs() < (best - at).abs()) best = i;
      }
      if (best >= 0) idx = best;
    }
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

  /// The points drawn for [window]: the bucket closes with
  /// [KuteLineChart.buckets], else null (every point).
  List<int>? _drawn(KuteIndexWindow window) =>
      widget.buckets?.indicesFor(widget.values.length, window);

  /// First and last index inside [window].
  (int, int) _visibleRange(KuteIndexWindow window) {
    final n = widget.values.length;
    if (n == 0) return (0, 0);
    final drawn = _drawn(window);
    if (drawn != null && drawn.isNotEmpty) {
      final inside = [
        for (final i in drawn)
          if (i >= window.start - 1e-6 && i <= window.end + 1e-6) i
      ];
      if (inside.isEmpty) return (drawn.first, drawn.last);
      return (inside.first, inside.last);
    }
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
        lockedMinY: widget.lockedMinY,
        lockedMaxY: widget.lockedMaxY,
        indices: _drawn(window),
        minShare: widget.minScaleShare,
        include: widget.baselineAt);
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

    _viewport
      ..defaultSpan = widget.defaultSpan
      ..minSpan = widget.minSpan;
    final window = _nudged(_viewport.windowFor(_extent));
    final drawn = _drawn(window);
    final (firstOnScreen, lastOnScreen) = _visibleRange(window);
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
                    baseline: widget.baselineAt ??
                        (widget.startBaseline ? values[firstOnScreen] : null),
                    includeBaseline: widget.baselineAt != null,
                    fillAbove: widget.baselineAt == null
                        ? null
                        : widget.fillAboveColor,
                    fillBelow: widget.baselineAt == null
                        ? null
                        : widget.fillBelowColor,
                    projectedFrom: widget.projectedFrom,
                    lockedMinY: widget.lockedMinY,
                    lockedMaxY: widget.lockedMaxY,
                    indices: drawn,
                    minScaleShare: widget.minScaleShare,
                    scaleMinStep: widget.scaleMinStep,
                  ),
                ),
              ),
            ),
            if (widget.plotOverlay != null)
              Positioned.fill(
                child: IgnorePointer(child: widget.plotOverlay!(window)),
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

    final Widget? summary;
    if (widget.headerBuilder != null) {
      summary = widget.headerBuilder!(KuteLineView(
        first: firstOnScreen,
        last: lastOnScreen,
        touched: scrubbing ? ti : null,
        window: window,
        isDefault: _viewport.isDefault,
      ));
    } else {
      summary = widget.summaryBuilder?.call(firstOnScreen, lastOnScreen);
    }

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
              zoomAroundFingers: widget.zoomAroundFingers,
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
      final all = KuteIndexWindow(0, _extent);
      final whole = kuteLineDomain(values, all,
          lockedMinY: widget.lockedMinY,
          lockedMaxY: widget.lockedMaxY,
          indices: _drawn(all),
          minShare: widget.minScaleShare,
          include: widget.baselineAt);
      final levels = kuteScaleLevels(whole.minY, whole.maxY,
          minStep: widget.scaleMinStep);
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
                          lockedMaxY: widget.lockedMaxY,
                          indices: morphSeries != null ? null : drawn,
                          minShare: widget.minScaleShare,
                          include: widget.baselineAt),
                      label: label,
                      color: c.textTertiary,
                      minStep: widget.scaleMinStep,
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
/// series of amounts held. With [minStep] the levels are never closer
/// than that (one sat for a bitcoin balance).
List<double> kuteScaleLevels(double lo, double hi,
    {int maxLevels = 3, double? minStep}) {
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
  if (minStep != null && step < minStep) step = minStep;
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
  final double? minStep;

  _KuteScaleLabelsPainter({
    required this.domain,
    required this.label,
    required this.color,
    this.minStep,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final levels =
        kuteScaleLevels(domain.minY, domain.maxY, minStep: minStep);
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
      old.domain != domain ||
      old.color != color ||
      old.label != label ||
      old.minStep != minStep;
}

/// The y-domain of a line over the points in [window]: the venue charts'
/// autoscale ([kuteAutoScaleDomain]: a tenth of the plot free above and
/// below the visible high and low, a flat line centred), unless the host
/// locks it. With [indices] (a bucketed line) only those points count,
/// and where the line crosses an edge of the window, so a point off
/// screen never stretches the scale. With [minShare] the scale spans at
/// least that share of its largest value (see
/// [KuteLineChart.minScaleShare]). With [include] that value is always on
/// the scale ([KuteLineChart.baselineAt]). A line flat at zero sits in the
/// middle with a single level, zero.
KuteYDomain kuteLineDomain(
  List<double> series,
  KuteIndexWindow window, {
  double? lockedMinY,
  double? lockedMaxY,
  List<int>? indices,
  double? minShare,
  double? include,
}) {
  if (lockedMinY != null && lockedMaxY != null) {
    return (minY: lockedMinY, maxY: lockedMaxY);
  }
  final n = series.length;
  if (n == 0) return (minY: 0, maxY: 1);
  double? lo, hi;
  void take(double v) {
    if (lo == null || v < lo!) lo = v;
    if (hi == null || v > hi!) hi = v;
  }

  if (indices != null && indices.isNotEmpty) {
    for (var k = 0; k < indices.length; k++) {
      final i = indices[k];
      if (i < 0 || i >= n) continue;
      if (i >= window.start - 1e-9 && i <= window.end + 1e-9) take(series[i]);
      if (k == 0) continue;
      final a = indices[k - 1];
      if (a < 0 || a >= n || i <= a) continue;
      for (final edge in [window.start, window.end]) {
        if (a < edge && i > edge) {
          final f = (edge - a) / (i - a);
          take(series[a] + (series[i] - series[a]) * f);
        }
      }
    }
  }
  if (lo == null || hi == null) {
    // The points on screen plus one either side, so the line entering and
    // leaving the window is on the scale too.
    final i0 = (window.start.floor()).clamp(0, n - 1).toInt();
    final i1 = (window.end.ceil()).clamp(i0, n - 1).toInt();
    for (var i = i0; i <= i1; i++) {
      take(series[i]);
    }
  }
  if (include != null && include.isFinite) take(include);
  if (lo == 0 && hi == 0) return (minY: -0.4, maxY: 0.4);
  var l = lo!, u = hi!;
  final least = (minShare ?? 0) * math.max(l.abs(), u.abs());
  if (u - l < least) {
    // Widened about the middle, never below zero for amounts held.
    final mid = (l + u) / 2;
    l = mid - least / 2;
    u = mid + least / 2;
    if (lo! >= 0 && l < 0) {
      u -= l;
      l = 0;
    }
  }
  return kuteAutoScaleDomain(l, u);
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

  /// The points drawn (a bucketed line); null draws every point.
  final List<int>? indices;

  /// See [KuteLineChart.minScaleShare].
  final double? minScaleShare;

  /// The value the dotted baseline is drawn at; null draws none.
  final double? baseline;

  /// The baseline is a fixed value kept on the scale
  /// ([KuteLineChart.baselineAt]).
  final bool includeBaseline;

  /// The fill between the line and [baseline], per side; null for both
  /// fills down to the bottom in the line's colour.
  final Color? fillAbove;
  final Color? fillBelow;

  /// See [KuteLineChart.scaleMinStep].
  final double? scaleMinStep;

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
    this.indices,
    this.minScaleShare,
    this.scaleMinStep,
    this.baseline,
    this.includeBaseline = false,
    this.fillAbove,
    this.fillBelow,
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

    // Mid-morph the series is resampled: every point is drawn.
    final drawn = morphSeries != null ? null : indices;
    final d = kuteLineDomain(series, view,
        lockedMinY: lockedMinY,
        lockedMaxY: lockedMaxY,
        indices: drawn,
        minShare: minScaleShare,
        include: includeBaseline ? baseline : null);
    double toY(double v) => kuteLineY(v, h, d);
    double toX(int i) => n == 1 ? w : view.xOf(i.toDouble(), w);

    // The scale's hairlines sit under everything else.
    if (showScale) {
      final hairline = Paint()
        ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05)
        ..strokeWidth = 1.0;
      for (final level
          in kuteScaleLevels(d.minY, d.maxY, minStep: scaleMinStep)) {
        final y = toY(level);
        canvas.drawLine(Offset(0, y), Offset(w, y), hairline);
      }
    }

    // The dotted baseline at the first value on screen, under the line.
    // Mid-morph the window is the whole resampled series: none.
    final base = morphSeries == null ? baseline : null;
    if (base != null && base.isFinite) {
      final y = toY(base);
      final dot = Paint()
        ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.22);
      for (var x = 1.0; x < w; x += 5) {
        canvas.drawCircle(Offset(x, y), 0.75, dot);
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
    final idx = drawn != null && drawn.isNotEmpty
        ? drawn
        : (() {
            final a = view.start.floor().clamp(0, n - 1).toInt();
            final b = view.end.ceil().clamp(a, n - 1).toInt();
            return List<int>.generate(b - a + 1, (k) => a + k);
          })();
    final i0 = idx.first;
    final i1 = idx.last;
    final pts = List<Offset>.generate(
        idx.length, (k) => Offset(toX(idx[k]), toY(series[idx[k]])),
        growable: true);
    // A bucketed line holds its first close's level back to the start of
    // the series (nothing is drawn before the first close).
    final lead = drawn != null && drawn.isNotEmpty && drawn.first > view.start;
    if (lead) pts.insert(0, Offset(toX(0), pts.first.dy));

    // Where history ends. Mid-morph the index space is resampled, so the
    // split rides along proportionally instead of pointing at the wrong
    // sample.
    var split = projectedFrom;
    if (split != null && morphSeries != null && values.length > 1) {
      split = (split / (values.length - 1) * (n - 1)).round();
    }
    final historyEnd = split == null ? n - 1 : split.clamp(0, n - 1).toInt();
    // The same split inside the visible points.
    var localEnd = idx.lastIndexWhere((i) => i <= historyEnd);
    if (lead && localEnd >= 0) localEnd++;
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
      final fillBase = morphSeries == null ? baseline : null;
      if (showFill &&
          fillBase != null &&
          fillBase.isFinite &&
          (fillAbove != null || fillBelow != null)) {
        // Between the line and the baseline, tinted by the side: the
        // area above it in one colour, below it in the other, each
        // fading towards the baseline.
        final y0 = toY(fillBase);
        final fill = Path.from(path)
          ..lineTo(historyPts.last.dx, y0)
          ..lineTo(historyPts.first.dx, y0)
          ..close();
        final bounds = fill.getBounds();
        void side(Color? color, Rect rect, bool above) {
          if (color == null || rect.height <= 0) return;
          canvas.save();
          // Inside the plot's width: the stroke may run off the edges of a
          // zoomed window, the shading stops at them.
          canvas.clipRect(Rect.fromLTRB(0, rect.top, w, rect.bottom));
          canvas.drawPath(
              fill,
              Paint()
                ..shader = LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: above
                      ? [
                          color.withValues(alpha: 0.18),
                          color.withValues(alpha: 0.03),
                        ]
                      : [
                          color.withValues(alpha: 0.03),
                          color.withValues(alpha: 0.18),
                        ],
                ).createShader(rect));
          canvas.restore();
        }

        side(fillAbove, Rect.fromLTRB(0, math.min(bounds.top, y0), w, y0),
            true);
        side(fillBelow,
            Rect.fromLTRB(0, y0, w, math.max(bounds.bottom, y0)), false);
      } else if (showFill) {
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
      !listEquals(old.indices, indices) ||
      old.minScaleShare != minScaleShare ||
      old.baseline != baseline ||
      old.includeBaseline != includeBaseline ||
      old.fillAbove != fillAbove ||
      old.fillBelow != fillBelow ||
      old.scaleMinStep != scaleMinStep ||
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
