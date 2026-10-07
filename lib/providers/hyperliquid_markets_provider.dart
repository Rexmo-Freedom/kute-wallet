// lib/providers/hyperliquid_markets_provider.dart
//
// Browse layer for the Trading tab: the FULL Hyperliquid universe (every
// live perp + every USDC-quoted spot pair — NO allowlist, hard product
// requirement), refreshed on the same 30 s cadence as the legacy
// `hyperliquidTickersProvider` so list prices/24h% stay current without
// hammering the API. Sorted by 24h notional volume desc, which is the
// default order the market list renders.
//
// wireCoin vs coin — the one mapping that must never leak: every
// WS/l2Book/candle call takes `HlMarket.wireCoin` (perp name, or
// `@<index>`/canonical pair name for spot); every DISPLAY key is
// `HlMarket.coin` (perp name / spot base-token name, e.g. 'TSLA').
// This file centralizes the translation via
// [hyperliquidWireToCoinMapProvider] (wire → display, spot pairs) so the
// live-prices provider can re-key allMids frames, and via
// [hyperliquidMarketProvider] (display coin → full descriptor) for
// everything else. Getting this wrong is silent (empty charts/books).
//
// The legacy hyperliquidSpotTickersProvider (hyperliquid_provider.dart)
// is untouched. The cards' sparklines come from
// hyperliquid_sparkline_provider.dart.

import 'dart:async';


import 'package:kute/providers/hyperliquid_watchlist_provider.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/venue_analytics.dart';
import 'package:kute/services/hyperliquid/hl_markets_disk_cache.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/hyperliquid_model.dart';

/// Shared thin HTTP client for the trading read paths. Stateless — one
/// instance app-wide is fine (also imported by the account/orderbook/
/// fills providers so we don't scatter `HyperliquidModel()` allocations).
final hyperliquidTradingModelProvider =
    Provider<HyperliquidModel>((ref) => HyperliquidModel());

/// Symbols that get TAGGED as EQUITIES for the "Stocks" category pill on
/// the Trading tab. TAGGING ONLY — this set must never filter the market
/// list or search results (full-universe requirement); an untagged token
/// simply lands in the default/Crypto bucket until someone extends this
/// set. Equities ONLY — the tokenized gold/silver trackers live in
/// [kHlCommoditySymbols] and the broad-market INDEX trackers (SPY/QQQ/…) in
/// [kHlIndexSymbols], each with its own pill.
const kHlStockSymbols = <String>{
  'AAPL',
  'AMD',
  'AMZN',
  'COIN',
  'CRCL',
  'GOOGL',
  'HOOD',
  'INTC',
  'META',
  'MSFT',
  'MSTR',
  'NFLX',
  'NVDA',
  'PLTR',
  'TSLA',
};

/// Broad-market INDEX proxies — the S&P 500 (SPY/SP500/SPX), Nasdaq 100
/// (QQQ/NDX), Dow (DJI/DIA) and Russell (IWM/RUT). These are NOT stocks
/// (a user browsing "Stocks" doesn't expect the S&P); they get their own
/// Indices pill. The backend/annotation `category` ('indices') is preferred
/// when present — this set is the offline fallback. [isHlIndexMarket] is the
/// predicate.
const kHlIndexSymbols = <String>{
  'SPY',
  'QQQ',
  'SP500',
  'SPX',
  'NDX',
  'DJI',
  'DIA',
  'IWM',
  'RUT',
};

/// Tokenized COMMODITY proxies known to trade on HL spot — gold/silver
/// trackers (GLD, SLV), Tether Gold (XAUT0) and Paxos Gold (PAXG if listed).
/// Split out of [kHlStockSymbols] so the Trading tab's Commodities pill can
/// surface them on their own; [isHlCommodityMarket] is the predicate.
const kHlCommoditySymbols = <String>{
  'GLD',
  'SLV',
  'XAUT0',
  'PAXG',
};

/// True when [market] should surface under the Stocks pill (real equities
/// ONLY — indices + commodities have their own pills).
bool isHlStockMarket(HlMarket market) => kHlStockSymbols.contains(market.coin);

/// True when [market] should surface under the Indices pill (broad-market
/// index trackers — the S&P 500, Nasdaq 100, Dow, Russell).
bool isHlIndexMarket(HlMarket market) => kHlIndexSymbols.contains(market.coin);

/// A stock-linked perpetual: a derivative on an equity, not a share. The
/// venue's own annotation wins; the symbol set catches a market the venue
/// left unannotated. Spot tokens are not perpetuals and never count.
bool isHlStockPerp(HlMarket market) =>
    !market.isSpot && (market.category == 'stocks' || isHlStockMarket(market));

/// The policy capabilities a NEW position on [market] needs: opening
/// investments, plus the stock-perp gate for a stock-linked perpetual.
/// Hot and Ledger order paths both check exactly this list, and every
/// exit (close, reduce, cancel) stays on its own capability.
List<String> hlOpenCapabilities(HlMarket market) => [
      'hyperliquid.trade',
      if (isHlStockPerp(market)) 'hyperliquid.stocks',
    ];

/// Whether [market] may be offered as somewhere to open a position under
/// the current policy. A stock-linked perp disappears from browse, search
/// and Sal while `hyperliquid.stocks` denies, including when the policy
/// cannot be read at all (the gate fails closed). Positions already held
/// are looked up by their own providers and never pass through here.
bool hlMarketOfferedUnderPolicy(
        HlMarket market, RuntimeCapabilitiesService policy) =>
    !isHlStockPerp(market) || policy.allows('hyperliquid.stocks');

/// [markets] minus the ones the policy hides; see [hlMarketOfferedUnderPolicy].
List<HlMarket> hlMarketsOfferedUnderPolicy(
    List<HlMarket> markets, RuntimeCapabilitiesService policy) {
  if (policy.allows('hyperliquid.stocks')) return markets;
  return [
    for (final m in markets)
      if (!isHlStockPerp(m)) m
  ];
}

/// True when [market] should surface under the Commodities pill (tokenized
/// gold/silver trackers).
bool isHlCommodityMarket(HlMarket market) =>
    kHlCommoditySymbols.contains(market.coin);

