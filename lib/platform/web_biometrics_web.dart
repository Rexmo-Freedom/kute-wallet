/// Web: the browser's platform authenticator (Touch ID, Face ID, Windows
/// Hello, an Android fingerprint) through WebAuthn, with the PRF extension.
///
/// No server sees the challenge or the assertion and the signature is never
/// checked against a public key: the assertion itself proves nothing. What
/// unlocks is the PRF output: a secret only the authenticator can compute,
/// after its own user verification. web_biometrics.dart derives a key from
/// it (HKDF) that unwraps the seed vault's key; without PRF support there
/// is no biometric unlock on web and the Kute PIN is the only way in.
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

/// The PRF output in a WebAuthn result's client extension results, or
/// null; [enabled] reports `prf.enabled` from a create.
({Uint8List? first, bool enabled}) _prfResult(JSObject credential) {
  try {
    final ext = credential
        .callMethod<JSObject?>('getClientExtensionResults'.toJS);
    final prf = ext?['prf'] as JSObject?;
    if (prf == null) return (first: null, enabled: false);
    final enabled = (prf['enabled'] as JSBoolean?)?.toDart ?? false;
    final results = prf['results'] as JSObject?;
    final first = results?['first'] as JSObject?;
    if (first == null) return (first: null, enabled: enabled);
    final bytes = first.instanceOfString('ArrayBuffer')
        ? (first as JSArrayBuffer).toDart.asUint8List()
        : (first as JSUint8Array).toDart;
    return (first: bytes.isEmpty ? null : Uint8List.fromList(bytes), enabled: true);
  } catch (_) {
    return (first: null, enabled: false);
  }
}

JSObject _prfExtension(Uint8List input) => _object({
      'prf': _object({
        'eval': _object({'first': input.toJS}),
      }),
    });

/// Creates a platform credential asking for the PRF extension with
/// [prfInput]. Returns its id (base64url), the PRF output when the browser
/// returned one at creation, and whether PRF is enabled; null when the user
/// cancelled or the browser refused.
Future<({String id, Uint8List? prf, bool prfEnabled})?>
    createPlatformCredential(Uint8List prfInput) async {
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
      'extensions': _prfExtension(prfInput),
    });
    final credential = await credentials
        .callMethod<JSPromise<JSObject?>>(
            'create'.toJS, _object({'publicKey': publicKey}))
        .toDart;
    if (credential == null) return null;
    final rawId = credential['rawId'] as JSArrayBuffer?;
    if (rawId == null) return null;
    final id = rawId.toDart.asUint8List();
    if (id.isEmpty) return null;
    final prf = _prfResult(credential);
    return (id: _encode(id), prf: prf.first, prfEnabled: prf.enabled);
  } catch (_) {
    return null;
  }
}

/// Asks the platform authenticator for [credentialId], evaluating PRF on
/// [prfInput]. `verified` is true only when an assertion for that
/// credential came back with the UV flag set, null when the user dismissed
/// the sheet, false for any other failure; `prf` is the PRF output.
Future<({bool? verified, Uint8List? prf})> getPlatformAssertion(
    String credentialId, Uint8List prfInput) async {
  const failed = (verified: false, prf: null);
  try {
    final credentials = _credentialsContainer();
    final host = _host();
    if (credentials == null || host == null) return failed;
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
      'extensions': _prfExtension(prfInput),
    });
    final assertion = await credentials
        .callMethod<JSPromise<JSObject?>>(
            'get'.toJS, _object({'publicKey': publicKey}))
        .toDart;
    if (assertion == null) return failed;
    final rawId = assertion['rawId'] as JSArrayBuffer?;
    if (rawId == null ||
        _encode(rawId.toDart.asUint8List()) != credentialId) {
      return failed;
    }
    final response = assertion['response'] as JSObject?;
    final authData = response?['authenticatorData'] as JSArrayBuffer?;
    if (authData == null) return failed;
    final bytes = authData.toDart.asUint8List();
    // 32 bytes of rpIdHash, then the flags byte.
    if (bytes.length < 37) return failed;
    if ((bytes[32] & _flagUserVerified) == 0) return failed;
    return (verified: true, prf: _prfResult(assertion).first);
  } catch (e) {
    return _isCancel(e) ? (verified: null, prf: null) : failed;
  }
}
