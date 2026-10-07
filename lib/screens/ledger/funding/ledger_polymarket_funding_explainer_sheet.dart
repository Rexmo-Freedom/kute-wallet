// lib/screens/ledger/funding/ledger_polymarket_funding_explainer_sheet.dart
//
// Shown before a Ledger BTC to Predictions (or Predictions to Ledger BTC)
// route starts (Wallet hardening Phase 4, P4.11, plan B11). It explains,
// before anything is signed or quoted:
// * how many Ledger approvals the route needs,
// * that Bitcoin needs network confirmations,
// * that the network fee for this step is covered (Kute's relayer pays it),
// * that funds cannot be used until they are made available,
// * that creating the predictions account needs an explicit confirmation,
// * for the reverse route, that open predictions are not withdrawable and
//   that the transfer shows a code on the Ledger, not the details.
//
// While O3 (`kLedgerPolymarketWithdrawEnabled`) is off, the reverse
// explainer only says withdrawals are not available yet and offers Close.
//
// The sheet returns a decision; the caller runs the funding service. No
// amounts are shown here and nothing is signed from this sheet.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/constants/feature_flags.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/services/funding/ledger_polymarket_funding_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// What the user chose in the explainer.
class LedgerPmFundingExplainerDecision {
  const LedgerPmFundingExplainerDecision({required this.deployConfirmed});

  /// True only when the account had to be created and the user explicitly
  /// ticked the confirmation. Pass it to
  /// `LedgerPolymarketFundingService.quoteForward(deployConfirmed:)`.
  final bool deployConfirmed;
}

/// Returns null when the user closed the sheet or the route is not
/// available.
Future<LedgerPmFundingExplainerDecision?>
    showLedgerPolymarketFundingExplainerSheet(
  BuildContext context, {
  required LedgerPmFundingDirection direction,
  bool requiresDeploy = false,
  bool needsUnwrap = false,
  int? openPositions,
  bool withdrawEnabled = kLedgerPolymarketWithdrawEnabled,
}) {
  return showAppBottomSheet<LedgerPmFundingExplainerDecision>(
    context: context,
    builder: (_) => LedgerPolymarketFundingExplainerSheet(
      direction: direction,
      requiresDeploy: requiresDeploy,
      needsUnwrap: needsUnwrap,
      openPositions: openPositions,
      withdrawEnabled: withdrawEnabled,
    ),
  );
}

class LedgerPolymarketFundingExplainerSheet extends StatefulWidget {
  const LedgerPolymarketFundingExplainerSheet({
    super.key,
    required this.direction,
    this.requiresDeploy = false,
    this.needsUnwrap = false,
    this.openPositions,
    this.withdrawEnabled = kLedgerPolymarketWithdrawEnabled,
  });

  final LedgerPmFundingDirection direction;
  final bool requiresDeploy;
  final bool needsUnwrap;
  final int? openPositions;
  final bool withdrawEnabled;

  @override
  State<LedgerPolymarketFundingExplainerSheet> createState() =>
      _LedgerPolymarketFundingExplainerSheetState();
}

