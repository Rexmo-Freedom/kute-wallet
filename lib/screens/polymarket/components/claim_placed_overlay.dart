// Confirmation shown after winnings are claimed. The payout stays in the
// Predictions balance (redeemPosition does not route it to Bitcoin), so
// there is nothing pending to mention.

import 'package:flutter/material.dart';
import 'package:kute/l10n/l10n.dart';

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
    final l10n = context.l10n;
    final amount = amountUsd;
    return KuteConfirmation(
      tone: KuteConfirmationTone.celebrate,
      message: l10n.confirmationWinningsClaimed,
      amount: amount == null ? null : '\$${amount.toStringAsFixed(2)}',
      contextLine: _context(outcome, marketQuestion),
      rows: {
        l10n.ledgerSummaryDestination: l10n.homeNavPredictionsBalance,
        // The claim is relayer-paid: the one fact the old review page
        // added, now on the confirmation.
        l10n.networkFee2: l10n.ledgerFeeFree,
      },
      // The credited amount still updating is the one pending fact.
      detail: amount == null ? l10n.betClaimUpdating : null,
      onDone: () => Navigator.of(context).pop(),
    );
  }
}

String _context(String outcome, String marketQuestion) =>
    outcome.isEmpty ? marketQuestion : '$outcome · $marketQuestion';

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
        contextLine: _context(outcome, marketQuestion),
        onDone: nav.pop,
      ));
}
