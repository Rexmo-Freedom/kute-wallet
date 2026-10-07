// lib/screens/ledger/funding/ledger_fund_investing_sheet.dart
//
// Ledger Bitcoin into Investing (HyperCore USDC) through Orchestra
// (Wallet hardening Phase 4, P4.10). Behind `kLedgerInvestingEnabled`.
//
// Laid out like the Move sheet on the main screen: From (this Ledger) and
// To (Investing) chips, one big amount with the currency pill, the shared
// fee block on review and one primary CTA. The From chip offers the
// onramps the runtime policy offers (Cash App today); those hand over to
// the Move sheet through the caller. With none on offer the chip is
// plain: a picker whose only row is this Ledger's Bitcoin has no purpose.
//
// Order of steps, chosen so the two-minute quote is not spent on device
// setup:
//   1. Amount entry under one plain line (two Ledger approvals, ready
//      after the network confirms); the details sit behind "How this
//      works".
//   2. Connect (device picker), confirm the refund address on the Ledger.
//   3. Verified quote, review.
//   4. Build the PSBT, sign on the Ledger, broadcast. An expired quote is
//      never broadcast: the sheet re-quotes and asks for a new review.
//
// Enforcement lives in the services; this sheet never holds a key and
// never touches hot providers.

import 'dart:async';
import 'package:kute/helpers/formatters/currency_formatter.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/constants/feature_flags.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/bitcoin_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/balance_provider.dart'
    show balanceForWalletProvider;
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart';
import 'package:kute/screens/ledger/funding/ledger_deposit_source_sheet.dart';
import 'package:kute/screens/ledger/funding/ledger_funding_parts.dart';
import 'package:kute/screens/ledger/ledger_action_ui.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/screens/shared/ledger_device_picker.dart';
import 'package:kute/screens/shared/route_pause_gate.dart';
import 'package:kute/services/release/route_pause_policy.dart';
import 'package:kute/services/bitcoin/ledger_btc_send_service.dart';
import 'package:kute/services/funding/ledger_hypercore_funding_service.dart';
import 'package:kute/services/ledger_service.dart';
import 'package:kute/services/onramp_visibility.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/models/settlement_operation.dart' show SettlementFlow;
import 'package:kute/services/security/wallet_guard_exception.dart';
import 'package:kute/services/tracking_service.dart';

/// Opens the sheet for Ledger wallet [walletId]. Does nothing while
/// `kLedgerInvestingEnabled` is off.
///
/// Returns a fiat [LedgerDepositSource] only when the user changed the From
/// chip to Cash App or bank; the caller then opens that deposit in the Move
/// sheet. Null after a Bitcoin deposit or a cancel.
Future<LedgerDepositSource?> showLedgerFundInvestingSheet(
  BuildContext context, {
  required String walletId,
  int? initialAmountSats,
  bool autoStart = false,
  VoidCallback? onSubmitted,
}) async {
  if (!kLedgerInvestingEnabled) return null;
  // F16: a remote pause of new Ledger funding stops here.
  if (!await ensureRouteNotPaused(context, PausableRoute.ledgerFunding) ||
      !context.mounted) {
    return null;
  }
  return showAppBottomSheet<LedgerDepositSource>(
    context: context,
    isDismissible: false,
    builder: (_) => LedgerFundInvestingSheet(
      walletId: walletId,
      initialAmountSats: initialAmountSats,
      autoStart: autoStart,
      onSubmitted: onSubmitted,
    ),
  );
}

enum _FundStep {
  intro,
  connecting,
  verifyingRefund,
  quoting,
  review,
  preparing,
  signing,
  broadcasting,
  error,
}

class LedgerFundInvestingSheet extends ConsumerStatefulWidget {
  const LedgerFundInvestingSheet({
    super.key,
    required this.walletId,
    this.initialAmountSats,
    this.autoStart = false,
    this.onSubmitted,
  });

  final String walletId;
  final int? initialAmountSats;
  final bool autoStart;
  /// Called once when the device flow submitted the move (the caller's
  /// funnel outcome; this sheet reports its own result).
  final VoidCallback? onSubmitted;

