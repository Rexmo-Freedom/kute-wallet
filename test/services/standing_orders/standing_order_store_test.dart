// Persistence of a standing order: the public facts in Hive per wallet,
// the secret in secure storage once per order, gone when asked.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/services/standing_orders/standing_order.dart';
import 'package:kute/services/standing_orders/standing_order_store.dart';

import 'fake_secret_store.dart';

StandingOrder _order(String id, String walletId,
        {StandingOrderState state = StandingOrderState.funding,
        int minute = 0}) =>
    StandingOrder(
      id: id,
      walletId: walletId,
      venue: StandingOrderVenue.investing,
      marketKey: 'BTC',
      marketTitle: 'BTC · Perp',
      sideLabel: 'long',
      isBuy: true,
      size: 20,
      approvedPrice: 60000,
      amountUsd: 20,
      orderKind: 'market',
      state: state,
      createdAt: DateTime.utc(2026, 11, 9, 12, minute),
      updatedAt: DateTime.utc(2026, 11, 9, 12, minute),
      leverage: 2,
      marketKind: 'perp',
    );

void main() {
  late Directory dir;
  late FakeSecretStore secrets;
  late StandingOrderStore store;

  setUpAll(() {
    dir = Directory.systemTemp.createTempSync('standing_store_test');
    Hive.init(dir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  setUp(() async {
    secrets = FakeSecretStore();
    store = StandingOrderStore(secrets: secrets, boxName: 'standing_test');
    final box = await Hive.openBox<String>('standing_test');
    await box.clear();
  });

  test('saves per wallet and loads oldest first, other wallets apart',
      () async {
    await store.save(_order('b', 'w1', minute: 1));
    await store.save(_order('a', 'w1', minute: 5));
    await store.save(_order('c', 'w2'));
    final mine = await store.load('w1');
    expect(mine.map((o) => o.id), ['b', 'a']);
    expect((await store.load('w2')).single.id, 'c');
    expect(await store.load('w3'), isEmpty);
    // A state change overwrites the row.
    await store.save(
        _order('a', 'w1', state: StandingOrderState.filled, minute: 5));
    expect((await store.load('w1')).last.state, StandingOrderState.filled);
    await store.remove(_order('a', 'w1'));
    expect((await store.load('w1')).map((o) => o.id), ['b']);
  });

  test('an unreadable row is skipped, never a stop', () async {
    final box = await Hive.openBox<String>('standing_test');
    await box.put('w1:bad', 'not json');
    await box.put('w1:old', '{"v": 0}');
    await store.save(_order('ok', 'w1'));
    expect((await store.load('w1')).single.id, 'ok');
  });

  test('one secret per order: a second write is refused', () async {
    await store.writeSecret('so_1', {'venue': 'investing', 'x': 1});
    expect(await store.hasSecret('so_1'), isTrue);
    expect((await store.readSecret('so_1'))!['x'], 1);
    await expectLater(
        store.writeSecret('so_1', {'venue': 'investing', 'x': 2}),
        throwsA(isA<StandingOrderSecretExists>()));
    expect((await store.readSecret('so_1'))!['x'], 1,
        reason: 'the first signature stands');
    expect(secrets.writes, 1);
  });

  test('a deleted secret reads as none; an unreadable one too', () async {
    await store.writeSecret('so_2', {'venue': 'investing'});
    await store.deleteSecret('so_2');
    expect(await store.hasSecret('so_2'), isFalse);
    expect(await store.readSecret('so_2'), isNull);
    secrets.values[StandingOrderStore.secretKey('so_3')] = 'garbage';
    expect(await store.readSecret('so_3'), isNull);
    expect(StandingOrderStore.secretKey('so_3'), 'standing_order:so_3');
    expect(StandingOrderStore.rowKey('w1', 'so_3'), 'w1:so_3');
  });
}
