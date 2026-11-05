// Settings opens on four big cards (founder, 4 November 2026: "the
// passwords/backup, referrals, and support should be 4 big cards on the
// top and the rest of the items below"): Backup and recovery, the app PIN,
// the referral program and support, 2 x 2, in the shared big-square style;
// every other setting stays a row below, and none of the four is also a
// row. With the referral program withheld, Rate the app takes its card.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/settings_model.dart' as settings_model;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/settings/settings.dart';
import 'package:kute/screens/shared/components/kute_list_row.dart';
import 'package:kute/screens/shared/kute_action_cards.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

final _l10n = AppLocalizationsEn();

RuntimeCapabilitiesService _policy({required bool referral}) =>
    RuntimeCapabilitiesService.forTesting(
      client: MockClient((request) async {
        final now = DateTime.now().toUtc();
        return http.Response(
            jsonEncode({
              'schemaVersion': 1,
              'revision': 1,
              'evaluatedAt': now.toIso8601String(),
              'expiresAt':
                  now.add(const Duration(minutes: 2)).toIso8601String(),
              'capabilities': {
                'affiliate.program': {
                  'allowed': referral,
                  'reason': referral ? '' : 'feature_disabled',
                },
                'export.transactions': {'allowed': true, 'reason': ''},
                'settings.advanced': {'allowed': true, 'reason': ''},
              },
            }),
            200);
      }),
      baseUrl: () => 'https://backend.test',
      sessionToken: () => AffiliateService.sessionToken,
      appVersion: () async => '2.1.0',
    );

Future<void> _pump(WidgetTester tester,
    {bool referral = true, bool dark = false}) async {
  final policy = _policy(referral: referral);
  RuntimeCapabilitiesService.debugInstance = policy;
  addTearDown(policy.dispose);
  expect(await tester.runAsync(policy.refresh), isTrue);
  // A phone, tall enough for the whole list.
  tester.view.physicalSize = const Size(390, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final never = Completer<settings_model.Settings>();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      initialSettingsProvider.overrideWith((ref) => never.future),
      biometricsAvailableProvider.overrideWith((ref) async => false),
      appVersionLabelProvider.overrideWith((ref) async => '2.1.0 (78)'),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: dark ? buildDarkTheme() : buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Settings(),
      ),
    ),
  ));
  await tester.pump();
}

Finder _card(String id) => find.byKey(ValueKey('settings-card-$id'));

Finder _row(String title) => find.widgetWithText(KuteListRow, title);

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    TrackingService.setDisabled(true);
  });

  tearDown(() => RuntimeCapabilitiesService.debugInstance = null);

  testWidgets(
      'four big cards on top, 2 x 2: Backup, App PIN, Referral program, '
      'Support; the rest are rows below, none of the four twice',
      (tester) async {
    await _pump(tester);
    final grid = find.byKey(const ValueKey('settings-top-cards'));
    expect(grid, findsOneWidget);
    expect(
        find.descendant(of: grid, matching: find.byType(KuteActionCard)),
        findsNWidgets(4));
    final backup = tester.getRect(_card('backup'));
    final pin = tester.getRect(_card('pin'));
    final referral = tester.getRect(_card('referral'));
    final support = tester.getRect(_card('support'));
    // Two rows of two equal squares-ish cards.
    expect(pin.top, closeTo(backup.top, 0.5));
    expect(pin.left, greaterThan(backup.right));
    expect(referral.top, greaterThan(backup.bottom));
    expect(support.top, closeTo(referral.top, 0.5));
    expect(support.left, greaterThan(referral.right));
    expect(backup.width, closeTo(pin.width, 0.5));
    // As tall as their content, the row's taller card setting both.
    expect(backup.height, closeTo(pin.height, 0.5));
    // Their words, and nothing of them repeated as a row.
    for (final (id, title, line) in [
      ('backup', _l10n.settingsBackupAndRecovery,
          _l10n.settingsBackupAndRecoverySubtitle),
      ('pin', _l10n.appPin, _l10n.changeUnlockCode),
      ('referral', _l10n.settingsReferralProgram, _l10n.shareCodeTitle),
      ('support', _l10n.chatWithSupport, _l10n.getHelpFromKuteTeam),
    ]) {
      expect(find.descendant(of: _card(id), matching: find.text(title)),
          findsOneWidget);
      expect(find.descendant(of: _card(id), matching: find.text(line)),
          findsOneWidget);
      expect(find.text(title), findsOneWidget);
      expect(_row(title), findsNothing);
    }
    // The rest below the cards, as rows.
    final security = tester.getRect(find.text(_l10n.security));
    expect(security.top, greaterThan(support.bottom));
    expect(_row(_l10n.settingsNotifications), findsOneWidget);
    expect(_row(_l10n.settingsRateTheApp), findsOneWidget);
    expect(tester.getRect(_row(_l10n.settingsRateTheApp)).top,
        greaterThan(security.top));
    expect(find.text(_l10n.advanced), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'referral program withheld: Rate the app takes its card, and is not '
      'a row as well', (tester) async {
    await _pump(tester, referral: false);
    expect(_card('referral'), findsNothing);
    expect(_card('rate'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('settings-top-cards')),
            matching: find.byType(KuteActionCard)),
        findsNWidgets(4));
    expect(find.text(_l10n.settingsRateTheApp), findsOneWidget);
    expect(_row(_l10n.settingsRateTheApp), findsNothing);
    expect(find.text(_l10n.settingsSupportAndFeedback), findsNothing);
  });

  testWidgets('the App PIN card opens the change-PIN sheet', (tester) async {
    await _pump(tester);
    await tester.tap(_card('pin'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(ChangePinSheet), findsOneWidget);
  });

  testWidgets('dark mode: the cards draw on the dark surface, no overflow',
      (tester) async {
    await _pump(tester, dark: true);
    expect(find.byType(KuteActionCard), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });
}
