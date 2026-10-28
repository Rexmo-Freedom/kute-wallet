// lib/services/haptic_patterns.dart
//
// The app's named haptic moments as real patterns, built the way
// Instagram builds its own (a continuous base layer shaped by intensity
// and sharpness curves, sharp transients on top, swells that fade or
// rise into a snap), with our own shapes and values. They play through
// the native bridge ([ContinuousHaptics.play]): Core Haptics on iOS, an
// amplitude waveform rendered from the same events on Android
// ([HapticPattern.androidWaveform]). A device that cannot play them (no
// Core Haptics, Android without amplitude control) falls back to the
// caller's system impacts, as before.
//
// One family for money: every success (a send, a bet or an order placed,
// a move landed, the rubber band's release) is [HapticPatterns.success],
// a short whoosh into a double snap; a release without is
// [HapticPatterns.softRelease]; money arriving is [HapticPatterns.moneyIn].
//
// Times are in milliseconds. Intensity and sharpness are 0..1 (Core
// Haptics' event parameters). A curve on intensity scales every event
// playing at that moment (0..1, as `hapticIntensityControl`), a curve on
// sharpness offsets it (-1..1, as `hapticSharpnessControl`); so a swell's
// curve returns to neutral (1, 0) before the snap it rises into.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

enum HapticEventKind { transient, continuous }

@immutable
class HapticEvent {
  const HapticEvent.transient(this.atMs,
      {required this.intensity, required this.sharpness})
      : kind = HapticEventKind.transient,
        durationMs = 0;

  const HapticEvent.continuous(this.atMs, this.durationMs,
      {required this.intensity, required this.sharpness})
      : kind = HapticEventKind.continuous;

  final HapticEventKind kind;
  final int atMs;
  final int durationMs;
  final double intensity;
  final double sharpness;

  int get endMs => kind == HapticEventKind.transient
      ? atMs + HapticPattern.transientMs(sharpness)
      : atMs + durationMs;

  Map<String, Object> toMap() => {
        'type': kind.name,
        'time': atMs / 1000,
        if (kind == HapticEventKind.continuous) 'duration': durationMs / 1000,
        'intensity': intensity,
        'sharpness': sharpness,
      };
}

enum HapticCurveParameter { intensity, sharpness }

@immutable
class HapticCurve {
  const HapticCurve(this.parameter, this.points);

  final HapticCurveParameter parameter;

  /// (time in ms, value), in time order.
  final List<(int, double)> points;

  /// The curve's value at [ms]: linear between points, held past the
  /// ends.
  double valueAt(int ms) {
    if (points.isEmpty) {
      return parameter == HapticCurveParameter.intensity ? 1 : 0;
    }
    if (ms <= points.first.$1) return points.first.$2;
    for (var i = 1; i < points.length; i++) {
      final (t1, v1) = points[i];
      if (ms <= t1) {
        final (t0, v0) = points[i - 1];
        final span = t1 - t0;
        return span <= 0 ? v1 : v0 + (v1 - v0) * (ms - t0) / span;
      }
    }
    return points.last.$2;
  }

  Map<String, Object> toMap() => {
        'parameter': parameter.name,
        'points': [
          for (final (t, v) in points) [t / 1000, v],
        ],
      };
}

@immutable
class HapticPattern {
  const HapticPattern(this.name, this.events, [this.curves = const []]);

  final String name;
  final List<HapticEvent> events;
  final List<HapticCurve> curves;

  /// How long one transient lasts on Android's waveform: sharper is
  /// shorter (8..20 ms), as a sharper click is on iOS.
  static int transientMs(double sharpness) =>
      (20 - 12 * sharpness.clamp(0.0, 1.0)).round();

  /// The rendering step of the Android waveform.
  static const int stepMs = 5;

  /// How long the pattern plays.
  Duration get duration =>
      Duration(milliseconds: events.fold(0, (m, e) => math.max(m, e.endMs)));

  double _intensityControlAt(int ms) {
    for (final c in curves) {
      if (c.parameter == HapticCurveParameter.intensity) return c.valueAt(ms);
    }
    return 1;
  }

  /// The pattern as one Android waveform: segment lengths (ms) and their
  /// amplitudes (0 = off, 1..255), rendered every [stepMs] from the same
  /// events (each at its intensity under the intensity curve, a transient
  /// as a short hit; the strongest wins where they overlap). Android has
  /// no sharpness, so a sharper transient is a shorter one.
  ({List<int> timings, List<int> amplitudes}) get androidWaveform {
    final end = duration.inMilliseconds;
    final slots = (end / stepMs).ceil();
    final amps = List<int>.filled(slots, 0);
    for (var s = 0; s < slots; s++) {
      final t = s * stepMs;
      var level = 0.0;
      for (final e in events) {
        if (t < e.atMs || t >= e.endMs) continue;
        // The intensity curve scales every event playing then, as Core
        // Haptics' intensity control does.
        level = math.max(level, e.intensity * _intensityControlAt(t));
      }
      amps[s] = level <= 0 ? 0 : (255 * level).round().clamp(1, 255);
    }
    final timings = <int>[];
    final amplitudes = <int>[];
    for (final a in amps) {
      if (amplitudes.isNotEmpty && amplitudes.last == a) {
        timings[timings.length - 1] += stepMs;
      } else {
        timings.add(stepMs);
        amplitudes.add(a);
      }
    }
    return (timings: timings, amplitudes: amplitudes);
  }

