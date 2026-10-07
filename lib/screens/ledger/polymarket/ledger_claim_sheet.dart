// lib/screens/ledger/polymarket/ledger_claim_sheet.dart
//
// Claim resolved Polymarket winnings for a Ledger account (Wallet
// hardening Phase 4a, P4.6).
//
// * One condition per approval; nothing claims automatically. The top
//   CTA and each row's button route through the same executor path.
// * A condition whose oracle result is not final yet is refused before
//   any prompt (the redeem would revert).
// * "Claim submitted. Funds arrive after the network confirms." on
//   success; a pending submission stays marked so it is not claimed twice
//   from this sheet, and its status is read without a new prompt.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart' show Position;

import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/ledger/ledger_action_controller.dart';
import 'package:kute/providers/ledger/ledger_executors_provider.dart';
import 'package:kute/providers/ledger/ledger_polymarket_account_provider.dart';
import 'package:kute/screens/ledger/ledger_action_ui.dart';
import 'package:kute/screens/ledger/ledger_approval_sheet.dart';
import 'package:kute/screens/ledger/polymarket/ledger_pm_support.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/services/hardware/ledger/ledger_polymarket_executor.dart';
import 'package:kute/services/polymarket/polymarket_account_resolver.dart';
import 'package:kute/services/polymarket_onboarding_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

enum LedgerClaimRowState { ready, working, submitted, pending }

class LedgerClaimSheet extends ConsumerStatefulWidget {
  const LedgerClaimSheet({
    super.key,
    required this.walletId,
    required this.positions,
  });

  final String walletId;

  /// Positions from the Ledger account provider; only redeemable ones are
  /// offered.
  final List<Position> positions;

  static Future<void> show(
    BuildContext context, {
    required String walletId,
    required List<Position> positions,
  }) {
    TrackingService.ledgerActionSheetOpened(action: 'pm_claim');
    return showAppBottomSheet<void>(
      context: context,
      builder: (_) =>
          LedgerClaimSheet(walletId: walletId, positions: positions),
    );
  }

  @override
  ConsumerState<LedgerClaimSheet> createState() => _LedgerClaimSheetState();
}

class _LedgerClaimSheetState extends ConsumerState<LedgerClaimSheet> {
  final Set<String> _submitted = {};
  final Set<String> _pending = {};
  String? _working;

  /// One entry per condition (both outcomes of a condition redeem
  /// together), in the order received.
  List<Position> get _conditions {
    final seen = <String>{};
    return [
      for (final p in widget.positions)
        if (p.redeemable && seen.add(p.conditionId)) p,
    ];
  }

  double _valueFor(String conditionId) => widget.positions
      .where((p) => p.conditionId == conditionId)
      .fold(0.0, (sum, p) => sum + p.currentValue);

  LedgerClaimRowState _stateFor(String conditionId) {
    if (_working == conditionId) return LedgerClaimRowState.working;
    if (_submitted.contains(conditionId)) return LedgerClaimRowState.submitted;
    if (_pending.contains(conditionId)) return LedgerClaimRowState.pending;
    return LedgerClaimRowState.ready;
  }

