// lib/services/funding/settlement_funding_probes.dart
//
// Funding source probes for the settlement reconciler (Phase 5 plan B7,
// B8). They read public data only (a Bitcoin Esplora API and the
// Polymarket relayer) and never move funds, sign, rebroadcast or read a
// secret.
//
//  - Ledger Bitcoin: the persisted txid seen in the mempool or a block
//    means funded. An input spent by another transaction with at least one
//    confirmation means the funding transaction can never confirm. A
//    mempool-only conflict can still be replaced, so it proves nothing.
//  - Polymarket relayer: the persisted relayer transaction id, read from
//    the relayer `/transaction` endpoint.

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:kute/services/api/api_client.dart';
import 'package:kute/services/funding/settlement_reconciler.dart'
    show BitcoinFundingProbe, FundingSourceProbe;

/// The spend of one outpoint as the chain reports it.
class BitcoinOutspend {
  const BitcoinOutspend({
    required this.spent,
    this.spendingTxid,
    this.confirmed = false,
  });

  final bool spent;

  /// Lowercase txid of the spending transaction, when spent.
  final String? spendingTxid;

  /// Whether the spending transaction has at least one confirmation.
  final bool confirmed;
}

/// Public chain reads the Bitcoin probe needs.
abstract interface class BitcoinChainReader {
  /// True when [txid] is in the mempool or a block, false when the API
  /// answers that it does not know it, null when it could not be read.
  Future<bool?> transactionKnown(String txid);

  /// The spend of `txid:vout`, or null when it could not be read.
  Future<BitcoinOutspend?> outspend(String txid, int vout);
}

/// [BitcoinChainReader] over the mempool.space Esplora API (mainnet; Ledger
/// funding routes are mainnet only).
class MempoolBitcoinChainReader implements BitcoinChainReader {
  MempoolBitcoinChainReader({ApiClient? api})
      : _api = api ?? ApiClient('https://mempool.space/api');

  final ApiClient _api;

  @override
  Future<bool?> transactionKnown(String txid) async {
    if (!_isTxid(txid)) return null;
    final res = await _api.getRaw('/tx/${txid.toLowerCase()}/status');
    if (res.isSuccess) return true;
    if (res.statusCode == 404) return false;
    return null;
  }

  @override
  Future<BitcoinOutspend?> outspend(String txid, int vout) async {
    if (!_isTxid(txid) || vout < 0) return null;
    final res = await _api.get<Map<String, dynamic>?>(
      '/tx/${txid.toLowerCase()}/outspend/$vout',
      (json) => json is Map<String, dynamic> ? json : null,
    );
    final data = res.data;
    if (!res.isSuccess || data == null) return null;
    final spent = data['spent'] == true;
    final status = data['status'];
    return BitcoinOutspend(
      spent: spent,
      spendingTxid: spent ? data['txid']?.toString().toLowerCase() : null,
      confirmed: status is Map && status['confirmed'] == true,
    );
  }
}

bool _isTxid(String txid) => RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(txid);

/// Classifies what the chain showed for a funding transaction [txid] that
/// spends [inputs]. [outspends] lines up with [inputs]; a null entry could
/// not be read. Positive evidence wins; any failed read without positive
/// evidence is `unavailable`, never a conflict or "no signal".
@visibleForTesting
BitcoinFundingProbe classifyBitcoinFundingProbe({
  required String txid,
  required bool? txKnown,
  required List<BitcoinOutspend?> outspends,
}) {
  final ours = txid.trim().toLowerCase();
  if (txKnown == true) return BitcoinFundingProbe.txidSeen;
  var failed = txKnown == null;
  var conflictUnconfirmed = false;
  for (final spend in outspends) {
    if (spend == null) {
      failed = true;
      continue;
    }
    if (!spend.spent) continue;
    final by = spend.spendingTxid;
    if (by == null || by.isEmpty) {
      failed = true;
    } else if (by == ours) {
      return BitcoinFundingProbe.txidSeen;
    } else if (spend.confirmed) {
      return BitcoinFundingProbe.conflictConfirmed;
    } else {
      conflictUnconfirmed = true;
    }
  }
  if (failed) return BitcoinFundingProbe.unavailable;
  return conflictUnconfirmed
      ? BitcoinFundingProbe.conflictUnconfirmed
      : BitcoinFundingProbe.noSignal;
}

/// Probes a Ledger Bitcoin funding: the persisted [txid] and the persisted
/// [inputs] (`txid:vout`). Reads only.
Future<BitcoinFundingProbe> probeLedgerBitcoinFunding({
  required String txid,
  required List<String> inputs,
  required BitcoinChainReader reader,
}) async {
  if (!_isTxid(txid.trim())) return BitcoinFundingProbe.unavailable;
  final bool? known;
  try {
    known = await reader.transactionKnown(txid.trim());
  } catch (_) {
    return BitcoinFundingProbe.unavailable;
  }
  if (known == true) return BitcoinFundingProbe.txidSeen;
  final spends = <BitcoinOutspend?>[];
  for (final input in inputs) {
    final at = input.lastIndexOf(':');
    final vout = at > 0 ? int.tryParse(input.substring(at + 1)) : null;
    if (at <= 0 || vout == null) {
      spends.add(null);
      continue;
    }
    try {
      spends.add(await reader.outspend(input.substring(0, at), vout));
    } catch (_) {
      spends.add(null);
    }
  }
  return classifyBitcoinFundingProbe(
      txid: txid, txKnown: known, outspends: spends);
}

/// Reads a Polymarket relayer transaction: its upper-case state and the
/// on-chain hash when known. Null when it could not be read.
typedef RelayerTransactionReader = Future<({String state, String? hash})?>
    Function(String relayerTxId);

/// Maps a relayer state the way the Phase 3 executor's `reconcileBatch`
/// does: mined or confirmed is funded; failed, invalid, error or skipped
/// means the batch never moved the funds.
@visibleForTesting
FundingSourceProbe classifyRelayerState(String state) {
  final s = state.toUpperCase();
  if (s.contains('CONFIRMED') || s.contains('MINED') || s == 'DONE') {
    return FundingSourceProbe.confirmed;
  }
  if (s.contains('FAILED') ||
      s.contains('INVALID') ||
      s.contains('ERROR') ||
      s.contains('SKIPPED')) {
    return FundingSourceProbe.provenNotSent;
  }
  return FundingSourceProbe.inconclusive;
}

/// Probes a Ledger Polymarket relayer funding. With no persisted relayer
/// id nothing can be read, which is inconclusive (only a provider order
/// then resolves it). Returns the on-chain hash when the relayer has one.
Future<({FundingSourceProbe probe, String? txHash})> probeRelayerFunding(
  String? relayerTxId,
  RelayerTransactionReader read,
) async {
  final id = relayerTxId?.trim() ?? '';
  if (id.isEmpty) {
    return (probe: FundingSourceProbe.inconclusive, txHash: null);
  }
  final ({String state, String? hash})? state;
  try {
    state = await read(id);
  } catch (_) {
    return (probe: FundingSourceProbe.unavailable, txHash: null);
  }
  if (state == null) {
    return (probe: FundingSourceProbe.unavailable, txHash: null);
  }
  final probe = classifyRelayerState(state.state);
  return (
    probe: probe,
    txHash: probe == FundingSourceProbe.confirmed ? state.hash : null,
  );
}
