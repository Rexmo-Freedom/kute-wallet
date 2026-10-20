// lib/screens/polymarket/components/position_chance_gauge.dart
//
// The open-position screen's chance gauge: the chance bar
// (position_chance_bar.dart) bent into a half circle, for the position
// detail screen of a bet that is still open (a live price, not settled).
// A settled position keeps the bar, and every list and row keeps it too.
//
// It is the screen's hero: the whole content width. It draws what the
// bar draws, from the same [PolyChanceBarSpec]:
//   * a thick 180° arc with round ends: a Yes / No or Up / Down market's
//     green from the left end up to the split, then red, each side ending
//     round with a small gap between them; any other outcome's own colour
//     on the neutral track;
//   * a knob at the split (the screen's surface ringed in white);
//   * a short white tick across the arc at the price paid, with a small
//     quiet "Bought · 54¢" label just outside the arc beside it: pushed
//     straight out from the tick, never on the arc, never cut (where the
//     width leaves no room beside an end, under it; higher up, lifted
//     just clear of the arc);
//   * the held outcome's chance, large, inside the arc ("75.8%"), the
//     localised "chance" wording under it, both cut from the one
//     `betPercentChance` string.
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

/// How high (sin of the angle) a tick still counts as at an end of the
/// arc: the first and last 10% of it (10% and 90% themselves included,
/// past the float's rounding).
final double _endBand = math.sin(math.pi * 0.1) + 1e-9;

/// The angle of [fraction] (0 to 1 from the left) along the half circle.
double polyGaugeAngle(double fraction) =>
    math.pi + fraction.clamp(0.0, 1.0) * math.pi;

/// The fill's sweep for [value] (0 to 1 from the left).
double polyGaugeSweep(double value) => value.clamp(0.0, 1.0) * math.pi;

/// Lays the gauge out across [width]: an arc of [outerRadius] and
/// [stroke], centred; the tick ([tick], 0 to 1 from the left) running
/// [overhang] past both edges of the arc; the tag of [tag] size pushed
/// out from the tick's outer end by [gap], along the tick; and
/// [belowCenter] of room under the arc's centre line (the knob at an
/// end). The box is as tall as all of that, and no taller.
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
  var bottom = math.max(stroke / 2, belowCenter);
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
    // Inside the width.
    final half = width / 2;
    final minX = -half + tag.width / 2;
    final maxX = math.max(minX, half - tag.width / 2);
    var dx = c.dx.clamp(minX, maxX).toDouble();
    var dy = c.dy;
    if ((dx - c.dx).abs() > 0.5) {
      // Pulled in from the side: the dial is wider than the room a tag
      // needs beside it (a large dial on a phone, a large text size).
      if (u.dy.abs() <= _endBand) {
        // Near an end (0–10%, 90–100%): under the arc's end, centred on
        // it, just below the round cap.
        dx = (u.dx.sign * radius).clamp(minX, maxX).toDouble();
        // Under whatever sits at the arc's end (the round cap, the knob
        // at 0% or 100%).
        dy = math.max(stroke / 2, belowCenter) + gap + tag.height / 2;
      } else {
        // Higher up: lifted only as far as clears the arc and the tick
        // (the tag's nearest corner just past the tick's reach).
        final near = math.max(0.0, dx.abs() - tag.width / 2);
        final clear =
            near >= reach ? 0.0 : math.sqrt(reach * reach - near * near);
        dy = math.min(dy, -(clear + tag.height / 2));
      }
    }
    label = Rect.fromCenter(
        center: Offset(dx, dy), width: tag.width, height: tag.height);
    top = math.min(top, label.top);
    bottom = math.max(bottom, label.bottom);
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

  /// The tick's quiet label ("Bought · 54¢"); none without a tick.
  final String? tickLabel;

  static const gaugeKey = ValueKey('poly-chance-gauge');
  static const paintKey = ValueKey('poly-chance-gauge-paint');
  static const labelKey = ValueKey('poly-chance-gauge-label');
  static const figureKey = ValueKey('poly-chance-gauge-figure');
  static const captionKey = ValueKey('poly-chance-gauge-caption');

  /// How far the tick runs past both edges of the arc, and the room
  /// between its outer end and the label.
  static const double _overhang = 3;
  static const double _gap = 4;

  /// The tick's label: small and quiet, no box.
  static TextStyle _tagStyle(Color color) => TextStyle(
        color: color,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1.2,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final scaler =
        MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    final tick = spec.tick;
    final label = tick == null ? null : tickLabel;
    final labelStyle = _tagStyle(c.textSecondary);

    final figureText = formatPolyChanceFigure(chance);
    final full = l10n.betPercentChance(figureText);
    final parts = polyGaugeChanceParts(full, figureText);
    final captionStyle = TextStyle(
      color: c.textTertiary,
      fontSize: 14.sp,
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
        tag = Size(math.min(w, tp.width + 4), tp.height + 2);
        tp.dispose();
      }
      // The hero of the screen: the whole content width (the tick's ends
      // just inside it), capped on tablets. A label at an end goes beside
      // the arc where the width leaves room (a tablet), under the arc's
      // end where it does not (polyChanceGaugeGeometry).
      final double outerRadius =
          (w / 2 - _overhang).clamp(math.min(60.0, w / 4), 190.0).toDouble();
      final stroke = (outerRadius * 0.095).clamp(10.0, 18.0).toDouble();
      final knob = polyGaugeKnobRadius(stroke);
      final figureStyle = TextStyle(
        color: c.textPrimary,
        fontSize: (outerRadius * 0.33).clamp(30.0, 56.0).toDouble(),
        fontWeight: FontWeight.w800,
        letterSpacing: -1.0,
        height: 1.0,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
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
      final g = polyChanceGaugeGeometry(
        width: w,
        outerRadius: outerRadius,
        stroke: stroke,
        overhang: _overhang,
        gap: _gap,
        // The knob at 0% or 100% hangs under the arc's end.
        belowCenter: knob + 1.5,
        tick: tick,
        tag: label == null ? null : tag,
      );
      final inner = g.radius - stroke / 2;
      final labelRect = g.labelRect;
      final semantics = label == null ? full : '$full, $label';
      // The caption just above the arc's centre line, the chance on it.
      final captionBottom = g.size.height - g.center.dy + 2;
      final figureBottom = captionBottom + captionH + 2;

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
                        knobFill: context.isDark ? c.background : c.surface,
                      ),
                    ),
                  ),
                ),
                // The chance, large, inside the arc.
                Positioned(
                  key: figureKey,
                  left: g.center.dx - inner * 0.8,
                  width: inner * 1.6,
                  bottom: figureBottom,
                  height: inner * 0.5,
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
                    left: g.center.dx - inner * 0.8,
                    width: inner * 1.6,
                    bottom: captionBottom,
                    height: captionH,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.bottomCenter,
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
              ],
            ),
          ),
        ),
      );
    });
  }
}

