// Settings surfaces behind runtime capabilities. A withheld capability
// hides its surface outright (never a disabled row, never an unavailable
// message):
// * `affiliate.program`: the Referral program row.
// * `export.transactions`: the Export section.
// * `settings.advanced`: only the custom Bitcoin server row inside
//   Advanced. The Advanced section itself always
//   shows, with the app version and affiliate id at its top for support.
// The install id (device id) row is gone in every build.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

final _l10n = AppLocalizationsEn();

/// A wallet session token in the backend's shape:
/// base64url(`pubkey|affiliate_id|exp|iat`).sig
String _sessionFor(int affiliateId) {
  final exp = DateTime.now().add(const Duration(days: 7));
  final payload = 'pubkey|$affiliateId|${exp.millisecondsSinceEpoch ~/ 1000}|1';
  return '${base64Url.encode(utf8.encode(payload)).replaceAll('=', '')}.sig';
}

RuntimeCapabilitiesService _policy(Map<String, bool> decisions) =>
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
                for (final e in decisions.entries)
                  e.key: {
                    'allowed': e.value,
                    'reason': e.value ? '' : 'feature_disabled',
                  },
              },
            }),
            200);
      }),
      baseUrl: () => 'https://backend.test',
      sessionToken: () => AffiliateService.sessionToken,
      appVersion: () async => '2.1.0',
    );

const _all = [
  'affiliate.program',
  'export.transactions',
  'settings.advanced',
];

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    TrackingService.setDisabled(true);
  });

  tearDown(() {
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
  });

  Future<void> pumpSettings(WidgetTester tester,
      {required Set<String> denied, String? session}) async {
    AffiliateService.debugSessionToken = session ?? _sessionFor(4242);
    final policy = _policy({for (final id in _all) id: !denied.contains(id)});
    RuntimeCapabilitiesService.debugInstance = policy;
    addTearDown(policy.dispose);
    // Outside the fake clock, so the policy's expiry timer is real.
    expect(await tester.runAsync(policy.refresh), isTrue);

    tester.view.physicalSize = const Size(430, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
          theme: ThemeData(
              fontFamily: 'Inter', extensions: [AppColorsExtension.light()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Settings(),
        ),
      ),
    ));
    await tester.pump();
  }

  Future<void> openAdvanced(WidgetTester tester) async {
    await tester.tap(find.text(_l10n.advanced));
    await tester.pump();
    // The app version label resolves on the next frame.
    await tester.pump();
  }

  testWidgets('all allowed: referral, export and the Bitcoin server show',
      (tester) async {
    await pumpSettings(tester, denied: {});
    expect(find.text(_l10n.settingsReferralProgram), findsOneWidget);
    expect(find.text(_l10n.export), findsOneWidget);
    expect(find.text(_l10n.settingsExportTransactions), findsOneWidget);
    await openAdvanced(tester);
    expect(find.text(_l10n.settingsSupportInfo), findsOneWidget);
    expect(find.text(_l10n.electrumNode), findsOneWidget);
  });

  testWidgets('affiliate.program denied: no referral row, no message',
      (tester) async {
    await pumpSettings(tester, denied: {'affiliate.program'});
    expect(find.text(_l10n.settingsReferralProgram), findsNothing);
    expect(find.text(_l10n.settingsEarnAShareOfFees), findsNothing);
    expect(find.text(_l10n.capabilityUnavailable), findsNothing);
    // The rest of Settings is there, so the absence is meaningful.
    expect(find.text(_l10n.settingsSupportAndFeedback), findsOneWidget);
  });

  testWidgets('export.transactions denied: the Export section is gone',
      (tester) async {
    await pumpSettings(tester, denied: {'export.transactions'});
    expect(find.text(_l10n.export), findsNothing);
    expect(find.text(_l10n.settingsExportTransactions), findsNothing);
    expect(find.text(_l10n.preferences), findsOneWidget);
  });

  testWidgets(
      'settings.advanced denied: Advanced still shows the app version and '
      'affiliate id; only the Bitcoin server row is hidden', (tester) async {
    await pumpSettings(tester, denied: {'settings.advanced'});
    expect(find.text(_l10n.advanced), findsOneWidget);
    await openAdvanced(tester);
    expect(find.text(_l10n.settingsSupportInfo), findsOneWidget);
    expect(find.text(_l10n.settingsAppVersion), findsOneWidget);
    expect(find.text('2.1.0 (78)'), findsOneWidget);
    expect(find.text(_l10n.settingsAffiliateId), findsOneWidget);
    expect(find.text('4242'), findsOneWidget);
    expect(find.text(_l10n.electrumNode), findsNothing);
  });

  testWidgets('every capability denied: Advanced still shows', (tester) async {
    await pumpSettings(tester, denied: _all.toSet());
    expect(find.text(_l10n.settingsReferralProgram), findsNothing);
    expect(find.text(_l10n.export), findsNothing);
    await openAdvanced(tester);
    expect(find.text(_l10n.settingsAppVersion), findsOneWidget);
    expect(find.text(_l10n.settingsAffiliateId), findsOneWidget);
    expect(find.text(_l10n.electrumNode), findsNothing);
  });

  testWidgets('tapping the affiliate id copies it', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await pumpSettings(tester, denied: {});
    await openAdvanced(tester);
    await tester.tap(find.text('4242'));
    await tester.pump();
    expect(copied, '4242');
    expect(find.text(_l10n.copied), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('no wallet session yet: affiliate id reads "not registered"',
      (tester) async {
    // A session without an affiliate (id 0) reads the same as none.
    await pumpSettings(tester, denied: {}, session: _sessionFor(0));
    await openAdvanced(tester);
    expect(find.text(_l10n.settingsAffiliateIdNotRegistered), findsOneWidget);
  });

  testWidgets('no device id row in Settings', (tester) async {
    await pumpSettings(tester, denied: {});
    await openAdvanced(tester);
    expect(find.textContaining('Device ID'), findsNothing);
  });

  test('affiliate id comes from the wallet session token', () {
    expect(AffiliateService.affiliateIdFromToken(_sessionFor(17)), '17');
    expect(AffiliateService.affiliateIdFromToken(_sessionFor(0)), isNull);
    expect(AffiliateService.affiliateIdFromToken(null), isNull);
    expect(AffiliateService.affiliateIdFromToken('garbage'), isNull);
    // An EVM (Ledger) session carries no affiliate.
    final evm = base64Url
        .encode(utf8.encode('0xabc|0|9999999999|1|evm'))
        .replaceAll('=', '');
    expect(AffiliateService.affiliateIdFromToken('$evm.sig'), isNull);
  });
}
