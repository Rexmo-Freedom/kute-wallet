// lib/screens/shared/charts/kute_trend_chart.dart
//
// THE modern line chart (founder, 31 October 2026: "make the graph modern;
// it seems like old fintech"). The Portfolio's P&L chart, the Bitcoin
// home Balance tab and the Dollars balance chart all draw through it:
//
//   * ONE line and no chrome: the monotone curve (kuteMonotonePath), a
//     2 px round stroke in the RESULT colour of the period on screen
//     (marketUp when it ended higher than it started, marketDown lower,
//     textPrimary when flat), a vertical fill from 18% of that colour to
//     nothing. No axes, no grid, no labels inside the plot, no dotted
//     baselines; the one reference is a 1 px dashed hairline at the
//     period's first value, in the border colour. The plot bleeds edge to
//     edge inside the page gutters, 200 tall (160 compact);
//   * SCRUB: a horizontal drag (or a long press, then slide) shows a 1 px
//     hairline and an 8 px dot on the line at the nearest point and hands
//     the point to the host ([KuteTrendChart.onScrub]), which writes the
//     value and the date in ITS header; null on release, so the header
//     goes back to the latest. A selection click on each new point, at
//     most ten a second;
//   * MOTION: the first paint draws the line left to right over 600 ms on
//     the settle easing with the fill fading in behind it; another series
//     (a range picked) MORPHS the line: both resampled to 60 points and
//     tweened on the chip spring. The last point breathes (1 → 1.35, a
//     1.6 s loop) while the series is live. Reduce Motion: none of it;
//   * RANGES ([KuteChartRangeRow]): one row of small 12 sp text pills 16
//     px under the plot, the picked one the home strip's small white pill
//     (hairline, shadow) sliding on the chip spring;
//   * NO EMPTY FRAME: with no history ([KuteTrendChart.values] empty) the
//     chart draws nothing but one quiet 12 sp caption; the host keeps its
//     headline and the range row is left out;
//   * EXTRA LINES ([KuteTrendChart.lines], the P&L chart's venues): 1.5 px
//     in their own colours, no fill, under the main line, on its scale.
//
// Painters here never read Theme — the widget resolves colours once per
// build and hands them down.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/screens/shared/charts/kute_chart_core.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/theme/kute_motion.dart';

/// The plot's height: the standard, and the compact (a tight card).
const double kKuteTrendPlotHeight = 200;
const double kKuteTrendPlotHeightCompact = 160;

/// The room between the plot and the range row.
const double kKuteTrendRangeGap = 16;

/// The first paint: the line drawn left to right.
const Duration kKuteTrendDrawIn = Duration(milliseconds: 600);

/// The breathing of the live dot: one full breath.
const Duration kKuteTrendBreath = Duration(milliseconds: 1600);

/// Points both series are resampled to before a morph.
const int kKuteTrendMorphSamples = 60;

/// The point under the finger: its index in [KuteTrendChart.values], its
/// value and its moment (null when the host gave no times).
@immutable
class KuteTrendPoint {
  final int index;
  final double value;
  final DateTime? time;

  const KuteTrendPoint(
      {required this.index, required this.value, required this.time});

  @override
  bool operator ==(Object other) =>
      other is KuteTrendPoint &&
      other.index == index &&
      other.value == value &&
      other.time == time;

  @override
  int get hashCode => Object.hash(index, value, time);

  @override
  String toString() => 'KuteTrendPoint($index, $value, $time)';
}

/// An extra line on the chart, in its own colour, with no fill.
@immutable
class KuteTrendLine {
  final List<double> values;
  final Color color;

  const KuteTrendLine({required this.values, required this.color});
}

/// The line's colour for a period that went from [first] to [last].
Color kuteTrendResultColor(AppColorsExtension c, double first, double last) =>
    last > first
        ? AppColors.marketUp
        : last < first
            ? AppColors.marketDown
            : c.textPrimary;

class KuteTrendChart extends StatefulWidget {
  /// The series on screen, in time order, spread edge to edge. Empty: no
  /// history yet, the chart draws [emptyCaption] alone.
  final List<double> values;

  /// The moment of each point (same length as [values]); null hands the
  /// host points without a time.
  final List<DateTime>? times;

  /// Extra lines on the same scale ([KuteTrendLine]).
  final List<KuteTrendLine> lines;

  /// The line's colour; null takes the period's result
  /// ([kuteTrendResultColor]).
  final Color? lineColor;

  /// The plot's height ([kKuteTrendPlotHeight] by default).
  final double height;

  /// The newest point is now: it breathes.
  final bool live;

  /// The one caption drawn when there is no history ([values] empty).
  final String? emptyCaption;

  /// The point under the finger, null when it lifts.
  final ValueChanged<KuteTrendPoint?>? onScrub;

