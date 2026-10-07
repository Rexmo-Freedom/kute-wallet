// lib/screens/search/unified_search_screen.dart
//
// Unified "Search kute" surface opened from the bottom search bar. ONE
// merged surface for search AND Sal: typing shows the live deterministic
// results, pressing send asks Sal (the chat takes over the body once a
// conversation is active). Rebuilt to match the app's shared bottom-sheet
// design language and to add three affordances:
//
//   1. Shared sheet chrome — the EXACT same rounded-top surface container
//      as Add funds (`showBankTransferSheet` / `_BuyMethodSheet`): opened
//      via `showModalBottomSheet(useRootNavigator: true,
//      isScrollControlled: true, useSafeArea: true, backgroundColor:
//      transparent)`, with a keyboard-aware bottom inset so the field +
//      results lift above the keyboard. No backdrop blur.
//
//   2. Category filter chips — a horizontal All / Transactions /
//      Predictions / Investing row styled like the Polymarket category
//      pills. All searches the three at once; selecting one narrows the
//      results to that section. Nothing else is searched: no balances,
//      no wallet-action shortcuts, no Settings destinations.
//
//   3. Correct per-type transaction icons — each transaction row reuses
//      the canonical activity-feed row builder (`buildUnifiedTransactionItem`)
//      so the Bitcoin / Spark / swap / Outlogic / Polymarket / USDB
//      leading icons match the rest of the app.
//
// Local results (transactions + the user's own positions) come from
// `unifiedSearchResultsProvider` and update instantly. The market groups
// stream in from the debounced remote providers, drawn with the Investing
// and Predictions tabs' own cards (positions with the Portfolio's), the
// named market first, four per group under All with a "See all", and card
// skeletons holding their place while they load.
//
// Public entrypoint: `showKuteSearch(BuildContext)`. The surface itself is
// `UnifiedSearchSurface`, which a host can also embed (the "+" sheet grows
// into it) by pairing `beginKuteSearchSession` / `endKuteSearchSession`.

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:kute/screens/shared/kute_dog_rig.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_search_provider.dart';
import 'package:kute/models/transactions_model.dart' show BaseTransaction;
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/transactions_provider.dart'
    show walletTransactionCacheProvider;
import 'package:kute/providers/polymarket_sports_provider.dart'
    show sportsLiveProvider, sportsUpdateFor, SportsMatchUpdate;
import 'package:kute/providers/unified_search_provider.dart';
import 'package:kute/screens/hyperliquid/market_detail_sheet.dart';
import 'package:kute/providers/ledger/ledger_identity_provider.dart';
import 'package:kute/screens/ledger/ledger_account_body.dart'
    show openLedgerInvestingSetup;
import 'package:kute/screens/polymarket/market_detail_sheet.dart';
import 'package:kute/screens/shared/animations/bouncy_touch.dart';
import 'package:kute/screens/shared/after_route_transition.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/components/kute_list_row.dart';
import 'package:kute/screens/shared/kute_composer.dart';
import 'package:kute/screens/shared/kute_skeleton.dart'
    show
        KuteSkeleton,
        SkeletonBar,
        SkeletonCard,
        SkeletonCardList,
        SkeletonCircle,
        SkeletonRowList;
import 'package:kute/screens/shared/kute_motion.dart' show ArrivalSwitcher;
import 'package:kute/screens/search/search_result_order.dart';
import 'package:kute/screens/hyperliquid/components/hl_market_card.dart';
import 'package:kute/screens/polymarket/components/live_token_scope.dart';
import 'package:kute/screens/polymarket/components/position_card.dart'
    show PolyPositionCard;
import 'package:kute/screens/polymarket/components/position_detail_sheet.dart'
    show polyPositionEnd;
import 'package:kute/screens/shared/investment_market_browser.dart'
    show PredictionBrowseCard;
import 'package:kute/models/hyperliquid_market.dart'
    show HlMarket, HlMarketKind, kHlLowLiquidityDayVolumeUsd;
import 'package:kute/providers/polymarket_live_prices_provider.dart'
    show livePriceProvider;
import 'package:kute/screens/shared/kute_taglines.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/screens/shared/transactions_builder.dart'
    show buildUnifiedTransactionItem, openTransactionDetails;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/models/advisor_context.dart';
import 'package:kute/services/advisor/advisor_input_guard.dart';
import 'package:kute/screens/shared/ask_sal_sheet.dart';
import 'package:kute/providers/sal_chip_signals.dart' show searchSalSignals;
import 'package:kute/services/advisor/sal_chip_catalogue.dart';

// ── Search analytics ──
//
// Never the query text, a market or a transaction: only the category,
// bucketed lengths and counts, and the categorical row kind
// (`transaction` | `owned_position` | `global_market` |
// `hyperliquid_market`).

/// Length bucket for typed text. The same cut points as the Sal events so
/// search and Sal read on one scale.
String _searchLengthBucket(int n) => n <= 20
    ? '1-20'
    : n <= 60
        ? '21-60'
        : n <= 200
            ? '61-200'
            : '200+';

String _searchCountBucket(int n) => n == 0
    ? '0'
    : n == 1
        ? '1'
        : n <= 5
            ? '2-5'
            : n <= 20
                ? '6-20'
                : '20+';

String _searchTimeBucket(Duration d) => d.inSeconds < 10
    ? '<10s'
    : d.inSeconds < 30
        ? '10-30s'
        : d.inSeconds < 120
            ? '30s-2m'
            : d.inMinutes < 10
                ? '2-10m'
                : '10m+';

/// What happened during one search open, reported once by
/// [endKuteSearchSession] as `search_closed`. Only one search surface is
/// ever on screen, so a single slot is enough.
class _SearchSessionStats {
  final Stopwatch watch = Stopwatch()..start();
  int resultsTapped = 0;
  int settledQueries = 0;
  bool submitted = false;
}

_SearchSessionStats? _searchStats;

/// One `search_result_tapped` per row tap. [position] is the row's 0-based
/// place in the visible result list; [target] is 'ledger' for a Ledger
/// account search. Same event name the dashboards already read.
void _trackSearchResultTap(
  WidgetRef ref,
  String resultType, {
  int? position,
  String? target,
}) {
  _searchStats?.resultsTapped++;
  TrackingService.track('search_result_tapped', params: {
    'result_type': resultType,
    'category': ref.read(selectedSearchCategoryProvider).name,
    if (position != null) 'position': position,
    if (target != null) 'target': target,
  });
}

