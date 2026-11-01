// lib/screens/search/unified_search_screen.dart
//
// THE SAL SHEET (founder, 31 October 2026: "it must be and look much
// better"): ONE surface for search AND Sal, opened from the floating pill
// (kute_shell_bar.dart). Typing shows the live results, send asks Sal (the
// chat takes over the body once a conversation is active).
//
// FLAT AND TYPOGRAPHIC (founder, 31 October 2026: the tile idea was "2019
// fintech"): no cards, no boxed input, no hairlines between rows, no
// filter pill row. The sheet stands at 96% of the screen with the KEYBOARD
// DOWN; under the drag handle the COMPOSER LINE is pinned at the top (Sal
// at 28, the text at 20 sp, a hairline under it, the send arrow only with
// text; search_composer.dart) and the content scrolls under it. Blocks
// are a 13 sp w600 title 12 over 56 px rows 14 apart, 28 between blocks;
// titles 16 w500, figures 16 w600 (search_rows.dart). Two variants:
//
//   * HOME (the bar on the Bitcoin or Dollars home): at most three blocks
//     while nothing is typed: "Recent" (the last things opened from
//     search, with Clear; only when there are any), "Moving now" (six of
//     the day's biggest liquid moves in a two-column grid of flat rows;
//     "See all ›" to Investing's Trending), "Trending predictions" (three
//     one-line rows with the chance gauge). Typing cross-fades (150 ms)
//     to the results, Predictions, Investing (with sparklines),
//     Transactions, three per group under All with a "See all" row, and
//     puts the SCOPE CHIP ("All ⌄") at the end of the composer line: it
//     opens a short menu of the four scopes (All · Predictions ·
//     Investing · Transactions) in the app's own sheet. Nothing found is
//     Sal's sad face over one line.
//   * CONTEXT (the bar on a market, position, send or receive screen):
//     the screen's preview row and its action rows (Sal's `share` face
//     leading a row that sends a pick, the share icon in a tinted circle
//     for a link), no scope chip. An [initialQuestion] is sent to Sal as
//     the sheet settles.
//
// THE PILL MORPHS INTO THE COMPOSER (search_morph.dart): the bar hands
// [showKuteSearch] the pill's rect ([KuteSearchMorphSource]) and the pill
// travels to the composer's rect on the sheet spring while the sheet rises
// behind it, and back on close. Blocks stagger in 20 ms apart
// (KuteStaggerIn). Reduce Motion: a plain sheet, no travel.
//
// Local results (transactions + the user's own positions, both under
// Transactions: Predictions and Investing list markets only) come from
// `unifiedSearchResultsProvider` and update instantly. The market groups
// stream in from the debounced remote providers, the named market first,
// with skeleton rows holding their place while they load
// (search_result_order.dart).
//
// Public entrypoint: `showKuteSearch(BuildContext)`. The surface itself is
// `UnifiedSearchSurface`, which a host can also embed (the "+" sheet grows
// into it) by pairing `beginKuteSearchSession` / `endKuteSearchSession`.

import 'package:kute/services/search_recent_store.dart';
import 'package:kute/screens/search/components/search_composer.dart';
import 'package:kute/screens/search/components/search_morph.dart';
import 'package:kute/screens/search/components/search_rows.dart';
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/screens/shared/kute_action_cards.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/kute_share_actions.dart'
    show KuteBarPreview, KuteMarketBarAction, KuteMarketBarContext;
import 'package:kute/screens/shared/kute_dog_scenes.dart' show KuteDogGlance;
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

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
import 'package:kute/screens/shared/kute_back_button.dart' show KuteCloseButton;
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/kute_skeleton.dart'
    show KuteSkeleton, SkeletonBar, SkeletonCircle, SkeletonRowList;
import 'package:kute/screens/shared/kute_motion.dart'
    show
        ArrivalSwitcher,
        KutePressable,
        KuteStaggerIn,
        kuteMotion,
        kuteReduceMotion;
import 'package:kute/theme/kute_motion.dart';
import 'package:kute/screens/search/search_result_order.dart';
import 'package:kute/screens/polymarket/components/live_token_scope.dart';
import 'package:kute/models/hyperliquid_market.dart'
    show HlMarket, kHlLowLiquidityDayVolumeUsd;