/// Coarse classification of a SPOT market into the Trading tab's browse
/// buckets. Perps are never passed here (they carry their own annotation
/// category); a spot pair is a tokenized equity ([HlSpotClass.stock]), a
/// broad-market index tracker ([HlSpotClass.indices]), a commodity tracker
/// ([HlSpotClass.commodity]), or a plain crypto spot token
/// ([HlSpotClass.otherSpot]). (`indices` rather than `index` — the latter
/// collides with Dart's built-in enum ordinal getter.)
enum HlSpotClass { stock, indices, commodity, otherSpot }

/// Classify a spot market. The backend/annotation [HlMarket.category] WINS
/// when present (so an annotation tagging SPY/QQQ as 'indices' beats any
/// stale symbol-set guess); otherwise we fall back to the known symbol sets.
HlSpotClass classifyHlSpotMarket(HlMarket market) {
  switch (market.category) {
    case 'indices':
      return HlSpotClass.indices;
    case 'commodities':
      return HlSpotClass.commodity;
    case 'stocks':
      return HlSpotClass.stock;
  }
  if (isHlIndexMarket(market)) return HlSpotClass.indices;
  if (isHlCommodityMarket(market)) return HlSpotClass.commodity;
  if (isHlStockMarket(market)) return HlSpotClass.stock;
  return HlSpotClass.otherSpot;
}

// ─────────────────────────── browse taxonomy ───────────────────────────
//
// The Investing tab browses like Predictions: one row of category pills
// that filter the list in place and, under it, the subcategories of the
// category on screen in the same pills.
//
// The tree is the one in Hyperliquid's own market selector
// (app.hyperliquid.xyz, read on 2026-10-04), under its own names:
//
//   Watchlist   the markets starred here (only once something is starred)
//   Trending    the app's own ranking: the most traded, by 24 h volume
//   Perps       every perp, main dex and builder dexes
//   Spot        every spot pair the app loads (USDC-quoted)
//   Crypto      the main dex's perps       → Layer 1 · Layer 2 · Defi ·
//                                            AI · Meme · Gaming · Other
//   Tradfi      builder-dex perps the venue classes as stocks, indices,
//               commodities, fx or preipo, and the spot tokens of those
//               classes                    → Stocks · Indices ·
//                                            Commodities · FX · Pre-IPO
//   Pre-launch  main-dex perps in strictIsolated margin mode
//
// A builder-dex market the venue classes as rates, crypto or nothing
// lists under Perps only. The site's All, HIP-3, HIP-4/Outcome and
// Favorites tabs are not offered (All repeats Perps and Spot). A pill or
// a sub-pill with no market is hidden, and a sub-row has no All: it opens
// on its first pill.

enum HlBrowseTab {
  /// The markets starred on this device (hyperliquid_watchlist_provider):
  /// first in the row, and only there once something is starred.
  watchlist,
  trending,
  perps,
  spot,
  crypto,
  tradfi,
  prelaunch,
}

extension HlBrowseTabX on HlBrowseTab {
  /// Analytics value.
  String get key => switch (this) {
        HlBrowseTab.watchlist => 'watchlist',
        HlBrowseTab.trending => 'trending',
        HlBrowseTab.perps => 'perps',
        HlBrowseTab.spot => 'spot',
        HlBrowseTab.crypto => 'crypto',
        HlBrowseTab.tradfi => 'tradfi',
        HlBrowseTab.prelaunch => 'pre_launch',
      };
}

/// A subcategory inside a category, in the site's order: Crypto's sectors
/// ([kHlCryptoSectors]) and Tradfi's asset classes.
enum HlBrowseSub {
  /// No narrowing: what a category with no sub-row lists.
  all,
  ai,
  defi,
  gaming,
  layer1,
  layer2,
  meme,
  stocks,
  indices,
  commodities,
  fx,
  preipo,

  /// Crypto's coins the site names in no sector.
  other,
}

/// The venue categories that make up Tradfi, in the site's order.
const List<HlBrowseSub> kHlTradfiSubs = [
  HlBrowseSub.stocks,
  HlBrowseSub.indices,
  HlBrowseSub.commodities,
  HlBrowseSub.fx,
  HlBrowseSub.preipo,
];

/// Crypto's sectors in the order the row shows them: the majors' sector
/// first, since the row has no All and opens on its first pill.
const List<HlBrowseSub> kHlCryptoSubs = [
  HlBrowseSub.layer1,
  HlBrowseSub.layer2,
  HlBrowseSub.defi,
  HlBrowseSub.ai,
  HlBrowseSub.meme,
  HlBrowseSub.gaming,
  HlBrowseSub.other,
];

extension HlBrowseSubX on HlBrowseSub {
  /// Analytics value.
  String get key => name;

  bool get isSector => kHlCryptoSectors.containsKey(this);

  bool matches(HlMarket m) => switch (this) {
        HlBrowseSub.all => true,
        HlBrowseSub.stocks ||
        HlBrowseSub.indices ||
        HlBrowseSub.commodities ||
        HlBrowseSub.fx ||
        HlBrowseSub.preipo =>
          m.category == name,
        HlBrowseSub.other => !kHlCryptoSectors.values
            .any((sector) => sector.contains(hlSectorSymbol(m))),
        _ => kHlCryptoSectors[this]!.contains(hlSectorSymbol(m)),
      };
}

