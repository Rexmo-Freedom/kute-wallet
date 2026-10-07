// lib/screens/ledger/funding/ledger_fund_predictions_sheet.dart
//
// Ledger Bitcoin into Predictions (Polygon USDC.e in this Ledger's deposit
// wallet) through Orchestra (Wallet hardening Phase 4, P4.11). Opened by
// Continue in the Polymarket funding explainer. Behind
// `kLedgerInvestingEnabled`.
//
// Order of steps, chosen so the two-minute quote is not spent on device
// setup:
//   1. Amount entry under one plain line (two approvals now, one more
//      when the bitcoin arrives); the details sit behind "How this works".
//   2. Plan (reads only): Phase 5 route availability (live catalog) and
//      the deposit wallet this Ledger owns. An unavailable route refuses
//      here, before any device prompt.
//   3. Connect (device picker). The service creates the account when the
//      user confirmed it, confirms the refund address on the Ledger and
//      fetches a verified quote. Review with a countdown.
//   4. Sign on the Ledger and broadcast through the service. An expired
//      quote is never broadcast: the sheet re-quotes and asks for a new
//      review.
//
// "Make funds available" is a separate later action, not part of this
// sheet. Enforcement lives in the service; this sheet never holds a key
// and never touches hot providers.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/constants/feature_flags.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/balance_provider.dart'
    show balanceForWalletProvider;
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/ledger/funding/ledger_funding_parts.dart';
import 'package:kute/screens/ledger/funding/ledger_polymarket_funding_explainer_sheet.dart';
import 'package:kute/screens/ledger/ledger_action_ui.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/ledger_device_picker.dart';
import 'package:kute/screens/shared/route_pause_gate.dart';
import 'package:kute/services/release/route_pause_policy.dart';
import 'package:kute/services/funding/ledger_hypercore_funding_service.dart'
    show LedgerHypercoreFundingService;
import 'package:kute/services/funding/ledger_polymarket_funding_service.dart';
import 'package:kute/services/ledger_service.dart';
import 'package:kute/models/settlement_operation.dart' show SettlementFlow;
import 'package:kute/services/security/wallet_guard_exception.dart';
import 'package:kute/services/tracking_service.dart';

/// Opens the sheet for Ledger wallet [walletId]. [deployConfirmed] must
/// come from the explainer's explicit confirmation. Does nothing while
/// `kLedgerInvestingEnabled` is off.
Future<void> showLedgerFundPredictionsSheet(
  BuildContext context, {
  required String walletId,
  required bool deployConfirmed,
  int? initialAmountSats,
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
    builder: (_) => LedgerFundPredictionsSheet(
      walletId: walletId,
      deployConfirmed: deployConfirmed,
      initialAmountSats: initialAmountSats,
      autoStart: autoStart,
      onSubmitted: onSubmitted,
    ),
  );
}

enum _PmFundStep {
  intro,
  planning,
  connecting,
  quoting,
  review,
  signing,
  broadcasting,
  error,
}

class LedgerFundPredictionsSheet extends ConsumerStatefulWidget {
  const LedgerFundPredictionsSheet({
    super.key,
    required this.walletId,
    required this.deployConfirmed,
    this.initialAmountSats,
    this.autoStart = false,
    this.onSubmitted,
  });

  final String walletId;
  final bool deployConfirmed;
  final int? initialAmountSats;
  final bool autoStart;
  /// Called once when the device flow submitted the move (the caller's
  /// funnel outcome; this sheet reports its own result).
  final VoidCallback? onSubmitted;

  @override
  ConsumerState<LedgerFundPredictionsSheet> createState() =>
      _LedgerFundPredictionsSheetState();
}

