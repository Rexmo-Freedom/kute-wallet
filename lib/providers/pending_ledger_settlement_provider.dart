// lib/providers/pending_ledger_settlement_provider.dart
//
// Read-only lookups of pending Ledger settlement operations for the UI
// (Phase 5 plan B13): a pending Ledger operation keeps the Ledger account
// reachable from Activity detail even when the Ledger release flag is off.
// Nothing here writes a record or moves funds.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/settlement_operation.dart';
import 'package:kute/services/funding/settlement_store.dart';

Future<List<SettlementOperation>> _pendingLedgerOperations() async {
  try {
    final store = await SettlementStore.shared();
    return (await store.pendingForReconcile())
        .where((op) => op.accountKind.isLedger)
        .toList();
  } catch (_) {
    return const [];
  }
}

/// The pending Ledger operation whose Bitcoin funding transaction is
/// [txid], or null.
final pendingLedgerSettlementForTxidProvider = FutureProvider.autoDispose
    .family<SettlementOperation?, String>((ref, txid) async {
  final wanted = txid.trim().toLowerCase();
  if (wanted.isEmpty) return null;
  for (final op in await _pendingLedgerOperations()) {
    if (op.funding?.btcTxid?.toLowerCase() == wanted) return op;
  }
  return null;
});

/// Whether Ledger wallet [walletId] has any pending settlement operation.
final walletHasPendingLedgerSettlementProvider =
    FutureProvider.autoDispose.family<bool, String>((ref, walletId) async {
  for (final op in await _pendingLedgerOperations()) {
    if (op.walletId == walletId) return true;
  }
  return false;
});
