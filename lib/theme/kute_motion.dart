// lib/theme/kute_motion.dart
//
// THE ONE PLACE THE APP'S SPRINGS LIVE (founder, 31 October 2026: every
// bottom sheet opens with the elastic settle Orchestra's sheets have, and
// a press anywhere gets the same spring feel). The numbers are
// Orchestra's own (framer-motion), read from its code:
//
//   * a sheet or picker opening: spring stiffness 380, damping 32, mass
//     0.9: a hair past its rest, settled in about 400 ms. Closing: the
//     settle easing cubic-bezier(0.22, 1, 0.36, 1) over 260 ms, no bounce;
//   * a chip or segmented pill: spring 500 / 25, more bounce;
//   * a press on a row or a button: 1 → 0.98 on touch, and back on release
//     on spring 520 / 42, mass 0.7 (overdamped: it returns, never bounces);
//   * the CSS parts' overshoot cubic-bezier(0.34, 1.56, 0.64, 1).
//
// A spring is given to Flutter as a [Curve] ([KuteSpringCurve]: the
// simulation's position over the curve's duration), so AnimatedScale,
// CurvedAnimation and a sheet's [AnimationStyle] all run it. Change a
// number here and every sheet, chip and press follows.
//
// Reduce Motion: no spring and no overshoot anywhere; a plain 150 ms line
// ([reducedDuration], [reducedStyle]). Every caller asks [sheetStyle] /
// [reduce] with its context rather than reading the setting itself.

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

abstract final class KuteMotion {
  // ── Sheets ───────────────────────────────────────────────────────────

  /// A sheet or picker rising: slight overshoot, settled in ~400 ms.
  static const SpringDescription sheetSpring =
      SpringDescription(mass: 0.9, stiffness: 380, damping: 32);
  static const Duration sheetInDuration = Duration(milliseconds: 420);
  static const Duration sheetOutDuration = Duration(milliseconds: 260);

  /// The open: [sheetSpring] over [sheetInDuration].
  static final Curve sheetIn = KuteSpringCurve(sheetSpring, sheetInDuration);

  /// The close: Orchestra's settle easing, no bounce.
  static const Curve sheetOut = Cubic(0.22, 1, 0.36, 1);

  /// Orchestra's CSS overshoot, for a part that pops into place (a check
  /// mark, a chip's fill) rather than a whole sheet.
  static const Curve overshoot = Cubic(0.34, 1.56, 0.64, 1);

  /// Orchestra's settle easing at 300 ms.
  static const Curve settle = Cubic(0.22, 1, 0.36, 1);
  static const Duration settleDuration = Duration(milliseconds: 300);

  // ── Chips and segmented pills ────────────────────────────────────────

  static const SpringDescription chipSpring =
      SpringDescription(mass: 1, stiffness: 500, damping: 25);
  static const Duration chipDuration = Duration(milliseconds: 360);
  static final Curve chip = KuteSpringCurve(chipSpring, chipDuration);

  // ── Press feedback ───────────────────────────────────────────────────

  /// The scale a row or button is held at while pressed.
  static const double pressScale = 0.98;

  /// Down: quick and plain. Up: [pressSpring] over [pressDuration].
  static const Duration pressInDuration = Duration(milliseconds: 90);
  static const SpringDescription pressSpring =
      SpringDescription(mass: 0.7, stiffness: 520, damping: 42);
  static const Duration pressDuration = Duration(milliseconds: 280);
  static final Curve press = KuteSpringCurve(pressSpring, pressDuration);

  // ── Reduce Motion ────────────────────────────────────────────────────

  /// Whether the person asked the system for less motion.
  static bool reduce(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// Everything under Reduce Motion: a 150 ms line, no overshoot.
  static const Duration reducedDuration = Duration(milliseconds: 150);
  static const AnimationStyle reducedStyle = AnimationStyle(
    curve: Curves.linear,
    duration: reducedDuration,
    reverseCurve: Curves.linear,
    reverseDuration: reducedDuration,
  );

  /// A modal bottom sheet's motion: the spring in, the settle out, or the
  /// line under Reduce Motion. Every sheet in the app opens with this
  /// (app_bottom_sheet.dart, showKuteModalSheet).
  static AnimationStyle sheetStyle(BuildContext context) => reduce(context)
      ? reducedStyle
      : AnimationStyle(
          curve: sheetIn,
          duration: sheetInDuration,
          reverseCurve: sheetOut,
          reverseDuration: sheetOutDuration,
        );
}

/// A spring as a curve: the position of [spring] released from 0 towards
/// 1, read over [duration] (the time the spring takes to settle). A curve
/// may pass 1 and come back, which is the bounce; Flutter's animated
/// widgets and sheets take that in their stride.
class KuteSpringCurve extends Curve {
  KuteSpringCurve(this.spring, this.duration)
      : _simulation = SpringSimulation(spring, 0, 1, 0);

  final SpringDescription spring;
  final Duration duration;
  final SpringSimulation _simulation;

  @override
  double transformInternal(double t) =>
      _simulation.x(t * duration.inMicroseconds / Duration.microsecondsPerSecond);
}
