import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Android options shared by both instances. They must stay byte-identical:
/// both instances use the same prefs file and the first native init wins.
///
/// - `encryptedSharedPreferences: true` is still read on the upgrade path
///   from the 9.x EncryptedSharedPreferences store.
/// - `resetOnError: false` makes decryption and migration errors surface to
///   Dart instead of deleting every stored secret.
const _legacyAndroidOptions = AndroidOptions(
  // ignore: deprecated_member_use
  encryptedSharedPreferences: true,
  resetOnError: false,
);

/// Centralized secure storage instance with platform-specific options.
///
/// Use this everywhere instead of creating your own FlutterSecureStorage
/// instances to ensure consistent behavior across iOS and Android.
///
/// - Android: key wrapped by the non-exportable Android Keystore;
///   `allowBackup="false"` in the manifest keeps even the ciphertext out of
///   Google backups.
/// - iOS: default Keychain (no group ID, not shared with extensions),
///   `...ThisDeviceOnly` accessibility so secrets are excluded from
///   encrypted device backups and never migrate off this device. Recovery
///   is by 12-word phrase (BIP39) or the OS-synced passkey and re-derivation.
///
/// Seed and PIN material in this store is written and deleted through
/// `KeychainLocal` so a synced iCloud Keychain twin under the same key is
/// never purged.
const secureStorage = FlutterSecureStorage(
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
  aOptions: _legacyAndroidOptions,
);

/// READ-ONLY for seed material. Allowed mutations: the one-time delete of
/// the retired passkey recovery manifest and the legacy credential id
/// delete. A source-scan test enforces this.
///
/// - iOS: iCloud Keychain items written by earlier builds
///   (`synchronizable: true`).
/// - Android: the same prefs file as [secureStorage].
const syncedSecureStorage = FlutterSecureStorage(
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
    synchronizable: true,
  ),
  aOptions: _legacyAndroidOptions,
);