  /// Once per scrub gesture, on the first point the finger lands on.
  final VoidCallback? onScrubStart;

  /// The range row under the plot; null draws none. With no history the
  /// row is left out too.
  final List<String>? rangeLabels;
  final int selectedRange;
  final ValueChanged<int>? onRangeSelected;

  const KuteTrendChart({
    super.key,
    required this.values,
    this.times,
    this.lines = const [],
    this.lineColor,
    this.height = kKuteTrendPlotHeight,
    this.live = true,
    this.emptyCaption,
    this.onScrub,
    this.onScrubStart,
    this.rangeLabels,
    this.selectedRange = 0,
    this.onRangeSelected,
  }) : assert(times == null || times.length == values.length);

  @override
  State<KuteTrendChart> createState() => _KuteTrendChartState();
}

class _KuteTrendChartState extends State<KuteTrendChart>
    with TickerProviderStateMixin {
  int? _touchIndex;
  DateTime _lastHaptic = DateTime(0);
  bool _scrubStartReported = false;
  bool _reduceMotion = false;
  bool _entranceStarted = false;

  /// The first paint: 0 → 1 across the width.
  late final AnimationController _drawIn =
      AnimationController(vsync: this, duration: kKuteTrendDrawIn);
  late final Animation<double> _drawInCurve =
      CurvedAnimation(parent: _drawIn, curve: KuteMotion.settle);

  /// Another series: the line tweens between the two, resampled.
  late final AnimationController _morph =
      AnimationController(vsync: this, duration: KuteMotion.chipDuration);
  late final Animation<double> _morphCurve =
      CurvedAnimation(parent: _morph, curve: KuteMotion.chip);
  List<double>? _morphFrom;
  List<double>? _morphTo;

  /// The live dot's breath, looping.
  late final AnimationController _breath =
      AnimationController(vsync: this, duration: kKuteTrendBreath);

  bool get _morphActive => _morphFrom != null && _morph.value < 1.0;

  @override
  void initState() {
    super.initState();
    _morph.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _morphFrom = null;
        _morphTo = null;
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = KuteMotion.reduce(context);
    if (!_entranceStarted) {
      _entranceStarted = true;
      if (_reduceMotion) {
        _drawIn.value = 1.0;
      } else {
        _drawIn.forward();
      }
    }
    _syncBreath();
  }

  @override
  void didUpdateWidget(covariant KuteTrendChart old) {
    super.didUpdateWidget(old);
    _syncBreath();
    if (_touchIndex != null && _touchIndex! >= widget.values.length) {
      _touchIndex = null;
    }
    if (kuteSameSeries(old.values, widget.values) &&
        old.values.length == widget.values.length) {
      return;
    }
    if (_reduceMotion || old.values.length < 2 || widget.values.length < 2) {
      if (_morphActive) _morph.value = 1.0;
      return;
    }
    // From where the line is now (mid-morph included) to the new series.
    final from = _morphActive
        ? kuteLerpSeries(_morphFrom!, _morphTo!, _morphCurve.value)
        : kuteResampleSeries(old.values, kKuteTrendMorphSamples);
    _morphFrom = from;
    _morphTo = kuteResampleSeries(widget.values, kKuteTrendMorphSamples);
    _morph.forward(from: 0);
  }

  void _syncBreath() {
    final breathe =
        widget.live && !_reduceMotion && widget.values.isNotEmpty;
    if (breathe && !_breath.isAnimating) {
      _breath.repeat();
    } else if (!breathe && _breath.isAnimating) {
      _breath.stop();
      _breath.value = 0;
    }
  }

  @override
  void dispose() {
    _drawIn.dispose();
    _morph.dispose();
    _breath.dispose();
    super.dispose();
  }

  // ── scrub ──────────────────────────────────────────────────────────

  void _scrubTo(double dx, double width) {
    final n = widget.values.length;
    // The points sit on the painter's width (the end dot's inset kept).
    final plotW = width - _kRightInset;
    if (n == 0 || plotW <= 0) return;
    final x = dx.clamp(0.0, plotW);
    final idx = n == 1
        ? 0
        : (x / plotW * (n - 1)).round().clamp(0, n - 1).toInt();
    if (idx == _touchIndex) return;
    if (!_scrubStartReported) {
      _scrubStartReported = true;
      widget.onScrubStart?.call();
    }
    final now = DateTime.now();
    if (now.difference(_lastHaptic).inMilliseconds > 100) {
      HapticFeedback.selectionClick();
      _lastHaptic = now;
    }
    setState(() => _touchIndex = idx);
    widget.onScrub?.call(KuteTrendPoint(
        index: idx, value: widget.values[idx], time: widget.times?[idx]));
  }

  void _endScrub() {
    _scrubStartReported = false;
    if (_touchIndex == null) return;
    setState(() => _touchIndex = null);
    widget.onScrub?.call(null);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final values = widget.values;
    final hasHistory = values.isNotEmpty;
    final lineColor = widget.lineColor ??
        (hasHistory
            ? kuteTrendResultColor(c, values.first, values.last)
            : c.textPrimary);
    final interactive = widget.onScrub != null && hasHistory;

    if (!hasHistory) {
      final caption = widget.emptyCaption;
      if (caption == null) return const SizedBox.shrink();
      return Padding(
        padding: EdgeInsets.only(top: 4.h),
        child: Text(
          caption,
          key: const ValueKey('trend-chart-empty'),
          style: TextStyle(
            color: c.textSecondary,
            fontSize: 12.sp,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    final plot = LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final ti = _touchIndex;
      final scrubbing = interactive && ti != null && ti < values.length;
      Widget canvas = AnimatedBuilder(
        animation: Listenable.merge([_drawIn, _morph, _breath]),
        builder: (context, _) {
          final morphed = _morphActive
              ? kuteLerpSeries(_morphFrom!, _morphTo!, _morphCurve.value)
              : null;
          return CustomPaint(
            size: Size(width, widget.height),
            painter: _KuteTrendPainter(
              values: morphed ?? values,
              startValue: values.first,
              lines: morphed == null ? widget.lines : const [],
              lineColor: lineColor,
              hairlineColor: c.border,
              surfaceColor: c.surface,
              drawIn: _drawInCurve.value,
              breath: widget.live && !_reduceMotion
                  ? math.sin(_breath.value * math.pi).abs()
                  : 0,
              scrubIndex: scrubbing ? ti : null,
              scrubHairline: c.textTertiary,
            ),
          );
        },
      );
      if (interactive) {
        canvas = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) => _scrubTo(d.localPosition.dx, width),
          onHorizontalDragUpdate: (d) => _scrubTo(d.localPosition.dx, width),
          onHorizontalDragEnd: (_) => _endScrub(),
          onHorizontalDragCancel: _endScrub,
          onLongPressStart: (d) => _scrubTo(d.localPosition.dx, width),
          onLongPressMoveUpdate: (d) => _scrubTo(d.localPosition.dx, width),
          onLongPressEnd: (_) => _endScrub(),
          onLongPressCancel: _endScrub,
          child: canvas,
        );
      }
      return canvas;
    });

    final labels = widget.rangeLabels;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          key: const ValueKey('trend-chart-plot'),
          height: widget.height,
          child: RepaintBoundary(child: plot),
        ),
        if (labels != null) ...[
          SizedBox(height: kKuteTrendRangeGap.h),
          KuteChartRangeRow(
            key: const ValueKey('trend-chart-ranges'),
            labels: labels,
            selectedIndex: widget.selectedRange,
            onSelected: widget.onRangeSelected ?? (_) {},
          ),
        ],
      ],
    );
  }
}