/// The crypto sectors of Hyperliquid's own web app (its market selector's
/// AI / Defi / Gaming / Layer 1 / Layer 2 / Meme lists, copied from
/// app.hyperliquid.xyz on 2026-10-04). The venue's API carries no sector,
/// so this is the one list that is its own; a coin it does not name has
/// no sector and lists under All.
const Map<HlBrowseSub, Set<String>> kHlCryptoSectors = {
  HlBrowseSub.ai: {
    'CHIP', 'FET', 'RNDR', 'TAO', 'NEAR', 'WLD', 'IO', 'RENDER',
    'GRASS', 'VIRTUAL', 'AIXBT', 'ZEREBRO', 'GRIFFAIN', 'VVV', 'KAITO',
    'PROMPT', '0G',
  },
  HlBrowseSub.layer1: {
    'ADA', 'APT', 'ATOM', 'AVAX', 'BCH', 'BNB', 'BSV', 'BTC', 'CFX',
    'DOT', 'ETH', 'FTM', 'INJ', 'KAS', 'LTC', 'MINA', 'NEAR', 'NEO',
    'POLYX', 'RUNE', 'SEI', 'SOL', 'SUI', 'TIA', 'TON', 'TRX', 'XRP',
    'ZEN', 'kLUNC', 'NTRN', 'ETC', 'ZETA', 'DYM', 'SAGA', 'XLM', 'ALGO',
    'HYPE', 'S', 'BERA', 'IP', 'OM', 'INIT', 'XPL', '0G', 'MON', 'CC',
    'ICP', 'STABLE', 'XMR', 'FOGO',
  },
  HlBrowseSub.layer2: {
    'MNT', 'ZK', 'BLAST', 'ARB', 'OP', 'STARK', 'MATIC', 'POL', 'IMX',
    'CELO', 'SCR', 'STRK', 'MOVE', 'LAYER', 'LINEA', 'HEMI', 'MEGA',
    'LIT', 'AZTEC',
  },
  HlBrowseSub.defi: {
    'AAVE', 'BNT', 'COMP', 'CRV', 'DYDX', 'FRAX', 'GMX', 'INJ', 'LDO',
    'LINK', 'PENDLE', 'PYTH', 'RLB', 'RUNE', 'SNX', 'SUSHI', 'TRB',
    'UNI', 'RSR', 'JTO', 'MAV', 'CAKE', 'UMA', 'ALT', 'JUP', 'ETHFI',
    'REZ', 'BANANA', 'ENA', 'EIGEN', 'MORPHO', 'WCT', 'RESOLV', 'SYRUP',
    'PUMP', 'PONS', 'SKY', 'STBL', 'MET', 'AERO',
  },
  HlBrowseSub.gaming: {
    'APE', 'BIGTIME', 'BLZ', 'ILV', 'IMX', 'YGG', 'GMT', 'SUPER',
    'GALA', 'ACE', 'XAI', 'MAVIA', 'HMSTR', 'NOT', 'SAND', 'NXPC', 'AXS',
  },
  HlBrowseSub.meme: {
    'CASHCAT', 'DOGE', 'HPOS', 'kPEPE', 'SHIA', 'kSHIB', 'kBONK',
    'MEME', 'WIF', 'PEOPLE', 'MYRO', 'kFLOKI', 'BOME', 'POPCAT',
    'TURBO', 'BRETT', 'MEW', 'kNEIRO', 'GOAT', 'MOODENG', 'PNUT',
    'CHILLGUY', 'FARTCOIN', 'SPX', 'TRUMP', 'MELANIA', 'VINE', 'JELLY',
    'TST', 'PENGU', 'YZY', 'USELESS',
  },
};

/// The symbol a market is filed under in [kHlCryptoSectors]: its coin, or
/// for a Unit-bridged spot token the asset it holds (UBTC → BTC).
String hlSectorSymbol(HlMarket m) =>
    m.isSpot && m.unitAssetName != null ? m.coin.substring(1) : m.coin;

/// The spot tokens Hyperliquid's own web app lists with its Strict
/// switch on (its verified list, resolved from the token ids in
/// app.hyperliquid.xyz on 2026-10-04). Ordering only: these lead the
/// spot lists, ahead of tokens anyone may deploy under any name, and only
/// these stand in for a perp of the same symbol. Nothing is hidden.
const Set<String> kHlVerifiedSpotTokens = {
  'ATEHUN', 'AXL', 'BASED', 'BUDDY', 'CATBAL', 'DRV', 'FEUSD', 'HAR',
  'HFUN', 'HPENGU', 'HPL', 'HSEI', 'HYPE', 'JEFF', 'KHYPE', 'KNTQ',
  'LIQD', 'MMOVE', 'MUX', 'NVDAX', 'ONEAR', 'PIP', 'POINTS', 'PURR',
  'QONE', 'QQQX', 'SEDA', 'SKHYX', 'SOLV', 'SPCXD', 'SPYX', 'STABLE',
  'SWAP', 'TREAD', 'UANSEM', 'UAVAX', 'UBONK', 'UBTC', 'UDZ', 'UENA',
  'UETH', 'UFART', 'UMON', 'UPUMP', 'USDE', 'USDH', 'USDHL', 'USDT0',
  'USOL', 'UUUSPX', 'UVIRT', 'UXPL', 'UZEC', 'XAUT0',
};

bool hlSpotIsVerified(HlMarket m) =>
    m.isSpot && kHlVerifiedSpotTokens.contains(m.coin);

/// The venue categories the site files under Tradfi.
const Set<String> kHlTradfiCategories = {
  'stocks',
  'indices',
  'commodities',
  'fx',
  'preipo',
};

/// A pre-launch market, as the site decides it: a main-dex perp in
/// strictIsolated margin mode (CASHCAT, which the site excludes by name,
/// aside).
bool hlMarketIsPreLaunch(HlMarket m) =>
    !m.isSpot &&
    !m.isHip3 &&
    m.marginMode == 'strictIsolated' &&
    m.coin != 'CASHCAT';

/// True when [m] belongs under [tab]. The Watchlist and Trending are a
/// list and a ranking of their own and never match here.
bool hlMarketMatchesTab(HlMarket m, HlBrowseTab tab) => switch (tab) {
      HlBrowseTab.perps => !m.isSpot,
      HlBrowseTab.spot => m.isSpot,
      // The main dex's perps.
      HlBrowseTab.crypto => !m.isSpot && !m.isHip3,
      // The builder dexes' perps, and the spot tokens of the same asset
      // classes: where the policy hides stock-linked perps, the stock
      // tokens are what Stocks still lists.
      HlBrowseTab.tradfi => (m.isSpot || m.isHip3) &&
          kHlTradfiCategories.contains(m.category),
      HlBrowseTab.prelaunch => hlMarketIsPreLaunch(m),
      HlBrowseTab.watchlist || HlBrowseTab.trending => false,
    };