/// Opens the unified search surface as a scroll-controlled bottom sheet
/// using the app's shared sheet chrome. The query is reset on open so a
/// fresh open starts empty; the category is seeded to [initialCategory]
/// (default [SearchCategory.all]) so callers can pre-select a section —
/// e.g. the Predictions screen passes [SearchCategory.predictions].
///
/// Home, Investing and Predictions combine search with Sal: typing filters
/// results in the initial category and submitting starts a general conversation.
/// [searchHint] lets a venue describe its initial market context in the field.
///
/// [source] is the categorical screen the search was opened from
/// ('home' | 'predictions' | 'portfolio' | 'wallet_detail' | 'trading'),
/// tagged onto the `search_opened` analytics event.
Future<void> showKuteSearch(
  BuildContext context, {
  SearchCategory initialCategory = SearchCategory.all,
  // Results-first open (the pool screens' Search chip): the sheet opens
  // straight into the filter chips + typeahead surface — no mascot / AI
  // intro. Submitting can still ask Sal a general question.
  bool searchFirst = false,
  // Domain-scoped open (user decision: the pool screens search ONLY their
  // own markets): the category is fixed, the filter chips are hidden, and
  // only that category's result leg renders.
  bool lockCategory = false,
  // Pool-scoped chip set: when non-null, the chip row renders THESE tabs
  // (even under lockCategory) so a scoped sheet can offer e.g.
  // Custom filters without exposing the global categories.
  List<(SearchCategory, String)>? scopedTabs,
  String source = 'unknown',
  String? walletId,
  // Ledger account market search (Predictions / Investing tabs): only the
  // public market legs render, locked to [initialCategory], and every
  // result opens on that Ledger wallet's targets. Never combined with
  // [walletId] (the transactions-only scope).
  String? ledgerWalletId,
  String? searchHint,
}) async {
  assert(walletId == null || ledgerWalletId == null);
  // One search sheet at a time: a second tap while it slides in must not
  // reseed (and so empty) the session of the sheet already opening.
  if (OpenOnce.isOpen(_kSearchSheetKey)) return;
  final container = ProviderScope.containerOf(context, listen: false);
  final ledgerMarkets = ledgerWalletId != null;
  final effectiveCategory = beginKuteSearchSession(
    container,
    initialCategory: initialCategory,
    lockCategory: lockCategory,
    walletId: walletId,
    ledgerWalletId: ledgerWalletId,
  );
  // Single search entry point — emit `search_opened` (+ a `search`
  // screen_view) here so every affordance is covered exactly once.
  TrackingService.searchOpened(
    source: source,
    initialCategory: effectiveCategory.name,
  );
  // The app's sheet (showAppBottomSheet): over the ROOT navigator so it
  // sits above tab-scoped routes, with the surface drawn by the shared
  // AppBottomSheetContainer, which lifts the field + results with the
  // keyboard frame for frame.
  try {
    await OpenOnce.run(_kSearchSheetKey, () => showAppBottomSheet<void>(
      context: context,
      builder: (_) => UnifiedSearchSurface(
        initialCategory: effectiveCategory,
        searchFirst: searchFirst || ledgerMarkets,
        lockCategory: walletId != null || ledgerMarkets || lockCategory,
        scopedTabs: walletId == null && !ledgerMarkets ? scopedTabs : null,
        walletId: walletId,
        searchHint: searchHint,
      ),
    ));
  } finally {
    endKuteSearchSession(container);
  }
}

const _kSearchSheetKey = 'kute_search';

/// Seeds the providers [UnifiedSearchSurface] reads and starts a clean Sal
/// session, exactly as the surface expects on entry. [showKuteSearch] calls
/// it before opening its own sheet; a host that EMBEDS the surface (the "+"
/// sheet, which grows into it instead of opening a second window) calls it
/// when the surface appears and pairs it with [endKuteSearchSession] when the
/// host goes away. Returns the category actually seeded — a wallet-scoped
/// open forces transactions.
SearchCategory beginKuteSearchSession(
  ProviderContainer container, {
  SearchCategory initialCategory = SearchCategory.all,
  bool lockCategory = false,
  String? walletId,
  String? ledgerWalletId,
}) {
  final effectiveCategory =
      walletId == null ? initialCategory : SearchCategory.transactions;
  final marketsOnly = ledgerWalletId != null ||
      walletId == null &&
          lockCategory &&
          (effectiveCategory == SearchCategory.predictions ||
              effectiveCategory == SearchCategory.perpetuals);
  // An embedded host can reopen without ending: close the previous open
  // out first so every `search_opened` gets its `search_closed`.
  _reportSearchClosed(container);
  container.read(searchQueryProvider.notifier).state = '';
  container.read(searchWalletScopeProvider.notifier).state = walletId;
  container.read(searchLedgerWalletIdProvider.notifier).state = ledgerWalletId;
  container.read(searchMarketsOnlyProvider.notifier).state = marketsOnly;
  container.read(selectedSearchCategoryProvider.notifier).state =
      effectiveCategory;
  container.read(advisorSessionProvider.notifier).clear();
  _searchStats = _SearchSessionStats();
  return effectiveCategory;
}

/// Reports the open search session (if any) as `search_closed`, plus
/// `sal_closed` when it turned into a Sal conversation. Reads the
/// conversation before it is cancelled or cleared: a turn still loading
/// here is one the user closed on. Once per session: the slot is emptied.
void _reportSearchClosed(ProviderContainer container) {
  final stats = _searchStats;
  _searchStats = null;
  if (stats == null) return;
  final advisor = container.read(advisorSessionProvider);
  if (advisor.isActive) {
    trackSalClosed(advisor, entry: 'search', surface: 'search');
  }
  TrackingService.track('search_closed', params: {
    'outcome': stats.resultsTapped > 0
        ? 'result_tapped'
        : advisor.isActive
            ? 'asked_sal'
            : stats.settledQueries > 0 || stats.submitted
                ? 'searched_no_tap'
                : 'no_query',
    'results_tapped': stats.resultsTapped,
    'queries': stats.settledQueries,
    'time_in_flow_bucket': _searchTimeBucket(stats.watch.elapsed),
  });
}

