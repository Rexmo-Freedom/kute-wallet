import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/models/onchain_types.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/providers/wallet_scope_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart';
import 'package:kute/services/api/api_client.dart';

/// Identity of the wallet whose coins the tab shows: the scoped wallet on a
/// detail screen, else the active one. A record (structural equality) so a
/// settings write that leaves the wallet untouched does not restart the
/// inventory. Null for Spark and signer wallets, which never open it.
final _coinsWalletProvider =
    Provider.autoDispose<({String id, bool usesBdk})?>((ref) {
  final wallet = scopedOperationalWallet(ref);
  if (wallet == null || wallet.isSparkWallet || wallet.isSigner) return null;
  return (id: wallet.id, usesBdk: wallet.usesBdk);
});

/// Display-only inventory. Tracked addresses have no descriptor or signer;
/// their explorer outputs must never enter the transaction-building provider.
/// BDK wallets read their own native snapshot without an extra API request.
///
/// Refresh edges are the viewed wallet's OWN cache slots, never the spending
/// wallet's notifiers: `BackgroundSyncService` writes both slots after every
/// scan (BDK and tracked address alike), so the tab follows the first scan
/// of a freshly imported wallet and every pull-to-refresh while the spending
/// wallet stays the active one.
final bitcoinCoinsDisplayProvider =
    FutureProvider.autoDispose<List<LocalOutput>>((ref) async {
  final wallet = ref.watch(_coinsWalletProvider);
  if (wallet == null) return [];
  ref.watch(walletBalanceCacheProvider.select((cache) => cache[wallet.id]));
  if (wallet.usesBdk) {
    ref.watch(
        walletTransactionCacheProvider.select((cache) => cache[wallet.id]));
    // Per-wallet model: the same native session the scan loop syncs, so
    // its snapshot already holds the outputs the scan just discovered.
    final model =
        await ref.watch(bitcoinModelForWalletProvider(wallet.id).future);
    return model.listUnspent();
  }
  final client = http.Client();
  ref.onDispose(client.close);
  final address = await AuthModel().getExternalAddress(wallet.id);
  if (address == null || address.isEmpty) {
    throw StateError('Missing tracked address');
  }
  final response = await ApiClient('https://mempool.space/api', client: client)
      .get<List<dynamic>>(
        '/address/${Uri.encodeComponent(address)}/utxo',
        (json) => json as List<dynamic>,
      )
      .timeout(const Duration(seconds: 15));
  if (!response.isSuccess || response.data == null) {
    throw StateError('Unable to load coins');
  }
  return response.data!.map((entry) {
    final row = entry as Map<String, dynamic>;
    final status = row['status'] as Map<String, dynamic>;
    final confirmed = status['confirmed'] == true;
    return LocalOutput(
      outpoint: OutPoint(
          txid: Txid.fromString(hex: row['txid'] as String),
          vout: row['vout'] as int),
      // Explorer inventory does not return scripts/derivation. These snapshots
      // are used only for the Coins view and labels, never PSBT construction.
      txout: TxOut(
          value: Amount.fromSat(sat: row['value'] as int), scriptPubkey: ''),
      keychain: KeychainKind.external_, isSpent: false, derivationIndex: 0,
      chainPosition: confirmed
          ? ConfirmedChainPosition(
              confirmationBlockTime: ConfirmationBlockTime(
                  blockId: BlockId(
                      height: status['block_height'] as int,
                      hash: BlockHash.fromString(
                          hex: status['block_hash'] as String)),
                  confirmationTime: status['block_time'] as int))
          : const UnconfirmedChainPosition(),
    );
  }).toList();
});
