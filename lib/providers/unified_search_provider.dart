// lib/providers/unified_search_provider.dart
//
// Backing state for the unified "Search kute" surface. Searches three
// sections at once, the ones the All filter shows:
//
//   1. TRANSACTIONS — local + synchronous. Iterates the per-wallet
//      `walletTransactionCacheProvider` (keyed by walletId) so each
//      matched row keeps its owning wallet's display label, filters by a
//      per-row lowercased searchable string (id, asset, direction,
//      amounts, and type-specific text), then sorts the cross-wallet
//      matches newest-first. Instant, never hits the network.
//
//   2. PREDICTIONS — the user's OWN positions (active + resolved +
//      claimable, local + synchronous, de-duped by conditionId) PLUS
//      global markets from the remote, debounced `polymarketSearchProvider`.
//
//   3. INVESTING — Hyperliquid markets from the remote, debounced
//      `hyperliquidMarketSearchProvider`.
//
// The query lives in `searchQueryProvider`. The synchronous results
// (transactions + owned positions) are computed in
// `unifiedSearchResultsProvider`; the global-market leg is folded in by
// the UI watching `globalMarketResultsProvider`, which wraps the
// debounced remote `polymarketSearchProvider`. Keeping the heavy local
// work in cancellable batches keeps typing responsive without waiting on
// public-market requests.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/helpers/search_debounce.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/models/settings_model.dart' show WalletConfig;
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/hyperliquid_search_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart'
    show sportsLiveProvider, sportsUpdateFor, SportsMatchUpdate;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/transactions_provider.dart';

/// Sealed union of everything the unified search can surface. The UI
/// switches on the concrete subtype to render the row and to dispatch
/// the tap.
sealed class SearchResult {
  const SearchResult();
}

/// A matched wallet transaction. Tapping opens the per-type detail sheet
/// via `openTransactionDetails`. [walletName] is the owning wallet's
/// display label (e.g. "Spending", "Ledger", a custom wallet name) so the
/// result row can show which wallet the tx belongs to — search spans every
/// wallet, so the row would otherwise be ambiguous.
class TransactionSearchResult extends SearchResult {
  final BaseTransaction transaction;
  final String walletName;
  const TransactionSearchResult(this.transaction, {this.walletName = ''});
}

/// One of the user's OWN Polymarket positions (active / resolved /
/// claimable). Tapping resolves the market by slug and opens its detail
/// sheet, falling back to the predictions tab.
class OwnedPositionSearchResult extends SearchResult {
  final PolymarketPosition position;
  const OwnedPositionSearchResult(this.position);
}

/// A global Polymarket market from the remote Gamma search. Tapping
/// opens `MarketDetailSheet.show(event:)`.
class GlobalMarketSearchResult extends SearchResult {
  final PolymarketEvent event;
  const GlobalMarketSearchResult(this.event);
}

/// Grouped synchronous results — everything except the remote
/// global-market leg, which streams in separately via
/// [globalMarketResultsProvider].
class UnifiedSearchResults {
  final List<TransactionSearchResult> transactions;
  final List<OwnedPositionSearchResult> ownedPositions;

  const UnifiedSearchResults({
    required this.transactions,
    required this.ownedPositions,
  });

  static const empty = UnifiedSearchResults(
    transactions: [],
    ownedPositions: [],
  );
}

/// The live search query. Driven by the search field's `onChanged`.
final searchQueryProvider = StateProvider<String>((ref) => '');

/// A wallet detail sheet searches its own history and must never offer actions
/// against the spending wallet. Null retains the cross-wallet Home search.
final searchWalletScopeProvider = StateProvider<String?>((ref) => null);

/// A Ledger account's market search: results open on that wallet's Ledger
/// Predictions / Investing targets, never the hot wallet. Null means the
/// hot routes. Separate from [searchWalletScopeProvider], which is the
/// transactions-only scope and disables the market legs.
final searchLedgerWalletIdProvider = StateProvider<String?>((ref) => null);