import 'package:kute/providers/polymarket_live_prices_provider.dart'
    show livePriceProvider;
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

  /// How the sheet went: `close_button` (the X beside the drag handle),
  /// else `other` (dragged down, back, a result that closed it).
  String closeMethod = 'other';
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
  // straight into the typeahead surface — no mascot / AI intro.
  // Submitting can still ask Sal a general question.
  bool searchFirst = false,
  // Domain-scoped open (user decision: the pool screens search ONLY their
  // own markets): the category is fixed, the filter chips are hidden, and
  // only that category's result leg renders.
  bool lockCategory = false,
  // Pool-scoped set: when non-null, the scope menu offers THESE scopes
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
  // The bar's context (kute_bar_context.dart): its recommended rows and
  // prompts on top of the sheet, the composer scoped to its venue.
  KuteBarContext? barContext,
  // A question sent to Sal the moment the sheet has slid in (an
  // informational screen's "What is this?" bar): the answer streams in
  // through the ordinary advisor path; nothing else is special.
  String? initialQuestion,
  // The floating pill's rect and label (kute_shell_bar.dart): the pill
  // travels to the composer as the sheet rises and back as it drops
  // (search_morph.dart). Null (every other caller, Reduce Motion): a
  // plain sheet.
  KuteSearchMorphSource? morph,
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
  // The shell bar hides while this sheet is up (a hidden bar context),
  // unless its own pill is the one travelling: then the bar keeps its
  // place and draws the pill transparent (kute_shell_bar.dart reads
  // kuteSearchMorphing / kuteSearchSheetOpen), so the pill's return lands
  // exactly where it rests; a hidden context would slide the bar down and
  // back and miss the landing. A context placed in the page's header
  // travels from KuteSalHeaderButton instead and the bar's pill is away
  // already, so the hidden context goes up as for any sheet (or the bar
  // would rise behind the tall sheet with the default pill).
  const hiddenBar = KuteBarContext.hidden();
  final overlay =
      morph == null ? null : Navigator.of(context, rootNavigator: true).overlay;
  final travels = morph != null && overlay != null;
  final keepBar = travels && !(barContext?.inHeader ?? false);
  if (!keepBar) container.read(kuteBarContextProvider.notifier).push(hiddenBar);
  final composerKey = GlobalKey(debugLabel: 'kute-search-composer');
  final hint = context.l10n.searchOrAskSalShort;
  Rect? restRect;
  if (travels) {
    // The way in: from the pill to where the composer will rest, on the
    // same frame the sheet starts to rise.
    restRect = KuteSearchMorph.composerRestRect(overlay.context);
    kuteSearchMorphing.value = true;
    unawaited(KuteSearchMorph.run(
      overlay,
      from: morph.rect,
      to: restRect,
      opening: true,
      label: morph.label,
      hint: hint,
    ).whenComplete(() {
      // Cut short by a close: the way back is already running.
      if (!KuteSearchMorph.running) kuteSearchMorphing.value = false;
    }));
  }
  try {
    kuteSearchSheetOpen.value = true;
    await OpenOnce.run(
        _kSearchSheetKey,
        () => showAppBottomSheet<void>(
              context: context,
              builder: (_) => UnifiedSearchSurface(
                initialCategory: effectiveCategory,
                searchFirst: searchFirst || ledgerMarkets,
                lockCategory: walletId != null || ledgerMarkets || lockCategory,
                scopedTabs:
                    walletId == null && !ledgerMarkets ? scopedTabs : null,
                walletId: walletId,
                searchHint: searchHint,
                barContext: barContext,
                initialQuestion: initialQuestion,
                composerKey: composerKey,
              ),
            ));
  } finally {
    if (travels) {
      // The way back, as the sheet drops: from the composer where it
      // stands (over the keyboard if it is up) to the pill where it rests.
      final from = KuteSearchMorph.rectOf(
              composerKey.currentContext?.findRenderObject(), overlay) ??
          restRect!;
      final to = morph.rectNow?.call() ?? morph.rect;
      kuteSearchMorphing.value = true;
      await KuteSearchMorph.run(
        overlay,
        from: from,
        to: to,
        opening: false,
        label: morph.label,
        hint: hint,
      );
      kuteSearchMorphing.value = false;
    }
    if (!keepBar) {
      container.read(kuteBarContextProvider.notifier).remove(hiddenBar);
    }
    kuteSearchSheetOpen.value = false;
    kuteSearchLoading.value = false;
    endKuteSearchSession(container);
  }
}

const _kSearchSheetKey = 'kute_search';

/// True while the search sheet is up. The dock's "Search or ask Sal" pill
/// shrinks and fades while it is (kute_bottom_action_bar.dart), and
/// springs back when it closes.
final ValueNotifier<bool> kuteSearchSheetOpen = ValueNotifier<bool>(false);