/// Inset on the right so the end dot (breathing) stays whole.
const double _kRightInset = 6;

class _KuteTrendPainter extends CustomPainter {
  final List<double> values;
  final double startValue;
  final List<KuteTrendLine> lines;
  final Color lineColor;
  final Color hairlineColor;
  final Color surfaceColor;
  final double drawIn;
  final double breath;
  final int? scrubIndex;
  final Color scrubHairline;

  const _KuteTrendPainter({
    required this.values,
    required this.startValue,
    required this.lines,
    required this.lineColor,
    required this.hairlineColor,
    required this.surfaceColor,
    required this.drawIn,
    required this.breath,
    required this.scrubIndex,
    required this.scrubHairline,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n == 0 || size.width <= 0 || size.height <= 0) return;
    final plotW = size.width - _kRightInset;
    // The scale: every value on screen and the start, a tenth free above
    // and below, a flat line centred.
    var lo = startValue, hi = startValue;
    for (final v in values) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    for (final l in lines) {
      for (final v in l.values) {
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
    }
    if (hi - lo < 1e-9) {
      final pad = hi.abs() > 1e-9 ? hi.abs() * 0.1 : 1.0;
      lo -= pad;
      hi += pad;
    }
    final span = hi - lo;
    final pad = span * 0.1;
    lo -= pad;
    hi += pad;
    final top = 6.0, bottom = size.height - 6.0;
    double yOf(double v) => bottom - (v - lo) / (hi - lo) * (bottom - top);
    double xOf(int i, int count) =>
        count <= 1 ? plotW : i / (count - 1) * plotW;

    // The reference: a dashed hairline at the period's first value.
    final yStart = yOf(startValue);
    final hair = Paint()
      ..color = hairlineColor
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (var x = 0.0; x < size.width; x += 6) {
      canvas.drawLine(Offset(x, yStart),
          Offset(math.min(x + 3, size.width), yStart), hair);
    }

    // What has been drawn so far of the first paint.
    final reveal = Rect.fromLTWH(0, 0, size.width * drawIn, size.height);
    canvas.save();
    canvas.clipRect(reveal);

    // The extra lines, under the main one.
    for (final l in lines) {
      if (l.values.length < 2) continue;
      final pts = [
        for (var i = 0; i < l.values.length; i++)
          Offset(xOf(i, l.values.length), yOf(l.values[i]))
      ];
      canvas.drawPath(
          kuteMonotonePath(pts), kuteStrokePaint(l.color, width: 1.5));
    }

    final pts = [for (var i = 0; i < n; i++) Offset(xOf(i, n), yOf(values[i]))];
    final path = kuteMonotonePath(pts);

    // The fill: 18% of the line colour fading to nothing, behind the
    // line, fading in with the draw.
    if (n >= 2) {
      final fill = Path.from(path)
        ..lineTo(pts.last.dx, size.height)
        ..lineTo(pts.first.dx, size.height)
        ..close();
      final shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          lineColor.withValues(alpha: 0.18 * drawIn),
          lineColor.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromLTWH(0, top, size.width, size.height - top));
      canvas.drawPath(fill, Paint()..shader = shader);
    }
    canvas.drawPath(path, kuteStrokePaint(lineColor, width: 2));
    canvas.restore();

    // The last point: a dot, breathing while live.
    if (drawIn >= 1) {
      final end = pts.last;
      final r = 4 * (1 + 0.35 * breath);
      if (breath > 0) {
        canvas.drawCircle(end, r * 1.8,
            Paint()..color = lineColor.withValues(alpha: 0.12 * breath));
      }
      canvas.drawCircle(end, r, Paint()..color = lineColor);
    }

    // The scrub: a hairline and an 8 px dot on the line.
    final si = scrubIndex;
    if (si != null && si >= 0 && si < n) {
      final p = pts[si];
      canvas.drawLine(
          Offset(p.dx, 0),
          Offset(p.dx, size.height),
          Paint()
            ..color = scrubHairline
            ..strokeWidth = 1);
      canvas.drawCircle(p, 6, Paint()..color = surfaceColor);
      canvas.drawCircle(p, 4, Paint()..color = lineColor);
    }
  }

