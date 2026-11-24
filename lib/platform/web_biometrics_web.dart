/// Web: the browser's platform authenticator (Touch ID, Face ID, Windows
/// Hello, an Android fingerprint) through WebAuthn, as a LOCAL gate.
///
/// What this is NOT: it is not a key, it is not sent anywhere and it
/// protects nothing cryptographically. No server sees the challenge or the
/// assertion, the signature is never checked against a public key, and
/// nothing is derived from or decrypted with it: the seed stays exactly as
/// protected as it is with the PIN alone. It only answers "did the person
/// at this browser just pass the device's own biometric check", the same
/// yes/no `local_auth` gives on a phone. The Kute PIN remains the real
/// lock and every PIN rule stays.
///
/// It is also not the Breez passkey wallet (keys.breez.technology, PRF):
/// this credential is created for the page's own host, carries a generic
/// label and is never used for a wallet.
library;

import 'dart:convert' show base64Url;
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' show Random;
import 'dart:typed_data';

/// The only user fields the credential carries: no name, email or wallet
/// data.
const String _label = 'Kute on this browser';

/// Ceremony timeout in milliseconds.
const int _timeoutMs = 60000;

/// The WebAuthn "user verified" flag in authenticatorData's flags byte.
const int _flagUserVerified = 0x04;

final Random _random = Random.secure();

JSUint8Array _randomBytes(int length) {
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = _random.nextInt(256);
  }
  return bytes.toJS;
}

JSObject _object(Map<String, JSAny?> fields) {
  final object = JSObject();
  fields.forEach((key, value) => object[key] = value);
  return object;
}

JSObject? _credentialsContainer() {
  final navigator = globalContext['navigator'] as JSObject?;
  return navigator?['credentials'] as JSObject?;
}

/// The page's own host, the relying party id.
String? _host() {
  final location = globalContext['location'] as JSObject?;
  final value = (location?['hostname'] as JSString?)?.toDart ?? '';
  return value.isEmpty ? null : value;
}

String _encode(Uint8List bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

Uint8List _decode(String value) =>
    base64Url.decode(value.padRight((value.length + 3) & ~3, '='));

bool _isCancel(Object error) {
  // DOMException name: NotAllowedError is a dismissed or timed-out sheet
  // (browsers use it for both, by design); AbortError an aborted one.
  try {
    final name = ((error as JSObject)['name'] as JSString?)?.toDart;
    return name == 'NotAllowedError' || name == 'AbortError';
  } catch (_) {}
  return false;
}

/// A secure context with a user-verifying platform authenticator.
Future<bool> platformAuthenticatorAvailable() async {
  try {
    final secure = globalContext['isSecureContext'] as JSBoolean?;
    if (secure == null || !secure.toDart) return false;
    if (_credentialsContainer() == null || _host() == null) return false;
    final pkcObject = globalContext['PublicKeyCredential'] as JSObject?;
    if (pkcObject == null) return false;
    if (!pkcObject.has('isUserVerifyingPlatformAuthenticatorAvailable')) {
      return false;
    }
    final result = await pkcObject
        .callMethod<JSPromise<JSBoolean>>(
            'isUserVerifyingPlatformAuthenticatorAvailable'.toJS)
        .toDart;
    return result.toDart;
  } catch (_) {
    return false;
  }
}

/// Creates a platform credential and returns its id (base64url), or null
/// when the user cancelled or the browser refused.
Future<String?> createPlatformCredential() async {
  try {
    final credentials = _credentialsContainer();
    final host = _host();
    if (credentials == null || host == null) return null;
    final publicKey = _object({
      'rp': _object({'name': 'Kute'.toJS, 'id': host.toJS}),
      'user': _object({
        'id': _randomBytes(16),
        'name': _label.toJS,
        'displayName': _label.toJS,
      }),
      'challenge': _randomBytes(32),
      'pubKeyCredParams': <JSObject>[
        _object({'type': 'public-key'.toJS, 'alg': (-7).toJS}),
        _object({'type': 'public-key'.toJS, 'alg': (-257).toJS}),
      ].toJS,
      'authenticatorSelection': _object({
        'authenticatorAttachment': 'platform'.toJS,
        'userVerification': 'required'.toJS,
        'residentKey': 'discouraged'.toJS,
        'requireResidentKey': false.toJS,
      }),
      'attestation': 'none'.toJS,
      'timeout': _timeoutMs.toJS,
    });
    final credential = await credentials
        .callMethod<JSPromise<JSObject?>>(
            'create'.toJS, _object({'publicKey': publicKey}))
        .toDart;
    if (credential == null) return null;
    final rawId = credential['rawId'] as JSArrayBuffer?;
    if (rawId == null) return null;
    final id = rawId.toDart.asUint8List();
    return id.isEmpty ? null : _encode(id);
  } catch (_) {
    return null;
  }
}

/// Asks the platform authenticator for [credentialId]. True only when an
/// assertion for that credential came back with the UV flag set; null when
/// the user dismissed the sheet; false for any other failure.
Future<bool?> verifyPlatformCredential(String credentialId) async {
  try {
    final credentials = _credentialsContainer();
    final host = _host();
    if (credentials == null || host == null) return false;
    final id = _decode(credentialId);
    final publicKey = _object({
      'challenge': _randomBytes(32),
      'rpId': host.toJS,
      'allowCredentials': <JSObject>[
        _object({
          'type': 'public-key'.toJS,
          'id': id.toJS,
          'transports': <JSString>['internal'.toJS].toJS,
        }),
      ].toJS,
      'userVerification': 'required'.toJS,
      'timeout': _timeoutMs.toJS,
    });
    final assertion = await credentials
        .callMethod<JSPromise<JSObject?>>(
            'get'.toJS, _object({'publicKey': publicKey}))
        .toDart;
    if (assertion == null) return false;
    final rawId = assertion['rawId'] as JSArrayBuffer?;
    if (rawId == null ||
        _encode(rawId.toDart.asUint8List()) != credentialId) {
      return false;
    }
    final response = assertion['response'] as JSObject?;
    final authData = response?['authenticatorData'] as JSArrayBuffer?;
    if (authData == null) return false;
    final bytes = authData.toDart.asUint8List();
    // 32 bytes of rpIdHash, then the flags byte.
    if (bytes.length < 37) return false;
    return (bytes[32] & _flagUserVerified) != 0;
  } catch (e) {
    return _isCancel(e) ? null : false;
  }
}
