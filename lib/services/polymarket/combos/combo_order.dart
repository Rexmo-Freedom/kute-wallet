// lib/services/polymarket/combos/combo_order.dart
//
// RFQ request bodies, quote parsing with the money-safety checks, and the
// Exchange v3 requester order a deposit wallet signs to accept a quote.
//
// The order is the same 11-field Order struct the CLOB V2 path signs
// (polymarket_order_v2.dart), with three differences (docs.polymarket.com
// /trading/combos/requesters.md, "Build and Sign the Requester Order"):
//   * EIP-712 domain "Polymarket CTF Exchange" version "3", verifying
//     contract Exchange v3;
//   * `timestamp` is Unix SECONDS (the CLOB V2 order uses milliseconds);
//   * `builder` is the zero bytes32 on the Requester API (the Builder
//     Gateway's `builder_code` otherwise).
// A deposit wallet (signatureType 3, maker = signer = deposit wallet) wraps
// it in TypedDataSign (ERC-7739), exactly as `signOrderV2Poly1271` does.

import 'dart:convert';
import 'dart:math';

import 'package:kute/constants/polymarket_constants.dart';
import 'package:kute/services/polymarket/combos/combo_ids.dart';
import 'package:kute/services/polymarket/combos/combo_models.dart';
import 'package:kute/services/polymarket_order_v2.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show EthPrivateKey;

const int kComboSignatureTypePoly1271 = 3;

/// A quote the app refuses to sign: it does not match what was asked.
/// English on purpose; screens show a generic "quote changed" line.
class ComboQuoteMismatch implements Exception {
  const ComboQuoteMismatch(this.field);
  final String field;
  @override
  String toString() => 'Combo quote mismatch: $field';
}

/// The `POST /requests` body. [legPositionIds] must already be canonical
/// ([ComboIds.canonicalLegs]). BUY sizes a pUSD budget including fees
/// (`notional`); SELL sizes combo shares (`shares`).
String comboRequestBody({
  required String depositWallet,
  required List<String> legPositionIds,
  required ComboDirection direction,
  required BigInt sizeE6,
}) =>
    jsonEncode({
      'signer_address': depositWallet,
      'maker_address': depositWallet,
      'signature_type': kComboSignatureTypePoly1271,
      'leg_position_ids': legPositionIds,
      'direction': direction.wire,
      'side': 'YES',
      'requested_size': {
        'unit': direction == ComboDirection.buy ? 'notional' : 'shares',
        'value_e6': sizeE6.toString(),
      },
    });

BigInt _e6(dynamic v, String field) {
  final s = v?.toString() ?? '';
  final parsed = BigInt.tryParse(s);
  if (parsed == null || parsed.isNegative) throw ComboQuoteMismatch(field);
  return parsed;
}

