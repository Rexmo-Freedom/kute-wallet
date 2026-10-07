// lib/screens/shared/market_pair_button.dart
//
// The shared directional "badge" CTA used by every paired market
// button in the app: Buy/Sell and Long/Short on the Hyperliquid market
// detail sheet, Close position on the HL position detail sheet, the
// YES/NO pair on the Polymarket market detail sheet, and Up/Down on
// the 5-minute crypto cards. Replaces four private near-copies
// (`_CtaButton`, `_CloseCtaButton`, `_ActionButton`, `_UpDownButton`)
// that had drifted apart on height, radius, glow, and hex codes.
//
// Spec (the consolidated look — SOLID fills, user decision: tinted /
// duotone pair buttons were explicitly rejected):
//   * 60.h tall, 16.r corners, solid saturated fill
//   * fill from `AppColors.marketUp` / `AppColors.marketDown` (callers
//     pass the color explicitly so semantic one-offs stay possible)
//   * label contrast picked via `contrastingOnColor`
//   * a whisper of a top highlight on the fill so the solid slab reads
//     as a pressable surface instead of flat paint
//   * optional icon — bare (centered row) or on a translucent disc
//     (left-aligned badge layout)
//   * optional big value/percentage second line (odds, price), rendered
//     with `RollingNumberText` so live updates roll instead of jump
//   * optional light-mode glow shadow (flag; some surfaces keep it,
//     the HL market detail deliberately dropped it) — tight and quiet
//     so it reads as elevation, not a color smear
//   * pressed: scale to 0.97 (reduce-motion aware) + medium haptic,
//     matching AppButton's press language
//   * disabled (enabled: false): 0.35 opacity + inert, matching
//     AppButton's disabled treatment

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/theme/app_theme.dart';

class MarketPairButton extends StatefulWidget {
  /// Main label. Sentence case verbs ("Buy", "Long", "Close position");
  /// outcome tokens (YES/NO) stay uppercase per the copy rules.
  final String label;

  /// Optional big second line (live odds "62%", price "34¢"). When set,
  /// the button renders the two-line badge layout: small label on top,
  /// big tabular value underneath.
  final String? value;

  /// Fill color — pass `AppColors.marketUp` / `AppColors.marketDown`
  /// for directional pairs.
  final Color color;

  final VoidCallback onTap;

  /// Optional icon glyph.
  final IconData? icon;

  /// When true the icon sits on a translucent disc and the content is
  /// left-aligned (the "physical badge" look). When false the icon is
  /// bare and the row is centered.
  final bool iconDisc;

  /// Soft colored glow under the button in light mode.
  final bool glow;

  /// When false the button renders at 0.35 opacity and ignores taps —
  /// same disabled grammar as AppButton. Default true (backward
  /// compatible: every existing call site stays enabled).
  final bool enabled;

  /// Compact variant: 44.h tall with a smaller label/icon — used while
  /// the HL chart's Advanced mode expands so the chart dominates the
  /// screen. The height change animates (reduce-motion instant).
  final bool compact;

  const MarketPairButton({
    super.key,
    required this.label,
    required this.color,
    required this.onTap,
    this.value,
    this.icon,
    this.iconDisc = false,
    this.glow = false,
    this.enabled = true,
    this.compact = false,
  });

  @override
  State<MarketPairButton> createState() => _MarketPairButtonState();
}

class _MarketPairButtonState extends State<MarketPairButton> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final fg = contrastingOnColor(widget.color);
    final twoLine = widget.value != null;

    final children = <Widget>[
      if (widget.icon != null) ...[
        if (widget.iconDisc)
          Container(
            width: 36.sp,
            height: 36.sp,
            decoration: BoxDecoration(
              color: fg.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10.r),
            ),
            alignment: Alignment.center,
            child: Icon(widget.icon, color: fg, size: 22.sp),
          )
        else
          Icon(widget.icon, color: fg, size: widget.compact ? 16.sp : 20.sp),
        SizedBox(width: widget.iconDisc ? 12.w : 8.w),
      ],
      if (twoLine)
        // Badge layout: small label on top, big tabular value under it.
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fg.withValues(alpha: 0.85),
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              SizedBox(height: 2.h),
              RollingNumberText(
                text: widget.value!,
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 250),
                style: TextStyle(
                  color: fg,
                  fontSize: 22.sp,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  height: 1.0,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        )
      else ...[
        () {
          final text = Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: fg,
              fontSize: widget.compact ? 14.sp : 17.sp,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          );
          // Disc layout fills the row (left-aligned badge); the bare
          // layout centers, so the label only flexes if it must.
          return widget.iconDisc
              ? Expanded(child: text)
              : Flexible(child: text);
        }(),
      ],
    ];

    final body = AnimatedContainer(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      height: widget.compact ? 44.h : 60.h,
      padding: EdgeInsets.symmetric(horizontal: 14.w),
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: AppRadius.buttonBorder,
        // Subtle top-highlight so the solid fill reads as a raised,
        // pressable surface (kept faint enough to preserve the flat
        // brand look; the label contrast math is unaffected).
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.alphaBlend(
                Colors.white.withValues(alpha: 0.08), widget.color),
            widget.color,
          ],
          stops: const [0.0, 0.55],
        ),
        // Tight, quiet elevation glow (light mode only, opt-in). The
        // previous 18-blur/0.22 halo read as a color smear on white.
        boxShadow: widget.glow && isLight && widget.enabled
            ? [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.16),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisAlignment: (twoLine || widget.iconDisc)
            ? MainAxisAlignment.start
            : MainAxisAlignment.center,
        children: children,
      ),
    );

    return Opacity(
      opacity: widget.enabled ? 1.0 : 0.35,
      child: GestureDetector(
        onTapDown: widget.enabled ? (_) => _setPressed(true) : null,
        onTapCancel: widget.enabled ? () => _setPressed(false) : null,
        onTapUp: widget.enabled ? (_) => _setPressed(false) : null,
        onTap: widget.enabled
            ? () {
                HapticFeedback.mediumImpact();
                widget.onTap();
              }
            : null,
        child: AnimatedScale(
          scale: (_pressed && !reduceMotion) ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeInOut,
          child: body,
        ),
      ),
    );
  }
}
