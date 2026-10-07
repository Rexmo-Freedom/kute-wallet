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

import '../support/fake_secret_store.dart';
import '../support/recording_secret_store.dart';

const phrase =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const unlocked = SeedSession(unlocked: true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storageError = PlatformException(code: 'x', details: -25308);
  late FakeKeychain keychain;
  late BiometricPinPolicy policy;
  final w1 = [WalletConfig(id: 'w1', name: 'Wallet')];

  setUp(() {
    keychain = FakeKeychain();
    policy =
        BiometricPinPolicy(store: keychain.local, syncedStore: keychain.synced);
  });

  group('evaluate', () {
    test('keeps it when a V1 copy is the only source', () async {
      keychain.seed('mnemonic_w1', 'cipher');
      expect((await policy.evaluate(w1)).exists, isTrue);
    });

    test('keeps it when an encrypted root is the only source', () async {
      keychain.seed('mnemonic', 'cipher');
      expect((await policy.evaluate(w1)).exists, isTrue);
    });

    test('a V1 copy needs the PIN even next to a plaintext root', () async {
      keychain
        ..seed('mnemonic_w1', 'cipher')
        ..seed('mnemonic', phrase);
      expect((await policy.evaluate(w1)).exists, isTrue);
    });

    test('a plaintext root needs no PIN', () async {
      keychain.seed('mnemonic', phrase);
      expect((await policy.evaluate(w1)).exists, isFalse);
    });

    test('removes it when every stored wallet has a V2 copy', () async {
      keychain
        ..seed('mnemonic_w1', 'cipher')
        ..seed('v2:wallet:w1.mnemonic', phrase)
        ..seed('mnemonic_w2', 'cipher')
        ..seedSynced('v2:wallet:w2.mnemonic', phrase);
      final wallets = [...w1, WalletConfig(id: 'w2', name: 'Second')];
      expect((await policy.evaluate(wallets)).exists, isFalse);
    });

    test('passkey, hardware, watch-only and external wallets never count',
        () async {
      final wallets = [
        WalletConfig(id: 'p', name: 'P', isPasskey: true),
        WalletConfig(id: 'h', name: 'H', isHardware: true),
        WalletConfig(id: 'o', name: 'O', isWatchOnly: true),
        WalletConfig(id: 'e', name: 'E', isExternalAddress: true),
      ];
      for (final w in wallets) {
        keychain.seed('mnemonic_${w.id}', 'cipher');
      }
      expect((await policy.evaluate(wallets)).exists, isFalse);
    });

    for (final (store, key) in [
      ('local', 'v2:wallet:w1.mnemonic'),
      ('synced', 'v2:wallet:w1.mnemonic'),
      ('local', 'mnemonic_w1'),
      ('local', 'mnemonic'),
    ]) {
      test('a failed $store read of $key keeps it', () async {
        keychain.failRead(store, storageError, key: key);
        expect((await policy.evaluate(w1)).exists, isTrue);
      });
    }

    test('reports the stored PIN state', () async {
      expect((await policy.evaluate(w1)).biometricPin, StoredPinState.absent);
      keychain.seed('biometric_pin', '123456');
      expect((await policy.evaluate(w1)).biometricPin, StoredPinState.present);
      keychain.failRead('local', storageError, key: 'biometric_pin');
      expect((await policy.evaluate(w1)).biometricPin, StoredPinState.failed);
    });
  });

  group('applyAfterUnlock', () {
    test('without a dependency the local copy is deleted, a synced twin kept',
        () async {
      keychain
        ..seed('v2:wallet:w1.mnemonic', phrase)
        ..seed('biometric_pin', '123456')
        ..seedSynced('biometric_pin', '123456');
      await policy.applyAfterUnlock(await policy.evaluate(w1),
          typedPin: '123456');
      expect(keychain.peek('biometric_pin'), isNull);
      expect(keychain.peekSynced('biometric_pin'), '123456');
      expect(keychain.mutations, const [
        FakeMutation('local', 'deleteLocalOnly', 'biometric_pin'),
      ]);
    });

    test('without a dependency and no copy nothing is written', () async {
      keychain.seed('v2:wallet:w1.mnemonic', phrase);
      await policy.applyAfterUnlock(await policy.evaluate(w1),
          typedPin: '123456');
      expect(keychain.mutations, isEmpty);
    });

    test('with a dependency the typed PIN stores a missing copy', () async {
      keychain.seed('mnemonic_w1', 'cipher');
      await policy.applyAfterUnlock(await policy.evaluate(w1),
          typedPin: '123456');
      expect(keychain.peek('biometric_pin'), '123456');
      expect(keychain.mutations, const [
        FakeMutation('local', 'writeLocalOnly', 'biometric_pin'),
      ]);
    });

    test('with a dependency the typed PIN replaces a stale copy', () async {
      keychain
        ..seed('mnemonic_w1', 'cipher')
        ..seed('biometric_pin', '000000');
      await policy.applyAfterUnlock(await policy.evaluate(w1),
          typedPin: '123456');
      expect(keychain.peek('biometric_pin'), '123456');
    });

    test(
        'with a dependency a matching copy or a biometric unlock writes '
        'nothing', () async {
      keychain
        ..seed('mnemonic_w1', 'cipher')
        ..seed('biometric_pin', '123456');
      final dependency = await policy.evaluate(w1);
      await policy.applyAfterUnlock(dependency, typedPin: '123456');
      await policy.applyAfterUnlock(dependency);
      expect(keychain.mutations, isEmpty);
    });
  });

  test('setting a PIN never writes biometric_pin', () async {
    final auth = AuthModel(store: keychain.local, syncedStore: keychain.synced);
    await auth.setPin('123456');
    await auth.setPinAsync('654321');
    expect(keychain.keys(), {'pin_hash'});
  });

  group('biometric unlock', () {
    late Directory hiveDir;

    setUp(() async {
      hiveDir = await Directory.systemTemp.createTemp('biometric_pin_policy');
      Hive.init(hiveDir.path);
      final box = await Hive.openBox('settings');
      await box.put('wallets', [
        {'id': 'w1', 'name': 'Wallet'},
      ]);
    });

    tearDown(() async {
      await Hive.close();
      await hiveDir.delete(recursive: true);
    });

    Future<bool> keepOnDevice() async {
      final dependency = await policy.evaluate(w1);
      return dependency.exists &&
          dependency.biometricPin == StoredPinState.present;
    }

    test('a V1-only wallet stays readable through biometrics and a PIN change',
        () async {
      keychain
        ..seed('pin_hash', PinHashHelper.hashPin('123456'))
        ..seed('biometric_pin', '123456')
        ..seed(
            'mnemonic_w1', PinEncryptionHelper.encryptData(phrase, '123456'));
      final auth =
          AuthModel(store: keychain.local, syncedStore: keychain.synced);

      final dependency = await policy.evaluate(w1);
      expect(dependency.exists, isTrue);
      final verdict = await checkBiometricUnlock(auth, dependency);
      expect((verdict as BiometricUnlockAllowed).storedPin, '123456');
      await policy.applyAfterUnlock(dependency);
      expect(keychain.mutations, isEmpty);
      expect(await auth.requireMnemonic('w1', session: unlocked), phrase);

      await auth.changePin('123456', '654321', keepBiometricPin: keepOnDevice);
      expect(keychain.peek('biometric_pin'), '654321');
      expect(await auth.requireMnemonic('w1', session: unlocked), phrase);
      final after = await checkBiometricUnlock(auth, await policy.evaluate(w1));
      expect((after as BiometricUnlockAllowed).storedPin, '654321');
    });

    test('without a V1-only wallet biometrics unlock alone and the copy goes',
        () async {
      final reads = <String>[];
      keychain
        ..seed('pin_hash', PinHashHelper.hashPin('123456'))
        ..seed('biometric_pin', '123456')
        ..seed('v2:wallet:w1.mnemonic', phrase)
        ..seed(
            'mnemonic_w1', PinEncryptionHelper.encryptData(phrase, '123456'));
      final auth = AuthModel(
        store: RecordingSecretStore(keychain.local, name: 'local', log: reads),
        syncedStore: keychain.synced,
      );

      final dependency = await policy.evaluate(w1);
      expect(dependency.exists, isFalse);
      final verdict = await checkBiometricUnlock(auth, dependency);
      expect((verdict as BiometricUnlockAllowed).storedPin, isNull);
      expect(reads, isEmpty, reason: 'biometric_pin is never read');
      await policy.applyAfterUnlock(dependency);
      expect(keychain.peek('biometric_pin'), isNull);

      keychain.seed('biometric_pin', '123456');
      await auth.changePin('123456', '654321', keepBiometricPin: keepOnDevice);
      expect(keychain.peek('biometric_pin'), isNull);
      expect(await auth.requireMnemonic('w1', session: unlocked), phrase);
    });

    test('a missing or stale stored PIN is refused when a wallet needs it',
        () async {
      keychain.seed('pin_hash', PinHashHelper.hashPin('123456'));
      final auth =
          AuthModel(store: keychain.local, syncedStore: keychain.synced);
      const needsPin =
          V1Dependency(exists: true, biometricPin: StoredPinState.absent);

      final missing = await checkBiometricUnlock(auth, needsPin);
      expect((missing as BiometricUnlockRefused).reason, 'stored_pin_null');
      keychain.seed('biometric_pin', '000000');
      final stale = await checkBiometricUnlock(auth, needsPin);
      expect((stale as BiometricUnlockRefused).reason, 'stored_pin_stale');
    });
  });
}
