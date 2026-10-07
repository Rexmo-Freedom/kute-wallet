// lib/screens/ledger/polymarket/ledger_withdraw_sheet.dart
//
// Withdraw Polymarket cash from a Ledger account to the Ledger's Bitcoin
// account through Orchestra (Wallet hardening Phase 4a, P4.6; O3).
//
// * Hidden entirely while `kLedgerPolymarketWithdrawEnabled` is off.
// * The quote binding (Orchestra deposit address, refund and recipient)
//   comes from the Phase 4b funding route; this sheet never builds or
//   refreshes quotes. The executor refuses any transfer whose recipient is
//   not that bound deposit address, or whose refund and recipient do not
//   belong to this Ledger.
// * USDC.e must be available: when part of the amount is still pUSD, a
//   separate "make funds withdrawable" approval comes first.
// * The destination sits inside calldata, so the review always shows the
//   "shows a code" note.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/constants/feature_flags.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/ledger/ledger_action_controller.dart';
import 'package:kute/providers/ledger/ledger_executors_provider.dart';
import 'package:kute/providers/ledger/ledger_polymarket_account_provider.dart';
import 'package:kute/screens/ledger/ledger_action_ui.dart';
import 'package:kute/screens/ledger/ledger_approval_sheet.dart';
import 'package:kute/screens/ledger/ledger_connect_steps.dart';
import 'package:kute/screens/ledger/polymarket/ledger_pm_support.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/services/hardware/ledger/deposit_wallet_call_allowlist.dart';
import 'package:kute/services/hardware/ledger/ledger_polymarket_executor.dart';
import 'package:kute/services/polymarket/polymarket_account_resolver.dart';
import 'package:kute/services/tracking_service.dart';

class LedgerWithdrawSheet extends ConsumerStatefulWidget {
  const LedgerWithdrawSheet({
    super.key,
    required this.walletId,
    required this.amount,
    required this.binding,
    required this.belongsToLedger,
    this.onSubmitted,
  });

  final String walletId;

  /// USDC.e base units (6 decimals) to send to the bound deposit address.
  final BigInt amount;
  final LedgerWithdrawalBinding binding;

  /// True for addresses of this Ledger (its EVM address and its Bitcoin
  /// receive addresses). Supplied by the funding route.
  final bool Function(String address) belongsToLedger;

  /// Called with the relayer transaction hash after a confirmed submit,
  /// or with null when the submission is pending.
  final ValueChanged<String?>? onSubmitted;

  static bool get isAvailable => kLedgerPolymarketWithdrawEnabled;

  static Future<void> show(
    BuildContext context, {
    required String walletId,
    required BigInt amount,
    required LedgerWithdrawalBinding binding,
    required bool Function(String address) belongsToLedger,
    ValueChanged<String?>? onSubmitted,
  }) async {
    if (!isAvailable) return;
    TrackingService.ledgerActionSheetOpened(action: 'pm_withdraw');
    await showAppBottomSheet<void>(
      context: context,
      builder: (_) => LedgerWithdrawSheet(
        walletId: walletId,
        amount: amount,
        binding: binding,
        belongsToLedger: belongsToLedger,
        onSubmitted: onSubmitted,
      ),
    );
  }

  @override
  ConsumerState<LedgerWithdrawSheet> createState() =>
      _LedgerWithdrawSheetState();
}

class _LedgerWithdrawSheetState extends ConsumerState<LedgerWithdrawSheet> {
  bool _busy = false;
  bool _submittedPending = false;