class _LedgerFundPredictionsSheetState
    extends ConsumerState<LedgerFundPredictionsSheet> {
  static const String _route = kLedgerBtcToPolygonUsdceRoute;

  final _amountController = TextEditingController();
  late final LedgerService _ledger = ref.read(ledgerServiceProvider.notifier);

  _PmFundStep _step = _PmFundStep.intro;
  String? _error;
  String? _errorDetail;
  bool _quoteRefreshed = false;

  /// The last refresh happened because the price ran out during the Ledger
  /// approval (the signature was discarded).
  bool _expiredDuringApproval = false;
  bool _connected = false;
  LedgerPmForwardQuote? _quote;
  Timer? _ticker;

  LedgerPolymarketFundingService get _service =>
      ref.read(ledgerPolymarketFundingServiceProvider(widget.walletId));

  WalletConfig? get _wallet {
    for (final w in ref.read(settingsProvider).wallets) {
      if (w.id == widget.walletId) return w;
    }
    return null;
  }

  bool get _busy =>
      _step != _PmFundStep.intro &&
      _step != _PmFundStep.review &&
      _step != _PmFundStep.error;

  @override
  void initState() {
    super.initState();
    final sats = widget.initialAmountSats;
    if (sats == null || sats <= 0 || sats > 2100000000000000) return;
    _amountController.text = formatSatsAsBtc(sats);
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _step == _PmFundStep.intro) unawaited(_start());
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

  BigInt? _amountSats() {
    final units = LedgerHypercoreFundingService.parseDecimalBaseUnits(
        _amountController.text, 8);
    if (units == null || units <= BigInt.zero) return null;
    if (units > BigInt.from(2100000000000000)) return null;
    return units;
  }

  double _usdPerBtc() => ref.read(selectedCurrencyProvider('USD')).toDouble();

  String _amountBucket(BigInt sats) =>
      TrackingService.usdBucket(sats.toDouble() / 1e8 * _usdPerBtc());

  void _setStep(_PmFundStep step) {
    if (!mounted) return;
    setState(() => _step = step);
  }

  void _fail(Object error) {
    if (!mounted) return;
    _ticker?.cancel();
    setState(() {
      _error = ledgerFundingErrorMessage(context, error);
      _errorDetail = ledgerFundingErrorDetail(error);
      _step = _PmFundStep.error;
    });
  }

  /// The service already reports results for signing and broadcast
  /// failures. Report the ones it does not, so each attempt is counted
  /// once.
  void _trackFailure(Object error, BigInt? sats) {
    final trackedByService = error is LedgerPmFundingOutcomeUnknown ||
        (_step == _PmFundStep.signing &&
            error is! StateError &&
            error is! LedgerPmFundingRefused &&
            error is! WalletGuardException);
    if (trackedByService) return;
    TrackingService.ledgerFundingResult(
      route: _route,
      outcome: ledgerFundingOutcomeCode(error),
      amountBucket: sats == null ? null : _amountBucket(sats),
    );
  }

  // ───────────────────────────── flow ─────────────────────────────

  Future<void> _start() async {
    if (_busy) return;
    final sats = _amountSats();
    if (sats == null) {
      setState(() {
        _error = context.l10n.ledgerFundInvalidAmount;
        _step = _PmFundStep.error;
      });
      return;
    }
    HapticFeedback.lightImpact();
    try {
      _setStep(_PmFundStep.planning);
      final plan = await _service.planForward();
      if (!mounted) return;
      if (plan.requiresDeploy && !widget.deployConfirmed) {
        throw const LedgerPmFundingRefused(
            LedgerPmFundingRefusal.deployNotConfirmed);
      }

      if (!_connected) {
        _setStep(_PmFundStep.connecting);
        final device = await showLedgerDevicePicker(context, ref);
        if (!mounted) return;
        if (device == null) {
          TrackingService.ledgerFundingCancelled(
              route: _route, step: 'connect');
          _setStep(_PmFundStep.intro);
          return;
        }
        _connected = true;
      }

      _setStep(_PmFundStep.quoting);
      final quote = await _service.quoteForward(
        plan: plan,
        amountSats: sats,
        usdPerBtc: _usdPerBtc(),
        deployConfirmed: widget.deployConfirmed,
      );
      TrackingService.ledgerAddressVerified(context: 'funding_refund');
      if (!mounted) return;
      _showReview(quote, refreshed: false);
    } catch (e) {
      _trackFailure(e, sats);
      _fail(e);
    }
  }

  void _showReview(
    LedgerPmForwardQuote quote, {
    required bool refreshed,
    bool duringApproval = false,
  }) {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    setState(() {
      _quote = quote;
      _quoteRefreshed = refreshed;
      _expiredDuringApproval = refreshed && duringApproval;
      _step = _PmFundStep.review;
    });
  }

  Future<void> _approve() async {
    final quote = _quote;
    if (quote == null || _busy) return;
    HapticFeedback.lightImpact();
    if (_quoteRefreshed) {
      TrackingService.settlementRereviewConfirmed(
          SettlementFlow.ledgerBtcToPredictions.code);
    }
    _ticker?.cancel();
    _setStep(_PmFundStep.signing);
    TrackingService.ledgerApprovalRequested(
        action: 'btc_funding_psbt', clarity: 'readable');
    try {
      final result = await _service.executeForward(
        quote,
        onStage: (stage) {
          if (stage == LedgerPmFundingStage.signed) {
            TrackingService.ledgerApprovalResult(
                action: 'btc_funding_psbt', outcome: 'signed');
          } else if (stage == LedgerPmFundingStage.broadcasting) {
            _setStep(_PmFundStep.broadcasting);
          }
        },
      );
      if (!mounted) return;
      _finish(quote, result);
    } on LedgerFundingQuoteExpiredException catch (expired) {
      // Nothing was broadcast. Get a new price and ask for a new review.
      if (!mounted) return;
      try {
        _setStep(_PmFundStep.quoting);
        final refreshed = await _service.refreshForwardQuote(quote,
            duringApproval: expired.duringApproval);
        if (!mounted) return;
        _showReview(refreshed,
            refreshed: true, duringApproval: expired.duringApproval);
      } catch (e) {
        _trackFailure(e, quote.amountSats);
        _fail(e);
      }
    } catch (e) {
      _trackFailure(e, quote.amountSats);
      _fail(e);
    }
  }

  void _finish(LedgerPmForwardQuote quote, LedgerPmForwardResult result) {
    _ticker?.cancel();
    TrackingService.ledgerActionSubmitted(
      action: 'btc_to_predictions',
      amountBucket: _amountBucket(quote.amountSats),
    );
    widget.onSubmitted?.call();
    final navigator = Navigator.of(context, rootNavigator: true);
    final l10n = context.l10n;
    Navigator.of(context).pop();
    // Plan B13: the copy stays "Bitcoin sent. Waiting for confirmations."
    // whether or not Orchestra accepted the submit yet.
    pushLedgerPmFundingSentConfirmation(
      navigator: navigator,
      l10n: l10n,
      onDone: () => navigator.pop(),
    );
  }

  void _cancel() {
    if (_step != _PmFundStep.intro) {
      TrackingService.ledgerFundingCancelled(route: _route, step: _step.name);
    }
    Navigator.of(context).pop();
  }

  void _backToIntro() {
    _ticker?.cancel();
    setState(() {
      _error = null;
      _errorDetail = null;
      _quote = null;
      _quoteRefreshed = false;
      _expiredDuringApproval = false;
      _step = _PmFundStep.intro;
    });
  }

  // ───────────────────────────── UI ───────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Keeps the wallet's service alive for the whole sheet: the refund
    // address confirmed in quoteForward is checked again in executeForward.
    ref.watch(ledgerPolymarketFundingServiceProvider(widget.walletId));
    final l10n = context.l10n;
    return AppBottomSheetContainer(
      maxHeight: 0.9,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppBottomSheetHeader(
            title: l10n.ledgerPmFundExplainerTitle,
            subtitle: l10n.ledgerFundInvestingSubtitle,
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              child: switch (_step) {
                _PmFundStep.intro => _PmFundIntro(
                    walletId: widget.walletId,
                    wallet: _wallet,
                    controller: _amountController,
                    deployConfirmed: widget.deployConfirmed,
                  ),
                _PmFundStep.review => _PmFundReview(
                    quote: _quote!,
                    wallet: _wallet,
                    refreshNote: _quoteRefreshed
                        ? ledgerQuoteRefreshedNote(l10n,
                            duringApproval: _expiredDuringApproval)
                        : null,
                  ),
                _PmFundStep.error => LedgerFundingMessageCard(
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
                if (_step == _PmFundStep.intro)
                  AppButton(
                    text: l10n.ledgerPmFundConnectCta,
                    onPressed: _start,
                  ),
                if (_step == _PmFundStep.review)
                  AppButton(
                    text: l10n.ledgerFundApproveCta,
                    onPressed: _approve,
                  ),
                if (_step == _PmFundStep.error)
                  AppButton(
                    text: l10n.retry,
                    onPressed: _backToIntro,
                  ),
                SizedBox(height: 10.h),
                AppButton(
                  text: l10n.cancel,
                  variant: AppButtonVariant.secondary,
                  onPressed:
                      _busy && _step != _PmFundStep.connecting ? null : _cancel,
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
      _PmFundStep.planning => l10n.ledgerPmFundStepPlan,
      _PmFundStep.connecting => l10n.ledgerFundStepConnect,
      _PmFundStep.quoting =>
        _quote == null ? l10n.ledgerPmFundStepQuote : l10n.ledgerFundStepQuote,
      _PmFundStep.signing => l10n.ledgerFundStepSign,
      _PmFundStep.broadcasting => l10n.ledgerFundStepBroadcast,
      _ => l10n.ledgerFundStepQuote,
    };
  }
}

// ─────────────────────────────── parts ──────────────────────────────────

/// From: this Ledger's Bitcoin. To: Predictions. Both pinned.
LedgerFundingEndpoints _pmEndpoints(BuildContext context, WalletConfig? wallet) {
  final l10n = context.l10n;
  return LedgerFundingEndpoints(
    from: ledgerWalletEndpoint(context, wallet),
    to: LedgerFundingEndpoint(
      title: l10n.ledgerTabPredictions,
      subtitle: l10n.ledgerFundBalanceLabel,
      asset: 'lib/assets/polymarket-logo.svg',
    ),
  );
}

class _PmFundIntro extends ConsumerWidget {
  const _PmFundIntro({
    required this.walletId,
    required this.wallet,
    required this.controller,
    required this.deployConfirmed,
  });

  final String walletId;
  final WalletConfig? wallet;
  final TextEditingController controller;
  final bool deployConfirmed;

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
        _pmEndpoints(context, wallet),
        SizedBox(height: 20.h),
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final units = LedgerHypercoreFundingService.parseDecimalBaseUnits(
                controller.text, 8);
            final typed =
                units == null || units <= BigInt.zero ? BigInt.zero : units;
            final usd = typed.toDouble() / 1e8 * usdPerBtc;
            return LedgerFundingBigAmountField(
              controller: controller,
              unitFlag: '₿',
              unitCode: 'BTC',
              semanticLabel: l10n.ledgerFundAmountLabel,
              conversionLabel: typed > BigInt.zero && usdPerBtc > 0
                  ? ledgerFormatUsd(usd)
                  : null,
              availableLabel: availableSats > 0
                  ? l10n.ledgerAvailableAmount(
                      '${formatSatsAsBtc(availableSats)} BTC')
                  : null,
              availableExceeded:
                  availableSats > 0 && typed > BigInt.from(availableSats),
            );
          },
        ),
        SizedBox(height: 16.h),
        LedgerFundingIntroLine(text: l10n.ledgerPmFundIntroLine),
        LedgerFundingHowThisWorks(lines: [
          l10n.ledgerPmFundSheetConfirmations,
          l10n.ledgerPmFundSheetGasPlain,
          l10n.ledgerPmFundSheetUnavailable,
          if (deployConfirmed) l10n.ledgerPmFundSheetDeploy,
        ]),
      ],
    );
  }
}

