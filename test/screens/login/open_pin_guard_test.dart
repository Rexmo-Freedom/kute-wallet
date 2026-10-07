import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/login/open_pin.dart';
import 'package:kute/screens/recovery/storage_unavailable_screen.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/services/secure/secret_error_class.dart';
import 'package:kute/services/secure/storage_bootstrap.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:local_auth/local_auth.dart';

import '../../services/support/fake_secret_store.dart';

class _FakeLocalAuth extends LocalAuthentication {
  int supportChecks = 0;

  @override
  Future<bool> isDeviceSupported() async {
    supportChecks++;
    return false;
  }

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async => const [];
}

Settings _settings({required bool biometrics}) => Settings(
      wallets: [WalletConfig(id: 'w1', name: 'Spending')],
      activeWalletId: 'w1',
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: true,
      biometricsEnabled: biometrics,
      bitcoinElectrumNode: 'ssl://example.com:50002',
      nodeType: 'electrum',
      reviewDone: true,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeKeychain keychain;

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    keychain = FakeKeychain();
    SecretStores.debugOverride(local: keychain.local, synced: keychain.synced);
    StorageUnavailableScreen.debugReset();
  });

  tearDown(SecretStores.debugReset);

  Widget app(ProviderContainer container, GoRouter router) =>
      UncontrolledProviderScope(
        container: container,
        child: ScreenUtilInit(
          designSize: const Size(430, 932),
          builder: (_, __) => MaterialApp.router(
            routerConfig: router,
            theme: ThemeData(
                fontFamily: 'Inter', extensions: [AppColorsExtension.light()]),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );

  void sizeView(WidgetTester tester) {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget stub(String name, GoRouterState state) =>
      Scaffold(body: Text('route:$name ${state.extra}'));

  Future<ProviderContainer> pumpOpenPin(
    WidgetTester tester, {
    StorageBootState boot = StorageBootState.ok,
    bool biometrics = false,
    LocalAuthentication? localAuth,
  }) async {
    sizeView(tester);
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith(
          (ref) => SettingsModel(_settings(biometrics: biometrics))),
    ]);
    addTearDown(container.dispose);
    container.read(storageBootStateProvider.notifier).state = boot;
    final router = GoRouter(initialLocation: '/open_pin', routes: [
      GoRoute(
          path: '/open_pin',
          builder: (_, __) =>
              OpenPin(localAuth: localAuth ?? _FakeLocalAuth())),
      GoRoute(
          path: '/restore_secrets',
          builder: (_, s) => stub('restore_secrets', s)),
      GoRoute(
          path: '/storage_unavailable',
          builder: (_, s) => stub('storage_unavailable', s)),
      GoRoute(path: '/home', builder: (_, s) => stub('home', s)),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(app(container, router));
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> typePin(WidgetTester tester, String digits) async {
    for (final d in digits.split('')) {
      await tester.tap(find.text(d));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    await tester.pump();
  }

  bool wiped() => keychain.mutations.any((m) => m.op.startsWith('delete'));

  testWidgets('a PIN without any PIN material never counts or wipes',
      (tester) async {
    await pumpOpenPin(tester);
    await typePin(tester, '222222');
    await tester.pumpAndSettle();

    expect(find.textContaining('route:restore_secrets'), findsOneWidget);
    expect(find.textContaining('secretsMissing'), findsOneWidget);
    expect(keychain.peek('failed_pin_attempts'), isNull);
    expect(keychain.mutations, isEmpty);
  });

  testWidgets('an unreadable PIN opens the retry screen without counting',
      (tester) async {
    keychain
      ..seed('pin', '111111')
      ..failRead('local', PlatformException(code: 'x', details: -25308),
          key: 'pin_hash');
    await pumpOpenPin(tester);
    await typePin(tester, '222222');
    await tester.pumpAndSettle();

    expect(find.textContaining('route:storage_unavailable'), findsOneWidget);
    expect(keychain.peek('failed_pin_attempts'), isNull);
    expect(keychain.mutations, isEmpty);
  });

  testWidgets('a normal start keeps the wipe warning and Forgot PIN',
      (tester) async {
    keychain.seed('pin', '111111');
    await pumpOpenPin(tester);
    await typePin(tester, '222222');

    expect(keychain.peek('failed_pin_attempts'), '1');
    expect(find.text('5 attempts remaining'), findsOneWidget);
    expect(find.text('Forgot PIN?'), findsOneWidget);
    expect(find.byKey(const ValueKey('open-pin-restore')), findsNothing);
  });

  group('binding mismatch', () {
    testWidgets('delays still apply', (tester) async {
      keychain
        ..seed('pin', '111111')
        ..seed('failed_pin_attempts', '2');
      await pumpOpenPin(tester, boot: StorageBootState.bindingMismatch);
      await typePin(tester, '222222');

      expect(keychain.peek('failed_pin_attempts'), '3');
      expect(keychain.peek('lockout_until'), isNotNull);
      expect(find.text('Locked for 30s'), findsOneWidget);
    });

    testWidgets('the counter stops at five and nothing is wiped',
        (tester) async {
      keychain
        ..seed('pin', '111111')
        ..seed('failed_pin_attempts', '5');
      await pumpOpenPin(tester, boot: StorageBootState.bindingMismatch);
      await typePin(tester, '222222');

      expect(keychain.peek('failed_pin_attempts'), '5');
      expect(find.text('Locked for 5m 00s'), findsOneWidget);
      expect(wiped(), isFalse);
      expect(keychain.peek('pin'), '111111');
    });

    testWidgets('offers Restore wallets instead of Forgot PIN', (tester) async {
      keychain.seed('pin', '111111');
      await pumpOpenPin(tester, boot: StorageBootState.bindingMismatch);
      expect(find.text('Forgot PIN?'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('open-pin-restore')));
      await tester.pumpAndSettle();
      expect(find.textContaining('bindingMismatch'), findsOneWidget);
    });
  });

  group('biometric start', () {
    testWidgets('waits while the app is not resumed', (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      addTearDown(() => tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
      keychain.seed('pin', '111111');
      final localAuth = _FakeLocalAuth();
      await pumpOpenPin(tester, biometrics: true, localAuth: localAuth);
      expect(localAuth.supportChecks, 0);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(localAuth.supportChecks, 1);
    });

    testWidgets('starts at once when resumed', (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      keychain.seed('pin', '111111');
      final localAuth = _FakeLocalAuth();
      await pumpOpenPin(tester, biometrics: true, localAuth: localAuth);
      expect(localAuth.supportChecks, 1);
    });

    testWidgets(
        'waits for the PIN when a V1-only wallet has no stored biometric PIN',
        (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      keychain
        ..seed('pin', '111111')
        ..seed('mnemonic_w1', 'cipher');
      final localAuth = _FakeLocalAuth();
      await pumpOpenPin(tester, biometrics: true, localAuth: localAuth);
      expect(localAuth.supportChecks, 0);
      expect(keychain.mutations, isEmpty);
    });

    testWidgets('prompts when the V1-only wallet has a stored biometric PIN',
        (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      keychain
        ..seed('pin', '111111')
        ..seed('mnemonic_w1', 'cipher')
        ..seed('biometric_pin', '111111');
      final localAuth = _FakeLocalAuth();
      await pumpOpenPin(tester, biometrics: true, localAuth: localAuth);
      expect(localAuth.supportChecks, 1);
    });
  });

  group('storage unavailable screen', () {
    Future<void> pumpScreen(
        WidgetTester tester, StorageBootResult result) async {
      sizeView(tester);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final router = GoRouter(initialLocation: '/storage_unavailable', routes: [
        GoRoute(
            path: '/storage_unavailable',
            builder: (_, __) => StorageUnavailableScreen(result: result)),
        GoRoute(path: '/splash', builder: (_, s) => stub('splash', s)),
        GoRoute(
            path: '/restore_secrets',
            builder: (_, s) => stub('restore_secrets', s)),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(app(container, router));
      await tester.pumpAndSettle();
    }

    testWidgets('shows retry without a keypad, Start fresh or Forgot PIN',
        (tester) async {
      await pumpScreen(
          tester,
          const StorageBootResult(StorageBootState.storageUnavailable,
              errorClass: SecretErrorClass.decode, failStarts: 1));
      expect(find.text('Try again'), findsOneWidget);
      expect(find.byKey(const ValueKey('storage-restore')), findsNothing);
      expect(find.text('Start fresh'), findsNothing);
      expect(find.text('Forgot PIN?'), findsNothing);
      expect(find.text('1'), findsNothing);
    });

    testWidgets('offers Restore wallets after three definitive starts',
        (tester) async {
      await pumpScreen(
          tester,
          const StorageBootResult(StorageBootState.storageUnavailable,
              errorClass: SecretErrorClass.decode, failStarts: 3));
      await tester.tap(find.byKey(const ValueKey('storage-restore')));
      await tester.pumpAndSettle();
      expect(find.textContaining('storageUnavailable'), findsOneWidget);
    });

    testWidgets('retrying backs off', (tester) async {
      const result = StorageBootResult(StorageBootState.storageUnavailable);
      await pumpScreen(tester, result);
      await tester.tap(find.byKey(const ValueKey('storage-retry')));
      await tester.pumpAndSettle();
      expect(find.textContaining('route:splash'), findsOneWidget);

      await pumpScreen(tester, result);
      expect(find.text('Try again (2s)'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Try again'), findsOneWidget);
    });
  });
}
