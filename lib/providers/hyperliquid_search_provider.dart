// lib/providers/hyperliquid_search_provider.dart
//
// Client-side Hyperliquid market typeahead for the unified "Search wallet"
// surface. Mirrors `polymarketSearchProvider` (polymarket_browse_provider.dart):
// a 300 ms-debounced FutureProvider.autoDispose.family keyed by the raw query,
// so the autoDispose family tears down the previous query's provider on each
// keystroke and the abandoned delay never yields a stale result.
//
// Filters the already-loaded FULL HL universe
// (`hyperliquidBrowseUniverseProvider`, loaded DIRECTLY from Hyperliquid —
// all perps incl. HIP-3/WHEAT + spot, with browse category + icon resolved
// like the Trading tab), so this needs no server (the backend is reserved
// for the AI's stock recommendations, not user search). Mapped into the small
// [HlMarketSearchResult] projection the rows render; the row re-resolves the
// full HlMarket via `hyperliquidMarketProvider(coin)` on tap.
//
// FUZZY + alias-aware (mirrors the backend matcher used for the AI): the
// query, coin symbol, friendly names (ours and the venue's annotation
// displayName) and the venue's annotation keywords are NORMALIZED (lowercase,
// non-alphanumerics stripped) before matching, a curated ALIAS map resolves
// short forms / natural names ("snp"→S&P/SPY, "tesla"→TSLA, "gold"→GLD), and
// a subsequence pass tolerates minor typos. Ranked exact-symbol → alias →
// prefix → substring → subsequence → 24h notional volume desc, capped at 8.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/helpers/search_debounce.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

/// A lightweight Hyperliquid market hit for the search surface. Carries
/// only what the result row needs — the full [HlMarket] (order-wire ids,
/// rounding metadata, book) is re-resolved from `hyperliquidMarketProvider`
/// when the row is tapped, so we never have to reconstruct it from the
/// backend payload.
class HlMarketSearchResult {
  /// Display symbol — perp name or spot base-token name ('BTC', 'TSLA').
  final String coin;

  /// The market-data wire key (perp name / spot `@<index>` pair name).
  final String wireCoin;

  final HlMarketKind kind;

  /// True for the tokenized-equity / commodity-proxy markets (Stocks pill).
  final bool isStock;

  /// Friendly name shown in parens after the ticker ('Apple', 'Bitcoin'),
  /// when known. Null → the row shows the bare symbol.
  final String? name;

  /// Browse category (`crypto|stocks|commodities|fx|indices|preipo|other`),
  /// resolved the same way the Trading tab resolves it — the row feeds it to
  /// `HlCoinIcon` so a CDN miss falls back to the category glyph, not a bare
  /// letter.
  final String category;

  /// Coin-logo URL as resolved for the Trading-tab cards (incl. the borrowed
  /// dex-qualified perp logo on spot siblings). Null → `HlCoinIcon` builds
  /// its own CDN candidates.
  final String? iconUrl;

  final double markPx;

  /// 24h change as a FRACTION (0.025 == +2.5%) — same contract as
  /// [HlMarket.dayChangePct]; the row colors it green/red.
  final double dayChangePct;

  /// How far a perp can be geared ([HlMarket.offeredMaxLeverage]), for
  /// the row's "40x"; null for a token or when not known.
  final int? maxLeverage;

  /// The decimals the venue prices this market to, as the browse cards
  /// round it ([HlMarket.pxDecimalCap]).
  final int? pxDecimalCap;

  /// What a Unit-bridged token holds (UBTC: Bitcoin), its row title.
  final String? unitAssetName;

  /// The browse market the hit came from, so a result draws with the
  /// Investing tab's own card. Null when built without one (tests).
  final HlMarket? market;

  const HlMarketSearchResult({
    required this.coin,
    required this.wireCoin,
    required this.kind,
    required this.isStock,
    required this.name,
    required this.category,
    required this.iconUrl,
    required this.markPx,
    required this.dayChangePct,
    this.maxLeverage,
    this.pxDecimalCap,
    this.unitAssetName,
    this.market,
  });

  bool get isPerp => kind == HlMarketKind.perp;
}

/// Cap on how many hits either leg returns.
const int _kHlSearchCap = 8;

