import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/tracking_service.dart';

/// The `app_language` super property: the resolved app language code is
/// registered once per value, mirrored on the person as `language`, and
/// nothing is registered while analytics are muted.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const posthog = MethodChannel('posthog_flutter');
  final calls = <MethodCall>[];

  List<Object?> registered() => [
        for (final c in calls)
          if (c.method == 'register') (c.arguments as Map)['value'],
      ];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(posthog, (call) async {
      calls.add(call);
      return null;
    });
    TrackingService.debugResetOptOut();
    TrackingService.debugResetAppLanguage();
    TrackingService.setDisabled(false);
  });

  tearDown(() {
    TrackingService.debugResetOptOut();
    TrackingService.debugResetAppLanguage();
    TrackingService.setDisabled(true);
    messenger.setMockMethodCallHandler(posthog, null);
  });

  test('registers app_language and the person language once per value',
      () async {
    TrackingService.setAppLanguage('de');
    TrackingService.setAppLanguage('de');
    await pumpEventQueue();

    final register = calls.singleWhere((c) => c.method == 'register');
    expect(register.arguments, {'key': 'app_language', 'value': 'de'});
    expect(TrackingService.debugPendingUserProperties['language'], 'de');

    TrackingService.setAppLanguage('pt');
    await pumpEventQueue();
    expect(registered(), ['de', 'pt']);
    expect(TrackingService.debugPendingUserProperties['language'], 'pt');
  });

  test('sends the bare language code, never a region or a name', () {
    expect(TrackingService.appLanguageCode('pt_PT'), 'pt');
    expect(TrackingService.appLanguageCode('de-DE'), 'de');
    expect(TrackingService.appLanguageCode('EL'), 'el');
    expect(TrackingService.appLanguageCode('Deutsch'), isNull);
    expect(TrackingService.appLanguageCode(''), isNull);
  });

  test('registers nothing while muted, and registers once unmuted', () async {
    TrackingService.setDisabled(true);
    TrackingService.setAppLanguage('fr');
    await pumpEventQueue();
    expect(registered(), isEmpty);

    TrackingService.setDisabled(false);
    TrackingService.setAppLanguage('fr');
    await pumpEventQueue();
    expect(registered(), ['fr']);
  });
}
