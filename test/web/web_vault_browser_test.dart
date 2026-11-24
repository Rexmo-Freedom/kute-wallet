// The real WebCrypto + IndexedDB path of the seed vault, in a browser:
//   flutter test --platform chrome test/web/web_vault_browser_test.dart
@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/secure/web_vault/seed_vault.dart';
import 'package:kute/services/secure/web_vault/web_vault_web.dart';

/// The public BIP39 test vector; never a real wallet.
const phrase = 'abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon about';
const seedKey = 'v2:wallet:w1.mnemonic';

Future<SeedVault> open({int iterations = 600000}) async {
  final vault = SeedVault(
      crypto: WebVaultCrypto(),
      db: IdbVaultDb(await debugOpenVaultDb()),
      iterations: iterations);
  await vault.load();
  return vault;
}

void main() {
  setUp(() async {
    final v = await open();
    await v.wipe();
  });

  test('real WebCrypto: create, lock, wrong PIN, right PIN, PIN change',
      () async {
    final vault = await open();
    await vault.create('123456');
    await vault.write(seedKey, phrase);
    vault.lock();

    final reloaded = await open();
    expect(reloaded.isOpen, isFalse);
    expect(await reloaded.unlock('000000'), VaultUnlock.wrongPin);
    expect(await reloaded.unlock('123456'), VaultUnlock.ok);
    expect(await reloaded.read(seedKey), phrase);

    await reloaded.changePin('654321');
    final again = await open();
    expect(await again.unlock('123456'), VaultUnlock.wrongPin);
    expect(await again.unlock('654321'), VaultUnlock.ok);
    expect(await again.read(seedKey), phrase);
  });

  test('the device key is a non-extractable CryptoKey; exportKey rejects',
      () async {
    final vault = await open(iterations: 1000);
    await vault.create('123456');
    final key = await vault.db.readDeviceKey() as JSObject;
    expect(key.instanceOfString('CryptoKey'), isTrue);
    expect((key['extractable'] as JSBoolean).toDart, isFalse);
    final subtle =
        (globalContext['crypto'] as JSObject)['subtle'] as JSObject;
    Object? error;
    try {
      await subtle
          .callMethod<JSPromise<JSAny?>>('exportKey'.toJS, 'raw'.toJS, key)
          .toDart;
    } catch (e) {
      error = e;
    }
    expect(error, isNotNull);
  });

  test('IndexedDB holds ciphertext only', () async {
    final vault = await open(iterations: 1000);
    await vault.create('123456');
    await vault.write(seedKey, phrase);
    final entries = await vault.db.readEntries();
    final meta = await vault.db.readMeta();
    expect('$entries$meta'.contains('abandon'), isFalse);
    expect('$entries$meta'.contains('123456'), isFalse);
  });

  test('PRF wrap opens with the right output only', () async {
    final vault = await open(iterations: 1000);
    await vault.create('123456');
    await vault.write(seedKey, phrase);
    final output = Uint8List.fromList(List.filled(32, 7));
    await vault.enrolPrf('cred', Uint8List(32), output);
    final reloaded = await open(iterations: 1000);
    expect(await reloaded.unlockWithPrf('cred', Uint8List(32)), isFalse);
    expect(await reloaded.unlockWithPrf('cred', output), isTrue);
    expect(await reloaded.read(seedKey), phrase);
  });

  test('the storage guard refuses secrets in localStorage', () {
    installWebStorageGuard();
    final ls = globalContext['localStorage'] as JSObject;
    void set(String k, String v) =>
        ls.callMethod<JSAny?>('setItem'.toJS, k.toJS, v.toJS);
    expect(() => set('FlutterSecureStorage', 'x'), throwsA(anything));
    expect(() => set('FlutterSecureStorage.$seedKey', 'x'), throwsA(anything));
    expect(() => set('anything', phrase), throwsA(anything));
    set('harmless', '1');
    expect(
        (ls.callMethod<JSString?>('getItem'.toJS, 'harmless'.toJS))?.toDart,
        '1');
    ls.callMethod<JSAny?>('removeItem'.toJS, 'harmless'.toJS);
  });
}
