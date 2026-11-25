// Restore ("I already have an account" → "Use your Apple/Google account")
// with a passkey whose password manager returns no WebAuthn PRF key: the
// discovery sign-in, or the confirmation of a discovered wallet, comes back
// as `PasskeyError.prf(prfNotSupported)`. The screen says so honestly and
// offers the recovery phrase; it never stores or wipes anything.

import 'dart:async';
import 'dart:io';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart' as settings_model;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/creation/recover_choice.dart';
import 'package:kute/services/passkey_prf_service.dart';
import 'package:kute/services/passkey_service.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../services/support/fake_secret_store.dart';
import '../../helpers/kute_bar_test_support.dart';

const phrase =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
final credential = Uint8List.fromList([4, 5, 6]);
final _noPrf = PasskeyError.prf(const PrfProviderError.prfNotSupported());

class _Client implements PasskeyClient {
  _Client({this.discoveryError, this.published = const []});

  final Object? discoveryError;
  final List<String> published;
  final requests = <SignInRequest>[];

  @override
  Future<SignInResponse> signIn({required SignInRequest request}) async {
    requests.add(request);
    if (request.label == null) {
      if (discoveryError != null) throw discoveryError!;
      return SignInResponse(
        wallet: Wallet(
          seed: Seed.mnemonic(mnemonic: phrase, passphrase: null),
          label: 'Default',
        ),
        labels: published,
        credential: PasskeyCredential(credentialId: credential),
      );
    }
    // The confirmation answers from a manager that drops the PRF key.
    throw _noPrf;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const legacyChannel = MethodChannel('com.kutewallet.app/passkey_prf');
  late FakeKeychain keychain;
  late Directory hiveDir;
  late List<(String, Map<String, Object>?)> events;
  late List<MethodCall> legacyCalls;

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    keychain = FakeKeychain();
    SecretStores.debugOverride(local: keychain.local, synced: keychain.synced);
    PasskeyPrfService.clearMemory();
    hiveDir = await Directory.systemTemp.createTemp('recover_prf');
    Hive.init(hiveDir.path);
    events = [];
    legacyCalls = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(legacyChannel, (call) async {
      legacyCalls.add(call);
      throw PlatformException(
          code: 'PRF_UNAVAILABLE',
          message: 'Credential did not return PRF output');
    });
  });

  tearDown(() async {
    TrackingService.debugTrackObserver = null;
    PasskeyService.debugSetClient(null);
    PasskeyPrfService.clearMemory();
    SecretStores.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(legacyChannel, null);
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final never = Completer<settings_model.Settings>();
    final router = GoRouter(initialLocation: '/recover', routes: [
      GoRoute(
          path: '/recover',
          builder: (_, __) => const RecoverChoiceScreen()),
      GoRoute(
          path: '/recover_wallet/seed',
          builder: (_, __) => const Scaffold(body: Text('SEED ENTRY'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        initialSettingsProvider.overrideWith((ref) => never.future),
      ],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp.router(
          builder: withKuteShellBar,
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
    await pumpFrames(tester);
  }

  const title = "This password manager didn't return your Kute key";

  List<Map<String, Object>?> paramsOf(String event) =>
      [for (final (e, p) in events) if (e == event) p];

  testWidgets(
      'a discovery passkey without PRF shows the restore sheet, the '
      'recovery phrase as the way through', (tester) async {
    final client = _Client(discoveryError: _noPrf);
    PasskeyService.debugSetClient(client);

    await pumpScreen(tester);

    expect(find.text(title), findsOneWidget);
    expect(kuteBarPrimaryWithText('Restore with your recovery phrase'),
        findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    // One ceremony; the legacy probe would only ask again.
    expect(client.requests, hasLength(1));
    expect(legacyCalls, isEmpty);
    expect(keychain.keys(), isEmpty);
    expect(paramsOf('passkey_prf_unsupported').single,
        {'platform': 'android', 'stage': 'restore_lookup'});

    await tester.tap(kuteBarPrimaryWithText('Restore with your recovery phrase'));
    await tester.pumpAndSettle();
    expect(find.text('SEED ENTRY'), findsOneWidget);
    expect(paramsOf('passkey_prf_unsupported_action').single,
        {'stage': 'restore_lookup', 'action': 'restore_with_phrase'});
  });

  testWidgets('"Try again" runs the lookup again', (tester) async {
    final client = _Client(discoveryError: _noPrf);
    PasskeyService.debugSetClient(client);

    await pumpScreen(tester);
    await tester.tap(find.text('Try again'));
    await pumpFrames(tester);

    expect(client.requests, hasLength(2));
    expect(find.text(title), findsOneWidget);
    expect(paramsOf('passkey_prf_unsupported'), hasLength(2));
    Navigator.of(tester.element(find.text(title))).pop();
    await tester.pumpAndSettle();
    expect(keychain.keys(), isEmpty);
  });

  testWidgets(
      'a wallet confirmation without PRF shows the sign-in variant and '
      'wipes nothing', (tester) async {
    const label = 'Spending Wallet · 1700000000000';
    // What this device already holds: the credential pin and another
    // wallet's cached seed. None of it may be touched.
    keychain.seed('passkey017_credential_id', '040506');
    keychain.seed('passkey017_seed_v1__other', '{"label":"x"}');
    final before = {for (final k in keychain.keys()) k: keychain.peek(k)};
    final client = _Client(published: [label]);
    PasskeyService.debugSetClient(client);

    await pumpScreen(tester);

    expect(find.text(title), findsOneWidget);
    expect(find.text('Nothing was changed. Try again and pick the password '
        'manager that holds your Kute passkey.'), findsOneWidget);
    expect(kuteBarPrimaryWithText('Try again'), findsOneWidget);
    expect(find.text('Restore with your recovery phrase'), findsOneWidget);
    expect(paramsOf('passkey_prf_unsupported').single,
        {'platform': 'android', 'stage': 'restore_confirm'});

    // Try again re-runs the confirmation, pinned to the same credential.
    await tester.tap(kuteBarPrimaryWithText('Try again'));
    await pumpFrames(tester);
    expect(client.requests.where((r) => r.label == label), hasLength(2));
    expect(client.requests.last.allowCredentials, [credential]);
    expect(find.text(title), findsOneWidget);

    await tester.tap(find.text('Restore with your recovery phrase'));
    await tester.pumpAndSettle();
    expect(find.text('SEED ENTRY'), findsOneWidget);
    expect({for (final k in keychain.keys()) k: keychain.peek(k)}, before);
  });

  testWidgets('a legacy probe without PRF shows the restore sheet',
      (tester) async {
    // Discovery finds nothing, so the legacy (pre-2.x) probe runs and its
    // native channel answers without PRF output.
    final client = _Client();
    PasskeyService.debugSetClient(client);

    // The probe reads the cached label from Hive: open the box for real
    // first, outside the test's fake clock.
    await tester.runAsync(() => Hive.openBox('settings'));
    await pumpScreen(tester);

    expect(legacyCalls, isNotEmpty);
    expect(find.text(title), findsOneWidget);
    expect(paramsOf('passkey_prf_unsupported').single,
        containsPair('stage', 'legacy_probe'));
    // The failed derive stored no seed and no credential pin.
    expect(keychain.keys(), isEmpty);
    Navigator.of(tester.element(find.text(title))).pop();
    await tester.pumpAndSettle();
  });
}

Future<void> pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
