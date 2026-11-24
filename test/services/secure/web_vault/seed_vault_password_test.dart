// The laptop browser's password lock (unlock_secret.dart): a password
// takes the PIN's place in the vault's derivation, after NFKC, and the
// record says which kind it was made with. Every secret here is a test
// literal.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/platform/unlock_secret.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/services/secure/web_vault/seed_vault.dart';
import 'package:kute/services/secure/web_vault/vault_router.dart';

import 'vault_fakes.dart';

/// The public BIP39 test vector; never a real wallet.
const phrase = 'abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon about';
const key = 'v2:wallet:w1.mnemonic';
const opts = <String, String>{};

const testPassword = 'correct horse battery';

void main() {
  late MemoryVaultDb db;
  late SeedVault vault;

  setUp(() async {
    db = MemoryVaultDb();
    vault = await newVault(db);
  });

  group('password-kind vault', () {
    test('create records the kind; the right password reopens it', () async {
      await vault.create(testPassword, kind: VaultSecretKind.password);
      expect(vault.secretKind, VaultSecretKind.password);
      expect(db.meta!['kind'], 'password');
      await vault.write(key, phrase);
      final dump = jsonEncode({'meta': db.meta, 'entries': db.entries});
      expect(dump.contains('horse'), isFalse);
      expect(dump.contains('abandon'), isFalse);

      final reloaded = await newVault(db);
      expect(reloaded.secretKind, VaultSecretKind.password);
      expect(reloaded.isOpen, isFalse);
      expect(await reloaded.unlock(testPassword), VaultUnlock.ok);
      expect(await reloaded.read(key), phrase);
    });

    test('a wrong password fails by the tag and opens nothing', () async {
      await vault.create(testPassword, kind: VaultSecretKind.password);
      vault.lock();
      for (final wrong in [
        'correct horse batterY',
        'correct horse battery ',
        '123456',
        '',
      ]) {
        expect(await vault.unlock(wrong), VaultUnlock.wrongPin);
        expect(vault.isOpen, isFalse);
      }
      expect(await vault.unlock(testPassword), VaultUnlock.ok);
    });

    test('a long Unicode password of any length works', () async {
      final long = '${'пароль密码🔐ñ' * 60}\u{1F469}‍\u{1F4BB} end';
      expect(long.length, greaterThan(400));
      await vault.create(long, kind: VaultSecretKind.password);
      await vault.write(key, phrase);
      vault.lock();
      expect(await vault.unlock(long.substring(0, long.length - 1)),
          VaultUnlock.wrongPin);
      expect(await vault.unlock(long), VaultUnlock.ok);
      expect(await vault.read(key), phrase);
    });

    test('NFKC-equivalent input unlocks (composed, decomposed, compat forms)',
        () async {
      // é composed, the ﬁ ligature, full-width digits.
      const typed = 'Café ﬁne ２０２６';
      // é as e + combining acute, plain fi, ASCII digits.
      const equivalent = 'Café fine 2026';
      expect(normalizeVaultSecret(typed), normalizeVaultSecret(equivalent));
      await vault.create(typed, kind: VaultSecretKind.password);
      vault.lock();
      expect(await vault.unlock(equivalent), VaultUnlock.ok);
      vault.lock();
      expect(await vault.unlock('Cafe fine 2026'), VaultUnlock.wrongPin);
    });

    test('NFKC leaves a 6-digit PIN unchanged', () {
      expect(normalizeVaultSecret('012345'), '012345');
    });
  });

  group('PIN-kind vault', () {
    test('a record without a kind is a PIN vault and still opens', () async {
      await vault.create('123456');
      db.meta!.remove('kind');
      final reloaded = await newVault(db);
      expect(reloaded.secretKind, VaultSecretKind.pin);
      expect(await reloaded.unlock('123456'), VaultUnlock.ok);
    });

    test('upgrades to a password: the PIN stops, the password opens the same '
        'key, PRF and entries survive', () async {
      await vault.create('123456');
      await vault.write(key, phrase);
      await vault.enrolPrf('cred', Uint8List.fromList(List.filled(32, 1)),
          Uint8List.fromList(List.filled(32, 2)));
      vault.lock();
      expect(await vault.unlock('123456'), VaultUnlock.ok);
      await vault.changePin(testPassword, kind: VaultSecretKind.password);
      expect(vault.secretKind, VaultSecretKind.password);
      expect(db.meta!['kind'], 'password');

      final reloaded = await newVault(db);
      expect(reloaded.secretKind, VaultSecretKind.password);
      expect(await reloaded.unlock('123456'), VaultUnlock.wrongPin);
      expect(await reloaded.unlock(testPassword), VaultUnlock.ok);
      expect(await reloaded.read(key), phrase);
      expect(reloaded.prf?.credentialId, 'cred');
    });

    test('a change without a kind keeps the record\'s kind', () async {
      await vault.create(testPassword, kind: VaultSecretKind.password);
      await vault.changePin('another long password');
      expect(vault.secretKind, VaultSecretKind.password);
    });
  });

  test('VaultSecretKind.of: six ASCII digits are a PIN, anything else a '
      'password', () {
    expect(VaultSecretKind.of('123456'), VaultSecretKind.pin);
    expect(VaultSecretKind.of('1234567890'), VaultSecretKind.password);
    expect(VaultSecretKind.of('１２３４５６'),
        VaultSecretKind.password);
    expect(VaultSecretKind.of(testPassword), VaultSecretKind.password);
  });

  group('AuthModel on the web vault', () {
    late FlutterSecureStoragePlatform original;
    late VaultStoragePlatform router;
    late AuthModel auth;

    setUpAll(() => original = FlutterSecureStoragePlatform.instance);
    tearDownAll(() => FlutterSecureStoragePlatform.instance = original);

    setUp(() async {
      router = VaultStoragePlatform(vault: vault, plain: const {});
      FlutterSecureStoragePlatform.instance = router;
      SecretStores.debugReset();
      auth = AuthModel(webVault: router);
    });

    test('a password set on create makes a password vault', () async {
      await auth.setPinAsync(testPassword);
      expect(vault.secretKind, VaultSecretKind.password);
      router.lock();
      expect(await auth.checkPin('123456'), PinCheck.mismatch);
      expect(await auth.checkPin(testPassword), PinCheck.match);
    });

    test('a PIN vault upgrades once its PIN opened it', () async {
      await auth.setPinAsync('123456');
      await SecretStores.local.writeLocalOnly(key: key, value: phrase);
      router.lock();
      expect(() => auth.upgradeToPassword(testPassword),
          throwsA(isA<VaultLockedException>()));
      expect(await auth.checkPin('123456'), PinCheck.match);
      expect(() => auth.upgradeToPassword('short'), throwsArgumentError);
      expect(vault.secretKind, VaultSecretKind.pin);
      await auth.upgradeToPassword(testPassword);
      expect(vault.secretKind, VaultSecretKind.password);
      router.lock();
      expect(await auth.checkPin('123456'), PinCheck.mismatch);
      expect(await auth.checkPin(testPassword), PinCheck.match);
      expect(await router.read(key: key, options: opts), phrase);
    });

    test('changing a PIN to a password marks the vault', () async {
      await auth.setPinAsync('123456');
      await auth.changePin('123456', testPassword);
      expect(vault.secretKind, VaultSecretKind.password);
      await auth.changePin(testPassword, '654321');
      expect(vault.secretKind, VaultSecretKind.pin);
    });
  });

  group('UnlockSecret', () {
    tearDown(() {
      UnlockSecret.debugDeviceKind = null;
      UnlockSecret.debugVaultKind = null;
    });

    BrowserSignals s({
      int touch = 0,
      bool coarse = false,
      bool noHover = false,
      String ua = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15',
    }) =>
        BrowserSignals(
            maxTouchPoints: touch,
            coarsePointer: coarse,
            noHover: noHover,
            userAgent: ua);

    test('a Mac laptop is a laptop', () {
      expect(UnlockSecret.classify(s()), VaultSecretKind.password);
    });

    test('iPadOS Safari (a "Mac" with touch points) keeps the PIN', () {
      expect(UnlockSecret.classify(s(touch: 5, coarse: true, noHover: true)),
          VaultSecretKind.pin);
      // With a trackpad attached the media queries may say fine/hover;
      // the touch points still give it away.
      expect(UnlockSecret.classify(s(touch: 5)), VaultSecretKind.pin);
    });

    test('phones keep the PIN', () {
      expect(
          UnlockSecret.classify(s(
              touch: 5,
              coarse: true,
              noHover: true,
              ua: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)')),
          VaultSecretKind.pin);
      expect(
          UnlockSecret.classify(s(
              touch: 5,
              ua: 'Mozilla/5.0 (Linux; Android 15; Pixel 9) Mobile Safari')),
          VaultSecretKind.pin);
    });

    test('a touch-screen Windows laptop with a mouse is a laptop', () {
      expect(
          UnlockSecret.classify(s(
              touch: 10,
              ua: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0')),
          VaultSecretKind.password);
    });

    test('a browser that says nothing gets the stronger secret', () {
      expect(UnlockSecret.classify(null), VaultSecretKind.password);
    });

    test('off the web everything is the PIN', () {
      expect(UnlockSecret.deviceKind, VaultSecretKind.pin);
      expect(UnlockSecret.current, VaultSecretKind.pin);
      expect(UnlockSecret.needsPasswordUpgrade, isFalse);
    });

    test('a PIN vault in a laptop browser needs the upgrade', () {
      UnlockSecret.debugDeviceKind = VaultSecretKind.password;
      UnlockSecret.debugVaultKind = VaultSecretKind.pin;
      expect(UnlockSecret.needsPasswordUpgrade, isTrue);
      expect(UnlockSecret.forChange, VaultSecretKind.password);
      UnlockSecret.debugVaultKind = VaultSecretKind.password;
      expect(UnlockSecret.needsPasswordUpgrade, isFalse);
      // A password vault seen from a touch device stays a password.
      UnlockSecret.debugDeviceKind = VaultSecretKind.pin;
      expect(UnlockSecret.current, VaultSecretKind.password);
      expect(UnlockSecret.forChange, VaultSecretKind.password);
    });

    test('the rule counts characters as seen, nothing else', () {
      expect(UnlockSecret.meetsRule('123456789'), isFalse);
      expect(UnlockSecret.meetsRule('aaaaaaaaaa'), isTrue);
      // Ten emoji are ten characters, though twenty UTF-16 units.
      expect(UnlockSecret.meetsRule('🔐' * 9), isFalse);
      expect(UnlockSecret.meetsRule('🔐' * 10), isTrue);
    });
  });
}
