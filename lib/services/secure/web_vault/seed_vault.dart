// lib/services/secure/web_vault/seed_vault.dart
//
// THE WEB SEED VAULT. Web only; iOS and Android never construct it.
//
// What it protects against:
//   * Reading browser storage. localStorage and sessionStorage hold no
//     secret at all, and IndexedDB holds only ciphertext. A script or
//     extension that can read storage but not run code in this page, a
//     backup or sync of site data, or a dump of localStorage gets nothing
//     usable.
//   * A copied browser profile. The vault key is wrapped under a key
//     stretched from the PIN (PBKDF2-SHA-256, 600,000 iterations) and then
//     under a device key. The device key is a non-extractable WebCrypto key
//     kept as a CryptoKey object in IndexedDB: no script can export it.
//     Note the browser still writes its bytes into the profile folder, so
//     forensic tooling on a copied profile can recover it; after that only
//     the 6-digit PIN is left, and 10^6 guesses at 600k iterations take
//     minutes on a GPU. Treat this as "raises the bar", not "safe".
//   * Another script reading localStorage while the app is locked. The old
//     layout kept the AES key right beside the ciphertext; now nothing in
//     storage decrypts anything without the PIN (or a WebAuthn PRF key).
//   * The locked app. The vault key exists in memory only between a
//     verified PIN (or PRF biometric) and the next lock, auto-lock, wipe or
//     tab close. The PIN is verified by the AES-GCM tag, so there is no
//     fast PIN hash on disk either.
//
// What it CANNOT protect against (do not over-trust it):
//   * A malicious script or extension running inside this page WHILE the
//     wallet is unlocked: it can call the same code the app calls and read
//     the phrase, or sign with keys already in memory.
//   * A script running inside this page while LOCKED can still USE the
//     non-extractable device key (non-extractable stops export, not use),
//     peel that layer and then guess the 6-digit PIN offline. The wrong-PIN
//     counter and wipe are enforced by the app, not by cryptography.
//   * A compromised device, OS or browser, a keylogger, or someone who
//     watches the PIN being typed.
//   * Secrets held by other components after unlock (the Lightning SDK,
//     signers) stay in their memory until the tab closes.
//
// Layout (IndexedDB, database `kute_vault`):
//   meta     one record: salt, iterations, vault id, the vault key K wrapped
//            as Enc_device(Enc_pin(K)), a check value Enc_K(known text),
//            and optionally Enc_device(Enc_prf(K)) for biometric unlock.
//   entries  one record per secret key: Enc_K(value), AAD binds the vault
//            id and the key name so records cannot be swapped.
//   device   the device CryptoKey object.
//   plain    ordinary (non-secret) values, unencrypted.
// Every encryption uses AES-GCM-256 with a fresh random 12-byte IV.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Wrong key or tampered data (AES-GCM tag mismatch).
class VaultTagError implements Exception {
  const VaultTagError();
  @override
  String toString() => 'VaultTagError';
}

/// A secret was written or read while the vault is locked.
class VaultLockedException implements Exception {
  const VaultLockedException();
  @override
  String toString() => 'Wallet locked. Please unlock first.';
}

/// The vault exists but cannot be opened at all (device key missing,
/// storage failure, corrupt record). Never a wrong PIN.
class VaultUnavailableException implements Exception {
  const VaultUnavailableException(this.reason);
  final String reason;
  @override
  String toString() => 'VaultUnavailableException($reason)';
}

/// The WebCrypto operations the vault needs. Keys are opaque handles: on
/// the web they are non-extractable `CryptoKey` objects.
abstract class VaultCrypto {
  Uint8List randomBytes(int length);

  /// A new AES-GCM-256 key, `extractable: false`.
  Future<Object> newDeviceKey();

  /// PBKDF2-SHA-256 of [pin] into a non-extractable AES-GCM-256 key.
  Future<Object> pinKey(String pin, Uint8List salt, int iterations);

  /// HKDF-SHA-256 of [ikm] into a non-extractable AES-GCM-256 key.
  Future<Object> hkdfKey(Uint8List ikm, Uint8List salt, Uint8List info);

  /// [raw] imported as a non-extractable AES-GCM-256 key.
  Future<Object> rawKey(Uint8List raw);

