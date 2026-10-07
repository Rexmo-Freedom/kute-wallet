import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
// Confirmation shown after winnings are claimed. The payout stays in the
// Predictions balance (redeemPosition does not route it to Bitcoin), so
// there is nothing pending to mention.

import 'package:flutter/material.dart';
import 'package:kute/l10n/l10n.dart';

import 'package:kute/screens/shared/trade_receipt.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/services/tracking_service.dart';

void pushClaimPlacedOverlay({
  required NavigatorState navigator,
  required String marketQuestion,
  required String outcome,
  required double? amountUsd,
}) {
  TrackingService.screenView('prediction_claimed');
  pushKuteSuccessOverlay(
    navigator: navigator,
    overlay: ClaimPlacedOverlay(
      marketQuestion: marketQuestion,
      outcome: outcome,
      amountUsd: amountUsd,
    ),
  );
}

class ClaimPlacedOverlay extends StatelessWidget {
  final String marketQuestion;
  final String outcome;
  final double? amountUsd;

  const ClaimPlacedOverlay({
    super.key,
    required this.marketQuestion,
    required this.outcome,
    required this.amountUsd,
  });

  @override
  Widget build(BuildContext context) {
    return KuteConfirmation(
      message: context.l10n.confirmationWinningsClaimed,
      detail: amountUsd == null
          ? context.l10n.betClaimUpdating
          : context.l10n.betClaimAdded,
      showCloseButton: true,
      onDone: () => Navigator.of(context).pop(),
      receipt: TradeReceipt(
          leading: const PolyReceiptArtwork(),
          title: marketQuestion,
          subtitle: outcome,
          rows: {
            context.l10n.payout:
                amountUsd == null ? '…' : '\$${amountUsd!.toStringAsFixed(2)}',
            context.l10n.ledgerSummaryDestination:
                context.l10n.homeNavPredictionsBalance,
            // The claim is relayer-paid: the one fact the old review page
            // added, now on the confirmation.
            context.l10n.networkFee2: context.l10n.ledgerFeeFree,
          }),
    );
  }
}

/// [navigator] when the screen the tap came from is already closing (its
/// context then no longer reaches one).
void pushPositionClearedOverlay(
    {required BuildContext context,
    NavigatorState? navigator,
    required String marketQuestion,
    required String outcome}) {
  final nav = navigator ?? Navigator.of(context, rootNavigator: true);
  pushKuteSuccessOverlay(
      navigator: nav,
      overlay: KuteConfirmation(
        message: nav.context.l10n.betPositionCleared,
        showCloseButton: true,
        onDone: nav.pop,
        receipt: TradeReceipt(
            leading: const PolyReceiptArtwork(),
            title: marketQuestion,
            subtitle: outcome,
            rows: const {}),
      ));
}