/// Whether [m] answers a search for [query]: its ticker, [friendlyName]
/// (the app's own name for the symbol), the venue's friendly name
/// (io:OAI → OPENAI, xyz:CL → WTIOIL) or one of the venue's keywords
/// (xyz:XYZ100 → nasdaq, qqq; xyz:CL → crude). Case and punctuation are
/// ignored, so "wti oil" finds WTIOIL and "s&p" finds S&P500.
bool hlMarketMatchesQuery(HlMarket m, String query, {String? friendlyName}) {
  final raw = query.trim().toLowerCase();
  if (raw.isEmpty) return true;
  final norm = hlNormalizeSearch(raw);
  bool has(String? s) {
    if (s == null || s.isEmpty) return false;
    final lower = s.toLowerCase();
    return lower.contains(raw) ||
        (norm.isNotEmpty && hlNormalizeSearch(lower).contains(norm));
  }

  return has(m.coin) ||
      has(friendlyName) ||
      has(m.annotatedName) ||
      m.keywords.any(has);
}

/// Lower case with every non-alphanumeric removed ("S&P 500" → "sp500").
String hlNormalizeSearch(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Top-N by 24h volume for the Trending section (the universe is already
/// volume-heavy, so this is a rank + slice).
const int kHlTrendingCount = 30;

int _byVolume(HlMarket a, HlMarket b) => b.dayNtlVlm.compareTo(a.dayNtlVlm);

/// Every market of [tab], unordered. The Watchlist is the starred
/// markets, in the order of [watchlist] (newest star first); Trending is
/// the most traded.
List<HlMarket> _hlTabMarkets(HlBrowseTab tab, List<HlMarket> universe,
    {List<String> watchlist = const []}) {
  switch (tab) {
    case HlBrowseTab.watchlist:
      return hlWatchlistMarkets(watchlist, universe);
    case HlBrowseTab.trending:
      // The most traded markets: pure volume.
      return ([...universe]..sort(_byVolume)).take(kHlTrendingCount).toList();
    default:
      return [
        for (final m in universe)
          if (hlMarketMatchesTab(m, tab)) m
      ];
  }
}

/// The subcategory pills of [tab], in the site's order, or an empty list
/// when it has none: each subcategory that has a market. Crypto's are the
/// sectors; Tradfi's the asset classes. There is no All: every market
/// sits under its own pill and the row opens on the first.
List<HlBrowseSub> hlSubsForTab(HlBrowseTab tab, List<HlMarket> universe) {
  final List<HlBrowseSub> candidates;
  switch (tab) {
    case HlBrowseTab.crypto:
      candidates = kHlCryptoSubs;
    case HlBrowseTab.tradfi:
      candidates = kHlTradfiSubs;
    default:
      return const [];
  }
  final markets = _hlTabMarkets(tab, universe);
  return [
    for (final s in candidates)
      if (markets.any(s.matches)) s
  ];
}

/// The subcategory [tab] shows for [selected]: [selected] when the row
/// offers it, else the row's first pill, or no narrowing without a row.
HlBrowseSub hlEffectiveSub(HlBrowseSub selected, List<HlBrowseSub> subs) {
  if (subs.contains(selected)) return selected;
  return subs.isEmpty ? HlBrowseSub.all : subs.first;
}

/// The browse list for [tab] and its subcategory [sub], derived
/// CLIENT-SIDE from the in-memory [universe] (no network pagination).
///
/// Order: the Watchlist as starred, newest first; Trending by 24 h
/// volume. Every other list puts the perps first, most traded first,
/// then the spot tokens: the ones Hyperliquid's own app verifies
/// ([kHlVerifiedSpotTokens]) by volume, then the rest by volume. Spot
/// volume on tokens anyone may deploy is not comparable with perp
/// volume, and ranked together an obscure token sat among the majors.
///
/// Shared by the Investing screen and the Ledger tab, so both show the
/// same membership and order.
List<HlMarket> hlBrowseListForTab(
  HlBrowseTab tab,
  List<HlMarket> universe, {
  HlBrowseSub sub = HlBrowseSub.all,
  List<String> watchlist = const [],
}) {
  // The Watchlist is exactly what was starred, newest star first.
  if (tab == HlBrowseTab.watchlist) {
    return hlWatchlistMarkets(watchlist, universe);
  }
  final list = _hlTabMarkets(tab, universe).where(sub.matches).toList();
  if (tab == HlBrowseTab.trending) {
    list.sort(_byVolume);
    return _preferOwnership(list, universe);
  }
  int rank(HlMarket m) => !m.isSpot ? 0 : (hlSpotIsVerified(m) ? 1 : 2);
  list.sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    return r != 0 ? r : _byVolume(a, b);
  });
  return list;
}

/// Ownership is the default landing on Trending: when an underlying is
/// listed both ways, the row the ranking renders is the one you can
/// actually OWN, so a tap lands on the spot market and the leveraged
/// contract for the same underlying is a deliberate second step (Perps,
/// Crypto, search, and the position you already hold). Only a verified
/// spot token stands in ([kHlVerifiedSpotTokens]): anyone may deploy a
/// token called PUMP, and that is not the PUMP the perp tracks. Every
/// category pill lists exactly what it names.
List<HlMarket> _preferOwnership(List<HlMarket> list, List<HlMarket> universe) {
  final spotByBase = <String, HlMarket>{};
  for (final m in universe) {
    if (hlSpotIsVerified(m)) {
      spotByBase.putIfAbsent(m.coin.toUpperCase(), () => m);
    }
  }
  if (spotByBase.isEmpty) return list;
  final out = <HlMarket>[];
  final seen = <String>{};
  for (final m in list) {
    // Only a default-dex crypto perp has a spot twin by symbol; a builder
    // perp shares symbols with unrelated tokens.
    final pick = m.isSpot || m.isHip3
        ? m
        : (spotByBase[m.coin.toUpperCase()] ?? m);
    // The swap can land on a market the list already carries; keep the
    // first appearance so the row order stays the ranked order.
    if (seen.add('${pick.kind.name}:${pick.wireCoin}')) out.add(pick);
  }
  return out;
}

/// The category on screen and, per category, its subcategory. Lives for
/// the session (not autoDispose), so opening a market or leaving the tab
/// comes back to the same list.
class HlBrowseSelection {
  final HlBrowseTab tab;
  final Map<HlBrowseTab, HlBrowseSub> subs;

  const HlBrowseSelection({
    this.tab = HlBrowseTab.trending,
    this.subs = const {},
  });

  HlBrowseSub get sub => subs[tab] ?? HlBrowseSub.all;

