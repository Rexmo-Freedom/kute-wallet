// lib/screens/polymarket/components/position_chance_gauge.dart
//
// The open-position screen's chance gauge: the chance bar
// (position_chance_bar.dart) bent into a half circle, for the position
// detail screen of a bet that is still open (a live price, not settled).
// A settled position keeps the bar, and every list and row keeps it too.
//
// It draws what the bar draws, from the same [PolyChanceBarSpec]:
//   * a 180° arc with round ends, the bar's track colour under the bar's
//     fill colour, filled from the left end up to the chance (a Yes / No
//     or Up / Down market keeps its green and red split, meeting square);
//   * a short radial tick at the price paid, in the bar's tick colour,
//     with the bar's "Bought · 54¢" tag just outside the arc beside it:
//     pushed straight out from the tick, so at 0–10% it sits to the left
//     of the arc's end and at 90–100% to its right, never on the arc;
//   * the held outcome's chance in the middle ("75.8%"), the localised
//     "chance" wording under it, both cut from the one `betPercentChance`
//     string, so the figure above the gauge does not repeat it.
//
// The fill eases to a new price over the bar's 300 ms, easeOutCubic,
// still under reduced motion. Nothing here is logged.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/polymarket/components/position_chance_bar.dart'
    show PolyChanceBarSpec;
import 'package:kute/screens/polymarket/components/price_format.dart'
    show formatPolyChanceFigure;
import 'package:kute/screens/shared/charts/kute_chart_core.dart'
    show kuteChartFontFamily;
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/theme/app_theme.dart';

/// Where everything of the gauge sits, in the gauge's own box.
typedef PolyChanceGaugeGeometry = ({
  Size size,
  Offset center,

  /// The arc's centre line.
  double radius,
  double stroke,

  /// The tick's two ends, from the centre.
  double tickInner,
  double tickOuter,

  /// The tick's angle (canvas radians: π at the left end, 3π/2 at the
  /// top, 2π at the right end); null without a tick.
  double? tickAngle,

  /// The "Bought" tag; null without a tick or a tag.
  Rect? labelRect,
});

/// The angle of [fraction] (0 to 1 from the left) along the half circle.
double polyGaugeAngle(double fraction) =>
    math.pi + fraction.clamp(0.0, 1.0) * math.pi;

/// The fill's sweep for [value] (0 to 1 from the left).
double polyGaugeSweep(double value) => value.clamp(0.0, 1.0) * math.pi;

/// Lays the gauge out across [width]: an arc of [outerRadius] and
/// [stroke], centred; the tick ([tick], 0 to 1 from the left) running
/// [overhang] past both edges of the arc; the tag of [tag] size pushed
/// out from the tick's outer end by [gap], along the tick; and
/// [belowCenter] of room under the arc's centre for the caption. The box
/// is as tall as all of that, and no taller.
PolyChanceGaugeGeometry polyChanceGaugeGeometry({
  required double width,
  required double outerRadius,
  required double stroke,
  double overhang = 3,
  double gap = 2,
  double belowCenter = 0,
  double? tick,
  Size? tag,
}) {
  final radius = outerRadius - stroke / 2;
  final tickOuter = outerRadius + overhang;
  final tickInner = math.max(0.0, outerRadius - stroke - overhang);
  final tickAngle = tick == null ? null : polyGaugeAngle(tick);

  // Laid out about the centre first, then moved into the box.
  var top = -(tick == null ? outerRadius : tickOuter);
  final bottom = math.max(stroke / 2, belowCenter);
  Rect? label;
  if (tickAngle != null && tag != null) {
    final u = Offset(math.cos(tickAngle), math.sin(tickAngle));
    // The tag's nearest side touches a point just past the tick's end,
    // straight out from the centre: all of it lies beyond that point
    // along the tick, so clear of the arc and the tick at any price.
    final reach = tickOuter + gap;
    final push = tag.width / 2 * u.dx.abs() + tag.height / 2 * u.dy.abs();
    var c = u * (reach + push);
    // Never under the box: an end tag sits level with the arc's end.
    final lowest = bottom - tag.height / 2;
    if (c.dy > lowest) c = Offset(c.dx, lowest);
    // Inside the width (the tag is narrow; the gauge leaves room).
    final half = width / 2;
    final dx = c.dx.clamp(-half + tag.width / 2,
        math.max(-half + tag.width / 2, half - tag.width / 2));
    label = Rect.fromCenter(
        center: Offset(dx.toDouble(), c.dy),
        width: tag.width,
        height: tag.height);
    top = math.min(top, label.top);
  }
  final center = Offset(width / 2, -top);
  return (
    size: Size(width, bottom - top),
    center: center,
    radius: radius,
    stroke: stroke,
    tickInner: tickInner,
    tickOuter: tickOuter,
    tickAngle: tickAngle,
    labelRect: label?.shift(center),
  );
}

