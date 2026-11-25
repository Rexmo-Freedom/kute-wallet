// The laptop browser's password lock (unlock_secret.dart) on the pages
// that ask for the PIN: create, confirm, unlock, the lock overlay and the
// one-time upgrade of a PIN vault. A touch-first browser and the native
// apps keep the PIN pad. Every secret here is a test literal.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
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
import 'package:kute/screens/shared/kute_dialog.dart' show KuteInPlaceFoot;
import 'package:kute/screens/shared/kute_password_field.dart';
import 'package:kute/screens/shared/kute_split_screen.dart';
import 'package:kute/screens/shared/lock_overlay.dart';
import 'package:kute/screens/shared/password_upgrade_page.dart';
import 'package:kute/screens/shared/pin_gate_sheet.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/services/secure/storage_bootstrap.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:local_auth/local_auth.dart';

import '../../helpers/kute_bar_test_support.dart';
import '../../services/support/fake_secret_store.dart';

const testPassword = 'correct horse battery';

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
    UnlockSecret.debugDeviceKind = null;
    UnlockSecret.debugVaultKind = null;
  });

  void laptop() {
    UnlockSecret.debugDeviceKind = VaultSecretKind.password;
    UnlockSecret.debugVaultKind = VaultSecretKind.password;
  }

  Future<ProviderContainer> pump(
    WidgetTester tester,
    String initial, {
    Size size = const Size(1440, 900),
    List<Override> overrides = const [],
    bool lock = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith((ref) => SettingsModel(_settings())),
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
          builder: (_, __) => split(OpenPin(localAuth: _NoBiometrics()))),
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
            if (lock) const LockOverlay(),
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

  group('laptop browser', () {
    testWidgets('create: one obscured, autofocused field, the rule, no pad; '
        'Next only at 10 characters', (tester) async {
      laptop();
      final container = await pump(tester, '/set_pin');
      expect(find.text('Create a password'), findsOneWidget);
      expect(find.byType(KutePasswordField), findsOneWidget);
      expect(find.byType(CustomKeypad), findsNothing);
      expect(find.text('At least 10 characters'), findsWidgets);
      final field = editable(tester);
      expect(field.obscureText, isTrue);
      expect(field.autofocus, isTrue);
      expect(field.autofillHints, [AutofillHints.newPassword]);

      await typeAndEnter(tester, '123456789');
      expect(kuteBarPrimaryContext(tester).enabled, isFalse);
      expect(container.read(pinProvider), isEmpty);

      await tester.tap(find.byKey(const ValueKey('kute-password-visibility')));
      await tester.pump();
      expect(editable(tester).obscureText, isFalse);

      await typeAndEnter(tester, testPassword);
      expect(container.read(pinProvider), testPassword);
      await settle(tester);
    });

    testWidgets('confirm: a different password does not match', (tester) async {
      laptop();
      await pump(tester, '/confirm_pin', overrides: [
        pinProvider.overrideWith((ref) => testPassword),
      ]);
      expect(find.text('Confirm your password'), findsOneWidget);
      expect(find.byType(CustomKeypad), findsNothing);
      expect(editable(tester).autofillHints, [AutofillHints.newPassword]);
      await typeAndEnter(tester, 'correct horse batterY');
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text("Passwords don't match"), findsOneWidget);
      expect(editable(tester).controller.text, isEmpty);
    });

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

    testWidgets('a PIN vault: after its PIN, a password must be created '
        'before going on', (tester) async {
      UnlockSecret.debugDeviceKind = VaultSecretKind.password;
      UnlockSecret.debugVaultKind = VaultSecretKind.pin;
      keychain.seed('pin', '111111');
      await pump(tester, '/open_pin');
      // The vault is a PIN vault: the pad, until the PIN opens it.
      expect(find.byType(CustomKeypad), findsOneWidget);
      for (final d in '111111'.split('')) {
        await tester.tap(find.text(d));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 150));
      // The unlock reads Hive (real file I/O): let it run.
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await settle(tester);
      expect(find.byType(PasswordUpgradePage), findsOneWidget);
      expect(find.text('Create a password'), findsOneWidget);
      expect(find.textContaining('route:home'), findsNothing);
      expect(find.byType(CustomKeypad), findsNothing);
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

    testWidgets('create and confirm: the button sits under the field, '
        'on as soon as the rule is met', (tester) async {
      laptop();
      await pump(tester, '/set_pin');
      expectButtonUnderField(tester);
      expect(drawn(tester).enabled, isFalse);
      await tester.enterText(find.byType(TextField), '123456789');
      await settle(tester);
      expect(drawn(tester).enabled, isFalse);
      await tester.enterText(find.byType(TextField), '1234567890');
      await settle(tester);
      expect(drawn(tester).enabled, isTrue);
      expect(drawn(tester).label, 'Next');
      expectButtonUnderField(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));

      await pump(tester, '/confirm_pin', overrides: [
        pinProvider.overrideWith((ref) => testPassword),
      ]);
      expectButtonUnderField(tester);
      await tester.enterText(find.byType(TextField), testPassword);
      await settle(tester);
      expect(drawn(tester).enabled, isTrue);
    });

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

    testWidgets('a phone-sized laptop window keeps the floating bar',
        (tester) async {
      laptop();
      await pump(tester, '/set_pin', size: const Size(430, 932));
      // Not in a split screen: the page's own geometry, the bar draws it.
      expect(find.byType(KuteInPlaceFoot), findsNothing);
      final field = tester.getRect(find.byType(KutePasswordField));
      final button = tester.getRect(find.byType(KuteBarPrimaryButton));
      expect(button.top - field.bottom, greaterThan(200));
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

  testWidgets('upgrade page: create, confirm, then the host goes on',
      (tester) async {
    var done = false;
    String? saved;
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      child: ScreenUtilInit(
        designSize: KuteLayout.designSizeFor(const Size(1440, 900)),
        builder: (_, __) => MaterialApp(
          theme: ThemeData(extensions: [AppColorsExtension.light()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: KuteSplitScreen(
            child: PasswordUpgradePage(
              onUpgraded: () => done = true,
              upgrade: (p) async => saved = p,
            ),
          ),
        ),
      ),
    ));
    await settle(tester);
    await typeAndEnter(tester, testPassword);
    await settle(tester);
    expect(find.text('Confirm your password'), findsOneWidget);
    await typeAndEnter(tester, 'something else entirely');
    await settle(tester);
    expect(find.text("Passwords don't match"), findsOneWidget);
    expect(find.text('Create a password'), findsOneWidget);
    await typeAndEnter(tester, testPassword);
    await settle(tester);
    await typeAndEnter(tester, testPassword);
    await settle(tester);
    expect(saved, testPassword);
    expect(done, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });

  group('touch-first browser and native keep the PIN pad', () {
    for (final (label, size, kind) in [
      ('phone-sized web', const Size(430, 932), VaultSecretKind.pin),
      ('iPad landscape web', const Size(1180, 820), VaultSecretKind.pin),
      ('native', const Size(430, 932), null),
    ]) {
      testWidgets('$label: create, confirm and unlock show the pad',
          (tester) async {
        UnlockSecret.debugDeviceKind = kind;
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
