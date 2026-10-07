// Ledger account actions keep the wallet ID explicit through Home Move.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/home/components/deposit_sheet.dart';
import 'package:kute/models/hyperliquid_market.dart' show HlOpenOrder;
import 'package:kute/providers/hyperliquid_markets_provider.dart'
    show hyperliquidWireMarketProvider, hlDisplayCoin;
import 'package:kute/screens/ledger/funding/ledger_make_funds_available_sheet.dart';
import 'package:kute/screens/ledger/hyperliquid/ledger_hl_execution_target.dart';
import 'package:kute/screens/ledger/ledger_action_ui.dart';
import 'package:kute/screens/ledger/ledger_actions.dart';
import 'package:kute/screens/ledger/ledger_connect_steps.dart';
import 'package:kute/screens/ledger/ledger_tab_actions.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/services/tracking_service.dart';

/// Hooks backed by the Ledger sheets. Use as the value of
/// `ledgerAccountActionsProvider`.
const LedgerAccountActions ledgerSheetAccountActions = LedgerAccountActions(
  onFundInvesting: _fundInvesting,
  onWithdrawInvesting: _withdrawInvesting,
  onCancelOrder: _cancelOrder,
  onSellPosition: _sellPosition,
  onClaimPosition: _claimPosition,
  onClaimAll: _claimAll,
  onPredictionsFund: _fundPredictions,
  onPredictionsWithdraw: _withdrawPredictions,
  onPredictionsMakeFundsAvailable: _makeFundsAvailable,
);

Future<void> _fundInvesting(BuildContext context, String walletId) =>
    showDepositSheet(context,
        ledgerWalletId: walletId,
        lockedSide: MoveLockedSide.depositToHyperliquid);

Future<void> _withdrawInvesting(BuildContext context, String walletId) =>
    showDepositSheet(context,
        ledgerWalletId: walletId,
        lockedSide: MoveLockedSide.withdrawFromHyperliquid);

Future<void> _fundPredictions(BuildContext context, String walletId,
        {required bool requiresDeploy}) =>
    // Account creation consent is resolved again from this wallet when the
    // user continues, after choosing an amount.
    showDepositSheet(context,
        ledgerWalletId: walletId,
        lockedSide: MoveLockedSide.depositToPredictions);

void _makeFundsAvailable(BuildContext context, String walletId) =>
    showLedgerMakeFundsAvailableSheet(context, walletId: walletId);

Future<void> _withdrawPredictions(BuildContext context, String walletId) =>
    showDepositSheet(context,
        ledgerWalletId: walletId,
        lockedSide: MoveLockedSide.withdrawFromPredictions);

void _sellPosition(BuildContext context, String walletId, position) =>
    LedgerActions.sellPosition(context, walletId: walletId, position: position);

void _claimPosition(BuildContext context, String walletId, position) =>
    LedgerActions.claim(context, walletId: walletId, positions: [position]);

void _claimAll(BuildContext context, String walletId, positions) =>
    LedgerActions.claim(context, walletId: walletId, positions: positions);

void _cancelOrder(BuildContext context, String walletId, HlOpenOrder order) {
  TrackingService.ledgerActionSheetOpened(action: 'hl_cancel');
  showAppBottomSheet<void>(
    context: context,
    builder: (_) => LedgerCancelOrderSheet(walletId: walletId, order: order),
  );
}

/// Confirms a resting order cancel before the Ledger approval. A
/// Hyperliquid cancel needs the account signature by protocol.
class LedgerCancelOrderSheet extends ConsumerStatefulWidget {
  const LedgerCancelOrderSheet({
    super.key,
    required this.walletId,
    required this.order,
  });

  final String walletId;
  final HlOpenOrder order;

  @override
  ConsumerState<LedgerCancelOrderSheet> createState() =>
      _LedgerCancelOrderSheetState();
}

class _LedgerCancelOrderSheetState
    extends ConsumerState<LedgerCancelOrderSheet> {
  bool _busy = false;

  Future<void> _cancel() async {
    if (_busy) return;
    setState(() => _busy = true);
    final done = await runLedgerHlCancel(context, ref,
        walletId: widget.walletId, order: widget.order);
    if (!mounted) return;
    setState(() => _busy = false);
    if (done) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final order = widget.order;
    // Orders carry wire coins ('@107', 'xyz:TSLA'); show the market name.
    final coin = hlDisplayCoin(
        ref.watch(hyperliquidWireMarketProvider(order.coin)), order.coin);
    return LedgerActionSheetFrame(
      title: l10n.ledgerCancelOrderSummary,
      subtitle: coin,
      body: [
        LedgerSummaryRow(
            label: l10n.ledgerSummarySide,
            value: order.isBuy ? l10n.buy : l10n.sell),
        LedgerSummaryRow(
            label: l10n.ledgerSummaryAmount,
            value: order.isTrailingStop ? '${order.sz} $coin'
                : ledgerFormatUsd(order.sz * order.limitPx)),
        // Coin size and worst price are mechanics: one tap away.
        LedgerAdvancedDisclosure(children: [
          LedgerSummaryRow(
              label: l10n.ledgerSummarySize,
              value: '${order.sz} $coin'),
          if (!order.isTrailingStop) LedgerSummaryRow(
              label: l10n.ledgerSummaryLimitPrice, value: '${order.limitPx}'),
        ]),
        SizedBox(height: 8.h),
        LedgerNote(
          text: LedgerActions.opaqueHyperliquidAvailable
              ? l10n.ledgerOpaqueNote
              : l10n.ledgerOpaqueActionsUnavailable,
        ),
      ],
      buttons: [
        if (LedgerActions.opaqueHyperliquidAvailable) ...[
          AppButton(
            text: l10n.ledgerCancelOrderCta,
            isLoading: _busy,
            onPressed: _busy ? null : _cancel,
          ),
          SizedBox(height: 10.h),
        ],
        AppButton(
          text: l10n.ledgerApprovalClose,
          variant: AppButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
