import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/bitcoin_model.dart';
import 'package:kute/models/onchain_types.dart';
import 'package:kute/providers/bitcoin_provider.dart';
import 'package:kute/providers/send_tx_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart';
import 'package:kute/services/bitcoin/fee_draft_while_syncing.dart';

typedef BitcoinSoftwareSendRequest = ({
  String walletId,
  String address,
  int amount,
  bool drain,
});

/// The preview and the send consume this same wallet-bound PSBT. Changing the
/// destination, amount, fee or coin selection creates a new review to approve.
/// A scan in flight no longer fails the preview: the build waits for the
/// wallet's native slot, so the review stays on its loading state instead.
final bitcoinSoftwareSendPreviewProvider = FutureProvider.autoDispose
    .family<Psbt, BitcoinSoftwareSendRequest>((ref, request) async {
  final feeFuture = ref.watch(getCustomFeeRateProvider.future);
  final utxos = List<OutPoint>.unmodifiable(ref.watch(selectedUtxosProvider));
  final modelFuture =
      ref.watch(bitcoinModelForWalletProvider(request.walletId).future);
  final fee = await feeFuture;
  final model = await modelFuture;
  final transaction = TransactionBuilder(request.amount, request.address, fee,
      selectedUtxos: utxos.isEmpty ? null : utxos);
  return buildPsbtWhenIdle(model, transaction, drain: request.drain);
});