class _LedgerPolymarketFundingExplainerSheetState
    extends State<LedgerPolymarketFundingExplainerSheet> {
  bool _deployConfirmed = false;

  bool get _isForward =>
      widget.direction == LedgerPmFundingDirection.toPredictions;

  bool get _reverseUnavailable => !_isForward && !widget.withdrawEnabled;

  String get _directionCode =>
      _isForward ? 'to_predictions' : 'to_ledger_bitcoin';

  @override
  void initState() {
    super.initState();
    TrackingService.ledgerPmFundingExplainerViewed(
      direction: _directionCode,
      requiresDeploy: widget.requiresDeploy,
      available: !_reverseUnavailable,
    );
  }

  bool get _canContinue =>
      !_reverseUnavailable && (!widget.requiresDeploy || _deployConfirmed);

  void _continue() {
    if (!_canContinue) return;
    TrackingService.ledgerPmFundingExplainerContinued(
      direction: _directionCode,
      deployConfirmed: widget.requiresDeploy && _deployConfirmed,
    );
    Navigator.of(context).pop(LedgerPmFundingExplainerDecision(
      deployConfirmed: widget.requiresDeploy && _deployConfirmed,
    ));
  }

  void _cancel() {
    TrackingService.ledgerPmFundingExplainerDismissed(direction: _directionCode);
    Navigator.of(context).pop();
  }

  List<_ExplainerPoint> _points(AppLocalizations l10n) {
    if (_isForward) {
      return [
        _ExplainerPoint(
          icon: Icons.verified_user_outlined,
          title: l10n.ledgerPmFundApprovalsTitle(kLedgerPmForwardDeviceApprovals),
          body: l10n.ledgerPmFundApprovalsBody,
        ),
        _ExplainerPoint(
          icon: Icons.schedule_rounded,
          title: l10n.ledgerPmFundConfirmationsTitle,
          body: l10n.ledgerPmFundConfirmationsBody,
        ),
        _ExplainerPoint(
          icon: Icons.local_gas_station_outlined,
          title: l10n.ledgerPmFundGasTitlePlain,
          body: l10n.ledgerPmFundGasBodyPlain,
        ),
        _ExplainerPoint(
          icon: Icons.lock_clock_outlined,
          title: l10n.ledgerPmFundUnavailableTitle,
          body: l10n.ledgerPmFundUnavailableBody,
        ),
      ];
    }
    return [
      _ExplainerPoint(
        icon: Icons.event_busy_outlined,
        title: l10n.ledgerPmWithdrawPositionsTitle,
        body: (widget.openPositions ?? 0) > 0
            ? l10n.ledgerPmWithdrawPositionsOpenBody(widget.openPositions!)
            : l10n.ledgerPmWithdrawPositionsBody,
      ),
      _ExplainerPoint(
        icon: Icons.verified_user_outlined,
        title: l10n.ledgerPmWithdrawApprovalsTitle(widget.needsUnwrap
            ? kLedgerPmReverseDeviceApprovalsWithUnwrap
            : 1),
        body: l10n.ledgerPmWithdrawApprovalsBody,
      ),
      _ExplainerPoint(
        icon: Icons.qr_code_2_rounded,
        title: l10n.ledgerPmWithdrawOpaqueTitle,
        body: l10n.ledgerOpaqueNote,
      ),
      _ExplainerPoint(
        icon: Icons.schedule_rounded,
        title: l10n.ledgerPmWithdrawArrivalTitle,
        body: l10n.ledgerPmWithdrawArrivalBodyPlain,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    return AppBottomSheetContainer(
      maxHeight: 0.9,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBottomSheetHeader(
            title: _isForward
                ? l10n.ledgerPmFundExplainerTitle
                : l10n.ledgerPmWithdrawExplainerTitle,
            subtitle: _reverseUnavailable
                ? l10n.ledgerPmWithdrawUnavailable
                : _isForward
                    ? l10n.ledgerPmFundExplainerSubtitle
                    : l10n.ledgerPmWithdrawExplainerSubtitle,
          ),
          if (!_reverseUnavailable)
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final point in _points(l10n))
                      _ExplainerPointRow(point: point),
                    if (_isForward && widget.requiresDeploy)
                      _DeployConfirmationRow(
                        value: _deployConfirmed,
                        onChanged: (value) =>
                            setState(() => _deployConfirmed = value),
                      ),
                  ],
                ),
              ),
            ),
          SizedBox(height: 12.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: _reverseUnavailable
                ? AppButton(
                    text: l10n.close,
                    variant: AppButtonVariant.secondary,
                    onPressed: _cancel,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppButton(
                        text: l10n.ledgerPmExplainerContinue,
                        onPressed: _canContinue ? _continue : null,
                      ),
                      SizedBox(height: 10.h),
                      AppButton(
                        text: l10n.cancel,
                        variant: AppButtonVariant.secondary,
                        onPressed: _cancel,
                      ),
                    ],
                  ),
          ),
          if (!_reverseUnavailable && widget.requiresDeploy && !_deployConfirmed)
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 0),
              child: Text(
                l10n.ledgerPmDeployConfirmHint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: c.textTertiary,
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ExplainerPoint {
  const _ExplainerPoint({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}

class _ExplainerPointRow extends StatelessWidget {
  const _ExplainerPointRow({required this.point});

  final _ExplainerPoint point;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(bottom: 16.h),
      child: MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Padding(
                padding: EdgeInsets.only(top: 2.h),
                child: Icon(point.icon, size: 22.sp, color: c.textSecondary),
              ),
            ),
            SizedBox(width: 14.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    point.title,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  SizedBox(height: 3.h),
                  Text(
                    point.body,
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeployConfirmationRow extends StatelessWidget {
  const _DeployConfirmationRow({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Semantics(
        checked: value,
        label: l10n.ledgerPmDeployConfirmLabel,
        child: InkWell(
          borderRadius: BorderRadius.circular(12.r),
          onTap: () => onChanged(!value),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 8.h),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Checkbox(
                    value: value,
                    onChanged: (v) => onChanged(v ?? false),
                    activeColor: AppColors.marketUp,
                  ),
                ),
                SizedBox(width: 6.w),
                Expanded(
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.ledgerPmDeployConfirmLabel,
                          style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                        SizedBox(height: 3.h),
                        Text(
                          l10n.ledgerPmDeployConfirmBody,
                          style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w500,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── confirmations ───────────────────────────

/// Shared success confirmation after the forward BTC broadcast (plan
/// B13: "Bitcoin sent. Waiting for confirmations.").
void pushLedgerPmFundingSentConfirmation({
  required NavigatorState navigator,
  required AppLocalizations l10n,
  VoidCallback? onDone,
}) {
  pushKuteSuccessOverlay(
    navigator: navigator,
    overlay: KuteSuccessOverlay(
      headlineLabel: l10n.ledgerPmFundSentHeadline,
      detail: l10n.ledgerPmFundSentDetail,
      onDone: onDone,
    ),
  );
}

/// Shared confirmation after "Make funds available" was accepted.
void pushLedgerPmFundsAvailableConfirmation({
  required NavigatorState navigator,
  required AppLocalizations l10n,
  VoidCallback? onDone,
}) {
  pushKuteSuccessOverlay(
    navigator: navigator,
    overlay: KuteSuccessOverlay(
      headlineLabel: l10n.ledgerPmFundsAvailableHeadline,
      detail: l10n.ledgerPmFundsAvailableDetail,
      onDone: onDone,
    ),
  );
}
