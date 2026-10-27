import 'package:kute/screens/shared/side_tint_palette.dart';
import 'package:kute/screens/polymarket/components/outcome_leading.dart'
    show polyOutcomeFill;
import 'package:kute/services/polymarket/polymarket_fee_terms.dart';
import 'package:kute/services/polymarket/market_buy_quote.dart'
    show
        PolymarketMarketBuyQuote,
        PolymarketThinBook,
        polymarketBuyCap,
        polymarketCentsLabel,
        polymarketEstimatedTick;
import 'package:kute/services/polymarket/placement_timeline.dart';
import 'package:kute/services/polymarket/polymarket_slippage_defaults.dart';
import 'package:kute/services/polymarket/placement_diagnostics.dart';
import 'package:kute/services/polymarket/placement_waits.dart';
import 'package:kute/services/polymarket/selected_outcome_guard.dart';
import 'package:kute/screens/polymarket/components/fast_bet_scope.dart';
import 'package:kute/services/polymarket/fast_bet_window.dart';
import 'package:kute/screens/shared/polymarket_fee_summary.dart';
import 'package:kute/screens/shared/kute_motion.dart';
import 'package:kute/screens/polymarket/components/slip_chrome.dart';
// lib/screens/polymarket/components/bet_slip_sheet.dart
//
// Bet slip bottom sheet for placing bets on Polymarket outcomes.
// Supports binary (Yes/No toggle) and multi-outcome (scrollable list).
// Wired to real trading via polymarketTradingProvider.

import 'dart:async';
import 'dart:math';

import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/require_fresh_auth.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart'
    show InvestmentsProduct;
import 'package:kute/screens/ledger/ledger_portfolio_screen.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show PolymarketPosition;

import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart';
import 'package:kute/helpers/formatters/polymarket_side_labels.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/pending_polymarket_bet_provider.dart';
import 'package:kute/providers/polymarket_bet_controller.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:kute/screens/home/home_feature_carousel.dart'
    show checkPolymarketGeoblock;
import 'package:kute/screens/polymarket/components/price_format.dart';
import 'package:kute/services/polymarket/crypto_round.dart'
    show kCryptoUpDown5mKind, polyIsCryptoUpDown5m;
import 'package:kute/services/polymarket/current_round.dart';
import 'package:kute/services/polymarket/live_game/game_sides.dart'
    show gameIsDrawName;
import 'package:kute/screens/home/components/deposit_sheet.dart'
    show showDepositSheet, MoveLockedSide;
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_open_orders_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/ledger/ledger_pm_buying_power_provider.dart';
import 'package:kute/screens/ledger/polymarket/ledger_pm_bet_target.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/screens/usd/usd_account_screen.dart'
    show openInvestmentsOrders;
import 'package:kute/services/polymarket/sell_settlement.dart'
    show pmLiveOrderDelaySeconds;
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/sticky_action_bar.dart';
import 'package:kute/screens/shared/kute_back_button.dart';

import 'package:kute/screens/shared/decimal_input_formatter.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/services/investment_provider_availability.dart'
    show ProviderAvailabilityException, ProviderAvailabilityStatus;
import 'package:kute/screens/shared/capability_block_note.dart';
import 'package:kute/screens/shared/capability_unavailable_sheet.dart';
import 'package:kute/screens/ledger/ledger_investment_gate.dart'
    show
        ledgerPredictionsCapability,
        ledgerInvestmentAllowed,
        showLedgerInvestmentUnavailable;
import 'package:kute/services/region_freshness.dart';
import 'package:kute/services/success_feedback.dart'
    show moneyFailureFeedbackAfterBand;
import 'package:kute/services/runtime_capabilities_service.dart'
    show
        CapabilityUnavailableException,
        confirmCapability,
        RuntimeCapabilitiesService,
        runtimeCapabilitiesProvider;
import 'package:kute/theme/app_theme.dart';
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/screens/polymarket/components/bet_placed_overlay.dart';
import 'package:kute/screens/polymarket/components/earlier_prediction_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/screens/shared/slip_shortfall.dart';
import 'package:kute/screens/shared/slip_form_body.dart';
import 'package:kute/screens/shared/slip_stat_tiles.dart';
import 'package:kute/screens/shared/money_fee_summary.dart'
    show MoneyFeeFigure, MoneyFeeLeg, fundingLegFeeLabel;
import 'package:kute/services/one_balance/money_steps.dart'
    show MoneyPlace;
import 'package:kute/screens/shared/rubber_band_progress.dart';
import 'package:kute/services/funding/venue_shortfall.dart';
import 'package:kute/providers/pending_bet_autofire.dart'
    show
        autofireRoundClosed,
        autofireSlippagePct,
        kPendingBetAutofireId,
        pendingBetAutoFireProvider,
        polymarketFundedWorstPrice;
import 'package:kute/helpers/auth_grant_registry.dart' show AuthGrantRegistry;
import 'package:kute/providers/spark_address_provider.dart'
    show sparkSelfAddressProvider;
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/services/one_balance/bitcoin_funded_order.dart';
import 'package:kute/services/one_balance/investments_spendable.dart'
    show investmentsSpendableExcludingProvider, venueCashRefreshProvider;
import 'package:kute/services/one_balance/bitcoin_to_dollars_leg.dart'
    show BitcoinLegPlan, BitcoinLegRules;
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/funding_fees.dart';
import 'package:kute/providers/venue_sweeper_provider.dart'
    show pendingBetHoldsCash, venueSweeperProvider;
import 'package:kute/services/one_balance/prediction_funding_ledger.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/services/funding/hot_settlement.dart' show HotSettlement;
import 'package:kute/services/one_balance/one_balance_state.dart'
    show OneBalanceVenue;
import 'package:kute/services/one_balance/bet_funding_plan.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart'
    show
        VenueCashDestination,
        VenueCashPlan,
        VenueCashPuller,
        venueCashPullerProvider,
        venueCashReachExcludingProvider;
import 'package:kute/services/one_balance/multi_source_move.dart'
    show MultiSourceMoveStore;
import 'package:kute/services/one_balance/venue_cash_funded_order.dart'
    show venueCashFundedOrderRunnerProvider;
import 'package:kute/services/one_balance/predictions_venue_cash_order.dart'
    show predictionsVenueCashRequest;
import 'package:kute/services/one_balance/order_funding.dart';
import 'package:kute/services/one_balance/predictions_venue_funder.dart'
    show predictionsVenueFunderProvider;
import 'package:kute/services/one_balance/venue_funder.dart'
    show UserGrantAuthorization;
import 'package:kute/services/polymarket/polymarket_category_gate.dart';
import 'package:kute/services/polymarket/bet_prefund.dart';
import 'package:kute/services/venue_analytics.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';

// Polymarket brand colors. The earlier `_kPolyGreen` / `_kPolyRed`
// were too pastel and scored under 3:1 against white, which forced
// the contrast helper into black text — looked cheap next to
// polymarket.com's saturated green/red CTAs. The deeper tones used
// on the Up/Down buttons live here too so the bet slip CTA matches.
const Color _kPolyGreen = AppColors.marketUp;
const Color _kPolyRed = AppColors.marketDown;
const Color _kPolyPurple = Color(0xFF3B82F6);

/// Outcome leading-thumb fallback palette. Mirrors the colour tier
/// used on the detail sheet's `_ExpandableOutcomeLegend` so the
/// price-rank ordering still reads when an outcome has no
/// `groupItemImage` (or the network image fails to load).
const _kOutcomeFallbackColors = [
  Color(0xFF4FC3F7),
  Color(0xFFCE93D8),
  Color(0xFFFFB74D),
  Color(0xFF81C784),
  Color(0xFFE57373),
  Color(0xFF64B5F6),
  Color(0xFFFFD54F),
  Color(0xFF4DB6AC),
  Color(0xFFBA68C8),
  Color(0xFFFF8A65),
];

Color _outcomeFallbackColor(int i) =>
    _kOutcomeFallbackColors[i % _kOutcomeFallbackColors.length];

/// The CLOB's own floor for a single order, and now ours.
///
/// It used to be doubled to \$2. That padding was for a flow that
/// funded and converted in the same step: the amount that actually
/// landed was only ever an estimate, so an order sized against it could
/// slip under the floor and be rejected after the person had already
/// confirmed. A prediction is placed from the Predictions balance now,
/// so the amount is exact when it is signed and there is nothing to pad
/// against.
///
/// A market whose own minimum order size costs more than this still
/// raises the floor for that market, which is what
/// [_BetSlipSheetState._effectiveMinBetUsd] is for.
const double _kMinBetUsd = 1.0;

/// The disc icon of a side button, from the label it shows: a check and a
/// cross only for a literal Yes/No, arrows for up and down sides (the
/// browse card's Up/Down arrows, Over/Under), a neutral bolt for a team or
/// any other named outcome.
IconData _sideGlyphIcon(String label) => switch (polymarketSideGlyph(label)) {
      PolymarketSideGlyph.yes => Icons.check_rounded,
      PolymarketSideGlyph.no => Icons.close_rounded,
      PolymarketSideGlyph.up => Icons.arrow_upward_rounded,
      PolymarketSideGlyph.down => Icons.arrow_downward_rounded,
      PolymarketSideGlyph.neutral => Icons.bolt_rounded,
    };

/// Pair of side labels for the YES/NO toggle + Predict CTA. Mapped from
/// the selected outcome's `name` via `_BetSlipSheetState._sideLabelFor`
/// so semantic shapes (Over/Under, Odd/Even, team handicap) read with
/// meaningful copy instead of generic YES/NO.
class _SideLabel {
  final String yes;
  final String no;
  const _SideLabel({required this.yes, required this.no});
}

/// The simple ticket and advanced page edit one draft. Navigating between
/// them never creates a second amount, order type, or selected outcome.
class _BetSlipDraft extends ChangeNotifier {
  _BetSlipDraft(
      {required this.selectedIndex,
      required this.buyNo,
      required this.amount,
      required String amountText})
      : amountController = TextEditingController(text: amountText);

  int selectedIndex;
  bool buyNo;
  double amount;
  bool isLimitMode = false;
  double limitPrice = 0;
  String? limitSideKey;
  /// The slippage the person picked; null while the market's own default
  /// applies (polymarketDefaultSlippagePct: wider on a short crypto round).
  double? slippageChoice;
  bool orderPlaced = false;
  bool amountEnteredTracked = false;
  bool ledgerBusy = false;
  bool ledgerPending = false;

  /// A Ledger market buy stopped because the price moved past the signed
  /// maximum: the maximum a new review would name, for "Retry at 85¢".
  double? ledgerRetryPrice;

  /// The open gate's refusal, shared with the Advanced page: see
  /// `_BetSlipSheetState._capabilityBlockMessage`.
  String? openBlockMessage;

  /// [openBlockMessage] is a region refusal: the slip's one button is
  /// "Check connection" (`_BetSlipSheetState._checkConnection`).
  bool openBlockRegion = false;

  /// The policy answered and allows this bet (not on offline grace): a
  /// fast market's slip may get the bet ready before Confirm.
  bool gateAllowed = false;

  /// Getting a fast market's bet ready before Confirm ([BetPrefund]):
  /// the root slip owns it, the Advanced page confirms through it too.
  BetPrefund? prefund;

  /// The policy could not be reached and the last check still allows a
  /// prediction: the decision's own words, shown above the button without
  /// disabling it. Null when the policy answered.
  String? openOfflineNote;
  final TextEditingController amountController;

  // Analytics: where the ticket is, how the amount was entered and why it
  // stopped, for the step / submitted / abandoned events.
  final DateTime openedAt = DateTime.now();
  String flowStep = 'amount';
  // none (opened empty) | prefill (carried in) | keypad | max |
  // min (the under-the-floor button wrote and placed the minimum) |
  // min_direct (the empty slip's button placed the minimum)
  String amountMethod = 'prefill';
  String? stopReason;
  String? lastErrorCategory;

  void changed() => notifyListeners();

  @override
  void dispose() {
    amountController.dispose();
    super.dispose();
  }
}

/// Test seam: stands in for the ONE approval a funded bet asks (the
/// prompt that issues its autofire grant): the intent in, a grant or null
/// (declined) out.
@visibleForTesting
Future<AuthGrant?> Function(SensitiveIntent intent)? debugPmBetFundingApproval;

/// Whether [pending]'s stop retries on its series' round in play: a short
/// round with a slug per window (`btc-updown-5m-…`) that has ended at
/// [now] (it ended while its money was moving, or its price moved past
/// the approval and the round is over since). Its own market can take
/// nothing more; the money is Predictions cash.
bool betSlipRetriesNextRound(PendingBetIntent pending, {DateTime? now}) =>
    pending.status == PendingBetStatus.failed &&
    polyRoundSeriesOf(pending.eventSlug) != null &&
    autofireRoundClosed(pending, now: now);

/// The slip's button once a placement stopped ([pending] failed). A short
/// round that has ended ([betSlipRetriesNextRound]): Retry on the series'
/// round in play ([nextRound]: a new slip on it, the same side and stake,
/// the money already in Predictions). "Retry at 81%" for a 5-minute round
/// still open whose price moved past the approval meanwhile (the tap
/// approves again at the price now and places it); "Retry at 85¢" when
/// the price moved past an approved maximum elsewhere; else Retry. A
/// retry always asks for a new approval; nothing places by itself, and
/// never on a market the person did not confirm.
({String label, bool nextRound}) betSlipStopAction(
    AppLocalizations l10n, PendingBetIntent? pending, {DateTime? now}) {
  if (pending != null && betSlipRetriesNextRound(pending, now: now)) {
    return (label: l10n.retry, nextRound: true);
  }
  final code = pending?.failureCode;
  final movedTo = pending?.movedToPrice;
  if (code == 'round_price_moved' && movedTo != null) {
    return (
      label: l10n.betRetryAtPrice(formatPolyChance(movedTo)),
      nextRound: false
    );
  }
  final retry = pending?.retryMaxPrice;
  return (
    label: retry != null
        ? l10n.betRetryAtPrice(polymarketCentsLabel(retry))
        : l10n.retry,
    nextRound: false,
  );
}

class BetSlipSheet extends ConsumerStatefulWidget {
  final String marketQuestion;
  final String? marketSlug;
  final String? marketImage;
  final List<PolymarketOutcome> outcomes;
  final int initialOutcomeIndex;
  final VoidCallback? onDeposit;

  /// Pins the account throughout review; never resolves through the hot wallet.
  final String? ledgerWalletId;

  /// When the market resolves. Threaded through to `PendingBetIntent`
  /// so the placement overlay can gate sub-5-minute markets to
  /// USDC-only (BTC→USDC swap won't finish in time).
  final DateTime? marketEndAt;

  /// Optional Polymarket category (`crypto` | `sports` | `politics` |
  /// `science` | `other`). Threaded into PendingBetIntent so the
  /// placement event can include it for analytics. Callers that don't
  /// have a PolymarketEvent in scope can leave this null.
  final String? marketCategory;

  /// Pre-selected Yes/No side for the chosen outcome. The market screen
  /// now resolves the side (binary Yes/No bar, or the per-candidate Yes/No
  /// step) before opening the slip, so the slip opens already scoped.
  final bool initialBuyNo;

  /// Resolved side labels from the market screen (moneyline → team names,
  /// O/U → OVER/UNDER …). When set, the binary toggle + CTA use these
  /// instead of re-parsing the market name (which is unreliable for teams).
  final String? sideLabelPos;
  final String? sideLabelNeg;

  /// The colour of each outcome's line on the market's chart, by index
  /// into [outcomes] (null where it has none). An outcome with one tints
  /// the slip in it ([polyOutcomeFill]) instead of the green and red of
  /// Yes and No; flipping to an outcome without one goes back to those.
  final List<Color?>? outcomeColors;

  /// The label each outcome's button writes, by index into [outcomes]. A
  /// three-way match (team, draw, team: three winner markets, each bought
  /// on its Yes) passes one per outcome, and the slip shows the three as
  /// side buttons ("Leeds | Draw | Man Utd") in place of a Yes / No pair.
  final List<String>? outcomeLabels;

  /// Optional amount (USDC) to prefill the slip with — e.g. an AI "bet $20 on
  /// Portugal" recommendation. Null leaves the default $10 seed.
  final double? initialAmountUsd;

  /// The event's Gamma negRisk flag — negRisk markets sign against a
  /// different exchange contract. Used as the fallback when the CLOB
  /// probe fails at placement time. Callers without an event in scope
  /// leave the default false (matches the old fail-open behavior).
  final bool negRisk;

  /// Surface the slip was opened from (feed_card | search | hot_events |
  /// group_landing | ledger | market_detail | ...). Analytics only:
  /// polymarket_bet_slip_opened.source and polymarket_bet_placed.entry_source.
  final String source;

  final _BetSlipDraft? _sharedDraft;
  final bool _advanced;

  const BetSlipSheet({
    super.key,
    required this.marketQuestion,
    this.marketSlug,
    this.marketImage,
    required this.outcomes,
    this.initialOutcomeIndex = 0,
    this.onDeposit,
    this.ledgerWalletId,
    this.marketEndAt,
    this.marketCategory,
    this.initialBuyNo = false,
    this.sideLabelPos,
    this.sideLabelNeg,
    this.outcomeColors,
    this.outcomeLabels,
    this.initialAmountUsd,
    this.negRisk = false,
    this.source = 'unknown',
  })  : _sharedDraft = null,
        _advanced = false;

  BetSlipSheet._advanced(BetSlipSheet source, _BetSlipDraft draft)
      : marketQuestion = source.marketQuestion,
        marketSlug = source.marketSlug,
        marketImage = source.marketImage,
        outcomes = source.outcomes,
        initialOutcomeIndex = source.initialOutcomeIndex,
        onDeposit = source.onDeposit,
        ledgerWalletId = source.ledgerWalletId,
        marketEndAt = source.marketEndAt,
        marketCategory = source.marketCategory,
        initialBuyNo = source.initialBuyNo,
        sideLabelPos = source.sideLabelPos,
        sideLabelNeg = source.sideLabelNeg,
        outcomeColors = source.outcomeColors,
        outcomeLabels = source.outcomeLabels,
        initialAmountUsd = source.initialAmountUsd,
        negRisk = source.negRisk,
        source = source.source,
        _sharedDraft = draft,
        _advanced = true;

  /// Route name used to identify the bet-slip route when popping back after
  /// an order is placed — see [popAllSheetsDownToBetSlipHost].
  static const routeName = 'polymarket-bet-slip';

  static Future<void> show(
    BuildContext context, {
    required String marketQuestion,
    String? marketSlug,
    String? marketImage,
    required List<PolymarketOutcome> outcomes,
    int initialOutcomeIndex = 0,
    VoidCallback? onDeposit,
    String? ledgerWalletId,
    DateTime? marketEndAt,
    String? marketCategory,
    bool initialBuyNo = false,
    String? sideLabelPos,
    String? sideLabelNeg,
    List<Color?>? outcomeColors,
    List<String>? outcomeLabels,
    double? initialAmountUsd,
    bool negRisk = false,
    String source = 'unknown',
    PolymarketEvent? event,
  }) async {
    // A Ledger bet answers to Ledger Predictions (`ledger.polymarket`)
    // first, wherever the slip was opened from (the Ledger Predictions
    // tab, search, a market page). Sells, claims and withdrawals keep
    // their own capabilities and never come through here.
    if (ledgerWalletId != null &&
        !ledgerInvestmentAllowed(ledgerPredictionsCapability)) {
      unawaited(showLedgerInvestmentUnavailable(
          context, ledgerPredictionsCapability));
      return;
    }
    // A market already over (closed, ended, or a short round past its
    // end) never opens a slip: nothing could be placed, and a funded bet
    // would only move money for nothing.
    if (polymarketSlipEnded(
        event: event,
        slug: marketSlug,
        question: marketQuestion,
        endAt: marketEndAt)) {
      showMessageSnackBar(
          context: context,
          message: context.l10n.builderMarketGone,
          error: true);
      return;
    }
    if (event != null) VenueAnalytics.rememberPolymarketEvent(event);
    final ids = [
      for (final o in outcomes) ...[o.tokenId, o.noTokenId, o.conditionId],
    ];
    if (!ids.any(VenueAnalytics.knowsPolymarket)) {
      final shortLived = marketEndAt != null &&
          marketEndAt.difference(DateTime.now()) < const Duration(hours: 1);
      if (marketCategory != null) {
        VenueAnalytics.rememberPolymarket(
            ids: ids,
            category: marketCategory,
            slug: marketSlug,
            endDate: marketEndAt);
      }
      if (marketCategory == null || !shortLived) {
        unawaited(VenueAnalytics.ensurePolymarket(slug: marketSlug, ids: ids));
      }
    }
    final walletKind = ledgerWalletId != null ? 'ledger' : 'hot';
    TrackingService.setFlowContext(
        flow: 'polymarket_bet',
        step: 'amount',
        venue: 'polymarket',
        walletKind: walletKind);
    TrackingService.screenView('bet_slip');
    TrackingService.polymarketBetSlipOpened(
      // Same id the placement events use for this market's outcome.
      outcomes.isNotEmpty &&
              initialOutcomeIndex >= 0 &&
              initialOutcomeIndex < outcomes.length
          ? (outcomes[initialOutcomeIndex].tokenId ?? marketSlug ?? '')
          : (marketSlug ?? ''),
      source: source,
      category: marketCategory,
      walletKind: walletKind,
      // The parent event, the market's own question and the side the slip
      // opened on (public Gamma data). An outcome opened as its own screen
      // passes a stand-in event: the parent's id and title are then the
      // ones on record for its tokens.
      eventId: event != null &&
              !event.isSyntheticBinary &&
              RegExp(r'^\d+$').hasMatch(event.id)
          ? event.id
          : null,
      eventSlug: event?.slug ?? marketSlug,
      eventTitle:
          event != null && !event.isSyntheticBinary ? event.title : null,
      marketTitle: marketQuestion,
      outcome: outcomes.isNotEmpty &&
              initialOutcomeIndex >= 0 &&
              initialOutcomeIndex < outcomes.length
          ? outcomes[initialOutcomeIndex].name
          : null,
      extra: {
        'entry_source': source,
        'funding_source': 'venue_balance',
        'prefilled_amount': initialAmountUsd != null && initialAmountUsd > 0,
        'outcome_count': outcomes.length,
      },
    );
    // NOTHING is awaited before the sheet is shown. The regional gate
    // used to run here, which meant a tap on an outcome sat on the old
    // screen for up to two network round-trips (provider availability
    // + the capabilities policy fetch, 5s timeouts each) before any
    // pixel of the slip appeared. The gate now runs INSIDE the slip,
    // which paints its chrome, outcome, price and amount immediately
    // and swaps to its own "unavailable here" wall the moment the
    // answer lands — see `_resolveCapabilityGate`. Placement is still
    // gated: `_handleBuyInner` and `_handleLedgerBuy` each re-run
    // `checkPolymarketGeoblock` before any order moves, unchanged.
    // Bet slip is a bottom modal sheet stacked over the market detail.
    // `enableDrag: false` because swipe-to-dismiss BYPASSES PopScope
    // (a long-standing Flutter gap) — that let a user swipe the sheet
    // away mid-placement. Dismissal is via tap-outside (isDismissible),
    // which DOES go through PopScope, so the placing-state lock holds.
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
      builder: (_) => FastBetScope(
        active: ledgerWalletId == null && polyIsFastBetRound(marketSlug),
        child: BetSlipSheet(
        marketQuestion: marketQuestion,
        marketSlug: marketSlug,
        marketImage: marketImage,
        outcomes: outcomes,
        initialOutcomeIndex: initialOutcomeIndex,
        onDeposit: onDeposit,
        ledgerWalletId: ledgerWalletId,
        marketEndAt: marketEndAt,
        marketCategory: marketCategory,
        initialBuyNo: initialBuyNo,
        sideLabelPos: sideLabelPos,
        sideLabelNeg: sideLabelNeg,
        outcomeColors: outcomeColors,
        outcomeLabels: outcomeLabels,
        initialAmountUsd: initialAmountUsd,
        negRisk: negRisk,
        source: source,
      )),
    );
  }

  /// Pop the bet slip plus any modal sheets / fullscreen routes that
  /// were stacked above the host (Polymarket / Home). Used before
  /// pushing a result overlay so the user doesn't see the stale slip
  /// or market detail behind it. Pops every ModalBottomSheetRoute
  /// (the slip is one) plus any opaque dialog/fullscreen routes
  /// above the host listing.
  static void popAllSheetsDownToBetSlipHost(NavigatorState navigator) {
    navigator.popUntil((route) {
      if (route is ModalBottomSheetRoute) return false;
      if (route is PopupRoute) return false;
      if (route.settings.name == routeName) return false;
      // PageRouteBuilder used by MarketDetailSheet — pop it too.
      if (route is PageRoute && route.fullscreenDialog) return false;
      return true;
    });
  }

  @override
  ConsumerState<BetSlipSheet> createState() => _BetSlipSheetState();
}

