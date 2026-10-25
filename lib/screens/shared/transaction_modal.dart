import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/screens/shared/trade_receipt.dart';

/// Data class for fee line items passed to the send confirmation.
class SendFeeDetail {
  final String label;
  final String value;
  const SendFeeDetail({required this.label, required this.value});
}

/// The send (or conversion) result sheet. Done used to tear down every
/// route over home and go there; now that happens first and the sheet
/// slides up over home, so Done only closes it.
void showFullscreenTransactionSendModal({
  required BuildContext context,
  required String amount,
  required String receiveAddress,
  int? confirmationBlocks,
  String? asset,
  bool fiat = false,
  String? fiatAmount,
  String? txid,
  bool isLiquid = false,
  bool isSwap = false,
  String? swapIconUrl,
  String? swapIconSvg,
  Color? swapIconColor,
  String? swapCoinCode,
  List<SendFeeDetail> fees = const [],
}) {
  // Capture both before anything is popped: this context's route is
  // about to go.
  final nav = Navigator.of(context, rootNavigator: true);
  final router = GoRouter.maybeOf(context);
  pushKuteSuccessOverlayAfter(
    navigator: nav,
    navigate: () {
      // Tear down every imperatively-pushed route sitting over the home
      // surface, THEN navigate home declaratively. `go('/home')` alone
      // only resets the GoRouter stack; a modal bottom sheet underneath
      // (the Move sheet with an embedded hardware-signing screen was the
      // canonical reproducer) is an imperative route on the root
      // Navigator and would stay visible.
      while (nav.canPop()) {
        nav.pop();
      }
      router?.go('/home');
    },
    overlay: PaymentTransactionOverlay(
      amount: amount,
      fiat: fiat,
      fiatAmount: fiatAmount,
      asset: asset,
      txid: txid,
      isLiquid: isLiquid,
      isSwap: isSwap,
      swapIconUrl: swapIconUrl,
      swapIconSvg: swapIconSvg,
      swapIconColor: swapIconColor,
      swapCoinCode: swapCoinCode,
      receiveAddress: receiveAddress,
      confirmationBlocks: confirmationBlocks,
      fees: fees,
    ),
  );
}

/// Send and conversion result sheet: the amount, who it went to (and its
/// fiat value), the network, the fees the caller knows exactly, and the
/// transaction when it is an on-chain Bitcoin one.
class PaymentTransactionOverlay extends StatelessWidget {
  final String amount;
  final bool fiat;
  final String? fiatAmount;
  final String? asset;
  final String? txid;
  final bool isLiquid;
  final bool isSwap;
  final String? swapIconUrl;
  final String? swapIconSvg;
  final Color? swapIconColor;
  final String? swapCoinCode;
  final String receiveAddress;
  final int? confirmationBlocks;
  final List<SendFeeDetail> fees;

  const PaymentTransactionOverlay({
    super.key,
    required this.amount,
    required this.receiveAddress,
    this.fiat = false,
    this.fiatAmount,
    this.asset,
    this.txid,
    this.isLiquid = false,
    this.isSwap = false,
    this.swapIconUrl,
    this.swapIconSvg,
    this.swapIconColor,
    this.swapCoinCode,
    this.confirmationBlocks,
    this.fees = const [],
  });

  /// A raw address or invoice as head…tail; a Lightning address or a
  /// name passes through.
  static String shortRecipient(String value) {
    final v = value.trim();
    if (v.length <= 20 || v.contains('@') || v.contains(' ')) return v;
    return '${v.substring(0, 8)}…${v.substring(v.length - 6)}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final recipient = receiveAddress.trim();
    final fiatValue = fiatAmount?.trim();
    final contextLine = [
      if (recipient.isNotEmpty)
        l10n.confirmationSentToRecipient(shortRecipient(recipient)),
      if (fiatValue != null && fiatValue.isNotEmpty) fiatValue,
    ].join(' · ');
    final network = asset?.trim();
    return KuteConfirmation(
      message: isSwap
          ? l10n.homeNavConversionStarted
          : l10n.confirmationBitcoinSent,
      amount: amount.trim().isEmpty ? null : amount,
      contextLine: contextLine.isEmpty ? null : contextLine,
      rows: {
        if (!isSwap && network != null && network.isNotEmpty)
          l10n.network: network,
        for (final fee in fees.take(isSwap ? 4 : 3)) fee.label: fee.value,
      },
      // Liquid and Spark sends have no mempool.space transaction.
      transaction: isLiquid ? null : TradeReceiptTransaction.bitcoin(txid),
      // The routes over home are already gone: Done closes the sheet.
      onDone: () => Navigator.of(context).pop(),
    );
  }
}
