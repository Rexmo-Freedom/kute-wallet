import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kute/services/secure_storage.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/services/onchain/native_onchain_service.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';

import '../services/support/fake_secret_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const phrase =
      'panel custom call awesome sick ready hamster wool patch client reduce clay';

  tearDown(() =>
      messenger.setMockMethodCallHandler(NativeOnchainService.channel, null));

  test('new wallet generation requests twelve words from native BDK', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(NativeOnchainService.channel,
        (call) async {
      calls.add(call);
      expect(call.method, 'mnemonic');
      final args = call.arguments as Map;
      expect(args['action'], 'generate');
      expect(args['wordCount'], 12);
      expect(args.containsKey('entropy'), isFalse);
      return phrase;
    });

    expect(await AuthModel().generateMnemonic(), phrase);
    expect(calls, hasLength(1));
  });

  test('validation passes the phrase unchanged and preserves native validity',
      () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(NativeOnchainService.channel,
        (call) async {
      calls.add(call);
      expect(call.method, 'mnemonic');
      final args = call.arguments as Map;
      expect(args['action'], 'validate');
      return args['mnemonic'] == phrase;
    });

    final auth = AuthModel();
    expect(await auth.validateMnemonic(phrase), isTrue);
    expect(await auth.validateMnemonic('invalid words'), isFalse);
    expect((calls[0].arguments as Map)['mnemonic'], phrase);
    expect((calls[1].arguments as Map)['mnemonic'], 'invalid words');
  });

  test(
      'forgetting one wallet removes both secret schemas and keeps other seeds',
      () async {
    FlutterSecureStorage.setMockInitialValues({
      'mnemonic_removed': 'legacy encrypted fixture',
      'v2:wallet:removed.mnemonic': phrase,
      'v2:wallet:retained.mnemonic': phrase,
      'pin_hash': 'retained-authentication',
    });
    await AuthModel().deleteWalletMnemonic('removed');
    expect(await secureStorage.read(key: 'mnemonic_removed'), isNull);
    expect(await secureStorage.read(key: 'v2:wallet:removed.mnemonic'), isNull);
    expect(
        await secureStorage.read(key: 'v2:wallet:retained.mnemonic'), phrase);
    expect(
        await secureStorage.read(key: 'pin_hash'), 'retained-authentication');
  });

  test('native validation failure cannot admit an unchecked phrase', () async {
    messenger.setMockMethodCallHandler(NativeOnchainService.channel,
        (_) async => throw PlatformException(code: 'internal'));

    expect(await AuthModel().validateMnemonic(phrase), isFalse);
  });

  group('device-local seed copies on iOS Keychain semantics', () {
    late FakeKeychain keychain;

    setUp(() {
      keychain = FakeKeychain();
      SecretStores.debugOverride(
          local: keychain.local, synced: keychain.synced);
      messenger.setMockMethodCallHandler(NativeOnchainService.channel,
          (call) async => (call.arguments as Map)['mnemonic'] == phrase);
    });

    tearDown(SecretStores.debugReset);

    test('a new V2 seed is written with a local-only write', () async {
      keychain.seedSynced('v2:wallet:w1.mnemonic', 'synced residue');
      await AuthModel().setMnemonicV2('w1', phrase);
      expect(keychain.mutations, const [
        FakeMutation('local', 'writeLocalOnly', 'v2:wallet:w1.mnemonic'),
      ]);
      expect(keychain.peekSynced('v2:wallet:w1.mnemonic'), 'synced residue');
    });

    test('forgetting a wallet leaves its synced twins in place', () async {
      keychain.seed('v2:wallet:w1.mnemonic', phrase);
      keychain.seedSynced('v2:wallet:w1.mnemonic', phrase);
      keychain.seed('mnemonic_w1', 'legacy');
      keychain.seedSynced('mnemonic_w1', 'legacy');
      await AuthModel().deleteWalletMnemonic('w1');
      expect(keychain.keys(), isEmpty);
      expect(keychain.keys(options: FakeStoreOptions.synced),
          {'v2:wallet:w1.mnemonic', 'mnemonic_w1'});
    });

    test('a synced V2 copy is returned without writing a local one', () async {
      keychain.seedSynced('v2:wallet:w1.mnemonic', phrase);
      expect(await AuthModel().getMnemonicV2('w1'), phrase);
      expect(keychain.mutations, isEmpty);
    });

    test('a failed local read surfaces instead of reading as missing',
        () async {
      keychain.seedSynced('v2:wallet:w1.mnemonic', phrase);
      keychain.failRead('local', PlatformException(code: 'x', details: -25308),
          key: 'v2:wallet:w1.mnemonic');
      await expectLater(
          AuthModel().getMnemonicV2('w1'), throwsA(isA<PlatformException>()));
    });
  });
}