/// Product search browses public markets; account holdings live in Portfolio.
final searchMarketsOnlyProvider = StateProvider<bool>((ref) => false);

/// The category-filter chip selected at the top of the search sheet.
/// `all` shows every section grouped; the others narrow results to a
/// single section. Held in a [StateProvider] so the chip row and the
/// results list share one source of truth. [perpetuals] narrows to the
/// Hyperliquid markets leg ([globalHyperliquidResultsProvider]).
enum SearchCategory {
  all,
  transactions,
  predictions,
  perpetuals,
}

/// Currently-selected filter chip. Reset to [SearchCategory.all] each
/// time the sheet opens (done in the sheet's initState alongside the
/// query reset).
final selectedSearchCategoryProvider =
    StateProvider<SearchCategory>((ref) => SearchCategory.all);

/// Per-subsection caps so a broad query ("a") can't dump hundreds of
/// rows into one section.
const int _kMaxTransactionResults = 25;
const int _kMaxOwnedPositionResults = 5;
const int kMaxGlobalMarketResults = 5;
const int kMaxHyperliquidResults = 6;

/// Short, user-facing label for a wallet, attached to each transaction
/// result row so the user can tell which wallet a tx belongs to (search
/// spans every wallet). Prefers the wallet's own `name`; falls back to a
/// type label ("Spending" / "Hardware" / "Watch-only") when the name is
/// blank.
String _walletLabel(WalletConfig? w) {
  if (w == null) return '';
  final name = w.name.trim();
  if (name.isNotEmpty) return name;
  if (w.isHardware) return 'Hardware';
  if (w.isWatchOnly) return 'Watch-only';
  if (w.isExternalAddress) return 'Address';
  if (w.sparkEnabled) return 'Spending';
  return 'Wallet';
}

/// Lowercased, searchable text for a single transaction row. Built from
/// the identity + user-visible fields plus per-type detail text. NEVER
/// touches `PolymarketTransaction.activityType` — that getter parses the
/// raw type string into a bundled SDK enum and THROWS on unknown values
/// (e.g. Polymarket's "YIELD"), which would blow up the whole filter.
/// We read the raw `activity.type` string and the explicit `side` field
/// instead.
/// Extra search words for an asset code, so a natural query ("bitcoin",
/// "dollar") hits a row stored under the short code ("btc", "usdc").
List<String> _assetSynonyms(String asset) {
  switch (asset.toLowerCase()) {
    case 'btc':
      return const ['bitcoin', 'sats', 'sat'];
    case 'usdc':
      return const ['usd coin', 'dollar', 'stablecoin'];
    case 'usdt':
      return const ['tether', 'dollar', 'stablecoin'];
    default:
      return const [];
  }
}

/// True for swap / on-ramp rows that haven't settled yet — the noisy
/// pending (₿0 / from ₿0) rows, legacy swap orders included, the user
/// doesn't want cluttering search. Native Bitcoin / Lightning / prediction activity is
/// NOT filtered (a pending receive is still legitimately findable).
bool _isPendingSwap(BaseTransaction tx) {
  if (tx is SwapOrderTransaction) return !tx.isComplete;
  if (tx is OutlogicTransaction) return tx.isPending;
  return false;
}

/// Public alias so the search sheet's pool-scoped Activity tab filters
/// past rows with EXACTLY the same haystack the Transactions leg uses.
String transactionSearchableText(BaseTransaction tx) => _searchableText(tx);

