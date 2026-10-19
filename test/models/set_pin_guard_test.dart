// setPin / setPinAsync store a NEW PIN hash. A stored pin_hash is what
// PIN-encrypted seed copies verify against, so an existing (or unreadable)
// hash is kept unless the caller asks to replace it.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/services/auth/pin_hash.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';

import '../services/support/fake_secret_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeKeychain keychain;
  late AuthModel auth;

  setUp(() {
    keychain = FakeKeychain();
    SecretStores.debugOverride(local: keychain.local, synced: keychain.synced);
    auth = AuthModel(wallets: () async => const []);
  });

  tearDown(SecretStores.debugReset);

  for (final (name, set) in [
    ('setPin', (String pin, {bool replace = false}) =>
        auth.setPin(pin, replace: replace)),
    ('setPinAsync', (String pin, {bool replace = false}) =>
        auth.setPinAsync(pin, replace: replace)),
  ]) {
    group(name, () {
      test('stores a first PIN and drops the legacy plain pin', () async {
        keychain.seed('pin', '111111');
        await set('123456');
        expect(PinHashHelper.verifyPin('123456', keychain.peek('pin_hash')!),
            isTrue);
        expect(keychain.peek('pin'), isNull);
      });

      test('refuses to overwrite a stored hash', () async {
        final existing = PinHashHelper.hashPin('123456');
        keychain.seed('pin_hash', existing);
        keychain.mutations.clear();
        await expectLater(
            set('654321'), throwsA(isA<PinAlreadySetException>()));
        expect(keychain.peek('pin_hash'), existing);
        expect(keychain.mutations, isEmpty);
        expect(await auth.checkPin('123456'), PinCheck.match);
      });

      test('an unreadable hash is kept too', () async {
        keychain.seed('pin_hash', PinHashHelper.hashPin('123456'));
        keychain.failRead('local',
            PlatformException(code: 'x', details: -25308),
            key: 'pin_hash');
        await expectLater(
            set('654321'),
            throwsA(isA<PinAlreadySetException>()
                .having((e) => e.unreadable, 'unreadable', isTrue)));
        expect(keychain.mutations, isEmpty);
      });

      test('replace: true writes over a stored hash', () async {
        keychain.seed('pin_hash', PinHashHelper.hashPin('123456'));
        await set('654321', replace: true);
        expect(await auth.checkPin('654321'), PinCheck.match);
        expect(await auth.checkPin('123456'), PinCheck.mismatch);
      });
    });
  }
}
