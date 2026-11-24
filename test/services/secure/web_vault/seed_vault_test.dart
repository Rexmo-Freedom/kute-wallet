import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/secure/web_vault/seed_vault.dart';

import 'vault_fakes.dart';

/// The public BIP39 test vector; never a real wallet.
const phrase = 'abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon about';
const key = 'v2:wallet:w1.mnemonic';

void main() {
  late MemoryVaultDb db;
  late SeedVault vault;

  setUp(() async {
    db = MemoryVaultDb();
    vault = await newVault(db);
  });

  test('defaults to PBKDF2 at 600,000 iterations or more', () {
    expect(SeedVault.defaultIterations, greaterThanOrEqualTo(600000));
    final v = SeedVault(crypto: FakeVaultCrypto(), db: db);
    expect(v.iterations, SeedVault.defaultIterations);
  });

  test('create opens the vault; only ciphertext and a key handle persist',
      () async {
    await vault.create('123456');
    expect(vault.isOpen, isTrue);
    await vault.write(key, phrase);
    expect(await vault.read(key), phrase);

    final dump = jsonEncode({'meta': db.meta, 'entries': db.entries});
    expect(dump.contains('abandon'), isFalse);
    expect(dump.contains('123456'), isFalse);
    // The device secret is an opaque handle, never bytes in a record.
    expect(db.deviceSecret, isA<FakeKey>());
    expect(db.meta!['v'], 2);
    expect(db.meta!.containsKey('devIv'), isFalse);
    expect(base64Decode(db.meta!['salt'] as String), hasLength(16));
    expect(db.meta!['iter'], 1000);
  });

  test('fresh 12-byte IVs for every encryption', () async {
    await vault.create('123456');
    await vault.write(key, phrase);
    final iv1 = db.entries[key]!['iv'];
    await vault.write(key, phrase);
    final iv2 = db.entries[key]!['iv'];
    expect(base64Decode(iv1 as String), hasLength(12));
    expect(iv1, isNot(iv2));
    expect(db.entries[key]!['ct'], isNot(iv1));
  });

  test('lock drops the key; a reload is locked; the PIN reopens it', () async {
    await vault.create('123456');
    await vault.write(key, phrase);
    vault.lock();
    expect(vault.isOpen, isFalse);
    expect(() => vault.read(key), throwsA(isA<VaultLockedException>()));
    expect(() => vault.write(key, phrase),
        throwsA(isA<VaultLockedException>()));
    // Names stay visible while locked: they are not secret.
    expect(vault.has(key), isTrue);

    final reloaded = await newVault(db);
    expect(reloaded.exists, isTrue);
    expect(reloaded.isOpen, isFalse);
    expect(await reloaded.unlock('123456'), VaultUnlock.ok);
    expect(await reloaded.read(key), phrase);
  });

  test('a wrong PIN is told apart by the AES-GCM tag and opens nothing',
      () async {
    await vault.create('123456');
    vault.lock();
    expect(await vault.unlock('654321'), VaultUnlock.wrongPin);
    expect(vault.isOpen, isFalse);
    expect(await vault.unlock('123456'), VaultUnlock.ok);
  });

  test('without the device secret the PIN cannot open it (unavailable)',
      () async {
    await vault.create('123456');
    vault.lock();
    db.deviceSecret = null;
    final reloaded = await newVault(db);
    expect(await reloaded.unlock('123456'), VaultUnlock.unavailable);
  });

  test('the right PIN with another device secret fails: guessing needs '
      'this browser', () async {
    await vault.create('123456');
    final other = MemoryVaultDb();
    final otherVault = await newVault(other, crypto: FakeVaultCrypto(seed: 99));
    await otherVault.create('000000');
    // An attacker who copied the record but not the device secret.
    db.deviceSecret = other.deviceSecret;
    final reloaded = await newVault(db);
    expect(await reloaded.unlock('123456'), VaultUnlock.wrongPin);
    expect(reloaded.isOpen, isFalse);
  });

  test('v1 record: migrates to v2 on its first PIN unlock, same vault key',
      () async {
    await vault.debugCreateV1('123456');
    await vault.write(key, phrase);
    expect(db.meta!['v'], 1);
    expect(db.deviceSecret, isNull);

    var reloaded = await newVault(db);
    expect(await reloaded.unlock('000000'), VaultUnlock.wrongPin);
    expect(db.meta!['v'], 1, reason: 'a wrong PIN changes nothing');
    expect(await reloaded.unlock('123456'), VaultUnlock.ok);
    expect(db.meta!['v'], 2);
    expect(db.meta!.containsKey('devIv'), isFalse);
    expect(db.deviceSecret, isA<FakeKey>());
    expect(await reloaded.read(key), phrase);

    reloaded = await newVault(db);
    expect(reloaded.formatVersionOnDisk, 2);
    expect(await reloaded.unlock('000000'), VaultUnlock.wrongPin);
    expect(await reloaded.unlock('123456'), VaultUnlock.ok);
    expect(await reloaded.read(key), phrase);
  });

  test('v1 record: a failed rewrap keeps v1 open and retries next unlock',
      () async {
    final flaky = _FlakyMetaDb();
    final v = await newVault(flaky);
    await v.debugCreateV1('123456');
    await v.write(key, phrase);
    flaky.failMetaWrites = true;
    var reloaded = await newVault(flaky);
    expect(await reloaded.unlock('123456'), VaultUnlock.ok);
    expect(flaky.meta!['v'], 1);
    expect(await reloaded.read(key), phrase);
    flaky.failMetaWrites = false;
    reloaded = await newVault(flaky);
    expect(await reloaded.unlock('123456'), VaultUnlock.ok);
    expect(flaky.meta!['v'], 2);
    expect(await reloaded.read(key), phrase);
  });

  test('records are bound to their name: a swapped ciphertext fails',
      () async {
    await vault.create('123456');
    await vault.write(key, phrase);
    await vault.write('v2:wallet:w2.mnemonic', 'other words');
    db.entries['v2:wallet:w2.mnemonic'] = Map.of(db.entries[key]!);
    final reloaded = await newVault(db);
    await reloaded.unlock('123456');
    expect(() => reloaded.read('v2:wallet:w2.mnemonic'),
        throwsA(isA<VaultTagError>()));
  });

  test('changing the PIN re-wraps: old PIN fails, new PIN reads the seed',
      () async {
    await vault.create('123456');
    await vault.write(key, phrase);
    final oldSalt = db.meta!['salt'];
    await vault.changePin('222222');
    expect(db.meta!['salt'], isNot(oldSalt));

    final reloaded = await newVault(db);
    expect(await reloaded.unlock('123456'), VaultUnlock.wrongPin);
    expect(await reloaded.unlock('222222'), VaultUnlock.ok);
    expect(await reloaded.read(key), phrase);
  });

  test('changing the PIN needs an open vault', () async {
    await vault.create('123456');
    vault.lock();
    expect(() => vault.changePin('222222'),
        throwsA(isA<VaultLockedException>()));
  });

  test('PRF: an enrolled output opens the vault; another output does not',
      () async {
    await vault.create('123456');
    await vault.write(key, phrase);
    final input = Uint8List.fromList(List.filled(32, 1));
    final output = Uint8List.fromList(List.filled(32, 42));
    await vault.enrolPrf('cred-1', input, output);
    expect(vault.prfInputFor('cred-1'), input);
    expect(vault.prfInputFor('cred-2'), isNull);

    final reloaded = await newVault(db);
    expect(await reloaded.unlockWithPrf('cred-1', Uint8List(32)), isFalse);
    expect(await reloaded.unlockWithPrf('cred-2', output), isFalse);
    expect(reloaded.isOpen, isFalse);
    expect(await reloaded.unlockWithPrf('cred-1', output), isTrue);
    expect(await reloaded.read(key), phrase);

    // A PIN change keeps biometrics working (same vault key).
    await reloaded.changePin('333333');
    final again = await newVault(db);
    expect(await again.unlockWithPrf('cred-1', output), isTrue);

    await again.removePrf();
    final last = await newVault(db);
    expect(await last.unlockWithPrf('cred-1', output), isFalse);
  });

  test('delete removes one entry; wipe removes everything and the device key',
      () async {
    await vault.create('123456');
    await vault.write(key, phrase);
    await vault.write('v2:wallet:w2.mnemonic', 'x y');
    await vault.delete(key);
    expect(vault.has(key), isFalse);
    expect(db.entries.containsKey(key), isFalse);

    await vault.wipe();
    expect(db.meta, isNull);
    expect(db.deviceKey, isNull);
    expect(db.deviceSecret, isNull);
    expect(db.entries, isEmpty);
    expect(vault.exists, isFalse);
    expect(vault.isOpen, isFalse);
  });

  test('a reader waiting for unlock resumes on unlock, or on wipe', () async {
    await vault.create('123456');
    vault.lock();
    final opened = vault.whenOpen();
    expect(await vault.unlock('123456'), VaultUnlock.ok);
    expect(await opened, isTrue);

    vault.lock();
    final wiped = vault.whenOpen();
    await vault.wipe();
    expect(await wiped, isFalse);
  });

  test('a new vault over an old one keeps old entries unreadable, not deleted',
      () async {
    await vault.create('123456');
    await vault.write(key, phrase);
    await vault.create('999999');
    expect(vault.has(key), isFalse);
    expect(db.entries.containsKey(key), isTrue);
    expect(await vault.read(key), isNull);
  });
}

class _FlakyMetaDb extends MemoryVaultDb {
  bool failMetaWrites = false;
  @override
  Future<void> writeMeta(Map<String, Object?> m) async {
    if (failMetaWrites) throw StateError('quota');
    return super.writeMeta(m);
  }
}
