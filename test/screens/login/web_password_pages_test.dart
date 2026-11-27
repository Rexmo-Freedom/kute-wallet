// One secret on the web (unlock_secret.dart, 27 November 2026): every new
// vault takes the 6-digit PIN, laptop browsers included, and on a laptop
// the PIN pad takes digits and Backspace from the keyboard on the create,
// confirm and unlock screens. A vault made with a password (24 to 27
// November) still asks for it on unlock, the lock overlay and the gate
// sheet; there is no password upgrade. Every secret here is a test
// literal.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/platform/browser_signals.dart';
import 'package:kute/platform/kute_layout.dart';
import 'package:kute/platform/unlock_secret.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/creation/confirm_pin.dart';
import 'package:kute/screens/creation/set_pin.dart';
import 'package:kute/screens/home/components/kute_shell_bar.dart';
import 'package:kute/screens/login/open_pin.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/custom_keypad.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/kute_password_field.dart';
import 'package:kute/screens/shared/kute_split_screen.dart';
import 'package:kute/screens/shared/lock_overlay.dart';
import 'package:kute/screens/shared/pin_gate_sheet.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/services/secure/storage_bootstrap.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:local_auth/local_auth.dart';

import '../../helpers/kute_bar_test_support.dart';
import '../../services/support/fake_secret_store.dart';

const testPassword = 'correct horse battery';

/// A device whose biometric check always passes.
class _PassingBiometrics extends LocalAuthentication {
  int prompts = 0;

  @override
  Future<bool> isDeviceSupported() async => true;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async =>
      const [BiometricType.fingerprint];

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<Object?> authMessages = const <Object?>[],
    bool biometricOnly = false,
    bool sensitiveTransaction = true,
    bool persistAcrossBackgrounding = false,
  }) async {
    prompts++;
    return true;
  }
}

class _NoBiometrics extends LocalAuthentication {
  @override
  Future<bool> isDeviceSupported() async => false;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async => const [];
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

/// A focused field's cursor and Sal never settle: fixed frames instead.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeKeychain keychain;
  late Directory hive;

