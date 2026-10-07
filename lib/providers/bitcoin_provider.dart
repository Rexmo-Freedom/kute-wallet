import 'dart:async';

import 'package:kute/models/bitcoin_model.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/send_tx_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/providers/wallet_scope_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart';
import 'package:kute/models/onchain_types.dart';
import 'package:kute/services/bitcoin/bitcoin_fee_estimate_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'bitcoin_config_provider.dart';

final bitcoinProvider = FutureProvider<Bitcoin>((ref) async {
  final session = await ref.watch(restoreWalletProvider.future);
  final config = await ref.read(bitcoinConfigProvider.future);
  return Bitcoin(session, config.network,
      needsFullScan:
          session.needsInitialScan || !_firstScanDone(ref, config.walletId),
      electrumUrl: config.electrumUrl);
});

/// Has [walletId] already completed its one-time first full scan?
/// Read from the persisted WalletConfig (settings). Defaults to false
/// (→ full scan) for an unknown id or a wallet that predates the flag.
bool _firstScanDone(Ref ref, String? walletId) {
  if (walletId == null) return false;
  for (final w in ref.read(settingsProvider).wallets) {
    if (w.id == walletId) return w.firstScanDone;
  }
  return false;
}

final bitcoinModelProvider = FutureProvider<BitcoinModel>((ref) async {
  final bitcoin = await ref.watch(bitcoinProvider.future);
  return BitcoinModel(bitcoin);
});

final lastUsedAddressProviderString = FutureProvider.autoDispose<String>((ref) async {
  final bitcoinModel = await ref.watch(bitcoinModelProvider.future);
  return bitcoinModel.getAddressString();
});

final getBitcoinTransactionsProvider = FutureProvider<List<TxDetails>>((ref) async {
  final bitcoinModel = await ref.watch(bitcoinModelProvider.future);
  return bitcoinModel.getTransactions();
});

/// The wallet whose coins the send flow can pick from: the scoped wallet
/// on a detail screen, else the active one. A plain id so a settings
/// write that leaves the wallet untouched does not reload the coins.
/// Null when that wallet has no BDK session (Spark, tracked, signer).
final _coinSelectionWalletProvider = Provider.autoDispose<String?>((ref) {
  final wallet = scopedOperationalWallet(ref);
  return wallet != null && wallet.usesBdk ? wallet.id : null;
});

/// Spendable coins of the picked wallet, read through that wallet's own
/// native session. Refresh edges are the wallet's cache slots (written by
/// `BackgroundSyncService` after every scan, cold wallets included) plus
/// the spending wallet's notifiers, so a cold wallet's list is current and
/// the active wallet still follows a new confirmed or pending transaction.
final unspentUtxosProvider =
    FutureProvider.autoDispose<List<LocalOutput>>((ref) async {
  final walletId = ref.watch(_coinSelectionWalletProvider);
  if (walletId == null) return [];
  ref.watch(walletBalanceCacheProvider.select((cache) => cache[walletId]));
  ref.watch(
      walletTransactionCacheProvider.select((cache) => cache[walletId]));
  ref.watch(transactionNotifierProvider);
  ref.watch(balanceNotifierProvider);
  final model = await ref.watch(bitcoinModelForWalletProvider(walletId).future);
  return model.listUnspent();
});

/// Recommended fee rates, independent of any wallet. A good result is
/// kept for about a minute after its last listener goes away; a failure
/// is never kept: the provider re-runs by itself after 15 seconds so the
/// review recovers without the user leaving the screen.
final bitcoinFeeRatePerBlockProvider =
    FutureProvider.autoDispose<BitcoinFeeModel>((ref) async {
  final link = ref.keepAlive();
  Timer? timer;
  ref.onDispose(() => timer?.cancel());
  try {
    final fees = await BitcoinFeeEstimateService.instance.fetch();
    timer = Timer(
        fees.isStale ? const Duration(seconds: 15) : const Duration(seconds: 60),
        link.close);
    return fees;
  } catch (_) {
    link.close();
    timer = Timer(const Duration(seconds: 15), ref.invalidateSelf);
    rethrow;
  }
});

final getCustomFeeRateProvider = FutureProvider.autoDispose<double>((ref) async {
  final customFee = ref.watch(customFeeRateProvider);
  if (customFee != null && customFee.isFinite && customFee > 0) {
    return customFee;
  }

  final blocks = ref.watch(sendBlocksProvider);
  final feeRate = await ref.watch(bitcoinFeeRatePerBlockProvider.future);

  switch (blocks) {
    case 1:
      return feeRate.fastestFee;
    case 2:
      return feeRate.halfHourFee;
    case 3:
      return feeRate.hourFee;
    case 4:
      return feeRate.economyFee;
    case 5:
      return feeRate.minimumFee;
    default:
      return feeRate.fastestFee;
  }
});