  Future<Uint8List> seal(
      Object key, Uint8List iv, Uint8List plain, Uint8List aad);

  /// Throws [VaultTagError] when the tag does not verify.
  Future<Uint8List> open(
      Object key, Uint8List iv, Uint8List sealed, Uint8List aad);
}

/// The vault's persistence (IndexedDB on the web).
abstract class VaultDb {
  Future<Map<String, Object?>?> readMeta();
  Future<void> writeMeta(Map<String, Object?> meta);
  Future<void> deleteMeta();
  Future<Object?> readDeviceKey();
  Future<void> writeDeviceKey(Object key);
  Future<Map<String, Map<String, Object?>>> readEntries();
  Future<void> writeEntry(String name, Map<String, Object?> entry);
  Future<void> deleteEntry(String name);
  Future<Map<String, String>> readPlain();
  Future<void> writePlain(String name, String value);
  Future<void> deletePlain(String name);

  /// Every store, the device key included.
  Future<void> clear();
}

enum VaultUnlock { ok, wrongPin, unavailable }

/// The biometric (WebAuthn PRF) enrolment of this vault.
@immutable
class VaultPrf {
  const VaultPrf(this.credentialId, this.salt);
  final String credentialId;

  /// The PRF input sent to the authenticator.
  final Uint8List salt;
}

class SeedVault {
  SeedVault({
    required this.crypto,
    required this.db,
    this.iterations = defaultIterations,
  });

  /// OWASP 2023 guidance for PBKDF2-HMAC-SHA256.
  static const int defaultIterations = 600000;
  static const int formatVersion = 1;
  static const String _checkText = 'kute-vault-check-v1';
  static final Uint8List _prfInfo =
      Uint8List.fromList(utf8.encode('kute web vault prf wrap v1'));

  final VaultCrypto crypto;
  final VaultDb db;
  final int iterations;

  Map<String, Object?>? _meta;
  final Map<String, Map<String, Object?>> _entries = {};
  bool _loaded = false;

  Uint8List? _kRaw;
  Object? _kKey;
  Completer<bool> _openSignal = Completer<bool>();

  /// Reads the vault's records. Safe to call again (reload).
  Future<void> load() async {
    _meta = await db.readMeta();
    _entries
      ..clear()
      ..addAll(await db.readEntries());
    _loaded = true;
  }

  void _requireLoaded() {
    if (!_loaded) throw StateError('SeedVault.load() was not called');
  }

  bool get exists {
    _requireLoaded();
    return _meta != null;
  }

  bool get isOpen => _kKey != null;

  String? get _vid => _meta?['vid'] as String?;

  /// Names of the secrets stored in the current vault. Key names are not
  /// secret, so this works while locked.
  Iterable<String> get names =>
      _entries.entries.where((e) => e.value['vid'] == _vid).map((e) => e.key);

  bool has(String name) => _vid != null && _entries[name]?['vid'] == _vid;

  /// Completes with true once the vault is open, or false when it is wiped
  /// first. Waiting callers never see a secret before the PIN.
  Future<bool> whenOpen() => isOpen ? Future.value(true) : _openSignal.future;

  VaultPrf? get prf {
    final p = _meta?['prf'];
    if (p is! Map) return null;
    return VaultPrf(p['cred'] as String, _b(p['salt']));
  }

  // ── Create, unlock, lock ──────────────────────────────────────────────

  /// Starts a new vault for [pin] and opens it. An older vault's entries
  /// stay on disk under their old vault id (unreadable without it, never
  /// deleted here); its meta is replaced.
  Future<void> create(String pin) async {
    _requireLoaded();
    final device = await _deviceKey(create: true);
    final k = crypto.randomBytes(32);
    final vid = _hex(crypto.randomBytes(16));
    final salt = crypto.randomBytes(16);
    final meta = <String, Object?>{
      'v': formatVersion,
      'vid': vid,
      'salt': _s(salt),
      'iter': iterations,
    };
    await _wrapUnderPin(meta, device, k, pin, salt, iterations);
    final kKey = await crypto.rawKey(k);
    final checkIv = crypto.randomBytes(12);
    meta['checkIv'] = _s(checkIv);
    meta['check'] = _s(await crypto.seal(kKey, checkIv,
        Uint8List.fromList(utf8.encode(_checkText)), _aad('check', vid)));
    await db.writeMeta(meta);
    _meta = meta;
    _setOpen(k, kKey);
  }