/// Undoes [beginKuteSearchSession]: the Sal turn in flight is cancelled and
/// every scope the surface set is released, so the next open starts clean.
void endKuteSearchSession(ProviderContainer container) {
  _reportSearchClosed(container);
  container.read(advisorSessionProvider.notifier).cancel();
  container.read(searchQueryProvider.notifier).state = '';
  container.read(searchWalletScopeProvider.notifier).state = null;
  container.read(searchLedgerWalletIdProvider.notifier).state = null;
  container.read(searchMarketsOnlyProvider.notifier).state = false;
}

/// The unified search surface itself: category tabs, live results and the
/// one composer that searches while you type and asks Sal on send.
///
/// [showKuteSearch] hosts it as a modal sheet with its own chrome. With
/// [embedded] true it renders as a bare content column instead, for a host
/// that already owns the sheet surface, the drag handle and the keyboard
/// inset (the "+" sheet). An embedded host must run
/// [beginKuteSearchSession] / [endKuteSearchSession] itself.
class UnifiedSearchSurface extends ConsumerStatefulWidget {
  final SearchCategory initialCategory;
  final bool searchFirst;
  final bool lockCategory;
  final List<(SearchCategory, String)>? scopedTabs;
  final String? walletId;
  final String? searchHint;
  final bool embedded;
  const UnifiedSearchSurface({
    super.key,
    this.initialCategory = SearchCategory.all,
    this.searchFirst = false,
    this.lockCategory = false,
    this.scopedTabs,
    this.walletId,
    this.searchHint,
    this.embedded = false,
  });

  @override
  ConsumerState<UnifiedSearchSurface> createState() =>
      _UnifiedSearchSurfaceState();
}

class _UnifiedSearchSurfaceState extends ConsumerState<UnifiedSearchSurface> {
  int _queryGeneration = 0;
  Timer? _queryDebounce;
  // `search_results_settled`: fires once per distinct settled query +
  // category, after the remote legs stop loading. Never the query itself;
  // the key only lives in memory for the dedupe.
  Timer? _settleTimer;
  String? _lastSettledKey;
  // What the last build showed, read by the settle timer (no events fire
  // from build).
  int _visibleResults = 0;
  List<String> _visibleTypes = const [];
  bool _resultsLoading = false;
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  VoidCallback? _cancelFocus;
  // Sal's opening questions for this open, chosen once per language from
  // the public movers and starred markets already loaded.
  (Locale, List<SalChip>)? _salChips;
  // Whether the markets lead the results, decided once per query.
  (String, bool)? _marketsFirst;

  /// Investing and Predictions above Transactions when [query] names a
  /// market. Decided on the query's first frame from what is on the device
  /// (hlQueryNamesMarket) and kept for that query, never from when the
  /// remote results arrive, so groups do not trade places on screen.
  bool _marketsFirstFor(String query) {
    if (query.isEmpty) return false;
    final memo = _marketsFirst;
    if (memo != null && memo.$1 == query) return memo.$2;
    // Only a universe already in memory: this never starts a read.
    final universe = ref.exists(hyperliquidBrowseUniverseProvider)
        ? ref.read(hyperliquidBrowseUniverseProvider).valueOrNull ?? const []
        : const <HlMarket>[];
    final first = hlQueryNamesMarket(query, universe);
    _marketsFirst = (query, first);
    return first;
  }