  HlBrowseSelection copyWith({HlBrowseTab? tab, HlBrowseSub? sub}) {
    final t = tab ?? this.tab;
    return HlBrowseSelection(
      tab: t,
      subs: sub == null ? subs : {...subs, t: sub},
    );
  }
}

final hlBrowseSelectionProvider =
    StateProvider<HlBrowseSelection>((ref) => const HlBrowseSelection());

/// Base symbols listed BOTH ways — a spot market and a perp for the same

/// underlying. A row for one of these is ambiguous on the ticker alone
/// (two 'BTC' rows), so [HlMarketCard] qualifies it beyond the kind badge.
/// Recomputed only when a 30 s universe refresh lands.
final hyperliquidDualListedBasesProvider =
    Provider.autoDispose<Set<String>>((ref) {
  final perps =
      ref.watch(hyperliquidPerpMarketsProvider).valueOrNull ?? const [];
  final spots =
      ref.watch(hyperliquidSpotMarketsProvider).valueOrNull ?? const [];
  if (perps.isEmpty || spots.isEmpty) return const <String>{};
  final perpBases = {for (final m in perps) m.coin.toUpperCase()};
  return {
    for (final m in spots)
      if (perpBases.contains(m.coin.toUpperCase())) m.coin.toUpperCase(),
  };
});

/// The FULL merged perp universe — the default (crypto) dex PLUS every
/// builder (HIP-3) dex (WHEAT, tokenized stocks/commodities/indices,
/// pre-launch, …), each coin already categorized/dex-tagged by the model
/// straight from Hyperliquid (no backend dependency). Volume-sorted desc,
/// 30 s refresh — same Timer.periodic + invalidateSelf idiom as
/// hyperliquidTickersProvider (hyperliquid_provider.dart). The `perpDexs`
/// enumeration + annotations happen inside the model's [getAllPerpMarkets]
/// and are only re-fetched on this 30 s cadence (never per widget rebuild).
final hyperliquidPerpMarketsProvider =
    FutureProvider.autoDispose<List<HlMarket>>((ref) async {
  final model = ref.watch(hyperliquidTradingModelProvider);

  final timer = Timer.periodic(const Duration(seconds: 30), (_) {
    ref.invalidateSelf();
  });
  ref.onDispose(timer.cancel);

  final catalogue = await model.getPerpCatalogue();
  HlMarketDirectory.rememberDexes(catalogue.dexes);
  var markets = catalogue.markets;
  final whole = catalogue.complete && catalogue.annotated;
  if (!whole) {
    // A read failed with nothing remembered to stand in. The builder
    // markets and categories this device last saw stay on the list, and
    // the read is tried again shortly rather than at the next 30 s tick.
    final cache = HlMarketsDiskCache.instance..load();
    markets = hlKeepLastKnownBuilderMarkets(
        catalogue, _hlLastWholePerps ?? cache.perps);
    _hlShortPerpLoads++;
    if (_hlShortPerpLoads <= 3) {
      final retry = Timer(Duration(seconds: 6 * _hlShortPerpLoads), () {
        ref.invalidateSelf();
      });
      ref.onDispose(retry.cancel);
    }
  } else {
    _hlShortPerpLoads = 0;
  }
  markets.sort((a, b) => b.dayNtlVlm.compareTo(a.dayNtlVlm));
  if (whole) {
    // Only a whole answer is remembered: saving a short list would make
    // the next failure fall back to it.
    _hlLastWholePerps = markets;
    unawaited(HlMarketsDiskCache.instance.savePerps(markets));
  } else {
    _hlShortPerpLists[markets] = true;
  }
  HlMarketDirectory.remember(markets);
  return markets;
});

/// The last whole perp list of this session, and how many loads in a row
/// came back short (which spaces the early retries).
List<HlMarket>? _hlLastWholePerps;
int _hlShortPerpLoads = 0;

/// Test hook: forget the last whole perp list and the retry spacing.
@visibleForTesting
void hlResetPerpListMemoryForTest() {
  _hlLastWholePerps = null;
  _hlShortPerpLoads = 0;
}

/// Marks a perp list that a failed read left short.
final Expando<bool> _hlShortPerpLists = Expando<bool>();

/// [catalogue]'s markets, with what a failed read left out put back from
/// [lastKnown] (the last whole list, from this session or from disk):
/// every builder dex the answer has no market for keeps its last known
/// markets, and when the categories could not be read a builder market
/// keeps the category, name and keywords it last had. Prices on a kept
/// row are old until the live feed overwrites them. A whole answer is
/// returned as it is: a dex missing from it has really gone.
List<HlMarket> hlKeepLastKnownBuilderMarkets(
    HlPerpCatalogue catalogue, List<HlMarket>? lastKnown) {
  final fresh = catalogue.markets;
  if ((catalogue.complete && catalogue.annotated) ||
      lastKnown == null ||
      lastKnown.isEmpty) {
    return fresh;
  }
  final knownByWire = {
    for (final m in lastKnown)
      if (m.isHip3) m.wireCoin: m
  };
  final out = <HlMarket>[];
  final dexes = <String>{};
  for (final m in fresh) {
    if (m.isHip3) dexes.add(m.dex);
    final known = catalogue.annotated ? null : knownByWire[m.wireCoin];
    out.add(known == null
        ? m
        : m.copyWith(
            category: known.category,
            keywords: known.keywords,
            annotatedName: known.annotatedName,
          ));
  }
  if (!catalogue.complete) {
    for (final m in knownByWire.values) {
      if (!dexes.contains(m.dex)) out.add(m);
    }
  }
  return out;
}

/// True when the perp list on screen is short of builder (HIP-3) markets
/// because the venue's dex list could not be read and this device has
/// never seen them: Stocks, Commodities and Indices would list a few
/// spot tokens and look complete. Those lists show their loading state
/// until a retry lands.
final hyperliquidBuilderMarketsMissingProvider =
    Provider.autoDispose<bool>((ref) {
  final perps = ref.watch(hyperliquidPerpMarketsProvider).valueOrNull;
  if (perps == null || _hlShortPerpLists[perps] != true) return false;
  return !perps.any((m) => m.isHip3);
});

