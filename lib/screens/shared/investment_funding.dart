import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/screens/home/components/deposit_sheet.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart'
    show InvestmentsProduct;

/// One balance: the spending account has no venue Deposit or Withdraw.
/// Money only reaches a venue through an order funded from Dollars (the
/// slip funds the shortfall itself) and comes back through the sweeper,
/// so the venue's Deposit button and the dock's Withdraw do nothing for
/// a hot wallet. A Ledger account keeps its own funding screens, which
/// never reach here.
void openInvestmentFunding(
  BuildContext context,
  WidgetRef ref,
  InvestmentsProduct product, {
  required bool deposit,
}) {
  final open = debugOpenFundingSheet;
  if (open == null) return;
  // Test seam only: the app never opens a venue door from here any more.
  open(
      context,
      product == InvestmentsProduct.predictions
          ? (deposit
              ? MoveLockedSide.depositToPredictions
              : MoveLockedSide.withdrawFromPredictions)
          : (deposit
              ? MoveLockedSide.depositToHyperliquid
              : MoveLockedSide.withdrawFromHyperliquid));
}

/// Test seam: stands in for [showDepositSheet], whose page needs the live
/// wallet and venue providers. Null in the app.
@visibleForTesting
void Function(BuildContext context, MoveLockedSide lockedSide)?
    debugOpenFundingSheet;
