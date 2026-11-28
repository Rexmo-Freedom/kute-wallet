// A web vault made with a password (24 to 27 November 2026; every new
// vault takes the PIN since, unlock_secret.dart): a password takes the
// PIN's place in the vault's derivation, after NFKC, and the record says
// which kind it was made with, so it keeps asking for it. Every secret
// here is a test literal.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/platform/browser_signals.dart';
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

    test('opened by its biometric (PRF) key, a PIN vault upgrades to a '
        'password, and the biometric still opens it after', () async {
      final input = Uint8List.fromList(List.filled(32, 1));
      final output = Uint8List.fromList(List.filled(32, 2));
      await vault.create('123456');
      await vault.write(key, phrase);
      await vault.enrolPrf('cred', input, output);
      vault.lock();
      // The biometric unlock: no PIN typed.
      expect(await vault.unlockWithPrf('cred', Uint8List.fromList(output)),
          isTrue);
      await vault.changePin(testPassword, kind: VaultSecretKind.password);

      final reloaded = await newVault(db);
      expect(reloaded.secretKind, VaultSecretKind.password);
      expect(await reloaded.unlock('123456'), VaultUnlock.wrongPin);
      expect(await reloaded.unlock(testPassword), VaultUnlock.ok);
      reloaded.lock();
      expect(await reloaded.unlockWithPrf('cred', Uint8List.fromList(output)),
          isTrue);
      expect(await reloaded.read(key), phrase);
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

    tearDown(() => debugBrowserSignals = null);

    test('a new vault is a PIN vault, laptop browser signals included',
        () async {
      debugBrowserSignals = _laptop;
      expect(readBrowserSignals()!.isLaptop, isTrue);
      await auth.setPinAsync('123456');
      expect(vault.secretKind, VaultSecretKind.pin);
      expect(db.meta!['kind'], 'pin');
      router.lock();
      expect(await auth.checkPin('123456'), PinCheck.match);
    });

    test('a new vault refuses anything but the 6-digit PIN', () async {
      debugBrowserSignals = _laptop;
      await expectLater(
          auth.setPinAsync(testPassword), throwsArgumentError);
      expect(vault.exists, isFalse);
    });

    test('an existing password vault still asks for its password and '
        'still unlocks with it', () async {
      debugBrowserSignals = _laptop;
      // Made before 27 November 2026, with a password.
      await vault.create(testPassword, kind: VaultSecretKind.password);
      await SecretStores.local.writeLocalOnly(key: key, value: phrase);
      router.lock();
      final reloaded = await newVault(db);
      expect(reloaded.secretKind, VaultSecretKind.password);
      expect(await auth.checkPin('123456'), PinCheck.mismatch);
      expect(await auth.checkPin(testPassword), PinCheck.match);
      expect(await router.read(key: key, options: opts), phrase);
      // Nothing migrated it.
      expect(vault.secretKind, VaultSecretKind.password);
    });

    test('a password vault changed to a PIN becomes a PIN vault', () async {
      await vault.create(testPassword, kind: VaultSecretKind.password);
      await auth.changePin(testPassword, '654321');
      expect(vault.secretKind, VaultSecretKind.pin);
      router.lock();
      expect(await auth.checkPin(testPassword), PinCheck.mismatch);
      expect(await auth.checkPin('654321'), PinCheck.match);
    });
  });

  group('UnlockSecret', () {
    tearDown(() {
      UnlockSecret.debugVaultKind = null;
      debugBrowserSignals = null;
    });

    test('off the web, and before any vault, the PIN', () {
      expect(UnlockSecret.current, VaultSecretKind.pin);
      debugBrowserSignals = _laptop;
      expect(UnlockSecret.current, VaultSecretKind.pin);
    });

    test('a vault recorded as a password keeps asking for it, whatever '
        'the browser', () {
      UnlockSecret.debugVaultKind = VaultSecretKind.password;
      debugBrowserSignals = _laptop;
      expect(UnlockSecret.current, VaultSecretKind.password);
      debugBrowserSignals = _signals(touch: 5, coarse: true, noHover: true);
      expect(UnlockSecret.current, VaultSecretKind.password);
    });
  });

  group('BrowserSignals.isLaptop', () {
    test('a Mac laptop is a laptop', () {
      expect(_laptop.isLaptop, isTrue);
    });

    test('iPadOS Safari (a "Mac" with touch points) is touch-first', () {
      expect(_signals(touch: 5, coarse: true, noHover: true).isLaptop,
          isFalse);
      // With a trackpad attached the media queries may say fine/hover;
      // the touch points still give it away.
      expect(_signals(touch: 5).isLaptop, isFalse);
    });

    test('phones are touch-first', () {
      expect(
          _signals(
                  touch: 5,
                  coarse: true,
                  noHover: true,
                  ua: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)')
              .isLaptop,
          isFalse);
      expect(
          _signals(
                  touch: 5,
                  ua: 'Mozilla/5.0 (Linux; Android 15; Pixel 9) Mobile Safari')
              .isLaptop,
          isFalse);
    });

    test('a touch-screen Windows laptop with a mouse is a laptop', () {
      expect(
          _signals(
                  touch: 10,
                  ua: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0')
              .isLaptop,
          isTrue);
    });
  });
}

BrowserSignals _signals({
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

final BrowserSignals _laptop = _signals();
