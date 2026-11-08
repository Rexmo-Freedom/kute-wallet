// lib/screens/shared/kute_back_button.dart
//
// The app-wide back/close affordances, ONE fintech chassis (founder, 4
// November 2026: "back buttons better also, and X buttons across the app
// are not very fintech-like"), after Revolut, Cash App and Apple Wallet:
//
//  • a 40 circle ([kKuteNavButtonSize], scaled by width) in a soft tint of
//    the ink (textPrimary at 6% in light, 10% in dark; no hairline), so it
//    reads on the page, a sheet or a card alike;
//  • a crisp thin glyph drawn, not a font icon ([KuteNavGlyphPainter]): a
//    rounded chevron or X, a 2 px stroke with round caps, in textPrimary;
//  • a 44 touch target at least ([kKuteNavHitSize]) around the circle;
//  • the press: the circle sinks to 92% and its tint deepens while held,
//    and springs back on [KuteMotion.press]; none of it under Reduce
//    Motion. A selection click on the tap.
//
// The widgets:
//
//  • [KuteBackButton]       — the chevron for AppBar `leading` and screen
//                             headers (router pop, [fallbackRoute] when
//                             there is nothing to pop).
//  • [KuteCloseButton]      — the X for sheet and full-screen-modal headers.
//  • [KuteCircleBackButton] — the chevron for "back a step" inside
//                             multi-step sheets (`Navigator.maybePop`).
//  • [KuteBareCloseButton]  — the X centred for an AppBar `leading` slot.
//  • [KuteCircleButton]     — the same chassis holding a glyph of its own.
//  • [KuteCirclePillButton] — the same chassis as a pill, an icon and a
//                             word (the Financial hub's Settings).
//
// Every screen uses one of these so navigation affordances look identical
// everywhere (no Material `arrow_back`, bare `arrow_back_ios`, hand-rolled
// X containers or IconButton ripples).
//
// Default behaviour pops the current route (falling back to [fallbackRoute]
// when there's nothing to pop). Screens that need a custom action pass
// [onPressed] (full override) or [onBack] (an async step to run before the
// pop, e.g. restoring the previously-active wallet).

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:kute/theme/app_theme.dart';
import 'package:kute/theme/kute_motion.dart';

/// The diameter of every navigation circle, in design units (pre-`.w`).
const double kKuteNavButtonSize = 40;

/// The least touch target around a navigation circle, in logical pixels.
const double kKuteNavHitSize = 44;

/// The scale a navigation circle sinks to while held: deeper than a row's
/// [KuteMotion.pressScale], as a small control needs to read the press.
const double kKuteNavPressScale = 0.92;

/// How far a navigation target beside a title starts above the title's
/// top, so the circle sits centred on the title's first line: half of what
/// the [kKuteNavHitSize] target is taller than that line ([fontSize] at
/// line [height], under the person's text scale); 0 for a taller line.
double kuteNavTitleLift(BuildContext context, double fontSize,
        {double height = 1.2}) =>
    math.max(
        0,
        (kKuteNavHitSize -
                MediaQuery.textScalerOf(context).scale(fontSize) * height) /
            2);

/// The circle's tint at rest: the ink at 6% in light mode, 10% in dark.
Color kuteNavFill(BuildContext context) => context.colors.textPrimary
    .withValues(alpha: context.isDark ? 0.10 : 0.06);

/// The circle's tint while held.
Color kuteNavPressedFill(BuildContext context) => context.colors.textPrimary
    .withValues(alpha: context.isDark ? 0.18 : 0.12);

/// The glyph a navigation circle draws.
enum KuteNavGlyph { back, close }

/// The thin, rounded navigation glyphs: a chevron pointing left (its
/// weight nudged a hair left of centre so it sits optically centred) or
/// an X, a stroke of 5% of the box (2 px in the 40 circle), round caps
/// and joins.
class KuteNavGlyphPainter extends CustomPainter {
  const KuteNavGlyphPainter(this.glyph, this.color);

  final KuteNavGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, s * 0.05)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final path = Path();
    switch (glyph) {
      case KuteNavGlyph.back:
        final h = s * 0.17;
        final w = s * 0.085;
        final x = cx - s * 0.015;
        path
          ..moveTo(x + w, cy - h)
          ..lineTo(x - w, cy)
          ..lineTo(x + w, cy + h);
      case KuteNavGlyph.close:
        final a = s * 0.135;
        path
          ..moveTo(cx - a, cy - a)
          ..lineTo(cx + a, cy + a)
          ..moveTo(cx + a, cy - a)
          ..lineTo(cx - a, cy + a);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(KuteNavGlyphPainter old) =>
      old.glyph != glyph || old.color != color;
}

