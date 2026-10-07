import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/services/secure/secret_error_class.dart';
import 'package:kute/services/secure/secret_store.dart';
import 'package:kute/services/secure/storage_bootstrap.dart';

import '../support/fake_secret_store.dart';

class _RecordingStore implements SecretStore {
  _RecordingStore(this.inner);
  final SecretStore inner;
  final reads = <String>[];

  @override
  Future<SecretRead> read({required String key}) {
    reads.add(key);
    return inner.read(key: key);
  }

  @override
  Future<void> write({required String key, required String value}) =>
      inner.write(key: key, value: value);
  @override
  Future<void> writeLocalOnly({required String key, required String value}) =>
      inner.writeLocalOnly(key: key, value: value);
  @override
  Future<void> delete({required String key}) => inner.delete(key: key);
  @override
  Future<void> deleteLocalOnly({required String key}) =>
      inner.deleteLocalOnly(key: key);
  @override
  Future<void> deleteAllLocalOnly() => inner.deleteAllLocalOnly();
  @override
  Future<bool> containsKey({required String key}) =>
      inner.containsKey(key: key);
}

final temporary = PlatformException(code: 'x', details: -25308);
final definitive = PlatformException(code: 'x', details: -26275);

void main() {
  late FakeKeychain keychain;
  late _RecordingStore store;
  late Directory hiveDir;
  late Box box;

  StorageBootstrap bootstrap() => StorageBootstrap(
        store: store,
        settingsBox: () => Hive.openBox('settings'),
        isCupertino: true,
      );

  setUp(() async {
    StorageBootstrap.debugResetProcess();
    keychain = FakeKeychain();
    store = _RecordingStore(keychain.local);
    hiveDir = await Directory.systemTemp.createTemp('storage_bootstrap');
    Hive.init(hiveDir.path);
    box = await Hive.openBox('settings');
  });

  tearDown(() async {
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  Future<StorageBootState> classify({bool hasWallets = true}) async =>
      (await bootstrap().classify(hasWallets: hasWallets)).state;

  group('classification matrix', () {
    test('no wallets is fresh and reads nothing', () async {
      keychain.failRead('local', definitive);
      expect(await classify(hasWallets: false), StorageBootState.fresh);
      expect(store.reads, isEmpty);
      expect(box.get(StorageBootstrap.failStartsKey), isNull);
    });

    test('reads the binding, pin_hash and pin in that order', () async {
      keychain.seed('pin_hash', 'hash');
      await classify();
      expect(store.reads, ['kute.binding.v1', 'pin_hash', 'pin']);
    });

    test('preBinding writes the same new id to both places, then ok', () async {
      keychain.seed('pin_hash', 'hash');
      expect(await classify(), StorageBootState.preBinding);
      final secure = keychain.peek(StorageBootstrap.bindingKey);
      expect(secure, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(box.get(StorageBootstrap.hiveBindingKey), secure);
      expect(await classify(), StorageBootState.ok);
    });

    test('equal bindings are ok and write nothing', () async {
      keychain
        ..seed('pin_hash', 'hash')
        ..seed(StorageBootstrap.bindingKey, 'abc');
      await box.put(StorageBootstrap.hiveBindingKey, 'abc');
      expect(await classify(), StorageBootState.ok);
      expect(keychain.mutations, isEmpty);
    });

    test('a legacy plaintext pin counts as PIN material', () async {
      keychain.seed('pin', '123456');
      expect(await classify(), StorageBootState.preBinding);
    });

    test('a missing Hive binding is copied from secure storage', () async {
      keychain
        ..seed('pin_hash', 'hash')
        ..seed(StorageBootstrap.bindingKey, 'abc');
      expect(await classify(), StorageBootState.hiveRestoredOld);
      expect(box.get(StorageBootstrap.hiveBindingKey), 'abc');
      expect(keychain.mutations, isEmpty);
      expect(await classify(), StorageBootState.ok);
    });

    test('different bindings are a mismatch and nothing is written', () async {
      keychain
        ..seed('pin_hash', 'hash')
        ..seed(StorageBootstrap.bindingKey, 'abc');
      await box.put(StorageBootstrap.hiveBindingKey, 'def');
      expect(await classify(), StorageBootState.bindingMismatch);
      expect(keychain.mutations, isEmpty);
      expect(box.get(StorageBootstrap.hiveBindingKey), 'def');
    });

    test('a Hive binding without a secure binding is a mismatch', () async {
      keychain.seed('pin_hash', 'hash');
      await box.put(StorageBootstrap.hiveBindingKey, 'def');
      expect(await classify(), StorageBootState.bindingMismatch);
      expect(keychain.mutations, isEmpty);
    });

    test('wallets without pin_hash and pin are secretsMissing', () async {
      keychain.seed(StorageBootstrap.bindingKey, 'abc');
      await box.put(StorageBootstrap.hiveBindingKey, 'abc');
      expect(await classify(), StorageBootState.secretsMissing);
      expect(keychain.mutations, isEmpty);
    });
  });

  group('storage failures', () {
    for (final key in ['kute.binding.v1', 'pin_hash', 'pin']) {
      test('a failed read of $key is storageUnavailable and writes nothing',
          () async {
        keychain
          ..seed('pin_hash', 'hash')
          ..failRead('local', temporary, key: key);
        final result = await bootstrap().classify(hasWallets: true);
        expect(result.state, StorageBootState.storageUnavailable);
        expect(result.errorClass, SecretErrorClass.interactionNotAllowed);
        expect(result.offerRestore, isFalse);
        expect(keychain.mutations, isEmpty);
        expect(box.get(StorageBootstrap.hiveBindingKey), isNull);
      });
    }

    test('temporary failures never count toward Restore wallets', () async {
      keychain.failRead('local', temporary, key: 'pin_hash');
      for (var i = 0; i < 4; i++) {
        StorageBootstrap.debugResetProcess();
        final result = await bootstrap().classify(hasWallets: true);
        expect(result.failStarts, 0);
      }
    });

    test('three cold starts with a definitive class offer Restore wallets',
        () async {
      keychain.failRead('local', definitive, key: 'pin_hash');
      final results = <StorageBootResult>[];
      for (var i = 0; i < 3; i++) {
        StorageBootstrap.debugResetProcess();
        results.add(await bootstrap().classify(hasWallets: true));
        results.add(await bootstrap().classify(hasWallets: true));
      }
      expect(results.map((r) => r.failStarts), [1, 1, 2, 2, 3, 3],
          reason: 'a retry in the same process is not a cold start');
      expect(results.last.offerRestore, isTrue);
      expect(results.last.errorClass, SecretErrorClass.decode);
      expect(keychain.mutations, isEmpty);
    });

    test('a readable start clears the failure count', () async {
      await box.put(StorageBootstrap.failStartsKey, 2);
      keychain.seed('pin_hash', 'hash');
      await classify();
      expect(box.get(StorageBootstrap.failStartsKey), isNull);
    });

    test('a failed binding write still routes as preBinding', () async {
      keychain
        ..seed('pin_hash', 'hash')
        ..failWrite('local', temporary);
      expect(await classify(), StorageBootState.preBinding);
      expect(box.get(StorageBootstrap.hiveBindingKey), isNull);
    });
  });

  test('onboarding writes a new binding to both places', () async {
    await box.put(StorageBootstrap.hiveBindingKey, 'old');
    keychain.seed(StorageBootstrap.bindingKey, 'old');
    await bootstrap().writeNewBinding();
    final first = keychain.peek(StorageBootstrap.bindingKey);
    expect(first, isNot('old'));
    expect(box.get(StorageBootstrap.hiveBindingKey), first);
    await bootstrap().writeNewBinding();
    expect(keychain.peek(StorageBootstrap.bindingKey), isNot(first));
  });

  group('protected data', () {
    test('waits for protected data before anything is read', () async {
      var available = false;
      final changes = StreamController<bool>.broadcast();
      addTearDown(changes.close);
      final boot = StorageBootstrap(
        store: store,
        settingsBox: () => Hive.openBox('settings'),
        isCupertino: true,
        isProtectedDataAvailable: () async => available,
        protectedDataChanges: () => changes.stream,
        protectedDataPoll: const Duration(hours: 1),
      );
      var done = false;
      final wait = boot.waitForProtectedData().then((waited) {
        done = true;
        return waited;
      });
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse);
      expect(store.reads, isEmpty);
      available = true;
      changes.add(true);
      expect(await wait, isTrue);
    });

    test('returns at once when available or off iOS', () async {
      expect(
          await StorageBootstrap(
            store: store,
            isCupertino: true,
            isProtectedDataAvailable: () async => true,
          ).waitForProtectedData(),
          isFalse);
      expect(
          await StorageBootstrap(
            store: store,
            isCupertino: false,
            isProtectedDataAvailable: () async => false,
          ).waitForProtectedData(),
          isFalse);
    });
  });
}
