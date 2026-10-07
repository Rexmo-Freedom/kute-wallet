// lib/helpers/session_unlock.dart
//
// Shared post-unlock bootstrap. Two callers:
//   * cold start (`open_pin.dart`'s `_unlockApp`) — runs this then
//     navigates to /home;
//   * the in-place `LockOverlay` (resume relock) — runs this and
//     dismisses itself WITHOUT navigating, so the user resumes on the
//     exact screen they left. Extracted so the Breez bad-state
//     reconnect + prime logic lives in one place.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/helpers/biometry_domain_state.dart';
import 'package:kute/helpers/small_action_allowance.dart';
import 'package:kute/models/breez/sdk_instance.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/services/polymarket/fast_bet_window.dart';
import 'package:kute/services/tracking_service.dart';

/// Step-up session start (Phase 1b, D-11). Called on cold start and each
/// time the lock engages, so the small-action allowance budget starts
/// from zero for the next unlocked session, and the Polymarket fast-bet
/// window ends (the next short-round order prompts again).
void resetStepUpSession() {
  SmallActionAllowance.instance.reset();
  FastBetWindow.instance.end(FastBetWindowEnd.sessionLock);
}

/// D-14 (iOS). After a biometric unlock, stores the current biometry
/// domain state hash, so a face or finger added later makes the next
/// step-up ask for the Kute PIN first. A PIN unlock never stores it.
/// No-op on Android or when the hash is unknown.
Future<void> recordBiometricUnlockDomainState() async {
  final hash = await BiometryDomainState.currentHash();
  if (hash != null) await BiometryDomainState.store(hash);
}

/// Post-unlock session bootstrap: heal a poisoned Breez provider and
/// prime the SDK connection so the wallet doesn't read "offline" right
/// after unlock. Deliberately does NOT navigate and does NOT touch
/// send-tx state; callers own those decisions (cold start resets and
/// goes home; the resume overlay must leave the live screen alone).
void completeUnlock(WidgetRef ref, {required String method}) {
  TrackingService.appUnlocked(method: method);
  // D-11: the per-action allowance cap is read from the current runtime
  // policy snapshot at each use, so nothing is fetched here.
  // Invalidate ONLY when the cached resolution is in a bad state
  // (error or unexpectedly null). Unconditionally invalidating forced
  // a fresh `crateSdkConnect` FFI handshake on every unlock — observed
  // at ~1 s on real hardware, blocking the main isolate and dropping
  // ~36 frames after each biometric resume. The bad-state case (a
  // `breezSDKProvider` read that fired while the session was still
  // locked and got cached as an error) still gets healed here; healthy
  // resolutions keep their connection.
  final current = ref.read(breezSDKProvider);
  final asData = current is AsyncData<BreezSdkSpark> ? current : null;
  final shouldReconnect = current is AsyncError ||
      (asData != null && asData.value.instance == null);
  if (shouldReconnect) {
    ref.invalidate(breezSDKProvider);
  }
  // Prime the connect so the FFI handshake (when needed) runs in
  // parallel with the unlock transition instead of racing the first
  // widget that watches it.
  ref.read(breezSDKProvider.future).then((_) {}, onError: (_) {});
}
