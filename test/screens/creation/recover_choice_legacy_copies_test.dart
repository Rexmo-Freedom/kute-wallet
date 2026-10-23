// The restore picker lists, beside the passkeys discovery found, the
// wallet copies an older build left on this phone under the legacy
// Keychain accessibility. Rows are built from key names and the Hive
// wallet record only; nothing is decrypted to show them.

import 'dart:io';
import 'dart:typed_data';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart' as settings_model;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/creation/recover_choice.dart';
import 'package:kute/services/auth/pin_encryption.dart';
import 'package:kute/services/passkey_prf_service.dart';
import 'package:kute/services/passkey_service.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/services/secure/legacy_keychain_rescue.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../services/support/fake_legacy_keychain_lookup.dart';
import '../../services/support/fake_secret_store.dart';

const phrase =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
final credential = Uint8List.fromList([4, 5, 6]);

/// Discovery (`label == null`) answers with [published]; a labelled
/// confirmation is cancelled.
class _Client implements PasskeyClient {
  _Client(this.published);
  final List<String> published;
  final requests = <SignInRequest>[];

  @override
  Future<SignInResponse> signIn({required SignInRequest request}) async {
    requests.add(request);
    if (request.label != null) throw StateError('user cancelled');
    return SignInResponse(
      wallet: Wallet(
        seed: Seed.mnemonic(mnemonic: phrase, passphrase: null),
        label: 'Default',
      ),
      labels: published,
      credential: PasskeyCredential(credentialId: credential),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeKeychain keychain;
  late FakeLegacyKeychainLookup lookup;
  late Directory hiveDir;
  late List<(String, Map<String, Object>?)> events;

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    keychain = FakeKeychain();
    lookup = FakeLegacyKeychainLookup(keychain);
    SecretStores.debugOverride(local: keychain.local, synced: keychain.synced);
    PasskeyPrfService.clearMemory();
    hiveDir = await Directory.systemTemp.createTemp('recover_choice_legacy');
    Hive.init(hiveDir.path);
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });

  tearDown(() async {
    TrackingService.debugTrackObserver = null;
    PasskeyService.debugSetClient(null);
    PasskeyPrfService.clearMemory();
    SecretStores.debugReset();
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  LegacyKeychainRescue rescue() => LegacyKeychainRescue(
        lookup: lookup,
        store: keychain.local,
        syncedStore: keychain.synced,
        validate: (m) async => m == phrase,
        deriveAddress: (m, _) async => '0xAAAA',
        // Synchronous: `compute` never completes under the test clock.
        decrypt: (blob, pin) async => PinEncryptionHelper.decryptData(blob, pin),
        isCupertino: true,
      );

  Future<void> pumpScreen(WidgetTester tester,
      {List<settings_model.WalletConfig> wallets = const []}) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = settings_model.Settings(
      wallets: wallets,
      activeWalletId: wallets.firstOrNull?.id,
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: true,
      biometricsEnabled: false,
      bitcoinElectrumNode: 'ssl://example.com:50002',
      nodeType: 'electrum',
      reviewDone: true,
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        initialSettingsProvider.overrideWith((ref) async => settings),
        settingsProvider
            .overrideWith((ref) => settings_model.SettingsModel(settings)),
      ],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: ThemeData(
              splashFactory: NoSplash.splashFactory,
              fontFamily: 'Inter',
              extensions: [AppColorsExtension.light()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RecoverChoiceScreen(rescue: rescue()),
        ),
      ),
    ));
    // The screen runs the lookups on its first frame.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 400));
  }

  void seedLegacy(String key, String value) =>
      keychain.seed(key, value, options: legacyAccessibility);

  /// The screen keeps a looping illustration running, so `pumpAndSettle`
  /// never returns; a fixed run of frames stands in for it.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('old copies are listed under their own heading, by key name',
      (tester) async {
    const a = 'Daily · 1700000000000';
    PasskeyService.debugSetClient(_Client([a]));
    seedLegacy('v2:wallet:w1.mnemonic', phrase);
    seedLegacy('mnemonic_w2', PinEncryptionHelper.encryptData(phrase, '123456'));
    keychain.seedSynced('v2:wallet:w3.mnemonic', phrase);
    final w1 = settings_model.WalletConfig(id: 'w1', name: 'Holiday');

    await pumpScreen(tester, wallets: [w1]);

    // One passkey alone would restore straight away; with old copies on
    // the phone the picker opens so they can be chosen instead.
    expect(find.text('Pick a wallet to restore'), findsOneWidget);
    expect(find.text('Daily'), findsOneWidget);
    expect(find.text('From an older version on this phone'), findsOneWidget);
    expect(find.text('Holiday'), findsOneWidget);
    expect(find.text('Wallet from an older version'), findsNWidgets(2));
    expect(find.text('Opens with the PIN that version used'), findsOneWidget);
    expect(find.text('Saved in iCloud Keychain'), findsOneWidget);
    expect(find.byKey(const ValueKey('legacy-copy-w1')), findsOneWidget);
    expect(find.byKey(const ValueKey('legacy-copy-w2')), findsOneWidget);
    expect(find.byKey(const ValueKey('legacy-copy-w3')), findsOneWidget);
    // Listing reads key names only: no phrase or blob was fetched.
    expect(lookup.reads, isNot(contains('v2:wallet:w1.mnemonic')));
    expect(lookup.reads, isNot(contains('mnemonic_w2')));
    expect(keychain.mutations, isEmpty);
    expect(
        events.where((e) => e.$1 == 'seed_rescue_lookup_completed').single.$2,
        {
          'source': 'sheet',
          'outcome': 'found',
          'plain_count': 1,
          'encrypted_count': 1,
          'icloud_count': 1,
        });
    for (final (_, params) in events) {
      for (final value in (params ?? const {}).values) {
        expect('$value', isNot(contains('w1')));
        expect('$value', isNot(contains('Holiday')));
      }
    }
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('no passkey and nothing old: the picker does not open',
      (tester) async {
    PasskeyService.debugSetClient(_Client(const []));
    await pumpScreen(tester);
    expect(find.text('From an older version on this phone'), findsNothing);
    expect(find.text('Pick a wallet to restore'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('an encrypted copy asks for the PIN that version used',
      (tester) async {
    PasskeyService.debugSetClient(_Client(const []));
    seedLegacy('mnemonic_w2', PinEncryptionHelper.encryptData(phrase, '123456'));
    // A stored biometric_pin is never tried silently on this surface: the
    // PIN is asked even though this copy would open with it.
    keychain.seed('biometric_pin', '123456');

    await pumpScreen(tester);
    expect(find.text('Restore this wallet?'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('legacy-copy-w2')));
    await settle(tester);
    expect(find.text('Enter the PIN that version used'), findsOneWidget);

    // A wrong PIN stays on the sheet and says so. It counts on the shared
    // attempt counter (sheet rules, never a wipe); no seed is touched.
    for (final digit in '000000'.split('')) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 150));
    await settle(tester);
    expect(find.text('Incorrect PIN'), findsOneWidget);
    expect(keychain.mutations,
        [const FakeMutation('local', 'write', 'failed_pin_attempts')]);
    expect(keychain.peek('failed_pin_attempts'), '1');
    expect(events.where((e) => e.$1 == 'pin_gate_failed').single.$2,
        {'surface': 'legacy_copy', 'attempt': 1});

    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(find.text('Enter the PIN that version used'), findsNothing);
    expect(events.where((e) => e.$1 == 'seed_rescue_failed').single.$2,
        {'source': 'sheet', 'era': 'a', 'reason': 'cancelled'});
    await tester.pump(const Duration(seconds: 5));
  });
}
