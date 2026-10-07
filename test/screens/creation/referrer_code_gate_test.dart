// The referral-code and share-code onboarding steps are part of the
// affiliate promotion, so they show only where the runtime policy allows
// `affiliate.program`. The survey decides at its navigation point on the
// current snapshot, and both screens skip themselves when reached anyway
// (deep link). Failing closed: no policy means no step. A referrer
// captured from an AppsFlyer deferred deep link stays pending either way;
// the backend decides whether it binds.

import 'dart:convert';

import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/screens/creation/beta_survey_screen.dart';
import 'package:kute/screens/creation/referrer_code_screen.dart';
import 'package:kute/screens/creation/share_code_screen.dart';
import 'package:kute/services/appsflyer_service.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// A policy that names `affiliate.program` as [allowed], or answers 500 so
/// no policy loads at all ([available] false).
RuntimeCapabilitiesService _policy(
        {required bool allowed, bool available = true}) =>
    RuntimeCapabilitiesService.forTesting(
      client: MockClient((request) async {
        if (!available) return http.Response('down', 500);
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
                  'allowed': allowed,
                  'reason': allowed ? '' : 'country_blocked',
                  'comingSoon': false,
                },
              },
            }),
            200);
      }),
      baseUrl: () => 'https://policy.test',
      sessionToken: () => 'test-session',
      appVersion: () async => '2.0.4',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> events;
  late Map<String, Map<String, Object>?> eventParams;

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    FlutterSecureStorage.setMockInitialValues({});
    AppsFlyerService.clearCapturedReferrer();
    AppsFlyerService.onReferrerCaptured = null;
    TrackingService.setDisabled(true);
    events = [];
    eventParams = {};
    TrackingService.debugTrackObserver = (e, p) {
      events.add(e);
      eventParams[e] = p;
    };
  });

  tearDown(() {
    TrackingService.debugTrackObserver = null;
    RuntimeCapabilitiesService.debugInstance = null;
    AppsFlyerService.clearCapturedReferrer();
    AppsFlyerService.onReferrerCaptured = null;
  });

  Future<RuntimeCapabilitiesService> install(
      {required bool allowed, bool available = true}) async {
    final policy = _policy(allowed: allowed, available: available);
    RuntimeCapabilitiesService.debugInstance = policy;
    expect(await policy.refresh(), available);
    return policy;
  }

  // The service arms an expiry timer on a loaded policy; widget tests must
  // not end with it pending, so each test disposes its policy last.

  Future<GoRouter> pump(WidgetTester tester, {required String at}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(initialLocation: at, routes: [
      GoRoute(
          path: '/beta_survey', builder: (_, __) => const BetaSurveyScreen()),
      GoRoute(
          path: '/referrer_code',
          builder: (_, __) => const ReferrerCodeScreen()),
      GoRoute(path: '/share_code', builder: (_, __) => const ShareCodeScreen()),
      GoRoute(
          path: '/home',
          builder: (_, __) => const Scaffold(body: Text('Home'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp.router(
          routerConfig: router,
          theme: ThemeData(
              splashFactory: NoSplash.splashFactory,
              fontFamily: 'Inter',
              extensions: [AppColorsExtension.light()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return router;
  }

  String location(GoRouter router) =>
      router.routerDelegate.currentConfiguration.uri.path;

  testWidgets('allowed: the survey leads to the referral-code step',
      (tester) async {
    final policy = await install(allowed: true);
    final router = await pump(tester, at: '/beta_survey');
    await tester.tap(find.text('Skip this step'));
    await tester.pumpAndSettle();

    expect(location(router), '/referrer_code');
    expect(find.byType(ReferrerCodeScreen), findsOneWidget);
    expect(find.text("Got a friend's code?"), findsOneWidget);
    expect(events, contains('onboarding_referrer_shown'));
    expect(events, isNot(contains('onboarding_referrer_skipped')));
    expect(tester.takeException(), isNull);
    policy.dispose();
  });

  testWidgets('blocked: the survey skips the step and lands on Home',
      (tester) async {
    final policy = await install(allowed: false);
    final router = await pump(tester, at: '/beta_survey');
    await tester.tap(find.text('Skip this step'));
    await tester.pumpAndSettle();

    expect(location(router), '/home');
    expect(find.text('Home'), findsOneWidget);
    expect(find.byType(ReferrerCodeScreen), findsNothing);
    expect(find.byType(ShareCodeScreen), findsNothing);
    expect(events, isNot(contains('onboarding_referrer_shown')));
    expect(events, isNot(contains('onboarding_share_code_viewed')));
    expect(
        events.where((e) => e == 'onboarding_referrer_skipped'), hasLength(1));
    expect(eventParams['onboarding_referrer_skipped'],
        containsPair('reason', 'blocked'));
    expect(tester.takeException(), isNull);
    policy.dispose();
  });

  testWidgets('policy unavailable: the step is skipped (fails closed)',
      (tester) async {
    final policy = await install(allowed: true, available: false);
    final router = await pump(tester, at: '/beta_survey');
    await tester.tap(find.text('Skip this step'));
    await tester.pumpAndSettle();

    expect(location(router), '/home');
    expect(find.byType(ReferrerCodeScreen), findsNothing);
    expect(events, isNot(contains('onboarding_referrer_shown')));
    expect(events, contains('onboarding_referrer_skipped'));
    expect(tester.takeException(), isNull);
    policy.dispose();
  });

  testWidgets(
      'blocked: the referral-code screen opened directly moves on, and a '
      'deep-link referrer stays pending', (tester) async {
    final policy = await install(allowed: false);
    AppsFlyerService.onReferrerCaptured = AffiliateService.setPendingReferrer;
    AppsFlyerService.handleDeepLinkForTest(DeepLinkResult(
        status: DeepLinkStatus.found,
        deepLink: DeepLink({'deep_link_value': 'friend7'})));
    await tester.pump();

    final router = await pump(tester, at: '/referrer_code');

    expect(location(router), '/home');
    expect(find.text("Got a friend's code?"), findsNothing);
    expect(find.byType(ReferrerCodeScreen), findsNothing);
    expect(events, isNot(contains('onboarding_referrer_shown')));
    expect(events, isNot(contains('onboarding_referrer_prefilled')));
    expect(events, contains('onboarding_referrer_skipped'));
    // The captured code is not the user's to confirm here, but it is not
    // dropped either: authWallet still forwards it and the backend decides.
    expect(AppsFlyerService.capturedReferrer, 'FRIEND7');
    expect(await secureStorageRead('kute_pending_referrer'), 'FRIEND7');
    expect(tester.takeException(), isNull);
    policy.dispose();
  });

  testWidgets('blocked: the share-code screen opened directly moves on',
      (tester) async {
    final policy = await install(allowed: false);
    final router = await pump(tester, at: '/share_code');

    expect(location(router), '/home');
    expect(find.byType(ShareCodeScreen), findsNothing);
    expect(events, isNot(contains('onboarding_share_code_viewed')));
    expect(events, isNot(contains('onboarding_share_code_continued')));
    expect(tester.takeException(), isNull);
    policy.dispose();
  });
}

Future<String?> secureStorageRead(String key) =>
    const FlutterSecureStorage().read(key: key);