  @override
  void initState() {
    super.initState();
    // Rebuild on focus change so the live type-ahead overlay appears while the
    // composer is focused and hides when the keyboard is dismissed / on send.
    _focusNode.addListener(() {
      if (mounted) setState(() {});
    });
    // Focus the composer once the sheet has slid in (never mid-slide:
    // afterRouteTransition), so the keyboard rises against a settled
    // sheet. Nothing else runs on open: results, and the live sports feed
    // they use, wait for the first query.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _cancelFocus = requestFocusAfterTransition(context, _focusNode);
    });
  }

  @override
  void dispose() {
    _cancelFocus?.call();
    _queryDebounce?.cancel();
    _settleTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // Keep editing immediate, but coalesce privacy checks and local matching.
  // Remote providers cancel their own delayed/in-flight work on query change.
  void _onChanged(String value) {
    final generation = ++_queryGeneration;
    _queryDebounce?.cancel();
    ref.read(searchQueryProvider.notifier).state = '';
    if (value.trim().isEmpty) return;
    _queryDebounce = Timer(
      const Duration(milliseconds: 150),
      () => _publishSafeQuery(value, generation),
    );
  }

  Future<void> _publishSafeQuery(String value, int generation) async {
    var safe = false;
    try {
      safe = await AdvisorInputGuard.isSafe(value);
    } catch (_) {
      // Unchecked text never reaches a public search provider.
    }
    if (!mounted || generation != _queryGeneration) return;
    if (!safe) {
      ref.read(searchQueryProvider.notifier).state = '';
      return;
    }
    if (!ref.read(advisorSessionProvider).isActive) {
      // The first query joins the live sports feed, so in-play prediction
      // markets in the results get tagged live with a real scoreline even
      // when search was opened from a surface that never connected it.
      // Idempotent: `connect()` does nothing when already connected.
      if (widget.walletId == null) {
        ref.read(sportsLiveProvider.notifier).connect();
      }
      ref.read(searchQueryProvider.notifier).state = value.trim();
      _scheduleSettle(value.trim(), generation);
    }
  }

  /// Reports the results a query settled on: once the user has stopped
  /// typing and the remote legs have answered (bounded wait), once per
  /// distinct query + category. Counts and the categorical row kinds only.
  void _scheduleSettle(String query, int generation, [int attempt = 0]) {
    _settleTimer?.cancel();
    if (widget.walletId != null || query.isEmpty) return;
    _settleTimer = Timer(Duration(milliseconds: attempt == 0 ? 1200 : 600), () {
      if (!mounted || generation != _queryGeneration) return;
      if (ref.read(advisorSessionProvider).isActive) return;
      if (ref.read(searchQueryProvider).trim() != query) return;
      if (_resultsLoading && attempt < 6) {
        _scheduleSettle(query, generation, attempt + 1);
        return;
      }
      final category = ref.read(selectedSearchCategoryProvider).name;
      final key = '$category|$query';
      if (key == _lastSettledKey) return;
      _lastSettledKey = key;
      _searchStats?.settledQueries++;
      TrackingService.track('search_results_settled', params: {
        'category': category,
        'query_length_bucket': _searchLengthBucket(query.length),
        'result_count_bucket': _searchCountBucket(_visibleResults),
        'has_results': _visibleResults > 0,
        'result_types': _visibleTypes.join(','),
        'still_loading': _resultsLoading,
        'ai_enabled': ref.read(aiEnabledProvider).valueOrNull ?? true,
      });
    });
  }

  /// Search results update while typing; submitting asks Sal a general question.
  /// With AI disabled, submit only publishes a privacy-checked search query.
  Future<void> _submit() async {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    HapticFeedback.lightImpact();
    _focusNode.unfocus();
    final aiEnabled = ref.read(aiEnabledProvider).valueOrNull ?? true;
    if (!mounted) return;
    if (!aiEnabled) {
      // Length bucket only; the query text never leaves the device.
      _searchStats?.submitted = true;
      TrackingService.track('search_submitted', params: {
        'query_length_bucket': _searchLengthBucket(q.length),
        'category': ref.read(selectedSearchCategoryProvider).name,
        'ai_enabled': false,
      });
      _queryDebounce?.cancel();
      await _publishSafeQuery(q, ++_queryGeneration);
      return;
    }
    // Send to the assistant — appends a chat turn (history is preserved).
    _queryGeneration++;
    _queryDebounce?.cancel();
    _settleTimer?.cancel();
    // The first question turns this search into a Sal conversation: that
    // is Sal opening from search (`sal_opened` otherwise only fires from
    // the Ask Sal sheet). Follow-ups in the same conversation don't re-open.
    final session = ref.read(advisorSessionProvider.notifier);
    if (!ref.read(advisorSessionProvider).isActive) {
      TrackingService.salOpened(entry: 'search', surface: 'search');
    }
    session.setAnalyticsSurface('search');
    session.ask(q,
        input: 'typed', locale: Localizations.localeOf(context).languageCode);
    _controller.clear();
    ref.read(searchQueryProvider.notifier).state = '';
  }

  List<SalChip> _chips(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final cached = _salChips;
    if (cached != null && cached.$1 == locale) return cached.$2;
    // The market questions are Investing ones: a Predictions search keeps
    // to the general questions.
    final chips = SalChipCatalogue.select(
      const AdvisorContext(surface: 'search'),
      context.l10n,
      signals: widget.initialCategory == SearchCategory.predictions
          ? const SalChipSignals()
          : searchSalSignals(ProviderScope.containerOf(context, listen: false)),
    );
    _salChips = (locale, chips);
    return chips;
  }

  /// A tapped opening question asks Sal like a submitted one. A market
  /// question carries that public market so Sal answers about it.
  void _askChip(SalChip chip, int index) {
    HapticFeedback.lightImpact();
    _focusNode.unfocus();
    _queryGeneration++;
    _queryDebounce?.cancel();
    _settleTimer?.cancel();
    final session = ref.read(advisorSessionProvider.notifier);
    if (!ref.read(advisorSessionProvider).isActive) {
      TrackingService.salOpened(entry: 'search', surface: 'search');
    }
    session.setAnalyticsSurface('search');
    session.ask(chip.text,
        context: chip.context,
        input: 'suggested',
        template: chip.template,
        chipIndex: index,
        locale: Localizations.localeOf(context).languageCode);
    _controller.clear();
    ref.read(searchQueryProvider.notifier).state = '';
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider).trim();
    final advisor = ref.watch(advisorSessionProvider);
    if (advisor.isActive && ref.watch(aiEnabledProvider).valueOrNull != false) {
      // Active chat does not subscribe to account or market search providers.
      // The conversation is only content inside this sheet's own chrome.
      return _buildSheet(
        context,
        chat: true,
        children: [
          Expanded(
            child: SalChatPanel(
              embedded: true,
              advisorContext:
                  advisor.context ?? const AdvisorContext(surface: 'chat'),
            ),
          ),
          if (widget.embedded) SizedBox(height: 8.h),
        ],
      );
    }
    final category = ref.watch(selectedSearchCategoryProvider);
    final hasDraft = _controller.text.trim().isNotEmpty;
    final localAsync = ref.watch(unifiedSearchResultsProvider);
    final local = localAsync.valueOrNull ?? UnifiedSearchResults.empty;
    final globalAsync = ref.watch(globalMarketResultsProvider);
    final hlAsync = ref.watch(globalHyperliquidResultsProvider);

    final globalResults = globalAsync.valueOrNull ?? const [];
    final globalLoading = query.isNotEmpty && globalAsync.isLoading;
    final hlResults = hlAsync.valueOrNull ?? const [];
    final hlLoading = query.isNotEmpty && hlAsync.isLoading;

    // Master AI kill switch (fail-open while loading). When AI is off the
    // surface degrades to search-only: no chat, no send-to-Sal.
    final aiEnabled = ref.watch(aiEnabledProvider).valueOrNull ?? true;

    // Visibility per category filter.
    final showTx = category == SearchCategory.all ||
        category == SearchCategory.transactions;
    final showPredictions = category == SearchCategory.all ||
        category == SearchCategory.predictions;
    // Hyperliquid markets (perps + stock tokens) show under All and the
    // dedicated Perpetuals filter.
    final showPerpetuals =
        category == SearchCategory.all || category == SearchCategory.perpetuals;
    final txSection = showTx && local.transactions.isNotEmpty;
    final predictionSection = showPredictions &&
        (local.ownedPositions.isNotEmpty ||
            globalResults.isNotEmpty ||
            globalLoading);
    final perpetualsSection =
        showPerpetuals && (hlResults.isNotEmpty || hlLoading);

    final hasAnyResult = txSection || predictionSection || perpetualsSection;

    // Result rows grouped by type: Investing, Predictions and Transactions,
    // nothing else. Under the "All" filter all three can appear at once, so
    // each group is introduced by the slips' quiet section label and shows
    // its first four with a "See all" that switches the filter to it. Under
    // a single-type filter only one group shows, whole and unlabelled (the
    // pill already names it).
    //
    // Within a group the market the person named leads (exact ticker or
    // name, then prefixes, then the rest; search_result_order.dart). When
    // the query names a market, Investing and Predictions sit above
    // Transactions; that is decided once per query from what is on the
    // device, so a group never jumps when the remote results land.
    final sportsLive = ref.read(sportsLiveProvider);
    final rankedHl = rankInvestingResults(query, hlResults);
    final rankedGlobal = rankPredictionResults(
      query,
      globalResults,
      (r) => r.event,
      isLive: (r) =>
          r.event.isInPlay ||
          (_liveUpdateFor(r.event, sportsLive)?.isInPlay ?? false),
    );
    final investing = _ResultGroup(
      key: 'investing',
      label: context.l10n.trading,
      filter: SearchCategory.perpetuals,
      loading: hlLoading,
      skeleton: const _MarketCardSkeletons(investing: true),
      rows: [
        for (final r in rankedHl)
          (int p) => _HlMarketRow(
              key: ValueKey('hl-${r.kind.name}-${r.wireCoin}'),
              result: r,
              position: p),
      ],
    );
    final predictions = _ResultGroup(
      key: 'predictions',
      label: context.l10n.predictions,
      filter: SearchCategory.predictions,
      loading: globalLoading,
      skeleton: const _MarketCardSkeletons(investing: false),
      rows: [
        // The person's own positions first.
        for (final r in local.ownedPositions)
          (int p) => _OwnedPositionRow(result: r, position: p),
        for (final r in rankedGlobal)
          (int p) => _GlobalMarketRow(
              key: ValueKey('poly-${r.event.slug}-${r.event.id}'),
              result: r,
              position: p),
      ],
    );
    final transactions = _ResultGroup(
      key: 'transactions',
      label: context.l10n.transactions,
      filter: SearchCategory.transactions,
      rows: [
        for (final r in local.transactions)
          (int p) => _TransactionRow(result: r, position: p),
      ],
    );
    final groups = <_ResultGroup>[
      if (_marketsFirstFor(query)) ...[
        if (perpetualsSection) investing,
        if (predictionSection) predictions,
        if (txSection) transactions,
      ] else ...[
        if (txSection) transactions,
        // Investing markets rank above Predictions in the All list.
        if (perpetualsSection) investing,
        if (predictionSection) predictions,
      ],
    ];
    // `pos` numbers the result rows in display order (analytics position
    // on tap); skeletons and "See all" take no number.
    var pos = 0;
    final labelGroups = category == SearchCategory.all;
    final resultChildren = <Widget>[];
    for (final g in groups) {
      final capped = labelGroups && g.rows.length > kSearchSectionCap;
      final shown = capped ? g.rows.take(kSearchSectionCap) : g.rows;
      final rows = [for (final build in shown) build(pos++)];
      final waiting = rows.isEmpty && g.loading;
      if (labelGroups) {
        resultChildren.add(_TypeSectionHeader(
            key: ValueKey('header-${g.key}'), label: g.label));
      }
      resultChildren.add(ArrivalSwitcher(
        key: ValueKey('group-${g.key}'),
        // Skeletons hold the group's place until its rows land, then
        // cross-fade into them while the height eases.
        state: waiting ? 'loading' : 'rows',
        child: waiting
            ? g.skeleton ?? const SizedBox.shrink()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...rows,
                  if (capped)
                    _SeeAllRow(onTap: () {
                      TrackingService.searchCategoryChanged(g.filter.name);
                      ref.read(selectedSearchCategoryProvider.notifier).state =
                          g.filter;
                    }),
                ],
              ),
      ));
    }
    // Snapshot for the settle timer: plain fields, no event from build.
    _visibleResults = pos;
    _visibleTypes = [
      for (final g in groups)
        if (g.rows.isNotEmpty) g.key,
    ];
    _resultsLoading = localAsync.isLoading || globalLoading || hlLoading;

    // Warm the HL universe while the Investing result leg can show, so
    // tapping a searched market resolves to the detail sheet
    // (`hyperliquidMarketProvider(coin)` needs the perp/spot lists loaded).
    if (query.isNotEmpty && showPerpetuals) {
      ref.watch(hyperliquidAllMarketsProvider);
    }

    // Active chat returns above. The remaining content is deterministic search.
    final Widget body;
    if (widget.walletId != null) {
      body = _WalletActivityResults(walletId: widget.walletId!, query: query);
    } else if (query.isNotEmpty) {
      body = !hasAnyResult && localAsync.isLoading
          ? SkeletonRowList(count: 3, padding: EdgeInsets.only(top: 8.h))
          : !hasAnyResult
              ? _EmptyState(
                  prompt: aiEnabled
                      ? context.l10n.searchNoMatchesAskSal(query)
                      : context.l10n.searchNoResultsFor(query),
                )
              : ListView(
                  // Manual (not onDrag) — scrolling the results must NOT dismiss
                  // the keyboard out from under the user mid-search.
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.manual,
                  padding: EdgeInsets.only(top: 8.h, bottom: 8.h),
                  children: resultChildren,
                );
    } else if (hasDraft) {
      body = _EmptyState(prompt: context.l10n.searchSearching);
    } else if (widget.searchFirst) {
      // Results-first idle: the chips row is already showing above; keep
      // the body a plain quiet prompt so the surface reads as search, not
      // as the Sal intro. A market-scoped open (a venue) names markets; an
      // open on everything (Home's bitcoin cards) names what it covers.
      body = _EmptyState(
          prompt: widget.initialCategory == SearchCategory.perpetuals ||
                  widget.initialCategory == SearchCategory.predictions
              ? context.l10n.searchTypeToSearchMarkets
              : context.l10n.searchIdlePrompt);
    } else if (aiEnabled) {
      body = _EmptyState(
        prompt: widget.searchHint ?? context.l10n.searchOrAskSal,
        showMascot: true,
        chips: [
          for (final (index, chip) in _chips(context).indexed)
            SalSuggestionButton(
              text: chip.text,
              onPressed: () => _askChip(chip, index),
            ),
        ],
      );
    } else {
      body = _EmptyState(prompt: context.l10n.searchIdlePrompt);
    }

    return _buildSheet(
      context,
      children: [
        // While a query is being typed (or in search-only mode) the
        // compact filter "tabs" (All · Transactions · Predictions ·
        // Investing) narrow the live results. Idle with Sal available:
        // no header row — the drag handle sits straight above the chat /
        // intro, so there's no empty gap. A pool-scoped sheet renders
        // its OWN tab set even under
        // lockCategory.
        if (widget.scopedTabs != null) ...[
          _WalletFilterChips(selected: category, tabs: widget.scopedTabs),
          SizedBox(height: 4.h),
        ] else if (!widget.lockCategory &&
            (hasDraft ||
                query.isNotEmpty ||
                !aiEnabled ||
                widget.searchFirst)) ...[
          _WalletFilterChips(selected: category),
          SizedBox(height: 4.h),
        ],
        Expanded(child: body),
        SizedBox(height: 8.h),
        // The composer searches while typing and asks Sal on submit.
        KuteComposer(
          controller: _controller,
          focusNode: _focusNode,
          onChanged: _onChanged,
          onSubmit: _submit,
          aiEnabled: aiEnabled,
          sendLabel: context.l10n.salSendQuestion,
          // With Sal available the field names both jobs, the words the
          // dock's square wears; search-only keeps the scoped hint.
          hint: aiEnabled
              ? context.l10n.searchOrAskSalShort
              : (widget.initialCategory == SearchCategory.perpetuals ||
                      widget.initialCategory == SearchCategory.predictions)
                  ? context.l10n.searchMarketsHint
                  : context.l10n.searchYourWallet,
        ),
        // Sal's disclaimer sits under its answers, once; the search
        // composer carries none.
        // The host of an embedded surface owns the keyboard inset; its
        // composer always sits this gap above the sheet's edge.
        if (widget.embedded) SizedBox(height: 8.h),
      ],
    );
  }

  Widget _buildSheet(
    BuildContext context, {
    required List<Widget> children,
    bool chat = false,
  }) {
    // Embedded: the host sheet already draws the surface, the drag handle
    // and the keyboard / bottom inset (AppBottomSheetContainer), so the
    // surface is only its content column. Adding any of it again would
    // double the padding and stack two handles.
    if (widget.embedded) {
      return Column(children: children);
    }
    // The shared sheet: AppBottomSheetContainer owns the surface, the
    // keyboard (followed frame by frame) and the home-indicator inset.
    // Searching keeps only the drag handle, where the shared header draws
    // it; a conversation wears the shared header with its close X, as the
    // Ask Sal sheet does.
    return AppBottomSheetContainer(
      maxHeight: .92,
      followKeyboard: true,
      child: Column(
        children: [
          if (chat)
            AppBottomSheetHeader(
              title: context.l10n.salChatWith,
              trailing: const AppBottomSheetCloseButton(),
            )
          else ...[
            SizedBox(height: 12.h),
            AppDecorations.dragHandle(context),
            SizedBox(height: 8.h),
          ],
          ...children,
        ],
      ),
    );
  }
}

