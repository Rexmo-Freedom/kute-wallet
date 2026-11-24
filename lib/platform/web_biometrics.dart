/// Biometric unlock on web: the browser's platform authenticator (Touch ID,
/// Face ID, Windows Hello, an Android fingerprint) through WebAuthn, used
/// wherever the phones use `local_auth`.
///
/// A LOCAL gate, exactly like `local_auth`: nothing is sent to a server, no
/// signature is checked against a key, and it protects nothing
/// cryptographically. It never derives, wraps or decrypts the seed; the
/// Kute PIN stays the lock and every PIN rule (attempt counter, lockout,
/// wipe, step-up fallback) is unchanged. A cancelled or failed check falls
/// back to the PIN, as a failed Face ID does on a phone. Separate from the
/// Breez passkey wallet: its own credential, never reused for keys.
///
/// Only the credential id is stored, in the Hive `settings` box beside
/// `biometricsEnabled`. On native every member answers "not here" and the
/// app keeps using `local_auth`.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hive_ce/hive.dart';

import 'web_biometrics_native.dart'
    if (dart.library.js_interop) 'web_biometrics_web.dart' as impl;

/// How a web biometric check ended.
enum WebBiometricResult { approved, cancelled, failed }

abstract final class WebBiometrics {
  static const String _box = 'settings';
  static const String _key = 'webBiometricCredentialId';

  static bool _available = false;
  static String? _credentialId;

  /// A secure context with a user-verifying platform authenticator, as
  /// checked by [prime]. Always false on native.
  static bool get available => _available;

  /// A credential was created on this browser (and the authenticator is
  /// still there): the web counterpart of "biometrics enrolled".
  static bool get enrolled => _available && _credentialId != null;

  /// Boot: checks the authenticator once and loads the stored credential
  /// id. No-op on native.
  static Future<void> prime() async {
    if (!kIsWeb) return;
    try {
      _available = await impl.platformAuthenticatorAvailable()
          .timeout(const Duration(seconds: 3), onTimeout: () => false);
      final box = await Hive.openBox(_box);
      final stored = box.get(_key);
      _credentialId = stored is String && stored.isNotEmpty ? stored : null;
    } catch (_) {
      _available = false;
    }
  }

  /// Creates this browser's credential (the user passes the platform
  /// check once) and stores its id. False when unavailable, cancelled or
  /// refused; nothing is stored then.
  static Future<bool> enrol() async {
    if (!_available) return false;
    final id = await impl.createPlatformCredential();
    if (id == null) return false;
    try {
      final box = await Hive.openBox(_box);
      await box.put(_key, id);
    } catch (_) {
      return false;
    }
    _credentialId = id;
    return true;
  }

  /// One platform check against the stored credential. Approved only when
  /// the browser returned an assertion for it with user verification.
  static Future<WebBiometricResult> verify() async {
    final id = _credentialId;
    if (!_available || id == null) return WebBiometricResult.failed;
    final ok = await impl.verifyPlatformCredential(id);
    return switch (ok) {
      true => WebBiometricResult.approved,
      null => WebBiometricResult.cancelled,
      false => WebBiometricResult.failed,
    };
  }

  /// Drops the stored credential id (biometric unlock turned off). The
  /// credential itself stays in the browser's authenticator, unused.
  static Future<void> forget() async {
    _credentialId = null;
    try {
      final box = await Hive.openBox(_box);
      await box.delete(_key);
    } catch (_) {}
  }
}