/// The categories made of builder-dex markets alone.
bool hlTabNeedsBuilderMarkets(HlBrowseTab tab) => tab == HlBrowseTab.tradfi;

/// Wire coins of the perps on [dex] ('' = main) at their open-interest
/// cap. The ticket warns before an order that would grow a position there.
/// Fail-soft (an empty set): the warning is advice, the venue decides.
final hyperliquidOiCappedProvider =
    FutureProvider.autoDispose.family<Set<String>, String>((ref, dex) async {
  try {
    return await ref
        .watch(hyperliquidTradingModelProvider)
        .getPerpsAtOpenInterestCap(dex: dex);
  } catch (_) {
    return const <String>{};
  }
});

/// The main dex's perps alone, one round trip, so the browse list paints
/// before the builder dexes have answered. Not refreshed on a timer: the
/// full list above takes over the moment it lands.
final hyperliquidPerpCoreMarketsProvider =
    FutureProvider.autoDispose<List<HlMarket>>((ref) async {
  final model = ref.watch(hyperliquidTradingModelProvider);
  final markets = await model.getCorePerpMarkets();
  markets.sort((a, b) => b.dayNtlVlm.compareTo(a.dayNtlVlm));
  return markets;
});

/// Every USDC-quoted spot pair (full universe — includes the tokenized
/// equities the Stocks pill surfaces), volume-sorted desc. 30 s refresh.
final hyperliquidSpotMarketsProvider =
    FutureProvider.autoDispose<List<HlMarket>>((ref) async {
  final model = ref.watch(hyperliquidTradingModelProvider);

  final timer = Timer.periodic(const Duration(seconds: 30), (_) {
    ref.invalidateSelf();
  });
  ref.onDispose(timer.cancel);

  final markets = await model.getSpotMarkets();
  markets.sort((a, b) => b.dayNtlVlm.compareTo(a.dayNtlVlm));
  unawaited(HlMarketsDiskCache.instance.saveSpots(markets));
  HlMarketDirectory.remember(markets);
  return markets;
});

/// Combined perp + spot list, volume-sorted desc across both kinds —
/// the single search source for the Trading tab's inline search field.
/// Renders whatever half has loaded so a slow spot fetch doesn't blank
/// the whole list.
final hyperliquidAllMarketsProvider =
    Provider.autoDispose<List<HlMarket>>((ref) {
  final perps =
      ref.watch(hyperliquidPerpMarketsProvider).valueOrNull ?? const [];
  final spots =
      ref.watch(hyperliquidSpotMarketsProvider).valueOrNull ?? const [];
  final all = <HlMarket>[...perps, ...spots];
  all.sort((a, b) => b.dayNtlVlm.compareTo(a.dayNtlVlm));
  return all;
});

/// Re-tag a direct-from-HL spot market with its browse [category] using
/// [classifyHlSpotMarket] (the direct spot parse defaults every pair to
/// 'crypto'; equities / indices / commodities are resolved from the symbol
/// sets, with any annotation category already on the market preferred). Perps
/// arrive pre-categorized from the model and skip this path.
HlMarket _classifyDirectSpot(HlMarket m) {
  final cat = switch (classifyHlSpotMarket(m)) {
    HlSpotClass.indices => 'indices',
    HlSpotClass.commodity => 'commodities',
    HlSpotClass.stock => 'stocks',
    HlSpotClass.otherSpot => 'crypto',
  };
  return m.copyWith(category: cat);
}

/// Give a perp the venue never annotated a category its symbol can
/// justify.
///
/// A coin on a builder dex with no annotation arrives as 'other', which
/// no topic tab filters on, so a tokenised equity or metal perp sat
/// outside Stocks, Commodities and Indices while the SPOT pair for the
/// same symbol was classified correctly. The same symbol classifier now
/// runs on both.
///
/// Only 'other' and an empty category are re-tagged. A perp the venue
/// DID annotate keeps what it was given, and the default dex's 'crypto'
/// is left alone: those are crypto perps, and a ticker that happens to
/// collide with an equity symbol must not be dragged into Stocks.
HlMarket _classifyUnannotatedPerp(HlMarket m) {
  final current = m.category.trim();
  if (current.isNotEmpty && current != 'other') return m;
  final resolved = switch (classifyHlSpotMarket(m)) {
    HlSpotClass.indices => 'indices',
    HlSpotClass.commodity => 'commodities',
    HlSpotClass.stock => 'stocks',
    HlSpotClass.otherSpot => null,
  };
  return resolved == null ? m : m.copyWith(category: resolved);
}

/// The Trading tab's browse universe: read DIRECTLY from Hyperliquid, no
/// backend. [hyperliquidPerpMarketsProvider] enumerates every builder
/// (HIP-3) dex itself and tags each coin's category from the HL annotations;
/// spot pairs are re-tagged via [_classifyDirectSpot]. So WHEAT, tokenized
/// stocks/indices/commodities and all HIP-3 markets surface on-device with
/// no server dependency. (The backend's catalog exists ONLY to ground the
/// AI's stock recommendations — browse never touches it.) Every market
/// carries a resolved [HlMarket.category] so the screen filters the tabs
/// uniformly. Volume-sorted desc.
final hyperliquidBrowseUniverseProvider =
    Provider.autoDispose<AsyncValue<List<HlMarket>>>((ref) {
  final perps = ref.watch(hyperliquidPerpMarketsProvider);
  final spots = ref.watch(hyperliquidSpotMarketsProvider);
  // While the full perp list is still loading, paint the main dex alone,
  // and before that the last lists this device saw. Both give way to the
  // live lists the moment they arrive.
  final core = perps.valueOrNull == null
      ? ref.watch(hyperliquidPerpCoreMarketsProvider).valueOrNull
      : null;
  final cache = HlMarketsDiskCache.instance..load();
  final perpList = perps.valueOrNull ?? core ?? cache.perps;
  final spotList = spots.valueOrNull ?? cache.spots;

  if (perpList == null && spotList == null) {
    final err = perps.error ?? spots.error;
    if (err != null && !perps.isLoading && !spots.isLoading) {
      return AsyncValue.error(
          err, perps.stackTrace ?? spots.stackTrace ?? StackTrace.current);
    }
    return const AsyncValue.loading();
  }

  // Re-evaluated whenever the policy changes, so a stock-perp block or
  // its lifting reaches every list built from the universe.
  final policy = ref.watch(runtimeCapabilitiesProvider);
  return AsyncValue.data(hlMarketsOfferedUnderPolicy(
      resolveHlBrowseUniverse(
          perpList ?? const <HlMarket>[], spotList ?? const <HlMarket>[]),
      policy));
});