/// The compact filter "tabs" shown while a query is being typed:
/// All · Transactions · Predictions · Investing. Selecting one writes
/// [selectedSearchCategoryProvider], which the sheet's `showTx` /
/// `showPredictions` / `showPerpetuals` visibility already reads to narrow
/// the result groups. Replaces the old "Search wallet" text label — the
/// segments name the surface, so no separate header is needed. The shared
/// control scrolls when labels need more room on narrow devices.
class _WalletFilterChips extends ConsumerWidget {
  final SearchCategory selected;

  /// Custom tab set for product sheets; null renders the global set.
  final List<(SearchCategory, String)>? tabs;
  const _WalletFilterChips({required this.selected, this.tabs});

  /// The global tab set. The Hyperliquid leg keeps its `perpetuals`
  /// category key (analytics stay stable) but reads Investing.
  static List<(SearchCategory, String)> _standardTabs(BuildContext context) => [
        (SearchCategory.all, context.l10n.searchFilterAll),
        (SearchCategory.transactions, context.l10n.transactions),
        (SearchCategory.predictions, context.l10n.predictions),
        (SearchCategory.perpetuals, context.l10n.trading),
      ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final effective = tabs ?? _standardTabs(context);
    // The same pills the category strips use, so a filter here and a
    // category on Investing or Predictions read as one control rather
    // than two vocabularies (user decision September 2026). Label only,
    // matching those strips after their glyphs came off.
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: KutePillTabs(
        horizontalPadding: 16,
        selectedIndex: effective.indexWhere((tab) => tab.$1 == selected),
        items: [for (final tab in effective) KutePillItem(label: tab.$2)],
        onTap: (index) {
          HapticFeedback.selectionClick();
          final next = effective[index].$1;
          if (next != selected) TrackingService.searchCategoryChanged(next.name);
          ref.read(selectedSearchCategoryProvider.notifier).state = next;
        },
      ),
    );
  }
}

