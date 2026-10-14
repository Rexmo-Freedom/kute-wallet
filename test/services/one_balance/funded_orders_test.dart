// Funded orders: what money on a rail is for. Persisted, so a restart
// keeps the rows' meaning, never resumes a chain (its approval was memory
// only), blocks a second "Add" while a Bitcoin leg is still on its way,
// and lets the header name the order.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/one_balance_provider.dart';
import 'package:kute/providers/pending_pool_deposits_provider.dart';
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';

const _bet = FundedOrderLabel(
  venue: OneBalanceVenue.predictions,
  orderUsd: 5,
  side: 'Yes',
  market: 'Lakers vs Celtics',
  marketKey: 'tok',
);

SwapOrder _row(String id,
        {required String from,
        required String fromNet,
        required String to,
        required String toNet,
        String deposit = '0.0001',
        String withdrawal = '6.00',
        String status = 'exchanging',
        int? at}) =>
    SwapOrder(
      id: id,
      coinFrom: from,
      networkFrom: fromNet,
      coinTo: to,
      networkTo: toNet,
      depositAddress: 'd',
      depositAmount: deposit,
      withdrawalAmount: withdrawal,
      status: status,
      timestamp: at ?? DateTime.now().millisecondsSinceEpoch,
      withdrawalAddress: 'w',
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: 'r',
      provider: 'Orchestra',
      walletId: 'w1',
    );

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('kute_funded_orders');
    Hive.init(dir.path);
    await Hive.openBox('settings');
  });
  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test(
      'restart: a chain left running never resumes; its bitcoin row still '
      'counts as the venue\'s deposit, and the slip can say tap to place',
      () async {
    final first = ProviderContainer();
    final orders = first.read(fundedOrdersProvider.notifier);
    final id = orders.start(_bet, stage: FundedOrderStage.adding, addUsd: 6);
    orders.addBtcRow(id, 'q_btc');
    orders.addBtcRow(id, 'ord_btc');
    first.dispose();

    // A new process reads the box.
    final second = ProviderContainer();
    addTearDown(second.dispose);
    final records = second.read(fundedOrdersProvider);
    expect(records, hasLength(1));
    expect(records.single.stage, FundedOrderStage.ready);
    expect(records.single.reason, 'interrupted');
    // Never live again: no header line claims the bet is being placed.
    expect(FundedOrdersNotifier.liveOwnerOf(records, 'ord_btc'), isNull);
    expect(
        FundedOrdersNotifier.activeOf(records, OneBalanceVenue.predictions),
        isNull);
    // Its bitcoin row is still this venue's deposit on its way.
    expect(FundedOrdersNotifier.btcRowVenue(records, 'ord_btc'),
        OneBalanceVenue.predictions);
    final row = _row('ord_btc',
        from: 'BTC', fromNet: 'SPARK', to: 'USDB', toNet: 'SPARK');
    expect(
        isPendingBitcoinLeg(row,
            walletId: 'w1', nowMs: DateTime.now().millisecondsSinceEpoch),
        isTrue);
    // The same market's slip shows the note; another market's does not.
    final now = DateTime.now();
    expect(
        FundedOrdersNotifier.readyOn(
            records, OneBalanceVenue.predictions, 'tok', now),
        isNotNull);
    expect(
        FundedOrdersNotifier.readyOn(
            records, OneBalanceVenue.predictions, 'other', now),
        isNull);
  });

  test('a new funded order for the market closes its tap-to-place note',
      () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final orders = c.read(fundedOrdersProvider.notifier);
    final id = orders.start(_bet, stage: FundedOrderStage.adding, addUsd: 6);
    orders.setStage(id, FundedOrderStage.ready, reason: 'timeout');
    orders.start(_bet, stage: FundedOrderStage.preparing);
    expect(
        FundedOrdersNotifier.readyOn(c.read(fundedOrdersProvider),
            OneBalanceVenue.predictions, 'tok', DateTime.now()),
        isNull);
  });

  test(
      'margin added through Investments is its own kind: kept across a '
      'restart, its note only on the margin sheet, named as margin', () {
    const margin = FundedOrderLabel(
      venue: OneBalanceVenue.investing,
      orderUsd: 30,
      side: 'Long',
      market: 'TSLA',
      marketKey: 'TSLA',
      kind: FundedOrderKind.margin,
    );
    final first = ProviderContainer();
    final orders = first.read(fundedOrdersProvider.notifier);
    final id = orders.start(margin, stage: FundedOrderStage.adding, addUsd: 9);
    expect(orders.byId(id)!.toInFlightOrder().margin, isTrue);
    orders.setStage(id, FundedOrderStage.ready, reason: 'timeout');
    first.dispose();

    final second = ProviderContainer();
    addTearDown(second.dispose);
    final records = second.read(fundedOrdersProvider);
    expect(records.single.label.kind, FundedOrderKind.margin);
    final now = DateTime.now();
    // The order slip for the same market never reads it as its own.
    expect(
        FundedOrdersNotifier.readyOn(
            records, OneBalanceVenue.investing, 'TSLA', now),
        isNull);
    expect(
        FundedOrdersNotifier.readyOn(
            records, OneBalanceVenue.investing, 'TSLA', now,
            kind: FundedOrderKind.margin),
        isNotNull);
    // An order's label stays as it always was on disk.
    expect(_bet.toJson().containsKey('kind'), isFalse);
  });

  test('rows carrying a live order are named by it, once per order', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final orders = c.read(fundedOrdersProvider.notifier);
    final id = orders.start(_bet, stage: FundedOrderStage.preparing, addUsd: 6);
    orders.addBtcRow(id, 'ord_btc');
    orders.addVenueRow(id, 'ord_venue');
    final records = c.read(fundedOrdersProvider);
    final now = DateTime.now().millisecondsSinceEpoch;
    final moves = inFlightMovesFrom(
      [
        _row('ord_btc',
            from: 'BTC', fromNet: 'SPARK', to: 'USDB', toNet: 'SPARK'),
        _row('ord_venue',
            from: 'USDB',
            fromNet: 'SPARK',
            to: 'USDC',
            toNet: 'POLYGON',
            deposit: '5.30',
            withdrawal: '5.25'),
        // A sweep home, no order.
        _row('ord_sweep',
            from: 'USDC',
            fromNet: 'HYPERCORE',
            to: 'USDB',
            toNet: 'SPARK',
            deposit: '3.00',
            withdrawal: '2.98'),
      ],
      walletId: 'w1',
      nowMs: now,
      orderOf: (rowId) =>
          FundedOrdersNotifier.liveOwnerOf(records, rowId)?.toInFlightOrder(),
    );
    final ordered = moves.where((m) => m.order != null).toList();
    expect(ordered, isNotEmpty);
    expect(ordered.map((m) => m.order!.id).toSet(), {id});
    expect(ordered.every((m) => m.hasLine), isTrue);
    final sweep = moves.where((m) => m.kind == InFlightKind.fromVenue);
    expect(sweep.single.order, isNull);
    expect(sweep.single.hasLine, isFalse);
    // Every dollar is still counted in the total.
    final total = moves.fold<double>(0, (s, m) => s + m.usd);
    expect(total, closeTo(6 + 5.30 + 2.98, 1e-9));
  });
}