/// Debounced, remote-first Hyperliquid market search. Empty query → empty
/// list (no request). Mirrors `polymarketSearchProvider`'s debounce +
/// autoDispose.family shape.
final hyperliquidMarketSearchProvider = FutureProvider.autoDispose
    .family<List<HlMarketSearchResult>, String>((ref, query) async {
  final q = query.trim();
  if (q.isEmpty) return const [];

  var disposed = false;
  final debounce = SearchDebounce(const Duration(milliseconds: 200));
  ref.onDispose(() {
    disposed = true;
    debounce.cancel();
  });
  if (!await debounce.ready) return const [];

  // Client-side over the full HL universe (loaded directly from HL). The
  // backend is reserved for the AI's stock recommendations — user search
  // never touches it, and the client universe is complete (all HIP-3 /
  // WHEAT / stocks), so a query like "wheat" resolves here.
  return _fallbackResults(ref, q, () => disposed);
});

/// Client-side: FUZZY, alias-aware filter of the full HL universe
/// by symbol OR friendly name, ranked exact → alias → prefix → substring →
/// subsequence → volume desc. Mirrors the backend matcher so an offline
/// search resolves "snp"/"tesla"/"gold"/minor typos the same way.
Future<List<HlMarketSearchResult>> _fallbackResults(
    Ref ref, String q, bool Function() isDisposed) async {
  // The browse-resolved universe (spot pairs re-tagged with their category +
  // borrowed dex-qualified icons) so a hit carries the SAME category/iconUrl
  // a Trading-tab card renders. It may not have loaded yet (search can run
  // before the Trading tab was ever opened) — await the perp/spot legs and
  // resolve them the same way so a cold fallback still returns hits.
  var all = ref.read(hyperliquidBrowseUniverseProvider).valueOrNull ??
      const <HlMarket>[];
  if (all.isEmpty) {
    try {
      final legs = await Future.wait([
        ref.read(hyperliquidPerpMarketsProvider.future),
        ref.read(hyperliquidSpotMarketsProvider.future),
      ]);
      all = hlMarketsOfferedUnderPolicy(
          resolveHlBrowseUniverse(legs[0], legs[1]),
          ref.read(runtimeCapabilitiesProvider));
    } catch (_) {
      return const [];
    }
  }

  if (isDisposed()) return const [];
  final normQ = _normalizeToken(q);
  if (normQ.isEmpty) return const [];
  final aliasTargets = _aliasTargets(q, normQ);

  // Ranks (lower = better); _kNoMatch drops the market entirely.
  const int kNoMatch = 99;
  int rankOf(HlMarket m) {
    final normCoin = _normalizeToken(m.coin);
    final normName =
        _normalizeToken(_kHlSymbolNames[m.coin.toUpperCase()] ?? '');
    // The venue's own friendly name (io:OAI → OPENAI, xyz:CL → WTIOIL)
    // ranks like ours; its keywords (nasdaq, crude) like a substring.
    final normVenueName = _normalizeToken(m.annotatedName ?? '');
    if (normCoin == normQ) return 0; // exact symbol
    if (aliasTargets.contains(normCoin)) return 1; // curated alias → symbol
    if (normCoin.startsWith(normQ) ||
        (normName.isNotEmpty && normName.startsWith(normQ)) ||
        (normVenueName.isNotEmpty && normVenueName.startsWith(normQ))) {
      return 2; // prefix (symbol or name)
    }
    if (normCoin.contains(normQ) ||
        (normName.isNotEmpty && normName.contains(normQ)) ||
        (normVenueName.isNotEmpty && normVenueName.contains(normQ)) ||
        m.keywords.any((k) {
          final nk = _normalizeToken(k);
          // "crude oil" still finds the 'crude' keyword; a keyword under
          // four letters ('ai', 'ev') must not match every longer query.
          return nk.isNotEmpty &&
              (nk.contains(normQ) || (nk.length >= 4 && normQ.contains(nk)));
        })) {
      return 3; // substring (symbol, name or a venue keyword)
    }
    // Subsequence fuzzy pass tolerates minor typos; length-gated so a 1-2
    // char query can't fuzz into everything.
    if (normQ.length >= 3 &&
        (_isSubsequence(normQ, normCoin) ||
            (normName.isNotEmpty && _isSubsequence(normQ, normName)))) {
      return 4;
    }
    return kNoMatch;
  }

  final ranked = <MapEntry<HlMarket, int>>[];
  var visited = 0;
  int compareHits(MapEntry<HlMarket, int> a, MapEntry<HlMarket, int> b) {
    if (a.value != b.value) return a.value.compareTo(b.value);
    return b.key.dayNtlVlm.compareTo(a.key.dayNtlVlm);
  }

  for (final m in all) {
    if (++visited % 64 == 0) {
      await Future<void>.delayed(Duration.zero);
      if (isDisposed()) return const [];
    }
    final r = rankOf(m);
    if (r != kNoMatch) {
      ranked.add(MapEntry(m, r));
      ranked.sort(compareHits);
      if (ranked.length > _kHlSearchCap) ranked.removeLast();
    }
  }

  return [
    for (final e in ranked.take(_kHlSearchCap))
      HlMarketSearchResult(
        coin: e.key.coin,
        wireCoin: e.key.wireCoin,
        kind: e.key.kind,
        isStock: isHlStockMarket(e.key),
        name: _kHlSymbolNames[e.key.coin.toUpperCase()],
        category: e.key.category,
        iconUrl: e.key.iconUrl,
        markPx: e.key.markPx,
        dayChangePct: e.key.dayChangePct,
        maxLeverage: e.key.isSpot ? null : e.key.offeredMaxLeverage,
        pxDecimalCap: e.key.pxDecimalCap,
        unitAssetName: e.key.unitAssetName,
        market: e.key,
      ),
  ];
}

