import 'package:kute/services/hyperliquid/hypercore_cash.dart'
    show hypercoreMaxOrderUsd;
import 'package:kute/screens/hyperliquid/components/builder_fee_consent.dart';
// lib/screens/shared/portfolio_builder/portfolio_builder_screen.dart
//
// The manual portfolio Builder: a full-screen, three-stage flow (Pick →
// Amounts → Review) opened from the "Build" chip on the Predictions and
// Trading pool screens. The user assembles a portfolio one market at a
// time, sets a USD size per leg, then confirms ONCE and the app places
// every leg sequentially with per-leg progress.
//
// Placement is USDC-only by design: the review CTA hard-blocks when the
// total exceeds the pool's available USDC and routes to the pool deposit
// instead (never an automatic swap from Bitcoin). The per-leg placement
// mechanics are lifted from the deleted AI confirm sheets (de241186) via
// builder_placement.dart; the draft legs live in builder_legs_provider.dart.

import 'package:flutter/material.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/ledger/ledger_identity_provider.dart';
import 'package:kute/providers/ledger/ledger_pm_buying_power_provider.dart';
import 'package:kute/screens/ledger/polymarket/ledger_pm_bet_target.dart';
import 'package:kute/screens/shared/portfolio_builder/ledger_builder_placement.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_search_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/pending_polymarket_bet_provider.dart';
import 'package:kute/services/polymarket/hot_order_guard.dart';
import 'package:kute/screens/home/components/action_pill.dart'
    show greenColor, redColor;
import 'package:kute/screens/home/components/deposit_sheet.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/hyperliquid/components/order_slip_sheet.dart'
    show checkHyperliquidGeoblock;
import 'package:kute/screens/ledger/ledger_investment_gate.dart'
    show
        ledgerPredictionsCapability,
        ledgerInvestmentAllowed,
        showLedgerInvestmentUnavailable;
import 'package:kute/screens/home/home_feature_carousel.dart'
    show checkPolymarketGeoblock;
import 'package:kute/screens/shared/amount_keypad_panel.dart';
import 'dart:async';

import 'package:kute/screens/shared/capability_block_note.dart';
import 'package:kute/screens/shared/hyperliquid_fee_summary.dart';
import 'package:kute/screens/shared/kute_dog_scenes.dart';
import 'package:kute/services/investment_provider_availability.dart'
    show ProviderAvailabilityException, ProviderAvailabilityStatus;
import 'package:kute/services/polymarket/polymarket_category_gate.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/screens/shared/portfolio_builder/builder_legs_provider.dart';
import 'package:kute/screens/shared/portfolio_builder/builder_market_card.dart';
import 'package:kute/screens/shared/portfolio_builder/builder_placement.dart';
import 'package:kute/screens/shared/portfolio_builder/combo_review_panel.dart';
import 'package:kute/providers/polymarket_combos_provider.dart';
import 'package:bootstrap_icons/bootstrap_icons.dart';
import 'package:kute/screens/home/components/deposit/deposit_quick_amounts.dart';
import 'package:kute/screens/polymarket/components/poly_browse_bar.dart'
    show PolyAutoScrollRow, polyPillLabel;
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/services/polymarket/market_card_shape.dart'
    show polyCardChance;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// Polymarket green — the same tone the bet slip / deleted bucket CTA used.
const Color _kPolyGreen = Color(0xFF1FA663);

enum _LegRunState { pending, placing, done, failed, paused }

class PortfolioBuilderScreen extends ConsumerStatefulWidget {
  final BuilderPool pool;
  final String? ledgerWalletId;

  const PortfolioBuilderScreen(
      {super.key, required this.pool, this.ledgerWalletId})
      : assert(ledgerWalletId == null || pool == BuilderPool.predictions);

  /// Full-screen presentation on the ROOT navigator (same rule the Move
  /// sheet follows) so the flow floats above the persistent shell nav bar.
  static void show(BuildContext context, BuilderPool pool,
      {String? ledgerWalletId}) {
    if (ledgerWalletId != null && pool != BuilderPool.predictions) return;
    // A Ledger run places new predictions: Ledger Predictions first.
    if (ledgerWalletId != null &&
        !ledgerInvestmentAllowed(ledgerPredictionsCapability)) {
      showLedgerInvestmentUnavailable(context, ledgerPredictionsCapability);
      return;
    }
    TrackingService.track('builder_opened', params: {
      'pool': pool == BuilderPool.predictions ? 'predictions' : 'trading',
      'signer': ledgerWalletId == null ? 'hot' : 'ledger',
    });
    // ignore: discarded_futures
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            PortfolioBuilderScreen(pool: pool, ledgerWalletId: ledgerWalletId),
      ),
    );
  }

  @override
  ConsumerState<PortfolioBuilderScreen> createState() =>
      _PortfolioBuilderScreenState();
}

