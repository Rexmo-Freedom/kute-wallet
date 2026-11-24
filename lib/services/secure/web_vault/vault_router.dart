// lib/services/secure/web_vault/vault_router.dart
//
// Web only: the flutter_secure_storage platform the app talks to on the
// web. It replaces the plugin's localStorage implementation (which kept
// the raw AES key beside the ciphertext) so every caller of
// `secureStorage` / `SecretStores` is covered without changing:
//
//   * secret keys (vault_keys.dart) go to the [SeedVault]; reading one
//     that exists waits until the vault is unlocked; writing one while
//     locked throws [VaultLockedException];
//   * ordinary keys go to a plain IndexedDB store, cached in memory;
//   * the old localStorage layout ([legacy]) is read as a fallback until
//     the first successful PIN unlock migrates it (see [WebVaultService]).
//
// Nothing here writes to localStorage or sessionStorage.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';

import 'package:kute/services/auth/pin_hash.dart';
import 'package:kute/services/secure/web_vault/seed_vault.dart';
import 'package:kute/services/secure/web_vault/vault_keys.dart';

/// The old flutter_secure_storage_web layout in localStorage.
class LegacyWebStore {
  LegacyWebStore({
    required this.platform,
    required this.options,
    required this.names,
    required this.rawKeyPresent,
  });

  /// The plugin's own implementation (FlutterSecureStorageWeb).
  final FlutterSecureStoragePlatform platform;
  final Map<String, String> options;

  /// Key names stored in the old layout, read from localStorage key names
  /// only (nothing is decrypted to list them).
  final Set<String> Function() names;

  /// The raw AES key entry (`FlutterSecureStorage`) is still there.
  final bool Function() rawKeyPresent;

  bool get isEmpty => names().isEmpty && !rawKeyPresent();

  Future<String?> read(String key) =>
      platform.read(key: key, options: options);
  Future<void> delete(String key) =>
      platform.delete(key: key, options: options);
  Future<void> deleteAll() => platform.deleteAll(options: options);
}

enum WebPinCheck { match, mismatch, noPinMaterial, unavailable }

/// What the last unlock's migration did, for the debug console and tests.
enum WebMigration { none, done, failedKeptOld }

/// The web secure storage: vault, plain store and the legacy fallback.
class VaultStoragePlatform extends FlutterSecureStoragePlatform {
  VaultStoragePlatform({
    required this.vault,
    required Map<String, String> plain,
    this.legacy,
  }) : _plain = Map.of(plain);

  final SeedVault vault;
  final LegacyWebStore? legacy;
  final Map<String, String> _plain;

  /// Set when the PIN verified against the old layout but the vault could
  /// not be created: the old copies serve this session, and the migration
  /// is retried at the next unlock.
  bool _legacyUnlocked = false;
  Completer<void> _legacySignal = Completer<void>();

  bool get unlocked => vault.isOpen || _legacyUnlocked;

  Set<String> _legacyNames() => legacy?.names() ?? const {};

  /// Resolves true once secrets may be read, false when wiped first.
  Future<bool> _whenUnlocked(String key) async {
    if (unlocked) return true;
    debugPrint('Web vault: a secret read waits for unlock '
        '(${_category(key)}).');
    final open = vault.whenOpen();
    final legacyOpen = _legacySignal.future.then((_) => true);
    return Future.any([open, legacyOpen]);
  }

  static String _category(String key) {
    for (final rule in webVaultKeyClasses) {
      if (rule.secret && rule.matches(key)) return rule.pattern;
    }
    return 'secret';
  }

  // ── Session ───────────────────────────────────────────────────────────

  void lock() {
    vault.lock();
    _legacyUnlocked = false;
    if (_legacySignal.isCompleted) _legacySignal = Completer<void>();
  }

  void _markLegacyUnlocked() {
    _legacyUnlocked = true;
    if (!_legacySignal.isCompleted) _legacySignal.complete();
  }

