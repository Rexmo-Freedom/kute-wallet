// A passkey wallet is one record per label: adding a label that is
// already listed returns the existing record and stores nothing, so a
// retried create or restore after a failure past the save never lists
// the same wallet twice. Other wallets still add as before.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/services/tracking_service.dart';

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

WalletConfig _passkey(String id, String? label) => WalletConfig(
      id: id,
      name: id,
      sparkEnabled: true,
      isPasskey: true,
      passkeyLabel: label,
      passkeyProvider: 'breez-0.17',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory hiveDir;
  late List<(String, Map<String, Object>?)> events;

  setUp(() async {
    hiveDir = await Directory.systemTemp.createTemp('add_wallet_dedupe');
    Hive.init(hiveDir.path);
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });

  tearDown(() async {
    TrackingService.debugTrackObserver = null;
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  Future<List<String>> storedIds() async {
    final stored = (await Hive.openBox('settings')).get('wallets') as List?;
    return [for (final w in stored ?? const []) (w as Map)['id'] as String];
  }

  test('the same passkey label again returns the existing record', () async {
    final a = _passkey('A', 'L · 1');
    final model = SettingsModel(_settings([]));
    expect(await model.addWallet(a), same(a));
    final again = await model.addWallet(_passkey('A2', 'L · 1'));
    expect(again, same(a));
    expect(model.state.wallets.map((w) => w.id), ['A']);
    expect(await storedIds(), ['A']);
    expect(model.state.activeWalletId, 'A');
    expect(events.map((e) => e.$1), ['wallet_add_deduped']);
    expect(events.single.$2!.values, isNot(contains('L · 1')));
  });

  test('a different label, an unlabelled record and a words wallet add',
      () async {
    final model = SettingsModel(_settings([_passkey('A', 'L · 1')]));
    await model.addWallet(_passkey('B', 'M · 2'));
    await model.addWallet(_passkey('C', null));
    await model.addWallet(_passkey('D', null));
    await model.addWallet(WalletConfig(id: 'W', name: 'Words'));
    expect(model.state.wallets.map((w) => w.id), ['A', 'B', 'C', 'D', 'W']);
    expect(events, isEmpty);
  });

  test('a words wallet never dedupes against a passkey label', () async {
    final model = SettingsModel(_settings([_passkey('A', 'L · 1')]));
    final words = WalletConfig(id: 'W', name: 'Words', passkeyLabel: 'L · 1');
    expect(await model.addWallet(words), same(words));
    expect(model.state.wallets.length, 2);
  });
}