  @override
  ConsumerState<LedgerFundInvestingSheet> createState() =>
      _LedgerFundInvestingSheetState();
}

class _LedgerFundInvestingSheetState
    extends ConsumerState<LedgerFundInvestingSheet> {
  static const String _route = kLedgerBtcToHypercoreRouteVersion;

  final _amountController = TextEditingController();
  late final String _btcFormat;
  late final LedgerService _ledger = ref.read(ledgerServiceProvider.notifier);

  _FundStep _step = _FundStep.intro;
  String? _error;
  String? _errorDetail;
  bool _quoteRefreshed = false;

  /// The last refresh happened because the price ran out during the Ledger
  /// approval (the signature was discarded).
  bool _expiredDuringApproval = false;
  bool _connected = false;
  LedgerVerifiedBtcAddress? _refund;
  LedgerHypercoreFundingReview? _review;
  Timer? _ticker;

  WalletConfig? get _wallet {
    for (final w in ref.read(settingsProvider).wallets) {
      if (w.id == widget.walletId) return w;
    }
    return null;
  }

  bool get _busy =>
      _step != _FundStep.intro &&
      _step != _FundStep.review &&
      _step != _FundStep.error;

  @override
  void initState() {
    super.initState();
    _btcFormat = ref.read(settingsProvider).btcFormat;
    final sats = widget.initialAmountSats;
    if (sats == null || sats <= 0 || sats > 2100000000000000) return;
    _amountController.text = _btcFormat == 'sats' ? sats.toString() : formatSatsAsBtc(sats);
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _step == _FundStep.intro) unawaited(_start());
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

  int? _amountSats() {
    final units = LedgerHypercoreFundingService.parseDecimalBaseUnits(
        _amountController.text, _btcFormat == 'sats' ? 0 : 8);
    if (units == null || units <= BigInt.zero) return null;
    if (units > BigInt.from(2100000000000000)) return null;
    return units.toInt();
  }

  double _usdPerBtc() => ref.read(selectedCurrencyProvider('USD')).toDouble();

  String _amountBucket(int sats) =>
      TrackingService.usdBucket(sats / 1e8 * _usdPerBtc());

  void _setStep(_FundStep step) {
    if (!mounted) return;
    setState(() => _step = step);
  }

  void _fail(Object error) {
    if (!mounted) return;
    setState(() {
      _error = ledgerFundingErrorMessage(context, error);
      _errorDetail = ledgerFundingErrorDetail(error);
      _step = _FundStep.error;
    });
  }

  // ───────────────────────────── flow ─────────────────────────────

  Future<void> _start() async {
    if (_busy) return;
    final wallet = _wallet;
    final sats = _amountSats();
    if (wallet == null || sats == null) {
      setState(() {
        _error = context.l10n.ledgerFundInvalidAmount;
        _step = _FundStep.error;
      });
      return;
    }
    HapticFeedback.lightImpact();
    TrackingService.ledgerFundingStarted(route: _route);
    final service = ref.read(ledgerHypercoreFundingServiceProvider);
    try {
      _setStep(_FundStep.connecting);
      if (!await service.forwardAvailable()) {
        throw const LedgerFundingException(LedgerFundingError.routeUnavailable);
      }
      if (!mounted) return;

      if (_refund == null) {
        _setStep(_FundStep.connecting);
        final device = await showLedgerDevicePicker(context, ref);
        if (!mounted) return;
        if (device == null) {
          TrackingService.ledgerFundingCancelled(
              route: _route, step: 'connect');
          _setStep(_FundStep.intro);
          return;
        }
        _connected = true;

        _setStep(_FundStep.verifyingRefund);
        final info =
            await ref.read(walletReceiveInfoProvider(wallet.id).future);
        final refund = await ref
            .read(ledgerBtcSendServiceProvider)
            .verifyReceiveAddress(
                wallet: wallet, address: info.address, index: info.index);
        TrackingService.ledgerAddressVerified(context: 'funding_refund');
        _refund = refund;
      }

      await _quote(wallet, sats);
    } catch (e) {
      TrackingService.ledgerFundingResult(
        route: _route,
        outcome: ledgerFundingOutcomeCode(e),
        amountBucket: _amountBucket(sats),
      );
      _fail(e);
    }
  }

  Future<void> _quote(
    WalletConfig wallet,
    int sats, {
    String? supersededQuoteId,
    bool duringApproval = false,
  }) async {
    _setStep(_FundStep.quoting);
    final review =
        await ref.read(ledgerHypercoreFundingServiceProvider).quoteForward(
              wallet: wallet,
              amountSats: sats,
              refund: _refund!,
              usdPerBtc: _usdPerBtc(),
              supersededQuoteId: supersededQuoteId,
              supersedeReason: duringApproval
                  ? 'expired_during_approval'
                  : 'expired_before_prompt',
            );
    if (!mounted) return;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    setState(() {
      _review = review;
      _step = _FundStep.review;
    });
  }

  Future<void> _approve() async {
    final review = _review;
    if (review == null || _busy) return;
    HapticFeedback.lightImpact();
    if (_quoteRefreshed) {
      TrackingService.settlementRereviewConfirmed(
          SettlementFlow.ledgerBtcToInvesting.code);
    }
    final service = ref.read(ledgerHypercoreFundingServiceProvider);
    try {
      _setStep(_FundStep.preparing);
      final feeRate = await ref.read(getCustomFeeRateProvider.future);
      final prepared =
          await service.prepareForward(review, feeRateSatVb: feeRate);
      if (!mounted) return;

      _setStep(_FundStep.signing);
      TrackingService.ledgerApprovalRequested(
          action: 'btc_funding_psbt', clarity: 'readable');
      final signed = await service.signForward(prepared);
      TrackingService.ledgerApprovalResult(
          action: 'btc_funding_psbt', outcome: 'signed');
      if (!mounted) return;

      _setStep(_FundStep.broadcasting);
      final outcome = await service.broadcastForward(signed);
      if (!mounted) return;
      switch (outcome) {
        case LedgerFundingQuoteExpired(:final duringApproval):
          await _requote(review, duringApproval: duringApproval);
        case LedgerFundingSubmitted():
          _finish(review, pending: false);
        case LedgerFundingSubmitPending():
          _finish(review, pending: true);
      }
    } on WalletGuardException catch (e) {
      // Too little time left before the device prompt (B5): nothing was
      // signed. Show the new price for another review instead of an error.
      if (e.reason != WalletGuardReason.quoteExpired || !mounted) {
        _trackAndFail(e, review);
        return;
      }
      try {
        await _requote(review, duringApproval: false);
      } catch (e2) {
        _trackAndFail(e2, review);
      }
    } catch (e) {
      _trackAndFail(e, review);
    }
  }

  /// A quote replaced before anything was sent: new quote, new review.
  Future<void> _requote(LedgerHypercoreFundingReview review,
      {required bool duringApproval}) async {
    TrackingService.ledgerFundingQuoteRefreshed(route: _route);
    _quoteRefreshed = true;
    _expiredDuringApproval = duringApproval;
    await _quote(
      review.wallet,
      review.amountSats,
      supersededQuoteId: review.quote.quoteId,
      duringApproval: duringApproval,
    );
  }

  void _trackAndFail(Object e, LedgerHypercoreFundingReview review) {
    TrackingService.ledgerFundingResult(
      route: _route,
      outcome: ledgerFundingOutcomeCode(e),
      amountBucket: _amountBucket(review.amountSats),
    );
    _fail(e);
  }

  void _finish(LedgerHypercoreFundingReview review, {required bool pending}) {
    _ticker?.cancel();
    TrackingService.ledgerFundingResult(
      route: _route,
      outcome: pending ? 'submit_pending' : 'submitted',
      amountBucket: _amountBucket(review.amountSats),
    );
    TrackingService.ledgerActionSubmitted(
      action: 'btc_to_hypercore',
      amountBucket: _amountBucket(review.amountSats),
    );
    widget.onSubmitted?.call();
    final navigator = Navigator.of(context, rootNavigator: true);
    final l10n = context.l10n;
    Navigator.of(context).pop();
    pushKuteSuccessOverlay(
      navigator: navigator,
      overlay: KuteConfirmation(
        message: l10n.ledgerFundSentMessage,
        detail: pending
            ? l10n.ledgerSubmitPendingPlain
            : l10n.ledgerFundSentDetail,
        onDone: () => navigator.pop(),
      ),
    );
  }

  void _cancel() {
    if (_step != _FundStep.intro) {
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
      _quoteRefreshed = false;
      _expiredDuringApproval = false;
      _step = _FundStep.intro;
    });
  }

  /// The From chip. Cash App and bank deposits run through the Move sheet,
  /// so the pick is handed back to the caller and this sheet closes.
  /// Wired only while the policy offers Cash App (see [build]).
  Future<void> _changeSource() async {
    if (_busy) return;
    final source =
        await showLedgerDepositSourceSheet(context, predictions: false);
    if (!mounted || source == null || source == LedgerDepositSource.bitcoin) {
      return;
    }
    Navigator.of(context).pop(source);
  }

  // ───────────────────────────── UI ───────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Watched, so the chip follows the policy live.
    final fiatSourceOffered = onrampVisible(
        ref.watch(runtimeCapabilitiesProvider), kOnrampCashApp);
    return AppBottomSheetContainer(
      maxHeight: 0.9,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppBottomSheetHeader(title: l10n.ledgerFundInvestingTitle),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              child: switch (_step) {
                _FundStep.intro => _LedgerFundIntro(
                    walletId: widget.walletId,
                    wallet: _wallet,
                    controller: _amountController,
                    btcFormat: _btcFormat,
                    onChangeSource: fiatSourceOffered ? _changeSource : null,
                  ),
                _FundStep.review => _LedgerFundReview(
                    review: _review!,
                    btcFormat: _btcFormat,
                    wallet: _wallet,
                    refreshNote: _quoteRefreshed
                        ? ledgerQuoteRefreshedNote(l10n,
                            duringApproval: _expiredDuringApproval)
                        : null,
                  ),
                _FundStep.error => LedgerFundingMessageCard(
                    message: _error ?? l10n.ledgerFundGenericError,
                    isError: true,
                    detail: _errorDetail,
                  ),
                _ => LedgerFundingBusyCard(message: _busyMessage(context)),
              },
            ),
          ),
          SizedBox(height: 16.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: Column(
              children: [
                if (_step == _FundStep.intro)
                  AppButton(
                    text: l10n.ledgerFundConnectCta,
                    onPressed: _start,
                  ),
                if (_step == _FundStep.review)
                  AppButton(
                    text: l10n.ledgerFundApproveCta,
                    onPressed: _approve,
                  ),
                if (_step == _FundStep.error)
                  AppButton(
                    text: l10n.retry,
                    onPressed: _backToIntro,
                  ),
                SizedBox(height: 10.h),
                AppButton(
                  text: l10n.cancel,
                  variant: AppButtonVariant.secondary,
                  onPressed:
                      _busy && _step != _FundStep.connecting ? null : _cancel,
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
      _FundStep.connecting => l10n.ledgerFundStepConnect,
      _FundStep.verifyingRefund => l10n.ledgerFundStepConfirmRefund,
      _FundStep.quoting => l10n.ledgerFundStepQuote,
      _FundStep.preparing => l10n.ledgerFundStepPrepare,
      _FundStep.signing => l10n.ledgerFundStepSign,
      _FundStep.broadcasting => l10n.ledgerFundStepBroadcast,
      _ => l10n.ledgerFundStepQuote,
    };
  }
}

// ─────────────────────────────── parts ──────────────────────────────────

/// From: this Ledger's Bitcoin. To: Investing (HyperCore USDC). The From
/// chip opens the source picker when [onChangeSource] is set.
LedgerFundingEndpoints _fundEndpoints(
  BuildContext context,
  WalletConfig? wallet, {
  VoidCallback? onChangeSource,
}) {
  final l10n = context.l10n;
  return LedgerFundingEndpoints(
    from: ledgerWalletEndpoint(context, wallet, onTap: onChangeSource),
    to: LedgerFundingEndpoint(
      title: l10n.ledgerTabInvesting,
      subtitle: l10n.ledgerFundBalanceLabel,
      asset: 'lib/assets/hyperliquid-logo.svg',
    ),
  );
}

class _LedgerFundIntro extends ConsumerWidget {
  const _LedgerFundIntro({
    required this.walletId,
    required this.wallet,
    required this.controller,
    required this.btcFormat,
    required this.onChangeSource,
  });

  final String walletId;
  final WalletConfig? wallet;
  final TextEditingController controller;
  final String btcFormat;

  /// Null leaves the From chip plain (no onramp on offer).
  final VoidCallback? onChangeSource;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final usdPerBtc = ref.watch(selectedCurrencyProvider('USD')).toDouble();
    // The Ledger's synced on-chain balance; 0 while nothing is cached, in
    // which case the line stays quiet instead of flagging every amount.
    final availableSats =
        ref.watch(balanceForWalletProvider(walletId)).onChainBtcBalance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fundEndpoints(context, wallet, onChangeSource: onChangeSource),
        SizedBox(height: 20.h),
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final units = LedgerHypercoreFundingService.parseDecimalBaseUnits(
                controller.text, btcFormat == 'sats' ? 0 : 8);
            final typed =
                units == null || units <= BigInt.zero ? BigInt.zero : units;
            final usd = typed.toDouble() / 1e8 * usdPerBtc;
            return LedgerFundingBigAmountField(
              controller: controller,
              unitFlag: '₿',
              unitCode: btcFormat == 'sats' ? 'sats' : 'BTC',
              semanticLabel: l10n.ledgerFundAmountLabel,
              conversionLabel: typed > BigInt.zero && usdPerBtc > 0
                  ? ledgerFormatUsd(usd)
                  : null,
              availableLabel: availableSats > 0
                  ? l10n.ledgerAvailableAmount(
                      '${availableSats.toFormattedString(btcFormat)} ${btcFormat == 'sats' ? 'sats' : 'BTC'}')
                  : null,
              availableExceeded:
                  availableSats > 0 && typed > BigInt.from(availableSats),
            );
          },
        ),
        SizedBox(height: 16.h),
        LedgerFundingIntroLine(text: l10n.ledgerFundIntroLine),
        LedgerFundingHowThisWorks(lines: [
          l10n.ledgerFundExplainConfirmations(
              LedgerHypercoreFundingService.forwardDeviceConfirmations),
          l10n.ledgerFundExplainUnavailable,
          l10n.ledgerFundExplainCashSeparate,
        ]),
      ],
    );
  }
}

