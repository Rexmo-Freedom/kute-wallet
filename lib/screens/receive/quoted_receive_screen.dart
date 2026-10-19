// The one-time receive of another coin from another network
// (onetime_receive.dart): after the coin and network are picked, the
// amount is asked in the Lightning receive's own "Request amount" sheet
// ([requestOneTimeReceiveAmount]: dollars for the Dollars receive, sats or
// fiat for Bitcoin, with the route's minimum on the sheet's minimum line),
// then the optional return address (onetime_refund_step.dart), and this
// sheet quotes it and shows the one-time deposit address: the code, the
// expiry countdown, the network it must come from, and the amount to
// send in the plate under it. Each step is a bottom sheet over the coin
// sheet, opened as the one before it closes, so closing any of them comes
// back to the coin sheet as it was. The quote is kept as a pending quote
// (watched after this sheet closes) and becomes an Activity row only once
// a deposit to it is detected. This sheet never signs, submits or pays
// anything.

import 'dart:async';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:share_plus/share_plus.dart';

import 'package:kute/helpers/user_error_copy.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/orchestra_route_limits.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/spark_address_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/screens/receive/components/request_amount_sheet.dart';
import 'package:kute/screens/receive/onetime_refund_step.dart';
import 'package:kute/screens/receive/orchestra_deposit_poller.dart';
import 'package:kute/screens/shared/account_switcher_pill.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/kute_back_button.dart' show KuteCloseButton;
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/screens/shared/qr_code.dart';
import 'package:kute/screens/shared/receive_surface.dart';
import 'package:kute/screens/shared/send/send_flow_widgets.dart'
    show sendShortAddress;
import 'package:kute/screens/usd/flow/usd_flow_widgets.dart'
    show UsdFlowAction, UsdReviewLine, UsdReviewPlate, usdFormatCountdown;
import 'package:kute/services/orchestra/onetime_receive.dart';
import 'package:kute/services/orchestra/orchestra_capability_requirements.dart'
    show orchestraOptionCapabilities, ensureOneTimeDestinationAllowed;
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

/// Starts the `/limits` read of every route in [options] into
/// spark:[destinationAsset], in the background, so the amount sheet
/// usually has the live minimum before a coin is tapped. Fire and forget.
void prefetchOneTimeReceiveMinimums(
  ReceiveMinimums minimums,
  Iterable<OrchestraReceiveOption> options, {
  required String destinationAsset,
}) {
  for (final option in options) {
    final route = oneTimeReceiveRoute(option, destinationAsset);
    if (minimums.cachedLive(route) != null) continue;
    unawaited(minimums.refresh(route));
  }
}

/// Asks the amount of a one-time receive of [option] into
/// spark:[destinationAsset] in the "Request amount" sheet the Lightning
/// receive uses: in dollars (fixed) for the Dollars receive, in the
/// person's receive unit (sats or fiat) for Bitcoin. The sheet opens at
/// once. The route's live minimum (Flashnet's own, no app floor) is on
/// its minimum line as soon as it is known (cached, or when the read
/// lands; no line before that), and an amount under it or over the
/// route's maximum turns that line red and keeps "Create request" off. A
/// tap while the read is in flight waits for it. Null when dismissed.
Future<OneTimeReceiveAmount?> requestOneTimeReceiveAmount(
  BuildContext context,
  WidgetRef ref, {
  required OrchestraReceiveOption option,
  required String destinationAsset,
}) async {
  final route = oneTimeReceiveRoute(option, destinationAsset);
  final minimums = ref.read(receiveMinimumsProvider);
  final l10n = context.l10n;
  var minimum = minimums.cachedLive(route) ?? kReceiveMinimumNone;

  String? outside(int cents) {
    final min = minimum.usdCents;
    if (min != null && cents < min) {
      return l10n.routeAmountTooSmall(minimum.usdText!);
    }
    final maxCents = oneTimeMaxUsdCents(minimums.cachedLimits(route));
    if (maxCents != null && cents > maxCents) {
      return l10n.routeAmountTooLarge(usdCentsText(maxCents));
    }
    return null;
  }

  RequestAmountLimits limitsNow() => (
        minimumLabel: minimum.usdText == null
            ? null
            : l10n.amountMinimumInline(minimum.usdText!),
        validate: (r) {
          final cents = oneTimeReceiveUsdCents(ref, r);
          return cents == null ? null : outside(cents);
        },
      );

  final limits = ValueNotifier<RequestAmountLimits>(limitsNow());
  // Re-read every time the sheet opens; never awaited before it shows.
  Future<void>? reading = minimums.refresh(route).then((read) {
    minimum = read;
    limits.value = limitsNow();
  });
  unawaited(reading.whenComplete(() => reading = null));

  final requested = await showRequestAmountSheet(
    context,
    fixedCurrency: destinationAsset == kOrchestraUsdAssetCode ? 'USD' : null,
    limits: limits,
    pending: () => reading,
  );
  if (requested == null || !context.mounted) return null;
  final cents = oneTimeReceiveUsdCents(ref, requested);
  if (cents == null || cents <= 0 || outside(cents) != null) return null;
  return (usdCents: cents, minimum: minimum, unit: requested.currency);
}

