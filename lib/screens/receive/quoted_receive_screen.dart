import 'dart:async';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:share_plus/share_plus.dart';

import 'package:kute/helpers/scanned_address.dart';
import 'package:kute/helpers/user_error_copy.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/spark_address_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/screens/receive/orchestra_deposit_poller.dart';
import 'package:kute/screens/shared/kute_paste_chip.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/screens/shared/qr_code.dart';
import 'package:kute/screens/shared/receive_surface.dart';
import 'package:kute/screens/shared/stepper/stepper_widgets.dart';
import 'package:kute/screens/usd/flow/usd_flow_widgets.dart';
import 'package:kute/services/orchestra/orchestra_capability_requirements.dart'
    show kOneTimeAddressCapability;
import 'package:kute/services/orchestra/orchestra_quote_gate.dart';
import 'package:kute/services/orchestra/orchestra_quote_guard.dart';
import 'package:kute/services/orchestra/pending_receive_quote_cache.dart';
import 'package:kute/services/orchestra_routes.dart';
import 'package:kute/services/orchestra_usd_send_routes.dart'
    show usdBaseUnitsFromTyped;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/security/address_guard.dart';
import 'package:kute/services/security/wallet_guard_exception.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

enum _ReceiveStep { amount, refund, address }

/// Prepares a single external deposit into this wallet's Bitcoin or Dollars.
/// This screen never signs, submits or pays a transaction.
class QuotedReceiveScreen extends ConsumerStatefulWidget {
  const QuotedReceiveScreen({
    super.key,
    required this.option,
    required this.destinationAsset,
  });

  final OrchestraReceiveOption option;
  final String destinationAsset;

  @override
  ConsumerState<QuotedReceiveScreen> createState() =>
      _QuotedReceiveScreenState();
}

class _QuotedReceiveScreenState extends ConsumerState<QuotedReceiveScreen> {
  final _refund = TextEditingController();
  late final OrchestraDepositPoller _poller = OrchestraDepositPoller(ref);
  late final String? _walletId;
  late final PendingReceiveQuoteScope? _receiveScope;
  _ReceiveStep _step = _ReceiveStep.amount;
  String _typed = '';
  String? _error;
  bool _busy = false;
  bool _walletChanged = false;
  int _generation = 0;
  Timer? _ticker;
  final _paymentClock = Stopwatch();
  Duration _paymentLifetime = Duration.zero;
  bool _paymentExpired = false;
  bool Function()? _sameSdk;
  VerifiedOrchestraQuote? _verified;
  SwapOrder? _display;
  String? _expectedOutput;

  /// Destination rail label for analytics (`spark_btc` | `spark_usd`).
  String get _destinationLabel =>
      widget.destinationAsset == 'USDB' ? 'spark_usd' : 'spark_btc';

  bool get _supported =>
      (widget.destinationAsset == 'BTC' || widget.destinationAsset == 'USDB') &&
      orchestraCanQuoteReceiveOn(widget.option.chain) &&
      widget.option.decimals >= 0 &&
      widget.option.decimals <= 18;

  bool get _sameWallet {
    final settings = ref.read(settingsProvider);
    return !_walletChanged &&
        _walletId != null &&
        _receiveScope != null &&
        PendingReceiveQuoteCache.isCurrent(_receiveScope) &&
        settings.activeWalletId == _walletId &&
        pickSpendingWallet(settings)?.id == _walletId;
  }

  BigInt? get _amount => _supported
      ? usdBaseUnitsFromTyped(_typed, decimals: widget.option.decimals)
      : null;

  bool get _amountValid => (_amount ?? BigInt.zero) > BigInt.zero;

  bool get _refundValid =>
      formatMatchesChain(widget.option.chain, _refund.text.trim(),
          mainnet: true) ==
      AddressFormatMatch.ok;

  bool _current(int generation) =>
      mounted && generation == _generation && _sameWallet;

