import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/screens/shared/kute_motion.dart' show KutePressable;
import 'package:kute/theme/app_theme.dart';
import 'package:kute/theme/kute_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// EVERY modal bottom sheet in the app opens through this (founder, 31
/// October 2026): Flutter's [showModalBottomSheet] with the same
/// arguments and defaults, plus the one motion every sheet shares
/// ([KuteMotion.sheetStyle]: the spring in, a hair past its rest and
/// settled; the settle easing out; a plain line under Reduce Motion).
/// [showAppBottomSheet] is this with the app's sheet chrome; a sheet with
/// its own chrome (a slip, a picker, a menu) calls this directly so its
/// look is untouched and only its motion is shared. Nothing in lib/ calls
/// [showModalBottomSheet] itself.
Future<T?> showKuteModalSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  Color? barrierColor,
  ShapeBorder? shape,
  bool isScrollControlled = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useSafeArea = false,
  bool useRootNavigator = false,
  RouteSettings? routeSettings,
}) {
  return showModalBottomSheet<T>(
    context: context,
    builder: builder,
    backgroundColor: backgroundColor,
    barrierColor: barrierColor,
    shape: shape,
    isScrollControlled: isScrollControlled,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    useSafeArea: useSafeArea,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    sheetAnimationStyle: KuteMotion.sheetStyle(context),
  );
}

/// Unified bottom sheet matching the Ledger device picker design language.
/// Clean, organized layout with drag handle, header, and scrollable content.
/// Opens through [showKuteModalSheet], so it rises on the app's spring.
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required Widget Function(BuildContext) builder,
  bool isScrollControlled = true,
  bool isDismissible = true,
  bool enableDrag = true,
  // `useSafeArea: true` insets the sheet below the iOS status bar /
  // notch and above the home indicator. Without it, a near-full
  // sheet (ours run at maxHeight 0.95) climbs all the way under the
  // status bar with only a few pixels of drag area at the top —
  // visually it looks like a fullscreen view instead of a sheet,
  // and (the bug the user hit on Move) there's no slack region to
  // grab so swipe-down dismiss never registers. Default to true.
  bool useSafeArea = true,
  // Modals MUST float above the persistent shell nav bar. Post nav-shell
  // (#40) the nav bar is mounted in the AppShell ABOVE the branch navigators,
  // so a branch-navigator sheet renders UNDER the bar and its header collides
  // with it. The root navigator sits above the shell — mirror the Polymarket /
  // Hyperliquid sheets, which all use useRootNavigator: true.
  bool useRootNavigator = true,
  // A name for the sheet's route, for a sheet that stands in for a named
  // screen (Receive): the route observers keep seeing that name.
  RouteSettings? routeSettings,
}) {
  return showKuteModalSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: isScrollControlled,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    useSafeArea: useSafeArea,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    // Tap anywhere on the sheet outside a focused field to dismiss the
    // keyboard. Child buttons/inputs still win their own taps; only empty
    // space triggers the unfocus. Applies to every sheet opened this way.
    builder: (ctx) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: builder(ctx),
    ),
  );
}

/// The container widget for unified bottom sheets.
/// Matches the Ledger picker design language.
class AppBottomSheetContainer extends ConsumerWidget {
  final Widget child;
  final double? maxHeight;

  /// Room under the content for the floating Sal bar while it is over
  /// this sheet (kute_bar_context.dart): on when a bar context is up
  /// and not hidden; off (no room taken) otherwise.
  final bool barInset;

  /// Lift the content with the keyboard frame for frame instead of easing
  /// after it. The platform already animates the inset, so a sheet whose
  /// field rises with the keyboard (search, Ask Sal) sets this: the eased
  /// lift trailed the keyboard by its own 200 ms. The lift is a plain
  /// padding on the inset, never a second animation fighting the
  /// keyboard's.
  final bool followKeyboard;

  /// Overrides the sheet surface colour (the receive sheet goes pure white
  /// in light mode so the QR plate has no visible edge). Null: the theme's
  /// sheet surface.
  final Color? color;

  const AppBottomSheetContainer({
    super.key,
    required this.child,
    this.maxHeight,
    this.followKeyboard = false,
    this.color,
    this.barInset = true,
  });

