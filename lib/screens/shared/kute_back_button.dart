// lib/screens/shared/kute_back_button.dart
//
// The app-wide back/close affordances:
//
//  • [KuteBackButton]       — a left chevron in a soft 44px circle for
//                             AppBar `leading` and screen headers.
//  • [KuteCloseButton]      — an X in the same circle for sheet and
//                             full-screen-modal headers.
//  • [KuteCircleBackButton] — the same circle chevron for "back a step"
//                             inside multi-step sheets (defaults to
//                             `Navigator.maybePop` instead of router pop).
//  • [KuteCirclePillButton] — the same chassis as a pill, an icon and a
//                             word (the Financial hub's Settings).
//
// Every screen uses one of these so navigation affordances look identical
// everywhere (no more mix of circular `arrow_back` buttons, bare
// `arrow_back_ios`, hand-rolled X containers, and platform defaults).
//
// Default behaviour pops the current route (falling back to [fallbackRoute]
// when there's nothing to pop). Screens that need a custom action pass
// [onPressed] (full override) or [onBack] (an async step to run before the
// pop, e.g. restoring the previously-active wallet).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:kute/theme/app_theme.dart';

class KuteBackButton extends StatelessWidget {
  /// Full override — when set, this is the only thing the tap does.
  final VoidCallback? onPressed;

  /// Async step run BEFORE the default pop (ignored when [onPressed] is set).
  final Future<void> Function()? onBack;

  /// Where to land if the route can't be popped (no history). Defaults to
  /// the home tab.
  final String fallbackRoute;

  /// Glyph colour override; defaults to `context.colors.textPrimary`.
  final Color? color;

  const KuteBackButton({
    super.key,
    this.onPressed,
    this.onBack,
    this.fallbackRoute = '/home',
    this.color,
  });

  // No haptic here: the circle chassis ticks on tap already.
  Future<void> _handle(BuildContext context) async {
    // A second back while the previous pop is still animating asks the
    // navigator to tear down a route that is already going, which can
    // trip a framework assertion. The tap is simply dropped until the
    // transition has settled.
    final route = ModalRoute.of(context);
    final animation = route?.animation;
    if (animation != null && animation.status != AnimationStatus.completed) {
      return;
    }
    if (onPressed != null) {
      onPressed!();
      return;
    }
    if (onBack != null) await onBack!();
    if (!context.mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(fallbackRoute);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: _KuteCircleIconButton(
        icon: Icons.chevron_left_rounded,
        iconSize: 26,
        size: 44,
        iconColor: color,
        onPressed: () => _handle(context),
      ),
    );
  }
}

/// Close for AppBar `leading` slots that swap between back and close
/// (e.g. confirm-send's stepper at step 0) — the same circled X as
/// [KuteCloseButton], centered for the leading slot so the swap with
/// [KuteBackButton] doesn't change chrome.
class KuteBareCloseButton extends StatelessWidget {
  /// Full override — when set, this is the only thing the tap does
  /// (besides the haptic tick).
  final VoidCallback? onPressed;

  const KuteBareCloseButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Center(child: KuteCloseButton(onPressed: onPressed));
  }
}

/// Shared chassis for the circled affordances: a `surface`-filled circle
/// with a hairline border and an InkWell ripple clipped to it.
class _KuteCircleIconButton extends StatelessWidget {
  final IconData? icon;
  final double iconSize;
  final double size;
  final Color? iconColor;
  final VoidCallback? onPressed;

  /// Drawn in the circle instead of [icon] (the Kute dog on Ask Sal).
  final Widget? child;

  const _KuteCircleIconButton({
    this.icon,
    this.iconSize = 22,
    required this.size,
    this.iconColor,
    this.onPressed,
    this.child,
  });

  void _handle(BuildContext context) {
    HapticFeedback.selectionClick();
    if (onPressed != null) {
      onPressed!();
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: size.w,
      height: size.w,
      decoration: BoxDecoration(
        color: c.surface,
        shape: BoxShape.circle,
        border: Border.all(color: c.borderSubtle, width: 0.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => _handle(context),
          child: child ??
              Icon(icon, color: iconColor ?? c.textSecondary, size: iconSize.sp),
        ),
      ),
    );
  }
}

/// The circled header affordance holding a glyph of its own (the Kute dog
/// on Ask Sal): the same chassis as [KuteCloseButton] and
/// [KuteCircleBackButton], with the selection click every header button
/// shares. [child] is centred in the circle.
class KuteCircleButton extends StatelessWidget {
  final Widget child;
  final String semanticsLabel;
  final VoidCallback onPressed;

  /// Circle diameter in logical px (pre-`.w`); the canonical 44.
  final double size;

  const KuteCircleButton({
    super.key,
    required this.child,
    required this.semanticsLabel,
    required this.onPressed,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: _KuteCircleIconButton(
        size: size,
        onPressed: onPressed,
        child: Center(child: child),
      ),
    );
  }
}

/// The circled header affordance stretched to a pill to carry a word next
/// to its icon (the Financial hub's Settings): the same `surface` fill,
/// hairline border, 44 height, icon colour and selection click as
/// [KuteCircleButton], so it sits beside one as a pair.
class KuteCirclePillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  /// Height in logical px (pre-`.w`); the circle's canonical 44.
  final double size;

  const KuteCirclePillButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: label,
      child: Container(
        height: size.w,
        decoration: ShapeDecoration(
          color: c.surface,
          shape: StadiumBorder(
              side: BorderSide(color: c.borderSubtle, width: 0.5)),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () {
              HapticFeedback.selectionClick();
              onPressed();
            },
            child: Padding(
              padding: EdgeInsets.fromLTRB(12.w, 0, 16.w, 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: c.textSecondary, size: 22.sp),
                  SizedBox(width: 6.w),
                  Text(
                    label,
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The single, app-wide close (X) affordance for sheets and full-screen
/// modals: an X in a soft circle. Default behaviour is
/// `Navigator.maybePop`; pass [onPressed] to fully override the tap.
class KuteCloseButton extends StatelessWidget {
  /// Full override — when set, this is the only thing the tap does
  /// (besides the haptic tick).
  final VoidCallback? onPressed;

  /// Circle diameter in logical px (pre-`.w`). Defaults to the canonical
  /// 44; only shrink it when a call site genuinely can't fit it.
  final double size;

  const KuteCloseButton({super.key, this.onPressed, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return _KuteCircleIconButton(
      icon: Icons.close_rounded,
      iconSize: 22,
      size: size,
      onPressed: onPressed,
    );
  }
}

/// The circled "back a step" affordance for multi-step sheet headers —
/// same chassis as [KuteCloseButton] but with a left chevron. Default
/// behaviour is `Navigator.maybePop`; step-based sheets pass [onPressed]
/// to walk their own state machine back instead.
class KuteCircleBackButton extends StatelessWidget {
  /// Full override — when set, this is the only thing the tap does
  /// (besides the haptic tick).
  final VoidCallback? onPressed;

  /// Circle diameter in logical px (pre-`.w`). Defaults to the canonical
  /// 44; only shrink it when a call site genuinely can't fit it.
  final double size;

  const KuteCircleBackButton({super.key, this.onPressed, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return _KuteCircleIconButton(
      icon: Icons.chevron_left_rounded,
      iconSize: 26,
      size: size,
      onPressed: onPressed,
    );
  }
}
