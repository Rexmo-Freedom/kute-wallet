import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/polymarket_backend_service.dart';
import 'package:kute/services/polymarket_order_v2.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show OrderType;

void main() {
  test('V2 submission includes immediate execution and unsigned wire expiry',
      () {
    const account = '0x1111111111111111111111111111111111111111';
    final order = OrderStructV2(
      salt: BigInt.one,
      maker: account,
      signer: account,
      tokenId: '123',
      makerAmount: BigInt.from(3000000),
      takerAmount: BigInt.from(6000000),
      side: 0,
      signatureType: 3,
      timestamp: BigInt.from(1700000000000),
      metadata: '0x${'0' * 64}',
      builder: '0x${'0' * 64}',
    );
    final service = PolymarketBackendService(
        apiKey: 'fixture-owner',
        secret: 'fixture',
        passphrase: 'fixture',
        walletAddress: account);
    final signed = SignedOrderV2(order: order, signature: 'fixture-signature');
    for (final type in [OrderType.gtc, OrderType.fok, OrderType.fak]) {
      final body =
          service.buildOrderPostBody(signedOrder: signed, orderType: type);
      expect(body['deferExec'], isFalse);
      expect(body['owner'], 'fixture-owner');
      expect(body['orderType'], type.toJson());
      final wire = body['order'] as Map;
      expect(wire['expiration'], '0');
      expect(wire['salt'], 1);
      expect(wire['side'], 'BUY');
      expect(wire['signatureType'], 3);
      expect(wire['makerAmount'], '3000000');
      expect(wire['signature'], 'fixture-signature');
    }
    // Expiration is a transport field, not a new field in the signed struct.
    expect(order.toJson().containsKey('expiration'), isFalse);
  });
}