  /// Verifies [pin] by opening the vault key; the AES-GCM tag is the check.
  Future<VaultUnlock> unlock(String pin) async {
    _requireLoaded();
    final meta = _meta;
    if (meta == null) return VaultUnlock.unavailable;
    final Object device;
    final Uint8List inner;
    try {
      device = await _deviceKey(create: false);
      inner = await crypto.open(device, _b(meta['devIv']), _b(meta['wrapped']),
          _aad('dev', meta['vid'] as String));
    } catch (_) {
      // No device key, or not this vault's: nothing a PIN can fix.
      return VaultUnlock.unavailable;
    }
    final Uint8List k;
    try {
      final pinKey = await crypto.pinKey(
          pin, _b(meta['salt']), (meta['iter'] as num).toInt());
      k = await crypto.open(pinKey, _b(meta['pinIv']), inner,
          _aad('pin', meta['vid'] as String));
    } on VaultTagError {
      return VaultUnlock.wrongPin;
    } catch (_) {
      return VaultUnlock.unavailable;
    }
    return await _openWith(k) ? VaultUnlock.ok : VaultUnlock.unavailable;
  }

  /// Opens the vault with a WebAuthn PRF output for [credentialId]. False
  /// when there is no enrolment for it or the key does not verify.
  Future<bool> unlockWithPrf(String credentialId, Uint8List prfOutput) async {
    _requireLoaded();
    final meta = _meta;
    final p = meta?['prf'];
    if (meta == null || p is! Map || p['cred'] != credentialId) return false;
    try {
      final vid = meta['vid'] as String;
      final device = await _deviceKey(create: false);
      final inner = await crypto.open(
          device, _b(p['devIv']), _b(p['wrapped']), _aad('prfdev', vid));
      final prfKey =
          await crypto.hkdfKey(prfOutput, _b(p['salt']), _prfInfo);
      final k = await crypto.open(prfKey, _b(p['iv']), inner, _aad('prf', vid));
      return await _openWith(k);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _openWith(Uint8List k) async {
    final meta = _meta!;
    try {
      final kKey = await crypto.rawKey(k);
      final check = await crypto.open(kKey, _b(meta['checkIv']),
          _b(meta['check']), _aad('check', meta['vid'] as String));
      if (utf8.decode(check) != _checkText) return false;
      _setOpen(k, kKey);
      return true;
    } catch (_) {
      k.fillRange(0, k.length, 0);
      return false;
    }
  }

  void _setOpen(Uint8List k, Object kKey) {
    if (_kRaw != null && !identical(_kRaw, k)) {
      _kRaw!.fillRange(0, _kRaw!.length, 0);
    }
    _kRaw = k;
    _kKey = kKey;
    if (!_openSignal.isCompleted) _openSignal.complete(true);
  }

  /// Drops the vault key from memory. Readers wait for the next unlock.
  void lock() {
    final raw = _kRaw;
    if (raw != null) raw.fillRange(0, raw.length, 0);
    _kRaw = null;
    _kKey = null;
    if (_openSignal.isCompleted) _openSignal = Completer<bool>();
  }

  // ── PIN change and biometrics ─────────────────────────────────────────

  /// Re-wraps the open vault's key under [newPin] with a fresh salt. One
  /// record write: the vault matches either the old PIN or the new one,
  /// never neither.
  Future<void> changePin(String newPin) async {
    final k = _kRaw;
    final meta = _meta;
    if (k == null || meta == null) throw const VaultLockedException();
    final device = await _deviceKey(create: false);
    final next = Map<String, Object?>.of(meta);
    final salt = crypto.randomBytes(16);
    next['salt'] = _s(salt);
    next['iter'] = iterations;
    await _wrapUnderPin(next, device, k, newPin, salt, iterations);
    await db.writeMeta(next);
    _meta = next;
  }

  /// Wraps the open vault's key under a key derived from a WebAuthn PRF
  /// output, so a biometric check can open the vault without the PIN.
  Future<void> enrolPrf(
      String credentialId, Uint8List prfSalt, Uint8List prfOutput) async {
    final k = _kRaw;
    final meta = _meta;
    if (k == null || meta == null) throw const VaultLockedException();
    final vid = meta['vid'] as String;
    final device = await _deviceKey(create: false);
    final hkdfSalt = crypto.randomBytes(32);
    final prfKey = await crypto.hkdfKey(prfOutput, hkdfSalt, _prfInfo);
    final iv = crypto.randomBytes(12);
    final inner = await crypto.seal(prfKey, iv, k, _aad('prf', vid));
    final devIv = crypto.randomBytes(12);
    final wrapped = await crypto.seal(device, devIv, inner, _aad('prfdev', vid));
    final next = Map<String, Object?>.of(meta)
      ..['prf'] = <String, Object?>{
        'cred': credentialId,
        'input': _s(prfSalt),
        'salt': _s(hkdfSalt),
        'iv': _s(iv),
        'devIv': _s(devIv),
        'wrapped': _s(wrapped),
      };
    await db.writeMeta(next);
    _meta = next;
  }

  /// The PRF input for [credentialId], or null when not enrolled.
  Uint8List? prfInputFor(String credentialId) {
    final p = _meta?['prf'];
    if (p is! Map || p['cred'] != credentialId) return null;
    return _b(p['input']);
  }

  Future<void> removePrf() async {
    final meta = _meta;
    if (meta == null || !meta.containsKey('prf')) return;
    final next = Map<String, Object?>.of(meta)..remove('prf');
    await db.writeMeta(next);
    _meta = next;
  }

  // ── Entries ───────────────────────────────────────────────────────────

  Future<String?> read(String name) async {
    final kKey = _kKey;
    if (kKey == null) throw const VaultLockedException();
    final entry = _entries[name];
    if (entry == null || entry['vid'] != _vid) return null;
    final plain = await crypto.open(
        kKey, _b(entry['iv']), _b(entry['ct']), _aad('entry', _vid!, name));
    return utf8.decode(plain);
  }

  Future<void> write(String name, String value) async {
    final kKey = _kKey;
    if (kKey == null || _vid == null) throw const VaultLockedException();
    final iv = crypto.randomBytes(12);
    final ct = await crypto.seal(kKey, iv,
        Uint8List.fromList(utf8.encode(value)), _aad('entry', _vid!, name));
    final entry = <String, Object?>{'vid': _vid, 'iv': _s(iv), 'ct': _s(ct)};
    await db.writeEntry(name, entry);
    _entries[name] = entry;
  }

  /// Works while locked: deleting needs no key.
  Future<void> delete(String name) async {
    _entries.remove(name);
    await db.deleteEntry(name);
  }

  /// Deletes every record and the device key, and locks. Waiting readers
  /// resume with "wiped".
  Future<void> wipe() async {
    lock();
    final signal = _openSignal;
    _entries.clear();
    _meta = null;
    try {
      await db.clear();
    } finally {
      if (!signal.isCompleted) signal.complete(false);
      _openSignal = Completer<bool>();
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  Future<void> _wrapUnderPin(Map<String, Object?> meta, Object device,
      Uint8List k, String pin, Uint8List salt, int iter) async {
    final vid = meta['vid'] as String;
    final pinKey = await crypto.pinKey(pin, salt, iter);
    final pinIv = crypto.randomBytes(12);
    final inner = await crypto.seal(pinKey, pinIv, k, _aad('pin', vid));
    final devIv = crypto.randomBytes(12);
    meta['pinIv'] = _s(pinIv);
    meta['devIv'] = _s(devIv);
    meta['wrapped'] =
        _s(await crypto.seal(device, devIv, inner, _aad('dev', vid)));
  }

  Future<Object> _deviceKey({required bool create}) async {
    final existing = await db.readDeviceKey();
    if (existing != null) return existing;
    if (!create) throw const VaultUnavailableException('device key missing');
    final key = await crypto.newDeviceKey();
    await db.writeDeviceKey(key);
    return key;
  }

  static Uint8List _aad(String purpose, String vid, [String? name]) =>
      Uint8List.fromList(
          utf8.encode('kute.vault.v1|$purpose|$vid${name == null ? '' : '|$name'}'));

  static String _s(Uint8List bytes) => base64Encode(bytes);
  static Uint8List _b(Object? value) => base64Decode(value as String);
  static String _hex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
