/// Native: no WebAuthn here. iOS, Android, macOS and Windows use
/// `local_auth`, so none of these is ever reached (see web_biometrics.dart).
library;

Future<bool> platformAuthenticatorAvailable() async => false;

Future<String?> createPlatformCredential() async => null;

/// See web_biometrics_web.dart for the result meaning.
Future<bool?> verifyPlatformCredential(String credentialId) async => false;
