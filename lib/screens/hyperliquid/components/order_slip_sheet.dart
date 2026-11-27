import 'package:kute/screens/share/share_wallet_gate.dart';
import 'package:kute/services/share_target.dart';
import 'package:kute/screens/shared/kute_side_panel.dart';
import 'package:kute/platform/kute_wide_frames.dart' show KuteDialogSurfaceMark;

import 'package:kute/screens/shared/kute_form_panel_route.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart' show showKuteModalSheet;
import 'package:kute/helpers/root_navigator.dart' show kuteRootContext;
import 'package:kute/screens/shared/standing_order_slips.dart'
    show StandingOrderSlips;
import 'package:kute/screens/shared/standing_order_toasts.dart'
    show StandingOrderToasts;
import 'package:kute/services/standing_orders/standing_orders_provider.dart'
    show
        StandingOrder,
        StandingOrderState,
        StandingOrderVenue,
        standingOrdersProvider;
import 'package:kute/services/hyperliquid/hypercore_cash.dart'
    show hypercoreMaxOrderUsd;
import 'package:kute/screens/shared/side_tint_palette.dart';
import 'package:kute/screens/hyperliquid/components/builder_fee_consent.dart';
import 'package:kute/screens/hyperliquid/components/hl_error_copy.dart';
import 'package:kute/screens/shared/hyperliquid_fee_summary.dart';
import 'package:kute/screens/shared/kute_motion.dart';
import 'package:kute/screens/hyperliquid/components/hl_order_controls.dart';
import 'package:kute/screens/shared/advanced_ticket.dart';
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
// Denomination: this slip is Dollars money, so the entry, the notional preview
// and the CTA amount are all dollars, whatever the Settings currency
// (formatDollars), and so is the asset PRICE (limit / trigger / mid).
//
// Risk UX carried over: spread ≥1% warning banner, ≥3% extra confirm; a mid
// that hasn't ticked for >10 s disables confirm ("refreshing price…"); the
// liquidation preview is client-estimated and labeled as an estimate.
//
// The policy helper below refreshes the relevant operation capability.
// Existing-position exits use a separate permission from new exposure.
//
// Shown, not bought (founder decision, 12 November 2026): every market
// stays browsable whatever the policy refuses for the person's region,
// so this ticket is where a refused buy stops. A market whose new
// positions the policy refuses (`hyperliquid.trade`, or
// `hyperliquid.stocks` on a stock-linked perp; [hlOpenCapabilities])
// opens with its confirm disabled under the policy's own reason
// ([CapabilityBlockNote], "Check connection" for a region refusal),
// adding to a held position included, before Face ID and before any
// money moves. Closing, reducing and selling answer to
// `hyperliquid.close` and stay open. A policy that cannot be read
// refuses the open (fail closed) while the market stays on screen.
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
import 'package:kute/providers/unified_search_provider.dart'
    show SearchCategory;
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/home/components/kute_shell_bar.dart'
    show KuteBarPrimaryButton;
import 'package:kute/screens/home/components/kute_bar_trade_row.dart'
    show KuteBarShareSlot;
import 'package:kute/screens/share/send_pick_session.dart';
import 'package:kute/screens/share/slip_share.dart';
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
import 'package:kute/providers/pending_hyperliquid_order_provider.dart';
import 'package:kute/providers/placing_hyperliquid_order_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/services/one_balance/committed_funds.dart'
    show committedFundsProvider, orderDollarsProvider;
import 'package:kute/screens/home/components/action_pill.dart'
    show greenColor, redColor;
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/hyperliquid/components/hl_protect_rules.dart'
    show hlProtectiveOrdersFor;
import 'package:kute/screens/hyperliquid/components/order_placed_overlay.dart';
import 'package:kute/screens/hyperliquid/components/hl_order_funding_rules.dart';
import 'package:kute/screens/ledger/hyperliquid/ledger_hl_execution_target.dart'
    show
        ledgerHlHeldPosition,
        runLedgerHlClose,
        runLedgerHlMarketOrder,
        runLedgerHlTrailingStop,
        ledgerHlReferencePx;
import 'package:kute/screens/ledger/hyperliquid/ledger_transfer_sheet.dart';
import 'package:kute/screens/ledger/ledger_action_ui.dart'
    show showLedgerConfirmation;
import 'package:kute/screens/shared/amount_keypad_panel.dart';
import 'package:kute/screens/shared/slip_form_body.dart';
import 'package:kute/screens/polymarket/components/slip_chrome.dart'
    show SlipAdvancedButton, SlipAdvancedChip, SlipAmountPills;
import 'package:kute/screens/shared/slip_stat_tiles.dart';
import 'package:kute/screens/shared/money_fee_summary.dart'
    show MoneyFeeFigure, MoneyFeeLeg, fundingLegFeeLabel;
import 'package:kute/screens/shared/decimal_input_formatter.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/market_side_toggle.dart';
import 'package:kute/services/hyperliquid/hl_failure_analytics.dart';
import 'package:kute/services/hyperliquid/hl_sent_order_trace.dart'
    show
        hlConfirmingMarketsProvider,
        hlConfirmingOrdersProvider,
        hlMarketConfirming;
import 'package:kute/screens/usd/usd_account_screen.dart'
    show openInvestmentsOrders, openInvestmentsPositions;
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';
import 'package:kute/services/hyperliquid/hl_exposure_rule.dart';
import 'package:kute/services/hyperliquid/hl_position_effect.dart';
import 'package:kute/services/hyperliquid/hl_twap_rules.dart';
import 'package:kute/services/hyperliquid/hyperliquid_rounding.dart';
import 'package:kute/services/hyperliquid/trailing_stop.dart';
import 'package:kute/services/hyperliquid/liquidation_estimate.dart';
import 'package:kute/services/venue_analytics.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/screens/shared/message_display.dart'
    show showMessageSnackBar;
import 'package:kute/screens/shared/slip_shortfall.dart';
import 'package:kute/services/one_balance/money_steps.dart'
    show MoneyPlace;
import 'package:kute/screens/shared/rubber_band_progress.dart';
import 'package:kute/services/funding/venue_shortfall.dart';
import 'package:kute/services/one_balance/hyperliquid_venue_funder.dart';
import 'package:kute/services/one_balance/order_funding.dart';
import 'package:kute/services/one_balance/bitcoin_funded_order.dart';
import 'package:kute/services/one_balance/investments_spendable.dart'
    show investmentsSpendableExcludingProvider, venueCashRefreshProvider;
import 'package:kute/services/one_balance/gift_funding.dart'
    show giftSpendableProvider;
import 'package:kute/services/one_balance/bitcoin_to_dollars_leg.dart'
    show BitcoinLegPlan, BitcoinLegRules;
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/funding_fees.dart';
import 'package:kute/providers/spark_address_provider.dart'
    show sparkSelfAddressProvider;
import 'package:kute/services/one_balance/venue_cash_source.dart'
    show
        VenueCashDestination,
        VenueCashPlan,
        venueCashPullerProvider,
        venueCashReachExcludingProvider;
import 'package:kute/services/one_balance/multi_source_move.dart'
    show MultiSourceMoveStore;
import 'package:kute/helpers/auth_grant_registry.dart';
import 'package:kute/services/one_balance/one_balance_state.dart'
    show OneBalanceVenue;
import 'package:kute/services/one_balance/venue_funder.dart'
    show RouteUnavailable, UserGrantAuthorization, VenueMoveQuote;
import 'package:kute/services/one_balance/venue_cash_funded_order.dart'
    show VenueCashFundedRequest, venueCashFundedOrderRunnerProvider;
import 'package:kute/providers/venue_sweeper_provider.dart'
    show venueSweeperProvider;
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/services/region_freshness.dart';
import 'package:kute/services/success_feedback.dart'
    show moneyFailureFeedbackAfterBand;
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
  ({String capability, CapabilityDecision decision})? denial;
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
    message = error.decision.bodyIn(l10n);
    regionBlocked = error.decision.regionBlocked;
    denial = (capability: error.capability, decision: error.decision);
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
    denial: denial,
    surface: 'investing_gate_sheet',
    title: l10n.gateInvestingUnavailable,
    capabilities: capabilities ?? [capability],
  ));
  return true;
}

/// Whether [fill] is on [market]. Fills carry the WIRE coin (a builder
/// dex's 'xyz:TSLA', a spot pair's '@107'), never the display coin the
/// ticket shows ('TSLA', 'HYPE'): matched on the display coin, a HIP-3 or
/// spot order never reached its receipt from the fill stream.
@visibleForTesting
bool hlFillOnMarket(HlMarket market, HlFill fill) =>
    fill.coin == market.wireCoin;

/// Whether [fill] is the ticket's own: on [market] and carrying the cloid
/// the order went out under ([cloid], or a send again of it,
/// [HlResendCloids]). A fill with no cloid or another one never is: a stop
/// that triggered, a TWAP slice or another client's order on the same coin
/// while this one is in the air.
@visibleForTesting
bool hlFillOfOrder(HlMarket market, String cloid, HlFill fill) {
  final id = fill.cloid?.toLowerCase();
  if (id == null || !hlFillOnMarket(market, fill)) return false;
  return HlResendCloids.all(cloid).any((c) => c.toLowerCase() == id);
}

/// The ticket's own fills ([hlFillOfOrder]) totalled for its receipt: the
/// size filled and its size-weighted average price (the fee and realised
/// P&L are summed from the same fills by the receipt). Null for none.
@visibleForTesting
({double size, double avgPx})? hlOwnFillsTotal(Iterable<HlFill> fills) {
  var size = 0.0;
  var notional = 0.0;
  for (final f in fills) {
    size += f.sz;
    notional += f.sz * f.px;
  }
  if (size <= 0) return null;
  return (size: size, avgPx: notional / size);
}

/// What the receipt of a Ledger close of the whole position says of the
/// stops and takes it leaves (each cancel needs the device): the close
/// sheet's same row and line. [left] is their count from the Ledger's last
/// read (-1 when it could not be read: the line, no count), null when
/// there are none or the close was not whole (nothing said).
@visibleForTesting
({Map<String, String> rows, String? note}) hlLedgerLeftoverReceipt(
        AppLocalizations l, int? left) =>
    (
      rows: {
        if ((left ?? 0) > 0) l.hlProtectOrdersNotCancelledRow: '$left',
      },
      note: left == null ? null : l.hlLeftLedgerStopsOpen,
    );

/// A scale ladder on the wrong side of [mid]: a buy ladder rests under the
/// price (a leg over it would buy at once, as a market order), a sell
/// ladder over it. Null when it rests where it should (or without a price).
@visibleForTesting
String? hlScaleSideIssue(AppLocalizations l,
    {required bool isLong,
    required double startPx,
    required double endPx,
    required double mid}) {
  if (mid <= 0) return null;
  if (isLong && math.max(startPx, endPx) >= mid) return l.hlAdvScaleBelowPrice;
  if (!isLong && math.min(startPx, endPx) <= mid) {
    return l.hlAdvScaleAbovePrice;
  }
  return null;
}

/// A take-profit or stop-loss attached to an opening order on the wrong
/// side of its [entry] (a long's take over it and stop under it, a short's
/// the mirror). Null when both are where they should be (or absent).
@visibleForTesting
String? hlTpSlEntryIssue(AppLocalizations l,
    {required bool isLong,
    required double entry,
    double? takeProfit,
    double? stopLoss}) {
  final tp = takeProfit;
  final sl = stopLoss;
  if (tp != null && ((isLong && tp <= entry) || (!isLong && tp >= entry))) {
    return isLong ? l.slipTpAboveEntry : l.slipTpBelowEntry;
  }
  if (sl != null && ((isLong && sl >= entry) || (!isLong && sl <= entry))) {
    return isLong ? l.slipSlBelowEntry : l.slipSlAboveEntry;
  }
  return null;
}

/// What a market ticket closes on from the fill stream: its own fills
/// ([own], already matched by [hlFillOfOrder]) totalled, once the venue's
/// answer was unclear ([unconfirmed]), or, while that answer is still
/// awaited, once they come to the whole size the ticket asked for
/// ([requestedSize], to within half a [sizeStep], as the limit path): a
/// slow answer (a builder dex's POST running to its 15 s timeout) never
/// holds back the receipt of an order filled in a second. Never on a part
/// while the answer is awaited (the answer says what filled), never with
/// [requestedSize] 0 (an order with a take-profit, stop-loss or trailing
/// stop attached, whose answer says whether those were placed), and never
/// for a limit, Scale or TWAP order, whose stream never closes it on a
/// total (a limit closes on its whole size alone, a part being said with
/// what still rests).
@visibleForTesting
({double size, double avgPx})? hlStreamReceipt(
    {required bool unconfirmed,
    required bool market,
    required Iterable<HlFill> own,
    double requestedSize = 0,
    double sizeStep = 0}) {
  if (!market) return null;
  final total = hlOwnFillsTotal(own);
  if (total == null || unconfirmed) return total;
  if (requestedSize <= 0) return null;
  return total.size >= requestedSize - sizeStep / 2 ? total : null;
}

/// The venue's [answer] to a market order the ticket sent, unless the
/// ticket already [closed] on that order's own fills from the stream
/// ([hlStreamReceipt]): then the fills said it was placed, and the answer,
/// whatever it is (a success, an error, a timeout or an unconfirmed
/// lookup), only calls [onClosed] (the placing tile marked placed) and
/// comes back null, never rethrown. No second receipt, no error, no lock.
@visibleForTesting
Future<HlOrderResult?> hlMarketAnswer(Future<HlOrderResult> answer,
    {required bool Function() closed,
    required void Function() onClosed}) async {
  try {
    final result = await answer;
    if (!closed()) return result;
  } catch (_) {
    if (!closed()) rethrow;
  }
  onClosed();
  return null;
}

/// How long the ticket gathers its order's fills from the stream before it
/// closes on them after an unclear answer: one match's fills arrive
/// together, a moment apart at most.
const Duration kHlStreamFillsSettle = Duration(milliseconds: 400);

/// Runs the trailing stop attached to an order that just filled and
/// returns what its receipt must say, since the ticket closes on that
/// receipt next and a line on the ticket would never be seen: null when
/// [place] placed it (it answers true), [AppLocalizations.
/// hlAdvTrailingNotApproved] when its own approval was declined (it
/// answers false), [AppLocalizations.slipTrailingNotPlaced] with the
/// reason ([describe]) when it threw. [onFailed] hears the error category
/// ('declined' for a decline), for analytics.
@visibleForTesting
Future<String?> hlAttachedTrailingNote(
  AppLocalizations l10n, {
  required Future<bool> Function() place,
  required String Function(Object error) describe,
  void Function(String category)? onFailed,
}) async {
  try {
    if (await place()) return null;
    onFailed?.call('declined');
    return l10n.hlAdvTrailingNotApproved;
  } catch (e) {
    onFailed?.call(TrackingService.errorCategory(e));
    return l10n.slipTrailingNotPlaced(describe(e));
  }
}

/// Top-level order mode — the Market | Limit | Pro tab.
enum _OrderMode { market, limit, pro }

/// The concrete order type behind the Pro tab. Stop and take orders are
/// not on the opening ticket (owner decision, Phase 2): they protect a
/// position and live on its close sheet.
enum _ProType { scale, twap }

/// A scale order's leg count: at least two, at most fifty (the ticket's
/// own bound, checked inline before Confirm; the venue documents none).
const int kHlScaleMinOrders = 2;
const int kHlScaleMaxOrders = 50;

/// Every numeric input on the Advanced page. The page has no focusable
/// TextField — one keypad is pinned at the bottom and writes to whichever
/// of these is focused, so the OS keyboard can never cover the ticket.
enum _NumField {
  size,
  limitPrice,
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

/// What funding the shortfall from Dollars costs, as the ticket shows it
/// before the tap: [fundUsd] leaves Dollars so that [arrivingUsd] lands
/// (at least the shortfall plus the engine's safety buffer,
/// [OrderFundingEngine.targetUsd]); the difference is the Move fee row.
/// What lands beyond the order stays at the venue as its cash.
class _FundPlan {
  const _FundPlan({
    required this.shortfallUsd,
    required this.fundUsd,
    required this.arrivingUsd,
    this.bitcoinSpread,
    this.quote,
    this.quotedAt,
  });

  final double shortfallUsd;
  final double fundUsd;
  final double arrivingUsd;

  /// The Bitcoin conversion's share Orchestra quoted with the plan (null:
  /// the fallback spread), for a Bitcoin leg's fee line.
  final double? bitcoinSpread;

  /// The funder's estimate this plan was read from, priced for
  /// [arrivingUsd] (the engine's target), and when: the accept sizes the
  /// move on it while it is fresh ([HyperliquidVenueFunder.freshFirstQuote])
  /// instead of asking Orchestra for the same figure again. Null for a
  /// fallback plan.
  final VenueMoveQuote? quote;
  final DateTime? quotedAt;

  double get moveFeeUsd => math.max(0, fundUsd - arrivingUsd);
}

/// Test seam: stands in for the Dollar deposit door a short hot ticket
/// opens ("Add $X to Investments"), with the prefill it was given.
@visibleForTesting
Future<void> Function(MoveLockedSide side, double? initialTargetUsd)?
    debugShowHlDollarsDeposit;

/// Test seam: stands in for the one approval a funded order asks for.
/// Receives the autofire intent (the order plus its funding limits) and
/// answers with the grant the registry holds for it, or null.
@visibleForTesting
Future<AuthGrant?> Function(SensitiveIntent intent)? debugHlOrderFundingApproval;

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

  /// Optional amount (dollars) the ticket opens with, written as if typed
  /// (a claimed share link's pick, claim_screen.dart). Null opens empty.
  final double? initialUsd;

  /// SEND MODE (screens/share/send_pick_session.dart): the ticket opened
  /// from Send's market search. Its primary sends this investment to a
  /// friend ("Send $50 · Short AMD", slip_share.dart) and nothing is ever
  /// placed; null: the ordinary ticket.
  final SendPickSession? sendPick;

  /// REOPENED from Sal's placing toast (founder, 10 November 2026, on
  /// 2.2.0 (101): "we should just reuse the betslip, the red or green
  /// one"): the ticket opens locked on the standing order the ticket that
  /// was left had accepted, exactly as it was left (its side's colour, the
  /// money's journey in the keypad's place, the "OK"), following that
  /// order: the orders on its market it looks past (every other one,
  /// [StandingOrderToasts.followSet]). Every way back to an order on its
  /// way opens it so (founder, 11 November 2026, on 2.2.0 (104): no white
  /// journey sheet, no Cancel, "OK", its haptics running again;
  /// standing_order_slips.dart), rebuilt from the order's record where
  /// the left ticket was not kept. Null: the ordinary ticket.
  final Set<String>? standingEndedBefore;

  /// THE TICKET IN PLACE (wide layouts, kute_layout.dart: on EXPANDED the
  /// market page's right pane holds the ticket, open, instead of a sheet).
  /// The same ticket, its money rules untouched; only where it sits
  /// changes: no sheet around it and no close button, its corners all
  /// round; its primary button drawn under it in the pane (the bar's own
  /// [KuteBarPrimaryButton], with [embeddedShare] beside it) instead of
  /// in the floating bar; a spot ticket on a token held offers Buy | Sell
  /// (the two doors the trade row had); a hardware keyboard types the
  /// amount. Where the sheet would close (a placed order, the "OK" of an
  /// order on its way) it closes only what stands over the page and calls
  /// [onEmbeddedDone], and the page starts a fresh ticket. Hot account
  /// only, never in send mode.
  final bool embedded;
  final VoidCallback? onEmbeddedDone;
  final KuteBarShare? embeddedShare;

  /// In place as the desk's side panel that opens on Long / Short: its
  /// header's X closes the panel. Null: no X (nothing to close).
  final VoidCallback? onEmbeddedClose;

  /// THE WEB'S MARKET PAGE (founder, 27 November 2026: "why is the right
  /// side so empty?"): the same ticket ([embedded]) always in the page's
  /// right column, under the column's own scroll: a card in the side's
  /// colour sized to its content (not a full-height panel), the amount a
  /// real typed field (a laptop's keyboard; the on-screen number pad is
  /// away). Everything else (the side switch, Max, Advanced, the result
  /// lines, the notices, the primary with its Confirm) is the ticket's
  /// own.
  final bool typedAmount;

  const HlOrderSlipSheet({
    super.key,
    required this.market,
    this.initialIsLong = true,
    this.source,
    this.entrySource,
    this.ledgerWalletId,
    this.initialUsd,
    this.sendPick,
    this.standingEndedBefore,
    this.embedded = false,
    this.onEmbeddedDone,
    this.embeddedShare,
    this.onEmbeddedClose,
    this.typedAmount = false,
  })  : assert(!embedded || (ledgerWalletId == null && sendPick == null)),
        assert(!typedAmount || embedded);

  /// The ticket in place on a wide market page ([embedded]). Hot account
  /// only and never in send mode, so [show]'s one extra door (a Ledger's
  /// Investing gate) has nothing to stop; the open gate runs in the
  /// ticket itself, as it does in the sheet, and again on confirm.
  static HlOrderSlipSheet inPlace({
    Key? key,
    required HlMarket market,
    required String entrySource,
    required VoidCallback onDone,
    KuteBarShare? share,
    bool isLong = true,
    double? initialUsd,
    VoidCallback? onClose,
    String source = 'market_detail',
    bool typedAmount = false,
  }) =>
      HlOrderSlipSheet(
        key: key,
        market: market,
        initialIsLong: isLong,
        initialUsd: initialUsd,
        source: source,
        entrySource: entrySource,
        embedded: true,
        onEmbeddedDone: onDone,
        embeddedShare: share,
        onEmbeddedClose: onClose,
        typedAmount: typedAmount,
      );

  /// What [show] counts as the ticket opens: the flow, the screen and the
  /// one slip-opened event. The desk's side panel counts the same when a
  /// Long / Short opens it (market_detail_sheet.dart).
  static void trackOpened({
    required HlMarket market,
    required bool isLong,
    String? source,
    String? entrySource,
    String? ledgerWalletId,
  }) {
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
  }

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
    double? initialUsd,
    SendPickSession? sendPick,
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
    // No wallet at all (a shared market's guest page): the wallet comes
    // first, then this same ticket (share_wallet_gate.dart).
    if (ledgerWalletId == null &&
        sendPick == null &&
        ShareWalletGate.needsWallet(context)) {
      return ShareWalletGate.open(context,
          target: ShareTarget.of(investing: true, slug: market.wireCoin),
          pick: ShareWalletPick(outcome: isLong ? 'long' : 'short'),
          resume: () {
            if (!context.mounted) return;
            HlOrderSlipSheet.show(context, ref,
                market: market,
                isLong: isLong,
                source: source,
                entrySource: entrySource,
                initialUsd: initialUsd);
          });
    }

    // Counted once the slip actually opens.
    trackOpened(
        market: market,
        isLong: isLong,
        source: source,
        entrySource: entrySource,
        ledgerWalletId: ledgerWalletId);
    if (ledgerWalletId != null) {
      TrackingService.ledgerActionSheetOpened(action: 'hl_order');
    }