/// True while the open search sheet is reading results for a query. The
/// dock's Sal sweeps faster while it is and is happy for a beat when it
/// turns false again.
final ValueNotifier<bool> kuteSearchLoading = ValueNotifier<bool>(false);

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
    'close_method': stats.closeMethod,
    'time_in_flow_ms': stats.watch.elapsed.inMilliseconds,
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

  /// The bar's context this sheet opened with (kute_bar_context.dart).
  final KuteBarContext? barContext;

  /// Sent to Sal once the sheet has slid in (see [showKuteSearch]).
  final String? initialQuestion;

  /// On the composer, so [showKuteSearch] can read where it stands when
  /// the sheet closes (the pill travels back from there).
  final GlobalKey? composerKey;
  const UnifiedSearchSurface({
    super.key,
    this.initialCategory = SearchCategory.all,
    this.searchFirst = false,
    this.lockCategory = false,
    this.scopedTabs,
    this.walletId,
    this.searchHint,
    this.embedded = false,
    this.barContext,
    this.initialQuestion,
    this.composerKey,
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
  // Whether the field holds text: flipped from the composer's onChanged so
  // the scope chip comes and goes on the first and the last keystroke, not
  // only once a query is published.
  bool _draft = false;
  @override
  void initState() {
    super.initState();
    // Rebuild on focus change so the live type-ahead overlay appears while the
    // composer is focused and hides when the keyboard is dismissed / on send.
    _focusNode.addListener(() {
      if (mounted) setState(() {});
    });
    // The keyboard stays DOWN on open, every variant (founder, 31 October
    // 2026: "still too dense"): the blocks have the screen and the
    // composer waits at the bottom edge until the person taps it. Nothing
    // else runs on open: results, and the live sports feed they use, wait
    // for the first query. The one exception is an [initialQuestion],
    // asked as soon as the sheet has settled (never mid-slide).
    final question = widget.initialQuestion?.trim() ?? '';
    if (question.isNotEmpty) {
      _controller.text = question;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _initialQuestion = Timer(KuteMotion.sheetInDuration, () {
          if (mounted) unawaited(_submit());
        });
      });
    }
  }

  Timer? _initialQuestion;

  /// A sheet opened from the bar on a screen with its own action rows
  /// (kute_bar_context.dart): the market page's preview card and rows take
  /// the top, the filter pills (search scoping) stay out, and the sheet
  /// fits its content while nothing is typed.
  bool get _contextScreen =>
      widget.barContext != null && widget.barContext!.hasRecommendations;

  @override
  void dispose() {
    _initialQuestion?.cancel();
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
    final draft = value.trim().isNotEmpty;
    if (draft != _draft) setState(() => _draft = draft);
    if (!draft) return;
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
        'query_length': query.length,
        'query_length_bucket': _searchLengthBucket(query.length),
        'result_count': _visibleResults,
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
    // Kept in Recent (on the device only).
    unawaited(SearchRecentStore.record(
        SearchRecentEntry(kind: SearchRecentKind.query, id: q, label: q)));
    _focusNode.unfocus();
    final aiEnabled = ref.read(aiEnabledProvider).valueOrNull ?? true;
    if (!mounted) return;
    if (!aiEnabled) {
      // Its length only; the query text never leaves the device.
      _searchStats?.submitted = true;
      TrackingService.track('search_submitted', params: {
        'query_length': q.length,
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
    session.setEntrySource('search');
    session.ask(q,
        input: 'typed', locale: Localizations.localeOf(context).languageCode);
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
    // The person's own positions are history and sit with Transactions;
    // Predictions and Investing list markets only.
    final txSection = showTx &&
        (local.transactions.isNotEmpty || local.ownedPositions.isNotEmpty);
    final predictionSection =
        showPredictions && (globalResults.isNotEmpty || globalLoading);
    final perpetualsSection =
        showPerpetuals && (hlResults.isNotEmpty || hlLoading);

    final hasAnyResult = txSection || predictionSection || perpetualsSection;

    // Result rows grouped by type: Investing, Predictions and Transactions,
    // nothing else. Under the "All" scope all three can appear at once, so
    // each group is a block (its 13 sp title over its rows) and shows its
    // first [kSearchSectionCap] with a "See all" that switches the scope
    // to it. Under a single scope only one group shows, whole and
    // unlabelled (the scope chip already names it).
    //
    // Within Investing the market the person named leads (exact ticker or
    // name, then prefixes, then the rest); within Predictions a game in
    // play leads, then the most traded (search_result_order.dart). The
    // groups themselves always read Predictions, Investing, Transactions,
    // so a group never jumps when the remote results land.
    final sportsLive = ref.read(sportsLiveProvider);
    final rankedHl = rankInvestingResults(query, hlResults);
    final rankedGlobal = rankPredictionResults(
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
      rows: [
        for (final r in rankedGlobal)
          (int p) => _GlobalMarketRow(
              key: ValueKey('poly-${r.event.slug}-${r.event.id}'),
              result: r,
              position: p),
      ],
    );
    // The wallet tag only tells rows apart when they come from more than
    // one wallet; from one wallet it would repeat on every row.
    final showWalletTags =
        local.transactions.map((r) => r.walletName).toSet().length > 1;
    final transactions = _ResultGroup(
      key: 'transactions',
      label: context.l10n.transactions,
      filter: SearchCategory.transactions,
      rows: [
        // The person's own prediction positions first, then the rest.
        for (final r in local.ownedPositions)
          (int p) => _OwnedPositionRow(result: r, position: p),
        for (final r in local.transactions)
          (int p) => _TransactionRow(
              result: r, position: p, showWallet: showWalletTags),
      ],
    );
    // Under All: Predictions, then Investing, then Transactions, always
    // (founder, 2026-10-27); a group with nothing to show is left out.
    final groups = <_ResultGroup>[
      if (predictionSection) predictions,
      if (perpetualsSection) investing,
      if (txSection) transactions,
    ];
    // `pos` numbers the result rows in display order (analytics position
    // on tap); skeletons and "See all" take no number.
    var pos = 0;
    final labelGroups = category == SearchCategory.all;
    final resultChildren = <Widget>[];
    for (final (gi, g) in groups.indexed) {
      final capped = labelGroups && g.rows.length > kSearchSectionCap;
      final shown = capped ? g.rows.take(kSearchSectionCap) : g.rows;
      final rows = [for (final build in shown) build(pos++)];
      final waiting = rows.isEmpty && g.loading;
      // 28 between groups; under All each group is a block (its title
      // over its rows, 14 apart, nothing drawn between them); under one
      // scope the rows alone, whole and unlabelled.
      if (gi > 0) resultChildren.add(SizedBox(height: kSearchBlockGap.h));
      if (labelGroups) {
        resultChildren.add(
            SearchBlockHeader(key: ValueKey('header-${g.key}'), text: g.label));
      }
      resultChildren.add(ArrivalSwitcher(
        key: ValueKey('group-${g.key}'),
        // Skeleton rows hold the group's place until its rows land, then
        // cross-fade into them while the height eases.
        state: waiting ? 'loading' : 'rows',
        child: waiting
            ? const _GroupSkeleton()
            : SearchRowList(
                children: [
                  ...rows,
                  if (capped)
                    _SeeAllRow(onTap: () {
                      TrackingService.searchCategoryChanged(g.filter.name,
                          source: 'see_all');
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
    // The dock's Sal follows (faster while loading, a beat when results
    // land); after the frame, never from inside the build.
    final loadingNow = _resultsLoading && query.isNotEmpty;
    if (kuteSearchLoading.value != loadingNow) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) kuteSearchLoading.value = loadingNow;
      });
    }

    // Warm the HL universe while the Investing result leg can show, so
    // tapping a searched market resolves to the detail sheet
    // (`hyperliquidMarketProvider(coin)` needs the perp/spot lists loaded).
    if (query.isNotEmpty && showPerpetuals) {
      ref.watch(hyperliquidAllMarketsProvider);
    }

    final typing = query.isNotEmpty || hasDraft;

    // Active chat returns above. The remaining content is deterministic
    // search. [bodyKey] names the state the body is in: the home, the
    // results, nothing found, a draft; a change cross-fades over 150 ms.
    final Widget body;
    final String bodyKey;
    final gutters = EdgeInsets.fromLTRB(
        kSearchSheetGutter.w, 12.h, kSearchSheetGutter.w, 16.h);
    if (widget.walletId != null) {
      body = _WalletActivityResults(walletId: widget.walletId!, query: query);
      bodyKey = 'wallet';
    } else if (query.isNotEmpty) {
      if (!hasAnyResult && localAsync.isLoading) {
        body = Padding(padding: gutters, child: const _GroupSkeleton());
        bodyKey = 'loading';
      } else if (!hasAnyResult) {
        body = SearchEmptyState(text: context.l10n.searchNoResultsFor(query));
        bodyKey = 'empty';
      } else {
        body = ListView(
          // Manual (not onDrag) — scrolling the results must NOT dismiss
          // the keyboard out from under the user mid-search.
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
          padding: gutters,
          children: resultChildren,
        );
        bodyKey = 'results';
      }
    } else if (hasDraft) {
      body = SearchEmptyState(text: context.l10n.searchSearching, sad: false);
      bodyKey = 'draft';
    } else {
      // The search home: Recent, Moving now and the trending predictions,
      // scoped by the pills (search_rows.dart). On a context screen it is
      // the screen's preview card and its action rows, sized to them.
      body = _SearchHome(
        category: category,
        barContext: widget.barContext,
        onRecentQuery: (q) {
          _controller.text = q;
          _controller.selection = TextSelection.collapsed(offset: q.length);
          _onChanged(q);
        },
      );
      bodyKey = 'home';
    }
    // The scope chip ("All ⌄") at the end of the composer line, only once
    // there is a query: it narrows the results through a short menu
    // (_showScopeMenu). The empty home has none (founder, 31 October
    // 2026: "still too dense"); a context screen never has one (its rows
    // are not a search). A pool-scoped sheet offers its OWN set even
    // under lockCategory.
    final scopes = widget.scopedTabs ??
        (!widget.lockCategory && !_contextScreen
            ? _ScopeChip.standardScopes(context)
            : null);
    final Widget? scope = typing && scopes != null
        ? _ScopeChip(selected: category, scopes: scopes)
        : null;

    return _buildSheet(
      context,
      children: [
        // The composer line, pinned at the top under the handle: searches
        // while typing, asks Sal on send; the content scrolls under it.
        // Transparent while the pill is travelling to or from it
        // (search_morph.dart): the travelling copy is the one on screen
        // then.
        ValueListenableBuilder<bool>(
          valueListenable: kuteSearchMorphing,
          builder: (context, morphing, child) =>
              Opacity(opacity: morphing ? 0 : 1, child: child),
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: KuteSearchComposer.gutter(context)),
            child: KuteSearchComposer(
              key: widget.composerKey,
              controller: _controller,
              focusNode: _focusNode,
              onChanged: _onChanged,
              onSubmit: _submit,
              aiEnabled: aiEnabled,
              sendLabel: context.l10n.salSendQuestion,
              scope: scope,
              // With Sal available the field names both jobs, the words the
              // pill wears; search-only keeps the scoped hint.
              hint: aiEnabled
                  ? context.l10n.searchOrAskSalShort
                  : (widget.initialCategory == SearchCategory.perpetuals ||
                          widget.initialCategory == SearchCategory.predictions)
                      ? context.l10n.searchMarketsHint
                      : context.l10n.searchYourWallet,
            ),
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: kuteMotion(context, const Duration(milliseconds: 150)),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            layoutBuilder: (current, previous) => Stack(
              fit: StackFit.expand,
              children: [...previous, if (current != null) current],
            ),
            child: KeyedSubtree(key: ValueKey(bodyKey), child: body),
          ),
        ),
        // Sal's disclaimer sits under its answers, once; the search
        // composer carries none. The host of an embedded surface owns the
        // keyboard inset; its content always ends this gap above the
        // sheet's edge.
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
    if (widget.embedded) return Column(children: children);
    // The shared sheet: AppBottomSheetContainer owns the surface, the
    // keyboard (followed frame by frame) and the home-indicator inset.
    // Searching keeps only the drag handle, where the shared header draws
    // it; a conversation wears the shared header with its close X, as the
    // Ask Sal sheet does.
    // The content rises a little and fades in, staggered 80 ms after the
    // sheet starts (its route animation, from a fifth in), on the settle
    // easing; at once under Reduce Motion.
    final route = ModalRoute.of(context);
    Widget entrance(Widget child) {
      final animation = route?.animation;
      if (animation == null || kuteReduceMotion(context)) return child;
      final curved = CurvedAnimation(
          parent: animation,
          curve: const Interval(0.2, 1.0, curve: KuteMotion.settle));
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position:
              Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero)
                  .animate(curved),
          child: child,
        ),
      );
    }

    return AppBottomSheetContainer(
      maxHeight: kSearchSheetFraction,
      followKeyboard: true,
      child: Column(
        children: [
          if (chat)
            AppBottomSheetHeader(
              title: context.l10n.salChatWith,
              trailing: const AppBottomSheetCloseButton(),
            )
          else
            // The drag handle with the shared close X at the row's end
            // (founder, 27 October 2026: a way out besides dragging down).
            // The same circled X the bet and order slips wear
            // (KuteCloseButton; founder, 28 October 2026).
            SizedBox(
              height: kSearchSheetHandleRow.h,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    top: 12.h,
                    child: AppDecorations.dragHandle(context),
                  ),
                  Positioned(
                    right: 16.w,
                    top: 6.h,
                    child: KuteCloseButton(onPressed: () {
                      // Named on search_closed; the pop is the button's own.
                      _searchStats?.closeMethod = 'close_button';
                      Navigator.of(context).pop();
                    }),
                  ),
                ],
              ),
            ),
          Expanded(child: entrance(Column(children: children))),
        ],
      ),
    );
  }
}