/// Resolve browse metadata over a combined perp + spot universe: spot pairs
/// are re-tagged with their browse [HlMarket.category] and borrow the
/// matching HIP-3 perp's dex-qualified logo. Volume-sorted desc. Shared by
/// [hyperliquidBrowseUniverseProvider] and the unified-search HL fallback so
/// a search hit carries the SAME category/iconUrl a Trading-tab card renders.
List<HlMarket> resolveHlBrowseUniverse(
    List<HlMarket> perps, List<HlMarket> spots) {
  // A tokenized-asset spot pair (e.g. SPCX/USDC) has no `dex:` prefix, so it
  // can only ever build the bare coins/SPCX.svg logo URL — which is HL's HTML
  // catch-all, not a logo. The matching HIP-3 PERP (xyz:SPCX) carries the
  // proven dex-qualified logo, so lend it to the spot sibling by base symbol.
  final dexIconByBase = <String, String>{};
  // The venue annotates perps only. A tokenized spot token (SPCX, HOOD)
  // shares its symbol with builder-dex perps, so it borrows the category
  // those perps agree on (a disagreement borrows nothing) and their
  // search keywords and friendly name.
  final perpCategoryByBase = <String, String?>{};
  final keywordsByBase = <String, Set<String>>{};
  final nameByBase = <String, String>{};
  for (final p in perps) {
    if (!p.wireCoin.contains(':')) continue;
    final base = HlMarket.baseCoin(p.wireCoin).toUpperCase();
    if (p.iconUrl?.isNotEmpty ?? false) {
      dexIconByBase.putIfAbsent(base, () => p.iconUrl!);
    }
    if (p.category != 'other' && p.category.isNotEmpty) {
      perpCategoryByBase[base] = !perpCategoryByBase.containsKey(base) ||
              perpCategoryByBase[base] == p.category
          ? p.category
          : null;
    }
    if (p.keywords.isNotEmpty) {
      (keywordsByBase[base] ??= <String>{}).addAll(p.keywords);
    }
    if (p.annotatedName != null) nameByBase.putIfAbsent(base, () => p.annotatedName!);
  }
  HlMarket classifyAndIconSpot(HlMarket m) {
    var classified = _classifyDirectSpot(m);
    final base = classified.coin.toUpperCase();
    final perpCategory = perpCategoryByBase[base];
    // Only a spot token the symbol sets left as plain crypto borrows.
    if (classified.category == 'crypto' &&
        perpCategory != null &&
        perpCategory != 'crypto') {
      classified = classified.copyWith(category: perpCategory);
    }
    final borrowed = dexIconByBase[base];
    final keywords = keywordsByBase[base];
    return classified.copyWith(
      iconUrl: borrowed,
      keywords: keywords == null ? null : (keywords.toList()..sort()),
      annotatedName: nameByBase[base],
    );
  }

  final list = <HlMarket>[
    // Perps carry their annotation category (crypto/fx/indices/…), dex and
    // isHip3 from the model. The only ones touched are those the venue
    // annotated as nothing at all.
    ...perps.map(_classifyUnannotatedPerp),
    ...spots.map(classifyAndIconSpot),
  ];
  list.sort((a, b) => b.dayNtlVlm.compareTo(a.dayNtlVlm));
  VenueAnalytics.rememberHlMarkets(list);
  HlMarketDirectory.remember(list);
  return list;
}

/// Display-coin → market descriptor lookup across both kinds. Perps win
/// on a name collision (a perp 'X' and spot token 'X' are different
/// instruments; the perp is the primary trading surface). Null while
/// the lists are still loading or when the coin isn't on Hyperliquid.
///
/// This is a by-NAME lookup used to REFRESH a descriptor someone already
/// has, so it must keep returning the same instrument it always did.
/// Which market a mixed browse section LANDS on is decided by
/// [hlBrowseListForTab] (ownership first) — not here.
final hyperliquidMarketProvider =
    Provider.autoDispose.family<HlMarket?, String>((ref, coin) {
  final perps = ref.watch(hyperliquidPerpMarketsProvider).valueOrNull;
  if (perps != null) {
    for (final m in perps) {
      if (m.coin == coin) return m;
    }
  }
  final spots = ref.watch(hyperliquidSpotMarketsProvider).valueOrNull;
  if (spots != null) {
    for (final m in spots) {
      if (m.coin == coin) return m;
    }
  }
  return null;
});

/// The [hyperliquidExactMarketProvider] key for [market]: its kind and
/// its wire identifier, which together name one instrument.
String hlExactMarketKey(HlMarket market) =>
    '${market.isSpot ? 'spot' : 'perp'}:${market.wireCoin}';

/// Refreshes a descriptor someone is already looking at, keeping the
/// EXACT instrument.
///
/// [hyperliquidMarketProvider] is keyed on the displayed symbol and
/// searches perps first, which is fine for a coin that exists once. It is
/// wrong for a symbol that exists twice: tapping the spot SPCX handed the
/// detail sheet the perp SPCX, so a row badged Own opened a screen badged
/// Leveraged, with Short in place of Sell and a perp's price decimals.
/// The kind is part of the identity, so it is part of the key.
final hyperliquidExactMarketProvider =
    Provider.autoDispose.family<HlMarket?, String>((ref, key) {
  final separator = key.indexOf(':');
  if (separator <= 0) return null;
  final wire = key.substring(separator + 1);
  final list = key.startsWith('spot:')
      ? ref.watch(hyperliquidSpotMarketsProvider).valueOrNull
      : ref.watch(hyperliquidPerpMarketsProvider).valueOrNull;
  if (list == null) return null;
  for (final market in list) {
    if (market.wireCoin == wire) return market;
  }
  return null;
});

