import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/services/auth/pin_hash.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/services/secure/web_vault/seed_vault.dart';
import 'package:kute/services/secure/web_vault/vault_keys.dart';
import 'package:kute/services/secure/web_vault/vault_router.dart';

import 'vault_fakes.dart';

/// The public BIP39 test vector; never a real wallet.
const phrase = 'abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon about';
const seedKey = 'v2:wallet:w1.mnemonic';
const opts = <String, String>{};

void main() {
  late MemoryVaultDb db;
  late SeedVault vault;
  late FakeLegacyWeb legacy;
  late VaultStoragePlatform router;
  late FlutterSecureStoragePlatform original;

  Future<VaultStoragePlatform> boot() async {
    vault = await newVault(db);
    final r = VaultStoragePlatform(
        vault: vault, plain: await db.readPlain(), legacy: legacy.store());
    await r.copyOrdinaryFromLegacy();
    FlutterSecureStoragePlatform.instance = r;
    return r;
  }

  /// Every value the old layout or the plain store holds, for "no secret
  /// outside the vault" checks.
  void expectNoSecretOutsideVault() {
    for (final entry in legacy.localStorage.entries) {
      expect(isKnownSecretKeyName(entry.key), isFalse,
          reason: 'secret key name in localStorage');
      expect(looksLikeSecretValue(entry.value), isFalse);
    }
    for (final entry in db.plain.entries) {
      expect(isVaultSecretKey(entry.key), isFalse);
      expect(looksLikeSecretValue(entry.value), isFalse);
    }
  }

  setUpAll(() => original = FlutterSecureStoragePlatform.instance);
  tearDownAll(() => FlutterSecureStoragePlatform.instance = original);

  setUp(() async {
    db = MemoryVaultDb();
    legacy = FakeLegacyWeb();
    router = await boot();
  });

  group('classification', () {
    test('seeds, passkey seeds, CLOB credentials and PIN material are secret',
        () {
      for (final k in [
        'v2:wallet:abc.mnemonic',
        'mnemonic_abc',
        'mnemonic_abc.next',
        'mnemonic',
        'prf_seed_v1__ff',
        'passkey017_seed_v1__ff',
        'pm_api_credentials_abc',
        'pin_hash',
        'pin',
        'biometric_pin',
      ]) {
        expect(isVaultSecretKey(k), isTrue, reason: k);
      }
      for (final k in [
        'kute.binding.v1',
        'failed_pin_attempts',
        'lockout_until',
        'xpub_abc',
        'pm_proxy_wallet_abc',
        'prf_credential_id_v1__ff',
        'passkey_registered_v1',
        'kute_device_uuid',
        'standing_order:1',
      ]) {
        expect(isVaultSecretKey(k), isFalse, reason: k);
      }
    });

    test('the guards spot phrases and secret names under any prefix', () {
      expect(looksLikeSecretValue(phrase), isTrue);
      expect(looksLikeSecretValue('{"seed":"$phrase"}'), isTrue);
      expect(looksLikeSecretValue('2026-11-24T10:00:00Z'), isFalse);
      expect(looksLikeSecretValue('a' * 64), isFalse);
      expect(isKnownSecretKeyName('FlutterSecureStorage'), isTrue);
      expect(isKnownSecretKeyName('FlutterSecureStorage.$seedKey'), isTrue);
      expect(isKnownSecretKeyName('FlutterSecureStorage.pin_hash'), isTrue);
      expect(isKnownSecretKeyName('ph_phc_xyz_posthog'), isFalse);
    });
  });

  group('routing', () {
    test('secrets go to the vault, ordinary keys to the plain store', () async {
      await vault.create('123456');
      await router.write(key: seedKey, value: phrase, options: opts);
      await router.write(key: 'failed_pin_attempts', value: '2', options: opts);
      expect(db.entries.keys, [seedKey]);
      expect(db.plain, {'failed_pin_attempts': '2'});
      expect(await router.read(key: seedKey, options: opts), phrase);
      expectNoSecretOutsideVault();
    });

    test('locked: absent secrets answer at once, present ones wait', () async {
      await vault.create('123456');
      await router.write(key: seedKey, value: phrase, options: opts);
      router.lock();

      expect(await router.read(key: 'mnemonic_none', options: opts), isNull);
      expect(await router.containsKey(key: seedKey, options: opts), isTrue);
      expect(
          () => router.write(key: seedKey, value: phrase, options: opts),
          throwsA(isA<VaultLockedException>()));

      var done = false;
      final pending = router.read(key: seedKey, options: opts)
        ..then((_) => done = true);
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse);
      expect(await router.checkPin('123456'), WebPinCheck.match);
      expect(await pending, phrase);
    });

    test('wipe resumes a waiting reader with nothing and clears every store',
        () async {
      legacy.seed({'fcmToken': 't'});
      await vault.create('123456');
      await router.write(key: seedKey, value: phrase, options: opts);
      await router.write(key: 'hl_enabled_w1', value: 'true', options: opts);
      router.lock();
      final pending = router.read(key: seedKey, options: opts);
      await router.deleteAll(options: opts);
      expect(await pending, isNull);
      expect(db.meta, isNull);
      expect(db.deviceKey, isNull);
      expect(db.entries, isEmpty);
      expect(db.plain, isEmpty);
      expect(legacy.localStorage, isEmpty);
      expect(router.hasPinMaterial, isFalse);
    });
  });

  group('AuthModel on web', () {
    late AuthModel auth;
    setUp(() {
      SecretStores.debugReset();
      auth = AuthModel(webVault: router);
    });

    test('setPin creates the vault: no pin_hash anywhere', () async {
      expect(await auth.hasPinSet(), isFalse);
      await auth.setPinAsync('123456');
      expect(await auth.hasPinSet(), isTrue);
      expect(db.plain.containsKey('pin_hash'), isFalse);
      expect(db.entries.containsKey('pin_hash'), isFalse);
      expect(() => auth.setPin('111111'),
          throwsA(isA<PinAlreadySetException>()));
    });

    test('wrong PIN is a mismatch (counted), right PIN reads the seed',
        () async {
      await auth.setPinAsync('123456');
      await SecretStores.local.writeLocalOnly(key: seedKey, value: phrase);
      router.lock();
      expect(await auth.checkPin('000000'), PinCheck.mismatch);
      expect(vault.isOpen, isFalse);
      expect(await auth.checkPin('123456'), PinCheck.match);
      final read = await auth.readMnemonic('w1',
          access: SeedAccess.automatic,
          session: const SeedSession(unlocked: true));
      expect(read, isA<SeedOk>());
      expect((read as SeedOk).value, phrase);
    });

    test('no vault and no old layout: no PIN material (no keypad counting)',
        () async {
      expect(await auth.checkPin('123456'), PinCheck.noPinMaterial);
    });

    test('changePin re-wraps the vault; the old PIN stops working', () async {
      await auth.setPinAsync('123456');
      await SecretStores.local.writeLocalOnly(key: seedKey, value: phrase);
      await auth.changePin('123456', '654321');
      expect(() => auth.changePin('123456', '111111'),
          throwsA(isA<IncorrectPinException>()));
      router.lock();
      final reboot = await boot();
      final auth2 = AuthModel(webVault: reboot);
      expect(await auth2.checkPin('123456'), PinCheck.mismatch);
      expect(await auth2.checkPin('654321'), PinCheck.match);
      expect(await reboot.read(key: seedKey, options: opts), phrase);
      expect(await auth2.getBiometricPin(), isNull);
    });

    test('deleting a wallet deletes its vault entry', () async {
      await auth.setPinAsync('123456');
      await SecretStores.local.writeLocalOnly(key: seedKey, value: phrase);
      await auth.deleteWalletMnemonic('w1');
      expect(db.entries.containsKey(seedKey), isFalse);
    });
  });

  group('migration of the old localStorage layout', () {
    late String oldHash;
    setUpAll(() => oldHash = PinHashHelper.hashPin('123456'));

    Future<VaultStoragePlatform> seedOld() async {
      legacy.seed({
        'pin_hash': oldHash,
        seedKey: phrase,
        'kute.binding.v1': 'b1',
        'failed_pin_attempts': '1',
        'pm_api_credentials_w1': '{"secret":"s"}',
        'biometric_pin': '123456',
      });
      return boot();
    }

    test('boot copies ordinary values only; secrets wait for the PIN',
        () async {
      router = await seedOld();
      expect(db.plain, {'kute.binding.v1': 'b1', 'failed_pin_attempts': '1'});
      expect(db.entries, isEmpty);
      expect(router.hasPinMaterial, isTrue);
      // The old layout is untouched until a verified PIN.
      expect(legacy.localStorage.containsKey('FlutterSecureStorage'), isTrue);
    });

    test('wrong PIN: mismatch, nothing created, nothing deleted', () async {
      router = await seedOld();
      final before = Map.of(legacy.localStorage);
      expect(await router.checkPin('000000'), WebPinCheck.mismatch);
      expect(db.meta, isNull);
      expect(legacy.localStorage, before);
    });

    test('first unlock moves everything, verifies, then deletes the old '
        'entries, the raw key and pin_hash', () async {
      router = await seedOld();
      expect(await router.checkPin('123456'), WebPinCheck.match);
      expect(router.lastMigration, WebMigration.done);
      expect(legacy.localStorage, isEmpty);
      expect(await router.read(key: seedKey, options: opts), phrase);
      expect(
          await router.read(key: 'pm_api_credentials_w1', options: opts),
          '{"secret":"s"}');
      // Never migrated: the raw PIN copy and the fast hash.
      expect(db.entries.containsKey('biometric_pin'), isFalse);
      expect(db.entries.containsKey('pin_hash'), isFalse);
      expectNoSecretOutsideVault();

      // After a reload it is a plain vault: locked, PIN by tag.
      final reboot = await boot();
      expect(reboot.hasPinMaterial, isTrue);
      expect(await reboot.checkPin('000000'), WebPinCheck.mismatch);
      expect(await reboot.checkPin('123456'), WebPinCheck.match);
      expect(await reboot.read(key: seedKey, options: opts), phrase);
    });

    test('a failure keeps the old data; the next unlock finishes', () async {
      router = await seedOld();
      db.failEntryWritesAfter = 1; // the second secret write fails
      expect(await router.checkPin('123456'), WebPinCheck.match);
      expect(router.lastMigration, WebMigration.failedKeptOld);
      expect(legacy.localStorage.containsKey('FlutterSecureStorage'), isTrue);
      expect(legacy.localStorage.containsKey('FlutterSecureStorage.$seedKey'),
          isTrue);
      // The session still reads every secret.
      expect(await router.read(key: seedKey, options: opts), phrase);
      expect(
          await router.read(key: 'pm_api_credentials_w1', options: opts),
          '{"secret":"s"}');

      db.failEntryWritesAfter = -1;
      final reboot = await boot();
      expect(await reboot.checkPin('123456'), WebPinCheck.match);
      expect(reboot.lastMigration, WebMigration.done);
      expect(legacy.localStorage, isEmpty);
      expect(await reboot.read(key: seedKey, options: opts), phrase);
      expect(
          await reboot.read(key: 'pm_api_credentials_w1', options: opts),
          '{"secret":"s"}');
    });

    test('a vault that cannot be created: the old layout serves the session',
        () async {
      legacy.seed({'pin_hash': oldHash, seedKey: phrase});
      final broken = _ThrowingMetaDb();
      final v = await newVault(broken);
      final r = VaultStoragePlatform(
          vault: v, plain: const {}, legacy: legacy.store());
      expect(await r.checkPin('123456'), WebPinCheck.match);
      expect(r.lastMigration, WebMigration.failedKeptOld);
      expect(await r.read(key: seedKey, options: opts), phrase);
      expect(legacy.localStorage.containsKey('FlutterSecureStorage.pin_hash'),
          isTrue);
      r.lock();
      var done = false;
      r.read(key: seedKey, options: opts).then((_) => done = true);
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse, reason: 'locked again: secrets wait');
    });
  });
}

class _ThrowingMetaDb extends MemoryVaultDb {
  @override
  Future<void> writeMeta(Map<String, Object?> m) async =>
      throw StateError('quota');
}
