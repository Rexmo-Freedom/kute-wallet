import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/constants/feature_flags.dart';
import 'package:kute/constants/polymarket_constants.dart';
import 'package:kute/helpers/formatters/currency_formatter.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/ledger/ledger_action_controller.dart';
import 'package:kute/providers/ledger/ledger_executors_provider.dart';
import 'package:kute/providers/ledger/ledger_identity_provider.dart';
import 'package:kute/providers/ledger/ledger_polymarket_account_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/ledger/funding/ledger_funding_parts.dart';
import 'package:kute/screens/ledger/funding/ledger_polymarket_funding_explainer_sheet.dart';
import 'package:kute/screens/ledger/ledger_action_ui.dart';
import 'package:kute/screens/ledger/ledger_approval_sheet.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/ledger_device_picker.dart';
import 'package:kute/screens/shared/route_pause_gate.dart';
import 'package:kute/services/funding/ledger_polymarket_funding_service.dart';
import 'package:kute/services/funding/settlement_quote_policy.dart';
import 'package:kute/services/funding/settlement_runner.dart'
    show SettlementStopped, SettlementStopReason;
import 'package:kute/services/hardware/ledger/deposit_wallet_call_allowlist.dart';
import 'package:kute/services/hardware/ledger/ledger_action_intent.dart';
import 'package:kute/services/hardware/ledger/ledger_failure.dart';
import 'package:kute/services/hardware/ledger/ledger_hyperliquid_executor.dart'
    show LedgerSubmissionUnknownException;
import 'package:kute/services/hardware/ledger/ledger_polymarket_executor.dart'
    show ledgerPmContractsLabel;
import 'package:kute/services/hardware/ledger/ledger_submitted_action_store.dart';
import 'package:kute/services/hardware/signing_clarity.dart';
import 'package:kute/services/ledger_service.dart';
import 'package:kute/services/polymarket/polymarket_account_resolver.dart';
import 'package:kute/services/release/route_pause_policy.dart';

/// The amount is chosen in Move. This sheet only prepares, reviews and
/// approves its withdrawal to the same Ledger's device-verified Bitcoin address.
Future<void> showLedgerWithdrawPredictionsSheet(
  BuildContext context, {
  required String walletId,
  required BigInt amountBaseUnits,
  VoidCallback? onSubmitted,
}) async {
  if (!kLedgerInvestingEnabled || !kLedgerPolymarketWithdrawEnabled) {
    await showLedgerPolymarketFundingExplainerSheet(context,
        direction: LedgerPmFundingDirection.toLedgerBitcoin,
        withdrawEnabled: false);
    return;
  }
  if (!await ensureRouteNotPaused(context, PausableRoute.ledgerFunding) ||
      !context.mounted) {
    return;
  }
  await showAppBottomSheet<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => LedgerWithdrawPredictionsSheet(
      walletId: walletId,
      amountBaseUnits: amountBaseUnits,
      onSubmitted: onSubmitted,
    ),
  );
}

enum _Step {
  checking,
  prepare,
  ready,
  connecting,
  quoting,
  review,
  sending,
  error,
  pending
}

class LedgerWithdrawPredictionsSheet extends ConsumerStatefulWidget {
  const LedgerWithdrawPredictionsSheet({
    super.key,
    required this.walletId,
    required this.amountBaseUnits,
    this.onSubmitted,
  });

  final String walletId;
  final BigInt amountBaseUnits;
  /// Called once when the device flow submitted the move (the caller's
  /// funnel outcome; this sheet reports its own result).
  final VoidCallback? onSubmitted;

  @override
  ConsumerState<LedgerWithdrawPredictionsSheet> createState() =>
      _LedgerWithdrawPredictionsSheetState();
}

