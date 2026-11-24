/// Native: no WebAuthn here. iOS, Android, macOS and Windows use
/// `local_auth`, so none of these is ever reached (see web_biometrics.dart).
library;

import 'dart:typed_data';

Future<bool> platformAuthenticatorAvailable() async => false;

Future<({String id, Uint8List? prf, bool prfEnabled})?>
    createPlatformCredential(Uint8List prfInput) async => null;

/// See web_biometrics_web.dart for the result meaning.
Future<({bool? verified, Uint8List? prf})> getPlatformAssertion(
        String credentialId, Uint8List prfInput) async =>
    (verified: false, prf: null);
