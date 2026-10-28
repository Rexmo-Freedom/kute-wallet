// Mirror of the TestFlight 2.1.2 (80) report on an iPhone 15 Pro: a wallet
// created on a 1.x build keeps its seed as the PIN-encrypted `mnemonic_{id}`
// under the legacy Keychain accessibility, with `pin_hash` and
// `biometric_pin` beside it. flutter_secure_storage 10 filters reads by
// accessibility, so the current store sees none of them. The cold-start
// lookup re-saves the PIN material so the PIN screen opens; the verified
// PIN, typed or the stored `biometric_pin` after Face ID, must then re-save
// the seed in place before the app unlocks, so the Breez provider reads it
// (no "needs to be restored" banner) and Settings shows the words. The
// `biometric_pin` is kept while the wallet is not known to be PIN-free.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/helpers/session_auth.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/services/auth/pin_encryption.dart';
import 'package:kute/services/auth/pin_hash.dart';
import 'package:kute/services/secure/biometric_pin_policy.dart';
import 'package:kute/services/secure/keychain_local.dart';
import 'package:kute/services/secure/legacy_keychain_rescue.dart';
import 'package:kute/services/secure/secret_store.dart';
import 'package:kute/services/secure/storage_bootstrap.dart';
import 'package:kute/services/tracking_service.dart';

import '../support/fake_legacy_keychain_lookup.dart';
import '../support/fake_secret_store.dart';

