// The order search results are shown in, kept apart from the sheet so it
// can be tested without a widget tree.
//
// Investing puts the market the person named first: an exact ticker or
// name ("btc" puts the BTC market on top), then names that start with what
// was typed, then the rest, the venue order (already by volume) kept within
// each step.
//
// Predictions puts the markets ABOUT what was typed first (founder, 12
// November 2026: "porto" listed the Champions League winner, where Porto
// is one of 36 teams, above Porto's own games). Each event is placed by
// where the words match, whole words before word starts, accents and case
// ignored, "fc porto" as "porto", a localized name ("brasil") as its
// English rewrite too (search_aliases.dart):
//   1. the title ("FC Porto vs. USC Paredes", "Will FC Porto win…?");
//   2. a game's teams or outcomes (a 2- or 3-way game);
//   3. the event's tags or slug ("primeira liga");
//   4. one outcome among many ("UEFA Champions League: 2027 Champion",
//      Porto one of the teams): the row then shows that outcome's chance
//      ([predictionMatchedOutcome]);
//   5. nothing whole (Gamma matched a description or a substring).
// Within a step: a game in play first, then the games still to play,
// soonest first, then the most traded (the event's total volume), then the
// soonest to end, the venue's order for ties. The order only depends on
// the results themselves, so a list never reshuffles while it is on screen.

import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/hyperliquid_search_provider.dart'
    show HlMarketSearchResult;
import 'package:kute/screens/hyperliquid/components/hl_format.dart'
    show hlFriendlyName;
import 'package:kute/services/polymarket/search_aliases.dart';

/// Rows a section shows under the All filter before its "See all".
const int kSearchSectionCap = 3;

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

/// Words of [s] for matching: accent-folded, lower case, split on anything
/// that is not a letter or a digit.
List<String> _words(String s) => polySearchFold(s)
    .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
    .where((w) => w.isNotEmpty)
    .toList();

/// The word lists a query is matched as: as typed and, for a localized
/// name, its English rewrite; a club tag ("fc porto") left out while
/// another word remains.
List<List<String>> _queryVariants(String query) {
  final out = <List<String>>[];
  for (final q in [query, polySearchAlias(query)]) {
    if (q == null) continue;
    var words = _words(q);
    final named = words.where((w) => !kPolyClubTags.contains(w)).toList();
    if (named.isNotEmpty) words = named;
    if (words.isNotEmpty &&
        !out.any((o) => o.join(' ') == words.join(' '))) {
      out.add(words);
    }
  }
  return out;
}

/// 0 when every word of [query] is a whole word of [haystack], 1 when
/// every one at least starts a word there (typing "port" finds Porto,
/// never "report"), null otherwise.
int? _wordMatch(List<String> query, Set<String> haystack) {
  var quality = 0;
  for (final w in query) {
    if (haystack.contains(w)) continue;
    if (!haystack.any((h) => h.startsWith(w))) return null;
    quality = 1;
  }
  return quality;
}

/// A game between teams (or players): Gamma's teams or game id, or a
/// "Team A vs. Team B" title.
bool _isGame(PolymarketEvent e) =>
    e.teams.isNotEmpty || e.gameId != null || e.looksLikeMatchup;

/// Steps of [_predictionMatch], best first.
const int _kTitle = 0, _kGame = 1, _kTags = 2, _kOutcome = 3, _kNone = 4;

/// Where [query] matches [e] (the step, then 0 for whole words, 1 for word
/// starts) and, for a match on one outcome among many, that outcome.
({int step, int quality, PolymarketOutcome? outcome}) _predictionMatch(
    List<List<String>> variants, PolymarketEvent e) {
  var best = (step: _kNone, quality: 0, outcome: null as PolymarketOutcome?);
  if (variants.isEmpty) return best;
  final title = {..._words(e.title), ..._words(e.displayTitle)};
  final game = _isGame(e)
      ? {
          ...title,
          for (final t in e.teams) ...[
            ..._words(t.name),
            ..._words(t.alias ?? ''),
            ..._words(t.abbreviation ?? ''),
          ],
          for (final o in e.outcomes) ..._words(o.name),
        }
      : null;
  final tags = {
    ...title,
    for (final t in e.tags) ..._words(t),
    ..._words(e.slug),
  };
  void consider(int step, int? quality, [PolymarketOutcome? outcome]) {
    if (quality == null) return;
    if (step < best.step || (step == best.step && quality < best.quality)) {
      best = (step: step, quality: quality, outcome: outcome);
    }
  }

  for (final q in variants) {
    consider(_kTitle, _wordMatch(q, title));
    if (game != null) consider(_kGame, _wordMatch(q, game));
    consider(_kTags, _wordMatch(q, tags));
    if (best.step <= _kTags || e.isBinary) continue;
    for (final o in e.outcomes) {
      consider(
          _kOutcome,
          _wordMatch(q, {
            ...title,
            ..._words(o.name),
            ..._words(o.question ?? ''),
          }),
          o);
    }
  }
  return best;
}

/// The outcome a Predictions row shows when [query] matches [e] only
/// through one outcome among many ("porto" in "UEFA Champions League:
/// 2027 Champion" is Porto's 2%, not the leader's 24%); null when the
/// event itself is about it, or nothing in it matches whole.
PolymarketOutcome? predictionMatchedOutcome(String query, PolymarketEvent e) {
  final m = _predictionMatch(_queryVariants(query), e);
  return m.step == _kOutcome ? m.outcome : null;
}

/// Predictions hits for [query], the events about it first (see the file
/// header): by where it matches, then a game in play ([isLive], the live
/// feed's view; the event's own in-play flag without it), then the games
/// still to play, soonest first, then the most traded (the event's total
/// volume), then the soonest to end, the list's own order for ties.
List<T> rankPredictionResults<T>(List<T> results,
    PolymarketEvent Function(T) eventOf,
    {String query = '', bool Function(T)? isLive, DateTime? now}) {
  final at = now ?? DateTime.now();
  final variants = _queryVariants(query);
  final keys = [
    for (final r in results)
      () {
        final e = eventOf(r);
        final m = _predictionMatch(variants, e);
        final kickoff = e.kickoff;
        return (
          match: m.step * 2 + m.quality,
          live: isLive?.call(r) ?? e.isInPlay,
          upcoming: kickoff != null && kickoff.isAfter(at) && _isGame(e)
              ? kickoff
              : null,
          volume: e.volume,
          end: e.endDate,
        );
      }(),
  ];
  final indexed = results.indexed.toList()
    ..sort((a, b) {
      final ka = keys[a.$1], kb = keys[b.$1];
      if (ka.match != kb.match) return ka.match.compareTo(kb.match);
      if (ka.live != kb.live) return ka.live ? -1 : 1;
      final ua = ka.upcoming, ub = kb.upcoming;
      if ((ua == null) != (ub == null)) return ua != null ? -1 : 1;
      if (ua != null && ub != null && ua != ub) return ua.compareTo(ub);
      final v = kb.volume.compareTo(ka.volume);
      if (v != 0) return v;
      final ea = ka.end, eb = kb.end;
      if ((ea == null) != (eb == null)) return ea != null ? -1 : 1;
      if (ea != null && eb != null && ea != eb) return ea.compareTo(eb);
      return a.$1.compareTo(b.$1);
    });
  return [for (final e in indexed) e.$2];
}
