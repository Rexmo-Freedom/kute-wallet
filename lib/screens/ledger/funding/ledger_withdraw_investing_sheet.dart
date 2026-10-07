import 'package:kute/screens/shared/orchestra_fee_summary.dart';
// lib/screens/ledger/funding/ledger_withdraw_investing_sheet.dart
//
// Investing (HyperCore USDC) back to Ledger Bitcoin through Orchestra
// (Wallet hardening Phase 4, P4.10). Behind `kLedgerInvestingEnabled`.
//
// The recipient is confirmed in the Bitcoin app. Native USDC sends and any
// internal balance move are separately reviewed in the Ethereum app.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/constants/feature_flags.dart';
import 'package:kute/providers/ledger/ledger_action_controller.dart';
import 'package:kute/providers/ledger/ledger_executors_provider.dart';
import 'package:kute/screens/ledger/ledger_approval_sheet.dart';
import 'package:kute/services/hardware/ledger/ledger_action_intent.dart';
import 'package:kute/services/hardware/ledger/ledger_failure.dart';
import 'package:kute/services/hardware/ledger/ledger_hyperliquid_executor.dart';
import 'package:kute/services/hardware/signing_clarity.dart';
import 'package:kute/services/hyperliquid/hypercore_cash.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/ledger/ledger_hyperliquid_account_provider.dart';
import 'package:kute/providers/ledger/ledger_identity_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart';
import 'package:kute/screens/ledger/funding/ledger_funding_parts.dart';
import 'package:kute/screens/ledger/ledger_action_ui.dart'
    show LedgerNote, ledgerFormatUsd;
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/screens/shared/ledger_device_picker.dart';
import 'package:kute/screens/shared/route_pause_gate.dart';
import 'package:kute/services/release/route_pause_policy.dart';
import 'package:kute/services/bitcoin/ledger_btc_send_service.dart';
import 'package:kute/services/funding/ledger_hypercore_funding_service.dart';
import 'package:kute/services/ledger_service.dart';
import 'package:kute/services/tracking_service.dart';

/// Opens the sheet for Ledger wallet [walletId]. Does nothing while
/// `kLedgerInvestingEnabled` is off.
Future<void> showLedgerWithdrawInvestingSheet(
  BuildContext context, {
  required String walletId,
  BigInt? initialAmountBaseUnits,
  bool autoStart = false,
  VoidCallback? onSubmitted,
}) async {
  if (!kLedgerInvestingEnabled) return;
  // F16: a remote pause of new Ledger funding stops here.
  if (!await ensureRouteNotPaused(context, PausableRoute.ledgerFunding) ||
      !context.mounted) {
    return;
  }
  await showAppBottomSheet<void>(
    context: context,
    isDismissible: false,
    builder: (_) => LedgerWithdrawInvestingSheet(
      walletId: walletId,
      initialAmountBaseUnits: initialAmountBaseUnits,
      autoStart: autoStart,
      onSubmitted: onSubmitted,
    ),
  );
}

enum _WithdrawStep {
  intro,
  connecting,
  verifyingRecipient,
  quoting,
  review,
  sending,
  error,
}

class LedgerWithdrawInvestingSheet extends ConsumerStatefulWidget {
  const LedgerWithdrawInvestingSheet({
    super.key,
    required this.walletId,
    this.initialAmountBaseUnits,
    this.autoStart = false,
    this.onSubmitted,
  });

  final String walletId;
  final BigInt? initialAmountBaseUnits;
  final bool autoStart;
  /// Called once when the device flow submitted the move (the caller's
  /// funnel outcome; this sheet reports its own result).
  final VoidCallback? onSubmitted;

  @override
  ConsumerState<LedgerWithdrawInvestingSheet> createState() =>
      _LedgerWithdrawInvestingSheetState();
}

