// Start over on the Restore wallets screen never wipes over copies an
// older build left under the legacy Keychain accessibility: the lookup runs
// first and offers them instead.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/recovery/restore_secrets_screen.dart';
import 'package:kute/services/auth/pin_encryption.dart';
import 'package:kute/services/auth/pin_hash.dart';
import 'package:kute/services/onchain/native_onchain_service.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/services/secure/legacy_keychain_rescue.dart';
import 'package:kute/services/secure/secret_store.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../services/support/fake_legacy_keychain_lookup.dart';
import '../../services/support/fake_secret_store.dart';

const phraseA =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const pin = '123456';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late FakeKeychain keychain;
  late FakeLegacyKeychainLookup lookup;
  late AuthModel auth;
  late int wipes;
  late List<(String, Map<String, Object>?)> events;

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    keychain = FakeKeychain();
    lookup = FakeLegacyKeychainLookup(keychain);
    auth = AuthModel(store: keychain.local, syncedStore: keychain.synced);
    wipes = 0;
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    SecretStores.debugOverride(local: keychain.local, synced: keychain.synced);
    messenger.setMockMethodCallHandler(NativeOnchainService.channel,
        (call) async {
      final args = call.arguments as Map;
      if (args['action'] == 'validate') return args['mnemonic'] == phraseA;
      throw PlatformException(code: 'unexpected');
    });
  });

  tearDown(() {
    TrackingService.debugTrackObserver = null;
    SecretStores.debugReset();
    messenger.setMockMethodCallHandler(NativeOnchainService.channel, null);
  });

  LegacyKeychainRescue rescue() => LegacyKeychainRescue(
        lookup: lookup,
        store: keychain.local,
        syncedStore: keychain.synced,
        validate: (m) async => m == phraseA,
        deriveAddress: (m, _) async => '0xAAAA',
        // Synchronous: `compute` never completes under the test clock.
        decrypt: (blob, pin) async => PinEncryptionHelper.decryptData(blob, pin),
        isCupertino: true,
      );

  final w1 = WalletConfig(id: 'w1', name: 'Spending');

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith((ref) => SettingsModel(Settings(
            wallets: [w1],
            activeWalletId: 'w1',
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: true,
            biometricsEnabled: false,
            bitcoinElectrumNode: 'ssl://example.com:50002',
            nodeType: 'electrum',
            reviewDone: true,
          ))),
      authModelProvider.overrideWith((ref) => auth),
    ]);
    addTearDown(container.dispose);
    final router = GoRouter(initialLocation: '/restore', routes: [
      GoRoute(
        path: '/restore',
        builder: (_, __) => RestoreSecretsScreen(
          reason: RestoreSecretsReason.secretsMissing,
          deriveAddress: (_) async => '0xAAAA',
          checkBalance: (_) async => 0,
          offerLegacyCopies: true,
          wipe: () async => wipes++,
          rescue: rescue(),
        ),
      ),
      for (final name in ['set_pin', 'open_pin', 'home'])
        GoRoute(
            path: '/$name',
            builder: (_, __) => Scaffold(body: Text('route:$name'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
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
    ));
    await tester.pumpAndSettle();
  }

  Future<void> typeStartFresh(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('restore-start-fresh')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('restore-start-fresh-field')), 'DELETE');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('restore-start-fresh-confirm')));
    await tester.pumpAndSettle();
  }

  void seedLegacy(String key, String value) =>
      keychain.seed(key, value, options: legacyAccessibility);

  testWidgets('nothing old on the phone: Start over wipes as before',
      (tester) async {
    await pumpScreen(tester);
    await typeStartFresh(tester);
    expect(wipes, 1);
    expect(find.text('Use the saved copies'), findsNothing);
    expect(
        events.where((e) => e.$1 == 'seed_rescue_lookup_completed').single.$2,
        containsPair('source', 'start_over'));
    expect(events.map((e) => e.$1), contains('seed_restore_start_fresh'));
  });

  testWidgets('old copies found: the rescue is offered, nothing is wiped',
      (tester) async {
    seedLegacy('v2:wallet:w1.mnemonic', phraseA);
    seedLegacy('pin_hash', PinHashHelper.hashPin(pin));
    await pumpScreen(tester);
    expect(find.text('Needs recovery'), findsOneWidget);

    await typeStartFresh(tester);
    expect(wipes, 0);
    expect(find.text('Use the saved copies'), findsOneWidget);
    expect(keychain.mutations, isEmpty);

    // Declining leaves everything exactly as it was.
    await tester.tap(find.byKey(const ValueKey('restore-choice-cancel')));
    await tester.pumpAndSettle();
    expect(wipes, 0);
    expect(keychain.mutations, isEmpty);
    expect(events.map((e) => e.$1),
        isNot(contains('seed_restore_start_fresh')));

    // Accepting re-saves the copies in place and the row reads restored.
    await typeStartFresh(tester);
    await tester.tap(find.byKey(const ValueKey('restore-choice-confirm')));
    await tester.pumpAndSettle();
    expect(wipes, 0);
    expect(keychain.mutations.map((m) => m.op).toSet(), {'writeLocalOnly'});
    expect((await keychain.local.read(key: 'v2:wallet:w1.mnemonic'))
        .valueOrThrow(), phraseA);
    expect(await keychain.local.read(key: 'pin_hash'), isA<SecretPresent>());
    expect(find.text('Restored'), findsOneWidget);

    // Done goes to the PIN screen now that PIN material is readable.
    await tester.tap(find.byKey(const ValueKey('restore-done')));
    await tester.pumpAndSettle();
    expect(find.text('route:open_pin'), findsOneWidget);
  });

  testWidgets('an encrypted-only copy reads restored once its PIN can finish it',
      (tester) async {
    seedLegacy('mnemonic_w1', PinEncryptionHelper.encryptData(phraseA, pin));
    seedLegacy('pin_hash', PinHashHelper.hashPin(pin));
    await pumpScreen(tester);

    await typeStartFresh(tester);
    await tester.tap(find.byKey(const ValueKey('restore-choice-confirm')));
    await tester.pumpAndSettle();

    expect(wipes, 0);
    expect(find.text('Restored'), findsOneWidget);
    expect(await keychain.local.read(key: 'v2:wallet:w1.mnemonic'),
        isA<SecretAbsent>());
    // The PIN entry that follows finishes the rescue through the same
    // verified-PIN hook every unlock runs. (PBKDF2 runs on an isolate,
    // which needs the real event loop.)
    final auth = AuthModel(
        store: keychain.local,
        syncedStore: keychain.synced,
        rescue: rescue(),
        wallets: () async => [w1]);
    final check = await tester.runAsync(() => auth.checkPin(pin));
    expect(check, PinCheck.match);
    expect((await keychain.local.read(key: 'v2:wallet:w1.mnemonic'))
        .valueOrThrow(), phraseA);
    expect(keychain.mutations.map((m) => m.op).toSet(), {'writeLocalOnly'});
  });
}