/// The step every one-time receive records once its amount is known.
void _trackAmountEntered(OrchestraReceiveOption option, String destinationAsset,
    OneTimeReceiveAmount amount, String? fallbackReason) {
  final props = <String, Object>{
    'asset': option.assetCode,
    'chain': option.chain,
    'address_kind': 'onetime',
    if (fallbackReason != null) 'fallback_reason': fallbackReason,
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
/// the return-address sheet, then [QuotedReceiveSheet] with the address,
/// each over [context]'s sheet (the coin sheet) once the one before it
/// has closed. Nothing more opens when a sheet is dismissed, and closing
/// the address sheet comes back to the coin sheet as it was.
///
/// [fallbackReason] is why the reusable (standing) address could not serve
/// this coin (`StandingFallbackReason.analytics`), carried on the steps
/// and on `receive_address_generated` as `fallback_reason`.
Future<void> openOneTimeReceive(
  BuildContext context,
  WidgetRef ref, {
  required OrchestraReceiveOption option,
  required String destinationAsset,
  String? fallbackReason,
}) async {
  final amount = await requestOneTimeReceiveAmount(context, ref,
      option: option, destinationAsset: destinationAsset);
  if (amount == null || !context.mounted) return;
  _trackAmountEntered(option, destinationAsset, amount, fallbackReason);
  final refund = await askOneTimeRefundAddress(context,
      option: option, destinationAsset: destinationAsset);
  if (refund == null || !context.mounted) return;
  await showAppBottomSheet<void>(
    context: context,
    builder: (_) => QuotedReceiveSheet(
      option: option,
      destinationAsset: destinationAsset,
      amount: amount,
      refundAddress: refund.address,
      fallbackReason: fallbackReason,
    ),
  );
}

/// The one-time deposit address for [amount] of [option] into the wallet's
/// own Bitcoin (`BTC`) or Dollars (`USDB`), in the receive sheet's frame:
/// the close X and the balance it lands in, then the code. Closing it
/// leaves the quote watched in the background (the pending-quote cache and
/// background sync), as a late deposit still lands.
class QuotedReceiveSheet extends ConsumerStatefulWidget {
  const QuotedReceiveSheet({
    super.key,
    required this.option,
    required this.destinationAsset,
    required this.amount,
    required this.refundAddress,
    this.fallbackReason,
  });

  final OrchestraReceiveOption option;
  final String destinationAsset;
  final OneTimeReceiveAmount amount;

  /// The person's own return address on the source network, or null when
  /// they skipped it (the quote then carries none).
  final String? refundAddress;

  /// Why the reusable address could not serve this coin, for analytics
  /// (`fallback_reason`); null when nothing fell back.
  final String? fallbackReason;

  @override
  ConsumerState<QuotedReceiveSheet> createState() => _QuotedReceiveSheetState();
}

class _QuotedReceiveSheetState extends ConsumerState<QuotedReceiveSheet> {
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
  // Quiet restarts of a creation the SDK was rebuilt under (a reconnect).
  int _sdkRestarts = 0;
  static const _maxSdkRestarts = 3;
  // Bumped on every change of the SDK provider (a reconnect rebuilds it).
  int _sdkEpoch = 0;
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

  // How long before the quote's expiry the address stops being shown. The
  // payer is a person with a wallet, not the app's relayer, so the window
  // runs almost to Flashnet's own expiry (2 minutes per quote); a deposit
  // that lands late is still watched and repriced by Orchestra.
  static const _displayMargin = Duration(seconds: 10);

  // Stop displaying payment instructions just before the quote expires.
  // The record remains monitored after this deadline, including late deposits.
  DateTime? get _payBefore => _verified?.expiresAt.subtract(_displayMargin);

  Duration get _remaining {
    final wall = _payBefore?.difference(DateTime.now()) ?? Duration.zero;
    final elapsed = _paymentLifetime - _paymentClock.elapsed;
    return wall < elapsed ? wall : elapsed;
  }

  // Only the wallet matters once the address is shown: the deposit pays the
  // wallet's own Spark address, which a reconnect (a rebuilt SDK) keeps.
  bool get _canPay =>
      _sameWallet &&
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
        if (widget.fallbackReason != null)
          'fallback_reason': widget.fallbackReason!,
        'refund_address_set': widget.refundAddress != null,
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
    // Read only by a quote being made; a shown address ignores it.
    ref.listen(breezSDKProvider, (previous, next) => _sdkEpoch++);
    final l10n = context.l10n;
    // A clock correction must not revive instructions already shown expired.
    if (_verified != null && _remaining <= Duration.zero) {
      _paymentExpired = true;
    }
    final blocked = !_supported || !_sameWallet;
    final action = blocked ? null : _buildAction();
    // The receive sheet's frame, as the Bitcoin receive and the reusable
    // address wear it: the close X, the balance the money lands in. No
    // step bar and no page title.
    return ReceiveSheetFrame(
      leading: KuteCloseButton(
          onPressed: () => unawaited(Navigator.of(context).maybePop())),
      title: AccountSwitcherPill(
        pickerTitle: l10n.receiveInto,
        readOnly: true,
        label: _dollars ? l10n.assetDollars : l10n.bitcoin,
      ),
      semanticTitle: _dollars ? l10n.usdReceiveTitle : l10n.receiveBitcoin,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: blocked
                  ? SingleChildScrollView(
                      child: Padding(
                        padding: EdgeInsets.only(top: 12.h),
                        child: ReceiveCaption(
                          text: _walletChanged
                              ? l10n.quotedReceiveWalletChanged
                              : !_supported
                                  ? l10n.receiveCoinNetworkUnavailable
                                  : l10n.receiveOtherCoinsSpendingOnly,
                        ),
                      ),
                    )
                  : _verified == null
                      ? _buildPending()
                      : _buildAddress(),
            ),
            if (action != null) ...[
              SizedBox(height: 12.h),
              action,
            ],
          ],
        ),
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
            Padding(
              padding: EdgeInsets.only(top: 12.h),
              child: ReceiveCaption(text: error),
            )
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
            // Captions right under the code: the countdown first (the one
            // thing that runs out), then what a late deposit means. The
            // amount is in the plate below ("You send").
            SizedBox(height: ReceiveGaps.qrToCaption),
            ReceiveCaption(
              key: const ValueKey('onetime-receive-expiry'),
              text: l10n.receiveOneOffExpiresIn(usdFormatCountdown(_remaining)),
              emphasised: true,
            ),
            SizedBox(height: 4.h),
            ReceiveCaption(
              key: const ValueKey('onetime-receive-late-deposit'),
              text: l10n.receiveOneOffLateDepositRepriced,
            ),
            SizedBox(height: ReceiveGaps.qrToAddress),
            ReceiveAddressLine(
              address: display.depositAddress,
              onCopy: () => unawaited(_copyAddress()),
            ),
            // The network warning under the address, where the Bitcoin
            // receive puts its own caption: only this coin, only this
            // network.
            SizedBox(height: 8.h),
            ReceiveCaption(
              key: const ValueKey('onetime-receive-network-warning'),
              text: l10n.usdReceiveShareSubtitle(
                  widget.option.displaySymbol, widget.option.chainDisplayName),
            ),
            SizedBox(height: ReceiveGaps.addressToActions),
          ] else ...[
            ReceiveCaption(
              key: const ValueKey('onetime-receive-state'),
              text: arrived
                  ? _statusLabel(display.status)
                  : l10n.quotedReceiveExpired,
            ),
            SizedBox(height: ReceiveGaps.addressToActions),
          ],
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
            if (widget.refundAddress case final refund?)
              UsdReviewLine(
                  label: l10n.quotedReceiveReturnsTo,
                  value: sendShortAddress(refund)),
            UsdReviewLine(
                label: l10n.status, value: _statusLabel(display.status)),
          ]),
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

  /// Persists the quote before its address is shown, as a pending quote
  /// only: the deposit poller and background sync watch it after this
  /// sheet closes (late deposits included) and write the Activity row
  /// once Orchestra reports a deposit. Nothing reaches Activity before
  /// money was sent.
  Future<void> _record(
      SwapOrder row, DateTime expiresAt, PendingReceiveQuoteScope scope) async {
    final debug = OneTimeReceive.debugRecord;
    if (debug != null) return debug(row, expiresAt, scope);
    await PendingReceiveQuoteCache.save(
        display: row, expiresAt: expiresAt, scope: scope);
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
    var restart = false;
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
      // And the destination class (Bitcoin or Dollars), refused only when
      // the policy denies it explicitly: an older backend names none.
      ensureOneTimeDestinationAllowed(
          RuntimeCapabilitiesService.instance, destinationAsset);
      if (!_current(generation)) return;
      await ref
          .read(orchestraSupportedRoutesProvider.notifier)
          .refreshIfOlderThan(kMoneyCatalogMaxAge);
      if (!_current(generation)) return;
      _requireLiveRoute();
      final wrapper = await ref.read(breezSDKProvider.future);
      if (!_current(generation)) return;
      final sdk = wrapper.instance;
      final sdkEpoch = _sdkEpoch;
      if (sdk == null) {
        throw const WalletGuardException(
            WalletGuardReason.ownAddressUnavailable);
      }
      // The recipient Spark address is read from this SDK instance, so it
      // must not be rebuilt (a reconnect: network, VPN, resume) while the
      // quote is made. When it is, creation quietly starts over on the new
      // one; never "Your account changed". A wallet switch is [_sameWallet].
      bool sdkMoved() {
        if (_sdkEpoch == sdkEpoch && identical(wrapper.instance, sdk)) {
          return false;
        }
        if (++_sdkRestarts > _maxSdkRestarts) {
          throw const WalletGuardException(
              WalletGuardReason.ownAddressUnavailable);
        }
        restart = true;
        return true;
      }

      final receive = await sdk.receivePayment(
        request: const ReceivePaymentRequest(
          paymentMethod: ReceivePaymentMethod.sparkAddress(),
        ),
      );
      // The guard's own-recipient check needs an independent source.
      final ownSpark = await ref.read(sparkSelfAddressProvider.future);
      if (!_current(generation) || sdkMoved()) return;
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
        refundAddress: widget.refundAddress,
      );
      final verified = await OneTimeReceive.fetch(request);
      if (!_current(generation) || sdkMoved()) return;
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
      // Persisted and paying the wallet's own Spark address: from here a
      // rebuilt SDK changes nothing.
      if (!_current(generation)) return;
      _requireLiveRoute();
      OneTimeReceive.ensurePayable(verified, units);
      // Its deposits are read on every screen for a while.
      ReceiveAddressWatch.shown();
      _paymentLifetime = verified.expiresAt
          .subtract(_displayMargin)
          .difference(DateTime.now());
      _paymentClock
        ..reset()
        ..start();
      _paymentExpired = false;
      _terminalTracked = false;
      _sdkRestarts = 0;
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
        stillWanted: () => _current(generation),
        onProgress: (order) {
          if (_current(generation)) {
            setState(() => _display = order);
            _trackTerminal(order);
          }
        },
      );
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!_current(generation)) {
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
          OrchestraQuoteFailure e when e.routeError != null =>
            e.routeError!.messageFor(l10n,
                minimum: ref
                        .read(receiveMinimumsProvider)
                        .cachedLive(oneTimeReceiveRoute(
                            widget.option, widget.destinationAsset))
                        ?.usdText ??
                    _amount.minimum.usdText,
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
        // `_busy` is false again before the new attempt checks it.
        if (restart) unawaited(_createQuote());
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
    _sdkRestarts = 0;
    _busy = false;
    _error = null;
  }

  /// A new address for the same coin: the amount is asked again, then a
  /// new quote. The old one stays watched for a late deposit.
  Future<void> _startNewQuote() async {
    _step('new_address');
    final amount = await requestOneTimeReceiveAmount(context, ref,
        option: widget.option, destinationAsset: widget.destinationAsset);
    if (amount == null || !mounted || !_sameWallet) return;
    _trackAmountEntered(
        widget.option, widget.destinationAsset, amount, widget.fallbackReason);
    setState(() {
      _clearQuote();
      _amount = amount;
    });
    await _createQuote();
  }
}
