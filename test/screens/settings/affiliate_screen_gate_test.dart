// The Earn dashboard where the runtime policy withholds `affiliate.program`:
// the code card and the late-entry "got a friend's code?" prompt are
// hidden, with no unavailable message in their place. Balances, history
// and payouts keep their own backend rules and stay. Allowed, everything
// shows as before.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/screens/settings/affiliate_screen.dart';
import 'package:kute/screens/shared/capability_block_note.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

const _session = 'test-session';

RuntimeCapabilitiesService _policy({required bool allowed}) =>
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
                  'allowed': allowed,
                  'reason': allowed ? '' : 'country_blocked',
                  'comingSoon': false,
                },
              },
            }),
            200);
      }),
      baseUrl: () => 'https://backend.test',
      sessionToken: () => AffiliateService.sessionToken,
      appVersion: () async => '2.0.4',
    );

/// The affiliate backend for one wallet with a code, no referees and no
/// referrer of its own (so the late-entry prompt is on the table).
http.Client _affiliateBackend() => MockClient((request) async {
      switch (request.url.path) {
        case '/api/v1/affiliate/me':
          return http.Response(
              jsonEncode({
                'affiliate_code': 'KUTE42',
                'commission_rate_pct': 10,
                'referees_bound': 0,
                'accrued_usd': 0,
                'paid_usd': 0,
                'is_referred': false,
                'payments': <Object>[],
              }),
              200);
        case '/api/v1/affiliate/me/history':
          return http.Response(jsonEncode({'history': <Object>[]}), 200);
        case '/api/v1/affiliate/me/referees':
          return http.Response(jsonEncode({'referees': <Object>[]}), 200);
        default:
          return http.Response('not found', 404);
      }
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<(String, Map<String, Object>?)> events;

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    FlutterSecureStorage.setMockInitialValues({});
    dotenv.loadFromString(envString: 'BACKEND=https://backend.test');
    AffiliateService.debugSessionToken = _session;
    TrackingService.setDisabled(true);
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });

  tearDown(() {
    TrackingService.debugTrackObserver = null;
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
  });

  Future<void> pumpEarn(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          home: const AffiliateScreen(),
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
  }

  Map<String, Object>? dashboardParams() => events
      .where((e) => e.$1 == 'affiliate_dashboard_loaded')
      .map((e) => e.$2)
      .single;

  testWidgets('allowed: the code card and the late-entry prompt show',
      (tester) async {
    final policy = _policy(allowed: true);
    RuntimeCapabilitiesService.debugInstance = policy;
    await http.runWithClient(() async {
      await pumpEarn(tester);
      expect(find.text('Your code'), findsOneWidget);
      expect(find.text('KUTE42'), findsOneWidget);
      await tester.scrollUntilVisible(find.text("Got a friend's code?"), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text("Got a friend's code?"), findsOneWidget);
      expect(find.byType(CapabilityBlockNote), findsNothing);
      expect(dashboardParams(), containsPair('late_entry_shown', true));
      expect(tester.takeException(), isNull);
    }, _affiliateBackend);
    policy.dispose();
  });

  testWidgets(
      'blocked: no code card, no late-entry prompt, no unavailable message',
      (tester) async {
    final policy = _policy(allowed: false);
    RuntimeCapabilitiesService.debugInstance = policy;
    await http.runWithClient(() async {
      await pumpEarn(tester);
      expect(find.text('Your code'), findsNothing);
      expect(find.text('KUTE42'), findsNothing);
      expect(find.text("Got a friend's code?"), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(CapabilityBlockNote), findsNothing);
      expect(find.text(policy.blockReason('affiliate.program')!), findsNothing);
      expect(dashboardParams(), containsPair('late_entry_shown', false));
      expect(dashboardParams(), containsPair('participation_allowed', false));
      expect(tester.takeException(), isNull);
    }, _affiliateBackend);
    policy.dispose();
  });
}
