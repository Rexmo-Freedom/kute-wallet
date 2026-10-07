import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/services/auth/pin_encryption.dart';
import 'package:kute/services/auth/pin_hash.dart';

import '../services/support/fake_secret_store.dart';

const oldPin = '111111';
const newPin = '222222';
const otherPin = '999999';
const phraseA =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const phraseB = 'zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong';
const rootPhrase =
    'legal winner thank year wave sausage worth useful legal winner thank yellow';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String oldHash;
  late String encAOld;
  late String encBOld;
  late String encRootOld;
  late String encAOther;
  late String encBOther;

  setUpAll(() {
    oldHash = PinHashHelper.hashPin(oldPin);
    encAOld = PinEncryptionHelper.encryptData(phraseA, oldPin);
    encBOld = PinEncryptionHelper.encryptData(phraseB, oldPin);
    encRootOld = PinEncryptionHelper.encryptData(rootPhrase, oldPin);
    encAOther = PinEncryptionHelper.encryptData(phraseA, otherPin);
    encBOther = PinEncryptionHelper.encryptData(phraseB, otherPin);
  });

  late FakeKeychain keychain;
  late AuthModel auth;
  late Directory hiveDir;

  setUp(() async {
    keychain = FakeKeychain();
    auth = AuthModel(store: keychain.local, syncedStore: keychain.synced);
    hiveDir = await Directory.systemTemp.createTemp('change_pin');
    Hive.init(hiveDir.path);
    final box = await Hive.openBox('settings');
    await box.put('wallets', [
      {'id': 'a', 'name': 'A'},
      {'id': 'b', 'name': 'B'},
      {'id': 'passkey', 'name': 'P', 'isPasskey': true},
    ]);
  });

  tearDown(() async {
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  /// Wallet a: V1 and V2. Wallet b: V1 only. Root: PIN-encrypted.
  void seedStandard() {
    keychain
      ..seed('pin_hash', oldHash)
      ..seed('biometric_pin', oldPin)
      ..seed('mnemonic_a', encAOld)
      ..seed('v2:wallet:a.mnemonic', phraseA)
      ..seed('mnemonic_b', encBOld)
      ..seed('mnemonic', encRootOld);
  }

  const expected = {
    'mnemonic_a': phraseA,
    'mnemonic_b': phraseB,
    'mnemonic': rootPhrase,
  };

  Future<String?> decrypt(String key, String pin) async {
    final value = keychain.peek(key);
    if (value == null) return null;
    try {
      return PinEncryptionHelper.decryptData(value, pin);
    } catch (_) {
      return null;
    }
  }

  Set<String> pendingKeys() =>
      keychain.keys().where((k) => k.endsWith('.next')).toSet();

  test(
      're-encrypts V1 with V2, V1 only and the encrypted root under the new PIN',
      () async {
    seedStandard();
    await auth.changePin(oldPin, newPin);

    for (final entry in expected.entries) {
      expect(await decrypt(entry.key, newPin), entry.value, reason: entry.key);
    }
    expect(keychain.peek('v2:wallet:a.mnemonic'), phraseA);
    expect(pendingKeys(), isEmpty);
    expect(PinHashHelper.verifyPin(newPin, keychain.peek('pin_hash')!), isTrue);
    expect(keychain.peek('biometric_pin'), newPin);
    expect(
      keychain.mutations
          .where((m) => m.key.startsWith('mnemonic'))
          .map((m) => m.op)
          .toSet(),
      {'writeLocalOnly', 'deleteLocalOnly'},
    );
    expect(keychain.mutations.map((m) => m.store).toSet(), {'local'});
  });

  test(
      'takes the plaintext from V2 when V1 no longer decrypts with the old PIN',
      () async {
    seedStandard();
    keychain.seed('mnemonic_a', encAOther);
    await auth.changePin(oldPin, newPin);
    expect(await decrypt('mnemonic_a', newPin), phraseA);
  });

  test('takes the plaintext from a synced V2 copy and leaves it in place',
      () async {
    seedStandard();
    keychain
      ..seed('mnemonic_b', encBOther)
      ..seedSynced('v2:wallet:b.mnemonic', phraseB);
    await auth.changePin(oldPin, newPin);
    expect(await decrypt('mnemonic_b', newPin), phraseB);
    expect(keychain.peekSynced('v2:wallet:b.mnemonic'), phraseB);
    expect(keychain.peek('v2:wallet:b.mnemonic'), isNull);
  });

  test('throws ChangePinBlocked before any write when a copy has no source',
      () async {
    seedStandard();
    keychain.seed('mnemonic_b', encBOther);
    await expectLater(
      auth.changePin(oldPin, newPin),
      throwsA(isA<ChangePinBlocked>().having((e) => e.count, 'count', 1)),
    );
    expect(keychain.mutations, isEmpty);
    expect(keychain.peek('pin_hash'), oldHash);
    expect(keychain.peek('mnemonic_b'), encBOther);
  });

  test('an unreadable copy blocks the change', () async {
    seedStandard();
    keychain.failRead('local', PlatformException(code: 'x', details: -25308),
        key: 'mnemonic_b');
    await expectLater(
        auth.changePin(oldPin, newPin), throwsA(isA<ChangePinBlocked>()));
    expect(keychain.mutations, isEmpty);
  });

  test('a wrong old PIN writes nothing', () async {
    seedStandard();
    await expectLater(auth.changePin(otherPin, newPin),
        throwsA(isA<IncorrectPinException>()));
    expect(keychain.mutations, isEmpty);
  });

  test('a plaintext root is never rewritten', () async {
    seedStandard();
    keychain.seed('mnemonic', rootPhrase);
    await auth.changePin(oldPin, newPin);
    expect(keychain.peek('mnemonic'), rootPhrase);
    expect(keychain.mutations.where((m) => m.key.startsWith('mnemonic.')),
        isEmpty);
  });

  test('biometric_pin is deleted when it is not kept', () async {
    seedStandard();
    await auth.changePin(oldPin, newPin, keepBiometricPin: () async => false);
    expect(keychain.peek('biometric_pin'), isNull);
  });

  test('a crash after any write loses no copy and recovers at the next unlock',
      () async {
    seedStandard();
    await auth.changePin(oldPin, newPin);
    final total = keychain.mutations.length;
    expect(total, greaterThan(8));

    for (var crashAt = 0; crashAt < total; crashAt++) {
      keychain = FakeKeychain();
      auth = AuthModel(store: keychain.local, syncedStore: keychain.synced);
      seedStandard();
      keychain.crashAfter(crashAt);
      await expectLater(
          auth.changePin(oldPin, newPin), throwsA(isA<FakeCrash>()),
          reason: 'crash after $crashAt');
      keychain.restart();

      final activePin =
          await auth.checkPin(newPin) == PinCheck.match ? newPin : oldPin;
      final stalePin = activePin == newPin ? oldPin : newPin;
      expect(await auth.checkPin(stalePin), PinCheck.mismatch);

      await auth.recoverPendingPinChange(stalePin);
      await auth.recoverPendingPinChange(activePin);
      await auth.recoverPendingPinChange(activePin);

      for (final entry in expected.entries) {
        expect(await decrypt(entry.key, activePin), entry.value,
            reason: '${entry.key} after crash $crashAt');
      }
      expect(pendingKeys(), isEmpty, reason: 'crash after $crashAt');
      expect(keychain.peek('v2:wallet:a.mnemonic'), phraseA);

      final biometricPin = keychain.peek('biometric_pin');
      if (biometricPin != activePin) {
        expect(await auth.checkPin(biometricPin!), PinCheck.mismatch,
            reason: 'a stale biometric_pin never verifies');
      }
    }
  });

  test('recovery does nothing with a PIN that does not match pin_hash',
      () async {
    seedStandard();
    keychain.seed(
        'mnemonic_b.next', PinEncryptionHelper.encryptData(phraseB, otherPin));
    await auth.recoverPendingPinChange(otherPin);
    expect(keychain.mutations, isEmpty);
    expect(keychain.peek('mnemonic_b'), encBOld);
  });

  test('recovery leaves a pending copy that decrypts with neither PIN',
      () async {
    seedStandard();
    keychain
      ..seed('mnemonic_b', encBOther)
      ..seed('mnemonic_b.next', encBOther);
    await auth.recoverPendingPinChange(oldPin);
    expect(keychain.peek('mnemonic_b.next'), encBOther);
    expect(keychain.peek('mnemonic_b'), encBOther);
  });
}
