// lib/services/success_feedback.dart
//
// Apple Pay style success feedback for money moments — placing a bet or
// order, completing a move or deposit, sending or buying bitcoin.
//
// The signature is the two-beat "dun-DUN": a medium tap followed ~90ms
// later by a heavy one, matching the cadence Apple Pay plays when a
// payment is authorized. On Android we use the `vibration` package's
// waveform API to shape the same two beats with amplitude control
// (soft 35ms beat, 60ms gap, strong 60ms beat); devices without custom
// vibration support fall back to the same two impact haptics iOS uses.
//
// This is feedback, not an action — no analytics event fires here.
//
// Fire it ONCE per success, at the single choke point where the success
// surface appears (the shared overlays' entrance), never in both the
// caller and the overlay.
//
// The other named patterns (money arriving, scores, odds ticks, alerts)
// live in kute_haptics.dart.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

import 'package:kute/services/kute_haptics.dart';

/// One in-flight guard so a double-wired success (e.g. an overlay pushed
/// twice in the same frame) can't stack two overlapping choreographies.
bool _running = false;

/// Two-beat Apple Pay style success haptic. Safe to call from any
/// platform; failures are swallowed (haptics are never worth a crash).
Future<void> moneySuccessFeedback() async {
  if (_running) return;
  // Money that just buzzed as it arrived is the same moment (the receive
  // screen's confirmation over a detected payment): one pattern, not two.
  if (!KuteHaptics.claimMoneySuccess()) return;
  _running = true;
  try {
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
