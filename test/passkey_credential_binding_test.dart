import 'dart:convert';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/passkey_prf_service.dart';
import 'package:kute/services/passkey_service.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';

import 'services/support/fake_secret_store.dart';

class _Client implements PasskeyClient {
  final requests = <SignInRequest>[];
  Object? error;
  Uint8List credential = Uint8List.fromList([1, 2, 3]);

  @override
  Future<SignInResponse> signIn({required SignInRequest request}) async {
    requests.add(request);
    if (error != null) throw error!;
    return SignInResponse(
      wallet: Wallet(seed: Seed.entropy(Uint8List(32)), label: request.label ?? ''),
      labels: const [],
      credential: PasskeyCredential(credentialId: credential),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.kutewallet.app/passkey_prf');
  const rp = 'keys.breez.technology';
  const label = 'audit-fixture';
  final pinKey = 'prf_credential_id_v1__${sha256.convert(utf8.encode(rp))}';
  final seedKey = 'prf_seed_v1__${sha256.convert(utf8.encode('$rp|$label'))}';
  late FakeKeychain keychain;
  late _Client client;
  late List<MethodCall> calls;

  void native(Future<Object?> Function(MethodCall) body) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return body(call);
    });
  }

  setUp(() {
    keychain = FakeKeychain();
    SecretStores.debugOverride(local: keychain.local, synced: keychain.synced);
    PasskeyPrfService.clearMemory();
    client = _Client();
    PasskeyService.debugSetClient(client);
    calls = [];
    native((_) async => {
          'prf': Uint8List(32),
          'credentialId': Uint8List.fromList([1, 2, 3]),
        });
  });

  tearDown(() {
    PasskeyPrfService.clearMemory();
    PasskeyService.debugSetClient(null);
    SecretStores.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  for (final code in ['CANCELLED', 'PRF_ERROR', 'CREDENTIAL_NOT_FOUND']) {
    test('legacy $code preserves credential and never tries another', () async {
      keychain.seed(pinKey, '010203');
      native((_) async => throw PlatformException(code: code));
      await expectLater(PasskeyPrfService.derivePrfSeed(label),
          throwsA(isA<PlatformException>()));
      expect(calls, hasLength(1));
      expect((calls.single.arguments as Map)['credentialIds'],
          [Uint8List.fromList([1, 2, 3])]);
      expect(keychain.peek(pinKey), '010203');
      expect(keychain.peek(seedKey), isNull);
    });
  }

  test('legacy returned credential mismatch cannot populate seed cache', () async {
    keychain.seed(pinKey, 'aabb');
    await expectLater(PasskeyPrfService.derivePrfSeed(label),
        throwsA(isA<PlatformException>()));
    expect(calls, hasLength(1));
    expect(keychain.peek(pinKey), 'aabb');
    expect(keychain.peek(seedKey), isNull);
  });

  test('legacy storage failure is not mistaken for a missing seed', () async {
    keychain.failRead('local', StateError('locked'), key: seedKey);
    await expectLater(PasskeyPrfService.derivePrfSeed(label), throwsStateError);
    expect(calls, isEmpty);
  });

  test('legacy corrupt stored seed does not trigger replacement derivation', () async {
    keychain.seed(seedKey, 'invalid');
    await expectLater(PasskeyPrfService.derivePrfSeed(label), throwsStateError);
    expect(calls, isEmpty);
    expect(keychain.peek(seedKey), 'invalid');
  });

  test('legacy pin persistence failure cannot publish or cache the seed', () async {
    keychain.failWrite('local', StateError('locked'), key: pinKey);
    for (var attempt = 0; attempt < 2; attempt++) {
      await expectLater(PasskeyPrfService.derivePrfSeed(label), throwsStateError);
      expect(calls, hasLength(attempt + 1));
      expect(keychain.peek(seedKey), isNull);
    }
    keychain.clearFailures();
    expect(await PasskeyPrfService.derivePrfSeed(label), Uint8List(32));
    expect(calls, hasLength(3));
    expect(keychain.peek(pinKey), '010203');
  });

  test('legacy matching credential still derives and caches identical bytes', () async {
    keychain.seed(pinKey, '010203');
    expect(await PasskeyPrfService.derivePrfSeed(label), Uint8List(32));
    expect(await PasskeyPrfService.derivePrfSeed(label), Uint8List(32));
    expect(calls, hasLength(1));
    expect(keychain.peek(seedKey), '00' * 32);
  });

  test('SDK failure preserves pin without a second unpinned sign-in', () async {
    keychain.seed('passkey017_credential_id', '010203');
    client.error = StateError('unavailable');
    await expectLater(PasskeyService.getWallet(label: label, legacy: false),
        throwsStateError);
    expect(client.requests, hasLength(1));
    expect(client.requests.single.allowCredentials, [Uint8List.fromList([1, 2, 3])]);
    expect(keychain.peek('passkey017_credential_id'), '010203');
  });

  test('SDK returned credential mismatch does not replace the pin', () async {
    keychain.seed('passkey017_credential_id', 'aabb');
    await expectLater(PasskeyService.getWallet(label: label, legacy: false),
        throwsStateError);
    expect(client.requests, hasLength(1));
    expect(keychain.peek('passkey017_credential_id'), 'aabb');
  });

  test('SDK credential storage failure cannot open an unpinned picker', () async {
    keychain.failRead('local', StateError('locked'), key: 'passkey017_credential_id');
    await expectLater(PasskeyService.getWallet(label: label, legacy: false),
        throwsStateError);
    expect(client.requests, isEmpty);
  });

  test('SDK pin persistence failure cannot publish a wallet or either cache', () async {
    keychain.failWrite('local', StateError('locked'),
        key: 'passkey017_credential_id');
    for (var attempt = 0; attempt < 2; attempt++) {
      await expectLater(PasskeyService.getWallet(label: label, legacy: false),
          throwsStateError);
      expect(client.requests, hasLength(attempt + 1));
      expect(keychain.keys(), isEmpty);
      expect(keychain.keys(options: FakeStoreOptions.synced), isEmpty);
    }
    keychain.clearFailures();
    await PasskeyService.getWallet(label: label, legacy: false);
    expect(client.requests, hasLength(3));
    expect(keychain.peek('passkey017_credential_id'), '010203');
  });

  test('SDK corrupt cached wallet is not replaced with another derivation', () async {
    keychain.seed('passkey017_credential_id', '010203');
    final cache = 'passkey017_seed_v1__${sha256.convert(utf8.encode('$label|010203'))}';
    keychain.seed(cache, '{invalid');
    await expectLater(PasskeyService.getWallet(label: label, legacy: false),
        throwsFormatException);
    expect(client.requests, isEmpty);
    expect(keychain.peek(cache), '{invalid');
  });
}
