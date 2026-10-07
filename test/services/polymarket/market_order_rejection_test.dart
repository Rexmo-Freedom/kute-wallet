import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kute/services/polymarket_backend_service.dart';

void main() {
  const noFill =
      'no orders found to match with FAK order. FAK orders are partially filled or killed if no match is found.';
  test(
      'documented FAK rejection remains definitive when CLOB returns an order hash',
      () {
    expect(
        isDefinitivePolymarketHttpRejection(http.Response(
            '{"error":"$noFill","orderID":"0x${'e' * 64}"}', 400)),
        isTrue);
    expect(
        isDefinitivePolymarketHttpRejection(
            http.Response('{"error":"$noFill"}', 400)),
        isTrue);
    expect(
        isDefinitivePolymarketHttpRejection(http.Response(
            '{"error":"order match delayed due to market conditions","orderID":"0x${'e' * 64}"}',
            400)),
        isFalse);
    expect(
        isDefinitivePolymarketHttpRejection(
            http.Response('{"error":"$noFill","status":"matched"}', 400)),
        isFalse);
    expect(
        isDefinitivePolymarketHttpRejection(
            http.Response('{"error":"$noFill"}', 502)),
        isFalse);
  });

  group('any other 400 that names an error and no order', () {
    http.Response r(Map<String, Object?> body, [int status = 400]) =>
        http.Response(jsonEncode(body), status);

    test('is a refusal, with the venue\'s words', () {
      final cases = [
        {'error': 'invalid tick size'},
        {'errorMsg': 'the allowance is not enough'},
        {
          'errorMsg': 'order is invalid',
          'orderID': '',
          'success': false,
          'status': '',
          'transactionsHashes': <String>[],
        },
      ];
      for (final body in cases) {
        expect(isDefinitivePolymarketHttpRejection(r(body)), isTrue,
            reason: '$body');
      }
      expect(polymarketHttpRejection(r({'error': 'invalid tick size'})),
          'invalid tick size');
      expect(polymarketHttpRejection(r({'errorMsg': 'order is invalid'})),
          'order is invalid');
    });

    test('but never one that carries an order, a status or a delay', () {
      final cases = [
        {'error': 'something', 'orderID': '0x${'e' * 64}'},
        {'errorMsg': 'something', 'orderId': 'abc'},
        {'errorMsg': 'something', 'status': 'live'},
        {'errorMsg': 'something', 'success': true},
        {
          'errorMsg': 'something',
          'transactionsHashes': ['0x${'f' * 64}']
        },
        {'error': 'order match delayed due to market conditions'},
        {'error': ''},
        {'message': 'no error field'},
      ];
      for (final body in cases) {
        expect(isDefinitivePolymarketHttpRejection(r(body)), isFalse,
            reason: '$body');
      }
    });

    test('and never another status or an unreadable body', () {
      for (final status in [401, 403, 404, 425, 429, 500, 502, 503]) {
        expect(
            isDefinitivePolymarketHttpRejection(
                r({'error': 'invalid tick size'}, status)),
            isFalse,
            reason: '$status');
      }
      expect(isDefinitivePolymarketHttpRejection(http.Response('oops', 400)),
          isFalse);
      expect(isDefinitivePolymarketHttpRejection(http.Response('[1]', 400)),
          isFalse);
    });
  });
}
