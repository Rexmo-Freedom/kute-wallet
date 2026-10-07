import 'package:kute/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

/// Visual tiers for [AppButton]. The tier picks the fill (and, for
/// [secondary], the border/label treatment); every tier shares the same
/// geometry, type, press feedback, loading, and disabled handling.
///
/// The app's CTA grammar:
/// - [primary]     — navigate / proceed. Sober monochrome fill
///                   (near-black on light, near-white on dark).
/// - [moneyIn]     — commit money IN (purchase, vault deposit confirm,
///                   claim). The one green CTA tier.
/// - [secondary]   — quiet alternative action: `surface` fill with a
///                   hairline border, `textPrimary` label.
/// - [destructive] — commit money OUT / irreversible (close, reject).
///
/// Directional pairs (BUY/SELL, YES/NO) are NOT AppButton tiers — they use
/// `AppColors.marketUp`/`marketDown` via `color:` or the paired widgets.
enum AppButtonVariant { primary, moneyIn, secondary, destructive }

/// Unified primary button used across the entire app.
///
/// Replaces the old `CustomButton`, `AccentButton`, and `AppBottomSheetButton`.
/// - **Height:** 56.h (standard), 48.h when [compact] is true
/// - **Font:** 17.sp w700, letterSpacing -0.2
/// - **Border radius:** shared 12px action corners
/// - **Animation:** Scale 0.96 on tap + haptic feedback
/// - **Loading:** Staggered dots animation
/// - **Disabled:** 0.35 opacity
class AppButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  /// Which visual tier this button belongs to. [color] overrides the
  /// tier's fill when set (for the rare semantic one-off).
  final AppButtonVariant variant;
  final Color? color;
  final Color? textColor;
  final bool isOutlined;
  final bool isLoading;
  /// Said beside the dots while [isLoading] ("Loading account…"); the
  /// dots alone when null.
  final String? loadingLabel;
  final bool compact;
  /// Optional leading icon (e.g. the Add Funds "+"). Tinted to match the
  /// label so heroes can route through this one widget too.
  final IconData? icon;
  /// Optional leading SVG mark, for a button that carries an ASSET
  /// rather than a verb — the dollar deposit door wears the shared
  /// dollar mark. Keeps its own colors, so a brand mark stays itself;
  /// takes precedence over [icon] when both are set.
  final String? svgAsset;
  /// Override the label size. Defaults to 19.sp (compact: 17.sp). Lets
  /// individual buttons run bigger/smaller letters while staying centralized.
  final double? fontSize;
  /// Override the label weight. Defaults to w700.
  final FontWeight? fontWeight;
  /// Override the button height. Defaults to 56.h (compact: 48.h).
  final double? height;

  const AppButton({
    super.key,
    required this.text,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.color,
    this.textColor,
    this.isOutlined = false,
    this.isLoading = false,
    this.loadingLabel,
    this.compact = false,
    this.icon,
    this.svgAsset,
    this.fontSize,
    this.fontWeight,
    this.height,
  });

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  bool get _isDisabled => widget.onPressed == null && !widget.isLoading;

  @override
  Widget build(BuildContext context) {
    // Fill comes from the variant tier; `color:` remains a per-site
    // override for the rare semantic one-off (e.g. marketUp/marketDown).
    final c = context.colors;
    final variantColor = switch (widget.variant) {
      AppButtonVariant.primary => context.ctaFill,
      AppButtonVariant.moneyIn => c.success,
      AppButtonVariant.secondary => c.surface,
      AppButtonVariant.destructive => c.error,
    };
    final effectiveColor = widget.color ?? variantColor;
    // Label color is picked by contrast against the actual fill via
    // `contrastingOnColor` (white on the near-black light fill, black on the
    // near-white dark fill, and still correct for any forced `color:`).
    // Secondary's surface fill would resolve near-invisibly, so it pins
    // `textPrimary`. Callers can override with `textColor`.
    final effectiveTextColor = widget.textColor ??
        (widget.variant == AppButtonVariant.secondary
            ? c.textPrimary
            : contrastingOnColor(effectiveColor));

    // Reduce-motion: the 0.96 tap-bounce is decorative feedback, not
    // information. Skip it when the user has asked for reduced motion;
    // haptics + onPressed still fire so the button behaves identically.
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return GestureDetector(
      onTapDown: (_isDisabled || widget.isLoading || reduceMotion)
          ? null
          : (_) => _animationController.forward(),
      onTapUp: (_isDisabled || widget.isLoading)
          ? null
          : (_) {
              _animationController.reverse();
              HapticFeedback.lightImpact();
              widget.onPressed?.call();
            },
      onTapCancel: (_isDisabled || widget.isLoading) ? null : () => _animationController.reverse(),
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          );
        },
        child: Opacity(
          // Disabled state is a softer 0.35 instead of 0.5 — at 0.5 a
          // blue button on white reads as a half-painted glitch; 0.35
          // makes the disabled affordance obvious without looking like
          // a render bug.
          opacity: _isDisabled ? 0.35 : 1.0,
          child: Container(
            width: double.infinity,
            height: widget.height ?? (widget.compact ? 48.h : 56.h),
            decoration: _buildDecoration(effectiveColor),
            child: Center(
              child: widget.isLoading
                  ? _buildLoading(effectiveTextColor)
                  : _buildLabel(effectiveTextColor),
            ),
          ),
        ),
      ),
    );
  }

  /// The dots, with [AppButton.loadingLabel] beside them when given.
  Widget _buildLoading(Color color) {
    final dots =
        LoadingAnimationWidget.staggeredDotsWave(color: color, size: 24.sp);
    final label = widget.loadingLabel;
    if (label == null) return dots;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        dots,
        SizedBox(width: 10.w),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: widget.fontSize ?? 17.sp,
              fontWeight: widget.fontWeight ?? FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
        ),
      ],
    );
  }

  /// Label (+ optional leading icon), honoring the per-button size/weight
  /// overrides so letters can differ across buttons from one widget.
  Widget _buildLabel(Color color) {
    // Uniform label size across every button (callers can still override
    // via `fontSize`, but nothing in-app does now — one consistent size).
    final size = widget.fontSize ?? 17.sp;
    final label = Text(
      widget.text,
      style: TextStyle(
        color: color,
        fontSize: size,
        fontWeight: widget.fontWeight ?? FontWeight.w700,
        letterSpacing: -0.2,
      ),
    );
    if (widget.svgAsset == null && widget.icon == null) return label;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.svgAsset != null)
          SvgPicture.asset(widget.svgAsset!,
              width: size + 6, height: size + 6)
        else
          Icon(widget.icon, color: color, size: size + 3),
        SizedBox(width: 8.w),
        // A long label (Portuguese copy, larger text scale) wraps onto a
        // second line beside the icon instead of overflowing the button.
        Flexible(
          child: Text(
            widget.text,
            style: label.style,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  BoxDecoration _buildDecoration(Color effectiveColor) {
    if (widget.isOutlined) {
      // A secondary outline takes the theme's border: its own fill colour
      // is the screen surface, so a 30% tint of it drew no visible edge and
      // the button read as bare text.
      final quiet =
          widget.variant == AppButtonVariant.secondary && widget.color == null;
      return BoxDecoration(
        color: quiet
            ? Colors.transparent
            : effectiveColor.withValues(alpha: 0.08),
        borderRadius: AppRadius.buttonBorder,
        border: Border.all(
            color: quiet
                ? context.colors.border
                : effectiveColor.withValues(alpha: 0.3),
            width: 1.5),
      );
    }

    // Secondary is a quiet surface action: hairline border so it reads as a
    // button on the matching screen background.
    if (widget.variant == AppButtonVariant.secondary && widget.color == null) {
      return BoxDecoration(
        color: effectiveColor,
        borderRadius: AppRadius.buttonBorder,
        border: Border.all(
            color: context.colors.borderSubtle, width: 0.5),
      );
    }

    return BoxDecoration(
      color: effectiveColor,
      borderRadius: AppRadius.buttonBorder,
    );
  }
}

/// Backward-compatible alias for [AppButton].
///
/// Maps the old `CustomButton` constructor to the new unified `AppButton`.
/// Existing call sites pass `primaryColor` → mapped to `color`.
class CustomButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final Color primaryColor;
  // Nullable so callers can opt into [AppButton]'s WCAG auto-pick. Old
  // default was `Colors.white`, which read poorly on orange / PolyGreen
  // / PolyRed primaries. Existing call sites that pass `textColor`
  // explicitly are unaffected.
  final Color? textColor;
  final bool isOutlined;

  const CustomButton({
    super.key,
    required this.text,
    required this.onPressed,
    required this.primaryColor,
    this.textColor,
    this.isOutlined = false,
  });

  @override
  Widget build(BuildContext context) {
    return AppButton(
      text: text,
      onPressed: onPressed,
      color: primaryColor,
      textColor: textColor,
      isOutlined: isOutlined,
    );
  }
}

/// Unified secondary text button used across the entire app.
///
/// Replaces `AppBottomSheetTextButton` and inline `TextButton` usage.
/// - **Height:** 44.h
/// - **Font:** 16.sp, w500
/// - **Border radius:** shared action corners
/// - **Text color:** theme's textSecondary
/// - **No background**
class AppTextButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final Color? textColor;

  const AppTextButton({
    super.key,
    required this.text,
    this.onPressed,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      width: double.infinity,
      height: 44.h,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: textColor ?? c.textSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.buttonBorder,
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