/// A Bitcoin/hardware wallet keeps the search history within its account.
class _WalletActivityResults extends ConsumerWidget {
  final String walletId;
  final String query;
  const _WalletActivityResults({required this.walletId, required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = query.trim().toLowerCase();
    final rows = (ref
                .watch(walletTransactionCacheProvider)[walletId]
                ?.allTransactionsSorted ??
            const <BaseTransaction>[])
        .where((tx) => q.isEmpty || transactionSearchableText(tx).contains(q))
        .toList();
    if (rows.isEmpty) {
      return _EmptyState(
          prompt: q.isEmpty
              ? context.l10n.ledgerActivityEmpty
              : context.l10n.searchNoMatchingActivity);
    }
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
      padding: EdgeInsets.symmetric(vertical: 8.h),
      itemCount: rows.length,
      itemBuilder: (context, index) =>
          buildUnifiedTransactionItem(rows[index], context, ref),
    );
  }
}

/// Transaction result row. Reuses the canonical activity-feed row builder
/// so the per-type leading icon (Bitcoin / Spark / swap / Outlogic /
/// Polymarket / USDB) matches the rest of the app exactly, and tags each
/// row with the OWNING WALLET's name — search spans every wallet, so the
/// row would otherwise be ambiguous about which wallet a tx belongs to.
///
/// The canonical builder doesn't show the wallet, so we render a small
/// wallet-name pill under it. Tapping does NOT pop the search sheet: the
/// detail surface is dispatched directly so it stacks ON TOP of the
/// still-open search, and closing it returns the user to the search.
class _TransactionRow extends ConsumerWidget {
  final TransactionSearchResult result;
  final int? position;
  const _TransactionRow({required this.result, this.position});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tx = result.transaction;
    final walletName = result.walletName;
    // The canonical builder already renders the row with the correct
    // leading icon, title, subtitle, amount + an internal onTap that
    // opens the detail sheet. We keep the search sheet OPEN and dispatch
    // the detail through the public opener so it mounts ON TOP of search
    // (closing the detail returns here, not the underlying screen).
    return BouncyTouch(
      onTap: () {
        HapticFeedback.lightImpact();
        _trackSearchResultTap(ref, 'transaction', position: position);
        openTransactionDetails(context, ref, tx);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AbsorbPointer(
            child: buildUnifiedTransactionItem(tx, context, ref),
          ),
          if (walletName.isNotEmpty)
            Padding(
              // Align under the row text (leading icon ≈ 40w + 16w gap),
              // lifted up so it tucks beneath the row, above the divider.
              padding: EdgeInsets.fromLTRB(72.w, 0, 16.w, 10.h),
              child: _WalletTag(name: walletName),
            ),
        ],
      ),
    );
  }
}