class _LedgerWithdrawPredictionsSheetState
    extends ConsumerState<LedgerWithdrawPredictionsSheet> {
  late final WalletConfig? _wallet;
  late final LedgerIdentity? _identity;
  late final LedgerPolymarketFundingService _service;
  late final LedgerService _ledger;
  late final String _walletId;
  late final BigInt _amount;
  _Step _step = _Step.ready;
  BigInt _unwrapAmount = BigInt.zero;
  LedgerPmReverseQuote? _review;
  String? _error;
  String? _refreshedNote;
  Timer? _ticker;
  bool _connected = false;

  bool get _enabled =>
      kLedgerInvestingEnabled && kLedgerPolymarketWithdrawEnabled;
  bool get _busy =>
      _enabled &&
      (_step == _Step.checking ||
          _step == _Step.connecting ||
          _step == _Step.quoting ||
          _step == _Step.sending);

  @override
  void initState() {
    super.initState();
    _walletId = widget.walletId;
    _amount = widget.amountBaseUnits;
    _wallet = _currentWallet();
    _identity = ref.read(ledgerIdentityProvider(_walletId));
    _service = ref.read(ledgerPolymarketFundingServiceProvider(_walletId));
    _ledger = ref.read(ledgerServiceProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _enabled) unawaited(_prepare());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    if (_connected) unawaited(_ledger.disconnect().catchError((_) {}));
    super.dispose();
  }

  WalletConfig? _currentWallet() {
    for (final wallet in ref.read(settingsProvider).wallets) {
      if (wallet.id == _walletId) return wallet;
    }
    return null;
  }

  void _ensureWallet() {
    if (!mounted) throw const LedgerFailure(LedgerFailureCode.rejected);
    final current = _currentWallet();
    if (_wallet == null ||
        current == null ||
        !current.isLedger ||
        _identity?.hasVerifiedEvm != true ||
        ref.read(ledgerIdentityProvider(_walletId)) != _identity ||
        current.scriptType != _wallet.scriptType ||
        widget.walletId != _walletId ||
        widget.amountBaseUnits != _amount) {
      throw const LedgerFailure(LedgerFailureCode.wrongSigner);
    }
  }

  void _setStep(_Step step) {
    if (mounted) setState(() => _step = step);
  }

  void _fail(Object error, {bool submissionAttempted = false}) {
    if (!mounted) return;
    _ticker?.cancel();
    final pending = error is LedgerSubmissionUnknownException ||
        error is LedgerPmFundingOutcomeUnknown ||
        (error is SettlementStopped &&
            error.reason == SettlementStopReason.blockedPending) ||
        (submissionAttempted &&
            error is! LedgerFailure &&
            error is! LedgerPmFundingRefused &&
            error is! LedgerFundingQuoteExpiredException &&
            error is! LedgerActionBlockedException &&
            error is! LedgerIntentMismatchException &&
            error is! DepositWalletCallRejected &&
            error is! RoutePausedException);
    ref.invalidate(ledgerPendingActionsProvider(_walletId));
    setState(() {
      _error = pending
          ? context.l10n.ledgerFundOutcomeUnknown
          : ledgerFundingErrorMessage(context, error);
      _step = pending ? _Step.pending : _Step.error;
    });
  }

  Future<void> _prepare() async {
    if (_busy || !_enabled) return;
    _setStep(_Step.checking);
    try {
      _ensureWallet();
      if (_amount <= BigInt.zero) {
        throw const LedgerPmFundingRefused(
            LedgerPmFundingRefusal.nothingToMove);
      }
      final balances = await _service.readWithdrawable();
      _ensureWallet();
      final available = balances.availableCollateral;
      if (available == null) {
        throw const LedgerPmFundingRefused(
            LedgerPmFundingRefusal.balanceUnknown);
      }
      if (_amount > available) {
        throw const LedgerPmFundingRefused(
            LedgerPmFundingRefusal.collateralNotAvailable);
      }
      final shortfall = _amount - balances.usdce!;
      _unwrapAmount = shortfall > BigInt.zero ? shortfall : BigInt.zero;
      if (_unwrapAmount > BigInt.zero) {
        _setStep(_Step.prepare);
      } else {
        await _connectAndQuote();
      }
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> _unwrap() async {
    if (_busy || _step != _Step.prepare) return;
    _setStep(_Step.sending);
    try {
      _ensureWallet();
      await _service.unwrapForWithdrawal(
        amount: _unwrapAmount,
        approve: _approveAction,
        summary: {
          context.l10n.ledgerSummaryAction: context.l10n.ledgerUnwrapSummary,
          context.l10n.ledgerSummaryAmount: '${_units(_unwrapAmount, 6)} pUSD',
          context.l10n.ledgerSummaryContracts: ledgerPmContractsLabel(
              const [PolymarketConstants.collateralOfframpAddress]),
        },
      );
      if (!mounted) return;
      ref.invalidate(ledgerPmAccountProvider(_walletId));
      // No withdrawal follows this approval automatically. Continue reads
      // balances again, verifies the BTC address and obtains a fresh quote.
      _setStep(_Step.ready);
      showLedgerConfirmation(Navigator.of(context, rootNavigator: true),
          message: context.l10n.ledgerUnwrapDone);
    } catch (error) {
      _fail(error, submissionAttempted: true);
    }
  }

  Future<void> _connectAndQuote() async {
    _ensureWallet();
    _ticker?.cancel();
    _review = null;
    _setStep(_Step.connecting);
    final device = await showLedgerDevicePicker(context, ref);
    _ensureWallet();
    if (device == null) {
      _setStep(_Step.ready);
      return;
    }
    _connected = true;
    _setStep(_Step.quoting);
    // quoteReverse obtains walletReceiveInfo(walletId) and asks the Bitcoin
    // app to verify it before requesting a quote for that exact recipient.
    final review = await _service.quoteReverse(
      amountUsdce: _amount,
      usdPerBtc: ref.read(selectedCurrencyProvider('USD')).toDouble(),
    );
    _ensureWallet();
    if (review.walletId != _walletId ||
        review.amountUsdce != _amount ||
        int.tryParse(review.quote.quote.estimatedOut) == null) {
      throw const LedgerIntentMismatchException('withdrawal review');
    }
    setState(() {
      _review = review;
      _step = _Step.review;
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _step == _Step.review) setState(() {});
    });
  }

  Future<void> _refreshQuote({bool duringApproval = false}) async {
    if (_busy) return;
    _refreshedNote =
        ledgerQuoteRefreshedNote(context.l10n, duringApproval: duringApproval);
    try {
      await _connectAndQuote();
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> _withdraw() async {
    final review = _review;
    if (_busy || _step != _Step.review || review == null) return;
    _setStep(_Step.sending);
    _ticker?.cancel();
    try {
      _ensureWallet();
      final result = await _service
          .executeReverse(review, approve: _approveAction, summary: {
        context.l10n.ledgerSummaryAmount: '${_units(_amount, 6)} USDC.e',
        context.l10n.ledgerWithdrawReviewReceive: _receiveAmount(review),
        context.l10n.ledgerSummaryDestination: review.recipient.address,
      });
      widget.onSubmitted?.call();
      if (!mounted) return;
      ref.invalidate(ledgerPmAccountProvider(_walletId));
      final navigator = Navigator.of(context, rootNavigator: true);
      final l10n = context.l10n;
      Navigator.of(context).pop();
      showLedgerConfirmation(navigator,
          message: l10n.ledgerPmWithdrawSentHeadline,
          detail: result.submitAccepted
              ? l10n.ledgerPmWithdrawSentDetail
              : l10n.ledgerSubmitPendingPlain);
    } on LedgerFundingQuoteExpiredException catch (expired) {
      if (mounted) {
        _setStep(_Step.review);
        await _refreshQuote(duringApproval: expired.duringApproval);
      }
    } catch (error) {
      _fail(error, submissionAttempted: true);
    }
  }

  Future<String> _approveAction(
    LedgerActionIntent intent, {
    required PolymarketLedgerAccount account,
    bool Function(String address)? belongsToLedger,
    void Function()? ensureStillPayable,
    Future<void> Function(String relayerTxId)? onRelayerSubmitted,
  }) async {
    _ensureWallet();
    final withdrawal = intent.kind == LedgerActionKind.pmWithdrawal;
    if (intent.walletId != _walletId ||
        intent.param<BigInt>('amount') !=
            (withdrawal ? _amount : _unwrapAmount) ||
        (withdrawal &&
            (belongsToLedger == null ||
                ensureStillPayable == null ||
                onRelayerSubmitted == null)) ||
        (!withdrawal &&
            (intent.kind != LedgerActionKind.pmDepositWalletBatch ||
                intent.param<String>('op') != 'unwrap'))) {
      throw const LedgerIntentMismatchException('withdrawal approval');
    }
    final factory = ref.read(ledgerPmExecutorFactoryProvider);
    final pairedAddress = _identity!.evmAddress!;
    String? reconciledHash;
    String? reconciledRelayerId;
    bool reconciledRejected = false;
    bool approvalClosed = false;
    Future<bool?> reconcile(String recordId) async {
      final result = await factory(
        walletId: _walletId,
        pairedAddress: pairedAddress,
        signer: ledgerReadOnlySigner(pairedAddress),
        account: account,
        belongsToLedger: belongsToLedger,
      ).reconcileBatchResult(recordId, expectedIntent: intent);
      if (result.stage == LedgerSubmissionStage.confirmed &&
          result.hash != null) {
        reconciledHash = result.hash;
        reconciledRelayerId = result.relayerTxId;
        return true;
      }
      if (result.stage == LedgerSubmissionStage.rejected) {
        reconciledRejected = true;
        return false;
      }
      return null;
    }

    void beforeSubmit() {
      if (approvalClosed) throw const LedgerFailure(LedgerFailureCode.rejected);
      _ensureWallet();
      ensureStillPayable?.call();
    }

    beforeSubmit();
    Future<String>? execution;
    final outcome = await showLedgerApprovalSheet<String>(
      context,
      walletId: _walletId,
      request: LedgerActionRequest<String>(
        intent: intent,
        amountUsd: intent.param<BigInt>('amount').toDouble() / 1e6,
        execute: (signing) {
          // One funding operation owns one submission. A retry inside the
          // approval sheet follows that same future; it cannot sign again.
          if (execution != null) return execution!;
          execution = () async {
            beforeSubmit();
            if (signing.walletId != _walletId ||
                signing.pairedAddress.toLowerCase() !=
                    pairedAddress.toLowerCase()) {
              throw const LedgerFailure(LedgerFailureCode.wrongSigner);
            }
            final executor = factory(
              walletId: _walletId,
              pairedAddress: signing.pairedAddress,
              signer: signing.signer,
              account: account,
              belongsToLedger: belongsToLedger,
            );
            return withdrawal
                ? await executor.withdraw(intent,
                    beforeSubmit: beforeSubmit,
                    onRelayerSubmitted: onRelayerSubmitted)
                : await executor.unwrap(intent, beforeSubmit: beforeSubmit);
          }();
          return execution!;
        },
        reconcile: reconcile,
      ),
    );
    approvalClosed = true;
    if (outcome.isSuccess && outcome.result != null) return outcome.result!;
    if (outcome.isSuccess && reconciledHash != null) {
      final relayerId = reconciledRelayerId;
      if (relayerId != null) await onRelayerSubmitted?.call(relayerId);
      return reconciledHash!;
    }
    if (reconciledRejected) {
      throw const LedgerFailure(LedgerFailureCode.rejected);
    }
    // A cancelled device prompt can race its completion, just like closing
    // during a POST. Settle the exact future before classifying the outcome.
    if (execution != null) return await execution!;
    if (outcome.isPending) {
      throw LedgerSubmissionUnknownException(
          outcome.recordId ?? 'pm-withdrawal',
          StateError('Waiting for the relayer transaction result'));
    }
    throw const LedgerFailure(LedgerFailureCode.rejected);
  }

  bool get _quoteHasMargin {
    final review = _review;
    return review != null &&
        SettlementQuotePolicy.hasMargin(
          expiresAt: review.quote.expiresAt,
          localNow: DateTime.now(),
          skew: review.skew,
          moment: SettlementMoment.beforeDevicePrompt,
          payer: SettlementPayer.polygonRelayer,
        );
  }

  @override
  Widget build(BuildContext context) {
    // Keep the same service alive between quote and approval; never replace
    // its verified recipient with state from a newly selected wallet.
    ref.watch(ledgerPolymarketFundingServiceProvider(_walletId));
    ref.watch(settingsProvider.select((settings) => settings.btcFormat));
    final l10n = context.l10n;
    return PopScope(
      canPop: !_busy,
      child: LedgerActionSheetFrame(
        title: l10n.ledgerWithdrawTitle,
        subtitle: l10n.ledgerWithdrawSubtitle,
        body: [
          if (!_enabled)
            LedgerNote(text: l10n.ledgerPmWithdrawUnavailable)
          else if (_step == _Step.error || _step == _Step.pending)
            LedgerFundingMessageCard(
                message: _error ?? l10n.ledgerFundGenericError,
                isError: _step == _Step.error)
          else if (_busy)
            LedgerFundingBusyCard(
                message: switch (_step) {
              _Step.connecting => l10n.ledgerFundStepConnect,
              _Step.quoting => l10n.ledgerWithdrawStepConfirmRecipient,
              _Step.sending => l10n.ledgerWithdrawStepSend,
              _ => l10n.ledgerFundStepQuote,
            })
          else ...[
            LedgerFundingEndpoints(
              from: LedgerFundingEndpoint(
                title: l10n.ledgerTabPredictions,
                subtitle: l10n.ledgerFundBalanceLabel,
                asset: 'lib/assets/polymarket-logo.svg',
              ),
              to: ledgerWalletEndpoint(context, _wallet),
            ),
            LedgerFundingRow(
                label: l10n.ledgerWithdrawReviewSend,
                value: ledgerFormatMicros(_amount)),
            if (_step == _Step.prepare) ...[
              LedgerNote(text: l10n.ledgerWithdrawUnwrapFirst),
              LedgerFundingRow(
                  label: l10n.ledgerUnwrapSummary,
                  value: ledgerFormatMicros(_unwrapAmount)),
              LedgerFundingAdvancedRows(rows: {
                l10n.ledgerSummaryAmount: '${_units(_unwrapAmount, 6)} pUSD',
              }),
              const LedgerRelayerFeeRow(),
            ],
            if (_step == _Step.review) ..._reviewRows(context),
            LedgerNote(text: l10n.ledgerPmWithdrawPositionsBody),
            if (_step == _Step.prepare || _step == _Step.review)
              LedgerNote(text: l10n.ledgerOpaqueNote),
          ],
        ],
        buttons: [
          if (_enabled && !_busy && _step != _Step.pending) ...[
            AppButton(
              text: switch (_step) {
                _Step.prepare => l10n.ledgerWithdrawUnwrapCta,
                _Step.review =>
                  _quoteHasMargin ? l10n.ledgerFundApproveCta : l10n.retry,
                _Step.error => l10n.retry,
                _ => l10n.ledgerWithdrawConnectCta,
              },
              onPressed: switch (_step) {
                _Step.prepare => _unwrap,
                _Step.review => _quoteHasMargin ? _withdraw : _refreshQuote,
                _ => _prepare,
              },
            ),
            SizedBox(height: 10.h),
          ],
          AppButton(
            text: _step == _Step.pending || !_enabled ? l10n.done : l10n.cancel,
            variant: AppButtonVariant.secondary,
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  List<Widget> _reviewRows(BuildContext context) {
    final review = _review!;
    final l10n = context.l10n;
    final quote = review.quote.quote;
    final now = SettlementQuotePolicy.effectiveNow(DateTime.now(), review.skew);
    final seconds =
        review.quote.expiresAt.difference(now).inSeconds.clamp(0, 999);
    return [
      if (_refreshedNote != null)
        LedgerFundingMessageCard(message: _refreshedNote!),
      if (!_quoteHasMargin) LedgerNote(text: l10n.guardQuoteExpired),
      LedgerFundingRow(
          label: l10n.ledgerWithdrawReviewTo, value: review.recipient.address),
      LedgerFundingRow(
          label: l10n.ledgerFundReviewExpires,
          value: l10n.ledgerFundReviewSecondsLeft(seconds)),
      const LedgerRelayerFeeRow(),
      LedgerFundingAdvancedRows(rows: {
        l10n.ledgerSummaryAmount: '${_units(_amount, 6)} USDC.e',
        l10n.ledgerFundReviewProvider: 'Orchestra',
        l10n.providerFee: '${(quote.feeBps / 100).toStringAsFixed(2)}%',
        l10n.feeUiKuteFee: quote.appFeeBps == null
            ? l10n.feeUiIncludedInTheAmountYouReceive
            : '${(quote.appFeeBps! / 100).toStringAsFixed(2)}%',
        l10n.ledgerFundReviewRefund: review.refund.address,
      }),
      LedgerNote(text: l10n.ledgerPmWithdrawArrivalBodyPlain),
    ];
  }

  String _receiveAmount(LedgerPmReverseQuote review) {
    final format = ref.read(settingsProvider).btcFormat;
    return '₿${int.parse(review.quote.quote.estimatedOut).toFormattedString(format)}';
  }
}

String _units(BigInt amount, int decimals) {
  final scale = BigInt.from(10).pow(decimals);
  final fraction = (amount % scale)
      .toString()
      .padLeft(decimals, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return fraction.isEmpty
      ? '${amount ~/ scale}'
      : '${amount ~/ scale}.$fraction';
}
