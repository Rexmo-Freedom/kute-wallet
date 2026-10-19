// The one-time receive of another coin from another network
// (onetime_receive.dart): after the coin and network are picked, the
// amount is asked in the Lightning receive's own "Request amount" sheet
// ([requestOneTimeReceiveAmount]: dollars for the Dollars receive, sats or
// fiat for Bitcoin, with the route's minimum on the sheet's minimum line),
// and this screen quotes it and shows the one-time deposit address: the
// code, the exact amount to send, the network it must come from, the
// expiry countdown and what arrives. The quote is an Activity row from the
// moment it exists. This screen never signs, submits or pays anything.

import 'dart:async';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:share_plus/share_plus.dart';

import 'package:kute/helpers/formatters/currency_formatter.dart';
import 'package:kute/helpers/user_error_copy.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/orchestra_route_limits.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart'
    show hyperliquidAddressProvider;
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/spark_address_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/transactions_provider.dart'
    show walletTransactionCacheProvider;
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/screens/receive/components/request_amount_sheet.dart';
import 'package:kute/screens/receive/orchestra_deposit_poller.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/screens/shared/qr_code.dart';
import 'package:kute/screens/shared/receive_surface.dart';
import 'package:kute/screens/shared/stepper/stepper_widgets.dart';
import 'package:kute/screens/usd/flow/usd_flow_widgets.dart';
import 'package:kute/services/orchestra/onetime_receive.dart';
import 'package:kute/services/orchestra/orchestra_capability_requirements.dart'
    show orchestraOptionCapabilities;
import 'package:kute/services/orchestra/orchestra_quote_gate.dart';
import 'package:kute/services/orchestra/orchestra_quote_guard.dart';
import 'package:kute/services/orchestra/pending_receive_quote_cache.dart';
import 'package:kute/services/orchestra/receive_minimums.dart';
import 'package:kute/services/orchestra/standing_deposit_sweep.dart'
    show ReceiveAddressWatch;
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode, orchestraExchangeStatusIsTerminal;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/security/wallet_guard_exception.dart';
import 'package:kute/services/success_feedback.dart' show moneyFailureFeedback;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// What the person asked to receive: the amount in USD cents, the
/// minimum the sheet showed, and the unit it was typed in.
typedef OneTimeReceiveAmount = ({
  int usdCents,
  ReceiveMinimum minimum,
  String unit,
});

/// The route of a one-time receive of [option] into spark:[destinationAsset].
RouteKey oneTimeReceiveRoute(
        OrchestraReceiveOption option, String destinationAsset) =>
    RouteKey(
        fromChain: option.chain,
        fromAsset: option.assetCode,
        toChain: 'spark',
        toAsset: destinationAsset);