/// The knob's radius on an arc of [stroke]: a little wider than the arc,
/// so it reads as the dial's needle.
double polyGaugeKnobRadius(double stroke) => stroke * 0.72;

/// Paints the arc, its fill, the knob at the chance and the tick at the
/// price paid, of a [PolyChanceGaugeGeometry].
class PolyChanceGaugePainter extends CustomPainter {
  PolyChanceGaugePainter({
    required this.geometry,
    required this.value,
    required this.fill,
    required this.track,
    required this.split,
    required this.tickColor,
    required this.knobFill,
  });

  final PolyChanceGaugeGeometry geometry;

  /// The fill or split point, 0 to 1 from the left.
  final double value;
  final Color fill;
  final Color track;

  /// A two-tone split: the fill and the other side each end round, a
  /// small gap between them under the knob. Otherwise the fill runs on
  /// the whole neutral track, as on the bar.
  final bool split;

  /// The tick's colour and the knob's ring.
  final Color tickColor;

  /// The knob's middle: the screen's own dark (or light) surface.
  final Color knobFill;

  /// Where the fill starts and how far it sweeps (canvas radians).
  ({double start, double sweep}) get fillArc =>
      (start: math.pi, sweep: polyGaugeSweep(value));

  @override
  void paint(Canvas canvas, Size size) {
    final g = geometry;
    final rect = Rect.fromCircle(center: g.center, radius: g.radius);
    Paint arc(Color color) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = g.stroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true
      ..color = color;

    final v = value.clamp(0.0, 1.0).toDouble();
    if (!split) {
      canvas.drawArc(rect, math.pi, math.pi, false, arc(track));
      if (v > 0) canvas.drawArc(rect, math.pi, polyGaugeSweep(v), false, arc(fill));
    } else if (v <= 0) {
      canvas.drawArc(rect, math.pi, math.pi, false, arc(track));
    } else if (v >= 1) {
      canvas.drawArc(rect, math.pi, math.pi, false, arc(fill));
    } else {
      // Each side ends round, the gap between them (both caps and a
      // little air) under the knob.
      final half = (g.stroke / 2 + 2) / g.radius;
      final at = polyGaugeSweep(v);
      if (at - half > 0) {
        canvas.drawArc(rect, math.pi, at - half, false, arc(fill));
      }
      if (math.pi - at - half > 0) {
        canvas.drawArc(
            rect, math.pi + at + half, math.pi - at - half, false, arc(track));
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
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true,
      );
    }

    // The knob at the chance: the screen's surface ringed in white.
    final k = polyGaugeAngle(v);
    final at = g.center + Offset(math.cos(k), math.sin(k)) * g.radius;
    final r = polyGaugeKnobRadius(g.stroke);
    canvas.drawCircle(
        at,
        r,
        Paint()
          ..color = knobFill
          ..isAntiAlias = true);
    canvas.drawCircle(
        at,
        r - 1.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = tickColor
          ..isAntiAlias = true);
  }

  @override
  bool shouldRepaint(PolyChanceGaugePainter old) =>
      old.geometry != geometry ||
      old.value != value ||
      old.fill != fill ||
      old.track != track ||
      old.split != split ||
      old.tickColor != tickColor ||
      old.knobFill != knobFill;
}
