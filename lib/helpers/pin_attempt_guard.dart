import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/models/auth_model.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/services/tracking_service.dart';

/// Where a PIN was typed.
enum PinSurface {
  /// The cold-start PIN screen and the in-place lock overlay.
  lockScreen,

  /// A confirmation sheet opened from an unlocked app.
  sheet,
}

enum PinFailureAction {
  /// Stay on the surface; [PinFailureOutcome.lockout] may be non-zero.
  retry,

  /// A sheet reached the threshold: lock the app and dismiss the sheet.
  lockApp,

  /// The lock screen passed the last attempt: wipe as today.
  wipe,
}

class PinFailureOutcome {
  const PinFailureOutcome(this.action, this.attempts, this.lockout);
  final PinFailureAction action;
  final int attempts;
  final Duration lockout;
}

/// True after a confirmation sheet locked the app, so the lock overlay can
/// say why. Cleared when the app unlocks.
final pinSheetLockedProvider = StateProvider<bool>((ref) => false);

/// One attempt counter for every surface that accepts the Kute PIN, stored
/// in the existing `failed_pin_attempts` and `lockout_until` keys.
///
/// - The lock screen keeps today's escalation and wipes after the sixth
///   wrong PIN.
/// - A sheet never wipes: the counter stops at [sheetThreshold], the
///   300 s lockout applies and the app locks, so the next wrong PIN on the
///   lock screen follows the wipe path.
/// - With `allowWipe: false` (a start whose storage binding did not match)
///   the lock screen behaves like a sheet but stays on screen.
class PinAttemptGuard {
  PinAttemptGuard(this._auth, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final AuthModel _auth;
  final DateTime Function() _now;

  static const int sheetThreshold = 5;

  Future<int> attempts() => _auth.getFailedAttempts();

  Future<Duration> lockoutRemaining() async {
    final until = await _auth.getLockoutUntil();
    if (until == null) return Duration.zero;
    final remaining = until.difference(_now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Records one wrong PIN. Call only for [PinCheck.mismatch]; a missing or
  /// unreadable PIN never counts.
  Future<PinFailureOutcome> recordFailure({
    required PinSurface surface,
    bool allowWipe = true,
    String analyticsSurface = 'pin_gate',
  }) async {
    final wipes = surface == PinSurface.lockScreen && allowWipe;
    var attempts = await _auth.getFailedAttempts() + 1;
    if (!wipes && attempts > sheetThreshold) attempts = sheetThreshold;
    await _auth.setFailedAttempts(attempts);

    if (surface == PinSurface.sheet) {
      TrackingService.pinGateFailed(
          surface: analyticsSurface, attempt: attempts);
    } else {
      TrackingService.pinFailed(attemptNumber: attempts);
    }

    final seconds = AuthModel.getLockoutDuration(attempts);
    if (seconds < 0) {
      return PinFailureOutcome(PinFailureAction.wipe, attempts, Duration.zero);
    }
    final lockout = Duration(seconds: seconds);
    if (seconds > 0) {
      await _auth.setLockoutUntil(_now().add(lockout));
      if (surface == PinSurface.lockScreen) {
        TrackingService.accountLocked(lockoutSeconds: seconds);
      }
    }
    if (surface == PinSurface.sheet && attempts >= sheetThreshold) {
      TrackingService.pinSheetLockout();
      return PinFailureOutcome(PinFailureAction.lockApp, attempts, lockout);
    }
    return PinFailureOutcome(PinFailureAction.retry, attempts, lockout);
  }

  Future<void> recordSuccess() => _auth.resetFailedAttempts();
}

/// Locks the app from a confirmation sheet that reached the threshold.
void lockAppAfterSheetLockout(WidgetRef ref) {
  ref.read(pinSheetLockedProvider.notifier).state = true;
  ref.read(appLockedProvider.notifier).state = true;
}
