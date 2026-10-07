import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/home/components/deposit_sheet.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart'
    show InvestmentsProduct;
import 'package:kute/screens/shared/capability_unavailable_sheet.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';

/// Funds or withdraws from the spending account's venue through the Move
/// sheet, after the venue's capability check. One entry for the venue's
/// Deposit button at the top and the dock's Withdraw: both used to be the
/// dock's own pair.
void openInvestmentFunding(
  BuildContext context,
  WidgetRef ref,
  InvestmentsProduct product, {
  required bool deposit,
}) {
  final predictions = product == InvestmentsProduct.predictions;
  final walletId = ref.read(settingsProvider).activeWalletId;
  if (!context.mounted) return;
  if (walletId == null) {
    showMessageSnackBar(
      context: context,
      message: context.l10n.walletActionsWalletChanged,
      error: true,
    );
    return;
  }
  final capability =
      '${predictions ? 'polymarket' : 'hyperliquid'}.${deposit ? 'deposit' : 'withdraw'}';
  final decision = ref.read(runtimeCapabilitiesProvider).decision(capability);
  if (!decision.allowed) {
    TrackingService.track(
        predictions ? 'polymarket_funding_blocked' : 'hyperliquid_funding_blocked',
        params: {
          'direction': deposit ? 'deposit' : 'withdraw',
          'reason': decision.regionRestricted ? 'geoblocked' : 'capability',
        });
    showCapabilityDecisionSheet(context, decision);
    return;
  }
  showDepositSheet(
    context,
    lockedSide: predictions
        ? deposit
            ? MoveLockedSide.depositToPredictions
            : MoveLockedSide.withdrawFromPredictions
        : deposit
            ? MoveLockedSide.depositToHyperliquid
            : MoveLockedSide.withdrawFromHyperliquid,
  );
}
