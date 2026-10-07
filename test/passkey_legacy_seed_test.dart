// The legacy passkey wallet contract: first 16 PRF bytes become a 12-word
// mnemonic with no passphrase. Native conversion uses the captured pre-migration
// fixture; these tests verify Dart routing without loading the old FFI library.

import 'dart:convert';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/onchain/native_onchain_service.dart';
import 'package:kute/services/passkey_prf_service.dart';
import 'package:kute/services/passkey_service.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';

import 'fixtures/native_bdk/fixture_bundle.dart';
import 'services/support/fake_secret_store.dart';

Uint8List _hexToBytes(String hex) => Uint8List.fromList([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const entropyHex = '9f86d081884c7d659a2feaa0c55ad015';
  const prfHex = '${entropyHex}a3bf4f1b2b0b822cd15d6c15b0f00a08';
  const goldenMnemonic =
      'panel custom call awesome sick ready hamster wool patch client reduce clay';
  final fixture = (jsonDecode(nativeBdkFixtureJson)['entropy'] as List)
      .cast<Map<String, dynamic>>()
      .singleWhere((entry) => entry['hex'] == entropyHex);
  final calls = <MethodCall>[];

  void setHandler(Future<Object?> Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeOnchainService.channel, (call) {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(() {
    calls.clear();
    setHandler((call) async {
      expect(call.method, 'mnemonic');
      final args = call.arguments as Map;
      expect(args['action'], 'fromEntropy');
      expect(args['entropy'], isA<Uint8List>());
      expect(args['entropy'], orderedEquals(_hexToBytes(entropyHex)));
      return fixture['mnemonic'];
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeOnchainService.channel, null);
  });

  test(
      'legacy PRF reconstruction preserves the captured phrase and null passphrase',
      () async {
    expect(fixture['mnemonic'], goldenMnemonic);
    final seed = await PasskeyService.seedFromPrfBytes(_hexToBytes(prfHex));

    expect(seed, isA<Seed_Mnemonic>());
    final mnemonicSeed = seed as Seed_Mnemonic;
    expect(mnemonicSeed.mnemonic, goldenMnemonic);
    expect(mnemonicSeed.mnemonic.split(' '), hasLength(12));
    expect(mnemonicSeed.passphrase, isNull);
    expect(calls, hasLength(1));
  });

  test('only the first 16 PRF bytes reach native conversion', () async {
    final prf = _hexToBytes(prfHex);
    final differentTail = Uint8List.fromList(prf);
    for (var i = 16; i < differentTail.length; i++) {
      differentTail[i] ^= 0xff;
    }

    final first = await PasskeyService.seedFromPrfBytes(prf) as Seed_Mnemonic;
    final second =
        await PasskeyService.seedFromPrfBytes(differentTail) as Seed_Mnemonic;
    expect(first.mnemonic, goldenMnemonic);
    expect(second.mnemonic, goldenMnemonic);
    expect(calls, hasLength(2));
  });

  test('short PRF output fails before invoking native code', () async {
    await expectLater(
        PasskeyService.seedFromPrfBytes(Uint8List(15)), throwsArgumentError);
    expect(calls, isEmpty);
  });

  test(
      'native legacy conversion failures propagate instead of deriving another seed',
      () async {
    setHandler((_) async => throw PlatformException(code: 'internal'));

    await expectLater(PasskeyService.seedFromPrfBytes(_hexToBytes(prfHex)),
        throwsA(isA<OnchainException>()));
    expect(calls, hasLength(1));
  });

  test('an existing mnemonic is returned unchanged without conversion',
      () async {
    final seed =
        Seed.mnemonic(mnemonic: goldenMnemonic, passphrase: 'preserved');
    expect(await PasskeyService.mnemonicOfSeed(seed), goldenMnemonic);
    expect((seed as Seed_Mnemonic).passphrase, 'preserved');
    expect(calls, isEmpty);
  });

  test('nonlegacy entropy conversion forwards the entire seed', () async {
    final entropy = _hexToBytes(prfHex);
    const nativeResult = 'native entropy conversion result';
    setHandler((call) async {
      expect(call.method, 'mnemonic');
      final args = call.arguments as Map;
      expect(args['action'], 'fromEntropy');
      expect(args['entropy'], orderedEquals(entropy));
      expect((args['entropy'] as Uint8List).length, 32);
      return nativeResult;
    });

    expect(await PasskeyService.mnemonicOfSeed(Seed.entropy(entropy)),
        nativeResult);
    expect(calls, hasLength(1));
  });

  test('unrepresentable entropy remains a null mnemonic', () async {
    setHandler((_) async => throw PlatformException(code: 'invalid_request'));
    expect(await PasskeyService.mnemonicOfSeed(Seed.entropy(Uint8List(15))),
        isNull);
    expect(calls, hasLength(1));
  });

  group('persisted seed tiers', () {
    const prfChannel = MethodChannel('com.kutewallet.app/passkey_prf');
    const rpId = 'keys.breez.technology';
    late FakeKeychain keychain;
    late List<MethodCall> ceremonies;

    String prfKey(String salt) =>
        'prf_seed_v1__${sha256.convert(utf8.encode('$rpId|$salt'))}';

    setUp(() {
      keychain = FakeKeychain();
      SecretStores.debugOverride(
          local: keychain.local, synced: keychain.synced);
      PasskeyPrfService.clearMemory();
      PasskeyService.clearSession();
      ceremonies = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(prfChannel, (call) async {
        ceremonies.add(call);
        throw PlatformException(code: 'unexpected_ceremony');
      });
    });

    tearDown(() {
      SecretStores.debugReset();
      PasskeyPrfService.clearMemory();
      PasskeyService.clearSession();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(prfChannel, null);
    });

    test(
        'a device-local PRF copy under the frozen key rebuilds the legacy seed '
        'without a ceremony', () async {
      keychain.seed(prfKey('Default'), prfHex);
      final seed = await PasskeyService.getLegacySeed() as Seed_Mnemonic;
      expect(seed.mnemonic, goldenMnemonic);
      expect(seed.passphrase, isNull);
      expect(ceremonies, isEmpty);
      // No recovery manifest: the derive writes nothing to iCloud.
      expect(keychain.keys(options: FakeStoreOptions.synced), isEmpty);
    });

    test('a synced legacy PRF copy rebuilds the same seed and stays remote',
        () async {
      keychain.seedSynced(prfKey('Default'), prfHex);
      final seed =
          await PasskeyService.getLegacySeed(label: 'Default') as Seed_Mnemonic;
      expect(seed.mnemonic, goldenMnemonic);
      expect(ceremonies, isEmpty);
      expect(keychain.peek(prfKey('Default')), isNull);
    });

    test('a breez-0.17 wallet resolves from the frozen seed cache key',
        () async {
      const label = 'Spending Wallet · 1700000000000';
      const credentialHex = 'c0ffee';
      keychain.seed('passkey017_credential_id', credentialHex);
      keychain.seed(
        'passkey017_seed_v1__'
        '${sha256.convert(utf8.encode('$label|$credentialHex'))}',
        jsonEncode({
          'label': label,
          'seed': jsonEncode({'t': 'm', 'm': goldenMnemonic, 'p': 'kept'}),
        }),
      );
      final wallet =
          await PasskeyService.getWallet(label: label, legacy: false);
      final seed = wallet.seed as Seed_Mnemonic;
      expect(seed.mnemonic, goldenMnemonic);
      expect(seed.passphrase, 'kept');
      expect(wallet.label, label);
      expect(ceremonies, isEmpty);
      expect(calls, isEmpty);
    });
  });
}
