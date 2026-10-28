// A plugin write that collides with an item a 1.x build stored under
// another Keychain accessibility (`errSecDuplicateItem`, -25299) is retried
// once as an in-place local-only update instead of surfacing as a
// PlatformException. Any other failure is rethrown unchanged.

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/services/secure/keychain_local.dart';

class _FailingStorage extends FlutterSecureStorage {
  const _FailingStorage(this.error);
  final Object error;

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      throw error;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  final duplicate = PlatformException(
      code: 'Unexpected security result code',
      message: 'The specified item already exists in the keychain.',
      details: -25299);

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(KeychainLocal.channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(
      () => messenger.setMockMethodCallHandler(KeychainLocal.channel, null));

  test('errSecDuplicateItem is retried as an in-place local-only update',
      () async {
    final store = FlutterSecretStore(_FailingStorage(duplicate),
        localOnly: const KeychainLocal(platform: TargetPlatform.iOS));
    await store.write(key: 'reviewDone', value: 'true');
    expect(calls.map((c) => c.method), ['writeLocalOnly']);
    final args = calls.single.arguments as Map;
    expect(args['account'], 'reviewDone');
    expect(args['value'], 'true');
  });

  test('other failures are rethrown', () async {
    final error = PlatformException(code: 'x', details: -25308);
    final store = FlutterSecretStore(_FailingStorage(error),
        localOnly: const KeychainLocal(platform: TargetPlatform.iOS));
    await expectLater(
        store.write(key: 'k', value: 'v'), throwsA(same(error)));
    expect(calls, isEmpty);
  });

  test('the synced store has no local-only retry', () async {
    final store = FlutterSecretStore(_FailingStorage(duplicate));
    await expectLater(
        store.write(key: 'k', value: 'v'), throwsA(same(duplicate)));
    expect(calls, isEmpty);
  });
}
