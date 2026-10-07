// lib/screens/ledger/ledger_approval_sheet.dart
//
// Connect-and-approve sheet for one reviewed Ledger action (Wallet
// hardening Phase 4a, P4.5, plan B10). Steps: transport, scan, unlock,
// open or install the Ethereum app, checking account, review with the
// clarity note, approve on Ledger, submitting, result.
//
// * Opened on top of the caller's action sheet, so the caller keeps its
//   intent and entered amount whatever happens here.
// * Cancel is always available (button and system back). Swipe dismissal
//   is off because it would bypass the cancel path.
// * The sheet pops itself on success; the caller shows the shared
//   confirmation (kute_success_overlay.dart) with honest status copy.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/ledger/ledger_action_controller.dart';
import 'package:kute/providers/ledger/ledger_transports_provider.dart';
import 'package:kute/screens/ledger/ledger_connect_steps.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/theme/app_theme.dart';

/// Runs [request] through the Ledger. Never returns success unless the
/// executor completed; a closed sheet is `cancelled` (or `backgrounded`
/// once the request was already submitting).
Future<LedgerApprovalOutcome<R>> showLedgerApprovalSheet<R>(
  BuildContext context, {
  required String walletId,
  required LedgerActionRequest<R> request,
}) async {
  final outcome = await showAppBottomSheet<LedgerApprovalOutcome<Object?>>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => LedgerApprovalSheet(walletId: walletId, request: request),
  );
  if (outcome == null) {
    return LedgerApprovalOutcome<R>(LedgerApprovalOutcomeKind.cancelled);
  }
  final result = outcome.result;
  return LedgerApprovalOutcome<R>(
    outcome.kind,
    result: result is R ? result : null,
    recordId: outcome.recordId,
  );
}

class LedgerApprovalSheet extends ConsumerStatefulWidget {
  const LedgerApprovalSheet({
    super.key,
    required this.walletId,
    required this.request,
  });

  final String walletId;
  final LedgerActionRequest<Object?> request;

  @override
  ConsumerState<LedgerApprovalSheet> createState() =>
      _LedgerApprovalSheetState();
}

class _LedgerApprovalSheetState extends ConsumerState<LedgerApprovalSheet> {
  bool _closing = false;

  LedgerActionController get _controller =>
      ref.read(ledgerActionControllerProvider(widget.walletId).notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.begin(widget.request);
    });
  }

  void _close(LedgerApprovalOutcome<Object?> outcome) {
    if (_closing || !mounted) return;
    _closing = true;
    Navigator.of(context).pop(outcome);
  }

  Future<void> _cancel() async {
    if (_closing) return;
    final state = ref.read(ledgerActionControllerProvider(widget.walletId));
    final kind = await _controller.cancel();
    _close(LedgerApprovalOutcome(
      kind,
      result: state.result,
      recordId: state.recordId,
    ));
  }

  Future<void> _approve() async {
    final approval = ref.read(ledgerAppApprovalProvider);
    final reason = context.l10n.ledgerAppAuthReason;
    await _controller.approve(
      appAuth: (intent) async {
        if (!mounted) return const LedgerAppAuth.declined();
        return approval.authorize(context, ref, intent, reason: reason);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ledgerActionControllerProvider(widget.walletId));
    ref.listen<LedgerApprovalState>(
      ledgerActionControllerProvider(widget.walletId),
      (previous, next) {
        if (next.step == LedgerApprovalStep.success &&
            previous?.step != LedgerApprovalStep.success) {
          _close(LedgerApprovalOutcome(
            LedgerApprovalOutcomeKind.success,
            result: next.result,
            recordId: next.recordId,
          ));
        }
      },
    );
    final l10n = context.l10n;
    final c = context.colors;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: AppBottomSheetContainer(
        maxHeight: 0.9,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppBottomSheetHeader(
              title: ledgerApprovalTitle(l10n, state),
              subtitle: ledgerApprovalSubtitle(l10n, state),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _body(context, state),
                    if (state.step == LedgerApprovalStep.failed) ...[
                      SizedBox(height: 8.h),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          ledgerApprovalErrorMessage(l10n, state),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 15.sp,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _buttons(context, state),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, LedgerApprovalState state) {
    switch (state.step) {
      case LedgerApprovalStep.chooseTransport:
        return LedgerTransportOptions(
          transports: ref.watch(ledgerTransportsProvider),
          onSelected: _controller.selectTransport,
        );
      case LedgerApprovalStep.scanning:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const LedgerStepGlyph(step: LedgerApprovalStep.scanning),
            SizedBox(height: 8.h),
            LedgerFoundDevices(onSelected: _controller.connect),
          ],
        );
      case LedgerApprovalStep.review:
        return LedgerReviewCard(intent: widget.request.intent);
      default:
        return LedgerStepGlyph(step: state.step);
    }
  }

  List<Widget> _buttons(BuildContext context, LedgerApprovalState state) {
    final l10n = context.l10n;
    Widget gap() => SizedBox(height: 10.h);
    Widget secondary(String text, VoidCallback onPressed) => AppButton(
          text: text,
          variant: AppButtonVariant.secondary,
          onPressed: onPressed,
        );

    switch (state.step) {
      case LedgerApprovalStep.review:
        return [
          AppButton(text: l10n.ledgerApproveStep, onPressed: _approve),
          gap(),
          secondary(l10n.cancel, _cancel),
        ];
      case LedgerApprovalStep.unlock:
      case LedgerApprovalStep.installApp:
      case LedgerApprovalStep.updateApp:
        return [
          AppButton(text: l10n.tryAgain, onPressed: _controller.retryPreflight),
          gap(),
          secondary(l10n.cancel, _cancel),
        ];
      case LedgerApprovalStep.openApp:
        return [
          if (state.failure != null) ...[
            AppButton(
                text: l10n.tryAgain, onPressed: _controller.retryPreflight),
            gap(),
          ],
          secondary(l10n.cancel, _cancel),
        ];
      case LedgerApprovalStep.scanning:
        return [
          secondary(l10n.ledgerApprovalScanAgain, _controller.rescan),
          gap(),
          secondary(l10n.cancel, _cancel),
        ];
      case LedgerApprovalStep.submitting:
        return [secondary(l10n.ledgerApprovalClose, _cancel)];
      case LedgerApprovalStep.pending:
        return [
          if (widget.request.reconcile != null) ...[
            AppButton(
              text: l10n.ledgerCheckStatus,
              isLoading: state.checking,
              onPressed: state.checking ? null : _controller.checkPending,
            ),
            gap(),
          ],
          secondary(
            l10n.ledgerApprovalClose,
            () => _close(LedgerApprovalOutcome(
              LedgerApprovalOutcomeKind.pending,
              recordId: state.recordId,
            )),
          ),
        ];
      case LedgerApprovalStep.failed:
        return [
          if (state.canRetry) ...[
            AppButton(
              text: l10n.ledgerApproveAgain,
              onPressed: () => _controller.begin(widget.request),
            ),
            gap(),
          ],
          secondary(
            l10n.ledgerApprovalClose,
            () => _close(LedgerApprovalOutcome(
              LedgerApprovalOutcomeKind.failed,
              recordId: state.recordId,
            )),
          ),
        ];
      case LedgerApprovalStep.success:
        return const [];
      default:
        return [secondary(l10n.cancel, _cancel)];
    }
  }
}