String _searchableText(BaseTransaction tx) {
  final parts = <String>[
    tx.id,
    tx.asset,
    tx.type == TransactionType.sent ? 'sent' : 'received',
    tx.amount.toString(),
    // Asset synonyms so a full-word query ("bitcoin", "lightning", "dollar")
    // matches a row whose asset code is the short form ("btc", "usdc").
    ..._assetSynonyms(tx.asset),
  ];

  if (tx is SparkTransaction) {
    // Lightning / on-chain (Spark) payments: searchable by rail name AND by
    // the invoice description / LNURL comment.
    parts.add(tx.sparkType.name); // 'lightning' | 'bitcoin' | 'spark'
    if (tx.sparkType == SparkTransactionType.bitcoin) {
      parts.add('onchain on-chain');
    }
    parts.add(tx.searchableDetail);
  } else if (tx is PolymarketTransaction) {
    final a = tx.activity;
    parts.addAll([
      a.title ?? '',
      a.outcome ?? '',
      a.slug ?? '',
      a.eventSlug ?? '',
      a.side ?? '',
      a.type, // raw string — safe (unlike the `activityType` enum)
      a.transactionHash,
    ]);
  } else if (tx is SwapOrderTransaction) {
    final d = tx.details;
    parts.addAll([
      d.coinTo,
      d.coinFrom,
      d.networkTo,
      d.networkFrom,
      d.status,
    ]);
  } else if (tx is OutlogicTransaction) {
    final d = tx.details;
    parts.addAll([
      d.fromAsset,
      d.toAsset,
      d.status,
    ]);
  } else if (tx is PolymarketUsdcReceive) {
    parts.add(tx.fromAddress);
  } else if (tx is BitcoinTransaction) {
    parts.add(tx.receivedSats.toString());
    parts.add(tx.sentSats.toString());
  } else if (tx is MempoolAddressTransaction) {
    parts.add(tx.details.txid);
  }

  return parts.join(' ').toLowerCase();
}

/// Lowercased searchable text for one of the user's positions.
String _positionSearchableText(PolymarketPosition p) {
  return [
    p.marketQuestion,
    p.outcome,
    p.eventSlug ?? '',
    p.marketId,
    p.tokenId ?? '',
  ].join(' ').toLowerCase();
}

/// Local search yields between small batches and cancels superseded queries.
/// Private history stays on-device and never enters the public market legs.
final unifiedSearchResultsProvider = FutureProvider.autoDispose<UnifiedSearchResults>((ref) async {
  if (ref.watch(searchMarketsOnlyProvider)) return UnifiedSearchResults.empty;
  var disposed = false;
  ref.onDispose(() => disposed = true);
  final query = ref.watch(searchQueryProvider).trim().toLowerCase();
  if (query.isEmpty) return UnifiedSearchResults.empty;
  final category = ref.watch(selectedSearchCategoryProvider);
  final searchTransactions = category == SearchCategory.all ||
      category == SearchCategory.transactions;
  final walletScope = ref.watch(searchWalletScopeProvider);
  final searchPredictions = walletScope == null &&
      (category == SearchCategory.all || category == SearchCategory.predictions);
  if (!searchTransactions && !searchPredictions) {
    return UnifiedSearchResults.empty;
  }

  // 1. TRANSACTIONS — iterate the per-wallet cache (keyed by walletId)
  // rather than the flattened merged feed so each matched row keeps its
  // owning walletId, which we resolve to a display label. Results are
  // collected across every wallet then sorted newest-first to match the
  // merged feed's ordering, and capped.
  final cache = searchTransactions
      ? ref.watch(walletTransactionCacheProvider)
      : <String, Transaction>{};
  final wallets = searchTransactions
      ? ref.watch(settingsProvider.select((s) => s.wallets))
      : const <WalletConfig>[];
  final walletById = <String, WalletConfig>{
    for (final w in wallets) w.id: w,
  };
  final matched = <(BaseTransaction, String)>[];
  final positionSources = <PolymarketPosition>[
    if (searchPredictions) ...[
      ...ref.watch(polymarketActivePositionsProvider),
      ...ref.watch(polymarketClaimablePositionsProvider),
      ...ref.watch(polymarketResolvedPositionsProvider),
    ],
  ];
  for (final entry in cache.entries) {
    if (walletScope != null && entry.key != walletScope) continue;
    final label = _walletLabel(walletById[entry.key]);
    final rows = await searchInBatches(
      entry.value.allTransactionsSorted,
      matches: (t) => !_isPendingSwap(t) && _searchableText(t).contains(query),
      isCancelled: () => disposed,
      limit: _kMaxTransactionResults,
    );
    if (disposed) return UnifiedSearchResults.empty;
    matched.addAll(rows.map((t) => (t, label)));
  }
  matched.sort((a, b) => b.$1.timestamp.compareTo(a.$1.timestamp));
  final txResults = <TransactionSearchResult>[];
  for (final (t, label) in matched) {
    txResults.add(TransactionSearchResult(t, walletName: label));
    if (txResults.length >= _kMaxTransactionResults) break;
  }

  // 2a. OWNED POSITIONS — active + resolved + claimable, de-duped by
  // conditionId (marketId). First occurrence wins, capped.
  final owned = <OwnedPositionSearchResult>[];
  final seenConditionIds = <String>{};
  for (final p in positionSources) {
    if (owned.length >= _kMaxOwnedPositionResults) break;
    if (!_positionSearchableText(p).contains(query)) continue;
    if (!seenConditionIds.add(p.marketId)) continue;
    owned.add(OwnedPositionSearchResult(p));
  }

  return UnifiedSearchResults(
    transactions: txResults,
    ownedPositions: owned,
  );
});

