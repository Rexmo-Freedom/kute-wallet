import 'dart:async';
import 'dart:io';
import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/services/onchain/native_onchain_service.dart';
import 'package:kute/services/passkey_prf_service.dart';
import 'package:kute/services/passkey_service.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/services/secure/secret_store.dart';
import 'services/support/fake_secret_store.dart';

class _Client implements PasskeyClient {
  final pending = <Completer<SignInResponse>>[];
  Completer<RegisterResponse>? registration;
  @override
  Future<SignInResponse> signIn({required SignInRequest request}) {
    final response = Completer<SignInResponse>();
    pending.add(response);
    return response.future;
  }

  @override
  Future<RegisterResponse> register({required RegisterRequest request}) =>
      (registration ??= Completer<RegisterResponse>()).future;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _DelayedStore implements SecretStore {
  _DelayedStore(this.inner);
  final SecretStore inner;
  final entered = Completer<void>();
  final release = Completer<void>();
  bool deleted = false;
  @override
  Future<void> writeLocalOnly(
      {required String key, required String value}) async {
    if (key.startsWith('passkey017_seed_') || key.startsWith('prf_seed_')) {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    }
    await inner.writeLocalOnly(key: key, value: value);
  }

  @override
  Future<SecretRead> read({required String key}) => inner.read(key: key);
  @override
  Future<void> write({required String key, required String value}) =>
      inner.write(key: key, value: value);
  @override
  Future<void> delete({required String key}) => inner.delete(key: key);
  @override
  Future<void> deleteLocalOnly({required String key}) =>
      inner.deleteLocalOnly(key: key);
  @override
  Future<void> deleteAllLocalOnly() async {
    deleted = true;
    await inner.deleteAllLocalOnly();
  }

  @override
  Future<bool> containsKey({required String key}) =>
      inner.containsKey(key: key);
}

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue);
}

