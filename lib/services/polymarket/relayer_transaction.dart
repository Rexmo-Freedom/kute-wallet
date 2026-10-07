/// Select the exact relayer operation requested by ID. List order, nonce
/// advancement, a wallet balance or a bare transaction hash cannot identify
/// a particular withdrawal. An ambiguous response must remain pending.
/// Schema: Polymarket/builder-relayer-client src/types.ts RelayerTransaction.
Map<String, dynamic>? relayerTransactionForId(Object? payload, String id) {
  if (id.isEmpty) return null;
  final rows = payload is List ? payload : [payload];
  Map<String, dynamic>? match;
  for (final row in rows) {
    if (row is! Map || row['transactionID'] != id) continue;
    if (match != null || row.keys.any((key) => key is! String)) return null;
    match = Map<String, dynamic>.from(row);
  }
  return match;
}