  Future<void> _claim(
      Position position, PolymarketLedgerAccount account) async {
    final depositWallet = account.address;
    if (_working != null || depositWallet == null) return;
    if (_stateFor(position.conditionId) != LedgerClaimRowState.ready) return;
    final l10n = context.l10n;
    setState(() => _working = position.conditionId);

    final finalized = await PolymarketOnboardingService()
        .isConditionFinalized(position.conditionId);
    if (!mounted) return;
    if (finalized == false) {
      setState(() => _working = null);
      TrackingService.ledgerClaimNotReady();
      showMessageSnackBar(
          context: context, message: l10n.ledgerClaimNotReady, error: true);
      return;
    }

    final walletId = widget.walletId;
    final value = _valueFor(position.conditionId);
    final intent = LedgerPolymarketIntents.redeem(
      walletId: walletId,
      depositWallet: depositWallet,
      conditionId: position.conditionId,
      negRisk: position.negativeRisk,
      summary: {
        l10n.ledgerSummaryMarket: position.title,
        l10n.ledgerSummaryOutcome: position.outcome,
        l10n.ledgerSummaryAmount: ledgerFormatUsd(value),
      },
    );
    final factory = ref.read(ledgerPmExecutorFactoryProvider);
    final navigator = Navigator.of(context, rootNavigator: true);
    final outcome = await showLedgerApprovalSheet<String>(
      context,
      walletId: walletId,
      request: LedgerActionRequest<String>(
        intent: intent,
        amountUsd: value,
        execute: (signing) => factory(
          walletId: walletId,
          pairedAddress: signing.pairedAddress,
          signer: signing.signer,
          account: account,
        ).redeem(intent),
        reconcile:
            ledgerPmBatchReconcile(ref, walletId: walletId, account: account),
      ),
    );
    if (!mounted) return;

    setState(() {
      _working = null;
      switch (outcome.kind) {
        case LedgerApprovalOutcomeKind.success:
          _submitted.add(position.conditionId);
        case LedgerApprovalOutcomeKind.pending:
        case LedgerApprovalOutcomeKind.backgrounded:
          _pending.add(position.conditionId);
        case LedgerApprovalOutcomeKind.cancelled:
        case LedgerApprovalOutcomeKind.failed:
          break;
      }
    });

    if (outcome.isSuccess) {
      ref.invalidate(ledgerPmAccountProvider(walletId));
      final remaining = _conditions
          .where((p) => _stateFor(p.conditionId) == LedgerClaimRowState.ready);
      if (remaining.isEmpty) Navigator.of(context).pop();
      showLedgerConfirmation(navigator, message: l10n.ledgerClaimSubmitted);
    } else if (outcome.isPending) {
      ref.invalidate(ledgerPendingActionsProvider(walletId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final pm = ref.watch(ledgerPmAccountProvider(widget.walletId)).valueOrNull;
    final account = pm?.account;
    final canAct = account != null && account.canAct && account.address != null;
    final conditions = _conditions;
    Position? next;
    for (final p in conditions) {
      if (_stateFor(p.conditionId) == LedgerClaimRowState.ready) {
        next = p;
        break;
      }
    }

    return LedgerActionSheetFrame(
      title: l10n.ledgerClaimTitle,
      subtitle: l10n.ledgerClaimSubtitle,
      body: [
        const LedgerRelayerFeeRow(),
        for (final p in conditions)
          LedgerClaimRow(
            title: p.title,
            outcome: p.outcome,
            value: ledgerFormatUsd(_valueFor(p.conditionId)),
            state: _stateFor(p.conditionId),
            onClaim:
                canAct && _working == null ? () => _claim(p, account) : null,
          ),
        if (pm?.isReadOnly == true)
          LedgerNote(text: l10n.ledgerPmLegacyReadOnly)
        else if (pm != null && !canAct)
          LedgerNote(text: l10n.ledgerErrorAccountUnsupported),
        LedgerNote(text: l10n.ledgerClaimOneAtATime),
      ],
      buttons: [
        if (next != null) ...[
          AppButton(
            text: l10n.ledgerClaimCta,
            variant: AppButtonVariant.moneyIn,
            isLoading: _working != null,
            onPressed: canAct && _working == null
                ? () => _claim(next!, account)
                : null,
          ),
          SizedBox(height: 10.h),
        ],
        AppButton(
          text: next == null ? l10n.ledgerApprovalClose : l10n.cancel,
          variant: AppButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// One condition to claim. Its own widget so theme reads stay live.
class LedgerClaimRow extends StatelessWidget {
  const LedgerClaimRow({
    super.key,
    required this.title,
    required this.outcome,
    required this.value,
    required this.state,
    this.onClaim,
  });

  final String title;
  final String outcome;
  final String value;
  final LedgerClaimRowState state;
  final VoidCallback? onClaim;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final trailing = switch (state) {
      LedgerClaimRowState.submitted => Text(l10n.ledgerClaimRowSubmitted,
          style: TextStyle(color: c.textSecondary, fontSize: 13.sp)),
      LedgerClaimRowState.pending => Text(l10n.ledgerClaimRowPending,
          style: TextStyle(color: c.textSecondary, fontSize: 13.sp)),
      _ => SizedBox(
          width: 96.w,
          child: AppButton(
            text: l10n.claim,
            compact: true,
            height: 36.h,
            fontSize: 14.sp,
            variant: AppButtonVariant.moneyIn,
            isLoading: state == LedgerClaimRowState.working,
            onPressed: onClaim,
          ),
        ),
    };
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  '$outcome, $value',
                  style: TextStyle(color: c.textTertiary, fontSize: 13.sp),
                ),
              ],
            ),
          ),
          SizedBox(width: 12.w),
          trailing,
        ],
      ),
    );
  }
}