/// The scope chip at the end of the composer line while a query is typed:
/// the selected scope's name and a ⌄ ("All ⌄"), 13 w500 on a small
/// surfaceLight pill. Tapped, it opens a short menu of the scopes (All ·
/// Predictions · Investing · Transactions) in the app's own sheet
/// ([_showScopeMenu]); picking one writes [selectedSearchCategoryProvider],
/// which the sheet's `showTx` / `showPredictions` / `showPerpetuals`
/// visibility already reads to narrow the result groups.
class _ScopeChip extends StatelessWidget {
  const _ScopeChip({required this.selected, required this.scopes});

  final SearchCategory selected;

  /// The scopes on offer; a pool-scoped sheet passes its own set.
  final List<(SearchCategory, String)> scopes;

  static const chipKey = ValueKey('search-scope-chip');

  /// The global set, in All's section order: Predictions, Investing,
  /// Transactions. The Hyperliquid leg keeps its `perpetuals` category key
  /// (analytics stay stable) but reads Investing.
  static List<(SearchCategory, String)> standardScopes(BuildContext context) =>
      [
        (SearchCategory.all, context.l10n.searchFilterAll),
        (SearchCategory.predictions, context.l10n.predictions),
        (SearchCategory.perpetuals, context.l10n.trading),
        (SearchCategory.transactions, context.l10n.transactions),
      ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = scopes.where((s) => s.$1 == selected).firstOrNull?.$2 ??
        scopes.first.$2;
    return Semantics(
      button: true,
      label: label,
      child: KutePressable(
        child: GestureDetector(
          key: chipKey,
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            // ignore: discarded_futures
            _showScopeMenu(context, scopes: scopes, selected: selected);
          },
          child: Container(
            height: 28,
            padding: EdgeInsets.only(left: 10.w, right: 6.w),
            decoration: BoxDecoration(
              color: c.surfaceLight,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.2,
                  ),
                ),
                Icon(Icons.expand_more_rounded,
                    size: 16, color: c.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The scope menu: the app's sheet (the unit picker's chrome) with one row
/// per scope, the selected one checked; picking one closes it and narrows
/// the results. The same `search_category_changed` event as the old pills.
Future<void> _showScopeMenu(
  BuildContext context, {
  required List<(SearchCategory, String)> scopes,
  required SearchCategory selected,
}) {
  final container = ProviderScope.containerOf(context, listen: false);
  return showAppBottomSheet<void>(
    context: context,
    builder: (sheetContext) => AppBottomSheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBottomSheetHeader(title: sheetContext.l10n.searchScopeTitle),
          SizedBox(height: 8.h),
          for (final (category, label) in scopes)
            AppBottomSheetListTile(
              title: label,
              isSelected: category == selected,
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.of(sheetContext).pop();
                if (category != selected) {
                  TrackingService.searchCategoryChanged(category.name);
                }
                container.read(selectedSearchCategoryProvider.notifier).state =
                    category;
              },
            ),
          SizedBox(height: 16.h),
        ],
      ),
    ),
  );
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
      return SearchEmptyState(
          text: q.isEmpty
              ? context.l10n.ledgerActivityEmpty
              : context.l10n.searchNoMatchingActivity,
          sad: q.isNotEmpty);
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
/// Polymarket / USDB) matches the rest of the app exactly, and, when the
/// results span more than one wallet, tags each row with the OWNING
/// WALLET's name so it is clear which wallet a tx belongs to.
///
/// The canonical builder doesn't show the wallet, so we render a small
/// wallet-name pill under it. Tapping does NOT pop the search sheet: the
/// detail surface is dispatched directly so it stacks ON TOP of the
/// still-open search, and closing it returns the user to the search.
class _TransactionRow extends ConsumerWidget {
  final TransactionSearchResult result;
  final int? position;