/// Account rows carry wire identifiers, so prefer that exact instrument before
/// falling back to the older display-symbol lookup. This keeps a spot token's
/// artwork distinct from a perp with the same displayed symbol.
final hyperliquidAccountMarketProvider =
    Provider.autoDispose.family<HlMarket?, String>((ref, coin) {
  final perps = ref.watch(hyperliquidPerpMarketsProvider).valueOrNull ??
      const <HlMarket>[];
  final spots = ref.watch(hyperliquidSpotMarketsProvider).valueOrNull ??
      const <HlMarket>[];
  for (final market in [...perps, ...spots]) {
    if (market.wireCoin == coin) return market;
  }
  for (final market in [...perps, ...spots]) {
    if (market.coin == coin) return market;
  }
  return null;
});

/// The market an ACCOUNT row names by its wire coin, exact match only.
/// Orders, fills and positions come back from the venue with wire coins
/// ('xyz:TSLA', '@107', 'PURR/USDC', 'BTC'), so this is the lookup for
/// anything that signs against the result (a cancel): a by-name lookup
/// can land on a different instrument that shares the symbol (spot vs
/// perp, or the same ticker on two builder dexes). Null while the lists
/// load or when the wire coin is unknown.
final hyperliquidWireMarketProvider =
    Provider.autoDispose.family<HlMarket?, String>((ref, wire) {
  final perps = ref.watch(hyperliquidPerpMarketsProvider).valueOrNull ??
      const <HlMarket>[];
  for (final market in perps) {
    if (market.wireCoin == wire) return market;
  }
  final spots = ref.watch(hyperliquidSpotMarketsProvider).valueOrNull ??
      const <HlMarket>[];
  for (final market in spots) {
    if (market.wireCoin == wire) return market;
  }
  return null;
});

/// The last markets seen, by wire coin, for code that has no provider ref
/// (receipts written from a stream, analytics). Filled whenever the perp
/// or spot lists load; never a source for anything that signs.
class HlMarketDirectory {
  HlMarketDirectory._();
  static final Map<String, HlMarket> _byWire = {};

  static void remember(Iterable<HlMarket> markets) {
    for (final m in markets) {
      _byWire[m.wireCoin] = m;
      if (m.isHip3 && m.dex.isNotEmpty && _dexes.add(m.dex)) dexEpoch++;
    }
  }

  /// Every builder dex the venue lists, in its own order, including a dex
  /// whose markets are all delisted (it has no market above, but its
  /// logos are still hosted and a twin on another dex may show one).
  static final Set<String> _dexes = <String>{};
  static Iterable<String> get builderDexes => _dexes;

  /// Bumped when [builderDexes] grows, so an icon that resolved to its
  /// fallback before the list was known can try again.
  static int dexEpoch = 0;

  static void rememberDexes(Iterable<String> dexes) {
    for (final d in dexes) {
      if (d.isNotEmpty && _dexes.add(d)) dexEpoch++;
    }
  }

  static HlMarket? byWire(String wire) => _byWire[wire];

  /// The builder-dex perps named [symbol] ('GOLD' → ['xyz:GOLD',
  /// 'flx:GOLD']), the largest dex (xyz) first; only those of [category]
  /// when one is given. A spot token Hyperliquid keeps no logo for shows
  /// the logo of the perp on the same underlying.
  static List<String> builderWiresFor(String symbol, {String? category}) {
    final wires = [
      for (final m in _byWire.values)
        if (m.isHip3 &&
            m.coin == symbol &&
            (category == null || m.category == category))
          m.wireCoin
    ]..sort();
    final xyz = wires.where((w) => w.startsWith('xyz:')).toList();
    return [...xyz, ...wires.where((w) => !w.startsWith('xyz:'))];
  }

  /// The other builder-dex perps of the same symbol and category as
  /// [wire] ('xyz:COPPER' → ['flx:COPPER']). Hyperliquid keeps a logo per
  /// dex-qualified name and not every dex has one, so a market without a
  /// logo of its own shows the one its twin on another dex has. The
  /// category must match: para:STX is a stock, not the crypto STX.
  static List<String> builderSiblings(String wire) {
    final self = _byWire[wire];
    if (self == null || !self.isHip3) return const [];
    return [
      for (final m in _byWire.values)
        if (m.isHip3 &&
            m.wireCoin != wire &&
            m.coin == self.coin &&
            m.category == self.category)
          m.wireCoin
    ]..sort();
  }

  /// 'TSLA' for '@142' or 'xyz:TSLA'; the bare base while unknown.
  static String displayName(String wire) =>
      hlDisplayCoin(_byWire[wire], wire);
}

/// The name to show for a wire coin: the market's display symbol
/// ('@142' → 'TSLA', 'xyz:TSLA' → 'TSLA'), or the bare base while the
/// lists load. Never the raw '@N' pair id when the market is known.
String hlDisplayCoin(HlMarket? market, String wire) =>
    market?.coin ?? HlMarket.baseCoin(wire);

/// wireCoin → display coin for SPOT pairs ('@142' → 'TSLA'). Perps are
/// identity-mapped on the wire and are deliberately omitted — consumers
/// (the live-prices provider re-keying allMids frames) fall back to the
/// wire key itself when a lookup misses.
final hyperliquidWireToCoinMapProvider =
    Provider.autoDispose<Map<String, String>>((ref) {
  final spots =
      ref.watch(hyperliquidSpotMarketsProvider).valueOrNull ?? const [];
  return {
    for (final m in spots)
      if (m.wireCoin != m.coin) m.wireCoin: m.coin,
  };
});

/// A one-shot trade-ticket prefill handed from Sal (the AI advisor) to the
/// Trading screen. The dispatcher can't open the order slip directly — the
/// slip needs a live `WidgetRef` and Sal dispatches from a stable root
/// context after the search sheet is gone — so it navigates to
/// `/hyperliquid` and drops the intent here. [HyperliquidScreen] consumes
/// it once on mount (post-frame) and opens the slip with its own ref, then
/// clears it. This mirrors how `autoShowDeposit` is threaded through the
/// route, but carries the resolved market + side. Sal only ever OPENS the
/// slip; the user still confirms size and leverage (no leverage prefill).
class HlAdvisorSlipIntent {
  final HlMarket market;
  final bool isLong;
  const HlAdvisorSlipIntent({required this.market, required this.isLong});
}

final hlAdvisorSlipIntentProvider =
    StateProvider<HlAdvisorSlipIntent?>((_) => null);