  @override
  bool shouldRepaint(covariant _KuteTrendPainter old) =>
      !identical(old.values, values) ||
      old.startValue != startValue ||
      old.lines != lines ||
      old.lineColor != lineColor ||
      old.hairlineColor != hairlineColor ||
      old.drawIn != drawIn ||
      old.breath != breath ||
      old.scrubIndex != scrubIndex;
}

/// The range row under a chart: small 12 sp text pills sharing the width,
/// the picked one the home strip's small white pill (the hairline, the
/// shadow) sliding to its slot on the chip spring. Reduce Motion: it
/// jumps.
class KuteChartRangeRow extends StatelessWidget {
  const KuteChartRangeRow({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    this.height = 28,
  });

  final List<String> labels;
  final int selectedIndex;

  /// Called with the index tapped, the picked one included.
  final ValueChanged<int> onSelected;

  /// The row's height, in design points.
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final reduce = KuteMotion.reduce(context);
    final n = labels.length;
    if (n == 0) return const SizedBox.shrink();
    final picked = selectedIndex.clamp(0, n - 1);
    final h = height.h;
    final base = DefaultTextStyle.of(context).style;
    return SizedBox(
      height: h,
      child: LayoutBuilder(builder: (context, constraints) {
        final slot = constraints.maxWidth / n;
        return Stack(
          children: [
            AnimatedPositioned(
              duration: reduce ? Duration.zero : KuteMotion.chipDuration,
              curve: reduce ? Curves.linear : KuteMotion.chip,
              left: slot * picked,
              top: 0,
              width: slot,
              height: h,
              child: Container(
                key: const ValueKey('range-row-thumb'),
                decoration: BoxDecoration(
                  color: isLight ? Colors.white : c.surface,
                  borderRadius: BorderRadius.circular(h / 2),
                  border: Border.all(
                    color: isLight ? c.border : c.borderSubtle,
                    width: isLight ? 1.0 : 0.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isLight
                          ? Colors.black.withValues(alpha: 0.04)
                          : Colors.transparent,
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
            Row(
              children: [
                for (var i = 0; i < n; i++)
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: i == picked,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onSelected(i),
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: reduce
                                ? Duration.zero
                                : const Duration(milliseconds: 150),
                            style: base.merge(TextStyle(
                              color:
                                  i == picked ? c.textPrimary : c.textTertiary,
                              fontSize: 12.sp,
                              fontWeight: i == picked
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              height: 1.0,
                            )),
                            child: Text(labels[i], maxLines: 1),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      }),
    );
  }
}
