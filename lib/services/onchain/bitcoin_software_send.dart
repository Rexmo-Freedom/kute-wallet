import 'package:kute/models/bitcoin_model.dart';
import 'package:kute/models/onchain_types.dart';
import 'package:kute/services/onchain/native_onchain_service.dart';
import 'package:kute/services/bitcoin/bitcoin_transaction_review.dart';

class BitcoinSoftwareSendResult {
  final String txid;
  final int feeSats;
  final int recipientSats;
  const BitcoinSoftwareSendResult(this.txid, this.feeSats, this.recipientSats);
}

/// Operates on one captured wallet model and the exact preview the user approved.
class BitcoinSoftwareSend {
  /// Native BDK drain builds have exactly one output, to the supplied address.
  /// Read its value instead of subtracting the fee from an already-net MAX.
  static int drainRecipientSats(Psbt psbt) {
    final outputs = psbt.extractTx().output();
    if (psbt.extractTx().outputCount != 1 || outputs.length != 1) {
      throw const OnchainException('invalid_transaction');
    }
    final amount = outputs.single.value.toSat();
    if (amount <= 0) throw const OnchainException('insufficient_funds');
    return amount;
  }

  static Future<BitcoinSoftwareSendResult> send({
    required BitcoinModel model,
    required TransactionBuilder transaction,
    required bool drain,
    required bool Function() isCurrent,
    Psbt? reviewedPsbt,
  }) async {
    void checkCurrent() {
      if (!isCurrent()) throw const OnchainException('wallet_mismatch');
    }

    checkCurrent();
    final unsigned = reviewedPsbt ??
        (drain
            ? await model.drainWalletBitcoinTransaction(transaction)
            : await model.buildBitcoinTransaction(transaction));
    checkCurrent();
    final fee = unsigned.fee();
    final recipient = reviewedBitcoinRecipientSats(
      unsigned,
      transaction.outAddress,
      mainnet: model.config.network == Network.bitcoin,
    );
    if (drain) drainRecipientSats(unsigned);
    if (recipient <= 0) throw const OnchainException('insufficient_funds');
    if (recipient != transaction.amount) {
      throw const OnchainException('review_changed');
    }
    final signed = await model.signBitcoinTransaction(unsigned);
    checkCurrent();
    if (signed.signed != true || !_samePayment(unsigned, signed)) {
      throw const OnchainException('invalid_transaction');
    }
    final txid = await model.broadcastBitcoinTransaction(signed);
    return BitcoinSoftwareSendResult(txid, fee, recipient);
  }

  static bool _samePayment(Psbt unsigned, Psbt signed) {
    final before = unsigned.extractTx();
    final after = signed.extractTx();
    if (!before.hasInputOutputDetails ||
        !after.hasInputOutputDetails ||
        before.inputCount != after.inputCount ||
        before.outputCount != after.outputCount ||
        unsigned.fee() != signed.fee()) {
      return false;
    }
    for (var i = 0; i < before.inputCount; i++) {
      if (before.input()[i].previousOutput != after.input()[i].previousOutput) {
        return false;
      }
    }
    for (var i = 0; i < before.outputCount; i++) {
      if (before.output()[i].value.toSat() != after.output()[i].value.toSat() ||
          before.output()[i].scriptPubkey != after.output()[i].scriptPubkey) {
        return false;
      }
    }
    return true;
  }
}