SignInResponse _response(int byte) => SignInResponse(
      wallet: Wallet(
          seed: Seed.entropy(Uint8List.fromList(List.filled(32, byte))),
          label: 'wallet'),
      labels: const [],
      credential:
          PasskeyCredential(credentialId: Uint8List.fromList([1, 2, 3])),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.kutewallet.app/passkey_prf');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late FakeKeychain keychain;
  late _Client client;
  late Directory directory;
  late List<Completer<Object?>> native;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('passkey-cancellation');
    Hive.init(directory.path);
    keychain = FakeKeychain();
    SecretStores.debugOverride(local: keychain.local, synced: keychain.synced);
    PasskeyPrfService.clearMemory();
    client = _Client();
    PasskeyService.debugSetClient(client);
    native = [];
    messenger.setMockMethodCallHandler(channel, (_) {
      final response = Completer<Object?>();
      native.add(response);
      return response.future;
    });
  });
  tearDown(() async {
    PasskeyPrfService.clearMemory();
    PasskeyService.debugSetClient(null);
    SecretStores.debugReset();
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(NativeOnchainService.channel, null);
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test(
      'cleared SDK ceremony cannot publish or remove a newer in-flight ceremony',
      () async {
    final old = PasskeyService.getWallet(label: 'wallet', legacy: false);
    await _until(() => client.pending.length == 1);
    final rejected = expectLater(old, throwsStateError);
    PasskeyService.clearSession();
    final current = PasskeyService.getWallet(label: 'wallet', legacy: false);
    await _until(() => client.pending.length == 2);
    client.pending[0].complete(_response(1));
    await rejected;
    expect(keychain.keys(), isEmpty);
    final coalesced = PasskeyService.getWallet(label: 'wallet', legacy: false);
    await Future<void>.delayed(Duration.zero);
    expect(client.pending, hasLength(2));
    client.pending[1].complete(_response(2));
    expect(await current, same(await coalesced));
    final wallet =
        await PasskeyService.getWallet(label: 'wallet', legacy: false);
    expect((wallet.seed as Seed_Entropy).field0, List.filled(32, 2));
  });

  test('cleared legacy ceremony cannot publish or remove a newer derivation',
      () async {
    final old = PasskeyPrfService.derivePrfSeed('wallet');
    await _until(() => native.length == 1);
    final rejected = expectLater(old, throwsStateError);
    PasskeyPrfService.clearMemory();
    final current = PasskeyPrfService.derivePrfSeed('wallet');
    await _until(() => native.length == 2);
    native[0].complete({
      'prf': Uint8List(32),
      'credentialId': Uint8List.fromList([1])
    });
    await rejected;
    expect(keychain.keys(), isEmpty);
    final coalesced = PasskeyPrfService.derivePrfSeed('wallet');
    await Future<void>.delayed(Duration.zero);
    expect(native, hasLength(2));
    native[1].complete({
      'prf': Uint8List.fromList(List.filled(32, 2)),
      'credentialId': Uint8List.fromList([2])
    });
    expect(await current, List.filled(32, 2));
    expect(await coalesced, List.filled(32, 2));
  });

  test('cleared registration cannot write a credential pin or cache', () async {
    final pending = PasskeyService.createWallet(label: 'wallet');
    await _until(() => client.registration != null);
    final rejected = expectLater(pending, throwsStateError);
    PasskeyService.clearSession();
    client.registration!.complete(RegisterResponse(
      wallet: _response(1).wallet,
      credential:
          PasskeyCredential(credentialId: Uint8List.fromList([1, 2, 3])),
    ));
    await rejected;
    expect(keychain.keys(), isEmpty);
    expect(keychain.keys(options: FakeStoreOptions.synced), isEmpty);
  });

  test('registration cannot publish a wallet when its credential write fails',
      () async {
    keychain.failWrite('local', StateError('locked'),
        key: 'passkey017_credential_id');
    final registration = PasskeyService.createWallet(label: 'wallet');
    final rejected = expectLater(registration, throwsStateError);
    await _until(() => client.registration != null);
    client.registration!.complete(RegisterResponse(
      wallet: _response(1).wallet,
      credential:
          PasskeyCredential(credentialId: Uint8List.fromList([1, 2, 3])),
    ));
    await rejected;
    expect(keychain.keys(), isEmpty);
    expect(keychain.keys(options: FakeStoreOptions.synced), isEmpty);
    // A subsequent lookup must perform its own ceremony, not reuse the
    // failed registration's wallet in memory.
    final next = PasskeyService.getWallet(label: 'wallet', legacy: false);
    final nextRejected = expectLater(next, throwsStateError);
    await _until(() => client.pending.length == 1);
    client.pending.single.complete(_response(1));
    await nextRejected;
  });

  test('clearing during native conversion cannot return a mnemonic', () async {
    final conversion = Completer<Object?>();
    var converting = false;
    messenger.setMockMethodCallHandler(NativeOnchainService.channel, (_) {
      converting = true;
      return conversion.future;
    });
    final mnemonic = PasskeyService.getMnemonic(label: 'wallet', legacy: false);
    await _until(() => client.pending.length == 1);
    client.pending.single.complete(_response(1));
    await _until(() => converting);
    PasskeyService.clearSession();
    conversion.complete('public fixture phrase');
    expect(await mnemonic, isNull);
  });

  for (final sdk in [false, true]) {
    test(
        'wipe drains an already started ${sdk ? 'SDK' : 'legacy'} seed write before deletion',
        () async {
      final store = _DelayedStore(keychain.local);
      SecretStores.debugOverride(local: store, synced: keychain.synced);
      final Future<Object> derive;
      if (sdk) {
        derive = PasskeyService.getWallet(label: 'wallet', legacy: false);
        await _until(() => client.pending.length == 1);
        client.pending.single.complete(_response(1));
      } else {
        derive = PasskeyPrfService.derivePrfSeed('wallet');
        await _until(() => native.length == 1);
        native.single.complete({
          'prf': Uint8List(32),
          'credentialId': Uint8List.fromList([1])
        });
      }
      await store.entered.future;
      final rejected = expectLater(derive, throwsStateError);
      final wipe = AuthModel(store: store, syncedStore: keychain.synced)
          .deleteAuthentication();
      await Future<void>.delayed(Duration.zero);
      expect(store.deleted, isFalse);
      store.release.complete();
      await rejected;
      await wipe;
      expect(store.deleted, isTrue);
      expect(keychain.keys(), isEmpty);
    });
  }
}