class _BetSlipSheetState extends ConsumerState<BetSlipSheet>
    with SlipIncomingDeposit<BetSlipSheet> {
  late final _BetSlipDraft _draft;
  bool _openingAdvanced = false;

  /// Advanced page only: whether the rarely-touched Details group is
  /// expanded. Purely presentational, so it stays on the page rather
  /// than on the shared draft.
  bool _expertOpen = false;
  bool get _ownsDraft => widget._sharedDraft == null;
  bool get _showAdvanced => widget._advanced;
  bool get _isLedger => widget.ledgerWalletId != null;
  int get _selectedIndex => _draft.selectedIndex;
  set _selectedIndex(int value) => _draft.selectedIndex = value;
  bool get _buyNo => _draft.buyNo;
  set _buyNo(bool value) => _draft.buyNo = value;
  double get _amount => _draft.amount;
  set _amount(double value) => _draft.amount = value;
  bool get _isLimitMode => _draft.isLimitMode;
  set _isLimitMode(bool value) => _draft.isLimitMode = value;
  double get _limitPrice => _draft.limitPrice;
  set _limitPrice(double value) => _draft.limitPrice = value;
  String? get _limitSideKey => _draft.limitSideKey;
  set _limitSideKey(String? value) => _draft.limitSideKey = value;
  TextEditingController get _amountController => _draft.amountController;

  /// Live-feed hold — the slip can open OUTSIDE the Predictions tab
  /// (Home hot-events feed, AI recommendations) where the shell has the
  /// CLOB stream paused; acquire()/release() keeps it live while up.
  LivePriceNotifier? _livePrices;
  /// The controller this slip warmed the placement on (paired release in
  /// dispose, where `ref` is no longer read).
  PolymarketBetController? _warmedSlip;
  bool _isPlacing = false;

  /// In-play order delay (s) by market while its game is on, read from the
  /// CLOB so the button can say why a live game's order takes a moment.
  final Map<String, int> _liveDelays = {};

  /// When each market's delay was last asked for. A "no delay" answer (a
  /// game not started yet, or a read that failed) is asked again after
  /// [_kLiveDelayReread]: kept for the slip's life, a game that kicked off
  /// while it was open was never seen as live, so it was never prefunded.
  final Map<String, DateTime> _liveDelayReadAt = {};
  static const Duration _kLiveDelayReread = Duration(seconds: 20);

  void _loadLiveDelay(String? conditionId) {
    if (conditionId == null || conditionId.isEmpty) return;
    final readAt = _liveDelayReadAt[conditionId];
    if (readAt != null &&
        ((_liveDelays[conditionId] ?? 0) > 0 ||
            DateTime.now().difference(readAt) < _kLiveDelayReread)) {
      return;
    }
    _liveDelayReadAt[conditionId] = DateTime.now();
    _liveDelays.putIfAbsent(conditionId, () => 0);
    unawaited(pmLiveOrderDelaySeconds(conditionId).then((seconds) {
      if (!mounted || seconds <= 0) return;
      _updateState(() => _liveDelays[conditionId] = seconds);
    }));
  }

  /// Non-null once the regional / capability gate has come back with a
  /// refusal: the reason to show the user, in the policy's own words.
  /// The gate resolves behind the slip's first frame instead of in
  /// front of it, so a refusal is told INSIDE the sheet rather than
  /// after a blank wait: the market, outcome and amount stay on screen
  /// and the one action is disabled with this reason above it. Null
  /// means "allowed, or not answered yet" — it never unlocks anything,
  /// placement still re-checks. Lives on the draft so the Advanced page
  /// shows the same state.
  String? get _capabilityBlockMessage => _draft.openBlockMessage;

  /// The refusal the action wears now: none while a placement that
  /// passed its own place-time gate is running.
  String? get _tradeBlock => _isPlacing ? null : _capabilityBlockMessage;

  /// The tap stopped before its order existed: the account's one-time
  /// setup (or the price read) failed or ran out of time. Shows the same
  /// "Could not place prediction" notice and Retry a failed placement
  /// does; the status alone was set but nothing on the slip showed it, so
  /// the spinner just stopped.
  bool _prepareFailed = false;

  /// Synchronous re-entrancy guard for [_handleBuy]. `_isPlacing` only
  /// flips AFTER the awaited geoblock check, so a double-tap during that
  /// network round-trip would otherwise run two placements (two intents,
  /// two BTC swaps). Set before the first await, cleared in finally.
  bool _buyInFlight = false;

  /// The under-the-floor button just wrote the market's minimum: the next
  /// build places it when the button there is the bet itself (the same
  /// tap a typed minimum would get), and leaves it written when the
  /// minimum needs the deposit door instead ([_fillMinimum]).
  bool _placeMinimumOnBuild = false;

  /// "Check connection" is asking the venues and the policy again.
  bool _checkingConnection = false;

  /// From a Deposit door tap until the Move sheet opens (or the tap ends
  /// without one): the top-up is being worked out, and the door says so.
  /// The form is already frozen by [_buyInFlight] for the same span, so
  /// the bet queued behind the deposit is the one on the slip at the tap.
  bool _doorCalculating = false;

  /// The "Add $X to Investments" tap is running the bet through the
  /// normal tap, to be funded from the person's own bitcoin
  /// ([_fundAndPlaceFromBitcoin]) where Dollars fall short.
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

  /// The Bitcoin-funded run this slip started, if any.
  String? _bitcoinRunId;

  /// True while a swap leg is part of the active placement — drives the
  /// 3-step vs single-step progress bar in the placing panel.
  bool _swapNeeded = false;

  /// One balance: the move a short bet would make from Dollars, from the
  /// venue's live estimate (the "Move fee" row, the "Add $X to
  /// Investments" button). Worked out for [_fundingPlanAmount]; null
  /// until read, or while the bet is covered by venue cash.
  OrderFundingPlan? _fundingPlan;
  double? _fundingPlanAmount;
  bool _fundingPlanReading = false;

  /// The Bitcoin conversion's share Orchestra quoted when the plan was
  /// read (null: the fallback spread), for the Bitcoin leg's fee line.
  double? _fundingBitcoinSpread;

  /// What funding the placed bet cost (every leg, estimated), held from
  /// its approval for the receipt's fee. Null when nothing moved.
  double? _placedFundingFeeUsd;

  /// Read once in initState: dispose and a pre-fund move finishing after
  /// the slip went must not touch `ref`.
  late final PendingPolymarketBetNotifier _pendingNotifier;
  late final OrderFundingController _orderFunding;
  late final VenueCashPuller _venueCashPuller;

  /// The multi-source move a Confirm-time funding's venue cash went under,
  /// and the funding it was for: a Confirm again for the same funding
  /// continues it, so Investing cash already sent straight to Predictions
  /// is never pulled twice.
  String? _moveId;
  double? _moveUsd;
  late final Future<PolymarketMarketWindow?> Function(String conditionId)
      _marketWindowReader;

  /// What the pre-fund hold last looked at (outcome token, stake, order
  /// shape, market kind): a change restarts the one-second hold.
  (String?, double, bool, double, PrefundMarketKind?)? _prefundKey;

  /// Latches the success state so the ticket stays locked while the slip
  /// closes, even after the intent provider clears (the BTC auto-fire
  /// nulls it ~600ms after `done`).
  bool _placedSuccess = false;

  /// True once the user has tapped Place Order successfully — used by
  /// `dispose()` to distinguish a "user abandoned the slip" from a
  /// "user placed the bet" close. Without this flag every successful
  /// bet would also emit `bet_slip_abandoned`, inflating drop-off.
  bool get _orderPlaced => _draft.orderPlaced;
  set _orderPlaced(bool value) => _draft.orderPlaced = value;

  /// One-shot guard so `polymarketBetAmountEntered` fires once per slip
  /// lifetime (the first time the amount crosses above 0), not on every
  /// keystroke / rebuild. Reset only on a fresh slip instance.
  bool get _amountEnteredTracked => _draft.amountEnteredTracked;
  set _amountEnteredTracked(bool value) => _draft.amountEnteredTracked = value;
  /// The market order's slippage: the person's pick, else the market's
  /// default (10% on a 5- or 15-minute crypto round, 12% in its last
  /// minute, 5% elsewhere), shown as the maximum price before approval.
  double get _slippagePct =>
      _draft.slippageChoice ??
      polymarketDefaultSlippagePct(
          slug: widget.marketSlug,
          question: widget.marketQuestion,
          endAt: widget.marketEndAt,
          // A game in play (the venue holds its orders for an in-play
          // delay) moves like a short round and starts as wide.
          live: (_liveDelays[
                      widget.outcomes[_selectedIndex].conditionId ?? ''] ??
                  0) >
              0);
  set _slippagePct(double value) => _draft.slippageChoice = value;

  static const _slippageOptions = [1.0, 2.0, 5.0, 10.0];

  /// A market is "binary" whenever it has exactly two outcomes that price
  /// against each other (complementary odds summing to ~1). That covers
  /// Yes/No and every other two-sided market Polymarket hosts: Day/Night,
  /// Even/Odd, On/Off, Heads/Tails, Up/Down, etc. Keying off the structure
  /// instead of the string "yes" stops those markets from flopping into
  /// the less-useful multi-outcome list layout.
  bool get _isBinary {
    if (widget.outcomes.length != 2) return false;
    final a = widget.outcomes[0].price;
    final b = widget.outcomes[1].price;
    // Allow a generous tolerance — thin markets can show sums as far as
    // 0.85–1.15 when the book is quiet.
    return (a + b) > 0.8 && (a + b) < 1.2;
  }

  /// Index of the "positive / yes-equivalent" side for binary rendering
  /// (green, check or up arrow): Yes, Up or Over wherever it sits, else
  /// the first outcome. Colour and glyph only — the order always buys the
  /// outcome at [_selectedIndex].
  int get _positiveIndex =>
      polymarketPositiveIndex([for (final o in widget.outcomes) o.name]);

  /// The label of the binary side at outcome [index]: the title's
  /// semantic pair (UP / DOWN, teams, OVER / UNDER …) matched to the
  /// outcome it names, else the outcome's own name (null). The toggle and
  /// the button both read it, so they always name the outcome that is
  /// bought.
  String? _sideLabelAt(int index) {
    if (widget.outcomes.length != 2 || index < 0 || index > 1) return null;
    final l = _effectiveSideLabels;
    return polymarketBinarySideLabels(
        [for (final o in widget.outcomes) o.name], (pos: l.yes, neg: l.no))?[
      index];
  }

  int get _negativeIndex => 1 - _positiveIndex;

  /// A three-way match ([BetSlipSheet.outcomeLabels]): three side buttons,
  /// each buying its own winner market's Yes.
  bool get _isThreeWay =>
      widget.outcomes.length == 3 &&
      widget.outcomeLabels?.length == 3 &&
      !widget.outcomes.any((o) => o.hasYesNo);

  /// Map an outcome's `name` to the pair of side labels that should appear
  /// on the YES/NO toggle and in the "Predict [side]" CTA. Most candidate
  /// markets are plain YES/NO, but several common shapes read much better
  /// with semantic labels:
  ///
  ///   - Over/Under sub-markets (player props, totals) → OVER / UNDER
  ///   - Odd/Even markets → ODD / EVEN
  ///   - Team-vs-team handicap (e.g. "LGC (-1.5) vs Team Falcons (+1.5)")
  ///     → first-team + sign / second-team + sign ("LGC -1.5" / "FAL +1.5")
  ///
  /// Returns a [_SideLabel] always — defaults to ("YES", "NO") when no
  /// shape matches so callers don't have to null-check.
  _SideLabel _sideLabelFor(String outcomeName) {
    // Centralised in `polymarket_side_labels.dart` so the bet slip and the
    // market-detail buttons always agree (Over/Under, moneyline teams,
    // spread lines, handicap, Odd/Even, else Yes/No).
    final l = polymarketSideLabels(outcomeName);
    return _SideLabel(yes: l.pos, no: l.neg);
  }

  /// Binary-market side labels — caller-resolved override from the market
  /// screen (reliable team names for moneyline) when present, else parsed
  /// from the market name.
  _SideLabel get _effectiveSideLabels {
    if (widget.sideLabelPos != null && widget.sideLabelNeg != null) {
      return _SideLabel(yes: widget.sideLabelPos!, no: widget.sideLabelNeg!);
    }
    return _sideLabelFor(widget.marketQuestion);
  }

  /// True when the SELECTED outcome exposes its own Yes/No sub-market so the
  /// sheet can render the YES/NO side-flip toggle + a "Predict YES/NO" CTA
  /// for that candidate. Used to require `every` outcome to expose hasYesNo,
  /// but Gamma sometimes omits the `noTokenId` on thin or resolved variants
  /// of an event (e.g. handicap sub-markets on Counter-Strike where one side
  /// has no book) — which collapsed the whole sheet back to the bland
  /// "Predict · $X" fallback even when the user's pick had a perfectly
  /// valid Yes/No pair. Keying off the selected row only unlocks the
  /// toggle on a per-row basis. `_isBinary` is still excluded because the
  /// top-of-sheet binary toggle already exposes both sides there.
  bool get _isCandidatePicker =>
      !_isBinary &&
      widget.outcomes.isNotEmpty &&
      _selectedIndex >= 0 &&
      _selectedIndex < widget.outcomes.length &&
      widget.outcomes[_selectedIndex].hasYesNo;

  @override
  void initState() {
    super.initState();
    if (widget._sharedDraft case final draft?) {
      _draft = draft;
    } else {
      // An amount carried in (a deposit's come-back, a builder leg, Sal)
      // opens the slip on it; otherwise it opens empty, typed from zero,
      // and the button offers the market's minimum ([_placeMinimum]).
      final carried =
          widget.initialAmountUsd != null && widget.initialAmountUsd! > 0;
      final amount = carried ? widget.initialAmountUsd! : 0.0;
      final display = _usdcToFiat(amount);
      _draft = _BetSlipDraft(
        selectedIndex:
            widget.initialOutcomeIndex.clamp(0, widget.outcomes.length - 1),
        buyNo: widget.initialBuyNo,
        amount: amount,
        amountText: !carried
            ? ''
            : display == display.roundToDouble()
                ? display.toStringAsFixed(0)
                : display.toStringAsFixed(2),
      )..amountMethod = carried ? 'prefill' : 'none';
      _amountController.addListener(_onAmountChanged);
    }
    _draft.addListener(_onDraftChanged);
    if (!_isLedger) _loadLiveDelay(widget.outcomes[_selectedIndex].conditionId);
    _pendingNotifier = ref.read(pendingPolymarketBetProvider.notifier);
    _orderFunding = ref.read(orderFundingControllerProvider);
    _venueCashPuller = ref.read(venueCashPullerProvider);
    _marketWindowReader = ref.read(polymarketMarketWindowReaderProvider);
    if (_ownsDraft && !_isLedger) {
      _draft.prefund = BetPrefund(
        approve: _prefundApprove,
        fund: _prefundFund,
        plan: ({required requiredUsd, required readyUsd}) =>
            _fundingPlanFor(required: requiredUsd, ready: readyUsd),
        window: _fundingWindow,
        onDisarm: _dropArmedBet,
        onChanged: () {
          if (mounted) _updateState(() {});
        },
      );
      // Moves made to get the bet ready land with the venue's balance; an
      // account read late (or a policy answered late) looks again.
      ref.listenManual(polymarketTradingProvider, (prev, next) {
        final state = next.valueOrNull;
        final balance = state?.usdcBalance;
        if (balance != null) _draft.prefund?.observeBalance(balance);
        if (state?.balanceKnown == true &&
            prev?.valueOrNull?.balanceKnown != true) {
          _prefundKey = null;
          _maybeScheduleHold();
        }
      });
    }

    // Hold the live-price feed while the slip is up — it can open from
    // surfaces outside the Predictions tab (Home hot-events feed, AI
    // recommendations) where the shell has the stream paused. acquire()
    // BEFORE addTokens so the tokens subscribe on the revived socket;
    // paired release() in dispose.
    _livePrices = ref.read(livePriceProvider.notifier);
    _livePrices!.acquire();

    // Subscribe this market's tokens to live price WebSocket. For
    // candidate-picker events each outcome also has a `noTokenId`; we
    // must subscribe to those too, otherwise the No-leg's live price
    // never populates and the share-calc fallback lands on the Yes
    // price instead, which produces wildly wrong share counts.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tokenIds = <String>[];
      for (final o in widget.outcomes) {
        if (o.tokenId != null && o.tokenId!.isNotEmpty) {
          tokenIds.add(o.tokenId!);
        }
        if (o.noTokenId != null && o.noTokenId!.isNotEmpty) {
          tokenIds.add(o.noTokenId!);
        }
      }
      if (tokenIds.isNotEmpty) {
        _livePrices?.addTokens(tokenIds);
      }
      // Warm what the tap would otherwise fetch: the venue connection,
      // the saved market terms and fee curve, the builder code. The
      // live book comes through the feed subscribed above.
      if (_warmedSlip == null) {
        final controller = ref.read(polymarketBetControllerProvider);
        _warmedSlip = controller;
        controller.warmSlip(
            tokenId: widget.outcomes[_selectedIndex].tokenId ?? '');
      }
    });

    // Resolve the regional / capability gate behind the first frame.
    // Only the root slip runs it — Advanced is pushed from an already
    // resolved slip and shares its draft.
    if (!widget._advanced) {
      unawaited(_resolveCapabilityGate());
      // A refusal worked out at open belongs to the network it was asked
      // on: after a resume, a network or VPN change, or a venue answer
      // that flipped, the gate asks again and lifts it when it is gone.
      RegionFreshness.answers.addListener(_onRegionAnswers);
    }
  }

  void _onRegionAnswers() {
    if (!mounted || _isPlacing || _buyInFlight) return;
    if (_draft.openBlockMessage == null && _draft.openOfflineNote == null) {
      return;
    }
    unawaited(_resolveCapabilityGate());
  }

  /// Ask the policy whether this user may place a prediction at all.
  ///
  /// Same two checks (and the same refusal copy) that
  /// `checkPolymarketGeoblock` runs — they just no longer hold the
  /// sheet back. A refusal disables the slip's one action and puts the
  /// reason above it ([CapabilityBlockNote]); the market stays readable.
  /// This
  /// grants nothing: placement still calls `checkPolymarketGeoblock`
  /// at its own choke points.
  Future<void> _resolveCapabilityGate() async {
    String? message;
    var regionBlocked = false;
    // The policy's own reason (country_blocked, policy_unavailable,
    // offline_grace, …), so bet_slip_abandoned says why the slip stopped.
    var reason = 'capability_unavailable';
    var offline = false;
    CapabilityUnavailableException? denial;
    try {
      await RuntimeCapabilitiesService.instance
          .ensureAllAllowed(_betCapabilities());
    } on ProviderAvailabilityException catch (error) {
      message = error.availability.message;
      regionBlocked =
          error.availability.status == ProviderAvailabilityStatus.restricted;
    } on CapabilityUnavailableException catch (error) {
      final decision = error.decision;
      message = decision.message;
      regionBlocked = decision.regionRestricted;
      if (decision.reason.isNotEmpty) reason = decision.reason;
      offline = decision.offline;
      denial = error;
    }
    if (!mounted || _isPlacing || _buyInFlight) return;
    if (message == null) {
      // Allowed. A refusal shown earlier (a stale region answer, asked
      // again after a network change or resume) goes away. When that is
      // the last check standing in for a policy that cannot be reached
      // (offline grace), say so above the button, which stays enabled.
      var offlineGrace = false;
      String? offlineNote;
      for (final id in _betCapabilities()) {
        final decision = RuntimeCapabilitiesService.instance.decision(id);
        if (decision.offline) {
          offlineGrace = true;
          offlineNote = decision.message;
          break;
        }
      }
      if (_draft.openBlockMessage != null) {
        // The refusal no longer stands, so it is not why the slip stops.
        _draft.stopReason = null;
        _draft.lastErrorCategory = null;
      }
      if (_draft.openBlockMessage != null ||
          _draft.openOfflineNote != offlineNote) {
        _updateState(() {
          _draft.openBlockMessage = null;
          _draft.openBlockRegion = false;
          _draft.openOfflineNote = offlineNote;
        });
      }
      // Only a policy that answered lets the slip get a bet ready early.
      if (!offlineGrace) {
        _draft.gateAllowed = true;
        _prefundKey = null;
        _maybeScheduleHold();
      }
      return;
    }
    // Gone, or the user already committed — leave the slip be. A refusal
    // that lands mid-placement is caught by the place-time gate, so the
    // UI must not be swapped out from under it.
    if (offline) {
      _updateState(() => _draft.openOfflineNote = message);
      return;
    }
    // Counted once per refusal shown, not again for each re-check that
    // confirms it.
    if (regionBlocked && _draft.openBlockMessage == null) {
      TrackingService.polymarketGeoblockedShown();
      if (denial != null) {
        TrackingService.capabilityRegionBlocked(denial.capability,
            blockedBy: denial.decision.blockedBy, surface: 'bet_slip');
      }
    }
    _stopped(regionBlocked ? 'geoblocked' : reason);
    _draft.lastErrorCategory = reason;
    _updateState(() {
      _draft.openBlockMessage = message;
      _draft.openBlockRegion = regionBlocked;
    });
  }

  /// "Check connection" on a region refusal (founder decision, October
  /// 2026): the person says their connection changed, so the venues and
  /// Kute's policy are asked again ([RegionFreshness.checkConnection]).
  /// Allowed now: the refusal goes and the button is the bet again,
  /// ready to place. Still restricted: the refusal stays, with the soft
  /// failure tap, and the button can be tapped again. A check that could
  /// not be made never shows restricted.
  Future<void> _checkConnection() async {
    if (_checkingConnection) return;
    setState(() => _checkingConnection = true);
    await RegionFreshness.checkConnection();
    if (!mounted) return;
    if (!RegionFreshness.regionRefused(capabilities: _betCapabilities())) {
      _draft.stopReason = null;
      _draft.lastErrorCategory = null;
      _updateState(() {
        _checkingConnection = false;
        _draft.openBlockMessage = null;
        _draft.openBlockRegion = false;
      });
      // The rest of the open gate (an offline note, a bet got ready
      // early), as when the slip opened.
      if (!widget._advanced) unawaited(_resolveCapabilityGate());
      return;
    }
    setState(() => _checkingConnection = false);
    moneyFailureFeedbackAfterBand(() => mounted && _checkingConnection);
  }

  void _onDraftChanged() {
    if (mounted) setState(() {});
    _maybeScheduleHold();
  }

  // ── Getting a fast market's bet ready (BetPrefund) ─────────────────────

  /// A 5- or 15-minute round, or a game in play, else null.
  PrefundMarketKind? get _prefundKind => prefundMarketKind(
      slug: widget.marketSlug,
      question: widget.marketQuestion,
      endAt: widget.marketEndAt,
      live: (_liveDelays[widget.outcomes[_selectedIndex].conditionId ?? ''] ??
              0) >
          0);

  /// The root slip restarts the one-second hold whenever the stake, the
  /// outcome, the order or the market's kind changes.
  void _maybeScheduleHold() {
    final prefund = _draft.prefund;
    if (!_ownsDraft || prefund == null || !mounted) return;
    // The outcome picked now may be another market of the game (each
    // team's own): its in-play delay is read here, not only at open.
    _loadLiveDelay(widget.outcomes[_selectedIndex].conditionId);
    final key =
        (_selectedTokenId, _amount, _isLimitMode, _slippagePct, _prefundKind);
    if (key == _prefundKey) return;
    _prefundKey = key;
    prefund.scheduleHold(_prefundSnapshot);
  }

  /// The slip as the pre-funding reads it. Reads only, never watches.
  PrefundSnapshot _prefundSnapshot() {
    final trading = ref.read(polymarketTradingProvider);
    final account = trading.valueOrNull;
    final cash = account?.usdcBalance ?? 0;
    final token = _selectedTokenId;
    final terms = ref
            .read(polymarketFeeTermsProvider(
                widget.outcomes[_selectedIndex].tokenId ?? ''))
            .valueOrNull ??
        PolymarketFeeTerms.worstCase;
    final caps = ref.read(runtimeCapabilitiesProvider);
    final queued = ref.read(pendingPolymarketBetProvider);
    final sweeping = ref
        .read(venueSweeperProvider)
        .sweeping
        .contains(OneBalanceVenue.predictions);
    return PrefundSnapshot(
      kind: _prefundKind,
      priceNow: _isLimitMode ? null : _slipIntent()?.expectedPrice,
      selection: PrefundSelection(
          tokenId: token ?? '',
          isLimit: _isLimitMode,
          slippagePct: _slippagePct),
      amountUsd: _amount,
      minBetUsd: _effectiveMinBetUsd,
      requiredUsd: _predictionsRequired(terms),
      readyUsd: _predictionsReady(cash),
      balanceUsd: cash,
      // Dollars alone: a move that needs Bitcoin or the Investing cash is
      // Confirm's, which takes them in the founder's order
      // ([decideOrderSources]), never got ready ahead.
      dollarsUsd: _dollarsUsd(),
      allowed: !_isLedger &&
          token != null &&
          token.isNotEmpty &&
          trading.hasValue &&
          !trading.hasError &&
          (account?.balanceKnown ?? false) &&
          _draft.gateAllowed &&
          _capabilityBlockMessage == null &&
          caps.blockReason('polymarket.deposit') == null &&
          (!_usesAdvanced || caps.blockReason('trading.advanced') == null),
      busy: _isPlacing ||
          _buyInFlight ||
          _doorCalculating ||
          _orderPlaced ||
          _placedSuccess ||
          (queued != null && queued.funded && pendingBetHoldsCash(queued)) ||
          sweeping,
    );
  }

  /// The one prompt of a pre-funded bet: the slip's bet prepared, then
  /// the funded bet's approval (bet + funding cap, the autofire grant).
  /// The prepared bet stays in the pending provider, armed: waiting
  /// (`awaitingDeposit`) with its funding cap, so it never fires until
  /// Confirm queues it.
  Future<PrefundApproval> _prefundApprove(PrefundRequest request) async {
    if (!mounted) return const PrefundApproval.unavailable();
    final intent = _slipIntent();
    if (intent == null) return const PrefundApproval.unavailable();
    _pendingNotifier.setIntent(intent);
    final grant = await _approveBet(
        funding: OrderFundingPlan(
            fundUsd: request.fundingCapUsd,
            arrivingUsd: 0,
            rule: ShortfallRules.ruleRemaining,
            minUsd: 0),
        prefund: !request.atConfirm);
    if (grant == null) {
      final declined = _lastDeclineReason == 'approval_not_granted';
      if (mounted &&
          ref.read(pendingPolymarketBetProvider)?.status !=
              PendingBetStatus.failed) {
        _pendingNotifier.clear();
      }
      return declined
          ? const PrefundApproval.declined()
          : const PrefundApproval.unavailable();
    }
    final pending = mounted ? ref.read(pendingPolymarketBetProvider) : null;
    if (pending == null || !_orderMatchesSelection(pending.tokenId)) {
      grant.revoke();
      _pendingNotifier.clear();
      return const PrefundApproval.unavailable();
    }
    final armed = pending.copyWith(fundUsd: request.fundingCapUsd);
    _pendingNotifier.setIntent(armed);
    return PrefundApproval.approved(grant, armed,
        worstPrice: polymarketFundedWorstPrice(armed));
  }

  /// A pre-funding move under the armed approval, from Dollars alone: a
  /// move Dollars cannot cover is Confirm's, which takes Bitcoin and then
  /// the Investing cash in the founder's order ([decideOrderSources]).
  Future<OrderFundingOutcome> _prefundFund(double fundUsd, AuthGrant grant,
      {required double requiredUsd, required double readyUsd}) async {
    final dollars = _dollarsUsd();
    if (dollars + 1e-9 < fundUsd) {
      return OrderFundingNeedsDollars(fundUsd - dollars);
    }
    return _orderFunding.fundAndQueue(
      venue: OneBalanceVenue.predictions,
      orderUsd: _draft.amount,
      requiredUsd: requiredUsd,
      readyUsd: readyUsd,
      auth: UserGrantAuthorization(grant),
      fundUsd: fundUsd,
      entrySource: widget.source,
      marketKind: _prefundKind?.name,
    );
  }

  /// The legs a funding of [fundUsd] takes (Dollars first, then the
  /// Investing cash), less what an earlier try of [moveId] already sent
  /// straight here. Moves nothing; null when it cannot be read.
  Future<VenueCashPlan?> _planVenueCashLegs(double fundUsd,
      {String? moveId}) async {
    try {
      final earlier = moveId == null ? null : MultiSourceMoveStore.get(moveId);
      return await _venueCashPuller
          .plan(
            neededUsd: max(0.0, fundUsd - (earlier?.directDeliveredUsd ?? 0)),
            exclude: OneBalanceVenue.predictions,
            destination: VenueCashDestination.predictions,
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      return null;
    }
  }

  /// The armed approval went: the armed bet leaves the pending provider
  /// (which drops its grant). Deferred: it may run from dispose.
  void _dropArmedBet() {
    final notifier = _pendingNotifier;
    if (_disposing) {
      scheduleMicrotask(notifier.dropArmed);
    } else {
      notifier.dropArmed();
    }
  }

  /// Set in dispose, where providers must not be changed synchronously.
  bool _disposing = false;

  /// Whether this market can take a funded bet (audit P1-5): it takes
  /// orders, by the CLOB's own word, and a short round has not ended. One
  /// that may end before the money lands is funded all the same: the
  /// autofire places nothing on a round that ended or a price past the
  /// approval, and the slip's Retry opens the series' round in play
  /// (founder, 23 October 2026). [requireRead]: an unread market blocks
  /// too.
  Future<PredictionsFundingBlock?> _fundingWindow(
          {required bool requireRead}) async =>
      _fundingBlockFor(await _readMarketWindow(), requireRead: requireRead);

  /// The CLOB's word on this slip's market, or null when unread.
  Future<PolymarketMarketWindow?> _readMarketWindow() async {
    final conditionId = widget.outcomes[_selectedIndex].conditionId;
    if (conditionId == null || conditionId.isEmpty) return null;
    try {
      return await _marketWindowReader(conditionId);
    } catch (_) {
      return null;
    }
  }

  PredictionsFundingBlock? _fundingBlockFor(PolymarketMarketWindow? market,
          {required bool requireRead}) =>
      predictionsFundingBlock(
        market: market,
        endAt: widget.marketEndAt,
        fastRound: isPolymarketFastRound(
            slug: widget.marketSlug,
            question: widget.marketQuestion,
            endAt: widget.marketEndAt),
        requireRead: requireRead,
      );

  /// Says why nothing was funded: the market is over.
  void _showFundingBlock(PredictionsFundingBlock block) {
    _stopped('market_ended');
    PolymarketPlacementDiagnostics.declined('market_${block.name}');
    PolymarketPlacementTimeline.finish('declined',
        reason: 'market_${block.name}');
    if (!mounted) return;
    showMessageSnackBar(
      context: context,
      message: context.l10n.builderMarketGone,
      error: true,
    );
  }

  /// Confirm on a slip whose bet was got ready: queued behind the money
  /// with no second prompt (or the bet's own one prompt when the slip
  /// changed past what was approved). False when nothing was got ready:
  /// Confirm then runs as before.
  Future<bool> _confirmPrefunded(BetPrefund prefund,
      {required double balance,
      required String mode,
      required String outcomeLabel}) async {
    if (await _refuseBlockedDeposit() != null) {
      _stopped('insufficient_balance');
      PolymarketPlacementDiagnostics.declined('deposit_blocked');
      PolymarketPlacementTimeline.finish('declined',
          reason: 'deposit_blocked');
      return true;
    }
    final result = await prefund.confirm(_prefundSnapshot());
    switch (result) {
      case PrefundNotUsed():
        return false;
      case PrefundQueued(:final intent, :final fundUsd):
        // The autofire places it the moment the money lands (at once when
        // it already has), under the approval already given.
        String? fundedId;
        if (fundUsd > 0) {
          // Money moved for it: its steps from here to the end, named on
          // the header by the moves' rows.
          final runner = ref.read(bitcoinFundedOrderRunnerProvider);
          fundedId = runner.beginFunded(_fundedLabel(intent, outcomeLabel));
        }
        // Publish one fully bound intent: readiness must never start for
        // an unbound version whose identity changes during its first read.
        _pendingNotifier.setIntent(intent.copyWith(fundedRunId: fundedId));
        PolymarketPlacementTimeline.mark('funded');
        if (fundedId != null) {
          ref.read(bitcoinFundedOrderRunnerProvider)
              .followFunded(fundedId, rowIds: prefund.rowIds);
        }
        if (!mounted) return true;
        _swapNeeded = fundUsd > 0;
        TrackingService.track('bet_slip_place', params: {
          'amount_bucket': TrackingService.usdBucket(_amount),
          ...TrackingService.exactUsd('amount_usd', _amount),
          'mode': mode,
          'swap_needed': _swapNeeded ? 1 : 0,
          'balance_bucket': TrackingService.usdBucket(balance),
          ...TrackingService.exactUsd('balance_usd', balance),
          'market': _truncMarket(widget.marketQuestion),
          'outcome': outcomeLabel,
        });
        _orderPlaced = true;
        _trackSubmitted();
        _updateState(() {
          _isPlacing = true;
          _placedSuccess = false;
        });
        return true;
      case PrefundDeclined():
        PolymarketPlacementTimeline.finish('declined',
            reason: _lastDeclineReason ?? 'approval');
        return true;
      case PrefundBlocked(:final block):
        _pendingNotifier.dropArmed();
        _showFundingBlock(block);
        return true;
      case PrefundFundingFailed(:final outcome):
        final armed = ref.read(pendingPolymarketBetProvider);
        _pendingNotifier.dropArmed();
        _stopped('funding_refused',
            error: outcome is OrderFundingRefused ? outcome.error : null);
        PolymarketPlacementTimeline.finish('failed', reason: 'funding_prefund');
        if (!mounted) return true;
        if (outcome is OrderFundingRefused) {
          final error = outcome.error;
          if (error is AuthGrantException) {
            await handleGrantFailure(context, error,
                action: SensitiveAction.pmBet);
            return true;
          }
          if (outcome.reason == 'user_cancelled') return true;
          // The move step failed: said in the steps, with the money in
          // Investments.
          final label = armed ?? _slipIntent();
          if (label != null) {
            final runner = ref.read(bitcoinFundedOrderRunnerProvider);
            final id = runner.beginFunded(_fundedLabel(label, outcomeLabel));
            runner.stopFunded(id,
                reason: 'venue_refused',
                message: (error == null
                        ? null
                        : HotSettlement.messageFor(error, context.l10n)) ??
                    context.l10n.betActionNotCompleted);
          }
        } else if (outcome is OrderFundingNeedsDollars) {
          final terms = ref
                  .read(polymarketFeeTermsProvider(
                      widget.outcomes[_selectedIndex].tokenId ?? ''))
                  .valueOrNull ??
              PolymarketFeeTerms.worstCase;
          await _openDollarsTopUp(
              shortfallUsd: _predictionsShortfall(balance, terms),
              requiredUsd: _predictionsRequired(terms),
              readyUsd: _predictionsReady(balance),
              topUpUsd: _fundingPlan?.fundUsd);
        }
        return true;
    }
  }

  void _updateState(VoidCallback update) {
    setState(update);
    _draft.changed();
  }

  Future<void> _openAdvanced() async {
    if (_openingAdvanced ||
        _isPlacing ||
        _buyInFlight ||
        _draft.ledgerBusy ||
        _draft.ledgerPending) {
      return;
    }
    // Withheld Advanced opens nothing; the shared sheet says why.
    if (!advancedTradingOffered(
        context, ref.read(runtimeCapabilitiesProvider))) {
      return;
    }
    _openingAdvanced = true;
    FocusManager.instance.primaryFocus?.unfocus();
    HapticFeedback.selectionClick();
    _trackStep('advanced');
    try {
      await Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute(
          fullscreenDialog: true,
          settings: const RouteSettings(name: BetSlipSheet.routeName),
          builder: (_) => BetSlipSheet._advanced(widget, _draft),
        ),
      );
    } finally {
      _openingAdvanced = false;
      // Back from Advanced discards what was set there: the plain slip is
      // always a plain market prediction (owner decision). Limit orders
      // are placed from the Advanced page itself.
      if (mounted) _resetAdvancedDraft();
    }
  }

  /// Returns every Advanced-only setting to the slip's opening state; the
  /// side, amount and outcome stay as they were.
  void _resetAdvancedDraft() {
    _updateState(() {
      _draft.isLimitMode = false;
      _draft.limitPrice = 0;
      _draft.limitSideKey = null;
      _draft.slippageChoice = null;
    });
  }

  void _onAmountChanged() {
    // Fiat entry → the typed value is in the user's local fiat
    // (USD/EUR/GBP/…). Translate to USDC via the local helper which
    // computes FX from `settings.currency` directly, ignoring
    // `btcFormat`.
    final parsed = double.tryParse(_amountController.text) ?? 0.0;
    final usdc = _fiatToUsdc(parsed);
    if (!_fillingAmount) {
      _draft.amountMethod = 'keypad';
      _spendAllBudgetUsd = null;
    }
    // The keypad writes the raw typed string, so a keystroke that leaves
    // the parsed value alone ('10' -> '10.' -> '10.0') still has to
    // repaint the big figure. Always rebuild, only assign when it moved.
    _updateState(() {
      if (usdc != _amount) _amount = usdc;
    });
    _maybeTrackAmountEntered();
  }

  /// Fire `polymarketBetAmountEntered` once, the first time the user
  /// enters a positive amount. Guarded by `_amountEnteredTracked` so
  /// it never repeats on subsequent keystrokes. marketId follows the
  /// slip's convention of using the (public) market question.
  void _maybeTrackAmountEntered() {
    if (_amountEnteredTracked || _amount <= 0) return;
    _amountEnteredTracked = true;
    TrackingService.polymarketBetAmountEntered(
      marketId: widget.marketQuestion,
    );
  }

  /// Fire `polymarketOutcomeChipTapped` from every outcome-selection
  /// site (binary toggle, candidate rows, Over/Under pills). Lives in
  /// onTap handlers (never build()), so each call maps to a real user
  /// tap — no rebuild dedupe needed.
  void _trackOutcomeChip(String outcome) {
    TrackingService.polymarketOutcomeChipTapped(
      marketId: widget.marketQuestion,
      outcome: outcome,
    );
  }

  // ── Analytics: flow + inputs ────────────────────────────────────────

  bool _fillingAmount = false;

  /// The spendable cash when Max was tapped, kept until the amount is
  /// edited. It rides the pending bet so preparation re-sizes the stake
  /// against the executable best ask (see `PendingBetIntent`).
  double? _spendAllBudgetUsd;

  /// The price Max sized its fee reserve at, which the Deposit-door check
  /// below uses too so a Max stake never reads as unaffordable.
  double? _maxFeePrice;
  String get _settingsScope => 'bet_slip_${identityHashCode(_draft)}';

  String? get _selectedTokenId => polymarketSelectedTokenId(
      widget.outcomes, _selectedIndex,
      buyNo: _isCandidatePicker && _buyNo);

  String get _outcomeSide {
    if (_isBinary) return _selectedIndex == _positiveIndex ? 'yes' : 'no';
    if (_isCandidatePicker) return _buyNo ? 'no' : 'yes';
    return 'multi';
  }

  /// What the person has entered so far. No ref reads: also used from
  /// dispose.
  Map<String, Object> _slipInputs() {
    final hasOutcome =
        _selectedIndex >= 0 && _selectedIndex < widget.outcomes.length;
    return {
      'venue': 'polymarket',
      'entry_source': widget.source,
      'wallet_kind': _isLedger ? 'ledger' : 'hot',
      'funding_source': 'venue_balance',
      'smart_funding': false,
      ...TrackingService.moneyParams(
          amountUsd: _amount, asset: 'usdc', amount: _amount),
      'amount_method': _draft.amountMethod,
      'order_type': _isLimitMode ? 'limit' : 'market',
      if (_isLimitMode && _limitPrice > 0)
        'limit_price': (_limitPrice * 10000).round() / 10000,
      if (!_isLimitMode) 'slippage_bps': VenueAnalytics.bps(_slippagePct),
      'advanced_used': _usesAdvanced,
      'outcome_side': _outcomeSide,
      if (hasOutcome)
        'market_outcome': widget.outcomes[_selectedIndex].name.toLowerCase(),
      'bet_type': polymarketMarketType(widget.marketQuestion,
          outcome: hasOutcome ? widget.outcomes[_selectedIndex].name : null),
      if (widget.marketSlug != null) 'market_slug': widget.marketSlug!,
    };
  }

  Map<String, Object> _kindParams() => VenueAnalytics.pmKindParams([
        _selectedTokenId,
        if (_selectedIndex >= 0 && _selectedIndex < widget.outcomes.length)
          widget.outcomes[_selectedIndex].conditionId,
        widget.marketSlug,
      ], fallbackCategory: widget.marketCategory);

  /// Every policy gate this bet needs: opening predictions, plus the
  /// sports or politics gate when the market is one. The same list is
  /// checked when the slip opens and at the tap, for the spending wallet
  /// and for a Ledger alike.
  List<String> _betCapabilities() => polymarketBetCapabilities(
      _kindParams()['market_category'] as String?, const []);

  /// A real step transition: amount → advanced → review → approval →
  /// deposit | placing.
  void _trackStep(String step) {
    if (_draft.flowStep == step) return;
    _draft.flowStep = step;
    TrackingService.setFlowStep(step);
    TrackingService.track('polymarket_bet_step', params: {
      'step': step,
      ..._kindParams(),
      ..._slipInputs(),
    });
  }

  /// Why the ticket stopped short of an order (the abandon reason).
  void _stopped(String reason, {Object? error}) {
    _draft.stopReason = reason;
    if (error != null) {
      _draft.lastErrorCategory = TrackingService.errorCategory(error);
    }
  }

  /// The person committed: one polymarket_bet_submitted per order, and the
  /// ticket's settings staged so the placed / failed event carries them.
  void _trackSubmitted({Map<String, Object> extra = const {}}) {
    final inputs = _slipInputs();
    final token = _selectedTokenId;
    if (token != null) {
      VenueAnalytics.stage('pm', token, {
        for (final k in const [
          'entry_source',
          'funding_source',
          'smart_funding',
          'amount_method',
          'limit_price',
          'slippage_bps',
          'advanced_used',
          'outcome_side',
          'bet_type',
        ])
          if (inputs[k] != null) k: inputs[k]!,
      });
    }
    _draft.flowStep = 'submitted';
    TrackingService.setFlowStep('submitted');
    TrackingService.track('polymarket_bet_submitted', params: {
      ..._kindParams(),
      ...inputs,
      'time_in_flow_ms':
          DateTime.now().difference(_draft.openedAt).inMilliseconds,
      'time_in_flow_bucket': VenueAnalytics.timeInFlowBucket(
          DateTime.now().difference(_draft.openedAt)),
      ...extra,
    });
  }

  /// Always renders a USD amount in the user's chosen `settings.currency`,
  /// even when btcFormat is sats. Used for the sats-mode payout companion
  /// line where the primary already shows sats and the secondary must be
  /// the fiat equivalent (never another sats echo).
  String _fiatCompanion(double usdAmount) {
    final settings = ref.read(settingsProvider);
    final currency = settings.currency;
    if (currency == 'USD') {
      return NumberFormat.simpleCurrency(name: 'USD', decimalDigits: 2)
          .format(usdAmount);
    }
    final rate = ref.read(selectedCurrencyProviderFromUSD(currency)).toDouble();
    if (rate <= 0) {
      return NumberFormat.simpleCurrency(name: 'USD', decimalDigits: 2)
          .format(usdAmount);
    }
    return NumberFormat.simpleCurrency(name: currency, decimalDigits: 2)
        .format(usdAmount * rate);
  }

  /// USDC → user's local fiat. Always returns a value in the user's
  /// `settings.currency` regardless of `btcFormat`. We can NOT use
  /// `polyInputFromUsd` here because that helper routes by btcFormat
  /// and would return sats when btcFormat=sats — wrong for every
  /// fiat-mode callsite inside the bet slip (input seed, chip add,
  /// toggle restore, `_onAmountChanged` parse-back).
  double _usdcToFiat(double usdc) {
    final settings = ref.read(settingsProvider);
    if (settings.currency == 'USD') return usdc;
    final rate =
        ref.read(selectedCurrencyProviderFromUSD(settings.currency)).toDouble();
    return rate > 0 ? usdc * rate : usdc;
  }

  /// Reverse of [_usdcToFiat]. Used when reading the controller text
  /// (typed in fiat) and converting back to internal USDC.
  double _fiatToUsdc(double fiat) {
    final settings = ref.read(settingsProvider);
    if (settings.currency == 'USD') return fiat;
    final rate =
        ref.read(selectedCurrencyProviderFromUSD(settings.currency)).toDouble();
    return rate > 0 ? fiat / rate : fiat;
  }

  /// Switch between USDC and BTC entry. Carries the current `_amount` across
  /// modes — flipping to BTC converts USDC → sats via the live rate, flipping
  /// back converts sats → USDC. If the rate is unavailable we no-op the
  /// switch so the user can't end up entering sats with a zero rate.

  @override
  void dispose() {
    if (!widget._advanced) {
      RegionFreshness.answers.removeListener(_onRegionAnswers);
    }
    // Abandonment funnel signal — fires only when the user dismissed
    // the slip without proceeding to place an order. We pass the
    // market question as `market_id` (truncated to 80 chars by the
    // service) since BetSlipSheet doesn't carry a true marketId; the
    // question is already public-facing on Polymarket so this is
    // analytics-safe. `had_amount` / `had_outcome_selected` give the
    // dashboard a 4-way breakdown of abandonment shape (no amount,
    // no outcome, partial, full-intent).
    if (_ownsDraft && !_orderPlaced) {
      try {
        TrackingService.betSlipAbandoned(
          marketId: widget.marketQuestion,
          hadAmount: _amount > 0,
          hadOutcomeSelected: widget.outcomes.isNotEmpty,
          extra: {
            ..._slipInputs(),
            'step': _draft.flowStep,
            'reason': _draft.stopReason ?? 'user_closed',
            if (_draft.lastErrorCategory != null)
              'last_error_category': _draft.lastErrorCategory!,
            'time_in_flow_ms':
                DateTime.now().difference(_draft.openedAt).inMilliseconds,
            'time_in_flow_bucket': VenueAnalytics.timeInFlowBucket(
                DateTime.now().difference(_draft.openedAt)),
          },
        );
      } catch (_) {}
    }
    if (_ownsDraft) {
      TrackingService.clearFlowContext('polymarket_bet');
      VenueAnalytics.resetSettings(_settingsScope);
      // Closed before Confirm: the approval goes, cash already moved stays
      // on Predictions (one balance), nothing comes back.
      _disposing = true;
      _draft.prefund?.close();
    }
    _ownSparkWarm?.close();
    _ownSparkWarm = null;
    // Release the live-feed hold exactly once (nulled to guard a double
    // dispose from decrementing another surface's hold).
    _livePrices?.release();
    _livePrices = null;
    _warmedSlip?.releaseSlip();
    _warmedSlip = null;
    _draft.removeListener(_onDraftChanged);
    if (_ownsDraft) {
      _amountController.removeListener(_onAmountChanged);
      _draft.dispose();
    }
    super.dispose();
  }

  Color _colorForOutcome(int index) {
    // An outcome with a line on the chart wears its line's colour (its
    // Yes; a candidate's No stays red).
    final colors = widget.outcomeColors;
    final line = colors != null && index >= 0 && index < colors.length
        ? colors[index]
        : null;
    if (line != null && !(_isCandidatePicker && _buyNo)) {
      return polyOutcomeFill(line);
    }
    if (_isBinary) {
      // First leg = positive side (green), second = negative (red). The
      // labels can be anything (Yes/No, Day/Night, Even/Odd, …) — we
      // colour by structural role, not name.
      return index == _positiveIndex ? _kPolyGreen : _kPolyRed;
    }
    if (_isCandidatePicker) {
      return _buyNo ? _kPolyRed : _kPolyGreen;
    }
    return _kPolyPurple;
  }

  /// Until the REST book is prepared, show an estimate at the selected
  /// slippage. Preparation and signing use the same executable price cap.
  /// A resting limit or custom slippage is Advanced. While the policy
  /// withholds Advanced the page does not open (the tap shows the shared
  /// sheet); if it is withdrawn while the page is open, the slip cannot
  /// place until the order is back to a plain market buy.
  /// A picked slippage other than 5% is Advanced; the market's own wider
  /// default on a short crypto round is not.
  bool get _usesAdvanced =>
      _isLimitMode ||
      (_draft.slippageChoice ?? kPolymarketDefaultSlippagePct) !=
          kPolymarketDefaultSlippagePct;

  String? get _advancedBlock => _usesAdvanced
      ? ref.watch(runtimeCapabilitiesProvider).blockReason('trading.advanced')
      : null;

  /// Why the Deposit door is shut, or null while `polymarket.deposit` is
  /// allowed. Watched, so the door follows the admin switch live.
  String? get _depositBlock =>
      ref.watch(runtimeCapabilitiesProvider).blockReason('polymarket.deposit');

  /// The slip's Deposit door. While the policy withholds
  /// `polymarket.deposit` it stays listed, disabled, wearing its reason
  /// ([CapabilityBlockNote]), and never opens a deposit.
  Widget _depositDoor(
      {required bool busy,
      required bool enabled,
      required VoidCallback onTap,
      String? busyLabel,
      String? label}) {
    final block = _depositBlock;
    // Funding a bet that cannot be placed here would only strand the
    // money, so the door shuts with the open gate too.
    final shut = block != null || _tradeBlock != null;
    final door = PolySlipCta(
      key: const ValueKey('bet-slip-deposit-door'),
      // Deposit door: dark primary fill per the CTA grammar (directional
      // color stays reserved for the actual Predict confirm), and on the
      // tinted sheet a label that contrasts with it, never the side colour.
      color: context.ctaFill,
      neutral: true,
      isBusy: !shut && busy,
      busyLabel: busyLabel,
      enabled: !shut && enabled,
      onTap: onTap,
      label: label ?? context.l10n.depositToPredict,
    );
    // When new bets are shut, that note already sits above the action and
    // explains why nothing here can start. A deposit refusal is not said a
    // second time, even when the venue and the policy word it differently.
    if (block == null || _tradeBlock != null) return door;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [CapabilityBlockNote(block), door],
    );
  }

  /// Null when a deposit into Predictions may start; otherwise the reason,
  /// already shown to the user. Read at tap time, not watched: a refusal
  /// is asked again before it is shown ([confirmCapability]).
  Future<String?> _refuseBlockedDeposit() async {
    final decision = await confirmCapability(
        ref.read(runtimeCapabilitiesProvider), 'polymarket.deposit');
    if (decision.allowed && !decision.comingSoon) return null;
    if (mounted) unawaited(showCapabilityDecisionSheet(context, decision));
    return decision.message;
  }

  /// The price cap shown before the book is read: the quote's own rule
  /// (polymarketBuyCap, one tick of room at least) at the market's likely
  /// increment. Once prepared the quote's maxPrice is shown instead.
  double _orderPriceFor(double marketPrice) {
    final price = marketPrice.clamp(0.0001, 0.9999).toDouble();
    return polymarketBuyCap(
        ask: price,
        slippagePct: _slippagePct,
        tick: polymarketEstimatedTick(price));
  }

  /// Conservative share count: floors `_amount / orderPrice` to 2 decimals so
  /// the max USDC the CLOB will pull (`shares * orderPrice`) stays ≤ `_amount`.
  /// This is the key fix — the previous code divided by `bestAsk` instead of
  /// `orderPrice`, which silently overcharged by up to the slippage %.
  double _sharesFor(double orderPrice) {
    if (orderPrice <= 0 || _amount <= 0) return 0;
    final raw = _amount / orderPrice;
    return (raw * 100).floorToDouble() / 100;
  }

  /// Effective floor for THIS market: the venue's own order floor,
  /// raised when the CLOB's per-market minimum order size (shares × the
  /// price being paid) demands more, otherwise the CLOB rejects with a
  /// raw "Size lower than the minimum" after the user already confirmed.
  double get _effectiveMinBetUsd {
    // The Ledger target validates fresh public market rules before review.
    // This older warmup provider requires the software account.
    if (_isLedger) return _kMinBetUsd;
    var minBetUsd = _kMinBetUsd;
    final selCid = widget.outcomes[_selectedIndex].conditionId;
    if (selCid != null && selCid.isNotEmpty) {
      final minShares =
          ref.read(polymarketMinOrderSizeProvider(selCid)).valueOrNull;
      final px = _isLimitMode && _limitPrice > 0
          ? _limitPrice
          : widget.outcomes[_selectedIndex].price;
      if (minShares != null && minShares > 0 && px > 0) {
        final marketMin = (minShares * px * 100).ceilToDouble() / 100;
        if (marketMin > minBetUsd) minBetUsd = marketMin;
      }
    }
    return minBetUsd;
  }

  double _binaryYesPrice(LivePriceState livePrices) {
    final pos = widget.outcomes[_positiveIndex];
    final neg = widget.outcomes[_negativeIndex];
    final posLp = pos.tokenId != null ? livePrices.prices[pos.tokenId] : null;
    final negLp = neg.tokenId != null ? livePrices.prices[neg.tokenId] : null;
    bool isProb(double? v) => v != null && v > 0 && v < 1;
    double canonicalYes;
    if (isProb(posLp)) {
      canonicalYes = posLp!;
    } else if (isProb(negLp)) {
      canonicalYes = 1.0 - negLp!;
    } else if (isProb(pos.price)) {
      canonicalYes = pos.price;
    } else if (isProb(neg.price)) {
      canonicalYes = 1.0 - neg.price;
    } else {
      canonicalYes = pos.price;
    }
    canonicalYes = canonicalYes.clamp(0.0, 1.0).toDouble();
    return canonicalYes;
  }

  double _ledgerDisplayedPrice(LivePriceState prices) {
    if (_isBinary) {
      final yes = _binaryYesPrice(prices);
      return _selectedIndex == _positiveIndex ? yes : 1 - yes;
    }
    final selected = widget.outcomes[_selectedIndex];
    final yes = prices.prices[selected.tokenId] ?? selected.price;
    return _isCandidatePicker && _buyNo ? (1 - yes).clamp(0.0, 1.0) : yes;
  }

  Future<void> _handleLedgerBuy() async {
    final walletId = widget.ledgerWalletId;
    if (walletId == null || _draft.ledgerBusy || _draft.ledgerPending) return;
    final pending = ref.read(ledgerPmPendingBetProvider(walletId));
    if (pending.isLoading || pending.hasError || pending.valueOrNull != false) {
      return;
    }
    final selected = widget.outcomes[_selectedIndex];
    final tokenId =
        _isCandidatePicker && _buyNo ? selected.noTokenId : selected.tokenId;
    final conditionId = selected.conditionId;
    final amount = _amount;
    final marketQuestion = widget.marketQuestion;
    final marketEndAt = widget.marketEndAt;
    if (!amount.isFinite || amount < _effectiveMinBetUsd) return;
    if (tokenId == null ||
        tokenId.isEmpty ||
        conditionId == null ||
        conditionId.isEmpty) {
      showMessageSnackBar(
        context: context,
        message: context.l10n.outcomeNotAvailable,
        error: true,
      );
      return;
    }
    final prices = ref.read(livePriceProvider);
    final reviewedPrice =
        _isLimitMode ? _limitPrice : _ledgerDisplayedPrice(prices);
    final isLimit = _isLimitMode;
    final slippage = _slippagePct;
    final outcomeLabel = _isCandidatePicker
        ? '${selected.name} ${_buyNo ? "No" : "Yes"}'
        : selected.name;
    FocusManager.instance.primaryFocus?.unfocus();
    _updateState(() {
      _draft.ledgerBusy = true;
      _draft.ledgerRetryPrice = null;
    });
    TrackingService.track(
      'ledger_prediction_review_opened',
      params: {
        'amount_bucket': TrackingService.usdBucket(amount),
        ...TrackingService.exactUsd('amount_usd', amount),
        'order_type': isLimit ? 'limit' : 'market',
      },
    );
    _trackStep('review');
    try {
      if (await checkPolymarketGeoblock(context,
              capabilities: _betCapabilities()) ||
          !mounted) {
        _stopped('geoblocked');
        return;
      }
      // The same last check as the spending wallet's, before the device
      // is asked to sign.
      if (!_orderMatchesSelection(tokenId)) {
        showMessageSnackBar(
          context: context,
          message: context.l10n.betSideMismatchStopped,
          error: true,
        );
        return;
      }
      _trackStep('approval');
      final outcome = await showLedgerPredictionApproval(
        context,
        ref,
        walletId: walletId,
        tokenId: tokenId,
        conditionId: conditionId,
        amountUsd: amount,
        reviewedPrice: reviewedPrice,
        isLimit: isLimit,
        slippagePct: slippage,
        marketQuestion: marketQuestion,
        outcomeLabel: outcomeLabel,
        marketEndAt: marketEndAt,
        onPriceMoved: (retry) => _draft.ledgerRetryPrice = retry,
      );
      switch (outcome) {
        case LedgerPmBetOutcome.submitted:
          _trackSubmitted();
          VenueAnalytics.forgetLedgerPendingBet(walletId);
          _trackLedgerBetSubmitted(
            tokenId: tokenId,
            amount: amount,
            price: reviewedPrice,
            isLimit: isLimit,
            outcomeName: outcomeLabel,
          );
        case LedgerPmBetOutcome.pending:
          // Sent to the device; the later status check reports it once.
          _trackSubmitted();
          VenueAnalytics.rememberLedgerPendingBet(walletId, {
            'token_id': tokenId,
            'amount': amount,
            'price': reviewedPrice,
            'is_limit': isLimit,
            'outcome': outcomeLabel,
            'category': widget.marketCategory,
            'market_question': widget.marketQuestion,
            'market_slug': widget.marketSlug,
            'entry_source': widget.source,
          });
        case LedgerPmBetOutcome.cancelled:
          _stopped('signing_declined');
        case LedgerPmBetOutcome.failed:
          _stopped('ledger_failed');
        case LedgerPmBetOutcome.prepared:
        case LedgerPmBetOutcome.resolved:
          break;
      }
      if (!mounted) return;
      ref.invalidate(ledgerPmBuyingPowerProvider(walletId));
      ref.invalidate(ledgerPmPendingBetProvider(walletId));
      _handleLedgerOutcome(outcome);
    } finally {
      if (mounted) _updateState(() => _draft.ledgerBusy = false);
    }
  }

  /// Puts Ledger bets in the same polymarket_* funnels as hot-wallet bets,
  /// tagged wallet_kind 'ledger'. Mirrors the hot path's split: a market
  /// order is a placed bet; a resting limit order is
  /// polymarket_limit_order_placed until it fills.
  ///
  /// No backend provider event from here: the slip never sees the Ledger
  /// order hash, so it could only log a synthetic id, and the backend
  /// already creates the row keyed by the real hash from the builder fill
  /// (backfillPolymarketEarnings). Both would be two rows for one bet.
  void _trackLedgerBetSubmitted({
    required String tokenId,
    required double amount,
    required double price,
    required bool isLimit,
    required String outcomeName,
    Map<String, Object>? extra,
  }) {
    if (isLimit) {
      TrackingService.track('polymarket_limit_order_placed', params: {
        'wallet_kind': 'ledger',
        'amount_bucket': TrackingService.usdBucket(amount),
        ...TrackingService.exactUsd('amount_usd', amount),
        if (widget.marketCategory != null)
          'category': widget.marketCategory!.toLowerCase(),
      });
      return;
    }
    final shares = price > 0 ? (amount / price).round() : 0;
    TrackingService.polymarketBetPlaced(
      marketId: tokenId,
      outcome: 'buy',
      amount: amount,
      price: price,
      shares: shares,
      category: widget.marketCategory,
      marketTitle: widget.marketQuestion,
      betType:
          polymarketMarketType(widget.marketQuestion, outcome: outcomeName),
      side: 'buy',
      orderType: 'market',
      entrySource: widget.source,
      walletKind: 'ledger',
      marketOutcome: outcomeName,
      marketSlug: widget.marketSlug,
      logAffiliateEvent: false,
      extra: extra,
    );
  }

  /// A "check status" that confirms the bet sent to the device earlier:
  /// report the placed bet once, from what was entered at submit.
  void _reportLedgerBetConfirmed(String walletId) {
    final bet = VenueAnalytics.takeLedgerPendingBet(walletId);
    if (bet == null) return;
    final tokenId = bet['token_id'] as String? ?? '';
    final amount = (bet['amount'] as num?)?.toDouble() ?? 0;
    final price = (bet['price'] as num?)?.toDouble() ?? 0;
    final isLimit = bet['is_limit'] == true;
    final outcome = bet['outcome'] as String? ?? '';
    if (tokenId.isEmpty || amount <= 0) return;
    if (isLimit) {
      TrackingService.track('polymarket_limit_order_placed', params: {
        'wallet_kind': 'ledger',
        'amount_bucket': TrackingService.usdBucket(amount),
        ...TrackingService.exactUsd('amount_usd', amount),
        'confirmed_via': 'status_check',
        if (bet['category'] is String)
          'category': (bet['category'] as String).toLowerCase(),
      });
      return;
    }
    final shares = price > 0 ? (amount / price).round() : 0;
    TrackingService.polymarketBetPlaced(
      marketId: tokenId,
      outcome: 'buy',
      amount: amount,
      price: price,
      shares: shares,
      category: bet['category'] as String?,
      marketTitle: bet['market_question'] as String?,
      betType: polymarketMarketType(bet['market_question'] as String? ?? '',
          outcome: outcome),
      side: 'buy',
      orderType: 'market',
      entrySource: bet['entry_source'] as String?,
      walletKind: 'ledger',
      marketOutcome: outcome,
      marketSlug: bet['market_slug'] as String?,
      logAffiliateEvent: false,
      extra: const {'confirmed_via': 'status_check'},
    );
  }

  Future<void> _checkLedgerPrediction() async {
    if (_usesAdvanced) {
      await RuntimeCapabilitiesService.instance
          .ensureAllowed('trading.advanced');
    }
    final walletId = widget.ledgerWalletId;
    if (walletId == null || _draft.ledgerBusy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _updateState(() => _draft.ledgerBusy = true);
    TrackingService.track('ledger_prediction_status_checked');
    try {
      final outcome = await checkLedgerPredictionStatus(
        context,
        ref,
        walletId: walletId,
      );
      if (outcome == LedgerPmBetOutcome.submitted) {
        _reportLedgerBetConfirmed(walletId);
      } else if (outcome == LedgerPmBetOutcome.resolved) {
        VenueAnalytics.forgetLedgerPendingBet(walletId);
      }
      if (mounted) {
        ref.invalidate(ledgerPmBuyingPowerProvider(walletId));
        ref.invalidate(ledgerPmPendingBetProvider(walletId));
        _handleLedgerOutcome(outcome);
      }
    } finally {
      if (mounted) _updateState(() => _draft.ledgerBusy = false);
    }
  }

  void _handleLedgerOutcome(LedgerPmBetOutcome outcome) {
    switch (outcome) {
      case LedgerPmBetOutcome.submitted:
        _updateState(() {
          _orderPlaced = true;
          _draft.ledgerPending = false;
        });
        final message = context.l10n.ledgerBetSubmitted;
        final viewLabel = context.l10n.betViewPrediction;
        final ledgerWalletId = widget.ledgerWalletId;
        final navigator = Navigator.of(context, rootNavigator: true);
        BetSlipSheet.popAllSheetsDownToBetSlipHost(navigator);
        // Same door as the spending wallet: the confirmation opens the
        // prediction, which for a Ledger lives on that wallet's own
        // Predictions page, never the hot account's.
        pushKuteSuccessOverlay(
          navigator: navigator,
          overlay: KuteConfirmation(
            message: message,
            onDone: navigator.pop,
            secondaryButtonText: viewLabel,
            onSecondary: () {
              navigator.pop();
              if (ledgerWalletId != null) {
                LedgerPortfolioScreen.show(navigator.context,
                    walletId: ledgerWalletId,
                    product: InvestmentsProduct.predictions);
              }
            },
          ),
        );
      case LedgerPmBetOutcome.prepared:
        final navigator = Navigator.of(context, rootNavigator: true);
        pushKuteSuccessOverlay(
          navigator: navigator,
          overlay: KuteConfirmation(
            message: context.l10n.ledgerBetPrepared,
            onDone: navigator.pop,
          ),
        );
      case LedgerPmBetOutcome.pending:
        _stopped('pending_confirmation');
        _updateState(() => _draft.ledgerPending = true);
      case LedgerPmBetOutcome.resolved:
        _updateState(() => _draft.ledgerPending = false);
      case LedgerPmBetOutcome.cancelled:
      case LedgerPmBetOutcome.failed:
        // A failed status read cannot release an uncertain submission.
        break;
    }
  }

  Widget _buildLedgerPrimaryAction(AppColorsExtension c, Color selectedColor) {
    final walletId = widget.ledgerWalletId!;
    final pending = ref.watch(ledgerPmPendingBetProvider(walletId));
    if (_draft.ledgerPending || pending.valueOrNull == true) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.l10n.ledgerBetPending,
            style: TextStyle(color: c.textSecondary, fontSize: 14.sp),
          ),
          SizedBox(height: 12.h),
          PolySlipCta(
            color: context.ctaFill,
            neutral: true,
            isBusy: _draft.ledgerBusy,
            enabled: !_draft.ledgerBusy,
            onTap: _checkLedgerPrediction,
            label: context.l10n.ledgerBetCheckStatus,
          ),
        ],
      );
    }
    if (pending.hasError || pending.isLoading) {
      return PolySlipCta(
        color: context.ctaFill,
        neutral: true,
        isBusy: pending.isLoading,
        busyLabel: context.l10n.loadingAccount,
        enabled: !_draft.ledgerBusy && !pending.isLoading,
        onTap: () => ref.invalidate(ledgerPmPendingBetProvider(walletId)),
        label: pending.isLoading
            ? context.l10n.loadingAccount
            : context.l10n.retry,
      );
    }
    final buyingPower = ref.watch(ledgerPmBuyingPowerProvider(walletId));
    final verified = !buyingPower.isLoading && !buyingPower.hasError
        ? buyingPower.valueOrNull
        : null;
    if (buyingPower.hasError) {
      return PolySlipCta(
        color: context.ctaFill,
        neutral: true,
        isBusy: false,
        enabled: !_draft.ledgerBusy,
        onTap: () => ref.invalidate(ledgerPmBuyingPowerProvider(walletId)),
        label: context.l10n.retry,
      );
    }
    // Nothing to bet with, or not enough for this bet: the same door
    // Home offers, in the same words. The device is not named here,
    // because Home does not name a device either and this is meant to
    // be the same screen.
    final spendableUsd =
        verified == null ? null : verified.spendable.toDouble() / 1e6;
    final needsDeposit = spendableUsd != null &&
        (spendableUsd <= 0 ||
            (_amount.isFinite && _amount > spendableUsd + 1e-9));
    if (needsDeposit) {
      // Same door and same deposit rule as the spending account.
      return _depositDoor(
        busy: false,
        enabled: !_draft.ledgerBusy,
        onTap: _depositLedger,
      );
    }
    // Under the market's floor: the same minimum button the spending
    // account gets; a tap writes the minimum and places it when the
    // balance covers it ([_fillMinimum]).
    if (_belowMinimumStake && !buyingPower.isLoading) {
      return PolySlipCta(
        color: selectedColor,
        // Dark on the white button, never the side colour (founder).
        neutral: true,
        isBusy: _draft.ledgerBusy,
        enabled: !_draft.ledgerBusy &&
            _advancedBlock == null &&
            _tradeBlock == null,
        onTap: _fillMinimum,
        label: context.l10n
            .amountMinimumInline(_fiatCompanion(_effectiveMinBetUsd)),
      );
    }
    // Nothing typed yet: the button is the bet at the market's minimum,
    // and a tap opens its review. When the balance cannot cover it the
    // tap writes it and opens the deposit, as the door it then is would.
    if (_emptyStake && !buyingPower.isLoading) {
      final minStake = _minimumStakeUsd(_effectiveMinBetUsd);
      final covered =
          spendableUsd != null && minStake <= spendableUsd + 1e-9;
      return PolySlipCta(
        color: selectedColor,
        // Dark on the white button, never the side colour (founder).
        neutral: true,
        isBusy: _draft.ledgerBusy,
        enabled: !_draft.ledgerBusy &&
            _advancedBlock == null &&
            _tradeBlock == null,
        onTap: () {
          _placeMinimum(place: covered);
          if (!covered) _depositLedger();
        },
        label: _betCtaLabel(widget.outcomes[_selectedIndex], minStake,
            empty: true),
      );
    }
    // One button, like Home. The second deposit link underneath was a
    // Ledger-only extra and it made the sheet read as a different
    // screen from the one the spending account gets.
    return PolySlipCta(
      color: selectedColor,
      // Dark on the white button, never the side colour (founder).
      neutral: true,
      isBusy: _draft.ledgerBusy || buyingPower.isLoading,
      busyLabel: !_draft.ledgerBusy && buyingPower.isLoading
          ? context.l10n.loadingAccount
          : null,
      enabled: !_draft.ledgerBusy &&
          !buyingPower.isLoading &&
          _amount.isFinite &&
          _amount >= _effectiveMinBetUsd &&
          _advancedBlock == null &&
          _tradeBlock == null,
      onTap: _handleBuy,
      // Until the balance is known the button must not promise a review
      // the account may not be able to fund.
      label: buyingPower.isLoading
          ? context.l10n.loadingAccount
          : switch (_draft.ledgerRetryPrice) {
              final retry? =>
                context.l10n.betRetryAtPrice(polymarketCentsLabel(retry)),
              null => context.l10n.ledgerBetReviewTitle,
            },
    );
  }

  Future<void> _depositLedger() async {
    if (_draft.ledgerBusy || _draft.ledgerPending) return;
    if (await _refuseBlockedDeposit() != null || !mounted) return;
    final walletId = widget.ledgerWalletId!;
    FocusManager.instance.primaryFocus?.unfocus();
    _updateState(() => _draft.ledgerBusy = true);
    TrackingService.track('ledger_prediction_deposit_opened');
    _stopped('insufficient_balance');
    _trackStep('deposit');
    try {
      await showDepositSheet(
        context,
        ledgerWalletId: walletId,
        lockedSide: MoveLockedSide.depositToPredictions,
      );
      if (mounted) ref.invalidate(ledgerPmBuyingPowerProvider(walletId));
    } finally {
      if (mounted) _updateState(() => _draft.ledgerBusy = false);
    }
  }

  /// What the outcome on the slip is called on the bet ("Lula Yes").
  String get _outcomeLabel {
    final selected = widget.outcomes[_selectedIndex];
    return _isCandidatePicker
        ? '${selected.name} ${_buyNo ? "No" : "Yes"}'
        : selected.name;
  }

  /// The bet on the slip as a pending intent, before preparation; null
  /// when the selected outcome has no token.
  PendingBetIntent? _slipIntent() {
    final selected = widget.outcomes[_selectedIndex];
    final tokenId = _selectedTokenId;
    if (tokenId == null || tokenId.isEmpty) return null;
    // Display odds are a provisional estimate. Before approval, preparation
    // replaces them with the executable book price for this dollar amount.
    final livePrices = ref.read(livePriceProvider);
    final double displayFallback = _isCandidatePicker && _buyNo
        ? (1.0 - selected.price).clamp(0.0001, 0.9999)
        : selected.price;
    // Tick bounds, not a 1c/99c band — otherwise a sub-1% or >99% outcome is
    // priced (and sized) as if it were 1%/99%, mismatching the odds shown.
    final double expectedPrice =
        (livePrices.prices[tokenId] ?? displayFallback).clamp(0.0001, 0.9999);
    return PendingBetIntent(
      tokenId: tokenId,
      amount: _amount,
      slippagePct: _slippagePct,
      marketQuestion: widget.marketQuestion,
      marketImage: widget.marketImage,
      outcomeName: _outcomeLabel,
      // Limit mode resting price, else the live market price the user saw.
      expectedPrice:
          _isLimitMode && _limitPrice > 0 ? _limitPrice : expectedPrice,
      marketEndAt: widget.marketEndAt,
      marketCategory: widget.marketCategory,
      eventSlug: widget.marketSlug,
      isLimit: _isLimitMode,
      limitPrice: _isLimitMode ? _limitPrice.clamp(0.01, 0.99).toDouble() : 0.0,
      negRisk: widget.negRisk,
      entrySource: widget.source,
      spendAllBudgetUsd: _isLimitMode ? null : _spendAllBudgetUsd,
    );
  }

  Future<void> _handleBuy() async {
    if (_isLedger) {
      await _handleLedgerBuy();
      return;
    }
    // Re-entrancy guard. Blocks a second tap landing during the awaited
    // geoblock check (before `_isPlacing` flips) from starting a second
    // placement. Once `_isPlacing` is set the CTA and this guard both
    // keep further taps out.
    if (_buyInFlight || _isPlacing) return;
    // A new bet: nothing moved for it yet.
    _placedFundingFeeUsd = null;
    _updateState(() {
      _buyInFlight = true;
      _prepareFailed = false;
    });
    try {
      await _handleBuyInner();
    } finally {
      if (mounted) _updateState(() => _buyInFlight = false);
    }
  }

  Future<void> _handleBuyInner() async {
    PolymarketPlacementTimeline.begin();
    // A new try: an earlier funded bet's stop gives way to it.
    _clearFundedStop();
    _loadLiveDelay(widget.outcomes[_selectedIndex].conditionId);
    TrackingService.track('prediction_place_cta_tapped', params: {
      'amount_bucket': TrackingService.usdBucket(_amount),
      ...TrackingService.exactUsd('amount_usd', _amount),
      'denomination': 'fiat',
    });
    // Regional gate at place time. The slip is already gated on open, but
    // re-check here so a region change (or a slip left open) can't slip a
    // bet through — Polymarket isn't allowed where it's restricted. If
    // blocked, `checkPolymarketGeoblock` surfaces the "unavailable here"
    // sheet and we abort the placement.
    if (await checkPolymarketGeoblock(context,
        capabilities: _betCapabilities(),
        maxAge: const Duration(seconds: 60))) {
      _stopped('geoblocked');
      PolymarketPlacementDiagnostics.declined('region_or_policy');
      PolymarketPlacementTimeline.finish('declined',
          reason: 'region_or_policy');
      return;
    }
    PolymarketPlacementTimeline.mark('geoblock');
    if (!mounted) return;
    final tradingState = ref.read(polymarketTradingProvider);

    // If the provider is still loading, don't redirect — just wait
    if (tradingState.isLoading) {
      _stopped('account_loading');
      if (mounted) {
        showMessageSnackBar(
          context: context,
          message: context.l10n.loadingAccount,
          error: false,
        );
      }
      return;
    }

    // A balance that was not read is unknown, not $0.00: never decide a
    // shortfall (and a funding move from Dollars) on it. The button waits
    // in that state; this covers a tap that raced a failed read.
    if (!(tradingState.valueOrNull?.balanceKnown ?? false)) {
      _stopped('balance_unknown');
      if (mounted) {
        showMessageSnackBar(
          context: context,
          message: context.l10n.loadingAccount,
          error: false,
        );
      }
      return;
    }
    final balance = tradingState.valueOrNull?.usdcBalance ?? 0;

    if (_amount <= 0) {
      _stopped('no_amount');
      if (mounted) {
        showMessageSnackBar(
            context: context, message: context.l10n.enterAmount, error: true);
      }
      return;
    }
    final minBetUsd = _effectiveMinBetUsd;
    if (_amount < minBetUsd) {
      _stopped('below_minimum');
      if (mounted) {
        showMessageSnackBar(
          context: context,
          message: context.l10n.betMinimumBetIs(
              '\$${minBetUsd == minBetUsd.roundToDouble() ? minBetUsd.toStringAsFixed(0) : minBetUsd.toStringAsFixed(2)}'),
          error: true,
        );
      }
      return;
    }

    final selected = widget.outcomes[_selectedIndex];
    // For candidate-picker events each outcome carries its own YES and NO
    // token ids; pick the right one based on the Yes/No pill the user tapped.
    final tokenId =
        _isCandidatePicker && _buyNo ? selected.noTokenId : selected.tokenId;
    if (tokenId == null || tokenId.isEmpty) {
      _stopped('outcome_unavailable');
      if (mounted) {
        showMessageSnackBar(
          context: context,
          message: context.l10n.outcomeNotAvailable,
          error: true,
        );
      }
      return;
    }

    // Store the reviewed draft before funding or fresh approval.
    if (!mounted) return;
    final outcomeLabel = _outcomeLabel;
    TrackingService.track('bet_slip_open_picker', params: {
      // Exact amount and balance beside the legacy buckets. The market
      // question is truncated to keep the param bounded.
      'amount_bucket': TrackingService.usdBucket(_amount),
      ...TrackingService.exactUsd('amount_usd', _amount),
      'balance_bucket': TrackingService.usdBucket(balance),
      ...TrackingService.exactUsd('balance_usd', balance),
      'sufficient': (_amount <= balance) ? 1 : 0,
      'market': _truncMarket(widget.marketQuestion),
      'outcome': outcomeLabel,
    });
    // One bet queued behind its funding at a time (one approval slot): a
    // second tap must not overwrite the queued one, whose money is on its
    // way. And never while Predictions cash is on its way home: the stake
    // would be sized against cash that is leaving.
    final queued = ref.read(pendingPolymarketBetProvider);
    final sweeping = ref
        .read(venueSweeperProvider)
        .sweeping
        .contains(OneBalanceVenue.predictions);
    if ((queued != null && queued.funded && pendingBetHoldsCash(queued)) ||
        sweeping) {
      _stopped(sweeping ? 'venue_settling' : 'previous_order_pending');
      PolymarketPlacementDiagnostics.declined(
          sweeping ? 'venue_settling' : 'previous_order_pending');
      PolymarketPlacementTimeline.finish('declined',
          reason: sweeping ? 'venue_settling' : 'previous_order_pending');
      if (mounted) {
        showMessageSnackBar(
          context: context,
          message: sweeping
              ? context.l10n.betVenueSettling
              : context.l10n.ledgerBetPending,
          error: true,
        );
      }
      return;
    }
    // A fast market's bet got ready before Confirm: queued behind its
    // money under the approval already given, no second prompt.
    final prefund = _draft.prefund;
    if (prefund != null && prefund.engaged) {
      TrackingService.polymarketBetConfirmationShown(
        marketId: widget.marketQuestion,
        amountUsdc: _amount,
      );
      _trackStep('review');
      if (await _confirmPrefunded(prefund,
          balance: balance, mode: _resolveMode(), outcomeLabel: outcomeLabel)) {
        return;
      }
      if (!mounted) return;
    }
    ref.read(pendingPolymarketBetProvider.notifier).setIntent(_slipIntent()!);

    TrackingService.polymarketBetConfirmationShown(
      marketId: widget.marketQuestion,
      amountUsdc: _amount,
    );
    _trackStep('review');

    final mode = _resolveMode();
    // Predictions-funded orders require sufficient cash, the venue's fees
    // included (the same figure the button reads). Preserve the draft
    // while Deposit opens; returning still requires a fresh review.
    final terms =
        ref.read(polymarketFeeTermsProvider(selected.tokenId ?? '')).valueOrNull ??
            PolymarketFeeTerms.worstCase;
    final shortfall = _predictionsShortfall(balance, terms);
    if (shortfall > 0) {
      // One balance: the bet funds its shortfall from Dollars and queues
      // behind the credit, under one approval. Money this slip moved
      // before Confirm and still on its way (a pre-fund the slip left
      // for a limit order, or for a stake past what was approved) counts
      // as there: only the rest moves, never the same money twice.
      await _fundAndPlace(
          balance: balance,
          terms: terms,
          shortfallUsd: shortfall,
          mode: mode,
          outcomeLabel: outcomeLabel);
      return;
    }
    // Phase 1b.4: a fresh approval bound to the whole placement (the stake
    // cap, the worst ladder price and the order type) before anything is
    // signed. Declining leaves the slip as it was.
    final grant = await _approveBet();
    PolymarketPlacementTimeline.mark('approval');
    if (grant == null) {
      PolymarketPlacementTimeline.finish('declined',
          reason: _lastDeclineReason ?? 'approval');
      if (mounted &&
          ref.read(pendingPolymarketBetProvider)?.status !=
              PendingBetStatus.failed) {
        ref.read(pendingPolymarketBetProvider.notifier).clear();
      }
      return;
    }
    if (!mounted) {
      grant.revoke();
      return;
    }
    _swapNeeded = false;
    // Placement funnel — record the funding decision so we can see Smart
    // adoption, source mix, and how often a swap leg is involved.
    TrackingService.track('bet_slip_place', params: {
      'amount_bucket': TrackingService.usdBucket(_amount),
      ...TrackingService.exactUsd('amount_usd', _amount),
      'mode': mode,
      'swap_needed': _swapNeeded ? 1 : 0,
      'balance_bucket': TrackingService.usdBucket(balance),
      ...TrackingService.exactUsd('balance_usd', balance),
      'market': _truncMarket(widget.marketQuestion),
      'outcome': outcomeLabel,
    });
    _orderPlaced = true;
    _trackSubmitted();
    _updateState(() {
      _isPlacing = true;
      _placedSuccess = false;
    });
    // Run the engine inline. Progress is rendered from
    // `pendingPolymarketBetProvider`'s status by the placing panel; the
    // sheet stays open and locked until done/failed.
    unawaited(_runPlacement(mode, grant));
    return;
  }

  /// Phase 1b.4. Prompts for the pending bet's review intent. Null when the
  /// user declined or the account isn't ready (a message is shown).
  /// Why the last approval attempt ended without a grant, for the
  /// timeline's outcome. Null once a grant was issued.
  String? _lastDeclineReason;

  AuthGrant? _decline(String reason, {Object? error}) {
    _lastDeclineReason = reason;
    _stopped(
        switch (reason) {
          'prepare_failed' => 'quote_failed',
          'approval_not_granted' => 'signing_declined',
          _ => reason,
        },
        error: error);
    PolymarketPlacementDiagnostics.declined(reason, error: error);
    return null;
  }

  /// [funding] (one balance) asks for the ONE approval a funded bet
  /// needs: the bet review extended with the funding leg's cap and venue
  /// ([PmGrants.fundedBetReview]), issued as the autofire grant the queued
  /// bet fires on. No second prompt for the move.
  ///
  /// [prefund]: asked to get a fast market's bet ready before Confirm
  /// (`BetPrefund`). Its own reason line, and quiet: nothing on the slip
  /// or in the funnel changes when it cannot be asked (Confirm then runs
  /// as before).
  ///
  /// [directLegs]: the Investing cash planned to go straight into
  /// Predictions for a funded bet (`VenueLimit.directLegs`), bound into
  /// the same approval and carried on the queued bet so the autofire
  /// rebuilds exactly what was approved.
  Future<AuthGrant?> _approveBet(
      {OrderFundingPlan? funding,
      bool prefund = false,
      Map<String, Object?>? directLegs,
      Map<String, Object?>? btcLeg}) async {
    _lastDeclineReason = null;
    AuthGrant? decline(String reason, {Object? error}) {
      if (!prefund) return _decline(reason, error: error);
      _lastDeclineReason = reason;
      return null;
    }

    if (_usesAdvanced) {
      try {
        await RuntimeCapabilitiesService.instance
            .ensureAllowed('trading.advanced');
      } on CapabilityUnavailableException catch (e) {
        if (mounted && !prefund) {
          showMessageSnackBar(
              context: context, message: e.decision.message, error: true);
        }
        return decline('advanced_unavailable', error: e);
      }
    }
    var pending = ref.read(pendingPolymarketBetProvider);
    if (pending == null) return decline('no_intent');
    final controller = ref.read(polymarketBetControllerProvider);
    try {
      pending = await controller.prepareIntent(pending);
      PolymarketPlacementTimeline.mark('quote');
      // The book cannot fill this stake within the price cap: say what
      // does fill now instead of sending it to fill in part (or be
      // killed) after approval.
      final quote = pending.marketQuote;
      if (!pending.isLimit &&
          quote != null &&
          quote.fillableUsd + 1e-6 < pending.amount) {
        throw PolymarketThinBook(fillableUsd: quote.fillableUsd);
      }
    } catch (e) {
      final setup = e is PolymarketSetupIncomplete ? e : null;
      if (prefund) {
        decline('prepare_failed', error: e);
        return null;
      }
      _decline(
          setup == null
              ? (e is PolymarketThinBook || '$e'.contains('No liquidity')
                  ? 'liquidity_unavailable'
                  : 'prepare_failed')
              : setup.timedOut
                  ? 'setup_timeout'
                  : 'setup_failed',
          error: setup?.cause ?? e);
      if (!mounted) return null;
      final l10n = context.l10n;
      ref.read(pendingPolymarketBetProvider.notifier).updateStatus(
            PendingBetStatus.failed,
            errorMessage: setup != null
                ? (setup.timedOut ? l10n.betSetupSlow : l10n.betSetupFailed)
                : e is PolymarketThinBook
                    ? polymarketThinBookMessage(l10n, e)
                : e.toString().toLowerCase().contains('liquidity')
                    ? l10n.betBuyLiquidityUnavailable
                    : l10n.betConnectionUnavailable,
          );
      // Said on the slip with a Retry, not left as a stopped spinner.
      _updateState(() => _prepareFailed = true);
      return null;
    }
    if (!mounted) return null;
    final legs = funding != null ? directLegs : null;
    if (legs != null || pending.directLegs != null) {
      pending = pending.copyWith(
          status: pending.status,
          errorMessage: pending.errorMessage,
          retryMaxPrice: pending.retryMaxPrice,
          directLegs: legs);
    }
    // The Bitcoin leg this approval also covers, or none.
    final btc = funding != null ? btcLeg : null;
    if (btc != null || pending.btcLeg != null) {
      pending = pending.copyWith(
          status: pending.status,
          errorMessage: pending.errorMessage,
          retryMaxPrice: pending.retryMaxPrice,
          btcLeg: btc);
    }
    ref.read(pendingPolymarketBetProvider.notifier).setIntent(pending);
    // Setup (if it ran) is done: the busy label moves on from it.
    _updateState(() {});
    // A Max stake was re-fitted to the executable book; show the stake
    // that is about to be approved and placed.
    if (pending.spendAllBudgetUsd != null && pending.amount != _amount) {
      final display = _usdcToFiat(pending.amount);
      _fillingAmount = true;
      _amountController.text = display.toStringAsFixed(2);
      _fillingAmount = false;
      _updateState(() => _amount = pending!.amount);
    }
    // Render the executable estimate before the biometric prompt.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return null;
    final review = controller.reviewIntent(pending);
    if (review == null) {
      unawaited(ref
          .read(polymarketTradingProvider.notifier)
          .enableTrading()
          .catchError((_) {}));
      if (!prefund) {
        showMessageSnackBar(
          context: context,
          message: context.l10n.receiveUsdcWalletNotReady,
          error: true,
        );
      }
      return decline('wallet_not_ready');
    }
    PolymarketPlacementDiagnostics.note('review', {
      'amount': pending.amount,
      'limit': pending.isLimit,
      'maxPrice': pending.marketQuote?.maxPrice,
      'bestAsk': pending.marketQuote?.bestAsk,
      'allInMax': pending.marketQuote?.allInMax,
      'feeCeiling': pending.marketQuote?.feeCeiling,
      'liveFeeTerms': pending.feeTerms?.live,
    });
    if (!prefund) {
      _trackStep('approval');
      // The book (kept at most a second old) and the account's pUSD are
      // read while the approval is on screen, not after it.
      controller.prefetchForSend(pending);
    }
    if (funding != null) {
      final stake = '\$${pending.amount.toStringAsFixed(2)}';
      final fundedIntent = _fundedReviewIntent(review, pending, funding);
      final seam = debugPmBetFundingApproval;
      final grant = seam != null
          ? await seam(fundedIntent)
          : await requireFreshAuthGrant(
              context,
              ref,
              intent: fundedIntent,
              // Getting it ready moves the money now and approves the bet
              // too.
              reason: prefund
                  ? context.l10n.stepUpReasonBetReady(stake)
                  : context.l10n.stepUpReasonBet(stake),
              amountUsd: pending.amount,
              autofireIntentId: kPendingBetAutofireId,
            );
      if (grant == null) return decline('approval_not_granted');
      return grant;
    }
    final grant = await requireFreshAuthGrant(
      context,
      ref,
      intent: review,
      reason: context.l10n
          .stepUpReasonBet('\$${pending.amount.toStringAsFixed(2)}'),
      amountUsd: pending.amount,
      smallAction: SmallActionContext(
        amountUsdCents: PmGrants.usdCentsCeil(review.amountMax),
        paidFromVenueBalance: true,
        hasFundingLeg: false,
      ),
      fastBet: FastBetRequest(eventSlug: widget.marketSlug, hot: !_isLedger),
    );
    if (grant == null) return _decline('approval_not_granted');
    return grant;
  }

  /// The review a funded bet approves once: the bet review's cap, raised
  /// to what the autofire may submit once the money lands (its own
  /// slippage rule on the price the ticket shows, the rounding cent), plus
  /// the funding leg's cap and venue. The autofire rebuilds exactly these
  /// bounds on the order it places, so the one grant covers both legs.
  SensitiveIntent _fundedReviewIntent(
      SensitiveIntent review, PendingBetIntent pending, OrderFundingPlan plan) {
    var intent = review;
    if (!pending.isLimit) {
      final slip = autofireSlippagePct(pending.expectedPrice, pending.slippagePct);
      final bound = review.limits[IntentLimit.limitPrice];
      // The same worst price the autofire prices the order under once the
      // money lands (from a fresh book, never above it).
      final worst = max(bound is double ? bound : 0.0,
          polymarketFundedWorstPrice(pending));
      final cap = IntentUnits.usd(pending.amount + 0.02);
      intent = review.copyWith(
        amountMax: review.amountMax > cap ? review.amountMax : cap,
        limits: {
          ...review.limits,
          IntentLimit.limitPrice: worst,
          IntentLimit.maxSlippageBps: IntentUnits.bps(slip),
        },
      );
    }
    return PmGrants.fundedBetReview(intent,
        fundUsd: plan.fundUsd,
        venue: IntentVenue.polymarket,
        directLegs: pending.directLegs,
        btcLeg: pending.btcLeg);
  }

  /// Runs the placement engine with [grant]. Drift closes the placing panel
  /// and shows "Review again" (C8). An expired approval stays on the failure
  /// panel, whose Retry asks again.
  Future<void> _runPlacement(String mode, AuthGrant grant) async {
    if (!_orderMatchesSelection(ref.read(pendingPolymarketBetProvider)?.tokenId)) {
      grant.revoke();
      ref.read(pendingPolymarketBetProvider.notifier).updateStatus(
          PendingBetStatus.failed,
          errorMessage: context.l10n.betSideMismatchStopped);
      // Retry runs the whole tap again from the side now on the slip.
      _updateState(() {
        _isPlacing = false;
        _prepareFailed = true;
      });
      return;
    }
    final failure = await ref.read(polymarketBetControllerProvider).place(
          mode,
          grant: grant,
          // Spot bets end on the shared confirmation, which fires the
          // success haptic itself; limit orders keep the controller's.
          successHaptic: !betSlipEndsOnConfirmation(isLimit: _isLimitMode),
          entrySource: widget.source,
        );
    if (failure == null || !mounted) return;
    if (failure is ReauthRequired) _dismissPlacing();
    await handleGrantFailure(context, failure, action: SensitiveAction.pmBet);
  }

  /// The last check before signing: the order's token must be the token
  /// of the outcome selected on this slip, by index from the same outcome
  /// list the cards are drawn from. On a mismatch nothing is signed: the
  /// stop is recorded (stop reason side_mismatch) and false is returned.
  bool _orderMatchesSelection(String? orderedTokenId) {
    try {
      ensureOrderBuysSelectedOutcome(
        orderedTokenId: orderedTokenId ?? '',
        outcomes: widget.outcomes,
        selectedIndex: _selectedIndex,
        buyNo: _isCandidatePicker && _buyNo,
      );
      return true;
    } on PolymarketSideMismatch catch (e) {
      _stopped('side_mismatch', error: e);
      PolymarketPlacementDiagnostics.declined('side_mismatch', error: e);
      PolymarketPlacementTimeline.finish('declined', reason: 'side_mismatch');
      return false;
    }
  }

  /// Bound the market question we attach to analytics (keeps the param
  /// length sane; the full question is public on Polymarket anyway).
  String _truncMarket(String q) => q.length > 80 ? q.substring(0, 80) : q;

  /// The "Add $X to Investments" door: the whole Investments balance
  /// cannot cover the move this bet needs. One tap at a time: a tap while
  /// it is worked out (or a sheet it opened is up) is ignored, and the
  /// door shows "Calculating…" meanwhile.
  ///
  /// The tap first asks [decideSlipFunding], the same decision the order
  /// slip makes, on the spending bitcoin read fresh when the app's figures
  /// are not in yet:
  ///  * the bitcoin covers X: the tap is the bet itself (with nothing
  ///    typed, the market's minimum the button was sized for), funded
  ///    from Bitcoin into Predictions under its one approval, with the
  ///    steps on this slip. Never a sheet, whatever Investments hold;
  ///  * the bitcoin does not cover X: the Investments Receive sheet, since
  ///    the money has to come from outside;
  ///  * nothing could be read: a message, no sheet.
  /// The slip stays open underneath with the same market, side and amount.
  Future<void> _onAddDollarsTap() async {
    if (_buyInFlight || _isPlacing || _doorCalculating) return;
    final shown = _shownAddUsd;
    if (_isLedger || shown == null || shown <= 0) {
      await _openDollarsDoor();
      return;
    }
    final read = ProviderScope.containerOf(context, listen: false).read;
    _updateState(() {
      _buyInFlight = true;
      _doorCalculating = true;
    });
    SlipFundingDecision decision;
    try {
      decision = await decideSlipFunding(read, addUsd: shown);
    } finally {
      if (mounted) {
        _updateState(() {
          _buyInFlight = false;
          _doorCalculating = false;
        });
      }
    }
    if (!mounted) return;
    switch (decision.route) {
      case SlipFundingRoute.bitcoin:
        // Nothing typed: the bet the button was sized for (the market's
        // minimum), funded in place like a typed one.
        if (_emptyStake) _placeMinimum(place: false);
        if (await slipBitcoinChainStoodIn(
                OneBalanceVenue.predictions, decision) ||
            !mounted) {
          return;
        }
        _bitcoinArmed = true;
        _bitcoinFellBack = false;
        _bitcoinFallbackUsd = null;
        _bitcoinTapAddUsd = shown;
        _bitcoinTapPlan = decision.plan;
        try {
          await _handleBuy();
        } finally {
          _bitcoinArmed = false;
          _bitcoinTapPlan = null;
        }
        if (!mounted || !_bitcoinFellBack) return;
        await _openInvestmentsReceive(_bitcoinFallbackUsd ?? shown);
      case SlipFundingRoute.insufficient:
        await _openInvestmentsReceive(shown);
      case SlipFundingRoute.unavailable:
        _stopped('funding_refused');
        showMessageSnackBar(
            context: context,
            message: context.l10n.betActionNotCompleted,
            error: true);
    }
  }

  /// What this stake lacks in Predictions cash right now, for the Receive
  /// sheet's `slip_top_up_opened` (sent by [openSlipReceive]).
  double _receiveShortfallUsd() {
    try {
      final terms = ref
              .read(polymarketFeeTermsProvider(_selectedTokenId ?? ''))
              .valueOrNull ??
          PolymarketFeeTerms.worstCase;
      final cash =
          ref.read(polymarketTradingProvider).valueOrNull?.usdcBalance ?? 0;
      return _predictionsShortfall(cash, terms);
    } catch (_) {
      return 0;
    }
  }

  /// The Investments Receive sheet for an X the bitcoin cannot cover, the
  /// slip frozen while it is up ([openSlipReceive]).
  Future<void> _openInvestmentsReceive(double addUsd) async {
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    _stopped('insufficient_balance');
    _trackStep('deposit');
    _updateState(() => _buyInFlight = true);
    try {
      await openSlipReceive(context,
          venue: SlipVenue.predictions,
          depositWhenKnownEmpty: true,
          onDepositCompleted: slipTopUpReturned,
          addUsd: addUsd,
          shortfallUsd: _receiveShortfallUsd());
    } catch (_) {
      if (mounted) {
        showMessageSnackBar(
            context: context,
            message: context.l10n.errorCopyGeneric,
            error: true);
      }
    } finally {
      if (mounted) _updateState(() => _buyInFlight = false);
    }
  }

  /// The Bitcoin → Dollars Move sheet, prefilled with what is missing
  /// from Dollars for the move this bet needs. The slip is frozen for the
  /// whole tap, the open door included (the same guard a placement
  /// holds), so the bet behind the door is the one on the slip at the tap.
  Future<void> _openDollarsDoor() async {
    HapticFeedback.mediumImpact();
    _updateState(() {
      _buyInFlight = true;
      _doorCalculating = true;
    });
    try {
      // An empty slip asks for the market's minimum.
      if (_emptyStake) _placeMinimum(place: false);
      final terms = ref
              .read(polymarketFeeTermsProvider(_selectedTokenId ?? ''))
              .valueOrNull ??
          PolymarketFeeTerms.worstCase;
      final cash =
          ref.read(polymarketTradingProvider).valueOrNull?.usdcBalance ?? 0;
      final required = _predictionsRequired(terms);
      _stopped('insufficient_balance');
      _trackStep('deposit');
      await _openDollarsTopUp(
        shortfallUsd: _predictionsShortfall(cash, terms),
        requiredUsd: required,
        readyUsd: _predictionsReady(cash),
        topUpUsd: _fundingPlan?.fundUsd,
      );
    } catch (_) {
      if (!mounted) return;
      showMessageSnackBar(
          context: context,
          message: context.l10n.errorCopyGeneric,
          error: true);
    } finally {
      _depositSheetOpening();
      if (mounted) _updateState(() => _buyInFlight = false);
    }
  }
  /// The prefill is worked out (or the tap ended): the door stops
  /// calculating.
  void _depositSheetOpening() {
    if (mounted && _doorCalculating) {
      _updateState(() => _doorCalculating = false);
    }
  }

  /// Opens the Dollars deposit door prefilled with what is missing from
  /// Dollars for the move this bet needs. The ticket keeps its draft;
  /// depositing does not approve or submit this bet.
  Future<void> _openDollarsTopUp({
    required double shortfallUsd,
    required double requiredUsd,
    required double readyUsd,
    double? topUpUsd,
  }) async {
    if (!mounted) return;
    await openSlipTopUp(
      context,
      ref,
      venue: SlipVenue.predictions,
      shortfallUsd: shortfallUsd,
      orderUsd: _amount,
      requiredUsd: requiredUsd,
      readyUsd: readyUsd,
      topUpUsd: topUpUsd,
      fallbackTargetUsd: _amount,
      onReturned: slipTopUpReturned,
      onSheetOpening: _depositSheetOpening,
    );
  }

  /// The spending account's Dollars, read, never sent anywhere.
  double _dollarsUsd() {
    try {
      final d = ref.read(usdBalanceProvider);
      return d.isFinite && d > 0 ? d : 0;
    } catch (_) {
      return 0;
    }
  }

  /// The move this bet would make from Dollars, for [required] venue cash
  /// with [ready] there: the plan already read for this amount, else the
  /// venue's live estimate now (held as the slip's plan).
  Future<OrderFundingPlan> _fundingPlanFor(
      {required double required, required double ready}) async {
    final held = _fundingPlan;
    if (held != null && _fundingPlanAmount == _amount && held.fundUsd > 0) {
      return planBetFunding(
        requiredUsd: required,
        readyUsd: ready,
        routeFee: 1 - held.arrivingUsd / held.fundUsd,
        minUsd: held.minUsd,
      );
    }
    final plan = await readBetFunding(
      ref.read(predictionsVenueFunderProvider),
      requiredUsd: required,
      readyUsd: ready,
    );
    if (mounted) {
      _fundingPlan = plan;
      _fundingPlanAmount = _amount;
    }
    return plan;
  }

  /// Reads the venue's estimate for the stake on the slip while it is
  /// short of venue cash, so the ticket can show the move's fee and the
  /// button can say what Dollars are missing before any tap. One read per
  /// amount; a failed read keeps the fallback plan. [stakeUsd] is the
  /// stake the button stands for (the minimum on an empty slip).
  void _refreshFundingPlan(
      {required double required,
      required double ready,
      required double stakeUsd}) {
    if (_fundingPlanReading ||
        _fundingPlanAmount == stakeUsd ||
        stakeUsd <= 0) {
      return;
    }
    _fundingPlanReading = true;
    final amount = stakeUsd;
    unawaited(() async {
      try {
        final plan = await readBetFunding(
          ref.read(predictionsVenueFunderProvider),
          requiredUsd: required,
          readyUsd: ready,
        );
        if (!mounted) return;
        // Dollars short of the move: a Bitcoin leg may carry part of it,
        // priced on Orchestra's own spread for the fee row.
        final dollars = _dollarsUsd();
        double? spread;
        if (dollars + 1e-9 < plan.fundUsd) {
          spread = await bitcoinLegSpreadEstimate(
              cachedSpendingBitcoin(ref.read), plan.fundUsd - dollars);
          if (!mounted) return;
        }
        _fundingPlan = plan;
        _fundingPlanAmount = amount;
        _fundingBitcoinSpread = spread;
      } catch (_) {
        // The fallback share stands until the next read.
      } finally {
        _fundingPlanReading = false;
        if (mounted) _updateState(() {});
      }
    }());
  }

  /// One balance: a bet short of venue cash funds itself from Dollars and
  /// queues behind the credit, under ONE approval that covers the move and
  /// the bet. Dollars short of the move send the person to the Dollars
  /// door with nothing queued; a refused move clears the queued bet with
  /// Dollars untouched. Once Dollars have left, the autofire places the
  /// bet when the venue credits them (the slip may be closed by then).
  Future<void> _fundAndPlace({
    required double balance,
    required PolymarketFeeTerms terms,
    required double shortfallUsd,
    required String mode,
    required String outcomeLabel,
  }) async {
    final pendingNotifier = ref.read(pendingPolymarketBetProvider.notifier);
    void dropQueued() {
      if (!mounted) return;
      if (ref.read(pendingPolymarketBetProvider)?.status !=
          PendingBetStatus.failed) {
        pendingNotifier.clear();
      }
    }

    // A withheld `polymarket.deposit` shuts every door into Predictions,
    // this one included: the bet stays unplaced and the slip says why.
    if (await _refuseBlockedDeposit() != null) {
      _stopped('insufficient_balance');
      PolymarketPlacementDiagnostics.declined('deposit_blocked');
      PolymarketPlacementTimeline.finish('declined',
          reason: 'deposit_blocked');
      dropQueued();
      return;
    }
    final required = _predictionsRequired(terms);
    final spendable = _predictionsReady(balance);
    final prefund = _draft.prefund;
    final ready = prefund == null
        ? spendable
        : prefund.readyAtConfirmUsd(
            spendableUsd: spendable, balanceUsd: balance);
    // Pre-funded money still on its way: the queued bet waits for it too.
    final incoming = ready - spendable;
    // Nothing moves for a market that no longer takes orders (audit
    // P1-5). Read alongside the move's estimate. A round that may end
    // before the money lands is funded all the same: the autofire places
    // nothing once it has, the money stays as Predictions cash.
    final marketRead = _readMarketWindow();
    OrderFundingPlan plan;
    try {
      plan = await _fundingPlanFor(required: required, ready: ready);
      final block = _fundingBlockFor(await marketRead, requireRead: false);
      if (block != null && block != PredictionsFundingBlock.unread) {
        dropQueued();
        _showFundingBlock(block);
        return;
      }
    } catch (e) {
      _decline('quote_failed', error: e);
      PolymarketPlacementTimeline.finish('declined', reason: 'quote_failed');
      dropQueued();
      if (mounted) {
        showMessageSnackBar(
            context: context,
            message: context.l10n.errorCopyGeneric,
            error: true);
      }
      return;
    }
    if (!mounted) return;
    PolymarketPlacementTimeline.mark('funding_plan');
    // The receipt's fee carries what this move costs, every leg.
    final fundingFees = _fundingFees(plan);
    _placedFundingFeeUsd = fundingFees.isEmpty || fundingFees.dollarsOnly
        ? plan.feeUsd
        : fundingFees.totalUsd;
    // The shared funding engine: Dollars first, then Bitcoin, and the
    // Investing cash only for what those cannot cover (founder decision,
    // 15 October 2026: venue to venue is the slow way;
    // [decideOrderSources]). Only when even that falls short is it the
    // Receive sheet, nothing queued.
    var pullFirst = false;
    OrderSources? sources;
    if (_dollarsUsd() + 1e-9 < plan.fundUsd) {
      // Dollars plus the other venue's reachable cash: the whole
      // Investments balance this move can draw on.
      var reach = _dollarsUsd();
      try {
        reach = await ref
            .read(venueCashPullerProvider)
            .reachUsd(exclude: OneBalanceVenue.predictions)
            .timeout(const Duration(seconds: 8));
      } catch (_) {}
      if (!mounted) return;
      final fromAdd = _bitcoinArmed;
      sources = await decideOrderSources(
        ProviderScope.containerOf(context, listen: false).read,
        fundUsd: plan.fundUsd,
        dollarsUsd: _dollarsUsd(),
        otherVenueUsd: reach - _dollarsUsd(),
        shownAddUsd: fromAdd ? _bitcoinTapAddUsd : null,
        sized: fromAdd ? _bitcoinTapPlan : null,
        investmentsCover: reach + 1e-9 >= plan.fundUsd,
      );
      if (!mounted) return;
      pullFirst = sources.route == OrderSourceRoute.otherVenue;
    }
    if (sources != null && !pullFirst) {
      // Dollars short, whichever button was tapped ("Add $X", or the
      // bet): the person's own bitcoin funds the rest under this bet's
      // one approval, the Investing cash only what Bitcoin cannot. Only
      // when nothing covers it is it the Investments Receive sheet.
      await _fundAndPlaceFromBitcoin(
        balance: balance,
        plan: plan,
        required: required,
        ready: ready,
        mode: mode,
        outcomeLabel: outcomeLabel,
        dropQueued: dropQueued,
        sources: sources,
      );
      return;
    }
    // Investing cash for what Dollars lack is planned before the one
    // approval (nothing moves): its legs straight into Predictions are
    // bound into it and run only under it, exactly as planned.
    VenueCashPlan? legPlan;
    Map<String, Object?>? directLegs;
    if (pullFirst) {
      if (_moveUsd != plan.fundUsd) _moveId = null;
      legPlan = await _planVenueCashLegs(plan.fundUsd, moveId: _moveId);
      if (!mounted) return;
      if (legPlan == null || !legPlan.covers) {
        // The legs could not be planned: nothing is approved or moved.
        _stopped('funding_refused');
        PolymarketPlacementTimeline.finish('declined',
            reason: 'venue_cash_unread');
        dropQueued();
        showMessageSnackBar(
            context: context,
            message: context.l10n.betActionNotCompleted,
            error: true);
        return;
      }
      directLegs = _venueCashPuller.directLegLimit(
          legPlan, VenueCashDestination.predictions);
    }
    // One approval, bound to the whole placement, the funding leg and the
    // legs straight into Predictions.
    final grant = await _approveBet(funding: plan, directLegs: directLegs);
    PolymarketPlacementTimeline.mark('approval');
    if (grant == null) {
      PolymarketPlacementTimeline.finish('declined',
          reason: _lastDeclineReason ?? 'approval');
      dropQueued();
      return;
    }
    if (!mounted) {
      grant.revoke();
      return;
    }
    final pending = ref.read(pendingPolymarketBetProvider);
    if (pending == null || !_orderMatchesSelection(pending.tokenId)) {
      grant.revoke();
      dropQueued();
      return;
    }
    if (legPlan != null) {
      // Dollars and the Investing cash, every source at once, on the
      // bet's step graph from this approval (venue_cash_funded_order.dart).
      _runVenueCashFunded(
        grant: grant,
        pending: pending,
        legPlan: legPlan,
        plan: plan,
        required: required,
        ready: ready,
        balance: balance,
        incoming: incoming,
        mode: mode,
        outcomeLabel: outcomeLabel,
      );
      return;
    }
    // Approved: the bet's steps show from now, on this slip and (named)
    // on the Investments header, whatever happens to the slip.
    final runner = ref.read(bitcoinFundedOrderRunnerProvider);
    final fundedId = runner.beginFunded(_fundedLabel(pending, outcomeLabel));
    _swapNeeded = true;
    TrackingService.track('bet_slip_place', params: {
      'amount_bucket': TrackingService.usdBucket(_amount),
      ...TrackingService.exactUsd('amount_usd', _amount),
      'mode': mode,
      'swap_needed': 1,
      'balance_bucket': TrackingService.usdBucket(balance),
      ...TrackingService.exactUsd('balance_usd', balance),
      'market': _truncMarket(widget.marketQuestion),
      'outcome': outcomeLabel,
    });
    _orderPlaced = true;
    _trackSubmitted();
    _updateState(() {
      _isPlacing = true;
      _placedSuccess = false;
    });
    // Fund first, queue once the Dollars have left. Queued before the move,
    // venue cash already covering 99% of the stake fired the bet at once
    // (a smaller bet, the approval consumed) and the funding leg was then
    // refused, or both happened. The intent carries the funding cap now
    // (nothing fires before awaitingBalance).
    pendingNotifier.setIntent(
        pending.copyWith(fundUsd: plan.fundUsd, fundedRunId: fundedId));
    final outcome = await ref.read(orderFundingControllerProvider).fundAndQueue(
          venue: OneBalanceVenue.predictions,
          orderUsd: pending.amount,
          requiredUsd: required,
          readyUsd: ready,
          auth: UserGrantAuthorization(grant),
          fundUsd: plan.fundUsd,
          entrySource: widget.source,
          marketKind: _prefundKind?.name,
          onStage: (_) {
            if (mounted) _updateState(() {});
          },
        );
    if (ref.read(pendingPolymarketBetProvider)?.fundedRunId != fundedId) {
      // Keep the old transfer recorded without replacing a newer attempt.
      if (outcome case OrderFundingFunded(:final move)) {
        runner.followFunded(fundedId, move: move);
      } else {
        runner.dropFunded(fundedId);
      }
      grant.revoke();
      return;
    }
    switch (outcome) {
      case OrderFundingFunded(:final move):
        // Dollars have left. The row is in Activity; the autofire takes
        // over, once the venue holds what it held plus this move. The slip
        // may close now: nothing here is needed any more.
        PolymarketPlacementTimeline.mark('funded');
        final quoteRef = TrackingService.orderRef(move.quoteId);
        PredictionFundingLedger.instance.sent(quoteRef, usd: move.sentUsd);
        // The move's rows name this bet; its steps follow the autofire.
        runner.followFunded(fundedId, move: move);
        // An earlier try's legs home to Dollars: this move is their last
        // leg.
        MultiSourceMoveStore.attachFinal(
            _moveId, move.operationId ?? move.quoteId);
        _moveId = null;
        final current = ref.read(pendingPolymarketBetProvider) ?? pending;
        pendingNotifier.setIntent(current.copyWith(
          status: PendingBetStatus.awaitingBalance,
          fundUsd: plan.fundUsd,
          fundQuoteRef: quoteRef,
          // Earlier moves still on their way count as held before this
          // one, so the bet fires once both have landed.
          fundReadyUsd: balance + incoming,
          fundArrivingUsd: move.arrivingUsdEstimate,
          queuedAt: DateTime.now(),
        ));
      case OrderFundingNotNeeded():
        // The venue covers it after all (or with the pre-funded money on
        // its way): the queued bet fires on the balance tick that shows it
        // landed.
        _moveId = null;
        final current = ref.read(pendingPolymarketBetProvider) ?? pending;
        final arriving = incoming;
        pendingNotifier.setIntent(current.copyWith(
          status: PendingBetStatus.awaitingBalance,
          fundReadyUsd: arriving > 0 ? balance : null,
          fundArrivingUsd: arriving > 0 ? arriving : null,
          queuedAt: DateTime.now(),
        ));
        runner.followFunded(fundedId);
      case OrderFundingRefused(:final reason, :final error):
        // Nothing left Dollars: the queued bet goes, the slip is back.
        grant.revoke();
        pendingNotifier.clear();
        _swapNeeded = false;
        _stopped('funding_refused', error: error);
        PolymarketPlacementTimeline.finish('failed', reason: 'funding_$reason');
        if (error is AuthGrantException || reason == 'user_cancelled') {
          // Declined at the rail's own prompt: nothing to show in steps.
          runner.dropFunded(fundedId);
        } else {
          // The move step failed; the money is in Investments.
          runner.stopFunded(fundedId,
              reason: 'venue_refused',
              message: mounted
                  ? (error == null
                          ? null
                          : HotSettlement.messageFor(error, context.l10n)) ??
                      context.l10n.betActionNotCompleted
                  : null);
        }
        if (!mounted) return;
        _updateState(() => _isPlacing = false);
        if (error is AuthGrantException) {
          await handleGrantFailure(context, error,
              action: SensitiveAction.pmBet);
          return;
        }
      case OrderFundingNeedsDollars():
        // Dollars fell short since the slip looked: the Dollars door.
        runner.dropFunded(fundedId);
        grant.revoke();
        pendingNotifier.clear();
        _swapNeeded = false;
        _stopped('insufficient_balance');
        PolymarketPlacementTimeline.finish('declined',
            reason: 'insufficient_dollars');
        if (!mounted) return;
        _updateState(() => _isPlacing = false);
        await _openDollarsTopUp(
            shortfallUsd: shortfallUsd,
            requiredUsd: required,
            readyUsd: ready,
            topUpUsd: plan.fundUsd);
    }
  }

  /// The bet funded from Dollars and the Investing cash, approved: every
  /// source starts at once on the bet's step graph ("Moving $6.00 from
  /// Investing", "Moving $5.00 from Dollars", Predictions' readiness, the
  /// bet), headless, whatever happens to this slip
  /// ([VenueCashFundedOrderRunner]). The approved plan runs exactly; the
  /// bet is queued with Dollars' own share (at once when there is none)
  /// and the autofire places it once Predictions hold enough. A leg home
  /// to Dollars lands by its order's status and goes on under the same
  /// approval; every wait is bounded and a stop says where the money is.
  void _runVenueCashFunded({
    required AuthGrant grant,
    required PendingBetIntent pending,
    required VenueCashPlan legPlan,
    required OrderFundingPlan plan,
    required double required,
    required double ready,
    required double balance,
    required double incoming,
    required String mode,
    required String outcomeLabel,
  }) {
    final container = ProviderScope.containerOf(context, listen: false);
    final source = widget.source;
    final marketKind = _prefundKind?.name;
    _swapNeeded = true;
    TrackingService.track('bet_slip_place', params: {
      'amount_bucket': TrackingService.usdBucket(_amount),
      ...TrackingService.exactUsd('amount_usd', _amount),
      'mode': mode,
      'swap_needed': 1,
      'balance_bucket': TrackingService.usdBucket(balance),
      ...TrackingService.exactUsd('balance_usd', balance),
      'market': _truncMarket(widget.marketQuestion),
      'outcome': outcomeLabel,
      'funding_source': 'venue_cash',
    });
    _orderPlaced = true;
    _trackSubmitted();
    _updateState(() {
      _isPlacing = true;
      _placedSuccess = false;
    });
    // Held, never fired, until the chain queues it (awaitingBalance).
    ref
        .read(pendingPolymarketBetProvider.notifier)
        .setIntent(pending.copyWith(fundUsd: plan.fundUsd));
    ref.read(pendingBetAutoFireProvider);
    PolymarketPlacementTimeline.mark('funding_venue_cash');
    _moveId ??= MultiSourceMoveStore.newId();
    _moveUsd = plan.fundUsd;
    final run = container.read(venueCashFundedOrderRunnerProvider).start(
          predictionsVenueCashRequest(
            container,
            grant: grant,
            pending: pending,
            label: _fundedLabel(pending, outcomeLabel),
            legPlan: legPlan,
            fundUsd: plan.fundUsd,
            requiredUsd: required,
            readyUsd: ready,
            balanceUsd: balance,
            incomingUsd: incoming,
            moveId: _moveId,
            entrySource: source,
            marketKind: marketKind,
          ),
        );
    _bitcoinRunId = run.id;
    unawaited(run.ended.then((end) {
      if (end == BitcoinFundedEnd.placed) _moveId = null;
      if (mounted) _onBitcoinRunEnded(run.id, end, source: 'venue_cash');
    }));
  }

  /// A hot slip whose whole Investments balance is short of the bet's move
  /// (founder decision 14 October 2026), whichever button was tapped: ONE
  /// approval for the bet, the Dollars move AND a Bitcoin → Dollars leg
  /// (at most the sized sats, `spark:BTC → spark:USDB`, to the wallet's
  /// own Spark address), then the chain runs headless
  /// ([BitcoinFundedOrderRunner]): Bitcoin → Dollars, Dollars →
  /// Predictions, the bet at a fresh price. The normal tap validated the
  /// bet and the market before this point; the leg is sized and checked
  /// against the wallet's bitcoin here ([decideSlipFunding], the order
  /// slip's same decision), before the prompt. Declining moves nothing.
  ///
  /// When the bitcoin genuinely does not cover X, nothing is approved: an
  /// "Add" tap opens the Dollars door itself once this returns
  /// ([_bitcoinFellBack]); a tap on the bet opens it here. Both prefill X.
  Future<void> _fundAndPlaceFromBitcoin({
    required double balance,
    required OrderFundingPlan plan,
    required double required,
    required double ready,
    required String mode,
    required String outcomeLabel,
    required void Function() dropQueued,
    required OrderSources sources,
  }) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final source = widget.source;
    final fromAdd = _bitcoinArmed;
    if (FundedOrdersNotifier.activeOf(
            ref.read(fundedOrdersProvider), OneBalanceVenue.predictions) !=
        null) {
      _stopped('previous_order_pending');
      PolymarketPlacementTimeline.finish('declined',
          reason: 'previous_order_pending');
      dropQueued();
      showMessageSnackBar(
          context: context, message: context.l10n.ledgerBetPending, error: true);
      return;
    }
    // An "Add" tap whose X no longer covers what Investments lack: nothing
    // moves and the button names the new figure.
    if (sources.route == OrderSourceRoute.addChanged) {
      _stopped('add_amount_changed');
      PolymarketPlacementTimeline.finish('declined',
          reason: 'add_amount_changed');
      dropQueued();
      _fundingPlan = plan;
      _fundingPlanAmount = _amount;
      _updateState(() {});
      return;
    }
    final dollars = _dollarsUsd();

    /// The bitcoin (or the rest of Investments) genuinely does not cover
    /// it: the money has to come from outside, so the Investments Receive
    /// sheet, for what is missing.
    Future<void> toReceive(double missingUsd) async {
      _bitcoinFellBack = true;
      _bitcoinFallbackUsd = missingUsd > 0 ? missingUsd : null;
      PolymarketPlacementTimeline.finish('declined',
          reason: 'insufficient_dollars');
      dropQueued();
      if (fromAdd || !mounted) return;
      _stopped('insufficient_balance');
      _trackStep('deposit');
      PolymarketPlacementDiagnostics.declined('insufficient_dollars');
      await openSlipReceive(context,
          venue: SlipVenue.predictions,
          depositWhenKnownEmpty: true,
          onDepositCompleted: slipTopUpReturned,
          addUsd: missingUsd,
          shortfallUsd: _receiveShortfallUsd());
    }

    /// Nothing could be worked out in time (no price, the wallet's own
    /// Spark address or the other venue's plan unread): nothing moves and
    /// no door opens; the slip says the bet did not go through.
    void unavailable(String reason) {
      _stopped('funding_refused');
      PolymarketPlacementTimeline.finish('declined', reason: reason);
      dropQueued();
      if (!mounted) return;
      showMessageSnackBar(
          context: context,
          message: context.l10n.betActionNotCompleted,
          error: true);
    }

    switch (sources.route) {
      case OrderSourceRoute.insufficient:
        await toReceive(sources.missingUsd > 0
            ? sources.missingUsd
            : slipDollarsShortfallUsd(
                topUpUsd: plan.fundUsd, dollarsUsd: dollars));
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
    // The rest of the bet from the other venue (Dollars first, then its
    // cash), planned before the one approval, which binds the legs that
    // go straight into Predictions.
    OtherVenuePlan? other;
    try {
      other = await planOtherVenueCash(_venueCashPuller,
              venue: OneBalanceVenue.predictions,
              fundUsd: plan.fundUsd,
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
      await toReceive(slipDollarsShortfallUsd(
          topUpUsd: plan.fundUsd, dollarsUsd: dollars));
      return;
    }
    final rest = other;
    // The Bitcoin leg the approval binds: via Dollars to the own Spark
    // address, or straight to the own Predictions deposit.
    final btcLeg = await bitcoinLegLimitFor(container.read,
        venue: OneBalanceVenue.predictions, leg: leg, ownSpark: ownSpark);
    if (!mounted) return;
    // The ONE approval: the bet, the Dollars it may take, the other
    // venue's legs straight into Predictions, the bitcoin leg. Held as the
    // bet's autofire grant. Declined: nothing is quoted or moved.
    final runner = container.read(bitcoinFundedOrderRunnerProvider);
    var declined = false;
    final run = await runner.startApproved(
      approve: () async {
        final grant = await _approveBet(
            funding: plan, directLegs: rest.directLegs, btcLeg: btcLeg);
        PolymarketPlacementTimeline.mark('approval');
        declined = grant == null;
        return grant;
      },
      build: (grant) {
        if (!mounted) {
          AuthGrantRegistry.instance.cancelAutofire(kPendingBetAutofireId);
          return null;
        }
        final pending = ref.read(pendingPolymarketBetProvider);
        if (pending == null || !_orderMatchesSelection(pending.tokenId)) {
          dropQueued();
          return null;
        }
        _swapNeeded = true;
        TrackingService.track('bet_slip_place', params: {
          'amount_bucket': TrackingService.usdBucket(_amount),
          ...TrackingService.exactUsd('amount_usd', _amount),
          'mode': mode,
          'swap_needed': 1,
          'balance_bucket': TrackingService.usdBucket(balance),
          ...TrackingService.exactUsd('balance_usd', balance),
          'market': _truncMarket(widget.marketQuestion),
          'outcome': outcomeLabel,
          'funding_source': 'bitcoin',
        });
        _orderPlaced = true;
        _trackSubmitted();
        _updateState(() {
          _isPlacing = true;
          _placedSuccess = false;
        });
        // Held, never fired, while the bitcoin leg runs (converting holds
        // the venue's cash from the sweeper and a second bet out).
        final heldAttempt = pending.copyWith(
            status: PendingBetStatus.converting,
            fundUsd: plan.fundUsd,
            btcLeg: btcLeg);
        ref.read(pendingPolymarketBetProvider.notifier).setIntent(heldAttempt);
        String? activeRunId;
        ref.read(pendingBetAutoFireProvider);
        PolymarketPlacementTimeline.mark('funding_bitcoin');
        return BitcoinFundedOrderRequest(
          venue: OneBalanceVenue.predictions,
          bindAttempt: (id) {
            final bound = container
                .read(pendingPolymarketBetProvider.notifier)
                .bindFundingRun(heldAttempt, id);
            if (bound) activeRunId = id;
            return bound;
          },
          isCurrentAttempt: () => identical(
              container.read(pendingPolymarketBetProvider), heldAttempt),
          grant: grant,
          plan: leg,
          otherVenueUsed: rest.otherUsd > 0,
          label: FundedOrderLabel(
            venue: OneBalanceVenue.predictions,
            orderUsd: pending.amount,
            side: outcomeLabel,
            market: FundedOrderLabel.shortName(widget.marketQuestion),
            marketKey: pending.tokenId,
          ),
          fundUsd: plan.fundUsd,
          readyUsd: ready,
          entrySource: source,
          // Runs whatever happens to this slip: reads only the container.
          // The rest from the other venue under the same grant, then the
          // move from Dollars.
          fundVenue: (controller, legs) async {
            final current = container.read(pendingPolymarketBetProvider);
            if (current == null ||
                current.fundedRunId != activeRunId ||
                current.tokenId != pending.tokenId ||
                current.status != PendingBetStatus.converting) {
              return const OrderFundingRefused('order_gone');
            }
            final venueCash = container
                    .read(polymarketTradingProvider)
                    .valueOrNull
                    ?.usdcBalance ??
                balance;
            return fundRestThenMove(
              legs: legs,
              puller: container.read(venueCashPullerProvider),
              venue: OneBalanceVenue.predictions,
              fundUsd: plan.fundUsd,
              readyUsd: ready,
              needsOtherVenue: rest.otherUsd > 0,
              grant: grant,
              queue: ({
                required double fundUsd,
                required double readyUsd,
                required double directArrivingUsd,
                String? moveId,
              }) async {
                final outcome = await controller.fundAndQueue(
                  venue: OneBalanceVenue.predictions,
                  orderUsd: pending.amount,
                  requiredUsd: required,
                  readyUsd: readyUsd,
                  auth: UserGrantAuthorization(grant),
                  fundUsd: fundUsd,
                  entrySource: source,
                  continueJourney: true,
                );
                final queued =
                    container.read(pendingPolymarketBetProvider) ?? current;
                if (queued.fundedRunId != activeRunId) return outcome;
                final pendingNotifier =
                    container.read(pendingPolymarketBetProvider.notifier);
                switch (outcome) {
                  case OrderFundingFunded(:final move):
                    // Dollars have left: the autofire places the bet once
                    // the venue holds what it held plus this move and the
                    // legs straight here, at a fresh price.
                    final quoteRef = TrackingService.orderRef(move.quoteId);
                    PredictionFundingLedger.instance
                        .sent(quoteRef, usd: move.sentUsd);
                    MultiSourceMoveStore.attachFinal(
                        moveId, move.operationId ?? move.quoteId);
                    pendingNotifier.setIntent(queued.copyWith(
                      status: PendingBetStatus.awaitingBalance,
                      fundUsd: plan.fundUsd,
                      fundQuoteRef: quoteRef,
                      fundReadyUsd: venueCash,
                      fundArrivingUsd:
                          move.arrivingUsdEstimate + directArrivingUsd,
                      queuedAt: DateTime.now(),
                    ));
                  case OrderFundingNotNeeded():
                    pendingNotifier.setIntent(queued.copyWith(
                      status: PendingBetStatus.awaitingBalance,
                      fundReadyUsd:
                          directArrivingUsd > 0 ? venueCash : null,
                      fundArrivingUsd:
                          directArrivingUsd > 0 ? directArrivingUsd : null,
                      queuedAt: DateTime.now(),
                    ));
                  default:
                    break;
                }
                return outcome;
              },
            );
          },
          dropOrder: () {
            final current = container.read(pendingPolymarketBetProvider);
            if (current != null &&
                current.fundedRunId == activeRunId &&
                current.tokenId == pending.tokenId &&
                (current.status == PendingBetStatus.converting ||
                    current.status == PendingBetStatus.awaitingDeposit)) {
              container.read(pendingPolymarketBetProvider.notifier).clear();
            }
            if (current?.fundedRunId == activeRunId) {
              AuthGrantRegistry.instance.cancelAutofire(kPendingBetAutofireId);
            }
            grant.revoke();
          },
        );
      },
    );
    if (run == null) {
      if (declined) {
        PolymarketPlacementTimeline.finish('declined',
            reason: _lastDeclineReason ?? 'approval');
        dropQueued();
      }
      return;
    }
    _bitcoinRunId = run.id;
    unawaited(run.ended.then((end) {
      if (mounted) _onBitcoinRunEnded(run.id, end);
    }));
  }

  /// The slip's Bitcoin-funded run ended. A placed bet or a venue refusal
  /// is the placing panel's (the confirmation, or Retry); a chain that
  /// stopped before the bet says so here, with the money where it is.
  void _onBitcoinRunEnded(String id, BitcoinFundedEnd end,
      {String source = 'bitcoin'}) {
    if (_bitcoinRunId != id) return;
    _bitcoinRunId = null;
    if (end == BitcoinFundedEnd.placed ||
        end == BitcoinFundedEnd.placementFailed) {
      return;
    }
    final error = ref.read(bitcoinFundedOrderRunnerProvider).errorOf(id);
    _stopped('funding_refused', error: error);
    PolymarketPlacementTimeline.finish('failed',
        reason: 'funding_${source}_${end.name}');
    _swapNeeded = false;
    _orderPlaced = false;
    // The steps keep the stop: the failed step and one line saying what
    // happened and where the money is (the refund, the unknown transfer,
    // "Your $X is in Investments"); the button is the bet again.
    _updateState(() => _isPlacing = false);
  }

  /// The X "Add $X to Investments" names on a hot slip
  /// ([BitcoinLegRules.addUsd], on the stake typed or, with nothing typed,
  /// the market's minimum): what the tap converts from bitcoin. Whether
  /// the bitcoin covers it is decided at the tap ([decideSlipFunding]) on
  /// the wallet's own figures. Set by the build.
  double? _shownAddUsd;

  /// What the button's Dollars door adds ("Add $X · Place …"), null while
  /// the button is anything else. Set by the build with the button, so
  /// the line under the amount names the same figure.
  double? _doorAddUsd;

  /// [_shownAddUsd] as it was at the Add tap: what the leg converts.
  double? _bitcoinTapAddUsd;

  /// Whether [_warmBitcoinLeg] already ran for this slip.
  bool _ownSparkWarmed = false;

  /// From the first time "Add" shows, holds the wallet's own Spark
  /// address (the Bitcoin leg's pinned recipient) so the tap finds it
  /// ready instead of waiting on a cold SDK. Once per slip; a failed read
  /// is let go and the tap reads again.
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

  /// The step lines of a funded bet on this slip: the Bitcoin leg (only
  /// with one), the move into Predictions, the bet.
  List<String> _fundingSteps(FundedOrderRecord record) => [
        if (record.fromBitcoin)
          context.l10n
              .slipStepAddingToInvestments(_fiatCompanion(record.addUsd)),
        context.l10n.slipStepPreparingPrediction,
        context.l10n.slipStepPlacingBet(
            _fiatCompanion(record.label.orderUsd), record.label.side),
      ];

  /// The funded bet for the market on this slip (this slip's, or one
  /// started before it was reopened): on its way, just placed, or stopped
  /// and not yet tried again.
  FundedProgress? _fundedProgress(List<FundedOrderRecord> records) {
    if (_isLedger) return null;
    final progress = FundedOrdersNotifier.progressOn(records,
        OneBalanceVenue.predictions, _selectedTokenId ?? '', DateTime.now());
    // A placed bet's finished steps show only while this slip is still
    // on its placement, never on a reopen.
    if (progress != null && progress.done && !_isPlacing) return null;
    return progress;
  }

  /// A new try on this market: an earlier stop's steps give way to it.
  void _clearFundedStop() {
    if (_isLedger) return;
    final notifier = ref.read(fundedOrdersProvider.notifier);
    final progress = FundedOrdersNotifier.progressOn(ref.read(fundedOrdersProvider),
        OneBalanceVenue.predictions, _selectedTokenId ?? '', DateTime.now());
    if (progress != null && progress.failed) {
      notifier.clearStop(progress.record.id);
    }
  }

  /// The label the funded record names this bet by.
  FundedOrderLabel _fundedLabel(PendingBetIntent pending, String side) =>
      FundedOrderLabel(
        venue: OneBalanceVenue.predictions,
        orderUsd: pending.amount,
        side: side,
        market: FundedOrderLabel.shortName(widget.marketQuestion),
        marketKey: pending.tokenId,
      );

  /// "Add more" under "Deposit incoming": the rest of the shortfall.
  Future<void> _addMoreDeposit(double shortfallUsd, double incomingUsd) async {
    if (await _refuseBlockedDeposit() != null || !mounted) return;
    await openSlipTopUp(
      context,
      ref,
      venue: SlipVenue.predictions,
      shortfallUsd: shortfallUsd,
      orderUsd: _amount,
      incomingUsd: incomingUsd,
      onReturned: slipTopUpReturned,
    );
  }

  /// The Predictions cash this stake takes: the stake plus the venue's
  /// fee ceiling at the price the ticket shows. [stakeUsd] defaults to
  /// the typed stake; the empty slip's button passes the minimum it
  /// would place.
  double _predictionsRequired(PolymarketFeeTerms terms, {double? stakeUsd}) {
    final stake = stakeUsd ?? _amount;
    if (!stake.isFinite || stake <= 0) return 0;
    final selected = widget.outcomes[_selectedIndex];
    // The fees at the order's worst price (its tolerance), plus the
    // rounding cent: the most the order can take of the venue's cash.
    final shown = _maxFeePrice ?? selected.price;
    final worst = _isLimitMode && _limitPrice > 0
        ? _limitPrice
        : shown * (1 + _slippagePct / 100);
    final price = worst.clamp(0.01, 0.99).toDouble();
    return terms.allInCost(stake, price) +
        PolymarketMarketBuyQuote.roundingHeadroom;
  }

  /// What the venue lets a new buy spend of [cash]: less what resting buys
  /// reserve (the placement checks the same figure).
  double _predictionsReady(double cash) {
    final orders =
        ref.read(polymarketTradingProvider).valueOrNull?.openOrders ??
            const [];
    return PolymarketBetController.spendableUsdc(cash, orders);
  }

  /// What this stake is short of in Predictions cash:
  /// [_predictionsRequired] less [cash]. The button and the tap read the
  /// same figure.
  double _predictionsShortfall(double cash, PolymarketFeeTerms terms,
      {double? stakeUsd}) {
    final stake = stakeUsd ?? _amount;
    if (!stake.isFinite || stake <= 0) return 0;
    return ShortfallRules.shortfallUsd(
        requiredUsd: _predictionsRequired(terms, stakeUsd: stake),
        readyUsd: _predictionsReady(cash));
  }

  @override
  SlipVenue get slipVenue => SlipVenue.predictions;

  /// Read while a deposit is on its way (about 20 s to a few minutes), so
  /// the button turns into the bet by itself. Nothing is placed: the
  /// person taps.
  @override
  void refreshSlipVenueCash() {
    final notifier = ref.read(polymarketTradingProvider.notifier);
    notifier.invalidateBalanceCache();
    unawaited(notifier.refresh().catchError((_) {}));
  }

  // ── Spot / Limit ────────────────────────────────────────────────────────

  Widget _buildOrderTypeToggle(AppColorsExtension c, double currentPrice) {
    Widget seg(String label, bool isLimit) {
      final selected = _isLimitMode == isLimit;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (_isLimitMode == isLimit) return;
            HapticFeedback.selectionClick();
            _updateState(() {
              _isLimitMode = isLimit;
              if (isLimit && _limitPrice <= 0) {
                _limitPrice = currentPrice.clamp(0.01, 0.99).toDouble();
              }
            });
            TrackingService.track('bet_slip_order_type',
                params: {'type': isLimit ? 'limit' : 'spot'});
          },
          child: Container(
            height: 38.h,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? c.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(9.r),
              border: selected ? Border.all(color: c.border) : null,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? c.textPrimary : c.textTertiary,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.all(3.w),
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: c.border),
      ),
      child: Row(children: [
        seg(context.l10n.betOrderTypeSpot, false),
        seg(context.l10n.betOrderTypeLimit, true),
      ]),
    );
  }

  Widget _limitStepBtn(
      AppColorsExtension c, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        // 44x44 minimum hit target (was 42x36). Standalone +/- stepper
        // button; growing the box keeps the icon centred and doesn't
        // disturb the surrounding limit-price row layout.
        width: 44.sp,
        height: 44.sp,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(8.r),
          border: Border.all(color: c.border),
        ),
        child: Icon(icon, size: 18.sp, color: c.textPrimary),
      ),
    );
  }

  void _trackLimitPriceEdited() {
    VenueAnalytics.settingChanged('bet_slip_limit_price_edited',
        setting: 'limit_price', value: 'edited', scope: _settingsScope);
  }

  Widget _buildLimitPriceInput(AppColorsExtension c, double currentPrice) {
    void bump(double deltaCents) {
      final next =
          (((_limitPrice * 100) + deltaCents).clamp(1.0, 99.0)) / 100.0;
      HapticFeedback.selectionClick();
      _updateState(() => _limitPrice = next);
      _trackLimitPriceEdited();
    }

    final cents = _limitPrice * 100;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              context.l10n.betLimitPrice,
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: c.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => _updateState(() =>
                  _limitPrice = currentPrice.clamp(0.01, 0.99).toDouble()),
              behavior: HitTestBehavior.opaque,
              child: Text(
                context.l10n.betMarketPrice(formatPolyCents(currentPrice)),
                style: TextStyle(fontSize: 12.sp, color: _kPolyPurple),
              ),
            ),
          ],
        ),
        SizedBox(height: 8.h),
        Container(
          decoration: BoxDecoration(
            color: c.surfaceLight,
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: c.border),
          ),
          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
          child: Row(
            children: [
              _limitStepBtn(c, Icons.remove_rounded, () => bump(-1)),
              Expanded(
                child: Center(
                  child: Text(
                    '${cents.toStringAsFixed(1)}¢',
                    style: TextStyle(
                      fontSize: 22.sp,
                      fontWeight: FontWeight.w700,
                      color: c.textPrimary,
                    ),
                  ),
                ),
              ),
              _limitStepBtn(c, Icons.add_rounded, () => bump(1)),
            ],
          ),
        ),
        SizedBox(height: 6.h),
        Text(
          context.l10n.betLimitRestsOnBook,
          style: TextStyle(
            fontSize: 12.sp,
            color: c.textTertiary,
            height: 1.3,
          ),
        ),
      ],
    );
  }

  /// Every placement is USDC-only (user decision: no betting straight
  /// from Lightning). Kept as a method for the legacy call sites.
  String _resolveMode() => 'usdc';

  Future<void> _retryPlacement() async {
    // A retry is a new placement, so it asks for a fresh approval
    // (Phase 1b.4).
    if (_buyInFlight) return;
    // A retry of a 5-minute round stopped by its price moving: the
    // submit says why it is sent again (categorical only).
    final stopped = ref.read(pendingPolymarketBetProvider);
    final retryParams = <String, Object>{
      if (stopped != null &&
          stopped.failureCode == 'round_price_moved' &&
          polyIsCryptoUpDown5m(stopped.eventSlug)) ...{
        'reason': 'price_moved',
        'market_kind': kCryptoUpDown5mKind,
      },
    };
    _clearFundedStop();
    _updateState(() => _buyInFlight = true);
    AuthGrant? grant;
    try {
      grant = await _approveBet();
    } finally {
      if (mounted) _updateState(() => _buyInFlight = false);
    }
    if (grant == null) return;
    if (!mounted) {
      grant.revoke();
      return;
    }
    final mode = _resolveMode();
    final balance =
        ref.read(polymarketTradingProvider).valueOrNull?.usdcBalance ?? 0;
    _swapNeeded = mode == 'btc' || (mode == 'smart' && balance < _amount);
    _trackSubmitted(extra: retryParams);
    _updateState(() {
      _placedSuccess = false;
      _isPlacing = true;
    });
    unawaited(_runPlacement(mode, grant));
  }

  /// Retry for a short round that ended with its bet not placed
  /// ([betSlipRetriesNextRound]): the series' round in play now, resolved
  /// from the series (every window is a new market with its own slug and
  /// tokens), opens on a fresh slip with the same side and stake. The
  /// money is already Predictions cash, so nothing moves twice; nothing
  /// is placed until the person confirms there, under a new approval.
  Future<void> _retryOnCurrentRound() async {
    if (_buyInFlight) return;
    final stopped = ref.read(pendingPolymarketBetProvider);
    if (stopped == null) return;
    _updateState(() => _buyInFlight = true);
    Btc5MinEvent? round;
    try {
      round = await resolveCurrentPolyRound(
          ref.read(polyRoundWindowReaderProvider), stopped.eventSlug);
    } finally {
      if (mounted) _updateState(() => _buyInFlight = false);
    }
    if (!mounted) return;
    if (round == null) {
      showMessageSnackBar(
          context: context,
          message: context.l10n.builderMarketGone,
          error: true);
      return;
    }
    final outcomes = [
      PolymarketOutcome(
          name: 'Up',
          price: round.upPrice,
          tokenId: round.upTokenId,
          conditionId: round.conditionId),
      PolymarketOutcome(
          name: 'Down',
          price: round.downPrice,
          tokenId: round.downTokenId,
          conditionId: round.conditionId),
    ];
    final side = stopped.outcomeName.trim().toLowerCase();
    final index = side == 'down' || side == 'no' ? 1 : 0;
    final navigator = Navigator.of(context, rootNavigator: true);
    final host = navigator.context;
    final onDeposit = widget.onDeposit;
    _clearFundedStop();
    _dismissPlacing();
    // This slip (and its Advanced page, when open) gives way to the new
    // round's; the round sheet under it stays.
    navigator.popUntil(
        (r) => r.isFirst || r.settings.name != BetSlipSheet.routeName);
    if (!host.mounted) return;
    await BetSlipSheet.show(
      host,
      marketQuestion: round.title,
      marketSlug: round.slug,
      marketImage: round.image,
      outcomes: outcomes,
      initialOutcomeIndex: index,
      marketEndAt: round.endDate,
      marketCategory: 'crypto',
      initialAmountUsd: stopped.amount,
      onDeposit: onDeposit,
      source: 'round_retry',
    );
  }

  /// True once this placement has started accounting for the earlier
  /// order, so it runs once rather than on every rebuild.
  bool _resolvingPending = false;

  /// An earlier submission is unaccounted for, so the venue would not
  /// take this one. Finding out what happened to it is work, and it
  /// happens here, behind the CTA that is still spinning. Nothing reads
  /// as "checking" in front of the person: they see the button working
  /// and then the answer.
  Future<void> _resolveAwaitingConfirmation() async {
    if (_resolvingPending || _buyInFlight) return;
    _resolvingPending = true;
    _updateState(() => _buyInFlight = true);
    final notifier = ref.read(polymarketTradingProvider.notifier);
    final container = ProviderScope.containerOf(context, listen: false);
    final intent = ref.read(pendingPolymarketBetProvider);
    final tokenId = intent?.tokenId;
    final accepted = intent?.venueAccepted == true;
    final l10n = context.l10n;
    var result = (message: l10n.betOrderAcceptedPendingFill, read: true);
    try {
      // The submission guard already retries reads. Do not multiply that into
      // nine requests, or look up a receipt the venue just acknowledged.
      if (!accepted) {
        result = await checkEarlierPrediction(notifier, tokenId, l10n);
      }
    } finally {
      _buyInFlight = false;
      _resolvingPending = false;
    }
    TrackingService.track('bet_slip_pending_check_result',
        params: {'read': result.read});
    if (!mounted) return;
    // A result, not a progress bar: reached once, after the button has
    // finished. When it could not be settled, the result offers the check
    // again instead of only telling the person to do it.
    final navigator = Navigator.of(context, rootNavigator: true);
    _dismissPlacing();
    BetSlipSheet.popAllSheetsDownToBetSlipHost(navigator);
    pushKuteSuccessOverlay(
      navigator: navigator,
      overlay: EarlierPredictionResult(
        message: result.message,
        success: result.read,
        onDone: navigator.pop,
        recheck: () async {
          // The slip is gone by now; keep the account alive while it reads.
          final hold = container.listen(polymarketTradingProvider, (_, __) {});
          try {
            await container.read(polymarketTradingProvider.future);
            return await checkEarlierPrediction(
                container.read(polymarketTradingProvider.notifier),
                tokenId,
                l10n);
          } catch (_) {
            return (message: l10n.betConnectionUnavailable, read: false);
          } finally {
            hold.close();
          }
        },
      ),
    );
  }

  /// Release the ticket after a terminal placement state (back to the
  /// editable form).
  void _dismissPlacing() {
    ref.read(pendingPolymarketBetProvider.notifier).clear();
    _updateState(() {
      _isPlacing = false;
      _placedSuccess = false;
      _prepareFailed = false;
    });
  }

  /// Retry after the tap stopped before its order existed: the whole tap
  /// again (region, balance, setup, price, approval), which joins a setup
  /// still running rather than starting another.
  void _retryFromStart() {
    _updateState(() => _prepareFailed = false);
    unawaited(_handleBuy());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Warm the per-market minimum-order-size lookup so the buy
    // handler's synchronous read has data by the time the user
    // confirms (the provider is autoDispose; watching here keeps it
    // alive for the sheet's lifetime). Fail-safe: while loading, the
    // static $2 floor applies.
    final warmCid = widget.outcomes[_selectedIndex].conditionId;
    if (!_isLedger && warmCid != null && warmCid.isNotEmpty) {
      ref.watch(polymarketMinOrderSizeProvider(warmCid));
    }
    // Drive the placing panel's success → auto-close. When the engine
    // (or the BTC auto-fire) flips the intent to `done`, show the brief
    // "Placed" state, then close the sheet and land where the position
    // shows.
    if (!_isLedger) {
      ref.listen<PendingBetStatus?>(
          pendingPolymarketBetProvider.select((i) => i?.status),
          (prev, status) {
        if (!_isPlacing || _placedSuccess) return;
        // `done` = order placed: show the success state and release the sheet.
        if (status == PendingBetStatus.done) {
          // Success haptic fires in PolymarketBetController (the single
          // choke point — it also covers the BTC auto-fire path where
          // this sheet is already closed), not here.
          if (betSlipEndsOnConfirmation(isLimit: _isLimitMode)) {
            // Spot bet placed: close the slip and show the shared
            // confirmation, which fires the success haptic as its check
            // completes (the controller skips it for this path). The
            // ticket stays as it is for the frame it takes to close, so
            // nothing flickers under the confirmation.
            _updateState(() => _placedSuccess = true);
            final intent = ref.read(pendingPolymarketBetProvider);
            // Part of a market order filled (the book ran out at the
            // approved price): the receipt says how much, and that the
            // rest was not bought.
            final partial = _partialFill(intent);
            final l10n = context.l10n;
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (!mounted) return;
              // The band snaps on _placedSuccess; the confirmation comes
              // once the snap has been seen (at once under Reduce Motion,
              // covered or in the background).
              await RubberBand.settle(context);
              if (!mounted) return;
              final nav = Navigator.of(context, rootNavigator: true);
              ref.read(pendingPolymarketBetProvider.notifier).clear();
              showBetSlipPlacedConfirmation(
                navigator: nav,
                marketQuestion: intent?.marketQuestion ?? widget.marketQuestion,
                marketImage: intent?.marketImage,
                outcome: intent?.outcomeName ?? '',
                total: intent?.amount ?? _amount,
                price: intent?.expectedPrice ?? 0,
                filledCost: intent?.filledCost,
                filledShares: intent?.filledShares,
                feeTerms: intent?.feeTerms,
                fundingFeeUsd: _placedFundingFeeUsd,
                note: partial == null
                    ? null
                    : l10n.betBuyPartialMarket(
                        partial.bought, partial.total, partial.price),
                position: placedPositionFor(
                  intent: intent,
                  outcomes: widget.outcomes,
                  eventSlug: widget.marketSlug,
                ),
                keepMarketSheet: polyIsFastBetRound(widget.marketSlug),
              );
            });
            return;
          }
          // A limit order that bought shares on arrival ends on a receipt
          // too: all of it, or how much and that the rest waits at the
          // person's price (in Open orders).
          final limitIntent = ref.read(pendingPolymarketBetProvider);
          final limitBought = limitIntent?.filledShares ?? 0;
          if (limitBought > 0) {
            _updateState(() => _placedSuccess = true);
            final partial = _partialFill(limitIntent);
            final l10n = context.l10n;
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (!mounted) return;
              // The band snaps on _placedSuccess; the confirmation comes
              // once the snap has been seen (at once under Reduce Motion,
              // covered or in the background).
              await RubberBand.settle(context);
              if (!mounted) return;
              final nav = Navigator.of(context, rootNavigator: true);
              ref.read(pendingPolymarketBetProvider.notifier).clear();
              if (partial == null) {
                showBetSlipPlacedConfirmation(
                  navigator: nav,
                  marketQuestion: limitIntent!.marketQuestion,
                  marketImage: limitIntent.marketImage,
                  outcome: limitIntent.outcomeName,
                  total: limitIntent.amount,
                  price: limitIntent.limitPrice,
                  filledCost: limitIntent.filledCost,
                  filledShares: limitIntent.filledShares,
                  feeTerms: limitIntent.feeTerms,
                  fundingFeeUsd: _placedFundingFeeUsd,
                  position: placedPositionFor(
                    intent: limitIntent,
                    outcomes: widget.outcomes,
                    eventSlug: widget.marketSlug,
                  ),
                );
                return;
              }
              nav.popUntil((route) {
                final name = route.settings.name;
                return name != 'polymarket-bet-slip' &&
                    name != 'polymarket-market-detail-sheet';
              });
              final cost = limitIntent!.filledCost;
              final costLabel =
                  cost == null ? null : '\$${cost.toStringAsFixed(2)}';
              pushKuteSuccessOverlay(
                navigator: nav,
                overlay: KuteConfirmation(
                  message: l10n.betPredictionPlaced,
                  amount: costLabel == null
                      ? null
                      : l10n.betAmountOnSide(
                          costLabel, limitIntent.outcomeName),
                  contextLine: limitIntent.marketQuestion,
                  rows: {l10n.betShares: limitBought.toStringAsFixed(2)},
                  // How much bought, and that the rest waits at the
                  // person's price.
                  detail: l10n.betBuyPartialLimit(
                      partial.bought, partial.total, partial.price),
                  onDone: nav.pop,
                  // The rest waits at the person's price: "View orders"
                  // opens the Portfolio's P&L charts, where it is listed.
                  secondaryButtonText: l10n.investingViewOrders,
                  onSecondary: () {
                    nav.pop();
                    openInvestmentsOrders(nav.context,
                        product: 'predictions',
                        orderKind: 'limit_buy_partial');
                  },
                ),
              );
            });
            return;
          }
          // A limit buy that bought nothing yet rests on the book: once the
          // band's snap has been seen, the slip closes onto a pending
          // result sheet saying what waits at which price. The controller
          // keeps the success haptic for limit orders, so the sheet
          // (pending, no haptic) adds none.
          _updateState(() => _placedSuccess = true);
          final restingIntent = limitIntent;
          final l10n = context.l10n;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) return;
            await RubberBand.settle(context);
            if (!mounted) return;
            ref.read(pendingPolymarketBetProvider.notifier).clear();
            final nav = Navigator.of(context, rootNavigator: true);
            nav.popUntil((route) {
              final name = route.settings.name;
              return name != 'polymarket-bet-slip' &&
                  name != 'polymarket-market-detail-sheet';
            });
            if (restingIntent == null) return;
            final price = restingIntent.limitPrice;
            final shares = restingIntent.orderedShares ??
                (price > 0 ? restingIntent.amount / price : 0.0);
            final cost = '\$${restingIntent.amount.toStringAsFixed(2)}';
            pushKuteSuccessOverlay(
              navigator: nav,
              overlay: KuteConfirmation(
                tone: KuteConfirmationTone.pending,
                message: l10n.investingOrderAccepted,
                amount: restingIntent.outcomeName.isEmpty
                    ? cost
                    : l10n.betAmountOnSide(cost, restingIntent.outcomeName),
                contextLine: restingIntent.marketQuestion,
                rows: {
                  l10n.betLimitPrice: formatPolyCents(price),
                  if (shares > 0) l10n.betShares: shares.toStringAsFixed(2),
                },
                detail: l10n.betRestingBuyNote,
                onDone: nav.pop,
                // The order rests: "View orders" opens the Portfolio's P&L
                // charts, where it is listed.
                secondaryButtonText: l10n.investingViewOrders,
                onSecondary: () {
                  nav.pop();
                  openInvestmentsOrders(nav.context,
                      product: 'predictions', orderKind: 'limit_buy');
                },
              ),
            );
          });
        }
      });
    }
    // Actively-placing = the button is working, so the ticket is inert
    // and the sheet cannot be dismissed out from under the order. Only a
    // failure is terminal here (success hands off to the confirmation,
    // and an unaccounted-for order is still work in progress).
    final betStatus = _isLedger
        ? null
        : ref.watch(pendingPolymarketBetProvider.select((i) => i?.status));
    final placementFailed = (_isPlacing || _prepareFailed) &&
        betStatus == PendingBetStatus.failed;
    final activelyPlacing = _isPlacing && !_placedSuccess && !placementFailed;
    // Where the submitted order is; the button's label follows it.
    final placeStage = _isLedger
        ? null
        : ref.watch(pendingPolymarketBetProvider.select((i) => i?.stage));
    // An earlier submission nobody can account for is settled behind the
    // busy button, never in front of the person.
    if (betStatus == PendingBetStatus.awaitingConfirmation &&
        _isPlacing &&
        !_resolvingPending) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_resolveAwaitingConfirmation());
      });
    }
    final selected = widget.outcomes[_selectedIndex];
    final selectedColor = _colorForOutcome(_selectedIndex);
    // The compact sheet wears the side's colour, so the whole ticket is
    // re-inked on it. Advanced (fullscreen) keeps the neutral palette.
    final tintColors = sideTintPalette(c, selectedColor);
    final tintOn = tintColors.textPrimary;
    // BTC display unit honors Settings → Bitcoin unit. `'sats'` keeps
    // the legacy sats display; anything else (BTC / mBTC / bits) renders
    // as fractional BTC inside the slip — the user's setting is the
    // source of truth, the slip just follows.

    // Unscoped entry points still require the active spending wallet.
    // Explicit Ledger targets use their own approval path and never read
    // the active account while deciding which signer can place this order.
    final activeWallet = _isLedger
        ? null
        : ref.watch(settingsProvider.select((s) => s.activeWallet));
    final cantSign = activeWallet != null &&
        (activeWallet.isHardware ||
            activeWallet.isWatchOnly ||
            activeWallet.isExternalAddress ||
            activeWallet.isSigner);
    if (cantSign) {
      return _buildSwitchToSpendingWall(c);
    }

    // Use live WebSocket prices when available for real-time odds.
    // Only rebuild when prices for this market's tokens change.
    final outcomeTokenIds = widget.outcomes
        .expand((o) => [o.tokenId, if (_isLedger) o.noTokenId])
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
    final livePrices = ref.watch(livePriceProvider.select((s) {
      final filtered = <String, double>{};
      for (final id in outcomeTokenIds) {
        final p = s.prices[id];
        if (p != null) filtered[id] = p;
      }
      return LivePriceState(prices: filtered, live: s.live);
    }));
    // For candidate-picker events, the `selected` outcome is the Yes sub-market;
    // we derive the effective token/price based on whether the user picked the
    // Yes or No pill on that row.
    final String? effectiveTokenId =
        _isCandidatePicker && _buyNo ? selected.noTokenId : selected.tokenId;
    final lp = effectiveTokenId != null
        ? livePrices.prices[effectiveTokenId]
        : (selected.tokenId != null
            ? livePrices.prices[selected.tokenId]
            : null);
    final double yesLive = lp ?? selected.price;
    final double currentPrice = _isLedger
        ? _ledgerDisplayedPrice(livePrices)
        : _isCandidatePicker && _buyNo
            ? (1.0 - yesLive).clamp(0.0, 1.0)
            : yesLive;
    // When the user flips Yes↔No (or picks a different candidate) the price
    // context changes entirely, so re-seed the limit price to the new side's
    // market. Done in build (no setState) so it stays in sync with whatever
    // outcome is currently selected; manual stepper edits persist because the
    // side key is unchanged between them.
    if (_isLimitMode) {
      final sideKey = '${_selectedIndex}_$_buyNo';
      if (_limitSideKey != sideKey) {
        _limitSideKey = sideKey;
        _limitPrice = currentPrice.clamp(0.01, 0.99).toDouble();
      }
    } else {
      _limitSideKey = null;
    }
    // Limit mode sizes against the user's chosen limit price; spot uses the
    // slippage-adjusted market price (so the displayed shares/total match
    // what the CLOB will execute).
    final prepared = ref.watch(pendingPolymarketBetProvider)?.marketQuote;
    final preparedPrice = (_buyInFlight || _isPlacing) &&
            prepared?.tokenId == effectiveTokenId &&
            prepared?.amount == _amount
        ? prepared?.maxPrice
        : null;
    final double orderPrice = (_isLimitMode && _limitPrice > 0)
        ? _limitPrice
        : preparedPrice ?? _orderPriceFor(currentPrice);
    final double shares = _sharesFor(orderPrice);
    final double payout = shares * 1.0;

    double? cash;
    double? spendable;
    // Dollars plus the other venue's reachable cash (hot slip only).
    var otherSpendable = 0.0;
    String available;
    if (widget.ledgerWalletId case final walletId?) {
      final buyingPower = ref.watch(ledgerPmBuyingPowerProvider(walletId));
      if (!buyingPower.hasError && !buyingPower.isLoading) {
        spendable = buyingPower.valueOrNull?.spendable.toDouble();
        if (spendable != null) spendable /= 1e6;
        cash = spendable;
      }
      // The same one-line available figure Home shows. The Ledger branch
      // used to put a whole sentence about connecting the device here,
      // which made the slip read as a different screen.
      available = buyingPower.hasError || spendable == null
          ? '${context.l10n.available} ${_fiatCompanion(0)}'
          : buyingPower.isLoading
              ? context.l10n.loadingAccount
              : '${context.l10n.available} ${_fiatCompanion(spendable)}';
    } else {
      final trading = ref.watch(polymarketTradingProvider);
      final orders = ref.watch(polymarketOpenOrdersProvider);
      // A cash read that failed is unknown, not $0.00: "Updating balance…"
      // until a read lands, never an Available built on a 0.
      final account = trading.valueOrNull;
      cash = account != null && account.balanceKnown
          ? account.usdcBalance
          : null;
      if (!trading.hasError &&
          !orders.hasError &&
          cash != null &&
          orders.valueOrNull != null) {
        var committed = 0.0;
        for (final order in orders.valueOrNull!) {
          if (order.side.toUpperCase() != 'BUY') continue;
          final remaining = ((double.tryParse(order.originalSize) ?? 0) -
                  (double.tryParse(order.sizeMatched) ?? 0))
              .clamp(0.0, double.infinity);
          committed += remaining * (double.tryParse(order.price) ?? 0);
        }
        spendable = (cash - committed).clamp(0.0, double.infinity);
      }
      // "Available" is the whole spendable Investments: this account's
      // free cash plus Dollars and the other venue's reachable cash (the
      // figure the one-balance planner draws on), never the Predictions
      // cash alone. Max works on the same figure (below).
      otherSpendable = ref
          .watch(investmentsSpendableExcludingProvider(
              OneBalanceVenue.predictions))
          .maxUsd;
      ref.watch(venueCashRefreshProvider);
      available = trading.hasError || orders.hasError
          ? context.l10n.feeUiBalanceUnavailable
          : spendable == null
              ? context.l10n.betSlipBalanceUpdating
              : context.l10n.betSlipAvailableAmount(_fiatCompanion(
                  slipAvailableUsd(
                      venueUsd: spendable,
                      otherSpendableUsd: otherSpendable,
                      // Funded bets draw on the spending Bitcoin too; the
                      // line only (Max and the minimum keep their figure).
                      bitcoinUsd:
                          ref.watch(spendingBitcoinLandingUsdProvider))));
    }

    // Max is the largest stake whose stake PLUS venue fees fits what is
    // spendable, sized at the price the order would pay. Until the
    // market's fee curve has loaded the documented maxima apply, which
    // only ever leaves a little more headroom. The engine re-checks the
    // same all-in figure before placing.
    //
    // The fee is sized at the LOWER of the order price and the side's
    // live price: a buy's fee per dollar rises as the fill price falls,
    // and the checks downstream size it at the price shown (the Ledger
    // reserve, the Deposit door) or at the best ask (the placement), not
    // at the slippage-raised order price. A hot market buy also keeps the
    // placement's rounding cent free. Preparation then re-fits a hot Max
    // to the executable best ask exactly.
    double? maxStake;
    // Max reaches past this account's cash: the bet is funded at the tap,
    // so it is not a spend-all of the venue's cash.
    var maxIsFunded = false;
    final maxFeePrice = _isLimitMode
        ? orderPrice
        : min(orderPrice, currentPrice.clamp(0.0001, 0.9999).toDouble());
    _maxFeePrice = maxFeePrice;
    if (spendable case final budget?) {
      final feeToken = effectiveTokenId;
      final terms = feeToken == null || feeToken.isEmpty
          ? PolymarketFeeTerms.worstCase
          : ref.watch(polymarketFeeTermsProvider(feeToken)).valueOrNull ??
              PolymarketFeeTerms.worstCase;
      final reserve = !_isLedger && !_isLimitMode
          ? PolymarketMarketBuyQuote.roundingHeadroom
          : 0.0;
      maxStake = terms.maxNotionalFor(budget, maxFeePrice, reserve: reserve);
      // A hot slip's Max works on the whole spendable Investments: the
      // largest stake this slip's own funding check passes (the venue's
      // cash, else a move the rest of Investments covers, the move's cost
      // counted), so Max never turns the button into "Add".
      if (!_isLedger &&
          otherSpendable > 0 &&
          cash != null &&
          _depositBlock == null) {
        final venueCash = cash;
        final double reachRead = ref
                .watch(venueCashReachExcludingProvider(
                    OneBalanceVenue.predictions))
                .valueOrNull ??
            ref.watch(usdBalanceProvider);
        final reach = min(otherSpendable, reachRead);
        final ready = _predictionsReady(venueCash);
        final held = _fundingPlan;
        final funded = slipMaxFundableUsd(
          upperUsd: terms.maxNotionalFor(
              budget + otherSpendable, maxFeePrice,
              reserve: reserve),
          fits: (stake) {
            final required = _predictionsRequired(terms, stakeUsd: stake);
            if (required <= ready + 1e-9) return true;
            final plan = held != null && held.fundUsd > 0
                ? planBetFunding(
                    requiredUsd: required,
                    readyUsd: ready,
                    routeFee: 1 - held.arrivingUsd / held.fundUsd,
                    minUsd: held.minUsd)
                : planBetFunding(requiredUsd: required, readyUsd: ready);
            return plan.fundUsd * (1 + kSlipMaxMoveHeadroom) <=
                reach + 1e-9;
          },
        );
        if (funded > maxStake) {
          maxStake = funded;
          maxIsFunded = true;
        }
      }
    }

    final ledgerStatus = _isLedger
        ? ref.watch(ledgerPmPendingBetProvider(widget.ledgerWalletId!))
        : null;
    final ledgerLocked = _draft.ledgerBusy ||
        _draft.ledgerPending ||
        (ledgerStatus != null &&
            (ledgerStatus.isLoading ||
                ledgerStatus.hasError ||
                ledgerStatus.valueOrNull != false));

    Widget ticket({required bool fullscreen}) {
      // The compact slip wears the side colour; Advanced keeps the app
      // palette (user decision: only sheets wear the direction).
      final tc = fullscreen ? c : tintColors;
      // The side block is identical on both steps — it says what is being
      // bought — so it is built once.
      final sideBlock = <Widget>[
        if (_isBinary)
          _buildBinaryToggle(tc, livePrices)
        else if (_isThreeWay)
          _buildThreeWayToggle(livePrices)
        else ...[
          _buildSelectedOutcomeHeader(tc, livePrices,
              accentText: tc.textPrimary),
          if (_isCandidatePicker) ...[
            SizedBox(height: 10.h),
            _buildCandidateSideToggle(livePrices),
          ],
        ],
      ];
      // The fee is estimated where the stake is expected to fill, the same
      // price Max and the placement check size it at: the side's live
      // price, never the slippage-raised cap. A buy's fee per dollar rises
      // as the fill price falls, so pricing it at the cap understated it,
      // most on favourites (a 95c side capped at 99.99c showed about no
      // venue fee at all). A limit is priced at its own limit.
      // One balance: a bet short of venue cash moves Dollars first; the
      // move's own cost is folded into the one fee row (the total, plus a
      // "Move fee" detail), never a row of its own.
      final moveFee = _moveFee(cash);
      final feeSummary = PolymarketFeeSummary(
        tokenId: effectiveTokenId,
        shares: _sharesFor(maxFeePrice),
        price: maxFeePrice,
        bitcoinFirst: false,
        limit: _isLimitMode,
        // A bet short of venue cash is funded from Dollars: the row prices
        // it (venue fees plus the move) instead of asking for funds.
        hasFunds: cash == null || cash > 0 || moveFee != null,
        showNote: _showAdvanced,
        moveFeeUsd: moveFee?.usd,
        moveFeeLabel: context.l10n.slipMoveFee,
        moveFeePending: moveFee != null && moveFee.usd == null,
        moveLegs: moveFee?.legs ?? const [],
      );
      final minBetWarning = _amount > 0 && _amount < _effectiveMinBetUsd
          ? Text(
              context.l10n.betMinimumBetIs(_fiatCompanion(_effectiveMinBetUsd)),
              style: TextStyle(fontSize: 14.sp, color: tc.textSecondary),
            )
          : null;
      // A placement that did not go through says so on the ticket the
      // person is still looking at, and the CTA underneath becomes the
      // retry the locked panel used to carry.
      // A funded bet's stop: on the Advanced page it is told in its steps
      // under the button (the failed step, what happened, where the money
      // is), never twice. The plain slip folds its journey away and comes
      // back as it was typed, the same words in this one notice.
      final stopped = _fundedProgress(ref.watch(fundedOrdersProvider));
      final stoppedRecord =
          stopped != null && stopped.failed ? stopped.record : null;
      final fundedStop = placementFailed && stoppedRecord != null;
      final failureNotice = !fullscreen && stoppedRecord != null
          ? PolySlipNotice(
              key: const ValueKey('bet-slip-funded-stop'),
              title: context.l10n.betCouldNotPlacePrediction,
              message:
                  fundedStopLine(context.l10n, stoppedRecord, _fiatCompanion),
            )
          : placementFailed && !fundedStop
              ? PolySlipNotice(
                  title: context.l10n.betCouldNotPlacePrediction,
                  message: ref.watch(pendingPolymarketBetProvider
                          .select((i) => i?.errorMessage)) ??
                      context.l10n.betFundsSafeRetryOrClose,
                )
              : null;

      final action = Padding(
        padding: EdgeInsets.fromLTRB(
            20.w,
            8.h,
            20.w,
            fullscreen
                ? 16.h
                : max(16.h, MediaQuery.of(context).padding.bottom)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_tradeBlock case final reason?)
            CapabilityBlockNote(reason)
          else if (_draft.openOfflineNote case final note? when !_isPlacing)
            CapabilityBlockNote(note),
          if (_advancedBlock case final reason? when reason != _tradeBlock)
            CapabilityBlockNote(reason),
          // While an order waits on a live game's in-play delay, the line
          // over the button says why it is taking a moment.
          if (_liveDelayNote(placeStage, activelyPlacing) case final note?)
            Padding(
              padding: EdgeInsets.only(bottom: 6.h),
              child: Text(
                note,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: tc.textSecondary,
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          // The action fades out and the new one in when it changes what
          // it is (the deposit door giving way to Predict once a deposit
          // lands), never as its amount changes, and never two labels at
          // once.
          () {
            final primary = _buildPrimaryAction(tc, selectedColor, selected,
                busy: activelyPlacing,
                failed: placementFailed,
                busyLabel: _placingLabel(betStatus),
                stepsUnder: fullscreen);
            return ArrivalSwitcher(
              state: primary.key ?? primary.runtimeType,
              alignment: Alignment.bottomCenter,
              sequential: true,
              child: primary,
            );
          }(),
        ]),
      );
      // While the money moves the plain slip shows its journey where the
      // figures were (they and the keypad fold away), the amount staying
      // with one quiet line under it. Worked out after the button, which
      // decides the Dollars door's figure the line under the amount names.
      final journey =
          fullscreen ? null : _fundingJourney(activelyPlacing, running: true);
      final journeyShown = journey != null;
      // The real gap to the market's minimum, said once under the amount
      // while the button is the Dollars door (which names the top-up the
      // route actually needs).
      final double? minimumGap = spendable == null
          ? null
          : _effectiveMinBetUsd -
              slipAvailableUsd(
                  venueUsd: spendable, otherSpendableUsd: otherSpendable);
      final String? heroNote =
          _emptyStake && _doorAddUsd != null && (minimumGap ?? 0) >= 0.005
              ? context.l10n.slipShortOfMinimum(_fiatCompanion(minimumGap!))
              : null;
      // Advanced holds exactly the same controls as before, grouped into
      // four boxes instead of one long run: what you are buying, how much,
      // how the order rests, what it comes to — and the read-only rows
      // folded into Details. Nothing here computes or guards anything.
      final form = Padding(
        padding: EdgeInsets.symmetric(horizontal: 20.w),
        child: fullscreen
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(height: 12.h),
                  Text(polySlipTitle(widget.marketQuestion),
                      style: TextStyle(
                          fontSize: 20.sp,
                          fontWeight: FontWeight.w700,
                          color: tc.textPrimary)),
                  SizedBox(height: 20.h),
                  ...sideBlock,
                  SizedBox(height: 20.h),
                  PolySlipSection(
                    title: context.l10n.amount,
                    trailing: Text(available,
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14.sp, color: tc.textSecondary)),
                    children: [
                      PolySlipAmountField(
                        controller: _amountController,
                        prefix: polyDisplayLabel(ref),
                        readOnly: _draft.ledgerBusy || _draft.ledgerPending,
                        inputFormatters: const [
                          DecimalInputFormatter(fractionDigits: 2)
                        ],
                      ),
                      if (minBetWarning != null) ...[
                        SizedBox(height: 10.h),
                        minBetWarning,
                      ],
                    ],
                  ),
                  SizedBox(height: 14.h),
                  PolySlipSection(
                    title: context.l10n.portfolioTabOrders,
                    children: _buildOrderControls(tc, currentPrice),
                  ),
                  SizedBox(height: 14.h),
                  PolySlipSection(
                    children: [
                      _buildPayout(tc, payout, accentText: tc.textPrimary),
                      SizedBox(height: 10.h),
                      feeSummary,
                    ],
                  ),
                  SizedBox(height: 14.h),
                  PolySlipDetailsGroup(
                    // Opens the rows in a bottom sheet; the event hears it open
                    // and close.
                    onToggle: (open) => TrackingService.track(
                        'bet_slip_advanced_details_toggled',
                        params: {'open': open}),
                    rows: _buildOrderDetails(tc, shares, orderPrice),
                  ),
                  if (failureNotice != null) ...[
                    SizedBox(height: 14.h),
                    failureNotice,
                  ],
                  SizedBox(height: 16.h),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (failureNotice != null) ...[
                    failureNotice,
                    SlipGap(12.h),
                  ],
                  // While the money moves the side is settled: it folds
                  // away with the rest, the order's line says it.
                  FoldAway(
                    folded: journeyShown,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [...sideBlock, SlipGap(22.h)],
                    ),
                  ),
                  // One small Max chip beside the figure, then the
                  // Advanced pill (its dot when it is not the default);
                  // the market's
                  // minimum rides on the available line under it, red while
                  // the stake is under it. A balance too small to stake has
                  // no Max and goes straight to the deposit door instead.
                  // While the money moves the top is the bet itself, one
                  // big number rolling up from what Predictions already
                  // holds to the stake as each leg lands; a stop brings the
                  // amount back as it was typed.
                  ArrivalSwitcher(
                    state: journeyShown,
                    child: journeyShown
                        ? SlipOrderFigure(
                            record: journey.record,
                            orderUsd: _amount,
                            money: _fiatCompanion,
                            orderLine: context.l10n.betSlipPaysIfYouWin(
                                _sideDisplayName(selected),
                                _fiatCompanion(payout)),
                          )
                        : _buildAmountHero(
                            available,
                            belowMinimum: minBetWarning != null,
                            onMax: maxStake != null && maxStake >= _kMinBetUsd
                                ? () => _fillAmount(maxStake!, 100,
                                    budget: maxIsFunded ? null : spendable)
                                : null,
                            maxLocked:
                                _buyInFlight || ledgerLocked || activelyPlacing,
                            advancedModified:
                                _advancedSummary(orderPrice) != null,
                            note: heroNote,
                          ),
                  ),
                  // Two figures, no boxes: what it pays if it wins and the
                  // fee, zero in each until a stake is typed (a tap on the
                  // fee opens its breakdown sheet). Advanced is the pill
                  // beside Max; when it is not the default, a chip under
                  // the amount says what it is set to. They give their
                  // room to the money's journey while it runs.
                  FoldAway(
                    folded: journeyShown,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_advancedSummary(orderPrice)
                            case final summary?) ...[
                          SlipGap(10.h),
                          SlipAdvancedChip(
                              text: summary, onTap: _openAdvanced),
                        ],
                        SlipGap(24.h),
                        SlipFigures(
                          left: _buildPayoutFigure(payout),
                          right: KeyedSubtree(
                            key: const ValueKey('bet-slip-fee-tile'),
                            child: MoneyFeeFigure(child: feeSummary),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SlipJourney(steps: journey?.steps),
                  SlipGap(12.h),
                ],
              ),
      );
      if (fullscreen) {
        // Advanced pins the action as a bottom bar, like the market
        // sheet's Yes / No bar, so the form scrolls underneath it.
        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                key: const ValueKey('prediction-advanced-form-scroll'),
                physics: const ClampingScrollPhysics(),
                primary: false,
                child: IgnorePointer(
                    ignoring: _buyInFlight || ledgerLocked || activelyPlacing,
                    child: form),
              ),
            ),
            KuteStickyActionBar(child: action),
          ],
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IgnorePointer(
            ignoring: _buyInFlight || _draft.ledgerBusy || activelyPlacing,
            child: _buildHeader(tc, selectedColor),
          ),
          // The form over the pinned keypad, fitted to the screen: the
          // keypad gives its room first, then the ticket goes compact,
          // and only then does the form scroll (SlipFormBody).
          Flexible(
            child: SlipFormBody(
              expandForMessage: false,
              form: IgnorePointer(
                  ignoring: _buyInFlight || ledgerLocked || activelyPlacing,
                  child: form),
              // While the money's journey shows the stake cannot change:
              // the keypad folds away and the journey takes its room, so
              // nothing is squeezed. A stop brings it back with the rest
              // of the slip.
              input: FoldAway(
                folded: journeyShown,
                child: _buildAmountKeypad(
                    _buyInFlight || ledgerLocked || activelyPlacing),
              ),
            ),
          ),
          action,
        ],
      );
    }

    // Both steps of the ticket — the compact slip and the fullscreen
    // Advanced page — sit inside the side colour and hand the whole
    // subtree the tinted palette, so every child that reads
    // `context.colors` follows the side without knowing about it.
    final baseTheme = Theme.of(context);
    final tintDuration = MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 200);
    Widget tinted(Widget child) => SheetTint(
          side: selectedColor,
          on: tintOn,
          child: Theme(
            data: baseTheme.copyWith(
              brightness:
                  tintOn == Colors.white ? Brightness.dark : Brightness.light,
              extensions: [
                ...baseTheme.extensions.values
                    .where((e) => e is! AppColorsExtension),
                tintColors,
              ],
            ),
            child: child,
          ),
        );

    if (widget._advanced) {
      // The full-screen Advanced page keeps the app palette (user
      // decision: only sheets wear the side colour).
      return PopScope(
        canPop: !_buyInFlight && !_draft.ledgerBusy && !activelyPlacing,
        child: Builder(
          builder: (context) => PolySlipAdvancedScaffold(
            title: context.l10n.betSlipAdvancedTitle,
            canPop: !_buyInFlight && !_draft.ledgerBusy && !activelyPlacing,
            onBack: () => Navigator.of(context).pop(),
            body: KeyboardDismissOnTap(child: ticket(fullscreen: true)),
          ),
        ),
      );
    }
    // Flipping side inside the sheet (Yes↔No, candidate Yes↔No) slides the
    // whole sheet to the other colour rather than cutting to it.
    return PopScope(
      canPop: !_buyInFlight && !_draft.ledgerBusy && !activelyPlacing,
      child: KeyboardDismissOnTap(
        child: tinted(
          AnimatedContainer(
            duration: tintDuration,
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: selectedColor,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
              border: Border(top: BorderSide(color: tintColors.border)),
            ),
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              // Top inset only, so the action block below is the single
              // place deciding the gap under the button. SafeArea zeroes
              // the bottom padding it consumes for its descendants, so a
              // PlatformSafeArea here left that block reading zero on
              // Android and the real inset on iOS.
              child: SafeArea(
                bottom: false,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: (MediaQuery.of(context).size.height * 0.92 -
                            MediaQuery.of(context).viewInsets.bottom)
                        .clamp(0.0, double.infinity),
                  ),
                  child: SlipFit(child: ticket(fullscreen: false)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Compact slip amount: one big typed figure with the USDC equivalent,
  /// a small Max chip beside it ([onMax]; null hides it, [maxLocked]
  /// dims it, and the Advanced pill after it, with its dot when
  /// [advancedModified]) and the available line beneath it, which also names the
  /// market's minimum ([belowMinimum] paints that part red). There is no
  /// TextField on this step, so the OS keyboard never opens over the
  /// ticket; the pinned [AmountKeypad] under the form is the only way in.
  /// [note] is one quiet line under the available line (how much more the
  /// minimum needs).
  Widget _buildAmountHero(String available,
      {VoidCallback? onMax,
      bool maxLocked = false,
      bool advancedModified = false,
      bool belowMinimum = false,
      String? note}) {
    final currency = ref.watch(settingsProvider.select((s) => s.currency));
    // The figure is typed in the user's own currency while the order is
    // sized in USDC, so a non-USD user gets the dollar equivalent.
    final conversion = currency == 'USD' || _amount <= 0
        ? null
        : '≈ ${NumberFormat.simpleCurrency(name: 'USD', decimalDigits: 2).format(_amount)}';
    return BigAmountDisplay(
      prefix: polyDisplayLabel(ref),
      amountText: _amountController.text,
      conversionLabel: conversion,
      availableLabel: available,
      minimumLabel: context.l10n
          .amountMinimumInline(_fiatCompanion(_effectiveMinBetUsd)),
      minimumIsError: belowMinimum,
      noteLabel: note,
      trailing: SlipAmountPills(
        max: onMax == null
            ? null
            : AmountMaxChip(
                label: context.l10n.max,
                semanticLabel: context.l10n.amountUseMaximum,
                onTap: maxLocked ? null : onMax,
              ),
        advanced: SlipAdvancedButton(
          onTap: _openAdvanced,
          modified: advancedModified,
          enabled: !maxLocked,
        ),
      ),
    );
  }

  /// The compact slip's only amount input, pinned under the scrolling
  /// form so the figure above it never hides behind a keyboard. It edits
  /// the shared draft controller, so the advanced page keeps working on
  /// the same draft, with the same two-decimal rule the formatter
  /// enforced. [locked] is the Ledger lock the form already carries.
  Widget _buildAmountKeypad(bool locked) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8.w),
      child: AmountKeypad(
        value: _amountController.text,
        maxDecimals: 2,
        enabled: !locked,
        onChanged: (v) => _amountController.text = v,
      ),
    );
  }

  /// Writes [pct] percent of [cash] into the figure. The quick-percent
  /// row this replaced is gone from every ticket (owner decision); the
  /// Max chip beside the number stakes all of it.
  void _fillAmount(double cash, int pct, {double? budget}) {
    final target = (cash * pct).floorToDouble() / 100;
    if (target <= 0) return;
    _spendAllBudgetUsd = pct >= 100 ? budget : null;
    _writeFilledAmount(target, pct >= 100 ? 'max' : 'quick_$pct');
  }

  /// The primary button while the stake is under the market's floor: it
  /// reads the minimum and a tap stakes exactly that ([_effectiveMinBetUsd]),
  /// up to the cent so the stake never lands a fraction under it, and
  /// places it in the same tap on the path a typed minimum takes. Where the
  /// balance cannot cover the minimum it is only written and the button
  /// turns into the deposit door for it.
  void _fillMinimum() {
    final target = _minimumStakeUsd(_effectiveMinBetUsd);
    if (target <= 0) return;
    _spendAllBudgetUsd = null;
    // The placement brings its own haptics.
    _writeFilledAmount(target, 'min', haptic: false);
    if (_isLedger) {
      // The Ledger button's own rule: placed when the device's balance
      // covers it, else the deposit door the button then is.
      if (_ledgerCovers(target)) _handleBuy();
      return;
    }
    _placeMinimumOnBuild = true;
  }

  /// Whether a Ledger's read balance covers a stake of [usd].
  bool _ledgerCovers(double usd) {
    final walletId = widget.ledgerWalletId;
    if (walletId == null) return false;
    final buyingPower = ref.read(ledgerPmBuyingPowerProvider(walletId));
    final verified = !buyingPower.isLoading && !buyingPower.hasError
        ? buyingPower.valueOrNull
        : null;
    if (verified == null) return false;
    return usd <= verified.spendable.toDouble() / 1e6 + 1e-9;
  }

  /// No stake typed yet (the slip opens empty): the primary button names
  /// the market's minimum, and a tap places exactly that ([_placeMinimum]).
  bool get _emptyStake => !(_amount > 0);

  /// The empty slip's primary button: writes the market's minimum into
  /// the figure and places it on the path a typed minimum takes (the
  /// same checks, deposit, approval and quote). With [place] false it
  /// only writes it: a Ledger whose balance cannot cover it opens the
  /// deposit instead.
  void _placeMinimum({bool place = true}) {
    final target = _minimumStakeUsd(_effectiveMinBetUsd);
    if (target <= 0) return;
    _spendAllBudgetUsd = null;
    _writeFilledAmount(target, 'min_direct', fromChip: false);
    if (place) _handleBuy();
  }

  /// [minUsd] up to the cent, so a stake of it never lands a fraction
  /// under the floor.
  static double _minimumStakeUsd(double minUsd) =>
      (minUsd * 100 - 1e-6).ceilToDouble() / 100;

  /// Whether a typed stake sits above zero but under the market's floor,
  /// where the primary button offers the minimum instead of the bet.
  bool get _belowMinimumStake =>
      _amount > 0 && _amount.isFinite && _amount < _effectiveMinBetUsd;

  /// [fromChip] false is the empty slip's button placing the minimum:
  /// no chip was tapped, so no chip haptic or event. [haptic] false keeps
  /// the event but leaves the haptic to the placement that follows.
  void _writeFilledAmount(double target, String method,
      {bool fromChip = true, bool haptic = true}) {
    final display = _usdcToFiat(target);
    _fillingAmount = true;
    _amountController.text = display == display.roundToDouble()
        ? display.toStringAsFixed(0)
        : display.toStringAsFixed(2);
    _fillingAmount = false;
    _draft.amountMethod = method;
    _updateState(() => _amount = target);
    if (!fromChip) return;
    if (haptic) HapticFeedback.selectionClick();
    TrackingService.track('bet_slip_available_tapped',
        params: {'chip': method == 'min' ? 'min' : 'max'});
  }

  /// The plain slip's payout figure: what the bet pays if it wins; zero
  /// until a stake is typed.
  Widget _buildPayoutFigure(double payout) {
    final typed = _amount > 0 && payout > 0;
    return SlipFigure(
      key: const ValueKey('bet-slip-payout-tile'),
      label: context.l10n.betReceiptPayout,
      value: typed ? _fiatCompanion(payout) : slipZeroFigure(_fiatCompanion(0)),
    );
  }

  /// The side the bet is on, in the words its button uses ("UP", "Yes",
  /// a team's name).
  String _sideDisplayName(PolymarketOutcome selected) {
    if (_isCandidatePicker) {
      final sides = _sideLabelFor(selected.name);
      return _buyNo ? sides.no : sides.yes;
    }
    if (_isThreeWay) return widget.outcomeLabels![_selectedIndex];
    if (widget.outcomes.length <= 2) {
      return _sideLabelAt(_selectedIndex) ?? selected.name;
    }
    return selected.name;
  }

  /// [accentText] overrides the green payout figure — the side-tinted
  /// sheet passes its own ink, since green on green is not a number.
  Widget _buildPayout(AppColorsExtension c, double payout,
      {Color? accentText}) {
    return PolySlipFigureRow(
      label: context.l10n.betReceiptPayout,
      value: _fiatCompanion(payout),
      valueColor: accentText ?? _kPolyGreen,
    );
  }

  /// What Advanced is set to when it is not the default, for the chip
  /// under the amount (null: the default, no chip and no dot). A limit
  /// names its price; a market order with its own slippage names its
  /// maximum price (the ask plus the slippage, the cap the approval
  /// binds), or the slippage before a stake is typed.
  String? _advancedSummary(double maxPrice) {
    if (_isLimitMode) {
      return context.l10n.betSlipLimitAt(formatPolyCents(_limitPrice));
    }
    final slippage = _draft.slippageChoice ?? kPolymarketDefaultSlippagePct;
    if (slippage == kPolymarketDefaultSlippagePct) return null;
    return _amount > 0 && maxPrice > 0 && maxPrice < 1
        ? context.l10n.betSlipMaxAt(polymarketCentsLabel(maxPrice))
        : context.l10n.slipMaxSlippageSummary(slippage.toStringAsFixed(0));
  }

  Widget _buildCandidateSideToggle(LivePriceState livePrices) {
    final sel = widget.outcomes[_selectedIndex];
    final yesP =
        (sel.tokenId != null ? livePrices.prices[sel.tokenId] : null) ??
            sel.price;
    final pair = formatPolyChancePair(yesP, fineEnds: true);
    final sides = _sideLabelFor(sel.name);
    return _YesNoSideToggle(
      candidate: sel.name,
      yesPrice: pair.first,
      noPrice: pair.second,
      yesLabel: sides.yes,
      noLabel: sides.no,
      showPrices: _showAdvanced,
      isNo: _buyNo,
      onChanged: (no) {
        if (_buyNo == no) return;
        _updateState(() => _buyNo = no);
        HapticFeedback.selectionClick();
        TrackingService.track('bet_slip_side_flipped', params: {
          'side': no ? 'no' : 'yes',
          'candidate': sel.name,
          'market': _truncMarket(widget.marketQuestion),
        });
      },
    );
  }

  /// The two controls people actually open Advanced for: the order type
  /// and whatever that choice needs (a resting limit price, or the
  /// slippage budget for a market buy). Same widgets, same guards, same
  /// events — they just live in the Orders section now.
  List<Widget> _buildOrderControls(AppColorsExtension c, double currentPrice) {
    return [
      _buildOrderTypeToggle(c, currentPrice),
      // What the chosen type does, in one sentence, right where it is
      // chosen.
      SizedBox(height: 10.h),
      Text(
        _isLimitMode
            ? context.l10n.betSlipLimitExplainer
            : context.l10n
                .betSlipMarketExplainer(_slippagePct.toStringAsFixed(0)),
        style: TextStyle(fontSize: 13.sp, color: c.textSecondary, height: 1.4),
      ),
      if (_isLimitMode) ...[
        SizedBox(height: 16.h),
        _buildLimitPriceInput(c, currentPrice),
      ] else ...[
        // Slippage is the one expert knob on a market order: closed by
        // default, opened by the few who know what they are looking for.
        SizedBox(height: 14.h),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _expertOpen = !_expertOpen);
          },
          child: Row(
            children: [
              Expanded(
                child: Text(context.l10n.slipExpertSettings,
                    style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w500)),
              ),
              Icon(
                  _expertOpen
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  color: c.textTertiary),
            ],
          ),
        ),
      ],
      if (!_isLimitMode &&
          (_expertOpen ||
              (_draft.slippageChoice ?? kPolymarketDefaultSlippagePct) !=
                  kPolymarketDefaultSlippagePct)) ...[
        SizedBox(height: 12.h),
        Text(context.l10n.maxSlippage,
            style: TextStyle(
                color: c.textSecondary,
                fontSize: 15.sp,
                fontWeight: FontWeight.w500)),
        SizedBox(height: 8.h),
        Wrap(
          spacing: 8.w,
          runSpacing: 8.h,
          children: [
            for (final opt in _slippageOptions)
              ChoiceChip(
                label: Text('${opt.toStringAsFixed(0)}%'),
                showCheckmark: false,
                selected: _slippagePct == opt,
                backgroundColor: c.surfaceLight,
                selectedColor: context.ctaFill,
                side: BorderSide(color: c.border, width: 0.5),
                labelStyle: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: _slippagePct == opt
                        ? context.ctaOnColor
                        : c.textSecondary),
                onSelected: (_) {
                  final previous = _slippagePct;
                  _updateState(() => _slippagePct = opt);
                  HapticFeedback.selectionClick();
                  if (previous != opt) {
                    TrackingService.polymarketSlippageAdjusted(
                        oldSlippage: previous, newSlippage: opt);
                  }
                  TrackingService.track('bet_slip_slippage_changed',
                      params: {'slippage_pct': opt});
                  TrackingService.track('prediction_slippage_adjusted',
                      params: {
                        'slippage_pct': opt,
                        'slippage_pct_bucket': opt.toStringAsFixed(0),
                      });
                },
              ),
          ],
        ),
      ],
    ];
  }

  /// Read-only description of the order, folded into the Details group:
  /// the estimated shares and price the page used to print at the very
  /// bottom, the limit order's duration, and the account it spends from.
  List<Widget> _buildOrderDetails(
      AppColorsExtension c, double shares, double orderPrice) {
    return [
      PolySlipDetailRow(
          label: context.l10n.betSlipEstimatedShares,
          value: shares.toStringAsFixed(2)),
      SizedBox(height: 12.h),
      PolySlipDetailRow(
          // A market order's figure is its maximum (the approved cap).
          label: _isLimitMode
              ? context.l10n.betPricePerShare
              : context.l10n.ledgerBetWorstPrice,
          value: _fiatCompanion(orderPrice)),
      if (_isLimitMode) ...[
        SizedBox(height: 12.h),
        PolySlipDetailRow(
            label: context.l10n.betOrderDuration,
            value: context.l10n.betUntilCanceled),
      ],
      SizedBox(height: 12.h),
      _buildFundingSource(c),
    ];
  }

  /// The money's journey for the bet on this slip, or null when no money
  /// moves for it: a funded bet's steps (from Bitcoin, Dollars, Investing
  /// or any mix) from the moment it was approved, through the placement,
  /// to the end; a stop keeps them, the failed step marked and one line
  /// saying where the money is. A fast market's money made ready before
  /// Confirm and still moving shows its step too. [line] says what pays
  /// for the bet. The plain slip shows it at the top, where its figures
  /// were; the Advanced page under its button.
  /// With [running], a stopped bet has none: the plain slip comes back
  /// as it was, the stop said in one notice over it.
  ({Widget steps, FundedOrderRecord? record})? _fundingJourney(
      bool busy,
      {bool running = false}) {
    if (_draft.openBlockRegion && _tradeBlock != null && !busy) return null;
    if (_isLedger) return null;
    final progress = _fundedProgress(ref.watch(fundedOrdersProvider));
    if (progress != null) {
      if (running && progress.failed) return null;
      return (
        steps: SlipFundingSteps(
          steps: _fundingSteps(progress.record),
          active: progress.active,
          slow: progress.record.slow,
          failed: progress.failed,
          graph: progress.record.steps,
          money: _fiatCompanion,
          from: progress.record.fromBitcoin
              ? MoneyPlace.bitcoin
              : MoneyPlace.dollars,
          to: MoneyPlace.predictions,
          note: progress.failed
              ? fundedStopLine(context.l10n, progress.record, _fiatCompanion)
              : null,
        ),
        record: progress.record,
      );
    }
    final prefund = _draft.prefund;
    if (prefund != null && prefund.moving && !busy && !_isPlacing) {
      return (
        steps: SlipFundingSteps(
          key: const ValueKey('bet-slip-prefund-progress'),
          steps: [
            context.l10n.slipStepPreparingPrediction,
            context.l10n
                .slipStepPlacingBet(_fiatCompanion(_amount), _outcomeSide),
          ],
          active: 0,
          to: MoneyPlace.predictions,
        ),
        record: null,
      );
    }
    return null;
  }

  /// [busy] is the placement actually running, [failed] its one terminal
  /// error state. The panel that used to own both is gone: the button
  /// carries the wait, and becomes the retry when it ends badly.
  /// With [stepsUnder] (the Advanced page) the money's journey shows
  /// under the button.
  Widget _buildPrimaryAction(
      AppColorsExtension c, Color selectedColor, PolymarketOutcome selected,
      {required bool busy,
      required bool failed,
      required String busyLabel,
      bool stepsUnder = false}) {
    _doorAddUsd = null;
    // Taken once, by this build: the minimum the under-the-floor button
    // wrote is placed only by the bet button below, never later.
    final placeFilledMinimum = _placeMinimumOnBuild;
    _placeMinimumOnBuild = false;
    // A region refusal: the one button asks again, never a dead one.
    if (_draft.openBlockRegion && _tradeBlock != null && !busy) {
      return PolySlipCta(
        key: const ValueKey('bet-slip-check-connection'),
        color: context.ctaFill,
        neutral: true,
        isBusy: _checkingConnection,
        busyLabel: context.l10n.checkConnection,
        bandExpected: const Duration(seconds: 2),
        enabled: !_checkingConnection,
        onTap: _checkConnection,
        label: context.l10n.checkConnection,
      );
    }
    if (_isLedger) return _buildLedgerPrimaryAction(c, selectedColor);
    // A bet whose money is being moved: one busy button while its steps
    // run ([_fundingJourney]), the try again once they stopped.
    final journey = stepsUnder ? _fundingJourney(busy) : null;
    final records = ref.watch(fundedOrdersProvider);
    final progress = _fundedProgress(records);
    if (progress != null) {
      final steps = _fundingSteps(progress.record);
      final running = !progress.failed && !progress.done;
      final Widget button;
      if (running || progress.done) {
        final label = steps[progress.active.clamp(0, steps.length - 1)];
        button = PolySlipCta(
          color: selectedColor,
          // Dark on the white button (founder decision).
          neutral: true,
          isBusy: true,
          busyLabel: label,
          // The steps name the step: the button only spins (a screen
          // reader still hears the step).
          busyLabelInSteps: true,
          enabled: false,
          onTap: () {},
          label: label,
          band: false,
        );
      } else {
        button = _buildPrimaryActionInner(c, selectedColor, selected,
            busy: busy,
            failed: failed,
            busyLabel: busyLabel,
            band: false,
            placeFilledMinimum: placeFilledMinimum);
      }
      return RubberBandProgress(
        key: const ValueKey('bet-slip-funded-progress'),
        progress: progress.progress,
        outcome: progress.done
            ? RubberBandOutcome.success
            : progress.failed
                ? RubberBandOutcome.failure
                : RubberBandOutcome.none,
        child: journey == null
            ? button
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [button, journey.steps],
              ),
      );
    }
    final action = _buildPrimaryActionInner(c, selectedColor, selected,
        busy: busy,
        failed: failed,
        busyLabel: busyLabel,
        placeFilledMinimum: placeFilledMinimum);
    if (journey == null) return action;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [action, journey.steps],
    );
  }

  Widget _buildPrimaryActionInner(
      AppColorsExtension c, Color selectedColor, PolymarketOutcome selected,
      {required bool busy,
      required bool failed,
      required String busyLabel,
      bool band = true,
      bool placeFilledMinimum = false}) {
    // The placement's band: pulled while it places, snapped back once it
    // placed, let go softly when it did not.
    final bandOutcome = _placedSuccess ? RubberBandOutcome.success : null;
    // After a stop the button is the same bet again, said so: "Try again
    // · Place $12.00 on UP". It draws on the money already moved (in
    // Predictions, or back in Investments, which Available counts), adding
    // only what is still missing.
    final fundedStopped = !_isLedger &&
        (_fundedProgress(ref.watch(fundedOrdersProvider))?.failed ?? false);
    String again(String label) =>
        fundedStopped ? '${context.l10n.walletsTryAgain} · $label' : label;
    final trading = ref.watch(polymarketTradingProvider);
    // Nothing to bet with, or not enough for this bet once the venue's
    // fees are counted: the button is the deposit door, never a dead
    // Predict label (user decision). The tap runs the same placement,
    // which opens the deposit and fires the bet once the funds land.
    final cash = trading.valueOrNull?.usdcBalance;
    final terms = ref
            .watch(polymarketFeeTermsProvider(selected.tokenId ?? ''))
            .valueOrNull ??
        PolymarketFeeTerms.worstCase;
    // Money moved to get this bet ready and still on its way counts as
    // there: the button stays the bet (Confirm queues it behind the move).
    final prefund = _draft.prefund;
    final prefundIncoming = prefund?.inFlightArrivingUsd ?? 0;
    // The stake the button stands for: what is typed, or the market's
    // minimum the empty slip's button places. Measured on that, a slip
    // whose Investments cannot cover even the minimum reads "Add $X to
    // Investments" from the start, never a bet whose tap only opens the
    // deposit.
    final stake =
        _emptyStake ? _minimumStakeUsd(_effectiveMinBetUsd) : _amount;
    final noFunds = trading.hasValue &&
        !trading.hasError &&
        cash != null &&
        (cash + prefundIncoming < 0.01 ||
            _predictionsShortfall(cash + prefundIncoming, terms,
                    stakeUsd: stake) >
                0);
    if (failed) {
      final stop = betSlipStopAction(
          context.l10n, ref.watch(pendingPolymarketBetProvider));
      // A short round that ended with its bet not placed: nothing more
      // goes in on it. The line under the steps says where the money is;
      // the button opens the series' round in play, the same side and
      // stake, for the person to confirm there.
      if (stop.nextRound) {
        return PolySlipCta(
          key: const ValueKey('bet-slip-retry-next-round'),
          band: band,
          color: selectedColor,
          // Dark on the white button, never the side colour (founder).
          neutral: true,
          isBusy: _buyInFlight || busy,
          busyLabel: context.l10n.loading,
          enabled: !_buyInFlight && !busy,
          onTap: _retryOnCurrentRound,
          label: '${context.l10n.walletsTryAgain} · '
              '${_betCtaLabel(selected, _amount)}',
        );
      }
      return PolySlipCta(
        key: const ValueKey('bet-slip-retry'),
        band: band,
        color: selectedColor,
        // Dark on the white button, never the side colour (founder).
        neutral: true,
        isBusy: _buyInFlight || busy,
        busyLabel: context.l10n.loading,
        enabled: !_buyInFlight && !busy,
        onTap: _isPlacing ? _retryPlacement : _retryFromStart,
        // Stopped because the price moved past the approved maximum: the
        // retry names the new maximum it will ask to approve; else it is
        // the same bet again, named ("Try again · Place $12.00 on UP").
        label: stop.label == context.l10n.retry
            ? '${context.l10n.walletsTryAgain} · '
                '${_betCtaLabel(selected, _amount)}'
            : stop.label,
      );
    }
    // Until the Predictions account is set up and its balance was read,
    // the button waits: a 0 that only means "not read yet" must never
    // turn it into the Deposit door, nor let a tap through.
    final balanceKnown =
        trading.hasValue && (trading.valueOrNull?.balanceKnown ?? false);
    if (!balanceKnown && !_isPlacing && !busy && !_buyInFlight) {
      return PolySlipCta(
        key: const ValueKey('bet-slip-loading-account'),
        color: context.ctaFill,
        neutral: true,
        isBusy: true,
        busyLabel: context.l10n.loadingAccount,
        enabled: false,
        onTap: () {},
        label: context.l10n.loadingAccount,
      );
    }
    if (noFunds && !_isPlacing) {
      // A deposit into Predictions already on its way: say so, never offer
      // a second one while it lands.
      final shortfall = _predictionsShortfall(cash, terms, stakeUsd: stake);
      final funding = slipFunding(shortfallUsd: shortfall);
      // A closed trade gate keeps its own shut door and note; a deposit
      // already on its way still reads as incoming when new deposits are
      // withheld, only "Add more" goes.
      if (funding.isIncoming &&
          _tradeBlock == null &&
          !(prefund?.engaged ?? false)) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PolySlipCta(
              key: const ValueKey('bet-slip-deposit-incoming'),
              color: context.ctaFill,
              neutral: true,
              // Disabled, like the order slip's: the line under it says
              // what is happening.
              isBusy: false,
              enabled: false,
              onTap: () {},
              label: context.l10n
                  .slipDepositIncoming(_fiatCompanion(funding.incomingUsd)),
            ),
            SlipIncomingDepositNote(
              onAddMore: funding.state == SlipFundingState.incomingShort &&
                      _depositBlock == null
                  ? () => _addMoreDeposit(shortfall, funding.incomingUsd)
                  : null,
            ),
          ],
        );
      }
      // One balance: the bet funds its shortfall from Dollars at the tap.
      // Only when Dollars cannot cover that move either is the button the
      // Dollars door, naming exactly what is missing.
      final required = _predictionsRequired(terms, stakeUsd: stake);
      final ready = _predictionsReady(cash) + prefundIncoming;
      _refreshFundingPlan(required: required, ready: ready, stakeUsd: stake);
      final plan = _fundingPlanAmount == stake && _fundingPlan != null
          ? _fundingPlan!
          : planBetFunding(requiredUsd: required, readyUsd: ready);
      // Dollars plus Investing cash: the bet pulls what Dollars lack.
      final dollarsOnly = ref.watch(usdBalanceProvider);
      final dollars = dollarsOnly + 1e-9 >= plan.fundUsd
          ? dollarsOnly
          : (ref
                  .watch(venueCashReachExcludingProvider(
                      OneBalanceVenue.predictions))
                  .valueOrNull ??
              dollarsOnly);
      var missing = slipDollarsShortfallUsd(
          topUpUsd: plan.fundUsd, dollarsUsd: dollars);
      // The button names exactly what the Bitcoin leg would add for the
      // stake (typed, or the minimum an empty slip places; the same
      // rounding, the route minimum): the tap converts that and nothing
      // more when the bitcoin covers it, else opens the Investments
      // Receive sheet. Whether it covers is decided at the tap on the
      // wallet's own figures, so a balance or price still loading here
      // never decides where the tap goes.
      final bitcoinAdd = BitcoinLegRules.addUsd(
          fundUsd: plan.fundUsd, investmentsUsd: dollars);
      _shownAddUsd = missing <= 0 || _isLedger
          ? null
          : bitcoinAdd > 0
              ? bitcoinAdd
              : missing;
      if (_shownAddUsd != null) {
        missing = _shownAddUsd!;
        _warmBitcoinLeg();
      }
      if (missing > 0) {
        _doorAddUsd = missing;
        final door = _depositDoor(
          // Busy while the tap is worked out (the bitcoin read, the prefill)
          // and while it runs the bet; shut until the tap (and the Dollars
          // door it may open) is done.
          busy: _doorCalculating || (_bitcoinArmed && _buyInFlight),
          busyLabel: context.l10n.feeUiCalculating,
          enabled: !_buyInFlight && !_doorCalculating,
          onTap: _onAddDollarsTap,
          // Both deeds, short: what is added, then the bet placed right
          // after it ("Add $1.00 · $12.00 on No"). An empty slip (the tap
          // places the minimum after the top-up) says only the bet.
          label: again(_emptyStake
              ? _betCtaLabel(selected, stake, empty: true)
              : context.l10n.slipAddThenOrder(_fiatCompanion(missing),
                  _betCtaLabel(selected, stake, afterTopUp: true))),
        );
        if (!funding.failed) return door;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [const SlipDepositFailedNote(), door],
        );
      }
      // Dollars cover the move: the bet itself, funded at the tap.
    } else if (cash != null && trading.hasValue && !trading.hasError) {
      // Only a balance that was read and covers the bet ends the wait; a
      // refresh in flight keeps what the slip is following.
      slipFundingCovered();
      if (_fundingPlan != null) {
        _fundingPlan = null;
        _fundingPlanAmount = null;
      }
    }
    // A stake under the market's floor: the one button names the minimum
    // and a tap places exactly that, so the disabled bet never sits there
    // unexplained ([_fillMinimum]).
    if (_belowMinimumStake) {
      return PolySlipCta(
        band: band,
        bandOutcome: bandOutcome,
        color: selectedColor,
        // Dark on the white button, never the side colour (founder).
        neutral: true,
        isBusy: busy || _buyInFlight,
        busyLabel: busyLabel,
        enabled: !_isPlacing &&
            !_buyInFlight &&
            _advancedBlock == null &&
            _tradeBlock == null,
        onTap: _fillMinimum,
        label: context.l10n
            .amountMinimumInline(_fiatCompanion(_effectiveMinBetUsd)),
      );
    }
    // Nothing typed yet: the button is the bet at the market's minimum,
    // and a tap places exactly that.
    final placeMinimum = _emptyStake;
    final enabled = (placeMinimum || _amount >= _effectiveMinBetUsd) &&
        !_isPlacing &&
        !_buyInFlight &&
        _advancedBlock == null &&
        _tradeBlock == null;
    // The build after the under-the-floor button wrote the minimum, with
    // the bet button standing for it: the same tap places it.
    if (placeFilledMinimum && enabled && !placeMinimum) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _handleBuy();
      });
    }
    return PolySlipCta(
      band: band,
      bandOutcome: bandOutcome,
      color: selectedColor,
      // Dark on the white button, never the side colour (founder).
      neutral: true,
      // A placement runs a few seconds: signing, the venue, its answer.
      bandExpected: const Duration(seconds: 3),
      isBusy: busy || _buyInFlight,
      busyLabel: busyLabel,
      enabled: enabled,
      onTap: placeMinimum ? _placeMinimum : _handleBuy,
      label: again(placeMinimum
          ? _betCtaLabel(selected, 0, empty: true)
          : _betCtaLabel(selected, _amount)),
    );
  }

  /// The bet button's words for a stake of [amountUsd] on [selected].
  /// [empty]: nothing typed yet, the bet's short name with no amount
  /// ("Place minimum on No"). [afterTopUp]: the bet after an "Add $1.00 · ",
  /// without its verb ("$12.00 on No").
  String _betCtaLabel(PolymarketOutcome selected, double amountUsd,
      {bool empty = false, bool afterTopUp = false}) {
    if (empty) return context.l10n.betPlaceOnSide(_sideDisplayName(selected));
    // When the input is in sats (BTC tab) show sats.
    // Otherwise route through the localized fiat helper
    // so a UK user sees `Predict YES · £8.05` instead
    // of `$10.00`.
    final amountStr = _fiatCompanion(amountUsd);
    if (afterTopUp && !_isLimitMode) {
      return context.l10n
          .betAmountOnSide(amountStr, _sideDisplayName(selected));
    }
    // Limit orders read as "Place limit · 39¢ · $X" so the
    // CTA is unmistakably a resting order, not a market buy.
    if (_isLimitMode) {
      return context.l10n
          .betPlaceLimitCta(formatPolyCents(_limitPrice), amountStr);
    }
    if (_isCandidatePicker) {
      final sides = _sideLabelFor(selected.name);
      final sideLabel = _buyNo ? sides.no : sides.yes;
      return context.l10n.betPredictSide(sideLabel, amountStr);
    }
    if (_isThreeWay) {
      return context.l10n
          .betPredictSide(widget.outcomeLabels![_selectedIndex], amountStr);
    }
    if (widget.outcomes.length <= 2) {
      // Binary: the selected side's own label, the one its toggle
      // button shows (team names, UP/DOWN, Over/Under …), else
      // the raw outcome name. Read by index: it used to test
      // "is the outcome called No", so DOWN read "Place … on UP".
      final name = _sideLabelAt(_selectedIndex) ?? selected.name;
      return context.l10n.betPredictSide(name, amountStr);
    }
    return context.l10n.betPredictAmount(amountStr);
  }

  // ── Funding source ─────────────────────────────────────────────────────

  /// The "Move fee": what moving the shortfall from Dollars costs, from
  /// the slip's funding plan, for the fee summary to fold into its row.
  /// Null while the venue cash covers the stake (nothing moves), on a
  /// Ledger slip, or before the stake is typed; a null `usd` while the
  /// plan for this stake is still being read.
  ///
  /// A move from more than Dollars (Bitcoin, the Investing cash, every
  /// leg at once) is every leg's fee added, each leg its own line
  /// ([estimateOrderFundingFees]), never the Dollars route's share on the
  /// whole move.
  ({double? usd, List<MoneyFeeLeg> legs})? _moveFee(double? cash) {
    if (_isLedger || cash == null || _amount <= 0) return null;
    final terms = ref
            .watch(polymarketFeeTermsProvider(_selectedTokenId ?? ''))
            .valueOrNull ??
        PolymarketFeeTerms.worstCase;
    if (_predictionsShortfall(cash, terms) <= 0) return null;
    final plan = _fundingPlanAmount == _amount ? _fundingPlan : null;
    if (plan == null) return (usd: null, legs: const []);
    final fees = _fundingFees(plan);
    if (fees.isEmpty || fees.dollarsOnly) {
      return (usd: plan.feeUsd, legs: const []);
    }
    return (
      usd: fees.totalUsd,
      legs: [
        for (final leg in fees.legs)
          (
            label: fundingLegFeeLabel(context.l10n, leg.source),
            usd: leg.feeUsd
          ),
      ],
    );
  }

  /// Every leg the move of [plan] would take and its fee, on the figures
  /// the app holds now (Dollars, the spending bitcoin, the Investing
  /// cash). Reads nothing new.
  OrderFundingFees _fundingFees(OrderFundingPlan plan) =>
      estimateOrderFundingFees(
        fundUsd: plan.fundUsd,
        arrivingUsd: plan.arrivingUsd,
        dollarsUsd: _dollarsUsd(),
        venue: OneBalanceVenue.predictions,
        bitcoinMaxUsd: bitcoinMaxLandingUsd(cachedSpendingBitcoin(ref.read)),
        bitcoinSpread: _fundingBitcoinSpread ?? BitcoinLegRules.fallbackSpread,
        otherVenues: venueCashCandidatesNow(ref.read),
      );

  /// Source account detail in the advanced order summary.
  Widget _buildFundingSource(AppColorsExtension c) {
    if (widget.ledgerWalletId case final walletId?) {
      final buyingPower = ref.watch(ledgerPmBuyingPowerProvider(walletId));
      final spendable = buyingPower.isLoading || buyingPower.hasError
          ? null
          : buyingPower.valueOrNull?.spendable;
      return PolySlipDetailRow(
        label: context.l10n.predictions,
        value: spendable == null
            ? context.l10n.ledgerBalanceUnavailable
            : _fiatCompanion(spendable.toDouble() / 1e6),
      );
    }
    final usdc = ref.watch(polymarketTradingProvider
        .select((s) => s.valueOrNull?.usdcBalance ?? 0));
    return PolySlipDetailRow(
        label: context.l10n.betSlipFromPredictions,
        value: _fiatCompanion(usdc));
  }

  // ── Placement progress ─────────────────────────────────────────────────

  /// "While the game is live, orders wait 1s…" while a market order (or a
  /// limit order the venue is holding) waits on the game's in-play delay.
  String? _liveDelayNote(PendingBetStage? stage, bool placing) {
    if (!placing || _isLedger) return null;
    if (stage != PendingBetStage.submitting &&
        stage != PendingBetStage.delayed) {
      return null;
    }
    if (_isLimitMode && stage != PendingBetStage.delayed) return null;
    final delay =
        _liveDelays[widget.outcomes[_selectedIndex].conditionId ?? ''] ?? 0;
    return delay > 0 ? context.l10n.polyGameInPlayDelay('$delay') : null;
  }

  /// The order got fewer shares than it asked for: what it got, of what,
  /// at what price per share (the venue's, else the price asked).
  ({String bought, String total, String price})? _partialFill(
      PendingBetIntent? intent) {
    final bought = intent?.filledShares;
    final ordered = intent?.orderedShares;
    if (intent == null ||
        bought == null ||
        ordered == null ||
        bought <= 0 ||
        bought >= ordered - 0.01) {
      return null;
    }
    final cost = intent.filledCost;
    final price = cost != null
        ? cost / bought
        : (intent.isLimit ? intent.limitPrice : intent.expectedPrice);
    return (
      bought: bought.toStringAsFixed(2),
      total: ordered.toStringAsFixed(2),
      price: formatPolyCents(price),
    );
  }

  /// What the busy CTA says while the placement runs. The panel this
  /// replaced carried the same words over a progress bar; the bar is gone
  /// because the button is the progress now, but the steps of a swap leg
  /// are still worth naming, so they stay on the label.
  String _placingLabel(PendingBetStatus? status) {
    if (!_swapNeeded) {
      final l10n = context.l10n;
      // Before the order is sent: the account's one-time setup, when it
      // is what the button is waiting on.
      if (!_isPlacing &&
          !ref.read(polymarketTradingProvider.notifier).tradingReady) {
        return l10n.betSettingUpWallet;
      }
      return switch (ref.read(pendingPolymarketBetProvider)?.stage) {
        PendingBetStage.settingUp => l10n.betSettingUpWallet,
        PendingBetStage.approving => l10n.betApprovingSpend,
        PendingBetStage.confirming => l10n.betMatchedConfirming,
        _ => l10n.betPlacingPrediction,
      };
    }
    // One balance: the funding leg is on its way, then the order. Phrased
    // around the bet, never as money moving into Investments (it is there).
    final moving = context.l10n.slipStepPreparingPrediction;
    switch (status) {
      case PendingBetStatus.placing:
      case PendingBetStatus.done:
      case PendingBetStatus.awaitingConfirmation:
        return context.l10n.betPlacingOrder;
      default:
        return moving;
    }
  }

  // ── Switch-to-spending wall ────────────────────────────────────────────

  Widget _buildSwitchToSpendingWall(AppColorsExtension c) {
    final settings = ref.watch(settingsProvider);
    // The "spending wallet" for predictions is the first hot wallet —
    // not hardware / watch-only / tracked / signer-only. There can be
    // at most one of these (`project_one_spending_wallet`).
    final spending = settings.wallets.where((w) =>
        !w.isHardware && !w.isWatchOnly && !w.isExternalAddress && !w.isSigner);
    final hasSpending = spending.isNotEmpty;
    final spendingId = hasSpending ? spending.first.id : null;

    return Scaffold(
      backgroundColor: context.isDark
          ? context.colors.gradientBottom
          : context.colors.background,
      body: Container(
        decoration: AppDecorations.screenGradient(context),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 4.h),
                child: Row(
                  children: [
                    KuteCloseButton(
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 28.w),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 72.sp,
                        height: 72.sp,
                        decoration: BoxDecoration(
                          color: c.surfaceLight,
                          borderRadius: BorderRadius.circular(16.r),
                          border: Border.all(color: c.borderSubtle, width: 0.5),
                        ),
                        child: Icon(
                          Icons.swap_horiz_rounded,
                          color: c.textSecondary,
                          size: 36.sp,
                        ),
                      ),
                      SizedBox(height: 20.h),
                      Text(
                        hasSpending
                            ? context.l10n.betSwitchToSpendingWallet
                            : context.l10n.betAddSpendingWallet,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 20.sp,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                      SizedBox(height: 10.h),
                      Text(
                        hasSpending
                            ? context.l10n.betSigningOnlyCantPlaceOrders
                            : context.l10n.betNeedSpendingWallet,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 14.sp,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 24.h),
                // Dark primary tier (AppButton fires the light haptic
                // itself and picks the label contrast per mode).
                child: AppButton(
                  text: hasSpending
                      ? context.l10n.betSwitchWallet
                      : context.l10n.betCreateSpendingWallet,
                  fontWeight: FontWeight.w800,
                  onPressed: () async {
                    if (hasSpending && spendingId != null) {
                      await ref
                          .read(settingsProvider.notifier)
                          .setActiveWallet(spendingId);
                      if (context.mounted) Navigator.of(context).pop();
                    } else {
                      if (context.mounted) {
                        TrackingService.track('add_wallet_cta_tapped',
                            params: {'source': 'prediction_slip'});
                        Navigator.of(context).pop();
                        context.pushNamed('addWallet');
                      }
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────

  Widget _buildHeader(AppColorsExtension c, Color accentColor) {
    // The shared ticket header (market thumb + question + close X). No
    // Sal here: the slip is the moment of decision.
    return PolySlipHeader(
      marketQuestion: widget.marketQuestion,
      marketImage: widget.marketImage,
    );
  }

  // ── Binary toggle ──────────────────────────────────────────────────────

  Widget _buildBinaryToggle(AppColorsExtension c, LivePriceState livePrices) {
    // Structural positive/negative — works for Yes/No, Day/Night,
    // Even/Odd, On/Off, Up/Down and any other complementary pair the
    // market has. The positive side renders green, the negative red,
    // and the label comes from the outcome's own name so we honour the
    // market's actual wording.
    final positiveIdx = _positiveIndex;
    final negativeIdx = _negativeIndex;

    // YES + NO must sum to 1 by definition (complementary CTF tokens),
    // but the live-price websocket emits each side independently and a
    // brief drift between updates can make our display sum to 99¢ or
    // 101¢ (e.g. YES 45¢ + NO 56¢ — visually broken). To guarantee
    // sum-to-1, pick a single canonical YES probability and derive NO
    // from it. Source-of-truth priority:
    //   1. positive (YES) live price if it's a real probability
    //   2. negative (NO) live price → invert to YES
    //   3. positive's static .price (initial fetch from Gamma)
    //   4. negative's static .price → invert to YES
    final canonicalYes = _binaryYesPrice(livePrices);

    // The two sides written off the one price, at one precision, so the
    // toggle buttons always add up to 100.
    final pricePair = formatPolyChancePair(canonicalYes, fineEnds: true);
    String liveOdds(int idx) =>
        idx == positiveIdx ? pricePair.first : pricePair.second;

    String upperName(int idx) => widget.outcomes[idx].name.toUpperCase();

    // Semantic side labels (team names, OVER/UNDER, UP/DOWN …), each
    // matched to the outcome it names; otherwise the real outcome names.
    String labelFor(int idx) => _sideLabelAt(idx) ?? upperName(idx);
    // The disc names the outcome, never yes/no on a market that is not:
    // a check and a cross only on a literal Yes/No, arrows on Up/Down.
    IconData iconFor(int idx) => _sideGlyphIcon(labelFor(idx));

    return Row(
      children: [
        Expanded(
          child: _BinaryToggleButton(
            label: labelFor(positiveIdx),
            price: _showAdvanced ? liveOdds(positiveIdx) : null,
            color: _colorForOutcome(positiveIdx),
            icon: iconFor(positiveIdx),
            selected: _selectedIndex == positiveIdx,
            onTap: () {
              _updateState(() => _selectedIndex = positiveIdx);
              HapticFeedback.selectionClick();
              _trackOutcomeChip(upperName(positiveIdx).toLowerCase());
              TrackingService.track('bet_slip_outcome_toggled', params: {
                'side': upperName(positiveIdx).toLowerCase(),
                'market': _truncMarket(widget.marketQuestion),
              });
            },
          ),
        ),
        SizedBox(width: 10.w),
        Expanded(
          child: _BinaryToggleButton(
            label: labelFor(negativeIdx),
            price: _showAdvanced ? liveOdds(negativeIdx) : null,
            color: _colorForOutcome(negativeIdx),
            icon: iconFor(negativeIdx),
            selected: _selectedIndex == negativeIdx,
            onTap: () {
              _updateState(() => _selectedIndex = negativeIdx);
              HapticFeedback.selectionClick();
              _trackOutcomeChip(upperName(negativeIdx).toLowerCase());
              TrackingService.track('bet_slip_outcome_toggled', params: {
                'side': upperName(negativeIdx).toLowerCase(),
                'market': _truncMarket(widget.marketQuestion),
              });
            },
          ),
        ),
      ],
    );
  }

  /// The three sides of a three-way match as the binary toggle's buttons,
  /// one per winner market ("Leeds | Draw | Man Utd"), each in its line's
  /// colour. Without the side disc: three to a row leave the name no room
  /// beside it.
  Widget _buildThreeWayToggle(LivePriceState livePrices) {
    final labels = widget.outcomeLabels!;
    Widget side(int i) {
      final o = widget.outcomes[i];
      final price =
          (o.tokenId != null ? livePrices.prices[o.tokenId] : null) ?? o.price;
      return Expanded(
        child: _BinaryToggleButton(
          label: labels[i],
          price: _showAdvanced ? formatPolyChance(price) : null,
          color: _colorForOutcome(i),
          icon: null,
          selected: _selectedIndex == i,
          onTap: () {
            _updateState(() => _selectedIndex = i);
            HapticFeedback.selectionClick();
            final key = gameIsDrawName(o.name) ? 'draw' : o.name.toLowerCase();
            _trackOutcomeChip(key);
            TrackingService.track('bet_slip_outcome_toggled', params: {
              'side': key,
              'market': _truncMarket(widget.marketQuestion),
            });
          },
        ),
      );
    }

    return Row(
      children: [
        side(0),
        SizedBox(width: 8.w),
        side(1),
        SizedBox(width: 8.w),
        side(2),
      ],
    );
  }

  // ── Multi-outcome list (scrollable, no overflow) ───────────────────────

  /// Parse an outcome name into `(group, line)`:
  ///   "Jarrett Allen: Rebounds O/U 1.5" → ("Jarrett Allen", "Rebounds O/U 1.5")
  ///   "Knicks vs. Cavaliers: Team to Score First" → ("Knicks vs. Cavaliers",
  ///       "Team to Score First")
  ///   "RBLS" → (null, "RBLS")
  /// On `: `-split prefixes we treat the prefix as the group key, which Polymarket
  /// uses consistently for player-prop and team-prop multi-outcome events.

  /// Detect "Over/Under N" markers (e.g. "Rebounds O/U 1.5"). Returns
  /// the threshold string so the row can render "Over 1.5" / "Under 1.5".
  /// Recognises common variants: "O/U", "Over/Under", "OU".

  /// Compact header for the already-chosen outcome on multi-outcome
  /// markets — replaces the full scrollable candidate list inside the
  /// slip (the candidate is picked on the market screen now). Shows the
  /// thumb + name; the Yes/No %s are only rendered for non-candidate
  /// markets, since candidate-pickers expose a dedicated Yes/No selector
  /// under the amount and we don't want to duplicate them.
  Widget _buildSelectedOutcomeHeader(
      AppColorsExtension c, LivePriceState livePrices,
      {Color? accentText}) {
    final sel = widget.outcomes[_selectedIndex];
    final tokenId = sel.tokenId;
    final yes =
        (tokenId != null ? livePrices.prices[tokenId] : null) ?? sel.price;
    final sides = formatPolyChancePair(yes, fineEnds: true);
    // Inert identity card: it states which outcome is being bought and
    // nothing taps it, so it stays on the quietest step.
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: c.borderSubtle, width: 0.5),
      ),
      child: Row(
        children: [
          _OutcomeLeadingThumb(
            imageUrl: sel.imageUrl ?? widget.marketImage,
            fallbackColor: _outcomeFallbackColor(_selectedIndex),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              sel.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
                height: 1.25,
              ),
            ),
          ),
          if (_showAdvanced && !_isCandidatePicker) ...[
            SizedBox(width: 8.w),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.l10n.betYesPrice(sides.first),
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w800,
                    color: accentText ?? _kPolyGreen,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  context.l10n.betNoPrice(sides.second),
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                    color: c.textTertiary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// One outcome row. Branches on:
  ///   - O/U line on a hasYesNo sub-market → render Over / Under pills
  ///   - hasYesNo sub-market → render Yes / No pills (original behaviour)
  ///   - standalone categorical token → full-width selectable card

  // ── Info row ───────────────────────────────────────────────────────────
}

/// Leading widget for multi-outcome candidate-picker rows: 28sp
/// rounded-square per-candidate image (Gamma `groupItemImage` — flag,
/// team logo, candidate portrait). Falls back to a coloured square
/// (price-rank tier) so the row never renders blank when no image is
/// available or the network load fails.
class _OutcomeLeadingThumb extends StatelessWidget {
  final String? imageUrl;
  final Color fallbackColor;
  const _OutcomeLeadingThumb({
    required this.imageUrl,
    required this.fallbackColor,
  });

  @override
  Widget build(BuildContext context) {
    final size = 28.sp;
    final radius = BorderRadius.circular(8.r);
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fallbackColor,
        borderRadius: radius,
      ),
    );
    if (imageUrl == null || imageUrl!.isEmpty) return fallback;
    return PolyCrestImage(
      url: imageUrl!,
      size: size,
      radius: 8.r,
      fallback: fallback,
    );
  }
}

// `_AmountUnitToggle` was extracted to
// `lib/screens/polymarket/components/amount_unit_toggle.dart` so the
// sell sheet can reuse the exact same pill widget without duplicating
// the shape / animation / color set. Imported above as
// `AmountUnitToggle`.

// Binary YES/NO selector button — mirrors the `_UpDownButton` design
// language on the predictions surface: icon disc on the left, small
// label on top of the right column, big price stacked underneath. The
// unselected side renders as a muted outline so the user still sees
// the price for the other side at a glance.
/// An outcome name on a side button: the button's own face while it fits
/// on one line, then a step smaller and onto a second line ([maxLines]),
/// and only past the smallest step is it cut with an ellipsis. Long names
/// ("Francesco Maestrelli") read whole instead of "Francesco …".
class _FittedOutcomeLabel extends StatelessWidget {
  const _FittedOutcomeLabel({
    required this.label,
    required this.color,
    required this.fontSize,
    required this.maxLines,
  });

  final String label;
  final Color color;
  final double fontSize;
  final int maxLines;

  TextStyle _style(double size) => TextStyle(
        color: color,
        fontSize: size,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
        height: 1.15,
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final scaler = MediaQuery.textScalerOf(context);
      final direction = Directionality.of(context);
      bool fits(double size, int lines, [String? text]) {
        final painter = TextPainter(
          text: TextSpan(text: text ?? label, style: _style(size)),
          maxLines: lines,
          textDirection: direction,
          textScaler: scaler,
        )..layout(maxWidth: constraints.maxWidth);
        final ok = !painter.didExceedMaxLines &&
            painter.width <= constraints.maxWidth + 0.5;
        painter.dispose();
        // Two lines only between words: a name cut mid-word
        // ("Sunderlan / d") reads worse than a smaller face.
        return ok &&
            (lines == 1 || label.split(' ').every((w) => fits(size, 1, w)));
      }

      // One line at the full face, then shrinking steps down to 75% of
      // it, each tried on one line before two.
      final minSize = fontSize * 0.75;
      var size = fontSize;
      var lines = 1;
      var found = false;
      for (var s = fontSize; s >= minSize - 0.01; s -= 1) {
        for (var l = 1; l <= maxLines; l++) {
          if (fits(s, l)) {
            size = s;
            lines = l;
            found = true;
            break;
          }
        }
        if (found) break;
      }
      if (!found) {
        size = minSize;
        lines = maxLines;
      }
      return Text(
        label,
        maxLines: lines,
        overflow: TextOverflow.ellipsis,
        style: _style(size),
      );
    });
  }
}

class _BinaryToggleButton extends StatelessWidget {
  const _BinaryToggleButton({
    required this.label,
    required this.price,
    required this.color,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String? price;
  final Color color;

  /// The side's disc glyph; null draws no disc (three sides to a row).
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    // Reduce-motion: the selection-state colour/shape tween is decorative,
    // so collapse it to an instant swap when the user has asked for it.
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    // Selected side: SOLID directional fill (tinted fills rejected —
    // user decision). Unselected side: neutral grey surface, hairline
    // border, no color tint anywhere. On a side-tinted sheet the fill IS
    // the background, so the selected side reads as a brighter pane of
    // the sheet's own ink instead.
    // On the tinted sheet the two sides have to separate without either
    // outranking the primary CTA (which owns full-strength ink). The
    // selected side takes a clear pane of that ink, the unselected side a
    // quiet one; borrowing the neutral surface tones flattened the pair
    // into one slab once the sheet itself went saturated.
    final tintOn = SheetTint.maybeOf(context)?.on;
    final bg = selected
        ? (tintOn?.withValues(alpha: 0.32) ?? color)
        : (tintOn?.withValues(alpha: 0.10) ?? c.surfaceLight);
    final fg = selected
        ? (tintOn ?? Colors.white)
        : (tintOn?.withValues(alpha: 0.82) ?? c.textPrimary);
    final discBg = selected
        ? (tintOn ?? Colors.white)
            .withValues(alpha: tintOn == null ? 0.18 : 0.40)
        : (tintOn?.withValues(alpha: 0.18) ?? c.surface);
    final discIcon = selected
        ? (tintOn ?? Colors.white)
        : (tintOn?.withValues(alpha: 0.82) ?? c.textSecondary);
    final borderColor = selected
        ? tintOn?.withValues(alpha: 0.62)
        : (tintOn?.withValues(alpha: 0.24) ?? c.border);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16.r),
        child: AnimatedContainer(
          duration:
              reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
          height: 60.h,
          padding: EdgeInsets.symmetric(horizontal: 12.w),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16.r),
            border: borderColor == null ? null : Border.all(color: borderColor),
            boxShadow: (selected && isLight && tintOn == null)
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.16),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 32.sp,
                  height: 32.sp,
                  decoration: BoxDecoration(
                    color: discBg,
                    borderRadius: BorderRadius.circular(9.r),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: discIcon, size: 18.sp),
                ),
                SizedBox(width: 10.w),
              ],
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FittedOutcomeLabel(
                      label: label,
                      color: fg,
                      fontSize: price == null ? 17.sp : 15.sp,
                      // With the odds under it the name keeps one line;
                      // alone it may take two before anything is cut.
                      maxLines: price == null ? 2 : 1,
                    ),
                    if (price != null) ...[
                      SizedBox(height: 2.h),
                      Text(
                        price!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: fg,
                          fontSize: 18.sp,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          height: 1.0,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Yes / No side-flip pill for candidate-picker events. Two
// segmented chips with the selected candidate's name baked in so the
// user knows what they're voting on ("Ghana YES" / "Ghana NO" rather
// than a bare YES/NO with no anchor).
class _YesNoSideToggle extends StatelessWidget {
  const _YesNoSideToggle({
    required this.candidate,
    required this.yesPrice,
    required this.noPrice,
    required this.isNo,
    required this.onChanged,
    this.yesLabel = 'YES',
    this.noLabel = 'NO',
    this.showPrices = false,
  });

  final String candidate;
  final String yesPrice;
  final String noPrice;
  final bool isNo;
  final ValueChanged<bool> onChanged;

  /// Side labels for the two buttons. Defaults to YES/NO but the
  /// bet-slip overrides these for semantic market shapes — OVER/UNDER,
  /// ODD/EVEN, and team-handicap rows ("FAL +1.5" / "LGC -1.5").
  final String yesLabel;
  final String noLabel;
  final bool showPrices;

  @override
  Widget build(BuildContext context) {
    // Candidate context above + two large icon-disc buttons in the
    // Up/Down style (matches the 5-min crypto banner CTAs and the
    // detail-screen Buy YES/NO). Was previously a single segmented
    // strip with `<question> · YES` baked into the pill — long
    // questions truncated both pills to the same prefix and lost the
    // YES/NO distinction.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: _IconDiscButton(
                label: yesLabel,
                subLabel: showPrices ? yesPrice : null,
                icon: _sideGlyphIcon(yesLabel),
                color: _kPolyGreen,
                selected: !isNo,
                onTap: () => onChanged(false),
              ),
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: _IconDiscButton(
                label: noLabel,
                subLabel: showPrices ? noPrice : null,
                icon: _sideGlyphIcon(noLabel),
                color: _kPolyRed,
                selected: isNo,
                onTap: () => onChanged(true),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Up/Down-style button used by the bet-slip YES/NO side-flip toggle.
/// Saturated fill + white icon-disc on the selected side, muted
/// surface + tinted icon-disc on the unselected side. Icon disc on
/// the left, label centered on the right. Matches the design language
/// of `_UpDownButton` on the predictions screen and the detail-screen
/// Buy YES / Buy NO sticky CTAs.
class _IconDiscButton extends StatelessWidget {
  const _IconDiscButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
    this.subLabel,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  /// Optional small caption rendered below [label] (e.g. live cents
  /// price "50.00¢"). When non-null the layout stacks label + caption;
  /// when null the label centers vertically on its own.
  final String? subLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    // Reduce-motion: this is the same decorative selection tween as the
    // binary toggle — instant swap when reduce-motion is on.
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    // Same selection grammar as `_BinaryToggleButton`: solid fill when
    // selected, neutral grey (no color tint) when not — and the same
    // inversion when the sheet underneath is already the side colour.
    // On the tinted sheet the two sides have to separate without either
    // outranking the primary CTA (which owns full-strength ink). The
    // selected side takes a clear pane of that ink, the unselected side a
    // quiet one; borrowing the neutral surface tones flattened the pair
    // into one slab once the sheet itself went saturated.
    final tintOn = SheetTint.maybeOf(context)?.on;
    final bg = selected
        ? (tintOn?.withValues(alpha: 0.32) ?? color)
        : (tintOn?.withValues(alpha: 0.10) ?? c.surfaceLight);
    final fg = selected
        ? (tintOn ?? Colors.white)
        : (tintOn?.withValues(alpha: 0.82) ?? c.textPrimary);
    final discBg = selected
        ? (tintOn ?? Colors.white)
            .withValues(alpha: tintOn == null ? 0.18 : 0.40)
        : (tintOn?.withValues(alpha: 0.18) ?? c.surface);
    final discIcon = selected
        ? (tintOn ?? Colors.white)
        : (tintOn?.withValues(alpha: 0.82) ?? c.textSecondary);
    final borderColor = selected
        ? tintOn?.withValues(alpha: 0.62)
        : (tintOn?.withValues(alpha: 0.24) ?? c.border);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16.r),
        child: AnimatedContainer(
          duration:
              reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
          height: 60.h,
          padding: EdgeInsets.symmetric(horizontal: 12.w),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16.r),
            border: borderColor == null ? null : Border.all(color: borderColor),
            boxShadow: (selected && isLight && tintOn == null)
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.16),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 32.sp,
                height: 32.sp,
                decoration: BoxDecoration(
                  color: discBg,
                  borderRadius: BorderRadius.circular(9.r),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: discIcon, size: 18.sp),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color:
                            subLabel != null ? fg.withValues(alpha: 0.85) : fg,
                        fontSize: subLabel != null ? 15.sp : 17.sp,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                    if (subLabel != null) ...[
                      SizedBox(height: 2.h),
                      Text(
                        subLabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: fg,
                          fontSize: 18.sp,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          height: 1.0,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Predict CTA. Polymarket's reference: a flat saturated fill with
// white text — no shadow chrome, no contrast helper picking black.
// We add a subtle colored glow on light mode so the CTA still pops
// against the white sheet.
/// Whether a successful placement from the slip ends on the shared
/// confirmation. Spot bets do (and the confirmation fires the success
/// haptic, so the controller skips its own); limit orders keep the short
/// in-sheet beat and the controller haptic.
bool betSlipEndsOnConfirmation({required bool isLimit}) => !isLimit;

/// Closes the bet slip (and the market detail sheet under it) and shows
/// the shared "Prediction placed" confirmation on [navigator].
///
/// [keepMarketSheet] closes only the slip, leaving the market sheet under
/// the confirmation, as the five-minute round sheet always stays: a 5 or
/// 15 minute round keeps its sheet so the next bet rides the fast-bet
/// window (`FastBetWindow`).
void showBetSlipPlacedConfirmation({
  required NavigatorState navigator,
  required String marketQuestion,
  String? marketImage,
  required String outcome,
  required double total,
  required double price,
  double? filledCost,
  double? filledShares,
  PolymarketFeeTerms? feeTerms,
  double? fundingFeeUsd,
  String? note,
  PolymarketPosition? position,
  bool keepMarketSheet = false,
}) {
  navigator.popUntil((route) {
    final name = route.settings.name;
    return name != 'polymarket-bet-slip' &&
        (keepMarketSheet || name != 'polymarket-market-detail-sheet');
  });
  final shares = price > 0 ? total / price : 0.0;
  final boughtShares = filledShares ?? shares;
  final cost = filledCost ?? total;
  pushBetPlacedOverlay(
    navigator: navigator,
    marketQuestion: marketQuestion,
    marketImage: marketImage,
    outcome: outcome,
    shares: filledShares ?? shares,
    total: filledCost ?? total,
    avgPrice: price,
    potentialPayout: filledShares ?? shares,
    estimated: filledShares == null || filledCost == null,
    feeUsd: betReceiptFeeUsd(
        terms: feeTerms,
        shares: boughtShares,
        costUsd: cost,
        fundingFeeUsd: fundingFeeUsd),
    note: note,
    position: position,
  );
}

/// The receipt's fee: the venue's fee curve and Kute's at what the order
/// got ([shares] for [costUsd]: the fill's average price), plus what
/// funding it cost ([fundingFeeUsd], every leg). An estimate (the venue
/// reports no fee with the fill), shown as "Estimated fee"; null without
/// the market's fee terms.
double? betReceiptFeeUsd({
  required PolymarketFeeTerms? terms,
  required double shares,
  required double costUsd,
  double? fundingFeeUsd,
}) {
  if (terms == null || shares <= 0 || costUsd <= 0) return null;
  final price = costUsd / shares;
  final venue = terms.totalFee(shares, price);
  final funding =
      fundingFeeUsd != null && fundingFeeUsd.isFinite && fundingFeeUsd > 0
          ? fundingFeeUsd
          : 0.0;
  final total = venue + funding;
  return total.isFinite && total > 0 ? total : null;
}

/// The prediction just filled, as the position its own page shows, from
/// what the slip and the fill know. The Data API catches up within a
/// minute; until then the page shows this snapshot and the live price.
PolymarketPosition? placedPositionFor({
  required PendingBetIntent? intent,
  required List<PolymarketOutcome> outcomes,
  required String? eventSlug,
}) {
  if (intent == null) return null;
  final tokenId = intent.tokenId;
  final outcome = outcomes
      .where((o) => o.tokenId == tokenId || o.noTokenId == tokenId)
      .firstOrNull;
  final conditionId = outcome?.conditionId;
  if (conditionId == null || conditionId.isEmpty) return null;
  final price = intent.expectedPrice;
  final shares =
      intent.filledShares ?? (price > 0 ? intent.amount / price : 0.0);
  final cost = intent.filledCost ?? intent.amount;
  final avgPrice = shares > 0 ? cost / shares : price;
  if (shares <= 0) return null;
  return PolymarketPosition(
    marketId: conditionId,
    marketQuestion: intent.marketQuestion,
    marketImage: intent.marketImage,
    outcome: intent.outcomeName,
    size: shares,
    avgPrice: avgPrice,
    currentPrice: avgPrice,
    pnl: 0,
    pnlPercent: 0,
    isResolved: false,
    createdAt: DateTime.now(),
    tokenId: tokenId,
    eventSlug: eventSlug,
    endDateStr: intent.marketEndAt?.toIso8601String(),
  );
}