/// The words a screen reader says for [glyph] ("Back", "Close"), from the
/// app's Material localizations; null where there are none.
String? _navLabel(BuildContext context, KuteNavGlyph glyph) {
  final m =
      Localizations.of<MaterialLocalizations>(context, MaterialLocalizations);
  if (m == null) return null;
  return glyph == KuteNavGlyph.back
      ? m.backButtonTooltip
      : m.closeButtonTooltip;
}

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
      child: _KuteNavChassis(
        glyph: KuteNavGlyph.back,
        size: kKuteNavButtonSize,
        glyphColor: color,
        semanticsLabel: _navLabel(context, KuteNavGlyph.back),
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

/// The one chassis every navigation affordance shares (see the file
/// header): the tinted circle (or pill, [pill]) of [size] holding [glyph]
/// or [child], inside a touch target of at least [kKuteNavHitSize], with
/// the press and the selection click. Its tap runs [onPressed], else
/// `Navigator.maybePop`. [enabled] false: faded, no press, no tap.
class _KuteNavChassis extends StatefulWidget {
  const _KuteNavChassis({
    this.glyph,
    this.child,
    required this.size,
    this.glyphColor,
    this.onPressed,
    this.enabled = true,
    this.fill,
    this.borderColor,
    this.semanticsLabel,
    this.pill = false,
  }) : assert(glyph != null || child != null);

  final KuteNavGlyph? glyph;

  /// Drawn in the circle instead of [glyph] (the Kute dog on Ask Sal, a
  /// pill's icon and word).
  final Widget? child;

  /// The circle's diameter (the pill's height) in design units.
  final double size;
  final Color? glyphColor;
  final VoidCallback? onPressed;
  final bool enabled;

  /// Overrides the tint, and adds a hairline (the scanner's controls over
  /// live video).
  final Color? fill;
  final Color? borderColor;
  final String? semanticsLabel;
  final bool pill;

  @override
  State<_KuteNavChassis> createState() => _KuteNavChassisState();
}

class _KuteNavChassisState extends State<_KuteNavChassis> {
  bool _down = false;

  void _set(bool value) {
    if (_down != value && mounted) setState(() => _down = value);
  }

  void _handle() {
    HapticFeedback.selectionClick();
    final onPressed = widget.onPressed;
    if (onPressed != null) {
      onPressed();
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reduce = KuteMotion.reduce(context);
    final live = widget.enabled;
    final down = _down && live;
    final d = widget.size.w;
    final own = widget.fill;
    final fill = own == null
        ? (down ? kuteNavPressedFill(context) : kuteNavFill(context))
        : (down
            ? Color.alphaBlend(Colors.white.withValues(alpha: 0.12), own)
            : own);
    final border = widget.borderColor;
    final side = border == null
        ? BorderSide.none
        : BorderSide(color: border, width: 0.5);
    final duration = reduce
        ? Duration.zero
        : (down ? KuteMotion.pressInDuration : KuteMotion.pressDuration);
    final glyph = widget.glyph;
    Widget face = AnimatedContainer(
      duration: duration,
      curve: Curves.easeOut,
      // No alignment: a pill hugs its icon and word (an aligned container
      // would stretch to the row's width).
      width: widget.pill ? null : d,
      height: d,
      decoration: ShapeDecoration(
        color: fill,
        shape: widget.pill
            ? StadiumBorder(side: side)
            : CircleBorder(side: side),
      ),
      child: widget.child ??
          CustomPaint(
            size: Size.square(d),
            painter: KuteNavGlyphPainter(
                glyph!, widget.glyphColor ?? c.textPrimary),
          ),
    );
    face = AnimatedScale(
      scale: down && !reduce ? kKuteNavPressScale : 1.0,
      duration: duration,
      curve: down ? Curves.easeOut : KuteMotion.press,
      child: face,
    );
    // The box it lays out in: the 44 the circles always took, scaled by
    // width like the rest of the layout (so no header moves); the touch
    // target reaches at least 44 logical px past it on a narrow phone.
    final box = math.max(kKuteNavHitSize, widget.size).w;
    return _MinHitArea(
      extent: kKuteNavHitSize,
      child: Semantics(
        button: true,
        enabled: live,
        label: widget.semanticsLabel,
        excludeSemantics: widget.semanticsLabel != null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: live ? (_) => _set(true) : null,
          onTapUp: live ? (_) => _set(false) : null,
          onTapCancel: live ? () => _set(false) : null,
          onTap: live ? _handle : null,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: box, minHeight: box),
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: Opacity(opacity: live ? 1 : 0.4, child: face),
            ),
          ),
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

  /// Circle diameter in logical px (pre-`.w`); the canonical
  /// [kKuteNavButtonSize].
  final double size;

  /// Overrides the tint and adds a hairline. The scanner's controls set
  /// them: they sit over live video, so they wear a translucent dark fill
  /// that reads in light and dark mode alike. Swap's circle sets them too:
  /// it rides the edge two cards share, so it wears the page's own ground
  /// with a hairline and no card edge shows through it.
  final Color? fill;
  final Color? borderColor;

  /// False: faded, no press, no tap (a busy sheet's swap circle).
  final bool enabled;

  const KuteCircleButton({
    super.key,
    required this.child,
    required this.semanticsLabel,
    required this.onPressed,
    this.size = kKuteNavButtonSize,
    this.fill,
    this.borderColor,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return _KuteNavChassis(
      size: size,
      semanticsLabel: semanticsLabel,
      onPressed: onPressed,
      enabled: enabled,
      fill: fill,
      borderColor: borderColor,
      child: Center(child: child),
    );
  }
}

/// The circled header affordance stretched to a pill to carry a word next
/// to its icon (the Financial hub's Settings): the same tint, height,
/// press and selection click as [KuteCircleButton], so it sits beside one
/// as a pair.
class KuteCirclePillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  /// Height in logical px (pre-`.w`); the circle's canonical
  /// [kKuteNavButtonSize].
  final double size;

  const KuteCirclePillButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.size = kKuteNavButtonSize,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _KuteNavChassis(
      size: size,
      pill: true,
      semanticsLabel: label,
      onPressed: onPressed,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12.w, 0, 16.w, 0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: c.textPrimary, size: 20.sp),
            SizedBox(width: 6.w),
            Text(
              label,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 15.sp,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The single, app-wide close (X) affordance for sheets and full-screen
/// modals. Default behaviour is `Navigator.maybePop`; pass [onPressed] to
/// fully override the tap. [enabled] false holds it (a change on its way
/// that the ticket must not be closed under).
class KuteCloseButton extends StatelessWidget {
  /// Full override — when set, this is the only thing the tap does
  /// (besides the haptic tick).
  final VoidCallback? onPressed;

  /// Circle diameter in logical px (pre-`.w`); the canonical
  /// [kKuteNavButtonSize]. Every header uses it.
  final double size;

  final bool enabled;

  const KuteCloseButton({
    super.key,
    this.onPressed,
    this.size = kKuteNavButtonSize,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return _KuteNavChassis(
      glyph: KuteNavGlyph.close,
      size: size,
      enabled: enabled,
      semanticsLabel: _navLabel(context, KuteNavGlyph.close),
      onPressed: onPressed,
    );
  }
}

/// The circled "back a step" affordance for multi-step sheet headers —
/// same chassis as [KuteCloseButton] but with the chevron. Default
/// behaviour is `Navigator.maybePop`; step-based sheets pass [onPressed]
/// to walk their own state machine back instead.
class KuteCircleBackButton extends StatelessWidget {
  /// Full override — when set, this is the only thing the tap does
  /// (besides the haptic tick).
  final VoidCallback? onPressed;

  /// Circle diameter in logical px (pre-`.w`); the canonical
  /// [kKuteNavButtonSize]. Every header uses it.
  final double size;

  const KuteCircleBackButton(
      {super.key, this.onPressed, this.size = kKuteNavButtonSize});

  @override
  Widget build(BuildContext context) {
    return _KuteNavChassis(
      glyph: KuteNavGlyph.back,
      size: size,
      semanticsLabel: _navLabel(context, KuteNavGlyph.back),
      onPressed: onPressed,
    );
  }
}

/// A touch target of at least [extent] x [extent] logical px around its
/// child, centred on it, without changing its layout: a tap just outside
/// a box the width scale made smaller than [extent] still lands on it.
class _MinHitArea extends SingleChildRenderObjectWidget {
  const _MinHitArea({required this.extent, super.child});

  final double extent;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMinHitArea(extent);

  @override
  void updateRenderObject(
          BuildContext context, _RenderMinHitArea renderObject) =>
      renderObject.extent = extent;
}

class _RenderMinHitArea extends RenderProxyBox {
  _RenderMinHitArea(this.extent);

  double extent;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final dx = math.max(0.0, (extent - size.width) / 2);
    final dy = math.max(0.0, (extent - size.height) / 2);
    final area = Rect.fromLTRB(
        -dx, -dy, size.width + dx, size.height + dy);
    if (!area.contains(position)) return false;
    // A point in the margin is handed to the child at its nearest edge.
    final inside = Offset(
      position.dx.clamp(0.0, math.max(0.0, size.width - 0.001)),
      position.dy.clamp(0.0, math.max(0.0, size.height - 0.001)),
    );
    if (hitTestChildren(result, position: inside)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }
}
