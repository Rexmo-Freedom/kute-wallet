// A cancelled passkey ceremony is recognised by its typed verdict only:
// the SDK's PrfProviderError.userCancelled or the legacy channel's
// USER_CANCELLED code. An error whose text merely mentions a cancel is a
// failure, so it is surfaced rather than swallowed as the user backing out.

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/passkey_service.dart';

void main() {
  test('the SDK typed cancel and the legacy platform code are cancels', () {
    expect(
        PasskeyService.isUserCancelledError(
            PasskeyError.prf(PrfProviderError.userCancelled())),
        isTrue);
    expect(
        PasskeyService.isUserCancelledError(
            PlatformException(code: 'USER_CANCELLED', message: 'cancelled')),
        isTrue);
  });

  test('text alone is never a cancel', () {
    for (final e in [
      Exception('request cancelled'),
      StateError('Cancelled by the relay'),
      PlatformException(code: 'PRF_ERROR', message: 'User cancelled'),
      PlatformException(code: 'CREDENTIAL_MISMATCH'),
      PasskeyError.prf(
          PrfProviderError.credentialNotFound('no credential; cancel')),
      'cancel',
    ]) {
      expect(PasskeyService.isUserCancelledError(e), isFalse, reason: '$e');
    }
  });
}
