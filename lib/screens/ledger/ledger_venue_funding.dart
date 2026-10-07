import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/ledger/ledger_hyperliquid_account_provider.dart';
import 'package:kute/providers/ledger/ledger_identity_provider.dart';
import 'package:kute/providers/ledger/ledger_polymarket_account_provider.dart';
import 'package:kute/screens/ledger/ledger_account_body.dart';
import 'package:kute/screens/ledger/ledger_tab_actions.dart';
import 'package:kute/screens/shared/capability_unavailable_sheet.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/services/polymarket/polymarket_account_resolver.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

/// The Ledger venue's Deposit and Withdraw, bound to the exact wallet the
/// tab shows. Shared by the venue's Deposit button at the top and by the
/// dock's Withdraw (the pair used to be the dock's own). A null callback
/// means the verb is unavailable right now (no verified identity, a read
/// for another wallet, a read-only predictions account, an unwired hook)
/// and renders disabled, never hidden.
({VoidCallback? deposit, VoidCallback? withdraw}) ledgerVenueFunding(
  BuildContext context,
  WidgetRef ref, {
  required String walletId,
  required LedgerAccountTab tab,
}) {
  final l10n = context.l10n;
  final hooks = ref.watch(ledgerAccountActionsProvider);
  final identity = ref.watch(ledgerIdentityProvider(walletId));
  final verified = identity != null &&
      identity.walletId == walletId &&
      identity.hasVerifiedEvm;
  VoidCallback? deposit;
  VoidCallback? withdraw;
  if (tab == LedgerAccountTab.investing) {
    final async = ref.watch(ledgerHlAccountProvider(walletId));
    final data = async.valueOrNull;
    final current = verified &&
        !async.isLoading &&
        !async.hasError &&
        data != null &&
        data.walletId == walletId &&
        data.address?.toLowerCase() == identity.evmAddress?.toLowerCase();
    if (current) {
      if (hooks.onFundInvesting != null) {
        deposit = () => hooks.onFundInvesting!(context, walletId);
      }
    }
  } else if (tab == LedgerAccountTab.predictions) {
    final async = ref.watch(ledgerPmAccountProvider(walletId));
    final data = async.valueOrNull;
    final current = verified &&
        !async.isLoading &&
        !async.hasError &&
        data != null &&
        data.walletId == walletId &&
        data.eoa?.toLowerCase() == identity.evmAddress?.toLowerCase();
    if (current && !data.isReadOnly) {
      final kind = data.account?.kind;
      if (hooks.onPredictionsFund != null &&
          (kind == PolymarketAccountKind.depositWallet ||
              kind == PolymarketAccountKind.none)) {
        deposit = () => hooks.onPredictionsFund!(context, walletId,
            requiresDeploy: kind == PolymarketAccountKind.none);
      }
    }
  }
  // Navigation stays available with zero, loading or unavailable balances.
  // The wallet-bound amount flow validates identity, capability and funds.
  if (tab == LedgerAccountTab.investing && hooks.onWithdrawInvesting != null) {
    withdraw = () => hooks.onWithdrawInvesting!(context, walletId);
  } else if (tab == LedgerAccountTab.predictions &&
      hooks.onPredictionsWithdraw != null) {
    withdraw = () => hooks.onPredictionsWithdraw!(context, walletId);
  }
  void navigate(VoidCallback action) {
    if (!context.mounted) return;
    final currentIdentity = ref.read(ledgerIdentityProvider(walletId));
    if (currentIdentity == null ||
        !currentIdentity.hasVerifiedEvm ||
        currentIdentity.evmAddress?.toLowerCase() !=
            identity?.evmAddress?.toLowerCase()) {
      showMessageSnackBar(
          context: context,
          message: l10n.walletActionsWalletChanged,
          error: true);
      return;
    }
    final venue =
        tab == LedgerAccountTab.predictions ? 'polymarket' : 'hyperliquid';
    final decision = ref
        .read(runtimeCapabilitiesProvider)
        .decision('$venue.deposit');
    if (!decision.allowed) {
      showCapabilityDecisionSheet(context, decision);
      return;
    }
    action();
  }

  return (
    deposit: deposit == null ? null : () => navigate(deposit!),
    withdraw: withdraw,
  );
}