class _LedgerWithdrawInvestingSheetState
    extends ConsumerState<LedgerWithdrawInvestingSheet> {
  static const String _route = kHypercoreToLedgerBtcRouteVersion;

  final _amountController = TextEditingController();
  late final LedgerService _ledger = ref.read(ledgerServiceProvider.notifier);

  _WithdrawStep _step = _WithdrawStep.intro;
  String? _error;
  String? _errorDetail;
  bool _quoteRefreshed = false;
  bool _connected = false;
  LedgerVerifiedBtcAddress? _recipient;
  HypercoreLedgerWithdrawReview? _review;
  Timer? _ticker;

  WalletConfig? get _wallet {
    for (final w in ref.read(settingsProvider).wallets) {
      if (w.id == widget.walletId) return w;
    }
    return null;
  }

  bool get _busy =>
      _step != _WithdrawStep.intro &&
      _step != _WithdrawStep.review &&
      _step != _WithdrawStep.error;

  @override
  void initState() {
    super.initState();
    final units = widget.initialAmountBaseUnits;
    if (units == null || units <= BigInt.zero) return;
    final scale = BigInt.from(10).pow(kHypercoreUsdcDecimals);
    final fraction = (units % scale).toString().padLeft(kHypercoreUsdcDecimals, '0');
    _amountController.text = '${units ~/ scale}.$fraction';
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _step == _WithdrawStep.intro) unawaited(_start());
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _amountController.dispose();
    if (_connected) unawaited(_ledger.disconnect().catchError((_) {}));
    super.dispose();
  }

  double? _availableUsdc(LedgerHlAccount? account) {
    final snapshot = account?.account;
    return snapshot == null
        ? null
        : hypercoreAvailableUsdc(snapshot.withdrawable, snapshot.spotBalances);
  }

  String _bucket(BigInt baseUnits) => TrackingService.usdBucket(
      baseUnits.toDouble() / math.pow(10, kHypercoreUsdcDecimals));

  void _setStep(_WithdrawStep step) {
    if (!mounted) return;
    setState(() => _step = step);
  }

  void _fail(Object error) {
    if (!mounted) return;
    setState(() {
      _error = ledgerFundingErrorMessage(context, error);
      _errorDetail = ledgerFundingErrorDetail(error);
      _step = _WithdrawStep.error;
    });
  }

  // ───────────────────────────── flow ─────────────────────────────

  Future<void> _start() async {
    if (_busy) return;
    final l10n = context.l10n;
    final wallet = _wallet;
    final units = LedgerHypercoreFundingService.parseDecimalBaseUnits(
        _amountController.text, kHypercoreUsdcDecimals);
    if (wallet == null || units == null || units <= BigInt.zero) {
      setState(() {
        _error = l10n.ledgerFundInvalidAmount;
        _step = _WithdrawStep.error;
      });
      return;
    }
    final service = ref.read(ledgerHypercoreFundingServiceProvider);
    try {
      _setStep(_WithdrawStep.quoting);
      final identity = ref.read(ledgerIdentityProvider(wallet.id));
      final account =
          await ref.refresh(ledgerHlAccountProvider(wallet.id).future);
      if (!mounted) return;
      final currentIdentity = ref.read(ledgerIdentityProvider(wallet.id));
      final available = identity != null &&
              identity.hasVerifiedEvm &&
              identity == currentIdentity &&
              account.walletId == wallet.id &&
              account.address?.toLowerCase() == identity.evmAddress?.toLowerCase()
          ? _availableUsdc(account)
          : null;
      final cap = available == null || !available.isFinite || available < 0
          ? null
          : BigInt.from(
              (available * math.pow(10, kHypercoreUsdcDecimals)).floor());
      if (cap == null || units > cap) {
        setState(() {
          _error = cap == null
              ? l10n.ledgerWithdrawBalanceUnavailable
              : l10n.ledgerWithdrawExceedsAvailable;
          _step = _WithdrawStep.error;
        });
        return;
      }
      HapticFeedback.lightImpact();
      TrackingService.ledgerFundingStarted(route: _route);
      if (!await service.reverseAvailable()) {
        throw LedgerFundingException(service.reverseReady
            ? LedgerFundingError.routeUnavailable
            : LedgerFundingError.reverseNotReady);
      }
      if (!mounted) return;

      if (_recipient == null) {
        _setStep(_WithdrawStep.connecting);
        final device = await showLedgerDevicePicker(context, ref);
        if (!mounted) return;
        if (device == null) {
          TrackingService.ledgerFundingCancelled(
              route: _route, step: 'connect');
          _setStep(_WithdrawStep.intro);
          return;
        }
        _connected = true;

        _setStep(_WithdrawStep.verifyingRecipient);
        final info =
            await ref.read(walletReceiveInfoProvider(wallet.id).future);
        final recipient = await ref
            .read(ledgerBtcSendServiceProvider)
            .verifyReceiveAddress(
                wallet: wallet, address: info.address, index: info.index);
        TrackingService.ledgerAddressVerified(context: 'withdraw_recipient');
        _recipient = recipient;
      }

      await _quote(wallet, units);
    } catch (e) {
      TrackingService.ledgerFundingResult(
        route: _route,
        outcome: ledgerFundingOutcomeCode(e),
        amountBucket: _bucket(units),
      );
      _fail(e);
    }
  }

  Future<void> _quote(WalletConfig wallet, BigInt units) async {
    _setStep(_WithdrawStep.quoting);
    final review =
        await ref.read(ledgerHypercoreFundingServiceProvider).quoteReverse(
              wallet: wallet,
              amountBaseUnits: units,
              recipient: _recipient!,
              usdPerBtc: ref.read(selectedCurrencyProvider('USD')).toDouble(),
            );
    if (!mounted) return;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    setState(() {
      _review = review;
      _step = _WithdrawStep.review;
    });
  }

  Future<void> _approve() async {
    final review = _review;
    if (review == null || _busy) return;
    HapticFeedback.lightImpact();
    final service = ref.read(ledgerHypercoreFundingServiceProvider);
    try {
      _setStep(_WithdrawStep.sending);
      TrackingService.ledgerApprovalRequested(
          action: 'hl_reverse_send', clarity: 'readable');
      final outcome =
          await service.executeReverse(review, approve: _approveNativeAction);
      if (!mounted) return;
      switch (outcome) {
        case LedgerFundingQuoteExpired():
          TrackingService.ledgerFundingQuoteRefreshed(route: _route);
          _quoteRefreshed = true;
          await _quote(review.wallet, review.totalDebitBaseUnits);
        case LedgerFundingSubmitted():
          _finish(review, pending: false);
        case LedgerFundingSubmitPending():
          _finish(review, pending: true);
      }
    } catch (e) {
      TrackingService.ledgerFundingResult(
        route: _route,
        outcome: ledgerFundingOutcomeCode(e),
        amountBucket: _bucket(review.amountBaseUnits),
      );
      _fail(e);
    }
  }

  Future<int> _approveNativeAction(
    LedgerActionIntent intent, {
    Future<void> Function(int nonce)? onBeforeSend,
    void Function()? beforeSend,
  }) async {
    if (!mounted) throw const LedgerFailure(LedgerFailureCode.rejected);
    final factory = ref.read(ledgerHlExecutorFactoryProvider);
    final originalIdentity = ref.read(ledgerIdentityProvider(widget.walletId));
    void checkDispatch() {
      if (!mounted) throw const LedgerFailure(LedgerFailureCode.rejected);
      final currentIdentity = ref.read(ledgerIdentityProvider(widget.walletId));
      if (originalIdentity == null ||
          originalIdentity != currentIdentity ||
          !originalIdentity.hasVerifiedEvm ||
          originalIdentity.evmAddress?.toLowerCase() !=
              intent.sensitive.account?.toLowerCase()) {
        throw const LedgerIntentMismatchException('wallet');
      }
      beforeSend?.call();
    }
    Object? executionError;
    Future<int>? execution;
    final outcome = await showLedgerApprovalSheet<int>(
      context,
      walletId: widget.walletId,
      request: LedgerActionRequest<int>(
        intent: intent,
        amountUsd: double.parse(intent.param<String>('amount')),
        execute: (signing) {
          execution = () async {
            try {
              final executor = factory(
                  walletId: widget.walletId,
                  pairedAddress: signing.pairedAddress,
                  signer: signing.signer);
              if (intent.kind == LedgerActionKind.hlUsdClassTransfer) {
                await executor.usdClassTransfer(intent,
                    onBeforeSend: onBeforeSend, beforeSend: checkDispatch);
                return 0;
              }
              if (intent.kind != LedgerActionKind.hlUsdSend) {
                throw StateError('Unsupported withdrawal action');
              }
              return await executor.usdSend(intent,
                  onBeforeSend: onBeforeSend!, beforeSend: checkDispatch);
            } catch (error) {
              executionError = error;
              rethrow;
            }
          }();
          return execution!;
        },
      ),
    );
    if (outcome.isSuccess && outcome.result != null) return outcome.result!;
    // Closing while the POST is running does not cancel its outcome. Keep
    // following that exact action rather than offering another signature.
    if (outcome.kind == LedgerApprovalOutcomeKind.backgrounded &&
        execution != null) {
      return await execution!;
    }
    if (executionError != null) throw executionError!;
    if (outcome.isPending) {
      throw LedgerSubmissionUnknownException(outcome.recordId ?? 'native-send',
          StateError('Waiting for the native transfer result'));
    }
    throw const LedgerFailure(LedgerFailureCode.rejected);
  }

  void _finish(HypercoreLedgerWithdrawReview review, {required bool pending}) {
    _ticker?.cancel();
    ref.invalidate(ledgerHlAccountProvider(widget.walletId));
    TrackingService.ledgerApprovalResult(
        action: 'hl_reverse_send', outcome: 'signed');
    TrackingService.ledgerFundingResult(
      route: _route,
      outcome: pending ? 'submit_pending' : 'submitted',
      amountBucket: _bucket(review.amountBaseUnits),
    );
    TrackingService.ledgerActionSubmitted(
      action: 'hypercore_to_btc',
      amountBucket: _bucket(review.amountBaseUnits),
    );
    widget.onSubmitted?.call();
    final navigator = Navigator.of(context, rootNavigator: true);
    final l10n = context.l10n;
    Navigator.of(context).pop();
    pushKuteSuccessOverlay(
      navigator: navigator,
      overlay: KuteConfirmation(
        message: l10n.ledgerWithdrawSentMessage,
        detail: pending
            ? l10n.ledgerSubmitPendingPlain
            : l10n.ledgerArrivesAfterNetwork,
        onDone: () => navigator.pop(),
      ),
    );
  }

  void _cancel() {
    if (_step != _WithdrawStep.intro) {
      TrackingService.ledgerFundingCancelled(route: _route, step: _step.name);
    }
    Navigator.of(context).pop();
  }

  void _backToIntro() {
    _ticker?.cancel();
    setState(() {
      _error = null;
      _errorDetail = null;
      _review = null;
      _step = _WithdrawStep.intro;
    });
  }

  // ───────────────────────────── UI ───────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final service = ref.watch(ledgerHypercoreFundingServiceProvider);
    final ready = service.reverseReady;
    final account =
        ref.watch(ledgerHlAccountProvider(widget.walletId)).valueOrNull;
    final available = _availableUsdc(account);

    return AppBottomSheetContainer(
      maxHeight: 0.9,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppBottomSheetHeader(title: l10n.ledgerWithdrawInvestingTitle),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              child: !ready
                  ? LedgerFundingMessageCard(
                      message: l10n.ledgerWithdrawNotAvailableYet)
                  : switch (_step) {
                      _WithdrawStep.intro => _LedgerWithdrawIntro(
                          wallet: _wallet,
                          controller: _amountController,
                          available: available,
                        ),
                      _WithdrawStep.review => _LedgerWithdrawReview(
                          review: _review!,
                          wallet: _wallet,
                          refreshed: _quoteRefreshed,
                        ),
                      _WithdrawStep.error => LedgerFundingMessageCard(
                          message: _error ?? l10n.ledgerFundGenericError,
                          isError: true,
                          detail: _errorDetail,
                        ),
                      _ =>
                        LedgerFundingBusyCard(message: _busyMessage(context)),
                    },
            ),
          ),
          SizedBox(height: 16.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: Column(
              children: [
                if (ready && _step == _WithdrawStep.intro)
                  AppButton(
                    text: l10n.ledgerWithdrawConnectCta,
                    onPressed: _start,
                  ),
                if (ready && _step == _WithdrawStep.review)
                  AppButton(
                    text: l10n.ledgerFundApproveCta,
                    onPressed: _approve,
                  ),
                if (ready && _step == _WithdrawStep.error)
                  AppButton(text: l10n.retry, onPressed: _backToIntro),
                SizedBox(height: 10.h),
                AppButton(
                  text: ready ? l10n.cancel : l10n.done,
                  variant: AppButtonVariant.secondary,
                  onPressed: _busy && _step != _WithdrawStep.connecting
                      ? null
                      : _cancel,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _busyMessage(BuildContext context) {
    final l10n = context.l10n;
    return switch (_step) {
      _WithdrawStep.connecting => l10n.ledgerFundStepConnect,
      _WithdrawStep.verifyingRecipient =>
        l10n.ledgerWithdrawStepConfirmRecipient,
      _WithdrawStep.sending => l10n.ledgerWithdrawStepSend,
      _ => l10n.ledgerFundStepQuote,
    };
  }
}

/// From: Investing (HyperCore USDC). To: this Ledger's Bitcoin. Both are
/// pinned; a withdrawal only ever goes back to the Ledger.
LedgerFundingEndpoints _withdrawEndpoints(
    BuildContext context, WalletConfig? wallet) {
  final l10n = context.l10n;
  return LedgerFundingEndpoints(
    from: LedgerFundingEndpoint(
      title: l10n.ledgerTabInvesting,
      subtitle: l10n.ledgerFundBalanceLabel,
      asset: 'lib/assets/hyperliquid-logo.svg',
    ),
    to: ledgerWalletEndpoint(context, wallet),
  );
}

class _LedgerWithdrawIntro extends StatelessWidget {
  const _LedgerWithdrawIntro({
    required this.wallet,
    required this.controller,
    required this.available,
  });

  final WalletConfig? wallet;
  final TextEditingController controller;
  final double? available;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final avail = available;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _withdrawEndpoints(context, wallet),
        SizedBox(height: 20.h),
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final units = LedgerHypercoreFundingService.parseDecimalBaseUnits(
                controller.text, kHypercoreUsdcDecimals);
            final typed = units == null || units <= BigInt.zero
                ? 0.0
                : units.toDouble() / math.pow(10, kHypercoreUsdcDecimals);
            return LedgerFundingBigAmountField(
              controller: controller,
              unitFlag: r'$',
              unitCode: 'USD',
              semanticLabel: l10n.ledgerWithdrawAmountLabel,
              availableLabel: avail == null
                  ? l10n.ledgerWithdrawBalanceUnavailable
                  : l10n.ledgerAvailableAmount(ledgerFormatUsd(avail)),
              availableExceeded: avail != null && typed > avail,
              maxLabel: l10n.max,
              onMax: avail == null
                  ? null
                  : () => controller.text =
                      ((avail * 100).floor() / 100).toStringAsFixed(2),
            );
          },
        ),
        SizedBox(height: 16.h),
        LedgerFundingIntroLine(text: l10n.ledgerWithdrawIntroLine),
        LedgerFundingHowThisWorks(lines: [
          l10n.ledgerWithdrawExplainSteps,
          l10n.ledgerFundArrivalPlain,
        ]),
      ],
    );
  }
}

