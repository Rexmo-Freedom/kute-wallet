// The order search results are shown in, kept apart from the sheet so it
// can be tested without a widget tree.
//
// Investing puts the market the person named first: an exact ticker or
// name ("btc" puts the BTC market on top), then names that start with what
// was typed, then the rest, the venue order (already by volume) kept within
// each step. Predictions is ordered like polymarket.com: a game in play
// first, then the most traded (the event's total volume), the venue's
// relevance order for ties; no title re-ranking, Gamma already matched the
// titles and the candidate names. The order only depends on the results
// themselves, so a list never reshuffles while it is on screen.

import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/hyperliquid_search_provider.dart'
    show HlMarketSearchResult;
import 'package:kute/screens/hyperliquid/components/hl_format.dart'
    show hlFriendlyName;

/// Rows a section shows under the All filter before its "See all".
const int kSearchSectionCap = 4;

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// 0: the query is the whole ticker or name; 1: a ticker, name or word
/// starts with it; 2: anything else.
int _tier(String q, Iterable<String> names) {
  if (q.isEmpty) return 2;
  var tier = 2;
  for (final name in names) {
    final n = _norm(name);
    if (n.isEmpty) continue;
    if (n == q) return 0;
    if (n.startsWith(q)) tier = 1;
  }
  return tier;
}

/// Investing hits, exact ticker or name first, then prefixes, then the
/// rest; the venue's order (by volume) is kept within each step.
List<HlMarketSearchResult> rankInvestingResults(
    String query, List<HlMarketSearchResult> results) {
  final q = _norm(query);
  final tiers = {
    for (final r in results)
      r: _tier(q, [
        r.coin,
        if (r.name != null) r.name!,
        if (r.unitAssetName != null) r.unitAssetName!,
        if (hlFriendlyName(r.coin) case final String friendly) friendly,
      ]),
  };
  final indexed = results.indexed.toList()
    ..sort((a, b) {
      final t = tiers[a.$2]!.compareTo(tiers[b.$2]!);
      return t != 0 ? t : a.$1.compareTo(b.$1);
    });
  return [for (final e in indexed) e.$2];
}

/// Predictions hits: a game in play first ([isLive], the live feed's view;
/// the event's own in-play flag without it), then the most traded (the
/// event's total volume), the list's own order for ties.
List<T> rankPredictionResults<T>(List<T> results,
    PolymarketEvent Function(T) eventOf,
    {bool Function(T)? isLive}) {
  bool live(T r) => isLive?.call(r) ?? eventOf(r).isInPlay;
  final indexed = results.indexed.toList()
    ..sort((a, b) {
      final la = live(a.$2), lb = live(b.$2);
      if (la != lb) return la ? -1 : 1;
      final v = eventOf(b.$2).volume.compareTo(eventOf(a.$2).volume);
      return v != 0 ? v : a.$1.compareTo(b.$1);
    });
  return [for (final e in indexed) e.$2];
}
