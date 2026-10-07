// lib/screens/shared/charts/kute_chart_zoom_hint.dart
//
// The one-time zoom nudge: the first time a person ever sees a zoomable
// chart (the Predictions chart, the Bitcoin or Dollars balance chart)
// with at least [kKuteZoomNudgeMinPoints] points, once its lines have
// landed, the window zooms in by [kKuteZoomNudgeDepth] and back out over
// [kKuteZoomNudgeDuration] (ease in, ease out), anchored on the newest
// point, so the chart shows it can be pinched. Then never again, on any
// chart: one flag for the device, in the app's settings box, written when
// the nudge starts.
//
//   * Under Reduce Motion it never plays, and counts as seen.
//   * Never while a finger is on the chart; a touch stops it at once and
//     the window is back where it was.
//   * No text, no event.

import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';

/// How far the nudge zooms in: a share of the window's span.
const double kKuteZoomNudgeDepth = 0.08;

/// The whole nudge, in and back out.
const Duration kKuteZoomNudgeDuration = Duration(milliseconds: 800);

/// The fewest points a chart needs for the nudge (a zoom into fewer reads
/// as a glitch).
const int kKuteZoomNudgeMinPoints = 20;

/// How long after its lines land a chart waits before the nudge, so it
/// plays on a chart at rest and not during a sheet's slide-in.
const Duration kKuteZoomNudgeDelay = Duration(milliseconds: 600);

/// Whether the nudge was ever seen on this device: one flag in the
/// settings box ([key]).
class KuteZoomHint {
  KuteZoomHint._();

  /// The settings box key.
  static const String key = 'chart_zoom_hint_seen';

  static bool Function() _read = _readBox;
  static void Function() _write = _writeBox;
  static bool _claimed = false;

  /// With no settings box open (a test, storage that failed), the nudge
  /// counts as seen: never a nudge on every launch.
  static bool _readBox() {
    try {
      if (!Hive.isBoxOpen('settings')) return true;
      return Hive.box('settings').get(key) == true;
    } catch (_) {
      return true;
    }
  }

  static void _writeBox() {
    try {
      if (Hive.isBoxOpen('settings')) Hive.box('settings').put(key, true);
    } catch (_) {/* a nudge seen twice is harmless */}
  }

  /// True when the device has seen the nudge.
  static bool get seen => _claimed || _read();

  /// Takes the one nudge: true the first time ever (the flag is written
  /// now), false after that.
  static bool claim() {
    if (seen) return false;
    _claimed = true;
    _write();
    return true;
  }

  /// Tests: the store to read and write, and a fresh session.
  @visibleForTesting
  static void debugReset({bool Function()? read, void Function()? write}) {
    _read = read ?? _readBox;
    _write = write ?? _writeBox;
    _claimed = false;
  }
}

/// How far into the window the nudge is at [t] (0..1 of its run): up to
/// [kKuteZoomNudgeDepth] halfway, eased in and out both ways.
double kuteZoomNudgeAmount(double t) {
  final c = t.clamp(0.0, 1.0);
  return kKuteZoomNudgeDepth * (1 - math.cos(2 * math.pi * c)) / 2;
}

/// One chart's nudge: its animation, and the share of the window it takes
/// off the window's old end ([amount], 0 at rest).
class KuteZoomNudge {
  KuteZoomNudge(TickerProvider vsync)
      : _controller =
            AnimationController(vsync: vsync, duration: kKuteZoomNudgeDuration);

  final AnimationController _controller;

  /// Fires on every frame of the nudge and when it stops.
  Listenable get listenable => _controller;

  bool get running => _controller.isAnimating;

  /// The share of the window's span the nudge has zoomed in by now.
  double get amount => running ? kuteZoomNudgeAmount(_controller.value) : 0;

  /// Plays the nudge if this device never saw it. Under [reduceMotion] it
  /// is marked seen and does not play. True when it started.
  bool tryStart({required bool reduceMotion}) {
    if (running) return false;
    if (!KuteZoomHint.claim()) return false;
    if (reduceMotion) return false;
    // Its last frame is back at rest (the amount at the end is 0).
    _controller.forward(from: 0);
    return true;
  }

  /// Stops the nudge at once, the window back where it was.
  void cancel() {
    if (!running) return;
    _controller.stop();
    _controller.value = 0;
  }

  void dispose() => _controller.dispose();
}
