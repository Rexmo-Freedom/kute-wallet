// Settings > Security > Notifications shows the live OS permission state:
// "On" when granted, and an "Off" hint that says how to turn it on.

import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart' as settings_model;
import 'package:kute/notifications/push_permission.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/settings/settings.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

void main() {
  final l10n = AppLocalizationsEn();
  var requests = 0;

  PushPermissionPorts ports(AuthorizationStatus current) =>
      PushPermissionPorts(
        currentStatus: () async => current,
        requestPermission: () async {
          requests++;
          return AuthorizationStatus.authorized;
        },
        subscribeToTopics: () async => true,
        registerUninstallToken: () async {},
      );

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    TrackingService.setDisabled(true);
    requests = 0;
  });

  tearDown(() => PushPermission.debugPorts = null);

  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final never = Completer<settings_model.Settings>();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        initialSettingsProvider.overrideWith((ref) => never.future),
        biometricsAvailableProvider.overrideWith((ref) async => false),
      ],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: ThemeData(
              fontFamily: 'Inter', extensions: [AppColorsExtension.light()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Settings(),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('granted: the row reads On', (tester) async {
    PushPermission.debugPorts = ports(AuthorizationStatus.authorized);
    await pumpSettings(tester);

    expect(find.text(l10n.security), findsOneWidget);
    expect(find.text(l10n.settingsNotifications), findsOneWidget);
    expect(find.text(l10n.settingsNotificationsOn), findsOneWidget);
  });

  testWidgets('denied: the row reads Off and points at the OS settings',
      (tester) async {
    PushPermission.debugPorts = ports(AuthorizationStatus.denied);
    await pumpSettings(tester);

    expect(find.text(l10n.settingsNotifications), findsOneWidget);
    expect(find.text(l10n.settingsNotificationsOffOpenSystemSettings),
        findsOneWidget);
    expect(find.text(l10n.settingsNotificationsOn), findsNothing);
  });

  testWidgets('never asked: tapping the row shows the system prompt',
      (tester) async {
    PushPermission.debugPorts = ports(AuthorizationStatus.notDetermined);
    await pumpSettings(tester);

    expect(find.text(l10n.settingsNotificationsOffTapToTurnOn),
        findsOneWidget);
    await tester.tap(find.text(l10n.settingsNotifications));
    await tester.pump();
    await tester.pump();

    expect(requests, 1);
    expect(find.text(l10n.settingsNotificationsOn), findsOneWidget);
  });
}
