// A password manager that makes a passkey but returns no WebAuthn PRF key
// (Microsoft Authenticator, some other third-party providers) cannot hold a
// Kute wallet: the seed is derived from that key. The SDK reports it from
// `register()` as `createdButNotDerived(source: prfNotSupported)` (the
// create sheet succeeded, the pinned assertion that follows returned no
// PRF output), and from `signIn()` as `prf(prfNotSupported)`.
//
// Before: the create flow treated that as a generic failure and silently
// made a recovery-phrase wallet ("Couldn't set up Face ID. Your wallet was
// created with recovery words instead.") or, with the session locked,
// showed "Couldn't create your wallet". Now: nothing is created, and a
// sheet says why and offers the ways forward.

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/models/breez/sdk_instance.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/creation/passkey_choice.dart';
import 'package:kute/services/passkey_service.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:local_auth/local_auth.dart';

import '../../services/support/fake_secret_store.dart';
import '../../helpers/kute_bar_test_support.dart';

const phrase =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

/// What the SDK throws, exactly: `register()` after a create ceremony in a
/// manager without PRF, and `signIn()` resolving such a passkey.
final _createdNoPrf = PasskeyError.createdButNotDerived(
  credentialId: Uint8List.fromList([9, 9, 9]),
  source: const PrfProviderError.prfNotSupported(),
);
final _signInNoPrf = PasskeyError.prf(const PrfProviderError.prfNotSupported());
final _noCredential =
    PasskeyError.prf(const PrfProviderError.credentialNotFound('none'));

class _FakeLocalAuth extends LocalAuthentication {
  @override
  Future<bool> isDeviceSupported() async => true;

  @override
  Future<bool> get canCheckBiometrics async => true;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async =>
      const [BiometricType.face];
}

class _Auth extends AuthModel {
  final stored = <String, String>{};

  @override
  Future<String> generateMnemonic() async => phrase;

  @override
  Future<void> setMnemonic(String walletId, String mnemonic) async =>
      stored[walletId] = mnemonic;
}

class _Settings extends SettingsModel {
  _Settings()
      : super(Settings(
          currency: 'USD',
          language: 'en',
          btcFormat: 'sats',
          backup: false,
          biometricsEnabled: true,
          bitcoinElectrumNode: 'https://blockstream.info/api',
          nodeType: 'Blockstream',
          reviewDone: false,
          wallets: const [],
        ));

  @override
  Future<WalletConfig> addWallet(WalletConfig newWallet) async {
    state = state.copyWith(
        wallets: [...state.wallets, newWallet], activeWalletId: newWallet.id);
    return newWallet;
  }

