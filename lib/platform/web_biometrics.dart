/// Biometric unlock on web: the browser's platform authenticator (Touch ID,
/// Face ID, Windows Hello, an Android fingerprint) through WebAuthn, used
/// wherever the phones use `local_auth`.
///
/// A key, not just a gate: enrolment asks the authenticator for the
/// WebAuthn PRF extension and wraps the seed vault's key under a key
/// derived (HKDF) from the PRF output (`SeedVault.enrolPrf`). A biometric
/// unlock is approved only when the PRF output opens the vault, so it
/// cannot bypass the PIN without a key. An authenticator without PRF
/// cannot be enrolled: the Kute PIN is then the only unlock. Every PIN rule
/// (attempt counter, lockout, wipe, step-up fallback) is unchanged, and a
/// cancelled or failed check falls back to the PIN. Nothing is sent to a
/// server. Separate from the Breez passkey wallet: its own credential,
/// never reused for wallet keys.
///
/// The credential id is stored in the Hive `settings` box beside
/// `biometricsEnabled`; the PRF input and the wrapped key live in the vault
/// record. On native every member answers "not here" and the app keeps
/// using `local_auth`.
library;

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:hive_ce/hive.dart';

import 'package:kute/services/secure/web_vault/web_vault.dart';

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

  /// A PRF credential was enrolled on this browser and the vault holds its
  /// wrapped key: the web counterpart of "biometrics enrolled". An older
  /// credential without PRF is not enrolled; the PIN is asked instead.
  static bool get enrolled {
    final id = _credentialId;
    if (!_available || id == null) return false;
    return WebVault.instance?.vault.prfInputFor(id) != null;
  }

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

  /// Creates this browser's credential with the PRF extension (the user
  /// passes the platform check once, twice when the browser returns PRF
  /// only on an assertion) and wraps the open vault's key under it. Needs
  /// an unlocked vault. False when unavailable, cancelled, refused or
  /// without PRF; nothing is stored then. [begin] then [commit].
  static Future<bool> enrol() async {
    final pending = await begin();
    return pending != null && await commit(pending);
  }

  /// The platform-check half of [enrol]: creates the credential and reads
  /// its PRF output, storing nothing. Call it straight from the user's tap:
  /// Safari runs a WebAuthn ceremony only while the page still has the
  /// tap's user activation, which is long gone after a PIN step-up (the
  /// PIN's own key derivation takes seconds). Null when unavailable,
  /// cancelled, refused or without PRF.
  static Future<WebBiometricEnrolment?> begin() async {
    final web = WebVault.instance;
    if (!_available || web == null || !web.vault.isOpen) return null;
    final input = web.vault.crypto.randomBytes(32);
    final created = await impl.createPlatformCredential(input);
    if (created == null) return null;
    var output = created.prf;
    if (output == null && created.prfEnabled) {
      final assertion = await impl.getPlatformAssertion(created.id, input);
      if (assertion.verified == true) output = assertion.prf;
    }
    if (output == null) {
      debugPrint('Web biometrics: no PRF from this authenticator; the PIN '
          'stays the only unlock.');
      return null;
    }
    return WebBiometricEnrolment._(created.id, input, output);
  }

  /// The storing half of [enrol], once the change is approved: wraps the
  /// open vault's key under [pending]'s PRF output and keeps the
  /// credential id. Always clears [pending]'s secret.
  static Future<bool> commit(WebBiometricEnrolment pending) async {
    final web = WebVault.instance;
    try {
      if (web == null || !web.vault.isOpen || pending._output.isEmpty) {
        return false;
      }
      await web.vault.enrolPrf(pending.id, pending._input, pending._output);
      final box = await Hive.openBox(_box);
      await box.put(_key, pending.id);
    } catch (_) {
      return false;
    } finally {
      pending.discard();
    }
    _credentialId = pending.id;
    return true;
  }

  /// One platform check against the stored credential, evaluating PRF.
  /// Approved only when the browser returned a user-verified assertion for
  /// it AND its PRF output opened the vault (a step-up re-opens the same
  /// key, so it proves the same thing).
  static Future<WebBiometricResult> verify() async {
    final id = _credentialId;
    final web = WebVault.instance;
    final input = id == null ? null : web?.vault.prfInputFor(id);
    if (!_available || id == null || web == null || input == null) {
      return WebBiometricResult.failed;
    }
    final assertion = await impl.getPlatformAssertion(id, input);
    if (assertion.verified == null) return WebBiometricResult.cancelled;
    final output = assertion.prf;
    if (assertion.verified != true || output == null) {
      return WebBiometricResult.failed;
    }
    try {
      return await web.vault.unlockWithPrf(id, output)
          ? WebBiometricResult.approved
          : WebBiometricResult.failed;
    } finally {
      output.fillRange(0, output.length, 0);
    }
  }

  /// Biometric unlock turned off: drops the stored credential id and the
  /// vault's PRF-wrapped key. The credential itself stays in the browser's
  /// authenticator, unused.
  static Future<void> forget() async {
    _credentialId = null;
    try {
      await WebVault.instance?.vault.removePrf();
    } catch (_) {}
    try {
      final box = await Hive.openBox(_box);
      await box.delete(_key);
    } catch (_) {}
  }
}

/// A credential created by [WebBiometrics.begin] and not yet stored: its id,
/// its PRF input and, in memory only, its PRF output.
class WebBiometricEnrolment {
  WebBiometricEnrolment._(this.id, this._input, this._output);

  final String id;
  final Uint8List _input;
  Uint8List _output;

  /// Drops the PRF output (zeroed). The credential stays in the browser's
  /// authenticator, unused, as after [WebBiometrics.forget].
  void discard() {
    _output.fillRange(0, _output.length, 0);
    _output = Uint8List(0);
  }
}
