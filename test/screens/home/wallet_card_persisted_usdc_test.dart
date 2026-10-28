import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/screens/home/components/wallet_cards.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('wallet_card');
    Hive.init(dir.path);
    await Hive.openBox('settings');
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('a USDC card saved by an earlier build opens the bitcoin card', () {
    Hive.box('settings').put('selectedWalletCard', 'usdc');
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(selectedWalletCardProvider), WalletCardType.bitcoin);
  });

  test('a saved bank card still opens the bank card', () {
    Hive.box('settings').put('selectedWalletCard', 'bank');
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(selectedWalletCardProvider), WalletCardType.bank);
  });
}