  // Stop displaying payment instructions before the guard's expiry margin.
  // The record remains monitored after this deadline, including late deposits.
  DateTime? get _payBefore =>
      _verified?.expiresAt.subtract(_verified!.expiryMargin);

  Duration get _remaining {
    final wall = _payBefore?.difference(DateTime.now()) ?? Duration.zero;
    final elapsed = _paymentLifetime - _paymentClock.elapsed;
    return wall < elapsed ? wall : elapsed;
  }

  bool get _canPay =>
      _sameWallet &&
      (_sameSdk?.call() ?? false) &&
      _display?.id == _verified?.quoteId &&
      _display?.status == 'wait' &&
      !_paymentExpired &&
      _remaining > Duration.zero;

  bool get _canRequestNewQuote {
    final display = _display;
    if (_canPay || display == null || _verified == null) return false;
    if (display.id != _verified!.quoteId) {
      return orchestraExchangeStatusIsTerminal(display.status);
    }
    return _paymentExpired || _remaining <= Duration.zero;
  }

  @override
  void initState() {
    super.initState();
    _walletId = ref.read(settingsProvider).activeWalletId;
    _receiveScope =
        _walletId == null ? null : PendingReceiveQuoteCache.capture(_walletId);
    // initState runs once per mounted screen, so rebuilds never refire.
    TrackingService.moneyFlowStarted(
      'quoted_receive',
      event: 'quoted_receive_opened',
      entrySource: TrackingService.takeEntrySource('quoted_receive',
          fallback: _destinationLabel == 'spark_usd' ? 'usd_receive' : 'receive'),
      network: widget.option.chain,
      props: {
        'asset': widget.option.assetCode,
        'network': widget.option.chain,
        'destination': _destinationLabel,
      },
    );
  }

  bool _terminalTracked = false;

  /// Funnel props: the route and the typed amount (native units).
  Map<String, Object> _flowInputs() {
    final amount = _amount;
    final typed = double.tryParse(_typed);
    return {
      'destination': _destinationLabel,
      'refund_entered': _refund.text.trim().isNotEmpty,
      ...TrackingService.routeParams(
        fromAsset: widget.option.assetCode,
        fromNetwork: widget.option.chain,
        toAsset: widget.destinationAsset == 'USDB' ? 'usd' : 'btc',
        toNetwork: 'spark',
        provider: 'orchestra',
      ),
      if (amount != null && amount > BigInt.zero && typed != null)
        ...TrackingService.moneyParams(
            amount: typed, asset: widget.option.assetCode),
    };
  }

  void _trackTerminal(SwapOrder order) {
    if (_terminalTracked || !orchestraExchangeStatusIsTerminal(order.status)) {
      return;
    }
    _terminalTracked = true;
    final ok = order.status == 'success';
    TrackingService.track(
        ok ? 'quoted_receive_completed' : 'quoted_receive_failed', params: {
      ..._flowInputs(),
      'status': order.status,
      if (!ok) 'error_category': 'settlement',
      if (!ok) 'stage': 'settle',
    });
    TrackingService.moneyFlowFinished('quoted_receive');
  }

  @override
  void dispose() {
    TrackingService.moneyFlowAbandoned('quoted_receive', props: {
      ..._flowInputs(),
      if (_verified != null) 'address_shown': true,
    });
    _generation++;
    _ticker?.cancel();
    _paymentClock.stop();
    _poller.cancel();
    _refund.dispose();
    super.dispose();
  }

