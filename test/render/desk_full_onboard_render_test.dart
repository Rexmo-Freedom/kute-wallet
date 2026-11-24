// Onboarding and the lock on a laptop (round three; founder, 25 November
// 2026: "it must be all occupying full screen when we can"): every step
// before the wallet opens is the split screen on EXPANDED
// (kute_split_screen.dart): the brand half on the left, the step's form at
// phone width on the right, its primary under the form inside that half,
// never the floating bar at the bottom middle. The Start screen stays its
// centred hero. Checked at every EXPANDED size; shot when asked:
// DESK_FULL_RENDER=<dir>.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/share_link_model.dart';
import 'package:kute/platform/kute_layout.dart';
import 'package:kute/platform/kute_wide_frames.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/screens/creation/beta_survey_screen.dart';
import 'package:kute/screens/creation/confirm_pin.dart';
import 'package:kute/screens/creation/passkey_choice.dart';
import 'package:kute/screens/creation/recover_choice.dart';
import 'package:kute/screens/creation/referrer_code_screen.dart';
import 'package:kute/screens/creation/set_pin.dart';
import 'package:kute/screens/creation/start.dart';
import 'package:kute/screens/home/components/kute_shell_bar.dart';
import 'package:kute/screens/login/open_pin.dart';
import 'package:kute/screens/share/claim_screen.dart';
import 'package:kute/screens/shared/custom_keypad.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/lock_overlay.dart';
import 'package:kute/services/api/share_links_api.dart';
import 'package:kute/services/passkey_prf_service.dart';
import 'package:kute/services/passkey_service.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/services/secure/storage_bootstrap.dart';
import 'package:kute/services/share_links_store.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:local_auth/local_auth.dart';

import '../mocks/fake_share_links_api.dart';
import '../services/support/fake_secret_store.dart';
import '../screens/share/share_test_harness.dart' show shareCardVenueOverrides;
import 'desk_full_support.dart';

class _NoBiometrics extends LocalAuthentication {
  @override
  Future<bool> isDeviceSupported() async => false;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async => const [];

  @override
  Future<bool> get canCheckBiometrics async => false;
}

/// A passkey sign-in the person cancels: the recover choice's automatic
/// try ends on the choice itself.
class _CancelledPasskey implements PasskeyClient {
  @override
  Future<SignInResponse> signIn({required SignInRequest request}) async =>
      throw PasskeyError.prf(PrfProviderError.userCancelled());

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Settings _settings() => Settings(
      wallets: [WalletConfig(id: 'w1', name: 'Spending')],
      activeWalletId: 'w1',
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: true,
      biometricsEnabled: false,
      bitcoinElectrumNode: 'ssl://example.com:50002',
      nodeType: 'electrum',
      reviewDone: true,
    );

RuntimeCapabilitiesService _policy() => RuntimeCapabilitiesService.forTesting(
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
                'affiliate.program': {'allowed': true, 'reason': ''},
              },
            }),
            200);
      }),
      baseUrl: () => 'https://policy.test',
      sessionToken: () => 'test-session',
      appVersion: () async => '2.1.0',
    );

final FakeShareLinksApi _claims = FakeShareLinksApi();

/// A step: its page, its route's mode, its providers.
typedef _Step = (Widget Function(), KuteWideMode, List<Override> Function());

List<Override> _signedIn() => [
      settingsProvider.overrideWith((ref) => SettingsModel(_settings())),
      storageBootStateProvider.overrideWith((ref) => StorageBootState.ok),
    ];

List<Override> _fresh() {
  final never = Completer<Settings>();
  return [initialSettingsProvider.overrideWith((ref) => never.future)];
}

