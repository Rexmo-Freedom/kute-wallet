import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';

/// Data class for fee line items passed to the send confirmation.
class SendFeeDetail {
  final String label;
  final String value;
  const SendFeeDetail({required this.label, required this.value});
}

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
  // Decorative fade-in of the overlay route. Collapse it to an instant
  // cut when the user has requested reduced motion (WCAG 2.3.3).
  final reduceMotion =
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      transitionDuration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 300),
      reverseTransitionDuration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 300),
      pageBuilder: (context, _, __) => PaymentTransactionOverlay(
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
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    ),
  );
}

/// Send and conversion confirmation. Shows the shared check and a short
/// message; the send details stay in Activity.
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

  @override
  Widget build(BuildContext context) {
    return KuteConfirmation(
      message: isSwap
          ? context.l10n.homeNavConversionStarted
          : context.l10n.confirmationBitcoinSent,
      onDone: () {
        // Tear down every imperatively-pushed route sitting between this
        // overlay and the home surface, THEN navigate home declaratively.
        // `context.go('/home')` alone only resets the GoRouter stack; a
        // modal bottom sheet underneath (the Move sheet with an embedded
        // hardware-signing screen was the canonical reproducer) is an
        // imperative route on the root Navigator and would stay visible.
        final nav = Navigator.of(context, rootNavigator: true);
        while (nav.canPop()) {
          nav.pop();
        }
        context.go('/home');
      },
    );
  }
}