    // `enableDrag: false` because swipe-to-dismiss BYPASSES PopScope
    // (long-standing Flutter gap) — that would let a user swipe the
    // sheet away mid-placement. Dismissal is via tap-outside
    // (isDismissible), which DOES go through PopScope.
    _present(
      context,
      HlOrderSlipSheet(
        market: market,
        initialIsLong: isLong,
        source: source,
        entrySource: entrySource,
        ledgerWalletId: ledgerWalletId,
        initialUsd: initialUsd,
        sendPick: ledgerWalletId == null ? sendPick : null,
      ),
    );
  }

  /// The ticket's sheet over everything (the root navigator), as [show]
  /// opens it.
  static Future<void> _present(BuildContext context, HlOrderSlipSheet slip) =>
      showKuteModalSheet(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        isDismissible: true,
        enableDrag: false,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.4),
        routeSettings: const RouteSettings(name: routeName),
        builder: (_) => slip,
      );

  /// Opens the ticket [left] again, locked on its standing order (Sal's
  /// placing toast's tap, [standingEndedBefore]): the same market, side
  /// and amount as it was left. Nothing is counted again (it is the same
  /// ticket, not a new one opened) and no gate runs (nothing new can be
  /// placed from it while its order is on its way). Locked whatever money
  /// journey there is to show (founder, 11 November 2026, on 2.2.0 (109)):
  /// the keypad folded, the order's line placing in its place, "OK";
  /// never the editable form, never checked against a minimum again. It
  /// goes by itself once its order ends with nothing on it to show
  /// (placed, resting, over quietly), and only ever opens on a tap.
  static Future<void> reopenStanding(
    BuildContext context,
    HlOrderSlipSheet left, {
    required bool isLong,
    required double marginUsd,
    required Set<String> endedBefore,
  }) =>
      _present(
        context,
        HlOrderSlipSheet(
          market: left.market,
          initialIsLong: isLong,
          source: left.source,
          entrySource: left.entrySource,
          initialUsd: marginUsd,
          standingEndedBefore: endedBefore,
        ),
      );

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
  double _slippagePct = 1.0;

  /// LEVERAGE IS BLOCKED IN THIS APP (founder, 14 October 2026): every
  /// order this ticket builds is 1x isolated, whatever the policy says
  /// ([kHlMaxOfferedLeverage]). An open position on this market, opened
  /// here or elsewhere at any leverage or in cross, is never rewritten:
  /// the order path sends no leverage write while a position is open, so
  /// an add trades at the venue's own setting for it and is sized here
  /// at 1x (the typed dollars are the notional added).
  int get _leverage => kHlMaxOfferedLeverage;
  bool get _isCross => kHlCrossMarginOffered;

  /// The open-interest cap note was counted (once per ticket).
  bool _oiCapWarned = false;

  // ── Ticket structure ───────────────────────────────────────────────
  _OrderMode _mode = _OrderMode.market;
  _ProType _proType = _ProType.scale;

  /// The Advanced page's floating primary, as last measured (its notes
  /// and steps over the button): the form's foot clears it.
  double _advancedPrimaryHeight = 120;

  /// The full-screen editor shares this ticket's draft and live-price hold.
  bool _advancedRouteOpen = false;
  final _draftChanges = ValueNotifier<int>(0);

  // Advanced inputs.
  late final TextEditingController _priceController; // limit px
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
          // A price left with more precision than the venue takes reads
          // back as the price that will be sent (the order and its
          // approval are built on that same rounded figure).
          if (!node.hasFocus && mounted) _showWirePrice(field);
        });
        return node;
      });

  /// Advanced's rare-controls group. Null until the user touches the
  /// header, so the group opens itself when the ticket already carries a
  /// non-default option and nothing stays hidden behind a chevron.
  bool? _advancedOptionsOpen;

  bool _isPlacing = false;

  /// The cloid of the order this ticket sent last: while the trading
  /// notifier is looking it up after a send with no answer, the busy
  /// button says "Confirming with the exchange…".
  String? _sentCloid;

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

  /// The "Add $X to Investments" tap is running the order through the
  /// normal confirm, to be funded from the person's own bitcoin
  /// ([_confirmFundedFromBitcoin]) where Dollars fall short.
  bool _bitcoinArmed = false;

  /// The bitcoin genuinely could not cover it at the tap: the Dollars door
  /// opens, prefilled with [_bitcoinFallbackUsd].
  bool _bitcoinFellBack = false;

  /// What the Dollars door is prefilled with when [_bitcoinFellBack]: the
  /// X the tap found missing.
  double? _bitcoinFallbackUsd;

  /// The leg [decideSlipFunding] sized at the "Add" tap, reused by the
  /// confirm it runs when it is for the same X.
  BitcoinLegPlan? _bitcoinTapPlan;

  /// Holds the wallet's own Spark address from when "Add" first shows, so
  /// a tap never waits on the SDK for it (see [_warmBitcoinLeg]).
  ProviderSubscription<AsyncValue<String>>? _ownSparkWarm;

  /// Whether [_warmBitcoinLeg] already ran for this ticket.
  bool _ownSparkWarmed = false;

  /// The Bitcoin-funded run this ticket started, if any.
  String? _bitcoinRunId;

  /// From a Deposit door tap until the Move sheet opens: the top-up is
  /// being worked out. The button shows it and the form is frozen, so the
  /// sheet is sized for the order on the ticket at the tap.
  bool _depositCalculating = false;

  // ── Per-order funding (one balance) ───────────────────────────────
  // A hot ticket short of venue cash funds the shortfall from Dollars on
  // the same tap that places the order: one approval, "Preparing your
  // order", then the placing tile and the receipt. The plan below is
  // what the ticket shows before the tap (the Move fee row and the
  // Dollars check); the controller quotes again when the money moves.

  /// The venue cash the order on the ticket still needs, as computed in
  /// the last build (zero when it is covered, or on a Ledger ticket).
  double _slipShortfallUsd = 0;

  /// The funding the ticket currently shows, for [_slipShortfallUsd].
  _FundPlan? _fundPlan;

  /// This order is funded into an account that holds nothing yet: the
  /// one-time builder-fee approval cannot be signed before the money
  /// lands, so the auto-fire signs it after the credit, before placing.
  bool _deferBuilderApproval = false;

  /// Dollars cover the move the ticket shows (set in build).
  bool _canFundFromDollars = false;

  /// The shortfall the plan (or the estimate on its way) is for.
  String? _fundPlanKey;

  /// The multi-source move this order's funding pulled venue cash under,
  /// and the funding it was for: another Confirm of the same funding
  /// continues it (money already moved is reused, never pulled twice).
  String? _moveId;
  double? _moveUsd;
  Timer? _fundPlanTimer;

  /// Where a funded order is, from the tap to the placement. Null while
  /// nothing is being funded.
  OrderFundingStage? _fundingStage;
  DateTime? _fundingStartedAt;
  ProviderSubscription<PendingHlOrderIntent?>? _pendingSub;

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
  // none (opened empty) | prefill (carried in) | keypad | max | min (the
  // under-the-minimum button wrote and placed it) | min_direct (the empty
  // ticket's button placed the minimum)
  String _amountMethod = 'none';

  /// The empty ticket's button wrote the minimum; the next build places
  /// it if the ticket can be confirmed at it ([_placeMinimum]).
  bool _placeMinimumOnBuild = false;

  /// With [_placeMinimumOnBuild]: the under-the-minimum button wrote it,
  /// so the next build places it only through the order's own confirm,
  /// never a deposit door ([_placeFilledMinimum]).
  bool _placeMinimumTradeOnly = false;
  late final String _settingsScope = 'hl_slip_${identityHashCode(this)}';

  String get _entrySource => widget.entrySource ?? widget.source ?? 'unknown';

  /// The ticket as it stands (no ref reads: used from dispose).
  Map<String, Object> _slipInputs() {
    final lev = isSpot ? 1 : _leverage;
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

  /// [_openGateMessage] is a region refusal: the one button is "Check
  /// connection" ([_checkConnection]).
  bool _openGateRegion = false;

  /// "Check connection" is asking the venues and the policy again.
  bool _checkingConnection = false;

  /// A send's tap is asking the open gate again ([_sendTapped]).
  bool _sendAsking = false;

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
    CapabilityUnavailableException? denial;
    try {
      await ref
          .read(runtimeCapabilitiesProvider)
          .ensureAllAllowed(hlOpenCapabilities(market));
    } on CapabilityUnavailableException catch (error) {
      message = error.decision.message;
      regionBlocked = error.decision.regionBlocked;
      denial = error;
    } on ProviderAvailabilityException catch (error) {
      message = error.availability.message;
      regionBlocked =
          error.availability.status == ProviderAvailabilityStatus.restricted;
    } catch (_) {
      // Unanswered: confirm asks again and says why there. An unanswered
      // check never shows a refusal, so one shown earlier goes too.
    }
    if (!mounted || _isPlacing || _orderInFlight) return;
    if (message == null) {
      // Allowed now: a refusal shown earlier (asked again after a network
      // change or resume) goes away.
      if (_openGateMessage != null) {
        _updateDraft(() {
          _openGateMessage = null;
          _openGateRegion = false;
        });
      }
      return;
    }
    // Counted once per refusal shown, not again for each re-check.
    if (regionBlocked && _openGateMessage == null) {
      TrackingService.hyperliquidGeoblockedShown();
      if (denial != null) {
        TrackingService.capabilityRegionBlocked(denial.capability,
            blockedBy: denial.decision.blockedBy,
            surface:
                widget.sendPick != null ? kSendModeSlipSource : 'order_slip');
      }
    }
    _updateDraft(() {
      _openGateMessage = message;
      _openGateRegion = regionBlocked;
    });
  }

  /// "Check connection" on a region refusal (founder decision, October
  /// 2026): the person says their connection changed, so the venues and
  /// Kute's policy are asked again ([RegionFreshness.checkConnection]).
  /// Allowed now: the refusal goes and the button is the order again,
  /// ready to place (a Ledger ticket follows the policy it watches).
  /// Still restricted: the refusal stays, with the soft failure tap, and
  /// the button can be tapped again. A check that could not be made never
  /// shows restricted.
  Future<void> _checkConnection() async {
    if (_checkingConnection) return;
    setState(() => _checkingConnection = true);
    await RegionFreshness.checkConnection();
    if (!mounted) return;
    final capabilities = _isLedger
        ? const ['hyperliquid.browse']
        : hlOpenCapabilities(market);
    if (!RegionFreshness.regionRefused(capabilities: capabilities)) {
      _updateDraft(() {
        _checkingConnection = false;
        _openGateMessage = null;
        _openGateRegion = false;
      });
      // The rest of the open gate, as when the ticket opened.
      if (!_isLedger) unawaited(_resolveOpenGate());
      return;
    }
    setState(() => _checkingConnection = false);
    moneyFailureFeedbackAfterBand(() => mounted && _checkingConnection);
  }

  void _onRegionAnswers() {
    if (!mounted || _openGateMessage == null) return;
    unawaited(_resolveOpenGate());
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
    // The funding legs the order needs (every leg's fee, an estimate), so
    // the placed / failed event carries them too.
    Map<String, Object> funding = const {};
    try {
      funding = fundingFeeAnalytics(_fundingFeesNow());
    } catch (_) {}
    final inputs = {..._slipInputs(), ...funding};
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
        'funding_fee_estimated_usd',
        'funding_legs',
        'funding_sources',
      ])
        if (inputs[k] != null) k: inputs[k]!,
    });
    _stagedOwn = VenueAnalytics.staged('hl', market.coin);
    TrackingService.track('hyperliquid_order_submitted', params: {
      ...inputs,
      // What the order does to the position held here (perps only):
      // open | add | reduce | close | flip.
      if (_positionEffectName != null) 'position_effect': _positionEffectName!,
      'time_in_flow_ms': DateTime.now().difference(_openedAt).inMilliseconds,
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

  /// What the ticket sends in send mode, read at each build and at the
  /// tap (screens/share/slip_share.dart): this market by the wire coin the
  /// Claim screen resolves, Long or Short, the amount typed. A spot sale
  /// is no investment to send: the market's card alone.
  SlipSharePick _slipSharePick({required double minUsd, required bool blocked}) {
    final name = hlFriendlyName(market.coin) ?? market.coin;
    final mid = market.midPx > 0 ? market.midPx : market.markPx;
    final selling = isSpot && !_isLong;
    return SlipSharePick(
      investing: true,
      slug: market.wireCoin,
      marketLinkSlug: market.coin,
      title: name,
      outcome: _isLong ? _strings.longLabel : _strings.shortLabel,
      side: _isLong ? 'long' : 'short',
      sideLabel: _isLong ? _strings.longLabel : _strings.shortLabel,
      amountUsd: _marginUsd,
      minUsd: minUsd,
      minLabel: formatHlUsd(minUsd),
      blocked: blocked,
      cardOnly: selling,
      price: mid > 0
          ? formatHlPrice(mid, decimalCap: market.pxDecimalCap)
          : null,
      ticker: name != market.coin ? market.coin : null,
      wireCoin: market.wireCoin,
      coinCategory: market.category,
      coinIconUrl: market.iconUrl,
      reachUsd: ref.read(giftSpendableProvider),
    );
  }

  /// A tap on the send: the open gate is asked again first, its answer at
  /// open landing behind the first frame, and a refused market creates no
  /// link (screens/share/slip_share.dart).
  Future<void> _sendTapped(SendPickSession session,
      {required double minUsd}) async {
    if (_sendAsking) return;
    setState(() => _sendAsking = true);
    await _resolveOpenGate();
    if (!mounted) return;
    setState(() => _sendAsking = false);
    if (_openGateMessage != null) return;
    await sendFromSlip(
        context, _slipSharePick(minUsd: minUsd, blocked: false),
        session: session);
  }

  /// SEND MODE's one primary (screens/share/slip_share.dart): "Send $50 ·
  /// Short AMD", disabled with the step to take, or under the gate's reason
  /// where this market is refused. A region's refusal is the ticket's own
  /// "Check connection", the send again once that finds it open. Never an
  /// order.
  KuteBarContext _sendBarContext(SendPickSession session,
      {required double minUsd}) {
    if (_openGateMessage != null && _openGateRegion) {
      return KuteBarContext.primary(
        label: context.l10n.checkConnection,
        onPrimary: _checkingConnection ? null : _checkConnection,
        enabled: !_checkingConnection,
        busy: _checkingConnection,
        busyLabel: context.l10n.checkConnection,
        category: SearchCategory.perpetuals,
        source: 'order_slip',
        // Never waits on input.
        disabledLabel: null,
      );
    }
    final cta = slipSendCta(context.l10n,
        _slipSharePick(minUsd: minUsd, blocked: _openGateMessage != null));
    return KuteBarContext.primary(
      label: cta.label,
      onPrimary: cta.enabled && !_sendAsking
          ? () => unawaited(_sendTapped(session, minUsd: minUsd))
          : null,
      enabled: cta.enabled,
      busy: _sendAsking,
      category: SearchCategory.perpetuals,
      source: 'order_slip',
      disabledLabel: cta.disabledLabel,
    );
  }
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
          case _ProType.twap:
            return 'twap';
        }
    }
  }

  @override
  void initState() {
    super.initState();
    _isLong = widget.initialIsLong;
    // Opens empty, typed from zero; the button offers the minimum this
    // order needs ([_orderMinimumUsd], [_placeMinimum]). A carried-in
    // amount (a claimed pick) is written as if typed.
    final carried = widget.initialUsd;
    final prefilled = carried != null && carried > 0;
    _marginUsd = prefilled ? carried : 0;
    // Reopened from Sal's placing toast: locked on the order the left
    // ticket accepted, as that ticket was once it accepted.
    if (widget.standingEndedBefore case final ended?) {
      _standingAccepted = true;
      _standingEndedBefore = ended;
      // Reopened on an order on record: its record going is its end.
      _standingSeen = _standingOrderIn(
              ref.read(standingOrdersProvider), market.coin, ended) !=
          null;
    }
    _amountController = TextEditingController(
        text: prefilled ? _trimZeros(carried.toStringAsFixed(2)) : null);
    if (prefilled) _amountMethod = 'prefill';
    _amountController.addListener(_onAmountChanged);
    _priceController = TextEditingController();
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

    if (widget.embedded) HardwareKeyboard.instance.addHandler(_onHardwareKey);
    if (!_isLedger) {
      unawaited(_resolveOpenGate());
      // A refusal worked out at open belongs to the network it was asked
      // on: after a resume, a network or VPN change, or a venue answer
      // that flipped, the gate asks again and lifts it when it is gone.
      RegionFreshness.answers.addListener(_onRegionAnswers);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Live mid for the preview (and the stale guard).
      _livePrices?.watchCoins([market.coin]);
      _livePrices?.focus(market.coin, wire: market.wireCoin);
    });
  }

  @override
  void dispose() {
    _streamSettle?.cancel();
    if (widget.embedded) {
      HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    }
    if (!_isLedger) RegionFreshness.answers.removeListener(_onRegionAnswers);
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
          'time_in_flow_ms':
              DateTime.now().difference(_openedAt).inMilliseconds,
          'time_in_flow_bucket': VenueAnalytics.timeInFlowBucket(
              DateTime.now().difference(_openedAt)),
        });
      } catch (_) {}
    }
    // The person closed the ticket while its funding was still going:
    // the queued order carries on off-screen (the tile and the receipt
    // overlay still show), the ticket just stops watching.
    if (_fundingStage != null && !_completed) {
      try {
        TrackingService.track('order_funding_abandoned', params: {
          'venue': 'hyperliquid',
          'stage': _fundingStage!.name,
        });
      } catch (_) {}
    }
    _pendingSub?.close();
    _ownSparkWarm?.close();
    _ownSparkWarm = null;
    _fundPlanTimer?.cancel();
    TrackingService.clearFlowContext('hl_order');
    // A market order still waiting for its answer keeps its staged
    // settings for its placed / failed event ([_answerPending]).
    if (!_answerPending) VenueAnalytics.unstage('hl', market.coin);
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
    _typedFocus.dispose();
    _priceController.dispose();
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

  /// The position on this market as the account this ticket trades
  /// positively knows it (hl_exposure_rule.dart): the Ledger's own reads,
  /// or the spending wallet's account read. Unknown while it loads.
  HlHeldPosition _heldPositionNow() {
    if (isSpot) return const HlHeldPosition.flat();
    if (_isLedger) {
      return ledgerHlHeldPosition(
          ref.watch(ledgerHlAccountProvider(widget.ledgerWalletId!)).valueOrNull,
          market);
    }
    return HlHeldPosition.fromSnapshot(
        market, ref.watch(hyperliquidAccountProvider).valueOrNull);
  }

  /// What the exposure rule says of the ticket's order of [size] coins
  /// against [held]: null when it may go as the ticket sends it. At market
  /// a reduce or a close goes out reduce-only ([_confirmExit]); the other
  /// types only with Reduce only on. LEVERAGE IS BLOCKED: on a market held
  /// above 1x or in cross, nothing that adds to or flips the position.
  HlExposureRefusal? _exposureRefusal(HlHeldPosition held, double size) {
    if (isSpot) return null;
    final atMarket = _mode == _OrderMode.market;
    final check = hlExposureCheck(
      market: market,
      held: held,
      isBuy: _isLong,
      size: size,
      reduceOnly: !atMarket && _reduceOnly,
    );
    final plan = hlPositionPlan(
      position: held.position,
      orderIsLong: _isLong,
      orderSize: size,
      szDecimals: market.szDecimals,
    );
    return check.refusalFor(
        sentReduceOnly: atMarket ? plan.isExit : _reduceOnly);
  }

  /// [_exposureRefusal] at the tap, before any approval or money: the
  /// position read fresh when the account has not been read yet (one read
  /// of this market's dex; a loaded account reads nothing).
  Future<HlExposureRefusal?> _exposureRefusalAtTap() async {
    if (isSpot || _isLedger) return null;
    final held = await ref.read(hlHeldPositionProvider)(market);
    return _exposureRefusal(held, _currentPlan().orderSize);
  }

  /// The last plan the ticket showed, for the order-submitted event.
  String? _positionEffectName;

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

  /// "12.00" -> "12", "12.50" -> "12.5": the figure as the keypad would
  /// leave it.
  static String _trimZeros(String fixed) => fixed.contains('.')
      ? fixed.replaceFirst(RegExp(r'\.?0+$'), '')
      : fixed;

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
  /// [haptic] false when an order follows on the same tap and brings its
  /// own. Max and the minimum report `order_slip_available_tapped`, as the
  /// bet slip's chips do; the empty ticket's button ('min_direct') rides
  /// on the order's own `amount_method`.
  void _fillAmountChip(double usd, String method, {bool haptic = true}) {
    if (usd <= 0) return;
    if (haptic) HapticFeedback.selectionClick();
    _onKeypadAmount(usd.toStringAsFixed(2));
    _amountMethod = method;
    if (method == 'max' || method == 'min') {
      TrackingService.track('order_slip_available_tapped', params: {
        'chip': method,
        'venue': 'hyperliquid',
        'kind': isSpot ? 'spot' : 'perp',
        // What the chip wrote, exact; on Max, what the spending Bitcoin
        // lands of it (since kute-wallet d0f76b8 Max counts it too).
        ...TrackingService.exactUsd('amount_usd', usd),
        if (method == 'max' && _maxBitcoinUsd > 0)
          ...TrackingService.exactUsd('bitcoin_usd', _maxBitcoinUsd),
      });
    }
  }

  /// What the spending Bitcoin lands, as the Max chip last counted it
  /// (zero on a Ledger or a sell): `order_slip_available_tapped`'s
  /// `bitcoin_usd`.
  double _maxBitcoinUsd = 0;

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
    _placeMinimumTradeOnly = false;
    _fillAmountChip(minAmountUsd, 'min_direct', haptic: false);
  }

  /// The button while the amount is under the minimum: writes
  /// [minAmountUsd] the way the keypad would, and the next build places it
  /// through the normal confirm when the ticket can be confirmed at it.
  /// When the minimum needs money added first it is only written, and the
  /// button turns into the door for it.
  void _placeFilledMinimum(double minAmountUsd) {
    if (minAmountUsd <= 0) return;
    _placeMinimumOnBuild = true;
    _placeMinimumTradeOnly = true;
    _fillAmountChip(minAmountUsd, 'min', haptic: false);
  }

  /// Nothing typed on a market order with a minimum of [minAmountUsd]:
  /// the empty ticket's button is the order at that minimum.
  bool placesMinimumAmount(double minAmountUsd) =>
      _marginUsd <= 0 &&
      _mode == _OrderMode.market &&
      !_reduceOnly &&
      minAmountUsd > 0;

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

  /// Rewrites a price field to its wire-rounded value ([_wirePx]) once it
  /// is left, so the ticket shows the price the order will carry.
  void _showWirePrice(_NumField f) {
    switch (f) {
      case _NumField.limitPrice:
      case _NumField.scaleStart:
      case _NumField.scaleEnd:
      case _NumField.takeProfit:
      case _NumField.stopLoss:
        break;
      default:
        return;
    }
    final c = _controllerFor(f);
    final typed = _parse(c);
    final wire = _wirePx(typed);
    if (typed == null || wire == null || wire == typed) return;
    try {
      c.text = roundPrice(typed, szDecimals: market.szDecimals, isSpot: isSpot);
    } catch (_) {
      return;
    }
    _updateDraft(() {});
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
        // The page; the shared panel on EXPANDED (kute_form_panel_route).
        kuteFormPanelRoute<void>(
          context,
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
      // are placed from the Advanced page itself. Not while the order
      // placed from there is still on its way: the ticket stays that
      // order (its locked line, its receipt) until it ends.
      if (mounted && !_advancedOrderUnderway) _resetAdvanced();
    }
  }

  /// The order placed from the Advanced page has not ended on this ticket
  /// yet: it is being prepared, placed or funded, accepted as a standing
  /// order, unconfirmed, or already on its receipt.
  bool get _advancedOrderUnderway =>
      _standingAccepted ||
      _isPlacing ||
      _preparing ||
      _orderInFlight ||
      _completed ||
      _unconfirmedLock ||
      _fundingStage != null;

  /// Returns every Advanced-only setting to the ticket's opening state:
  /// each field back to what [initState] gave it (the scale's 5 orders,
  /// the TWAP's 30 minutes), so a type picked again opens valid.
  void _resetAdvanced() {
    _updateDraft(() {
      _mode = _OrderMode.market;
      _proType = _ProType.scale;
      _tif = 'Gtc';
      _postOnly = false;
      _reduceOnly = false;
      _randomizeTwap = false;
      _attachTpSl = false;
      _attachTrailing = false;
      _trailPercent = true;
      _trailActivate = false;
      _slippagePct = 1.0;
      _advancedOptionsOpen = null;
      for (final controller in [
        _priceController,
        _startPxController,
        _endPxController,
        _tpController,
        _slController,
        _trailActivationController,
      ]) {
        controller.clear();
      }
      _countController.text = '5';
      _twapMinutesController.text = '30';
      _trailDistanceController.text = '1';
    });
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
        // A ladder rests on its own side of the price, the way a person
        // would set one: a buy from 1% to 5% under it, a sell over it.
        // Both equal to the price would cross the book at once.
        final mid = _midNow();
        _prefill(_startPxController, mid * (_isLong ? 0.99 : 1.01));
        _prefill(_endPxController, mid * (_isLong ? 0.95 : 1.05));
      case _ProType.twap:
        _reduceOnly = false;
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
    // Against the other side, or added to a position held above 1x or in
    // cross (refused by the exposure rule; its liquidation is the venue's
    // own, from that position's margin, never this ticket's 1x isolated
    // figure): no estimate here.
    if (existing != null &&
        (existing.isLong != _isLong || hlPositionIsLeveraged(existing))) {
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
        return _parsePx(_priceController) ?? mid;
      case _OrderMode.pro:
        switch (_proType) {
          case _ProType.scale:
            final s = _parsePx(_startPxController);
            final e = _parsePx(_endPxController);
            if (s != null && e != null) return (s + e) / 2;
            return s ?? e ?? mid;
          case _ProType.twap:
            return mid;
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
      if (_isTwap) {
        return _strings.hlAdvTwapMinimum(formatHlUsd(HlTwapRules.minAmountUsd(
            referencePx: _midNow(),
            szDecimals: market.szDecimals,
            leverage: isSpot ? 1 : _leverage)));
      }
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
      _attachTpSl ||
      _attachTrailing ||
      _slippagePct != 1.0;

  Future<void> _handleConfirm() async {
    if (_isLedger) {
      await _confirmLedger();
      return;
    }
    if (_orderInFlight || _isPlacing || _unconfirmedLock) return;
    // A new try: an earlier funded order's stop gives way to it, and the
    // ticket is locked while it places until its own accept.
    _clearFundedStop();
    _standingAccepted = false;
    _standingEndedBefore = null;
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

    // The exposure rule before anything is approved, signed or moved (an
    // add to, or a flip of, a position held above 1x or in cross; or a
    // position that cannot be read).
    final exposure = await _exposureRefusalAtTap();
    if (!mounted) return;
    if (exposure != null) {
      _trackBlocked(exposure == HlExposureRefusal.positionUnknown
          ? 'position_unknown'
          : 'leveraged_position');
      _updateDraft(() => _errorText = hlExposureRefusalText(_strings, exposure));
      return;
    }

    // The venue's cash read fresh, not the last poll: a close a moment
    // ago, a sweep or a credit since changes what the order needs moved.
    await _refreshVenueCashNow();
    if (!mounted) return;

    // An account Hyperliquid has never funded cannot post the signed
    // builder-fee approval; an order that funds it signs it after the
    // money lands instead (the auto-fire, before placing).
    _deferBuilderApproval = hlDeferBuilderApproval(
        accountUnfunded: _accountUnfunded(), shortfallUsd: _shortfallNow());
    if (!_deferBuilderApproval &&
        !await ensureHotHlBuilderFeeConsent(context, ref)) {
      _trackBlocked('builder_fee');
      return;
    }
    if (!mounted) return;

    final mid = _lastMid ?? (market.midPx > 0 ? market.midPx : market.markPx);
    if (mid <= 0) {
      _trackBlocked('no_price');
      return;
    }

    // The ticket's prices against the price now, before any approval.
    if (!_pricesStillHold()) return;
    // An earlier order on this market of this account is still being
    // looked up: never a possible duplicate of it.
    if (!_isLedger &&
        hlMarketConfirming(ref.read(hlConfirmingMarketsProvider),
            account:
                ref.read(hyperliquidTradingProvider.notifier).accountAddress,
            wireCoin: market.wireCoin)) {
      _trackBlocked('order_confirming');
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
    _sentMarket = true;
    // The stream closes the ticket on the order's whole size before the
    // venue answers, unless something rides on it whose fate only the
    // answer says (a take-profit / stop-loss leg, a trailing stop placed
    // after the fill).
    final attached = (_trailingAvailable && _attachTrailing) ||
        (!isSpot &&
            _attachTpSl &&
            (_parsePx(_tpController) != null ||
                _parsePx(_slController) != null));
    _sentMarketAttached = attached;
    _sentMarketSize = attached ? 0 : size;
    if (plan.isExit) {
      if (size <= 0) {
        _trackBlocked('below_min');
        return;
      }
      await _confirmExit(plan);
      return;
    }
    // An open or add is sized again by the notifier after funding, at the
    // live price: the stream closes on the size it actually sends
    // ([_onMarketSent]), never on this ticket's own estimate.
    if (!isSpot) _sentMarketSize = 0;
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
    // The venue cannot cover the order yet: fund the difference from
    // Dollars on this same tap, then place it once the money lands.
    final shortfall = _shortfallNow();
    if (shortfall > 0) {
      await _confirmFunded(
        walletId: walletId,
        cloid: cloid,
        mid: mid,
        shortfallUsd: shortfall,
        orderKind: 'market',
        resizable: true,
        orderAt: _marketOrderAt(walletId, cloid),
      );
      return;
    }
    _trackStep('approval');
    final grant = await _approve(
      _marketOrder(walletId, cloid).intent,
      amountUsd: _marginUsd,
      smallAction: SmallActionContext.usd(_marginUsd),
    );
    if (grant == null || !mounted) {
      if (grant == null) _stopped('signing_declined');
      return;
    }
    // The price moved while the approval was up: re-checked right before
    // signing, nothing sent when it crossed.
    if (!_pricesStillHold()) {
      grant.revoke();
      return;
    }

    // Pre-existing SIGNED size so the placing tile reconciles on the
    // position delta, not the absolute size.
    double preExisting = 0;
    for (final p in ref.read(hyperliquidPerpPositionsProvider)) {
      if (p.coin == market.wireCoin) {
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
      // Only this order's own fills, by its cloid: never a same-coin fill
      // with no cloid or another's.
      if (!hlFillOfOrder(market, cloid, f)) return;
      _orderFills.add(f);
      // The stream closes the ticket once these fills come to the whole
      // size asked for, or once the answer was unclear; a part waits for
      // the answer, which says what filled ([_settleFromStream]).
      _settleFromStream();
    });

    _updateDraft(() {
      _isPlacing = true;
      _sentCloid = cloid;
      _errorText = null;
      _errorCause = null;
    });

    try {
      // Rebuilt from the ticket as it is now. Anything that changed since
      // the approval (leverage, side, amount) makes the notifier throw
      // ReauthRequired before it signs.
      _submitted = true;
      _trackSubmitted();
      _answerPending = true;
      // Closed on the order's own fills meanwhile: the answer, whatever
      // it is, only marks the tile placed ([hlMarketAnswer]).
      final result = await hlMarketAnswer(
          _marketOrder(walletId, cloid).place(grant),
          closed: () => _completed,
          onClosed: () => placing.markSucceeded(placementId));
      if (result == null) return;
      placing.markSucceeded(placementId);
      if (result.filledSz > 0) {
        final trailNote = await _placeAttachedTrailing(result.filledSz);
        if (!mounted) return;
        final fills = _sentPlan?.effect == HlPositionEffect.flip
            ? await _fillsOf(result)
            : const <HlFill>[];
        if (!mounted) return;
        _onFilled(
            sizeFilled: result.filledSz,
            avgPx: result.avgPx,
            fills: fills,
            notices: [
              ...hlOrderResultNotices(_strings, result),
              if (trailNote != null) trailNote,
            ]);
      } else {
        // Accepted but not (yet) filled — the WS listener / placing
        // tile takes over; close the slip so the user isn't trapped.
        if (mounted && !_completed) {
          _closeTicket();
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
      if (e is HyperliquidOrderUnconfirmedException) {
        // Sent, and nobody has heard back: never "failed". The tile stays
        // confirming and the fill listener stays on, so a fill that lands
        // still ends on the receipt.
        placing.markConfirming(placementId);
      } else {
        placing.markFailed(placementId, _messageFor(e));
      }
      if (mounted) {
        _updateDraft(() {
          _isPlacing = false;
          // The venue may hold it: this ticket never sends it again
          // ([_unconfirmedLock]).
          if (e is HyperliquidOrderUnconfirmedException) {
            _unconfirmedLock = true;
          }
          _errorText = _messageFor(e);
          _errorCause = e;
        });
        // Fills of it the stream already brought end on the receipt.
        if (e is HyperliquidOrderUnconfirmedException) _settleFromStream();
      }
    } finally {
      _answerPending = false;
      // Closed on the stream before the answer: the settings staged for
      // the order's placed / failed event stayed for it until now.
      if (!mounted) _unstageOwn();
    }
  }

  /// A market order this ticket sent is still waiting for the venue's
  /// answer: the ticket may close on its fills first, and the settings
  /// staged for its placed / failed event ([_trackSubmitted]) stay until
  /// the answer is in.
  bool _answerPending = false;

  /// The settings this ticket staged for its order's event, to unstage
  /// them only while they are still this ticket's.
  Map<String, Object>? _stagedOwn;

  void _unstageOwn() {
    final own = _stagedOwn;
    if (own == null ||
        identical(VenueAnalytics.staged('hl', market.coin), own)) {
      VenueAnalytics.unstage('hl', market.coin);
    }
  }

  /// The size the market order sent asks for, for the stream to close the
  /// ticket on its whole fill before the answer ([hlStreamReceipt]); 0
  /// when something rides on it whose fate only the answer says.
  double _sentMarketSize = 0;

  /// The market order sent has a take-profit / stop-loss leg or a trailing
  /// stop riding on it: the stream never closes it before the answer.
  bool _sentMarketAttached = false;

  /// The notifier's word of the size it is sending ([HyperliquidTrading
  /// Notifier.openPosition]'s onSent): what the stream close compares the
  /// ticket's own fills against.
  void _onMarketSent(double size) {
    if (!mounted) return;
    _sentMarketSize = _sentMarketAttached ? 0 : size;
    _settleFromStream();
  }

  /// Closes the ticket on its order's own fills from the stream, totalled
  /// ([hlOwnFillsTotal]), once they come to the whole size asked for
  /// ([_sentMarketSize]) or once the venue's answer was unclear
  /// ([_unconfirmedLock]); a part waits for the answer, which says what
  /// filled. The fills of one match are gathered a moment
  /// ([kHlStreamFillsSettle]) first, so a multi-fill order is never said
  /// as its first fill.
  void _settleFromStream() {
    if (_completed) return;
    ({double size, double avgPx})? receipt() => hlStreamReceipt(
        unconfirmed: _unconfirmedLock,
        market: _sentMarket,
        own: _orderFills,
        requestedSize: _sentMarketSize,
        sizeStep: _sizeStep);
    if (receipt() == null) return;
    _streamSettle?.cancel();
    _streamSettle = Timer(kHlStreamFillsSettle, () {
      _streamSettle = null;
      if (!mounted || _completed) return;
      final total = receipt();
      if (total == null) return;
      _onFilled(
          sizeFilled: total.size,
          avgPx: total.avgPx,
          fills: List.of(_orderFills));
    });
  }

  Timer? _streamSettle;

  /// Whether the order this ticket sent last is a market order (as sent;
  /// the ticket's mode may change under a locked ticket).
  bool _sentMarket = false;

  /// After an unclear answer ([_unconfirmedLock]): the ticket goes and
  /// the orders ([resting]) or what is held opens, to check the order
  /// there. A fresh ticket is a fresh order, never locked; while the
  /// order's lookup is still running no ticket on the market sends
  /// ([hlConfirmingMarketsProvider]).
  void _viewAfterUnconfirmed({required bool resting}) {
    final nav = Navigator.of(context, rootNavigator: true);
    _closeTicket();
    if (resting) {
      openInvestmentsOrders(nav.context,
          product: 'investing', orderKind: 'open');
    } else {
      openInvestmentsPositions(nav.context);
    }
  }

  /// The ticket's prices against the price as it is right now, re-checked
  /// before anything is sent and again after the approval, right before
  /// signing (the price moves while Face ID is up): a scale ladder on its
  /// side of the price ([hlScaleSideIssue]), an opening order's take-profit
  /// and stop-loss on their side of its entry ([hlTpSlEntryIssue]). Crossed:
  /// the inline message, nothing sent, false.
  bool _pricesStillHold() {
    final live = ref.read(hyperliquidLiveMidProvider(market.coin));
    final mid = (live != null && live > 0) ? live : _midNow();
    String? issue;
    if (_isScale) {
      final s = _parsePx(_startPxController);
      final e = _parsePx(_endPxController);
      if (s != null && e != null && s != e) {
        issue = hlScaleSideIssue(_strings,
            isLong: _isLong, startPx: s, endPx: e, mid: mid);
      }
    }
    if (_isOpening && _attachTpSl) {
      issue = hlTpSlEntryIssue(_strings,
              isLong: _isLong,
              entry: _entryPx(mid),
              takeProfit: _parsePx(_tpController),
              stopLoss: _parsePx(_slController)) ??
          issue;
    }
    if (issue == null) return true;
    _trackBlocked('price_moved');
    if (mounted) {
      _updateDraft(() {
        _lastMid = mid;
        _errorText = issue;
        _errorCause = null;
      });
    }
    return false;
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
      // What the close takes off: the position's value for that share.
      smallAction:
          SmallActionContext.usd(pos.positionValue.abs() * fraction),
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
      if (hlFillOnMarket(market, f)) _orderFills.add(f);
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
        // The whole position closed: its left-over stops, takes and
        // trailing stops are cancelled by the notifier once it is gone
        // (as from the close sheet); the receipt waits to say what it did.
        final leftovers = pos.szi.abs() > 0 &&
                result.filledSz >= pos.szi.abs() * (1 - 1e-9)
            ? await _leftoverSweepOf(trading, pos.coin)
            : null;
        if (!mounted) return;
        _onFilled(
            sizeFilled: result.filledSz,
            avgPx: result.avgPx,
            fills: fills,
            leftovers: leftovers);
      } else if (!_completed) {
        _closeTicket();
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

  /// What the cancel of [coin]'s left-over protective orders did, awaited
  /// ([HyperliquidTradingNotifier.leftoverSweepFor]); null when none ran.
  Future<HlLeftoverSweep?> _leftoverSweepOf(
      HyperliquidTradingNotifier trading, String coin) async {
    final sweep = trading.leftoverSweepFor(coin);
    if (sweep == null) return null;
    try {
      return await sweep;
    } catch (_) {
      return null;
    }
  }

  /// The whole position on this market (perps, hot account) goes with the
  /// order on the ticket as the notifier arms it (a close sized to it, or
  /// reduce-only sized past it), and protective orders rest on it: the
  /// close sheet's line before Confirm, the count of those orders. Null
  /// otherwise.
  int? _closeCancelsCount(
      {required HlPositionPlan marketPlan, required double legSize}) {
    if (isSpot || _isLedger || widget.sendPick != null) return null;
    final bool whole;
    if (_mode == _OrderMode.market) {
      whole = _netsAgainstPosition &&
          marketPlan.effect == HlPositionEffect.close;
    } else if (_mode == _OrderMode.limit || _isTwap) {
      final plan =
          _positionPlanFor(_mode == _OrderMode.limit ? _limitSizeNow() : legSize);
      whole = plan.effect == HlPositionEffect.close ||
          (_reduceOnly && plan.effect == HlPositionEffect.flip);
    } else {
      whole = false;
    }
    if (!whole) return null;
    final orders = ref.watch(hyperliquidTradingProvider).valueOrNull?.openOrders ??
        const <HlOpenOrder>[];
    final n = hlProtectiveOrdersFor(orders, market.wireCoin).length;
    return n == 0 ? null : n;
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
    _sentMarket = false;
    // What the receipt says about the order, as it is sent: the ticket
    // behind it may change (or be reset) before the venue answers.
    _sentReceipt = _receiptNow();
    final isLimit = _mode == _OrderMode.limit;
    _sentLimitSize = isLimit ? _limitSizeNow() : 0;
    _orderFills.clear();
    // A resting order needs its margin as much as a market one: fund the
    // difference from Dollars, then place it exactly as approved (never
    // resized) once the money lands.
    final shortfall = _reduceOnly ? 0.0 : _shortfallNow();
    if (shortfall > 0) {
      await _confirmFunded(
        walletId: walletId,
        cloid: cloid,
        mid: mid,
        shortfallUsd: shortfall,
        orderKind: _mode == _OrderMode.limit ? 'limit' : 'pro',
        resizable: false,
        // Built once, here: the call captures the ticket's values and
        // may run after the ticket is gone.
        orderAt: (_) => approved,
      );
      return;
    }
    _trackStep('approval');
    final grant = await _approve(approved.intent,
        amountUsd: _marginUsd,
        smallAction: SmallActionContext.usd(_marginUsd));
    if (grant == null || !mounted) {
      if (grant == null) _stopped('signing_declined');
      return;
    }
    // Re-checked against the price now, right before signing.
    if (!_pricesStillHold()) {
      grant.revoke();
      return;
    }

    // Limit orders may fill immediately — listen for the matching fill by
    // cloid. Scale/TWAP/trigger fills don't carry our cloid (and rest
    // rather than fill on placement), so we don't listen for them: they
    // resolve via _onRestingAccepted, and matching a cloid-less fill here
    // would risk latching onto an unrelated fill mid-submit.
    if (isLimit) {
      _fillSub?.cancel();
      _fillSub =
          ref.read(hyperliquidUserEventsProvider.notifier).fills.listen((f) {
        // Only our own cloid-tagged fills.
        if (!hlFillOfOrder(market, cloid, f)) return;
        _orderFills.add(f);
        // The stream closes the ticket on the WHOLE order only: a part
        // filled is said by the venue's answer ([_onLimitAnswered]), with
        // what still rests.
        final filled = _fillsSize(_orderFills);
        if (_sentLimitSize > 0 && filled >= _sentLimitSize - _sizeStep / 2) {
          _onFilled(
              sizeFilled: filled,
              avgPx: _fillsAvgPx(_orderFills),
              fills: List.of(_orderFills));
        }
      });
    }

    _updateDraft(() {
      _isPlacing = true;
      _sentCloid = cloid;
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

      if (isLimit) {
        _onLimitAnswered(result);
      } else if (result.filledSz > 0) {
        _onFilled(
            sizeFilled: result.filledSz,
            avgPx: result.avgPx,
            notices: hlOrderResultNotices(_strings, result));
      } else {
        _onRestingAccepted(result: result);
      }
    } catch (e) {
      // Unconfirmed: a fill can still arrive for it, and ends on the
      // receipt.
      if (e is! HyperliquidOrderUnconfirmedException) _fillSub?.cancel();
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
          // The venue may hold it: this ticket never sends it again
          // ([_unconfirmedLock]).
          if (e is HyperliquidOrderUnconfirmedException) {
            _unconfirmedLock = true;
          }
          _errorText = _messageFor(e);
          _errorCause = e;
        });
      }
    }
  }

  /// A fill on the stream while a funded order ([cloid]) goes out. Only
  /// the order's own cloid-tagged fills count (a stop's, a TWAP's or
  /// another order's never). A market order's receipt comes from the
  /// queued order's answer with its whole fill, or from the stream on its
  /// whole size or once that answer was unclear ([_settleFromStream]),
  /// whichever comes first ([_completed]); a limit closes the
  /// ticket from the stream on its whole size only: a part is said with
  /// what still rests by the venue's answer ([_onLimitAnswered]).
  void _onFundedFill(HlFill f, String cloid) {
    // Only the order's own cloid-tagged fills (a send again's too), never
    // a same-coin fill with no cloid or another's.
    if (!hlFillOfOrder(market, cloid, f)) return;
    final advanced = _mode != _OrderMode.market;
    _orderFills.add(f);
    if (!advanced) {
      // A market order: the queued order's answer closes the ticket with
      // its whole fill; the stream once its fills come to the whole size
      // asked for, or once that answer was unclear.
      _settleFromStream();
      return;
    }
    if (_attachTrailing || _attachTpSl) return;
    if (_sentPlan != null) return;
    final filled = _fillsSize(_orderFills);
    if (_mode == _OrderMode.limit &&
        _sentLimitSize > 0 &&
        filled >= _sentLimitSize - _sizeStep / 2) {
      _onFilled(
          sizeFilled: filled,
          avgPx: _fillsAvgPx(_orderFills),
          fills: List.of(_orderFills));
    }
  }

  /// The order this ticket sent got no answer and the account could not
  /// say whether the venue took it ([HyperliquidOrderUnconfirmedException]):
  /// it may be filled or resting. The ticket never sends it again (a new
  /// tap would be a new cloid, so a possible duplicate): the confirm stays
  /// off with the notice saying to check the orders and balance, the fill
  /// listener stays on and a fill that lands still ends on the receipt.
  bool _unconfirmedLock = false;

  /// What the accepted receipt says about the advanced order sent (its
  /// type and prices), captured as it was sent ([_receiptNow]).
  ({Map<String, String> rows, bool isClose, String? detail})? _sentReceipt;

  /// The size (in coins) of the limit order sent, as the notifier sizes it,
  /// to tell a whole fill from a part.
  double _sentLimitSize = 0;

  double get _sizeStep => math.pow(10, -market.szDecimals).toDouble();

  static double _fillsSize(Iterable<HlFill> fills) =>
      fills.fold<double>(0, (a, f) => a + f.sz);

  static double _fillsAvgPx(Iterable<HlFill> fills) {
    final size = _fillsSize(fills);
    if (size <= 0) return 0;
    return fills.fold<double>(0, (a, f) => a + f.sz * f.px) / size;
  }

  /// The limit order's size as [HyperliquidTradingNotifier.placeLimit]
  /// sizes it: the margin times the leverage at the (wire-rounded) limit.
  double _limitSizeNow() {
    final px = _parsePx(_priceController);
    if (px == null) return 0;
    return sizeFromUsd(
        usd: _marginUsd * (isSpot ? 1 : _leverage),
        px: px,
        szDecimals: market.szDecimals);
  }

  /// The venue answered the limit order: filled whole, filled in part with
  /// the rest resting (said as such, never "Order filled" for a part), or
  /// resting untouched (the accepted receipt). A resting answer behind a
  /// part the stream already brought is a part too.
  void _onLimitAnswered(HlOrderResult result) {
    var filled = result.filledSz;
    var avgPx = result.avgPx;
    final streamed = _fillsSize(_orderFills);
    if (streamed > filled) {
      filled = streamed;
      avgPx = _fillsAvgPx(_orderFills);
    }
    final notices = hlOrderResultNotices(_strings, result);
    if (filled <= 0) {
      _onRestingAccepted(result: result);
      return;
    }
    final rest = _sentLimitSize - filled;
    _onFilled(
      sizeFilled: filled,
      avgPx: avgPx,
      fills: List.of(_orderFills),
      restingSize: rest > _sizeStep / 2 ? flooredSize(rest + 1e-12, market.szDecimals) : 0,
      notices: notices,
    );
  }

  /// The order on the ticket in the accepted receipt's words: its type
  /// and prices (a limit's price; a scale's range and order count; a
  /// TWAP's running time, with its own line), and whether it only reduces.
  ({Map<String, String> rows, bool isClose, String? detail}) _receiptNow() {
    final l = _strings;
    final cap = market.pxDecimalCap;
    final rows = <String, String>{};
    String? detail;
    if (_mode == _OrderMode.limit) {
      rows[l.investingOrderType] = l.slipLimitOrder;
      final p = _parsePx(_priceController);
      if (p != null) rows[l.betLimitPrice] = formatHlPrice(p, decimalCap: cap);
    } else if (_isScale) {
      rows[l.investingOrderType] = l.slipScaleOrder;
      final s = _parsePx(_startPxController);
      final e = _parsePx(_endPxController);
      if (s != null) rows[l.slipStartPrice] = formatHlPrice(s, decimalCap: cap);
      if (e != null) rows[l.slipEndPrice] = formatHlPrice(e, decimalCap: cap);
      final n = _parseInt(_countController);
      if (n != null) rows[l.slipNumberOfOrders] = '$n';
    } else if (_isTwap) {
      rows[l.investingOrderType] = l.slipTwapOrder;
      final m = _parseInt(_twapMinutesController);
      if (m != null) {
        rows[l.betOrderDuration] = l.slipMinutesValue(m);
        detail = l.hlAdvTwapRunning(m);
      }
    }
    return (rows: rows, isClose: _reduceOnly, detail: detail);
  }

  // ── Per-order funding (one balance) ─────────────────────────────────

  /// Dollars on the spending account, read live. Zero when unreadable.
  double _dollarsUsd({bool watch = false}) {
    try {
      // Less what other accepted orders hold (committed_funds.dart): an
      // order never sizes on dollars a bet already took.
      return watch
          ? ref.watch(orderDollarsProvider)
          : ref.read(orderDollarsProvider);
    } catch (_) {
      return 0;
    }
  }

  /// The venue cash the order on the ticket (or the minimum order, with
  /// nothing typed) still needs beyond what is ready. Zero on a Ledger
  /// ticket, which keeps its own deposit door.
  double _shortfallNow({double? marginUsd}) {
    if (_isLedger) return 0;
    final margin = marginUsd ?? _marginUsd;
    if (margin <= 0) return 0;
    return ShortfallRules.shortfallUsd(
        requiredUsd: _hlRequiredUsdFor(margin), readyUsd: _hlReadyUsd());
  }

  /// The rest of Investments the last build read (Dollars plus the other
  /// venue's cash), for the "Add" door's prefill.
  double? _slipInvestmentsUsd;

  /// What the Move sheet prefills when everything in Investments
  /// ([haveUsd], Dollars alone by default) falls short of [fundUsd].
  double _dollarsShortUsd(double fundUsd, {double? haveUsd}) {
    final short = fundUsd - (haveUsd ?? _dollarsUsd());
    if (short <= 1e-6) return 0;
    return ((short * 100) - 1e-9).ceilToDouble() / 100;
  }

  /// The funding shown for [shortfallUsd]: the plan the estimate gave,
  /// else the route's fallback fee while it is on its way (the
  /// controller quotes again when the money moves).
  _FundPlan _fundPlanFor(double shortfallUsd) {
    final plan = _fundPlan;
    if (plan != null && (plan.shortfallUsd - shortfallUsd).abs() < 0.005) {
      return plan;
    }
    final target = OrderFundingEngine.targetUsd(shortfallUsd: shortfallUsd);
    final fallback =
        ((target / (1 - ShortfallRules.fallbackRouteFee)) * 100 - 1e-9)
                .ceilToDouble() /
            100;
    return _FundPlan(
        shortfallUsd: shortfallUsd, fundUsd: fallback, arrivingUsd: target);
  }

  /// Asks the funder what moving [shortfallUsd] costs, once per distinct
  /// shortfall, a moment after the amount settles. Read, never moved.
  void _scheduleFundPlan(double shortfallUsd) {
    final key = shortfallUsd.toStringAsFixed(2);
    if (_fundPlanKey == key) return;
    _fundPlanKey = key;
    _fundPlanTimer?.cancel();
    if (shortfallUsd <= 0) return;
    _fundPlanTimer = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted || _fundPlanKey != key) return;
      _FundPlan plan;
      try {
        final target =
            OrderFundingEngine.targetUsd(shortfallUsd: shortfallUsd);
        final quote = await ref
            .read(hyperliquidVenueFunderProvider)
            .estimate(target)
            .timeout(const Duration(seconds: 6));
        final quotedAt = DateTime.now();
        final fund =
            HyperliquidVenueFunder.fundUsdFor(shortfallUsd: target, quote: quote);
        // Dollars short of the move: a Bitcoin leg may carry part of it,
        // priced on Orchestra's own spread for the fee row.
        final dollars = _dollarsUsd();
        final spread = dollars + 1e-9 < fund
            ? await bitcoinLegSpreadEstimate(
                cachedSpendingBitcoin(ref.read), fund - dollars)
            : null;
        plan = _FundPlan(
          shortfallUsd: shortfallUsd,
          fundUsd: fund,
          arrivingUsd: target,
          bitcoinSpread: spread,
          quote: quote,
          quotedAt: quotedAt,
        );
      } catch (_) {
        plan = _fundPlanFor(shortfallUsd);
      }
      if (!mounted || _fundPlanKey != key) return;
      _updateDraft(() => _fundPlan = plan);
    });
  }

  /// `order_funding_step` and the ticket's own step, together.
  void _trackFundingStep(OrderFundingStage stage) {
    if (_fundingStage == stage) return;
    _fundingStage = stage;
    TrackingService.track('order_funding_step', params: {
      'venue': 'hyperliquid',
      'step': stage.name,
    });
  }

  void _trackFundingFailed(String stage, Object? error, {String? category}) {
    final startedAt = _fundingStartedAt;
    TrackingService.track('order_funding_failed', params: {
      'venue': 'hyperliquid',
      'stage': stage,
      'error_category': category ?? TrackingService.errorCategory(error),
      'duration_ms': startedAt == null
          ? 0
          : DateTime.now().difference(startedAt).inMilliseconds,
    });
  }

  /// The accept is done and the order's money is on its way as a
  /// standing order (standing_orders/). The ticket stays up, locked as it
  /// always was while placing (founder, 10 November 2026: "the same bottom
  /// modal sheet we had before when it was locked ... only difference is
  /// that we allow the user to leave"): the money's journey and the bar's
  /// button on the running step, then the result. From here the person
  /// can leave it, which never cancels the order ([_onLeave]); the bar's
  /// button is "OK", which leaves it too, while the order is on its way
  /// ([_standingOnItsWay]).
  void _closeForStandingOrder() {
    if (!mounted || _standingAccepted) return;
    _updateDraft(() => _standingAccepted = true);
  }

  /// The orders on the ticket's market that had already ended when it
  /// first looked after its accept: never this accept's own. Null: not
  /// looked yet.
  Set<String>? _standingEndedBefore;

  /// The accept made a standing order of this ticket's order: the ticket
  /// may be left while it places. Reset by every new try.
  bool _standingAccepted = false;

  /// The person left the ticket while its order goes on: every progress
  /// haptic of the ticket stops at once, and nothing it still hears
  /// navigates.
  bool _left = false;

  /// Whether this ticket's accepted order is still on its way: from the
  /// accept (before its record exists) until it ends. Watched, so the
  /// button gives way to the result the moment it is known.
  bool _standingOnItsWay() {
    if (!_standingAccepted || _left || _completed) return false;
    final coin = market.coin;
    final ended = _standingEndedBefore ??= {
      for (final o in ref.read(standingOrdersProvider))
        if (o.venue == StandingOrderVenue.investing &&
            o.marketKey == coin &&
            !o.isOpen)
          o.id,
    };
    // This accept's order (newest on the market that had not ended
    // before it); null until its record exists, which is on its way too
    // while its queued order is. A record seen and then gone ended
    // quietly (standing_orders_provider.dart `_forget`): never "on its
    // way" for good (founder, 11 November 2026, on 2.2.0 (109): "that
    // thing is just stale there").
    final state = ref.watch(standingOrdersProvider
        .select((all) => _standingOrderIn(all, coin, ended)?.state));
    if (state != null) {
      _standingSeen = true;
      return !state.isTerminal;
    }
    if (_standingSeen) return false;
    return ref.watch(pendingHyperliquidOrderProvider.select((p) => p != null)) ||
        _isPlacing ||
        _preparing;
  }

  /// This ticket's accepted order has been on record ([_standingOnItsWay]).
  bool _standingSeen = false;

  /// This ticket's accepted order among [all]: the newest on [coin] not in
  /// [ended].
  static StandingOrder? _standingOrderIn(
      List<StandingOrder> all, String coin, Set<String> ended) {
    StandingOrder? found;
    for (final o in all) {
      if (o.venue == StandingOrderVenue.investing &&
          o.marketKey == coin &&
          !ended.contains(o.id)) {
        found = o;
      }
    }
    return found;
  }

  /// Reopened from the placing toast ([HlOrderSlipSheet.standingEndedBefore])
  /// and its order still on its way: the ticket is locked as the left one
  /// was while it placed (the form inert, the "OK" its button).
  bool _followingStanding() =>
      widget.standingEndedBefore != null && _standingOnItsWay();

  /// Whether this ticket's order would wait for another Investing order
  /// still being placed: the very refusal [_confirmFunded] (and the
  /// Bitcoin-funded confirm) gives an order that needs money moved
  /// ([wouldFund]) while one is queued or placing
  /// ([PendingHyperliquidOrderNotifier.blocksNewOrder]) or a funded chain
  /// (an order or margin) is live. Never this ticket's own order (its
  /// accept, its placing, its funded steps on this market, a reopened
  /// standing ticket), and never over a shut open, which says its own
  /// reason. Watched, so the ticket frees itself the moment it is done.
  bool _heldByOtherOrder(List<FundedOrderRecord> runs,
      {required bool wouldFund,
      required bool fundedRunning,
      required bool openBlocked}) {
    if (_isLedger ||
        !wouldFund ||
        fundedRunning ||
        openBlocked ||
        widget.sendPick != null ||
        widget.standingEndedBefore != null ||
        _standingAccepted ||
        _isPlacing ||
        _preparing) {
      return false;
    }
    final queued = ref.watch(pendingHyperliquidOrderProvider.select(
        (i) => PendingHyperliquidOrderNotifier.blocksNewOrder(i, runs)));
    return queued ||
        FundedOrdersNotifier.activeOf(runs, OneBalanceVenue.investing) != null;
  }

  /// The ticket is going (didPop; OK, the X, a tap above, back or a swipe
  /// down): once it had a standing order, its haptics stop now, and while
  /// that order is still on its way Sal's placing toast takes over at the
  /// top (standing_order_toasts.dart: Sal and the words, no spinner, no
  /// Cancel, closable). While the ticket is up it never shows.
  void _onLeave() {
    if (!_standingAccepted || _left) return;
    _updateDraft(() => _left = true);
    if (_completed) return;
    final coin = market.coin;
    final container = ProviderScope.containerOf(context, listen: false);
    // This ticket's own order when it is on record, else the open one on
    // its market.
    final ended = _standingEndedBefore;
    final mine = ended == null
        ? null
        : _standingOrderIn(container.read(standingOrdersProvider), coin, ended);
    if (mine != null && mine.state.isTerminal) return;
    final order = mine ??
        StandingOrderToasts.openOn(
            container, StandingOrderVenue.investing, coin);
    // Only an order still on its way gets the toast: not one that ended
    // on the ticket, nor one waiting on a new price (Sal asks about that).
    final status = ref.read(pendingHyperliquidOrderProvider)?.status;
    if (status == PendingHlOrderStatus.failed ||
        status == PendingHlOrderStatus.done ||
        status == PendingHlOrderStatus.unconfirmed ||
        order?.state == StandingOrderState.needsApproval ||
        (order == null && status == null)) {
      return;
    }
    // The order's own label (the standing order's title).
    final label = isSpot
        ? market.coin
        : '${market.coin} · ${hlKindLabel(_strings, isSpot: false)}';
    // Any tap on this order (the toast, its Overview card, its Activity
    // row) opens this ticket again, locked on this order, as it is being
    // left (founder, on 2.2.0 (101): "we should just reuse the betslip,
    // the red or green one"; on 2.2.0 (104): never the white journey
    // sheet, no Cancel, the haptics running again):
    // standing_order_slips.dart.
    final left = widget;
    final isLong = _isLong;
    final margin = _marginUsd;
    StandingOrderSlips.remember(
      venue: StandingOrderVenue.investing,
      marketKey: coin,
      orderId: order?.id,
      endedBefore: ended,
      open: (root, follow) => HlOrderSlipSheet.reopenStanding(root, left,
          isLong: isLong, marginUsd: margin, endedBefore: follow),
    );
    // The root overlay (root_navigator.dart); this ticket's own context
    // only where the app has no root key.
    StandingOrderToasts.placing(kuteRootContext(context), context.l10n,
        venue: StandingOrderVenue.investing,
        marketKey: coin,
        marketTitle: label,
        order: order);
  }

  /// Funds [shortfallUsd] from Dollars and places the order once the
  /// money lands: one approval (the order plus the dollars allowed to
  /// leave for it, held as the autofire grant), the controller moves the
  /// money, and the pending-order watcher places the order on the credit
  /// through [orderAt]. The ticket stays open saying "Preparing your
  /// order", then shows the placing tile and the receipt.
  ///
  /// A refusal before any funds left (declined, no route, below the
  /// minimum) leaves Dollars untouched and the ticket as it was; Dollars
  /// that cannot cover the move turn the button into "Add $X to
  /// Investments". A credit timeout keeps the cash at the venue for the
  /// sweeper and says so with the existing copy.

  Future<void> _confirmFunded({
    required String walletId,
    required String cloid,
    required double mid,
    required double shortfallUsd,
    required String orderKind,
    required bool resizable,
    required _SlipOrder Function(double marginUsd) orderAt,
  }) async {
    final lev = isSpot ? 1 : _leverage;
    final marginUsd = _marginUsd;
    // One funded order at a time: while one is queued behind its money or
    // being placed, a second never takes its money or its approval.
    // A Bitcoin-funded order still on its way here counts too: its order
    // waits (unqueued) for its dollars. So does margin being added from
    // Investments (the margin sheet): its credit must not be this order's.
    // A venue-cash order held while its legs run counts too
    // ([PendingHyperliquidOrderNotifier.blocksNewOrder]).
    final runs = ref.read(fundedOrdersProvider);
    final activeFunding =
        FundedOrdersNotifier.activeOf(runs, OneBalanceVenue.investing);
    if (PendingHyperliquidOrderNotifier.blocksNewOrder(
            ref.read(pendingHyperliquidOrderProvider), runs) ||
        activeFunding?.fromBitcoin == true ||
        activeFunding?.label.kind == FundedOrderKind.margin) {
      _trackBlocked('order_queued');
      _updateDraft(() {
        _errorCause = null;
        _errorText = _strings.slipOtherOrderPlacingNote;
      });
      return;
    }
    // Before any money moves: the market must still take the order.
    final unavailable = await _fundedMarketBlock();
    if (unavailable != null) {
      _trackBlocked(unavailable);
      if (mounted) {
        _updateDraft(() {
          _errorCause = null;
          _errorText = _fundedBlockText ?? _strings.errorCopyGeneric;
        });
      }
      return;
    }
    if (!mounted) return;
    final ready = _hlReadyUsd();
    final required = _hlRequiredUsdFor(marginUsd);
    _fundingStartedAt = DateTime.now();
    _fundingStage = null;
    _trackFundingStep(OrderFundingStage.quote);
    _updateDraft(() => _preparing = true);

    // ONE plan before anything is approved: what must land (the
    // shortfall plus the engine's safety buffer, never under $1), and
    // what to send for it, priced on what ARRIVES at the very amount sent
    // (the route's near-flat cost and an unseen account's one-time
    // activation are inside the estimate). The approval binds exactly
    // that amount and the controller sends exactly it.
    final quoteStart = DateTime.now();
    final double fundUsd;
    final double arrivingUsd;
    final target = OrderFundingEngine.targetUsd(shortfallUsd: shortfallUsd);
    // The estimate the ticket read for this very target while it was on
    // screen sizes the move when it is fresh: the accept then waits on the
    // one verifying estimate at the amount sent, not on two round trips.
    final held = _fundPlan;
    final first = HyperliquidVenueFunder.freshFirstQuote(
      quote: held?.quote,
      readAt: held?.quotedAt,
      quotedForUsd: held?.arrivingUsd ?? 0,
      neededUsd: target,
      now: quoteStart,
    );
    try {
      final size = await HyperliquidVenueFunder.sizeFunding(
              ref.read(hyperliquidVenueFunderProvider),
              neededUsd: target,
              first: first)
          .timeout(const Duration(seconds: 12));
      if (!size.covers(shortfallUsd)) {
        // Even the most the rail sends would not land what the order
        // needs: refused here, before any approval or money.
        throw const RouteUnavailable('arriving_below_needed');
      }
      fundUsd = size.fundUsd;
      arrivingUsd = size.arrivingUsd;
    } catch (e) {
      _trackFundingFailed('quote', e);
      _stopped('funding_quote', error: e);
      if (mounted) {
        _updateDraft(() {
          _fundingStage = null;
          _errorCause = e;
          _errorText = _messageFor(e);
        });
      }
      return;
    }
    final quoteMs = DateTime.now().difference(quoteStart).inMilliseconds;
    if (!mounted) return;
    final plan = _FundPlan(
        shortfallUsd: shortfallUsd, fundUsd: fundUsd, arrivingUsd: arrivingUsd);
    _fundPlanKey = shortfallUsd.toStringAsFixed(2);
    final dollars = _dollarsUsd();
    // This is a request before approval. Only the approved journey emits
    // order_funding_started, once, regardless of its selected sources.
    TrackingService.track('order_funding_requested', params: {
      'venue': 'hyperliquid',
      'order_usd': marginUsd,
      'fund_usd': fundUsd,
      'ready_usd': ready,
      'dollars_usd': dollars,
      'entry_source': _entrySource,
      'wallet_kind': 'hot',
      'order_kind': orderKind,
      if (_positionEffectName != null) 'position_effect': _positionEffectName!,
      if (_bitcoinArmed) 'funding_source': 'bitcoin',
    });
    // The funding engine: Dollars first, then Bitcoin, and the other
    // venue's cash only for what those cannot cover (founder decision, 15
    // October 2026: venue to venue is the slow way; [decideOrderSources]).
    // Only when even that falls short is it the Receive sheet.
    var pullFirst = false;
    OrderSources? sources;
    if (dollars + 1e-9 < fundUsd) {
      // Dollars plus the other venue's reachable cash: the whole
      // Investments balance this move can draw on.
      var reach = dollars;
      try {
        reach = await ref
            .read(venueCashPullerProvider)
            .reachUsd(exclude: OneBalanceVenue.investing)
            .timeout(const Duration(seconds: 8));
      } catch (_) {}
      if (!mounted) return;
      final fromAdd = _bitcoinArmed;
      sources = await decideOrderSources(
        ProviderScope.containerOf(context, listen: false).read,
        fundUsd: fundUsd,
        dollarsUsd: dollars,
        otherVenueUsd: reach - dollars,
        shownAddUsd: fromAdd ? _bitcoinTapAddUsd : null,
        sized: fromAdd ? _bitcoinTapPlan : null,
        investmentsCover: OrderFundingEngine.decide(
              needUsd: fundUsd,
              haveHereUsd: dollars,
              investmentsUsd: reach - dollars,
            ).route ==
            OrderFundingRoute.move,
      );
      if (!mounted) return;
      pullFirst = sources.route == OrderSourceRoute.otherVenue;
    }
    if (sources != null && !pullFirst) {
      // Dollars short, whichever button was tapped ("Add $X", or the
      // order): the person's own bitcoin funds the rest under this
      // order's one approval, the other venue only what Bitcoin cannot.
      // Only when nothing covers it is it the Investments Receive sheet.
      // The bet slip makes the same decision.
      await _confirmFundedFromBitcoin(
        walletId: walletId,
        cloid: cloid,
        mid: mid,
        orderKind: orderKind,
        resizable: resizable,
        orderAt: orderAt,
        plan: plan,
        ready: ready,
        required: required,
        quoteMs: quoteMs,
        marginUsd: marginUsd,
        lev: lev,
        dollars: dollars,
        sources: sources,
      );
      return;
    }

    // The other venue's legs are planned before the one approval (nothing
    // moves): a leg straight into the Investing account runs only under
    // that approval, which binds its cap.
    Map<String, Object?>? directLegs;
    VenueCashPlan? legPlan;
    if (pullFirst) {
      if (_moveUsd != fundUsd) _moveId = null;
      try {
        final puller = ref.read(venueCashPullerProvider);
        final earlier =
            _moveId == null ? null : MultiSourceMoveStore.get(_moveId!);
        legPlan = await puller
            .plan(
              neededUsd:
                  math.max(0.0, fundUsd - (earlier?.directDeliveredUsd ?? 0)),
              exclude: OneBalanceVenue.investing,
              destination: VenueCashDestination.investing,
            )
            .timeout(const Duration(seconds: 8));
        directLegs =
            puller.directLegLimit(legPlan, VenueCashDestination.investing);
      } catch (_) {
        legPlan = null;
      }
      if (!mounted) return;
      if (legPlan == null || !legPlan.covers) {
        // The legs could not be planned: nothing is approved or moved.
        _trackFundingFailed('quote', null, category: 'venue_cash_unread');
        _stopped('funding_quote');
        _updateDraft(() {
          _preparing = false;
          _fundingStage = null;
          _errorCause = null;
          _errorText = _strings.errorCopyGeneric;
        });
        return;
      }
    }

    // One approval for the order AND the dollars that leave for it. The
    // grant is held as the autofire grant: the rail's step-up hook reads
    // its funding limits before the money moves, and the watcher
    // consumes it against the exact order when it places it.
    final pending = PendingHlOrderIntent(
      coin: market.coin,
      kind: market.kind,
      isLong: _isLong,
      marginUsd: marginUsd,
      leverage: lev,
      slippagePct: _mode == _OrderMode.market ? _slippagePct : 0,
      expectedPx: mid,
      marketLabel: isSpot
          ? market.coin
          : '${market.coin} · ${hlKindLabel(_strings, isSpot: false)}',
      source: widget.source,
      market: market,
      placement: PendingHlOrderPlacement(
        intentAt: (margin) => orderAt(margin).intent,
        placeAt: (grant, margin) => orderAt(margin).place(grant),
        resizable: resizable,
        cloid: cloid,
        scaleLegs: _scaleLegsNow(),
      ),
      fundUsd: fundUsd,
      directLegs: directLegs,
      requiredUsd: required,
      readyAtQueueUsd: ready,
      arrivingUsd: arrivingUsd,
      orderKind: orderKind,
      needsBuilderApproval: _deferBuilderApproval,
      positionEffect: _positionEffectName,
      entrySource: _entrySource,
      quoteMs: quoteMs,
    );
    _trackStep('approval');
    final approved =
        pendingHlOrderAutofireIntent(pending, market, walletId: walletId);
    final seam = debugHlOrderFundingApproval;
    final grant = seam != null
        ? await seam(approved)
        : await requireFreshAuthGrant(
            context,
            ref,
            intent: approved,
            reason: context.l10n.stepUpReasonOrder(pending.marketLabel),
            amountUsd: marginUsd,
            smallAction: SmallActionContext.usd(marginUsd),
            autofireIntentId: kPendingHlOrderAutofireId,
          );
    if (grant == null || !mounted) {
      if (grant == null) {
        _stopped('signing_declined');
        TrackingService.track('order_funding_abandoned', params: {
          'venue': 'hyperliquid',
          'stage': 'approval',
        });
      } else {
        // Approved as the ticket went: nothing was started under it, so
        // the approval goes too (never left live for its 30 minutes).
        grant.revoke();
        AuthGrantRegistry.instance.cancelAutofire(kPendingHlOrderAutofireId);
      }
      if (mounted) _updateDraft(() => _fundingStage = null);
      return;
    }
    // Re-checked against the price now, before anything moves under it.
    if (!_pricesStillHold()) {
      grant.revoke();
      AuthGrantRegistry.instance.cancelAutofire(kPendingHlOrderAutofireId);
      _updateDraft(() => _fundingStage = null);
      return;
    }
    if (legPlan != null) {
      // Dollars and the other venue's cash, every source at once, on the
      // order's step graph (venue_cash_funded_order.dart).
      _runVenueCashFunded(
          grant: grant,
          pending: pending,
          legPlan: legPlan,
          plan: plan,
          cloid: cloid,
          marginUsd: marginUsd,
          required: required,
          ready: ready,
          fundUsd: fundUsd);
      return;
    }
    // Approved: the order's steps show from now, on this ticket and
    // (named) on the Investments header, whatever happens to the ticket.
    final runner = ref.read(bitcoinFundedOrderRunnerProvider);
    final fundedId = runner.beginFunded(FundedOrderLabel(
      venue: OneBalanceVenue.investing,
      orderUsd: marginUsd,
      side: _sideWord(),
      market: FundedOrderLabel.shortName(market.coin),
      marketKey: market.coin,
    ));
    // The Dollars this order moves are its own from this accept: a bet
    // accepted meanwhile sizes and checks against the rest, never the same
    // dollars (committed_funds.dart). A bet took them first: nothing
    // moves, the button becomes the Dollars door, exactly as a balance
    // that fell.
    final commitments = ref.read(committedFundsProvider.notifier);
    if (!commitments.commitDollars(OneBalanceVenue.investing,
        usd: fundUsd, runId: fundedId)) {
      final short =
          commitments.dollarsShortUsd(OneBalanceVenue.investing, fundUsd);
      runner.dropFunded(fundedId);
      grant.revoke();
      AuthGrantRegistry.instance.cancelAutofire(kPendingHlOrderAutofireId);
      _trackFundingFailed('fund', null, category: 'insufficient_funds');
      _stopped('insufficient_balance');
      _updateDraft(() {
        _preparing = false;
        _fundingStage = null;
        _fundPlan = _FundPlan(
            shortfallUsd: plan.shortfallUsd,
            fundUsd: _dollarsUsd() + short,
            arrivingUsd: plan.arrivingUsd);
      });
      return;
    }

    // Listen for the order's fill BEFORE anything moves, so a fast fill
    // cannot slip between the placement and the subscription.
    _orderFills.clear();
    _fillSub?.cancel();
    _fillSub =
        ref.read(hyperliquidUserEventsProvider.notifier).fills.listen((f) {
      _onFundedFill(f, cloid);
    });
    _listenPending();
    _updateDraft(() {
      _isPlacing = true;
      _preparing = false;
      _fundPlan = plan;
      _errorText = null;
      _errorCause = null;
    });
    _trackFundingStep(OrderFundingStage.fund);

    // The order's placement, followed BEFORE it is queued (as the
    // Predictions slip does): it is queued before its move is sent, so the
    // auto-fire may place it, and clear it, while the move is still
    // awaited (a long unconfirmed settlement while the credit lands).
    // Followed only after, that order read as failed.
    final placement = runner.watchPlacement(fundedId);
    final OrderFundingOutcome outcome;
    try {
      // The watcher that places the order on the credit, alive before
      // the order is queued (the Investing screen normally keeps it so).
      ref.read(pendingHlOrderAutoFireProvider);
      outcome =
          await ref.read(pendingHyperliquidOrderProvider.notifier).fundAndQueue(
        pending,
        fundedRunId: fundedId,
        grant: grant,
        controller: ref.read(orderFundingControllerProvider),
        orderUsd: marginUsd,
        requiredUsd: required,
        readyUsd: ready,
        onStage: (stage) {
          if (stage == OrderFundingStage.quote ||
              stage == OrderFundingStage.fund) {
            _trackFundingStep(stage);
          }
        },
      );
    } catch (e) {
      placement.cancel();
      runner.stopFunded(fundedId,
          reason: 'venue_refused', message: _messageFor(e));
      _fundingFailedBeforeMove('fund', e, _messageFor(e), inSteps: true);
      return;
    }
    // Followed to the end whatever happens to the ticket.
    switch (outcome) {
      case OrderFundingFunded(:final move):
        runner.followFunded(fundedId, move: move, watch: placement);
      case OrderFundingNotNeeded() || OrderFundingUnconfirmed():
        runner.followFunded(fundedId, watch: placement);
      case OrderFundingRefused(:final reason)
          when reason == kHlOrderQueuedReason:
        // Another order's queue: this one never was.
        placement.cancel();
        runner.dropFunded(fundedId);
      case _ when placement.placedNow == true:
        // Placed meanwhile all the same: never a failure in its steps.
        runner.followFunded(fundedId, watch: placement);
      case OrderFundingRefused():
        placement.cancel();
        runner.stopFunded(fundedId,
            reason: 'venue_refused', message: _strings.errorCopyGeneric);
      case OrderFundingNeedsDollars():
        // The button turns into the Add door: nothing to show in steps.
        placement.cancel();
        runner.dropFunded(fundedId);
    }
    if (!mounted) return;
    switch (outcome) {
      case OrderFundingFunded(:final move):
        _submitted = true;
        _closeForStandingOrder();
        // The order's own funding move is the last leg of its
        // multi-source move: one Activity row.
        MultiSourceMoveStore.attachFinal(
            _moveId, move.operationId ?? move.quoteId);
        _moveId = null;
        TrackingService.track('order_funding_submitted', params: {
          'venue': 'hyperliquid',
          'fund_usd': move.sentUsd,
          'amount_usd': marginUsd,
          'quote_id': TrackingService.orderRef(move.quoteId),
          'order_id': TrackingService.orderRef(move.orderId ?? ''),
        });
        _trackFundingStep(OrderFundingStage.credit);
      case OrderFundingNotNeeded():
        // The venue covered it after all: the watcher places it now.
        _submitted = true;
        _closeForStandingOrder();
        _trackFundingStep(OrderFundingStage.credit);
      case OrderFundingUnconfirmed():
        // The rail could not say whether the money left: the order stays
        // queued and the watcher keeps reading the venue. The ticket
        // keeps its "Moving" line; a retry cannot fund it twice.
        _submitted = true;
        _trackFundingStep(OrderFundingStage.credit);
      case OrderFundingRefused(:final reason) when reason == kHlOrderQueuedReason:
        _fundingFailedBeforeMove(
            'fund', reason, _strings.slipOtherOrderPlacingNote);
      case OrderFundingRefused(:final reason):
        _fundingFailedBeforeMove('fund', reason, _strings.errorCopyGeneric,
            inSteps: true);
      case OrderFundingNeedsDollars(:final shortfallUsd):
        // Dollars fell short once the controller quoted: the button
        // becomes the Dollar deposit door for the difference.
        _fillSub?.cancel();
        _pendingSub?.close();
        _pendingSub = null;
        _trackFundingFailed('fund', null, category: 'insufficient_funds');
        _stopped('insufficient_balance');
        _updateDraft(() {
          _isPlacing = false;
          _fundingStage = null;
          _fundPlan = _FundPlan(
              shortfallUsd: plan.shortfallUsd,
              fundUsd: _dollarsUsd() + shortfallUsd,
              arrivingUsd: plan.arrivingUsd);
        });
    }
  }

  /// The order funded from Dollars and the other venue's cash, approved:
  /// every source starts at once on the order's step graph (one line per
  /// source, the credit, the order), headless, whatever happens to this
  /// ticket ([VenueCashFundedOrderRunner]). The order is queued with
  /// Dollars' own share; the venue's autofire places it once the account
  /// holds enough.
  void _runVenueCashFunded({
    required AuthGrant grant,
    required PendingHlOrderIntent pending,
    required VenueCashPlan legPlan,
    required _FundPlan plan,
    required String cloid,
    required double marginUsd,
    required double required,
    required double ready,
    required double fundUsd,
  }) {
    final container = ProviderScope.containerOf(context, listen: false);
    // Held, never fired, until the chain queues it (awaitingBalance).
    ref.read(pendingHyperliquidOrderProvider.notifier).setIntent(pending);
    ref.read(pendingHlOrderAutoFireProvider);
    // Listen for the order's fill BEFORE anything moves.
    _orderFills.clear();
    _fillSub?.cancel();
    _fillSub =
        ref.read(hyperliquidUserEventsProvider.notifier).fills.listen((f) {
      _onFundedFill(f, cloid);
    });
    _listenPending();
    _submitted = true;
    _updateDraft(() {
      _isPlacing = true;
      _preparing = false;
      _fundPlan = plan;
      _errorText = null;
      _errorCause = null;
      _fundingStage = OrderFundingStage.fund;
    });
    _closeForStandingOrder();
    _moveId ??= MultiSourceMoveStore.newId();
    _moveUsd = fundUsd;
    final run = container.read(venueCashFundedOrderRunnerProvider).start(
          VenueCashFundedRequest(
            venue: OneBalanceVenue.investing,
            grant: grant,
            label: FundedOrderLabel(
              venue: OneBalanceVenue.investing,
              orderUsd: marginUsd,
              side: _sideWord(),
              market: FundedOrderLabel.shortName(market.coin),
              marketKey: market.coin,
            ),
            fundUsd: fundUsd,
            readyUsd: ready,
            plan: legPlan,
            moveId: _moveId,
            entrySource: _entrySource,
            queue: ({required double fundUsd, required double readyUsd}) =>
                container
                    .read(pendingHyperliquidOrderProvider.notifier)
                    .fundAndQueue(
                      pending,
                      grant: grant,
                      controller: container.read(orderFundingControllerProvider),
                      orderUsd: marginUsd,
                      requiredUsd: required,
                      // Nothing from Dollars: queued only, nothing moves.
                      readyUsd: fundUsd > 0 ? readyUsd : required,
                      fundUsd: fundUsd,
                      continueJourney: true,
                    ),
            fundMore: (controller, usd) => controller.fundAndQueue(
              venue: OneBalanceVenue.investing,
              orderUsd: marginUsd,
              requiredUsd: required,
              // The order is queued already: this only moves what came
              // home, within what the approval binds.
              readyUsd: 0,
              auth: UserGrantAuthorization(grant),
              fundUsd: usd,
              keepUnconfirmed: true,
              continueJourney: true,
            ),
            dropOrder: () {
              final current = container.read(pendingHyperliquidOrderProvider);
              if (current != null &&
                  identical(current.placement, pending.placement) &&
                  current.status != PendingHlOrderStatus.placing &&
                  current.status != PendingHlOrderStatus.done) {
                container.read(pendingHyperliquidOrderProvider.notifier).clear();
              }
              AuthGrantRegistry.instance
                  .cancelAutofire(kPendingHlOrderAutofireId);
              grant.revoke();
            },
          ),
        );
    _bitcoinRunId = run.id;
    unawaited(run.ended.then((end) {
      if (end == BitcoinFundedEnd.placed) _moveId = null;
      if (mounted) _onBitcoinRunEnded(run.id, end);
    }));
  }

  /// A hot ticket whose whole Investments balance is short of the order's
  /// move (founder decision 14 October 2026), whichever button was
  /// tapped: ONE approval for the order, the Dollars move AND a Bitcoin →
  /// Dollars leg (at most the sized sats, `spark:BTC → spark:USDB`, to the
  /// wallet's own Spark address), then the chain runs headless
  /// ([BitcoinFundedOrderRunner]): Bitcoin → Dollars, Dollars → Investing,
  /// the order at a fresh price. Everything was validated by the normal
  /// confirm before this point; the leg is sized and checked against the
  /// wallet's bitcoin here ([decideSlipFunding], the bet slip's same
  /// decision), before the prompt. Declining moves nothing.
  ///
  /// When the bitcoin genuinely does not cover X, nothing is approved: an
  /// "Add" tap opens the Dollars door itself once this returns
  /// ([_bitcoinFellBack]); a tap on the order opens it here. Both prefill
  /// X.
  Future<void> _confirmFundedFromBitcoin({
    required String walletId,
    required String cloid,
    required double mid,
    required String orderKind,
    required bool resizable,
    required _SlipOrder Function(double marginUsd) orderAt,
    required _FundPlan plan,
    required double ready,
    required double required,
    required int quoteMs,
    required double marginUsd,
    required int lev,
    required double dollars,
    required OrderSources sources,
  }) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final planFundUsd = plan.fundUsd;
    final fromAdd = _bitcoinArmed;
    // One funded order per venue at a time.
    if (FundedOrdersNotifier.activeOf(
            ref.read(fundedOrdersProvider), OneBalanceVenue.investing) !=
        null) {
      _trackBlocked('order_queued');
      _updateDraft(() {
        _fundingStage = null;
        _errorCause = null;
        _errorText = _strings.slipOtherOrderPlacingNote;
      });
      return;
    }
    // An "Add" tap whose X no longer covers what Investments lack: nothing
    // moves and the button names the new figure.
    if (sources.route == OrderSourceRoute.addChanged) {
      _trackBlocked('add_amount_changed');
      _updateDraft(() {
        _fundingStage = null;
        _fundPlan = plan;
      });
      return;
    }
    final puller = ref.read(venueCashPullerProvider);

    /// The bitcoin (or the rest of Investments) genuinely does not cover
    /// it: the money has to come from outside, so the Investments Receive
    /// sheet, for what is missing.
    Future<void> toReceive(double missingUsd) async {
      _bitcoinFellBack = true;
      _bitcoinFallbackUsd = missingUsd > 0 ? missingUsd : null;
      _trackFundingFailed('quote', null, category: 'insufficient_funds');
      _stopped('insufficient_balance');
      _updateDraft(() {
        _fundingStage = null;
        _fundPlan = plan;
      });
      if (fromAdd || !mounted) return;
      await _openInvestmentsReceive(missingUsd);
    }

    /// Nothing could be worked out in time (no price, the wallet's own
    /// Spark address or the other venue's plan unread): nothing moves and
    /// no door opens; the ticket says the order did not go through.
    void unavailable(String reason) {
      _trackFundingFailed('quote', null, category: reason);
      _stopped('funding_quote');
      if (!mounted) return;
      _updateDraft(() {
        _fundingStage = null;
        _errorCause = null;
        _errorText = _strings.errorCopyGeneric;
      });
    }

    switch (sources.route) {
      case OrderSourceRoute.insufficient:
        await toReceive(sources.missingUsd > 0
            ? sources.missingUsd
            : _dollarsShortUsd(planFundUsd, haveUsd: dollars));
        return;
      case OrderSourceRoute.unavailable:
        unavailable('bitcoin_price_unread');
        return;
      case OrderSourceRoute.bitcoin:
        break;
      case OrderSourceRoute.dollars:
      case OrderSourceRoute.otherVenue:
      case OrderSourceRoute.addChanged:
        return;
    }
    final leg = sources.plan!;
    // Held from when "Add" showed: normally ready. A cold SDK is waited
    // on (the button stays busy), never taken for a lack of bitcoin.
    final ownSpark = await ownSparkForBitcoinLeg(container.read);
    // The rest of the order from the other venue (Dollars first, then its
    // cash), planned before the one approval, which binds the legs that go
    // straight into the account.
    OtherVenuePlan? other;
    try {
      other = await planOtherVenueCash(puller,
              venue: OneBalanceVenue.investing,
              fundUsd: planFundUsd,
              addUsd: leg.targetUsd,
              dollarsUsd: dollars)
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      other = null;
    }
    if (!mounted) return;
    if (ownSpark == null) {
      unavailable('own_spark_unread');
      return;
    }
    if (other == null) {
      unavailable('venue_cash_unread');
      return;
    }
    if (!other.covers) {
      // The other venue's cash cannot bring the rest: what Dollars lack
      // with nothing from it.
      await toReceive(_dollarsShortUsd(planFundUsd, haveUsd: dollars));
      return;
    }
    final rest = other;
    // The Bitcoin leg the approval binds: via Dollars to the own Spark
    // address, or straight to the own Investing account.
    final btcLeg = await bitcoinLegLimitFor(container.read,
        venue: OneBalanceVenue.investing, leg: leg, ownSpark: ownSpark);
    if (!mounted) return;
    final pending = PendingHlOrderIntent(
      coin: market.coin,
      kind: market.kind,
      isLong: _isLong,
      marginUsd: marginUsd,
      leverage: lev,
      slippagePct: _mode == _OrderMode.market ? _slippagePct : 0,
      expectedPx: mid,
      marketLabel: isSpot
          ? market.coin
          : '${market.coin} · ${hlKindLabel(_strings, isSpot: false)}',
      source: widget.source,
      market: market,
      placement: PendingHlOrderPlacement(
        intentAt: (margin) => orderAt(margin).intent,
        placeAt: (grant, margin) => orderAt(margin).place(grant),
        resizable: resizable,
        cloid: cloid,
        scaleLegs: _scaleLegsNow(),
      ),
      fundUsd: planFundUsd,
      directLegs: rest.directLegs,
      btcLeg: btcLeg,
      requiredUsd: required,
      readyAtQueueUsd: ready,
      arrivingUsd: plan.arrivingUsd,
      orderKind: orderKind,
      needsBuilderApproval: _deferBuilderApproval,
      positionEffect: _positionEffectName,
      entrySource: _entrySource,
      quoteMs: quoteMs,
      fundingSource: 'bitcoin',
    );
    _trackStep('approval');
    // The ONE approval: the order, the Dollars it may take, the other
    // venue's legs straight into the account, the bitcoin leg. Held as
    // the order's autofire grant. Declined: nothing is quoted or moved.
    final approved =
        pendingHlOrderAutofireIntent(pending, market, walletId: walletId);
    var declined = false;
    final runner = container.read(bitcoinFundedOrderRunnerProvider);
    final run = await runner.startApproved(
      approve: () async {
        final seam = debugHlOrderFundingApproval;
        final grant = seam != null
            ? await seam(approved)
            : await requireFreshAuthGrant(
                context,
                ref,
                intent: approved,
                reason: context.l10n.stepUpReasonOrder(pending.marketLabel),
                amountUsd: marginUsd,
                smallAction: SmallActionContext.usd(marginUsd),
                autofireIntentId: kPendingHlOrderAutofireId,
              );
        declined = grant == null;
        return grant;
      },
      build: (grant) {
        if (!mounted) {
          AuthGrantRegistry.instance
              .cancelAutofire(kPendingHlOrderAutofireId);
          return null;
        }
        // Re-checked against the price now, before anything moves.
        if (!_pricesStillHold()) {
          grant.revoke();
          AuthGrantRegistry.instance
              .cancelAutofire(kPendingHlOrderAutofireId);
          return null;
        }
        // Held, never fired, while the bitcoin leg runs (awaitingDeposit).
        ref.read(pendingHyperliquidOrderProvider.notifier).setIntent(pending);
        // The watcher that places the order on the credit, alive before
        // the order is queued.
        ref.read(pendingHlOrderAutoFireProvider);
        // Listen for the order's fill BEFORE anything moves.
        _orderFills.clear();
        _fillSub?.cancel();
        _fillSub =
            ref.read(hyperliquidUserEventsProvider.notifier).fills.listen((f) {
          _onFundedFill(f, cloid);
        });
        _listenPending();
        _submitted = true;
        _updateDraft(() {
          _isPlacing = true;
          _preparing = false;
          _fundPlan = plan;
          _errorText = null;
          _errorCause = null;
          _fundingStage = OrderFundingStage.bitcoin;
        });
        _closeForStandingOrder();
        return BitcoinFundedOrderRequest(
          venue: OneBalanceVenue.investing,
          otherVenueUsed: rest.otherUsd > 0,
          grant: grant,
          plan: leg,
          label: FundedOrderLabel(
            venue: OneBalanceVenue.investing,
            orderUsd: marginUsd,
            side: _sideWord(),
            market: FundedOrderLabel.shortName(market.coin),
            marketKey: market.coin,
          ),
          fundUsd: planFundUsd,
          readyUsd: ready,
          // Each source's share is this order's from the accept.
          dollarsUsd: math.min(dollars, planFundUsd),
          otherVenueUsd: rest.otherUsd,
          entrySource: _entrySource,
          // Runs whatever happens to this ticket: reads only the
          // container. The rest from the other venue under the same
          // grant, then the move from Dollars.
          fundVenue: (controller, legs) => fundRestThenMove(
            legs: legs,
            puller: container.read(venueCashPullerProvider),
            venue: OneBalanceVenue.investing,
            fundUsd: planFundUsd,
            readyUsd: ready,
            needsOtherVenue: rest.otherUsd > 0,
            grant: grant,
            queue: ({
              required double fundUsd,
              required double readyUsd,
              required double directArrivingUsd,
              String? moveId,
            }) async {
              final outcome = await container
                  .read(pendingHyperliquidOrderProvider.notifier)
                  .fundAndQueue(
                    pending.copyWith(
                        bitcoinSentAt: legs.bitcoinSentAt,
                        bitcoinLandedAt: legs.bitcoinLandedAt),
                    grant: grant,
                    controller: controller,
                    orderUsd: marginUsd,
                    requiredUsd: required,
                    readyUsd: readyUsd,
                    fundUsd: fundUsd,
                    continueJourney: true,
                  );
              if (outcome case OrderFundingFunded(:final move)) {
                // The order's own move is the last leg of its
                // multi-source move: one Activity row.
                MultiSourceMoveStore.attachFinal(
                    moveId, move.operationId ?? move.quoteId);
              }
              return outcome;
            },
          ),
          dropOrder: () {
            final current = container.read(pendingHyperliquidOrderProvider);
            if (current != null &&
                identical(current.placement, pending.placement) &&
                !PendingHyperliquidOrderNotifier.isActive(current)) {
              container.read(pendingHyperliquidOrderProvider.notifier).clear();
            }
            AuthGrantRegistry.instance
                .cancelAutofire(kPendingHlOrderAutofireId);
            grant.revoke();
          },
        );
      },
    );
    if (run == null) {
      if (declined) {
        _stopped('signing_declined');
        TrackingService.track('order_funding_abandoned', params: {
          'venue': 'hyperliquid',
          'stage': 'approval',
          'funding_source': 'bitcoin',
        });
      }
      if (mounted) _updateDraft(() => _fundingStage = null);
      return;
    }
    _bitcoinRunId = run.id;
    unawaited(run.ended.then((end) {
      if (mounted) _onBitcoinRunEnded(run.id, end);
    }));
  }

  /// The ticket's Bitcoin-funded run ended. A placed order or a venue
  /// refusal is the pending listener's (receipt, or the venue's message);
  /// a chain that stopped before the order says so here, with the money
  /// where it is.
  void _onBitcoinRunEnded(String id, BitcoinFundedEnd end) {
    if (_bitcoinRunId != id || _completed) return;
    _bitcoinRunId = null;
    if (end == BitcoinFundedEnd.placed ||
        end == BitcoinFundedEnd.placementFailed) {
      return;
    }
    _pendingSub?.close();
    _pendingSub = null;
    _fillSub?.cancel();
    final error = ref.read(bitcoinFundedOrderRunnerProvider).errorOf(id);
    _stopped('funding_refused', error: error);
    // The steps keep the stop: the failed step and one line saying what
    // happened and where the money is; the button is the order again.
    _updateDraft(() {
      _isPlacing = false;
      _preparing = false;
      _fundingStage = null;
      _errorCause = null;
      _errorText = null;
    });
  }

  /// The X "Add $X to Investments" names on a hot ticket
  /// ([BitcoinLegRules.addUsd], on the order typed or, with nothing typed,
  /// the market's minimum): what the tap converts from bitcoin. Whether
  /// the bitcoin covers it is decided at the tap ([decideSlipFunding]) on
  /// the wallet's own figures. Set by the build.
  double? _shownAddUsd;

  /// [_shownAddUsd] as it was at the Add tap: what the leg converts.
  double? _bitcoinTapAddUsd;

  /// The order an empty hot ticket's button stands for (the market's
  /// minimum), while nothing is typed. Set by the build.
  double? _emptyMinimumUsd;

  /// From the first time "Add" shows, holds the wallet's own Spark
  /// address (the Bitcoin leg's pinned recipient) so the tap finds it
  /// ready instead of waiting on a cold SDK. Once per ticket; a failed
  /// read is let go and the tap reads again.
  void _warmBitcoinLeg() {
    if (_ownSparkWarmed || _isLedger) return;
    _ownSparkWarmed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _ownSparkWarm != null) return;
      try {
        if (pickSpendingWallet(ref.read(settingsProvider)) == null) return;
        _ownSparkWarm = ref.listenManual(sparkSelfAddressProvider, (_, next) {
          if (next.hasError) {
            _ownSparkWarm?.close();
            _ownSparkWarm = null;
          }
        });
      } catch (_) {}
    });
  }

  /// The step lines of a funded order on this ticket: the Bitcoin leg
  /// (only with one), the move into Investing, the order.
  List<String> _fundingSteps(FundedOrderRecord record) => [
        if (record.fromBitcoin)
          _strings.slipStepAddingToInvestments(formatHlUsd(record.addUsd)),
        _strings.slipStepPreparingOrder,
        _strings.slipStepOpeningOrder(formatHlUsd(record.label.orderUsd),
            record.label.side, market.annotatedName ?? market.coin),
      ];

  /// The funded order for the market on this ticket (this ticket's, or
  /// one started before it was reopened): on its way, just placed while
  /// this ticket still follows it, or stopped and not yet tried again.
  FundedProgress? _fundedProgress(List<FundedOrderRecord> records) {
    if (_isLedger) return null;
    final progress = FundedOrdersNotifier.progressOn(
        records, OneBalanceVenue.investing, market.coin, DateTime.now());
    if (progress != null && progress.done && !_isPlacing && !_completed) {
      return null;
    }
    return progress;
  }

  /// The ticket's rubber band around its button and steps: a funded
  /// order's tension follows its steps; any other placement eases while
  /// it is placing. Success snaps back, a stop lets go softly.
  Widget _orderBand({required FundedProgress? funded, required Widget child}) {
    if (funded != null) {
      return RubberBandProgress(
        key: const ValueKey('order-slip-funded-progress'),
        // Left: the pull is felt no more.
        haptic: !_left,
        progress: funded.progress,
        outcome: funded.done
            ? RubberBandOutcome.success
            : funded.failed
                ? RubberBandOutcome.failure
                : RubberBandOutcome.none,
        child: child,
      );
    }
    return RubberBandBusy(
      key: const ValueKey('order-slip-placement-band'),
      haptic: !_left,
      busy: _checkingConnection ||
          (!_isLedger && (_isPlacing || _preparing) && !_completed),
      outcome: _completed ? RubberBandOutcome.success : null,
      expected: const Duration(seconds: 3),
      child: child,
    );
  }

  /// A new try on this market: an earlier stop's steps give way to it.
  void _clearFundedStop() {
    if (_isLedger) return;
    final progress = FundedOrdersNotifier.progressOn(
        ref.read(fundedOrdersProvider),
        OneBalanceVenue.investing,
        market.coin,
        DateTime.now());
    if (progress != null && progress.failed) {
      ref.read(fundedOrdersProvider.notifier).clearStop(progress.record.id);
    }
  }

  /// The move stopped before any funds left: the queued order is gone
  /// (the notifier cleared it with its grant), the ticket says why
  /// ([inSteps]: in the funded steps, where the failed step and the line
  /// under it carry it, so never a second notice).
  void _fundingFailedBeforeMove(String stage, Object? error, String message,
      {bool inSteps = false}) {
    _fillSub?.cancel();
    _pendingSub?.close();
    _pendingSub = null;
    _trackFundingFailed(stage, error);
    _lastErrorCategory = TrackingService.errorCategory(error);
    _stopped('funding_refused', error: error);
    if (!mounted) return;
    _updateDraft(() {
      _isPlacing = false;
      _preparing = false;
      _fundingStage = null;
      _errorText = inSteps ? null : message;
      _errorCause = inSteps ? null : error;
    });
  }

  /// Follows the queued order from the credit to the placement: the
  /// placing stage, then the venue's answer (the receipt, or the ticket
  /// closing on an accepted order) or the failure, on this ticket.
  void _listenPending() {
    _pendingSub?.close();
    _pendingSub = ref.listenManual(pendingHyperliquidOrderProvider,
        (previous, next) {
      // Left: the order's end is Sal's (the toast), never this ticket's.
      if (!mounted || next == null || _left) return;
      switch (next.status) {
        case PendingHlOrderStatus.placing:
          _trackFundingStep(OrderFundingStage.order);
          _trackStep('placing');
        case PendingHlOrderStatus.done:
          _onFundedPlaced(next);
        case PendingHlOrderStatus.failed:
          _onFundedFailed(next);
        case PendingHlOrderStatus.unconfirmed:
          _onFundedUnconfirmed(next);
        case PendingHlOrderStatus.awaitingDeposit:
        case PendingHlOrderStatus.awaitingBalance:
          break;
      }
    });
  }

  /// The queued order went out and its answer never came, and the account
  /// could not say either: the ticket says the result is not confirmed,
  /// never that it failed, and its fill listener stays on, so a fill that
  /// lands still ends on the receipt.
  void _onFundedUnconfirmed(PendingHlOrderIntent intent) {
    if (_completed || !mounted) return;
    _pendingSub?.close();
    _pendingSub = null;
    _stopped('order_unconfirmed');
    _updateDraft(() {
      _isPlacing = false;
      _fundingStage = null;
      _unconfirmedLock = true;
      _errorText = intent.errorMessage ?? _strings.investingSubmissionUnknown;
      _errorCause = null;
    });
    // Fills of it the stream already brought end on the receipt.
    _settleFromStream();
  }

  /// The watcher placed the funded order: the same receipt the direct
  /// path shows (filled, resting, or accepted and closing the ticket).
  Future<void> _onFundedPlaced(PendingHlOrderIntent intent) async {
    if (_completed || !mounted) return;
    _pendingSub?.close();
    _pendingSub = null;
    _fundingStage = null;
    final result = intent.result;
    if (intent.orderKind == 'limit' && result != null) {
      _onLimitAnswered(result);
      return;
    }
    if (result != null && result.filledSz > 0) {
      String? trailNote;
      if (intent.orderKind == 'market') {
        trailNote = await _placeAttachedTrailing(result.filledSz);
        if (!mounted) return;
      }
      _onFilled(
          sizeFilled: result.filledSz,
          avgPx: result.avgPx,
          notices: [
            ...hlOrderResultNotices(_strings, result),
            if (trailNote != null) trailNote,
          ]);
      return;
    }
    if (intent.orderKind != 'market') {
      _onRestingAccepted(result: result);
      return;
    }
    // Accepted but not (yet) filled — the WS listener / placing tile
    // takes over; close the ticket so the person is not trapped.
    if (!_completed) {
      _closeTicket();
    }
  }

  /// The funded order did not place (the credit never came, the grant
  /// lapsed, the venue refused): the ticket shows the watcher's own
  /// message, with the money where it is (the sweeper brings idle venue
  /// cash home).
  void _onFundedFailed(PendingHlOrderIntent intent) {
    if (_completed || !mounted) return;
    _pendingSub?.close();
    _pendingSub = null;
    _fillSub?.cancel();
    _stopped('funding_failed');
    _updateDraft(() {
      _isPlacing = false;
      _fundingStage = null;
      _errorText = intent.errorMessage ?? _strings.errorCopyGeneric;
      _errorCause = null;
    });
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
      ...TrackingService.exactUsd('amount_usd', marginUsd),
      'kind': isSpot ? 'spot' : 'perp',
    });
    _trackStep('review');
    _updateDraft(() {
      _ledgerBusy = true;
      _errorText = null;
      _errorCause = null;
    });
    final HlOrderResult? result;
    // A whole close on the Ledger leaves its stops and takes (each cancel
    // needs the device): counted before it goes, said on the receipt as
    // the close sheet says it.
    int? ledgerLeftovers;
    var closingSize = 0.0;
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
        if (plan.effect == HlPositionEffect.close) {
          closingSize = plan.heldSize;
          ledgerLeftovers = _ledgerProtectiveCount(walletId);
        }
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
    // offeredMaxLeverage is at least 1: a market reporting no leverage
    // (0) would otherwise put clamp's upper bound below its lower one.
    final ledgerLev =
        isSpot ? 1 : HlIntents.clampLeverage(market, _leverage);
    TrackingService.hyperliquidOrderPlaced(
      coin: market.coin,
      kind: isSpot ? 'spot' : 'perp',
      isBuy: _isLong,
      leverage: ledgerLev,
      marginUsd: marginUsd,
      notionalUsd: marginUsd * ledgerLev,
      source: widget.source,
      orderType: 'market',
      isCross: isSpot ? null : kHlCrossMarginOffered,
      filled: filled,
      walletKind: 'ledger',
      marketType: isSpot ? 'spot' : (market.dex.isEmpty ? 'perp' : market.dex),
      hasTp: _attachTpSl && _parse(_tpController) != null,
      hasSl: _attachTpSl && _parse(_slController) != null,
    );
    if (!mounted) return;
    String? trailNote;
    if (filled) {
      final mid = _midNow();
      final fallbackSize = mid > 0
          ? sizeFromUsd(
              usd: marginUsd * (isSpot ? 1 : _leverage),
              px: mid,
              szDecimals: market.szDecimals)
          : 0.0;
      trailNote = await _placeAttachedTrailing(
          result.filledSz > 0 ? result.filledSz : fallbackSize);
      if (!mounted) return;
    }
    // The whole position closed: its stops and takes are still there.
    final leftOnLedger = ledgerLeftovers != null &&
            closingSize > 0 &&
            result.filledSz >= closingSize * (1 - 1e-9)
        ? ledgerLeftovers
        : null;
    final leftReceipt = hlLedgerLeftoverReceipt(l10n, leftOnLedger);
    final detailLines = [
      if (trailNote != null) trailNote,
      if (leftReceipt.note case final note?) note,
    ];
    Navigator.of(context).pop();
    showLedgerConfirmation(
      navigator,
      message: filled ? l10n.ledgerOrderFilled : l10n.ledgerOrderPlaced,
      amount: l10n.slipCtaSideAmount(
          isSpot
              ? (_isLong ? l10n.buy : l10n.sell)
              : (_isLong ? l10n.longLabel : l10n.shortLabel),
          formatHlUsd(marginUsd)),
      contextLine: HlMarket.baseCoin(market.coin),
      rows: {
        if (!isSpot) l10n.ledgerSummaryLeverage: '$ledgerLev×',
        ...leftReceipt.rows,
      },
      detail: detailLines.isEmpty ? null : detailLines.join(' '),
      tone: filled ? KuteConfirmationTone.success : KuteConfirmationTone.pending,
    );
  }

  /// The Ledger's protective orders on this coin, from its last account
  /// read: null when there are none, -1 when its orders could not be read
  /// (they may still be there). The close sheet's same count.
  int? _ledgerProtectiveCount(String walletId) {
    final orders =
        ref.read(ledgerHlAccountProvider(walletId)).valueOrNull?.openOrders;
    if (orders == null) return -1;
    final n = hlProtectiveOrdersFor(orders, market.wireCoin).length;
    return n == 0 ? null : n;
  }

  /// The one funding door. A Ledger ticket opens the Move sheet locked to
  /// its own Investing account with the margin filled in. A hot ticket's
  /// "Add $X to Investments" first asks [decideSlipFunding], the same
  /// decision the bet slip makes, on the spending bitcoin read fresh when
  /// the app's figures are not in yet ("Calculating…" meanwhile):
  ///  * the bitcoin covers X and an order is typed: the tap is the order
  ///    itself, funded Bitcoin → Dollars → Investing under its one
  ///    approval, with the steps on this ticket;
  ///  * the bitcoin does not cover X: the Investments Receive sheet, since
  ///    the money has to come from outside;
  ///  * nothing could be read: a message, no sheet.
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
    final shown = _shownAddUsd;
    if (_isLedger || shown == null || shown <= 0) {
      await _openDollarsDoor();
      return;
    }
    final read = ProviderScope.containerOf(context, listen: false).read;
    setState(() {
      _depositDoorBusy = true;
      _depositCalculating = true;
    });
    SlipFundingDecision decision;
    try {
      decision = await decideSlipFunding(read, addUsd: shown);
    } finally {
      if (mounted) {
        setState(() {
          _depositDoorBusy = false;
          _depositCalculating = false;
        });
      }
    }
    if (!mounted) return;
    switch (decision.route) {
      case SlipFundingRoute.bitcoin:
        // Nothing typed: the order the button was sized for (the market's
        // minimum), drawn before the confirm reads the ticket, then funded
        // in place like a typed one.
        final minimum = _emptyMinimumUsd;
        if (_marginUsd <= 0 && minimum != null) {
          _fillAmountChip(minimum, 'min_direct', haptic: false);
          await WidgetsBinding.instance.endOfFrame;
          if (!mounted) return;
        }
        if (await slipBitcoinChainStoodIn(
                OneBalanceVenue.investing, decision) ||
            !mounted) {
          return;
        }
        _bitcoinArmed = true;
        _bitcoinFellBack = false;
        _bitcoinFallbackUsd = null;
        _bitcoinTapAddUsd = shown;
        _bitcoinTapPlan = decision.plan;
        try {
          await _handleConfirm();
        } finally {
          _bitcoinArmed = false;
          _bitcoinTapPlan = null;
        }
        if (!mounted || !_bitcoinFellBack) return;
        await _openInvestmentsReceive(_bitcoinFallbackUsd ?? shown);
      case SlipFundingRoute.insufficient:
        await _openInvestmentsReceive(shown);
      case SlipFundingRoute.unavailable:
        _stopped('funding_quote');
        showMessageSnackBar(
            context: context,
            message: context.l10n.errorCopyGeneric,
            error: true);
    }
  }

  /// The Investments Receive sheet for an X the bitcoin cannot cover
  /// ([openSlipReceive]); the ticket stays open underneath, its door shut
  /// while the sheet is up.
  Future<void> _openInvestmentsReceive(double addUsd) async {
    if (!mounted) return;
    _stopped('insufficient_balance');
    _trackStep('deposit');
    setState(() => _depositDoorBusy = true);
    try {
      // `slip_top_up_opened` is sent by openSlipReceive itself.
      await openSlipReceive(context,
          venue: SlipVenue.investing,
          depositWhenKnownEmpty: true,
          onDepositCompleted: slipTopUpReturned,
          addUsd: addUsd,
          shortfallUsd: _slipShortfallUsd);
    } catch (_) {
      if (mounted) {
        showMessageSnackBar(
            context: context,
            message: context.l10n.errorCopyGeneric,
            error: true);
      }
    } finally {
      if (mounted) setState(() => _depositDoorBusy = false);
    }
  }

  /// The Move sheet: a Ledger ticket's, locked to its own Investing
  /// account; a hot ticket's Bitcoin → Dollars door, prefilled with what
  /// Investments lack for this order's move.
  Future<void> _openDollarsDoor() async {
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
      // Hot ticket: money only reaches Investing through an order funded
      // from Dollars, so the door is the Dollar deposit, prefilled with
      // what Investments lack for this order's move. The ticket stays open
      // underneath with the same coin, side, size, leverage and order
      // type; once the Dollars are there the button is the order again.
      final shortfall = _slipShortfallUsd;
      final fundUsd = _fundPlanFor(shortfall).fundUsd;
      final target = _dollarsShortUsd(fundUsd, haveUsd: _slipInvestmentsUsd);
      TrackingService.track('slip_top_up_opened', params: {
        'venue': 'hyperliquid',
        'shortfall_bucket': TrackingService.usdBucket(shortfall),
        ...TrackingService.exactUsd('shortfall_usd', shortfall),
        'top_up_bucket': TrackingService.usdBucket(target),
        ...TrackingService.exactUsd('top_up_usd', target),
        'prefill_rule': 'dollars_shortfall',
        'suggested_source': 'dollars',
      });
      final seam = debugShowHlDollarsDeposit;
      if (seam != null) {
        await seam(MoveLockedSide.depositToUsd, target > 0 ? target : null);
        return;
      }
      await showDepositSheet(
        context,
        lockedSide: MoveLockedSide.depositToUsd,
        initialTargetUsd: target > 0 ? target : null,
        onCompleted: () {
          if (!mounted) return;
          TrackingService.track('slip_top_up_returned', params: {
            'venue': 'hyperliquid',
            'top_up_bucket': TrackingService.usdBucket(target),
            ...TrackingService.exactUsd('top_up_usd', target),
          });
          slipTopUpReturned();
        },
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

  /// The hot account's Investing cash that is ready: perp withdrawable
  /// plus spot USDC (the notifier sweeps between them on the way).
  double _hlReadyUsd() {
    var spot = 0.0;
    for (final b in ref.read(hyperliquidSpotBalancesProvider)) {
      if (b.coin == 'USDC') spot += b.available;
    }
    final queued = ref.read(pendingHyperliquidOrderProvider);
    // Less what a bet accepted meanwhile is about to pull from it
    // (committed_funds.dart): never this order's.
    final held = ref
        .read(committedFundsProvider.notifier)
        .heldUsd(MoneyPlace.investing, exceptHeldOn: OneBalanceVenue.investing);
    return hlSlipReadyUsd(
      withdrawableUsd: ref.read(hyperliquidWithdrawableProvider),
      spotUsdc: spot,
      // A funded order still queued or placing owns the money it moved;
      // a bet's leg about to leave owns its share.
      queuedRequiredUsd: (PendingHyperliquidOrderNotifier.isActive(queued)
              ? PendingHlOrderAutoFire.requiredFor(queued!)
              : 0) +
          held,
      // A sweep carrying the venue's cash home right now: none of it is
      // this order's (the funding then covers the whole order).
      sweeping: ref.exists(venueSweeperProvider) &&
          ref
              .read(venueSweeperProvider)
              .sweeping
              .contains(OneBalanceVenue.investing),
    );
  }

  /// Why the market cannot take a funded order right now (checked before
  /// any money moves), or null: a builder perp whose dex does not settle
  /// in USDC (or whose collateral cannot be confirmed) can't be funded
  /// with Dollars, a perp at its open-interest cap refuses new exposure,
  /// and a market no longer listed (delisted, halted out of the venue's
  /// universe) takes nothing. On a block it also sets the reason the
  /// slip shows.
  Future<String?> _fundedMarketBlock() async {
    final hip3 = !isSpot && market.dex.isNotEmpty;
    bool? usdcCollateral = true;
    if (hip3) {
      try {
        usdcCollateral = await ref
            .read(hyperliquidTradingModelProvider)
            .isUsdcCollateralDex(market.dex)
            .timeout(const Duration(seconds: 4));
      } catch (_) {
        usdcCollateral = null;
      }
    }
    bool? listed;
    try {
      final markets = await (isSpot
              ? ref.read(hyperliquidSpotMarketsProvider.future)
              : ref.read(hyperliquidPerpMarketsProvider.future))
          .timeout(const Duration(seconds: 4));
      if (markets.isNotEmpty) {
        // The dex-qualified coin: a bare name repeats across dexes.
        listed = markets.any((m) => m.wireCoin == market.wireCoin);
      }
    } catch (_) {
      // The list could not be read: the venue answers at the order.
    }
    final reason = hlFundedMarketBlock(
      isSpot: isSpot,
      reduceOnly: _reduceOnly,
      oiCapped: ref
              .read(hyperliquidOiCappedProvider(market.dex))
              .valueOrNull
              ?.contains(market.wireCoin) ??
          false,
      listed: listed,
      hip3: hip3,
      usdcCollateral: usdcCollateral,
    );
    if (reason != null && hlFundedBlockIsMarketUnavailable(reason)) {
      _fundedBlockText = _strings.salMarketUnavailable;
    } else {
      _fundedBlockText = null;
    }
    return reason;
  }

  /// What the slip says for the last [_fundedMarketBlock] block: the
  /// market's own reason when it has one, else the generic retry line.
  String? _fundedBlockText;

  /// The venue cash this order takes: the margin with its price headroom
  /// plus fees.
  double _hlRequiredUsd() => _hlRequiredUsdFor(_marginUsd);

  /// [_hlRequiredUsd] for an order of [marginUsd] with the ticket's
  /// leverage and slippage.
  double _hlRequiredUsdFor(double marginUsd) =>
      ShortfallRules.hyperliquidRequiredUsd(
        marginUsd: marginUsd,
        leverage: isSpot ? 1 : _leverage,
        slippagePct: _mode == _OrderMode.market ? _slippagePct : 0,
      );

  /// Reads the Investing account now (bounded); a failed read keeps the
  /// last figures.
  Future<void> _refreshVenueCashNow() async {
    if (_isLedger) return;
    try {
      await ref
          .read(hyperliquidAccountProvider.notifier)
          .refresh()
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  /// Nothing on the Investing account yet: no cash and no position.
  bool _accountUnfunded() {
    if (_isLedger) return false;
    var ready = ref.read(hyperliquidWithdrawableProvider);
    for (final b in ref.read(hyperliquidSpotBalancesProvider)) {
      if (b.coin == 'USDC') ready += b.total;
    }
    return ready < 0.01 && ref.read(hyperliquidPerpPositionsProvider).isEmpty;
  }

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
  /// openPosition), at [marginUsd] when a funded order goes out smaller
  /// than typed. Every ticket value is read here, once: the call may run
  /// from the auto-fire after the ticket is gone.
  _SlipOrder _marketOrder(String walletId, String cloid, {double? marginUsd}) {
    final trading = ref.read(hyperliquidTradingProvider.notifier);
    final isLong = _isLong;
    final margin = marginUsd ?? _marginUsd;
    final slippagePct = _slippagePct;
    final source = widget.source;
    if (isSpot) {
      return _SlipOrder(
        HlIntents.spotOrder(
          walletId: walletId,
          market: market,
          isBuy: isLong,
          usd: margin,
          slippagePct: slippagePct,
        ),
        (grant) => trading.placeSpotOrder(
          market: market,
          isBuy: isLong,
          usd: margin,
          slippagePct: slippagePct,
          source: source,
          cloid: cloid,
          grant: grant,
        ),
      );
    }
    final leverage = _leverage;
    final isCross = _isCross;
    final takeProfitPx = _attachTpSl ? _parsePx(_tpController) : null;
    final stopLossPx = _attachTpSl ? _parsePx(_slController) : null;
    return _SlipOrder(
      HlIntents.openPosition(
        walletId: walletId,
        market: market,
        isLong: isLong,
        marginUsd: margin,
        leverage: leverage,
        slippagePct: slippagePct,
        isCross: isCross,
        takeProfitPx: takeProfitPx,
        stopLossPx: stopLossPx,
      ),
      (grant) => trading.openPosition(
        market: market,
        isLong: isLong,
        marginUsd: margin,
        leverage: leverage,
        slippagePct: slippagePct,
        isCross: isCross,
        takeProfitPx: takeProfitPx,
        stopLossPx: stopLossPx,
        source: source,
        cloid: cloid,
        onSent: _onMarketSent,
        grant: grant,
      ),
    );
  }

  /// A margin-parameterised copy of [_marketOrder] with the ticket read
  /// once, for the auto-fire to resize a funded market order after the
  /// ticket's controllers are gone.
  _SlipOrder Function(double marginUsd) _marketOrderAt(
      String walletId, String cloid) {
    final trading = ref.read(hyperliquidTradingProvider.notifier);
    final isLong = _isLong;
    final slippagePct = _slippagePct;
    final source = widget.source;
    final leverage = _leverage;
    final isCross = _isCross;
    final takeProfitPx = _attachTpSl ? _parsePx(_tpController) : null;
    final stopLossPx = _attachTpSl ? _parsePx(_slController) : null;
    final spot = isSpot;
    final mkt = market;
    return (margin) => spot
        ? _SlipOrder(
            HlIntents.spotOrder(
              walletId: walletId,
              market: mkt,
              isBuy: isLong,
              usd: margin,
              slippagePct: slippagePct,
            ),
            (grant) => trading.placeSpotOrder(
              market: mkt,
              isBuy: isLong,
              usd: margin,
              slippagePct: slippagePct,
              source: source,
              // A send again after a margin refusal goes under a fresh
              // cloid (HlResendCloids), never this one twice.
              cloid: HlResendCloids.current(cloid),
              grant: grant,
            ),
          )
        : _SlipOrder(
            HlIntents.openPosition(
              walletId: walletId,
              market: mkt,
              isLong: isLong,
              marginUsd: margin,
              leverage: leverage,
              slippagePct: slippagePct,
              isCross: isCross,
              takeProfitPx: takeProfitPx,
              stopLossPx: stopLossPx,
            ),
            (grant) => trading.openPosition(
              market: mkt,
              isLong: isLong,
              marginUsd: margin,
              leverage: leverage,
              slippagePct: slippagePct,
              isCross: isCross,
              takeProfitPx: takeProfitPx,
              stopLossPx: stopLossPx,
              source: source,
              // A send again after a margin refusal goes under a fresh
              // cloid (HlResendCloids), never this one twice.
              cloid: HlResendCloids.current(cloid),
              onSent: _onMarketSent,
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
            (_attachTpSl && !reduceOnly) ? _parsePx(_tpController) : null;
        final stopLossPx =
            (_attachTpSl && !reduceOnly) ? _parsePx(_slController) : null;
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
            grant: grant,
          ),
        );
      case _OrderMode.pro:
        switch (_proType) {
          case _ProType.scale:
            final startPx = _parsePx(_startPxController) ?? entry;
            final endPx = _parsePx(_endPxController) ?? entry;
            // 2..50 is checked inline before Confirm; the clamp only
            // guards a ticket that changed under the approval.
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
                // The cloid this send goes under: its legs' ids derive
                // from it (hlScaleLegCloids), and the lookup after an
                // unclear answer and "Confirming…" key on the same.
                cloid: HlResendCloids.current(cloid),
                grant: grant,
              ),
            );
          case _ProType.twap:
            // The bounds are checked inline before Confirm
            // ([HlTwapRules]); the notifier refuses anything else before
            // a leverage write or any money moves, never clamps it.
            final minutes = _parseInt(_twapMinutesController) ?? 30;
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
                grant: grant,
              ),
            );
        }
    }
  }

  /// The legs the scale order on the ticket sends (as [_advancedOrder]
  /// clamps them), null when the ticket is not a scale order.
  int? _scaleLegsNow() => _isScale
      ? (_parseInt(_countController) ?? 5).clamp(2, 50)
      : null;

  /// The stop-loss on the ticket sits past the estimated liquidation (set
  /// by the build, read by [_buildTpSlAttach]).
  bool _slPastLiquidation = false;

  /// The value of the least-worth leg the scale order on the ticket would
  /// send ([hlScaleLegs], the venue's own legs: the total size at the
  /// range's middle, split equally, each leg at its own price). Null while
  /// the range or the count cannot describe one.
  double? _scaleLowestLegUsd(double notional, int? count) {
    final s = _parsePx(_startPxController);
    final e = _parsePx(_endPxController);
    if (s == null || e == null || count == null || count < 2) return null;
    final avg = (s + e) / 2;
    final total =
        sizeFromUsd(usd: notional, px: avg, szDecimals: market.szDecimals);
    if (total <= 0) return 0;
    try {
      final legs = hlScaleLegs(
          market: market,
          totalSize: total,
          startPx: s,
          endPx: e,
          count: count.clamp(2, kHlScaleMaxOrders));
      return legs
          .map((l) => double.parse(l.px) * double.parse(l.sz))
          .reduce(math.min);
    } catch (_) {
      // A leg that rounds to nothing is worth nothing.
      return 0;
    }
  }

  /// [px] as the wire sends it ([roundPrice]: five significant figures,
  /// the market's decimal cap), so the approval binds the price the venue
  /// gets. Null for nothing usable.
  double? _wirePx(double? px) =>
      wireRoundedPrice(px, szDecimals: market.szDecimals, isSpot: isSpot);

  /// A typed price, wire-rounded ([_wirePx]).
  double? _parsePx(TextEditingController c) => _wirePx(_parse(c));

  /// Accepted but not (yet) filled: the WS listener / placing tile takes
  /// over and the ticket closes so the person is not trapped. In place
  /// ([HlOrderSlipSheet.embedded]) the page stays: only what stands over
  /// it goes, and the page starts a fresh ticket.
  void _closeTicket() {
    final navigator = Navigator.of(context, rootNavigator: true);
    final ticketRoute = ModalRoute.of(context);
    navigator.popUntil((route) => route == ticketRoute || route.isFirst);
    if (widget.embedded) {
      widget.onEmbeddedDone?.call();
      return;
    }
    if (ticketRoute?.isCurrent == true && navigator.canPop()) {
      navigator.pop();
    }
  }

  /// Before a receipt: the sheets down to the host, or, in place, what
  /// stands over the page holding the ticket ([ticketRoute]).
  void _popDownToHost(NavigatorState nav, Route<dynamic>? ticketRoute) {
    if (widget.embedded) {
      nav.popUntil((route) => route == ticketRoute || route.isFirst);
    } else {
      HlOrderSlipSheet.popAllSheetsDownToHost(nav);
    }
  }

  /// Accepted is distinct from filled; show a receipt without inventing a fill.
  Future<void> _onRestingAccepted({HlOrderResult? result}) async {
    if (_completed || !mounted || _left) return;
    _completed = true;
    _fillSub?.cancel();
    final amount = formatDollars(_marginUsd);
    // What was placed, as it was sent (the ticket may have been reset
    // since), and what of it the venue did not take.
    final sent = _sentReceipt ?? _receiptNow();
    final notices = hlOrderResultNotices(_strings, result);
    final nav = Navigator.of(context, rootNavigator: true);
    final ticketRoute = ModalRoute.of(context);
    // The rebuild flips the band to its success snap; the sheet closes
    // once the snap has been seen (RubberBand.settle returns at once under
    // Reduce Motion, covered or in the background).
    setState(() {});
    await RubberBand.settle(context);
    if (!nav.mounted || _left) return;
    _popDownToHost(nav, ticketRoute);
    pushKuteSuccessOverlay(
      navigator: nav,
      overlay: HlOrderAcceptedOverlay(
          coin: market.coin,
          market: market,
          amount: amount,
          isClose: sent.isClose,
          rows: sent.rows,
          detail: sent.detail,
          notices: notices,
          viewOrders: !_isLedger),
    );
    if (widget.embedded) widget.onEmbeddedDone?.call();
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

  Future<void> _onFilled({
    required double sizeFilled,
    required double avgPx,
    Iterable<HlFill> fills = const [],
    double restingSize = 0,
    List<String> notices = const [],
    HlLeftoverSweep? leftovers,
  }) async {
    if (_completed || !mounted || _left) return;
    _completed = true;
    _fillSub?.cancel();
    // What the fill did to the position held when the order went out:
    // the same plan as the slip, sized on what actually filled.
    final filledPlan = isSpot
        ? null
        : hlFilledPlan(_sentPlan,
            sizeFilled: sizeFilled, szDecimals: market.szDecimals);
    final nav = Navigator.of(context, rootNavigator: true);
    final ticketRoute = ModalRoute.of(context);
    // The fee the fills paid, as the exchange reported it with each fill
    // (exact, Kute's builder fee inside it), the receipt's "Fee" row: the
    // one figure the slip's estimates can be read against. UX analytics
    // (fee_shown_*), never a balance; revenue itself stays the backend's
    // builder export.
    final paidFeeUsd = hlFeeFromFills(
        fills.isNotEmpty ? fills : _orderFills, sizeFilled);
    if (paidFeeUsd != null) {
      TrackingService.track('hyperliquid_fill_fee_reported', params: {
        'venue': 'hyperliquid',
        'coin': market.coin,
        'kind': isSpot ? 'spot' : 'perp',
        ...VenueAnalytics.hlAssetParams(market.coin,
            kind: isSpot ? 'spot' : 'perp'),
        'wallet_kind': 'hot',
        'fee_shown_usd': (paidFeeUsd * 100).round() / 100,
        'fee_shown_basis': 'fill',
        ...TrackingService.exactUsd('notional_usd', sizeFilled * avgPx),
      });
    }
    // Let the band's success snap play before the sheet goes.
    setState(() {});
    await RubberBand.settle(context);
    if (!nav.mounted || _left) return;
    _popDownToHost(nav, ticketRoute);
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
      // The fee the fills paid, as the exchange reported it (exact).
      feeUsd: paidFeeUsd,
      restingSize: restingSize,
      notices: notices,
      leftovers: leftovers,
    );
    // In place: a fresh ticket under the receipt.
    if (widget.embedded) widget.onEmbeddedDone?.call();
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Reopened from Sal's placing toast: once its order is placed the
    // ticket goes, and Sal's result toast says so (nothing is placed
    // here, so there is no receipt of the ticket's own). So does every
    // other end with nothing on the ticket to show (founder, 11 November
    // 2026, on 2.2.0 (109): nothing may stay "Placing" once the venue has
    // the order): resting on the book or over quietly (its record gone),
    // cancelled, or not placed with no funded stop to show. A funded
    // move's stop stays on the ticket as it does on the one that was left.
    final followed = widget.standingEndedBefore;
    if (followed != null) {
      final coin = market.coin;
      ref.listen<StandingOrderState?>(
          standingOrdersProvider.select(
              (all) => _standingOrderIn(all, coin, followed)?.state),
          (prev, next) {
        if (_left || !mounted) return;
        final ended = next == null
            ? prev != null
            : next == StandingOrderState.filled ||
                next == StandingOrderState.cancelled ||
                (next == StandingOrderState.failed &&
                    !(_fundedProgress(ref.read(fundedOrdersProvider))
                            ?.failed ??
                        false));
        if (ended) Navigator.of(context).maybePop();
      });
    }
    return _buildTicket(context, ref);
  }

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
    // Shut only by the region: "Check connection", never Close.
    final ledgerRegionBlocked = _isLedger &&
        opaqueActions &&
        ledgerTradingEnabled &&
        !geoAllowed &&
        !_ledgerPending &&
        ref
            .watch(runtimeCapabilitiesProvider)
            .decision('hyperliquid.browse')
            .regionBlocked;

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
    // What the hot ticket's "Available" and Max stand for: the whole
    // spendable Investments (this account's cash plus Dollars and the
    // other venue's reachable cash), the figure the one-balance planner
    // draws on, never the Investing cash alone. A Ledger, and a spot sell
    // (what is held), keep their own figure.
    final buysFromInvestments = !_isLedger && !(isSpot && !_isLong);
    final otherSpendableUsd = buysFromInvestments
        ? ref
            .watch(investmentsSpendableExcludingProvider(
                OneBalanceVenue.investing))
            .maxUsd
        : 0.0;
    if (buysFromInvestments) ref.watch(venueCashRefreshProvider);
    final shownAvailable = buysFromInvestments
        ? slipAvailableUsd(
            venueUsd: available, otherSpendableUsd: otherSpendableUsd)
        : available;
    // What the "Available" line reads: the same, plus what the spending
    // Bitcoin can land, since funded orders draw on it too (founder,
    // 27 October 2026). The line only: Max and the minimum keep
    // [shownAvailable].
    // Send mode: an amount is judged against what the person can really
    // reach for a gift, whose destination is Dollars
    // (one_balance/gift_funding.dart): this line, Max below, and the send's
    // refusal.
    final giftReach = widget.sendPick != null && !(isSpot && !_isLong)
        ? ref.watch(giftSpendableProvider)
        : null;
    final availableLineUsd = giftReach ??
        (buysFromInvestments
            ? slipAvailableUsd(
                venueUsd: available,
                otherSpendableUsd: otherSpendableUsd,
                bitcoinUsd: ref.watch(spendingBitcoinLandingUsdProvider))
            : available);

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
    final legNotional = notional;
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
    // A scale order is the legs it sends ([hlScaleLegs]): each one must
    // clear the venue minimum at its OWN price, so the leg furthest down
    // the ladder (the least worth) is the one checked.
    final scaleLegValue = _isScale ? _scaleLowestLegUsd(notional, scaleCount) : null;
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
    // A whole-position close: its resting stops and takes go with it,
    // said before Confirm as the close sheet says it.
    final closeCancels =
        _closeCancelsCount(marketPlan: netPlan, legSize: legSize);
    // A TWAP has its own, larger minimum (HlTwapRules, the venue's $100
    // total), named in its own words.
    final minAmountUsd = _isTwap
        ? HlTwapRules.minAmountUsd(
            referencePx: legPx, szDecimals: market.szDecimals, leverage: lev)
        : netPlan.effect == HlPositionEffect.flip
            ? _orderMinimumUsd(px: legPx, baseSize: netPlan.heldSize)
            : openMinUsd;
    final belowMin = !_reduceOnly &&
        !exitPlan &&
        notional > 0 &&
        (_isScale
            // No legs to judge yet (a missing price or count): the field's
            // own message says what is missing.
            ? scaleLegValue != null &&
                scaleLegValue < HyperliquidConstants.minOrderNotionalUsd - 1e-9
            : _marginUsd < minAmountUsd - 1e-9);
    final sizeZero = _marginUsd > 0 && size <= 0;

    // Per-type price/param validity.
    String? paramError;
    if (_mode == _OrderMode.limit) {
      if (_parse(_priceController) == null) {
        paramError = _strings.slipEnterLimitPrice;
      }
    } else if (_isScale) {
      final s = _parsePx(_startPxController);
      final e = _parsePx(_endPxController);
      if (s == null || e == null) {
        paramError = _strings.slipEnterStartEndPrices;
      } else if (scaleCount == null ||
          scaleCount < kHlScaleMinOrders ||
          scaleCount > kHlScaleMaxOrders) {
        paramError = _strings.hlAdvScaleCountRange(
            kHlScaleMinOrders, kHlScaleMaxOrders);
      } else if (s == e) {
        paramError = _strings.hlAdvScaleSamePrice;
      } else {
        paramError = hlScaleSideIssue(_strings,
            isLong: _isLong, startPx: s, endPx: e, mid: mid);
      }
    } else if (_isTwap) {
      if (!HlTwapRules.minutesValid(twapMinutes)) {
        // Exchange rule: 5 minutes to 7 days.
        paramError = _strings.slipTwapDurationRange;
      }
    }

    // TP/SL sanity (opens only).
    _slPastLiquidation = false;
    if (_isOpening && _attachTpSl) {
      final tp = _parsePx(_tpController);
      final sl = _parsePx(_slController);
      // A stop-loss past where the position would be liquidated never
      // gets to act: said under the fields, a warning, not a block (a 1x
      // isolated long has no liquidation in practice; a 1x short's is near
      // twice its entry).
      if (sl != null && entry > 0 && _marginUsd > 0) {
        final liq = _liquidationEstimate(entry, size).price;
        if (liq != null && liq.isFinite && liq > 0) {
          _slPastLiquidation = _isLong ? sl <= liq : sl >= liq;
        }
      }
      paramError = hlTpSlEntryIssue(_strings,
              isLong: _isLong, entry: entry, takeProfit: tp, stopLoss: sl) ??
          paramError;
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
    // The margin the button stands for: what is typed, or on a hot ticket
    // with nothing typed the minimum order its button places. Measured on
    // that, a ticket whose Investments cannot cover even the minimum reads
    // "Add $X to Investments" from the start, never an order whose tap
    // only opens the deposit. A Ledger ticket keeps its own doors.
    final fundMarginUsd = _marginUsd > 0 || _isLedger
        ? _marginUsd
        : (placesMinimumAmount(minAmountUsd) && !netPlan.opposes
            ? minAmountUsd
            : 0.0);
    if (!_reduceOnly && !exitPlan) {
      if (isSpot) {
        if (_isLong) {
          insufficient = fundMarginUsd > available + 1e-6;
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
            : fundMarginUsd;
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
    // The exposure rule (hl_exposure_rule.dart), Advanced on or off: on a
    // market held above 1x or in cross only a reduction or a close goes.
    // Said above the disabled button, before Face ID. A position still
    // loading is not a refusal here: the tap reads it before anything.
    final heldNow = _heldPositionNow();
    final exposureRefusal =
        heldNow.known ? _exposureRefusal(heldNow, legSize) : null;
    final exposureBlock = exposureRefusal == null
        ? null
        : hlExposureRefusalText(_strings, exposureRefusal);
    // A new position the policy (or the venue) refuses here: the confirm
    // stays on screen, disabled, with the reason above it. Exits never,
    // but a slip in send mode places nothing: its refusal stands whatever
    // the ticket shows.
    // A Ledger ticket asks no open gate; on a stock-linked perp the stock
    // gate is watched here instead, so it too opens shut under the reason
    // (founder, 12 November 2026: shown, not bought).
    final openBlock = (_isExitOrder || exitPlan) && widget.sendPick == null
        ? null
        : _openGateMessage ??
            (_isLedger && isHlStockPerp(market)
                ? ref
                    .watch(runtimeCapabilitiesProvider)
                    .blockReason('hyperliquid.stocks')
                : null);
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
    // Per-order funding (one balance): a hot ticket short of venue cash
    // funds the difference from Dollars on the order's own tap. With
    // nothing typed, the minimum order is what the move is sized for, so
    // the empty ticket's button is still the order. Dollars that cannot
    // cover the move make the button the Dollar deposit door instead.
    final fundShortfall = _isLedger || !canDeposit || depositBlock != null
        ? 0.0
        : _shortfallNow(
            marginUsd: _marginUsd > 0
                ? _marginUsd
                : (placesMinimumAmount(minAmountUsd) ? minAmountUsd : 0));
    _slipShortfallUsd = fundShortfall;
    _emptyMinimumUsd = !_isLedger &&
            _marginUsd <= 0 &&
            placesMinimumAmount(minAmountUsd)
        ? minAmountUsd
        : null;
    _scheduleFundPlan(fundShortfall);
    final fundPlan = fundShortfall > 0 ? _fundPlanFor(fundShortfall) : null;
    final dollarsUsd = _dollarsUsd(watch: true);
    // The rest of Investments (Dollars plus the other venue's cash): the
    // order moves what it needs from there inside the same Confirm, and
    // only when even that is short does the button become "Add".
    final investmentsUsd = fundPlan == null || dollarsUsd + 1e-9 >= fundPlan.fundUsd
        ? dollarsUsd
        : (ref
                .watch(venueCashReachExcludingProvider(OneBalanceVenue.investing))
                .valueOrNull ??
            dollarsUsd);
    final canFundFromDollars = fundPlan != null &&
        openBlock == null &&
        investmentsUsd + 1e-9 >= fundPlan.fundUsd;
    _canFundFromDollars = canFundFromDollars;
    // Max on the whole wallet: the largest order this ticket's own funding
    // check passes (the Investing cash, else a move the rest of
    // Investments and what the spending Bitcoin lands cover, the move's
    // cost counted; founder, 28 October 2026). Past what Investments hold,
    // the tap converts the Bitcoin first, as for a typed order.
    final bitcoinUsd =
        buysFromInvestments ? ref.watch(spendingBitcoinLandingUsdProvider) : 0.0;
    _maxBitcoinUsd = bitcoinUsd;
    double? fundedMaxUsd;
    if (buysFromInvestments &&
        otherSpendableUsd + bitcoinUsd > 0 &&
        canDeposit &&
        depositBlock == null) {
      final reach = math.min(
              otherSpendableUsd,
              ref
                      .watch(venueCashReachExcludingProvider(
                          OneBalanceVenue.investing))
                      .valueOrNull ??
                  dollarsUsd) +
          bitcoinUsd;
      final held = _fundPlan;
      fundedMaxUsd = slipMaxFundableUsd(
        upperUsd: hypercoreMaxOrderUsd(
          availableUsd: shownAvailable + bitcoinUsd,
          leverage: isSpot ? 1 : _leverage,
          slippagePct: _mode == _OrderMode.market ? _slippagePct : 0,
        ),
        fits: (margin) {
          final short = _shortfallNow(marginUsd: margin);
          if (short <= 0) return true;
          // The route's cost is near flat: the last estimate's cost stands
          // for any size, never under the fallback share.
          final plan = _fundPlanFor(short);
          final heldCost = held == null
              ? 0.0
              : math.max(0.0, held.fundUsd - held.arrivingUsd);
          final fund = math.max(plan.fundUsd,
              OrderFundingEngine.targetUsd(shortfallUsd: short) + heldCost);
          return fund * (1 + kSlipMaxMoveHeadroom) <= reach + 1e-9;
        },
      );
    }
    // Nothing is placed in send mode: Max is the gift's reach.
    if (giftReach != null) fundedMaxUsd = giftReach;
    _slipInvestmentsUsd = investmentsUsd;
    var dollarsShort = fundPlan == null
        ? 0.0
        : _dollarsShortUsd(fundPlan.fundUsd, haveUsd: investmentsUsd);
    // The button names exactly what the Bitcoin leg would add for the
    // order (typed, or the minimum an empty ticket opens; the same
    // rounding, the route minimum): the tap converts that and nothing more
    // when the bitcoin covers it, else opens the Investments Receive
    // sheet. Whether it covers is decided at the tap
    // on the wallet's own figures, so a balance or price still loading
    // here never decides where the tap goes. The bet slip does the same.
    final bitcoinAdd = fundPlan == null
        ? 0.0
        : BitcoinLegRules.addUsd(
            fundUsd: fundPlan.fundUsd, investmentsUsd: investmentsUsd);
    _shownAddUsd = dollarsShort <= 0 || _isLedger
        ? null
        : bitcoinAdd > 0
            ? bitcoinAdd
            : dollarsShort;
    if (_shownAddUsd != null) {
      dollarsShort = _shownAddUsd!;
      _warmBitcoinLeg();
    }
    // An earlier order on this market (from a ticket closed meanwhile) is
    // still being looked up after an unclear answer: this one waits, so it
    // is never a duplicate of an order the venue took. Not this ticket's
    // own lookup (its button is busy anyway), never another account's.
    final otherConfirming = !_isPlacing &&
        !_isLedger &&
        hlMarketConfirming(ref.watch(hlConfirmingMarketsProvider),
            account:
                ref.read(hyperliquidTradingProvider.notifier).accountAddress,
            wireCoin: market.wireCoin);
    final gatesOpen = advancedBlock == null &&
        exposureBlock == null &&
        openBlock == null &&
        !_unconfirmedLock &&
        !otherConfirming &&
        (!insufficient || canFundFromDollars) &&
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
    final placesMinimum = placesMinimumAmount(minAmountUsd) &&
        !netPlan.opposes;

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

    // A Bitcoin-funded order for this market on its way (this ticket's,
    // or one started before it was reopened): the steps, one busy button.
    final fundedOrders = _isLedger
        ? const <FundedOrderRecord>[]
        : ref.watch(fundedOrdersProvider);
    // A funded order for this market (from Bitcoin, Dollars, Predictions
    // or any mix): its steps from the approval to the end; a stop keeps
    // them, the failed step marked, the button the order again.
    final funded = _fundedProgress(fundedOrders);
    final fundedSteps = funded == null ? null : _fundingSteps(funded.record);
    final fundedRunning = funded != null && !funded.failed;
    // Another Investing order is still being placed and this one would
    // wait for it (one at a time, [_confirmFunded]): the note above the
    // button says so and the button (or the note) opens the one placing.
    final heldByOther = _heldByOtherOrder(fundedOrders,
        wouldFund: fundShortfall > 0 ||
            _errorText == _strings.slipOtherOrderPlacingNote,
        fundedRunning: fundedRunning,
        openBlocked: openBlock != null);
    final otherPlacing = heldByOther
        ? StandingOrderSlips.placingOn(
            ref.watch(standingOrdersProvider), StandingOrderVenue.investing)
        : null;
    // The plain ticket: while the money moves the order itself takes the
    // amount's place, one big number rolling up from what Investing holds
    // to the order as each leg lands, and the journey the figures' (they,
    // the side and the keypad fold away). A stop brings the ticket back as
    // it was typed, the stop told in one notice, the button the same order
    // again ("Try again · Go Long …").
    final journeyShown = !advanced && fundedRunning;
    // Locked on its accepted order with no money journey to show (its
    // journey done, the order funded from what Investing held, or the
    // ticket reopened from the order's record): the same locked ticket
    // all the same (founder, 11 November 2026, on 2.2.0 (109): never the
    // editable-looking form under an "OK"): the order's figure, the
    // keypad folded, the journey's last line (the order being placed) in
    // its place. Never checked against a minimum again: the order was
    // accepted at it.
    final standingLocked = !advanced &&
        !journeyShown &&
        widget.sendPick == null &&
        !(funded?.failed ?? false) &&
        _standingOnItsWay();
    final lockedShown = journeyShown || standingLocked;
    // Its money already landed (a standing order is always funded): the
    // journey's lines done, the order's own line running.
    final landed = standingLocked && !_isLedger
        ? FundedOrdersNotifier.progressOn(fundedOrders,
            OneBalanceVenue.investing, market.coin, DateTime.now())
        : null;
    final placingSteps = landed != null
        ? _fundingSteps(landed.record)
        : [
            _strings.slipStepPreparingOrder,
            _strings.slipStepOpeningOrder(formatHlUsd(_marginUsd),
                _sideWord(), market.annotatedName ?? market.coin),
          ];
    final placingLine = standingLocked
        ? SlipFundingSteps(
            key: const ValueKey('order-slip-standing-placing'),
            steps: placingSteps,
            active: placingSteps.length - 1,
            from: landed?.record.fromBitcoin == true
                ? MoneyPlace.bitcoin
                : MoneyPlace.dollars,
            to: MoneyPlace.investing,
            haptics: !_left,
          )
        : null;
    final fundedJourney = funded == null
        ? null
        : SlipFundingSteps(
            steps: fundedSteps!,
            active: funded.active,
            slow: funded.record.slow,
            failed: funded.failed,
            graph: funded.record.steps,
            money: formatHlUsd,
            from: funded.record.fromBitcoin
                ? MoneyPlace.bitcoin
                : MoneyPlace.dollars,
            to: MoneyPlace.investing,
            note: funded.failed
                ? fundedStopLine(_strings, funded.record, formatHlUsd)
                : null,
            haptics: !_left,
          );
    // What the order does to a position already held here: adding to it
    // is a small pill; reducing, closing or flipping it stays a line. No
    // gap to the minimum is ever said (owner decision: the whole wallet
    // pays).
    final addsToHeld = !isSpot && netPlan.effect == HlPositionEffect.add;
    final String? amountNote = addsToHeld ? null : _positionNote(netPlan);

    // While the order is in flight the ticket STAYS. It used to be
    // replaced by a centered card, so the moment someone committed money
    // the numbers they had just checked vanished and a box appeared in
    // their place. The Predictions slip does the opposite: the slip holds
    // still, the one button turns into a spinner, and the person waits on
    // the screen they were already reading. This does the same, so the
    // two venues behave alike at the one moment that matters most.
    final form = Padding(
      // The Advanced frame pads its own content (AdvancedTicketFrame).
      padding: EdgeInsets.symmetric(horizontal: advanced ? 0 : 20.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Side switch, the Long/Short twin of the bet slip's Yes/No
          // (user decision). The +$ quick-amount row is gone.
          // While the money moves the side is settled: it folds away with
          // the rest, the order's line says it.
          // In place, a spot token held offers Buy | Sell: the two doors
          // the trade row had (the sheet opens on one of them).
          if (!isSpot ||
              (widget.embedded && !advanced && (heldSize > 0 || !_isLong)))
            FoldAway(
              folded: lockedShown,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [_buildSideToggle(), SlipGap(16.h)],
              ),
            ),
          if (!advanced)
            ArrivalSwitcher(
              state: lockedShown,
              child: lockedShown
                  ? SlipOrderFigure(
                      record: funded?.record,
                      orderUsd: _marginUsd,
                      money: formatHlUsd,
                      orderLine:
                          '${_sideWord()} ${market.coin} · ${_orderTypeName()}',
                    )
                  : _buildAmountField(c, available,
                      shownAvailableUsd: availableLineUsd,
                      balanceKnown: balanceKnown,
                      maxUsdOverride: fundedMaxUsd,
                      keypad: true,
                      // Against a held position only a flip has a minimum.
                      minAmountUsd: _reduceOnly ||
                              _isScale ||
                              (netPlan.opposes &&
                                  netPlan.effect != HlPositionEffect.flip)
                          ? null
                          : minAmountUsd,
                      belowMinimum: belowMin,
                      positionNote: amountNote),
            )
          else
          _buildAmountField(c, available,
              shownAvailableUsd: availableLineUsd,
              balanceKnown: balanceKnown,
              maxUsdOverride: fundedMaxUsd,
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
          if (!advanced && addsToHeld && !lockedShown) ...[
            SlipGap(10.h),
            SlipPositionPill(
              long: netPlan.heldSide == 'long',
              text: _strings.slipAddsToYourPosition(netPlan.heldSide),
            ),
          ],
          // Advanced is the pill beside Max; when it is not the default,
          // a chip under the amount says what it is set to.
          if (!advanced && !lockedShown && _hasAdvancedConfiguration) ...[
            SlipGap(10.h),
            SlipAdvancedChip(text: _advancedSummary(), onTap: _openAdvanced),
          ],
          if (advanced) SizedBox(height: 20.h),
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
            // The figures give their room to the money's journey while it
            // runs.
            FoldAway(
              folded: lockedShown,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SlipGap(20.h),
                  _buildCompactSummary(
                    c,
                    notional,
                    transferFromPerp,
                    hasFunds: available > 0 || _reduceOnly,
                    size: size,
                  ),
                ],
              ),
            ),
            SlipJourney(steps: journeyShown ? fundedJourney : placingLine),
          ],

          if (oiCapped) ...[
            SizedBox(height: 10.h),
            Text(
              context.l10n.hlSlipOiCapWarning(market.coin),
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
                  : _isTwap
                      ? context.l10n.hlAdvTwapMinimum(formatHlUsd(minAmountUsd))
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
          // A funded order's stop: on the Advanced page it is told in its
          // steps under the button, never twice; the plain ticket comes
          // back as it was typed with the same words in this one notice.
          if (!advanced && funded != null && funded.failed) ...[
            SlipGap(10.h),
            HlTradeErrorNotice(
              key: const ValueKey('order-slip-funded-stop'),
              message: fundedStopLine(_strings, funded.record, formatHlUsd),
            ),
          ] else if (_errorText != null &&
              _errorText != _strings.slipOtherOrderPlacingNote &&
              !(funded?.failed ?? false)) ...[
            SlipGap(10.h),
            HlTradeErrorNotice(message: _errorText!, error: _errorCause),
          ],
          SlipGap(16.h),
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
    // The order went out without an answer and is being looked up on the
    // account: the busy button says so.
    final sentCloid = _sentCloid;
    final confirmingWithExchange = _isPlacing &&
        sentCloid != null &&
        ref.watch(hlConfirmingOrdersProvider
            .select((cloids) => cloids.contains(sentCloid)));
    // The busy button's words while its money moves (or it just placed).
    final bitcoinStep = fundedRunning
        ? fundedSteps![funded.active.clamp(0, fundedSteps.length - 1)]
        : null;
    if (bitcoinStep != null) {
      primaryKind = 'trade';
      primaryLabel = bitcoinStep;
      primaryAction = null;
      primaryNeutral = false;
    } else if (_unconfirmedLock && !_isPlacing && !_completed) {
      // The order went out and nobody can say whether the venue took it:
      // this ticket never sends it again. The notice says to check; the
      // one button opens where it would be (a resting order in the
      // orders, a filled one in what is held), as the receipts' own.
      final resting = _mode != _OrderMode.market;
      primaryKind = 'view';
      primaryLabel = resting
          ? context.l10n.investingViewOrders
          : context.l10n.investingViewPositions;
      primaryAction = () => _viewAfterUnconfirmed(resting: resting);
      primaryNeutral = true;
    } else if ((openBlock != null &&
            _openGateRegion &&
            !_isPlacing &&
            !_preparing) ||
        ledgerRegionBlocked) {
      // A region refusal: the one button asks again, never a dead one.
      primaryKind = 'check';
      primaryLabel = context.l10n.checkConnection;
      primaryAction =
          _checkingConnection || _ledgerBusy ? null : _checkConnection;
      primaryNeutral = true;
    } else if (ledgerBlocked || _ledgerPending) {
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
    } else if (_fundingStage != null && _isPlacing) {
      // The order's own money is on its way from Dollars: the trade
      // button, busy, saying so. Its own deposit row on its way must not
      // read as a second deposit.
      primaryKind = 'trade';
      primaryLabel = _positionCtaLabel(netPlan) ?? _ctaLabel();
      primaryAction = null;
      primaryNeutral = false;
    } else if (incoming) {
      primaryKind = 'incoming';
      primaryLabel = context.l10n
          .slipDepositIncoming(formatHlUsd(funding.incomingUsd));
      primaryAction = null;
      primaryNeutral = true;
    } else if (canDeposit && !canFundFromDollars) {
      // Insufficient balance for this trade and Dollars cannot fund it:
      // the hot ticket's button is the Dollar deposit door for what is
      // missing ("Add $X to Investments"); a Ledger ticket keeps the Move
      // sheet locked to its own Investing account with the margin
      // prefilled.
      primaryKind = 'deposit';
      // With no amount to name yet (nothing typed on a limit ticket, or a
      // shut door), the hot ticket still says where the money goes.
      // With an amount typed the button names only the order ("Short
      // $12.00"), never the top-up it needs (owner decision: the tap
      // draws on the whole wallet). An empty ticket that places the
      // minimum says so ("Long minimum on ETH"); the tap is unchanged.
      primaryLabel = _isLedger
          ? context.l10n.depositToTrade
          : dollarsShort > 0
              ? _marginUsd > 0
                  ? _positionCtaLabel(netPlan, amountUsd: _marginUsd) ??
                      _ctaLabel(amountUsd: _marginUsd)
                  : placesMinimum
                      ? _emptyCtaLabel(netPlan)
                      : context.l10n
                          .slipAddToInvestments(formatHlUsd(dollarsShort))
              : context.l10n.addMoneyToInvestments;
      // Funding a position that cannot be opened here would only strand
      // the money, so the door shuts with the open gate too.
      primaryAction =
          depositBlock == null && openBlock == null && !_depositDoorBusy
              ? _openDepositDoor
              : null;
      primaryNeutral = true;
    } else if (heldByOther) {
      // Another order is still being placed: the button stays this order,
      // and a tap opens the one placing (its locked ticket) instead.
      final placing = otherPlacing;
      primaryKind = 'trade';
      primaryLabel = placesMinimum
          ? _emptyCtaLabel(netPlan)
          : _positionCtaLabel(netPlan) ?? _ctaLabel();
      primaryAction = placing == null
          ? null
          : () => StandingOrderSlips.openInstead(context, placing);
      primaryNeutral = false;
    } else if (belowMin &&
        !_isScale &&
        // A TWAP under its own (larger) minimum stays the order, disabled,
        // its minimum said inline: never a one-tap jump to $100.
        !_isTwap &&
        _marginUsd > 0 &&
        minAmountUsd > 0) {
      // An amount under the venue minimum: the button names the minimum
      // the available line shows, and a tap writes it and places it, as
      // the order at a typed minimum would. Against a held position (a
      // flip) the tap only writes it, as the empty ticket's button never
      // places one either: the button then names the flip. It stays the
      // trade button (same face, no cross-fade); only what it says and
      // does changes until the amount clears the floor.
      primaryKind = 'trade';
      primaryLabel =
          context.l10n.amountMinimumInline(formatHlUsd(minAmountUsd));
      // Shut with the open gate (any refusal, not only a region one), as
      // the order button is: the minimum would only be refused again.
      primaryAction = _isPlacing ||
              _preparing ||
              _ledgerBusy ||
              _unconfirmedLock ||
              openBlock != null
          ? null
              : netPlan.opposes
                  ? () => _fillAmountChip(minAmountUsd, 'min')
                  : () => _placeFilledMinimum(minAmountUsd);
      primaryNeutral = false;
    } else if (placesMinimum) {
      primaryKind = 'trade';
      // Nothing typed: the order and that it is the minimum ("Long
      // minimum on ETH"), as Predictions' "Place minimum on Yes"; a tap
      // places the minimum.
      primaryLabel = _emptyCtaLabel(netPlan);
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
          : !_placeMinimumTradeOnly &&
                  (primaryKind == 'deposit' || primaryKind == 'prepare')
              ? primaryAction
              : null;
      _placeMinimumTradeOnly = false;
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
    // The standing order this ticket accepted, while it is on its way: the
    // bar's busy button is its "OK" (leaves the ticket, never cancels).
    final standingOk = widget.sendPick == null &&
        !(funded?.failed ?? false) &&
        _standingOnItsWay();
    // One note per distinct reason: a region block that shuts both the
    // trade and the deposit says so once.
    final actionNotes = <Widget>[
          if (openBlock != null) CapabilityBlockNote(openBlock),
          if (advancedBlock != null &&
              !primaryNeutral &&
              advancedBlock != openBlock)
            CapabilityBlockNote(advancedBlock),
          if (exposureBlock != null && openBlock == null)
            CapabilityBlockNote(exposureBlock),
          // A shut open already explains the disabled deposit door.
          if (depositBlock != null && openBlock == null && !incoming)
            CapabilityBlockNote(depositBlock),
          if (!incoming && (funding?.failed ?? false))
            const SlipDepositFailedNote(),
          if (otherConfirming && primaryKind == 'trade')
            CapabilityBlockNote(_strings.slipOtherOrderPlacingNote),
          if (heldByOther && primaryKind == 'trade')
            GestureDetector(
              key: const ValueKey('order-slip-other-placing'),
              behavior: HitTestBehavior.opaque,
              onTap: primaryAction,
              child: CapabilityBlockNote(_strings.slipOtherOrderPlacingNote),
            ),
          if (closeCancels != null)
            Padding(
              padding: EdgeInsets.only(bottom: 8.h),
              child: Text(
                context.l10n.hlProtectCloseCancelsOrders(closeCancels),
                key: const ValueKey('order-slip-leftovers-note'),
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textSecondary, fontSize: 13.sp),
              ),
            ),
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
    ];
    // On the Advanced page the button floats over the scrolling form
    // (AdvancedTicketFrame): a note over it, and the steps growing in
    // above it, sit on the page's own ground so the form scrolling under
    // them never shows through. The ground fades in above them; no bar.
    Widget onGround(Widget child) => advanced
        ? ColoredBox(
            color: base.background,
            child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: child))
        : child;
    final grounded =
        advanced && (actionNotes.isNotEmpty || fundedJourney != null);
    final action = Padding(
      padding: EdgeInsets.fromLTRB(
        advanced ? 0 : 20.w,
        advanced ? 0 : 8.h,
        advanced ? 0 : 20.w,
        advanced ? 16.h : math.max(16.h, MediaQuery.of(context).padding.bottom),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (grounded)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    base.background.withValues(alpha: 0),
                    base.background,
                  ],
                ),
              ),
              child: SizedBox(height: 28.h, width: double.infinity),
            ),
          if (actionNotes.isNotEmpty)
            onGround(Column(
                mainAxisSize: MainAxisSize.min, children: actionNotes)),
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
          // The button fades out and the new one in when it changes what
          // it is (the deposit door giving way to the trade once a deposit
          // lands), never as its amount changes, and never two labels at
          // once.
          // The placement's band: pulled while the order (and its money)
          // goes, snapped back once placed, let go softly when it is not.
          _orderBand(
            funded: funded,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Above the bar's room, never under the floating bar (founder,
          // 8 November 2026: it clipped): on the Advanced page the steps
          // grow in here; the plain ticket shows them at the top, where its
          // figures were. No "Add more" under a deposit on its way here
          // (founder, 11 November 2026: "don't have the add more button in
          // the sheet of investing, makes no sense there").
          StepsReveal(
            child: advanced && fundedJourney != null
                ? onGround(fundedJourney)
                : null,
          ),
          ArrivalSwitcher(
            state: primaryKind,
            alignment: Alignment.bottomCenter,
            sequential: true,
            animateSize: false,
            child: DecoratedBox(
              // On the tinted sheet the white button is only a shade away
              // from the veils around it, so it gets a soft drop shadow to
              // lift clear of the fill. Dropped while the action is
              // disabled, where the button fades to 0.35 and a full-weight
              // shadow would read as a rendering fault.
              decoration: BoxDecoration(
                borderRadius: AppRadius.buttonBorder,
                // In place the bar's own button carries its own lift.
                boxShadow: tinted &&
                        primaryAction != null &&
                        !(widget.embedded && !advanced)
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : null,
              ),
              // The steps under the button name the step it is on: the
              // busy button only spins, and a screen reader hears it.
              child: Semantics(
                label: bitcoinStep,
                liveRegion: bitcoinStep != null,
                // THE BAR IS THE BUTTON (kute_shell_bar.dart): the ticket
                // declares its primary action and draws no button of its
                // own. In send mode the send is the one primary, never
                // an order (screens/share/slip_share.dart).
                child: _barOrInPlace(
                  advanced: advanced,
                  theme: appTheme,
                  barContext: widget.sendPick != null
                      ? _sendBarContext(widget.sendPick!,
                          minUsd: minAmountUsd)
                      : standingOk
                      // The busy button as it is (Sal working on it),
                      // saying "OK" and taking the tap while the order is
                      // on its way: it closes the ticket exactly as
                      // leaving does, the order goes on (founder, 10
                      // November 2026, on 2.2.0 (99): "instead of cancel,
                      // we should say ok"). No Cancel anywhere (founder,
                      // 11 November 2026).
                      ? KuteBarContext.primary(
                          label: context.l10n.ok,
                          // In place the page stays: leaving the ticket
                          // is a fresh one in its place.
                          onPrimary: widget.embedded && !advanced
                              ? _leaveInPlace
                              : () => Navigator.of(context).maybePop(),
                          busy: true,
                          tapWhileBusy: true,
                          busyLabel: context.l10n.ok,
                          category: SearchCategory.perpetuals,
                          source: 'order_slip',
                          // Never waits on input.
                          disabledLabel: null,
                        )
                      : KuteBarContext.primary(
                    label: funded != null &&
                        funded.failed &&
                        !belowMin &&
                        (primaryKind == 'trade' || primaryKind == 'deposit')
                    ? '${_strings.walletsTryAgain} · $primaryLabel'
                    : primaryLabel,
                    onPrimary: primaryAction,
                    enabled: primaryAction != null,
                    busy: _ledgerBusy ||
                    _checkingConnection ||
                    bitcoinStep != null ||
                    _isPlacing ||
                    _preparing ||
                    _depositCalculating ||
                    primaryKind == 'loading',
                    busyLabel: primaryKind == 'loading'
                    ? context.l10n.loadingAccount
                    : primaryKind == 'check'
                        ? context.l10n.checkConnection
                        : _depositCalculating && primaryKind == 'deposit'
                        ? context.l10n.feeUiCalculating
                        : bitcoinStep != null
                            ? null
                            : confirmingWithExchange
                            ? context.l10n.investingConfirmingWithExchange
                            : (_isPlacing &&
                                    _fundingStage != null &&
                                    _fundingStage != OrderFundingStage.order
                                // Phrased around the order, never as money
                                // moving into Investments (it is there).
                                ? context.l10n.slipStepPreparingOrder
                                // After the tap the button says what is
                                // happening, never the action again
                                // (founder, 12 November 2026: "should be,
                                // after I press, processing or something").
                                : _isPlacing
                                ? context.l10n.betPlacingOrder
                                : _preparing
                                ? context.l10n.activityProcessingEllipsis
                                : null),
                    category: SearchCategory.perpetuals,
                    source: 'order_slip',
                    disabledLabel: primaryKind == 'trade' && _marginUsd <= 0 && !placesMinimum ? context.l10n.barNeedAmount : null,
                  ),
                ),
              ),
            ),
          ),
            ]),
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
        _preparing ||
        _followingStanding();
    if (!advanced) _keypadTakesKeys = !ledgerLocked && !lockedShown;
    if (advanced) {
      // The Advanced page: the form scrolls under its one primary, which
      // floats at the foot (no bar, only the page's own ground fading in
      // behind it; AdvancedTicketFrame). The room it takes is measured, so
      // the last card always scrolls clear of it.
      return PopScope(
        // Locked while it places; once the accept made a standing order
        // of it, the person may step back (the order goes on). Back from
        // this page lands on the ticket, still open and still following
        // the order to its receipt: leaving is the ticket's own pop
        // ([_onLeave]), never this page's.
        canPop: _standingAccepted || !_isPlacing,
        child: KeyboardDismissOnTap(
          child: AdvancedTicketFrame(
            title: context.l10n.slipAdvancedTitle(_sideWord(), market.coin),
            onBack: () => Navigator.of(context).maybePop(),
            scrollKey: const ValueKey('hl-advanced-form-scroll'),
            primaryHeight: _advancedPrimaryHeight,
            primary: HlReportSize(
              onSize: (size) {
                if (!mounted ||
                    (size.height - _advancedPrimaryHeight).abs() < 0.5) {
                  return;
                }
                _advancedPrimaryHeight = size.height;
                _draftChanges.value++;
              },
              child: action,
            ),
            children: [
              // The page's switches as Settings draws them.
              hlAdvancedSwitchTheme(
                context,
                child: IgnorePointer(ignoring: ledgerLocked, child: form),
              ),
            ],
          ),
        ),
      );
    }
    final ticket = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(c),
              Flexible(
                child: SlipFormBody(
                  expandForMessage:
                      _errorText != null || (funded?.failed ?? false),
                  form: IgnorePointer(ignoring: ledgerLocked, child: form),
                  // While a funded order's steps run under the button the
                  // amount cannot change: the keypad folds away and the
                  // steps take its room. A stop brings it back.
                  // The web's column types the amount in its field: no
                  // number pad.
                  input: widget.typedAmount
                      ? const SizedBox.shrink()
                      : FoldAway(
                    folded: lockedShown,
                    child: Padding(
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
                  ),
                ),
              ),
              // In the side panel (EXPANDED), what the person holds on
              // this market, over the button (kute_side_panel.dart).
              if (widget.embedded)
                SlipPanelFooterSlot(horizontal: 20.w),
              action,
            ],
          );
    return PopScope(
      // The ticket's own lock is the tap-outside's (see the file header);
      // this only hears it go.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _onLeave();
      },
      child: KeyboardDismissOnTap(
      child: Theme(
        // Shared widgets inside the sheet read `context.colors`; handing
        // them the tinted palette keeps them legible without forking them.
        data: tintedTheme,
        // A side panel on EXPANDED (the position page's editor opens the
        // ticket there) wears the side's colour to its foot, the primary
        // on it (kute_dialog.dart).
        child: KuteDialogSurfaceMark(
        color: widget.embedded ? null : sideColor,
        child: Container(
          padding: widget.embedded
              ? EdgeInsets.zero
              : EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          // Flipping side re-paints the sheet rather than snapping.
          child: AnimatedContainer(
            duration: MediaQuery.of(context).disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            // In place the ticket IS the side panel: its colour the
            // panel's surface from the window's top to its bottom,
            // rounded only where it meets the page (kute_side_panel.dart).
            decoration: widget.typedAmount
                ? BoxDecoration(
                    color: sideColor,
                    borderRadius: BorderRadius.circular(24),
                  )
                : widget.embedded
                ? kuteSidePanelDecoration(sideColor)
                : BoxDecoration(
                    color: sideColor,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(24.r)),
                    border: Border(top: BorderSide(color: c.border)),
                  ),
            // Top inset only, so the action block below is the single
            // place that decides the gap under the button. SafeArea
            // zeroes the bottom padding it consumes for everything
            // inside it, so a PlatformSafeArea here left the action
            // block reading zero on Android and the real inset on iOS,
            // and the one expression down there could not mean the same
            // thing on both.
            // In place the pane bounds it.
            // In place it is a full-height card: the keypad takes the
            // pane's spare height, the button at its foot.
            child: widget.typedAmount
                // The column's card: its content's height, at most a
                // tall window's worth, the column scrolling past it.
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 760),
                      child: SlipFit(child: ticket),
                    ),
                  )
                : widget.embedded
                ? Padding(
                    padding: kuteSidePanelInsets,
                    child: SlipFit(fill: true, child: ticket))
                : SafeArea(
                    bottom: false,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: (MediaQuery.sizeOf(context).height * 0.92 -
                                MediaQuery.viewInsetsOf(context).bottom)
                            .clamp(0.0, double.infinity),
                      ),
                      child: SlipFit(child: ticket),
                    ),
                  ),
          ),
        ),
        ),
      ),
      ),
    );
  }

  /// The ticket's primary button: the floating bar's (declared through
  /// its context, the room for it left under the ticket), or, in place
  /// ([HlOrderSlipSheet.embedded], the simple ticket), the bar's own
  /// button drawn here at the ticket's foot, in the app's palette (never
  /// the tinted one), with the round Sal button beside it as the bar has
  /// it.
  Widget _barOrInPlace({
    required bool advanced,
    required ThemeData theme,
    required KuteBarContext barContext,
  }) {
    if (!widget.embedded || advanced) {
      return KuteBarContextScope(
        barContext: barContext,
        child: SizedBox(height: kuteBarScrollClearance.h),
      );
    }
    final share = widget.embeddedShare;
    return Theme(
      data: theme,
      child: Padding(
        padding: EdgeInsets.only(top: 4.h),
        child: Row(
          key: const ValueKey('order-slip-in-place-primary'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: KuteBarPrimaryButton(
                barContext: barContext,
                // No Sal sheet from the ticket itself.
                onAsk: () {},
              ),
            ),
            KuteBarShareSlot(
              share: share,
              onTap: (_) {
                final direct = share?.brag ??
                    share?.send ??
                    share?.open ??
                    share?.barContext?.directAction;
                if (direct == null) return;
                HapticFeedback.lightImpact();
                direct();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// In place, the "OK" of an order on its way: the ticket is left as the
  /// sheet's is (Sal's placing toast takes over) and a fresh one opens.
  void _leaveInPlace() {
    _onLeave();
    widget.onEmbeddedDone?.call();
  }

  /// The simple ticket's keypad takes keys now (not locked, not folded):
  /// what the last build drew, for [_onHardwareKey].
  bool _keypadTakesKeys = false;

  /// In place, a hardware keyboard types the amount as the keypad does:
  /// digits, the dot (or a comma), backspace. Only while this page is on
  /// top, the simple ticket open for typing, and no text field has focus.
  bool _onHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    if (!mounted || _advancedRouteOpen) return false;
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    // A focused text field keeps its own keys. The focus node's context is
    // the field's inner Focus, never the EditableText itself, so the field
    // is found above it (as the shell bar and the keypad look for it).
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused != null &&
        (focused.widget is EditableText ||
            focused.findAncestorWidgetOfExactType<EditableText>() != null)) {
      return false;
    }
    // The keypad's own lock, as the last build drew it.
    if (!_keypadTakesKeys) return false;
    final key = event.logicalKey;
    final value = _amountController.text;
    if (key == LogicalKeyboardKey.backspace) {
      // The editor beside the panel removes its selected drawing.
      if (KuteDeskKeys.editorHoldsSelection) return false;
      _onKeypadAmount(amountBackspace(value));
      return true;
    }
    final ch = event.character;
    if (ch == null || ch.length != 1) return false;
    if (RegExp(r'[0-9]').hasMatch(ch)) {
      _onKeypadAmount(amountAppendKey(value, ch, maxDecimals: 2));
      return true;
    }
    if (ch == '.' || ch == ',') {
      _onKeypadAmount(amountAppendKey(value, '.', maxDecimals: 2));
      return true;
    }
    return false;
  }

  /// The web column's amount ([HlOrderSlipSheet.typedAmount]): the
  /// ticket's own controller in a real field, digits and one dot, two
  /// decimals, the figure's own size and weight, so it reads as the
  /// ticket's figure and takes a laptop's keyboard first. Locked as the
  /// number pad is (while the order goes out).
  final FocusNode _typedFocus = FocusNode(debugLabel: 'hl-ticket-amount');

  Widget _typedAmountField(AppColorsExtension c) {
    final figure = TextStyle(
      color: c.textPrimary,
      fontSize: 44.sp,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.2,
      height: 1.1,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(r'$',
            style: figure.copyWith(
                color: _amountController.text.isEmpty
                    ? c.textTertiary
                    : c.textPrimary)),
        Expanded(child: _typedAmountInput(c, figure)),
      ],
    );
  }

  Widget _typedAmountInput(AppColorsExtension c, TextStyle figure) =>
      TextField(
        key: const ValueKey('order-slip-typed-amount'),
        controller: _amountController,
        focusNode: _typedFocus,
        enabled: _keypadTakesKeys,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.done,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          TextInputFormatter.withFunction((old, next) {
            final text = next.text.replaceAll(',', '.');
            if (!RegExp(r'^\d*\.?\d{0,2}$').hasMatch(text)) return old;
            return next.copyWith(text: text);
          }),
        ],
        onChanged: (_) => _updateDraft(() {}),
        cursorColor: c.textPrimary,
        style: figure,
        decoration: InputDecoration(
          isDense: true,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          hintText: '0',
          hintStyle: figure.copyWith(color: c.textTertiary),
        ),
      );

  // ── Section builders ────────────────────────────────────────────────

  bool get _hasAdvancedConfiguration =>
      _mode != _OrderMode.market ||
      _reduceOnly ||
      _attachTpSl ||
      _attachTrailing ||
      _postOnly ||
      _slippagePct != 1.0;

  /// The order's type in words ("Market order", "Limit order", "TWAP").
  String _orderTypeName() => switch (_mode) {
        _OrderMode.market => _strings.slipMarketOrder,
        _OrderMode.limit => _strings.slipLimitOrder,
        _OrderMode.pro => _proTypeLabel(),
      };

  String _advancedSummary() {
    return [
      _orderTypeName(),
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
    final levels = mid > 0 ? _priceMapLevels(mid) : const <AdvancedPriceLevel>[];
    final protect = (!_isLedger && _isOpening) || _trailingAvailable;
    // Ledger supports the reviewed market flow and a separate native
    // trailing-stop ticket. Other hot-only order controls stay hidden.
    return [
      if (!_isLedger) ...[
        _advancedHeading(c, l.investingOrderType),
        _buildOrderTypeTiles(c),
        // The chosen type's own numbers, each a stepper.
        ..._buildPriceInputs(c, mid),
      ],

      // Where every level sits against the price now: the limit, the
      // ladder, the take profit and the stop, the trailing stop's start.
      if (levels.isNotEmpty) ...[
        SizedBox(height: 16.h),
        AdvancedPriceMap(
          now: mid,
          entry: entry > 0 ? entry : mid,
          levels: levels,
          // Room for every pill (a ladder of legs stands taller).
          height: math.max(132.0, 36.0 + 24.0 * (levels.length + 1)),
          nowLabel: l.betNow,
          formatPrice: (p) => formatHlPrice(p, decimalCap: market.pxDecimalCap),
        ),
      ],

      // The two attach options together, under the one question they
      // answer, so protecting the position is not buried among the
      // switches most tickets never touch.
      if (protect) ...[
        SizedBox(height: 24.h),
        _advancedHeading(c, l.slipProtectPosition),
        // TP/SL attach (opening orders only).
        if (!_isLedger && _isOpening) _buildTpSlAttach(c, entry > 0 ? entry : mid),
        // Trailing stop attach: set here, placed by the one button once
        // the opening market order fills (perps only).
        if (_trailingAvailable) ...[
          if (!_isLedger && _isOpening) SizedBox(height: 10.h),
          _buildTrailingAttach(c, mid),
        ],
      ],

      // Time in force, post-only, reduce-only and slippage: closed by
      // default, opened by the few who know what they are looking for.
      if (!_isLedger || _mode == _OrderMode.market) ...[
        SizedBox(height: 24.h),
        _buildExpertSettings(c),
      ],

      SizedBox(height: 24.h),
      _advancedHeading(c, l.details),
      _buildAdvancedSummary(c, mid, notional, size, scaleCount,
          transferFromPerp,
          hasFunds: hasFunds, entry: entry),
    ];
  }

  /// A group's quiet heading on the Advanced page.
  Widget _advancedHeading(AppColorsExtension c, String text) => Padding(
        padding: EdgeInsets.only(bottom: 10.h),
        child: Text(
          text,
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 17.sp,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      );

  /// The order types as tiles: Market, Limit, and on a perp Scale and
  /// TWAP (the venue documents neither for spot). The same handlers the
  /// segmented control used, so every default, prefill, analytics event
  /// and revalidation is unchanged.
  Widget _buildOrderTypeTiles(AppColorsExtension c) {
    final l = context.l10n;
    final options = <(AdvancedTypeOption, VoidCallback)>[
      (
        AdvancedTypeOption(
            label: l.ledgerOrderMarketPrice,
            glyph: AdvancedTypeGlyph.market,
            key: const ValueKey('hl-adv-type-market')),
        () => _onSelectMode(_OrderMode.market),
      ),
      (
        AdvancedTypeOption(
            label: l.betOrderTypeLimit,
            glyph: AdvancedTypeGlyph.limit,
            key: const ValueKey('hl-adv-type-limit')),
        () => _onSelectMode(_OrderMode.limit),
      ),
      if (!isSpot) ...[
        (
          AdvancedTypeOption(
              label: _strings.slipScale,
              glyph: AdvancedTypeGlyph.scale,
              key: const ValueKey('hl-adv-type-scale')),
          () => _selectProType(_ProType.scale),
        ),
        (
          const AdvancedTypeOption(
              label: 'TWAP',
              glyph: AdvancedTypeGlyph.twap,
              key: ValueKey('hl-adv-type-twap')),
          () => _selectProType(_ProType.twap),
        ),
      ],
    ];
    final selected = switch (_mode) {
      _OrderMode.market => 0,
      _OrderMode.limit => 1,
      _OrderMode.pro => _proType == _ProType.scale ? 2 : 3,
    };
    return AdvancedTypeTiles(
      options: [for (final o in options) o.$1],
      selected: selected,
      onSelected: (i) => options[i].$2(),
      // Selection is the app's neutral pill, never the side's colour: the
      // colour is the shared tiles' API only and no longer paints.
      sideColor: c.textPrimary,
      // A small phone takes the shorter tiles.
      tileHeight: MediaQuery.sizeOf(context).height < 700 ? 68 : 76,
      // What the chosen type does, in one sentence, right where it is
      // chosen rather than at the bottom of the page.
      explanation: _orderExplanation(),
    );
  }

  /// Scale or TWAP picked: Pro mode through the same two handlers the
  /// type sheet used.
  void _selectProType(_ProType t) {
    if (_mode == _OrderMode.pro && _proType == t) return;
    if (_mode != _OrderMode.pro) _onSelectMode(_OrderMode.pro);
    _onSelectProType(t);
  }

  // ── Steppers ─────────────────────────────────────────────────────────

  double _priceTick(double px) =>
      hlPriceTick(px, szDecimals: market.szDecimals, isSpot: isSpot);

  /// Writes [px] into a price [field] as the wire sends it.
  void _setPrice(_NumField field, double px) {
    if (!(px > 0) || !px.isFinite) return;
    final String text;
    try {
      text = roundPrice(px, szDecimals: market.szDecimals, isSpot: isSpot);
    } catch (_) {
      return;
    }
    _controllerFor(field).text = text;
    _updateDraft(() {});
  }

  /// One tick up or down from the typed price (or from [base] when the
  /// field is empty).
  void _stepPrice(_NumField field, int dir, double base) {
    final cur = _parse(_controllerFor(field)) ?? base;
    if (!(cur > 0)) return;
    // Stepping down from a round figure takes the finer step under it.
    final tick = _priceTick(dir < 0 ? cur * (1 - 1e-9) : cur);
    _setPrice(field, cur + dir * tick);
  }

  /// A whole-number field stepped by [step], never under [min].
  void _stepInt(_NumField field, int dir, {int step = 1, int min = 1}) {
    final controller = _controllerFor(field);
    final cur = _parseInt(controller) ?? min;
    final next = math.max(min, cur + dir * step);
    controller.text = '$next';
    _updateDraft(() {});
  }

  /// The preset whose price the field holds now, if any.
  int? _presetIndex(_NumField field, List<double> prices) {
    final now = _parsePx(_controllerFor(field));
    if (now == null) return null;
    for (var i = 0; i < prices.length; i++) {
      if (_wirePx(prices[i]) == now) return i;
    }
    return null;
  }

  /// "−2%" / "+5%" for a chip.
  static String _pctChip(double pct) =>
      '${pct < 0 ? '−' : '+'}${_trimZeros(pct.abs().toStringAsFixed(1))}%';

  /// Distance presets from [from] (signed percents) as chips under a
  /// price stepper: a chip only writes the field, the rules judge it.
  Widget _priceChips(_NumField field, double from, List<double> pcts) {
    final prices = [for (final p in pcts) from * (1 + p / 100)];
    return Padding(
      padding: EdgeInsets.only(top: 8.h),
      child: AdvancedChips(
        key: ValueKey('hl-adv-chips-${field.name}'),
        labels: [for (final p in pcts) _pctChip(p)],
        selected: _presetIndex(field, prices),
        onSelected: (i) => _setPrice(field, prices[i]),
      ),
    );
  }

  /// One number on the Advanced page as a stepper ([HlStepField]): its
  /// own field, focus node (the wire rounding on leaving) and formatter.
  Widget _stepField(
    AppColorsExtension c,
    _NumField field,
    String label, {
    required ValueChanged<int> onStep,
    bool price = false,
    String suffix = '',
    String? trailing,
    VoidCallback? onTrailing,
  }) =>
      HlStepField(
        key: ValueKey('hl-adv-stepper-${field.name}'),
        fieldKey: ValueKey('hl-adv-field-${field.name}'),
        controller: _controllerFor(field),
        focusNode: _focusNodeFor(field),
        label: label,
        prefix: price ? r'$' : '',
        suffix: suffix,
        formatPrice: price
            ? (v) => formatHlPrice(v, decimalCap: market.pxDecimalCap)
            : null,
        inputFormatters: [
          DecimalInputFormatter(fractionDigits: _decimalsFor(field))
        ],
        decimal: _decimalsFor(field) > 0,
        onChanged: (_) => _updateDraft(() {}),
        onStep: onStep,
        trailing: trailing,
        onTrailing: onTrailing,
      );

  /// A price stepper with the snap to the market and, under it, the
  /// distance presets on [pcts] from the market.
  List<Widget> _priceStepper(AppColorsExtension c, _NumField field,
      String label, double mid, List<double> pcts) {
    return [
      _stepField(
        c,
        field,
        label,
        price: true,
        onStep: (dir) => _stepPrice(field, dir, mid),
        trailing: mid > 0
            ? '${context.l10n.ledgerOrderMarketPrice} '
                '${formatHlPrice(mid, decimalCap: market.pxDecimalCap)}'
            : null,
        onTrailing: () => _setPrice(field, mid),
      ),
      if (mid > 0) _priceChips(field, mid, pcts),
    ];
  }

  /// The resting side's presets: under the market for a buy, over it for
  /// a sell.
  List<double> _restingPcts(List<double> magnitudes) =>
      [for (final m in magnitudes) _isLong ? -m : m];

  List<Widget> _buildPriceInputs(AppColorsExtension c, double mid) {
    final l = context.l10n;
    switch (_mode) {
      case _OrderMode.market:
        return const [];
      case _OrderMode.limit:
        return [
          SizedBox(height: 12.h),
          ..._priceStepper(c, _NumField.limitPrice, l.betLimitPrice, mid,
              _restingPcts(const [1, 2, 5])),
        ];
      case _OrderMode.pro:
        switch (_proType) {
          case _ProType.scale:
            return [
              SizedBox(height: 12.h),
              ..._priceStepper(c, _NumField.scaleStart, l.slipStartPrice,
                  mid, _restingPcts(const [1, 2, 5])),
              SizedBox(height: 10.h),
              ..._priceStepper(c, _NumField.scaleEnd, l.slipEndPrice, mid,
                  _restingPcts(const [5, 10, 20])),
              SizedBox(height: 10.h),
              _stepField(c, _NumField.scaleCount, l.slipNumberOfOrders,
                  onStep: (dir) => _stepInt(_NumField.scaleCount, dir)),
            ];
          case _ProType.twap:
            return [
              SizedBox(height: 12.h),
              _stepField(c, _NumField.twapMinutes, l.slipTwapMinutes,
                  onStep: (dir) => _stepInt(_NumField.twapMinutes, dir,
                      step: 5, min: 5)),
              SizedBox(height: 10.h),
              _switchRow(
                c,
                l.slipRandomizeTiming,
                _randomizeTwap,
                (v) {
                  _settingChanged('twap_randomized', v);
                  _updateDraft(() => _randomizeTwap = v);
                },
                card: true,
              ),
            ];
        }
    }
  }

  /// The levels the price map draws for the ticket as it stands, each at
  /// the price the order would carry. Distance in % only: the page works
  /// out no profit or loss at a level.
  List<AdvancedPriceLevel> _priceMapLevels(double mid) {
    final l = _strings;
    final levels = <AdvancedPriceLevel>[];
    if (_mode == _OrderMode.limit) {
      final p = _parsePx(_priceController);
      if (p != null) {
        levels.add(AdvancedPriceLevel(
            price: p, kind: AdvancedLevelKind.limit, label: l.betOrderTypeLimit));
      }
    } else if (_isScale) {
      final s = _parsePx(_startPxController);
      final e = _parsePx(_endPxController);
      final n = _parseInt(_countController);
      if (s != null && e != null && n != null && n >= 2 && n <= 8 && s != e) {
        // Every leg at the price it is sent at ([hlScaleLegs]: evenly
        // spaced from start to end, wire-rounded), while a few.
        final step = (e - s) / (n - 1);
        for (var i = 0; i < n; i++) {
          final px = _wirePx(s + step * i);
          if (px != null) {
            levels.add(AdvancedPriceLevel(
                price: px, kind: AdvancedLevelKind.scaleLeg));
          }
        }
      } else {
        for (final p in [s, e]) {
          if (p != null) {
            levels.add(AdvancedPriceLevel(
                price: p, kind: AdvancedLevelKind.scaleLeg));
          }
        }
      }
    }
    if (!_isLedger && _isOpening && _attachTpSl) {
      final tp = _parsePx(_tpController);
      final sl = _parsePx(_slController);
      if (tp != null) {
        levels.add(AdvancedPriceLevel(
            price: tp, kind: AdvancedLevelKind.takeProfit, label: l.hlTakeProfit));
      }
      if (sl != null) {
        levels.add(AdvancedPriceLevel(
            price: sl, kind: AdvancedLevelKind.stopLoss, label: l.hlStopLoss));
      }
    }
    if (_trailingAvailable && _attachTrailing) {
      final d = _parse(_trailDistanceController);
      if (d != null && (!_trailPercent || d < 100)) {
        final away = _trailPercent ? mid * d / 100 : d;
        final px = _isLong ? mid - away : mid + away;
        if (px > 0) {
          levels.add(AdvancedPriceLevel(
              price: px,
              kind: AdvancedLevelKind.trailing,
              label: l.investingTrailingStop));
        }
      }
    }
    return levels;
  }

  Widget _switchRow(AppColorsExtension c, String label, bool value,
          ValueChanged<bool> onChanged,
          {bool card = false}) =>
      HlSwitchRow(
          label: label, value: value, onChanged: onChanged, card: card);

  /// Take profit / stop loss: one switch, and while it is on a stepper for
  /// each with its distance presets from the entry.
  Widget _buildTpSlAttach(AppColorsExtension c, double entry) {
    final l = context.l10n;
    final up = const [2.0, 5.0, 10.0];
    return AdvancedToggleRow(
      key: const ValueKey('order-slip-tpsl-row'),
      icon: Icons.shield_outlined,
      title: l.slipTakeProfitStopLoss,
      value: _attachTpSl,
      switchKey: const ValueKey('order-slip-tpsl-switch'),
      onChanged: (v) {
        _settingChanged('tp_sl', v);
        _updateDraft(() => _attachTpSl = v);
      },
      children: [
        _stepField(c, _NumField.takeProfit, l.slipTakeProfitPrice,
            price: true,
            onStep: (dir) => _stepPrice(_NumField.takeProfit, dir, entry)),
        if (entry > 0)
          _priceChips(_NumField.takeProfit, entry,
              [for (final p in up) _isLong ? p : -p]),
        SizedBox(height: 12.h),
        _stepField(c, _NumField.stopLoss, l.slipStopLossPrice,
            price: true,
            onStep: (dir) => _stepPrice(_NumField.stopLoss, dir, entry)),
        if (entry > 0)
          _priceChips(_NumField.stopLoss, entry,
              [for (final p in up) _isLong ? -p : p]),
        // The same quiet warning line as the open-interest cap's.
        if (_slPastLiquidation) ...[
          SizedBox(height: 10.h),
          Text(
            l.hlAdvSlPastLiquidation,
            key: const ValueKey('order-slip-sl-past-liquidation'),
            style:
                TextStyle(color: c.textSecondary, fontSize: 13.sp, height: 1.4),
          ),
        ],
      ],
    );
  }

  /// The trailing stop attach: one switch, and while it is on the
  /// distance (in % or in dollars), its presets, and an optional
  /// activation price.
  Widget _buildTrailingAttach(AppColorsExtension c, double mid) {
    final l = context.l10n;
    final pcts = const [1.0, 2.0, 5.0];
    final distance = _parse(_trailDistanceController);
    int? pctSelected;
    if (_trailPercent && distance != null) {
      final i = pcts.indexWhere((p) => (p - distance).abs() < 1e-9);
      pctSelected = i < 0 ? null : i;
    }
    return AdvancedToggleRow(
      key: const ValueKey('order-slip-trailing-row'),
      icon: _isLong ? Icons.trending_down_rounded : Icons.trending_up_rounded,
      title: l.investingTrailingStop,
      value: _attachTrailing,
      switchKey: const ValueKey('order-slip-trailing-switch'),
      onChanged: (v) {
        _settingChanged('trailing', v);
        _updateDraft(() => _attachTrailing = v);
      },
      children: [
        Text(
          _isLong ? l.slipTrailingExplainLong : l.slipTrailingExplainShort,
          style:
              TextStyle(fontSize: 13.sp, color: c.textSecondary, height: 1.4),
        ),
        SizedBox(height: 10.h),
        AdvancedChips(
          key: const ValueKey('order-slip-trailing-unit'),
          labels: [l.slipPercent, l.price2],
          selected: _trailPercent ? 0 : 1,
          onSelected: (i) => _updateDraft(() => _trailPercent = i == 0),
        ),
        SizedBox(height: 10.h),
        _stepField(
          c,
          _NumField.trailDistance,
          _trailPercent ? l.slipDistancePercent : l.slipDistance,
          price: !_trailPercent,
          suffix: _trailPercent ? '%' : '',
          onStep: (dir) {
            if (_trailPercent) {
              final cur = _parse(_trailDistanceController) ?? 1;
              final next = math.max(0.1, ((cur + dir * 0.1) * 10).round() / 10);
              _trailDistanceController.text =
                  _trimZeros(next.toStringAsFixed(1));
              _updateDraft(() {});
            } else {
              final cur = _parse(_trailDistanceController) ?? 0;
              final tick = mid > 0 ? _priceTick(mid) : 1.0;
              final next = math.max(tick, cur + dir * tick);
              _trailDistanceController.text =
                  _trimZeros(next.toStringAsFixed(6));
              _updateDraft(() {});
            }
          },
        ),
        if (_trailPercent)
          Padding(
            padding: EdgeInsets.only(top: 8.h),
            child: AdvancedChips(
              key: const ValueKey('hl-adv-chips-trailDistance'),
              labels: [for (final p in pcts) '${_trimZeros(p.toString())}%'],
              selected: pctSelected,
              onSelected: (i) {
                _trailDistanceController.text = _trimZeros(pcts[i].toString());
                _updateDraft(() {});
              },
            ),
          ),
        SizedBox(height: 10.h),
        _switchRow(
          c,
          l.slipStartFollowingAtPrice,
          _trailActivate,
          (v) => _updateDraft(() => _trailActivate = v),
        ),
        if (_trailActivate) ...[
          SizedBox(height: 8.h),
          _stepField(c, _NumField.trailActivation, l.slipActivationPrice,
              price: true,
              onStep: (dir) =>
                  _stepPrice(_NumField.trailActivation, dir, mid),
              trailing: mid > 0
                  ? '${l.ledgerOrderMarketPrice} '
                      '${formatHlPrice(mid, decimalCap: market.pxDecimalCap)}'
                  : null,
              onTrailing: () => _setPrice(_NumField.trailActivation, mid)),
        ],
      ],
    );
  }

  /// Expert settings, one collapsed card: time in force and post-only on
  /// a limit, reduce-only on a perp's non-market order, slippage on a
  /// market order.
  Widget _buildExpertSettings(AppColorsExtension c) {
    final l = context.l10n;
    final expanded = _advancedOptionsExpanded;
    final rows = <Widget>[];
    void gap() {
      if (rows.isNotEmpty) rows.add(SizedBox(height: 12.h));
    }

    if (!_isLedger && _mode == _OrderMode.limit) {
      gap();
      rows.add(_expertLabel(c, l.slipTimeInForce));
      rows.add(AdvancedChips(
        key: const ValueKey('order-slip-tif'),
        labels: [for (final t in _tifOptions) t.toUpperCase()],
        selected: _tifOptions.contains(_tif) ? _tifOptions.indexOf(_tif) : null,
        onSelected: (i) {
          final t = _tifOptions[i];
          _settingChanged('tif', t.toLowerCase());
          _updateDraft(() {
            _tif = t;
            _postOnly = t == 'Alo';
          });
        },
      ));
      gap();
      rows.add(_switchRow(c, l.slipPostOnlyOption, _postOnly, (v) {
        _settingChanged('post_only', v);
        _updateDraft(() {
          _postOnly = v;
          _tif = v ? 'Alo' : (_tif == 'Alo' ? 'Gtc' : _tif);
        });
      }));
    }
    // Reduce-only — relevant for every non-market type on a perp. A spot
    // sell is already an exit; there is no position to reduce.
    if (!_isLedger && _mode != _OrderMode.market && !isSpot) {
      gap();
      rows.add(_switchRow(c, l.slipReduceOnlyOption, _reduceOnly, (v) {
        _settingChanged('reduce_only', v);
        _updateDraft(() => _reduceOnly = v);
      }));
    }
    if (_mode == _OrderMode.market) {
      gap();
      rows.add(_expertLabel(c, l.maxSlippage));
      final i = _slippageOptions.indexOf(_slippagePct);
      rows.add(AdvancedChips(
        key: const ValueKey('order-slip-slippage'),
        labels: [
          for (final opt in _slippageOptions)
            '${opt.toStringAsFixed(opt == opt.roundToDouble() ? 0 : 1)}%'
        ],
        selected: i < 0 ? null : i,
        onSelected: (k) {
          final opt = _slippageOptions[k];
          _settingChanged('slippage_bps', VenueAnalytics.bps(opt));
          _updateDraft(() => _slippagePct = opt);
        },
      ));
    }

    return Container(
      key: const ValueKey('order-slip-expert-settings'),
      padding: EdgeInsets.fromLTRB(16.w, 4.h, 12.w, expanded ? 16.h : 4.h),
      decoration: AppDecorations.card(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            expanded: expanded,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.selectionClick();
                _updateDraft(
                    () => _advancedOptionsOpen = !_advancedOptionsExpanded);
              },
              child: SizedBox(
                height: 48.h,
                child: Row(
                  children: [
                    Icon(Icons.tune_rounded, size: 20, color: c.textSecondary),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Text(
                        l.slipExpertSettings,
                        style: TextStyle(
                            fontSize: 15.sp,
                            fontWeight: FontWeight.w600,
                            color: c.textPrimary),
                      ),
                    ),
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 22,
                      color: c.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: expanded && rows.isNotEmpty
                ? Padding(
                    padding: EdgeInsets.only(top: 4.h),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: rows,
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _expertLabel(AppColorsExtension c, String text) => Padding(
        padding: EdgeInsets.only(bottom: 8.h),
        child: Text(
          text,
          style: TextStyle(
            color: c.textSecondary,
            fontSize: 13.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

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
  /// reduce-only order on the opposite side. The position itself is
  /// already open, and the ticket closes on its receipt next, so what went
  /// wrong is returned for that receipt to say ("the trailing stop was not
  /// placed"): a failure, or its own approval declined. Null when it was
  /// placed (or none was asked for).
  Future<String?> _placeAttachedTrailing(double filledSize) async {
    if (!_trailingAvailable || !_attachTrailing || !mounted) return null;
    final trail = _trailingDraft();
    final size = flooredSize(filledSize, market.szDecimals);
    final walletId = widget.ledgerWalletId ?? _spendingWalletId();
    if (trail == null || size <= 0 || walletId == null) {
      return _strings.slipTrailingNotPlaced(_strings.errorCopyGeneric);
    }
    final isBuy = !_isLong;
    return hlAttachedTrailingNote(
      _strings,
      describe: _messageFor,
      onFailed: (category) =>
          TrackingService.track('hyperliquid_attached_trailing_failed', params: {
        'coin': market.coin,
        'wallet_kind': _isLedger ? 'ledger' : 'hot',
        'error_category': category,
      }),
      place: () async {
        await RuntimeCapabilitiesService.instance
            .ensureAllowed('trading.advanced');
        await RuntimeCapabilitiesService.instance
            .ensureAllowed('hyperliquid.close');
        final price = await ledgerHlReferencePx(market);
        trail.validate(market: market, isBuy: isBuy, referencePrice: price);
        if (!mounted) return true;
        if (_isLedger) {
          var pending = false;
          final placed = await runLedgerHlTrailingStop(context, ref,
              walletId: walletId,
              market: market,
              isBuy: isBuy,
              size: size,
              trail: trail,
              reduceOnly: true,
              leverage: _leverage,
              isCross: _isCross,
              onPending: () => pending = true);
          // Declined on the device (a submission still in the air is
          // pending, not refused).
          if (placed == null) return pending;
          // The hot path reports from the trading notifier; the Ledger
          // order never touches it.
          final lev = HlIntents.clampLeverage(market, _leverage);
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
          return true;
        }
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
        // Its own approval declined: the receipt says so (it used to
        // return without a word, and the ticket closed on "filled").
        if (grant == null) return false;
        if (!mounted) return true;
        await ref.read(hyperliquidTradingProvider.notifier).placeTrailingStop(
            market: market,
            isLong: isBuy,
            size: size,
            trail: trail,
            leverage: _leverage,
            isCross: _isCross,
            reduceOnly: true,
            grant: grant);
        return true;
      },
    );
  }

  /// [available] is this account's own figure (what a spot sell holds);
  /// [shownAvailableUsd] what "Available" reads for a buy (the whole
  /// spendable Investments and the spending Bitcoin on a hot ticket; the
  /// label only) and [maxUsdOverride] the Max, worked out without the
  /// Bitcoin.
  Widget _buildAmountField(AppColorsExtension c, double available,
      {double? shownAvailableUsd,
      bool balanceKnown = true,
      double? maxUsdOverride,
      bool keypad = false,
      double? minAmountUsd,
      bool belowMinimum = false,
      String? positionNote}) {
    final shown = shownAvailableUsd ?? available;
    // Until the account was read its cash is unknown, not $0.00: the line
    // says the balance is updating rather than adding a 0 into Available.
    final availLabel = isSpot && !_isLong
        ? context.l10n.slipHeld(
            '${formatHlSize(available > 0 ? available / (_midNow() > 0 ? _midNow() : 1) : 0)} ${market.coin}')
        : !balanceKnown
            ? context.l10n.betSlipBalanceUpdating
            : context.l10n.ledgerAvailableAmount(formatHlUsd(shown));
    // Simple ticket: the shared hero + the app's own keypad (pinned by the
    // ticket below the form), so the OS keyboard never covers the sheet.
    if (keypad) {
      // The whole wallet a buy draws on (Dollars, both venues' cash and
      // what the spending Bitcoin lands); a spot sell says what is held,
      // the most it can sell. One row under the figure: the minimum at the
      // left, this at the right.
      final compactAvailLabel = isSpot && !_isLong
          ? availLabel
          : !balanceKnown
              ? context.l10n.betSlipBalanceUpdating
              : context.l10n.betSlipAvailableAmount(formatHlUsd(shown));
      // Everything, floored to a cent: a spot sell of the whole holding
      // as is, a buy or a perp margin with its slippage and fees reserved
      // out of the same cash so the order can be funded (on a hot ticket,
      // the whole spendable Investments, [maxUsdOverride]).
      final venueMaxUsd = available <= 0
          ? 0.0
          : isSpot && !_isLong
              ? (available * 100).floorToDouble() / 100
              : hypercoreMaxOrderUsd(
                  availableUsd: available,
                  leverage: isSpot ? 1 : _leverage,
                  slippagePct: _mode == _OrderMode.market ? _slippagePct : 0,
                );
      // Send mode's Max is its override alone (no order is fitted to this
      // venue's cash).
      final maxUsd = widget.sendPick != null && maxUsdOverride != null
          ? maxUsdOverride
          : math.max(venueMaxUsd, maxUsdOverride ?? 0);
      // One small Max chip beside the figure (and the Advanced pill after
      // it), and under it one quiet line
      // with the balance and the venue minimum. An empty account has
      // nothing to fill and goes straight to the deposit door.
      return BigAmountDisplay(
        prefix: r'$',
        amountText: _amountController.text,
        // The web's column: the figure is a typed field.
        field: widget.typedAmount ? _typedAmountField(c) : null,
        // At the right of the minimum's row.
        trailingCaption: compactAvailLabel,
        minimumOnOwnLine: true,
        // The minimum until an amount is typed, then just the figure; it
        // comes back, red, while the amount is under it.
        minimumLabel: minAmountUsd == null ||
                (_marginUsd > 0 && !belowMinimum)
            ? null
            : context.l10n.amountMinimumInline(formatHlUsd(minAmountUsd)),
        minimumIsError: belowMinimum && minAmountUsd != null,
        noteLabel: positionNote,
        // Max, then the Advanced pill (inert while the order goes out,
        // its dot when Advanced is not the default).
        trailing: SlipAmountPills(
          max: maxUsd > 0
              ? AmountMaxChip(
                  label: context.l10n.max,
                  semanticLabel: context.l10n.amountUseMaximum,
                  onTap: () => _fillAmountChip(maxUsd, 'max'),
                )
              : null,
          advanced: SlipAdvancedButton(
            onTap: _openAdvanced,
            modified: _hasAdvancedConfiguration,
            enabled: !(_isPlacing || _preparing || _ledgerBusy),
          ),
        ),
      );
    }
    // Advanced: the amount is the page's hero, the same controller and
    // its formatter under it (AdvancedHeroAmount), what it is for over it
    // (the total margin of a scale or TWAP) and what is available under.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _amountLabel(),
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
              color: c.textSecondary),
        ),
        SizedBox(height: 4.h),
        AdvancedHeroAmount(
          key: const ValueKey('hl-advanced-amount'),
          controller: _amountController,
          caption: availLabel,
          inputFormatters: [DecimalInputFormatter(fractionDigits: 2)],
        ),
      ],
    );
  }

  String _amountLabel() {
    if (isSpot) return _strings.amount;
    if (_isScale || _isTwap) return _strings.slipTotalMargin;
    return _strings.amount;
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

    // On a market with a position the order trades at the position's own
    // leverage and margin mode (never rewritten): said as it is.
    final heldPos = _heldPositionNow().position;
    final leverage = isSpot
        ? ''
        : heldPos != null
            ? l.slipLeverageSuffix(
                '${heldPos.leverageValue}',
                heldPos.isCross ? l.slipMarginCross : l.slipMarginIsolated)
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
        }
    }
  }

  /// Buy / Sell for spot, Long / Short for perps, in the app language.
  String _sideWord() => isSpot
      ? (_isLong ? _strings.buy : _strings.sell)
      : (_isLong ? _strings.longLabel : _strings.shortLabel);

  /// The Advanced page's details in one card: what the order buys as its
  /// headline, then the price it works at, what backs it (leverage and
  /// margin mode, small: a held position's own), where it would be
  /// liquidated, and the fee with its breakdown. The figures the page
  /// already worked out; nothing new.
  Widget _buildAdvancedSummary(
    AppColorsExtension c,
    double mid,
    double notional,
    double size,
    int? scaleCount,
    double transferFromPerp, {
    required bool hasFunds,
    required double entry,
  }) {
    final l = _strings;
    final cap = market.pxDecimalCap;
    final rows = <AdvancedSummaryRow>[];
    if (!isSpot) rows.add(AdvancedSummaryRow(l.slipNotional, formatHlUsd(notional)));

    // Price context per order type.
    if (_mode == _OrderMode.market) {
      rows.add(AdvancedSummaryRow(
          l.slipEstEntry, formatHlPrice(mid, decimalCap: cap)));
    } else if (_mode == _OrderMode.limit) {
      final p = _parse(_priceController);
      rows.add(AdvancedSummaryRow(l.betLimitPrice,
          p != null ? formatHlPrice(p, decimalCap: cap) : '—'));
    } else if (_isScale) {
      final s = _parse(_startPxController);
      final e = _parse(_endPxController);
      rows.add(AdvancedSummaryRow(
        l.slipRange,
        (s != null && e != null)
            ? '${formatHlPrice(s, decimalCap: cap)} → ${formatHlPrice(e, decimalCap: cap)}'
            : '—',
      ));
      rows.add(AdvancedSummaryRow(
          l.investingOrderCount, l.slipLegsCount(scaleCount ?? 0)));
    } else if (_isTwap) {
      final m = _parseInt(_twapMinutesController);
      rows.add(AdvancedSummaryRow(
          l.slipOver, m != null ? l.slipMinutesValue(m) : '—'));
    }

    final holdingCost = _holdingCostLine(notional);
    if (!isSpot) {
      final heldPos = _heldPositionNow().position;
      final liq = _isOpening && entry > 0 && _marginUsd > 0
          ? _liquidationEstimate(entry, size)
          : (price: null, blocker: null);
      if (_leverage > 1) {
        rows.add(AdvancedSummaryRow(l.slipPositionValue, formatHlUsd(notional)));
      }
      // Where this position would be liquidated, before anything is
      // placed. Only a real price (a 1x long has none worth saying).
      if (liq.blocker != null ||
          (liq.price != null && liq.price!.isFinite && liq.price! > 0)) {
        rows.add(AdvancedSummaryRow(
          l.slipEstLiquidation,
          liq.blocker ?? formatHlPrice(liq.price!, decimalCap: cap),
        ));
      }
      // Leverage AND margin mode, on every ticket: which balance backs
      // this position. A position already held (opened elsewhere, say at
      // 5x cross) keeps its own setting, which the order trades at: its
      // real figures, never "1x". A detail, never the headline.
      rows.add(AdvancedSummaryRow(
        l.chartLeverage,
        '${heldPos?.leverageValue ?? _leverage}× · ${(heldPos?.isCross ?? _isCross) ? l.investingCrossMargin : l.investingIsolatedMargin}',
        key: const ValueKey('order-slip-adv-leverage'),
      ));
    }

    TextStyle note(double size) =>
        TextStyle(fontSize: size, color: c.textSecondary, height: 1.4);
    return AdvancedSummaryCard(
      key: const ValueKey('order-slip-adv-summary'),
      headline: AdvancedSummaryRow(
        l.ledgerSummarySize,
        '${_marginUsd > 0 && size > 0 ? formatHlSize(size) : '0'} ${market.coin}',
        key: const ValueKey('order-slip-adv-size'),
      ),
      rows: rows,
      footer: [
        SizedBox(height: 6.h),
        Divider(height: 1, thickness: 0.5, color: c.borderSubtle),
        SizedBox(height: 10.h),
        _feeSummary(notional, hasFunds: hasFunds),
        if (!isSpot && holdingCost != null) ...[
          SizedBox(height: 10.h),
          Text(holdingCost, style: note(13.sp)),
        ],
        // How the liquidation figure is estimated.
        if (!isSpot && _isOpening && entry > 0 && _marginUsd > 0) ...[
          SizedBox(height: 8.h),
          Text(
            _isCross ? context.l10n.slipLiqNoteCross : context.l10n.slipLiqNoteIsolated,
            style: note(12.sp),
          ),
        ],
        if (transferFromPerp > 0) ...[
          SizedBox(height: 10.h),
          Text(l.investingFundingFromBalance(formatHlUsd(transferFromPerp)),
              style: note(13.sp)),
        ],
      ],
    );
  }

  /// The order's fee: the venue's and Kute's, plus what moving the
  /// shortfall costs while the order needs the move.
  Widget _feeSummary(double notional, {required bool hasFunds}) =>
      HyperliquidFeeSummary(
        notional: notional,
        spot: isSpot,
        buy: _isLong,
        maker: _mode == _OrderMode.limit && _postOnly,
        builder: !_isTwap,
        dex: market.dex,
        hasFunds: hasFunds || _canFundFromDollars,
        // The Ledger account's own fee tier, never the hot account's.
        address: _isLedger ? _ledgerAddress : null,
        useHotAccount: !_isLedger,
        // What moving the shortfall from Dollars costs (the route's fee),
        // inside the one fee row: added to the total, one "Move fee"
        // detail. Only while the order needs the move.
        moveFeeUsd: _moveFee()?.usd,
        moveLegs: _moveFee()?.legs ?? const [],
        moveFeeLabel: _strings.slipMoveFee,
        moveFeePending: _slipShortfallUsd > 0 &&
            (_fundPlan == null ||
                (_fundPlan!.shortfallUsd - _slipShortfallUsd).abs() >= 0.005),
      );

  /// Every leg the move of the shortfall would take and its fee, on the
  /// figures the app holds now, from the plan read for this shortfall
  /// ([estimateOrderFundingFees]). Null while no move is needed or its
  /// plan is still being read. Reads nothing new.
  OrderFundingFees? _fundingFeesNow() {
    final plan = _fundPlan;
    if (_slipShortfallUsd <= 0 ||
        plan == null ||
        (plan.shortfallUsd - _slipShortfallUsd).abs() >= 0.005) {
      return null;
    }
    return estimateOrderFundingFees(
      fundUsd: plan.fundUsd,
      arrivingUsd: plan.arrivingUsd,
      dollarsUsd: _dollarsUsd(),
      venue: OneBalanceVenue.investing,
      bitcoinMaxUsd: bitcoinMaxLandingUsd(cachedSpendingBitcoin(ref.read)),
      bitcoinSpread: plan.bitcoinSpread ?? BitcoinLegRules.fallbackSpread,
      otherVenues: venueCashCandidatesNow(ref.read),
    );
  }

  /// What moving the shortfall costs while the order needs the move, from
  /// the plan read for it: the Dollars route's share when Dollars carry it
  /// all, else every leg's fee added (Bitcoin, the Predictions cash, at
  /// once), each leg its own line ([estimateOrderFundingFees]). Null while
  /// no move is needed or its plan is still being read.
  ({double usd, List<MoneyFeeLeg> legs})? _moveFee() {
    // Send mode moves nothing here: "Send now" names its own fee.
    if (widget.sendPick != null) return null;
    final plan = _fundPlan;
    final fees = _fundingFeesNow();
    if (plan == null || fees == null) return null;
    if (fees.isEmpty || fees.dollarsOnly) {
      return (usd: plan.moveFeeUsd, legs: const []);
    }
    return (
      usd: fees.totalUsd,
      legs: [
        for (final leg in fees.legs)
          (label: fundingLegFeeLabel(_strings, leg.source), usd: leg.feeUsd),
      ],
    );
  }

  /// The plain ticket's two figures, no boxes: what the order buys (the
  /// size in the coin) and its fee, zero in each until an amount is typed
  /// (a tap on the fee opens its breakdown sheet). The leverage, margin
  /// mode, position value and liquidation estimate live in Advanced
  /// (leverage is 1× here); only the carrying cost stays, as a quiet line
  /// under the figures, when it applies.
  Widget _buildCompactSummary(
    AppColorsExtension c,
    double notional,
    double transferFromPerp, {
    required bool hasFunds,
    double size = 0,
  }) {
    final holdingCost = _holdingCostLine(notional);
    final sized = _marginUsd > 0 && size > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SlipFigures(
          left: SlipFigure(
            key: const ValueKey('order-slip-size-tile'),
            label: isSpot
                ? _strings.ledgerSummarySize
                : _strings.chartPositionSize,
            value: '${sized ? formatHlSize(size) : '0'} ${market.coin}',
          ),
          right: KeyedSubtree(
            key: const ValueKey('order-slip-fee-tile'),
            child: MoneyFeeFigure(
                child: _feeSummary(notional, hasFunds: hasFunds)),
          ),
        ),
        // No full-width rows under the two figures: the position value
        // and the liquidation estimate live on the Advanced page.
        if (!isSpot && holdingCost != null) ...[
          SizedBox(height: 10.h),
          Text(
            holdingCost,
            style:
                TextStyle(fontSize: 13.sp, color: c.textSecondary, height: 1.4),
          ),
        ],
        if (transferFromPerp > 0) ...[
          SizedBox(height: 10.h),
          Text(
            _strings.investingFundingFromBalance(formatHlUsd(transferFromPerp)),
            style:
                TextStyle(fontSize: 14.sp, color: c.textSecondary, height: 1.4),
          ),
        ],
      ],
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
    final amount = formatDollars(amountUsd ?? _marginUsd);
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

  /// The button on a ticket with nothing typed: the order's short name
  /// ("Long ETH", "Buy BTC", "Close long"), never an amount.
  String _emptyCtaLabel(HlPositionPlan plan) =>
      plan.effect == HlPositionEffect.close
          ? _strings.slipCtaClose(plan.heldSide)
          : _ctaLabel(empty: true);

  String _ctaLabel({double? amountUsd, bool empty = false}) {
    // The stake, in dollars like the asset PRICE.
    final amount = formatDollars(amountUsd ?? _marginUsd);
    final side = _sideWord();
    final l = _strings;
    // The button is the deed, short (founder): "Short $12.00", "Buy
    // $12.00"; before an amount is typed, the minimum a tap places,
    // "Long minimum on ETH".
    switch (_mode) {
      case _OrderMode.market:
        if (empty) return l.slipCtaSideMinimum(side, market.coin);
        return l.slipCtaSideAmount(side, amount);
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
        }
    }
  }

  // Header identity with public-market educational help and close control.
  Widget _buildHeader(AppColorsExtension c) {
    // Built in its own context, under the slip's [SlipFit].
    return Builder(builder: (context) => _headerRow(context, c));
  }

  Widget _headerRow(BuildContext context, AppColorsExtension c) {
    final pad = SlipDensity.tight(context) ? 9.h : 14.h;
    final row = Padding(
      padding: EdgeInsets.fromLTRB(20.w, pad, 20.w, pad),
      child: Row(
        children: [
          // Web: no logo to draw, no box and no gap (hlLogoShown).
          if (hlLogoShown(market.coin, market.wireCoin, market.iconUrl,
              market.category)) ...[
            HlCoinIcon(
              coin: market.coin,
              wireCoin: market.wireCoin,
              category: market.category,
              iconUrl: market.iconUrl,
              size: 36,
            ),
            SizedBox(width: 10.w),
          ],
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
          // No Sal here: the slip is the moment of decision. In place
          // (embedded) there is no sheet to close.
          if (!widget.embedded) ...[
            SizedBox(width: 8.w),
            const KuteCloseButton(),
          ] else if (widget.onEmbeddedClose case final close?) ...[
            // The desk's side panel closes back to the page.
            SizedBox(width: 8.w),
            KuteCloseButton(
                key: const ValueKey('order-slip-panel-close'),
                onPressed: close),
          ],
        ],
      ),
    );
    // Send mode says it at the top (send_pick_session.dart).
    final send = widget.sendPick;
    if (send == null) return row;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20.w, pad, 20.w, 0),
          child: SendPickChip(session: send),
        ),
        row,
      ],
    );
  }

}