class _PortfolioBuilderScreenState
    extends ConsumerState<PortfolioBuilderScreen> {
  /// 0 = Pick, 1 = Amounts, 2 = Review.
  int _stage = 0;

  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  /// The category the Predictions pick list browses. Breaking is the
  /// list the Builder always opened on.
  PolyPill _pill = PolyPill.breaking;

  /// The categories of the pick row: Breaking and Trending, then every
  /// topic pill of the Predictions screen, in its order (no watchlist,
  /// no games in play).
  static List<PolyPill> get _pickCategories => [
        PolyPill.breaking,
        PolyPill.trending,
        for (final p in PolyPill.values)
          if (p.isTopic) p,
      ];

  /// What `polymarketEventsProvider` calls [pill]'s list.
  static String _categoryOf(PolyPill pill) =>
      pill.isTopic ? pill.tagSlugs.first : pill.key;

  bool _placing = false;

  /// True while the run's step-up prompt is up (Phase 1b).
  bool _approving = false;
  bool _finished = false;
  bool _paused = false;
  bool _checking = false;
  int _done = 0;
  int _failed = 0;
  int _total = 0;
  double _runTotal = 0;

  /// Snapshot of the legs at place time — successful legs leave the draft
  /// provider immediately, but the review list keeps rendering the full
  /// run (with per-leg check/cross states) until the screen closes.
  List<PredictionBuilderLeg> _runPredLegs = const [];
  List<TradeBuilderLeg> _runTradeLegs = const [];
  final Map<String, _LegRunState> _runStates = {};
  final Map<String, String> _runErrors = {};

  /// Polymarket Combos: "Combine into one bet" on the hot Predictions
  /// review. One stake over every leg; Ledger never sees it.
  bool _combine = false;
  bool _comboBusy = false;
  double _comboStake = 0;

  /// The leg set whose Gamma combo eligibility was last looked up.
  String? _comboLookupKey;

  /// The legs of a combo that was placed, kept on screen after the draft
  /// is cleared.
  List<PredictionBuilderLeg>? _comboPlacedLegs;

  bool get _isLedger => widget.ledgerWalletId != null;
  bool get _isPredictions => widget.pool == BuilderPool.predictions;

  // ── Availability (Predictions) ──────────────────────────────────────
  //
  // The bet slip's own gate, asked when the Builder opens: the venue's
  // location answer and Kute's runtime policy, through the one call the
  // slip makes (`ensureAllAllowed`). Until it answers nothing can be
  // picked; a refusal replaces the whole flow with the reason. Passing
  // it grants nothing: placement re-checks at its own choke points.

  /// What opening the Builder needs: placing predictions, and the browse
  /// the pick list is.
  static const List<String> _kOpenCapabilities = [
    'polymarket.trade',
    'polymarket.browse',
  ];

  /// False until the opening gate has answered.
  bool _gateAnswered = false;

  /// The opening gate's refusal, in the policy's (or the venue's) own
  /// words; null when it allowed.
  String? _gateMessage;
  bool _gateRegion = false;
  String _gateCapability = 'polymarket.trade';

  /// The blocked state was counted once.
  bool _blockTracked = false;

  @override
  void initState() {
    super.initState();
    if (_isPredictions) {
      unawaited(_resolveOpenGate());
    } else {
      _gateAnswered = true;
    }
  }

  Future<void> _resolveOpenGate() async {
    String? message;
    var region = false;
    var capability = 'polymarket.trade';
    try {
      await ref
          .read(runtimeCapabilitiesProvider)
          .ensureAllAllowed(_kOpenCapabilities);
    } on ProviderAvailabilityException catch (error) {
      message = error.availability.message;
      region =
          error.availability.status == ProviderAvailabilityStatus.restricted;
    } on CapabilityUnavailableException catch (error) {
      message = error.decision.message;
      region = error.decision.regionRestricted;
      capability = error.capability;
    } catch (_) {
      // A check that could not be made allows nothing.
      message = const CapabilityDecision(
              allowed: false, reason: 'policy_unavailable')
          .message;
    }
    if (!mounted) return;
    setState(() {
      _gateAnswered = true;
      _gateMessage = message;
      _gateRegion = region;
      _gateCapability = capability;
    });
  }

  /// A run that passed its own place-time gate is on screen: its state
  /// is not swapped out from under it.
  bool get _runOnScreen =>
      _placing ||
      _approving ||
      _checking ||
      _finished ||
      _comboBusy ||
      _comboPlacedLegs != null;

  /// Why the Builder is shut for this person, or null while it is open:
  /// the opening gate's refusal, else the live policy's (so a switch
  /// thrown while the Builder is up closes it too).
  ({String message, bool region, String capability})? _watchBlock() {
    if (!_isPredictions) return null;
    final policy = ref.watch(runtimeCapabilitiesProvider);
    // Still being read: the loading state, not a verdict.
    if (_runOnScreen || !_gateAnswered) return null;
    if (_gateMessage case final message?) {
      return (message: message, region: _gateRegion, capability: _gateCapability);
    }
    for (final id in _kOpenCapabilities) {
      final decision = policy.decision(id);
      if (!decision.allowed || decision.comingSoon) {
        return (
          message: decision.message,
          region: decision.regionRestricted,
          capability: id,
        );
      }
    }
    return null;
  }

  /// Counts the blocked state once, with the events the bet slip's gate
  /// sends: the geoblock one for a region, the capability one otherwise.
  void _trackBlocked(({String message, bool region, String capability}) block) {
    if (_blockTracked) return;
    _blockTracked = true;
    if (block.region) {
      TrackingService.polymarketGeoblockedShown();
    } else {
      TrackingService.track('feature_unavailable_shown', params: {
        'feature': 'predictions',
        'capability': block.capability,
        'reason': 'capability_disabled',
        'surface': 'portfolio_builder',
      });
    }
  }

  /// Every policy gate the draft's bets need: opening predictions, plus
  /// the sports or politics gate of each leg's market (the list the bet
  /// slip checks for one market).
  List<String> _draftCapabilities() => {
        'polymarket.trade',
        for (final l in _readPredictionLegs())
          ...polymarketBetCapabilitiesFor([l.tokenId, l.conditionId, l.slug]),
      }.toList();
  String get _poolLabel =>
      _isPredictions ? context.l10n.predictions : context.l10n.trading;
  String get _poolParam => _isPredictions ? 'predictions' : 'trading';
  // Progress uses the same success color as the shared money-in action.
  Color get _poolAccent => _kPolyGreen;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Balance ─────────────────────────────────────────────────────────

  /// Available USDC in this pool. Predictions: the Safe USDC balance.
  /// Trading: perp withdrawable (funds spot buys via an in-flight
  /// usdClassTransfer) plus any spot USDC already parked — the same sum
  /// the Trading screen's hero shows.
  double? _watchAvailableUsd() {
    if (_isLedger) {
      final spendable = ref
          .watch(ledgerPmBuyingPowerProvider(widget.ledgerWalletId!))
          .valueOrNull
          ?.spendable;
      return spendable == null ? null : spendable.toDouble() / 1e6;
    }
    if (_isPredictions) return ref.watch(polymarketBalanceProvider);
    final withdrawable = ref.watch(hyperliquidWithdrawableProvider);
    double spotUsdc = 0;
    for (final b in ref.watch(hyperliquidSpotBalancesProvider)) {
      if (b.coin == 'USDC') spotUsdc = b.available;
    }
    return withdrawable + spotUsdc;
  }

  double? _readAvailableUsd() {
    if (_isLedger) {
      final spendable = ref
          .read(ledgerPmBuyingPowerProvider(widget.ledgerWalletId!))
          .valueOrNull
          ?.spendable;
      return spendable == null ? null : spendable.toDouble() / 1e6;
    }
    if (_isPredictions) return ref.read(polymarketBalanceProvider);
    final withdrawable = ref.read(hyperliquidWithdrawableProvider);
    double spotUsdc = 0;
    for (final b in ref.read(hyperliquidSpotBalancesProvider)) {
      if (b.coin == 'USDC') spotUsdc = b.available;
    }
    return withdrawable + spotUsdc;
  }

  List<PredictionBuilderLeg> _watchPredictionLegs() => _isLedger
      ? ref.watch(ledgerBuilderPredictionLegsProvider(widget.ledgerWalletId!))
      : ref.watch(builderPredictionLegsProvider);

  List<PredictionBuilderLeg> _readPredictionLegs() => _isLedger
      ? ref.read(ledgerBuilderPredictionLegsProvider(widget.ledgerWalletId!))
      : ref.read(builderPredictionLegsProvider);

  void _writePredictionLegs(List<PredictionBuilderLeg> legs) {
    if (_isLedger) {
      ref
          .read(ledgerBuilderPredictionLegsProvider(widget.ledgerWalletId!)
              .notifier)
          .state = List.unmodifiable(legs);
    } else {
      ref.read(builderPredictionLegsProvider.notifier).replaceAll(legs);
    }
  }

  void _updatePrediction(String key,
          PredictionBuilderLeg Function(PredictionBuilderLeg) update) =>
      _writePredictionLegs([
        for (final leg in _readPredictionLegs())
          leg.key == key ? update(leg) : leg
      ]);

  String _availableText(double? available) => available == null
      ? context.l10n.ledgerBuilderCashUnknown
      : context.l10n.builderAvailableIn(formatHlUsd(available), _poolLabel);

  bool _insufficient(double total, double? available) =>
      available != null &&
      builderInsufficientBalance(totalUsd: total, availableUsd: available);

  /// The deposit capability of this Builder's pool.
  String get _depositCapability =>
      _isPredictions ? 'polymarket.deposit' : 'hyperliquid.deposit';

  /// Why new bets / orders are shut in this pool, or null while they are
  /// allowed. Watched, so the Place button follows the admin switch live.
  String? get _tradeBlock => ref
      .watch(runtimeCapabilitiesProvider)
      .blockReason(_isPredictions ? 'polymarket.trade' : 'hyperliquid.trade');

  /// Why the pool's deposit door is shut, or null while it is open.
  /// Watched, so the door follows the admin switch live.
  String? get _depositBlock =>
      ref.watch(runtimeCapabilitiesProvider).blockReason(_depositCapability);

  void _deposit() {
    // A withheld deposit capability opens nothing: the door is already
    // disabled, and a tap racing the policy change must not slip through.
    final policy = ref.read(runtimeCapabilitiesProvider);
    if (policy.blockReason(_depositCapability) != null) return;
    showDepositSheet(context,
        ledgerWalletId: widget.ledgerWalletId,
        lockedSide: _isPredictions
            ? MoveLockedSide.depositToPredictions
            : MoveLockedSide.depositToHyperliquid);
  }

  int get _selectedCount => _isPredictions
      ? _watchPredictionLegs().length
      : ref.watch(builderTradeLegsProvider).length;

  double get _draftTotal => _isPredictions
      ? _watchPredictionLegs()
          .fold<double>(0, (sum, leg) => sum + leg.amountUsd)
      : ref.watch(builderTradeTotalProvider);

  static String _fmtTyped(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  // ── Leg toggling (stage 1) ──────────────────────────────────────────

  /// Builds a Builder leg from a browse/search event. Binary events map
  /// straight onto Yes/No; multi-outcome events bet on the candidate
  /// picked on the card, the LEADING one when none is named (Yes = they
  /// win, No = they don't, only when the sub-market carries a No token).
  PredictionBuilderLeg _legFromEvent(PolymarketEvent e,
      {PolymarketOutcome? outcome}) {
    if (e.isBinary || e.outcomes.isEmpty) {
      return PredictionBuilderLeg(
        slug: e.slug,
        title: e.title,
        imageUrl: e.imageUrl,
        conditionId: e.conditionId,
        marketEndAt: e.endDate,
        yesTokenId: e.yesTokenId,
        noTokenId: e.noTokenId,
        yesPrice: e.yesPrice,
        noPrice: e.noPrice,
      );
    }
    final sorted = [...e.outcomes]..sort((a, b) => b.price.compareTo(a.price));
    final top = outcome ?? sorted.first;
    final isPlainYes = top.name.toLowerCase() == 'yes';
    return PredictionBuilderLeg(
      slug: e.slug,
      title: isPlainYes ? e.title : '${e.title}: ${top.name}',
      imageUrl: top.imageUrl ?? e.imageUrl,
      conditionId: top.conditionId,
      marketEndAt: e.endDate,
      yesTokenId: top.tokenId ?? e.yesTokenId,
      noTokenId: top.noTokenId,
      yesPrice: top.price,
      noPrice: (1 - top.price).clamp(0.0, 1.0),
    );
  }

  /// A tap on a pick card: the market itself, or one [outcome] of an
  /// event with several. An event holds one leg, so another outcome of
  /// an event already in the draft takes the place of the first.
  void _togglePrediction(PolymarketEvent e, [PolymarketOutcome? outcome]) {
    HapticFeedback.selectionClick();
    final leg = _legFromEvent(e, outcome: outcome);
    final current = _readPredictionLegs();
    final held = current.where((value) => value.key == leg.key).firstOrNull;
    if (held != null && outcome != null && !builderLegIsOutcome(held, outcome)) {
      _writePredictionLegs(
          [for (final value in current) value.key == leg.key ? leg : value]);
      return;
    }
    final added = held == null;
    _writePredictionLegs(added
        ? [...current, leg]
        : current.where((value) => value.key != leg.key).toList());
    TrackingService.track(
      added ? 'builder_leg_added' : 'builder_leg_removed',
      params: {'pool': _poolParam},
    );
  }

  void _toggleTrade(TradeBuilderLeg leg) {
    HapticFeedback.selectionClick();
    final added = ref.read(builderTradeLegsProvider.notifier).toggle(leg);
    TrackingService.track(
      added ? 'builder_leg_added' : 'builder_leg_removed',
      params: {'pool': _poolParam},
    );
  }

  void _removeLeg(String key) {
    HapticFeedback.selectionClick();
    if (_isPredictions) {
      _writePredictionLegs(
          _readPredictionLegs().where((leg) => leg.key != key).toList());
    } else {
      ref.read(builderTradeLegsProvider.notifier).remove(key);
    }
    TrackingService.track('builder_leg_removed', params: {'pool': _poolParam});
  }

  // ── Amount editing (stage 2) ────────────────────────────────────────

  Future<void> _editAmount({
    required String rowTitle,
    required double current,
    required void Function(double amount, bool spendAll) commit,
    double Function(double available)? fullAmount,
  }) async {
    HapticFeedback.selectionClick();
    final available = _readAvailableUsd();
    var typed = current > 0 ? _fmtTyped(current) : '';
    // True while the amount is the 100% chip's, untouched since.
    var spendAll = false;
    await showAppBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final v = double.tryParse(typed) ?? 0;
          return AppBottomSheetContainer(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppBottomSheetHeader(
                    title: context.l10n.amount, subtitle: rowTitle),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: 8.h),
                      BigAmountDisplay(
                        prefix: r'$',
                        amountText: typed,
                        availableLabel: _availableText(available),
                        availableExceeded: _insufficient(v, available),
                      ),
                      SizedBox(height: 14.h),
                      // The Move sheet's chips: fixed dollars, then Max
                      // (while the pool's cash is known).
                      AmountQuickChips(
                        chips: moveQuickAmountChips(
                          amountIsUsd: true,
                          withMax: available != null,
                          maxLabel: context.l10n.max,
                          exceedsAvailable: (usd) =>
                              available != null && usd > available,
                          onDollars: (usd) {
                            HapticFeedback.selectionClick();
                            setSheet(() {
                              typed = moveQuickAmountTyped(usd);
                              spendAll = false;
                            });
                          },
                          onPercent: (r, {chip}) {
                            if (available == null) return;
                            HapticFeedback.selectionClick();
                            setSheet(() {
                              // 100% is what the order can be funded
                              // with when the pool pays more than the
                              // amount itself (Investing's slippage and
                              // fees); Predictions re-fits at placement.
                              final full = r >= 1 ? fullAmount : null;
                              typed = _fmtTyped(full != null
                                  ? full(available)
                                  : ((available * r) * 100).floorToDouble() /
                                      100);
                              spendAll = r >= 1;
                            });
                          },
                        ),
                      ),
                      SizedBox(height: 8.h),
                      AmountKeypad(
                        value: typed,
                        onChanged: (nv) => setSheet(() {
                          typed = nv;
                          spendAll = false;
                        }),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 4.h),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20.w),
                  child: AppBottomSheetButton(
                    text: context.l10n.builderSetAmount,
                    onPressed: v > 0
                        ? () {
                            HapticFeedback.selectionClick();
                            commit(v, spendAll);
                            Navigator.of(ctx).pop();
                          }
                        : null,
                  ),
                ),
                SizedBox(height: 8.h + MediaQuery.of(ctx).padding.bottom),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Combos (stage 3) ────────────────────────────────────────────────

  /// Reads Gamma's `comboStatus` and `positionIds` for the draft legs once
  /// per leg set, and stores them on the legs. Hot Predictions only.
  Future<void> _lookupComboEligibility(List<PredictionBuilderLeg> legs) async {
    if (_isLedger || !_isPredictions || legs.length < 2) return;
    final key = ([for (final l in legs) l.conditionId ?? l.slug]..sort())
        .join(',');
    if (key == _comboLookupKey) return;
    _comboLookupKey = key;
    final ids = [
      for (final l in legs)
        if (l.conditionId?.isNotEmpty ?? false) l.conditionId!
    ];
    if (ids.length != legs.length) return;
    try {
      final found = await ref
          .read(polymarketComboServiceProvider)
          .fetchEligibility(ids);
      if (!mounted || _comboLookupKey != key) return;
      _writePredictionLegs([
        for (final leg in _readPredictionLegs())
          switch (found[leg.conditionId?.toLowerCase()]) {
            final e? => leg.withCombo(
                status: e.status,
                yesPositionId: e.positionIdFor('Yes'),
                noPositionId: e.positionIdFor('No'),
              ),
            null => leg,
          }
      ]);
    } catch (_) {
      // No combo offer without eligibility; separate bets still work.
      if (mounted && _comboLookupKey == key) _comboLookupKey = null;
    }
  }

  bool _comboOffered(List<PredictionBuilderLeg> legs) =>
      !_isLedger && _isPredictions && comboEligible(legs);

  void _setCombine(bool on) {
    HapticFeedback.selectionClick();
    setState(() {
      _combine = on;
      if (on && _comboStake <= 0) _comboStake = _draftTotal;
    });
    TrackingService.track('builder_combo_toggled', params: {
      'pool': _poolParam,
      'enabled': on,
      'legs': _readPredictionLegs().length,
    });
  }

  void _editComboStake() {
    _editAmount(
      rowTitle: context.l10n.comboStake,
      current: _comboStake,
      commit: (v, _) => setState(() => _comboStake = v),
    );
  }

  void _onComboPlaced() {
    final legs = _readPredictionLegs();
    setState(() => _comboPlacedLegs = legs);
    _writePredictionLegs(const []);
  }

  // ── Placement (stage 3) ─────────────────────────────────────────────

  Future<void> _placeAll() async {
    if (_placing || _approving || _finished || _checking) return;
    if (_isLedger) {
      // The same place-time gate the hot path runs below, in front of
      // the Ledger run (each leg's device review checks again).
      if (await checkPolymarketGeoblock(context,
              capabilities: _draftCapabilities()) ||
          !mounted) {
        return;
      }
      await _placeLedger();
      return;
    }
    if (_isPredictions &&
        _hotIntentActive(ref.read(pendingPolymarketBetProvider)?.status)) {
      _toast(context.l10n.builderOrderStatusPending);
      return;
    }

    // Kill-switch + geoblock, checked ONCE before the loop (the same
    // gates the slips use) so a review left open can't trade through a
    // region/config change. A refusal opens the shared unavailable sheet
    // with the policy's own reason (the network / VPN sentence for a
    // region block).
    if (_isPredictions
        ? await checkPolymarketGeoblock(context,
            capabilities: _draftCapabilities())
        : await checkHyperliquidGeoblock(context, ref)) {
      return;
    }
    if (!mounted) return;

    if (!_isPredictions &&
        (!await ensureHotHlBuilderFeeConsent(context, ref) || !mounted)) {
      return;
    }

    final predLegs =
        _isPredictions ? _readPredictionLegs() : const <PredictionBuilderLeg>[];
    final tradeLegs = _isPredictions
        ? const <TradeBuilderLeg>[]
        : ref.read(builderTradeLegsProvider);
    final count = _isPredictions ? predLegs.length : tradeLegs.length;
    if (count == 0) return;

    // Wallet Hardening Phase 1b.3 and 1b.4: one step-up approval for the
    // whole run, bound to the exact leg list. Declining places nothing.
    BuilderRunApproval? approval;
    setState(() => _approving = true);
    try {
      approval = _isPredictions
          ? await PredictionBuilderApproval.request(context, ref, predLegs)
          : await TradeBuilderApproval.request(context, ref, tradeLegs);
    } finally {
      if (mounted) setState(() => _approving = false);
    }
    if (approval == null) return;
    if (!mounted) {
      approval.close();
      return;
    }
    final runApproval = approval;
    // The fee row's figures for exactly the legs being placed, read before
    // the loop removes placed legs from the draft.
    final runFee = _isPredictions
        ? null
        : readHyperliquidFeeTotals(ref, builderTradeFeeLegs(ref, tradeLegs));

    HapticFeedback.mediumImpact();
    final keys = _isPredictions
        ? predLegs.map((l) => l.key)
        : tradeLegs.map((l) => l.key);
    setState(() {
      _placing = true;
      _total = count;
      _done = 0;
      _failed = 0;
      _paused = false;
      _runPredLegs = predLegs;
      _runTradeLegs = tradeLegs;
      _runTotal = _isPredictions
          ? predLegs.fold(0.0, (s, l) => s + l.amountUsd)
          : tradeLegs.fold(0.0, (s, l) => s + l.amountUsd);
      _runStates.clear();
      _runErrors.clear();
      for (final k in keys) {
        _runStates[k] = _LegRunState.pending;
      }
    });

    final placedKeys = <String>[];
    Future<void> run(
        String key, Future<BuilderLegResult> Function() place) async {
      setState(() => _runStates[key] = _LegRunState.placing);
      final res = await place();
      if (!mounted) return;
      if (res.success) placedKeys.add(key);
      setState(() {
        if (res.success) {
          _done++;
          _runStates[key] = _LegRunState.done;
        } else if (res.stopRun) {
          _paused = true;
          _runStates[key] = _LegRunState.paused;
          _runErrors[key] = res.error ?? context.l10n.builderRunPaused;
        } else {
          _failed++;
          _runStates[key] = _LegRunState.failed;
          _runErrors[key] = res.error ?? context.l10n.builderOrderNotPlaced;
        }
      });
    }

    try {
      if (runApproval is PredictionBuilderApproval) {
        for (final leg in predLegs) {
          await run(leg.key,
              () => placePredictionBuilderLeg(ref, leg, approval: runApproval));
          if (!mounted) return;
          if (_paused) break;
        }
        _writePredictionLegs(_readPredictionLegs()
            .where((leg) => !placedKeys.contains(leg.key))
            .toList());
      } else if (runApproval is TradeBuilderApproval) {
        for (final leg in tradeLegs) {
          await run(leg.key,
              () => placeTradeBuilderLeg(ref, leg, approval: runApproval));
          if (!mounted) return;
        }
        ref.read(builderTradeLegsProvider.notifier).removeAll(placedKeys);
      }
    } finally {
      runApproval.close();
    }

    // Aggregate outcome event. Amounts leave the device bucketed only.
    TrackingService.track('builder_placed', params: {
      'pool': _poolParam,
      'legs': _total,
      'placed': _done,
      'failed': _failed,
      'total_bucket': TrackingService.usdBucket(_runTotal),
      // Exact fee shown on the review (Kute's fee across the legs, plus the
      // venue's taker estimate when the account's rate was known).
      if (runFee?.kute != null)
        'fee_shown_usd': _feeUsd(runFee!.kute! + (runFee.exchange ?? 0)),
      if (runFee?.kute != null) 'kute_fee_shown_usd': _feeUsd(runFee!.kute!),
      if (runFee?.exchange != null)
        'exchange_fee_estimate_usd': _feeUsd(runFee!.exchange!),
    });
    if (mounted) {
      setState(() {
        _placing = false;
        _finished = true;
      });
    }
  }

  /// A fee amount for analytics: exact to the USDC unit.
  static double _feeUsd(double v) => (v * 1e6).roundToDouble() / 1e6;

  bool _hotIntentActive(PendingBetStatus? status) => const {
        PendingBetStatus.placing,
        PendingBetStatus.converting,
        PendingBetStatus.awaitingBalance,
        PendingBetStatus.awaitingConfirmation,
      }.contains(status);

  Future<void> _checkHotPending() async {
    if (_checking || _placing || _approving) return;
    final intent = ref.read(pendingPolymarketBetProvider);
    if (intent?.status != PendingBetStatus.awaitingConfirmation) return;
    final notifier = ref.read(polymarketTradingProvider.notifier);
    setState(() => _checking = true);
    var resolved = false;
    try {
      await notifier.checkPendingOrder();
      resolved = true;
    } on ResolvedPolymarketOrder {
      resolved = true;
    } catch (_) {
      if (mounted) _toast(context.l10n.builderOrderStatusPending);
    } finally {
      if (mounted) {
        if (resolved &&
            identical(ref.read(pendingPolymarketBetProvider), intent)) {
          ref.read(pendingPolymarketBetProvider.notifier).clear();
          // Status belongs to an earlier action. Do not remove any draft leg
          // or automatically resume the portfolio after this read.
          _finished = false;
          _paused = false;
          _resetRun();
          _toast(context.l10n.betPreviousOrderChecked);
        }
        setState(() => _checking = false);
      }
    }
  }

  Future<void> _placeLedger() async {
    final walletId = widget.ledgerWalletId!;
    final identity = ref.read(ledgerIdentityProvider(walletId));
    final legs = List<PredictionBuilderLeg>.unmodifiable(_readPredictionLegs());
    if (legs.isEmpty || identity?.hasVerifiedEvm != true) {
      _toast(context.l10n.ledgerBetUnavailable);
      return;
    }
    setState(() => _checking = true);
    try {
      ref.invalidate(ledgerPmPendingBetProvider(walletId));
      final pending =
          await ref.read(ledgerPmPendingBetProvider(walletId).future);
      if (!mounted) return;
      if (pending ||
          ref.read(ledgerBuilderPendingIntentsProvider(walletId)).isNotEmpty) {
        _toast(context.l10n.builderOrderStatusPending);
        return;
      }
      if (ref.read(ledgerIdentityProvider(walletId)) != identity) {
        _toast(context.l10n.ledgerBetDetailsChanged);
        return;
      }
    } catch (_) {
      if (mounted) _toast(context.l10n.builderOrderStatusPending);
      return;
    } finally {
      if (mounted) setState(() => _checking = false);
    }
    if (!mounted) return;
    setState(() {
      _placing = true;
      _paused = false;
      _finished = false;
      _total = legs.length;
      _done = 0;
      _failed = 0;
      _runPredLegs = legs;
      _runTradeLegs = const [];
      _runTotal = legs.fold(0, (sum, leg) => sum + leg.amountUsd);
      _runStates.clear();
      _runErrors.clear();
      for (final leg in legs) {
        _runStates[leg.key] = _LegRunState.pending;
      }
    });
    String? current;
    try {
      for (final leg in legs) {
        current = leg.key;
        if (!mounted) return;
        if (ref.read(ledgerIdentityProvider(walletId)) != identity) {
          setState(() {
            _paused = true;
            _runStates[leg.key] = _LegRunState.paused;
            _runErrors[leg.key] = context.l10n.ledgerBetDetailsChanged;
          });
          break;
        }
        setState(() => _runStates[leg.key] = _LegRunState.placing);
        final result =
            await placeLedgerBuilderLeg(context, ref, leg, walletId: walletId);
        if (!mounted) return;
        if (!result.success) {
          setState(() {
            _paused = true;
            _runStates[leg.key] = _LegRunState.paused;
            _runErrors[leg.key] = result.error ?? context.l10n.builderRunPaused;
          });
          break;
        }
        // A returned submission belongs to this exact reviewed leg. Remove it
        // immediately, so a later paused leg cannot cause it to be sent twice.
        _writePredictionLegs(
            _readPredictionLegs().where((value) => value != leg).toList());
        setState(() {
          _done++;
          _runStates[leg.key] = _LegRunState.done;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _paused = true;
          final key = current;
          if (key != null && _runStates[key] != _LegRunState.done) {
            _runStates[key] = _LegRunState.paused;
            _runErrors[key] ??= context.l10n.builderRunPaused;
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _placing = false;
          _finished = true;
        });
        TrackingService.track('builder_placed', params: {
          'pool': 'predictions',
          'signer': 'ledger',
          'legs': _total,
          'placed': _done,
          'paused': _paused,
          'total_bucket': TrackingService.usdBucket(_runTotal),
        });
      }
    }
  }

  Future<void> _checkLedgerPending() async {
    if (_checking || _placing || _approving) return;
    final walletId = widget.ledgerWalletId!;
    final pending = ref.read(ledgerBuilderPendingIntentsProvider(walletId));
    final entry = pending.entries.firstOrNull;
    setState(() => _checking = true);
    try {
      final result = await checkLedgerPredictionStatus(context, ref,
          walletId: walletId, expectedIntent: entry?.value.intent);
      if (!mounted) return;
      if (result != LedgerPmBetOutcome.submitted &&
          result != LedgerPmBetOutcome.resolved) {
        _toast(context.l10n.builderOrderStatusPending);
        return;
      }
      var remaining = _readPredictionLegs();
      var confirmed = false;
      if (entry != null &&
          clearLedgerBuilderPending(ref, walletId, entry.key,
              expected: entry.value)) {
        if (result == LedgerPmBetOutcome.submitted) {
          remaining =
              remaining.where((leg) => !entry.value.matches(leg)).toList();
          _writePredictionLegs(remaining);
          confirmed = true;
        }
      }
      // Only the exact reviewed leg of this run completes it. An unrelated
      // old action never completes a current draft leg.
      final String? completedKey = entry != null &&
              confirmed &&
              remaining.isEmpty &&
              _runStates[entry.key] == _LegRunState.paused
          ? entry.key
          : null;
      setState(() {
        _paused = false;
        if (completedKey != null) {
          _runStates[completedKey] = _LegRunState.done;
          _runErrors.remove(completedKey);
          _done++;
          _finished = true;
        } else {
          _finished = false;
          _resetRun();
          if (confirmed && remaining.isEmpty) _stage = 0;
        }
      });
      _toast(context.l10n.betPreviousOrderChecked);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  /// Back to an editable draft: the previous run's markers must not label
  /// draft rows. Call inside setState or right before one.
  void _resetRun() {
    _runStates.clear();
    _runErrors.clear();
    _runPredLegs = const [];
    _runTradeLegs = const [];
    _runTotal = 0;
    _done = 0;
    _failed = 0;
    _total = 0;
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Shell ───────────────────────────────────────────────────────────

  String get _stageTitle {
    if (_finished) return context.l10n.builderRunSummary;
    return switch (_stage) {
      0 => context.l10n.builderStepBuild,
      1 => context.l10n.builderStepAmounts,
      _ => context.l10n.builderStepReview,
    };
  }

  void _goBack() {
    if (_placing || _approving || _checking || _comboBusy) return;
    if (_comboPlacedLegs != null) {
      Navigator.of(context).maybePop();
      return;
    }
    HapticFeedback.selectionClick();
    if (_stage == 0 || _finished || _shut) {
      Navigator.of(context).maybePop();
    } else {
      setState(() => _stage -= 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final block = _watchBlock();
    // Nothing is picked, sized or reviewed until the gate has allowed.
    _shut = block != null || !_gateAnswered;
    if (block != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _trackBlocked(block));
    }
    return PopScope(
      canPop: !_placing &&
          !_approving &&
          !_checking &&
          !_comboBusy &&
          (_stage == 0 || _finished || _comboPlacedLegs != null || _shut),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _placing || _approving || _checking || _comboBusy) {
          return;
        }
        setState(() => _stage -= 1);
      },
      child: Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(
          backgroundColor: c.background,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          leading: KuteBackButton(onPressed: _goBack),
          title: Text(_shut ? context.l10n.builderStepBuild : _stageTitle,
              style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w600)),
        ),
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusScope.of(context).unfocus(),
          child: SafeArea(
            top: false,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: KeyedSubtree(
                key: ValueKey<int>(block != null
                    ? -2
                    : !_gateAnswered
                        ? -1
                        : _stage),
                child: block != null
                    ? _blockedState(c, block.message, region: block.region)
                    : !_gateAnswered
                        ? _predictionPickLoading()
                        : switch (_stage) {
                            0 => _pickStage(c),
                            1 => _amountsStage(c),
                            _ => _reviewStage(c),
                          },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The Builder is not showing its flow: the gate is still being read,
  /// or it refused. Set by [build].
  bool _shut = false;

  /// Predictions cannot be placed here: the app's "not here" state (the
  /// Predictions screen's own, when browsing is withheld) with the
  /// unavailable sheet's title and the reason, and one way out.
  Widget _blockedState(AppColorsExtension c, String message,
      {required bool region}) {
    final l10n = context.l10n;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 28.h),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExcludeSemantics(
                    child: KuteDogNotHere(
                        width: 220, ink: c.textPrimary, accent: c.accent),
                  ),
                  SizedBox(height: 16.h),
                  Text(
                    region
                        ? l10n.capabilityRegionTitle
                        : l10n.gatePredictionsUnavailable,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 20.sp,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: c.textSecondary, fontSize: 16.sp, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        _bottomArea(
          c,
          child: AppButton(
            text: l10n.close,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
      ],
    );
  }

  // ── Stage 1: Pick ───────────────────────────────────────────────────

  Widget _pickStage(AppColorsExtension c) {
    return Column(children: [
      Padding(
        padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 10.h),
        child: _searchField(c),
      ),
      // A search reads every category, so the row steps aside for it.
      if (_isPredictions && _query.trim().isEmpty) ...[
        _pickPills(),
        SizedBox(height: 10.h),
      ],
      Expanded(
          child: _isPredictions ? _predictionPickList(c) : _tradePickList(c)),
      _pickBottomBar(c),
    ]);
  }

  /// The Predictions category pills (one row), over the pick list.
  Widget _pickPills() {
    final policy = ref.watch(runtimeCapabilitiesProvider);
    final pills = [
      for (final p in _pickCategories)
        if (polyPillOffered(p, policy)) p,
    ];
    final selected = pills.contains(_pill) ? _pill : PolyPill.breaking;
    return PolyAutoScrollRow(
      height: 34.h,
      itemCount: pills.length,
      selectedIndex: pills.indexOf(selected),
      itemBuilder: (context, i) => KutePill(
        label: polyPillLabel(context.l10n, pills[i]),
        selected: pills[i] == selected,
        onTap: () {
          HapticFeedback.selectionClick();
          if (pills[i] == _pill) return;
          TrackingService.track('category_pill_tapped', params: {
            'section': pills[i].key,
            'surface': 'portfolio_builder',
          });
          setState(() => _pill = pills[i]);
        },
      ),
    );
  }

  Widget _searchField(AppColorsExtension c) {
    return TextField(
      controller: _searchCtrl,
      onChanged: (t) => setState(() => _query = t),
      autocorrect: false,
      textInputAction: TextInputAction.search,
      cursorColor: c.accent,
      // The app's search input (PickerSearchField): surfaceLight fill,
      // 12.r corners, hairline border, accent focus ring.
      style: TextStyle(
          color: c.textPrimary, fontSize: 16.sp, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        filled: true,
        fillColor: c.surfaceLight,
        prefixIcon:
            Icon(Icons.search_rounded, size: 22.sp, color: c.textTertiary),
        suffixIcon: _query.trim().isEmpty
            ? null
            : IconButton(
                tooltip: context.l10n.builderClearSearch,
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() => _query = '');
                },
                icon: Icon(Icons.close_rounded,
                    size: 20.sp, color: c.textTertiary),
              ),
        hintText: _isPredictions
            ? context.l10n.searchMarketsHint
            : context.l10n.builderSearchCoinsStocks,
        hintStyle: TextStyle(
            color: c.textTertiary, fontSize: 16.sp, fontWeight: FontWeight.w500),
        contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 13.h),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide(color: c.borderSubtle, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide(color: c.accent, width: 1.5),
        ),
      ),
    );
  }

  Widget _predictionPickList(AppColorsExtension c) {
    final q = _query.trim();
    final policy = ref.watch(runtimeCapabilitiesProvider);
    final pill = polyPillOffered(_pill, policy) ? _pill : PolyPill.breaking;
    final async = q.isEmpty
        ? ref.watch(polymarketEventsProvider(_categoryOf(pill)))
        : ref.watch(polymarketSearchProvider(q));
    final legs = {for (final l in _watchPredictionLegs()) l.key: l};
    return async.when(
      data: (events) {
        // The providers already leave out the categories the policy
        // hides; filtered again here so no card of one can be picked.
        final list = polymarketEventsOffered(events, policy)
            .where((e) => e.outcomes.isNotEmpty && !e.closed)
            .toList();
        if (list.isEmpty) {
          return _pickEmpty(
              c,
              q.isEmpty
                  ? context.l10n.builderNoMarketsNow
                  : context.l10n.builderNoMarketsFound);
        }
        // The Predictions list's own cards, each answer a pick.
        return ListView.separated(
          padding: EdgeInsets.fromLTRB(16.w, 2.h, 16.w, 16.h),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          itemCount: list.length,
          separatorBuilder: (_, __) => SizedBox(height: 12.h),
          itemBuilder: (_, i) {
            final e = list[i];
            return BuilderMarketCard(
              key: ValueKey<String>(e.slug),
              event: e,
              leg: legs[e.slug],
              onToggle: (outcome) => _togglePrediction(e, outcome),
            );
          },
        );
      },
      loading: () => _predictionPickLoading(),
      error: (_, __) => _pickEmpty(c, context.l10n.builderMarketsLoadFailed),
    );
  }

  /// The Predictions list's loading cards.
  Widget _predictionPickLoading() => SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.only(top: 2.h),
        child: SkeletonCardList(count: 5, height: 120.h),
      );

  Widget _tradePickList(AppColorsExtension c) {
    final q = _query.trim();
    final selectedKeys =
        ref.watch(builderTradeLegsProvider).map((l) => l.key).toSet();

    if (q.isEmpty) {
      final async = ref.watch(hyperliquidBrowseUniverseProvider);
      return async.when(
        data: (universe) {
          // The idle state mirrors the Trading tab's browse universe
          // (volume-sorted). Capped to keep the toggle list snappy.
          final list = universe.take(100).toList();
          if (list.isEmpty) {
            return _pickEmpty(c, context.l10n.builderNoMarketsNow);
          }
          return ListView.separated(
            padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 16.h),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            itemCount: list.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: context.colors.borderSubtle),
            itemBuilder: (_, i) {
              final m = list[i];
              final leg = TradeBuilderLeg(
                coin: m.coin,
                name: hlFriendlyName(m.coin),
                isSpot: m.kind == HlMarketKind.spot,
                iconUrl: m.iconUrl,
                category: m.category,
              );
              return _PickRow(
                accent: context.ctaFill,
                selected: selectedKeys.contains(leg.key),
                leading: HlCoinIcon(
                  coin: m.coin,
                  wireCoin: m.wireCoin,
                  iconUrl: m.iconUrl,
                  category: m.category,
                  size: 38,
                ),
                title: leg.name ?? m.coin,
                subtitle: [
                  if (leg.name != null) m.coin,
                  formatHlPrice(m.markPx, decimalCap: m.pxDecimalCap),
                  leg.isSpot
                      ? context.l10n.investingSpot
                      : context.l10n.investingKindLeveraged,
                ].join(' · '),
                onTap: () => _toggleTrade(leg),
              );
            },
          );
        },
        loading: () => _pickLoading(),
        error: (_, __) =>
            _pickEmpty(c, context.l10n.builderMarketsLoadFailed),
      );
    }

    final async = ref.watch(hyperliquidMarketSearchProvider(q));
    return async.when(
      data: (results) {
        if (results.isEmpty) {
          return _pickEmpty(c, context.l10n.builderNoMarketsFound);
        }
        return ListView.separated(
          padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 16.h),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          itemCount: results.length,
          separatorBuilder: (_, __) =>
              Divider(height: 1, color: context.colors.borderSubtle),
          itemBuilder: (_, i) {
            final r = results[i];
            final leg = TradeBuilderLeg(
              coin: r.coin,
              name: r.name,
              isSpot: !r.isPerp,
              iconUrl: r.iconUrl,
              category: r.category,
            );
            return _PickRow(
              accent: context.ctaFill,
              selected: selectedKeys.contains(leg.key),
              leading: HlCoinIcon(
                coin: r.coin,
                wireCoin: r.wireCoin,
                iconUrl: r.iconUrl,
                category: r.category,
                size: 38,
              ),
              title: r.name ?? r.coin,
              subtitle: [
                if (r.name != null) r.coin,
                formatHlPrice(r.markPx),
                leg.isSpot
                    ? context.l10n.investingSpot
                    : context.l10n.investingKindLeveraged,
              ].join(' · '),
              onTap: () => _toggleTrade(leg),
            );
          },
        );
      },
      loading: () => _pickLoading(),
      error: (_, __) => _pickEmpty(c, context.l10n.builderNoMarketsFound),
    );
  }

  Widget _eventImage(AppColorsExtension c, String? url) =>
      BuilderThumb(imageUrl: url);

  Widget _pickLoading() {
    return KuteSkeleton(
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 16.h),
        itemCount: 8,
        separatorBuilder: (_, __) =>
            Divider(height: 1, color: context.colors.borderSubtle),
        itemBuilder: (_, index) => Padding(
          padding: EdgeInsets.symmetric(vertical: 16.h),
          child: Row(
            children: [
              SkeletonCircle(38.sp),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FractionallySizedBox(
                      widthFactor: index.isEven ? 0.8 : 0.65,
                      child: SkeletonBar(double.infinity, 17.h),
                    ),
                    SizedBox(height: 7.h),
                    FractionallySizedBox(
                      widthFactor: 0.45,
                      child: SkeletonBar(double.infinity, 12.h),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 16.w),
              SkeletonCircle(22.sp),
            ],
          ),
        ),
      ),
    );
  }

  /// Nothing to list: the Predictions screen's empty state (a quiet
  /// glyph over one line).
  Widget _pickEmpty(AppColorsExtension c, String message) {
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 40.w, vertical: 24.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(BootstrapIcons.compass, color: c.textTertiary, size: 48.sp),
            SizedBox(height: 16.h),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 15.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The quiet area pinned under each stage's list: a hairline, then
  /// the stage's rows and its button.
  Widget _bottomArea(AppColorsExtension c, {required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: c.background,
        border: Border(top: BorderSide(color: c.borderSubtle, width: 0.5)),
      ),
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 12.h),
      child: child,
    );
  }

  Widget _pickBottomBar(AppColorsExtension c) {
    final count = _selectedCount;
    return _bottomArea(
      c,
      child: AppButton(
        text: count == 0
            ? context.l10n.builderSelectMarkets
            : context.l10n.builderContinueSelected(count),
        onPressed: count == 0
            ? null
            : () {
                FocusScope.of(context).unfocus();
                setState(() => _stage = 1);
              },
      ),
    );
  }

  // ── Stage 2: Amounts ────────────────────────────────────────────────

  Widget _amountsStage(AppColorsExtension c) {
    final available = _watchAvailableUsd();
    final total = _draftTotal;
    final predLegs = _watchPredictionLegs();
    final tradeLegs = ref.watch(builderTradeLegsProvider);
    final legsReady = _isPredictions
        ? predLegs.every((l) => l.amountUsd > 0)
        : tradeLegs.every((l) => l.amountUsd > 0);
    final count = _isPredictions ? predLegs.length : tradeLegs.length;

    return Column(
      children: [
        Expanded(
          child: count == 0
              ? _pickEmpty(c, context.l10n.builderChooseMarkets)
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
                  itemCount: count,
                  separatorBuilder: (_, __) => SizedBox(height: 12.h),
                  itemBuilder: (_, i) => _isPredictions
                      ? _predictionAmountRow(c, predLegs[i])
                      : _tradeAmountRow(c, tradeLegs[i]),
                ),
        ),
        _bottomArea(
          c,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    context.l10n.total,
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    formatHlUsd(total),
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 17.sp,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 4.h),
              Text(
                _availableText(available),
                style: TextStyle(
                  color: _insufficient(total, available)
                      ? AppColors.error
                      : c.textTertiary,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 12.h),
              AppButton(
                text: context.l10n.builderReviewPortfolio,
                onPressed: count > 0 && legsReady
                    ? () => setState(() => _stage = 2)
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The leg's amount: a plain row of its card that opens the amount
  /// sheet (big amount, quick chips, keypad).
  Widget _amountField(AppColorsExtension c, double amountUsd,
      {required VoidCallback onTap}) {
    return Semantics(
      button: true,
      label: context.l10n.builderEditAmountSemantics(formatHlUsd(amountUsd)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10.r),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 10.h),
          child: Row(children: [
            Text(context.l10n.amount,
                style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600)),
            SizedBox(width: 16.w),
            Expanded(
                child: Text(amountUsd > 0 ? formatHlUsd(amountUsd) : r'$0',
                    textAlign: TextAlign.end,
                    style: TextStyle(
                        color: amountUsd > 0 ? c.textPrimary : c.textTertiary,
                        fontSize: 20.sp,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        fontFeatures: const [FontFeature.tabularFigures()]))),
            SizedBox(width: 8.w),
            Icon(Icons.edit_outlined, size: 16.sp, color: c.textSecondary),
          ]),
        ),
      ),
    );
  }

  Widget _predictionAmountRow(AppColorsExtension c, PredictionBuilderLeg leg) {
    final noAvailable = leg.noTokenId != null && leg.noTokenId!.isNotEmpty;
    return _legShell(
      c,
      leading: _eventImage(c, leg.imageUrl),
      title: leg.title,
      trailing: _amountField(
        c,
        leg.amountUsd,
        onTap: () => _editAmount(
          rowTitle: leg.title,
          current: leg.amountUsd,
          // A hot 100% leg is re-fitted with its fees at placement; the
          // Ledger path reserves its own fees on the device review.
          commit: (v, spendAll) => _updatePrediction(
              leg.key,
              (value) => value.copyWith(
                  amountUsd: v, spendAll: spendAll && !_isLedger)),
        ),
      ),
      onRemove: () => _removeLeg(leg.key),
      footer: Row(
        children: [
          _ChoiceChip(
            label: context.l10n.yes,
            color: _kPolyGreen,
            selected: !leg.isNo,
            onTap: () {
              HapticFeedback.selectionClick();
              _updatePrediction(
                  leg.key, (value) => value.copyWith(outcomeName: 'Yes'));
            },
          ),
          SizedBox(width: 6.w),
          _ChoiceChip(
            label: context.l10n.betNo,
            color: redColor,
            selected: leg.isNo,
            onTap: noAvailable
                ? () {
                    HapticFeedback.selectionClick();
                    _updatePrediction(
                        leg.key, (value) => value.copyWith(outcomeName: 'No'));
                  }
                : null,
          ),
          const Spacer(),
          // The picked side's chance: the card's right-hand number.
          Text(
            polyCardChance(leg.price),
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 20.sp,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tradeAmountRow(AppColorsExtension c, TradeBuilderLeg leg) {
    final notifier = ref.read(builderTradeLegsProvider.notifier);
    return _legShell(
      c,
      leading: HlCoinIcon(
        coin: leg.coin,
        iconUrl: leg.iconUrl,
        category: leg.category,
        size: 38,
      ),
      title: leg.name ?? leg.coin,
      trailing: _amountField(
        c,
        leg.amountUsd,
        onTap: () => _editAmount(
          rowTitle: leg.name ?? leg.coin,
          current: leg.amountUsd,
          commit: (v, _) => notifier.setAmount(leg.key, v),
          // A 1x market order at the default 1% slippage, taker and
          // builder fees paid from the same cash.
          fullAmount: (available) =>
              hypercoreMaxOrderUsd(availableUsd: available),
        ),
      ),
      onRemove: () => _removeLeg(leg.key),
      footer: leg.isSpot
          ? Text(context.l10n.builderBuySpot(leg.coin),
              style: TextStyle(
                  color: c.textSecondary,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w500))
          : Wrap(
              spacing: 8.w,
              runSpacing: 8.h,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _ChoiceChip(
                    label: context.l10n.longLabel,
                    color: greenColor,
                    selected: leg.isLong,
                    onTap: () => notifier.setSide(leg.key, true)),
                _ChoiceChip(
                    label: context.l10n.shortLabel,
                    color: redColor,
                    selected: !leg.isLong,
                    onTap: () => notifier.setSide(leg.key, false)),
                Text('${leg.coin} · 1×',
                    style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w500)),
              ],
            ),
    );
  }

  /// One leg of the draft as a card in the Predictions list's language:
  /// image and whole title, the side with its number, then the amount.
  Widget _legShell(
    AppColorsExtension c, {
    required Widget leading,
    required String title,
    required Widget trailing,
    required Widget footer,
    required VoidCallback onRemove,
  }) {
    return BuilderCardFrame(
      padding: EdgeInsets.fromLTRB(16.w, 16.w, 16.w, 6.h),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          leading,
          SizedBox(width: 10.w),
          Expanded(child: _legTitle(c, title)),
          SizedBox(width: 4.w),
          IconButton(
              tooltip: context.l10n.builderRemoveMarket,
              onPressed: onRemove,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: BoxConstraints(minWidth: 40.w, minHeight: 40.w),
              icon: Icon(Icons.close_rounded,
                  size: 20.sp, color: c.textTertiary)),
        ]),
        SizedBox(height: 14.h),
        footer,
        SizedBox(height: 12.h),
        Divider(height: 1, thickness: 0.5, color: c.borderSubtle),
        trailing,
      ]),
    );
  }

  /// A leg's title in the list card's style, written whole.
  Widget _legTitle(AppColorsExtension c, String title) => Text(
        title,
        style: TextStyle(
          color: c.textPrimary,
          fontSize: 17.sp,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          height: 1.25,
        ),
      );

  // ── Stage 3: Review ─────────────────────────────────────────────────

  Widget _reviewStage(AppColorsExtension c) {
    final comboDone = _comboPlacedLegs;
    if (comboDone != null) return _comboReview(c, comboDone);
    final showRun = _placing || _finished;
    final predLegs = showRun ? _runPredLegs : _watchPredictionLegs();
    if (!showRun && !_isLedger && _isPredictions && predLegs.length >= 2) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _lookupComboEligibility(predLegs));
    }
    final comboOffered = !showRun && _comboOffered(predLegs);
    if (comboOffered && _combine) return _comboReview(c, predLegs);
    final tradeLegs =
        showRun ? _runTradeLegs : ref.watch(builderTradeLegsProvider);
    final count = _isPredictions ? predLegs.length : tradeLegs.length;
    final total = showRun ? _runTotal : _draftTotal;
    final available = _watchAvailableUsd();
    final insufficient = _insufficient(total, available);
    // Listed, disabled, wearing its reason while the pool's deposit
    // capability is withheld ([CapabilityBlockNote]).
    final depositBlock = _depositBlock;
    final tradeBlock = _tradeBlock;
    final ledgerDepositLink =
        _isLedger && available == null && !_placing && !_checking;
    final pendingStatus = _isLedger
        ? ref.watch(ledgerPmPendingBetProvider(widget.ledgerWalletId!))
        : null;
    final hotStatus = !_isLedger && _isPredictions
        ? ref.watch(
            pendingPolymarketBetProvider.select((intent) => intent?.status))
        : null;
    final hotNeedsStatus = hotStatus == PendingBetStatus.awaitingConfirmation;
    final hotInFlight = _hotIntentActive(hotStatus) && !hotNeedsStatus;
    final ledgerLoading = pendingStatus?.isLoading ?? false;
    final ledgerPending = _isLedger &&
        (pendingStatus?.valueOrNull != false ||
            ref
                .watch(
                    ledgerBuilderPendingIntentsProvider(widget.ledgerWalletId!))
                .isNotEmpty);

    return Column(
      children: [
        if (comboOffered) _comboToggle(c),
        Expanded(
          child: count == 0
              ? _pickEmpty(c, context.l10n.builderChooseMarkets)
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
                  itemCount: count,
                  separatorBuilder: (_, __) => SizedBox(height: 12.h),
                  itemBuilder: (_, i) => _isPredictions
                      ? _reviewRow(
                          c,
                          key: predLegs[i].key,
                          leading: _eventImage(c, predLegs[i].imageUrl),
                          title: predLegs[i].title,
                          sideText: predLegs[i].outcomeName,
                          sideColor: predLegs[i].isNo ? redColor : _kPolyGreen,
                          chance: predLegs[i].price,
                          amountUsd: predLegs[i].amountUsd,
                        )
                      : _reviewRow(
                          c,
                          key: tradeLegs[i].key,
                          leading: HlCoinIcon(
                            coin: tradeLegs[i].coin,
                            iconUrl: tradeLegs[i].iconUrl,
                            category: tradeLegs[i].category,
                            size: 38,
                          ),
                          title: tradeLegs[i].name ?? tradeLegs[i].coin,
                          sideText: tradeLegs[i].isSpot
                              ? 'BUY'
                              : (tradeLegs[i].isLong ? 'LONG' : 'SHORT'),
                          sideColor: tradeLegs[i].isSpot || tradeLegs[i].isLong
                              ? greenColor
                              : redColor,
                          amountUsd: tradeLegs[i].amountUsd,
                        ),
                ),
        ),
        _bottomArea(
          c,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _finished
                        ? context.l10n.builderRunSummary
                        : context.l10n.total,
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    _finished
                        ? context.l10n.builderDoneOfTotal(_done, _total)
                        : formatHlUsd(total),
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 17.sp,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 4.h),
              Text(
                _finished
                    ? (_paused
                        ? context.l10n.builderRunPaused
                        : _failed > 0
                            ? context.l10n.builderFailedCount(_failed)
                            : context.l10n.builderAllPlaced)
                    : _availableText(available),
                style: TextStyle(
                  color: !_finished && insufficient
                      ? AppColors.error
                      : c.textTertiary,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (!_finished && !_placing && insufficient) ...[
                SizedBox(height: 8.h),
                Text(
                    context.l10n
                        .builderAddToContinue(formatHlUsd(total - available!)),
                    style: TextStyle(color: c.textSecondary, fontSize: 14.sp)),
              ],
              if (_placing) ...[
                SizedBox(height: 8.h),
                Text(context.l10n.builderPlacingProgress(_done, _total),
                    style: TextStyle(color: c.textSecondary, fontSize: 14.sp)),
              ],
              // The run's fee, total across its legs, in the order slip's
              // own row: Kute's fee on each leg plus the venue's taker
              // estimate at this account's tier.
              if (!_isPredictions && !_finished && tradeLegs.isNotEmpty)
                HyperliquidFeeSummary.legs(
                    legs: builderTradeFeeLegs(ref, tradeLegs)),
              if (_isLedger) ...[
                SizedBox(height: 8.h),
                Text(context.l10n.ledgerBuilderReviewEach,
                    style: TextStyle(color: c.textTertiary, fontSize: 13.sp)),
                if (ledgerDepositLink)
                  TextButton(
                      onPressed: depositBlock == null ? _deposit : null,
                      child: Text(context.l10n.deposit)),
              ],
              if (_finished && _paused && !ledgerPending && _isLedger) ...[
                SizedBox(height: 8.h),
                TextButton(
                    onPressed: () => setState(() {
                          _finished = false;
                          _paused = false;
                          _resetRun();
                        }),
                    child: Text(context.l10n.builderRunReviewRemaining)),
              ],
              SizedBox(height: 16.h),
              // New bets / orders shut here: the Place button stays,
              // disabled, with the reason above it. A run already placing
              // finishes under its own place-time gate.
              if (tradeBlock != null &&
                  !ledgerPending &&
                  !hotNeedsStatus &&
                  !_finished &&
                  !_placing)
                CapabilityBlockNote(tradeBlock),
              // A shut Place already explains the disabled deposit door.
              if (depositBlock != null &&
                  tradeBlock == null &&
                  !ledgerPending &&
                  !hotNeedsStatus &&
                  !_finished &&
                  ((insufficient && !_placing) || ledgerDepositLink))
                CapabilityBlockNote(depositBlock),
              AppButton(
                text: ledgerPending || hotNeedsStatus
                    ? context.l10n.ledgerBetCheckStatus
                    : _finished
                        ? context.l10n.done
                        : insufficient
                            ? context.l10n.builderDepositTo(_poolLabel)
                            : _isPredictions
                                ? context.l10n.builderPlacePredictions(count)
                                : context.l10n.builderPlaceOrders(count),
                variant: !_finished && !insufficient
                    ? AppButtonVariant.moneyIn
                    : AppButtonVariant.primary,
                isLoading: _placing || _approving || _checking || ledgerLoading,
                onPressed: _placing ||
                        _approving ||
                        _checking ||
                        ledgerLoading ||
                        hotInFlight
                    ? null
                    : hotNeedsStatus
                        ? _checkHotPending
                        : ledgerPending
                            ? _checkLedgerPending
                            : _finished
                                ? () => Navigator.of(context).maybePop()
                                : tradeBlock != null
                                    ? null
                                    : insufficient
                                        ? depositBlock != null
                                            ? null
                                            : () {
                                                TrackingService.track(
                                                    'builder_deposit_prompted',
                                                    params: {
                                                      'pool': _poolParam
                                                    });
                                                _deposit();
                                              }
                                        : count > 0
                                            ? _placeAll
                                            : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _comboToggle(AppColorsExtension c) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 4.h, 8.w, 4.h),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.comboCombineTitle,
                    style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w700)),
                SizedBox(height: 2.h),
                Text(context.l10n.comboCombineSubtitle,
                    style:
                        TextStyle(color: c.textSecondary, fontSize: 13.sp)),
              ],
            ),
          ),
          Switch.adaptive(
            value: _combine,
            activeTrackColor: _kPolyGreen,
            onChanged: _comboBusy ? null : _setCombine,
          ),
        ],
      ),
    );
  }

  /// The combined review: the legs (no per-leg amounts) above one stake
  /// and its RFQ quote. [legs] is the live draft, or the placed snapshot.
  Widget _comboReview(AppColorsExtension c, List<PredictionBuilderLeg> legs) {
    final placed = _comboPlacedLegs != null;
    final depositBlock = _depositBlock;
    final tradeBlock = _tradeBlock;
    return Column(
      children: [
        if (!placed) _comboToggle(c),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
            itemCount: legs.length,
            separatorBuilder: (_, __) => SizedBox(height: 12.h),
            itemBuilder: (_, i) => _reviewRow(
              c,
              key: legs[i].key,
              leading: _eventImage(c, legs[i].imageUrl),
              title: legs[i].title,
              sideText: legs[i].outcomeName,
              sideColor: legs[i].isNo ? redColor : _kPolyGreen,
              chance: legs[i].price,
              amountUsd: 0,
              showAmount: false,
            ),
          ),
        ),
        _bottomArea(
          c,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (tradeBlock != null && !placed) ...[
                CapabilityBlockNote(tradeBlock),
                AppButton(text: context.l10n.comboPlace, onPressed: null),
              ] else
                ComboReviewPanel(
                  legs: legs,
                  stakeUsd: _comboStake,
                  availableUsd: _watchAvailableUsd(),
                  onEditStake: _editComboStake,
                  onDeposit: depositBlock == null ? _deposit : null,
                  onPlaced: _onComboPlaced,
                  onBusy: (busy) {
                    if (mounted) setState(() => _comboBusy = busy);
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// One leg under review, as a card: image and whole title, the side
  /// under it, and on the right the number that matters (the leg's
  /// amount; the side's chance on a combined bet, which has one stake).
  Widget _reviewRow(
    AppColorsExtension c, {
    required String key,
    required Widget leading,
    required String title,
    required String sideText,
    required Color sideColor,
    required double amountUsd,
    double? chance,
    bool showAmount = true,
  }) {
    final run = _runStates[key];
    final error = _runErrors[key];
    final caption = TextStyle(
      color: c.textTertiary,
      fontSize: 13.sp,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.1,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final figure = TextStyle(
      color: c.textPrimary,
      fontSize: 20.sp,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
      height: 1.1,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return BuilderCardFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              leading,
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _legTitle(c, title),
                    SizedBox(height: 4.h),
                    Wrap(children: [
                      Text(
                        sideText,
                        style: caption.copyWith(
                            color: sideColor, fontWeight: FontWeight.w700),
                      ),
                      if (showAmount && chance != null)
                        Text(' · ${polyCardChance(chance)}', style: caption),
                    ]),
                  ],
                ),
              ),
              SizedBox(width: 10.w),
              if (showAmount) ...[
                Text(formatHlUsd(amountUsd), style: figure),
                if (run != null) ...[
                  SizedBox(width: 8.w),
                  _runStateIcon(c, run),
                ],
              ] else if (chance != null)
                Text(polyCardChance(chance), style: figure),
            ],
          ),
          if (error != null) ...[
            SizedBox(height: 10.h),
            Text(
              error,
              style: TextStyle(
                color: AppColors.error,
                fontSize: 13.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _runStateIcon(AppColorsExtension c, _LegRunState? run) {
    final child = switch (run) {
      _LegRunState.placing => SizedBox(
          width: 16.sp,
          height: 16.sp,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: _poolAccent,
          ),
        ),
      _LegRunState.done =>
        Icon(Icons.check_circle_rounded, size: 18.sp, color: greenColor),
      _LegRunState.paused =>
        Icon(Icons.hourglass_top_rounded, size: 18.sp, color: c.textSecondary),
      _LegRunState.failed =>
        Icon(Icons.cancel_rounded, size: 18.sp, color: AppColors.error),
      _LegRunState.pending =>
        Icon(Icons.circle_outlined, size: 16.sp, color: c.textTertiary),
      null => SizedBox(width: 16.sp),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: KeyedSubtree(
        key: ValueKey<_LegRunState?>(run),
        child: child,
      ),
    );
  }
}

// ── Small shared widgets ──────────────────────────────────────────────

/// Market selection uses the same plain rows as search; the trailing check
/// shows selection without wrapping each result in another card.
class _PickRow extends StatelessWidget {
  final Color accent;
  final bool selected;
  final Widget leading;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _PickRow({
    required this.accent,
    required this.selected,
    required this.leading,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(vertical: 16.h),
        child: Row(
          children: [
            leading,
            SizedBox(width: 10.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 17.sp,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (subtitle != null) ...[
                    SizedBox(height: 2.h),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.textTertiary,
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(width: 8.w),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.add_circle_outline_rounded,
                key: ValueKey<bool>(selected),
                size: 22.sp,
                color: selected ? accent : c.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact Yes/No and Long/Short selector chip. A null [onTap] renders it
/// disabled (e.g. a market with no No token). Selected side is a SOLID
/// market-color fill; unselected is a neutral chip (no pastel tints,
/// app-wide rule).
class _ChoiceChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  const _ChoiceChip({
    required this.label,
    required this.color,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final disabled = onTap == null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Opacity(
        opacity: disabled ? 0.4 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          constraints: BoxConstraints(minHeight: 44.h, minWidth: 76.w),
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 10.h),
          decoration: BoxDecoration(
            color: selected ? color : c.surfaceLight,
            borderRadius: AppRadius.buttonBorder,
            border:
                selected ? null : Border.all(color: c.borderSubtle, width: 0.5),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? contrastingOnColor(color) : c.textSecondary,
              fontSize: 14.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
