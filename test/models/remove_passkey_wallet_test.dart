// Removing a passkey wallet forgets the seed this device derived for it:
// the 0.17 seed cache entries under its label and the legacy PRF seed for
// its salt. The other wallet's entries, the credential pins and the
// passkey registry stay, and adding the wallet back runs a ceremony.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/services/passkey_prf_service.dart';
import 'package:kute/services/passkey_service.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';

import '../services/support/fake_secret_store.dart';

const phrase =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const credHex = '010203';
const rp = 'keys.breez.technology';

String seedCacheKey(String label, [String cred = credHex]) =>
    'passkey017_seed_v1__${sha256.convert(utf8.encode('$label|$cred'))}';
String prfKey(String salt) =>
    'prf_seed_v1__${sha256.convert(utf8.encode('$rp|$salt'))}';
final legacyPinKey =
    'prf_credential_id_v1__${sha256.convert(utf8.encode(rp))}';

class _Client implements PasskeyClient {
  int signIns = 0;

  @override
  Future<SignInResponse> signIn({required SignInRequest request}) async {
    signIns++;
    return SignInResponse(
      wallet: Wallet(
        seed: Seed.mnemonic(mnemonic: phrase, passphrase: null),
        label: request.label ?? 'Default',
      ),
      labels: const [],
      credential:
          PasskeyCredential(credentialId: Uint8List.fromList([1, 2, 3])),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Settings _settings(List<WalletConfig> wallets, String active) => Settings(
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: false,
      balancePrivacy: 0,
      biometricsEnabled: true,
      bitcoinElectrumNode: 'bitcoin-mainnet.blockstream.info:50002',
      nodeType: 'Blockstream',
      reviewDone: false,
      themeMode: 'dark',
      wallets: wallets,
      activeWalletId: active,
    );

WalletConfig _passkey(String id, String? label, {String? provider}) =>
    WalletConfig(
      id: id,
      name: id,
      sparkEnabled: true,
      isPasskey: true,
      passkeyLabel: label,
      passkeyProvider: provider,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeKeychain keychain;
  late Directory hiveDir;
  late _Client client;

  final a = _passkey('A', 'A · 1', provider: 'breez-0.17');
  final b = _passkey('B', 'B · 2', provider: 'breez-0.17');

  /// Device-level and other-wallet items removing A must never touch.
  final keep = {
    seedCacheKey('B · 2'): 'seed-b',
    prfKey('B · 2'): 'aa' * 32,
    'passkey017_credential_id': credHex,
    legacyPinKey: 'ffff',
    'passkey_registered_v1': '1',
    'pin_hash': 'salt:hash',
  };

  Future<void> seedRecords(List<WalletConfig> wallets) async {
    final box = await Hive.openBox('settings');
    await box.put('wallets', wallets.map((w) => w.toMap()).toList());
    await box.put('activeWalletId', wallets.first.id);
  }

  setUp(() async {
    keychain = FakeKeychain();
    SecretStores.debugOverride(local: keychain.local, synced: keychain.synced);
    for (final e in keep.entries) {
      keychain.seed(e.key, e.value);
    }
    keychain.seedSynced('passkey_registered_v1', '1');
    PasskeyPrfService.clearMemory();
    hiveDir = await Directory.systemTemp.createTemp('remove_passkey');
    Hive.init(hiveDir.path);
    client = _Client();
    PasskeyService.debugSetClient(client);
  });

  tearDown(() async {
    PasskeyService.debugSetClient(null);
    PasskeyPrfService.clearMemory();
    SecretStores.debugReset();
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  test('removing A forgets A\'s seed; B, the pins and the registry stay',
      () async {
    await seedRecords([a, b]);
    final box = await Hive.openBox('settings');
    await box.put('passkey_cached_label', 'A · 1');
    keychain
      ..seed(seedCacheKey('A · 1', ''), 'seed-a-unpinned')
      ..seed(prfKey('A · 1'), 'bb' * 32);
    final model = SettingsModel(_settings([a, b], 'A'));

    // A warm device: the first resolve runs the ceremony and caches the
    // seed under (label, credential); the next one is served from it.
    await PasskeyService.getWallet(label: 'A · 1', legacy: false);
    expect(client.signIns, 1);
    expect(keychain.peek(seedCacheKey('A · 1')), isNotNull);
    PasskeyService.clearSession();
    await PasskeyService.getWallet(label: 'A · 1', legacy: false);
    expect(client.signIns, 1);

    await model.removeWallet('A');

    expect(model.state.wallets.map((w) => w.id), ['B']);
    expect(keychain.peek(seedCacheKey('A · 1')), isNull);
    expect(keychain.peek(seedCacheKey('A · 1', '')), isNull);
    expect(keychain.peek(prfKey('A · 1')), isNull);
    expect(box.get('passkey_cached_label'), isNull);
    for (final e in keep.entries) {
      expect(keychain.peek(e.key), e.value, reason: e.key);
    }
    expect(keychain.peekSynced('passkey_registered_v1'), '1');

    // Adding A back goes through the normal ceremony again.
    PasskeyService.clearSession();
    await PasskeyService.getWallet(label: 'A · 1', legacy: false);
    expect(client.signIns, 2);
  });

  test('the cached label of another wallet is kept', () async {
    await seedRecords([a, b]);
    final box = await Hive.openBox('settings');
    await box.put('passkey_cached_label', 'B · 2');
    final model = SettingsModel(_settings([a, b], 'A'));
    await model.removeWallet('A');
    expect(box.get('passkey_cached_label'), 'B · 2');
  });

  test('a PRF seed under a label another record still carries is kept',
      () async {
    // Two records on the same label (a duplicate add); the salt cannot be
    // tied to the removed one alone.
    final dup = _passkey('A2', 'A · 1', provider: 'breez-0.17');
    await seedRecords([a, dup, b]);
    keychain.seed(prfKey('A · 1'), 'bb' * 32);
    final model = SettingsModel(_settings([a, dup, b], 'A'));
    await model.removeWallet('A');
    expect(keychain.peek(prfKey('A · 1')), 'bb' * 32);
    // The 0.17 cache entry under the label is this device's derived seed
    // for that label and goes regardless.
    expect(keychain.peek(seedCacheKey('A · 1')), isNull);
  });

  test('a record with no label forgets nothing passkey-related', () async {
    final unlabelled = _passkey('A', null);
    await seedRecords([unlabelled, b]);
    keychain.seed(prfKey('Default'), 'bb' * 32);
    final model = SettingsModel(_settings([unlabelled, b], 'A'));
    await model.removeWallet('A');
    expect(keychain.peek(prfKey('Default')), 'bb' * 32);
    for (final e in keep.entries) {
      expect(keychain.peek(e.key), e.value, reason: e.key);
    }
  });

  test('a failed delete never stops the record removal or the other steps',
      () async {
    await seedRecords([a, b]);
    keychain.seed(prfKey('A · 1'), 'bb' * 32);
    keychain.failDelete('local', StateError('keychain'),
        key: seedCacheKey('A · 1', ''));
    final model = SettingsModel(_settings([a, b], 'A'));
    await model.removeWallet('A');
    expect(model.state.wallets.map((w) => w.id), ['B']);
    expect(keychain.peek(prfKey('A · 1')), isNull);
    for (final e in keep.entries) {
      expect(keychain.peek(e.key), e.value, reason: e.key);
    }
  });
}
