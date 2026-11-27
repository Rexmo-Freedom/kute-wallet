// Protective orders on the account's side:
//
//   * an order first seen over the WebSocket (orderUpdates carries only
//     the basic order: no type, trigger price or time in force) is kept
//     as "kind unknown" until REST describes it, never as a limit at its
//     guard price; a row REST already described keeps its kind;
//   * the chart's modify refuses a row it cannot move: still loading, a
//     trailing stop, a trigger turned into a limit;
//   * an unclear trailing-stop send is looked up on the open orders and
//     the order history before the asset stays blocked.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/services/hyperliquid/hyperliquid_websocket.dart'
    show HlOrderUpdate;
import 'package:kute/services/hyperliquid/trailing_stop_guard.dart';

const _btc = HlMarket(
  coin: 'BTC',
  wireCoin: 'BTC',
  assetId: 0,
  kind: HlMarketKind.perp,
  szDecimals: 5,
  maxLeverage: 40,
  onlyIsolated: false,
  markPx: 66000,
  midPx: 66000,
  prevDayPx: 65000,
  dayNtlVlm: 1e9,
);

const _restStop = HlOpenOrder(
  coin: 'BTC',
  oid: 7,
  isBuy: false,
  limitPx: 57000,
  sz: 0.5,
  origSz: 0.5,
  timestamp: 1000,
  cloid: null,
  reduceOnly: true,
  orderType: 'Stop Market',
  isTrigger: true,
  triggerPx: 60000,
);

class _Trading extends HyperliquidTradingNotifier {
  _Trading(this.orders);
  final List<HlOpenOrder> orders;
  @override
  Future<HyperliquidTradingState> build() async =>
      HyperliquidTradingState(isInitialized: true, openOrders: orders);
}

HlOrderUpdate _open(int oid, {double limitPx = 57000, bool? reduceOnly}) =>
    HlOrderUpdate(
      status: 'open',
      statusTimestamp: 2000,
      coin: 'BTC',
      oid: oid,
      isBuy: false,
      limitPx: limitPx,
      sz: 0.5,
      origSz: 0.5,
      timestamp: 2000,
      cloid: null,
      reduceOnly: reduceOnly,
    );

Future<ProviderContainer> _container(List<HlOpenOrder> orders) async {
  final container = ProviderContainer(overrides: [
    hyperliquidTradingProvider.overrideWith(() => _Trading(orders)),
  ]);
  addTearDown(container.dispose);
  container.listen(hyperliquidTradingProvider, (_, __) {});
  await container.read(hyperliquidTradingProvider.future);
  return container;
}