  /// Whether the owning wallet's tag shows: only when the results span
  /// more than one wallet.
  final bool showWallet;
  const _TransactionRow(
      {required this.result, this.position, this.showWallet = true});

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
          if (showWallet && walletName.isNotEmpty)
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
                fontWeight: FontWeight.w500,
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

/// One of the user's own positions that matches the query, in the sheet's
/// row ([SearchPositionRow]): the market's picture and question, the
/// position in one line, its value with the profit or loss under it,
/// following the held outcome's live price. Tapping keeps search's
/// destination: the market's detail sheet.
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
    return LiveTokenScope(
      tokens: [if (!p.isResolved && p.tokenId != null) p.tokenId!],
      child: SearchPositionRow(
        position: p,
        price: price,
        onTap: () {
          _trackSearchResultTap(ref, 'owned_position', position: position);
          _openMarket(context, ref, p);
        },
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

/// A Polymarket market from the remote search, in the sheet's row
/// ([SearchPredictionRow]): the picture, the question, the leading
/// chance. Search stays open — the market detail stacks on top (root
/// navigator) and closing it returns to the results.
class _GlobalMarketRow extends ConsumerWidget {
  final GlobalMarketSearchResult result;
  final int? position;
  const _GlobalMarketRow({super.key, required this.result, this.position});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = result.event;
    return SearchPredictionRow(
      event: e,
      onTap: () {
        // A Ledger account search opens the market on that wallet's
        // Ledger bet target (MarketDetailSheet forwards ledgerWalletId).
        final ledgerWalletId = ref.read(searchLedgerWalletIdProvider);
        _trackSearchResultTap(ref, 'global_market',
            position: position,
            target: ledgerWalletId != null ? 'ledger' : null);
        // ignore: discarded_futures
        SearchRecentStore.record(SearchRecentEntry(
            kind: SearchRecentKind.prediction,
            id: e.slug,
            label: e.title,
            image: e.imageUrl));
        MarketDetailSheet.show(context,
            event: e, ledgerWalletId: ledgerWalletId, source: 'search');
      },
    );
  }
}

/// An Investing market from [globalHyperliquidResultsProvider], in the
/// sheet's row ([SearchInvestingRow]): the logo, the name over its ticker,
/// the price over the day's change. Tapping re-resolves the full
/// [HlMarket] and opens the Investing detail sheet on the root navigator
/// (so it stacks ON TOP of search); if the universe hasn't loaded yet it
/// falls back to the Investing tab.
class _HlMarketRow extends ConsumerWidget {
  final HlMarketSearchResult result;
  final int? position;
  const _HlMarketRow({super.key, required this.result, this.position});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      SearchInvestingRow(result: result, onTap: () => _open(context, ref));

  void _open(BuildContext context, WidgetRef ref) {
    // Re-resolve the full descriptor (order-wire ids, book) from the loaded
    // universe. Keep search OPEN — the detail sheet pushes on the root
    // navigator so it stacks on top and closing it returns here.
    // Resolve THIS row's instrument: the wire id pins the exact market, so
    // a row badged Own never opens the leveraged contract behind the same
    // ticker (and vice versa).
    final market = ref.read(hyperliquidExactMarketProvider(
            '${result.kind.name}:${result.wireCoin}')) ??
        result.market;
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
    // ignore: discarded_futures
    SearchRecentStore.record(SearchRecentEntry(
        kind: SearchRecentKind.investing,
        id: result.coin,
        label: result.coin,
        image: result.iconUrl));
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
/// the filter its "See all" switches to, and whether its remote leg is
/// still loading (skeleton rows hold its place then).
class _ResultGroup {
  final String key;
  final String label;
  final SearchCategory filter;
  final List<Widget Function(int position)> rows;
  final bool loading;

  const _ResultGroup({
    required this.key,
    required this.label,
    required this.rows,
    required this.filter,
    this.loading = false,
  });
}

/// Three skeleton rows, flat and 14 apart like the rows they stand in
/// for: a group's place while its markets load, and the whole body's
/// while the first local results are read.
class _GroupSkeleton extends StatelessWidget {
  const _GroupSkeleton();

  @override
  Widget build(BuildContext context) {
    return KuteSkeleton(
      child: SearchRowList(
        children: [
          for (var i = 0; i < 3; i++)
            SizedBox(
              height: kSearchRowHeight,
              child: Row(
                children: [
                  const SkeletonCircle(kSearchRowLogo),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      // Unscaled heights: the row is a fixed 56.
                      children: [
                        SkeletonBar(160.w, 14),
                        const SizedBox(height: 6),
                        SkeletonBar(90.w, 12),
                      ],
                    ),
                  ),
                  SkeletonBar(56.w, 14),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// "See all" as a group's last row when it is capped at
/// [kSearchSectionCap]: switches the scope to that group.
class _SeeAllRow extends StatelessWidget {
  final VoidCallback onTap;
  const _SeeAllRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: context.l10n.seeAll,
      child: KutePressable(
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Container(
            constraints: const BoxConstraints(minHeight: kSearchRowHeight),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.seeAll,
                    style: SearchListRow.titleStyle(context),
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: c.textTertiary, size: 20.sp),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The search home (founder, 31 October 2026; flat): at most three blocks
/// on the sheet's surface, 28 apart, each a 13 sp w600 title 12 over its
/// rows (search_rows.dart), rising in 20 ms apart (KuteStaggerIn):
///
///   1. "Recent" (the last things opened from search, SearchRecentStore;
///      only when there are any): 56 px rows with the logo or a magnifier,
///      the name, its ✕; "Clear" at the title's end.
///   2. "Moving now": six of the day's largest moves among the loaded
///      liquid Investing markets, a two-column grid of flat rows (the
///      ticker, the move); "See all ›" opens Investing on Trending.
///   3. "Trending predictions": three one-line rows from the loaded
///      trending feed, the chance gauge and the chance at the right.
///
/// No Investing block here (it is a results group) and no prompt chips:
/// the composer is the way to Sal. On a context screen (the bar on a
/// market page) it is the screen's preview row and its action rows
/// instead.
class _SearchHome extends ConsumerWidget {
  const _SearchHome(
      {required this.category, required this.onRecentQuery, this.barContext});

  final SearchCategory category;

  /// A recent query tapped: back into the field, searched again.
  final ValueChanged<String> onRecentQuery;

  /// The bar's context: with action rows, the context screen in place of
  /// the home's blocks.
  final KuteBarContext? barContext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final showInvesting =
        category == SearchCategory.all || category == SearchCategory.perpetuals;
    final showPredictions = category == SearchCategory.all ||
        category == SearchCategory.predictions;
    final gutters = EdgeInsets.fromLTRB(
        kSearchSheetGutter.w, 12.h, kSearchSheetGutter.w, 16.h);
    final gap = SizedBox(height: kSearchBlockGap.h);

    final ctx = barContext;
    if (ctx != null && ctx.hasRecommendations) {
      // The context screen: the preview row, then the action rows.
      final preview = ctx is KuteMarketBarContext ? ctx.preview : null;
      var block = 0;
      return ListView(
        padding: gutters,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          if (preview != null) ...[
            KuteStaggerIn(
                index: block++, child: _ContextPreviewRow(preview: preview)),
            gap,
          ],
          KuteStaggerIn(
              index: block++,
              child:
                  _ContextActionCards(actions: ctx.actions, preview: preview)),
        ],
      );
    }

    // Moving now: the biggest moves, liquid markets only.
    final universe =
        ref.watch(hyperliquidBrowseUniverseProvider).valueOrNull ?? const [];
    final movers = [
      for (final m in universe)
        if (m.prevDayPx > 0 &&
            m.markPx > 0 &&
            m.dayNtlVlm >= kHlLowLiquidityDayVolumeUsd)
          m,
    ]..sort((a, b) => (b.markPx / b.prevDayPx - 1)
        .abs()
        .compareTo((a.markPx / a.prevDayPx - 1).abs()));
    final moving = showInvesting
        ? movers.take(SearchMoverGrid.count).toList()
        : const <HlMarket>[];

    // Trending predictions: the trending feed as it is loaded. While it
    // is still on its way (a cold start) the block stands with skeleton
    // rows and the rows land in place: it never vanishes (founder, 31
    // October 2026, the sheet showing Moving now alone).
    final trendingFeed = showPredictions
        ? ref.watch(polyBrowseFeedProvider(
            const PolyFeedQuery(pill: PolyPill.trending)))
        : null;
    final trending =
        trendingFeed?.events.take(3).toList() ?? const <PolymarketEvent>[];
    final trendingLoading =
        trendingFeed != null && trending.isEmpty && trendingFeed.loading;

    // ignore: discarded_futures
    SearchRecentStore.load();

    // The blocks, in order, each with its stagger index; 28 between them.
    Widget block(int index, String header, Widget rows, {Widget? trailing}) =>
        KuteStaggerIn(
          index: index,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SearchBlockHeader(text: header, trailing: trailing),
              rows,
            ],
          ),
        );

    return ListView(
      padding: gutters,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        ValueListenableBuilder<List<SearchRecentEntry>>(
          valueListenable: SearchRecentStore.entries,
          builder: (context, recent, _) => recent.isEmpty
              ? const SizedBox.shrink()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    block(
                      0,
                      l10n.searchHomeRecent,
                      SearchRowList(
                        key: const ValueKey('search-home-recent'),
                        children: [
                          for (final e in recent)
                            _RecentRow(
                                entry: e,
                                onQuery: onRecentQuery,
                                universe: universe),
                        ],
                      ),
                      trailing: SearchBlockAction(
                        label: l10n.searchHomeClear,
                        onTap: () {
                          // ignore: discarded_futures
                          SearchRecentStore.clear();
                        },
                      ),
                    ),
                    if (moving.isNotEmpty ||
                        trending.isNotEmpty ||
                        trendingLoading)
                      gap,
                  ],
                ),
        ),
        if (moving.isNotEmpty) ...[
          block(
            1,
            l10n.searchHomeMovingNow,
            SearchMoverGrid(
              key: const ValueKey('search-home-moving'),
              markets: moving,
              onTap: (m) => HlMarketDetailSheet.show(context,
                  market: m, source: 'search'),
            ),
            trailing: SearchBlockAction(
              label: l10n.seeAll,
              chevron: true,
              onTap: () => _openInvestingTrending(context, ref),
            ),
          ),
          if (trending.isNotEmpty || trendingLoading) gap,
        ],
        if (trendingLoading)
          block(
            2,
            l10n.searchHomeTrendingPredictions,
            SkeletonRowList(
              key: const ValueKey('search-home-trending-loading'),
              count: 3,
              padding: EdgeInsets.zero,
            ),
          )
        else if (trending.isNotEmpty)
          block(
            2,
            l10n.searchHomeTrendingPredictions,
            SearchRowList(
              key: const ValueKey('search-home-trending'),
              children: [
                for (final e in trending)
                  SearchPredictionRow(
                    event: e,
                    titleLines: 1,
                    onTap: () => MarketDetailSheet.show(context,
                        event: e,
                        ledgerWalletId: ref.read(searchLedgerWalletIdProvider),
                        source: 'search'),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  /// "See all ›" on Moving now: the sheet closes and Investing opens on
  /// its Trending category.
  void _openInvestingTrending(BuildContext context, WidgetRef ref) {
    ref
        .read(hlBrowseSelectionProvider.notifier)
        .update((s) => s.copyWith(tab: HlBrowseTab.trending));
    final router = GoRouter.maybeOf(context);
    Navigator.of(context).maybePop();
    router?.go('/hyperliquid');
  }
}

/// A Recent row: the logo (a coin's, an event's, a magnifier for a query)
/// at 36, the name, and its ✕. Tapped: the market, the event (read by its
/// slug), or the query back in the field.
class _RecentRow extends ConsumerWidget {
  const _RecentRow(
      {required this.entry, required this.onQuery, required this.universe});

  final SearchRecentEntry entry;
  final ValueChanged<String> onQuery;
  final List<HlMarket> universe;

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    switch (entry.kind) {
      case SearchRecentKind.query:
        onQuery(entry.id);
      case SearchRecentKind.investing:
        final market = universe.where((m) => m.coin == entry.id).firstOrNull;
        if (market != null) {
          HlMarketDetailSheet.show(context, market: market, source: 'search');
        }
      case SearchRecentKind.prediction:
        PolymarketEvent? event;
        try {
          event =
              await ref.read(polymarketEventDetailsProvider(entry.id).future);
        } catch (_) {
          event = null;
        }
        if (event != null && context.mounted) {
          MarketDetailSheet.show(context,
              event: event,
              ledgerWalletId: ref.read(searchLedgerWalletIdProvider),
              source: 'search');
        }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final image = entry.image;
    final Widget logo = switch (entry.kind) {
      SearchRecentKind.query =>
        Icon(Icons.search_rounded, size: 22, color: c.textTertiary),
      SearchRecentKind.investing =>
        HlCoinIcon(coin: entry.id, iconUrl: image, size: kSearchRowLogo),
      SearchRecentKind.prediction => searchEventLogo(context, image),
    };
    return SearchListRow(
      leading: logo,
      title: entry.label,
      titleLines: 1,
      semanticLabel: entry.label,
      // A 40 target inside the row's 56, not Material's 48 with its own
      // padding, which would stretch the row.
      trailing: IconButton(
        tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
        iconSize: 20,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        style: IconButton.styleFrom(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        icon: Icon(Icons.close_rounded, color: c.textTertiary),
        onPressed: () {
          HapticFeedback.selectionClick();
          // ignore: discarded_futures
          SearchRecentStore.remove(entry);
        },
      ),
      onTap: () => _open(context, ref),
    );
  }
}

/// The widest the context preview's trailing figure or pick may be.
const double kContextPreviewFigureWidth = 112;

/// The market's picture, drawn exactly as its page header draws it: an
/// Investing market's logo through HlCoinIcon (the wire coin a
/// builder-dex market trades under, its category and logo URL, the same
/// fallbacks), a prediction's event image.
Widget contextPreviewLogo(BuildContext context, KuteBarPreview preview,
    {double size = kSearchRowLogo}) {
  final coin = preview.coin;
  if (coin != null && coin.isNotEmpty) {
    return HlCoinIcon(
      coin: coin,
      wireCoin: preview.wireCoin ?? coin,
      category: preview.coinCategory,
      iconUrl: preview.coinIconUrl,
      size: size,
    );
  }
  return searchEventLogo(context, preview.imageUrl, size: size);
}

/// The context screen's preview row, flat: the market's picture (36), its
/// name on up to two lines (an Investing market's ticker under its display
/// name) and the pick or the price at the end, in the sheet's row scale.
class _ContextPreviewRow extends StatelessWidget {
  const _ContextPreviewRow({required this.preview});

  final KuteBarPreview preview;

  @override
  Widget build(BuildContext context) {
    final line = preview.line;
    final subtitle = preview.subtitle;
    return Container(
      key: const ValueKey('context-preview-card'),
      constraints: const BoxConstraints(minHeight: kSearchRowHeight),
      child: Row(
        children: [
          contextPreviewLogo(context, preview),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  preview.title,
                  key: const ValueKey('context-preview-title'),
                  maxLines: subtitle == null ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: SearchListRow.titleStyle(context),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    key: const ValueKey('context-preview-subtitle'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SearchListRow.subtitleStyle(context),
                  ),
              ],
            ),
          ),
          // The figure or the pick at a fixed width at most, one line: a
          // long candidate ("Gen.G Esports 47%") overflowed the row by
          // 96 px; the title gives way first, then the figure ellipsises.
          if (line != null && line.isNotEmpty) ...[
            SizedBox(width: 12.w),
            ConstrainedBox(
              key: const ValueKey('context-preview-figure'),
              constraints:
                  BoxConstraints(maxWidth: kContextPreviewFigureWidth.w),
              child: Text(
                line,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: SearchListRow.figureStyle(context),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// THE CONTEXT SCREEN'S SEND ACTIONS AS CARDS (founder, 1 November 2026):
/// the shared big-square cards (kute_action_cards.dart): two actions side
/// by side as two equal cards, 12 apart; one action, one full-width card;
/// three (an open position's brag row) three across where they fit, else
/// two over one.
class _ContextActionCards extends StatelessWidget {
  const _ContextActionCards({required this.actions, this.preview});

  final List<KuteBarAction> actions;
  final KuteBarPreview? preview;

  @override
  Widget build(BuildContext context) => KuteActionCardGrid(
        key: const ValueKey('context-actions-card'),
        cards: [
          for (final a in actions) _contextActionCard(context, a, preview),
        ],
      );
}

/// The height of a send card's visual box: Sal's `share` face at 56.
const double kContextCardVisualSlot = 56;

/// One send card: a large visual at the top (the market's logo at 40 with
/// a small share badge for the market's link; Sal's `share` face at 56 for
/// a card that sends a pick), the title (16, w600), two lines under it
/// (13, textSecondary) and, at the foot, what is sent (13, w600,
/// textPrimary): the market's name for the link, the pick ("Gen.G · 47%")
/// for the pick. The press spring; a tap runs the action and the sheet
/// closes.
KuteActionCard _contextActionCard(
    BuildContext context, KuteBarAction a, KuteBarPreview? p) {
  final c = context.colors;
  final isLight = Theme.of(context).brightness == Brightness.light;
  final clip = a is KuteMarketBarAction ? a.salClip : null;
  final icon = a is KuteMarketBarAction
      ? (a.icon ?? Icons.arrow_forward_rounded)
      : Icons.arrow_forward_rounded;
  final Widget visual;
  if (clip != null) {
    visual = SalSprite(
      clip: clip,
      size: 56,
      fallback: SalSprite(
          clip: 'happy',
          size: 56,
          fallback: KuteDogGlance(size: 48, color: c.accent)),
    );
  } else if (p != null) {
    // The market's logo with a small share badge on its corner.
    visual = SizedBox(
      width: 52,
      height: 56,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
              left: 0, top: 8, child: contextPreviewLogo(context, p, size: 40)),
          Positioned(
            left: 26,
            top: 34,
            child: Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.textPrimary,
                shape: BoxShape.circle,
                border: Border.all(
                    color: isLight ? Colors.white : c.surface, width: 2),
              ),
              child: Icon(icon,
                  size: 12, color: isLight ? Colors.white : c.background),
            ),
          ),
        ],
      ),
    );
  } else {
    visual = Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.accent.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 22, color: c.accent),
    );
  }
  // What is sent: the pick on a card that sends it, else the market.
  final sent = clip != null ? p?.line : p?.title;
  return KuteActionCard(
    key: ValueKey('context-action-card-${a.label}'),
    visual: visual,
    visualSlot: kContextCardVisualSlot,
    title: a.label,
    subtitle: a.sublabel,
    footer: sent,
    footerKey: ValueKey('context-action-sent-${a.label}'),
    onTap: () {
      a.onTap(context);
      Navigator.of(context).maybePop();
    },
  );
}
