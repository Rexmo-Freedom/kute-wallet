import 'package:kute/services/hyperliquid/hypercore_cash.dart'
    show hypercoreMaxOrderUsd;
import 'package:kute/screens/hyperliquid/components/hl_order_controls.dart';
import 'package:kute/screens/shared/side_tint_palette.dart';
import 'package:kute/screens/hyperliquid/components/builder_fee_consent.dart';
import 'package:kute/screens/hyperliquid/components/hl_error_copy.dart';
import 'package:kute/screens/shared/hyperliquid_fee_summary.dart';
import 'package:kute/screens/shared/kute_motion.dart';
// lib/screens/hyperliquid/components/order_slip_sheet.dart
//
// Order slip bottom sheet — a full Hyperliquid trading ticket mirroring
// HL's real order form (Cross/Isolated + leverage, Market/Limit/Pro order
// types, Scale/Stop/Take/TWAP, TIF, Reduce-Only, TP/SL attach, liquidation
// preview) while keeping the original Polymarket BetSlipSheet safety
// skeleton:
//
//   * gates FIRST in [HlOrderSlipSheet.show] (kill-switch + geoblock)
//     and AGAIN on confirm, so a slip left open can't trade through a
//     region/config change;
//   * `enableDrag: false` + PopScope(canPop: !_isPlacing) — swipe-to-
//     dismiss bypasses PopScope (the documented Flutter gap the bet
//     slip fixed), so dismissal is tap-outside only and the placing
//     lock holds;
//   * synchronous `_orderInFlight` re-entrancy guard — `_isPlacing`
//     flips only after awaited gate checks, so a double-tap during the
//     round-trip would otherwise fire two orders.
//
// The simple ticket shows the selected direction, amount, available funds,
// trading fees, leverage and margin mode. Advanced contains
// order types, leverage controls, liquidation estimates, price and size details, and
// execution options on a separate full-screen route. Both surfaces share one
// order draft; returning to the simple ticket preserves every selected setting.
// Every order still routes to the matching notifier method
// (openPosition/placeSpotOrder/placeLimit/placeTrigger/placeScale/placeTwap)
// and margin mode + leverage are applied inside those methods (isCross +
// _ensureLeverage) so the write is atomic with the order.
//
// Denomination: the user's money (margin input companion, notional preview
// and CTA amount) honours the app's Assets/Predictions denomination via
// formatPolyAmount — a sats/BTC (or non-USD fiat) companion line,
// mirroring the bet slip. Entry stays in USD; the asset PRICE (limit /
// trigger / mid) always stays in USD — it's the market price, not the stake.
//
// Risk UX carried over: spread ≥1% warning banner, ≥3% extra confirm; a mid
// that hasn't ticked for >10 s disables confirm ("refreshing price…"); the
// liquidation preview is client-estimated and labeled as an estimate.
//
// The policy helper below refreshes the relevant operation capability.
// Existing-position exits use a separate permission from new exposure.
//
// Step-up (Wallet Hardening Phase 1b.3): confirm builds the order once as a
// [_SlipOrder] (intent plus the exact notifier call) and asks for a fresh
// approval bound to that intent before the placing tile or any state
// change. The call is then rebuilt from the ticket as it is at submit, and
// the notifier consumes the grant before signing, so a leverage, side or
// amount change since the approval throws ReauthRequired and shows "Review
// again" with nothing sent.

import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/constants/feature_flags.dart';
import 'package:kute/constants/hyperliquid_constants.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart';
import 'package:kute/helpers/require_fresh_auth.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_config_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/ledger/ledger_hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_orderbook_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/hyperliquid_user_events_provider.dart';
import 'package:kute/providers/placing_hyperliquid_order_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/home/components/action_pill.dart'
    show greenColor, redColor;
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/hyperliquid/components/order_placed_overlay.dart';
import 'package:kute/screens/ledger/hyperliquid/ledger_hl_execution_target.dart'
    show
        runLedgerHlClose,
        runLedgerHlMarketOrder,
        runLedgerHlTrailingStop,
        ledgerHlReferencePx;
import 'package:kute/screens/ledger/hyperliquid/ledger_transfer_sheet.dart';
import 'package:kute/screens/ledger/ledger_action_ui.dart'
    show showLedgerConfirmation;
import 'package:kute/screens/shared/amount_keypad_panel.dart';
import 'package:kute/screens/shared/decimal_input_formatter.dart';
import 'package:kute/screens/shared/ask_sal_chip.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/sticky_action_bar.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/market_side_toggle.dart';
import 'package:kute/services/hyperliquid/hl_failure_analytics.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';
import 'package:kute/services/hyperliquid/hl_position_effect.dart';
import 'package:kute/services/hyperliquid/hyperliquid_rounding.dart';
import 'package:kute/services/hyperliquid/trailing_stop.dart';
import 'package:kute/services/hyperliquid/liquidation_estimate.dart';
import 'package:kute/services/venue_analytics.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/screens/shared/message_display.dart'
    show showMessageSnackBar;
import 'package:kute/screens/shared/slip_shortfall.dart';
import 'package:kute/services/funding/venue_shortfall.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/screens/shared/capability_block_note.dart';
import 'package:kute/screens/shared/capability_unavailable_sheet.dart';
import 'package:kute/screens/ledger/ledger_investment_gate.dart'
    show
        ledgerInvestingCapability,
        ledgerInvestmentAllowed,
        showLedgerInvestmentUnavailable;
import 'package:kute/services/investment_provider_availability.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/screens/home/components/deposit_sheet.dart';

/// Returns true after showing why the requested operation is unavailable.
/// A fresh authenticated policy is required, including for an already open slip.
Future<bool> checkHyperliquidGeoblock(BuildContext context, WidgetRef ref,
    {String capability = 'hyperliquid.trade',
    Iterable<String>? capabilities,
    Duration maxAge = Duration.zero}) async {
  late String message;
  var regionBlocked = false;
  final l10n = context.l10n;
  try {
    // At confirm the ticket re-checks what it checked when it opened; a
    // policy fetched within [maxAge] is read rather than fetched again.
    // [capabilities] names every gate a new position needs (opening
    // investments plus the stock-perp gate); [capability] alone serves
    // the exits.
    await RuntimeCapabilitiesService.instance
        .ensureAllAllowed(capabilities ?? [capability], maxAge: maxAge);
    return false;
  } on CapabilityUnavailableException catch (error) {
    message = error.decision.messageIn(l10n);
    regionBlocked = error.decision.regionRestricted;
  } on ProviderAvailabilityException catch (error) {
    message = error.availability.messageIn(l10n);
    regionBlocked =
        error.availability.status == ProviderAvailabilityStatus.restricted;
  }
  if (!context.mounted) return true;

  if (regionBlocked) TrackingService.hyperliquidGeoblockedShown();
  // The shared unavailable sheet: "Not available in your region" with the
  // network / VPN sentence for a region block, "Investing unavailable"
  // with the policy's own reason otherwise.
  unawaited(showCapabilityUnavailableSheet(
    context,
    message: message,
    regionRestricted: regionBlocked,
    title: l10n.gateInvestingUnavailable,
  ));
  return true;
}

/// Top-level order mode — the Market | Limit | Pro tab.
enum _OrderMode { market, limit, pro }

/// The concrete order type behind the Pro tab.
enum _ProType { scale, stopLimit, stopMarket, takeLimit, takeMarket, twap }

/// Every numeric input on the Advanced page. The page has no focusable
/// TextField — one keypad is pinned at the bottom and writes to whichever
/// of these is focused, so the OS keyboard can never cover the ticket.
enum _NumField {
  size,
  limitPrice,
  trigger,
  stopLimitPrice,
  scaleStart,
  scaleEnd,
  scaleCount,
  twapMinutes,
  takeProfit,
  stopLoss,
  trailDistance,
  trailActivation,
}

/// One order the slip is about to place (Wallet Hardening Phase 1b.3): the
/// intent the user approves and the notifier call with exactly those
/// arguments, built from the same local values so they cannot disagree.
class _SlipOrder {
  const _SlipOrder(this.intent, this.place);

  final SensitiveIntent intent;
  final Future<HlOrderResult> Function(AuthGrant grant) place;
}

class HlOrderSlipSheet extends ConsumerStatefulWidget {
  final HlMarket market;
  final bool initialIsLong;

  /// Analytics source ('market_detail' | 'position_card' | 'advisor').
  final String? source;

  /// Where the journey started (search | market_list | sal | portfolio …);
  /// [source] is the surface the slip opened from. Analytics only.
  final String? entrySource;

  /// Pins the ticket to a Ledger account: balances come from that account
  /// and the order is signed on the device. Null is the hot account.
  /// Mirrors BetSlipSheet's ledgerWalletId — one slip, two signers, so a
  /// Ledger user gets the same screen rather than a second product.
  final String? ledgerWalletId;

  const HlOrderSlipSheet({
    super.key,
    required this.market,
    this.initialIsLong = true,
    this.source,
    this.entrySource,
    this.ledgerWalletId,
  });

  /// Route name used to pop back down to the host after a fill — see
  /// [popAllSheetsDownToHost] (mirrors BetSlipSheet.routeName).
  static const routeName = 'hyperliquid-order-slip';

  static Future<void> show(
    BuildContext context,
    WidgetRef ref, {
    required HlMarket market,
    bool isLong = true,
    String? source,
    String? entrySource,
    String? ledgerWalletId,
  }) async {
    // The ticket always opens: markets and their tickets stay browsable,
    // and a policy that withholds new positions disables the one confirm
    // button with its reason above it (see `_resolveOpenGate`), the
    // blocked-state grammar the bet slip uses. Placement re-checks at
    // confirm (`_confirmInner`), so this grants nothing.
    //
    // A Ledger ticket that would open a position answers to Ledger
    // Investing (`ledger.hyperliquid`) first, wherever it was opened
    // from: the Ledger Investing tab, search or a market page. Exits
    // (a spot sell) never do.
    if (ledgerWalletId != null &&
        !(market.isSpot && !isLong) &&
        !ledgerInvestmentAllowed(ledgerInvestingCapability)) {
      unawaited(showLedgerInvestmentUnavailable(
          context, ledgerInvestingCapability));
      return;
    }
    if (!context.mounted) return;

    // Counted once the slip actually opens.
    VenueAnalytics.rememberHlMarkets([market]);
    TrackingService.setFlowContext(
        flow: 'hl_order',
        step: 'amount',
        venue: 'hyperliquid',
        walletKind: ledgerWalletId != null ? 'ledger' : 'hot');
    TrackingService.screenView('hyperliquid_order_slip');
    TrackingService.hyperliquidOrderSlipOpened(
      coin: market.coin,
      kind: market.isSpot ? 'spot' : 'perp',
      source: source,
      walletKind: ledgerWalletId != null ? 'ledger' : 'hot',
      extra: {
        'entry_source': entrySource ?? source ?? 'unknown',
        'side': isLong ? 'long' : 'short',
      },
    );
    if (ledgerWalletId != null) {
      TrackingService.ledgerActionSheetOpened(action: 'hl_order');
    }

    // `enableDrag: false` because swipe-to-dismiss BYPASSES PopScope
    // (long-standing Flutter gap) — that would let a user swipe the
    // sheet away mid-placement. Dismissal is via tap-outside
    // (isDismissible), which DOES go through PopScope.
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: false,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      routeSettings: const RouteSettings(name: routeName),
      builder: (_) => HlOrderSlipSheet(
        market: market,
        initialIsLong: isLong,
        source: source,
        entrySource: entrySource,
        ledgerWalletId: ledgerWalletId,
      ),
    );
  }

  /// Pop the slip plus any modal sheets / fullscreen routes stacked
  /// above the host screen — copy of
  /// BetSlipSheet.popAllSheetsDownToBetSlipHost with this routeName.
  static void popAllSheetsDownToHost(NavigatorState navigator) {
    navigator.popUntil((route) {
      if (route is ModalBottomSheetRoute) return false;
      if (route is PopupRoute) return false;
      if (route.settings.name == routeName) return false;
      if (route is PageRoute && route.fullscreenDialog) return false;
      return true;
    });
  }

  @override
  ConsumerState<HlOrderSlipSheet> createState() => _HlOrderSlipSheetState();
}