class _LedgerWithdrawReview extends StatelessWidget {
  const _LedgerWithdrawReview({
    required this.review,
    required this.wallet,
    required this.refreshed,
  });

  final HypercoreLedgerWithdrawReview review;
  final WalletConfig? wallet;
  final bool refreshed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final secondsLeft =
        review.expiresAt.difference(DateTime.now()).inSeconds.clamp(0, 999);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _withdrawEndpoints(context, wallet),
        SizedBox(height: 16.h),
        if (refreshed) ...[
          LedgerFundingMessageCard(message: l10n.guardQuoteExpired),
          SizedBox(height: 12.h),
        ],
        LedgerFundingRow(
          label: l10n.ledgerTotalWithdrawal,
          value: '${(review.totalDebitBaseUnits.toDouble() / 1e8).toStringAsFixed(2)} USDC',
        ),
        OrchestraFeeSummary(
          sourceFeeUsd: review.activationFeeBaseUnits.toDouble() / 1e8,
          route: (
            fromChain: 'hypercore',
            fromAsset: 'USDC',
            toChain: 'bitcoin',
            toAsset: 'BTC',
            amount: review.amountBaseUnits.toString(),
          ),
        ),
        LedgerFundingRow(
          label: l10n.ledgerFundReviewExpires,
          value: l10n.ledgerFundReviewSecondsLeft(secondsLeft),
        ),
        LedgerFundingAdvancedRows(rows: {
          l10n.ledgerWithdrawReviewTo: review.recipient.address,
          l10n.ledgerFundReviewProvider: 'Orchestra',
        }),
        SizedBox(height: 8.h),
        LedgerNote(text: l10n.ledgerFundReviewDeviceNote),
      ],
    );
  }
}
