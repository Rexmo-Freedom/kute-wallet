import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/models/auth_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/services/secure/biometric_pin_policy.dart';

/// Evaluates [BiometricPinPolicy] for the wallets in settings.
Future<V1Dependency> evaluateV1Dependency(WidgetRef ref,
    {BiometricPinPolicy? policy}) async {
  final List<WalletConfig> wallets;
  try {
    wallets = ref.read(settingsProvider).wallets;
  } catch (_) {
    return V1Dependency.unknown;
  }
  return (policy ?? BiometricPinPolicy()).evaluate(wallets);
}

sealed class BiometricUnlockCheck {
  const BiometricUnlockCheck();
}

/// Unlock. [storedPin] is the verified `biometric_pin`, set only when a
/// stored wallet still needs the PIN.
final class BiometricUnlockAllowed extends BiometricUnlockCheck {
  const BiometricUnlockAllowed(this.storedPin);
  final String? storedPin;
}

/// Stay on the keypad. [reason] is `stored_pin_null` or `stored_pin_stale`.
final class BiometricUnlockRefused extends BiometricUnlockCheck {
  const BiometricUnlockRefused(this.reason);
  final String reason;
}

/// Runs after the OS biometric prompt succeeded. Without a [dependency]
/// biometrics alone unlock and `biometric_pin` is never read. With one, the
/// stored PIN must exist and still match `pin_hash`; a stale copy (a PIN
/// change interrupted between its writes) is never used, and the typed PIN
/// stores it again.
Future<BiometricUnlockCheck> checkBiometricUnlock(
    AuthModel auth, V1Dependency dependency) async {
  if (!dependency.exists) return const BiometricUnlockAllowed(null);
  final storedPin = await auth.getBiometricPin();
  if (storedPin == null) {
    return const BiometricUnlockRefused('stored_pin_null');
  }
  if (await auth.checkPin(storedPin) != PinCheck.match) {
    return const BiometricUnlockRefused('stored_pin_stale');
  }
  return BiometricUnlockAllowed(storedPin);
}

/// Records a verified unlock or PIN entry. A typed PIN is kept only while
/// [dependency] says a stored wallet still needs it; otherwise any held PIN
/// is dropped.
void markSessionUnlocked(
  WidgetRef ref, {
  required UnlockMethod method,
  required V1Dependency dependency,
  String? typedPin,
}) {
  ref.read(sessionAuthProvider.notifier).state =
      SessionAuth(method: method, unlockedAt: DateTime.now());
  ref.read(typedPinProvider.notifier).state =
      dependency.exists ? (typedPin ?? ref.read(typedPinProvider)) : null;
}

/// Ends the session, for flows that leave onboarding before a wallet exists.
void clearSession(WidgetRef ref) {
  ref.read(sessionAuthProvider.notifier).state = null;
  ref.read(typedPinProvider.notifier).state = null;
}
