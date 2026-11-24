/// The web seed vault as the rest of the app sees it. On iOS, Android and
/// desktop [WebVault.instance] is always null and nothing here runs; the
/// native secure storage paths are untouched.
///
/// See seed_vault.dart for the design and the threat note.
library;

import 'package:flutter/foundation.dart';

import 'package:kute/services/secure/web_vault/vault_router.dart';
import 'web_vault_native.dart'
    if (dart.library.js_interop) 'web_vault_web.dart' as impl;

export 'package:kute/services/secure/web_vault/vault_router.dart'
    show VaultStoragePlatform, WebPinCheck, WebMigration;

abstract final class WebVault {
  static VaultStoragePlatform? _instance;

  /// The installed web storage, or null off the web (and before
  /// [install]).
  static VaultStoragePlatform? get instance => _instance;

  @visibleForTesting
  static set debugInstance(VaultStoragePlatform? value) => _instance = value;

  /// Web boot, before anything touches secure storage: opens the vault
  /// database, copies the old layout's ordinary values and makes every
  /// flutter_secure_storage call go through the vault. Fails closed: when
  /// IndexedDB or WebCrypto is missing, every storage call fails instead of
  /// falling back to localStorage. No-op off the web.
  static Future<void> install() async {
    if (!kIsWeb || _instance != null) return;
    _instance = await impl.installWebVault();
  }

  /// Drops the decrypted vault key (lock, auto-lock, sign-out). No-op off
  /// the web.
  static void lock() => _instance?.lock();
}
