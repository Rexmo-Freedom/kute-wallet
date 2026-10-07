// lib/screens/ledger/funding/ledger_make_funds_available_sheet.dart
//
// "Make funds available" for a Ledger Predictions account (Wallet
// hardening Phase 4b, P4.11). After Ledger bitcoin arrives as USDC.e in
// the deposit wallet, one Ledger approval runs the exact approve plus wrap
// batch into the cash predictions use.
//
// Reached from the Predictions tab when arrived USDC.e is not usable yet.
// The service reads the balance, checks the deposit wallet against the
// verified Ledger EVM address and validates the batch against the Phase 3
// allowlist before any prompt; the Ledger approval flow connects the
// device and signs. The batch is opaque on the device, so the amount is
// shown here first. Behind `kLedgerInvestingEnabled`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/constants/feature_flags.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/ledger/ledger_action_controller.dart';
import 'package:kute/providers/ledger/ledger_executors_provider.dart';
import 'package:kute/providers/ledger/ledger_polymarket_account_provider.dart';
import 'package:kute/screens/ledger/funding/ledger_funding_parts.dart';
import 'package:kute/screens/ledger/funding/ledger_polymarket_funding_explainer_sheet.dart'
    show pushLedgerPmFundsAvailableConfirmation;
import 'package:kute/screens/ledger/ledger_action_ui.dart';
import 'package:kute/screens/ledger/ledger_approval_sheet.dart';
import 'package:kute/screens/ledger/polymarket/ledger_pm_support.dart'
    show ledgerPmBatchReconcile;
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/route_pause_gate.dart';
import 'package:kute/services/funding/ledger_polymarket_funding_service.dart';
import 'package:kute/services/release/route_pause_policy.dart';
import 'package:kute/services/tracking_service.dart';

/// Opens the sheet for Ledger wallet [walletId]. Does nothing while
/// `kLedgerInvestingEnabled` is off.
Future<void> showLedgerMakeFundsAvailableSheet(
  BuildContext context, {
  required String walletId,
}) async {
  if (!kLedgerInvestingEnabled) return;
  // F16: making funds available is the last step of Ledger funding.
  if (!await ensureRouteNotPaused(context, PausableRoute.ledgerFunding) ||
      !context.mounted) {
    return;
  }
  TrackingService.ledgerActionSheetOpened(action: 'pm_make_funds_available');
  await showAppBottomSheet<void>(
    context: context,
    builder: (_) => LedgerMakeFundsAvailableSheet(walletId: walletId),
  );
}

class LedgerMakeFundsAvailableSheet extends ConsumerStatefulWidget {
  const LedgerMakeFundsAvailableSheet({super.key, required this.walletId});

  final String walletId;

  @override
  ConsumerState<LedgerMakeFundsAvailableSheet> createState() =>
      _LedgerMakeFundsAvailableSheetState();
}

