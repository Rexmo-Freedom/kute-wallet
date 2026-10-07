import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/helpers/session_auth.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/pin_gate_sheet.dart';
import 'package:kute/services/secure/biometric_pin_policy.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/theme/app_theme.dart';

import '../services/support/fake_secret_store.dart';

class _QuickAuth extends AuthModel {
  _QuickAuth(FakeKeychain keychain)
      : super(store: keychain.local, syncedStore: keychain.synced);

  @override
  Future<PinCheck> checkPin(String incomingPin) async =>
      incomingPin == '111111' ? PinCheck.match : PinCheck.mismatch;
}

Settings _settings(List<WalletConfig> wallets) => Settings(
      wallets: wallets,
      activeWalletId: wallets.isEmpty ? null : wallets.first.id,
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: true,
      biometricsEnabled: false,
      bitcoinElectrumNode: 'ssl://example.com:50002',
      nodeType: 'electrum',
      reviewDone: true,
    );

final _session =
    SessionAuth(method: UnlockMethod.pin, unlockedAt: DateTime(2026));
const _needsPin =
    V1Dependency(exists: true, biometricPin: StoredPinState.absent);
const _noNeed =
    V1Dependency(exists: false, biometricPin: StoredPinState.absent);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeKeychain keychain;

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    keychain = FakeKeychain();
    SecretStores.debugOverride(local: keychain.local, synced: keychain.synced);
  });

  tearDown(SecretStores.debugReset);

  group('providers', () {
    test('the session is unlocked only with sessionAuth and no overlay', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(sessionUnlockedProvider), isFalse);
      expect(container.read(seedSessionProvider).unlocked, isFalse);

      container.read(sessionAuthProvider.notifier).state = _session;
      expect(container.read(sessionUnlockedProvider), isTrue);

      container.read(appLockedProvider.notifier).state = true;
      expect(container.read(sessionUnlockedProvider), isFalse);
      expect(container.read(sessionAuthProvider), same(_session),
          reason: 'the overlay keeps the session');

      container.read(appLockedProvider.notifier).state = false;
      container.read(typedPinProvider.notifier).state = '111111';
      final seed = container.read(seedSessionProvider);
      expect(seed.unlocked, isTrue);
      expect(seed.typedPin, '111111');
      expect(seed.toString(), isNot(contains('111111')));
    });

    test('a provider built while locked builds again once unlocked', () async {
      var builds = 0;
      final probe = FutureProvider<bool>((ref) async {
        builds++;
        return watchSessionUnlock(ref);
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.listen(probe, (_, __) {});

      expect(await container.read(probe.future), isFalse);
      container.read(sessionAuthProvider.notifier).state = _session;
      expect(await container.read(probe.future), isTrue);
      expect(builds, 2);

      container.read(appLockedProvider.notifier).state = true;
      await container.read(probe.future);
      expect(builds, 2, reason: 'built unlocked, the overlay does not rebuild');
    });
  });

  group('markSessionUnlocked', () {
    Future<(ProviderContainer, WidgetRef)> pumpRef(WidgetTester tester,
        {List<WalletConfig> wallets = const []}) async {
      final container = ProviderContainer(overrides: [
        settingsProvider
            .overrideWith((ref) => SettingsModel(_settings(wallets))),
      ]);
      addTearDown(container.dispose);
      late WidgetRef captured;
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: Consumer(builder: (context, ref, _) {
          captured = ref;
          return const SizedBox();
        }),
      ));
      return (container, captured);
    }

    testWidgets('drops the typed PIN when no wallet needs it', (tester) async {
      final (container, ref) = await pumpRef(tester);
      container.read(typedPinProvider.notifier).state = '222222';
      markSessionUnlocked(ref,
          method: UnlockMethod.pin, typedPin: '111111', dependency: _noNeed);
      expect(container.read(sessionAuthProvider)?.method, UnlockMethod.pin);
      expect(container.read(typedPinProvider), isNull);
    });

    testWidgets('keeps the typed PIN while a wallet needs it', (tester) async {
      final (container, ref) = await pumpRef(tester);
      markSessionUnlocked(ref,
          method: UnlockMethod.pin, typedPin: '111111', dependency: _needsPin);
      expect(container.read(typedPinProvider), '111111');

      markSessionUnlocked(ref,
          method: UnlockMethod.biometric, dependency: _needsPin);
      expect(
          container.read(sessionAuthProvider)?.method, UnlockMethod.biometric);
      expect(container.read(typedPinProvider), '111111',
          reason: 'biometric unlock keeps the PIN typed earlier');

      markSessionUnlocked(ref,
          method: UnlockMethod.biometric, dependency: _noNeed);
      expect(container.read(typedPinProvider), isNull);
    });

    testWidgets('clearSession ends the session', (tester) async {
      final (container, ref) = await pumpRef(tester);
      markSessionUnlocked(ref,
          method: UnlockMethod.pin, typedPin: '111111', dependency: _needsPin);
      clearSession(ref);
      expect(container.read(sessionAuthProvider), isNull);
      expect(container.read(typedPinProvider), isNull);
    });

    testWidgets('evaluates the wallets in settings', (tester) async {
      keychain.seed('mnemonic_w1', 'cipher');
      final (_, ref) = await pumpRef(tester,
          wallets: [WalletConfig(id: 'w1', name: 'Spending')]);
      final dependency = await evaluateV1Dependency(ref);
      expect(dependency.exists, isTrue);
    });
  });

  group('PIN sheet', () {
    Future<ProviderContainer> pumpSheet(
        WidgetTester tester, List<WalletConfig> wallets) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer(overrides: [
        authModelProvider.overrideWith((ref) => _QuickAuth(keychain)),
        settingsProvider
            .overrideWith((ref) => SettingsModel(_settings(wallets))),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: ScreenUtilInit(
          designSize: const Size(430, 932),
          builder: (_, __) => MaterialApp(
            theme: ThemeData(
                fontFamily: 'Inter', extensions: [AppColorsExtension.light()]),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: PinGateSheet(
                title: 'Confirm',
                onVerified: () {},
                onCancelled: () {},
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      for (final d in '111111'.split('')) {
        await tester.tap(find.text(d));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('holds the typed PIN for a V1-only wallet', (tester) async {
      keychain.seed('mnemonic_w1', 'cipher');
      final container =
          await pumpSheet(tester, [WalletConfig(id: 'w1', name: 'Old')]);
      expect(container.read(sessionAuthProvider)?.method, UnlockMethod.pin);
      expect(container.read(typedPinProvider), '111111');
    });

    testWidgets('drops the typed PIN when every wallet has a V2 copy',
        (tester) async {
      keychain
        ..seed('mnemonic_w1', 'cipher')
        ..seed('v2:wallet:w1.mnemonic', 'words');
      final container =
          await pumpSheet(tester, [WalletConfig(id: 'w1', name: 'New')]);
      expect(container.read(sessionAuthProvider)?.method, UnlockMethod.pin);
      expect(container.read(typedPinProvider), isNull);
    });
  });
}
