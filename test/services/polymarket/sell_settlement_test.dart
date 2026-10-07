import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/services/polymarket/sell_settlement.dart';

void main() {
  final orderId = '0x${'a' * 64}';
  const token = '111';
  const other = '222';

  // A clock the watcher's sleeps move forward, so timeouts run instantly.
  late DateTime clock;
  PmSellSettlementWatcher watcher({
    required Future<Map<String, dynamic>?> Function(String) order,
    Future<Map<String, dynamic>?> Function(String)? trade,
    Future<bool> Function()? moved,
  }) =>
      PmSellSettlementWatcher(
        readOrder: order,
        readTrade: trade,
        positionMoved: moved,
        now: () => clock,
        sleep: (d) async => clock = clock.add(d),
      );

  setUp(() => clock = DateTime(2026, 10, 5, 12));

  Map<String, dynamic> tradeAs(String status,
          {String? taker, List<Map<String, dynamic>> makers = const []}) =>
      {
        'id': 't1',
        'status': status,
        'taker_order_id': taker ?? orderId,
        'maker_orders': makers,
      };

  test('a market sell matched on the POST is sold once its trade is mined',
      () async {
    final stages = <PmSellStage>[];
    var reads = 0;
    final s = await watcher(
      order: (_) async => null,
      trade: (_) async => tradeAs(++reads < 3 ? 'MATCHED' : 'MINED'),
    ).watch(
      response: {
        'success': true,
        'orderID': orderId,
        'status': 'matched',
        'makingAmount': '4.5',
        'takingAmount': '2.745',
        'tradeIDs': ['t1'],
      },
      tokenId: token,
      offeredShares: 4.5,
      resting: false,
      onStage: (stage, _) => stages.add(stage),
    );
    expect(s.result, PmSellResult.filled);
    expect(s.soldShares, 4.5);
    expect(s.proceeds, 2.745);
    expect(s.confirmedBy, 'mined');
    expect(s.timeToMatch, Duration.zero);
    expect(s.timeToConfirm, const Duration(seconds: 2));
    expect(stages, [PmSellStage.matched]);
  });

  test('a delayed sell waits for the live game, then reads the fill and '
      'the proceeds from the trade', () async {
    final stages = <PmSellStage>[];
    var reads = 0;
    final s = await watcher(
      order: (_) async => ++reads < 3
          ? {'status': 'DELAYED', 'size_matched': '0'}
          : {
              'status': 'MATCHED',
              'size_matched': '4',
              'associate_trades': ['t1'],
            },
      trade: (_) async => tradeAs('CONFIRMED', makers: [
        {'asset_id': token, 'matched_amount': '3', 'price': '0.6'},
        // A maker selling the other outcome (a merge) leaves 1 - 0.45.
        {'asset_id': other, 'matched_amount': '1', 'price': '0.45'},
      ]),
    ).watch(
      response: {'success': true, 'orderID': orderId, 'status': 'delayed'},
      tokenId: token,
      offeredShares: 4,
      resting: false,
      onStage: (stage, _) => stages.add(stage),
    );
    expect(s.result, PmSellResult.filled);
    expect(s.delayed, isTrue);
    expect(s.soldShares, 4);
    expect(s.proceeds, closeTo(3 * 0.6 + 0.55, 1e-9));
    expect(s.confirmedBy, 'confirmed');
    expect(s.timeToMatch, const Duration(seconds: 2));
    expect(stages, [PmSellStage.delayed, PmSellStage.matched]);
  });

  test('a delayed sell killed when the delay ends sold nothing', () async {
    final s = await watcher(
      order: (_) async => {'status': 'CANCELED', 'size_matched': '0'},
    ).watch(
      response: {'success': true, 'orderID': orderId, 'status': 'delayed'},
      tokenId: token,
      offeredShares: 4,
      resting: false,
    );
    expect(s.result, PmSellResult.notFilled);
    expect(s.soldShares, 0);
    expect(s.proceeds, isNull);
  });

  test('a trade that fails on chain is a failed sale, never a sold one',
      () async {
    final s = await watcher(
      order: (_) async => null,
      trade: (_) async => tradeAs('FAILED'),
    ).watch(
      response: {
        'orderID': orderId,
        'status': 'matched',
        'makingAmount': '2',
        'takingAmount': '1',
        'tradeIDs': ['t1'],
      },
      tokenId: token,
      offeredShares: 2,
      resting: false,
    );
    expect(s.result, PmSellResult.failed);
    expect(s.proceeds, isNull);
  });

  test('a limit sell that rests whole, or sold part on arrival', () async {
    final resting = await watcher(
      order: (_) async => {'status': 'LIVE', 'size_matched': '0'},
    ).watch(
      response: {'success': true, 'orderID': orderId, 'status': 'live'},
      tokenId: token,
      offeredShares: 4.5,
      resting: true,
    );
    expect(resting.result, PmSellResult.resting);

    final partial = await watcher(
      order: (_) async => {
        'status': 'LIVE',
        'size_matched': '2.1',
        'associate_trades': ['t1'],
      },
      // Resting, the order is a maker: its own entry says what it sold.
      trade: (_) async => tradeAs('MINED', taker: '0x${'b' * 64}', makers: [
        {'order_id': orderId, 'matched_amount': '2.1', 'price': '0.61'},
        {'order_id': '0x${'c' * 64}', 'matched_amount': '9', 'price': '0.61'},
      ]),
    ).watch(
      response: {'success': true, 'orderID': orderId, 'status': 'live'},
      tokenId: token,
      offeredShares: 4.5,
      resting: true,
    );
    expect(partial.result, PmSellResult.partial);
    expect(partial.soldShares, 2.1);
    expect(partial.remainingShares, closeTo(2.4, 1e-9));
    expect(partial.proceeds, closeTo(2.1 * 0.61, 1e-9));
    expect(partial.averagePrice, closeTo(0.61, 1e-9));
  });

  test('an order the venue never answers for is unknown, not sold', () async {
    final s = await watcher(order: (_) async => throw StateError('down'))
        .watch(
      response: {'success': true, 'orderID': orderId, 'status': 'delayed'},
      tokenId: token,
      offeredShares: 1,
      resting: false,
    );
    expect(s.result, PmSellResult.unknown);
  });

  test('a matched sale the chain has not shown in time still stands', () async {
    final s = await watcher(
      order: (_) async => null,
      trade: (_) async => tradeAs('MATCHED'),
    ).watch(
      response: {
        'orderID': orderId,
        'status': 'matched',
        'makingAmount': '1',
        'takingAmount': '0.5',
        'tradeIDs': ['t1'],
      },
      tokenId: token,
      offeredShares: 1,
      resting: false,
    );
    expect(s.result, PmSellResult.filled);
    expect(s.confirmedBy, 'timeout');
    expect(s.proceeds, 0.5);
  });

  test('the account showing the sale confirms it without the trade read',
      () async {
    final s = await watcher(
      order: (_) async => null,
      moved: () async => true,
    ).watch(
      response: {
        'orderID': orderId,
        'status': 'matched',
        'makingAmount': '1',
        'takingAmount': '0.5',
      },
      tokenId: token,
      offeredShares: 1,
      resting: false,
    );
    expect(s.confirmedBy, 'position');
  });

  test('a buy reads its shares and cost the other way round, unbounded by '
      'the shares it priced at its cap', () async {
    final s = await watcher(
      order: (_) async => null,
      trade: (_) async => tradeAs('MINED'),
    ).watch(
      response: {
        'success': true,
        'orderID': orderId,
        'status': 'matched',
        // Paid $6.00, got 10.5 shares (priced for 10 at the cap).
        'makingAmount': '6',
        'takingAmount': '10.5',
        'tradeIDs': ['t1'],
      },
      tokenId: token,
      offeredShares: 10,
      resting: false,
      buy: true,
    );
    expect(s.result, PmSellResult.filled);
    expect(s.soldShares, 10.5);
    expect(s.proceeds, 6);
    expect(s.confirmedBy, 'mined');
    expect(s.analyticsParams()['fill_outcome'], 'filled');
    expect(s.analyticsParams()['notional_usd'], 6);
  });

  test('a delayed buy that matched in part, its cost from the trade',
      () async {
    final s = await watcher(
      order: (_) async => {
        'status': 'MATCHED',
        'size_matched': '2.1',
        'associate_trades': ['t1'],
      },
      trade: (_) async => tradeAs('MINED', makers: [
        // A maker selling the same outcome is paid its price.
        {'asset_id': token, 'matched_amount': '2.1', 'price': '0.61'},
      ]),
    ).watch(
      response: {'success': true, 'orderID': orderId, 'status': 'delayed'},
      tokenId: token,
      offeredShares: 4.5,
      resting: false,
      buy: true,
    );
    expect(s.soldShares, 2.1);
    expect(s.proceeds, closeTo(2.1 * 0.61, 1e-9));
    expect(s.delayed, isTrue);
  });

  group('pmLiveOrderDelaySeconds', () {
    final condition = '0x${'d' * 64}';
    MockClient market(Map<String, Object?> body) =>
        MockClient((_) async => http.Response(jsonEncode(body), 200));

    test('the market delay while its game is on', () async {
      expect(
          await pmLiveOrderDelaySeconds(condition,
              client: market({'sd': 1, 'gst': '2026-10-05T09:00:00Z'}),
              now: DateTime.utc(2026, 10, 5, 10)),
          1);
    });

    test('nothing before kickoff, without a delay, or on a bad read',
        () async {
      final now = DateTime.utc(2026, 10, 5, 10);
      expect(
          await pmLiveOrderDelaySeconds(condition,
              client: market({'sd': 3, 'gst': '2026-10-05T18:00:00Z'}),
              now: now),
          0);
      expect(
          await pmLiveOrderDelaySeconds(condition,
              client: market({'sd': 0}), now: now),
          0);
      expect(
          await pmLiveOrderDelaySeconds(condition,
              client: MockClient((_) async => http.Response('nope', 500)),
              now: now),
          0);
      expect(await pmLiveOrderDelaySeconds('not-a-condition'), 0);
    });
  });
}
