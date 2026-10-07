import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// A structured dialog action rendered as a compact [AppButton], so every
/// alert shares the button tiers (primary / secondary / destructive)
/// instead of hand-rolling fills and label colors at each call site.
class CustomAlertAction {
  final String text;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final bool isLoading;

  const CustomAlertAction({
    required this.text,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.isLoading = false,
  });

  const CustomAlertAction.secondary({
    required this.text,
    this.onPressed,
  })  : variant = AppButtonVariant.secondary,
        isLoading = false;

  const CustomAlertAction.destructive({
    required this.text,
    this.onPressed,
  })  : variant = AppButtonVariant.destructive,
        isLoading = false;
}

/// Shows [CustomAlertDialog]. Prefer [buttons] (structured
/// [CustomAlertAction]s) for new call sites; [actions] keeps accepting raw
/// widgets for the existing ones.
Future<void> showCustomAlertDialog({
  required BuildContext context,
  required String title,
  required String content,
  List<Widget> actions = const [],
  List<CustomAlertAction> buttons = const [],
}) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: context.colors.modalBarrier,
    builder: (BuildContext context) {
      return CustomAlertDialog(
        title: title,
        content: content,
        actions: actions,
        buttons: buttons,
      );
    },
  );
}

class CustomAlertDialog extends StatelessWidget {
  final String title;
  final String content;

  /// Raw action widgets (legacy). Stacked full-width, 12 apart.
  final List<Widget> actions;

  /// Structured actions rendered as compact [AppButton]s, above [actions].
  final List<CustomAlertAction> buttons;

  const CustomAlertDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions = const [],
    this.buttons = const [],
  });

  /// A zero-height, childless SizedBox is a leftover horizontal spacer
  /// (`SizedBox(width: 12)`) from the old Row layout that a few call sites
  /// still pass. Inside a Column it renders nothing but still earns a 12h
  /// gap on each side, so it is skipped rather than doubling the spacing.
  static bool _isEmptySpacer(Widget w) =>
      w is SizedBox && w.child == null && (w.height ?? 0) == 0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = <Widget>[
      for (final b in buttons)
        AppButton(
          text: b.text,
          onPressed: b.onPressed,
          variant: b.variant,
          isLoading: b.isLoading,
          compact: true,
        ),
      for (final a in actions)
        if (!_isEmptySpacer(a)) a,
    ];
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        padding: EdgeInsets.all(20.w),
        // Solid card, same material as every other card surface (no glass
        // blur, no translucent fill): 16 radius, hairline only in dark.
        decoration: AppDecorations.card(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 22.sp,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                height: 1.1,
              ),
            ),
            SizedBox(height: 10.h),
            Text(
              content,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 15.sp,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
            SizedBox(height: 24.h),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < rows.length; i++) ...[
                  rows[i],
                  if (i < rows.length - 1) SizedBox(height: 12.h),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