/// Small rounded pill showing the wallet a transaction belongs to.
class _WalletTag extends StatelessWidget {
  final String name;
  const _WalletTag({required this.name});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(6.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.account_balance_wallet_rounded,
            size: 11.sp,
            color: c.textTertiary,
          ),
          SizedBox(width: 5.w),
          Flexible(
            child: Text(
              name,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 12.sp,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// One of the user's own positions that matches the query, drawn as the
/// Portfolio draws it ([PolyPositionCard]): the game's teams or the
/// market's image and title, the position in one line, its value with the
/// profit or loss under it, following the held outcome's live price.
/// Tapping keeps search's destination: the market's detail sheet.
class _OwnedPositionRow extends ConsumerWidget {
  final OwnedPositionSearchResult result;
  final int? position;
  const _OwnedPositionRow({required this.result, this.position});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = result.position;
    final live = ref.watch(
        livePriceProvider.select((s) => s.live ? s.prices[p.tokenId] : null));
    final price = p.isResolved ? p.currentPrice : live ?? p.currentPrice;
    final pnl = (price - p.avgPrice) * p.size;
    return _MarketCardSlot(
      child: LiveTokenScope(
        tokens: [if (!p.isResolved && p.tokenId != null) p.tokenId!],
        child: PolyPositionCard(
          question: p.marketQuestion,
          imageUrl: p.marketImage,
          outcome: p.outcome,
          shares: p.size,
          avgPrice: p.avgPrice,
          value: p.size * price,
          pnl: pnl,
          pnlPercent: p.avgPrice > 0 ? (price / p.avgPrice - 1) * 100 : 0.0,
          eventSlug: p.eventSlug,
          end: polyPositionEnd(p),
          conditionId: p.marketId,
          resolved: p.isResolved,
          claimable: p.won == true,
          onTap: () {
            HapticFeedback.lightImpact();
            _trackSearchResultTap(ref, 'owned_position', position: position);
            _openMarket(context, ref, p);
          },
        ),
      ),
    );
  }

  Future<void> _openMarket(
      BuildContext context, WidgetRef ref, PolymarketPosition p) async {
    // Keep the search sheet open — `MarketDetailSheet.show` pushes on the
    // root navigator so it stacks ON TOP of search; closing it returns
    // here rather than dropping to the underlying screen.
    final slug = p.eventSlug;
    PolymarketEvent? event;
    if (slug != null && slug.isNotEmpty) {
      try {
        event = await ref.read(polymarketEventDetailsProvider(slug).future);
      } catch (_) {
        event = null;
      }
    }
    if (!context.mounted) return;
    final ledgerWalletId = ref.read(searchLedgerWalletIdProvider);
    if (event != null) {
      MarketDetailSheet.show(context,
          event: event, ledgerWalletId: ledgerWalletId, source: 'search');
    } else if (ledgerWalletId == null) {
      // No resolvable event — fall back to the predictions tab. A Ledger
      // search never routes to the hot Predictions tab.
      context.go('/polymarket');
    }
  }
}

/// A Polymarket market from the remote search, drawn with the Predictions
/// list's own card ([PredictionBrowseCard] over [MarketCard]): the game's
/// teams and score from the live feed, a Yes/No market's chance and day
/// move, or an event's two most likely outcomes. Search stays open — the
/// market detail stacks on top (root navigator) and closing it returns to
/// the results.
class _GlobalMarketRow extends ConsumerWidget {
  final GlobalMarketSearchResult result;
  final int? position;
  const _GlobalMarketRow({super.key, required this.result, this.position});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = result.event;
    return _MarketCardSlot(
      child: PredictionBrowseCard(
        event: e,
        followLiveGame: true,
        onTap: () {
          HapticFeedback.lightImpact();
          // A Ledger account search opens the market on that wallet's
          // Ledger bet target (MarketDetailSheet forwards ledgerWalletId).
          final ledgerWalletId = ref.read(searchLedgerWalletIdProvider);
          _trackSearchResultTap(ref, 'global_market',
              position: position,
              target: ledgerWalletId != null ? 'ledger' : null);
          MarketDetailSheet.show(context,
              event: e, ledgerWalletId: ledgerWalletId, source: 'search');
        },
      ),
    );
  }
}

/// An Investing market from [globalHyperliquidResultsProvider], drawn with
/// the Investing list's own card ([HlMarketCard]): the logo, the name over
/// "TICKER · 40x", the daily line, and the live price over the day's
/// change. Tapping re-resolves the full [HlMarket] and opens the Investing
/// detail sheet on the root navigator (so it stacks ON TOP of search); if
/// the universe hasn't loaded yet it falls back to the Investing tab.
class _HlMarketRow extends ConsumerWidget {
  final HlMarketSearchResult result;
  final int? position;
  const _HlMarketRow({super.key, required this.result, this.position});

