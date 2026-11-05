// lib/screens/polymarket/components/game_side_button.dart
//
// One side of a game's line, as a button: the side's name on top and its
// live chance under it. The one button of a game's page, so the board's
// tiles (Winner, Spread, Total) and the two sides of every "More markets"
// row read as the same thing (founder, 5 November 2026: "the line items
// are now a bit different, so fix it please").
//
//   * Neutral: the surface card with its hairline border, the name in the
//     secondary colour and the chance in [accent] (the primary text
//     colour unless a team's own colour is asked for). No tints: the app
//     has no tinted chips (founder, 1 November 2026).
//   * On a line the chart draws ([lineColor]): a solid slab of that
//     line's colour ([polyOutcomeFill]) with white text, the weight of
//     the Up / Down buttons, so the side reads as its line.
//   * [dense]: a "More markets" row's pair, a step down from the board's
//     tiles (46 high against 62, 12 corners against 16, 11.5 / 15 sp
//     against 13 / 18).
//   * [muted]: a line that is settled or not trading yet; its figures in
//     the tertiary colour, still a button.
//
// Press language (scale 0.97, medium haptic, reduce-motion aware) matches
// `MarketPairButton`.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/screens/polymarket/components/outcome_leading.dart'
    show polyOutcomeFill;
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/theme/app_theme.dart';

class PolyGameSideButton extends StatefulWidget {
  final String label;

  /// The side's crest (a team's badge or flag), before its name.
  final String? crestUrl;
  final String pctText;

  /// The chance's colour on the neutral card; the primary text colour
  /// when null.
  final Color? accent;

  /// The colour of this side's line on the chart above. When set the
  /// button is a solid slab of it ([polyOutcomeFill]) with white text.
  final Color? lineColor;

  /// A "More markets" row's pair: smaller than the board's tiles.
  final bool dense;

  /// A settled line, or one not trading yet: quiet figures.
  final bool muted;

  /// What screen readers hear; the name and the chance when null.
  final String? semanticLabel;
  final VoidCallback onTap;

  const PolyGameSideButton({
    super.key,
    required this.label,
    this.crestUrl,
    required this.pctText,
    this.accent,
    this.lineColor,
    this.dense = false,
    this.muted = false,
    this.semanticLabel,
    required this.onTap,
  });

  @override
  State<PolyGameSideButton> createState() => _PolyGameSideButtonState();
}

class _PolyGameSideButtonState extends State<PolyGameSideButton> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final line = widget.lineColor;
    final fill = line == null ? null : polyOutcomeFill(line);
    final dense = widget.dense;
    final radius = BorderRadius.circular((dense ? 12 : 16).r);
    final labelColor = fill != null
        ? Colors.white
        : widget.muted
            ? c.textTertiary
            : c.textSecondary;
    final figureColor = fill != null
        ? Colors.white
        : widget.muted
            ? c.textTertiary
            : (widget.accent ?? c.textPrimary);
    return Semantics(
      button: true,
      label: widget.semanticLabel ?? '${widget.label} ${widget.pctText}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        onTap: () {
          HapticFeedback.mediumImpact();
          widget.onTap();
        },
        child: AnimatedScale(
          scale: (_pressed && !reduceMotion) ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeInOut,
          child: Container(
            height: (dense ? 46 : 62).h,
            padding: EdgeInsets.symmetric(horizontal: 6.w),
            decoration: fill == null
                ? BoxDecoration(
                    color: c.surface,
                    borderRadius: radius,
                    border: Border.all(color: c.borderSubtle, width: 0.5),
                  )
                // MarketPairButton's slab: the solid fill with a faint top
                // highlight so it reads as pressable, not flat paint.
                : BoxDecoration(
                    color: fill,
                    borderRadius: radius,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color.alphaBlend(
                            Colors.white.withValues(alpha: 0.08), fill),
                        fill,
                      ],
                      stops: const [0.0, 0.55],
                    ),
                  ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.crestUrl != null &&
                        widget.crestUrl!.isNotEmpty) ...[
                      PolyCrestImage(
                        url: widget.crestUrl!,
                        size: (dense ? 13 : 16).sp,
                        radius: 4.r,
                        fit: BoxFit.contain,
                        fallback: const SizedBox.shrink(),
                      ),
                      SizedBox(width: 5.w),
                    ],
                    Flexible(
                      child: () {
                        final text = Text(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            // Full white on a slab: the fill is set for
                            // 4.5:1 on it.
                            color: labelColor,
                            fontSize: (dense ? 11.5 : 13).sp,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.1,
                            height: 1.15,
                          ),
                        );
                        // A row's button is narrow: a long name ("Hull
                        // City +1.5") shrinks a little rather than lose
                        // its line.
                        return dense
                            ? FittedBox(fit: BoxFit.scaleDown, child: text)
                            : text;
                      }(),
                    ),
                  ],
                ),
                SizedBox(height: (dense ? 2 : 3).h),
                RollingNumberText(
                  text: widget.pctText,
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 250),
                  style: TextStyle(
                    color: figureColor,
                    fontSize: (dense ? 15 : 18).sp,
                    fontWeight: FontWeight.w800,
                    letterSpacing: dense ? -0.2 : -0.4,
                    height: 1.0,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