void main() {
  group('WebSocket rebuild of open orders', () {
    test('a stop first seen over the socket is not a limit: kind unknown, '
        'never drawn or moved until REST says what it is', () async {
      final c = await _container(const []);
      c
          .read(hyperliquidTradingProvider.notifier)
          .applyOrderUpdates([_open(9, reduceOnly: true)]);
      final row = c.read(hyperliquidTradingProvider).value!.openOrders.single;
      expect(row.oid, 9);
      expect(row.detailsKnown, isFalse);
      expect(row.isTrigger, isFalse);
      // Not the 'Limit' placeholder: no kind until REST.
      expect(row.orderType, isEmpty);
      expect(row.reduceOnly, isTrue);
      expect(() => hlCheckModifiable(row, [row]), throwsStateError);
    });

    test('a row REST described keeps its trigger fields across a socket '
        'update', () async {
      final c = await _container(const [_restStop]);
      c
          .read(hyperliquidTradingProvider.notifier)
          .applyOrderUpdates([_open(7, limitPx: 56000)]);
      final row = c.read(hyperliquidTradingProvider).value!.openOrders.single;
      expect(row.detailsKnown, isTrue);
      expect(row.isTrigger, isTrue);
      expect(row.orderType, 'Stop Market');
      expect(row.triggerPx, 60000);
      expect(row.reduceOnly, isTrue);
      expect(row.limitPx, 56000);
    });

    test('the REST row replacing a socket-only row counts as a change', () {
      const ws = HlOpenOrder(
        coin: 'BTC',
        oid: 7,
        isBuy: false,
        limitPx: 57000,
        sz: 0.5,
        origSz: 0.5,
        timestamp: 1000,
        cloid: null,
        reduceOnly: true,
        orderType: 'Stop Market',
        isTrigger: true,
        triggerPx: 60000,
        detailsKnown: false,
      );
      expect(hlOpenOrderListEquals(const [ws], const [_restStop]), isFalse);
    });
  });

  group('modify refuses what the chart must never send', () {
    test('a trigger is never re-sent as a limit', () {
      const asLimit = HlOpenOrder(
        coin: 'BTC',
        oid: 7,
        isBuy: false,
        limitPx: 57000,
        sz: 0.5,
        origSz: 0.5,
        timestamp: 1000,
        cloid: null,
        reduceOnly: true,
        orderType: 'Limit',
        isTrigger: false,
        triggerPx: null,
      );
      expect(() => hlCheckModifiable(asLimit, const [_restStop]),
          throwsStateError);
      expect(() => hlCheckModifiable(_restStop, const [_restStop]),
          returnsNormally);
    });

    test('a trailing stop and an unnamed trigger cannot be moved', () {
      const trail = HlOpenOrder(
        coin: 'BTC',
        oid: 8,
        isBuy: false,
        limitPx: 0,
        sz: 0.5,
        origSz: 0.5,
        timestamp: 1,
        cloid: null,
        reduceOnly: true,
        orderType: 'Trailing Stop Market',
        isTrigger: true,
        triggerPx: 60000,
      );
      const unnamed = HlOpenOrder(
        coin: 'BTC',
        oid: 9,
        isBuy: false,
        limitPx: 0,
        sz: 0.5,
        origSz: 0.5,
        timestamp: 1,
        cloid: null,
        reduceOnly: true,
        orderType: 'Trigger',
        isTrigger: true,
        triggerPx: 60000,
      );
      expect(() => hlCheckModifiable(trail, const []), throwsStateError);
      expect(() => hlCheckModifiable(unnamed, const []), throwsStateError);
    });
  });

  group('trailing-stop lookup', () {
    const sentAt = 1700000000000;
    HyperliquidModel model({
      List<Map<String, dynamic>> open = const [],
      List<Map<String, dynamic>> history = const [],
      bool historyFails = false,
    }) =>
        HyperliquidModel(
            client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (body['type'] == 'frontendOpenOrders') {
            return http.Response(jsonEncode(open), 200);
          }
          if (body['type'] == 'historicalOrders') {
            if (historyFails) return http.Response('oops', 500);
            return http.Response(jsonEncode(history), 200);
          }
          return http.Response('[]', 200);
        }));
    Map<String, dynamic> trail({int at = sentAt + 400}) => {
          'coin': 'BTC',
          'oid': 3,
          'side': 'A',
          'limitPx': '0',
          'sz': '0.5',
          'origSz': '0.5',
          'timestamp': at,
          'reduceOnly': true,
          'orderType': 'Trailing Stop Market',
          'isTrigger': false,
        };

    Future<TrailingStopVenueState> look(HyperliquidModel m) =>
        hlLookupTrailingStop(
            model: m, address: '0xabc', market: _btc, sentAtMs: sentAt);

    test('resting: found', () async {
      expect(await look(model(open: [trail()])), TrailingStopVenueState.found);
    });
    test('already triggered (in the history): found', () async {
      expect(
          await look(model(history: [
            {'order': trail(), 'status': 'triggered', 'statusTimestamp': 1}
          ])),
          TrailingStopVenueState.found);
    });
    test('an older trailing stop is not this send: absent', () async {
      expect(await look(model(open: [trail(at: sentAt - 60000)])),
          TrailingStopVenueState.absent);
    });
    test('a list that cannot be read throws (the guard keeps blocking)',
        () async {
      await expectLater(look(model(historyFails: true)), throwsA(anything));
    });
  });
}
