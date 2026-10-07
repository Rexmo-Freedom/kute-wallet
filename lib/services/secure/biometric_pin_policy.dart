import 'package:kute/models/settings_model.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/services/secure/recovery_check.dart';
import 'package:kute/services/secure/secret_store.dart';
import 'package:kute/services/tracking_service.dart';

enum StoredPinState { present, absent, failed }

/// Whether some stored wallet can only be read with the Kute PIN.
class V1Dependency {
  const V1Dependency({required this.exists, required this.biometricPin});

  /// Used when the evaluation itself failed: keep everything.
  static const unknown =
      V1Dependency(exists: true, biometricPin: StoredPinState.failed);

  /// A stored-seed wallet has no PIN-free copy but has a PIN-encrypted
  /// one, or a read failed.
  final bool exists;

  /// The state of `biometric_pin` when this was evaluated.
  final StoredPinState biometricPin;
}

/// Decides whether the raw `biometric_pin` copy stays (D-3).
///
/// It stays only where a stored-seed wallet (not passkey, hardware,
/// watch-only or external address) would need the PIN to read its seed:
/// no V2 copy (local or synced) and a V1 copy, or no V1 copy and an
/// encrypted root. A plaintext root needs no PIN. Any failed read keeps it.
class BiometricPinPolicy {
  BiometricPinPolicy({SecretStore? store, SecretStore? syncedStore})
      : _store = store ?? SecretStores.local,
        _syncedStore = syncedStore ?? SecretStores.synced;

  final SecretStore _store;
  final SecretStore _syncedStore;

  static const String _key = 'biometric_pin';

  Future<V1Dependency> evaluate(List<WalletConfig> wallets) async {
    try {
      final biometricPin = switch (await _store.read(key: _key)) {
        SecretPresent(:final value) when value.isNotEmpty =>
          StoredPinState.present,
        SecretFailed() => StoredPinState.failed,
        _ => StoredPinState.absent,
      };
      SecretRead? root;
      var exists = false;
      for (final wallet in wallets.where(RecoveryCheck.holdsStoredSeed)) {
        final v2Key = 'v2:wallet:${wallet.id}.mnemonic';
        final local = await _store.read(key: v2Key);
        if (_hasValue(local)) continue;
        final synced = await _syncedStore.read(key: v2Key);
        if (_hasValue(synced)) continue;
        if (local is SecretFailed || synced is SecretFailed) {
          exists = true;
          break;
        }
        final v1 = await _store.read(key: 'mnemonic_${wallet.id}');
        if (v1 is! SecretAbsent) {
          exists = true;
          break;
        }
        root ??= await _store.read(key: 'mnemonic');
        if (root is SecretFailed ||
            (root is SecretPresent && root.value.split(' ').length <= 1)) {
          exists = true;
          break;
        }
      }
      return V1Dependency(exists: exists, biometricPin: biometricPin);
    } catch (_) {
      return V1Dependency.unknown;
    }
  }

  static bool _hasValue(SecretRead read) =>
      read is SecretPresent && read.value.isNotEmpty;

  /// Runs after a verified unlock. Without a dependency a stored
  /// `biometric_pin` is deleted. With one, a verified [typedPin] replaces a
  /// missing or stale copy so biometric unlock keeps working for the wallet
  /// that needs it.
  Future<void> applyAfterUnlock(V1Dependency dependency,
      {String? typedPin}) async {
    try {
      if (!dependency.exists) {
        if (dependency.biometricPin == StoredPinState.present) {
          await _store.deleteLocalOnly(key: _key);
          TrackingService.biometricPinRemoved();
        }
        return;
      }
      if (typedPin == null || typedPin.isEmpty) return;
      final current = await _store.read(key: _key);
      if (current is SecretFailed) return;
      if (current is SecretPresent && current.value == typedPin) return;
      await _store.writeLocalOnly(key: _key, value: typedPin);
    } catch (_) {
      // Left as is; the next unlock evaluates again.
    }
  }
}