  // ── Platform interface ────────────────────────────────────────────────

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    if (!isVaultSecretKey(key)) {
      final value = _plain[key];
      if (value != null) return value;
      if (_legacyNames().contains(key)) return legacy!.read(key);
      return null;
    }
    // Absent is not secret: answer at once, locked or not.
    final inVault = vault.has(key);
    if (!inVault && !_legacyNames().contains(key)) return null;
    if (!await _whenUnlocked(key)) return null;
    if (vault.isOpen && vault.has(key)) return vault.read(key);
    if (_legacyNames().contains(key)) return legacy!.read(key);
    return null;
  }

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    if (isVaultSecretKey(key)) {
      if (!vault.isOpen) throw const VaultLockedException();
      await vault.write(key, value);
    } else {
      assert(!looksLikeSecretValue(value),
          'A recovery-phrase-like value was written to the ordinary key "$key".');
      _plain[key] = value;
      await vault.db.writePlain(key, value);
    }
    if (_legacyNames().contains(key)) await legacy!.delete(key);
  }

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    if (isVaultSecretKey(key)) {
      await vault.delete(key);
    } else {
      _plain.remove(key);
      await vault.db.deletePlain(key);
    }
    if (_legacyNames().contains(key)) await legacy!.delete(key);
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async {
    if (isVaultSecretKey(key)) {
      return vault.has(key) || _legacyNames().contains(key);
    }
    return _plain.containsKey(key) || _legacyNames().contains(key);
  }

  /// Ordinary values, plus secrets only while unlocked.
  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async {
    final out = <String, String>{};
    for (final name in _legacyNames()) {
      if (isVaultSecretKey(name) && !unlocked) continue;
      final value = await legacy!.read(name);
      if (value != null) out[name] = value;
    }
    out.addAll(_plain);
    if (vault.isOpen) {
      for (final name in vault.names.toList()) {
        final value = await vault.read(name);
        if (value != null) out[name] = value;
      }
    }
    return out;
  }

  /// "Wipe everything": the vault, its device key, the plain store and the
  /// old localStorage layout.
  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    lock();
    _plain.clear();
    Object? failure;
    try {
      await vault.wipe();
    } catch (e) {
      failure = e;
    }
    try {
      await legacy?.deleteAll();
    } catch (e) {
      failure ??= e;
    }
    if (failure != null) throw failure;
  }

  // ── Migration of the old layout ───────────────────────────────────────

  /// Boot: copies the old layout's ORDINARY values into the plain store
  /// (they are needed before the PIN: attempt counters, the binding).
  /// Nothing is deleted here and no secret is decrypted.
  Future<void> copyOrdinaryFromLegacy() async {
    final old = legacy;
    if (old == null) return;
    for (final name in _legacyNames()) {
      if (isVaultSecretKey(name) || _plain.containsKey(name)) continue;
      try {
        final value = await old.read(name);
        if (value == null) continue;
        _plain[name] = value;
        await vault.db.writePlain(name, value);
      } catch (_) {
        // Read through the legacy fallback until the next try.
      }
    }
  }

  /// The PIN material the boot classification sees: the vault, or the old
  /// layout's `pin_hash` / `pin` until it is migrated.
  bool get hasPinMaterial {
    if (vault.exists) return true;
    final names = _legacyNames();
    return names.contains('pin_hash') || names.contains('pin');
  }

  WebMigration lastMigration = WebMigration.none;

  /// Verifies [pin]. With a vault: by its AES-GCM tag. Without one but with
  /// the old layout: against the old `pin_hash`, then a vault is created
  /// with this PIN and the old values move into it. Any old data left
  /// over is migrated on every successful unlock until none is left.
  Future<WebPinCheck> checkPin(String pin) async {
    if (vault.exists) {
      switch (await vault.unlock(pin)) {
        case VaultUnlock.wrongPin:
          return WebPinCheck.mismatch;
        case VaultUnlock.unavailable:
          return WebPinCheck.unavailable;
        case VaultUnlock.ok:
          await migrateLegacy();
          return WebPinCheck.match;
      }
    }
    final old = legacy;
    final names = _legacyNames();
    if (old == null || (!names.contains('pin_hash') && !names.contains('pin'))) {
      return WebPinCheck.noPinMaterial;
    }
    final bool matches;
    try {
      final hash = names.contains('pin_hash') ? await old.read('pin_hash') : null;
      if (hash != null) {
        matches = await PinHashHelper.verifyPinAsync(pin, hash);
      } else {
        final plain = await old.read('pin');
        if (plain == null) return WebPinCheck.unavailable;
        matches = plain == pin;
      }
    } catch (_) {
      return WebPinCheck.unavailable;
    }
    if (!matches) return WebPinCheck.mismatch;
    try {
      await vault.create(pin);
    } catch (_) {
      // The old layout keeps serving; the next unlock tries again.
      _markLegacyUnlocked();
      lastMigration = WebMigration.failedKeptOld;
      return WebPinCheck.match;
    }
    await migrateLegacy();
    return WebPinCheck.match;
  }

  static const Set<String> _neverMigrated = {'pin_hash', 'pin', 'biometric_pin'};

  /// Moves every old value into the vault (secrets) or the plain store
  /// (ordinary), verifies each by reading it back, and only then deletes
  /// the old layout, the raw AES key and the old `pin_hash` included. On
  /// any failure nothing old is deleted and the session reads the old
  /// copies for what the vault lacks.
  Future<WebMigration> migrateLegacy() async {
    final old = legacy;
    if (old == null || old.isEmpty) return lastMigration = WebMigration.none;
    try {
      for (final name in _legacyNames().toList()) {
        if (_neverMigrated.contains(name)) continue;
        if (isVaultSecretKey(name)) {
          // A vault copy is newer (written after a partial migration).
          if (vault.has(name)) continue;
          final value = await old.read(name);
          if (value == null) {
            throw StateError('An old secret did not decrypt');
          }
          await vault.write(name, value);
          if (await vault.read(name) != value) {
            throw StateError('Vault read-back mismatch');
          }
        } else {
          if (_plain.containsKey(name)) continue;
          final value = await old.read(name);
          if (value == null) continue;
          _plain[name] = value;
          await vault.db.writePlain(name, value);
        }
      }
      // Every old secret is readable from the vault now.
      for (final name in _legacyNames()) {
        if (_neverMigrated.contains(name)) continue;
        if (isVaultSecretKey(name) && !vault.has(name)) {
          throw StateError('Vault is missing a migrated secret');
        }
      }
      await old.deleteAll();
      if (!old.isEmpty) throw StateError('Old entries survived the delete');
      _legacyUnlocked = false;
      return lastMigration = WebMigration.done;
    } catch (_) {
      return lastMigration = WebMigration.failedKeptOld;
    }
  }
}
