// The end of a biometric prompt that threw (open_pin.dart and
// lock_overlay.dart both report through TrackingService.biometricPromptThrew).
// local_auth 3 throws a LocalAuthException for a dismissed prompt instead of
// returning false, so a cancel must file as biometric_prompt_cancelled with
// its code, and only real errors as biometric_failed.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:local_auth/local_auth.dart';

void main() {
  final events = <(String, Map<String, Object>?)>[];

  setUp(() {
    events.clear();
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });

  tearDown(() => TrackingService.debugTrackObserver = null);

  test('a dismissed prompt is a cancel with its code, per surface', () {
    TrackingService.biometricPromptThrew(
        const LocalAuthException(code: LocalAuthExceptionCode.userCanceled),
        surface: 'cold_start');
    TrackingService.biometricPromptThrew(
        const LocalAuthException(code: LocalAuthExceptionCode.systemCanceled),
        surface: 'lock_overlay');
    expect(events.map((e) => e.$1),
        everyElement('biometric_prompt_cancelled'));
    expect(events[0].$2, {'surface': 'cold_start', 'reason': 'userCanceled'});
    expect(events[1].$2,
        {'surface': 'lock_overlay', 'reason': 'systemCanceled'});
  });

  test('every other LocalAuthException is a failure carrying its code', () {
    for (final code in LocalAuthExceptionCode.values) {
      if (TrackingService.biometricCancelCodes.contains(code)) continue;
      events.clear();
      TrackingService.biometricPromptThrew(
          LocalAuthException(
              code: code, description: 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq'),
          surface: 'lock_overlay');
      expect(events.single.$1, 'biometric_failed', reason: code.name);
      expect(events.single.$2, {'reason': code.name, 'surface': 'lock_overlay'});
    }
  });

  test('platform and other errors keep the old code / class reason', () {
    TrackingService.biometricPromptThrew(
        PlatformException(code: 'NotAvailable', message: 'no sensor'),
        surface: 'cold_start');
    TrackingService.biometricPromptThrew(StateError('oops'),
        surface: 'cold_start');
    expect(events.map((e) => e.$1), everyElement('biometric_failed'));
    expect(events[0].$2, {'reason': 'NotAvailable', 'surface': 'cold_start'});
    expect(events[1].$2, {'reason': 'StateError', 'surface': 'cold_start'});
  });
}