class _PmFundReview extends StatelessWidget {
  const _PmFundReview({
    required this.quote,
    required this.wallet,
    this.refreshNote,
  });

  final LedgerPmForwardQuote quote;
  final WalletConfig? wallet;

  /// Why the price on screen is new, or null for a first review.
  final String? refreshNote;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final verified = quote.quote;
    final secondsLeft =
        verified.expiresAt.difference(DateTime.now()).inSeconds.clamp(0, 999);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _pmEndpoints(context, wallet),
        SizedBox(height: 16.h),
        if (refreshNote != null) ...[
          LedgerFundingMessageCard(message: refreshNote!),
          SizedBox(height: 12.h),
        ],
        LedgerFundingFeesRow(
          quote: verified.quote,
          amountSats: quote.amountSats.toDouble(),
        ),
        LedgerFundingRow(
          label: l10n.ledgerFundReviewExpires,
          value: l10n.ledgerFundReviewSecondsLeft(secondsLeft),
        ),
        LedgerFundingAdvancedRows(rows: {
          l10n.ledgerPmFundReviewAccount: quote.recipient.address,
          l10n.ledgerFundReviewRefund: quote.refund.address,
          l10n.ledgerFundReviewProvider: 'Orchestra',
        }),
        SizedBox(height: 8.h),
        LedgerNote(text: l10n.ledgerFundReviewDeviceNote),
        LedgerNote(text: l10n.ledgerPmFundReviewNextStep),
      ],
    );
  }
}