  /// What crosses the bridge: the events and curves (iOS) and the
  /// rendered waveform (Android).
  Map<String, Object> toMap() {
    final wave = androidWaveform;
    return {
      'name': name,
      'events': [for (final e in events) e.toMap()],
      'curves': [for (final c in curves) c.toMap()],
      'timings': wave.timings,
      'amplitudes': wave.amplitudes,
    };
  }
}

/// The patterns. Ours, in Instagram's structure: base layer, transients,
/// swells.
abstract final class HapticPatterns {
  /// Success, for every money action that went through (and the rubber
  /// band's release): a 100 ms whoosh swelling from almost nothing, then
  /// a double snap, a firm one and the full one 90 ms later.
  static const success = HapticPattern('success', [
    HapticEvent.continuous(0, 100, intensity: 1, sharpness: 0.25),
    HapticEvent.transient(100, intensity: 0.75, sharpness: 0.55),
    HapticEvent.transient(190, intensity: 1, sharpness: 1),
  ], [
    HapticCurve(
        HapticCurveParameter.intensity, [(0, 0.12), (95, 0.75), (100, 1)]),
    HapticCurve(
        HapticCurveParameter.sharpness, [(0, -0.15), (95, 0.25), (100, 0)]),
  ]);

  /// The band let go without the action going through: one soft, dull
  /// tap.
  static const softRelease = HapticPattern('softRelease', [
    HapticEvent.transient(0, intensity: 0.45, sharpness: 0.2),
  ]);

  /// Money landed: a soft swell rising over 260 ms, one clean snap, and a
  /// short tail fading out (about 0.4 s in all).
  static const moneyIn = HapticPattern('moneyIn', [
    HapticEvent.continuous(0, 260, intensity: 1, sharpness: 0.2),
    HapticEvent.transient(270, intensity: 0.85, sharpness: 0.75),
    HapticEvent.continuous(280, 120, intensity: 0.3, sharpness: 0.3),
  ], [
    HapticCurve(HapticCurveParameter.intensity,
        [(0, 0.05), (260, 0.6), (270, 1), (400, 0)]),
  ]);

  /// The open market's price moved a point: the lightest, crispest tick.
  static const oddsTick = HapticPattern('oddsTick', [
    HapticEvent.transient(0, intensity: 0.3, sharpness: 0.95),
  ]);

  /// The last seconds of a held round: lub-dub, two soft dull beats, and
  /// a tiny tail after the dub.
  static const heartbeat = HapticPattern('heartbeat', [
    HapticEvent.transient(0, intensity: 0.6, sharpness: 0.15),
    HapticEvent.transient(130, intensity: 0.4, sharpness: 0.1),
    HapticEvent.continuous(140, 100, intensity: 0.25, sharpness: 0.05),
  ], [
    HapticCurve(HapticCurveParameter.intensity, [(140, 1), (240, 0)]),
  ]);

  /// A combo leg won: two bright ticks, the second brighter, and a short
  /// shimmer fading after them.
  static const legWon = HapticPattern('legWon', [
    HapticEvent.transient(0, intensity: 0.65, sharpness: 0.9),
    HapticEvent.transient(90, intensity: 0.8, sharpness: 1),
    HapticEvent.continuous(100, 120, intensity: 0.3, sharpness: 0.85),
  ], [
    HapticCurve(HapticCurveParameter.intensity, [(100, 1), (220, 0)]),
  ]);

  /// A combo leg lost: one soft, dull thud that fades.
  static const legLost = HapticPattern('legLost', [
    HapticEvent.transient(0, intensity: 0.5, sharpness: 0.08),
    HapticEvent.continuous(0, 220, intensity: 0.4, sharpness: 0.05),
  ], [
    HapticCurve(HapticCurveParameter.intensity, [(0, 1), (220, 0)]),
  ]);

  /// An Investing order filled or a take-profit hit: a brief whoosh into
  /// a firm snap.
  static const fill = HapticPattern('fill', [
    HapticEvent.continuous(0, 110, intensity: 1, sharpness: 0.3),
    HapticEvent.transient(110, intensity: 0.95, sharpness: 0.85),
  ], [
    HapticCurve(
        HapticCurveParameter.intensity, [(0, 0.1), (105, 0.7), (110, 1)]),
  ]);

  /// An Investing trigger fired or a level is near: one light tap.
  static const notice = HapticPattern('notice', [
    HapticEvent.transient(0, intensity: 0.5, sharpness: 0.5),
  ]);

  /// An Investing warning: three hard, sharp hits, 70 ms apart (closer
  /// and firmer than anything else).
  static const warning = HapticPattern('warning', [
    HapticEvent.transient(0, intensity: 1, sharpness: 0.9),
    HapticEvent.transient(70, intensity: 1, sharpness: 0.9),
    HapticEvent.transient(140, intensity: 1, sharpness: 0.9),
  ]);
}