  void _invalidateWallet() {
    if (!mounted || _walletChanged) return;
    _generation++;
    _ticker?.cancel();
    _poller.cancel();
    setState(() {
      _walletChanged = true;
      _busy = false;
      _verified = null;
      _display = null;
      _expectedOutput = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      settingsProvider.select(
        (s) => (s.activeWalletId, pickSpendingWallet(s)?.id),
      ),
      (previous, next) {
        if (!_sameWallet) _invalidateWallet();
      },
    );
    ref.listen(breezSDKProvider, (previous, next) {
      if (_sameSdk != null && !_sameSdk!()) _invalidateWallet();
    });
    final l10n = context.l10n;
    // A clock correction must not revive instructions already shown expired.
    if (_verified != null && _remaining <= Duration.zero) {
      _paymentExpired = true;
    }
    final blocked = !_supported || !_sameWallet;
    final index = _step.index;
    return PopScope(
      canPop: index == 0 || blocked,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: UsdFlowScaffold(
        title: widget.destinationAsset == 'USDB'
            ? l10n.usdReceiveTitle
            : l10n.receiveBitcoin,
        totalSteps: 3,
        currentStep: index,
        completedSteps: {for (var i = 0; i < index; i++) i},
        onBack: _onBack,
        resizeToAvoidBottomInset: _step == _ReceiveStep.refund,
        action: blocked ? null : _buildAction(),
        child: blocked
            ? Padding(
                padding: EdgeInsets.only(top: 24.h),
                child: UsdFlowNote(lines: [
                  _walletChanged
                      ? l10n.quotedReceiveWalletChanged
                      : !_supported
                          ? l10n.receiveCoinNetworkUnavailable
                          : l10n.receiveOtherCoinsSpendingOnly,
                ]),
              )
            : StepPageWrapper(
                title: switch (_step) {
                  _ReceiveStep.amount => l10n.receiveOneOffAmountTitle,
                  _ReceiveStep.refund => l10n.ledgerFundReviewRefund,
                  _ReceiveStep.address => l10n.usdReceiveShareStep,
                },
                subtitle: switch (_step) {
                  _ReceiveStep.amount => l10n.quotedReceiveAmountSubtitle(
                      widget.option.displaySymbol,
                      widget.option.chainDisplayName,
                    ),
                  _ReceiveStep.refund => l10n.quotedReceiveRefundSubtitle(
                      widget.option.chainDisplayName,
                    ),
                  _ReceiveStep.address => _canPay
                      ? l10n.usdReceiveShareSubtitle(
                          widget.option.displaySymbol,
                          widget.option.chainDisplayName,
                        )
                      : '',
                },
                colors: context.colors,
                child: switch (_step) {
                  _ReceiveStep.amount => UsdAmountStepBody(
                      typed: _typed,
                      suffix: widget.option.displaySymbol,
                      maxDecimals: widget.option.decimals,
                      onChanged: (value) => setState(() => _typed = value),
                    ),
                  _ReceiveStep.refund => _buildRefund(),
                  _ReceiveStep.address => _buildAddress(),
                },
              ),
      ),
    );
  }

  Widget? _buildAction() {
    final l10n = context.l10n;
    return switch (_step) {
      _ReceiveStep.amount => UsdFlowAction(
          label: l10n.continueLabel,
          onPressed: _amountValid
              ? () => setState(() => _step = _ReceiveStep.refund)
              : null,
        ),
      _ReceiveStep.refund => UsdFlowAction(
          label: l10n.continueLabel,
          loading: _busy,
          onPressed: !_busy && _amountValid && _refundValid
              ? () => unawaited(_createQuote())
              : null,
        ),
      _ReceiveStep.address => _canRequestNewQuote
          ? UsdFlowAction(
              label: l10n.receiveOneOffNewAddress,
              onPressed: _startNewQuote,
            )
          : null,
    };
  }

  Widget _buildRefund() {
    final c = context.colors;
    final l10n = context.l10n;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UsdReviewPlate(children: [
            UsdReviewLine(label: l10n.youSend, value: _sourceAmount),
            UsdReviewLine(
              label: l10n.network,
              value: widget.option.chainDisplayName,
            ),
          ]),
          SizedBox(height: 16.h),
          TextField(
            controller: _refund,
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            minLines: 1,
            maxLines: 3,
            maxLength: 256,
            onChanged: (_) => setState(() => _error = null),
            style: TextStyle(
                color: c.textPrimary,
                fontSize: 15.sp,
                fontWeight: FontWeight.w600),
            cursorColor: c.accent,
            decoration: InputDecoration(
              counterText: '',
              hintText: l10n.enterRefundAddress,
              filled: true,
              fillColor: c.surfaceLight,
              hintStyle: TextStyle(
                  color: c.textTertiary,
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w500),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: BorderSide(color: c.borderSubtle, width: 0.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: BorderSide(color: c.accent, width: 1.5),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: BorderSide(color: c.borderSubtle, width: 0.5),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: BorderSide(color: c.error),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: BorderSide(color: c.error, width: 1.5),
              ),
              errorText: _refund.text.trim().isNotEmpty && !_refundValid
                  ? l10n.quotedReceiveRefundInvalid(
                      widget.option.chainDisplayName)
                  : null,
            ),
          ),
          SizedBox(height: 12.h),
          if (!_busy)
            Row(
              children: [
                KutePasteChip(onPressed: () => unawaited(_pasteRefund())),
                SizedBox(width: 8.w),
                KuteScanChip(onPressed: () => unawaited(_scanRefund())),
              ],
            ),
          if (_error != null) ...[
            SizedBox(height: ReceiveGaps.block),
            UsdFlowNote(lines: [_error!]),
          ],
          if (const {'ton', 'xrp'}.contains(widget.option.chain))
            UsdFlowNote(lines: [context.l10n.receiveOwnRefundAddress]),
        ],
      ),
    );
  }

  String get _sourceAmount =>
      '${_decimalAmount(_verified?.amountIn ?? _amount ?? BigInt.zero, widget.option.decimals)} '
      '${widget.option.displaySymbol}';

  Widget _buildAddress() {
    final l10n = context.l10n;
    final display = _display!;
    final payable = _canPay;
    final arrived = display.id != _verified!.quoteId;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (payable) ...[
            if ((display.depositMemo ?? '').isEmpty)
              ReceiveQrPlate(
                  child: buildQrCode(display.depositAddress, context)),
            SizedBox(height: ReceiveGaps.qrToCaption),
            ReceiveCaption(text: l10n.quotedReceiveExactAmount(_sourceAmount)),
            SizedBox(height: ReceiveGaps.qrToAddress),
            ReceiveAddressLine(
              address: display.depositAddress,
              onCopy: () => unawaited(_copyAddress()),
            ),
            if ((display.depositMemo ?? '').isNotEmpty) ...[
              SizedBox(height: ReceiveGaps.block),
              Text(l10n.receiveRequiredMemo,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              ReceiveAddressLine(
                  address: display.depositMemo!,
                  onCopy: () async {
                    if (_canPay) {
                      await Clipboard.setData(
                          ClipboardData(text: display.depositMemo!));
                    }
                  }),
              UsdFlowNote(lines: [l10n.receiveMemoRequiredWarning]),
            ],
            SizedBox(height: ReceiveGaps.addressToActions),
          ] else
            UsdFlowNote(lines: [
              arrived
                  ? _statusLabel(display.status)
                  : l10n.quotedReceiveExpired,
            ]),
          ReceiveActionPills(
            onCopy: payable ? () => unawaited(_copyAddress()) : null,
            onShare: payable ? () => unawaited(_shareAddress()) : null,
          ),
          SizedBox(height: ReceiveGaps.block),
          UsdReviewPlate(children: [
            UsdReviewLine(
              label: l10n.youSend,
              value: _sourceAmount,
              emphasised: true,
            ),
            UsdReviewLine(
                label: l10n.network, value: widget.option.chainDisplayName),
            UsdReviewLine(
              label: l10n.ledgerFundReviewRefund,
              value: _verified!.request.refundAddress,
              monospace: true,
            ),
            UsdReviewLine(
                label: l10n.status, value: _statusLabel(display.status)),
          ]),
          SizedBox(height: ReceiveGaps.block),
          UsdFlowNote(
            lines: [
              if (_expectedOutput != null)
                l10n.quotedReceiveExpectedOutput(_expectedOutput!),
              l10n.quotedReceiveRefundSubtitle(widget.option.chainDisplayName),
            ],
            emphasis: payable
                ? l10n.receiveOneOffExpiresIn(
                    usdFormatCountdown(_remaining),
                  )
                : null,
          ),
          SizedBox(height: ReceiveGaps.tail),
        ],
      ),
    );
  }

  String _statusLabel(String status) => switch (status) {
        'success' || 'settled' => context.l10n.completed,
        'refunded' => context.l10n.refunded,
        'failed' || 'overdue' => context.l10n.activityNeedsAttention,
        'expired' => context.l10n.expired,
        'confirmation' || 'exchanging' || 'sending' => context.l10n.processing,
        _ => _canPay ? context.l10n.waitingForDeposit : context.l10n.pending,
      };

  Future<void> _createQuote() async {
    final amount = _amount;
    if (_busy ||
        !_sameWallet ||
        !_supported ||
        !_refundValid ||
        amount == null ||
        amount <= BigInt.zero) {
      return;
    }
    final generation = ++_generation;
    final refund = _refund.text.trim();
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // The operator switch for one-time receive addresses, re-read from
      // a fresh policy before any address is minted. Fails closed.
      await RuntimeCapabilitiesService.instance
          .ensureAllAllowed(const [kOneTimeAddressCapability]);
      if (!_current(generation)) return;
      await ref
          .read(orchestraSupportedRoutesProvider.notifier)
          .refreshIfOlderThan(kMoneyCatalogMaxAge);
      if (!_current(generation)) return;
      final destinationDecimals = widget.destinationAsset == 'BTC' ? 8 : 6;
      _requireLiveRoute();
      final wrapper = await ref.read(breezSDKProvider.future);
      if (!_current(generation)) return;
      final sdk = wrapper.instance;
      if (sdk == null) {
        throw const WalletGuardException(
            WalletGuardReason.ownAddressUnavailable);
      }
      bool sameSdk() =>
          identical(wrapper.instance, sdk) &&
          identical(ref.read(breezSDKProvider).asData?.value.instance, sdk);
      _sameSdk = sameSdk;
      final receive = await sdk.receivePayment(
        request: const ReceivePaymentRequest(
          paymentMethod: ReceivePaymentMethod.sparkAddress(),
        ),
      );
      // The guard's own-recipient check needs an independent source.
      final ownSpark = await ref.read(sparkSelfAddressProvider.future);
      if (!_current(generation) || !sameSdk()) return;
      _requireLiveRoute();
      final request = OrchestraQuoteRequest(
        sourceChain: widget.option.chain,
        sourceAsset: widget.option.assetCode,
        destinationChain: 'spark',
        destinationAsset: widget.destinationAsset,
        amountBaseUnits: amount,
        recipientAddress: receive.paymentRequest,
        refundAddress: refund,
        recipientKind: RecipientKind.ownSpark,
        ownAddress: ownSpark,
        deliveryMode: 'variable',
        externalDepositMemo: true,
      );
      final verified = await OrchestraQuoteGate.fetchVerified(
        request,
        OrchestraQuoteBounds.forSource(widget.option.chain,
            inputValueInOutputUnits: null),
        flow: 'quoted_receive',
      );
      if (!_current(generation) || !sameSdk()) return;
      final rawOutput = verified.quote.estimatedOut;
      final output = RegExp(r'^\d+$').hasMatch(rawOutput)
          ? BigInt.tryParse(rawOutput)
          : null;
      if (output == null || output <= BigInt.zero) {
        throw const WalletGuardException(WalletGuardReason.echoMismatch);
      }
      final display = SwapOrder(
        activityDirection: 'receive',
        id: verified.quoteId,
        coinFrom: widget.option.assetCode,
        networkFrom: widget.option.chain,
        coinTo: widget.destinationAsset,
        networkTo: 'SPARK',
        depositAddress: verified.depositAddress,
        depositExtraId: verified.quote.depositMemo,
        depositAmount: _decimalAmount(amount, widget.option.decimals),
        withdrawalAmount: _decimalAmount(output, destinationDecimals),
        status: 'wait',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        withdrawalAddress: request.recipientAddress,
        depositMin: '0',
        depositMax: '0',
        rate: '0',
        refundAddress: refund,
        provider: 'Orchestra',
        walletId: _walletId,
        expiresAt: verified.expiresAt.millisecondsSinceEpoch,
        purchaseSource: 'crypto_receive',
      );
      // Persist the real quote before exposing its deposit address. The
      // background monitor discovers an actual order even after we close.
      await PendingReceiveQuoteCache.save(
        display: display,
        expiresAt: verified.expiresAt,
        scope: _receiveScope!,
      );
      if (!_current(generation) || !sameSdk()) return;
      _requireLiveRoute();
      OrchestraQuoteGate.ensurePayable(verified,
          amountBaseUnits: amount, now: DateTime.now());
      _paymentLifetime = verified.expiresAt
          .subtract(verified.expiryMargin)
          .difference(DateTime.now());
      _paymentClock
        ..reset()
        ..start();
      _paymentExpired = false;
      setState(() {
        _verified = verified;
        _display = display;
        _expectedOutput = '${display.withdrawalAmount} '
            '${widget.destinationAsset == 'USDB' ? 'USD' : 'BTC'}';
        _step = _ReceiveStep.address;
      });
      // One-time quoted deposit address: never reused. `quote_id` is
      // hashed by `track()`; the address itself never leaves the device.
      TrackingService.track('receive_address_generated', params: {
        'asset': widget.option.assetCode,
        'network': widget.option.chain,
        'provider': 'orchestra',
        'reused': false,
        'destination': _destinationLabel,
        'address_kind': 'one_time',
        'quote_id': verified.quoteId,
      });
      TrackingService.moneyFlowSubmitted('quoted_receive', props: {
        ..._flowInputs(),
        'quote_id': verified.quoteId,
      });
      _poller.start(
        display,
        stillWanted: () => _current(generation) && sameSdk(),
        onProgress: (order) {
          if (_current(generation) && sameSdk()) {
            setState(() => _display = order);
            _trackTerminal(order);
          }
        },
      );
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!_current(generation) || !sameSdk()) {
          _invalidateWallet();
          return;
        }
        setState(() {});
      });
    } catch (error) {
      if (!mounted || !_current(generation)) return;
      TrackingService.track('receive_address_failed', params: {
        'asset': widget.option.assetCode,
        'network': widget.option.chain,
        'provider': 'orchestra',
        'destination': _destinationLabel,
        'address_kind': 'one_time',
        'error_category': TrackingService.errorCategory(error),
      });
      TrackingService.moneyFlowError('quoted_receive', error);
      final l10n = context.l10n;
      setState(() {
        _error = switch (error) {
          WalletGuardException e => e.messageFor(l10n),
          OrchestraQuoteFailure e when e.routeError != null =>
            e.routeError!.messageFor(l10n),
          _ => railSafeErrorCopy(context, error,
              fallback: l10n.receiveDepositAddressFailed),
        };
      });
    } finally {
      if (mounted && !_sameWallet) {
        _invalidateWallet();
      } else if (_current(generation)) {
        setState(() => _busy = false);
      }
    }
  }

  void _requireLiveRoute() {
    final catalog = ref.read(orchestraSupportedRoutesProvider);
    final route = RouteKey(
      fromChain: widget.option.chain,
      fromAsset: widget.option.assetCode,
      toChain: 'spark',
      toAsset: widget.destinationAsset,
    );
    if (!catalog
            .availability(route,
                req: RouteRequirement.live, now: DateTime.now())
            .isAvailable ||
        catalog.find(route.fromChain, route.fromAsset)?.decimals !=
            widget.option.decimals ||
        catalog.find(route.toChain, route.toAsset)?.decimals !=
            (widget.destinationAsset == 'BTC' ? 8 : 6)) {
      throw const WalletGuardException(WalletGuardReason.decimalsMismatch);
    }
  }

  Future<void> _pasteRefund() async {
    final generation = _generation;
    final value = await Clipboard.getData(Clipboard.kTextPlain);
    if (!_current(generation) || _busy || _step != _ReceiveStep.refund) return;
    final text = value?.text?.trim();
    if (text == null) return;
    _fillRefund(text);
  }

  /// The shared smart scanner in return-value mode, the same one the
  /// bitcoin send's Scan opens.
  Future<void> _scanRefund() async {
    final generation = _generation;
    final scanned = await scanRecipientRaw(context);
    if (scanned == null) return;
    if (!_current(generation) || _busy || _step != _ReceiveStep.refund) return;
    _fillRefund(scanned);
  }

  /// Paste and Scan share this: a payment URI is reduced to its bare
  /// address and [_refundValid] then checks it against the chain, so a
  /// code for another network shows the same refusal a paste would.
  void _fillRefund(String raw) {
    final text = bareRecipientAddress(raw);
    if (text.isEmpty || text.length > 256) return;
    setState(() {
      _refund.text = text;
      _error = null;
    });
  }

  Future<void> _copyAddress() async {
    if (!_canPay) return;
    TrackingService.track('receive_qr_shared', params: {
      'method': 'copy',
      'invoice_type': 'quoted_deposit_address',
      'network': widget.option.chain,
    });
    final generation = _generation;
    await Clipboard.setData(ClipboardData(text: _verified!.depositAddress));
    if (!mounted || !_current(generation) || !_canPay) return;
    showMessageSnackBar(
        context: context, message: context.l10n.copied, error: false);
  }

  Future<void> _shareAddress() async {
    if (!_canPay) return;
    TrackingService.track('receive_qr_shared', params: {
      'method': 'share',
      'invoice_type': 'quoted_deposit_address',
      'network': widget.option.chain,
    });
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(ShareParams(
      text: (_verified!.quote.depositMemo ?? '').isEmpty
          ? _verified!.depositAddress
          : '${_verified!.depositAddress}\n${context.l10n.receiveRequiredMemo}: ${_verified!.quote.depositMemo}',
      sharePositionOrigin:
          box == null ? Rect.zero : box.localToGlobal(Offset.zero) & box.size,
    ));
  }

  void _clearQuote() {
    _generation++;
    _ticker?.cancel();
    _paymentClock.stop();
    _paymentLifetime = Duration.zero;
    _paymentExpired = false;
    _poller.cancel();
    _verified = null;
    _display = null;
    _expectedOutput = null;
    _sameSdk = null;
    _busy = false;
    _error = null;
  }

  void _startNewQuote() {
    TrackingService.track('quoted_receive_new_quote_tapped',
        params: {'network': widget.option.chain});
    _clearQuote();
    setState(() => _step = _ReceiveStep.amount);
  }

  void _onBack() {
    if (_step == _ReceiveStep.amount || !_sameWallet || !_supported) {
      unawaited(Navigator.of(context).maybePop());
      return;
    }
    final previous = _step == _ReceiveStep.address
        ? _ReceiveStep.refund
        : _ReceiveStep.amount;
    _clearQuote();
    setState(() => _step = previous);
  }
}

String _decimalAmount(BigInt units, int decimals) {
  final digits = units.toString().padLeft(decimals + 1, '0');
  if (decimals == 0) return digits;
  final split = digits.length - decimals;
  final fraction = digits.substring(split).replaceFirst(RegExp(r'0+$'), '');
  return fraction.isEmpty
      ? digits.substring(0, split)
      : '${digits.substring(0, split)}.$fraction';
}