class _HlOrderSlipSheetState extends ConsumerState<HlOrderSlipSheet>
    with SlipIncomingDeposit<HlOrderSlipSheet> {
  static const _slippageOptions = [0.5, 1.0, 2.0, 5.0];
  static const _tifOptions = ['Gtc', 'Ioc', 'Alo'];

  late bool _isLong;
  double _marginUsd = 0;
  late final TextEditingController _amountController;
  int _leverage = 1;
  double _slippagePct = 1.0;

  /// The leverage and margin mode the ticket starts from (and Back from
  /// Advanced returns to): the open position's own on this market, else
  /// isolated 1x. An order on a market with an open position must never
  /// change that position's leverage or margin mode unless the person
  /// moves the slider or the mode switch themselves (the order path
  /// writes the ticket's values to the venue before the order).
  int _defaultLeverage = 1;
  bool _defaultIsCross = false;

  /// The person moved the leverage slider or the margin mode switch.
  bool _leverageTouched = false;

  /// The defaults came from an open position (once per ticket).
  bool _positionDefaultsApplied = false;

  /// The open-interest cap note was counted (once per ticket).
  bool _oiCapWarned = false;

  // ── Ticket structure ───────────────────────────────────────────────
  _OrderMode _mode = _OrderMode.market;
  _ProType _proType = _ProType.stopMarket;
  late bool _isCross;

  /// The full-screen editor shares this ticket's draft and live-price hold.
  bool _advancedRouteOpen = false;
  final _draftChanges = ValueNotifier<int>(0);

  // Advanced inputs.
  late final TextEditingController _priceController; // limit px
  late final TextEditingController _triggerController; // stop/take trigger
  late final TextEditingController _stopLimitController; // stop/take limit px
  late final TextEditingController _startPxController; // scale start
  late final TextEditingController _endPxController; // scale end
  late final TextEditingController _countController; // scale legs
  late final TextEditingController _twapMinutesController;
  late final TextEditingController _tpController; // TP attach px
  late final TextEditingController _slController; // SL attach px

  bool _reduceOnly = false;
  String _tif = 'Gtc';
  bool _postOnly = false;
  bool _randomizeTwap = false;
  bool _attachTpSl = false;

  /// Trailing stop attached to an opening market order: placed as a
  /// reduce-only order on the opposite side once the order fills, so the
  /// one button places both.
  bool _attachTrailing = false;
  bool _trailPercent = true;
  bool _trailActivate = false;
  late final TextEditingController _trailDistanceController;
  late final TextEditingController _trailActivationController;

  /// The Advanced field being edited, used for the accent border and the
  /// promoted label. It follows the real focus now rather than driving a
  /// pinned pad.
  _NumField _focusedField = _NumField.size;

  /// One focus node per Advanced field. The page used to have no focusable
  /// input at all, because a single pinned pad wrote to whichever field was
  /// last tapped. Predictions does it the other way round, with ordinary
  /// fields that raise the keyboard, and that is the one the owner prefers:
  /// the form has many numbers and a permanently pinned pad ate the room
  /// they need.
  final Map<_NumField, FocusNode> _numFocusNodes = <_NumField, FocusNode>{};

  FocusNode _focusNodeFor(_NumField field) =>
      _numFocusNodes.putIfAbsent(field, () {
        final node = FocusNode(debugLabel: 'hl-advanced-${field.name}');
        node.addListener(() {
          if (node.hasFocus && _focusedField != field) {
            _updateDraft(() => _focusedField = field);
          }
        });
        return node;
      });

  /// Advanced's rare-controls group. Null until the user touches the
  /// header, so the group opens itself when the ticket already carries a
  /// non-default option and nothing stays hidden behind a chevron.
  bool? _advancedOptionsOpen;

  bool _isPlacing = false;

  /// Tapped, and the checks that run before the order is built are
  /// still going. Separate from [_isPlacing], which means the order
  /// itself is on the wire: this covers the gap between the two, where
  /// the geo re-check and the builder fee approval live.
  bool _preparing = false;

  /// Ledger ticket only: a device flow (review, approvals, submit) is
  /// running, or the submission is waiting for confirmation. The Ledger
  /// path draws its own approval sheets, so it never swaps the ticket for
  /// the hot placing card — it only locks the one button.
  bool _ledgerBusy = false;
  bool _ledgerPending = false;

  /// The Ledger account's EVM address, read while building so the fee row
  /// quotes that account's tier instead of the hot one.
  String? _ledgerAddress;

  /// Synchronous re-entrancy guard for [_handleConfirm] — `_isPlacing`
  /// only flips AFTER the awaited geoblock re-check, so a double-tap
  /// during that round-trip would otherwise run two placements.
  bool _orderInFlight = false;

  /// From a Deposit door tap until its Move sheet closes (or the tap ends
  /// without one): further taps open nothing.
  bool _depositDoorBusy = false;

  /// From a Deposit door tap until the Move sheet opens: the top-up is
  /// being worked out. The button shows it and the form is frozen, so the
  /// sheet is sized for the order on the ticket at the tap.
  bool _depositCalculating = false;

  /// One order per slip lifetime — set once a fill/ack has routed so a
  /// racing WS fill + REST result can't push two.
  bool _completed = false;

  /// Set right before an order (hot or Ledger) is submitted; a slip
  /// disposed while this is still false was abandoned.
  bool _submitted = false;

  /// The user changed the amount from the pre-filled minimum.
  bool _amountEdited = false;

  /// Explicit extra confirm required when the spread is ≥3%.
  bool _acceptWideSpread = false;

  String? _errorText;
  Object? _errorCause;
  late AppLocalizations _strings;

  // Analytics: flow timing, where it is, why it stopped.
  final DateTime _openedAt = DateTime.now();
  String _flowStep = 'amount';
  String? _stopReason;
  String? _lastErrorCategory;
  // none (opened empty) | keypad | max | min | min_direct (the empty
  // ticket's button placed the minimum)
  String _amountMethod = 'none';

  /// The empty ticket's button wrote the minimum; the next build places
  /// it if the ticket can be confirmed at it ([_placeMinimum]).
  bool _placeMinimumOnBuild = false;
  late final String _settingsScope = 'hl_slip_${identityHashCode(this)}';

  String get _entrySource => widget.entrySource ?? widget.source ?? 'unknown';

  /// The ticket as it stands (no ref reads: used from dispose).
  Map<String, Object> _slipInputs() {
    final lev = isSpot ? 1 : _leverage;
    final trigger = _parse(_triggerController);
    final limitPx = _parse(_priceController);
    return {
      'venue': 'hyperliquid',
      'coin': market.coin,
      'kind': isSpot ? 'spot' : 'perp',
      ...VenueAnalytics.hlAssetParams(market.coin,
          kind: isSpot ? 'spot' : 'perp'),
      'entry_source': _entrySource,
      if (widget.source != null) 'source': widget.source!,
      'wallet_kind': _isLedger ? 'ledger' : 'hot',
      'funding_source': 'venue_balance',
      'side':
          isSpot ? (_isLong ? 'buy' : 'sell') : (_isLong ? 'long' : 'short'),
      ...TrackingService.moneyParams(amountUsd: _marginUsd),
      'margin_usd': (_marginUsd * 100).round() / 100,
      'notional_usd': (_marginUsd * lev * 100).round() / 100,
      'size_unit': 'usd',
      'amount_method': _amountMethod,
      'amount_edited': _amountEdited,
      'leverage': lev,
      'leverage_bucket': TrackingService.leverageBucket(lev),
      if (!isSpot) 'margin_mode': _isCross ? 'cross' : 'isolated',
      'order_type': _salOrderTypeLabel,
      'advanced_used': _usesAdvanced,
      'slippage_bps': VenueAnalytics.bps(_slippagePct),
      if (_mode == _OrderMode.limit && limitPx != null) 'limit_price': limitPx,
      if (_mode == _OrderMode.limit) 'tif': _tif.toLowerCase(),
      if (_mode == _OrderMode.limit) 'post_only': _postOnly,
      'reduce_only': _reduceOnly,
      'has_tp': _attachTpSl && _parse(_tpController) != null,
      'has_sl': _attachTpSl && _parse(_slController) != null,
      'attach_trailing': _attachTrailing,
      if (_attachTrailing) 'trail_type': _trailPercent ? 'percent' : 'price',
      if (_isTriggerType && trigger != null) 'trigger_price': trigger,
      if (_isScale) 'scale_legs': _parseInt(_countController) ?? 0,
      if (_isTwap) 'twap_minutes': _parseInt(_twapMinutesController) ?? 0,
      if (_isTwap) 'twap_randomized': _randomizeTwap,
    };
  }

  void _trackStep(String step) {
    if (_flowStep == step) return;
    _flowStep = step;
    TrackingService.setFlowStep(step);
    TrackingService.track('hl_order_step', params: {
      'step': step,
      ..._slipInputs(),
    });
  }

  /// Non-null once the open gate came back with a refusal: the reason to
  /// show above the disabled confirm, in the policy's (or the venue's)
  /// own words. Resolved behind the first frame, so the ticket paints at
  /// once and a refusal is told in place. Null means "allowed, or not
  /// answered yet": it never unlocks anything, `_confirmInner` re-checks.
  /// Only a hot ticket asks; a Ledger ticket keeps its own gates.
  String? _openGateMessage;

  /// The order on the ticket only reduces or closes, so it answers to
  /// `hyperliquid.close` and never to the open gate (the same split
  /// `_confirmInner` makes).
  bool get _isExitOrder =>
      (_mode != _OrderMode.market && _reduceOnly) || (isSpot && !_isLong);

  /// Asks whether this market may take a new position at all: the venue's
  /// own location check, then a fresh policy read.
  Future<void> _resolveOpenGate() async {
    String? message;
    var regionBlocked = false;
    try {
      await ref
          .read(runtimeCapabilitiesProvider)
          .ensureAllAllowed(hlOpenCapabilities(market));
    } on CapabilityUnavailableException catch (error) {
      message = error.decision.message;
      regionBlocked = error.decision.regionRestricted;
    } on ProviderAvailabilityException catch (error) {
      message = error.availability.message;
      regionBlocked =
          error.availability.status == ProviderAvailabilityStatus.restricted;
    } catch (_) {
      // Unanswered: confirm asks again and says why there.
    }
    if (message == null || !mounted) return;
    if (regionBlocked) TrackingService.hyperliquidGeoblockedShown();
    _updateDraft(() => _openGateMessage = message);
  }

  void _stopped(String reason, {Object? error}) {
    _stopReason = reason;
    if (error != null) {
      _lastErrorCategory = TrackingService.errorCategory(error);
    }
  }

  /// The person committed: one hyperliquid_order_submitted per order sent,
  /// and the ticket settings staged so the provider's placed / failed
  /// event carries them.
  void _trackSubmitted() {
    final inputs = _slipInputs();
    _flowStep = 'submitted';
    TrackingService.setFlowStep('submitted');
    VenueAnalytics.stage('hl', market.coin, {
      for (final k in const [
        'entry_source',
        'funding_source',
        'size_unit',
        'amount_method',
        'slippage_bps',
        'tif',
        'post_only',
        'attach_trailing',
        'trail_type',
        'advanced_used',
        'scale_legs',
        'twap_minutes',
        'twap_randomized',
      ])
        if (inputs[k] != null) k: inputs[k]!,
    });
    TrackingService.track('hyperliquid_order_submitted', params: {
      ...inputs,
      // What the order does to the position held here (perps only):
      // open | add | reduce | close | flip.
      if (_positionEffectName != null) 'position_effect': _positionEffectName!,
      'time_in_flow_bucket':
          VenueAnalytics.timeInFlowBucket(DateTime.now().difference(_openedAt)),
    });
  }

  /// One event per real change of a ticket setting (deduped per slip).
  void _settingChanged(String setting, Object value) {
    VenueAnalytics.settingChanged('hl_order_slip_setting_changed',
        setting: setting,
        value: value,
        scope: _settingsScope,
        extra: {
          'coin': market.coin,
          'kind': isSpot ? 'spot' : 'perp',
          ...VenueAnalytics.hlAssetParams(market.coin,
              kind: isSpot ? 'spot' : 'perp'),
          'wallet_kind': _isLedger ? 'ledger' : 'hot',
        });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _strings = context.l10n;
  }

  // ── Stale-price guard ──────────────────────────────────────────────
  // No mid tick for >10 s → confirm disabled with "refreshing price…".
  double? _lastMid;
  DateTime _lastPriceAt = DateTime.now();
  bool _priceStale = false;
  Timer? _staleTimer;

  StreamSubscription<HlFill>? _fillSub;
  HlLivePricesNotifier? _livePrices;

  /// The position held when the order went out, for a perp at market
  /// against one (null for an open): the filled receipt says what the
  /// fill did to it.
  HlPositionPlan? _sentPlan;

  /// This order's fills as the venue reports them, for what a fill against
  /// the position realised.
  final List<HlFill> _orderFills = [];

  HlMarket get market => widget.market;
  bool get isSpot => market.isSpot;

  /// The plain-money cost of HOLDING a leveraged position for a day at the
  /// current funding rate, as a finished sentence — or null when there is
  /// no rate to quote, or the number would round to nothing. A cost is
  /// never invented: no rate, no line.
  String? _holdingCostLine(double notional) {
    final funding = market.funding;
    if (isSpot || funding == null || funding == 0 || notional <= 0) {
      return null;
    }
    // HL settles funding hourly; the ticket speaks in days.
    final perDay = notional * funding.abs() * 24;
    if (perDay < 0.01) return null;
    final amount = formatHlUsd(perDay);
    final pays = _isLong ? funding > 0 : funding < 0;
    return pays
        ? _strings.investingSlipHoldingCost(amount)
        : _strings.investingSlipHoldingPaid(amount);
  }

  /// This ticket is pinned to a Ledger account.
  bool get _isLedger => widget.ledgerWalletId != null;

  bool get _isTriggerType =>
      _mode == _OrderMode.pro &&
      (_proType == _ProType.stopLimit ||
          _proType == _ProType.stopMarket ||
          _proType == _ProType.takeLimit ||
          _proType == _ProType.takeMarket);

  bool get _isScale => _mode == _OrderMode.pro && _proType == _ProType.scale;
  bool get _isTwap => _mode == _OrderMode.pro && _proType == _ProType.twap;

  /// An "opening" order (Market/Limit non-reduce-only) can carry a TP/SL
  /// attach and shows a liquidation estimate.
  bool get _isOpening =>
      !isSpot &&
      !_reduceOnly &&
      (_mode == _OrderMode.market || _mode == _OrderMode.limit);

  /// Allowlisted educational order type, without side, size or leverage.
  String get _salOrderTypeLabel {
    switch (_mode) {
      case _OrderMode.market:
        return 'market';
      case _OrderMode.limit:
        return 'limit';
      case _OrderMode.pro:
        switch (_proType) {
          case _ProType.scale:
            return 'scale';
          case _ProType.stopLimit:
            return 'stop_limit';
          case _ProType.stopMarket:
            return 'stop_market';
          case _ProType.takeLimit:
            return 'take_profit_limit';
          case _ProType.takeMarket:
            return 'take_profit_market';
          case _ProType.twap:
            return 'twap';
        }
    }
  }

  @override
  void initState() {
    super.initState();
    _isLong = widget.initialIsLong;
    // Isolated by default, everywhere the venue allows a choice. Cross
    // margin lets ONE losing position reach every other position in the
    // account; isolated keeps the damage inside this ticket. Cross is still
    // one tap away in the margin-mode control for anyone who wants it.
    // A market with an open position starts from THAT position's leverage
    // and mode instead (see _defaultLeverage).
    _isCross = false;
    _applyPositionDefaults(initial: true);
    if (!isSpot && !_positionDefaultsApplied) {
      // The account may still be loading: take the position's settings
      // when it lands, unless the person already chose their own.
      if (_isLedger) {
        ref.listenManual(ledgerHlAccountProvider(widget.ledgerWalletId!),
            (_, __) => _applyPositionDefaults());
      } else {
        ref.listenManual(hyperliquidPerpPositionsProvider,
            (_, __) => _applyPositionDefaults());
      }
    }
    // Opens empty, typed from zero; the button offers the minimum this
    // order needs ([_orderMinimumUsd], [_placeMinimum]).
    _marginUsd = 0;
    _amountController = TextEditingController();
    _amountController.addListener(_onAmountChanged);
    _priceController = TextEditingController();
    _triggerController = TextEditingController();
    _stopLimitController = TextEditingController();
    _startPxController = TextEditingController();
    _endPxController = TextEditingController();
    _countController = TextEditingController(text: '5');
    _twapMinutesController = TextEditingController(text: '30');
    _tpController = TextEditingController();
    _slController = TextEditingController();
    _trailDistanceController = TextEditingController(text: '1');
    _trailActivationController = TextEditingController();

    _staleTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final stale =
          DateTime.now().difference(_lastPriceAt) > const Duration(seconds: 10);
      if (stale != _priceStale && mounted) {
        _updateDraft(() => _priceStale = stale);
      }
    });

    // Hold the live-price feed while the slip is up — it lives on the
    // root navigator, so the shell's Trading-tab pause must not freeze
    // the price this ticket quotes. acquire() BEFORE watchCoins so the
    // coin subscribes on the revived socket; paired release() in dispose.
    _livePrices = ref.read(hyperliquidLivePricesProvider.notifier);
    _livePrices!.acquire();

    if (!_isLedger) unawaited(_resolveOpenGate());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Live mid for the preview (and the stale guard).
      _livePrices?.watchCoins([market.coin]);
      _livePrices?.focus(market.coin, wire: market.wireCoin);
    });
  }

  @override
  void dispose() {
    if (!_submitted) {
      try {
        TrackingService.track('hyperliquid_order_slip_abandoned', params: {
          ..._slipInputs(),
          'mode': _salOrderTypeLabel,
          'had_amount': _amountEdited && _marginUsd > 0,
          'step': _flowStep,
          'reason': _stopReason ?? 'user_closed',
          if (_lastErrorCategory != null)
            'last_error_category': _lastErrorCategory!,
          'time_in_flow_bucket': VenueAnalytics.timeInFlowBucket(
              DateTime.now().difference(_openedAt)),
        });
      } catch (_) {}
    }
    TrackingService.clearFlowContext('hl_order');
    VenueAnalytics.unstage('hl', market.coin);
    VenueAnalytics.resetSettings(_settingsScope);
    // Release the live-feed hold exactly once (nulled to guard a double
    // dispose from decrementing another surface's hold).
    _livePrices?.unfocus(market.coin);
    _livePrices?.release();
    _livePrices = null;
    _staleTimer?.cancel();
    _fillSub?.cancel();
    _amountController.removeListener(_onAmountChanged);
    _amountController.dispose();
    _priceController.dispose();
    _triggerController.dispose();
    _stopLimitController.dispose();
    _startPxController.dispose();
    _endPxController.dispose();
    _countController.dispose();
    _twapMinutesController.dispose();
    _tpController.dispose();
    _slController.dispose();
    _trailDistanceController.dispose();
    _trailActivationController.dispose();
    for (final node in _numFocusNodes.values) {
      node.dispose();
    }
    _numFocusNodes.clear();
    _draftChanges.dispose();
    super.dispose();
  }

  /// The open position on this market (perps only), from the account this
  /// ticket trades: the Ledger's own reads or the spending wallet's.
  HlPerpPosition? _openPosition() {
    if (isSpot) return null;
    final Iterable<HlPerpPosition> positions;
    if (_isLedger) {
      final account =
          ref.read(ledgerHlAccountProvider(widget.ledgerWalletId!)).valueOrNull;
      positions = [
        ...?account?.account?.positions,
        for (final dex in account?.dexAccounts.values ?? const <HlAccountSnapshot>[])
          ...dex.positions,
      ];
    } else {
      positions = ref.read(hyperliquidPerpPositionsProvider);
    }
    for (final p in positions) {
      // Positions carry the wire coin ('xyz:TSLA').
      if (p.coin == market.wireCoin) return p;
    }
    return null;
  }

  /// Whether a market order here reads and routes against the position
  /// already held ([HlPositionPlan]): a perp, at market, not reduce-only.
  bool get _netsAgainstPosition =>
      !isSpot && _mode == _OrderMode.market && !_reduceOnly;

  /// What an order of [orderSize] (floored, in coins) does to the position
  /// held here: open, add, or on the other side reduce, close (within one
  /// size step of it) or flip.
  HlPositionPlan _positionPlanFor(double orderSize) => isSpot
      ? const HlPositionPlan.open()
      : hlPositionPlan(
          position: _openPosition(),
          orderIsLong: _isLong,
          orderSize: orderSize,
          szDecimals: market.szDecimals,
        );

  /// The plan for the ticket as it stands, at [px] (the live mid by
  /// default), sized the way the submit path sizes it.
  HlPositionPlan _currentPlan({double? px}) {
    final ref = px ?? _lastMid ?? (market.midPx > 0 ? market.midPx : market.markPx);
    final lev = isSpot ? 1 : _leverage;
    final size = ref > 0
        ? sizeFromUsd(
            usd: _marginUsd * lev, px: ref, szDecimals: market.szDecimals)
        : 0.0;
    return _positionPlanFor(size);
  }

  /// The last plan the ticket showed, for the order-submitted event.
  String? _positionEffectName;

  /// Starts the ticket from the open position's leverage and margin mode,
  /// so adding to it sends the same values and the order path changes
  /// nothing. Never overrides a choice the person already made.
  void _applyPositionDefaults({bool initial = false}) {
    if (_positionDefaultsApplied || _leverageTouched || !mounted) return;
    final pos = _openPosition();
    if (pos == null) return;
    _positionDefaultsApplied = true;
    final lev = pos.leverageValue.clamp(1, market.offeredMaxLeverage).toInt();
    final cross = pos.isCross && !market.onlyIsolated;
    void apply() {
      _defaultLeverage = lev;
      _defaultIsCross = cross;
      _leverage = lev;
      _isCross = cross;
    }

    if (initial) {
      apply();
    } else {
      _updateDraft(apply);
    }
  }

  /// A placement stopped before anything was submitted.
  void _trackBlocked(String reason) {
    _stopped(reason);
    TrackingService.track('hyperliquid_order_blocked', params: {
      ..._slipInputs(),
      'action': 'open',
      'reason': reason,
      'coin': market.coin,
      'wallet_kind': _isLedger ? 'ledger' : 'hot',
    });
  }

  void _onAmountChanged() {
    final parsed = double.tryParse(_amountController.text) ?? 0.0;
    if (parsed != _marginUsd) {
      _amountEdited = true;
      _amountMethod = 'keypad';
      _updateDraft(() => _marginUsd = parsed);
    }
  }

  /// A key on the simple ticket's built-in keypad. The controller stays the
  /// single source of truth (Advanced shares it), so this only writes the
  /// new string and lets [_onAmountChanged] move `_marginUsd`. The extra
  /// repaint covers keystrokes that leave the parsed value alone but change
  /// what the big number reads ('10' → '10.').
  void _onKeypadAmount(String v) {
    if (v == _amountController.text) return;
    _amountController.text = v;
    _updateDraft(() {});
  }

  /// The Max chip beside the figure on the simple ticket, or the primary
  /// button while the amount is under the minimum: types [usd] as the
  /// keypad would and records how the amount was filled ('max' / 'min').
  void _fillAmountChip(double usd, String method) {
    if (usd <= 0) return;
    HapticFeedback.selectionClick();
    _onKeypadAmount(usd.toStringAsFixed(2));
    _amountMethod = method;
  }

  /// The smallest amount the field can take (margin on a perp, dollars on
  /// spot) for the order this ticket would send now: its size floored the
  /// way the submit path floors it, valued at the price the venue checks
  /// (the slippage price for a market sell or short, see [hlMinCheckPx]),
  /// with a small buffer for the price moving before it is sent. One
  /// figure for the available line, the minimum buttons and the check
  /// before submit. [px] defaults to the live mid.
  double _orderMinimumUsd({double? px, double baseSize = 0}) {
    final ref = px ?? _lastMid ?? (market.midPx > 0 ? market.midPx : market.markPx);
    final checkPx = hlMinCheckPx(
      referencePx: ref,
      isBuy: _isLong,
      slippage: _mode == _OrderMode.market ? _slippagePct / 100 : 0,
      szDecimals: market.szDecimals,
      isSpot: isSpot,
    );
    return hlMinOrderAmountUsd(
      referencePx: ref,
      checkPx: checkPx,
      szDecimals: market.szDecimals,
      leverage: isSpot ? 1 : _leverage,
      baseSize: baseSize,
    );
  }

  /// The empty ticket's button: writes [minAmountUsd] into the amount the
  /// way the keypad would, and the next build places it through the
  /// normal confirm, or opens the funding it needs when the balance
  /// cannot cover it, the way a typed minimum would.
  void _placeMinimum(double minAmountUsd) {
    if (minAmountUsd <= 0) return;
    _placeMinimumOnBuild = true;
    _fillAmountChip(minAmountUsd, 'min_direct');
  }

  double? _parse(TextEditingController c) {
    final v = double.tryParse(c.text.trim());
    return (v != null && v > 0) ? v : null;
  }

  int? _parseInt(TextEditingController c) => int.tryParse(c.text.trim());

  /// Non-watching mid for use in tap handlers (build uses [_referenceMid]).
  double _midNow() =>
      _lastMid ?? (market.midPx > 0 ? market.midPx : market.markPx);

  void _prefill(TextEditingController c, double px) {
    if (c.text.trim().isEmpty && px > 0) {
      try {
        c.text = roundPrice(px, szDecimals: market.szDecimals, isSpot: isSpot);
      } catch (_) {}
    }
  }

  void _updateDraft(VoidCallback update) {
    setState(() {
      update();
      // A type switch can hide the field the keypad was writing to; fall
      // back to the size field so the pad never edits something invisible.
      if (!_fieldVisible(_focusedField)) _focusedField = _NumField.size;
    });
    _draftChanges.value++;
  }

  // ── Advanced numeric fields ────────────────────────────────────────
  // The Advanced page carries several numbers at once, so instead of one
  // keyboard per field it has one pinned keypad that writes to the field
  // the user last tapped. Each field keeps its own controller (and so its
  // own validation and side effects) and its own decimal rule.

  /// Is [f] on screen for the ticket as it stands?
  bool _fieldVisible(_NumField f) {
    switch (f) {
      case _NumField.size:
        return true;
      case _NumField.limitPrice:
        return _mode == _OrderMode.limit;
      case _NumField.trigger:
        return _isTriggerType;
      case _NumField.stopLimitPrice:
        return _mode == _OrderMode.pro &&
            (_proType == _ProType.stopLimit || _proType == _ProType.takeLimit);
      case _NumField.scaleStart:
      case _NumField.scaleEnd:
      case _NumField.scaleCount:
        return _isScale;
      case _NumField.twapMinutes:
        return _isTwap;
      case _NumField.takeProfit:
      case _NumField.stopLoss:
        return _isOpening && _attachTpSl;
      case _NumField.trailDistance:
        return _trailingAvailable && _attachTrailing;
      case _NumField.trailActivation:
        return _trailingAvailable && _attachTrailing && _trailActivate;
    }
  }

  /// A trailing stop can only follow a position that exists, so it is
  /// offered on opening market orders, which fill before the ticket closes.
  bool get _trailingAvailable =>
      !isSpot && _isOpening && _mode == _OrderMode.market;

  TextEditingController _controllerFor(_NumField f) {
    switch (f) {
      case _NumField.size:
        return _amountController;
      case _NumField.limitPrice:
        return _priceController;
      case _NumField.trigger:
        return _triggerController;
      case _NumField.stopLimitPrice:
        return _stopLimitController;
      case _NumField.scaleStart:
        return _startPxController;
      case _NumField.scaleEnd:
        return _endPxController;
      case _NumField.scaleCount:
        return _countController;
      case _NumField.twapMinutes:
        return _twapMinutesController;
      case _NumField.takeProfit:
        return _tpController;
      case _NumField.stopLoss:
        return _slController;
      case _NumField.trailDistance:
        return _trailDistanceController;
      case _NumField.trailActivation:
        return _trailActivationController;
    }
  }

  /// A price is not a count is not minutes — the pad hides its decimal key
  /// entirely for the integer fields.
  int _decimalsFor(_NumField f) {
    switch (f) {
      case _NumField.size:
        return 2;
      case _NumField.scaleCount:
      case _NumField.twapMinutes:
        return 0;
      case _NumField.limitPrice:
      case _NumField.trigger:
      case _NumField.stopLimitPrice:
      case _NumField.scaleStart:
      case _NumField.scaleEnd:
      case _NumField.takeProfit:
      case _NumField.stopLoss:
      case _NumField.trailActivation:
        return 8;
      case _NumField.trailDistance:
        return 4;
    }
  }

  Future<void> _openAdvanced() async {
    if (_advancedRouteOpen ||
        _isPlacing ||
        _orderInFlight ||
        _ledgerBusy ||
        _ledgerPending) {
      return;
    }
    // Withheld Advanced opens nothing; the shared sheet says why. Anything
    // a caller set up for the page (Sal's switch to limit) goes back too,
    // so the plain ticket stays a plain market order.
    if (!advancedTradingOffered(
        context, ref.read(runtimeCapabilitiesProvider))) {
      _resetAdvanced();
      return;
    }
    HapticFeedback.selectionClick();
    FocusManager.instance.primaryFocus?.unfocus();
    _advancedRouteOpen = true;
    _trackStep('advanced');
    try {
      await Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          settings: const RouteSettings(name: 'hyperliquid-advanced-order'),
          builder: (routeContext) => Consumer(
            builder: (context, routeRef, _) => AnimatedBuilder(
              animation: _draftChanges,
              builder: (context, _) =>
                  _buildTicket(context, routeRef, advanced: true),
            ),
          ),
        ),
      );
    } finally {
      _advancedRouteOpen = false;
      // Back from Advanced discards what was set there: the plain ticket
      // is always a plain market order (owner decision). Advanced orders
      // are placed from the Advanced page itself.
      if (mounted) _resetAdvanced();
    }
  }

  /// Returns every Advanced-only setting to the ticket's opening state.
  void _resetAdvanced() {
    _updateDraft(() {
      _mode = _OrderMode.market;
      _proType = _ProType.stopMarket;
      _tif = 'Gtc';
      _postOnly = false;
      _reduceOnly = false;
      _attachTpSl = false;
      _attachTrailing = false;
      _trailPercent = true;
      _trailActivate = false;
      _slippagePct = 1.0;
      // Back to the ticket's starting point: the open position's own
      // leverage and mode, else isolated 1x.
      _leverage = _defaultLeverage;
      _isCross = _defaultIsCross;
      _leverageTouched = false;
      for (final controller in [
        _priceController,
        _triggerController,
        _stopLimitController,
        _startPxController,
        _endPxController,
        _countController,
        _twapMinutesController,
        _tpController,
        _slController,
        _trailActivationController,
      ]) {
        controller.clear();
      }
      _trailDistanceController.text = '1';
    });
  }

  // The sheet asks for confirmation before calling this. Recheck the origin
  // after dismissal; no amount, side or leverage is supplied by Sal.
  bool _applySalAction(String actionId) {
    if (!mounted ||
        _isPlacing ||
        _orderInFlight ||
        ModalRoute.of(context)?.isCurrent != true) {
      return false;
    }
    if (actionId == 'switch_to_limit') {
      final keepReduceOnly = _reduceOnly;
      _onSelectMode(_OrderMode.limit);
      _updateDraft(() => _reduceOnly = keepReduceOnly);
      unawaited(_openAdvanced());
      return true;
    }
    if (actionId == 'open_leverage_settings' && !isSpot) {
      unawaited(_openAdvanced());
      return true;
    }
    return false;
  }

  void _onSelectMode(_OrderMode m) {
    if (_mode == m) return;
    HapticFeedback.selectionClick();
    if (m != _OrderMode.pro) _settingChanged('order_type', m.name);
    _updateDraft(() {
      _mode = m;
      _errorText = null;
      _errorCause = null;
      if (m == _OrderMode.limit) {
        _reduceOnly = false;
        _prefill(_priceController, _midNow());
      }
      if (m == _OrderMode.pro) _applyProDefaults();
    });
  }

  void _onSelectProType(_ProType t) {
    HapticFeedback.selectionClick();
    _settingChanged('order_type', t.name);
    _updateDraft(() {
      _proType = t;
      _errorText = null;
      _errorCause = null;
      _applyProDefaults();
    });
  }

  void _applyProDefaults() {
    switch (_proType) {
      case _ProType.scale:
        _reduceOnly = false;
        _prefill(_startPxController, _midNow());
        _prefill(_endPxController, _midNow());
      case _ProType.twap:
        _reduceOnly = false;
      case _ProType.stopLimit:
      case _ProType.stopMarket:
      case _ProType.takeLimit:
      case _ProType.takeMarket:
        // Stops/takes are protective by default.
        _reduceOnly = true;
        _prefill(_triggerController, _midNow());
        if (_proType == _ProType.stopLimit || _proType == _ProType.takeLimit) {
          _prefill(_stopLimitController, _midNow());
        }
    }
  }

  /// Live mid → snapshot mid → mark. Feeds the stale-guard clock from ANY
  /// usable price (live tick OR the 30s-refreshed snapshot) — a quiet market,
  /// or a HIP-3 builder market that isn't in the allMids feed, still has a
  /// valid snapshot mid and must NOT read as stale. The guard only fires when
  /// there's genuinely no price at all.
  double _referenceMid(WidgetRef observingRef) {
    final live = observingRef.watch(hyperliquidLiveMidProvider(market.coin));
    final price = (live != null && live > 0)
        ? live
        : (market.midPx > 0 ? market.midPx : market.markPx);
    if (price > 0) {
      _lastMid = price;
      _lastPriceAt = DateTime.now();
    }
    return price;
  }

  /// The price used to derive size / preview for the current order type:
  /// mid for market/TWAP, the entered limit for Limit, avg for Scale, the
  /// trigger for Stop/Take. Falls back to mid when the field is empty.
  /// The liquidation price this order would most likely get, from the
  /// venue's documented rule (see LiquidationEstimate). Null when the
  /// inputs cannot describe a position, or when an opposite position on
  /// this market means the order reduces rather than opens.
  ({double? price, String? blocker}) _liquidationEstimate(
      double entry, double size) {
    if (!(entry > 0) || !(size > 0)) return (price: null, blocker: null);
    final positions = ref.watch(hyperliquidPerpPositionsProvider);
    HlPerpPosition? existing;
    for (final p in positions) {
      // Positions carry the wire coin ('xyz:TSLA').
      if (p.coin == market.wireCoin) {
        existing = p;
        break;
      }
    }
    if (existing != null && existing.isLong != _isLong) {
      return (price: null, blocker: _strings.slipDependsOnPosition);
    }
    // Adding to a position in the same direction: estimate the combined
    // position at its size-weighted entry, backed by both margins.
    final combinedSize = size + (existing?.szi.abs() ?? 0);
    final combinedNotional =
        entry * size + (existing?.entryPx ?? 0) * (existing?.szi.abs() ?? 0);
    final combinedEntry = combinedNotional / combinedSize;
    final double? price;
    if (_isCross) {
      final account = ref.watch(hyperliquidAccountProvider).valueOrNull;
      if (account == null) return (price: null, blocker: null);
      price = LiquidationEstimate.cross(
        price: combinedEntry,
        size: combinedSize,
        isLong: _isLong,
        accountValue: account.accountValue,
        // The existing position's own maintenance margin is counted
        // again inside the combined position, so take it back out.
        maintenanceMarginUsed: account.crossMaintenanceMarginUsed -
            (existing != null && existing.leverageType == 'cross'
                ? existing.positionValue.abs() *
                    LiquidationEstimate.maintenanceFraction(market.maxLeverage)
                : 0),
        maxLeverage: market.maxLeverage,
      );
    } else {
      price = LiquidationEstimate.isolated(
        price: combinedEntry,
        size: combinedSize,
        isLong: _isLong,
        marginUsd: _marginUsd +
            (existing != null && existing.leverageType == 'isolated'
                ? existing.marginUsed
                : 0),
        maxLeverage: market.maxLeverage,
      );
    }
    return (price: price, blocker: null);
  }

  double _entryPx(double mid) {
    switch (_mode) {
      case _OrderMode.market:
        return mid;
      case _OrderMode.limit:
        return _parse(_priceController) ?? mid;
      case _OrderMode.pro:
        switch (_proType) {
          case _ProType.scale:
            final s = _parse(_startPxController);
            final e = _parse(_endPxController);
            if (s != null && e != null) return (s + e) / 2;
            return s ?? e ?? mid;
          case _ProType.twap:
            return mid;
          case _ProType.stopLimit:
          case _ProType.stopMarket:
          case _ProType.takeLimit:
          case _ProType.takeMarket:
            return _parse(_triggerController) ?? mid;
        }
    }
  }

  String _messageFor(Object e) {
    if (e is ProviderAvailabilityException) {
      return e.availability.message;
    }
    if (e is CapabilityUnavailableException) {
      return e.decision.message;
    }
    // The venue minimum: name the minimum this ticket needs now, the
    // figure the button and the available line show, not the bare $10.
    if (hlIsMinNotionalError(e) && !_reduceOnly && !_isScale) {
      return _strings.investingMinimumOrder(formatHlUsd(_orderMinimumUsd()));
    }
    return hlTradeErrorMessage(_strings, e);
  }

  // ── Confirm ────────────────────────────────────────────────────────

  /// Anything past a plain 1x market order at default slippage is
  /// Advanced. While the policy withholds Advanced the page does not open
  /// (the tap shows the shared sheet); if it is withdrawn while the page
  /// is open, the ticket cannot submit until these are back to plain.
  bool get _usesAdvanced =>
      _mode != _OrderMode.market ||
      _leverage > 1 ||
      _isCross ||
      _attachTpSl ||
      _attachTrailing ||
      _slippagePct != 1.0;

  Future<void> _handleConfirm() async {
    if (_isLedger) {
      await _confirmLedger();
      return;
    }
    if (_orderInFlight || _isPlacing) return;
    _orderInFlight = true;
    // The button starts thinking HERE, on the tap, not once the order
    // is on the wire. Everything _confirmInner does before that point
    // is a network round trip too: the geo re-check, and the builder
    // fee approval, which signs and posts to the venue. Those took
    // seconds on a cold account and the slip sat there looking like
    // the tap had missed.
    if (mounted) _updateDraft(() => _preparing = true);
    try {
      if (_usesAdvanced) {
        await RuntimeCapabilitiesService.instance
            .ensureAllowed('trading.advanced');
      }
      await _confirmInner();
    } catch (e) {
      if (mounted) {
        _updateDraft(() {
          _errorCause = e;
          _errorText = _messageFor(e);
        });
      }
    } finally {
      _orderInFlight = false;
      if (mounted) _updateDraft(() => _preparing = false);
    }
  }

  Future<void> _confirmInner() async {
    HapticFeedback.mediumImpact();
    // Re-check both gates at place time — a slip left open must not
    // trade through a region/config change (mirrors _handleBuyInner).
    // Reducing or closing the held position is an exit, gated as one.
    final exit = _netsAgainstPosition && _currentPlan().isExit;
    if (await checkHyperliquidGeoblock(context, ref,
        maxAge: const Duration(seconds: 60),
        capabilities: (_mode != _OrderMode.market && _reduceOnly) ||
                (isSpot && !_isLong) ||
                exit
            ? const ['hyperliquid.close']
            : hlOpenCapabilities(market))) {
      return;
    }
    if (!mounted) return;

    if (!await ensureHotHlBuilderFeeConsent(context, ref)) {
      _trackBlocked('builder_fee');
      return;
    }
    if (!mounted) return;

    final mid = _lastMid ?? (market.midPx > 0 ? market.midPx : market.markPx);
    if (mid <= 0) {
      _trackBlocked('no_price');
      return;
    }

    if (_mode == _OrderMode.market) {
      await _confirmMarket(mid);
    } else {
      await _confirmAdvanced(mid);
    }
  }

  /// Market path — keeps the original placing-tile + WS-fill reconciliation
  /// (openPosition / placeSpotOrder), plus optional reduce-only TP/SL for
  /// perp opens.
  Future<void> _confirmMarket(double mid) async {
    final lev = isSpot ? 1 : _leverage;
    final notional = _marginUsd * lev;
    final size =
        sizeFromUsd(usd: notional, px: mid, szDecimals: market.szDecimals);
    // Against a held position on the other side: a reduce or a close goes
    // out reduce-only through the close path (no venue minimum), a flip
    // as one order whose part past the position must meet the minimum.
    final plan = _netsAgainstPosition
        ? _positionPlanFor(size)
        : const HlPositionPlan.open();
    if (!isSpot) _positionEffectName = plan.effect.name;
    _sentPlan = plan.effect == HlPositionEffect.open ? null : plan;
    _orderFills.clear();
    if (plan.isExit) {
      if (size <= 0) {
        _trackBlocked('below_min');
        return;
      }
      await _confirmExit(plan);
      return;
    }
    // The FLOORED size decides it, not the amount typed: those differ
    // by up to one step, which on BTC is most of a dollar. And it is
    // valued where the venue values it: a sell or short at its slippage
    // price, under the mid. An order the venue would refuse is never
    // sent; the ticket re-reads the minimum at this price instead, and
    // the button turns into it.
    final checkPx = hlMinCheckPx(
      referencePx: mid,
      isBuy: _isLong,
      slippage: _slippagePct / 100,
      szDecimals: market.szDecimals,
      isSpot: isSpot,
    );
    final opening = plan.effect == HlPositionEffect.flip ? plan.remainder : size;
    if (size <= 0 || !meetsMinNotional(px: checkPx, sz: opening)) {
      _trackBlocked('below_min');
      if (mounted) _updateDraft(() => _lastMid = mid);
      return;
    }

    // Phase 1b.3: a fresh approval bound to exactly this order, before the
    // placing tile or any state change. Declining stops here.
    final walletId = _spendingWalletId();
    if (walletId == null) {
      _trackBlocked('no_wallet');
      _updateDraft(() => _errorText = _messageFor(Exception('No wallet')));
      return;
    }
    final cloid = newHlCloid();
    _trackStep('approval');
    final grant = await _approve(
      _marketOrder(walletId, cloid).intent,
      amountUsd: _marginUsd,
      smallAction: isSpot && _isLong
          ? SmallActionContext(
              amountUsdCents: (_marginUsd * 100).ceil(),
              paidFromVenueBalance: true,
              hasFundingLeg: false,
            )
          : null,
    );
    if (grant == null || !mounted) {
      if (grant == null) _stopped('signing_declined');
      return;
    }

    // Pre-existing SIGNED size so the placing tile reconciles on the
    // position delta, not the absolute size.
    double preExisting = 0;
    for (final p in ref.read(hyperliquidPerpPositionsProvider)) {
      if (p.coin == market.coin) {
        preExisting = p.szi;
        break;
      }
    }

    final label = isSpot
        ? market.coin
        : '${market.coin} · ${hlKindLabel(_strings, isSpot: false)}';
    final placing = ref.read(placingHyperliquidOrderProvider.notifier);
    final placementId = placing.markPlacing(
      coin: market.coin,
      marketLabel: label,
      isLong: _isLong,
      marginUsd: _marginUsd,
      leverage: lev,
      sizeRequested: size,
      preExistingSize: preExisting,
    );
    placing.attachCloid(placementId, cloid);

    // Listen for the matching WS fill BEFORE submitting, so a fast fill
    // can't slip between the REST response and the subscription.
    _fillSub?.cancel();
    _fillSub =
        ref.read(hyperliquidUserEventsProvider.notifier).fills.listen((f) {
      if (f.coin != market.coin) return;
      if (f.cloid != null && f.cloid != cloid) return;
      _orderFills.add(f);
      // With a trailing stop attached the result path places it first,
      // then closes the ticket; a stream fill must not close it early.
      if (_attachTrailing) return;
      // Against a held position the receipt says what the whole fill did
      // to it, so the venue's answer (with the filled total) closes it.
      if (_sentPlan != null) return;
      _onFilled(sizeFilled: f.sz, avgPx: f.px);
    });

    _updateDraft(() {
      _isPlacing = true;
      _errorText = null;
      _errorCause = null;
    });

    try {
      // Rebuilt from the ticket as it is now. Anything that changed since
      // the approval (leverage, side, amount) makes the notifier throw
      // ReauthRequired before it signs.
      _submitted = true;
      _trackSubmitted();
      final result = await _marketOrder(walletId, cloid).place(grant);
      placing.markSucceeded(placementId);
      if (result.filledSz > 0) {
        await _placeAttachedTrailing(result.filledSz);
        if (!mounted) return;
        final fills = _sentPlan?.effect == HlPositionEffect.flip
            ? await _fillsOf(result)
            : const <HlFill>[];
        if (!mounted) return;
        _onFilled(
            sizeFilled: result.filledSz, avgPx: result.avgPx, fills: fills);
      } else {
        // Accepted but not (yet) filled — the WS listener / placing
        // tile takes over; close the slip so the user isn't trapped.
        if (mounted && !_completed) {
          final navigator = Navigator.of(context, rootNavigator: true);
          final ticketRoute = ModalRoute.of(context);
          navigator.popUntil((route) => route == ticketRoute || route.isFirst);
          if (ticketRoute?.isCurrent == true && navigator.canPop()) {
            navigator.pop();
          }
        }
      }
    } catch (e) {
      _lastErrorCategory = TrackingService.errorCategory(e);
      if (e is AuthGrantException) {
        // Nothing was signed: drop the tile and ask for a new review.
        _fillSub?.cancel();
        placing.clear(placementId);
        if (mounted) _updateDraft(() => _isPlacing = false);
        await _onGrantFailure(e);
        return;
      }
      placing.markFailed(placementId, _messageFor(e));
      if (mounted) {
        _updateDraft(() {
          _isPlacing = false;
          _errorText = _messageFor(e);
          _errorCause = e;
        });
      }
    }
  }

  /// A market order that only reduces or closes the position held here,
  /// placed reduce-only through the close path: a fraction of the
  /// position for a reduce, all of it for a close. The venue minimum does
  /// not apply and no margin is moved.
  Future<void> _confirmExit(HlPositionPlan plan) async {
    final pos = plan.position!;
    final walletId = _spendingWalletId();
    if (walletId == null) {
      _trackBlocked('no_wallet');
      _updateDraft(() => _errorText = _messageFor(Exception('No wallet')));
      return;
    }
    final fraction = plan.closeFraction;
    final slippagePct = _slippagePct;
    final trading = ref.read(hyperliquidTradingProvider.notifier);
    _trackStep('approval');
    final grant = await _approve(
      HlIntents.close(
        walletId: walletId,
        market: market,
        positionIsLong: pos.isLong,
        fraction: fraction,
        slippagePct: slippagePct,
      ),
      amountUsd: _marginUsd,
    );
    if (grant == null || !mounted) {
      if (grant == null) _stopped('signing_declined');
      return;
    }
    _updateDraft(() {
      _isPlacing = true;
      _errorText = null;
      _errorCause = null;
    });
    // The close's fills carry what it realised; it sends its own cloid,
    // so they are matched on the order id once the venue answers.
    _fillSub?.cancel();
    _fillSub =
        ref.read(hyperliquidUserEventsProvider.notifier).fills.listen((f) {
      if (f.coin == market.coin) _orderFills.add(f);
    });
    try {
      _submitted = true;
      _trackSubmitted();
      final result = await trading.closePosition(
        coin: pos.coin,
        fraction: fraction,
        slippagePct: slippagePct,
        grant: grant,
      );
      if (!mounted) return;
      if (result.filledSz > 0) {
        final fills = await _fillsOf(result);
        if (!mounted) return;
        _onFilled(
            sizeFilled: result.filledSz, avgPx: result.avgPx, fills: fills);
      } else if (!_completed) {
        final navigator = Navigator.of(context, rootNavigator: true);
        final ticketRoute = ModalRoute.of(context);
        navigator.popUntil((route) => route == ticketRoute || route.isFirst);
        if (ticketRoute?.isCurrent == true && navigator.canPop()) {
          navigator.pop();
        }
      }
    } catch (e) {
      _fillSub?.cancel();
      _lastErrorCategory = TrackingService.errorCategory(e);
      if (e is AuthGrantException) {
        if (mounted) _updateDraft(() => _isPlacing = false);
        await _onGrantFailure(e);
        return;
      }
      if (mounted) {
        _updateDraft(() {
          _isPlacing = false;
          _errorText = _messageFor(e);
          _errorCause = e;
        });
      }
    }
  }

  /// Limit / Pro path — routes to the matching notifier method. Marketable
  /// fills and accepted resting orders have distinct confirmation receipts.
  Future<void> _confirmAdvanced(double mid) async {
    // Phase 1b.3: approve exactly this order before listening or placing.
    final walletId = _spendingWalletId();
    if (walletId == null) {
      _trackBlocked('no_wallet');
      _updateDraft(() => _errorText = _messageFor(Exception('No wallet')));
      return;
    }
    final cloid = newHlCloid();
    final approved = _advancedOrder(walletId, mid, cloid);
    if (approved == null) return; // Market mode: handled by _confirmMarket.
    _sentPlan = null;
    _trackStep('approval');
    final grant = await _approve(approved.intent, amountUsd: _marginUsd);
    if (grant == null || !mounted) {
      if (grant == null) _stopped('signing_declined');
      return;
    }

    // Limit orders may fill immediately — listen for the matching fill by
    // cloid. Scale/TWAP/trigger fills don't carry our cloid (and rest
    // rather than fill on placement), so we don't listen for them: they
    // resolve via _onRestingAccepted, and matching a cloid-less fill here
    // would risk latching onto an unrelated fill mid-submit.
    if (_mode == _OrderMode.limit) {
      _fillSub?.cancel();
      _fillSub =
          ref.read(hyperliquidUserEventsProvider.notifier).fills.listen((f) {
        if (f.coin != market.coin) return;
        if (f.cloid != null && f.cloid != cloid) return;
        if (f.cloid == null) return; // only our own cloid-tagged fills
        _onFilled(sizeFilled: f.sz, avgPx: f.px);
      });
    }

    _updateDraft(() {
      _isPlacing = true;
      _errorText = null;
      _errorCause = null;
    });

    try {
      // Rebuilt from the ticket as it is now (see _confirmMarket). A switch
      // back to Market since the approval is a change too.
      final order = _advancedOrder(walletId, mid, cloid) ??
          (throw ReauthRequired(const {DriftField.other}));
      _submitted = true;
      _trackSubmitted();
      final result = await order.place(grant);

      if (result.filledSz > 0) {
        _onFilled(sizeFilled: result.filledSz, avgPx: result.avgPx);
      } else {
        _onRestingAccepted();
      }
    } catch (e) {
      _fillSub?.cancel();
      _lastErrorCategory = TrackingService.errorCategory(e);
      if (e is AuthGrantException) {
        // Nothing was signed.
        if (mounted) _updateDraft(() => _isPlacing = false);
        await _onGrantFailure(e);
        return;
      }
      if (mounted) {
        _updateDraft(() {
          _isPlacing = false;
          _errorText = _messageFor(e);
          _errorCause = e;
        });
      }
    }
  }

  // ── Step-up (Wallet Hardening Phase 1b.3) ───────────────────────────

  String? _spendingWalletId() =>
      pickSpendingWallet(ref.read(settingsProvider))?.id;

  /// Asks for a fresh approval bound to [intent]. Null when declined.
  Future<AuthGrant?> _approve(
    SensitiveIntent intent, {
    required double amountUsd,
    SmallActionContext? smallAction,
  }) {
    final label = isSpot
        ? market.coin
        : '${market.coin} · ${hlKindLabel(_strings, isSpot: false)}';
    return requireFreshAuthGrant(
      context,
      ref,
      intent: intent,
      reason: context.l10n.stepUpReasonOrder(label),
      amountUsd: amountUsd,
      smallAction: smallAction,
    );
  }

  /// A grant failure thrown by the notifier: drift shows "Review again", a
  /// stale grant stops quietly. Nothing was signed in either case.
  Future<void> _onGrantFailure(AuthGrantException e) async {
    if (!mounted) {
      trackGrantFailure(e, action: SensitiveAction.hlOrder);
      return;
    }
    await handleGrantFailure(context, e, action: SensitiveAction.hlOrder);
  }

  // ── Ledger (Wallet hardening Phase 4a, P4.7) ────────────────────────
  // The device signs a plain market order: the builder fee once, the
  // leverage when it differs, then the order — each its own reviewed
  // approval inside runLedgerHlMarketOrder. Nothing here signs, and no
  // hot provider is touched.

  /// Builder fee → leverage → order, then the filled / placed receipt.
  /// "Filled" only on a filled result (plan B13); a pending submission
  /// keeps the journal's word and leaves the ticket standing.
  Future<void> _confirmLedger() async {
    final walletId = widget.ledgerWalletId;
    if (walletId == null || _ledgerBusy || _ledgerPending) return;
    HapticFeedback.mediumImpact();
    FocusManager.instance.primaryFocus?.unfocus();
    final l10n = context.l10n;
    final navigator = Navigator.of(context, rootNavigator: true);
    final marginUsd = _marginUsd;
    TrackingService.track('ledger_investing_review_opened', params: {
      'amount_bucket': TrackingService.usdBucket(marginUsd),
      'kind': isSpot ? 'spot' : 'perp',
    });
    _trackStep('review');
    _updateDraft(() {
      _ledgerBusy = true;
      _errorText = null;
      _errorCause = null;
    });
    final HlOrderResult? result;
    try {
      if (_usesAdvanced) {
        await RuntimeCapabilitiesService.instance
            .ensureAllowed('trading.advanced');
      }
      if (!mounted) return;
      // Reducing or closing the position held here goes out reduce-only
      // through the Ledger's close, as on the spending wallet.
      final plan = _netsAgainstPosition
          ? _currentPlan()
          : const HlPositionPlan.open();
      if (!isSpot) _positionEffectName = plan.effect.name;
      _submitted = true;
      _trackSubmitted();
      if (plan.isExit && plan.orderSize > 0) {
        final outcome = await runLedgerHlClose(
          context,
          ref,
          walletId: walletId,
          position: plan.position!,
          market: market,
          size: plan.effect == HlPositionEffect.close
              ? plan.heldSize
              : plan.orderSize,
          slippagePct: _slippagePct,
        );
        if (outcome?.isPending == true && mounted) {
          _updateDraft(() => _ledgerPending = true);
        }
        result = outcome?.isSuccess == true ? outcome!.result : null;
      } else {
        result = await runLedgerHlMarketOrder(
          context,
          ref,
          walletId: walletId,
          market: market,
          isBuy: _isLong,
          marginUsd: marginUsd,
          leverage: isSpot ? 1 : _leverage,
          slippagePct: _slippagePct,
          onPending: () {
            if (mounted) _updateDraft(() => _ledgerPending = true);
          },
        );
      }
    } catch (e, st) {
      _lastErrorCategory = TrackingService.errorCategory(e);
      TrackingService.hyperliquidOrderFailed(
        coin: market.coin,
        reason: TrackingService.errorCategory(e),
        action: 'open',
        orderType: 'market',
        isBuy: _isLong,
        notionalUsd: marginUsd * (isSpot ? 1 : _leverage),
        leverage: isSpot ? 1 : _leverage,
        walletKind: 'ledger',
        stackTrace: st,
        extra: hlFailureParams(e),
      );
      if (mounted) {
        _updateDraft(() {
          _errorCause = e;
          _errorText = _messageFor(e);
        });
      }
      return;
    } finally {
      if (mounted) _updateDraft(() => _ledgerBusy = false);
    }
    if (result == null) {
      _stopped('signing_declined');
      return;
    }
    final filled =
        result.kind == HlOrderResultKind.filled || result.filledSz > 0;
    final ledgerLev =
        isSpot ? 1 : _leverage.clamp(1, market.maxLeverage).toInt();
    TrackingService.hyperliquidOrderPlaced(
      coin: market.coin,
      kind: isSpot ? 'spot' : 'perp',
      isBuy: _isLong,
      leverage: ledgerLev,
      marginUsd: marginUsd,
      notionalUsd: marginUsd * ledgerLev,
      source: widget.source,
      orderType: 'market',
      isCross: isSpot ? null : !market.onlyIsolated,
      filled: filled,
      walletKind: 'ledger',
      marketType: isSpot ? 'spot' : (market.dex.isEmpty ? 'perp' : market.dex),
      hasTp: _attachTpSl && _parse(_tpController) != null,
      hasSl: _attachTpSl && _parse(_slController) != null,
    );
    if (!mounted) return;
    if (filled) {
      final mid = _midNow();
      final fallbackSize = mid > 0
          ? sizeFromUsd(
              usd: marginUsd * (isSpot ? 1 : _leverage),
              px: mid,
              szDecimals: market.szDecimals)
          : 0.0;
      await _placeAttachedTrailing(
          result.filledSz > 0 ? result.filledSz : fallbackSize);
      if (!mounted) return;
    }
    Navigator.of(context).pop();
    showLedgerConfirmation(
      navigator,
      message: filled ? l10n.ledgerOrderFilled : l10n.ledgerOrderPlaced,
    );
  }

  /// The one funding door, locked to Trading with this ticket's margin
  /// already filled in. A Ledger ticket pins both legs to its account.
  /// One tap at a time: a tap while one runs is ignored, events included.
  Future<void> _openDepositDoor() async {
    if (_depositDoorBusy) return;
    // A withheld `hyperliquid.deposit` shuts the door: the button is
    // already disabled, and a tap racing the policy change opens nothing.
    if (ref
            .read(runtimeCapabilitiesProvider)
            .blockReason('hyperliquid.deposit') !=
        null) {
      return;
    }
    _stopped('insufficient_balance');
    _trackStep('deposit');
    setState(() => _depositDoorBusy = true);
    try {
      if (_isLedger) {
        TrackingService.track('ledger_investing_deposit_opened');
        await showDepositSheet(
          context,
          ledgerWalletId: widget.ledgerWalletId,
          lockedSide: MoveLockedSide.depositToHyperliquid,
          initialTargetUsd: _marginUsd > 0 ? _marginUsd : null,
        );
        return;
      }
      // Hot ticket: prefilled with the order's own amount (the fees added
      // only when the deposit alone would not cover it), on the spending
      // source that covers it alone. The ticket stays open underneath with
      // the same coin, side, size, leverage and order type. Everything the
      // top-up is sized on is read here, at the tap.
      final ready = _hlReadyUsd();
      final required = _hlRequiredUsd();
      setState(() => _depositCalculating = true);
      await openSlipTopUp(
        context,
        ref,
        venue: SlipVenue.investing,
        shortfallUsd: ShortfallRules.shortfallUsd(
            requiredUsd: required, readyUsd: ready),
        orderUsd: _marginUsd,
        requiredUsd: required,
        readyUsd: ready,
        fallbackTargetUsd: _marginUsd > 0 ? _marginUsd : null,
        onReturned: slipTopUpReturned,
        onSheetOpening: _depositSheetOpening,
      );
    } catch (_) {
      if (mounted) {
        showMessageSnackBar(
            context: context,
            message: context.l10n.errorCopyGeneric,
            error: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _depositDoorBusy = false;
          _depositCalculating = false;
        });
      }
    }
  }

  /// The top-up is worked out: the door stops calculating while its Move
  /// sheet is open.
  void _depositSheetOpening() {
    if (mounted && _depositCalculating) {
      setState(() => _depositCalculating = false);
    }
  }

  /// "Add more" under "Deposit incoming": the rest of the shortfall.
  void _addMoreDeposit(double shortfallUsd, double incomingUsd) {
    if (ref
            .read(runtimeCapabilitiesProvider)
            .blockReason('hyperliquid.deposit') !=
        null) {
      return;
    }
    unawaited(openSlipTopUp(
      context,
      ref,
      venue: SlipVenue.investing,
      shortfallUsd: shortfallUsd,
      orderUsd: _marginUsd,
      incomingUsd: incomingUsd,
      onReturned: slipTopUpReturned,
    ));
  }

  /// The hot account's Investing cash that is ready: perp withdrawable
  /// plus spot USDC (the notifier sweeps between them on the way).
  double _hlReadyUsd() {
    var ready = ref.read(hyperliquidWithdrawableProvider);
    for (final b in ref.read(hyperliquidSpotBalancesProvider)) {
      if (b.coin == 'USDC') ready += b.available;
    }
    return ready;
  }

  /// The venue cash this order takes: the margin with its price headroom
  /// plus fees.
  double _hlRequiredUsd() => ShortfallRules.hyperliquidRequiredUsd(
        marginUsd: _marginUsd,
        leverage: isSpot ? 1 : _leverage,
        slippagePct: _mode == _OrderMode.market ? _slippagePct : 0,
      );

  @override
  SlipVenue get slipVenue => SlipVenue.investing;

  @override
  void refreshSlipVenueCash() => unawaited(ref
      .read(hyperliquidAccountProvider.notifier)
      .refresh()
      .catchError((_) {}));

  /// Perp margin sits in the spot account: the device moves it across
  /// before the order can be signed. On the hot ticket the notifier does
  /// this silently, so this is the one extra step a Ledger really has.
  Future<void> _ledgerMakeFundsAvailable() async {
    final walletId = widget.ledgerWalletId;
    if (walletId == null || _ledgerBusy || _ledgerPending) return;
    _updateDraft(() => _ledgerBusy = true);
    TrackingService.track('ledger_investing_make_available_opened');
    try {
      await LedgerTransferSheet.show(context, walletId: walletId);
    } finally {
      if (mounted) _updateDraft(() => _ledgerBusy = false);
    }
  }

  /// The market order for the ticket as it is now (placeSpotOrder or
  /// openPosition).
  _SlipOrder _marketOrder(String walletId, String cloid) {
    final trading = ref.read(hyperliquidTradingProvider.notifier);
    final isLong = _isLong;
    final marginUsd = _marginUsd;
    final slippagePct = _slippagePct;
    final source = widget.source;
    if (isSpot) {
      return _SlipOrder(
        HlIntents.spotOrder(
          walletId: walletId,
          market: market,
          isBuy: isLong,
          usd: marginUsd,
          slippagePct: slippagePct,
        ),
        (grant) => trading.placeSpotOrder(
          market: market,
          isBuy: isLong,
          usd: marginUsd,
          slippagePct: slippagePct,
          source: source,
          cloid: cloid,
          grant: grant,
        ),
      );
    }
    final leverage = _leverage;
    final isCross = _isCross;
    final takeProfitPx = _attachTpSl ? _parse(_tpController) : null;
    final stopLossPx = _attachTpSl ? _parse(_slController) : null;
    return _SlipOrder(
      HlIntents.openPosition(
        walletId: walletId,
        market: market,
        isLong: isLong,
        marginUsd: marginUsd,
        leverage: leverage,
        slippagePct: slippagePct,
        isCross: isCross,
        takeProfitPx: takeProfitPx,
        stopLossPx: stopLossPx,
      ),
      (grant) => trading.openPosition(
        market: market,
        isLong: isLong,
        marginUsd: marginUsd,
        leverage: leverage,
        slippagePct: slippagePct,
        isCross: isCross,
        takeProfitPx: takeProfitPx,
        stopLossPx: stopLossPx,
        source: source,
        cloid: cloid,
        changeOpenPosition: _leverageTouched,
        grant: grant,
      ),
    );
  }

  /// The Limit or Pro order for the ticket as it is now, or null in Market
  /// mode.
  _SlipOrder? _advancedOrder(String walletId, double mid, String cloid) {
    final trading = ref.read(hyperliquidTradingProvider.notifier);
    final lev = isSpot ? 1 : _leverage;
    final entry = _entryPx(mid);
    final isLong = _isLong;
    final marginUsd = _marginUsd;
    final isCross = _isCross;
    final reduceOnly = _reduceOnly;
    final source = widget.source;
    switch (_mode) {
      case _OrderMode.market:
        return null;
      case _OrderMode.limit:
        final tif = _tif;
        final postOnly = _postOnly;
        final takeProfitPx =
            (_attachTpSl && !reduceOnly) ? _parse(_tpController) : null;
        final stopLossPx =
            (_attachTpSl && !reduceOnly) ? _parse(_slController) : null;
        return _SlipOrder(
          HlIntents.limit(
            walletId: walletId,
            market: market,
            isLong: isLong,
            marginUsd: marginUsd,
            leverage: lev,
            isCross: isCross,
            px: entry,
            tif: tif,
            postOnly: postOnly,
            reduceOnly: reduceOnly,
            takeProfitPx: takeProfitPx,
            stopLossPx: stopLossPx,
          ),
          (grant) => trading.placeLimit(
            market: market,
            isLong: isLong,
            marginUsd: marginUsd,
            leverage: lev,
            isCross: isCross,
            px: entry,
            tif: tif,
            postOnly: postOnly,
            reduceOnly: reduceOnly,
            takeProfitPx: takeProfitPx,
            stopLossPx: stopLossPx,
            source: source,
            cloid: cloid,
            changeOpenPosition: _leverageTouched,
            grant: grant,
          ),
        );
      case _OrderMode.pro:
        switch (_proType) {
          case _ProType.scale:
            final startPx = _parse(_startPxController) ?? entry;
            final endPx = _parse(_endPxController) ?? entry;
            final count = (_parseInt(_countController) ?? 5).clamp(2, 50);
            return _SlipOrder(
              HlIntents.scale(
                walletId: walletId,
                market: market,
                isLong: isLong,
                totalUsd: marginUsd,
                startPx: startPx,
                endPx: endPx,
                count: count,
                leverage: lev,
                isCross: isCross,
                reduceOnly: reduceOnly,
              ),
              (grant) => trading.placeScale(
                market: market,
                isLong: isLong,
                totalUsd: marginUsd,
                startPx: startPx,
                endPx: endPx,
                count: count,
                leverage: lev,
                isCross: isCross,
                reduceOnly: reduceOnly,
                source: source,
                changeOpenPosition: _leverageTouched,
                grant: grant,
              ),
            );
          case _ProType.twap:
            final minutes = (_parseInt(_twapMinutesController) ?? 30).clamp(
                HyperliquidExchangeService.minTwapMinutes,
                HyperliquidExchangeService.maxTwapMinutes);
            final randomize = _randomizeTwap;
            return _SlipOrder(
              HlIntents.twap(
                walletId: walletId,
                market: market,
                isLong: isLong,
                marginUsd: marginUsd,
                leverage: lev,
                isCross: isCross,
                durationMinutes: minutes,
                randomize: randomize,
                reduceOnly: reduceOnly,
              ),
              (grant) => trading.placeTwap(
                market: market,
                isLong: isLong,
                marginUsd: marginUsd,
                leverage: lev,
                isCross: isCross,
                durationMinutes: minutes,
                randomize: randomize,
                reduceOnly: reduceOnly,
                source: source,
                changeOpenPosition: _leverageTouched,
                grant: grant,
              ),
            );
          case _ProType.stopLimit:
          case _ProType.stopMarket:
          case _ProType.takeLimit:
          case _ProType.takeMarket:
            final isMarket = _proType == _ProType.stopMarket ||
                _proType == _ProType.takeMarket;
            final tpsl = (_proType == _ProType.takeLimit ||
                    _proType == _ProType.takeMarket)
                ? 'tp'
                : 'sl';
            final trig = _parse(_triggerController) ?? entry;
            final szCoin = sizeFromUsd(
              usd: marginUsd * lev,
              px: trig > 0 ? trig : mid,
              szDecimals: market.szDecimals,
            );
            final limitPx = isMarket ? null : _parse(_stopLimitController);
            return _SlipOrder(
              HlIntents.trigger(
                walletId: walletId,
                market: market,
                isLong: isLong,
                size: szCoin,
                triggerPx: trig,
                isMarket: isMarket,
                tpsl: tpsl,
                limitPx: limitPx,
                reduceOnly: reduceOnly,
              ),
              (grant) => trading.placeTrigger(
                market: market,
                isLong: isLong,
                size: szCoin,
                triggerPx: trig,
                isMarket: isMarket,
                tpsl: tpsl,
                limitPx: limitPx,
                reduceOnly: reduceOnly,
                source: source,
                cloid: cloid,
                grant: grant,
              ),
            );
        }
    }
  }

  /// Accepted is distinct from filled; show a receipt without inventing a fill.
  void _onRestingAccepted() {
    if (_completed || !mounted) return;
    _completed = true;
    _fillSub?.cancel();
    final amount = formatPolyAmount(ref, _marginUsd);
    final nav = Navigator.of(context, rootNavigator: true);
    HlOrderSlipSheet.popAllSheetsDownToHost(nav);
    pushKuteSuccessOverlay(
      navigator: nav,
      overlay: HlOrderAcceptedOverlay(
          coin: market.coin, market: market, amount: amount),
    );
  }

  /// The fills of [result]'s order, waiting a moment for the stream when
  /// they have not all arrived. Fewer than the filled size leaves the
  /// receipt without a realised P&L rather than a partial one.
  Future<List<HlFill>> _fillsOf(HlOrderResult result,
      {Duration wait = const Duration(milliseconds: 1500)}) async {
    final oid = result.oid;
    if (oid == null) return const [];
    List<HlFill> mine() => _orderFills.where((f) => f.oid == oid).toList();
    final deadline = DateTime.now().add(wait);
    while (mounted &&
        hlRealizedFromFills(mine(), result.filledSz) == null &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return mine();
  }

  void _onFilled({
    required double sizeFilled,
    required double avgPx,
    Iterable<HlFill> fills = const [],
  }) {
    if (_completed || !mounted) return;
    _completed = true;
    _fillSub?.cancel();
    // What the fill did to the position held when the order went out:
    // the same plan as the slip, sized on what actually filled.
    final filledPlan = isSpot
        ? null
        : hlFilledPlan(_sentPlan,
            sizeFilled: sizeFilled, szDecimals: market.szDecimals);
    final nav = Navigator.of(context, rootNavigator: true);
    HlOrderSlipSheet.popAllSheetsDownToHost(nav);
    pushHlOrderPlacedOverlay(
      navigator: nav,
      coin: market.coin,
      market: market,
      isLong: _isLong,
      leverage: isSpot ? 1 : _leverage,
      isSpot: isSpot,
      sizeFilled: sizeFilled,
      avgPx: avgPx,
      notionalUsd: sizeFilled * avgPx,
      positionPlan: filledPlan,
      realizedPnl: filledPlan == null
          ? null
          : hlRealizedFromFills(fills.toList(), sizeFilled),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) => _buildTicket(context, ref);

  Widget _buildTicket(BuildContext context, WidgetRef ref,
      {bool advanced = false}) {
    final base = context.colors;
    final sideColor = _isLong ? greenColor : redColor;
    // The compact ticket is painted in the side color; the full-screen
    // Advanced page keeps the app palette (user decision: only sheets
    // wear the direction, full-screen flows stay neutral).
    final tinted = !advanced;
    final c = tinted ? sideTintPalette(base, sideColor) : base;
    final appTheme = Theme.of(context);
    final tintedTheme = appTheme.copyWith(extensions: [c]);
    // Validation copy: white on the tinted fill (red on red is unreadable).
    final errorColor = tinted ? c.error : redColor;
    final mid = _referenceMid(ref);
    // Amount companions follow live denomination changes on either surface.
    ref.watch(settingsProvider);

    // Balances. A Ledger ticket reads the wallet-scoped account and never
    // the hot providers; everything downstream is the same ticket.
    final ledgerWalletId = widget.ledgerWalletId;
    final ledgerAccount = ledgerWalletId == null
        ? null
        : ref.watch(ledgerHlAccountProvider(ledgerWalletId)).valueOrNull;
    // Until the account was read the balances below are 0 for "unknown":
    // the button waits instead of offering a deposit on them.
    final balanceKnown = ledgerWalletId == null
        ? ref.watch(hyperliquidAccountProvider).hasValue
        : ledgerAccount != null;
    _ledgerAddress = ledgerAccount?.address;
    final ledgerSnapshot = ledgerAccount?.account;
    final withdrawable = _isLedger
        ? (market.dex.isEmpty
                ? ledgerSnapshot?.withdrawable
                : ledgerAccount?.dexAccounts[market.dex]?.withdrawable) ??
            0
        : ref.watch(hyperliquidWithdrawableProvider);
    final List<HlSpotBalance> spotBalances = _isLedger
        ? (ledgerSnapshot?.spotBalances ?? const <HlSpotBalance>[])
        : ref.watch(hyperliquidSpotBalancesProvider);
    double spotUsdc = 0;
    double heldSize = 0;
    for (final b in spotBalances) {
      if (b.coin == 'USDC') spotUsdc = b.available;
      if (b.coin == market.coin) heldSize = b.available;
    }

    // Ledger gates, watched while the ticket is open so a config change
    // closes the door under a slip someone left standing.
    final opaqueActions = !_isLedger || kLedgerHyperliquidOpaqueActionsEnabled;
    final geoAllowed = !_isLedger || ref.watch(hyperliquidGeoAllowedProvider);
    final ledgerTradingEnabled =
        !_isLedger || ref.watch(hyperliquidTradingEnabledProvider);
    final ledgerBlocked =
        _isLedger && (!opaqueActions || !geoAllowed || !ledgerTradingEnabled);

    final lev = isSpot ? 1 : _leverage;
    final entry = _entryPx(mid);
    final notional = _marginUsd * lev;
    final priceForSize = entry > 0 ? entry : mid;
    final size = priceForSize > 0
        ? sizeFromUsd(
            usd: notional, px: priceForSize, szDecimals: market.szDecimals)
        : 0.0;
    // Available balance for the % slider / insufficiency check. A Ledger
    // cannot sweep USDC between its spot and perp accounts on the way to
    // an order — the hot notifier does that silently, the device needs a
    // separate approval — so each side counts only its own account there.
    final double available;
    if (isSpot) {
      available =
          _isLong ? spotUsdc + (_isLedger ? 0 : withdrawable) : heldSize * mid;
    } else {
      available = withdrawable + (_isLedger ? 0 : spotUsdc);
    }

    // Spread guard from the order book (market orders only).
    final spreadPct = ref
        .watch(hyperliquidOrderbookProvider(market.wireCoin))
        .valueOrNull
        ?.spreadPct;
    final wideSpread =
        _mode == _OrderMode.market && spreadPct != null && spreadPct >= 1.0;
    final verySpread =
        _mode == _OrderMode.market && spreadPct != null && spreadPct >= 3.0;

    // ── Validation ─────────────────────────────────────────────────
    final int? scaleCount = _isScale ? _parseInt(_countController) : null;
    final int? twapMinutes = _isTwap ? _parseInt(_twapMinutesController) : null;

    // Min-notional check (skipped when reduce-only — closing dust is fine).
    final legDivisor = _isScale ? (scaleCount ?? 1).clamp(1, 50) : 1;
    final legNotional = notional / legDivisor;
    // Judge the order we will actually SEND. Size is floored to the
    // market's step, so a leg worth exactly the minimum before flooring
    // is worth less than it after, and the venue rejects what the
    // screen had already called valid. BTC steps in 0.00001, about 85
    // cents near 85,000, so ten dollars floors to about 9.33 and comes
    // back "below minimum" from Hyperliquid with nothing on our side
    // having warned.
    final legPx = _lastMid ?? (market.midPx > 0 ? market.midPx : market.markPx);
    final legSize = legPx > 0
        ? sizeFromUsd(
            usd: legNotional, px: legPx, szDecimals: market.szDecimals)
        : 0.0;
    final sentLegNotional = legSize * legPx;
    // The floor in the amount the person types (margin on a perp, dollars
    // on spot) for the order this ticket would actually send, so the
    // minimum on the available line, the minimum button and this check
    // are one figure. A market sell or short is valued at its slippage
    // price, where the venue checks it.
    final openMinUsd = _orderMinimumUsd(px: legPx);
    // The position already held here: an order on its other side nets
    // against it (one position per market on Hyperliquid). A reduce or a
    // close is an exit, with no venue minimum and nothing to fund; a flip
    // needs only what it opens past the position to meet the minimum.
    if (!_isLedger && !isSpot) ref.watch(hyperliquidPerpPositionsProvider);
    final plan = _positionPlanFor(legSize);
    _positionEffectName = isSpot ? null : plan.effect.name;
    final netPlan =
        _netsAgainstPosition ? plan : const HlPositionPlan.open();
    final exitPlan = netPlan.isExit;
    final minAmountUsd = netPlan.effect == HlPositionEffect.flip
        ? _orderMinimumUsd(px: legPx, baseSize: netPlan.heldSize)
        : openMinUsd;
    final belowMin = !_reduceOnly &&
        !exitPlan &&
        notional > 0 &&
        (_isScale
            ? sentLegNotional < HyperliquidConstants.minOrderNotionalUsd - 1e-9
            : _marginUsd < minAmountUsd - 1e-9);
    final sizeZero = _marginUsd > 0 && size <= 0;

    // Per-type price/param validity.
    String? paramError;
    if (_mode == _OrderMode.limit) {
      if (_parse(_priceController) == null) {
        paramError = _strings.slipEnterLimitPrice;
      }
    } else if (_isScale) {
      final s = _parse(_startPxController);
      final e = _parse(_endPxController);
      if (s == null || e == null) {
        paramError = _strings.slipEnterStartEndPrices;
      } else if ((scaleCount ?? 0) < 2) {
        paramError = _strings.slipScaleMinOrders;
      }
    } else if (_isTwap) {
      if (twapMinutes == null ||
          twapMinutes < HyperliquidExchangeService.minTwapMinutes ||
          twapMinutes > HyperliquidExchangeService.maxTwapMinutes) {
        // Exchange rule: 5 minutes to 7 days.
        paramError = _strings.slipTwapDurationRange;
      }
    } else if (_isTriggerType) {
      if (_parse(_triggerController) == null) {
        paramError = _strings.slipEnterTriggerPrice;
      } else if ((_proType == _ProType.stopLimit ||
              _proType == _ProType.takeLimit) &&
          _parse(_stopLimitController) == null) {
        paramError = _strings.slipEnterLimitPrice;
      }
    }

    // TP/SL sanity (opens only).
    if (_isOpening && _attachTpSl) {
      final tp = _parse(_tpController);
      final sl = _parse(_slController);
      if (tp != null &&
          ((_isLong && tp <= entry) || (!_isLong && tp >= entry))) {
        paramError = _isLong
            ? _strings.slipTpAboveEntry
            : _strings.slipTpBelowEntry;
      } else if (sl != null &&
          ((_isLong && sl >= entry) || (!_isLong && sl <= entry))) {
        paramError = _isLong
            ? _strings.slipSlBelowEntry
            : _strings.slipSlAboveEntry;
      }
    }

    // Trailing stop sanity (opening market orders only).
    if (_trailingAvailable && _attachTrailing && paramError == null) {
      final distance = _parse(_trailDistanceController);
      if (distance == null ||
          distance <= 0 ||
          (_trailPercent && distance >= 100)) {
        paramError = _trailPercent
            ? _strings.slipTrailingBelow100
            : _strings.slipEnterTrailingDistance;
      } else if (_trailActivate &&
          (_parse(_trailActivationController) ?? 0) <= 0) {
        paramError = _strings.slipEnterActivationPrice;
      }
    }

    // Insufficiency (skipped for reduce-only and for an order that only
    // reduces or closes the held position — you're closing, not funding).
    bool insufficient = false;
    String? insufficientLine;
    double transferFromPerp = 0;
    if (!_reduceOnly && !exitPlan) {
      if (isSpot) {
        if (_isLong) {
          insufficient = _marginUsd > available + 1e-6;
          if (!_isLedger && !insufficient && _marginUsd > spotUsdc + 1e-6) {
            transferFromPerp = _marginUsd - spotUsdc;
          }
        } else {
          final heldValue = heldSize * mid;
          insufficient = _marginUsd > heldValue + 1e-6;
          if (insufficient) {
            insufficientLine = heldSize > 0
                ? _strings.slipYouHold(formatHlSize(heldSize), market.coin,
                    formatHlUsd(heldValue))
                : _strings.slipYouHoldNone(market.coin);
          }
        }
      } else {
        // A flip frees the held position's margin as it closes it: only
        // the share it opens past the position needs funding.
        final fundedMargin = netPlan.effect == HlPositionEffect.flip &&
                netPlan.orderSize > 0
            ? _marginUsd * netPlan.remainder / netPlan.orderSize
            : _marginUsd;
        insufficient = fundedMargin > available + 1e-6;
      }
    }
    // Perp margin parked in the Ledger's spot account: the ticket offers
    // the move instead of a deposit, because the money is already there.
    final ledgerPrepareSpot = _isLedger &&
        !isSpot &&
        !_reduceOnly &&
        _ledgerAddress != null &&
        spotUsdc >= 0.01 &&
        insufficient;
    // Every open needs its margin before the order can be placed, a
    // resting limit as much as a market order: when the balance cannot
    // cover it the one button is the deposit door, never a dead
    // investment label (user decision).
    final showDepositCta = (insufficient || available <= 0) &&
        (_isLong || !isSpot) &&
        !_reduceOnly &&
        !exitPlan &&
        !ledgerBlocked &&
        !ledgerPrepareSpot &&
        !_ledgerPending;

    // Everything but the amount: also what the empty ticket's minimum
    // button needs to be live.
    final formReadyButAmount = mid > 0 &&
        paramError == null &&
        (!verySpread || _acceptWideSpread);
    final formValid =
        _marginUsd > 0 && !belowMin && !sizeZero && formReadyButAmount;
    // Stale-price guard applies only where we quote a live mid.
    final priceStaleBlocks =
        _priceStale && (_mode == _OrderMode.market || _isTwap);
    final advancedBlock = _usesAdvanced
        ? ref.watch(runtimeCapabilitiesProvider).blockReason('trading.advanced')
        : null;
    // A new position the policy (or the venue) refuses here: the confirm
    // stays on screen, disabled, with the reason above it. Exits never.
    final openBlock = _isExitOrder || exitPlan ? null : _openGateMessage;
    // The venue may refuse growing a position on a market at its
    // open-interest cap: say so before the order, not after.
    final oiCapped = !isSpot &&
        !_isExitOrder &&
        !exitPlan &&
        !_reduceOnly &&
        (ref
                .watch(hyperliquidOiCappedProvider(market.dex))
                .valueOrNull
                ?.contains(market.wireCoin) ??
            false);
    if (oiCapped && !_oiCapWarned) {
      _oiCapWarned = true;
      TrackingService.track('hyperliquid_oi_cap_warning_shown', params: {
        'coin': market.coin,
        ...VenueAnalytics.hlAssetParams(market.coin, kind: 'perp'),
        'wallet_kind': _isLedger ? 'ledger' : 'hot',
      });
    }
    // The person moved leverage or margin mode on a market where they hold
    // a position: the order will change that position's settings too.
    final heldPosition = _leverageTouched ? _openPosition() : null;
    final changesPosition = heldPosition != null &&
        (heldPosition.leverageValue != _leverage ||
            (heldPosition.isCross && !market.onlyIsolated) != _isCross);
    final gatesOpen = advancedBlock == null &&
        openBlock == null &&
        !insufficient &&
        !_isPlacing &&
        !_preparing &&
        !priceStaleBlocks &&
        !ledgerBlocked &&
        !_ledgerBusy &&
        !_ledgerPending &&
        (!_isLedger || _ledgerAddress != null);
    final canConfirm = formValid && gatesOpen;
    // Nothing typed yet on a market order that has a minimum: the button
    // is the order at that minimum, and a tap places exactly that.
    final placesMinimum = _marginUsd <= 0 &&
        _mode == _OrderMode.market &&
        !_reduceOnly &&
        !netPlan.opposes &&
        minAmountUsd > 0;
    // Funding is navigation, so it does not depend on a complete order form.
    // Order validation still applies when the user returns with funds.
    final canDeposit = showDepositCta;
    // While the policy withholds `hyperliquid.deposit` the door stays
    // listed, disabled, wearing its reason ([CapabilityBlockNote]).
    // Watched, so it follows the admin switch live.
    final depositBlock = canDeposit
        ? ref
            .watch(runtimeCapabilitiesProvider)
            .blockReason('hyperliquid.deposit')
        : null;
    // A hot deposit into Investing already on its way: the button says so
    // instead of offering a second one while it lands.
    SlipFunding? funding;
    double hlShortfall = 0;
    if (!_isLedger && canDeposit) {
      hlShortfall = ShortfallRules.shortfallUsd(
          requiredUsd: _hlRequiredUsd(), readyUsd: _hlReadyUsd());
      funding = slipFunding(shortfallUsd: hlShortfall);
    } else if (!_isLedger) {
      slipFundingCovered();
    }
    // A shut open keeps its own disabled door and note; a deposit already
    // on its way still reads as incoming when new deposits are withheld,
    // only "Add more" goes.
    final incoming =
        funding != null && funding.isIncoming && openBlock == null;

    // The one line a Ledger carries that the hot ticket cannot tell the
    // user: what the device is about to ask for, or why it is shut. It
    // sits where Home puts its own inline lines, in Home's type.
    String? ledgerNote;
    if (_isLedger) {
      final l = context.l10n;
      if (!opaqueActions) {
        ledgerNote = l.ledgerOpaqueActionsUnavailable;
      } else if (!geoAllowed) {
        ledgerNote = l.ledgerErrorGeoBlocked;
      } else if (!ledgerTradingEnabled) {
        ledgerNote = l.ledgerErrorTradingDisabled;
      } else if (_ledgerPending) {
        ledgerNote = l.ledgerPendingStatus;
      } else if (ledgerSnapshot == null) {
        ledgerNote = l.ledgerPartialLoad;
      } else {
        ledgerNote = l.ledgerOrderStepsNote;
      }
    }

    // While the order is in flight the ticket STAYS. It used to be
    // replaced by a centered card, so the moment someone committed money
    // the numbers they had just checked vanished and a box appeared in
    // their place. The Predictions slip does the opposite: the slip holds
    // still, the one button turns into a spinner, and the person waits on
    // the screen they were already reading. This does the same, so the
    // two venues behave alike at the one moment that matters most.
    final form = Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Side switch, the Long/Short twin of the bet slip's Yes/No
          // (user decision). The +$ quick-amount row is gone.
          if (!isSpot) ...[
            _buildSideToggle(),
            SizedBox(height: 16.h),
          ],
          _buildAmountField(c, available,
              keypad: !advanced,
              // Against a held position only a flip has a minimum.
              minAmountUsd: _reduceOnly ||
                      _isScale ||
                      (netPlan.opposes &&
                          netPlan.effect != HlPositionEffect.flip)
                  ? null
                  : minAmountUsd,
              belowMinimum: belowMin,
              positionNote: _positionNote(netPlan)),
          SizedBox(height: 20.h),
          if (advanced)
            ..._buildAdvancedSections(
              c,
              mid,
              entry,
              notional,
              size,
              scaleCount,
              transferFromPerp,
              hasFunds: available > 0 || _reduceOnly,
            )
          else ...[
            _buildEssentialSummary(
              c,
              notional,
              transferFromPerp,
              hasFunds: available > 0 || _reduceOnly,
              explain: false,
              entry: entry,
              size: size,
            ),
            SizedBox(height: 16.h),
            _buildAdvancedEntry(c),
          ],

          if (oiCapped) ...[
            SizedBox(height: 10.h),
            Text(
              context.l10n.hlSlipOiCapWarning(market.coin),
              style: TextStyle(
                  color: c.textSecondary, fontSize: 13.sp, height: 1.4),
            ),
          ],
          if (changesPosition) ...[
            SizedBox(height: 10.h),
            Text(
              context.l10n.hlSlipChangesPosition(market.coin),
              style: TextStyle(
                  color: c.textSecondary, fontSize: 13.sp, height: 1.4),
            ),
          ],

          // Spread warning (market; ≥3% needs the extra confirm).
          if (wideSpread)
            _buildSpreadWarning(c, spreadPct, verySpread, advanced: advanced),

          // Inline validation / error copy. On the simple ticket the
          // minimum lives on the available line under the figure (red
          // while the amount is under it), so it is not said twice here.
          if (belowMin && (advanced || _isScale)) ...[
            SizedBox(height: 10.h),
            Text(
              _isScale
                  ? context.l10n.investingMinimumScaleOrder(
                      formatHlUsd(HyperliquidConstants.minOrderNotionalUsd))
                  : context.l10n
                      .investingMinimumOrder(formatHlUsd(minAmountUsd)),
              style: TextStyle(color: errorColor, fontSize: 13.sp),
            ),
          ] else if (sizeZero) ...[
            SizedBox(height: 10.h),
            Text(
              context.l10n.amountIsTooSmall,
              style: TextStyle(color: errorColor, fontSize: 13.sp),
            ),
          ] else if (paramError != null) ...[
            SizedBox(height: 10.h),
            Text(
              paramError,
              style: TextStyle(color: errorColor, fontSize: 13.sp),
            ),
          ],
          if (insufficientLine != null) ...[
            SizedBox(height: 10.h),
            Text(
              insufficientLine,
              style: TextStyle(color: c.textSecondary, fontSize: 13.sp),
            ),
          ],
          if (ledgerNote != null) ...[
            SizedBox(height: 10.h),
            Text(
              ledgerNote,
              style: TextStyle(
                  color: c.textSecondary, fontSize: 13.sp, height: 1.4),
            ),
          ],
          if (_errorText != null) ...[
            SizedBox(height: 10.h),
            HlTradeErrorNotice(message: _errorText!, error: _errorCause),
          ],
          SizedBox(height: 16.h),
        ],
      ),
    );
    // One button in every state, the way Home has it: the trade, the
    // deposit door when there is nothing to trade with, the Ledger's own
    // move when its margin sits in the other account, or Close while the
    // device gate is shut or a submission is still in the air.
    final String primaryLabel;
    final VoidCallback? primaryAction;
    final bool primaryNeutral;
    // What the button is, for its cross-fade (presentation only).
    final String primaryKind;
    if (ledgerBlocked || _ledgerPending) {
      primaryKind = 'close';
      primaryLabel = context.l10n.ledgerApprovalClose;
      primaryAction = _ledgerBusy ? null : () => Navigator.of(context).pop();
      primaryNeutral = true;
    } else if (!balanceKnown &&
        !_isPlacing &&
        !_preparing &&
        !_ledgerBusy &&
        !_depositDoorBusy) {
      // The account is still being read: a disabled wait, never the
      // deposit door on a balance that only reads 0 for now.
      primaryKind = 'loading';
      primaryLabel = context.l10n.loadingAccount;
      primaryAction = null;
      primaryNeutral = true;
    } else if (ledgerPrepareSpot) {
      primaryKind = 'prepare';
      primaryLabel = context.l10n.ledgerPmMakeAvailableCta;
      primaryAction = _ledgerBusy ? null : _ledgerMakeFundsAvailable;
      primaryNeutral = true;
    } else if (incoming) {
      primaryKind = 'incoming';
      primaryLabel = context.l10n
          .slipDepositIncoming(formatHlUsd(funding.incomingUsd));
      primaryAction = null;
      primaryNeutral = true;
    } else if (canDeposit) {
      // Insufficient balance for this trade: open the Move sheet locked
      // to Trading with the trade's margin prefilled (user decision: one
      // deposit door, value already filled in). A Ledger ticket pins the
      // move to its own account.
      primaryKind = 'deposit';
      primaryLabel = context.l10n.depositToTrade;
      // Funding a position that cannot be opened here would only strand
      // the money, so the door shuts with the open gate too.
      primaryAction =
          depositBlock == null && openBlock == null && !_depositDoorBusy
              ? _openDepositDoor
              : null;
      primaryNeutral = true;
    } else if (belowMin && !_isScale && _marginUsd > 0 && minAmountUsd > 0) {
      // An amount under the venue minimum: the button names the minimum
      // the available line shows, and a tap fills it the way Max does.
      // It stays the trade button (same face, no cross-fade); only what
      // it says and does changes until the amount clears the floor.
      primaryKind = 'trade';
      primaryLabel =
          context.l10n.amountMinimumInline(formatHlUsd(minAmountUsd));
      primaryAction = _isPlacing || _preparing || _ledgerBusy
          ? null
          : () => _fillAmountChip(minAmountUsd, 'min');
      primaryNeutral = false;
    } else if (placesMinimum) {
      primaryKind = 'trade';
      primaryLabel =
          _positionCtaLabel(netPlan, amountUsd: minAmountUsd) ??
              _ctaLabel(amountUsd: minAmountUsd);
      primaryAction = formReadyButAmount && gatesOpen
          ? () => _placeMinimum(minAmountUsd)
          : null;
      primaryNeutral = false;
    } else {
      primaryKind = 'trade';
      primaryLabel = _positionCtaLabel(netPlan) ?? _ctaLabel();
      primaryAction = canConfirm ? _handleConfirm : null;
      primaryNeutral = false;
    }
    // The build after the empty ticket's button wrote the minimum: place
    // it through the normal confirm, or open the funding it needs (the
    // deposit door, the Ledger's move), as one more tap on this button
    // would. Anything else (a missing price, the wide-spread confirm)
    // stays on screen for the person.
    if (_placeMinimumOnBuild) {
      _placeMinimumOnBuild = false;
      final VoidCallback? next = primaryKind == 'trade'
          ? (canConfirm && !belowMin ? _handleConfirm : null)
          : primaryKind == 'deposit' || primaryKind == 'prepare'
              ? primaryAction
              : null;
      if (next != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) next();
        });
      }
    }
    // The greater of a comfortable gap and the system inset, never the
    // two added together. On a phone with a gesture bar the inset is
    // already the gap, so adding 16 on top of it pushed the button
    // visibly up the sheet, worst on Android where a three button nav
    // bar is half again as tall as an iOS home indicator. A phone with
    // no inset at all still gets its 16.
    final action = Padding(
      padding: EdgeInsets.fromLTRB(
        20.w,
        8.h,
        20.w,
        advanced ? 16.h : math.max(16.h, MediaQuery.of(context).padding.bottom),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // One note per distinct reason: a region block that shuts both
          // the trade and the deposit says so once.
          if (openBlock != null) CapabilityBlockNote(openBlock),
          if (advancedBlock != null &&
              !primaryNeutral &&
              advancedBlock != openBlock)
            CapabilityBlockNote(advancedBlock),
          // A shut open already explains the disabled deposit door.
          if (depositBlock != null && openBlock == null && !incoming)
            CapabilityBlockNote(depositBlock),
          if (!incoming && (funding?.failed ?? false))
            const SlipDepositFailedNote(),
          if (priceStaleBlocks)
            Padding(
              padding: EdgeInsets.only(bottom: 8.h),
              child: Text(
                context.l10n.slipWaitingForPrice,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: c.textTertiary,
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          // Deposit branch wears the canonical dark primary
          // tier (navigational door — green stays reserved
          // for the actual trade confirm, user decision);
          // the trade confirm keeps the directional side
          // color sourced from the market pair tokens.
          // On the tinted sheet the one action inverts: a white
          // button lettered in the side color, because a green
          // button on a green sheet stops reading as the thing
          // to do. Deposit keeps a neutral label there, so the
          // funding door never wears the trade's direction.
          // The button cross-fades when it changes what it is (the
          // deposit door giving way to the trade once a deposit lands),
          // never as its amount changes.
          ArrivalSwitcher(
            state: primaryKind,
            alignment: Alignment.bottomCenter,
            animateSize: false,
            child: DecoratedBox(
              // On the tinted sheet the white button is only a shade away
              // from the veils around it, so it gets a soft drop shadow to
              // lift clear of the fill. Dropped while the action is
              // disabled, where the button fades to 0.35 and a full-weight
              // shadow would read as a rendering fault.
              decoration: BoxDecoration(
                borderRadius: AppRadius.buttonBorder,
                boxShadow: tinted && primaryAction != null
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : null,
              ),
              child: AppButton(
                text: primaryLabel,
                onPressed: primaryAction,
                isLoading: _ledgerBusy ||
                    _isPlacing ||
                    _preparing ||
                    _depositCalculating ||
                    primaryKind == 'loading',
                loadingLabel: primaryKind == 'loading'
                    ? context.l10n.loadingAccount
                    : _depositCalculating && primaryKind == 'deposit'
                        ? context.l10n.feeUiCalculating
                        : null,
                color: c.textPrimary,
                textColor: primaryNeutral
                    ? contrastingOnColor(c.textPrimary)
                    : sideColor,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (incoming)
            SlipIncomingDepositNote(
              onAddMore: funding.state == SlipFundingState.incomingShort &&
                      depositBlock == null
                  ? () => _addMoreDeposit(hlShortfall, funding!.incomingUsd)
                  : null,
            ),
        ],
      ),
    );
    // Advanced pins the action as a bottom bar, like the market sheet's
    // Invest / Short bar, so the form scrolls underneath it.
    // While the device holds the flow (or the gate is shut) the ticket is
    // read-only: the numbers behind an approval must not move under it.
    // Same lock the bet slip puts on its Ledger path.
    // Placing locks the form for the same reason a Ledger prompt does:
    // the numbers behind a submitted order must not move under it.
    final ledgerLocked = _ledgerBusy ||
        _depositCalculating ||
        _ledgerPending ||
        ledgerBlocked ||
        _isPlacing ||
        _preparing;
    final ticket = advanced
        ? Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  key: const ValueKey('hl-advanced-form-scroll'),
                  physics: const ClampingScrollPhysics(),
                  primary: false,
                  // No manual keyboard padding here: the page is a Scaffold
                  // and already resizes for the inset, so adding it again
                  // would leave dead space under the form.
                  child: IgnorePointer(ignoring: ledgerLocked, child: form),
                ),
              ),
              KuteStickyActionBar(child: action),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(c),
              Flexible(
                  child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                primary: false,
                child: IgnorePointer(ignoring: ledgerLocked, child: form),
              )),
              // The keypad and the one action are pinned: the form above
              // scrolls, these two never move out of thumb reach. The
              // tinted Theme wrapper below hands the keypad the sheet's
              // palette, so it reads as part of the green / red fill.
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: IgnorePointer(
                  ignoring: ledgerLocked,
                  child: AmountKeypad(
                    value: _amountController.text,
                    maxDecimals: 2,
                    onChanged: _onKeypadAmount,
                  ),
                ),
              ),
              action,
            ],
          );
    if (advanced) {
      return PopScope(
        canPop: !_isPlacing,
        child: Scaffold(
          backgroundColor: base.background,
          appBar: AppBar(
            backgroundColor: base.background,
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            centerTitle: true,
            leading: KuteBackButton(
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            title: Text(
              context.l10n.slipAdvancedTitle(_sideWord(), market.coin),
              style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w600),
            ),
          ),
          body: KeyboardDismissOnTap(
            child: SafeArea(top: false, child: ticket),
          ),
        ),
      );
    }
    return KeyboardDismissOnTap(
      child: Theme(
        // Shared widgets inside the sheet read `context.colors`; handing
        // them the tinted palette keeps them legible without forking them.
        data: tintedTheme,
        child: Container(
          padding:
              EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          // Flipping side re-paints the sheet rather than snapping.
          child: AnimatedContainer(
            duration: MediaQuery.of(context).disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: sideColor,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
              border: Border(top: BorderSide(color: c.border)),
            ),
            // Top inset only, so the action block below is the single
            // place that decides the gap under the button. SafeArea
            // zeroes the bottom padding it consumes for everything
            // inside it, so a PlatformSafeArea here left the action
            // block reading zero on Android and the real inset on iOS,
            // and the one expression down there could not mean the same
            // thing on both.
            child: SafeArea(
              bottom: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: (MediaQuery.sizeOf(context).height * 0.92 -
                          MediaQuery.viewInsetsOf(context).bottom)
                      .clamp(0.0, double.infinity),
                ),
                child: ticket,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Section builders ────────────────────────────────────────────────

  /// Opens the full-screen editor without expanding the simple ticket.
  Widget _buildAdvancedEntry(AppColorsExtension c) {
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _openAdvanced,
        // A card, not a bare row: on the tinted sheet a loose row reads
        // as an orphan line, and this is a tap target.
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(14.r),
            border: Border.all(color: c.borderSubtle, width: 0.5),
          ),
          child: Row(
            children: [
              Icon(Icons.tune_rounded, size: 20.sp, color: c.textSecondary),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.l10n.advanced,
                        style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w600)),
                    if (_hasAdvancedConfiguration) ...[
                      SizedBox(height: 3.h),
                      Text(_advancedSummary(),
                          style: TextStyle(
                              color: c.textSecondary, fontSize: 14.sp)),
                    ],
                  ],
                ),
              ),
              SizedBox(width: 8.w),
              Icon(Icons.chevron_right_rounded,
                  size: 22.sp, color: c.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  bool get _hasAdvancedConfiguration =>
      _mode != _OrderMode.market ||
      _reduceOnly ||
      _attachTpSl ||
      _attachTrailing ||
      _postOnly ||
      _slippagePct != 1.0;

  String _advancedSummary() {
    final type = switch (_mode) {
      _OrderMode.market => _strings.slipMarketOrder,
      _OrderMode.limit => _strings.slipLimitOrder,
      _OrderMode.pro => _proTypeLabel(),
    };
    return [
      type,
      if (_reduceOnly) _strings.slipReduceOnly,
      if (_attachTpSl) _strings.slipTakeProfitStopLoss,
      if (_attachTrailing) _strings.investingTrailingStop,
      if (_postOnly) _strings.slipPostOnly,
      if (_mode == _OrderMode.market && _slippagePct != 1.0)
        _strings.slipMaxSlippageSummary(_slippagePct.toStringAsFixed(1)),
    ].join(' · ');
  }

  String _proTypeLabel() {
    switch (_proType) {
      case _ProType.scale:
        return _strings.slipScaleOrder;
      case _ProType.stopLimit:
        return _strings.slipStopLimit;
      case _ProType.stopMarket:
        return _strings.slipStopMarket;
      case _ProType.takeLimit:
        return _strings.slipTakeLimit;
      case _ProType.takeMarket:
        return _strings.slipTakeMarket;
      case _ProType.twap:
        return _strings.slipTwapOrder;
    }
  }

  /// Is the rare-controls group open? Defaults to open whenever the
  /// ticket already carries a non-default option, so nothing a previous
  /// step set can hide behind a collapsed header.
  bool get _advancedOptionsExpanded =>
      _advancedOptionsOpen ??
      (_reduceOnly ||
          _postOnly ||
          _attachTpSl ||
          _tif != 'Gtc' ||
          _slippagePct != 1.0);

  /// Advanced's full control set, grouped into titled sections instead of
  /// one long stack: what people change on most tickets first (order type
  /// and its prices, then leverage), the rare switches inside a collapsed
  /// group, and the read-out last. Every control is the same widget with
  /// the same guard as before — only where it sits changed.
  List<Widget> _buildAdvancedSections(
    AppColorsExtension c,
    double mid,
    double entry,
    double notional,
    double size,
    int? scaleCount,
    double transferFromPerp, {
    required bool hasFunds,
  }) {
    final l = context.l10n;
    // Ledger supports the reviewed market flow and a separate native
    // trailing-stop ticket. Other hot-only order controls stay hidden.
    return [
      if (!_isLedger)
        _advancedSection(
          c,
          l.investingOrderType,
          [
            _buildOrderTypeControl(c),
            // Per-type price inputs (limit price / trigger / scale range /
            // TWAP duration) — revealed when a non-Market type is picked.
            _buildPriceInputs(c, mid),
            // What the chosen type does, in one sentence, right where it
            // is chosen rather than at the bottom of the sheet.
            SizedBox(height: 10.h),
            Text(
              _orderExplanation(),
              style: TextStyle(
                  fontSize: 13.sp, color: c.textSecondary, height: 1.4),
            ),
          ],
        ),

      // Margin mode + leverage (perps only).
      if (!isSpot && (!_isLedger || market.offeredMaxLeverage > 1))
        _advancedSection(
          c,
          market.offeredMaxLeverage > 1
              ? l.chartLeverage
              : l.investingMarginMode,
          [
            if (!_isLedger) ...[
              _sectionLabel(c, l.investingMarginMode),
              SizedBox(height: 8.h),
              _buildMarginModeRow(c),
            ],
            if (market.offeredMaxLeverage > 1) _buildLeverage(c),
          ],
        ),

      // The two attach options together, under the one question they
      // answer, so protecting the position is not buried among the
      // switches most tickets never touch.
      if ((!_isLedger && _isOpening) || _trailingAvailable)
        _advancedSection(
          c,
          context.l10n.slipProtectPosition,
          [
            // TP/SL attach (opening orders only).
            if (!_isLedger && _isOpening) _buildTpSlAttach(c, entry),
            // Trailing stop attach: set here, placed by the one button
            // once the opening market order fills (perps only).
            if (_trailingAvailable) _buildTrailingAttach(c),
          ],
        ),

      // Time in force, post-only, reduce-only and slippage: closed by
      // default, opened by the few who know what they are looking for.
      if (!_isLedger || _mode == _OrderMode.market)
        _advancedSection(
          c,
          context.l10n.slipExpertSettings,
          [
            if (!_isLedger) _buildOptions(c),
            if (_mode == _OrderMode.market) ...[
              if (!_isLedger) SizedBox(height: 14.h),
              _buildSlippage(c),
            ],
          ],
          collapsible: true,
          expanded: _advancedOptionsExpanded,
          onToggle: () => _updateDraft(
              () => _advancedOptionsOpen = !_advancedOptionsExpanded),
        ),

      _advancedSection(
        c,
        l.details,
        [
          _buildEssentialSummary(
            c,
            notional,
            transferFromPerp,
            hasFunds: hasFunds,
            // The sentence now sits under the order type picker.
            explain: false,
            entry: entry,
            size: size,
          ),
          SizedBox(height: 12.h),
          _buildOrderDetails(c, mid, notional, size, scaleCount),
        ],
      ),
    ];
  }

  /// A titled neutral group on the tinted page: hairline border, 16
  /// radius, generous padding, and an optional chevron that collapses the
  /// rare controls.
  Widget _advancedSection(
          AppColorsExtension c, String title, List<Widget> children,
          {bool collapsible = false,
          bool expanded = true,
          VoidCallback? onToggle}) =>
      HlAdvancedSection(
          title: title,
          collapsible: collapsible,
          expanded: expanded,
          onToggle: onToggle,
          children: children);

  Widget _sectionLabel(AppColorsExtension c, String text) => Text(
        text,
        style: TextStyle(
          color: c.textSecondary,
          fontSize: 14.sp,
          fontWeight: FontWeight.w600,
        ),
      );

  /// The house segmented track: a hairline rail, one filled pill for the
  /// selection. Shared by the order type, time in force and slippage so
  /// the page has one control language instead of rows of small chips.
  Widget _segmentTrack(AppColorsExtension c, List<Widget> segments) =>
      HlSegmentTrack(segments: segments);

  Widget _trackSegment(AppColorsExtension c,
          {required String label,
          required bool selected,
          required VoidCallback onTap,
          bool chevron = false}) =>
      HlTrackSegment(
          label: label, selected: selected, onTap: onTap, chevron: chevron);

  /// One order-type control. Market and Limit are the two people actually
  /// pick; the six rarer types live BEHIND the third segment instead of
  /// sitting beside it as a grid of chips, and that segment reads back
  /// whichever of them is armed.
  Widget _buildOrderTypeControl(AppColorsExtension c) {
    final isPro = _mode == _OrderMode.pro;
    return Padding(
      padding: EdgeInsets.only(top: 4.h),
      child: _segmentTrack(c, [
        _trackSegment(
          c,
          label: context.l10n.ledgerOrderMarketPrice,
          selected: _mode == _OrderMode.market,
          onTap: () => _onSelectMode(_OrderMode.market),
        ),
        _trackSegment(
          c,
          label: context.l10n.betOrderTypeLimit,
          selected: _mode == _OrderMode.limit,
          onTap: () => _onSelectMode(_OrderMode.limit),
        ),
        _trackSegment(
          c,
          label: isPro ? _proTypeShortLabel() : context.l10n.receiveMoreOptions,
          selected: isPro,
          chevron: true,
          onTap: _openProTypeSheet,
        ),
      ]),
    );
  }

  String _proTypeShortLabel() {
    switch (_proType) {
      case _ProType.scale:
        return _strings.slipScale;
      case _ProType.stopLimit:
        return _strings.slipStopLimit;
      case _ProType.stopMarket:
        return _strings.slipStopMarket;
      case _ProType.takeLimit:
        return _strings.slipTakeLimit;
      case _ProType.takeMarket:
        return _strings.slipTakeMarket;
      case _ProType.twap:
        return 'TWAP';
    }
  }

  /// The rarer order types, one full-width row each. Picking one arms the
  /// Pro mode through the same handlers the old chip grid used, so every
  /// default, prefill and revalidation is unchanged.
  Future<void> _openProTypeSheet() async {
    HapticFeedback.selectionClick();
    final items = <(_ProType, String)>[
      (_ProType.scale, _strings.slipScale),
      (_ProType.stopLimit, _strings.slipStopLimit),
      (_ProType.stopMarket, _strings.slipStopMarket),
      (_ProType.takeLimit, _strings.slipTakeLimit),
      (_ProType.takeMarket, _strings.slipTakeMarket),
      (_ProType.twap, 'TWAP'),
    ];
    final picked = await showHlOrderTypePicker<_ProType>(context,
        items: items, selected: _mode == _OrderMode.pro ? _proType : null);
    if (picked == null || !mounted) return;
    if (_mode != _OrderMode.pro) _onSelectMode(_OrderMode.pro);
    _onSelectProType(picked);
  }

  /// The trailing stop attach, in the same fields as the rest of More
  /// options: a checkbox, the distance, and an optional activation price.
  Widget _buildTrailingAttach(AppColorsExtension c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 14.h),
        _buildCheckbox(
          c,
          context.l10n.slipAttachTrailing,
          _attachTrailing,
          (v) {
            _settingChanged('trailing', v);
            _updateDraft(() => _attachTrailing = v);
          },
        ),
        if (_attachTrailing) ...[
          SizedBox(height: 8.h),
          Text(
            _isLong
                ? context.l10n.slipTrailingExplainLong
                : context.l10n.slipTrailingExplainShort,
            style:
                TextStyle(fontSize: 13.sp, color: c.textSecondary, height: 1.4),
          ),
          SizedBox(height: 12.h),
          _segmentTrack(c, [
            _trackSegment(
              c,
              label: context.l10n.slipPercent,
              selected: _trailPercent,
              onTap: () {
                HapticFeedback.selectionClick();
                _updateDraft(() => _trailPercent = true);
              },
            ),
            _trackSegment(
              c,
              label: context.l10n.price2,
              selected: !_trailPercent,
              onTap: () {
                HapticFeedback.selectionClick();
                _updateDraft(() => _trailPercent = false);
              },
            ),
          ]),
          SizedBox(height: 12.h),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _trailPercent
                    ? _numField(c, _NumField.trailDistance,
                        context.l10n.slipDistancePercent,
                        prefix: '%')
                    : _priceField(
                        c, _NumField.trailDistance, context.l10n.slipDistance),
              ),
              if (_trailActivate) ...[
                SizedBox(width: 10.w),
                Expanded(
                  child: _priceField(
                      c, _NumField.trailActivation,
                      context.l10n.slipActivationPrice),
                ),
              ],
            ],
          ),
          SizedBox(height: 8.h),
          _buildCheckbox(
            c,
            context.l10n.slipStartFollowingAtPrice,
            _trailActivate,
            (v) => _updateDraft(() => _trailActivate = v),
          ),
        ],
      ],
    );
  }

  HlTrailingStop? _trailingDraft() {
    final distance = _parse(_trailDistanceController);
    if (distance == null || distance <= 0) return null;
    final activation =
        _trailActivate ? _parse(_trailActivationController) : null;
    if (_trailActivate && (activation == null || activation <= 0)) return null;
    return HlTrailingStop(
        retracement: distance,
        percent: _trailPercent,
        activationPrice: activation);
  }

  /// Places the attached trailing stop for the size that just filled: a
  /// reduce-only order on the opposite side. A failure is reported on the
  /// ticket; the position itself is already open.
  Future<void> _placeAttachedTrailing(double filledSize) async {
    if (!_trailingAvailable || !_attachTrailing || !mounted) return;
    final trail = _trailingDraft();
    final size = flooredSize(filledSize, market.szDecimals);
    if (trail == null || size <= 0) return;
    final walletId = widget.ledgerWalletId ?? _spendingWalletId();
    if (walletId == null) return;
    final isBuy = !_isLong;
    try {
      await RuntimeCapabilitiesService.instance
          .ensureAllowed('trading.advanced');
      await RuntimeCapabilitiesService.instance
          .ensureAllowed('hyperliquid.close');
      final price = await ledgerHlReferencePx(market);
      trail.validate(market: market, isBuy: isBuy, referencePrice: price);
      if (!mounted) return;
      if (_isLedger) {
        final placed = await runLedgerHlTrailingStop(context, ref,
            walletId: walletId,
            market: market,
            isBuy: isBuy,
            size: size,
            trail: trail,
            reduceOnly: true,
            leverage: _leverage,
            isCross: _isCross,
            onPending: () {});
        if (placed != null) {
          // The hot path reports from the trading notifier; the Ledger
          // order never touches it.
          final lev = _leverage.clamp(1, market.maxLeverage).toInt();
          TrackingService.hyperliquidOrderPlaced(
            coin: market.coin,
            kind: 'perp',
            isBuy: isBuy,
            leverage: lev,
            marginUsd: size * price / lev,
            notionalUsd: size * price,
            orderType: 'trailing',
            reduceOnly: true,
            filled: placed.isFilled,
            walletKind: 'ledger',
            marketType: market.dex.isEmpty ? 'perp' : market.dex,
            builderFeeApplied: false,
          );
        }
      } else {
        final intent = HlIntents.trailingStop(
            walletId: walletId,
            market: market,
            isLong: isBuy,
            size: size,
            trail: trail,
            leverage: _leverage,
            isCross: _isCross,
            reduceOnly: true);
        final grant = await requireFreshAuthGrant(context, ref,
            intent: intent,
            reason: context.l10n.stepUpReasonOrder(market.coin),
            amountUsd: size * price / _leverage);
        if (grant == null || !mounted) return;
        await ref.read(hyperliquidTradingProvider.notifier).placeTrailingStop(
            market: market,
            isLong: isBuy,
            size: size,
            trail: trail,
            leverage: _leverage,
            isCross: _isCross,
            reduceOnly: true,
            grant: grant);
      }
    } catch (e) {
      TrackingService.track('hyperliquid_attached_trailing_failed', params: {
        'coin': market.coin,
        'wallet_kind': _isLedger ? 'ledger' : 'hot',
        'error_category': TrackingService.errorCategory(e),
      });
      if (mounted) {
        _updateDraft(() {
          _errorCause = e;
          _errorText = _strings.slipTrailingNotPlaced(_messageFor(e));
        });
      }
    }
  }

  Widget _buildMarginModeRow(AppColorsExtension c) {
    Widget seg(String label, bool cross) {
      final locked = market.onlyIsolated;
      final disabled = locked && cross; // can't pick cross on isolated-only
      final sel = !disabled && _isCross == cross;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: disabled
              ? null
              : () {
                  if (_isCross == cross) return;
                  HapticFeedback.selectionClick();
                  _settingChanged('margin_mode', cross ? 'cross' : 'isolated');
                  _updateDraft(() {
                    _isCross = cross;
                    _leverageTouched = true;
                  });
                },
          child: Container(
            height: 36.h,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: sel ? c.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(9.r),
              border: Border.all(
                color: sel ? c.border : Colors.transparent,
                width: 0.5,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: disabled
                    ? c.textTertiary.withValues(alpha: 0.4)
                    : sel
                        ? c.textPrimary
                        : c.textTertiary,
                fontWeight: FontWeight.w700,
                fontSize: 13.sp,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: EdgeInsets.all(3.w),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: c.border, width: 0.5),
              ),
              child: Row(
                children: [
                  seg(context.l10n.slipCross, true),
                  seg(context.l10n.slipIsolated, false),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The most leverage this ticket offers: the venue's maximum, tightened
  /// to the policy's cap for this region. Both tickets (spending wallet and
  /// Ledger) draw the same slider from it.
  int get _offeredLeverage => ref
      .watch(runtimeCapabilitiesProvider)
      .offeredLeverage(market.offeredMaxLeverage);

  Widget _buildLeverage(AppColorsExtension c) {
    final offered = _offeredLeverage;
    final capped = offered < market.offeredMaxLeverage;
    if (_leverage > offered) {
      // A cap that arrived (or tightened) while the ticket was open pulls
      // the draft down to it rather than leaving a value the order path
      // would refuse.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _leverage > offered) {
          _updateDraft(() => _leverage = offered);
        }
      });
    }
    final capNote = capped
        ? Padding(
            padding: EdgeInsets.only(top: 4.h),
            child: Text(
              context.l10n.investingLeverageCapped(offered),
              style: TextStyle(
                color: c.textTertiary,
                fontSize: 12.sp,
                height: 1.3,
              ),
            ),
          )
        : null;
    if (offered <= 1) {
      // Nothing to slide: the region allows 1x only.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                context.l10n.ledgerSummaryLeverage,
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                  color: c.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Text(
                '1x',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w800,
                  color: c.textPrimary,
                ),
              ),
            ],
          ),
          if (capNote != null) capNote,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              context.l10n.ledgerSummaryLeverage,
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: c.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            Text(
              '${_leverage}x',
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.w800,
                // The page is already painted in the side color, so the
                // slider and its readout take the contrasting ink.
                color: c.textPrimary,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: c.textPrimary,
            inactiveTrackColor: c.surface,
            thumbColor: c.textPrimary,
            overlayColor: c.textPrimary.withValues(alpha: 0.12),
            trackHeight: 3,
          ),
          child: Slider(
            value: _leverage.clamp(1, offered).toDouble(),
            min: 1,
            max: offered.toDouble(),
            divisions: offered - 1,
            onChanged: (v) {
              final next = v.round();
              if (next != _leverage) {
                HapticFeedback.selectionClick();
                _updateDraft(() {
                  _leverage = next;
                  _leverageTouched = true;
                });
              }
            },
            onChangeEnd: (v) => _settingChanged('leverage', v.round()),
          ),
        ),
        Row(
          children: [
            Text('1x',
                style: TextStyle(color: c.textTertiary, fontSize: 12.sp)),
            const Spacer(),
            Text(context.l10n.slipMaxLeverage('$offered'),
                style: TextStyle(color: c.textTertiary, fontSize: 12.sp)),
          ],
        ),
        if (capNote != null) capNote,
        if (market.onlyIsolated) ...[
          SizedBox(height: 4.h),
          Text(
            context.l10n.slipIsolatedOnly,
            style: TextStyle(
              color: c.textTertiary,
              fontSize: 12.sp,
              height: 1.3,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAmountField(AppColorsExtension c, double available,
      {bool keypad = false,
      double? minAmountUsd,
      bool belowMinimum = false,
      String? positionNote}) {
    final availLabel = isSpot && !_isLong
        ? context.l10n.slipHeld(
            '${formatHlSize(available > 0 ? available / (_midNow() > 0 ? _midNow() : 1) : 0)} ${market.coin}')
        : context.l10n.ledgerAvailableAmount(formatHlUsd(available));
    // Simple ticket: the shared hero + the app's own keypad (pinned by the
    // ticket below the form), so the OS keyboard never covers the sheet.
    if (keypad) {
      // The balance reads "Available $X" here so the minimum can follow
      // it on the same line.
      final compactAvailLabel = isSpot && !_isLong
          ? availLabel
          : context.l10n.betSlipAvailableAmount(formatHlUsd(available));
      // Everything, floored to a cent: a spot sell of the whole holding
      // as is, a buy or a perp margin with its slippage and fees reserved
      // out of the same cash so the order can be funded.
      final maxUsd = available <= 0
          ? 0.0
          : isSpot && !_isLong
              ? (available * 100).floorToDouble() / 100
              : hypercoreMaxOrderUsd(
                  availableUsd: available,
                  leverage: isSpot ? 1 : _leverage,
                  slippagePct: _mode == _OrderMode.market ? _slippagePct : 0,
                );
      // One small Max chip beside the figure, and under it one quiet line
      // with the balance and the venue minimum. An empty account has
      // nothing to fill and goes straight to the deposit door.
      return BigAmountDisplay(
        prefix: r'$',
        amountText: _amountController.text,
        conversionLabel:
            _marginUsd > 0 ? _denomLine(_denomEquivalent(_marginUsd)) : null,
        availableLabel: compactAvailLabel,
        minimumLabel: minAmountUsd == null
            ? null
            : context.l10n.amountMinimumInline(formatHlUsd(minAmountUsd)),
        minimumIsError: belowMinimum && minAmountUsd != null,
        noteLabel: positionNote,
        trailing: maxUsd > 0
            ? AmountMaxChip(
                label: context.l10n.max,
                semanticLabel: context.l10n.amountUseMaximum,
                onTap: () => _fillAmountChip(maxUsd, 'max'),
              )
            : null,
      );
    }
    // Advanced: the same field treatment as every other number on that
    // page, so one pinned keypad serves all of them.
    final denom = _marginUsd > 0 ? _denomEquivalent(_marginUsd) : null;
    return _numField(
      c,
      _NumField.size,
      _amountLabel(),
      prefix: r'$',
      hint: '0.00',
      valueFontSize: 28.sp,
      footer: [
        SizedBox(height: 8.h),
        Text(
          availLabel,
          style: TextStyle(fontSize: 14.sp, color: c.textSecondary),
        ),
        // Denominated companion — the entered stake in the user's
        // chosen unit (sats/BTC or non-USD fiat). USD stays the entry
        // unit; this mirrors the bet slip's secondary line.
        if (denom != null)
          Padding(
            padding: EdgeInsets.only(top: 8.h, left: 2.w),
            child: Text(
              denom,
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
                color: c.textTertiary,
              ),
            ),
          ),
      ],
    );
  }

  /// '…' wrapper for the denominated companion, or null when the display
  /// unit is plain USD (nothing to echo).
  String? _denomLine(String? denom) => denom;

  String _amountLabel() {
    if (isSpot) return _strings.amount;
    if (_isScale || _isTwap) return _strings.slipTotalMargin;
    return _strings.amount;
  }

  /// The user's money rendered in their chosen Assets/Predictions
  /// denomination (sats/BTC in Bitcoin mode, or a non-USD fiat), or null
  /// when the display unit is plain USD (so we don't echo `$10 $10`).
  /// USD stays the entry/primary unit everywhere — this only feeds the
  /// secondary companion lines that mirror the bet slip.
  String? _denomEquivalent(double usd) {
    final settings = ref.watch(settingsProvider);
    if (true && settings.currency == 'USD') {
      return null;
    }
    return formatPolyAmount(ref, usd);
  }

  /// Long or Short in one row, mirroring the prediction slip's Yes/No.
  /// The selected half carries its own direction colour (the shared
  /// [MarketSideToggle], identical on the simple ticket, on Advanced and
  /// on the Ledger ticket). The sheet re-paints to the new side colour as
  /// it flips.
  Widget _buildSideToggle() {
    final l10n = context.l10n;
    return MarketSideToggle(
      isUp: _isLong,
      upLabel: isSpot ? l10n.buy : l10n.longLabel,
      downLabel: isSpot ? l10n.sell : l10n.shortLabel,
      onChanged: (long) {
        if (_isLong != long) _settingChanged('side', long ? 'long' : 'short');
        _updateDraft(() => _isLong = long);
      },
    );
  }

  Widget _buildPriceInputs(AppColorsExtension c, double mid) {
    switch (_mode) {
      case _OrderMode.market:
        return const SizedBox.shrink();
      case _OrderMode.limit:
        return Padding(
          padding: EdgeInsets.only(top: 16.h),
          child: _priceField(
              c, _NumField.limitPrice, context.l10n.betLimitPrice),
        );
      case _OrderMode.pro:
        switch (_proType) {
          case _ProType.scale:
            return Padding(
              padding: EdgeInsets.only(top: 16.h),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child:
                            _priceField(
                                c, _NumField.scaleStart, context.l10n.slipStartPrice),
                      ),
                      SizedBox(width: 10.w),
                      Expanded(
                        child: _priceField(
                            c, _NumField.scaleEnd, context.l10n.slipEndPrice),
                      ),
                    ],
                  ),
                  SizedBox(height: 12.h),
                  _intField(
                      c, _NumField.scaleCount, context.l10n.slipNumberOfOrders),
                ],
              ),
            );
          case _ProType.twap:
            return Padding(
              padding: EdgeInsets.only(top: 16.h),
              child: Column(
                children: [
                  _intField(
                      c, _NumField.twapMinutes, context.l10n.slipTwapMinutes),
                  SizedBox(height: 12.h),
                  _buildCheckbox(
                    c,
                    context.l10n.slipRandomizeTiming,
                    _randomizeTwap,
                    (v) {
                      _settingChanged('twap_randomized', v);
                      _updateDraft(() => _randomizeTwap = v);
                    },
                  ),
                ],
              ),
            );
          case _ProType.stopLimit:
          case _ProType.takeLimit:
            return Padding(
              padding: EdgeInsets.only(top: 16.h),
              child: Column(
                children: [
                  _priceField(
                      c, _NumField.trigger, context.l10n.slipTriggerPrice),
                  SizedBox(height: 12.h),
                  _priceField(
                      c, _NumField.stopLimitPrice, context.l10n.betLimitPrice),
                ],
              ),
            );
          case _ProType.stopMarket:
          case _ProType.takeMarket:
            return Padding(
              padding: EdgeInsets.only(top: 16.h),
              child: _priceField(
                      c, _NumField.trigger, context.l10n.slipTriggerPrice),
            );
        }
    }
  }

  Widget _buildOptions(AppColorsExtension c) {
    final children = <Widget>[];

    if (_mode == _OrderMode.limit) {
      children.add(SizedBox(height: 16.h));
      children.add(_buildTifSelector(c));
      children.add(SizedBox(height: 12.h));
      children.add(_buildCheckbox(
        c,
        context.l10n.slipPostOnlyOption,
        _postOnly,
        (v) {
          _settingChanged('post_only', v);
          _updateDraft(() {
            _postOnly = v;
            _tif = v ? 'Alo' : (_tif == 'Alo' ? 'Gtc' : _tif);
          });
        },
      ));
    }

    // Reduce-only — relevant for every non-market type.
    if (_mode != _OrderMode.market) {
      children.add(SizedBox(height: 12.h));
      children.add(_buildCheckbox(
        c,
        context.l10n.slipReduceOnlyOption,
        _reduceOnly,
        (v) {
          _settingChanged('reduce_only', v);
          _updateDraft(() => _reduceOnly = v);
        },
      ));
    }

    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  Widget _buildTifSelector(AppColorsExtension c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(c, context.l10n.slipTimeInForce),
        SizedBox(height: 8.h),
        _segmentTrack(c, [
          for (final t in _tifOptions)
            _trackSegment(
              c,
              label: t.toUpperCase(),
              selected: _tif == t,
              onTap: () {
                HapticFeedback.selectionClick();
                _settingChanged('tif', t.toLowerCase());
                _updateDraft(() {
                  _tif = t;
                  _postOnly = t == 'Alo';
                });
              },
            ),
        ]),
      ],
    );
  }

  Widget _buildTpSlAttach(AppColorsExtension c, double entry) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 14.h),
        _buildCheckbox(
          c,
          context.l10n.slipAttachTpSl,
          _attachTpSl,
          (v) {
            _settingChanged('tp_sl', v);
            _updateDraft(() => _attachTpSl = v);
          },
        ),
        if (_attachTpSl) ...[
          SizedBox(height: 12.h),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child:
                    _priceField(c, _NumField.takeProfit,
                        context.l10n.slipTakeProfitPrice),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: _priceField(
                    c, _NumField.stopLoss, context.l10n.slipStopLossPrice),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildSlippage(AppColorsExtension c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(c, context.l10n.maxSlippage),
        SizedBox(height: 8.h),
        _segmentTrack(c, [
          for (final opt in _slippageOptions)
            _trackSegment(
              c,
              label:
                  '${opt.toStringAsFixed(opt == opt.roundToDouble() ? 0 : 1)}%',
              selected: _slippagePct == opt,
              onTap: () {
                HapticFeedback.selectionClick();
                _settingChanged('slippage_bps', VenueAnalytics.bps(opt));
                _updateDraft(() => _slippagePct = opt);
              },
            ),
        ]),
      ],
    );
  }

  /// The summary every ticket carries, simple or Advanced. It opens by
  /// saying, in plain words, WHAT this order leaves the person with: a
  /// holding they own outright, or a geared position with a margin mode
  /// and a daily cost to carry.
  /// A plain sentence describing the order the ticket will place.
  String _orderExplanation() {
    final l = _strings;
    final coin = market.coin;
    final verb = isSpot
        ? (_isLong ? l.slipVerbBuys : l.slipVerbSells)
        : (_isLong ? l.slipVerbGoesLong : l.slipVerbGoesShort);
    String px(TextEditingController controller) {
      final v = _parse(controller);
      return v == null
          ? '—'
          : formatHlPrice(v, decimalCap: market.pxDecimalCap);
    }

    final leverage = isSpot
        ? ''
        : l.slipLeverageSuffix(
            '$_leverage',
            _isCross && !market.onlyIsolated
                ? l.slipMarginCross
                : l.slipMarginIsolated);
    final reduce = _reduceOnly ? l.slipReduceSentence : '';
    final tpsl = _attachTpSl && _isOpening ? l.slipTpSlSentence : '';
    final action = l.slipAction(verb, coin, leverage);
    switch (_mode) {
      case _OrderMode.market:
        return l.slipExplainMarket(
            _slippagePct.toStringAsFixed(1), action, '$reduce$tpsl');
      case _OrderMode.limit:
        final tif = switch (_tif) {
          'Ioc' => l.slipTifIoc,
          'Alo' => l.slipTifAlo,
          _ => l.slipTifGtc,
        };
        return l.slipExplainLimit(
            px(_priceController), action, '$tif$reduce$tpsl');
      case _OrderMode.pro:
        switch (_proType) {
          case _ProType.scale:
            final n = _parseInt(_countController) ?? 0;
            return l.slipExplainScale(
                n,
                px(_startPxController),
                px(_endPxController),
                l.slipSliceAction(verb, coin, leverage),
                reduce);
          case _ProType.twap:
            final m = _parseInt(_twapMinutesController) ?? 0;
            return l.slipExplainTwap(m, action, reduce);
          case _ProType.stopMarket:
            return l.slipExplainStopMarket(
                coin, px(_triggerController), action, reduce);
          case _ProType.stopLimit:
            return l.slipExplainStopLimit(coin, px(_triggerController),
                px(_stopLimitController), action, reduce);
          case _ProType.takeMarket:
            return l.slipExplainTakeMarket(
                coin, px(_triggerController), action, reduce);
          case _ProType.takeLimit:
            return l.slipExplainTakeLimit(coin, px(_triggerController),
                px(_stopLimitController), action, reduce);
        }
    }
  }

  /// Buy / Sell for spot, Long / Short for perps, in the app language.
  String _sideWord() => isSpot
      ? (_isLong ? _strings.buy : _strings.sell)
      : (_isLong ? _strings.longLabel : _strings.shortLabel);

  Widget _buildEssentialSummary(
    AppColorsExtension c,
    double notional,
    double transferFromPerp, {
    required bool hasFunds,
    // The order sentence belongs to Advanced, where the type is chosen;
    // the plain ticket stays plain (owner decision).
    bool explain = false,
    // Entry price and size of the order, for the liquidation estimate.
    double entry = 0,
    double size = 0,
  }) {
    final holdingCost = _holdingCostLine(notional);
    final liq = !isSpot && _isOpening && entry > 0 && _marginUsd > 0
        ? _liquidationEstimate(entry, size)
        : (price: null, blocker: null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Nothing is said about a spot buy. "You end up owning QQQ, it
        // is yours to hold or sell" tells someone who has already
        // chosen to buy a thing they already know, in the sheet where
        // they are about to commit money. The leveraged side below says
        // what it says because leverage, margin mode and a daily
        // carrying cost are facts the order does not otherwise show.
        if (!isSpot) ...[
          // Leverage AND margin mode, on every ticket: which balance backs
          // this position is not an Advanced detail.
          _previewRow(
            c,
            context.l10n.chartLeverage,
            '$_leverage× · ${_isCross ? context.l10n.investingCrossMargin : context.l10n.investingIsolatedMargin}',
          ),
          if (_leverage > 1) ...[
            SizedBox(height: 10.h),
            _previewRow(
                c, context.l10n.slipPositionValue, formatHlUsd(notional)),
          ],
          // Where this position would be liquidated, before anything is
          // placed: the one number a leveraged ticket must show up front.
          if (liq.price != null || liq.blocker != null) ...[
            SizedBox(height: 10.h),
            _previewRow(
              c,
              context.l10n.slipEstLiquidation,
              liq.price != null
                  ? formatHlPrice(liq.price!, decimalCap: market.pxDecimalCap)
                  : liq.blocker!,
            ),
          ],
          if (holdingCost != null) ...[
            SizedBox(height: 10.h),
            Text(
              holdingCost,
              style: TextStyle(
                  fontSize: 13.sp, color: c.textSecondary, height: 1.4),
            ),
          ],
          SizedBox(height: 12.h),
        ],
        HyperliquidFeeSummary(
          notional: notional,
          spot: isSpot,
          buy: _isLong,
          maker: _mode == _OrderMode.limit && _postOnly,
          builder: !_isTwap,
          dex: market.dex,
          hasFunds: hasFunds,
          // The Ledger account's own fee tier, never the hot account's.
          address: _isLedger ? _ledgerAddress : null,
          useHotAccount: !_isLedger,
        ),
        // What this order will actually do, in one plain sentence, so the
        // type picked in Advanced is never a mystery at the button.
        if (explain) ...[
          SizedBox(height: 10.h),
          Text(
            _orderExplanation(),
            style:
                TextStyle(fontSize: 13.sp, color: c.textSecondary, height: 1.4),
          ),
        ],
        if (transferFromPerp > 0) ...[
          SizedBox(height: 10.h),
          Text(
            context.l10n
                .investingFundingFromBalance(formatHlUsd(transferFromPerp)),
            style:
                TextStyle(fontSize: 14.sp, color: c.textSecondary, height: 1.4),
          ),
        ],
      ],
    );
  }

  Widget _buildOrderDetails(
    AppColorsExtension c,
    double mid,
    double notional,
    double size,
    int? scaleCount,
  ) {
    final rows = <Widget>[];
    void add(String label, String value, {String? sub}) {
      if (rows.isNotEmpty) rows.add(SizedBox(height: 8.h));
      rows.add(_previewRow(c, label, value, sub: sub));
    }

    // Notional in USD, with the denominated equivalent (sats/BTC or
    // non-USD fiat) as a companion so the exposure reads in the user's unit.
    if (!isSpot) {
      final denomN = _denomEquivalent(notional);
      add(_strings.slipNotional, formatHlUsd(notional), sub: denomN);
    }
    add(_strings.ledgerSummarySize, '${formatHlSize(size)} ${market.coin}');

    // Price context per order type.
    if (_mode == _OrderMode.market) {
      add(_strings.slipEstEntry,
          formatHlPrice(mid, decimalCap: market.pxDecimalCap));
    } else if (_mode == _OrderMode.limit) {
      final p = _parse(_priceController);
      add(_strings.betLimitPrice,
          p != null ? formatHlPrice(p, decimalCap: market.pxDecimalCap) : '—');
    } else if (_isScale) {
      final s = _parse(_startPxController);
      final e = _parse(_endPxController);
      add(
        _strings.slipRange,
        (s != null && e != null)
            ? '${formatHlPrice(s, decimalCap: market.pxDecimalCap)} → ${formatHlPrice(e, decimalCap: market.pxDecimalCap)}'
            : '—',
      );
      add(_strings.investingOrderCount, _strings.slipLegsCount(scaleCount ?? 0));
    } else if (_isTwap) {
      final m = _parseInt(_twapMinutesController);
      add(_strings.slipOver, m != null ? _strings.slipMinutesValue(m) : '—');
    } else if (_isTriggerType) {
      final t = _parse(_triggerController);
      add(_strings.slipTrigger,
          t != null ? formatHlPrice(t, decimalCap: market.pxDecimalCap) : '—');
      if (_proType == _ProType.stopLimit || _proType == _ProType.takeLimit) {
        final l = _parse(_stopLimitController);
        add(
            _strings.betOrderTypeLimit,
            l != null
                ? formatHlPrice(l, decimalCap: market.pxDecimalCap)
                : '—');
      }
    }

    final entry = _entryPx(mid);
    // The figure itself is on the summary above; only the note on how it
    // is estimated lives here.
    if (_isOpening && entry > 0 && _marginUsd > 0) {
      rows.add(Padding(
        padding: EdgeInsets.only(top: 8.h),
        child: Text(
          _isCross
              ? context.l10n.slipLiqNoteCross
              : context.l10n.slipLiqNoteIsolated,
          style:
              TextStyle(fontSize: 13.sp, color: c.textSecondary, height: 1.4),
        ),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows,
    );
  }

  Widget _buildSpreadWarning(
      AppColorsExtension c, double spreadPct, bool verySpread,
      {required bool advanced}) {
    // Info-card chrome (theme `warning` token, 12.r, icon + copy) —
    // matches the app's tinted notice cards instead of raw Colors.orange.
    final warn = c.warning;
    return Padding(
      padding: EdgeInsets.only(top: 10.h),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
        decoration: BoxDecoration(
          color: warn.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: warn.withValues(alpha: 0.30)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: warn, size: 18.sp),
                SizedBox(width: 8.w),
                Expanded(
                  child: Text(
                    advanced
                        ? context.l10n
                            .slipWideSpread(spreadPct.toStringAsFixed(1))
                        : context.l10n.investingThinMarket,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
            if (verySpread) ...[
              SizedBox(height: 8.h),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  _updateDraft(() => _acceptWideSpread = !_acceptWideSpread);
                },
                child: Row(
                  children: [
                    Icon(
                      _acceptWideSpread
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      color: _acceptWideSpread ? warn : c.textTertiary,
                      size: 20.sp,
                    ),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: Text(
                        context.l10n.hlWideSpreadAck,
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The order button against a held position: "Add to long · \$X",
  /// "Reduce long · \$X", "Close long", "Flip to short · \$X". Null keeps
  /// the plain order label (no position, or nothing typed yet).
  String? _positionCtaLabel(HlPositionPlan plan, {double? amountUsd}) {
    if (plan.position == null) return null;
    final amount = formatPolyAmount(ref, amountUsd ?? _marginUsd);
    final l = _strings;
    switch (plan.effect) {
      case HlPositionEffect.open:
        return null;
      case HlPositionEffect.add:
        return l.slipCtaAddTo(plan.heldSide, amount);
      case HlPositionEffect.reduce:
        return plan.orderSize > 0 ? l.slipCtaReduce(plan.heldSide, amount) : null;
      case HlPositionEffect.close:
        return l.slipCtaClose(plan.heldSide);
      case HlPositionEffect.flip:
        return l.slipCtaFlip(_isLong ? 'long' : 'short', amount);
    }
  }

  /// The quiet line under the amount that says what the order does to the
  /// position held here. Null with no position, or on the other side
  /// before anything is typed.
  String? _positionNote(HlPositionPlan plan) {
    final pos = plan.position;
    if (pos == null) return null;
    final held = formatHlSize(plan.heldSize);
    final coin = market.coin;
    final l = _strings;
    switch (plan.effect) {
      case HlPositionEffect.open:
        return null;
      case HlPositionEffect.add:
        return l.slipPositionAdds(plan.heldSide, held, coin);
      case HlPositionEffect.reduce:
        if (plan.orderSize <= 0) return null;
        return l.slipPositionReduces(
            plan.heldSide, held, formatHlSize(plan.remaining), coin);
      case HlPositionEffect.close:
        return l.slipPositionCloses(plan.heldSide, held, coin);
      case HlPositionEffect.flip:
        return l.slipPositionFlips(
            plan.heldSide, held, formatHlSize(plan.remainder), coin);
    }
  }

  String _ctaLabel({double? amountUsd}) {
    // Stake in the user's chosen denomination (sats/BTC or fiat) — the asset
    // PRICE stays USD, but the CTA is the user's money.
    final amount = formatPolyAmount(ref, amountUsd ?? _marginUsd);
    final side = _sideWord();
    final l = _strings;
    // The button is the deed, said the way a trader says it: "Go Long
    // BTC 5x · $100", "Buy BTC now · $100" (owner decision).
    switch (_mode) {
      case _OrderMode.market:
        if (isSpot) return l.slipCtaSpotNow(side, market.coin, amount);
        return l.slipCtaGo(side, market.coin, '$_leverage', amount);
      case _OrderMode.limit:
        return l.slipCtaLimit(side, market.coin);
      case _OrderMode.pro:
        switch (_proType) {
          case _ProType.scale:
            final n = _parseInt(_countController) ?? 0;
            return l.slipCtaScale(n, side);
          case _ProType.twap:
            final m = _parseInt(_twapMinutesController) ?? 0;
            return l.slipCtaTwap(m);
          case _ProType.stopLimit:
          case _ProType.stopMarket:
            return l.slipCtaStop;
          case _ProType.takeLimit:
          case _ProType.takeMarket:
            return l.slipCtaTakeProfit;
        }
    }
  }

  // ── Small field builders ────────────────────────────────────────────

  Widget _priceField(AppColorsExtension c, _NumField field, String label) =>
      _numField(c, field, label, prefix: r'$');

  Widget _intField(AppColorsExtension c, _NumField field, String label) =>
      _numField(c, field, label);

  /// One numeric field on the Advanced page: an ordinary text input that
  /// raises the keyboard, the way the Predictions advanced page works.
  /// Focus still drives the accent hairline and promotes the label.
  Widget _numField(AppColorsExtension c, _NumField field, String label,
          {String? prefix,
          String hint = '0',
          double? valueFontSize,
          List<Widget> footer = const []}) =>
      HlNumericField(
        controller: _controllerFor(field),
        label: label,
        prefix: prefix,
        hint: hint,
        focusNode: _focusNodeFor(field),
        valueFontSize: valueFontSize,
        inputFormatters: [
          DecimalInputFormatter(fractionDigits: _decimalsFor(field))
        ],
        decimal: _decimalsFor(field) > 0,
        onChanged: (_) => _updateDraft(() {}),
        footer: footer,
      );

  Widget _buildCheckbox(
    AppColorsExtension c,
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onChanged(!value);
      },
      child: Row(
        children: [
          Icon(
            value
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank_rounded,
            // The HL teal disappears into a green fill, so the tick
            // takes the palette's contrasting ink.
            color: value ? c.accent : c.textTertiary,
            size: 20.sp,
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Header identity with public-market educational help and close control.
  Widget _buildHeader(AppColorsExtension c) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 14.h, 20.w, 14.h),
      child: Row(
        children: [
          HlCoinIcon(
            coin: market.coin,
            wireCoin: market.wireCoin,
            category: market.category,
            iconUrl: market.iconUrl,
            size: 36,
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_sideWord()} ${market.coin}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 20.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 8.w),
          // The chip paints from `context.colors`, so leaving it on the
          // sheet's injected palette is what makes it turn with the fill
          // instead of staying a grey card on green / red. Sal's own
          // sheet captures the theme it opens from, so it inherits the
          // tint too.
          SideTintInverted(
            side: _isLong ? greenColor : redColor,
            child: AskSalChip(
              advisorContext: AdvisorContext(
                surface: 'hl_order_slip',
                marketVenue: 'hyperliquid',
                marketId: market.wireCoin,
                marketDisplayName: market.coin,
                orderType: _salOrderTypeLabel,
              ),
              chipSignals: salSignalsForHlMarket(market),
              onLocalAction: _applySalAction,
              localActions: {
                'switch_to_limit',
                if (!isSpot) 'open_leverage_settings',
              },
            ),
          ),
          SizedBox(width: 8.w),
          const KuteCloseButton(),
        ],
      ),
    );
  }

  Widget _previewRow(AppColorsExtension c, String label, String value,
      {String? sub}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: c.textSecondary, fontSize: 15.sp)),
        SizedBox(width: 12.w),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (sub != null) ...[
                SizedBox(height: 2.h),
                Text(
                  sub,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: c.textTertiary,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

