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
import 'package:kute/screens/shared/trade_receipt.dart';
import 'package:kute/services/polymarket/sell_settlement.dart'
    show pmLiveOrderDelaySeconds;
import 'package:kute/screens/shared/ask_sal_chip.dart';
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
import 'package:kute/services/runtime_capabilities_service.dart'
    show
        CapabilityUnavailableException,
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
import 'package:kute/services/funding/venue_shortfall.dart';
import 'package:kute/services/polymarket/polymarket_category_gate.dart';
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
  final TextEditingController amountController;

  // Analytics: where the ticket is, how the amount was entered and why it
  // stopped, for the step / submitted / abandoned events.
  final DateTime openedAt = DateTime.now();
  String flowStep = 'amount';
  // none (opened empty) | prefill (carried in) | keypad | max | min |
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
  bool _detailsOpen = false;
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
  bool _isPlacing = false;

  /// In-play order delay (s) by market while its game is on, read from the
  /// CLOB so the button can say why a live game's order takes a moment.
  final Map<String, int> _liveDelays = {};

  void _loadLiveDelay(String? conditionId) {
    if (conditionId == null ||
        conditionId.isEmpty ||
        _liveDelays.containsKey(conditionId)) {
      return;
    }
    _liveDelays[conditionId] = 0;
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

  /// From a Deposit door tap until the Move sheet opens (or the tap ends
  /// without one): the top-up is being worked out, and the door says so.
  /// The form is already frozen by [_buyInFlight] for the same span, so
  /// the bet queued behind the deposit is the one on the slip at the tap.
  bool _doorCalculating = false;

  /// True while a swap leg is part of the active placement — drives the
  /// 3-step vs single-step progress bar in the placing panel.
  bool _swapNeeded = false;

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
          endAt: widget.marketEndAt);
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
    });

    // Resolve the regional / capability gate behind the first frame.
    // Only the root slip runs it — Advanced is pushed from an already
    // resolved slip and shares its draft.
    if (!widget._advanced) unawaited(_resolveCapabilityGate());
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
    try {
      await RuntimeCapabilitiesService.instance
          .ensureAllAllowed(_betCapabilities());
    } on ProviderAvailabilityException catch (error) {
      message = error.availability.message;
      regionBlocked =
          error.availability.status == ProviderAvailabilityStatus.restricted;
    } on CapabilityUnavailableException catch (error) {
      message = error.decision.message;
      regionBlocked = error.decision.regionRestricted;
    }
    // Allowed, gone, or the user already committed — leave the slip be.
    // A refusal that lands mid-placement is caught by the place-time
    // gate, so the UI must not be swapped out from under it.
    if (message == null || !mounted || _isPlacing || _buyInFlight) return;
    if (regionBlocked) TrackingService.polymarketGeoblockedShown();
    _stopped(regionBlocked ? 'geoblocked' : 'capability_unavailable');
    _updateState(() => _draft.openBlockMessage = message);
  }

  void _onDraftChanged() {
    if (mounted) setState(() {});
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
  void _trackSubmitted() {
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
      'time_in_flow_bucket': VenueAnalytics.timeInFlowBucket(
          DateTime.now().difference(_draft.openedAt)),
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
            'time_in_flow_bucket': VenueAnalytics.timeInFlowBucket(
                DateTime.now().difference(_draft.openedAt)),
          },
        );
      } catch (_) {}
    }
    if (_ownsDraft) {
      TrackingService.clearFlowContext('polymarket_bet');
      VenueAnalytics.resetSettings(_settingsScope);
    }
    // Release the live-feed hold exactly once (nulled to guard a double
    // dispose from decrementing another surface's hold).
    _livePrices?.release();
    _livePrices = null;
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
      String? busyLabel}) {
    final block = _depositBlock;
    // Funding a bet that cannot be placed here would only strand the
    // money, so the door shuts with the open gate too.
    final shut = block != null || _tradeBlock != null;
    final door = PolySlipCta(
      key: const ValueKey('bet-slip-deposit-door'),
      // Deposit door: dark primary fill per the CTA grammar (directional
      // color stays reserved for the actual Predict confirm).
      color: context.ctaFill,
      isBusy: !shut && busy,
      busyLabel: busyLabel,
      enabled: !shut && enabled,
      onTap: onTap,
      label: context.l10n.depositToPredict,
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
  /// already shown to the user. Read at tap time, not watched.
  String? _refuseBlockedDeposit() {
    final block = ref
        .read(runtimeCapabilitiesProvider)
        .blockReason('polymarket.deposit');
    if (block != null && mounted) {
      unawaited(showCapabilityDecisionSheet(
          context,
          ref
              .read(runtimeCapabilitiesProvider)
              .decision('polymarket.deposit')));
    }
    return block;
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
            showCloseButton: true,
            buttonText: viewLabel,
            onDone: () {
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
    // account gets.
    if (_belowMinimumStake && !buyingPower.isLoading) {
      return PolySlipCta(
        color: selectedColor,
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
        isBusy: _draft.ledgerBusy,
        enabled: !_draft.ledgerBusy &&
            _advancedBlock == null &&
            _tradeBlock == null,
        onTap: () {
          _placeMinimum(place: covered);
          if (!covered) _depositLedger();
        },
        label: _betCtaLabel(widget.outcomes[_selectedIndex], minStake),
      );
    }
    // One button, like Home. The second deposit link underneath was a
    // Ledger-only extra and it made the sheet read as a different
    // screen from the one the spending account gets.
    return PolySlipCta(
      color: selectedColor,
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
    if (_refuseBlockedDeposit() != null) return;
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
    _loadLiveDelay(widget.outcomes[_selectedIndex].conditionId);
    TrackingService.track('prediction_place_cta_tapped', params: {
      'amount_bucket': TrackingService.usdBucket(_amount),
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
    final outcomeLabel = _isCandidatePicker
        ? '${selected.name} ${_buyNo ? "No" : "Yes"}'
        : selected.name;
    TrackingService.track('bet_slip_open_picker', params: {
      // Never send raw amounts or balances — bucket them. The market
      // question is truncated to keep the param bounded.
      'amount_bucket': TrackingService.usdBucket(_amount),
      'balance_bucket': TrackingService.usdBucket(balance),
      'sufficient': (_amount <= balance) ? 1 : 0,
      'market': _truncMarket(widget.marketQuestion),
      'outcome': outcomeLabel,
    });
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
    ref.read(pendingPolymarketBetProvider.notifier).setIntent(
          PendingBetIntent(
            tokenId: tokenId,
            amount: _amount,
            slippagePct: _slippagePct,
            marketQuestion: widget.marketQuestion,
            marketImage: widget.marketImage,
            outcomeName: outcomeLabel,
            // Limit mode resting price, else the live market price the user saw.
            expectedPrice:
                _isLimitMode && _limitPrice > 0 ? _limitPrice : expectedPrice,
            marketEndAt: widget.marketEndAt,
            marketCategory: widget.marketCategory,
            isLimit: _isLimitMode,
            limitPrice:
                _isLimitMode ? _limitPrice.clamp(0.01, 0.99).toDouble() : 0.0,
            negRisk: widget.negRisk,
            entrySource: widget.source,
            spendAllBudgetUsd: _isLimitMode ? null : _spendAllBudgetUsd,
          ),
        );

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
      _stopped('insufficient_balance');
      _trackStep('deposit');
      PolymarketPlacementDiagnostics.declined('insufficient_balance');
      PolymarketPlacementTimeline.finish('declined',
          reason: 'insufficient_balance');
      await _offerCryptoDeposit(balance,
          shortfallUsd: shortfall,
          requiredUsd: _predictionsRequired(terms));
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
      'mode': mode,
      'swap_needed': _swapNeeded ? 1 : 0,
      'balance_bucket': TrackingService.usdBucket(balance),
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

  Future<AuthGrant?> _approveBet() async {
    _lastDeclineReason = null;
    if (_usesAdvanced) {
      try {
        await RuntimeCapabilitiesService.instance
            .ensureAllowed('trading.advanced');
      } on CapabilityUnavailableException catch (e) {
        if (mounted) {
          showMessageSnackBar(
              context: context, message: e.decision.message, error: true);
        }
        return _decline('advanced_unavailable', error: e);
      }
    }
    var pending = ref.read(pendingPolymarketBetProvider);
    if (pending == null) return _decline('no_intent');
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
      showMessageSnackBar(
        context: context,
        message: context.l10n.receiveUsdcWalletNotReady,
        error: true,
      );
      return _decline('wallet_not_ready');
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
    _trackStep('approval');
    // The book (kept at most a second old) and the account's pUSD are
    // read while the approval is on screen, not after it.
    controller.prefetchForSend(pending);
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

  /// The hot Deposit door. One tap at a time: a tap while one is being
  /// worked out (or its Move sheet is open) is ignored, event included.
  /// The tap runs the normal placement path, which stores the bet as it
  /// stands and opens the top-up; the door shows "Calculating…" until the
  /// Move sheet opens. A failure on the way leaves the slip as it was
  /// with nothing queued.
  Future<void> _onDepositDoorTap() async {
    if (_buyInFlight || _isPlacing || _doorCalculating) return;
    HapticFeedback.mediumImpact();
    TrackingService.track('bet_slip_deposit_to_trade_tapped');
    final queuedBefore = ref.read(pendingPolymarketBetProvider);
    _updateState(() => _doorCalculating = true);
    try {
      // An empty slip funds and places the market's minimum.
      if (_emptyStake) _placeMinimum(place: false);
      await _handleBuy();
    } catch (_) {
      if (!mounted) return;
      // Only the bet this tap stored is dropped.
      final queued = ref.read(pendingPolymarketBetProvider);
      if (queued != null && !identical(queued, queuedBefore)) {
        ref.read(pendingPolymarketBetProvider.notifier).clear();
      }
      showMessageSnackBar(
          context: context,
          message: context.l10n.errorCopyGeneric,
          error: true);
    } finally {
      _depositSheetOpening();
    }
  }

  /// The top-up is worked out (or the tap ended): the door stops
  /// calculating.
  void _depositSheetOpening() {
    if (mounted && _doorCalculating) {
      _updateState(() => _doorCalculating = false);
    }
  }

  /// Keep the ticket and its pending intent while the shared funding sheet
  /// is open. Depositing does not approve or automatically submit this bet.
  Future<void> _offerCryptoDeposit(double availableUsd,
      {double shortfallUsd = 0, double requiredUsd = 0}) async {
    // A withheld `polymarket.deposit` shuts every door into Predictions,
    // this one included: the bet stays unplaced and the slip says why.
    if (_refuseBlockedDeposit() != null) return;
    TrackingService.track('bet_slip_deposit_offered', params: {
      'amount_bucket': TrackingService.usdBucket(_amount),
      'combined_bucket': TrackingService.usdBucket(availableUsd),
    });
    // Prefilled with the bet's own amount (the fee added only when the
    // deposit alone would not cover it), on the spending source that
    // covers it alone; the slip stays open underneath with the same
    // market, side and amount.
    await openSlipTopUp(
      context,
      ref,
      venue: SlipVenue.predictions,
      shortfallUsd: shortfallUsd,
      orderUsd: _amount,
      requiredUsd: requiredUsd,
      readyUsd: availableUsd,
      fallbackTargetUsd: _amount,
      onReturned: slipTopUpReturned,
      onSheetOpening: _depositSheetOpening,
    );
  }

  /// "Add more" under "Deposit incoming": the rest of the shortfall.
  Future<void> _addMoreDeposit(double shortfallUsd, double incomingUsd) async {
    if (_refuseBlockedDeposit() != null) return;
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
  /// fee ceiling at the price the ticket shows.
  double _predictionsRequired(PolymarketFeeTerms terms) {
    if (!_amount.isFinite || _amount <= 0) return 0;
    final selected = widget.outcomes[_selectedIndex];
    final price =
        (_maxFeePrice ?? selected.price).clamp(0.01, 0.99).toDouble();
    return terms.allInCost(_amount, price);
  }

  /// What this stake is short of in Predictions cash:
  /// [_predictionsRequired] less [cash]. The button and the tap read the
  /// same figure.
  double _predictionsShortfall(double cash, PolymarketFeeTerms terms) {
    if (!_amount.isFinite || _amount <= 0) return 0;
    return ShortfallRules.shortfallUsd(
        requiredUsd: _predictionsRequired(terms), readyUsd: cash);
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
    _trackSubmitted();
    _updateState(() {
      _placedSuccess = false;
      _isPlacing = true;
    });
    unawaited(_runPlacement(mode, grant));
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
            WidgetsBinding.instance.addPostFrameCallback((_) {
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
            WidgetsBinding.instance.addPostFrameCallback((_) {
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
              pushKuteSuccessOverlay(
                navigator: nav,
                overlay: KuteConfirmation(
                  message: l10n.betBuyPartialLimit(
                      partial.bought, partial.total, partial.price),
                  onDone: nav.pop,
                  receipt: TradeReceipt(
                    leading: PolyReceiptArtwork(url: limitIntent.marketImage),
                    title: limitIntent.marketQuestion,
                    subtitle: limitIntent.outcomeName,
                    rows: {
                      l10n.betShares: limitBought.toStringAsFixed(2),
                      if (cost != null)
                        l10n.betReceiptCost: '\$${cost.toStringAsFixed(2)}',
                    },
                  ),
                ),
              );
            });
            return;
          }
          _updateState(() => _placedSuccess = true);
          Future.delayed(const Duration(milliseconds: 1200), () {
            if (!mounted) return;
            ref.read(pendingPolymarketBetProvider.notifier).clear();
            final nav = Navigator.of(context, rootNavigator: true);
            nav.popUntil((route) {
              final name = route.settings.name;
              return name != 'polymarket-bet-slip' &&
                  name != 'polymarket-market-detail-sheet';
            });
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
      cash = trading.valueOrNull?.usdcBalance;
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
      available = trading.hasError || orders.hasError
          ? context.l10n.feeUiBalanceUnavailable
          : spendable == null
              ? context.l10n.betSlipBalanceUpdating
              : context.l10n.betSlipAvailableAmount(_fiatCompanion(spendable));
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
      maxStake = terms.maxNotionalFor(budget, maxFeePrice,
          reserve: !_isLedger && !_isLimitMode
              ? PolymarketMarketBuyQuote.roundingHeadroom
              : 0);
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
      final feeSummary = PolymarketFeeSummary(
        tokenId: effectiveTokenId,
        shares: _sharesFor(maxFeePrice),
        price: maxFeePrice,
        bitcoinFirst: false,
        limit: _isLimitMode,
        hasFunds: cash == null || cash > 0,
        showNote: _showAdvanced,
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
      final failureNotice = placementFailed
          ? PolySlipNotice(
              title: context.l10n.betCouldNotPlacePrediction,
              message: ref.watch(pendingPolymarketBetProvider
                      .select((i) => i?.errorMessage)) ??
                  context.l10n.betFundsSafeRetryOrClose,
            )
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
                    open: _detailsOpen,
                    onToggle: () {
                      HapticFeedback.selectionClick();
                      setState(() => _detailsOpen = !_detailsOpen);
                      TrackingService.track('bet_slip_advanced_details_toggled',
                          params: {'open': _detailsOpen});
                    },
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
                    SizedBox(height: 12.h),
                  ],
                  ...sideBlock,
                  SizedBox(height: 22.h),
                  // One small Max chip beside the figure; the market's
                  // minimum rides on the available line under it, red while
                  // the stake is under it. A balance too small to stake has
                  // no Max and goes straight to the deposit door instead.
                  _buildAmountHero(
                    available,
                    belowMinimum: minBetWarning != null,
                    onMax: maxStake != null && maxStake >= _kMinBetUsd
                        ? () => _fillAmount(maxStake!, 100, budget: spendable)
                        : null,
                    maxLocked: _buyInFlight || ledgerLocked || activelyPlacing,
                  ),
                  SizedBox(height: 24.h),
                  _buildPayout(tc, payout, accentText: tc.textPrimary),
                  SizedBox(height: 8.h),
                  feeSummary,
                  SizedBox(height: 8.h),
                  _buildAdvancedToggle(tc, maxPrice: orderPrice),
                  SizedBox(height: 12.h),
                ],
              ),
      );
      final action = Padding(
        padding: EdgeInsets.fromLTRB(
            20.w,
            8.h,
            20.w,
            fullscreen
                ? 16.h
                : max(16.h, MediaQuery.of(context).padding.bottom)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_tradeBlock case final reason?) CapabilityBlockNote(reason),
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
          // The action cross-fades when it changes what it is (the
          // deposit door giving way to Predict once a deposit lands),
          // never as its amount changes.
          () {
            final primary = _buildPrimaryAction(tc, selectedColor, selected,
                busy: activelyPlacing,
                failed: placementFailed,
                busyLabel: _placingLabel(betStatus));
            return ArrivalSwitcher(
              state: primary.key ?? primary.runtimeType,
              alignment: Alignment.bottomCenter,
              child: primary,
            );
          }(),
        ]),
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
          Flexible(
              child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            primary: false,
            child: IgnorePointer(
                ignoring: _buyInFlight || ledgerLocked || activelyPlacing,
                child: form),
          )),
          if (!placementFailed)
            _buildAmountKeypad(_buyInFlight || ledgerLocked || activelyPlacing),
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
                  child: ticket(fullscreen: false),
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
  /// dims it) and the available line beneath it, which also names the
  /// market's minimum ([belowMinimum] paints that part red). There is no
  /// TextField on this step, so the OS keyboard never opens over the
  /// ticket; the pinned [AmountKeypad] under the form is the only way in.
  Widget _buildAmountHero(String available,
      {VoidCallback? onMax, bool maxLocked = false, bool belowMinimum = false}) {
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
      trailing: onMax == null
          ? null
          : AmountMaxChip(
              label: context.l10n.max,
              semanticLabel: context.l10n.amountUseMaximum,
              onTap: maxLocked ? null : onMax,
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
  /// up to the cent so the stake never lands a fraction under it.
  void _fillMinimum() {
    final target = _minimumStakeUsd(_effectiveMinBetUsd);
    if (target <= 0) return;
    _spendAllBudgetUsd = null;
    _writeFilledAmount(target, 'min');
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
  /// no chip was tapped, so no chip haptic or event.
  void _writeFilledAmount(double target, String method,
      {bool fromChip = true}) {
    final display = _usdcToFiat(target);
    _fillingAmount = true;
    _amountController.text = display == display.roundToDouble()
        ? display.toStringAsFixed(0)
        : display.toStringAsFixed(2);
    _fillingAmount = false;
    _draft.amountMethod = method;
    _updateState(() => _amount = target);
    if (!fromChip) return;
    HapticFeedback.selectionClick();
    TrackingService.track('bet_slip_available_tapped',
        params: {'chip': method == 'min' ? 'min' : 'max'});
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

  /// A market order names its maximum price here before approval, the
  /// way a limit names its price: the ask plus the slippage, with one tick
  /// of room at least. Once prepared it is the cap the approval binds.
  Widget _buildAdvancedToggle(AppColorsExtension c, {required double maxPrice}) {
    return PolySlipAdvancedRow(
      onTap: _openAdvanced,
      trailingText: _isLimitMode
          ? context.l10n.betSlipLimitAt(formatPolyCents(_limitPrice))
          : _amount > 0 && maxPrice > 0 && maxPrice < 1
              ? context.l10n.betSlipMaxAt(polymarketCentsLabel(maxPrice))
              : null,
    );
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
                      params: {'slippage_pct_bucket': opt.toStringAsFixed(0)});
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

  /// [busy] is the placement actually running, [failed] its one terminal
  /// error state. The panel that used to own both is gone: the button
  /// carries the wait, and becomes the retry when it ends badly.
  Widget _buildPrimaryAction(
      AppColorsExtension c, Color selectedColor, PolymarketOutcome selected,
      {required bool busy, required bool failed, required String busyLabel}) {
    if (_isLedger) return _buildLedgerPrimaryAction(c, selectedColor);
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
    final noFunds = trading.hasValue &&
        !trading.hasError &&
        cash != null &&
        (cash < 0.01 || _predictionsShortfall(cash, terms) > 0);
    if (failed) {
      return PolySlipCta(
        key: const ValueKey('bet-slip-retry'),
        color: selectedColor,
        isBusy: _buyInFlight || busy,
        busyLabel: context.l10n.loading,
        enabled: !_buyInFlight && !busy,
        onTap: _isPlacing ? _retryPlacement : _retryFromStart,
        // Stopped because the price moved past the approved maximum: the
        // retry names the new maximum it will ask to approve.
        label: switch (ref.watch(
            pendingPolymarketBetProvider.select((i) => i?.retryMaxPrice))) {
          final retry? => context.l10n.betRetryAtPrice(polymarketCentsLabel(retry)),
          null => context.l10n.retry,
        },
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
      final shortfall = _predictionsShortfall(cash, terms);
      final funding = slipFunding(shortfallUsd: shortfall);
      // A closed trade gate keeps its own shut door and note; a deposit
      // already on its way still reads as incoming when new deposits are
      // withheld, only "Add more" goes.
      if (funding.isIncoming && _tradeBlock == null) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PolySlipCta(
              key: const ValueKey('bet-slip-deposit-incoming'),
              color: context.ctaFill,
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
      final door = _depositDoor(
        // Busy only while the top-up is worked out; shut until the tap
        // (and the Move sheet it opens) is done.
        busy: _doorCalculating,
        busyLabel: context.l10n.feeUiCalculating,
        enabled: !_buyInFlight && !_doorCalculating,
        onTap: _onDepositDoorTap,
      );
      if (!funding.failed) return door;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [const SlipDepositFailedNote(), door],
      );
    }
    // Only a balance that was read and covers the bet ends the wait; a
    // refresh in flight keeps what the slip is following.
    if (cash != null && trading.hasValue && !trading.hasError) {
      slipFundingCovered();
    }
    // A stake under the market's floor: the one button names the minimum
    // and a tap fills it, so the disabled bet never sits there unexplained.
    if (_belowMinimumStake) {
      return PolySlipCta(
        color: selectedColor,
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
    return PolySlipCta(
      color: selectedColor,
      isBusy: busy || _buyInFlight,
      busyLabel: busyLabel,
      enabled: (placeMinimum || _amount >= _effectiveMinBetUsd) &&
          !_isPlacing &&
          !_buyInFlight &&
          _advancedBlock == null &&
          _tradeBlock == null,
      onTap: placeMinimum ? _placeMinimum : _handleBuy,
      label: _betCtaLabel(selected,
          placeMinimum ? _minimumStakeUsd(_effectiveMinBetUsd) : _amount),
    );
  }

  /// The bet button's words for a stake of [amountUsd] on [selected].
  String _betCtaLabel(PolymarketOutcome selected, double amountUsd) {
    // When the input is in sats (BTC tab) show sats.
    // Otherwise route through the localized fiat helper
    // so a UK user sees `Predict YES · £8.05` instead
    // of `$10.00`.
    final amountStr = _fiatCompanion(amountUsd);
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
    switch (status) {
      case PendingBetStatus.awaitingBalance:
        return context.l10n.betContactingPolymarket;
      case PendingBetStatus.placing:
        return context.l10n.betPlacingOrder;
      default:
        return context.l10n.betSendingBitcoin;
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
    // The shared ticket header (market thumb + question + close X), with
    // the Ask Sal chip in the trailing cluster. Sal opens prefilled to
    // explain THIS bet in plain words — market names and public prices
    // only, the user's amount as a coarse bucket.
    return PolySlipHeader(
      marketQuestion: widget.marketQuestion,
      marketImage: widget.marketImage,
      trailing: SideTintInverted(
        side: accentColor,
        child: AskSalChip(
          advisorContext: AdvisorContext(
            surface: 'bet_slip',
            marketVenue: 'polymarket',
            marketId: widget.marketSlug,
            submarketId: widget.outcomes[_selectedIndex].gammaMarketId,
          ),
          chipSignals: SalChipSignals(closesAt: widget.marketEndAt),
        ),
      ),
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
    note: note,
    position: position,
  );
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
