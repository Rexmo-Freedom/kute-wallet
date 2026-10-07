import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/services/polymarket_backend_service.dart';

void main() {
  final service = PolymarketBackendService(
    apiKey: 'test',
    secret: 'dGVzdA==',
    passphrase: 'test',
    walletAddress: '0xtest',
  );

  Future<void> cancel(String body, {bool all = false}) => http.runWithClient(
        () => all ? service.cancelAllOrders() : service.cancelOrder('order-1'),
        () => MockClient((request) async {
          expect(request.method, 'DELETE');
          expect(request.url.path, all ? '/cancel-all' : '/order');
          return http.Response(body, 200);
        }),
      );

  test('confirmed individual cancellation succeeds', () async {
    await cancel('{"canceled":["order-1"],"not_canceled":{}}');
  });

  test('HTTP success with rejected cancellation fails', () async {
    await expectLater(
        cancel('{"canceled":[],"not_canceled":{"order-1":"matched"}}'),
        throwsStateError);
  });

  test('missing confirmation for the requested order fails', () async {
    await expectLater(
        cancel('{"canceled":["other"],"not_canceled":{}}'), throwsStateError);
  });

  test('partial bulk cancellation fails rather than claiming success',
      () async {
    await expectLater(
        cancel('{"canceled":["order-1"],"not_canceled":{"order-2":"matched"}}',
            all: true),
        throwsStateError);
  });

  test('bulk cancellation with nothing left succeeds', () async {
    await cancel('{"canceled":[],"not_canceled":{}}', all: true);
  });
  Map<String, Object> order(String id) => {
        'id': id,
        'market': 'market',
        'asset_id': 'asset',
        'owner': 'owner',
        'side': 'BUY',
        'price': '0.50',
        'original_size': '10',
        'size_matched': '0',
        'outcome': 'Yes',
      };

  test('open orders follows pagination and keeps market filtering', () async {
    var calls = 0;
    final orders = await http.runWithClient(
      () => service.getOpenOrders(market: 'market'),
      () => MockClient((request) async {
        expect(request.url.path, '/data/orders');
        expect(request.url.queryParameters['market'], 'market');
        calls++;
        expect(request.url.queryParameters['next_cursor'],
            calls == 1 ? null : 'page-2');
        return http.Response(
            jsonEncode({
              'data': [order('order-$calls')],
              'next_cursor': calls == 1 ? 'page-2' : 'LTE=',
            }),
            200);
      }),
    );
    expect(orders.map((o) => o.id), ['order-1', 'order-2']);
    expect(calls, 2);
  });

  test('open order failure is not an empty successful response', () async {
    await http.runWithClient(
      () => expectLater(service.getOpenOrders(), throwsStateError),
      () => MockClient((_) async => http.Response('unavailable', 503)),
    );
  });

  test('repeated pagination cursor fails instead of looping', () async {
    await http.runWithClient(
      () => expectLater(service.getOpenOrders(), throwsStateError),
      () => MockClient(
          (_) async => http.Response('{"data":[],"next_cursor":"same"}', 200)),
    );
  });
}
