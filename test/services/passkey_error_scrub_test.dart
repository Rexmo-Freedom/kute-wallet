// The SDK's passkey errors inline the provider's message, which names the
// WebAuthn user (the wallet label) on some platforms. What reaches the
// crash sink for them is the type and the union variant names, never the
// message, whether the error arrives through recordHandled or recordCrash.

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/tracking_service.dart';

void main() {
  const label = 'Holiday Fund · 1700000000000';
  final notFound = PasskeyError.prf(
      PrfProviderError.credentialNotFound('No credential for user $label'));

  late List<Object> envelopes;
  late List<String?> reasons;

  setUp(() {
    TrackingService.debugResetHandled();
    envelopes = [];
    reasons = [];
    TrackingService.debugCrashObserver = (envelope, stack, reason, log) {
      envelopes.add(envelope);
      reasons.add(reason);
    };
  });

  tearDown(() {
    TrackingService.debugCrashObserver = null;
    TrackingService.debugResetHandled();
  });

  test('the message itself carries the label', () {
    expect(notFound.toString(), contains('Holiday Fund'));
  });

  test('recordHandled sends the type and variants only', () {
    final recorded = TrackingService.recordHandled(
        'unknown', notFound, StackTrace.current,
        flow: 'onboarding', stage: 'wallet_create');
    expect(recorded, isTrue);
    final sent = envelopes.single.toString();
    expect(sent, isNot(contains('Holiday')));
    expect(sent, isNot(contains('1700000000000')));
    expect(sent, contains('PasskeyError_Prf'));
    expect(sent, contains('PrfProviderError.credentialNotFound'));
    expect(reasons.single, isNot(contains('Holiday')));
  });

  test('recordCrash on the raw error is scrubbed the same way', () {
    TrackingService.recordCrash(notFound, StackTrace.current,
        reason: 'passkey sign-in');
    final sent = envelopes.single.toString();
    expect(sent, isNot(contains('Holiday')));
    expect(sent, 'PasskeyError_Prf: '
        'PasskeyError.prf > PrfProviderError.credentialNotFound');
  });

  test('the inner provider error alone is scrubbed too', () {
    TrackingService.recordCrash(
        PrfProviderError.credentialNotFound('user $label'), null);
    final sent = envelopes.single.toString();
    expect(sent, isNot(contains('Holiday')));
    expect(sent, contains('PrfProviderError.credentialNotFound'));
  });

  test('a cancel keeps its variant and other errors keep their message', () {
    expect(
        TrackingService.passkeyErrorVariants(
            PasskeyError.prf(PrfProviderError.userCancelled())),
        'PasskeyError.prf > PrfProviderError.userCancelled');
    expect(TrackingService.isPasskeySdkError(StateError('x')), isFalse);
    TrackingService.recordCrash(StateError('relay timeout'), null);
    expect(envelopes.single.toString(), contains('relay timeout'));
  });
}