  /// The bar's height plus its air: what a sheet leaves under its content
  /// while the bar is over it.
  static const double barRoom = 76;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final top = kuteBarTop(ref.watch(kuteBarContextProvider));
    final barUp = barInset && top != null && !top.hidden;
    final resolvedMaxHeight = maxHeight != null && maxHeight! <= 1.0
        ? MediaQuery.sizeOf(context).height * maxHeight!
        : maxHeight;
    // Keyboard-aware shift: when an editable inside the sheet gains
    // focus, `MediaQuery.viewInsets.bottom` reports the keyboard
    // height. Padding the whole container by that inset lifts the
    // sheet so the field isn't hidden under the keyboard. Animated
    // so the rise tracks the OS keyboard transition smoothly. Read
    // through viewInsetsOf: only the inset's frames rebuild the sheet,
    // not every other MediaQuery change.
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final keyboardOpen = keyboardInset > 0;
    final padding = EdgeInsets.only(bottom: keyboardInset);
    // Keyboard handling that matches the HL / Polymarket sheets: the SURFACE
    // (this Container's decoration) keeps extending DOWN behind the keyboard,
    // and only the CONTENT is lifted above it. Earlier the whole decorated
    // Container was wrapped in the keyboard AnimatedPadding, which lifted the
    // surface too — so the sheet ended at the keyboard's top edge, showing the
    // dark background through the keyboard's rounded top corners (the corner
    // gap). Padding the content INSIDE the decoration fixes both: the sheet
    // reaches the screen bottom behind the keyboard, flush with no corner gaps.
    // Closed keyboard → honor the OS bottom inset (home indicator) + a 16dp
    // baseline. Open keyboard → the home indicator is covered by the
    // keyboard, so its inset goes; a sheet that follows the keyboard
    // (search and Ask Sal, whose composer is their last row) keeps the
    // same 16dp baseline above it rather than resting on the keys. Other
    // sheets sit flush above it, as before.
    final content = SafeArea(
      top: true,
      bottom: !keyboardOpen,
      child: Padding(
        padding: EdgeInsets.only(
            bottom: (keyboardOpen && !followKeyboard ? 0 : 16.h) +
                (barUp && !keyboardOpen ? barRoom.h : 0)),
        child: child,
      ),
    );
    return Container(
      constraints: resolvedMaxHeight != null
          ? BoxConstraints(maxHeight: resolvedMaxHeight)
          : null,
      decoration: color == null
          ? AppDecorations.bottomSheet(context)
          : AppDecorations.bottomSheet(context).copyWith(color: color),
      // Following the keyboard: the inset as it is, every frame, with no
      // easing of its own (the platform's keyboard curve is the one lift).
      child: followKeyboard
          ? Padding(padding: padding, child: content)
          : AnimatedPadding(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              padding: padding,
              child: content,
            ),
    );
  }
}

/// Standard bottom sheet header with drag handle, title, and subtitle.
/// Follows the Ledger picker design pattern.
///
/// [icon], [iconColor] and [svgAsset] are accepted for API compatibility
/// but never rendered (the sheet context already implies the icon); new
/// call sites should not pass them.
class AppBottomSheetHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final String? svgAsset;
  final Widget? trailing;

  /// A smaller heading and tighter spacing for compact action menus.
  final bool compact;

  /// False when the sheet draws its own handle above this heading (the
  /// receive sheets' header with the close X on the left), so the heading
  /// starts right under it.
  final bool showDragHandle;

  const AppBottomSheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.svgAsset,
    this.trailing,
    this.compact = false,
    this.showDragHandle = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final top = !showDragHandle ? 4.h : (compact ? 12.h : 20.h);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Drag handle
        if (showDragHandle)
          Padding(
            padding: EdgeInsets.only(top: 12.h),
            child: AppDecorations.dragHandle(context),
          ),

        // Header content — same hero hierarchy as the rest of the
        // new design language (receive, send, bank-transfer, etc.).
        // Big 28sp w800 title + 15sp tertiary subtitle, no inline
        // icon (the sheet context already implies it) but we keep
        // the trailing slot for scan-spinner / refresh buttons that
        // some sheets attach.
        Padding(
          padding:
              EdgeInsets.fromLTRB(20.w, top, 20.w, compact ? 12.h : 18.h),
          child: Row(
            crossAxisAlignment:
                compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: compact ? 22.sp : 28.sp,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                        height: 1.05,
                      ),
                    ),
                    if (subtitle != null) ...[
                      SizedBox(height: 6.h),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          color: c.textTertiary,
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.1,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                SizedBox(width: 12.w),
                trailing!,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The close X in a sheet header's trailing slot: the Settings sheets'
/// affordance, in the same top-right slot, with the selection click every
/// close shares. [onPressed] defaults to popping the sheet.
class AppBottomSheetCloseButton extends StatelessWidget {
  final VoidCallback? onPressed;
  const AppBottomSheetCloseButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
      onPressed: () {
        HapticFeedback.selectionClick();
        if (onPressed != null) {
          onPressed!();
        } else {
          Navigator.of(context).pop();
        }
      },
      icon: const Icon(Icons.close_rounded),
    );
  }
}