  /// The browse market the hit came from; a result built without one (a
  /// test) is drawn from its own figures.
  HlMarket _market() {
    final r = result;
    final known = r.market;
    if (known != null) return known;
    final spot = r.kind == HlMarketKind.spot;
    final change = r.dayChangePct;
    return HlMarket(
      coin: r.coin,
      wireCoin: r.wireCoin,
      assetId: -1,
      kind: r.kind,
      szDecimals: ((spot ? 8 : 6) - (r.pxDecimalCap ?? 2)).clamp(0, 8),
      maxLeverage: r.maxLeverage ?? 1,
      onlyIsolated: false,
      markPx: r.markPx,
      midPx: r.markPx,
      prevDayPx: change > -1 ? r.markPx / (1 + change) : 0,
      dayNtlVlm: kHlLowLiquidityDayVolumeUsd,
      category: r.category,
      iconUrl: r.iconUrl,
      unitAssetName: r.unitAssetName,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _MarketCardSlot(
      child: HlMarketCard(market: _market(), onTap: () => _open(context, ref)),
    );
  }

  void _open(BuildContext context, WidgetRef ref) {
    // Re-resolve the full descriptor (order-wire ids, book) from the loaded
    // universe. Keep search OPEN — the detail sheet pushes on the root
    // navigator so it stacks on top and closing it returns here.
    // Resolve THIS row's instrument: the wire id pins the exact market, so
    // a row badged Own never opens the leveraged contract behind the same
    // ticker (and vice versa).
    final market = ref.read(hyperliquidAccountMarketProvider(result.wireCoin));
    final ledgerWalletId = ref.read(searchLedgerWalletIdProvider);
    if (ledgerWalletId != null) {
      // Ledger account search: the Ledger order sheet is the only target
      // (same identity check as the Ledger Investing tab); never the hot
      // slip or the hot Investing tab.
      _trackSearchResultTap(ref, 'hyperliquid_market',
          position: position, target: 'ledger');
      final identity = ref.read(ledgerIdentityProvider(ledgerWalletId));
      if (identity == null || !identity.hasVerifiedEvm) {
        openLedgerInvestingSetup(context, ledgerWalletId);
        return;
      }
      if (market == null) {
        showMessageSnackBar(
            context: context, message: context.l10n.notAvailable, error: true);
        return;
      }
      HlMarketDetailSheet.show(context,
          market: market, ledgerWalletId: ledgerWalletId, source: 'search');
      return;
    }
    _trackSearchResultTap(ref, 'hyperliquid_market', position: position);
    if (market != null) {
      HlMarketDetailSheet.show(context, market: market, source: 'search');
    } else {
      // Universe not loaded yet — fall back to the Trading tab.
      context.go('/hyperliquid');
    }
  }
}

/// Look up the live WS update for an event by its Gamma slug, then by the
/// stable `game:<gameId>` key, then cricket's `eventMetadata.gameId` (the WS
/// slug isn't guaranteed to match Gamma's event slug — mirrors the
/// Predictions screen's lookup).
SportsMatchUpdate? _liveUpdateFor(
  PolymarketEvent e,
  Map<String, SportsMatchUpdate> sportsLive,
) =>
    sportsUpdateFor(sportsLive,
        slug: e.slug, gameId: e.gameId, metadataGameId: e.metadataGameId);

/// One result group: its rows (each built with its analytics position),
/// the filter its "See all" switches to, and the skeleton that holds its
/// place while its remote leg loads.
class _ResultGroup {
  final String key;
  final String label;
  final SearchCategory filter;
  final List<Widget Function(int position)> rows;
  final bool loading;
  final Widget? skeleton;

  const _ResultGroup({
    required this.key,
    required this.label,
    required this.rows,
    required this.filter,
    this.loading = false,
    this.skeleton,
  });
}

/// A market card's place in the results: the lists' 16 side inset and
/// 12 gap, as on the Investing and Predictions tabs.
class _MarketCardSlot extends StatelessWidget {
  final Widget child;
  const _MarketCardSlot({required this.child});

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 12.h),
        child: RepaintBoundary(child: child),
      );
}

/// Two card silhouettes the height of the cards they stand in for (the
/// Investing card's one row, the Predictions list card), so the group's
/// place is kept while its markets load.
class _MarketCardSkeletons extends StatelessWidget {
  final bool investing;
  const _MarketCardSkeletons({required this.investing});

  @override
  Widget build(BuildContext context) {
    if (!investing) {
      return SkeletonCardList(
          count: 2,
          height: 140.h,
          padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 12.h));
    }
    return KuteSkeleton(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 2; i++)
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 12.h),
              child: SkeletonCard(
                height: 72.h,
                radius: AppRadius.lg,
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                child: Row(
                  children: [
                    SkeletonCircle(36.w),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBar(110.w, 14.h),
                          SizedBox(height: 6.h),
                          SkeletonBar(70.w, 12.h),
                        ],
                      ),
                    ),
                    SkeletonBar(64.w, 14.h),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "See all" under a group capped at [kSearchSectionCap]: switches the
/// filter pills to that group, in the Settings rows' words and chevron.
class _SeeAllRow extends StatelessWidget {
  final VoidCallback onTap;
  const _SeeAllRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return BouncyTouch(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        color: Colors.transparent,
        padding: EdgeInsets.fromLTRB(20.w, 6.h, 16.w, 10.h),
        child: Row(
          children: [
            Expanded(
              child: Text(
                context.l10n.seeAll,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: c.textTertiary, size: 20.sp),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String prompt;

  /// Show the animated Sal mascot (the same looping GIF as the home screen)
  /// above the prompt — used for the fresh-open state before the user has
  /// typed anything.
  final bool showMascot;

  /// Sal's opening questions under the prompt (idle with Sal available).
  final List<Widget> chips;

  const _EmptyState(
      {required this.prompt, this.showMascot = false, this.chips = const []});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Keep the idle illustration compact when the keyboard is visible.
    final compact = showMascot && MediaQuery.viewInsetsOf(context).bottom > 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
              horizontal: chips.isEmpty ? 32.w : 20.w, vertical: 8.h),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showMascot)
                  // Sal waiting to be asked something, idling on the rig
                  // rather than looping a GIF that never matched the theme.
                  // Bounded like every other open surface: a sheet left open
                  // settles on a calm frame instead of repainting forever.
                  KuteDogIdle(size: compact ? 72.sp : 120.sp, cycles: 3)
                else
                  Icon(Icons.search_rounded,
                      size: 40.sp, color: c.textTertiary),
                SizedBox(height: showMascot ? (compact ? 12.h : 18.h) : 12.h),
                Text(
                  prompt,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: showMascot ? c.textPrimary : c.textSecondary,
                    fontSize: showMascot ? (compact ? 17.sp : 19.sp) : 15.sp,
                    fontWeight: showMascot ? FontWeight.w700 : FontWeight.w500,
                    letterSpacing: -0.3,
                  ),
                ),
                // Rotating brand-voice taglines — only when there's room (no
                // keyboard); they'd otherwise push the prompts off-screen.
                if (showMascot && !compact) ...[
                  SizedBox(height: 14.h),
                  RotatingTagline(
                    height: 56.h,
                    style: TextStyle(
                      color: c.textTertiary,
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.1,
                      height: 1.4,
                    ),
                  ),
                ],
                if (chips.isNotEmpty) ...[
                  SizedBox(height: 18.h),
                  // The Ask Sal sheet's question rows, in their card.
                  KuteListGroup(children: chips),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A result group's label under the "All" filter: the slips' quiet section
/// label (14sp w600 secondary), at the lists' side inset. No hairline, no
/// capitals.
class _TypeSectionHeader extends StatelessWidget {
  final String label;
  const _TypeSectionHeader({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 10.h),
      child: Semantics(
        header: true,
        child: Text(
          label,
          style: TextStyle(
            color: context.colors.textSecondary,
            fontSize: 14.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
