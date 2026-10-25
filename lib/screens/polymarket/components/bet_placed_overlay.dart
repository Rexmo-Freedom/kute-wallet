// lib/screens/polymarket/components/bet_placed_overlay.dart
//
// Result sheet shown after a prediction is placed: the cost on the side
// as the hero, the market under it, shares and payout as rows. Done
// closes it; "View prediction" opens the position. The layout lives in
// the shared `KuteConfirmation`.

import 'package:flutter/material.dart';
import 'package:kute/providers/polymarket_browse_provider.dart' show PolymarketPosition;
import 'package:kute/screens/polymarket/components/position_detail_sheet.dart';
import 'package:kute/screens/usd/usd_account_screen.dart'
    show openInvestmentsPositions;

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';

/// Push the confirmation using a pre-captured [NavigatorState]. Use
/// this from inside a bottom sheet's handler: capture
/// `Navigator.of(context, rootNavigator: true)` before popping the
/// sheet, then call this after.
void pushBetPlacedOverlay({
  required NavigatorState navigator,
  required String marketQuestion,
  String? marketImage,
  required String outcome,
  required double shares,
  required double total,
  required double avgPrice,
  required double potentialPayout,
  bool estimated = false,
  String? note,
  PolymarketPosition? position,
}) {
  pushKuteSuccessOverlay(
    navigator: navigator,
    overlay: BetPlacedOverlay(
      marketQuestion: marketQuestion,
      marketImage: marketImage,
      outcome: outcome,
      shares: shares,
      total: total,
      avgPrice: avgPrice,
      potentialPayout: potentialPayout,
      estimated: estimated,
      note: note,
      position: position,
    ),
  );
}

class BetPlacedOverlay extends StatelessWidget {
  final String marketQuestion;
  final String? marketImage;
  final String outcome;
  final double shares;
  final double total;
  final double avgPrice;
  final double potentialPayout;
  final bool estimated;

  /// What else happened, under the check (a part fill: how much was
  /// bought, and that the rest was not).
  final String? note;

  /// The prediction just placed, as a position, so "View prediction"
  /// opens its own live page rather than the list. Null falls back to
  /// the list (a fill the slip could not describe fully).
  final PolymarketPosition? position;

  const BetPlacedOverlay({
    super.key,
    required this.marketQuestion,
    this.marketImage,
    required this.outcome,
    required this.shares,
    required this.total,
    required this.avgPrice,
    required this.potentialPayout,
    this.estimated = false,
    this.note,
    this.position,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final approx = estimated ? '≈ ' : '';
    final cost = '\$${total.toStringAsFixed(2)}';
    return KuteConfirmation(
      message: l10n.betPredictionPlaced,
      amount: approx +
          (outcome.isEmpty ? cost : l10n.betAmountOnSide(cost, outcome)),
      contextLine: marketQuestion,
      rows: {
        l10n.betShares: '$approx${shares.toStringAsFixed(2)}',
        l10n.betReceiptPayout:
            '$approx\$${potentialPayout.toStringAsFixed(2)}',
      },
      detail: note ?? (estimated ? l10n.betReceiptUpdating : null),
      onDone: () => Navigator.of(context).pop(),
      secondaryButtonText: l10n.betViewPrediction,
      onSecondary: () {
        final nav = Navigator.of(context);
        final placed = position;
        nav.pop();
        if (placed != null) {
          PositionDetailSheet.show(nav.context, position: placed);
          return;
        }
        // What the account holds now: the Investments tab's Positions.
        openInvestmentsPositions(nav.context);
      },
    );
  }
}