/// The figure and the caption of [full] (`betPercentChance` of [figure]):
/// the figure with its own "%" ("75.8%", "75.8 %"), and the rest of the
/// sentence in any order ("chance", "de chances", "Szansa", "確率").
({String figure, String caption}) polyGaugeChanceParts(
    String full, String figure) {
  final at = full.indexOf(figure);
  if (at < 0) return (figure: full, caption: '');
  final before = full.substring(0, at);
  var after = full.substring(at + figure.length);
  final pct = RegExp('^[   ]?%').firstMatch(after);
  final shown = '$figure${pct?.group(0) ?? ''}';
  after = after.substring(pct?.end ?? 0);
  final caption = '$before $after'.replaceAll(RegExp(r'\s+'), ' ').trim();
  return (figure: shown, caption: caption);
}

class PolyPositionChanceGauge extends StatelessWidget {
  const PolyPositionChanceGauge({
    super.key,
    required this.spec,
    required this.chance,
    this.tickLabel,
  });

  /// The bar's own spec: fill or split point, colours and tick.
  final PolyChanceBarSpec spec;

  /// The held outcome's chance (0 to 1), written in the middle. Not
  /// [spec]'s value: a No / Down side's fill runs from the Yes / Up end.
  final double chance;

  /// The tick's tag ("Bought · 54¢"); none without a tick.
  final String? tickLabel;

  static const gaugeKey = ValueKey('poly-chance-gauge');
  static const paintKey = ValueKey('poly-chance-gauge-paint');
  static const labelKey = ValueKey('poly-chance-gauge-label');
  static const figureKey = ValueKey('poly-chance-gauge-figure');
  static const captionKey = ValueKey('poly-chance-gauge-caption');

  /// The chart's tag text style, as on the bar.
  static TextStyle _tagStyle(Color color) => TextStyle(
        fontFamily: kuteChartFontFamily,
        color: color,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        height: 1.2,
      );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDark = context.isDark;
    final l10n = context.l10n;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final scaler =
        MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    final outerRadius = 42.h;
    final stroke = 10.h;
    final overhang = 3.h;
    final gap = 2.h;
    final tick = spec.tick;
    final label = tick == null ? null : tickLabel;
    final labelStyle = _tagStyle(spec.held);

