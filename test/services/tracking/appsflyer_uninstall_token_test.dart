import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/tracking/appsflyer_uninstall_token.dart';

NotificationSettings _settings(AuthorizationStatus status) =>
    NotificationSettings(
      alert: AppleNotificationSetting.notSupported,
      announcement: AppleNotificationSetting.notSupported,
      authorizationStatus: status,
      badge: AppleNotificationSetting.notSupported,
      carPlay: AppleNotificationSetting.notSupported,
      lockScreen: AppleNotificationSetting.notSupported,
      notificationCenter: AppleNotificationSetting.notSupported,
      showPreviews: AppleShowPreviewSetting.notSupported,
      timeSensitive: AppleNotificationSetting.notSupported,
      criticalAlert: AppleNotificationSetting.notSupported,
      sound: AppleNotificationSetting.notSupported,
      providesAppNotificationSettings: AppleNotificationSetting.notSupported,
    );

void main() {
  final sent = <String>[];
  late StreamController<String> refresh;
  var settingsReads = 0;
  var tokenReads = 0;

  AppsFlyerUninstallTokenPorts ports({
    bool isIOS = false,
    bool canTrack = true,
    AuthorizationStatus status = AuthorizationStatus.authorized,
    String? apns = 'aabbccdd',
    String? fcm = 'fcm-token-1',
    Future<void> Function(String)? update,
  }) =>
      AppsFlyerUninstallTokenPorts(
        isIOS: isIOS,
        canTrack: () => canTrack,
        notificationSettings: () async {
          settingsReads++;
          return _settings(status);
        },
        apnsToken: () async {
          tokenReads++;
          return apns;
        },
        fcmToken: () async {
          tokenReads++;
          return fcm;
        },
        updateServerUninstallToken: update ??
            (t) async {
              sent.add(t);
            },
        tokenRefresh: () => refresh.stream,
      );

  setUp(() async {
    await AppsFlyerUninstallToken.debugReset();
    sent.clear();
    settingsReads = 0;
    tokenReads = 0;
    refresh = StreamController<String>.broadcast();
  });

  tearDown(() async {
    await AppsFlyerUninstallToken.debugReset();
    await refresh.close();
  });

  test('Android: forwards the FCM token once permission is granted', () async {
    AppsFlyerUninstallToken.debugPorts = ports();
    await AppsFlyerUninstallToken.register();
    expect(sent, ['fcm-token-1']);
    expect(AppsFlyerUninstallToken.debugLastSent, 'fcm-token-1');
  });

  test('iOS: forwards the APNs hex token, not the FCM one', () async {
    AppsFlyerUninstallToken.debugPorts = ports(isIOS: true);
    await AppsFlyerUninstallToken.register();
    expect(sent, ['aabbccdd']);
  });

  test('provisional permission counts as granted', () async {
    AppsFlyerUninstallToken.debugPorts =
        ports(status: AuthorizationStatus.provisional);
    await AppsFlyerUninstallToken.register();
    expect(sent, hasLength(1));
  });

  test('no permission: nothing is read or sent (and nothing prompts)',
      () async {
    for (final status in [
      AuthorizationStatus.denied,
      AuthorizationStatus.notDetermined,
    ]) {
      await AppsFlyerUninstallToken.debugReset();
      AppsFlyerUninstallToken.debugPorts = ports(status: status);
      await AppsFlyerUninstallToken.register();
      expect(sent, isEmpty, reason: '$status');
      expect(tokenReads, 0, reason: '$status');
    }
  });

  test('opted out / disabled: nothing leaves the device', () async {
    AppsFlyerUninstallToken.debugPorts = ports(canTrack: false);
    await AppsFlyerUninstallToken.register();
    expect(sent, isEmpty);
    expect(settingsReads, 0);
    expect(tokenReads, 0);
  });

  test('missing or blank token is a silent no-op', () async {
    AppsFlyerUninstallToken.debugPorts = ports(fcm: null);
    await AppsFlyerUninstallToken.register();
    expect(sent, isEmpty);

    AppsFlyerUninstallToken.debugPorts = ports(fcm: '   ');
    await AppsFlyerUninstallToken.register();
    expect(sent, isEmpty);
  });

  test('the same token is not re-sent on a second register', () async {
    AppsFlyerUninstallToken.debugPorts = ports();
    await AppsFlyerUninstallToken.register();
    await AppsFlyerUninstallToken.register();
    expect(sent, ['fcm-token-1']);
  });

  test('Android token refresh forwards the new token', () async {
    AppsFlyerUninstallToken.debugPorts = ports();
    await AppsFlyerUninstallToken.register();
    refresh.add('fcm-token-2');
    await pumpEventQueue();
    expect(sent, ['fcm-token-1', 'fcm-token-2']);
  });

  test('iOS ignores FCM token refreshes', () async {
    AppsFlyerUninstallToken.debugPorts = ports(isIOS: true);
    await AppsFlyerUninstallToken.register();
    refresh.add('fcm-token-2');
    await pumpEventQueue();
    expect(sent, ['aabbccdd']);
  });

  test('SDK failure never throws and is retried next time', () async {
    var fail = true;
    AppsFlyerUninstallToken.debugPorts = ports(update: (t) async {
      if (fail) throw StateError('sdk not ready');
      sent.add(t);
    });
    await AppsFlyerUninstallToken.register();
    expect(sent, isEmpty);
    expect(AppsFlyerUninstallToken.debugLastSent, isNull);

    fail = false;
    await AppsFlyerUninstallToken.register();
    expect(sent, ['fcm-token-1']);
  });

  test('a settings read failure is a silent no-op', () async {
    AppsFlyerUninstallToken.debugPorts = AppsFlyerUninstallTokenPorts(
      isIOS: false,
      canTrack: () => true,
      notificationSettings: () async => throw StateError('no firebase'),
      apnsToken: () async => null,
      fcmToken: () async => 'fcm',
      updateServerUninstallToken: (t) async => sent.add(t),
      tokenRefresh: () => refresh.stream,
    );
    await AppsFlyerUninstallToken.register();
    expect(sent, isEmpty);
  });
}
