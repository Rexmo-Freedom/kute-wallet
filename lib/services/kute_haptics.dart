// lib/services/kute_haptics.dart
//
// The named haptic patterns for things that HAPPEN (as opposed to things
// the person taps, which keep their plain `HapticFeedback` calls): money
// arriving, the odds moving on the open market, the last seconds of a held
// round, a combo leg resolving, an Investing alert. The money-success two-beat stays in success_feedback.dart.
//
// Haptics are always on (founder decision): no setting, no preference.
// The OS-level setting still applies, as it does to every haptic.
//
// Rules, enforced here so no call site can forget them:
//   * never in the background;
//   * each pattern has a minimum gap, so nothing buzzes continuously;
//   * one pattern at a time: a pattern asked for while another is still
//     playing is dropped, never queued;
//   * money arriving and the money-success beat are one moment: whichever
//     plays first, the other stays quiet for a few seconds.
//
// This is feedback, not an action: no analytics event fires here.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:vibration/vibration.dart';

enum KuteHaptic {
  /// Money landed in Bitcoin or in Dollars: a soft tap, then a medium one.
  moneyIn(minGapMs: 3000),

  /// The open market's price moved a point: the lightest tick there is.
  oddsTick(minGapMs: 1000),

  /// Last seconds of a held round: a "lub-dub", once a second.
  heartbeat(minGapMs: 900),

  /// A combo leg won: two light taps.
  legWon(minGapMs: 1500),

  /// A combo leg lost: one soft, low tap.
  legLost(minGapMs: 1500),

  /// An Investing order filled or a take-profit hit: one medium tap.
  fill(minGapMs: 1500),

  /// An Investing trigger fired or a level is near: one light tap.
  notice(minGapMs: 1500),

  /// An Investing warning (liquidation, stop-loss near, a cancelled
  /// order): three quick heavy taps.
  warning(minGapMs: 1500);

  const KuteHaptic({required this.minGapMs});

  /// The least time between two plays of this pattern.
  final int minGapMs;
}

enum _Impact { selection, light, medium, heavy }

/// One beat: wait [waitMs], then tap. [ms] and [amplitude] shape the same
/// beat on Android's waveform API.
class _Beat {
  const _Beat(this.waitMs, this.impact, this.ms, this.amplitude);
  final int waitMs;
  final _Impact impact;
  final int ms;
  final int amplitude;
}

const Map<KuteHaptic, List<_Beat>> _patterns = {
  KuteHaptic.moneyIn: [
    _Beat(0, _Impact.light, 25, 90),
    _Beat(110, _Impact.medium, 45, 190),
  ],
  KuteHaptic.oddsTick: [_Beat(0, _Impact.selection, 10, 60)],
  KuteHaptic.heartbeat: [
    _Beat(0, _Impact.medium, 35, 180),
    _Beat(120, _Impact.light, 25, 90),
  ],
  KuteHaptic.legWon: [
    _Beat(0, _Impact.light, 25, 100),
    _Beat(100, _Impact.light, 25, 100),
  ],
  KuteHaptic.legLost: [_Beat(0, _Impact.light, 60, 70)],
  KuteHaptic.fill: [_Beat(0, _Impact.medium, 40, 170)],
  KuteHaptic.notice: [_Beat(0, _Impact.light, 25, 100)],
  KuteHaptic.warning: [
    _Beat(0, _Impact.heavy, 50, 255),
    _Beat(90, _Impact.heavy, 50, 255),
    _Beat(90, _Impact.heavy, 50, 255),
  ],
};

abstract final class KuteHaptics {
  /// Test seam: stands in for the platform output of [play]. The gates
  /// (foreground, minimum gap, one at a time) still run in front of it.
  @visibleForTesting
  static Future<void> Function(KuteHaptic pattern)? debugOverride;

  /// Test seam for the foreground check.
  @visibleForTesting
  static bool Function()? debugForeground;

  /// Test seam for the clock.
  @visibleForTesting
  static DateTime Function()? debugNow;

  /// How long money arriving stays quiet after a money-success beat (the
  /// success overlay already marked the moment), and the other way round.
  static const Duration moneyInAfterSuccess = Duration(seconds: 8);
  static const Duration successAfterMoneyIn = Duration(seconds: 3);

  static final Map<KuteHaptic, DateTime> _lastPlayed = {};
  static DateTime? _lastMoneySuccess;
  static bool _running = false;

  @visibleForTesting
  static void debugReset() {
    debugOverride = null;
    debugForeground = null;
    debugNow = null;
    _lastPlayed.clear();
    _lastMoneySuccess = null;
    _running = false;
  }

  static DateTime _now() => (debugNow ?? DateTime.now)();

  /// True while the app is on screen. An unknown state (before the first
  /// lifecycle message) counts as on screen, as it does elsewhere.
  static bool get isForeground {
    final seam = debugForeground;
    if (seam != null) return seam();
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  /// Asked by `moneySuccessFeedback` before it plays. False when money
  /// arriving has just buzzed for the same moment.
  static bool claimMoneySuccess() {
    final now = _now();
    final arrived = _lastPlayed[KuteHaptic.moneyIn];
    if (arrived != null && now.difference(arrived) < successAfterMoneyIn) {
      return false;
    }
    _lastMoneySuccess = now;
    return true;
  }

  /// Plays [pattern] unless a rule says no. Returns whether it played.
  /// Safe to call from anywhere; failures are swallowed.
  static Future<bool> play(KuteHaptic pattern) async {
    if (!isForeground || _running) return false;
    final now = _now();
    final last = _lastPlayed[pattern];
    if (last != null &&
        now.difference(last) < Duration(milliseconds: pattern.minGapMs)) {
      return false;
    }
    if (pattern == KuteHaptic.moneyIn) {
      final success = _lastMoneySuccess;
      if (success != null && now.difference(success) < moneyInAfterSuccess) {
        return false;
      }
    }
    _lastPlayed[pattern] = now;
    _running = true;
    try {
      final seam = debugOverride;
      if (seam != null) {
        await seam(pattern);
      } else {
        await _emit(_patterns[pattern]!);
      }
    } catch (_) {
      // Haptics are best-effort.
    } finally {
      _running = false;
    }
    return true;
  }

  static Future<void> _emit(List<_Beat> beats) async {
    // Android shapes a multi-beat pattern as one waveform, the way
    // success_feedback.dart does; a single tap stays a system haptic.
    if (beats.length > 1 && !kIsWeb && Platform.isAndroid) {
      var custom = false;
      try {
        custom = await Vibration.hasCustomVibrationsSupport();
      } catch (_) {}
      if (custom) {
        await Vibration.vibrate(
          pattern: [for (final b in beats) ...[b.waitMs, b.ms]],
          intensities: [for (final b in beats) ...[0, b.amplitude]],
        );
        return;
      }
    }
    for (final b in beats) {
      if (b.waitMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: b.waitMs));
      }
      switch (b.impact) {
        case _Impact.selection:
          await HapticFeedback.selectionClick();
        case _Impact.light:
          await HapticFeedback.lightImpact();
        case _Impact.medium:
          await HapticFeedback.mediumImpact();
        case _Impact.heavy:
          await HapticFeedback.heavyImpact();
      }
    }
  }
}