const phrase =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const pin = '123456';
const v2 = 'v2:wallet:w1.mnemonic';
const v1 = 'mnemonic_w1';
const unlocked = SeedSession(unlocked: true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeKeychain keychain;
  late FakeLegacyKeychainLookup lookup;
  late List<(String, Map<String, Object>?)> events;
  late String encrypted;
  final wallets = [WalletConfig(id: 'w1', name: 'Spending', sparkEnabled: true)];

  setUpAll(() {
    encrypted = PinEncryptionHelper.encryptData(phrase, pin);
  });

  setUp(() {
    keychain = FakeKeychain();
    lookup = FakeLegacyKeychainLookup(keychain);
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });

  tearDown(() => TrackingService.debugTrackObserver = null);

  LegacyKeychainRescue rescue({bool isCupertino = true}) =>
      LegacyKeychainRescue(
        lookup: lookup,
        store: keychain.local,
        syncedStore: keychain.synced,
        validate: (m) async => m == phrase,
        deriveAddress: (m, _) async => '0xAAAA',
        isCupertino: isCupertino,
      );

  AuthModel auth({bool isCupertino = true}) => AuthModel(
        store: keychain.local,
        syncedStore: keychain.synced,
        rescue: rescue(isCupertino: isCupertino),
        legacyLookup: isCupertino
            ? lookup
            : const NativeLegacyKeychainLookup(platform: TargetPlatform.android),
        wallets: () async => wallets,
      );

  BiometricPinPolicy policy({bool isCupertino = true}) => BiometricPinPolicy(
        store: keychain.local,
        syncedStore: keychain.synced,
        lookup: isCupertino
            ? lookup
            : const NativeLegacyKeychainLookup(platform: TargetPlatform.android),
      );

  void seedLegacy(String key, String value) =>
      keychain.seed(key, value, options: legacyAccessibility);

  /// The phone as it was before the first 2.1.2 start.
  void seedPhone({bool biometricPin = true}) {
    seedLegacy(v1, encrypted);
    seedLegacy('pin_hash', PinHashHelper.hashPin(pin));
    if (biometricPin) seedLegacy('biometric_pin', pin);
  }

  Iterable<String> eventNames() => events.map((e) => e.$1);
  List<Map<String, Object>?> paramsOf(String event) =>
      events.where((e) => e.$1 == event).map((e) => e.$2).toList();
  Iterable<String> deletes() =>
      keychain.mutations.where((m) => m.op.startsWith('delete')).map((m) => m.key);

  /// The splash on a `secretsMissing` classification.
  Future<void> coldStart() async {
    expect(await rescue().rescueAtStartup(wallets),
        StartupRescueOutcome.pinScreen);
    expect(paramsOf('seed_rescue_lookup_completed').single, {
      'source': 'startup',
      'outcome': 'found',
      'plain_count': 0,
      'encrypted_count': 1,
      'icloud_count': 0,
    });
    expect(await keychain.local.read(key: 'pin_hash'), isA<SecretPresent>());
    expect(await keychain.local.read(key: v2), isA<SecretAbsent>());
    expect(await keychain.local.read(key: v1), isA<SecretAbsent>());
    expect(eventNames(), isNot(contains('seed_rescue_restored')));
  }

  /// What the home banner and the recovery phrase screen read.
  Future<void> expectSeedReadable(AuthModel auth, SeedSession session) async {
    expect(await auth.requireMnemonic('w1', session: session), phrase,
        reason: 'breezSDKProvider reads the seed; no banner');
    final interactive =
        await auth.readMnemonic('w1', access: SeedAccess.interactive);
    expect((interactive as SeedOk).value, phrase,
        reason: 'Settings > Recovery phrase shows the words');
  }

  group('iPhone 15 Pro, 1.x wallet, 2.1.2 cold start', () {
    test('(a) Face ID: the stored PIN restores the seed, biometric_pin stays',
        () async {
      seedPhone();
      await coldStart();

      // The PIN screen evaluates the dependency before prompting Face ID.
      final dependency = await policy().evaluate(wallets);
      expect(dependency.exists, isTrue,
          reason: 'the legacy mnemonic_w1 is listed, not read');
      expect(dependency.biometricPin, StoredPinState.present);
      expect(dependency.pinFree, isFalse);

      final a = auth();
      final verdict = await checkBiometricUnlock(a, dependency);
      expect((verdict as BiometricUnlockAllowed).storedPin, pin);

      // The seed was re-saved in place before the app unlocked.
      expect(keychain.peek(v2), phrase);
      expect(keychain.peek(v1), encrypted);
      expect((await keychain.local.read(key: v2)).valueOrThrow(), phrase);
      expect(paramsOf('seed_rescue_restored').single,
          {'source': 'biometric', 'era': 'a', 'check': 'none'});
      expect(paramsOf('seed_rescue_lookup_completed').last!['source'],
          'biometric');

      await policy().applyAfterUnlock(dependency);
      expect(keychain.peek('biometric_pin'), pin);
      expect(eventNames(), isNot(contains('biometric_pin_removed')));
      expect(deletes(), isEmpty);
      expect(eventNames(), isNot(contains('seed_rescue_failed')));

      // Biometric unlock holds no typed PIN; the V2 copy needs none.
      await expectSeedReadable(a, unlocked);

      // The next cold start: the wallet is PIN-free, Face ID alone unlocks.
      final next = await policy().evaluate(wallets);
      expect(next.exists, isFalse);
      expect(next.pinFree, isTrue);
      expect((await checkBiometricUnlock(auth(), next)).runtimeType,
          BiometricUnlockAllowed);
    });

    test('(b) typed PIN: same restore, biometric_pin kept and refreshed',
        () async {
      seedPhone();
      await coldStart();

      final dependency = await policy().evaluate(wallets);
      final a = auth();
      expect(await a.checkPin(pin), PinCheck.match);
      expect(keychain.peek(v2), phrase);
      expect(paramsOf('seed_rescue_restored').single,
          {'source': 'pin', 'era': 'a', 'check': 'none'});

      await policy().applyAfterUnlock(dependency, typedPin: pin);
      expect(keychain.peek('biometric_pin'), pin);
      expect(deletes(), isEmpty);
      await expectSeedReadable(a, const SeedSession(unlocked: true, typedPin: pin));
    });

    test('(b2) the phone after the broken build removed biometric_pin',
        () async {
      // 2.1.2 (80) re-saved pin_hash, then deleted biometric_pin because
      // the policy read the seed through the filtered store.
      seedLegacy(v1, encrypted);
      keychain.seed('pin_hash', PinHashHelper.hashPin(pin));

      final dependency = await policy().evaluate(wallets);
      expect(dependency.exists, isTrue);
      expect(dependency.biometricPin, StoredPinState.absent,
          reason: 'no Face ID prompt: the PIN is typed');

      expect(await auth().checkPin(pin), PinCheck.match);
      expect(keychain.peek(v2), phrase);
      await policy().applyAfterUnlock(dependency, typedPin: pin);
      expect(keychain.peek('biometric_pin'), pin,
          reason: 'the typed PIN stores the copy again');
      await expectSeedReadable(auth(), unlocked);
    });

    test('(c) a restart after the PIN material was re-saved still restores',
        () async {
      final hiveDir = await Directory.systemTemp.createTemp('seed_pin_hook');
      Hive.init(hiveDir.path);
      addTearDown(() async {
        await Hive.close();
        await hiveDir.delete(recursive: true);
      });
      StorageBootstrap.debugResetProcess();
      // After the first 2.1.2 start: pin_hash and biometric_pin readable,
      // the seed still only under the legacy accessibility.
      seedLegacy(v1, encrypted);
      keychain.seed('pin_hash', PinHashHelper.hashPin(pin));
      keychain.seed('biometric_pin', pin);

      final boot = await StorageBootstrap(
        store: keychain.local,
        settingsBox: () => Hive.openBox('settings'),
        isCupertino: true,
        isProtectedDataAvailable: () async => true,
        protectedDataChanges: () => null,
      ).classify(hasWallets: true);
      expect(boot.state, StorageBootState.preBinding,
          reason: 'not secretsMissing: the splash runs no startup rescue');
      expect(keychain.peek(v2), isNull);

      final dependency = await policy().evaluate(wallets);
      expect(dependency.exists, isTrue);
      final a = auth();
      final verdict = await checkBiometricUnlock(a, dependency);
      expect((verdict as BiometricUnlockAllowed).storedPin, pin);
      expect(keychain.peek(v2), phrase);
      expect(paramsOf('seed_rescue_restored').single,
          {'source': 'biometric', 'era': 'a', 'check': 'none'});
      await policy().applyAfterUnlock(dependency);
      expect(keychain.peek('biometric_pin'), pin);
      await expectSeedReadable(a, unlocked);
    });

    test('(d) the policy keeps biometric_pin while the seed is unreadable',
        () async {
      // A legacy copy the store cannot read.
      seedPhone();
      await coldStart();
      var dependency = await policy().evaluate(wallets);
      expect(dependency.exists, isTrue);
      await policy().applyAfterUnlock(dependency);
      expect(keychain.peek('biometric_pin'), pin);

      // Plain absence: unknown, not PIN-free.
      keychain = FakeKeychain()..seed('biometric_pin', pin);
      lookup = FakeLegacyKeychainLookup(keychain);
      dependency = await policy().evaluate(wallets);
      expect(dependency.exists, isFalse);
      expect(dependency.pinFree, isFalse);
      await policy().applyAfterUnlock(dependency);
      expect(keychain.peek('biometric_pin'), pin);
      expect(eventNames(), isNot(contains('biometric_pin_removed')));

      // A failing Keychain listing keeps it too.
      lookup.failure = PlatformException(code: 'x', details: -25308);
      dependency = await policy().evaluate(wallets);
      await policy().applyAfterUnlock(dependency);
      expect(keychain.peek('biometric_pin'), pin);
      expect(keychain.mutations, isEmpty);
    });

    test('(e) a wrong PIN restores nothing and deletes nothing', () async {
      seedPhone();
      await coldStart();
      final mutationsAfterStart = keychain.mutations.length;

      expect(await auth().checkPin('000000'), PinCheck.mismatch);
      expect(keychain.mutations, hasLength(mutationsAfterStart));
      expect(eventNames(), isNot(contains('seed_rescue_failed')));
      expect(keychain.peek(v1), encrypted);

      // The verified PIN does not open a blob encrypted under another one:
      // reported, left in place, nothing deleted.
      keychain.seed(v1, PinEncryptionHelper.encryptData(phrase, '999999'),
          options: legacyAccessibility);
      expect(await auth().checkPin(pin), PinCheck.match);
      expect(paramsOf('seed_rescue_failed').single,
          {'source': 'pin', 'era': 'a', 'reason': 'wrongPin'});
      expect(keychain.peek(v2), isNull);
      expect(deletes(), isEmpty);
      expect(keychain.peek('biometric_pin'), pin);
    });

    test('(f) Android: no lookup, no rescue, unchanged reads', () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final nativeCalls = <String>[];
      messenger.setMockMethodCallHandler(KeychainLocal.channel, (call) async {
        nativeCalls.add(call.method);
        return null;
      });
      addTearDown(
          () => messenger.setMockMethodCallHandler(KeychainLocal.channel, null));
      keychain = FakeKeychain(platform: FakePlatform.android)
        ..seed(v1, encrypted)
        ..seed('pin_hash', PinHashHelper.hashPin(pin))
        ..seed('biometric_pin', pin);
      lookup = FakeLegacyKeychainLookup(keychain);

      final dependency = await policy(isCupertino: false).evaluate(wallets);
      expect(dependency.exists, isTrue, reason: 'the V1 copy needs the PIN');
      final a = auth(isCupertino: false);
      final verdict = await checkBiometricUnlock(a, dependency);
      expect((verdict as BiometricUnlockAllowed).storedPin, pin);
      await policy(isCupertino: false).applyAfterUnlock(dependency);
      expect(keychain.mutations, isEmpty);
      expect(eventNames().where((e) => e.startsWith('seed_rescue')), isEmpty);
      expect(nativeCalls, isEmpty);
      expect(lookup.reads, isEmpty);

      final read = await a.readMnemonic('w1',
          access: SeedAccess.automatic, session: unlocked);
      expect((read as SeedOk).source, SeedSource.v1);
      expect(read.value, phrase);
      expect(keychain.mutations, isEmpty);
    });
  });
}
