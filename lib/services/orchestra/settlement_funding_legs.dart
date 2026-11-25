// lib/services/orchestra/settlement_funding_legs.dart
//
// The payment that paid for a conversion, as its own settlement record
// names it: a move out of Bitcoin (to Dollars, Investing or Predictions)
// pays Orchestra's deposit address with a Spark transfer, a move out of
// Dollars with a Dollars token transfer, and the runner records that
// payment's id on the operation (`SettlementFunding.sparkPaymentId`)
// before it registers the deposit.
//
// Activity folds that transfer into the conversion's row by the id
// itself ([fundingLegsOf]), before any amount or time match: the send is
// the conversion's, whatever it cost, however long the person took to
// approve it, and whatever the payment details say (a cached row has
// none). Read-only: rendering never writes the store.

import 'package:hive_ce/hive.dart';
import 'package:kute/models/transactions_model.dart' show SwapOrderTransaction;
import 'package:kute/services/funding/settlement_codec.dart'
    show SettlementCodec;
import 'package:kute/services/funding/settlement_store.dart'
    show SettlementStore;

/// The payment id that funded settlement operation [operationId], from its
/// record (null when there is none, or not yet). Test seam.
String? Function(String operationId) settlementFundingPaymentOf =
    _storedFundingPaymentOf;

/// A record's funding never changes once written: kept by operation. A
/// record without it yet is read again only when it changed.
final Map<String, String> _paymentByOperation = {};
final Map<String, int> _unfundedRecord = {};

String? _storedFundingPaymentOf(String operationId) {
  final known = _paymentByOperation[operationId];
  if (known != null) return known;
  try {
    if (!Hive.isBoxOpen(SettlementStore.boxName)) return null;
    final raw = Hive.box<String>(SettlementStore.boxName).get(operationId);
    if (raw == null) return null;
    if (_unfundedRecord[operationId] == raw.hashCode) return null;
    final id = SettlementCodec.decodeJson(raw).funding?.sparkPaymentId;
    if (id == null || id.isEmpty) {
      _unfundedRecord[operationId] = raw.hashCode;
      return null;
    }
    _unfundedRecord.remove(operationId);
    return _paymentByOperation[operationId] = id;
  } catch (_) {
    return null; // unreadable metadata links nothing
  }
}

/// The funding payments of [rows] by payment id, each mapped to the row
/// it paid for ([paymentOf]: [settlementFundingPaymentOf] by default).
Map<String, String> fundingLegsOf(
  Iterable<SwapOrderTransaction> rows, {
  String? Function(String operationId)? paymentOf,
}) {
  final read = paymentOf ?? settlementFundingPaymentOf;
  final legs = <String, String>{};
  for (final row in rows) {
    final op = row.details.operationId;
    if (op == null || op.isEmpty) continue;
    final payment = read(op);
    if (payment == null || payment.isEmpty) continue;
    legs[payment] = row.id;
  }
  return legs;
}
