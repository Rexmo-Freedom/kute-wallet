// The signed Polymarket order a standing order keeps: its JSON round
// trip, its figures, and a hash that is the order's own.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/constants/polymarket_constants.dart';
import 'package:kute/services/polymarket_order_v2.dart';
import 'package:kute/services/standing_orders/polymarket_signed_order.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show OrderType;

OrderStructV2 _order({BigInt? maker}) => OrderStructV2(
      salt: BigInt.from(12345),
      maker: '0x${'ab' * 20}',
      signer: '0x${'ab' * 20}',
      tokenId: '111',
      makerAmount: maker ?? BigInt.from(10000000),
      takerAmount: BigInt.from(19230000),
      side: 0,
      signatureType: 3,
      timestamp: BigInt.from(1794000000000),
      metadata: PolymarketConstants.bytes32Zero,
      builder: PolymarketConstants.bytes32Zero,
    );

void main() {
  test('round-trips through JSON and reads its figures', () {
    final signed = SignedOrderV2(order: _order(), signature: '0x${'cd' * 65}');
    final hash =
        polymarketOrderHash(signed.order, PolymarketConstants.exchangeAddress);
    final standing = StandingSignedOrder(
      signed: signed,
      exchange: PolymarketConstants.exchangeAddress,
      orderType: OrderType.fak,
      negRisk: false,
      orderHash: hash,
    );
    final back = StandingSignedOrder.fromJson(standing.toJson())!;
    expect(back.orderHash, hash);
    expect(back.exchange, PolymarketConstants.exchangeAddress);
    expect(back.orderType, OrderType.fak);
    expect(back.signed.signature, signed.signature);
    expect(back.order.toJson(), signed.order.toJson());
    expect(back.spendUsd, closeTo(10, 1e-9));
    expect(back.shares, closeTo(19.23, 1e-9));
    expect(back.price, closeTo(10 / 19.23, 1e-9));
    expect(back.isBuy, isTrue);
    expect(back.tokenId, '111');
    expect(StandingSignedOrder.fromJson({'venue': 'investing'}), isNull);
  });

  test('the hash is the order\'s own: another amount, another hash', () {
    final a = polymarketOrderHash(_order(), PolymarketConstants.exchangeAddress);
    final b = polymarketOrderHash(
        _order(maker: BigInt.from(10010000)), PolymarketConstants.exchangeAddress);
    expect(a, matches(RegExp(r'^0x[0-9a-f]{64}$')));
    expect(a, isNot(b));
    // The same order again hashes the same: posting it twice can match once.
    expect(polymarketOrderHash(_order(), PolymarketConstants.exchangeAddress), a);
  });
}