final Map<String, _Step> _steps = {
  'start': (() => const Start(), KuteWideMode.column, _fresh),
  'set_pin': (() => const SetPin(), KuteWideMode.split, _fresh),
  'confirm_pin': (() => const ConfirmPin(), KuteWideMode.split, _fresh),
  'open_pin': (
    () => OpenPin(localAuth: _NoBiometrics()),
    KuteWideMode.split,
    _signedIn
  ),
  'passkey_choice': (
    () => const PasskeyChoice(nextRoute: '/home'),
    KuteWideMode.split,
    _fresh
  ),
  'beta_survey': (() => const BetaSurveyScreen(), KuteWideMode.split, _fresh),
  'referrer_code': (
    () => const ReferrerCodeScreen(),
    KuteWideMode.split,
    _fresh
  ),
  'recover_choice': (
    () => const RecoverChoiceScreen(),
    KuteWideMode.split,
    _fresh
  ),
  'claim': (
    () => const ClaimScreen(id: 'lnk_1'),
    KuteWideMode.split,
    () => [
          ..._fresh(),
          shareLinksApiProvider.overrideWithValue(_claims),
          usdBalanceProvider.overrideWith((_) => 0),
          ...shareCardVenueOverrides(),
        ]
  ),
};

/// The lock overlay as the app mounts it (app_widget.dart): over the
/// router and the floating bar, on no route.
Future<void> _pumpLock(WidgetTester tester,
    {required Size size, required bool dark}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(initialLocation: '/', routes: [
    GoRoute(
        path: '/',
        builder: (_, __) => Scaffold(
            body: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _tapsUnderLock++,
                child: const SizedBox.expand()))),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ..._signedIn(),
      appLockedProvider.overrideWith((ref) => true),
    ],
    child: ScreenUtilInit(
      designSize: KuteLayout.designSizeFor(size),
      builder: (_, __) => MaterialApp.router(
        debugShowCheckedModeBanner: false,
        builder: (context, child) => Stack(children: [
          child!,
          const KuteShellBar(),
          const LockOverlay(),
        ]),
        routerConfig: router,
        theme: deskFullTheme(dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  ));
  await deskFullFrames(tester);
}

Future<void> _pump(WidgetTester tester, String name,
    {required Size size, required bool dark}) async {
  if (name == 'lock') return _pumpLock(tester, size: size, dark: dark);
  final (page, mode, overrides) = _steps[name]!;
  await pumpDeskPage(tester,
      size: size, dark: dark, page: page(), mode: mode, overrides: overrides());
}

Future<void> _end(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await deskFullEnd(tester);
}

const List<String> _all = [
  'start',
  'set_pin',
  'confirm_pin',
  'open_pin',
  'passkey_choice',
  'beta_survey',
  'referrer_code',
  'recover_choice',
  'claim',
  'lock',
];

late Directory _hive;

/// Taps that reached the page under the lock (must stay none).
int _tapsUnderLock = 0;
RuntimeCapabilitiesService? _live;

void main() {
  setUpAll(() async {
    _hive = await Directory.systemTemp.createTemp('desk_onboard');
    Hive.init(_hive.path);
  });
  tearDownAll(() async {
    await Hive.close();
    await _hive.delete(recursive: true);
  });
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    TrackingService.setDisabled(true);
    FlutterSecureStorage.setMockInitialValues({});
    final keychain = FakeKeychain();
    SecretStores.debugOverride(local: keychain.local, synced: keychain.synced);
    PasskeyPrfService.clearMemory();
    PasskeyService.debugSetClient(_CancelledPasskey());
    ShareLinksStore.debugMemory = <String, String>{};
    ClaimScreen.debugDestination = (_) async => 'spark1recipient';
    _claims.seed(ShareLink(
      id: 'lnk_1',
      kind: ShareLinkKind.dollars,
      amountMinor: 1250,
      senderLabel: 'Ana',
      status: ShareLinkStatus.open,
      rawStatus: 'open',
      expiresAt: DateTime.now().add(const Duration(days: 7)),
    ));
  });
  tearDown(() {
    PasskeyService.debugSetClient(null);
    SecretStores.debugReset();
    ShareLinksStore.debugMemory = null;
    ClaimScreen.debugDestination = null;
    RuntimeCapabilitiesService.debugInstance = null;
    _live?.dispose();
    _live = null;
  });

  Future<void> policyUp(WidgetTester tester) async {
    final policy = _live = _policy();
    RuntimeCapabilitiesService.debugInstance = policy;
    await tester.runAsync(policy.refresh);
  }

  for (final (label, size) in deskFullExpanded) {
    for (final name in _all) {
      testWidgets('$name at $label: the split screen, nothing stretched',
          (tester) async {
        // The real type: the fit of the PIN pad on a short form is
        // measured with the app's own font, not the test font's squares.
        await deskFullAssets(tester);
        await policyUp(tester);
        await _pump(tester, name, size: size, dark: false);
        expect(tester.takeException(), isNull);
        expectDeskNothingStretched(tester);
        if (name != 'start') {
          // The brand half on the left, the form on the right.
          final brand = tester.getRect(find.byType(StartBrandSide));
          expect(brand.left, 0);
          expect(brand.width, closeTo(size.width / 2, 1));
          // No floating bar over a split screen: its primary is under
          // the form, inside the right half.
          final primaries =
              find.byKey(const ValueKey('kute-bar-primary-button'));
          for (final e in primaries.evaluate()) {
            final r = tester.getRect(find.byWidget(e.widget));
            if (r.isEmpty) continue;
            expect(r.left, greaterThanOrEqualTo(size.width / 2),
                reason: '$name: a primary at $r outside the form half');
          }
          // The keypad fits the form, whole.
          for (final e in find.byType(CustomKeypad).evaluate()) {
            final r = tester.getRect(find.byWidget(e.widget));
            expect(r.bottom, lessThanOrEqualTo(size.height));
            expect(r.left, greaterThanOrEqualTo(size.width / 2));
          }
          // The back button at the form's top left.
          final formLeft = size.width * 3 / 4 - KuteLayout.paneWidth / 2;
          for (final e in find.byType(KuteBackButton).evaluate()) {
            final r = tester.getRect(find.byWidget(e.widget));
            expect(r.left, greaterThanOrEqualTo(formLeft));
            expect(r.left, lessThan(formLeft + 60));
          }
        }
        await _end(tester);
      });
    }
  }

  for (final (label, size) in deskFullExpanded) {
    testWidgets('lock at $label: covers the whole window, no tap through',
        (tester) async {
      _tapsUnderLock = 0;
      await _pump(tester, 'lock', size: size, dark: false);
      for (final at in [
        const Offset(20, 20),
        Offset(size.width / 4, size.height - 20),
        Offset(size.width - 20, 20),
        Offset(size.width / 2, size.height - 30),
      ]) {
        await tester.tapAt(at);
        await tester.pump();
      }
      expect(_tapsUnderLock, 0);
      // The PIN pad works in the form half.
      await tester.tap(find.text('1'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await _end(tester);
    });

    testWidgets('referrer code at $label: the field takes focus and text',
        (tester) async {
      await policyUp(tester);
      await _pump(tester, 'referrer_code', size: size, dark: false);
      final field = find.byType(TextField);
      expect(field, findsOneWidget);
      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, 'friend7');
      await deskFullFrames(tester, 4);
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.focusNode.hasFocus, isTrue);
      expect(editable.controller.text.toLowerCase(), 'friend7');
      // Its primary stays under the form, inside the right half.
      final primary = find.byKey(const ValueKey('kute-dialog-primary'));
      expect(primary, findsOneWidget);
      expect(
          tester.getRect(primary).left, greaterThanOrEqualTo(size.width / 2));
      expect(tester.takeException(), isNull);
      await _end(tester);
    });
  }

  for (final name in _all) {
    for (final (label, size) in [...deskFullExpanded, ...deskFullNarrow]) {
      for (final dark in [false, true]) {
        final mode = dark ? 'dark' : 'light';
        testWidgets('render: $name $label $mode', skip: deskFullDir == null,
            (tester) async {
          await deskFullAssets(tester,
              clips: const ['idle', 'body_idle', 'blink']);
          await policyUp(tester);
          await _pump(tester, name, size: size, dark: dark);
          await deskFullShoot(tester, '${name}_${label}_$mode');
          await _end(tester);
        });
      }
    }
  }
}
