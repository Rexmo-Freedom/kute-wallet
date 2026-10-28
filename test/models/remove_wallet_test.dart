// Removing a wallet drops its record first, then deletes only that
// wallet's secrets, best-effort. Another wallet's seed copies, passkey seed
// caches, the passkey registry and the credential pins stay untouched.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';

import '../services/support/fake_secret_store.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeKeychain keychain;
  late Directory hiveDir;
  late SettingsModel model;

  final a = WalletConfig(id: 'A', name: 'A');
  final b = WalletConfig(id: 'B', name: 'B');
  final c = WalletConfig(id: 'C', name: 'C');

  /// Device-level and other-wallet items that removing A must never touch.
  const keep = {
    'mnemonic_B': 'cipher-b',
    'v2:wallet:B.mnemonic': 'phrase-b',
    'xpub_B': 'xpub-b',
    'pm_api_credentials_B': 'creds-b',
    'pm_proxy_wallet_B': 'proxy-b',
    'passkey017_seed_v1__bbbb': 'seed-b',
    'prf_seed_v1__cccc': 'prf-seed',
    'passkey017_credential_id': 'cred',
    'prf_credential_id': 'legacy-cred',
    'passkey_registered_v1': 'true',
    'pin_hash': 'salt:hash',
    'biometric_pin': '123456',
  };
  const aKeys = {
    'mnemonic_A': 'cipher-a',
    'v2:wallet:A.mnemonic': 'phrase-a',
    'xpub_A': 'xpub-a',
    'external_address_A': 'addr-a',
    'pm_api_credentials_A': 'creds-a',
    'pm_proxy_wallet_A': 'proxy-a',
  };

  setUp(() async {
    keychain = FakeKeychain();
    SecretStores.debugOverride(local: keychain.local, synced: keychain.synced);
    for (final e in {...keep, ...aKeys}.entries) {
      keychain.seed(e.key, e.value);
    }
    keychain
      ..seedSynced('v2:wallet:B.mnemonic', 'phrase-b')
      ..seedSynced('passkey_registered_v1', 'true');
    hiveDir = await Directory.systemTemp.createTemp('remove_wallet');
    Hive.init(hiveDir.path);
    final box = await Hive.openBox('settings');
    await box.put('wallets', [a.toMap(), b.toMap(), c.toMap()]);
    await box.put('activeWalletId', 'A');
    model = SettingsModel(_settings([a, b, c], 'A'));
  });

  tearDown(() async {
    SecretStores.debugReset();
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  Future<List<String>> storedIds() async {
    final stored = (await Hive.openBox('settings')).get('wallets') as List;
    return [for (final w in stored) (w as Map)['id'] as String];
  }

  test('removing A deletes only A\'s secrets', () async {
    await model.removeWallet('A');

    expect(await storedIds(), ['B', 'C']);
    expect(model.state.wallets.map((w) => w.id), ['B', 'C']);
    expect(model.state.activeWalletId, 'B');
    for (final key in aKeys.keys) {
      expect(keychain.peek(key), isNull, reason: key);
    }
    for (final e in keep.entries) {
      expect(keychain.peek(e.key), e.value, reason: e.key);
    }
    expect(keychain.peekSynced('v2:wallet:B.mnemonic'), 'phrase-b');
    expect(keychain.peekSynced('passkey_registered_v1'), 'true');
  });

  test('a throw deleting a secret still removes the record', () async {
    final error = PlatformException(code: 'x', details: -25308);
    keychain.failDelete('local', error, key: 'mnemonic_A');

    await model.removeWallet('A');

    expect(await storedIds(), ['B', 'C']);
    expect(model.state.wallets.map((w) => w.id), ['B', 'C']);
    // The failing step was skipped; the steps after it still ran.
    expect(keychain.peek('mnemonic_A'), 'cipher-a');
    expect(keychain.peek('pm_api_credentials_A'), isNull);
    expect(keychain.peek('pm_proxy_wallet_A'), isNull);
    for (final e in keep.entries) {
      expect(keychain.peek(e.key), e.value, reason: e.key);
    }
  });

  test('the record is written before any secret is deleted', () async {
    final error = PlatformException(code: 'x', details: -25308);
    // Every local delete fails: nothing may stop the record going.
    keychain.failDelete('local', error);
    await model.removeWallet('A');
    expect(await storedIds(), ['B', 'C']);
  });
}