  @override
  Future<void> setRecoveryCheckAddress(String walletId, String address) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late List<(String, Map<String, Object>?)> events;
  late List<String> calls;
  late FakeKeychain keychain;

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    keychain = FakeKeychain();
    SecretStores.debugOverride(local: keychain.local, synced: keychain.synced);
    events = [];
    calls = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    // The recovery-phrase path clears the affiliate session through the
    // plugin directly.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (_) async => null);
  });

  tearDown(() {
    TrackingService.debugTrackObserver = null;
    SecretStores.debugReset();
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
  });

  Future<(_Settings, _Auth)> pump(
    WidgetTester tester, {
    required Future<Wallet> Function(String) signIn,
    required Future<Wallet> Function(String, String) register,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = _Settings();
    final auth = _Auth();
    final ceremonies = PasskeyCeremonies(
      signIn: (label) {
        calls.add('sign_in');
        return signIn(label);
      },
      register: (label, name) {
        calls.add('register');
        return register(label, name);
      },
      hasLegacyCredential: () async => false,
      hasKnownCredential: () async => false,
      cacheLabel: (_) async => calls.add('cache_label'),
      markPending: (_) async => calls.add('mark_pending'),
      publishLabel: (_) => calls.add('publish_label'),
      scheduleProvisioning: ({
        required mnemonic,
        required walletId,
        required evmDerivationVersion,
      }) {},
    );
    final router = GoRouter(initialLocation: '/passkey_choice', routes: [
      GoRoute(
          path: '/passkey_choice',
          builder: (_, __) => PasskeyChoice(
                nextRoute: '/home',
                ceremonies: ceremonies,
                localAuth: _FakeLocalAuth(),
              )),
      GoRoute(
          path: '/home',
          builder: (_, __) => const Scaffold(body: Text('HOME'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => settings),
        authModelProvider.overrideWith((ref) => auth),
        sessionUnlockedProvider.overrideWith((ref) => true),
        breezSDKProvider.overrideWith((ref) async =>
            BreezSdkSpark.forTesting(connectSdk: (_) async => throw 'test')),
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
    await tester.pumpAndSettle();
    return (settings, auth);
  }

  /// The screen's Continue spinner animates while the sheet is up, so
  /// pumpAndSettle would never return; pump a few frames.
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  List<Map<String, Object>?> paramsOf(String event) =>
      [for (final (e, p) in events) if (e == event) p];

  const title = "This password manager can't hold your Kute wallet";

  testWidgets(
      'register without PRF shows the sheet and creates nothing '
      '(the original failure)', (tester) async {
    final (settings, auth) = await pump(
      tester,
      signIn: (_) async => throw _noCredential,
      register: (_, __) async => throw _createdNoPrf,
    );
    await tester.tap(kuteBarPrimary);
    await pumpFrames(tester);

    expect(find.text(title), findsOneWidget);
    expect(calls, ['sign_in', 'register']);
    // Nothing created: no wallet record, no phrase, no label, no pin, no
    // seed in storage, no silent recovery-words fallback.
    expect(settings.state.wallets, isEmpty);
    expect(auth.stored, isEmpty);
    expect(keychain.keys(), isEmpty);
    expect(paramsOf('passkey_choice_fallback_bip'), isEmpty);
    expect(paramsOf('passkey_prf_unsupported').single,
        {'platform': 'android', 'stage': 'create'});
    // Android names its own manager.
    expect(kuteBarPrimaryWithText('Use Google Password Manager'),
        findsOneWidget);
    expect(find.text('Pick Google Password Manager when asked'),
        findsOneWidget);
    expect(find.text('Use a recovery phrase instead'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    // No provider name, label or id in analytics.
    for (final (_, p) in events) {
      for (final v in (p ?? const {}).values) {
        expect('$v', isNot(contains('090909')));
        expect('$v', isNot(contains('Spending Wallet')));
      }
    }
  });

  testWidgets('"Use a recovery phrase instead" lands on the phrase wallet',
      (tester) async {
    final (settings, auth) = await pump(
      tester,
      signIn: (_) async => throw _noCredential,
      register: (_, __) async => throw _createdNoPrf,
    );
    await tester.tap(kuteBarPrimary);
    await pumpFrames(tester);
    await tester.tap(find.text('Use a recovery phrase instead'));
    await tester.pumpAndSettle();

    final wallet = settings.state.wallets.single;
    expect(wallet.isPasskey, isFalse);
    expect(wallet.backedUp, isFalse, reason: 'the backup flow shows the words');
    expect(auth.stored[wallet.id], phrase);
    expect(find.text('HOME'), findsOneWidget);
    expect(paramsOf('passkey_prf_unsupported_action').single,
        {'stage': 'create', 'action': 'use_phrase'});
    expect(tester.takeException(), isNull);
    // The phrase path schedules its Predictions setup 5 s out.
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets(
      '"Use Google Password Manager" re-runs the create sheet, and a PRF '
      'manager there creates the passkey wallet', (tester) async {
    var attempts = 0;
    final (settings, _) = await pump(
      tester,
      signIn: (_) async => throw _noCredential,
      register: (label, _) async {
        if (attempts++ == 0) throw _createdNoPrf;
        return Wallet(
            seed: Seed.mnemonic(mnemonic: phrase, passphrase: null),
            label: label);
      },
    );
    await tester.tap(kuteBarPrimary);
    await pumpFrames(tester);
    await tester.tap(kuteBarPrimaryWithText('Use Google Password Manager'));
    await tester.pumpAndSettle();

    // Straight back to the create sheet: signing in first would only
    // find the passkey the other manager just made.
    expect(calls.take(3), ['sign_in', 'register', 'register']);
    expect(settings.state.wallets.single.isPasskey, isTrue);
    expect(find.text('HOME'), findsOneWidget);
    expect(paramsOf('passkey_prf_unsupported_action').single,
        {'stage': 'create', 'action': 'use_default_manager'});
  });

  testWidgets(
      'a sign-in that resolves a passkey without PRF never mints; '
      '"Try again" signs in again', (tester) async {
    final (settings, _) = await pump(
      tester,
      signIn: (_) async => throw _signInNoPrf,
      register: (_, __) async => throw StateError('must not mint'),
    );
    await tester.tap(kuteBarPrimary);
    await pumpFrames(tester);

    expect(find.text(title), findsOneWidget);
    expect(calls, ['sign_in']);
    expect(paramsOf('passkey_prf_unsupported').single,
        {'platform': 'android', 'stage': 'sign_in'});

    await tester.tap(find.text('Try again'));
    await pumpFrames(tester);

    expect(calls, ['sign_in', 'sign_in']);
    expect(find.text(title), findsOneWidget);
    expect(settings.state.wallets, isEmpty);

    // Dismissing creates nothing and resets the screen.
    Navigator.of(tester.element(find.text(title))).pop();
    await tester.pumpAndSettle();
    expect(settings.state.wallets, isEmpty);
    expect(find.byType(PasskeyChoice), findsOneWidget);
    expect(kuteBarPrimaryProbe(tester).onPressed, isNotNull);
    expect(paramsOf('passkey_prf_unsupported_action').last,
        {'stage': 'sign_in', 'action': 'dismissed'});
  });

  testWidgets('iOS names Apple Passwords on the sheet and the choice screen',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await pump(
      tester,
      signIn: (_) async => throw _noCredential,
      register: (_, __) async => throw _createdNoPrf,
    );
    expect(find.text('Works with Apple Passwords'), findsOneWidget);

    await tester.tap(kuteBarPrimary);
    await pumpFrames(tester);
    expect(kuteBarPrimaryWithText('Use Apple Passwords'), findsOneWidget);
    expect(find.text('Pick Passwords when asked'), findsOneWidget);
    expect(paramsOf('passkey_prf_unsupported').single,
        containsPair('platform', 'ios'));
    Navigator.of(tester.element(find.text(title))).pop();
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Android choice screen names Google Password Manager',
      (tester) async {
    await pump(
      tester,
      signIn: (_) async => throw _noCredential,
      register: (_, __) async => throw _createdNoPrf,
    );
    expect(find.text('Works with Google Password Manager'), findsOneWidget);
  });

  group('PasskeyService.isPrfUnsupportedError', () {
    test('matches every shape a manager without PRF produces', () {
      expect(PasskeyService.isPrfUnsupportedError(_createdNoPrf), isTrue);
      expect(PasskeyService.isPrfUnsupportedError(_signInNoPrf), isTrue);
      expect(
          PasskeyService.isPrfUnsupportedError(PasskeyError.prf(
              const PrfProviderError.prfEvaluationFailed('invalid'))),
          isTrue);
      // Android: `prf` with no `results` arrives as a generic error.
      expect(
          PasskeyService.isPrfUnsupportedError(
              PasskeyError.createdButNotDerived(
                  credentialId: Uint8List(1),
                  source: const PrfProviderError.generic(
                      'PasskeyPrfException(unknown): PRF evaluation failed'))),
          isTrue);
      // Legacy channel.
      expect(
          PasskeyService.isPrfUnsupportedError(PlatformException(
              code: 'PRF_UNAVAILABLE',
              message: 'Credential did not return PRF output')),
          isTrue);
    });

    test('never matches a cancel, a timeout, a missing credential or an '
        'old OS', () {
      for (final e in <Object>[
        PasskeyError.prf(const PrfProviderError.userCancelled()),
        PasskeyError.prf(const PrfProviderError.userTimedOut()),
        _noCredential,
        PasskeyError.createdButNotDerived(
            credentialId: Uint8List(1),
            source: const PrfProviderError.userCancelled()),
        PasskeyError.prf(const PrfProviderError.generic('network')),
        const PasskeyError.nostrReadFailed('relay'),
        PlatformException(
            code: 'PRF_UNAVAILABLE',
            message: 'Passkey PRF requires iOS 18.4 or newer'),
        StateError('x'),
      ]) {
        expect(PasskeyService.isPrfUnsupportedError(e), isFalse,
            reason: '$e');
      }
    });
  });
}