  setUpAll(() async {
    hive = await Directory.systemTemp.createTemp('web_password_pages');
    Hive.init(hive.path);
    // Opened here, for real: the unlock's reads then find it open.
    await Hive.openBox('settings');
  });
  tearDownAll(() async {
    await Hive.close();
    await hive.delete(recursive: true);
  });

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    TrackingService.setDisabled(true);
    keychain = FakeKeychain();
    SecretStores.debugOverride(local: keychain.local, synced: keychain.synced);
  });

  tearDown(() {
    SecretStores.debugReset();
    UnlockSecret.debugVaultKind = null;
    debugBrowserSignals = null;
    KuteKeypadHardwareKeys.debugIsWeb = false;
  });

  /// A Mac laptop's browser.
  void laptopBrowser() {
    debugBrowserSignals = const BrowserSignals(
      maxTouchPoints: 0,
      coarsePointer: false,
      noHover: false,
      userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15',
    );
    KuteKeypadHardwareKeys.debugIsWeb = true;
  }

  /// A laptop browser holding a vault made with a password (24 to 27
  /// November 2026).
  void laptop() {
    laptopBrowser();
    UnlockSecret.debugVaultKind = VaultSecretKind.password;
  }

  Future<ProviderContainer> pump(
    WidgetTester tester,
    String initial, {
    Size size = const Size(1440, 900),
    List<Override> overrides = const [],
    bool lock = false,
    LocalAuthentication? localAuth,
    Settings Function() settings = _settings,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith((ref) => SettingsModel(settings())),
      storageBootStateProvider.overrideWith((ref) => StorageBootState.ok),
      if (lock) appLockedProvider.overrideWith((ref) => true),
      ...overrides,
    ]);
    addTearDown(container.dispose);
    Widget stub(String name) => Scaffold(body: Text('route:$name'));
    Widget split(Widget child) => KuteSplitScreen(child: child);
    final router = GoRouter(initialLocation: initial, routes: [
      GoRoute(path: '/', builder: (_, __) => stub('root')),
      GoRoute(path: '/set_pin', builder: (_, __) => split(const SetPin())),
      GoRoute(
          path: '/confirm_pin', builder: (_, __) => split(const ConfirmPin())),
      GoRoute(
          path: '/open_pin',
          builder: (_, __) =>
              split(OpenPin(localAuth: localAuth ?? _NoBiometrics()))),
      GoRoute(path: '/home', builder: (_, __) => stub('home')),
      GoRoute(path: '/start', builder: (_, __) => stub('start')),
      GoRoute(
          path: '/passkey_choice', builder: (_, __) => stub('passkey_choice')),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: ScreenUtilInit(
        designSize: KuteLayout.designSizeFor(size),
        builder: (_, __) => MaterialApp.router(
          builder: (context, child) => Stack(children: [
            child!,
            const KuteShellBar(),
            if (lock) LockOverlay(localAuth: localAuth ?? _NoBiometrics()),
          ]),
          routerConfig: router,
          theme: ThemeData(
              fontFamily: 'Inter', extensions: [AppColorsExtension.light()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    ));
    await settle(tester);
    return container;
  }

  Future<void> typeAndEnter(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  EditableText editable(WidgetTester tester) =>
      tester.widget<EditableText>(find.byType(EditableText));

  Settings biometricSettings() => Settings(
        wallets: [WalletConfig(id: 'w1', name: 'Spending')],
        activeWalletId: 'w1',
        currency: 'USD',
        language: 'en',
        btcFormat: 'sats',
        backup: true,
        biometricsEnabled: true,
        bitcoinElectrumNode: 'ssl://example.com:50002',
        nodeType: 'electrum',
        reviewDone: true,
      );

  Future<void> letUnlockRun(WidgetTester tester) async {
    // The unlock reads Hive (real file I/O): let it run.
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await settle(tester);
  }


  Future<void> key(WidgetTester tester, LogicalKeyboardKey k,
      {String? character}) async {
    await tester.sendKeyDownEvent(k, character: character);
    await tester.sendKeyUpEvent(k);
    await tester.pump();
  }

  Future<void> typeDigits(WidgetTester tester, String digits) async {
    const keys = {
      '0': LogicalKeyboardKey.digit0,
      '1': LogicalKeyboardKey.digit1,
      '2': LogicalKeyboardKey.digit2,
      '3': LogicalKeyboardKey.digit3,
      '4': LogicalKeyboardKey.digit4,
      '5': LogicalKeyboardKey.digit5,
      '6': LogicalKeyboardKey.digit6,
      '7': LogicalKeyboardKey.digit7,
      '8': LogicalKeyboardKey.digit8,
      '9': LogicalKeyboardKey.digit9,
    };
    for (final d in digits.split('')) {
      await key(tester, keys[d]!, character: d);
    }
  }

  int dots(WidgetTester tester) => tester
      .widget<PinProgressIndicator>(find.byType(PinProgressIndicator))
      .currentLength;

  group('every new vault takes the PIN, laptop browsers included', () {
    testWidgets('create: the PIN pad, no password field; the keyboard '
        'types digits and Backspace removes one', (tester) async {
      laptopBrowser();
      final container = await pump(tester, '/set_pin');
      expect(find.text('Create a PIN'), findsOneWidget);
      expect(find.byType(CustomKeypad), findsOneWidget);
      expect(find.byType(KutePasswordField), findsNothing);
      expect(find.text('Create a password'), findsNothing);
      await typeDigits(tester, '123');
      expect(dots(tester), 3);
      await key(tester, LogicalKeyboardKey.backspace);
      expect(dots(tester), 2);
      // Letters type nothing.
      await key(tester, LogicalKeyboardKey.keyA, character: 'a');
      expect(dots(tester), 2);
      await typeDigits(tester, '3456');
      expect(dots(tester), 6);
      // A seventh digit is refused, as on the pad.
      await typeDigits(tester, '7');
      expect(dots(tester), 6);
      await settle(tester);
      expect(kuteBarPrimaryContext(tester).enabled, isTrue);
      kuteBarPrimaryContext(tester).onPrimary!();
      await settle(tester);
      expect(container.read(pinProvider), '123456');
    });

    testWidgets('confirm: the keyboard types the PIN again', (tester) async {
      laptopBrowser();
      await pump(tester, '/confirm_pin', overrides: [
        pinProvider.overrideWith((ref) => '123456'),
      ]);
      expect(find.byType(CustomKeypad), findsOneWidget);
      expect(find.byType(KutePasswordField), findsNothing);
      await typeDigits(tester, '1235');
      expect(dots(tester), 4);
      await key(tester, LogicalKeyboardKey.backspace);
      await key(tester, LogicalKeyboardKey.backspace);
      expect(dots(tester), 2);
      await typeDigits(tester, '3456');
      expect(dots(tester), 6);
      await settle(tester);
      expect(kuteBarPrimaryContext(tester).enabled, isTrue);
      expect(kuteBarPrimaryContext(tester).label, 'Set PIN');
    });

    testWidgets('unlock: a PIN vault is typed from the keyboard and goes '
        'straight on, no password asked', (tester) async {
      laptopBrowser();
      keychain.seed('pin', '111111');
      await pump(tester, '/open_pin');
      expect(find.byType(CustomKeypad), findsOneWidget);
      expect(find.byType(KutePasswordField), findsNothing);
      await typeDigits(tester, '12');
      await key(tester, LogicalKeyboardKey.backspace);
      await key(tester, LogicalKeyboardKey.backspace);
      expect(dots(tester), 0);
      await typeDigits(tester, '111111');
      await tester.pump(const Duration(milliseconds: 150));
      await letUnlockRun(tester);
      expect(find.text('Create a password'), findsNothing);
      expect(find.byType(KutePasswordField), findsNothing);
      expect(find.textContaining('route:home'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 7));
    });

    testWidgets('unlock: a wrong PIN from the keyboard counts',
        (tester) async {
      laptopBrowser();
      keychain.seed('pin', '111111');
      await pump(tester, '/open_pin');
      await typeDigits(tester, '222222');
      await tester.pump(const Duration(milliseconds: 150));
      await settle(tester);
      expect(keychain.peek('failed_pin_attempts'), '1');
      expect(find.text('5 attempts remaining'), findsOneWidget);
    });

    testWidgets('a PIN vault opened by biometrics goes straight on',
        (tester) async {
      laptopBrowser();
      final auth = _PassingBiometrics();
      final container = await pump(tester, '/open_pin',
          localAuth: auth, settings: biometricSettings);
      await letUnlockRun(tester);
      expect(auth.prompts, 1);
      expect(find.text('Create a password'), findsNothing);
      expect(find.textContaining('route:home'), findsOneWidget);
      expect(container.read(sessionAuthProvider)?.method,
          UnlockMethod.biometric);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 7));
    });

    testWidgets('the lock overlay: the PIN pad, typed from the keyboard',
        (tester) async {
      laptopBrowser();
      keychain.seed('pin', '111111');
      await pump(tester, '/', lock: true);
      expect(find.byType(CustomKeypad), findsOneWidget);
      expect(find.byType(KutePasswordField), findsNothing);
      await typeDigits(tester, '123');
      expect(dots(tester), 3);
      await key(tester, LogicalKeyboardKey.backspace);
      expect(dots(tester), 2);
      await key(tester, LogicalKeyboardKey.backspace);
      await key(tester, LogicalKeyboardKey.backspace);
      // A wrong PIN typed in full is checked and counted.
      await typeDigits(tester, '222222');
      await tester.pump(const Duration(milliseconds: 150));
      await settle(tester);
      expect(keychain.peek('failed_pin_attempts'), '1');
      expect(dots(tester), 0);
    });

    testWidgets('native: the keyboard types nothing on the pad (the phones '
        'as they were)', (tester) async {
      // No web flag: a hardware keyboard on an iPad stays as today.
      await pump(tester, '/set_pin', size: const Size(430, 932));
      await typeDigits(tester, '123');
      expect(dots(tester), 0);
    });
  });

  group('a vault made with a password, in a laptop browser', () {
    testWidgets('unlock: Welcome Back, a wrong password counts like a PIN',
        (tester) async {
      laptop();
      keychain.seed('pin', '111111');
      await pump(tester, '/open_pin');
      expect(find.text('Welcome Back'), findsOneWidget);
      expect(find.byType(CustomKeypad), findsNothing);
      expect(find.text('Forgot your password?'), findsOneWidget);
      expect(editable(tester).autofillHints, [AutofillHints.password]);
      await typeAndEnter(tester, testPassword);
      await settle(tester);
      expect(keychain.peek('failed_pin_attempts'), '1');
      expect(find.text('5 attempts remaining'), findsOneWidget);
      expect(editable(tester).controller.text, isEmpty);
    });

    /// The page's primary: one, right under the password field (its rule
    /// line included) and exactly as wide.
    void expectButtonUnderField(WidgetTester tester, {Finder? within}) {
      final primary = within == null
          ? find.byType(KuteBarPrimaryButton)
          : find.descendant(
              of: within, matching: find.byType(KuteBarPrimaryButton));
      expect(primary, findsOneWidget);
      final field = tester.getRect(find.byType(KutePasswordField));
      final button = tester.getRect(primary);
      final gap = button.top - field.bottom;
      expect(gap, inInclusiveRange(18, 26), reason: 'gap $gap');
      expect(button.width, moreOrLessEquals(field.width, epsilon: 1));
      expect(button.center.dx, moreOrLessEquals(field.center.dx, epsilon: 1));
    }

    KuteBarContext drawn(WidgetTester tester) => tester
        .widget<KuteBarPrimaryButton>(find.byType(KuteBarPrimaryButton))
        .barContext;

    testWidgets('unlock: Unlock under the field, Forgot under the button; '
        'a tap checks it as Enter does', (tester) async {
      laptop();
      keychain.seed('pin', '111111');
      await pump(tester, '/open_pin');
      expectButtonUnderField(tester);
      expect(drawn(tester).enabled, isFalse);
      final button = tester.getRect(find.byType(KuteBarPrimaryButton));
      final forgot = tester.getRect(find.text('Forgot your password?'));
      expect(forgot.top, greaterThan(button.bottom));
      expect(forgot.top - button.bottom, lessThan(40));
      await tester.enterText(find.byType(TextField), 'x');
      await settle(tester);
      expect(drawn(tester).enabled, isTrue);
      expect(drawn(tester).label, 'Unlock');
      await tester.enterText(find.byType(TextField), testPassword);
      await settle(tester);
      await tester.tap(find.byType(KuteBarPrimaryButton));
      await settle(tester);
      expect(keychain.peek('failed_pin_attempts'), '1');
    });

    testWidgets('a password vault opened by biometrics goes straight on',
        (tester) async {
      laptop();
      final auth = _PassingBiometrics();
      final container = await pump(tester, '/open_pin',
          localAuth: auth, settings: biometricSettings);
      await letUnlockRun(tester);
      expect(auth.prompts, 1);
      expect(find.textContaining('route:home'), findsOneWidget);
      expect(container.read(sessionAuthProvider)?.method,
          UnlockMethod.biometric);
      // The deferred post-unlock work (3 s and 6 s) runs out.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 7));
    });

    testWidgets('the lock overlay asks for the password', (tester) async {
      laptop();
      await pump(tester, '/', lock: true);
      expect(find.text('Welcome Back'), findsOneWidget);
      expect(find.byType(KutePasswordField), findsOneWidget);
      expect(find.byType(CustomKeypad), findsNothing);
      // (The floating bar under the overlay is covered by it.)
      expectButtonUnderField(tester, within: find.byType(LockOverlay));
    });

    testWidgets('the gate sheet: a Confirm button under its field, Cancel '
        'kept on the bar', (tester) async {
      laptop();
      keychain.seed('pin', '111111');
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var verified = false;
      var cancelled = false;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          settingsProvider.overrideWith((ref) => SettingsModel(_settings())),
        ],
        child: ScreenUtilInit(
          designSize: KuteLayout.designSizeFor(const Size(1440, 900)),
          builder: (_, __) => MaterialApp(
            builder: withKuteShellBar,
            theme: ThemeData(extensions: [AppColorsExtension.light()]),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => PinGateSheet.show(context,
                      title: 'Gate',
                      onVerified: () => verified = true,
                      onCancelled: () => cancelled = true),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await settle(tester);
      final confirm = find.byKey(const ValueKey('pin-gate-confirm'));
      expect(confirm, findsOneWidget);
      expect(find.text('Confirm'), findsOneWidget);
      expect(tester.widget<AppButton>(confirm).onPressed, isNull);
      final field = tester.getRect(find.byType(KutePasswordField));
      final button = tester.getRect(confirm);
      expect(button.top - field.bottom, inInclusiveRange(18, 26));
      expect(button.width, moreOrLessEquals(field.width, epsilon: 1));
      expect(kuteBarPrimaryWithText('Cancel'), findsOneWidget);

      await tester.enterText(find.byType(TextField), testPassword);
      await settle(tester);
      expect(tester.widget<AppButton>(confirm).onPressed, isNotNull);
      await tester.tap(confirm);
      await settle(tester);
      // Checked as Enter checks it: a wrong password counts.
      expect(keychain.peek('failed_pin_attempts'), '1');
      expect(verified, isFalse);
      expect(cancelled, isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('touch-first browser and native keep the PIN pad', () {
    for (final (label, size) in [
      ('phone-sized web', const Size(430, 932)),
      ('iPad landscape web', const Size(1180, 820)),
      ('native', const Size(430, 932)),
    ]) {
      testWidgets('$label: create, confirm and unlock show the pad',
          (tester) async {
        for (final route in ['/set_pin', '/confirm_pin', '/open_pin']) {
          await pump(tester, route, size: size);
          expect(find.byType(CustomKeypad), findsOneWidget, reason: route);
          expect(find.byType(KutePasswordField), findsNothing, reason: route);
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 3));
        }
      });
    }
  });
}
