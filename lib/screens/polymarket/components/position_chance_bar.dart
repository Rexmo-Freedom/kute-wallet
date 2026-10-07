// lib/screens/polymarket/components/position_chance_bar.dart
//
// The open-position screen's chance bar: where the held outcome's chance
// is now against what was paid for it, in one horizontal bar. It replaces
// the price chart there, which was unreadable on a short round (a handful
// of points: a flat line, then a vertical drop) when a position only
// needs "where I am now against where I bought". The market sheet keeps
// its chart.
//
// Two shapes:
//   * a Yes / No or Up / Down market is a two-tone split: Yes / Up in the
//     app's up green from the left, No / Down in its down red from the
//     right, meeting at the Yes / Up chance;
//   * an outcome with its own line colour (a game's team, the draw of a
//     three-way market, one outcome of a many-outcome market) fills from
//     the left in that colour up to its chance, the rest the neutral
//     track.
// A thin tick marks what was paid per share, measured from the held
// side's end (holding Down bought at 54¢: 54% in from the right), under
// the chart's own "Bought · 54¢" tag. The chance itself is not written
// again: the figure above the bar already says it.
//
// The split point eases to a new price over 300 ms (still under reduced
// motion). Nothing here is logged.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/providers/polymarket_browse_provider.dart'
    show PolymarketPosition;
import 'package:kute/screens/shared/charts/kute_chart_core.dart'
    show kuteChartFontFamily;
import 'package:kute/theme/app_theme.dart';

/// What the bar draws: the fill or split point ([value], 0 to 1 from the
/// left), the colour left of it, the colour right of it (null: the
/// neutral track), the tick (0 to 1 from the left, null: none) and the
/// colour of the held side, which the tick's tag is written in.
typedef PolyChanceBarSpec = ({
  double value,
  Color left,
  Color? right,
  double? tick,
  Color held,
});

/// The bar for a position on [outcome] whose token is at [chance], paid
/// [bought] per share (null when unknown). [lineColor] is the outcome's
/// own line colour when it has one (a team, a many-outcome market's
/// outcome): a fill from the left. Otherwise Yes / Up and No / Down make
/// the green and red split; any other outcome fills in [fallbackColor].
PolyChanceBarSpec polyPositionChanceBarSpec({
  required String outcome,
  required double chance,
  double? bought,
  Color? lineColor,
  required Color fallbackColor,
}) {
  final p = chance.clamp(0.0, 1.0).toDouble();
  final b = bought == null || !(bought > 0) || bought > 1 ? null : bought;
  if (lineColor == null) {
    switch (outcome.trim().toLowerCase()) {
      case 'yes' || 'up':
        return (
          value: p,
          left: AppColors.marketUp,
          right: AppColors.marketDown,
          tick: b,
          held: AppColors.marketUp,
        );
      case 'no' || 'down':
        return (
          value: 1 - p,
          left: AppColors.marketUp,
          right: AppColors.marketDown,
          tick: b == null ? null : 1 - b,
          held: AppColors.marketDown,
        );
    }
  }
  final color = lineColor ?? fallbackColor;
  return (value: p, left: color, right: null, tick: b, held: color);
}

/// The held token's chance the bar shows: the live (or last) price while
/// the market is open; once resolved, all or nothing by the result.
double polyPositionBarChance(PolymarketPosition pos, double currentPrice) {
  if (!pos.isResolved) return currentPrice.clamp(0.0, 1.0).toDouble();
  final won = pos.won ?? currentPrice >= 0.5;
  return won ? 1.0 : 0.0;
}

class PolyPositionChanceBar extends StatelessWidget {
  const PolyPositionChanceBar({
    super.key,
    required this.spec,
    this.tickLabel,
  });

  final PolyChanceBarSpec spec;

  /// The tick's tag ("Bought · 54¢"); none without a tick.
  final String? tickLabel;

  static const fillKey = ValueKey('poly-chance-bar-fill');
  static const trackKey = ValueKey('poly-chance-bar-track');
  static const tickKey = ValueKey('poly-chance-bar-tick');
  static const labelKey = ValueKey('poly-chance-bar-label');

  /// The chart's tag text style (kute_chart_trade_lines.dart).
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
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final trackH = 12.h;
    const tickW = 2.0;
    final overhang = 3.h;
    final gap = 4.h;
    final tick = spec.tick;
    final label = tick == null ? null : tickLabel;
    final labelStyle = _tagStyle(spec.held);
    final scaler = MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;

    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      // The tag's size, to keep it inside the bar's width.
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
      final tagH = tag?.height ?? 0;
      final barTop = tag == null ? overhang : tagH + gap + overhang;
      final height = barTop + trackH + overhang;
      final tickX = tick == null
          ? null
          : (tick.clamp(0.0, 1.0) * w).clamp(tickW / 2, w - tickW / 2);
      final radius = Radius.circular(trackH / 2);
      return SizedBox(
        key: const ValueKey('poly-chance-bar'),
        width: w,
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: barTop,
              height: trackH,
              child: ClipRRect(
                key: trackKey,
                borderRadius: BorderRadius.all(radius),
                child: ColoredBox(
                  color: spec.right ?? c.border,
                  child: TweenAnimationBuilder<double>(
                    // begin == end: no grow-in on open; a new price eases
                    // from where the bar is.
                    tween: Tween(begin: spec.value, end: spec.value),
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) => Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        key: fillKey,
                        widthFactor: v.clamp(0.0, 1.0),
                        heightFactor: 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: spec.left,
                            // A split meets its other side square; a fill
                            // ends round on the track.
                            borderRadius: spec.right == null
                                ? BorderRadius.horizontal(right: radius)
                                : BorderRadius.zero,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (tickX != null)
              Positioned(
                key: tickKey,
                left: tickX - tickW / 2,
                top: barTop - overhang,
                width: tickW,
                height: trackH + overhang * 2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.textPrimary,
                    borderRadius: BorderRadius.circular(tickW / 2),
                  ),
                ),
              ),
            if (tickX != null && tag != null)
              Positioned(
                key: labelKey,
                left: (tickX - tag.width / 2)
                    .clamp(0.0, math.max(0.0, w - tag.width)),
                top: 0,
                width: tag.width,
                height: tag.height,
                // The chart's "Bought" tag: the held side's colour on the
                // page's own white or black, a hairline in that colour.
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
      );
    });
  }
}