/// Standard primary button for bottom sheets.
/// Thin wrapper around [AppButton] for backward compatibility.
///
/// [backgroundColor] / [textColor] are legacy overrides; prefer
/// `AppButton(variant: ...)` (secondary / destructive) over a hand-rolled
/// fill or a forced label color.
class AppBottomSheetButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final Color? backgroundColor;
  final Color? textColor;

  const AppBottomSheetButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.backgroundColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return AppButton(
      text: text,
      onPressed: isLoading ? null : onPressed,
      color: backgroundColor,
      // textColor falls back to AppButton's WCAG auto-pick when null —
      // previously hardcoded white, which failed contrast on orange /
      // PolyGreen / PolyRed backgrounds.
      textColor: textColor,
      isLoading: isLoading,
    );
  }
}

/// Secondary text button for bottom sheets (Cancel, Skip, etc.)
/// Thin wrapper around [AppTextButton] for backward compatibility.
class AppBottomSheetTextButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;

  const AppBottomSheetTextButton({
    super.key,
    required this.text,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return AppTextButton(
      text: text,
      onPressed: onPressed,
    );
  }
}

/// Selectable list tile for bottom sheets (like language picker, fee picker).
///
/// Selection is the monochrome CTA: `ctaFill` ground with `ctaOnColor`
/// content (never the orange accent). Unselected rows are neutral
/// surfaceLight tiles with a 0.5 hairline.
class AppBottomSheetListTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final Widget? leading;
  final bool isSelected;
  final VoidCallback? onTap;

  const AppBottomSheetListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.leading,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final onColor = context.ctaOnColor;
    final titleColor = isSelected ? onColor : c.textPrimary;
    final subtitleColor =
        isSelected ? onColor.withValues(alpha: 0.72) : c.textTertiary;
    final glyphColor = isSelected ? onColor : c.textSecondary;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
      // The app's press: 0.98 while held, back on the press spring.
      child: KutePressable(
        enabled: onTap != null,
        child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
          decoration: BoxDecoration(
            color: isSelected ? context.ctaFill : c.surfaceLight,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            // Transparent (not null) when selected so the row keeps the
            // same box size in both states.
            border: Border.all(
              color: isSelected ? Colors.transparent : c.borderSubtle,
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              if (leading != null) ...[
                leading!,
                SizedBox(width: 14.w),
              ] else if (icon != null) ...[
                // Neutral 44 icon tile; on the selected (ctaFill) row it
                // becomes an outlined plate in the on-color, no tint fill.
                Container(
                  width: 44.sp,
                  height: 44.sp,
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.transparent : c.surface,
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(
                      color: isSelected
                          ? onColor.withValues(alpha: 0.3)
                          : c.borderSubtle,
                      width: 0.5,
                    ),
                  ),
                  child: Icon(
                    icon,
                    color: glyphColor,
                    size: 20.sp,
                  ),
                ),
                SizedBox(width: 14.w),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: titleColor,
                        fontSize: 17.sp,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (subtitle != null) ...[
                      SizedBox(height: 3.h),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          color: subtitleColor,
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: 8.w),
              Icon(
                isSelected
                    ? Icons.check_circle_rounded
                    : Icons.chevron_right_rounded,
                color: isSelected ? onColor : c.textTertiary,
                size: isSelected ? 22.sp : 20.sp,
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