/// Parses a create response and checks it against what was asked before
/// anything can be signed:
///   * the echoed direction, legs and requested size match the request;
///   * the YES position is the combo the legs derive to (so the order can
///     only ever trade the combo the user picked);
///   * BUY: the stake fits the budget and covers the order's collateral;
///     SELL: no more shares than asked, proceeds no more than the gross;
///   * the price is strictly between 0 and 1 and the window is still open.
/// Throws [ComboQuoteMismatch] on any failure.
ComboRfqResult parseComboCreateResponse(
  Map<String, dynamic> json, {
  required List<String> legPositionIds,
  required ComboDirection direction,
  required BigInt sizeE6,
  DateTime? now,
}) {
  final status = '${json['status'] ?? ''}'.toUpperCase();
  final quote = json['quote'];
  if (quote is! Map<String, dynamic>) {
    final error = json['error'];
    final code = error is Map ? '${error['code'] ?? ''}' : '';
    return ComboNoQuote(code.isEmpty ? (status.isEmpty ? 'FAILED' : status) : code);
  }
  final request = json['request'];
  if (request is! Map<String, dynamic>) {
    throw const ComboQuoteMismatch('request');
  }
  final rfqId = '${json['rfq_id'] ?? ''}';
  if (rfqId.isEmpty || '${request['rfq_id'] ?? rfqId}' != rfqId) {
    throw const ComboQuoteMismatch('rfq_id');
  }
  if ('${request['direction'] ?? ''}'.toUpperCase() != direction.wire) {
    throw const ComboQuoteMismatch('direction');
  }
  if ('${request['side'] ?? 'YES'}'.toUpperCase() != 'YES') {
    throw const ComboQuoteMismatch('side');
  }
  final echoedLegs = (request['leg_position_ids'] is List
          ? request['leg_position_ids'] as List
          : const [])
      .map((e) => '$e')
      .toList();
  final List<String> canonicalEcho;
  try {
    canonicalEcho = ComboIds.canonicalLegs(echoedLegs);
  } on ComboLegsException {
    throw const ComboQuoteMismatch('leg_position_ids');
  }
  if (canonicalEcho.length != legPositionIds.length ||
      [for (var i = 0; i < canonicalEcho.length; i++) i]
          .any((i) => canonicalEcho[i] != legPositionIds[i])) {
    throw const ComboQuoteMismatch('leg_position_ids');
  }
  final size = request['requested_size'];
  if (size is! Map ||
      '${size['unit']}' !=
          (direction == ComboDirection.buy ? 'notional' : 'shares') ||
      BigInt.tryParse('${size['value_e6']}') != sizeE6) {
    throw const ComboQuoteMismatch('requested_size');
  }
  final derived = ComboIds.derive(legPositionIds);
  final yes = '${request['yes_position_id'] ?? ''}';
  if (BigInt.tryParse(yes)?.toString() != derived.yesPositionId) {
    throw const ComboQuoteMismatch('yes_position_id');
  }
  final cond = '${request['condition_id'] ?? derived.conditionId}'.toLowerCase();
  if (cond != derived.conditionId) {
    throw const ComboQuoteMismatch('condition_id');
  }

  final quoteId = '${quote['quote_id'] ?? ''}';
  if (quoteId.isEmpty) throw const ComboQuoteMismatch('quote_id');
  final blended = _e6(quote['blended_price_e6'], 'blended_price_e6');
  final maker = _e6(quote['maker_amount_e6'], 'maker_amount_e6');
  final taker = _e6(quote['taker_amount_e6'], 'taker_amount_e6');
  final total = _e6(quote['total_required_e6'], 'total_required_e6');
  final net = _e6(quote['net_receive_e6'], 'net_receive_e6');
  final one = BigInt.from(1000000);
  if (blended <= BigInt.zero || blended >= one) {
    throw const ComboQuoteMismatch('blended_price_e6');
  }
  if (maker <= BigInt.zero || taker <= BigInt.zero || net <= BigInt.zero) {
    throw const ComboQuoteMismatch('amounts');
  }
  if (direction == ComboDirection.buy) {
    // The stake never exceeds the budget and covers the order's own
    // collateral; the shares bought are at most what the order receives.
    if (total > sizeE6 || total < maker) {
      throw const ComboQuoteMismatch('total_required_e6');
    }
    // Paying more than $1 per share can never be a fair combo price.
    if (maker >= taker) throw const ComboQuoteMismatch('price');
  } else {
    // Never sell more shares than asked; proceeds are net of fees.
    if (maker > sizeE6 || total > sizeE6 || maker > total) {
      throw const ComboQuoteMismatch('maker_amount_e6');
    }
    if (net > taker || taker >= maker) {
      throw const ComboQuoteMismatch('net_receive_e6');
    }
  }
  final expiresMs = int.tryParse('${json['expires_at'] ?? ''}');
  if (expiresMs == null) throw const ComboQuoteMismatch('expires_at');
  final expiresAt = DateTime.fromMillisecondsSinceEpoch(expiresMs);
  if (!expiresAt.isAfter(now ?? DateTime.now())) {
    throw const ComboQuoteMismatch('expires_at');
  }
  final builderCode = json['builder_code'];
  return ComboQuoted(ComboQuote(
    rfqId: rfqId,
    quoteId: quoteId,
    direction: direction,
    expiresAt: expiresAt,
    comboConditionId: derived.conditionId,
    yesPositionId: derived.yesPositionId,
    legPositionIds: legPositionIds,
    requestedE6: sizeE6,
    blendedPriceE6: blended,
    makerAmountE6: maker,
    takerAmountE6: taker,
    totalRequiredE6: total,
    netReceiveE6: net,
    builderCode: builderCode is String && builderCode.isNotEmpty
        ? builderCode
        : null,
  ));
}

/// A random 64-bit salt, as `@polymarket/client` draws it.
BigInt comboOrderSalt([Random? random]) {
  final r = random ?? Random.secure();
  var v = BigInt.zero;
  for (var i = 0; i < 8; i++) {
    v = (v << 8) | BigInt.from(r.nextInt(256));
  }
  return v;
}

/// The Exchange v3 requester order for [quote], unsigned. [builder] is the
/// zero bytes32 unless the route attributes builders.
OrderStructV2 buildComboOrder({
  required ComboQuote quote,
  required String depositWallet,
  String builder = PolymarketConstants.bytes32Zero,
  BigInt? salt,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  return OrderStructV2(
    salt: salt ?? comboOrderSalt(),
    maker: depositWallet,
    signer: depositWallet,
    tokenId: quote.yesPositionId,
    makerAmount: quote.makerAmountE6,
    takerAmount: quote.takerAmountE6,
    side: quote.isBuy ? 0 : 1,
    signatureType: kComboSignatureTypePoly1271,
    // Exchange v3: Unix SECONDS.
    timestamp: BigInt.from(at.millisecondsSinceEpoch ~/ 1000),
    metadata: PolymarketConstants.bytes32Zero,
    builder: builder,
  );
}

/// Signs [order] for a deposit wallet under Exchange v3 and returns the
/// `signed_order` object the accept endpoint takes.
Future<Map<String, dynamic>> signComboOrder({
  required OrderStructV2 order,
  required EthPrivateKey credentials,
}) async {
  if (order.signatureType != kComboSignatureTypePoly1271 ||
      order.maker.toLowerCase() != order.signer.toLowerCase()) {
    throw const ComboQuoteMismatch('signer');
  }
  final signature = await signOrderV2Poly1271(
    order: order,
    credentials: credentials,
    verifyingContract: PolymarketConstants.comboExchangeV3Address,
    domainVersion: PolymarketConstants.comboExchangeEip712DomainVersion,
  );
  return {...order.toJson(), 'signature': signature};
}

/// The `POST /requests/{rfq_id}/accept` body.
String comboAcceptBody({
  required String quoteId,
  required Map<String, dynamic> signedOrder,
}) =>
    jsonEncode({'quote_id': quoteId, 'signed_order': signedOrder});