  Future<void> _unwrap(PolymarketLedgerAccount account, BigInt amount) async {
    final depositWallet = account.address;
    if (_busy || depositWallet == null) return;
    final l10n = context.l10n;
    setState(() => _busy = true);
    final walletId = widget.walletId;
    final intent = LedgerPolymarketIntents.unwrap(
      walletId: walletId,
      depositWallet: depositWallet,
      amount: amount,
      summary: {
        l10n.ledgerSummaryAction: l10n.ledgerUnwrapSummary,
        l10n.ledgerSummaryAmount: ledgerFormatMicros(amount),
      },
    );
    final factory = ref.read(ledgerPmExecutorFactoryProvider);
    final navigator = Navigator.of(context, rootNavigator: true);
    final outcome = await showLedgerApprovalSheet<String>(
      context,
      walletId: walletId,
      request: LedgerActionRequest<String>(
        intent: intent,
        amountUsd: amount.toDouble() / 1e6,
        execute: (signing) => factory(
          walletId: walletId,
          pairedAddress: signing.pairedAddress,
          signer: signing.signer,
          account: account,
        ).unwrap(intent),
        reconcile:
            ledgerPmBatchReconcile(ref, walletId: walletId, account: account),
      ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (outcome.isSuccess) {
      ref.invalidate(ledgerPmAccountProvider(walletId));
      showLedgerConfirmation(navigator, message: l10n.ledgerUnwrapDone);
    } else if (outcome.isPending) {
      ref.invalidate(ledgerPendingActionsProvider(walletId));
    }
  }

  Future<void> _withdraw(PolymarketLedgerAccount account) async {
    final depositWallet = account.address;
    if (_busy || _submittedPending || depositWallet == null) return;
    final l10n = context.l10n;
    setState(() => _busy = true);
    final walletId = widget.walletId;
    final intent = LedgerPolymarketIntents.withdraw(
      walletId: walletId,
      depositWallet: depositWallet,
      amount: widget.amount,
      binding: widget.binding,
      summary: {
        l10n.ledgerSummaryAmount: ledgerFormatMicros(widget.amount),
        l10n.ledgerSummaryDestination: l10n.ledgerWithdrawDestination,
      },
    );
    final factory = ref.read(ledgerPmExecutorFactoryProvider);
    final navigator = Navigator.of(context, rootNavigator: true);
    final outcome = await showLedgerApprovalSheet<String>(
      context,
      walletId: walletId,
      request: LedgerActionRequest<String>(
        intent: intent,
        amountUsd: widget.amount.toDouble() / 1e6,
        execute: (signing) => factory(
          walletId: walletId,
          pairedAddress: signing.pairedAddress,
          signer: signing.signer,
          account: account,
          belongsToLedger: widget.belongsToLedger,
        ).withdraw(intent),
        reconcile:
            ledgerPmBatchReconcile(ref, walletId: walletId, account: account),
      ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    switch (outcome.kind) {
      case LedgerApprovalOutcomeKind.success:
        ref.invalidate(ledgerPmAccountProvider(walletId));
        widget.onSubmitted?.call(outcome.result);
        Navigator.of(context).pop();
        showLedgerConfirmation(navigator,
            message: l10n.ledgerWithdrawSentPlain);
      case LedgerApprovalOutcomeKind.pending:
      case LedgerApprovalOutcomeKind.backgrounded:
        ref.invalidate(ledgerPendingActionsProvider(walletId));
        widget.onSubmitted?.call(null);
        setState(() => _submittedPending = true);
      case LedgerApprovalOutcomeKind.cancelled:
      case LedgerApprovalOutcomeKind.failed:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final pm = ref.watch(ledgerPmAccountProvider(widget.walletId)).valueOrNull;
    final account = pm?.account;
    final canAct = account != null && account.canAct && account.address != null;
    final usdce = pm?.usdceBalance;
    final pusd = pm?.pusdBalance;
    final cashUnknown = pm == null ||
        pm.partialFailures.contains(LedgerPmReadCategory.cash) ||
        usdce == null;
    final shortfall = usdce == null ? BigInt.zero : widget.amount - usdce;
    final needsUnwrap = !cashUnknown && shortfall > BigInt.zero;
    final canUnwrap = needsUnwrap && pusd != null && pusd >= shortfall;

    return LedgerActionSheetFrame(
      title: l10n.ledgerWithdrawTitle,
      subtitle: l10n.ledgerWithdrawSubtitle,
      body: [
        const LedgerRelayerFeeRow(),
        LedgerSummaryRow(
            label: l10n.ledgerSummaryAmount,
            value: ledgerFormatMicros(widget.amount)),
        LedgerSummaryRow(
            label: l10n.ledgerSummaryDestination,
            value: l10n.ledgerWithdrawDestination),
        SizedBox(height: 8.h),
        if (pm?.isReadOnly == true)
          LedgerNote(text: l10n.ledgerPmLegacyReadOnly)
        else if (pm != null && !canAct)
          LedgerNote(text: l10n.ledgerErrorAccountUnsupported),
        if (cashUnknown) LedgerNote(text: l10n.ledgerPartialLoad),
        if (needsUnwrap) LedgerNote(text: l10n.ledgerWithdrawUnwrapFirst),
        if (needsUnwrap && !canUnwrap)
          LedgerNote(text: l10n.ledgerWithdrawNotEnough),
        if (_submittedPending)
          LedgerNote(
              text: l10n.ledgerPendingStatus, icon: Icons.schedule_rounded),
      ],
      buttons: [
        if (!_submittedPending) ...[
          if (needsUnwrap)
            AppButton(
              text: l10n.ledgerWithdrawUnwrapCta,
              isLoading: _busy,
              onPressed: canAct && canUnwrap && !_busy
                  ? () => _unwrap(account, shortfall)
                  : null,
            )
          else
            AppButton(
              text: l10n.ledgerWithdrawCta,
              isLoading: _busy,
              onPressed: canAct && !cashUnknown && !_busy
                  ? () => _withdraw(account)
                  : null,
            ),
          SizedBox(height: 10.h),
        ],
        AppButton(
          text: _submittedPending ? l10n.ledgerApprovalClose : l10n.cancel,
          variant: AppButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
