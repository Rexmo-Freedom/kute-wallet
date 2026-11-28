import 'package:kute/platform/kute_wide_frames.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart'
    show showKuteModalSheet;
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
/// widgets for the existing ones. Opens through [showKuteAlert].
Future<void> showCustomAlertDialog({
  required BuildContext context,
  required String title,
  required String content,
  List<Widget> actions = const [],
  List<CustomAlertAction> buttons = const [],
}) {
  return showKuteAlert<void>(
    context: context,
    barrierDismissible: false,
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

/// EVERY alert (a confirm, an "are you sure", a small form) opens through
/// this. On a phone it is Flutter's [showDialog] exactly as before: a card
/// centred over the dimmed screen. From MEDIUM up a Material [Dialog]
/// stretches to the window less 40 a side (founder, 25 November 2026, the
/// "Forgot your PIN?" card edge to edge on a laptop with a 1900 px red
/// button: "this still wrong"), so there the alert is a sheet like every
/// other one ([showKuteModalSheet]): the bottom-anchored
/// `KuteLayout.sheetMaxWidth` sheet on MEDIUM, the search panel's shape on
/// EXPANDED. The content is the same; [KuteAlertShell] draws it on the
/// sheet's surface instead of the card. Always on the root navigator, as
/// [showDialog] is, so the callers' `Navigator.of(context, rootNavigator:
/// true).pop()` still closes it. [barrierDismissible] false: nothing but
/// its buttons closes it (no drag, no X, no Escape), as before.
Future<T?> showKuteAlert<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = false,
  Color? barrierColor,
}) {
  if (!kuteWindowIsWide(context)) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: barrierColor ?? context.colors.modalBarrier,
      builder: builder,
    );
  }
  return showKuteModalSheet<T>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    isDismissible: barrierDismissible,
    enableDrag: barrierDismissible,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _KuteAlertAsSheet(child: builder(ctx)),
  );
}

/// Marks an alert opened as a sheet by [showKuteAlert] (MEDIUM and up).
class _KuteAlertAsSheet extends InheritedWidget {
  const _KuteAlertAsSheet({required super.child});

  @override
  bool updateShouldNotify(_KuteAlertAsSheet old) => false;
}

/// An alert's surface: on a phone the transparent [Dialog] with [child]
/// in a card ([decoration], the app card when null, [padding] inside);
/// opened as a sheet from MEDIUM up ([showKuteAlert]) the sheet's own
/// surface with [child] in the same padding, at the sheet's width.
class KuteAlertShell extends StatelessWidget {
  const KuteAlertShell({
    super.key,
    required this.child,
    this.decoration,
    this.padding,
    this.insetPadding,
  });

  final Widget child;
  final BoxDecoration? decoration;
  final EdgeInsetsGeometry? padding;

  /// The phone dialog's inset from the screen's edges; Flutter's when
  /// null.
  final EdgeInsets? insetPadding;

  /// Whether [context] is inside an alert opened as a sheet.
  static bool asSheet(BuildContext context) =>
      context.getElementForInheritedWidgetOfExactType<_KuteAlertAsSheet>() !=
      null;

  @override
  Widget build(BuildContext context) {
    final pad = padding ?? EdgeInsets.all(20.w);
    if (asSheet(context)) {
      // The dialog's 20 inside, with the sheet's breath above the title
      // and the home indicator's room under the buttons.
      final inside = pad.resolve(Directionality.of(context));
      return Material(
        type: MaterialType.transparency,
        child: Container(
          width: double.infinity,
          decoration: AppDecorations.bottomSheet(context),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: inside.copyWith(
                  top: inside.top + 8, bottom: inside.bottom + 8),
              child: child,
            ),
          ),
        ),
      );
    }
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: insetPadding,
      child: Container(
        padding: pad,
        decoration: decoration ?? AppDecorations.card(context),
        child: child,
      ),
    );
  }
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
    // Solid card, same material as every other card surface (no glass
    // blur, no translucent fill): 16 radius, hairline only in dark. From
    // MEDIUM up a sheet's surface instead (KuteAlertShell).
    return KuteAlertShell(
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
    );
  }
}
