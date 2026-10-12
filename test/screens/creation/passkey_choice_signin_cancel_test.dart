// A cancel on the sign-in sheet on a device that knows no passkey offers a
// fresh passkey instead of stopping; a cancel on the create sheet stops.
// Both report which sheet was dismissed.

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/breez/sdk_instance.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/creation/passkey_choice.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:local_auth/local_auth.dart';

import '../../services/support/fake_secret_store.dart';

const phrase =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

final _cancelled = PasskeyError.prf(PrfProviderError.userCancelled());

class _FakeLocalAuth extends LocalAuthentication {
  @override
  Future<bool> isDeviceSupported() async => true;

  @override
  Future<bool> get canCheckBiometrics async => true;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async =>
      const [BiometricType.face];
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
  Future<void> addWallet(WalletConfig newWallet) async {
    state = state.copyWith(
        wallets: [...state.wallets, newWallet], activeWalletId: newWallet.id);
  }

  @override
  Future<void> setRecoveryCheckAddress(String walletId, String address) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<(String, Map<String, Object>?)> events;
  late List<String> registered;
  late List<String> published;
  late FakeKeychain keychain;

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    keychain = FakeKeychain();
    SecretStores.debugOverride(local: keychain.local, synced: keychain.synced);
    events = [];
    registered = [];
    published = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });

  tearDown(() {
    TrackingService.debugTrackObserver = null;
    SecretStores.debugReset();
  });

  Future<_Settings> pump(
    WidgetTester tester, {
    required Future<Wallet> Function(String) signIn,
    Future<Wallet> Function(String, String)? register,
    bool knownCredential = false,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = _Settings();
    final ceremonies = PasskeyCeremonies(
      signIn: signIn,
      register: register ??
          (label, name) async {
            registered.add(name);
            return Wallet(
                seed: Seed.mnemonic(mnemonic: phrase, passphrase: null),
                label: label);
          },
      hasLegacyCredential: () async => false,
      hasKnownCredential: () async => knownCredential,
      cacheLabel: (_) async {},
      publishLabel: published.add,
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
        breezSDKProvider.overrideWith((ref) async =>
            BreezSdkSpark.forTesting(connectSdk: (_) async => throw 'test')),
      ],
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
    return settings;
  }

  /// The "Setup cancelled" toast runs a 4 s timer; let it finish so the
  /// test ends with no pending timers.
  Future<void> settleToast(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  /// While the offer dialog is up the Continue button's spinner animates
  /// forever, so pumpAndSettle would never return; pump a few frames.
  Future<void> pumpDialog(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
  }

  Map<String, Object>? cancelParams() => events
      .where((e) => e.$1 == 'passkey_choice_cancelled')
      .map((e) => e.$2)
      .lastOrNull;

  testWidgets('a dismissed sign-in sheet on a device with no passkey offers '
      'a new passkey, which creates the wallet', (tester) async {
    final settings =
        await pump(tester, signIn: (_) async => throw _cancelled);
    await tester.tap(find.byType(AppButton));
    await pumpDialog(tester);

    expect(cancelParams(), containsPair('sheet', 'sign_in'));
    expect(find.text('Create a new passkey'), findsOneWidget);
    expect(settings.state.wallets, isEmpty);

    await tester.tap(find.text('Create a new passkey'));
    await tester.pumpAndSettle();

    expect(registered, ['Spending Wallet']);
    expect(settings.state.wallets.single.isPasskey, isTrue);
    expect(settings.state.wallets.single.createdEmpty, isTrue);
    expect(published, hasLength(1));
    expect(find.text('HOME'), findsOneWidget);
    expect(
        events
            .where((e) => e.$1 == 'passkey_choice_create_new_offered')
            .single
            .$2,
        containsPair('accepted', true));
    final selected = events
        .where((e) => e.$1 == 'passkey_choice_passkey_selected')
        .single
        .$2!;
    expect(selected, containsPair('path', 'create_after_cancel'));
    expect(selected.keys, containsAll(['create_ms', 'save_ms', 'total_ms']));
    expect(tester.takeException(), isNull);
  });

  testWidgets('declining the offer creates nothing and resets the screen',
      (tester) async {
    final settings =
        await pump(tester, signIn: (_) async => throw _cancelled);
    await tester.tap(find.byType(AppButton));
    await pumpDialog(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(registered, isEmpty);
    expect(settings.state.wallets, isEmpty);
    expect(find.byType(PasskeyChoice), findsOneWidget);
    expect(
        events
            .where((e) => e.$1 == 'passkey_choice_create_new_offered')
            .single
            .$2,
        containsPair('accepted', false));
    // Continue is enabled again for a retry.
    expect(tester.widget<AppButton>(find.byType(AppButton)).onPressed,
        isNotNull);
    await settleToast(tester);
  });

  testWidgets('a device that knows a passkey gets no offer', (tester) async {
    await pump(tester,
        signIn: (_) async => throw _cancelled, knownCredential: true);
    await tester.tap(find.byType(AppButton));
    await tester.pumpAndSettle();

    expect(cancelParams(), containsPair('sheet', 'sign_in'));
    expect(find.text('Create a new passkey'), findsNothing);
    expect(registered, isEmpty);
    await settleToast(tester);
  });

  testWidgets('a dismissed create sheet stops and names that sheet',
      (tester) async {
    final settings = await pump(
      tester,
      signIn: (_) async => throw PasskeyError.prf(
          PrfProviderError.credentialNotFound('none')),
      register: (_, __) async => throw _cancelled,
    );
    await tester.tap(find.byType(AppButton));
    await tester.pumpAndSettle();

    expect(cancelParams(), containsPair('sheet', 'create'));
    expect(find.text('Create a new passkey'), findsNothing);
    expect(settings.state.wallets, isEmpty);
    expect(find.byType(PasskeyChoice), findsOneWidget);
    await settleToast(tester);
  });
}
