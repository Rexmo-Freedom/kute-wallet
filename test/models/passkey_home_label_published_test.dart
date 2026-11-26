// A label published by one passkey home's relay identity marks only that
// home's wallets backed up, and the backup reminder runs its ceremony on
// the home of the wallet it is for.

import 'dart:io';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_backup_provider.dart';
import 'package:kute/services/passkey_service.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';

import '../services/support/fake_secret_store.dart';

Settings _settings(List<WalletConfig> wallets) => Settings(
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
      activeWalletId: wallets.firstOrNull?.id,
    );

WalletConfig _passkey(String id, String label, String? provider) =>
    WalletConfig(
      id: id,
      name: id,
      sparkEnabled: true,
      isPasskey: true,
      passkeyLabel: label,
      passkeyProvider: provider,
      backedUp: false,
    );

/// Records every ceremony; none may run in these tests.
class _Client implements PasskeyClient {
  _Client(this.calls, this.name);
  final List<String> calls;
  final String name;

  @override
  Future<SignInResponse> signIn({required SignInRequest request}) async {
    calls.add('$name:${request.label}');
    throw PasskeyError.prf(PrfProviderError.userCancelled());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory hiveDir;

  setUp(() async {
    final keychain = FakeKeychain();
    SecretStores.debugOverride(local: keychain.local, synced: keychain.synced);
    hiveDir = await Directory.systemTemp.createTemp('passkey_home_published');
    Hive.init(hiveDir.path);
    await Hive.openBox('settings');
  });

  tearDown(() async {
    SecretStores.debugReset();
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  Future<SettingsModel> modelWith(List<WalletConfig> wallets) async {
    await Hive.box('settings')
        .put('wallets', wallets.map((w) => w.toMap()).toList());
    return SettingsModel(_settings(wallets));
  }

  bool backedUp(SettingsModel m, String id) =>
      m.state.wallets.singleWhere((w) => w.id == id).backedUp;

  test('a Breez-home publish marks Breez and legacy wallets, never Kute',
      () async {
    final model = await modelWith([
      _passkey('b', 'L · 1', 'breez-0.17'),
      _passkey('l', 'L · 1', null),
      _passkey('k', 'L · 1', 'kute-1'),
    ]);
    await model.markPasskeyLabelPublished('L · 1');
    expect(backedUp(model, 'b'), isTrue);
    expect(backedUp(model, 'l'), isTrue);
    expect(backedUp(model, 'k'), isFalse);
  });

  test('a Kute-home publish marks only Kute wallets', () async {
    final model = await modelWith([
      _passkey('b', 'L · 1', 'breez-0.17'),
      _passkey('k', 'L · 1', 'kute-1'),
    ]);
    await model.markPasskeyLabelPublished('L · 1', home: PasskeyHome.kute);
    expect(backedUp(model, 'b'), isFalse);
    expect(backedUp(model, 'k'), isTrue);
  });

  test('the reminder refuses a label it cannot tie to one home', () async {
    final calls = <String>[];
    PasskeyService.debugSetClient(_Client(calls, 'breez'));
    PasskeyService.debugSetHomeClient(PasskeyHome.kute, _Client(calls, 'kute'));
    addTearDown(() {
      PasskeyService.debugSetClient(null);
      PasskeyService.debugSetHomeClient(PasskeyHome.kute, null);
    });
    final container = ProviderContainer(overrides: [
      initialSettingsProvider.overrideWith((ref) async => _settings([
            _passkey('b', 'Both · 1', 'breez-0.17'),
            _passkey('k', 'Both · 1', 'kute-1'),
            _passkey('u', 'Odd · 1', 'breez-9'),
          ])),
    ]);
    addTearDown(container.dispose);
    await container.read(initialSettingsProvider.future);
    expect(container.read(settingsProvider).wallets, hasLength(3));
    final run = container.read(passkeyLabelBackupRunnerProvider);
    // Both homes carry it: no ceremony on either, the reminder stays.
    final both = await run('Both · 1', surface: 'home');
    expect(both.succeeded, isFalse);
    expect(both.cancelled, isFalse);
    // An unknown marker: no ceremony at all.
    final odd = await run('Odd · 1', surface: 'home');
    expect(odd.succeeded, isFalse);
    expect(calls, isEmpty);
  });

  test('the reminder runs on the home of the wallet it is for', () async {
    final calls = <String>[];
    PasskeyService.debugSetClient(_Client(calls, 'breez'));
    PasskeyService.debugSetHomeClient(PasskeyHome.kute, _Client(calls, 'kute'));
    addTearDown(() {
      PasskeyService.debugSetClient(null);
      PasskeyService.debugSetHomeClient(PasskeyHome.kute, null);
    });
    final container = ProviderContainer(overrides: [
      initialSettingsProvider.overrideWith((ref) async => _settings([
            _passkey('b', 'B · 1', 'breez-0.17'),
            _passkey('l', 'L · 1', null),
            _passkey('k', 'K · 1', 'kute-1'),
          ])),
    ]);
    addTearDown(container.dispose);
    await container.read(initialSettingsProvider.future);
    expect(container.read(settingsProvider).wallets, hasLength(3));
    final run = container.read(passkeyLabelBackupRunnerProvider);
    await run('K · 1', surface: 'home');
    await run('B · 1', surface: 'home');
    await run('L · 1', surface: 'home');
    expect(calls, ['kute:K · 1', 'breez:B · 1', 'breez:L · 1']);
  });
}
