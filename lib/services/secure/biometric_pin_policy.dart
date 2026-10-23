import 'package:kute/models/settings_model.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/services/secure/legacy_keychain_rescue.dart';
import 'package:kute/services/secure/recovery_check.dart';
import 'package:kute/services/secure/secret_store.dart';
import 'package:kute/services/tracking_service.dart';

enum StoredPinState { present, absent, failed }

/// Whether some stored wallet can only be read with the Kute PIN.
class V1Dependency {
  const V1Dependency({
    required this.exists,
    required this.biometricPin,
    this.pinFree = false,
  });

  /// Used when the evaluation itself failed: keep everything.
  static const unknown =
      V1Dependency(exists: true, biometricPin: StoredPinState.failed);

  /// A stored-seed wallet has no PIN-free copy but has a PIN-encrypted
  /// one (through the current store or under the legacy Keychain
  /// accessibility), or a read failed.
  final bool exists;

  /// The state of `biometric_pin` when this was evaluated.
  final StoredPinState biometricPin;

  /// Every stored-seed wallet has a copy readable without the PIN through
  /// the current store (a V2 copy or a plaintext root). Only then is a
  /// stored `biometric_pin` no longer needed: a wallet whose seed cannot
  /// be read at all is unknown, not PIN-free.
  final bool pinFree;
}

/// Decides whether the raw `biometric_pin` copy stays (D-3).
///
/// It stays wherever a stored-seed wallet (not passkey, hardware,
/// watch-only or external address) may need the PIN to read its seed:
/// no V2 copy (local or synced) and a V1 copy, or no V1 copy and an
/// encrypted root, or (iOS) a `mnemonic_{id}` / `v2:wallet:{id}.mnemonic`
/// item the Keychain lists under the legacy accessibility that the store
/// cannot read. A plaintext root needs no PIN. Any failed read, or a
/// failed Keychain listing, counts as a dependency.
/// It is removed only when every stored-seed wallet has a PIN-free copy
/// readable through the current store; plain absence keeps it.
class BiometricPinPolicy {
  BiometricPinPolicy({
    SecretStore? store,
    SecretStore? syncedStore,
    LegacyKeychainLookup? lookup,
  })  : _store = store ?? SecretStores.local,
        _syncedStore = syncedStore ?? SecretStores.synced,
        _lookup =
            lookup ?? const NativeLegacyKeychainLookup(reportListFailures: true);

  final SecretStore _store;
  final SecretStore _syncedStore;
  final LegacyKeychainLookup _lookup;

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
      Set<String>? legacyAccounts;
      var exists = false;
      var pinFree = true;
      for (final wallet in wallets.where(RecoveryCheck.holdsStoredSeed)) {
        final v2Key = LegacyKeychainRescue.v2Key(wallet.id);
        final local = await _store.read(key: v2Key);
        if (_hasValue(local)) continue;
        final synced = await _syncedStore.read(key: v2Key);
        if (_hasValue(synced)) continue;
        pinFree = false;
        if (local is SecretFailed || synced is SecretFailed) {
          exists = true;
          break;
        }
        final v1Key = LegacyKeychainRescue.v1Key(wallet.id);
        final v1 = await _store.read(key: v1Key);
        if (v1 is! SecretAbsent) {
          exists = true;
          break;
        }
        // Attributes only: an old copy the store cannot read still needs
        // the PIN (or is at least not known to be PIN-free).
        legacyAccounts ??= await _listLegacyAccounts();
        // A failed listing is unknown, not absent: an old copy the store
        // cannot read may be there, and only the verified-PIN unlock runs
        // the rescue for it.
        if (legacyAccounts == null ||
            legacyAccounts.contains(v1Key) ||
            legacyAccounts.contains(v2Key)) {
          exists = true;
          break;
        }
        root ??= await _store.read(key: 'mnemonic');
        if (root is SecretFailed ||
            (root is SecretPresent && root.value.split(' ').length <= 1)) {
          exists = true;
          break;
        }
        if (root is SecretPresent) {
          // A plaintext root is copied to the wallet id on read.
          pinFree = true;
        }
      }
      return V1Dependency(
          exists: exists, biometricPin: biometricPin, pinFree: pinFree);
    } catch (_) {
      return V1Dependency.unknown;
    }
  }

  /// The legacy account names, or null when the listing failed.
  Future<Set<String>?> _listLegacyAccounts() async {
    try {
      return {
        ...await _lookup.listAccounts(prefix: 'mnemonic_'),
        ...await _lookup.listAccounts(prefix: 'v2:wallet:'),
      };
    } catch (_) {
      return null;
    }
  }

  static bool _hasValue(SecretRead read) =>
      read is SecretPresent && read.value.isNotEmpty;

  /// Runs after a verified unlock. A stored `biometric_pin` is deleted
  /// only when no wallet depends on the PIN and every stored-seed wallet
  /// has a PIN-free copy the store can read. With a dependency, a verified
  /// [typedPin] replaces a missing or stale copy so biometric unlock keeps
  /// working for the wallet that needs it.
  Future<void> applyAfterUnlock(V1Dependency dependency,
      {String? typedPin}) async {
    try {
      if (!dependency.exists) {
        if (dependency.pinFree &&
            dependency.biometricPin == StoredPinState.present) {
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