/// Remote global-market leg. Wraps the debounced `polymarketSearchProvider`
/// (which already sleeps 300ms before hitting Gamma) and projects the
/// events into search results, de-duped against the conditionIds the
/// owned-positions subsection already surfaced (passed by the UI) and
/// capped at [kMaxGlobalMarketResults].
///
/// ONGOING / LIVE markets are surfaced FIRST: `polymarketSearchProvider`'s
/// resolved filter already keeps genuinely in-play games (it returns false
/// for a live, score/period-seeded, not-ended event), but the cap could
/// otherwise drop a live market sitting below the first five Gamma hits. We
/// stable-sort in-play markets ahead of the rest — using the live WS feed
/// (keyed by slug, then `game:<gameId>`) and the event's own seeded in-play
/// signal as a fallback — so a live game matching the query always makes the
/// (capped) cut and leads the section, where the UI tags it "LIVE".
final globalMarketResultsProvider =
    Provider.autoDispose<AsyncValue<List<GlobalMarketSearchResult>>>((ref) {
  if (!ref.watch(runtimeCapabilitiesProvider).allows('polymarket.browse')) {
    return const AsyncValue.data([]);
  }
  if (ref.watch(searchWalletScopeProvider) != null) return const AsyncValue.data([]);
  final category = ref.watch(selectedSearchCategoryProvider);
  if (category != SearchCategory.all && category != SearchCategory.predictions) {
    return const AsyncValue.data([]);
  }
  final query = ref.watch(searchQueryProvider).trim();
  if (query.isEmpty) return const AsyncValue.data([]);

  // conditionIds already shown as owned positions — don't repeat them
  // as global markets.
  final ownedConditionIds = ref
      .watch(unifiedSearchResultsProvider)
      .valueOrNull?.ownedPositions
      .map((r) => r.position.marketId)
      .toSet() ?? <String>{};

  final async = ref.watch(polymarketSearchProvider(query));
  // While the venue answers, the markets the Predictions screen already
  // holds in memory that match stand in, so results show at once.
  final events = async.valueOrNull ??
      (async.isLoading ? _browsedMarketsMatching(ref, query) : null);
  if (events == null) {
    return async.whenData((_) => const <GlobalMarketSearchResult>[]);
  }
  // Which of these markets are in play, as one value: only a game among
  // them starting or stopping re-sorts the list, not every score tick.
  final liveMask = ref.watch(sportsLiveProvider.select((live) => [
        for (final e in events)
          (_liveUpdateForEvent(e, live)?.isInPlay ?? false) ? '1' : '0',
      ].join()));
  final live = {
    for (var i = 0; i < events.length; i++)
      if (liveMask[i] == '1') events[i],
  };
  List<GlobalMarketSearchResult> project(List<PolymarketEvent> events) {
    // De-dup first (against owned positions + repeated conditionIds), then
    // stable-sort live-first, then cap — so the cap is applied AFTER live
    // markets are pulled to the top, never before.
    final deduped = <PolymarketEvent>[];
    final seen = <String>{};
    for (final e in events) {
      final cid = e.conditionId;
      if (cid.isNotEmpty && ownedConditionIds.contains(cid)) continue;
      if (cid.isNotEmpty && !seen.add(cid)) continue;
      deduped.add(e);
    }

    bool isLive(PolymarketEvent e) => live.contains(e) || e.isInPlay;

    // Stable partition: in-play markets first, original (Gamma) order kept
    // within each group.
    final sorted = [
      ...deduped.where(isLive),
      ...deduped.where((e) => !isLive(e)),
    ];

    return [
      for (final e in sorted.take(kMaxGlobalMarketResults))
        GlobalMarketSearchResult(e),
    ];
  }

  if (async.hasValue) return AsyncValue.data(project(events));
  // Still loading: the in-memory matches, flagged as loading so the sheet
  // keeps its "searching" row under them until the venue answers.
  return const AsyncLoading<List<GlobalMarketSearchResult>>()
      .copyWithPrevious(AsyncData(project(events)));
});

