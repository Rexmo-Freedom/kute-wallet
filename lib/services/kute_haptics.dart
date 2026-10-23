// lib/services/kute_haptics.dart
//
// The named haptic patterns for things that HAPPEN (as opposed to things
// the person taps, which keep their plain `HapticFeedback` calls): money
// arriving, the odds moving on the open market, the last seconds of a held
// round, a combo leg resolving, an Investing alert. The money-success beat
// stays in success_feedback.dart.
//
// Each plays its own pattern on the native engine ([HapticPatterns], the
// way Instagram builds theirs: a continuous base layer under intensity and
// sharpness curves, sharp transients on top, swells into snaps), through
// [ContinuousHaptics.play]: Core Haptics on iOS, the same events rendered
// as an amplitude waveform on Android. A phone that cannot play them (no
// Core Haptics, Android without amplitude control) plays today's beats
// below instead: the system impacts, or the `vibration` waveform.
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
//     plays first, the other stays quiet for a few seconds; a rubber
//     band's success release is that beat too ([noteSuccessRelease]), so
//     an overlay right after it does not play it again;
//   * the failure soft tap is one moment too: a rubber band's release
//     without ([noteFailureRelease]) or a failure tap
//     ([claimFailureRelease], `moneyFailureFeedback`) keeps a second one
//     for the same failure quiet.
//
// This is feedback, not an action: no analytics event fires here.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

import 'package:kute/services/continuous_haptics.dart';
import 'package:kute/services/haptic_patterns.dart';
import 'package:kute/services/haptic_lifecycle.dart';

enum KuteHaptic {
  /// Money landed in Bitcoin or in Dollars: a soft rising swell, one
  /// clean snap, a short fading tail ([HapticPatterns.moneyIn]).
  moneyIn(minGapMs: 3000),

  /// The open market's price moved a point: the lightest, crispest tick.
  oddsTick(minGapMs: 1000),

  /// Last seconds of a held round: a soft "lub-dub" with a tiny tail,
  /// once a second.
  heartbeat(minGapMs: 900),

  /// A combo leg won: two bright ticks and a short shimmer.
  legWon(minGapMs: 1500),

  /// A combo leg lost: one soft, dull thud that fades.
  legLost(minGapMs: 1500),

  /// An Investing order filled or a take-profit hit: a brief whoosh into
  /// a firm snap.
  fill(minGapMs: 1500),

  /// An Investing trigger fired or a level is near: one light tap.
  notice(minGapMs: 1500),

  /// An Investing warning (liquidation, stop-loss near, a cancelled
  /// order): three hard, sharp hits, close together.
  warning(minGapMs: 1500);

  const KuteHaptic({required this.minGapMs});

  /// The least time between two plays of this pattern.
  final int minGapMs;

  /// Its pattern on the native engine ([HapticPatterns]).
  HapticPattern get pattern => switch (this) {
        KuteHaptic.moneyIn => HapticPatterns.moneyIn,
        KuteHaptic.oddsTick => HapticPatterns.oddsTick,
        KuteHaptic.heartbeat => HapticPatterns.heartbeat,
        KuteHaptic.legWon => HapticPatterns.legWon,
        KuteHaptic.legLost => HapticPatterns.legLost,
        KuteHaptic.fill => HapticPatterns.fill,
        KuteHaptic.notice => HapticPatterns.notice,
        KuteHaptic.warning => HapticPatterns.warning,
      };
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

/// Today's beats, kept as the fallback for a phone that cannot play the
/// native patterns.
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

  /// How long the money-success beat stays quiet after a rubber band's
  /// success release played the same pattern (a sheet closing onto its
  /// confirmation within [RubberBand.snapSettle] and a frame or two).
  static const Duration successAfterRelease = Duration(seconds: 2);

  /// How long the failure soft tap stays quiet after it played (a rubber
  /// band's release without, or `moneyFailureFeedback`): one failure, one
  /// tap, however many paths report it.
  static const Duration failureAfterRelease = Duration(seconds: 1);

  static final Map<KuteHaptic, DateTime> _lastPlayed = {};
  static DateTime? _lastMoneySuccess;
  static DateTime? _lastRelease;
  static DateTime? _lastFailureRelease;
  static bool _running = false;

  @visibleForTesting
  static void debugReset() {
    debugOverride = null;
    debugForeground = null;
    debugNow = null;
    _lastPlayed.clear();
    _lastMoneySuccess = null;
    _lastRelease = null;
    _lastFailureRelease = null;
    _running = false;
  }

  static DateTime _now() => (debugNow ?? DateTime.now)();

  /// True while the app is on screen, including a biometric prompt Kute
  /// opened. An unknown lifecycle state counts as on screen too.
  static bool get isForeground {
    final seam = debugForeground;
    if (seam != null) return seam();
    return HapticLifecycle.isForeground;
  }

  /// Asked by `moneySuccessFeedback` before it plays. False when money
  /// arriving has just buzzed for the same moment.
  static bool claimMoneySuccess() {
    final now = _now();
    final arrived = _lastPlayed[KuteHaptic.moneyIn];
    if (arrived != null && now.difference(arrived) < successAfterMoneyIn) {
      return false;
    }
    final released = _lastRelease;
    if (released != null && now.difference(released) < successAfterRelease) {
      return false;
    }
    _lastMoneySuccess = now;
    return true;
  }

  /// Whether the money-success beat played moments ago (a band's success
  /// release, a confirmation's beat): a second surface marking the same
  /// moment (a money-steps tree's last check) stays quiet.
  static bool get moneySuccessJustPlayed {
    final last = _lastMoneySuccess;
    return last != null && _now().difference(last) < successAfterRelease;
  }

  /// A rubber band's success release just played [HapticPatterns.success]
  /// (a send, a bet, an order placed): it is the money-success moment,
  /// so the overlay's beat and money arriving right after it stay quiet.
  static void noteSuccessRelease() {
    final now = _now();
    _lastRelease = now;
    _lastMoneySuccess = now;
  }

  /// A rubber band's release without just played the soft tap
  /// ([HapticPatterns.softRelease]): a failure tap for the same failure
  /// right after it stays quiet.
  static void noteFailureRelease() => _lastFailureRelease = _now();

  /// Asked by `moneyFailureFeedback` before it plays: false when the soft
  /// tap already played for this failure (a band's release, or another
  /// path reporting the same failure).
  static bool claimFailureRelease() {
    final now = _now();
    final last = _lastFailureRelease;
    if (last != null && now.difference(last) < failureAfterRelease) {
      return false;
    }
    _lastFailureRelease = now;
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
      } else if (await ContinuousHaptics.play(pattern.pattern)) {
        // Native: held for as long as it plays (one pattern at a time).
        await Future<void>.delayed(pattern.pattern.duration);
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

  /// Today's beats: what a phone that cannot play the native pattern
  /// feels.
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
          pattern: [
            for (final b in beats) ...[b.waitMs, b.ms]
          ],
          intensities: [
            for (final b in beats) ...[0, b.amplitude]
          ],
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