class _LedgerMakeFundsAvailableSheetState
    extends ConsumerState<LedgerMakeFundsAvailableSheet> {
  LedgerPmMakeAvailablePlan? _plan;
  String? _error;
  String? _errorDetail;
  bool _loading = true;
  bool _working = false;
  String? _note;

  LedgerPolymarketFundingService get _service =>
      ref.read(ledgerPolymarketFundingServiceProvider(widget.walletId));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  static String _bucket(BigInt usdce) =>
      TrackingService.usdBucket(usdce.toDouble() / 1e6);

  Future<void> _load() async {
    if (!mounted) return;
    final l10n = context.l10n;
    setState(() {
      _loading = true;
      _error = null;
      _errorDetail = null;
    });
    try {
      final plan = await _service.prepareMakeFundsAvailable();
      if (!mounted) return;
      // The approval sheet shows this summary; the device shows a code.
      final labelled = await _service.prepareMakeFundsAvailable(
        amount: plan.amount,
        summary: {
          l10n.ledgerPmMakeAvailableAmountLabel:
              ledgerFormatMicros(plan.amount),
        },
      );
      if (!mounted) return;
      TrackingService.ledgerPmMakeAvailableViewed(available: true);
      setState(() {
        _plan = labelled;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      TrackingService.ledgerPmMakeAvailableViewed(available: false);
      setState(() {
        _loading = false;
        _error = _messageFor(e);
        _errorDetail = ledgerFundingErrorDetail(e);
      });
    }
  }

  String _messageFor(Object error) {
    final l10n = context.l10n;
    if (error is LedgerPmFundingRefused &&
        (error.reason == LedgerPmFundingRefusal.nothingToMove ||
            error.reason == LedgerPmFundingRefusal.collateralNotAvailable)) {
      return l10n.ledgerPmMakeAvailableNothing;
    }
    return ledgerFundingErrorMessage(context, error);
  }

  Future<void> _approve() async {
    final plan = _plan;
    if (plan == null || _working) return;
    final l10n = context.l10n;
    setState(() {
      _working = true;
      _note = null;
    });
    final walletId = widget.walletId;
    final service = _service;
    final factory = ref.read(ledgerPmExecutorFactoryProvider);
    final navigator = Navigator.of(context, rootNavigator: true);
    TrackingService.ledgerApprovalRequested(
        action: 'pm_make_funds_available', clarity: 'opaque');
    final outcome = await showLedgerApprovalSheet<String>(
      context,
      walletId: walletId,
      request: LedgerActionRequest<String>(
        intent: plan.intent,
        amountUsd: plan.amount.toDouble() / 1e6,
        execute: (signing) => service.executeMakeFundsAvailable(
          plan,
          executor: LedgerPolymarketExecutorCollateral(factory(
            walletId: walletId,
            pairedAddress: signing.pairedAddress,
            signer: signing.signer,
            account: plan.account,
            belongsToLedger: plan.belongsToLedger,
          )),
        ),
        reconcile: ledgerPmBatchReconcile(ref,
            walletId: walletId, account: plan.account),
      ),
    );
    if (!mounted) return;
    TrackingService.ledgerApprovalResult(
        action: 'pm_make_funds_available', outcome: outcome.kind.name);
    TrackingService.ledgerPmMakeAvailableResult(
      outcome: outcome.kind.name,
      amountBucket: _bucket(plan.amount),
    );
    switch (outcome.kind) {
      case LedgerApprovalOutcomeKind.success:
        TrackingService.ledgerActionSubmitted(
          action: 'pm_make_funds_available',
          amountBucket: _bucket(plan.amount),
        );
        ref.invalidate(ledgerPmAccountProvider(walletId));
        Navigator.of(context).pop();
        pushLedgerPmFundsAvailableConfirmation(
          navigator: navigator,
          l10n: l10n,
          onDone: () => navigator.pop(),
        );
        return;
      case LedgerApprovalOutcomeKind.pending:
      case LedgerApprovalOutcomeKind.backgrounded:
        ref.invalidate(ledgerPmAccountProvider(walletId));
        setState(() {
          _working = false;
          _note = l10n.ledgerPmMakeAvailablePending;
        });
        return;
      case LedgerApprovalOutcomeKind.cancelled:
      case LedgerApprovalOutcomeKind.failed:
        setState(() => _working = false);
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keeps the wallet's service alive for the whole sheet.
    ref.watch(ledgerPolymarketFundingServiceProvider(widget.walletId));
    final l10n = context.l10n;
    final plan = _plan;
    final note = _note;
    return LedgerActionSheetFrame(
      title: l10n.ledgerPmMakeAvailableTitle,
      subtitle: l10n.ledgerPmMakeAvailableSubtitle,
      body: [
        if (_loading)
          LedgerFundingBusyCard(message: l10n.ledgerPmFundStepPlan)
        else if (_error != null)
          LedgerFundingMessageCard(
              message: _error!, isError: true, detail: _errorDetail)
        else if (plan != null) ...[
          LedgerFundingIntroLine(text: l10n.ledgerPmMakeAvailableBody),
          SizedBox(height: 12.h),
          LedgerFundingRow(
            label: l10n.ledgerPmMakeAvailableAmountLabel,
            value: ledgerFormatMicros(plan.amount),
          ),
          SizedBox(height: 8.h),
          LedgerNote(text: l10n.ledgerOpaqueNote),
          LedgerFundingHowThisWorks(lines: [
            l10n.ledgerPmMakeAvailableApproval,
            l10n.ledgerPmFundSheetGasPlain,
          ]),
          if (note != null) ...[
            SizedBox(height: 8.h),
            LedgerFundingMessageCard(message: note),
          ],
        ],
      ],
      buttons: [
        if (plan != null && _error == null && !_loading) ...[
          AppButton(
            text: l10n.ledgerFundApproveCta,
            isLoading: _working,
            onPressed: _working ? null : _approve,
          ),
          SizedBox(height: 10.h),
        ],
        if (_error != null && !_loading) ...[
          AppButton(text: l10n.retry, onPressed: _load),
          SizedBox(height: 10.h),
        ],
        AppButton(
          text: l10n.cancel,
          variant: AppButtonVariant.secondary,
          onPressed: _working ? null : () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
