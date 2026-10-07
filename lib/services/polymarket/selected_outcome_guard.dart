// lib/services/polymarket/selected_outcome_guard.dart
//
// The last check before a prediction is signed: the token the order buys
// must be the token of the outcome the person selected, read by index
// from the same outcome list the slip draws its cards from. The label,
// the colour and the order all come from that one index; this makes a
// disagreement stop the order instead of buying the other side.

import 'package:kute/models/polymarket_model.dart';

/// The order about to be signed does not buy the selected outcome.
/// Nothing was signed or sent.
class PolymarketSideMismatch implements Exception {
  const PolymarketSideMismatch();

  @override
  String toString() => 'The order does not buy the selected outcome.';
}

/// The token the selection names: the outcome at [selectedIndex], its No
/// token when [buyNo] picks the No side of a sub-market. Null when the
/// index is out of range or the outcome has no such token.
String? polymarketSelectedTokenId(
  List<PolymarketOutcome> outcomes,
  int selectedIndex, {
  required bool buyNo,
}) {
  if (selectedIndex < 0 || selectedIndex >= outcomes.length) return null;
  final o = outcomes[selectedIndex];
  final token = buyNo ? o.noTokenId : o.tokenId;
  return token == null || token.isEmpty ? null : token;
}

/// Throws [PolymarketSideMismatch] unless [orderedTokenId] is the token of
/// the selected outcome (see [polymarketSelectedTokenId]).
void ensureOrderBuysSelectedOutcome({
  required String orderedTokenId,
  required List<PolymarketOutcome> outcomes,
  required int selectedIndex,
  required bool buyNo,
}) {
  final expected =
      polymarketSelectedTokenId(outcomes, selectedIndex, buyNo: buyNo);
  if (expected == null ||
      orderedTokenId.isEmpty ||
      expected != orderedTokenId) {
    throw const PolymarketSideMismatch();
  }
}
