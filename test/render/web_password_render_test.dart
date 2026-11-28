// A web vault made with a password (24 to 27 November 2026,
// unlock_secret.dart) shot in the split screen: unlock, the lock overlay
// and the gate sheet, light and dark; the PIN pad every new vault takes
// in a laptop browser (create, confirm, unlock); and the phone's PIN page
// to show it unchanged. Shot when asked: DESK_FULL_RENDER=<dir>.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/platform/kute_layout.dart';
import 'package:kute/platform/kute_wide_frames.dart';
import 'package:kute/platform/unlock_secret.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/creation/confirm_pin.dart';
import 'package:kute/screens/creation/set_pin.dart';
import 'package:kute/screens/home/components/kute_shell_bar.dart';
import 'package:kute/screens/login/open_pin.dart';
import 'package:kute/screens/shared/lock_overlay.dart';
import 'package:kute/screens/shared/pin_gate_sheet.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/services/secure/storage_bootstrap.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:local_auth/local_auth.dart';

import '../services/support/fake_secret_store.dart';
import 'desk_full_support.dart';

class _NoBiometrics extends LocalAuthentication {
  @override
  Future<bool> isDeviceSupported() async => false;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async => const [];

  @override
  Future<bool> get canCheckBiometrics async => false;
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

List<Override> _signedIn() => [
      settingsProvider.overrideWith((ref) => SettingsModel(_settings())),
      storageBootStateProvider.overrideWith((ref) => StorageBootState.ok),
    ];

Future<void> _pumpLock(WidgetTester tester,
    {required Size size, required bool dark}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(initialLocation: '/', routes: [
    GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(body: SizedBox.expand())),
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

/// Each shot of a password vault: its page, and what to type first.
final Map<String, (Widget Function(), List<Override> Function(), String?)>
    _shots = {
  'unlock': (() => OpenPin(localAuth: _NoBiometrics()), _signedIn, null),
  'unlock_typed': (
    () => OpenPin(localAuth: _NoBiometrics()),
    _signedIn,
    'kute test pass 42'
  ),
};

/// The PIN pad a new vault takes in a laptop browser.
final Map<String, (Widget Function(), List<Override> Function())> _pinShots = {
  'pin_create': (() => const SetPin(), () => const []),
  'pin_confirm': (
    () => const ConfirmPin(),
    () => [pinProvider.overrideWith((ref) => '123456')]
  ),
  'pin_unlock': (() => OpenPin(localAuth: _NoBiometrics()), _signedIn),
};

/// A page that opens the step-up gate over itself.
class _GateHost extends StatefulWidget {
  const _GateHost();

  @override
  State<_GateHost> createState() => _GateHostState();
}

class _GateHostState extends State<_GateHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      PinGateSheet.show(context,
          title: 'Confirm a \$5.00 prediction', onVerified: () {});
    });
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: SizedBox.expand());
}

late Directory _hive;

void main() {
  setUpAll(() async {
    _hive = await Directory.systemTemp.createTemp('web_password_render');
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
  });
  tearDown(() {
    SecretStores.debugReset();
    UnlockSecret.debugVaultKind = null;
  });

  Future<void> end(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await deskFullEnd(tester);
  }

  for (final (label, size) in const [
    ('1440x900', Size(1440, 900)),
    ('1000x700', Size(1000, 700)),
  ]) {
    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';
      for (final entry in _shots.entries) {
        testWidgets('password ${entry.key} $label $mode', (tester) async {
          UnlockSecret.debugVaultKind = VaultSecretKind.password;
          await deskFullAssets(tester);
          final (page, overrides, typed) = entry.value;
          await pumpDeskPage(tester,
              size: size,
              dark: dark,
              page: page(),
              mode: KuteWideMode.split,
              overrides: overrides());
          if (typed != null) {
            await tester.enterText(find.byType(TextField), typed);
            await deskFullFrames(tester, 4);
          }
          expect(tester.takeException(), isNull);
          expectDeskNothingStretched(tester);
          await deskFullShoot(tester, '${entry.key}_${label}_$mode');
          await end(tester);
        });
      }
      for (final entry in _pinShots.entries) {
        testWidgets('${entry.key} $label $mode', (tester) async {
          await deskFullAssets(tester);
          final (page, overrides) = entry.value;
          await pumpDeskPage(tester,
              size: size,
              dark: dark,
              page: page(),
              mode: KuteWideMode.split,
              overrides: overrides());
          expect(tester.takeException(), isNull);
          expectDeskNothingStretched(tester);
          await deskFullShoot(tester, '${entry.key}_${label}_$mode');
          await end(tester);
        });
      }
      testWidgets('password lock $label $mode', (tester) async {
        UnlockSecret.debugVaultKind = VaultSecretKind.password;
        await deskFullAssets(tester);
        await _pumpLock(tester, size: size, dark: dark);
        expect(tester.takeException(), isNull);
        await deskFullShoot(tester, 'lock_${label}_$mode');
        await end(tester);
      });
      testWidgets('password gate sheet $label $mode', (tester) async {
        UnlockSecret.debugVaultKind = VaultSecretKind.password;
        await deskFullAssets(tester);
        await pumpDeskPage(tester,
            size: size,
            dark: dark,
            page: const _GateHost(),
            mode: KuteWideMode.full,
            overrides: _signedIn());
        await tester.enterText(find.byType(TextField), 'kute test pass 42');
        await deskFullFrames(tester, 4);
        expect(tester.takeException(), isNull);
        await deskFullShoot(tester, 'gate_${label}_$mode');
        await end(tester);
      });
    }
  }

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    for (final (name, page, overrides) in [
      ('phone_create_pin', () => const SetPin(), () => const <Override>[]),
      ('phone_unlock_pin', () => OpenPin(localAuth: _NoBiometrics()),
          _signedIn),
    ]) {
      testWidgets('$name 430x932 $mode', (tester) async {
        // A touch-first browser: the PIN pad as it was.
        await deskFullAssets(tester);
        await pumpDeskPage(tester,
            size: const Size(430, 932),
            dark: dark,
            page: page(),
            mode: KuteWideMode.split,
            overrides: overrides());
        expect(tester.takeException(), isNull);
        await deskFullShoot(tester, '${name}_430x932_$mode');
        await end(tester);
      });
    }
  }
}