    final figureText = formatPolyChanceFigure(chance);
    final full = l10n.betPercentChance(figureText);
    final parts = polyGaugeChanceParts(full, figureText);
    final figureStyle = TextStyle(
      color: c.textPrimary,
      fontSize: 20.sp,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.6,
      height: 1.0,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final captionStyle = TextStyle(
      color: c.textTertiary,
      fontSize: 11.sp,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
      height: 1.2,
    );

    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      Size? tag;
      if (label != null) {
        final tp = TextPainter(
          text: TextSpan(text: label, style: labelStyle),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
          maxLines: 1,
        )..layout(maxWidth: w);
        tag = Size(math.min(w, tp.width + 10), tp.height + 5);
        tp.dispose();
      }
      double captionH = 0;
      if (parts.caption.isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(text: parts.caption, style: captionStyle),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        captionH = tp.height;
        tp.dispose();
      }
      final captionGap = 2.h;
      final g = polyChanceGaugeGeometry(
        width: w,
        outerRadius: outerRadius,
        stroke: stroke,
        overhang: overhang,
        gap: gap,
        belowCenter: captionH == 0 ? 0 : captionGap + captionH,
        tick: tick,
        tag: label == null ? null : tag,
      );
      final inner = g.radius - stroke / 2;
      final labelRect = g.labelRect;
      final semantics = label == null ? full : '$full, $label';

      return Semantics(
        container: true,
        label: semantics,
        child: ExcludeSemantics(
          child: SizedBox(
            key: gaugeKey,
            width: g.size.width,
            height: g.size.height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: TweenAnimationBuilder<double>(
                    // begin == end: no grow-in on open; a new price eases
                    // from where the fill is (the bar's own motion).
                    tween: Tween(begin: spec.value, end: spec.value),
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) => CustomPaint(
                      key: paintKey,
                      painter: PolyChanceGaugePainter(
                        geometry: g,
                        value: v,
                        fill: spec.left,
                        track: spec.right ?? c.border,
                        split: spec.right != null,
                        tickColor: c.textPrimary,
                      ),
                    ),
                  ),
                ),
                // The chance, sitting on the arc's centre line, inside it.
                Positioned(
                  key: figureKey,
                  left: g.center.dx - inner * 0.86,
                  width: inner * 1.72,
                  bottom: g.size.height - g.center.dy,
                  height: inner * 0.62,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.bottomCenter,
                    child: RollingNumberText(
                      text: parts.figure,
                      style: figureStyle,
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 250),
                    ),
                  ),
                ),
                if (parts.caption.isNotEmpty)
                  Positioned(
                    key: captionKey,
                    left: g.center.dx - outerRadius,
                    width: outerRadius * 2,
                    top: g.center.dy + captionGap,
                    height: captionH,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topCenter,
                      child: Text(
                        parts.caption,
                        style: captionStyle,
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ),
                  ),
                if (labelRect != null)
                  Positioned.fromRect(
                    key: labelKey,
                    rect: labelRect,
                    // The chart's "Bought" tag, as on the bar.
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: (isDark ? Colors.black : Colors.white)
                            .withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: spec.held.withValues(alpha: 0.7), width: 1),
                      ),
                      child: Center(
                        child: Text(
                          label!,
                          style: labelStyle,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          softWrap: false,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

/// Paints the arc, its fill and the tick of a [PolyChanceGaugeGeometry].
class PolyChanceGaugePainter extends CustomPainter {
  PolyChanceGaugePainter({
    required this.geometry,
    required this.value,
    required this.fill,
    required this.track,
    required this.split,
    required this.tickColor,
  });

  final PolyChanceGaugeGeometry geometry;

  /// The fill or split point, 0 to 1 from the left.
  final double value;
  final Color fill;
  final Color track;

  /// A two-tone split: the fill meets the track square. Otherwise the
  /// fill ends round on the track, as on the bar.
  final bool split;
  final Color tickColor;

  /// Where the fill starts and how far it sweeps (canvas radians).
  ({double start, double sweep}) get fillArc =>
      (start: math.pi, sweep: polyGaugeSweep(value));

  @override
  void paint(Canvas canvas, Size size) {
    final g = geometry;
    final rect = Rect.fromCircle(center: g.center, radius: g.radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = g.stroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawArc(rect, math.pi, math.pi, false, paint..color = track);

    final v = value.clamp(0.0, 1.0);
    if (v > 0) {
      paint.color = fill;
      if (split && v < 1) {
        // Round at the left end, square where it meets the other side.
        canvas.drawArc(rect, math.pi, polyGaugeSweep(v), false,
            paint..strokeCap = StrokeCap.butt);
        canvas.drawCircle(
            g.center + Offset(-g.radius, 0),
            g.stroke / 2,
            Paint()
              ..color = fill
              ..isAntiAlias = true);
      } else {
        canvas.drawArc(rect, math.pi, polyGaugeSweep(v), false,
            paint..strokeCap = StrokeCap.round);
      }
    }

    final a = g.tickAngle;
    if (a != null) {
      final u = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        g.center + u * g.tickInner,
        g.center + u * g.tickOuter,
        Paint()
          ..color = tickColor
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true,
      );
    }
  }

  @override
  bool shouldRepaint(PolyChanceGaugePainter old) =>
      old.geometry != geometry ||
      old.value != value ||
      old.fill != fill ||
      old.track != track ||
      old.split != split ||
      old.tickColor != tickColor;
}
