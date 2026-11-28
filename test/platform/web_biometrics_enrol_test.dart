// Web biometric enrolment is split so the WebAuthn ceremony runs from the
// user's tap (begin) and the vault key is wrapped only after the PIN
// step-up approves the change (commit). Off the web nothing of it runs.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/platform/web_biometrics.dart';

void main() {
  test('off the web there is nothing to begin or enrol', () async {
    expect(WebBiometrics.available, isFalse);
    expect(await WebBiometrics.begin(), isNull);
    expect(await WebBiometrics.enrol(), isFalse);
    expect(WebBiometrics.enrolled, isFalse);
  });
}