class _LedgerFundReview extends StatelessWidget {
  const _LedgerFundReview({
    required this.review,
    required this.btcFormat,
    required this.wallet,
    this.refreshNote,
  });

  final LedgerHypercoreFundingReview review;
  final String btcFormat;
  final WalletConfig? wallet;

  /// Why the price on screen is new, or null for a first review.
  final String? refreshNote;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final secondsLeft =
        review.expiresAt.difference(DateTime.now()).inSeconds.clamp(0, 999);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fundEndpoints(context, wallet),
        SizedBox(height: 16.h),
        if (refreshNote != null) ...[
          LedgerFundingMessageCard(message: refreshNote!),
          SizedBox(height: 12.h),
        ],
        LedgerFundingFeesRow(
          quote: review.quote.quote,
          amountSats: review.amountSats,
        ),
        LedgerFundingRow(
          label: l10n.ledgerFundReviewExpires,
          value: l10n.ledgerFundReviewSecondsLeft(secondsLeft),
        ),
        LedgerFundingAdvancedRows(rows: {
          l10n.ledgerFundReviewRefund: review.refund.address,
          l10n.ledgerFundReviewProvider: 'Orchestra',
        }),
        SizedBox(height: 8.h),
        LedgerNote(text: l10n.ledgerFundReviewDeviceNote),
      ],
    );
  }
}
