// lib/services/success_feedback.dart
//
// Success feedback for money moments — placing a bet or order, completing
// a move or deposit, sending or buying bitcoin.
//
// The signature is [HapticPatterns.success], the same family as the
// rubber band's success release so a send, a bet or an order placed
// feels the same everywhere: a short whoosh (a 100 ms swell) into a
// double snap, "dun-DUN", 90 ms apart. It plays on the native engine
// ([ContinuousHaptics.play]: Core Haptics on iOS, the same events as an
// amplitude waveform on Android). A phone that cannot play it falls back
// to today's two beats: the `vibration` waveform on Android with custom
// vibration support (soft 35ms beat, 60ms gap, strong 60ms beat), else a
// medium tap followed ~90ms later by a heavy one.
//
// A rubber band that just released on success already played it: the
// beat stays quiet then ([KuteHaptics.noteSuccessRelease]).
//
// This is feedback, not an action — no analytics event fires here.
//
// Fire it ONCE per success, at the single choke point where the success
// surface appears (the shared overlays' entrance), never in both the
// caller and the overlay.
//
// Failure feedback is its mirror: [moneyFailureFeedback], the soft tap
// ([HapticPatterns.softRelease]) a rubber band plays when it lets go
// without, for a send, a Move or a receive request that failed. Never on
// a cancel or a decline by the person (a face scan cancelled, a sheet
// closed): only where the action really failed.
//
// The other named patterns (money arriving, scores, odds ticks, alerts)
// live in kute_haptics.dart.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:vibration/vibration.dart';

import 'package:kute/services/continuous_haptics.dart';
import 'package:kute/services/haptic_patterns.dart';
import 'package:kute/services/kute_haptics.dart';

/// One in-flight guard so a double-wired success (e.g. an overlay pushed
/// twice in the same frame) can't stack two overlapping choreographies.
bool _running = false;

/// The money-success haptic: the whoosh and the double snap. Safe to
/// call from any platform; failures are swallowed (haptics are never
/// worth a crash).
Future<void> moneySuccessFeedback() async {
  if (_running) return;
  // Money that just buzzed as it arrived is the same moment (the receive
  // screen's confirmation over a detected payment): one pattern, not two.
  if (!KuteHaptics.claimMoneySuccess()) return;
  _running = true;
  try {
    const pattern = HapticPatterns.success;
    if (await ContinuousHaptics.play(pattern)) {
      // Held while it plays, so a double-wired success cannot stack.
      await Future<void>.delayed(pattern.duration);
      return;
    }
    if (!kIsWeb && Platform.isAndroid) {
      bool custom = false;
      try {
        custom = await Vibration.hasCustomVibrationsSupport();
      } catch (_) {}
      if (custom) {
        // [wait, beat, gap, beat] with per-segment amplitude — a soft
        // first tap, then the strong landing beat.
        await Vibration.vibrate(
          pattern: [0, 35, 60, 60],
          intensities: [0, 120, 0, 255],
        );
        return;
      }
    }
    // iOS (and Android without waveform support): the two-impact beat.
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 90));
    await HapticFeedback.heavyImpact();
  } catch (_) {
    // Haptics are best-effort.
  } finally {
    _running = false;
  }
}

/// The money-failure haptic: [HapticPatterns.softRelease], the soft tap
/// the bets' and orders' rubber band plays when it lets go without,
/// through the same path ([ContinuousHaptics.softTap]; without the native
/// bridge, a light impact). For a money action that failed where no band
/// releases: a send, a Move, a receive the person asked for.
///
/// Call it only for a real failure, never for a cancel or a decline by
/// the person. It plays only in the foreground, and once per failure
/// ([KuteHaptics.claimFailureRelease]): a band that just let go with the
/// same tap, or a second path reporting the same failure, stays quiet.
/// Safe to call from anywhere; failures are swallowed.
Future<void> moneyFailureFeedback() async {
  try {
    if (!KuteHaptics.isForeground) return;
    if (!KuteHaptics.claimFailureRelease()) return;
    ContinuousHaptics.softTap();
  } catch (_) {
    // Haptics are best-effort.
  }
}

/// [moneyFailureFeedback] for a send whose Send block wears the send's
/// rubber band (`SendRubberBand`, which lets go without a tap because its
/// stop may be a declined scan): it plays once [busy] is false and the
/// frame that lets the band go has run, so the band's rumble has stopped
/// first (on Android that stop cancels the vibrator and would cut a tap
/// played under it). [busy] is the band's own `busy` (false once the
/// screen is gone). Gives up after [timeout] of busy.
void moneyFailureFeedbackAfterBand(bool Function() busy,
    {Duration timeout = const Duration(seconds: 30)}) {
  final WidgetsBinding binding;
  try {
    binding = WidgetsBinding.instance;
  } catch (_) {
    unawaited(moneyFailureFeedback());
    return;
  }
  final until = DateTime.now().add(timeout);
  void check(Duration _) {
    bool waiting;
    try {
      waiting = busy();
    } catch (_) {
      waiting = false;
    }
    if (waiting) {
      if (DateTime.now().isAfter(until)) return;
      binding.addPostFrameCallback(check);
      return;
    }
    unawaited(moneyFailureFeedback());
  }

  binding.addPostFrameCallback(check);
  binding.ensureVisualUpdate();
}