/// "$1.50" for 150.
String usdCentsText(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';

/// [requested] in whole USD cents: as typed when in dollars, else its
/// sats at the local bitcoin price. Null without a price.
int? oneTimeReceiveUsdCents(WidgetRef ref, RequestedAmount requested) {
  if (requested.currency == 'USD') {
    final usd = double.tryParse(requested.amount);
    return usd == null || !usd.isFinite ? null : (usd * 100).round();
  }
  final sats = ref.read(inputToSatsProvider(
      (amount: requested.amount, currency: requested.currency)));
  final usdPerBtc = ref.read(selectedCurrencyProvider('USD')).toDouble();
  if (sats <= 0 || !usdPerBtc.isFinite || usdPerBtc <= 0) return null;
  return (sats * usdPerBtc / 1e6).round();
}

/// Asks the amount of a one-time receive of [option] into
/// spark:[destinationAsset] in the "Request amount" sheet the Lightning
/// receive uses: in dollars (fixed) for the Dollars receive, in the
/// person's receive unit (sats or fiat) for Bitcoin. The route's live
/// minimum (never under the $1 floor) is on the sheet's minimum line, and
/// an amount under it or over the route's maximum turns that line red and
/// keeps "Create request" off. Null when dismissed.
Future<OneTimeReceiveAmount?> requestOneTimeReceiveAmount(
  BuildContext context,
  WidgetRef ref, {
  required OrchestraReceiveOption option,
  required String destinationAsset,
}) async {
  final route = oneTimeReceiveRoute(option, destinationAsset);
  final minimums = ref.read(receiveMinimumsProvider);
  final reading = minimums.refresh(route);
  final minimum = minimums.cachedLive(route) ?? await reading;
  if (!context.mounted) return null;
  final minCents = minimum.usdCents ?? kReceiveMinimumFloorCents;
  final minText = minimum.usdText ?? usdCentsText(minCents);
  final maxCents = oneTimeMaxUsdCents(minimums.cachedLimits(route));
  final l10n = context.l10n;
  String? outside(int cents) {
    if (cents < minCents) return l10n.routeAmountTooSmall(minText);
    if (maxCents != null && cents > maxCents) {
      return l10n.routeAmountTooLarge(usdCentsText(maxCents));
    }
    return null;
  }

  final requested = await showRequestAmountSheet(
    context,
    fixedCurrency: destinationAsset == kOrchestraUsdAssetCode ? 'USD' : null,
    minimumLabel: l10n.amountMinimumInline(minText),
    validate: (r) {
      final cents = oneTimeReceiveUsdCents(ref, r);
      return cents == null ? null : outside(cents);
    },
  );
  if (requested == null || !context.mounted) return null;
  final cents = oneTimeReceiveUsdCents(ref, requested);
  if (cents == null || cents <= 0 || outside(cents) != null) return null;
  return (usdCents: cents, minimum: minimum, unit: requested.currency);
}

/// The step every one-time receive records once its amount is known.
void _trackAmountEntered(OrchestraReceiveOption option, String destinationAsset,
    OneTimeReceiveAmount amount) {
  final props = <String, Object>{
    'asset': option.assetCode,
    'chain': option.chain,
    'address_kind': 'onetime',
    'destination': oneTimeReceiveDestinationLabel(destinationAsset),
    'amount_usd': amount.usdCents / 100,
    'amount_unit': amount.unit.toLowerCase(),
    ...amount.minimum.trackingParams,
  };
  if (destinationAsset == kOrchestraUsdAssetCode) {
    TrackingService.moneyFlowStep('usd_receive', 'amount_entered',
        props: props);
  } else {
    TrackingService.moneyFlowStep('receive', 'amount_entered', props: props);
  }
}

/// The whole one-time receive after a coin is picked: the amount sheet,
/// then [QuotedReceiveScreen] with the address. Nothing opens when the
/// sheet is dismissed.
Future<void> openOneTimeReceive(
  BuildContext context,
  WidgetRef ref, {
  required OrchestraReceiveOption option,
  required String destinationAsset,
}) async {
  final amount = await requestOneTimeReceiveAmount(context, ref,
      option: option, destinationAsset: destinationAsset);
  if (amount == null || !context.mounted) return;
  _trackAmountEntered(option, destinationAsset, amount);
  await Navigator.of(context).push<void>(MaterialPageRoute(
    builder: (_) => QuotedReceiveScreen(
      option: option,
      destinationAsset: destinationAsset,
      amount: amount,
    ),
  ));
}

/// The one-time deposit address for [amount] of [option] into the wallet's
/// own Bitcoin (`BTC`) or Dollars (`USDB`).
class QuotedReceiveScreen extends ConsumerStatefulWidget {
  const QuotedReceiveScreen({
    super.key,
    required this.option,
    required this.destinationAsset,
    required this.amount,
  });

  final OrchestraReceiveOption option;
  final String destinationAsset;
  final OneTimeReceiveAmount amount;

  @override
  ConsumerState<QuotedReceiveScreen> createState() =>
      _QuotedReceiveScreenState();
}

class _QuotedReceiveScreenState extends ConsumerState<QuotedReceiveScreen> {
  late final OrchestraDepositPoller _poller = OrchestraDepositPoller(ref);
  late final String? _walletId;
  late final PendingReceiveQuoteScope? _receiveScope;
  late OneTimeReceiveAmount _amount = widget.amount;
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
  bool _terminalTracked = false;

  bool get _dollars => widget.destinationAsset == kOrchestraUsdAssetCode;

  String get _destinationLabel =>
      oneTimeReceiveDestinationLabel(widget.destinationAsset);

  bool get _supported =>
      (widget.destinationAsset == 'BTC' || _dollars) &&
      oneTimeReceiveOffered(widget.option.chain) &&
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_createQuote());
    });
  }

  /// What every event of this address says about it. Exact values only;
  /// never the address or the quote id.
  Map<String, Object> _addressProps() => {
        'asset': widget.option.assetCode,
        'network': widget.option.chain,
        'provider': 'orchestra',
        'destination': _destinationLabel,
        'address_kind': 'onetime',
        'amount_usd': _amount.usdCents / 100,
        ..._amount.minimum.trackingParams,
        if (!_dollars) 'entry_source': 'bitcoin_receive',
      };

  void _step(String step, [Map<String, Object>? props]) {
    final all = {..._addressProps(), ...?props};
    if (_dollars) {
      TrackingService.moneyFlowStep('usd_receive', step, props: all);
    } else {
      TrackingService.moneyFlowStep('receive', step, props: all);
    }
  }

  void _trackTerminal(SwapOrder order) {
    if (_terminalTracked || !orchestraExchangeStatusIsTerminal(order.status)) {
      return;
    }
    _terminalTracked = true;
    final ok = order.status == 'success';
    final props = {
      ..._addressProps(),
      'status': order.status,
      if (!ok) 'error_category': 'settlement',
      if (!ok) 'stage': 'settle',
    };
    if (_dollars) {
      TrackingService.track(ok ? 'usd_receive_completed' : 'usd_receive_failed',
          params: props);
      TrackingService.moneyFlowFinished('usd_receive');
    } else {
      _step(ok ? 'deposit_completed' : 'deposit_failed', props);
    }
  }

  @override
  void dispose() {
    _generation++;
    _ticker?.cancel();
    _paymentClock.stop();
    _poller.cancel();
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
    // The coin and the amount were the first two steps; this is the third.
    return UsdFlowScaffold(
      title: _dollars ? l10n.usdReceiveTitle : l10n.receiveBitcoin,
      totalSteps: 3,
      currentStep: 2,
      completedSteps: const {0, 1},
      onBack: () => unawaited(Navigator.of(context).maybePop()),
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
              title: l10n.usdReceiveShareStep,
              // The network warning: only this coin, only this network.
              subtitle: _canPay
                  ? l10n.usdReceiveShareSubtitle(
                      widget.option.displaySymbol,
                      widget.option.chainDisplayName,
                    )
                  : '',
              colors: context.colors,
              child: _verified == null ? _buildPending() : _buildAddress(),
            ),
    );
  }

  Widget? _buildAction() {
    final l10n = context.l10n;
    if (_verified == null && _error != null && !_busy) {
      return UsdFlowAction(
        label: l10n.tryAgain,
        onPressed: () => unawaited(_createQuote()),
      );
    }
    if (_canRequestNewQuote) {
      return UsdFlowAction(
        label: l10n.receiveOneOffNewAddress,
        onPressed: () => unawaited(_startNewQuote()),
      );
    }
    return null;
  }

  /// The finished page's own shape while the quote is asked, with the
  /// code shimmering in the plate; the reason when it could not be made.
  Widget _buildPending() {
    final l10n = context.l10n;
    final error = _error;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (error != null && !_busy)
            UsdFlowNote(lines: [error])
          else ...[
            const ReceiveQrPlate(child: ReceiveQrShimmer()),
            SizedBox(height: ReceiveGaps.qrToCaption),
            ReceiveCaption(text: l10n.usdReceiveCreating),
          ],
        ],
      ),
    );
  }

  String get _sourceAmount =>
      '${decimalAmount(_verified!.amountIn, widget.option.decimals)} '
      '${widget.option.displaySymbol}';

  /// What arrives, net of fees, as the destination balance prints it.
  String _expectedOutput(SwapOrder display) {
    if (_dollars) {
      final usd = double.tryParse(display.withdrawalAmount) ?? 0;
      return usdCentsText((usd * 100).floor());
    }
    final sats =
        ((double.tryParse(display.withdrawalAmount) ?? 0) * 1e8).round();
    final format = ref.read(settingsProvider).btcFormat;
    return '₿${sats.toFormattedString(format)}';
  }

  Widget _buildAddress() {
    final l10n = context.l10n;
    final display = _display!;
    final verified = _verified!;
    final payable = _canPay;
    final arrived = display.id != verified.quoteId;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (payable) ...[
            ReceiveQrPlate(child: buildQrCode(display.depositAddress, context)),
            SizedBox(height: ReceiveGaps.qrToCaption),
            ReceiveCaption(
              key: const ValueKey('onetime-receive-exact-amount'),
              text: l10n.quotedReceiveExactAmount(_sourceAmount),
            ),
            SizedBox(height: ReceiveGaps.qrToAddress),
            ReceiveAddressLine(
              address: display.depositAddress,
              onCopy: () => unawaited(_copyAddress()),
            ),
            SizedBox(height: ReceiveGaps.addressToActions),
          ] else
            UsdFlowNote(lines: [
              arrived
                  ? _statusLabel(display.status)
                  : l10n.quotedReceiveExpired,
            ]),
          ReceiveActionPills(
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
                label: l10n.status, value: _statusLabel(display.status)),
          ]),
          SizedBox(height: ReceiveGaps.block),
          UsdFlowNote(
            key: const ValueKey('onetime-receive-expiry'),
            lines: [l10n.quotedReceiveExpectedOutput(_expectedOutput(display))],
            emphasis: payable
                ? l10n.receiveOneOffExpiresIn(usdFormatCountdown(_remaining))
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

  /// Writes the quote's Activity row before its address is shown: the
  /// pending-quote record (watched after this screen closes, late
  /// deposits included) and the row itself, in the Bitcoin Activity for
  /// `spark:BTC` and the Investments Activity for `spark:USDB`.
  Future<void> _record(
      SwapOrder row, DateTime expiresAt, PendingReceiveQuoteScope scope) async {
    final debug = OneTimeReceive.debugRecord;
    if (debug != null) return debug(row, expiresAt, scope);
    await PendingReceiveQuoteCache.save(
        display: row, expiresAt: expiresAt, scope: scope);
    await ref.read(swapOrdersProvider.notifier).addExchange(row);
    ref.read(walletTransactionCacheProvider.notifier).mergeSwapOrder(row);
  }

  Future<void> _createQuote() async {
    final walletId = _walletId;
    final scope = _receiveScope;
    if (_busy ||
        !_sameWallet ||
        !_supported ||
        walletId == null ||
        scope == null) {
      return;
    }
    final generation = ++_generation;
    final option = widget.option;
    final destinationAsset = widget.destinationAsset;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // The switch for one-time receive addresses, crypto deposits and the
      // route's swap gates, re-read from a fresh policy before any address
      // exists. Fails closed.
      await RuntimeCapabilitiesService.instance.ensureAllAllowed(
          orchestraOptionCapabilities(option,
              otherLegAsset: destinationAsset, depositAddress: true));
      if (!_current(generation)) return;
      await ref
          .read(orchestraSupportedRoutesProvider.notifier)
          .refreshIfOlderThan(kMoneyCatalogMaxAge);
      if (!_current(generation)) return;
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
      // The refund of an EVM source: the wallet's own account-zero EVM
      // address (the Predictions EOA derivation), never one typed in.
      final ownEvm = oneTimeReceiveOwnRefund(option.chain)
          ? await ref.read(hyperliquidAddressProvider.future)
          : null;
      if (!_current(generation) || !sameSdk()) return;
      _requireLiveRoute();
      final route = oneTimeReceiveRoute(option, destinationAsset);
      final limits = ref.read(receiveMinimumsProvider).cachedLimits(route);
      final units = oneTimeSourceUnits(
        asset: option.assetCode,
        decimals: option.decimals,
        usdCents: _amount.usdCents,
        usdPerBtc: ref.read(selectedCurrencyProvider('USD')).toDouble(),
        limits: limits,
      );
      if (units == null) {
        throw const WalletGuardException(WalletGuardReason.noReferencePrice);
      }
      switch (limits?.checkBaseUnits(units)) {
        case RouteAmountCheck.belowMinimum:
          throw const OrchestraQuoteFailure('amount_too_small',
              routeError: RouteQuoteError(RouteQuoteErrorCode.amountTooSmall));
        case RouteAmountCheck.aboveMaximum:
          throw const OrchestraQuoteFailure('amount_too_large',
              routeError: RouteQuoteError(RouteQuoteErrorCode.amountTooLarge));
        default:
          break;
      }
      final request = OneTimeReceive.request(
        option: option,
        destinationAsset: destinationAsset,
        amountBaseUnits: units,
        recipient: receive.paymentRequest,
        ownSpark: ownSpark,
        ownEvm: ownEvm,
      );
      final verified = await OneTimeReceive.fetch(request);
      if (!_current(generation) || !sameSdk()) return;
      final row = OneTimeReceive.row(
        option: option,
        destinationAsset: destinationAsset,
        verified: verified,
        walletId: walletId,
        now: DateTime.now(),
      );
      // Persist the real quote before exposing its deposit address. The
      // background monitor discovers an actual order even after we close.
      await _record(row, verified.expiresAt, scope);
      if (!_current(generation) || !sameSdk()) return;
      _requireLiveRoute();
      OneTimeReceive.ensurePayable(verified, units);
      // Its deposits are read on every screen for a while.
      ReceiveAddressWatch.shown();
      _paymentLifetime = verified.expiresAt
          .subtract(verified.expiryMargin)
          .difference(DateTime.now());
      _paymentClock
        ..reset()
        ..start();
      _paymentExpired = false;
      _terminalTracked = false;
      setState(() {
        _verified = verified;
        _display = row;
      });
      // A one-time quoted deposit address, never reused. Neither the
      // address nor the quote id leaves the device.
      TrackingService.track('receive_address_generated', params: {
        ..._addressProps(),
        'reused': false,
        'quote_expiry_seconds':
            verified.expiresAt.difference(DateTime.now()).inSeconds,
        if (verified.quote.appFeeBps != null)
          'kute_fee_bps': verified.quote.appFeeBps!,
      });
      _step('deposit_address_shown');
      _poller.start(
        row,
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
        ..._addressProps(),
        'error_category': TrackingService.errorCategory(error),
      });
      if (_dollars) {
        TrackingService.moneyFlowError('usd_receive', error);
      } else {
        TrackingService.moneyFlowError('receive', error);
      }
      // The address the person asked for could not be made.
      unawaited(moneyFailureFeedback());
      final l10n = context.l10n;
      setState(() {
        _error = switch (error) {
          WalletGuardException e => e.messageFor(l10n),
          OrchestraQuoteFailure e when e.routeError != null => e.routeError!
              .messageFor(l10n,
                  minimum: _amount.minimum.usdText,
                  maximum: switch (oneTimeMaxUsdCents(ref
                      .read(receiveMinimumsProvider)
                      .cachedLimits(oneTimeReceiveRoute(
                          widget.option, widget.destinationAsset)))) {
                    final int cents => usdCentsText(cents),
                    _ => null,
                  }),
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
    final route = oneTimeReceiveRoute(widget.option, widget.destinationAsset);
    if (!catalog
            .availability(route,
                req: RouteRequirement.live, now: DateTime.now())
            .isAvailable ||
        catalog.find(route.fromChain, route.fromAsset)?.decimals !=
            widget.option.decimals ||
        catalog.find(route.toChain, route.toAsset)?.decimals !=
            OneTimeReceive.destinationDecimals(widget.destinationAsset)) {
      throw const WalletGuardException(WalletGuardReason.decimalsMismatch);
    }
  }

  Future<void> _copyAddress() async {
    if (!_canPay) return;
    if (_dollars) {
      TrackingService.track('usd_receive_address_copied',
          params: {'chain': widget.option.chain, 'address_kind': 'onetime'});
    } else {
      TrackingService.track('receive_qr_shared', params: {
        'method': 'copy',
        'invoice_type': 'quoted_deposit_address',
        'network': widget.option.chain,
      });
    }
    final generation = _generation;
    await Clipboard.setData(ClipboardData(text: _verified!.depositAddress));
    if (!mounted || !_current(generation) || !_canPay) return;
    HapticFeedback.lightImpact();
    showMessageSnackBar(
        context: context, message: context.l10n.copied, error: false);
  }

  Future<void> _shareAddress() async {
    if (!_canPay) return;
    if (_dollars) {
      TrackingService.track('usd_receive_address_shared',
          params: {'chain': widget.option.chain, 'address_kind': 'onetime'});
    } else {
      TrackingService.track('receive_qr_shared', params: {
        'method': 'share',
        'invoice_type': 'quoted_deposit_address',
        'network': widget.option.chain,
      });
    }
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(ShareParams(
      text: _verified!.depositAddress,
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
    _sameSdk = null;
    _busy = false;
    _error = null;
  }

  /// A new address for the same coin: the amount is asked again, then a
  /// new quote. The old one keeps its Activity row.
  Future<void> _startNewQuote() async {
    _step('new_address');
    final amount = await requestOneTimeReceiveAmount(context, ref,
        option: widget.option, destinationAsset: widget.destinationAsset);
    if (amount == null || !mounted || !_sameWallet) return;
    _trackAmountEntered(widget.option, widget.destinationAsset, amount);
    setState(() {
      _clearQuote();
      _amount = amount;
    });
    await _createQuote();
  }
}