/// The markets the Predictions screen has already read (the list on
/// screen and Trending) whose title holds [query], with the same filters
/// the venue search applies. Never starts a read: a list that is not in
/// memory is skipped.
List<PolymarketEvent> _browsedMarketsMatching(Ref ref, String query) {
  final q = query.toLowerCase();
  final feeds = {
    ref.read(polyBrowseSelectionProvider).query,
    const PolyFeedQuery(pill: PolyPill.trending),
  };
  final out = <PolymarketEvent>[];
  final seen = <String>{};
  for (final feed in feeds) {
    final provider = polyBrowseFeedProvider(feed);
    if (!ref.exists(provider)) continue;
    for (final e in ref.read(provider).events) {
      if (!e.title.toLowerCase().contains(q)) continue;
      if (e.liquidity < 1000 || e.closed) continue;
      if (e.slug.toLowerCase().contains('-updown-5m-')) continue;
      if (seen.add(e.slug.isEmpty ? e.id : e.slug)) out.add(e);
    }
  }
  return out;
}

/// Remote Hyperliquid-markets leg. Wraps the debounced
/// [hyperliquidMarketSearchProvider] (backend-first, client-side fallback)
/// exactly the way [globalMarketResultsProvider] wraps the Polymarket
/// search, and caps the projection at [kMaxHyperliquidResults] so the
/// Perpetuals result group stays compact. The UI watches this provider and
/// renders each hit as an `_HlMarketRow`.
final globalHyperliquidResultsProvider =
    Provider.autoDispose<AsyncValue<List<HlMarketSearchResult>>>((ref) {
  if (!ref.watch(runtimeCapabilitiesProvider).allows('hyperliquid.browse')) {
    return const AsyncValue.data([]);
  }
  if (ref.watch(searchWalletScopeProvider) != null) return const AsyncValue.data([]);
  final category = ref.watch(selectedSearchCategoryProvider);
  if (category != SearchCategory.all && category != SearchCategory.perpetuals) {
    return const AsyncValue.data([]);
  }
  final query = ref.watch(searchQueryProvider).trim();
  if (query.isEmpty) return const AsyncValue.data([]);
  final async = ref.watch(hyperliquidMarketSearchProvider(query));
  return async.whenData(
    (list) => list.take(kMaxHyperliquidResults).toList(),
  );
});

/// Live WS update for [e], joined by Gamma slug, then the stable
/// `game:<gameId>` key, then cricket's `eventMetadata.gameId` (the WS slug
/// isn't guaranteed to match Gamma's event slug). Mirrors the Predictions
/// screen's lookup so the search "live-first" sort agrees with the cards'
/// LIVE badge.
SportsMatchUpdate? _liveUpdateForEvent(
  PolymarketEvent e,
  Map<String, SportsMatchUpdate> sportsLive,
) =>
    sportsUpdateFor(sportsLive,
        slug: e.slug, gameId: e.gameId, metadataGameId: e.metadataGameId);
