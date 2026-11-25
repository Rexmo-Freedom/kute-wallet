// lib/services/standing_orders/polymarket_signed_order.dart
//
// The signed Polymarket order a standing order keeps in secure storage:
// the V2 order struct and its signature, the exchange it was signed for,
// the order type and the hash the venue files it under. Signed ONCE at
// the accept under the person's approval; posted later as is, so the
// price can never be worse than the one approved (the signed limit IS the
// approval) and the hash can match at most once at the venue.

import 'package:kute/services/polymarket_order_v2.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show OrderType;

Map<String, Object?> signedOrderV2ToJson(SignedOrderV2 signed) => {
      'order': signed.order.toJson(),
      'signature': signed.signature,
    };

SignedOrderV2 signedOrderV2FromJson(Map<String, Object?> json) {
  final o = (json['order'] as Map).cast<String, Object?>();
  return SignedOrderV2(
    order: OrderStructV2(
      salt: BigInt.parse('${o['salt']}'),
      maker: o['maker'] as String,
      signer: o['signer'] as String,
      tokenId: o['tokenId'] as String,
      makerAmount: BigInt.parse('${o['makerAmount']}'),
      takerAmount: BigInt.parse('${o['takerAmount']}'),
      side: o['side'] as int,
      signatureType: o['signatureType'] as int,
      timestamp: BigInt.parse('${o['timestamp']}'),
      metadata: o['metadata'] as String,
      builder: o['builder'] as String,
    ),
    signature: json['signature'] as String,
  );
}

/// The hash of [order] under [exchange]'s domain: the id the venue files
/// it under, as `HotPolymarketOrderGuard` computes it before any POST.
String polymarketOrderHash(OrderStructV2 order, String exchange) {
  final digest =
      orderV2TypedData(order: order, verifyingContract: exchange).digest;
  return '0x${digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
}

class StandingSignedOrder {
  const StandingSignedOrder({
    required this.signed,
    required this.exchange,
    required this.orderType,
    required this.negRisk,
    required this.orderHash,
  });

  final SignedOrderV2 signed;
  final String exchange;
  final OrderType orderType;
  final bool negRisk;
  final String orderHash;

  OrderStructV2 get order => signed.order;
  String get tokenId => order.tokenId;

  /// What the order spends (a buy's makerAmount), in dollars.
  double get spendUsd => order.side == 0
      ? order.makerAmount.toDouble() / 1e6
      : order.takerAmount.toDouble() / 1e6;

  /// The shares it asks for at its limit (a buy's takerAmount).
  double get shares => order.side == 0
      ? order.takerAmount.toDouble() / 1e6
      : order.makerAmount.toDouble() / 1e6;

  /// The signed limit price.
  double get price => order.price;

  bool get isBuy => order.side == 0;

  Map<String, Object?> toJson() => {
        'venue': 'predictions',
        'signedOrder': signedOrderV2ToJson(signed),
        'exchange': exchange,
        'orderType': orderType.name,
        'negRisk': negRisk,
        'orderHash': orderHash,
      };

  static StandingSignedOrder? fromJson(Map<String, Object?> json) {
    try {
      if (json['venue'] != 'predictions') return null;
      return StandingSignedOrder(
        signed: signedOrderV2FromJson(
            (json['signedOrder'] as Map).cast<String, Object?>()),
        exchange: json['exchange'] as String,
        orderType:
            OrderType.values.firstWhere((t) => t.name == json['orderType']),
        negRisk: json['negRisk'] as bool? ?? false,
        orderHash: json['orderHash'] as String,
      );
    } catch (_) {
      return null;
    }
  }
}
