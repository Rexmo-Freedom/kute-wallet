import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_scope_provider.dart';
import 'package:kute/models/send_tx_model.dart';
import 'package:kute/models/onchain_types.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final sendTxProvider =
    StateNotifierProvider.autoDispose<SendTxModel, SendTx>((ref) {
  return SendTxModel(
      SendTx(address: '', amount: 0, type: PaymentType.Unknown, drain: false));
});

final customFeeRateProvider = StateProvider.autoDispose<double?>((ref) {
  return null;
});

final sendBlocksProvider = StateProvider.autoDispose<int>((ref) {
  return 1;
});

/// Empty list means automatic UTXO selection.
final selectedUtxosProvider = StateProvider.autoDispose<List<OutPoint>>((ref) {
  // Never carry a manual selection into a different wallet.
  final scopeId = ref.watch(bdkScopeWalletIdProvider);
  if (scopeId == null) {
    ref.watch(settingsProvider.select((s) => s.activeWalletId));
  }
  return [];
});
