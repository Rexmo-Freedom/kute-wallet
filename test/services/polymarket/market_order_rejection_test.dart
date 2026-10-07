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
}
