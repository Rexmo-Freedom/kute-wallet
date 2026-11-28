// The passkey option on the web: the SDK's wasm client answers `skipped`
// on every browser that has a platform authenticator (its web provider has
// no domain-association probe), and that used to read as "Not available on
// this device" on app.kutewallet.com. On the web `skipped` is available;
// on the phones only `available` is, as before. A false answer carries a
// short reason code for analytics.

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/passkey_service.dart';

void main() {
  final read = PasskeyHomeService.readAvailability;

  test('web: available and skipped are available', () {
    expect(read(const PasskeyAvailability.available(), web: true),
        (available: true, reason: null));
    expect(
        read(const PasskeyAvailability.skipped(
                reason: 'Provider does not verify domain association'),
            web: true),
        (available: true, reason: null));
  });

  test('phones: only available is available', () {
    expect(read(const PasskeyAvailability.available(), web: false).available,
        isTrue);
    expect(read(const PasskeyAvailability.skipped(reason: 'x'), web: false),
        (available: false, reason: 'skipped'));
  });

  test('unavailable answers carry a code, never the SDK text', () {
    expect(read(const PasskeyAvailability.prfUnsupported(), web: true),
        (available: false, reason: 'prf_unsupported'));
    expect(
        read(
            const PasskeyAvailability.notAssociated(
                source: 'WebAuthn rpId scope check', reason: 'rpId "x"'),
            web: true),
        (available: false, reason: 'not_associated'));
  });
}
