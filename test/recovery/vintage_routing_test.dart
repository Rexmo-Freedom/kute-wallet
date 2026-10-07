import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/services/onchain/native_onchain_service.dart';
import 'package:kute/services/passkey_prf_service.dart';
import 'package:kute/services/passkey_service.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/services/secure/seed_access.dart';

import '../fixtures/native_bdk/fixture_bundle.dart';
import '../services/support/fake_secret_store.dart';

const rpId = 'keys.breez.technology';
const entropyHex = '9f86d081884c7d659a2feaa0c55ad015';
const prfHex = '${entropyHex}a3bf4f1b2b0b822cd15d6c15b0f00a08';
const legacyMnemonic =
    'panel custom call awesome sick ready hamster wool patch client reduce clay';
const sdkMnemonic = 'zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong';
const unlockedSession = SeedSession(unlocked: true);
const storedMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

Uint8List hexBytes(String hex) => Uint8List.fromList([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);

String prfKey(String salt) =>
    'prf_seed_v1__${sha256.convert(utf8.encode('$rpId|$salt'))}';

void seedSdkCache(FakeKeychain keychain, String label, String mnemonic) {
  const credentialHex = '0a0b0c';
  keychain.seed('passkey017_credential_id', credentialHex);
  keychain.seed(
    'passkey017_seed_v1__'
    '${sha256.convert(utf8.encode('$label|$credentialHex'))}',
    jsonEncode({
      'label': label,
      'seed': jsonEncode({'t': 'm', 'm': mnemonic, 'p': null}),
    }),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const prfChannel = MethodChannel('com.kutewallet.app/passkey_prf');
  final fixtureMnemonic = ((jsonDecode(nativeBdkFixtureJson)['entropy'] as List)
      .cast<Map<String, dynamic>>()
      .singleWhere((e) => e['hex'] == entropyHex))['mnemonic'] as String;
  late FakeKeychain keychain;
  late Directory hiveDir;
  late List<MethodCall> ceremonies;

  setUp(() async {
    keychain = FakeKeychain();
    SecretStores.debugOverride(local: keychain.local, synced: keychain.synced);
    PasskeyPrfService.clearMemory();
    PasskeyService.clearSession();
    hiveDir = await Directory.systemTemp.createTemp('vintage_routing');
    Hive.init(hiveDir.path);
    ceremonies = [];
    messenger.setMockMethodCallHandler(prfChannel, (call) async {
      ceremonies.add(call);
      return {
        'prf': hexBytes(prfHex),
        'credentialId': Uint8List.fromList([9, 9]),
      };
    });
    messenger.setMockMethodCallHandler(NativeOnchainService.channel,
        (call) async {
      final args = call.arguments as Map;
      if (args['action'] == 'validate') return true;
      expect(args['action'], 'fromEntropy');
      expect(args['entropy'], orderedEquals(hexBytes(entropyHex)));
      return fixtureMnemonic;
    });
  });

  tearDown(() async {
    SecretStores.debugReset();
    PasskeyPrfService.clearMemory();
    PasskeyService.clearSession();
    messenger.setMockMethodCallHandler(prfChannel, null);
    messenger.setMockMethodCallHandler(NativeOnchainService.channel, null);
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  test('the vintage literals are frozen', () {
    expect(PasskeyService.vintageBreez017, 'breez-0.17');
    expect(PasskeyService.vintageLegacy, '0.15.1');
  });

  test('WalletConfig keeps the stored vintage exactly', () {
    final legacy = WalletConfig(
        id: 'a', name: 'A', isPasskey: true, passkeyLabel: 'Default');
    final sdk = WalletConfig(
        id: 'b',
        name: 'B',
        isPasskey: true,
        passkeyLabel: 'B · 1',
        passkeyProvider: 'breez-0.17');
    expect(WalletConfig.fromMap(legacy.toMap()).passkeyProvider, isNull);
    expect(WalletConfig.fromMap(sdk.toMap()).passkeyProvider, 'breez-0.17');
    final oldBuildMap = Map<String, dynamic>.from(legacy.toMap())
      ..remove('passkeyProvider');
    expect(WalletConfig.fromMap(oldBuildMap).passkeyProvider, isNull);
  });

  test('a null vintage derives through the legacy PRF pipeline', () async {
    seedSdkCache(keychain, 'L', sdkMnemonic);
    final wallet =
        WalletConfig(id: 'p1', name: 'P', isPasskey: true, passkeyLabel: 'L');

    expect(
        await resolveBip39MnemonicFor(wallet,
            access: SeedAccess.automatic, session: unlockedSession),
        legacyMnemonic);

    expect(ceremonies, hasLength(1));
    expect(ceremonies.single.method, 'derivePrfSeed');
    expect((ceremonies.single.arguments as Map)['salt'], 'L');
    expect((ceremonies.single.arguments as Map)['rpId'], rpId);
    expect(keychain.peek(prfKey('L')), prfHex);
    // No recovery manifest: a legacy derive writes nothing to iCloud.
    expect(keychain.keys(options: FakeStoreOptions.synced), isEmpty);
  });

  test('a null vintage without a label uses the Default salt', () async {
    final wallet = WalletConfig(id: 'p1', name: 'P', isPasskey: true);
    expect(
        await resolveBip39MnemonicFor(wallet,
            access: SeedAccess.automatic, session: unlockedSession),
        legacyMnemonic);
    expect((ceremonies.single.arguments as Map)['salt'], 'Default');
  });

  test('breez-0.17 derives through the SDK wallet path, never the PRF channel',
      () async {
    keychain.seed(prfKey('L'), prfHex);
    seedSdkCache(keychain, 'L', sdkMnemonic);
    final wallet = WalletConfig(
        id: 'p2',
        name: 'P',
        isPasskey: true,
        passkeyLabel: 'L',
        passkeyProvider: 'breez-0.17');

    expect(
        await resolveBip39MnemonicFor(wallet,
            access: SeedAccess.automatic, session: unlockedSession),
        sdkMnemonic);
    expect(ceremonies, isEmpty);
  });

  test('the SDK wallet path refuses legacy wallets', () async {
    await expectLater(PasskeyService.getWallet(label: 'L', legacy: true),
        throwsArgumentError);
  });

  test('stored wallets read the stored seed and never a passkey', () async {
    keychain.seed('v2:wallet:w1.mnemonic', storedMnemonic);
    keychain.seed(prfKey('Default'), prfHex);
    final wallet = WalletConfig(id: 'w1', name: 'W');
    expect(
        await resolveBip39MnemonicFor(wallet,
            access: SeedAccess.automatic, session: unlockedSession),
        storedMnemonic);
    expect(ceremonies, isEmpty);
  });
}