/// Whether [query] names an Investing market outright, from what is on the
/// device: a ticker or friendly name typed in full, a curated alias
/// ("tesla", "s&p"), or the start of a friendly name (three letters or
/// more). Search uses it to put markets above activity for the query; it
/// never waits for the remote leg.
bool hlQueryNamesMarket(String query, Iterable<HlMarket> universe) {
  final normQ = _normalizeToken(query);
  if (normQ.isEmpty) return false;
  if (_aliasTargets(query, normQ).isNotEmpty) return true;
  for (final entry in _kHlSymbolNames.entries) {
    final symbol = _normalizeToken(entry.key);
    final name = _normalizeToken(entry.value);
    if (symbol == normQ || name == normQ) return true;
    if (normQ.length >= 3 && name.startsWith(normQ)) return true;
  }
  for (final m in universe) {
    if (_normalizeToken(m.coin) == normQ) return true;
  }
  return false;
}

/// Lowercase [s] and strip every non-alphanumeric char, so "S&P 500" →
/// "sp500" and "s&p" → "sp". Applied to the query, coin symbols and friendly
/// names alike so punctuation / short forms line up (mirrors the backend's
/// normalizeToken).
String _normalizeToken(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Resolve the curated alias map for a query into the SET of NORMALIZED
/// target symbols it should surface. Checks the whole normalized query
/// ("s&p 500" → "sp500") and each word token ("tesla" inside "buy tesla").
Set<String> _aliasTargets(String rawQ, String normQ) {
  final out = <String>{};
  void add(String key) {
    final syms = _kHlSearchAliases[key];
    if (syms == null) return;
    for (final s in syms) {
      out.add(_normalizeToken(s));
    }
  }

  if (normQ.isNotEmpty) add(normQ);
  for (final tok in rawQ.toLowerCase().split(RegExp(r'[^a-z0-9]+'))) {
    if (tok.isNotEmpty) add(_normalizeToken(tok));
  }
  return out;
}

/// True when every char of [needle] appears in [haystack] in order (not
/// necessarily contiguous) — a cheap typo-tolerant fuzzy check.
bool _isSubsequence(String needle, String haystack) {
  if (needle.isEmpty) return true;
  var i = 0;
  for (var j = 0; j < haystack.length && i < needle.length; j++) {
    if (needle.codeUnitAt(i) == haystack.codeUnitAt(j)) i++;
  }
  return i == needle.length;
}

/// Curated alias map (NORMALIZED query token → target base symbol[s]) so
/// common short forms / natural names resolve to the right ticker even when
/// they share no substring with it. Kept in lock-step with the backend's
/// `searchAliases` (internal/hyperliquid/markets.go). Targets are matched
/// against a market's normalized coin symbol, so listing a symbol absent
/// from the loaded universe is harmless.
const Map<String, List<String>> _kHlSearchAliases = {
  // S&P 500 — snp/s&p/sandp/sp/sp500/spx → the index (SPX/SP500) + ETF (SPY).
  'snp': ['SPX', 'SP500', 'SPY'],
  'sandp': ['SPX', 'SP500', 'SPY'],
  'sp': ['SPX', 'SP500', 'SPY'],
  'sp500': ['SPX', 'SP500', 'SPY'],
  'spx': ['SPX', 'SP500', 'SPY'],
  'snp500': ['SPX', 'SP500', 'SPY'],
  'standardandpoors': ['SPX', 'SP500', 'SPY'],
  // Nasdaq / Dow.
  'nasdaq': ['QQQ', 'NDX'],
  'ndx': ['QQQ', 'NDX'],
  'dow': ['DJI', 'DIA'],
  'djia': ['DJI', 'DIA'],
  'dowjones': ['DJI', 'DIA'],
  // Tokenized equities.
  'tesla': ['TSLA'],
  'apple': ['AAPL'],
  'google': ['GOOGL'],
  'alphabet': ['GOOGL'],
  'nvidia': ['NVDA'],
  'microsoft': ['MSFT'],
  'amazon': ['AMZN'],
  'meta': ['META'],
  'facebook': ['META'],
  'netflix': ['NFLX'],
  'coinbase': ['COIN'],
  'robinhood': ['HOOD'],
  'palantir': ['PLTR'],
  'microstrategy': ['MSTR'],
  'strategy': ['MSTR'],
  'circle': ['CRCL'],
  'intel': ['INTC'],
  // Commodities.
  'gold': ['GLD', 'XAUT0', 'PAXG'],
  'silver': ['SLV'],
  // Crypto majors (natural names → tickers).
  'bitcoin': ['BTC'],
  'ether': ['ETH'],
  'ethereum': ['ETH'],
  'solana': ['SOL'],
  'ripple': ['XRP'],
  'dogecoin': ['DOGE'],
  'cardano': ['ADA'],
  'avalanche': ['AVAX'],
  'chainlink': ['LINK'],
  'polkadot': ['DOT'],
  'polygon': ['MATIC'],
  'litecoin': ['LTC'],
  'hyperliquid': ['HYPE'],
  'dogwifhat': ['WIF'],
  'pepe': ['PEPE'],
};

/// Symbol → friendly name so a natural-language query ("apple", "gold",
/// "robinhood") resolves to its Hyperliquid ticker in the client-side
/// fallback, and so a matched row shows a human name in parens. Covers the
/// tokenized-equity set ([kHlStockSymbols]) plus the top crypto majors.
const Map<String, String> _kHlSymbolNames = {
  // Crypto majors.
  'BTC': 'Bitcoin',
  'ETH': 'Ethereum',
  'SOL': 'Solana',
  'XRP': 'XRP',
  'DOGE': 'Dogecoin',
  'HYPE': 'Hyperliquid',
  'SUI': 'Sui',
  'AVAX': 'Avalanche',
  'LINK': 'Chainlink',
  'LTC': 'Litecoin',
  'BNB': 'BNB',
  'ADA': 'Cardano',
  'TRX': 'TRON',
  'DOT': 'Polkadot',
  'MATIC': 'Polygon',
  'ARB': 'Arbitrum',
  'OP': 'Optimism',
  'ATOM': 'Cosmos',
  'NEAR': 'Near',
  'APT': 'Aptos',
  'PEPE': 'Pepe',
  'WIF': 'dogwifhat',
  'BONK': 'Bonk',
  // Tokenized equities / commodity proxies (kHlStockSymbols).
  'AAPL': 'Apple',
  'AMD': 'AMD',
  'AMZN': 'Amazon',
  'COIN': 'Coinbase',
  'CRCL': 'Circle',
  'GLD': 'Gold',
  'GOOGL': 'Google',
  'HOOD': 'Robinhood',
  'INTC': 'Intel',
  'META': 'Meta',
  'MSFT': 'Microsoft',
  'MSTR': 'Strategy',
  'NFLX': 'Netflix',
  'NVDA': 'Nvidia',
  'PLTR': 'Palantir',
  'QQQ': 'Nasdaq 100',
  'SLV': 'Silver',
  'SPY': 'S&P 500',
  'TSLA': 'Tesla',
  'XAUT0': 'Tether Gold',
};
