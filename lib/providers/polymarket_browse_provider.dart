import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:kute/services/polymarket/polymarket_category_gate.dart';
import 'package:kute/services/polymarket/polymarket_feed_cache.dart';
import 'package:kute/services/polymarket/price_history_disk_cache.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/helpers/search_debounce.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/polymarket_watchlist_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    hide PolymarketConstants;

export 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show Comment, Tag;

final Map<String, TagSlug> _tagMap = {
  // Long-lived legacy category mappings used by hardcoded sub-trees
  // (Crypto → Bitcoin/Ethereum/…). The TOP-tab row is no longer
  // hardcoded — categorical pills are pulled at runtime from
  // `polymarketParentTagsProvider` so the list stays in sync with
  // whatever Polymarket surfaces on their own header.
  'crypto': TagSlug.crypto,
  'sports': TagSlug.sports,
  'politics': TagSlug.politics,
  'science': TagSlug.science,
  'business': TagSlug.business,
  'entertainment': TagSlug.popCulture,
  'world': TagSlug.world,
  'tech': TagSlug.tech,
  // Crypto subs
  'bitcoin': TagSlug.bitcoin,
  'ethereum': TagSlug.ethereum,
  'solana': TagSlug.solana,
  'defi': TagSlug.defi,
  'nft': TagSlug.nft,
  // Politics subs
  'elections': TagSlug.election,
  'trump': TagSlug.trump,
  'congress': TagSlug.congress,
  'supreme-court': TagSlug.supremeCourt,
  // Sports subs
  'nba': TagSlug.nba,
  'nfl': TagSlug.nfl,
  'soccer': TagSlug.soccer,
  'ufc': TagSlug.ufc,
  'tennis': TagSlug.tennis,
  'golf': TagSlug.golf,
  'f1': TagSlug.f1,
  'mma': TagSlug.mma,
  // Entertainment subs
  'movies': TagSlug.movies,
  'music': TagSlug.music,
  'oscars': TagSlug.oscars,
  'streaming': TagSlug.streaming,
  // Business subs
  'fed': TagSlug.fed,
  'interest-rates': TagSlug.interestRates,
  'economy': TagSlug.economy,
  'ai': TagSlug.ai,
  // Science subs
  'spacex': TagSlug.spacex,
  'nasa': TagSlug.nasa,
  'climate': TagSlug.climate,
  'space': TagSlug.space,
  // World subs
  'ukraine': TagSlug.ukraine,
  'russia': TagSlug.russia,
  'china': TagSlug.china,
  'israel': TagSlug.israel,
  'iran': TagSlug.iran,
  'middle-east': TagSlug.middleEast,
};

/// Holds an autoDispose provider alive for [duration] after its last listener
/// detaches, then releases it so it can refresh on the next read. Used by the
/// browse feeds so opening a market detail and returning does NOT tear the feed
/// provider down and refetch — which reset the list to a spinner and scrolled
/// the user back to the top ("after clicking a certain event the screen
/// resets"). The visible feed survives the round-trip; a genuine
/// navigate-away-and-come-back-later still refreshes after the window lapses.
void _cacheFor(Ref ref, Duration duration) {
  final link = ref.keepAlive();
  final timer = Timer(duration, link.close);
  ref.onDispose(timer.cancel);
}

const Duration _kFeedCacheWindow = Duration(minutes: 3);

final polymarketEventsProvider = FutureProvider.autoDispose
    .family<List<PolymarketEvent>, String?>((ref, category) async {
  // Survive a detail-sheet open/close so the feed isn't refetched + scrolled
  // to the top on return (FIX: event-tap state reset).
  _cacheFor(ref, _kFeedCacheWindow);
  final model = PolymarketModel();
  ref.onDispose(() => model.dispose());

  List<PolymarketEvent> events;
  if (category == 'breaking') {
    // Breaking = polymarket.com/breaking (biggest 24h movers).
    // The /biggest-movers endpoint occasionally returns empty
    // (rate-limit, deploy, etc.) — fall back to the standard
    // events listing sorted by 24h volume so the user always
    // sees SOMETHING on the default tab.
    events = await model.listBiggestMovers(limit: 80);
    events = events.where((e) => e.outcomes.isNotEmpty).toList();
    if (events.isEmpty) {
      final hot = await model.listEvents(
        hot: true,
        order: 'volume24hr',
        limit: 50,
        preserveApiOrder: false,
      );
      final withOutcomes = hot.where((e) => e.outcomes.isNotEmpty).toList();
      // Prefer a light $100 liquidity floor (matching the home baseline),
      // but never strand the tab empty: if the floor removes everything
      // (off-hours / thin markets) fall back to the unfiltered hot list so
      // Breaking always shows SOMETHING instead of a blank feed.
      final liquid = withOutcomes.where((e) => e.liquidity >= 100).toList();
      events = liquid.isNotEmpty ? liquid : withOutcomes;
    }
  } else if (category == 'quick') {
    // Quick tab: returns empty list — the polymarket_screen uses
    // kCryptoPredictAssets directly to show all crypto Up/Down banners.
    // These 5-min markets rotate too fast for event-based listing.
    events = [];
  } else if (category == 'trending') {
    // Trending mirrors Polymarket's web homepage: hit the Gamma API with
    // `hot=true` and keep the API's native order. The web trending tab
    // surfaces markets with the largest lifetime volume (not just 24h), so
    // we ask for `volume` ordering — our previous `volume24hr` sort pulled
    // flash-in-the-pan markets to the top that the website doesn't show.
    events = await model.listEvents(
      hot: true,
      order: 'volume',
      limit: 100,
      preserveApiOrder: true,
    );
    events = events.where((e) => e.liquidity >= 1000).toList();
  } else if (category == 'livestream') {
    // Livestream = events broadcasting right now: one read of the events
    // Gamma flags live, kept when they carry a stream (see
    // [readPolyLiveStreams]).
    events = await readPolyLiveStreams();
  } else if (category == null) {
    // Default home mix — excitement-sorted blend of sports + hot + general.
    // This is NOT the Live pill: it intentionally surfaces upcoming + trending
    // markets too (the home/default surface), ranked by `_excitementScore`.
    final results = await Future.wait([
      model.listEvents(tag: TagSlug.sports, limit: 60),
      model.listEvents(hot: true, limit: 30),
      model.listEvents(limit: 80),
    ]);

    final sportsEvents = results[0];
    final hotEvents = results[1];
    final generalEvents = results[2];

    final now = DateTime.now();
    final seenIds = <String>{};
    final allEvents = <PolymarketEvent>[];
    for (final e in [...sportsEvents, ...hotEvents, ...generalEvents]) {
      if (e.liquidity < 5000) continue;
      if (seenIds.add(e.id)) allEvents.add(e);
    }

    allEvents.sort((a, b) {
      final scoreA = _excitementScore(a, now);
      final scoreB = _excitementScore(b, now);
      return scoreB.compareTo(scoreA);
    });

    events = allEvents;
  } else if (category == 'live') {
    // Live pill = GENUINELY in-play games ONLY. The old branch (shared with
    // the home default) surfaced upcoming, not-started sports under "Live"
    // (user: "none of these are live"). Filter to the real in-play predicate
    // (`PolymarketEvent.isInPlay` — a live score/period is seeded AND the game
    // hasn't ended). If nothing is in play the list is legitimately short /
    // empty — we do NOT pad it with upcoming games mislabeled as live.
    final results = await Future.wait([
      model.listEvents(tag: TagSlug.sports, limit: 200),
      model.listEvents(hot: true, limit: 50),
    ]);
    final now = DateTime.now();
    final seenIds = <String>{};
    final inPlay = <PolymarketEvent>[];
    for (final e in [...results[0], ...results[1]]) {
      if (!e.isInPlay) continue;
      if (seenIds.add(e.id)) inPlay.add(e);
    }
    // Hottest in-play game leads.
    inPlay.sort((a, b) {
      final scoreA = _excitementScore(a, now);
      final scoreB = _excitementScore(b, now);
      return scoreB.compareTo(scoreA);
    });
    events = inPlay;
  } else {
    final tag = _tagMap[category];
    final bool isDynamicTag = tag == null;
    if (tag != null) {
      events = await model.listEvents(tag: tag, limit: 200);
    } else {
      // Unknown to `_tagMap`. These are dynamic Gamma tags surfaced
      // by `polymarketParentTagsProvider` (Iran, Middle East,
      // Weather, Mentions, Esports, Geopolitics, etc.) — real
      // `tag_slug` values gamma accepts. Use as a tag scope, NOT a
      // free-text search (previous fallback to `searchEvents(category)`
      // returned unrelated events because it grepped event titles for
      // the slug string).
      events = await model.listEvents(
        tag: TagSlug.custom(category),
        limit: 200,
      );
    }
    // Liquidity gate. Hardcoded tags (Sports/Crypto/Politics) get the
    // strict 5k filter because high-volume markets dominate them.
    // Dynamic tags (Geopolitics, Iran, Weather, Mentions, Middle
    // East) are niche — many real, valid events sit at $500-$2k
    // liquidity. Filtering them out would leave the category empty,
    // which is worse than showing low-liquidity-but-relevant events.
    final floor = isDynamicTag ? 0 : 5000;
    events = events.where((e) => e.liquidity >= floor).toList();
    // Rank each category feed by HOTNESS so the most-active markets lead
    // instead of arriving in raw API order ("random" to the user). Prefer 24h
    // volume (recent activity); fall back to lifetime volume, then liquidity,
    // when 24h is missing/zero. Applies to BOTH dynamic Gamma tags and the
    // hardcoded `_tagMap` categories. The trending/breaking/live branches keep
    // their own bespoke sorts (handled above).
    events.sort((a, b) => _hotnessScore(b).compareTo(_hotnessScore(a)));
  }
  // Hide 5-minute crypto Up/Down markets from every browse list — the
  // Instant tab that surfaced them as a dedicated banner stack has
  // been removed, and the bare event-list rendering of them was
  // visually noisy (one row per 5-min window per asset, refreshing
  // constantly). Slug pattern matches `btc-updown-5m-…`,
  // `eth-updown-5m-…`, etc.
  events = events
      .where((e) => !RegExp(r'-updown-5m-').hasMatch(e.slug.toLowerCase()))
      .toList();

  // Hide events that can no longer be bet on — closed/inactive, or a binary
  // market already settled at ~0/1 (Gamma keeps `closed:false` for a while
  // after the outcome is effectively decided). Resolved markets reject new
  // orders, so surfacing them as something to bet on makes no sense.
  events = events.where((e) => !_isEventResolved(e)).toList();

  return _offeredUnderPolicy(ref, events);
});

/// Events streaming right now (Twitch / YouTube / Kick), most traded first:
/// one read of `events/keyset?live=true&closed=false&limit=100` (through
/// the Kute feed, whose cache is fine for this), kept when the event
/// carries a stream.
Future<List<PolymarketEvent>> readPolyLiveStreams() async {
  final model = PolymarketModel();
  try {
    final page = await PolymarketModel.readGammaKeysetPage(
      'events',
      const {'live': 'true', 'closed': 'false'},
      limit: 100,
    );
    final live = [
      for (final e in model.parseEventsRaw(page.rows))
        if (e.hasLivestream && !_isEventResolved(e)) e
    ];
    live.sort((a, b) => _hotnessScore(b).compareTo(_hotnessScore(a)));
    return live;
  } finally {
    model.dispose();
  }
}

/// [events] minus the categories the runtime policy withdraws here
/// (`polymarket.sports`, `polymarket.politics`); watched so the feed
/// re-evaluates when the policy changes. Held positions never come through
/// these feeds and keep their own providers.
List<PolymarketEvent> _offeredUnderPolicy(
        Ref ref, List<PolymarketEvent> events) =>
    polymarketEventsOffered(events, ref.watch(runtimeCapabilitiesProvider));

/// True when [e] can no longer be bet on: explicitly closed / inactive, or a
/// binary market whose price has effectively settled at ~0 / ~1 (trading is
/// over even if Gamma hasn't flipped `closed` yet).
bool _isEventResolved(PolymarketEvent e) {
  // `closed` is Gamma's reliable settlement flag and is safe to check FIRST:
  // Gamma only sets it on true settlement. A market like "US x Iran ceasefire
  // by …" comes back active:true, ended:false/null, endDate null-or-future, so
  // none of the other checks fire — only `closed` catches it. Keeping it ahead
  // of the live-in-play guard is fine because a live game never reads closed.
  if (e.closed) return true;
  if (!e.active) return true;
  // Explicit settlement always wins.
  if (e.ended) return true;

  // A live in-play game (score/period seeded, ended:false) must stay in the
  // feed even past its scheduled endDate and even at a lopsided price. Sports
  // games routinely run past endDate (injury time, OT, delayed kickoff), and a
  // ~0/1 mid-game price is a blowout, not a settled market. This mirrors the
  // screen's `!e.ended`-only rule and the detail sheet's `_allOutcomesResolved`
  // guard (`_isSportsMatchEvent && !_sportsGameEnded`).
  // `isInPlay` leaves out the periods of games that are not running
  // ("NS", "FT", "VFT", "CAN"), so a finished game past its endDate goes.
  if (e.isInPlay) return false;

  // Ended (resolution date passed) — "Ends in: Closed". No longer bettable.
  if (e.endDate != null && e.endDate!.isBefore(DateTime.now())) return true;
  // Do NOT infer "resolved" from a lopsided price. A longshot in an outright
  // (e.g. a 0.01% team in "Who will win the World Cup", whose No side sits at
  // ~99.99%) is a live, tradable market — not a settled one. The old
  // `maxP > 0.97` heuristic wrongly hid ~half the World Cup field (showed only
  // ~21 of ~48 teams). Real settlement is already caught above by !active /
  // ended / past-endDate, so a near-1 price alone must keep the market.
  return false;
}

/// Hotness rank for a category feed: most recent activity first. Uses 24h
/// volume when present (the truest "what's hot right now" signal), falling
/// back to lifetime volume, then liquidity, so a feed never collapses to raw
/// API order when 24h data is sparse.
double _hotnessScore(PolymarketEvent e) {
  if (e.volume24hr > 0) return e.volume24hr;
  if (e.volume > 0) return e.volume;
  return e.liquidity;
}

double _excitementScore(PolymarketEvent e, DateTime now) {
  double score = 0;

  // Genuinely in-play games (a live score/period) lead the "Live"/now feed.
  // Gamma's `live` flag fires pre-kickoff and is unreliable, so rank on the
  // real in-play signal instead.
  if (e.isInPlay) score += 2000;

  if (e.category == 'sports') score += 500;

  // Resolution-urgency bonus only applies to STARTED events. A future game
  // whose scheduled endDate is soon is NOT "about to resolve" — gating on
  // hasStarted stops an unstarted match from being ranked as maximum urgency.
  if (e.endDate != null && e.hasStarted) {
    final hoursLeft = e.endDate!.difference(now).inHours;
    if (hoursLeft >= 0 && hoursLeft < 1) {
      score += 1000; // ending within the hour — maximum urgency
    } else if (hoursLeft >= 0 && hoursLeft < 6) {
      score += 600;
    } else if (hoursLeft >= 0 && hoursLeft < 24) {
      score += 300;
    } else if (hoursLeft >= 0 && hoursLeft < 72) {
      score += 100;
    }
  }

  // Smaller "starting soon" bonus for an imminent upcoming game so it still
  // surfaces near the top without the (false) resolution-urgency weighting.
  final start = e.startDate;
  if (start != null && start.isAfter(now)) {
    final minutesToStart = start.difference(now).inMinutes;
    if (minutesToStart < 60) {
      score += 200;
    } else if (minutesToStart < 180) {
      score += 80;
    }
  }

  if (e.volume24hr > 100000) {
    score += 200;
  } else if (e.volume24hr > 50000) {
    score += 100;
  } else if (e.volume24hr > 10000) {
    score += 50;
  }

  if (e.volume > 0) {
    final ratio = e.volume24hr / e.volume;
    if (ratio > 0.2) {
      score += 300;
    } else if (ratio > 0.1) {
      score += 150;
    } else if (ratio > 0.05) {
      score += 50;
    }
  }

  final yesPrice = e.yesPrice;
  final closeness = 1.0 - (yesPrice - 0.5).abs() * 2;
  score += closeness * 100;

  score += (e.liquidity / 10000).clamp(0, 50);

  return score;
}

final polymarketSearchProvider = FutureProvider.autoDispose
    .family<List<PolymarketEvent>, String>((ref, query) async {
  if (query.trim().isEmpty) return [];

  final debounce = SearchDebounce(const Duration(milliseconds: 200));
  ref.onDispose(debounce.cancel);
  if (!await debounce.ready) return [];
  final model = PolymarketModel();
  ref.onDispose(() => model.dispose());
  final events = await model.searchEvents(query.trim());
  return _offeredUnderPolicy(
      ref,
      events
          .where((e) => e.liquidity >= 1000)
          .where((e) => !RegExp(r'-updown-5m-').hasMatch(e.slug.toLowerCase()))
          // Search bypassed the resolved filter entirely. `_serverSearch` hits
          // /public-search with events_status:'active', and a settled market stays
          // active:true for a while, so the server filter lets it through — this
          // client-side `_isEventResolved` (now keyed off the parsed `closed`
          // flag) is what removes it so a resolved market never opens a slip the
          // CLOB rejects.
          .where((e) => !_isEventResolved(e))
          .toList());
});

/// Events filtered by Gamma TAG ID — preferred over the slug-based
/// `polymarketEventsProvider` whenever a tag id is available (i.e.
/// the user tapped a dynamic Gamma pill). Slugs can be inconsistent
/// across Polymarket's data ("culture" is a tag in event metadata
/// but `tag_slug=culture` returns 0 events — the real slug is
/// `pop-culture`). Querying by `tag_id` bypasses that ambiguity
/// entirely.
final polymarketEventsByTagIdProvider = FutureProvider.autoDispose
    .family<List<PolymarketEvent>, int>((ref, tagId) async {
  // Same detail-open survival as polymarketEventsProvider (FIX: event-tap
  // state reset) — dynamic-tag feeds shouldn't refetch on detail return.
  _cacheFor(ref, _kFeedCacheWindow);
  try {
    // `/events/keyset` (cursor-paged, 100 rows per page; the helper walks
    // two pages for the 200 asked here) — the offset-paged `/events` is
    // being deprecated. `listEvents` has no tag_id parameter, so the raw
    // rows are fetched here and normalised through the model's parser via
    // `PolymarketModel.parseEventsRaw`.
    final body = await PolymarketModel.fetchGammaKeyset(
      'events',
      {
        'tag_id': '$tagId',
        'active': 'true',
        'closed': 'false',
        'order': 'volume24hr',
        'ascending': 'false',
      },
      limit: 200,
      timeout: const Duration(seconds: 12),
    );
    final model = PolymarketModel();
    ref.onDispose(() => model.dispose());
    final parsed = model.parseEventsRaw(body);
    return _offeredUnderPolicy(
        ref,
        parsed
            .where(
                (e) => !RegExp(r'-updown-5m-').hasMatch(e.slug.toLowerCase()))
            // Apply the same resolved-market filter the hardcoded-category feed
            // uses (polymarketEventsProvider). Without it, dynamic-tag tabs and
            // their See-all landing pages surfaced binary markets already settled
            // at ~0/1 (Gamma keeps closed:false for a while), so tapping Yes/No
            // opened a slip the CLOB would reject. Keeps both feed types consistent.
            .where((e) => !_isEventResolved(e))
            .toList());
  } catch (_) {
    return const [];
  }
});

/// Lazily fetches an event's team crests by slug. Used to backfill logos on
/// events that arrived without `teams` (the search API path drops them).
final polymarketEventTeamsProvider = FutureProvider.autoDispose
    .family<List<PolymarketTeam>, String>((ref, slug) async {
  if (slug.isEmpty) return const [];
  final model = PolymarketModel();
  ref.onDispose(() => model.dispose());
  return model.fetchEventTeams(slug);
});

/// Crest-first icon for a position, shared by every surface that renders
/// `pos.marketImage` (open-bets strip, position detail, home claim rows,
/// search rows, sold overlay). Gamma ships the generic league ball as every
/// sports sub-market's icon, so the raw field is useless there — the real
/// crests live in the event's `teams`, re-fetched by slug (cached
/// autoDispose family; a handful of positions won't cause a fetch storm).
///
/// Matching order:
///   1. Held outcome vs team names ("Portugal" — moneyline bets). Skipped
///      for bare "Yes"/"No" outcomes: logoFromTeams' substring fuzz matches
///      "no" inside team NAMES (Norway, Nottingham…), which would hijack
///      the crest from the question pass that knows the actual team.
///   2. Question text ("Will Portugal win…?" — Yes/No sub-market bets).
///   3. The raw `marketImage` (correct for non-sports markets).
///
/// [listen] false uses ref.read for one-shot contexts (async callbacks)
/// where watching would leak a subscription.
String? positionCrestImage(WidgetRef ref, PolymarketPosition pos,
    {bool listen = true}) {
  final slug = pos.eventSlug;
  if (slug != null && slug.isNotEmpty) {
    final teamsAsync = listen
        ? ref.watch(polymarketEventTeamsProvider(slug))
        : ref.read(polymarketEventTeamsProvider(slug));
    final teams = teamsAsync.valueOrNull ?? const <PolymarketTeam>[];
    final o = pos.outcome.toLowerCase();
    final crest = ((o == 'yes' || o == 'no')
            ? null
            : PolymarketEvent.logoFromTeams(teams, pos.outcome)) ??
        PolymarketEvent.logoForText(teams, pos.marketQuestion);
    if (crest != null && crest.isNotEmpty) return crest;
  }
  return pos.marketImage;
}

/// [positionCrestImage]'s twin for raw Data-API [Activity] records — the
/// "Placed/Sold/Won/Lost prediction" feed rows. Same ball problem, same
/// matching order (outcome → question text → raw icon), same Yes/No guard.
String? activityCrestIcon(WidgetRef ref, Activity activity,
    {bool listen = true}) {
  final slug = activity.eventSlug;
  if (slug != null && slug.isNotEmpty) {
    final teamsAsync = listen
        ? ref.watch(polymarketEventTeamsProvider(slug))
        : ref.read(polymarketEventTeamsProvider(slug));
    final teams = teamsAsync.valueOrNull ?? const <PolymarketTeam>[];
    final o = (activity.outcome ?? '').toLowerCase();
    final crest = ((o.isEmpty || o == 'yes' || o == 'no')
            ? null
            : PolymarketEvent.logoFromTeams(teams, activity.outcome!)) ??
        PolymarketEvent.logoForText(teams, activity.title ?? '');
    if (crest != null && crest.isNotEmpty) return crest;
  }
  return activity.icon;
}

/// Top-level navigation tags pulled live from Polymarket Gamma. Caches
/// for the lifetime of the autoDispose ref (~5 min in practice). We
/// filter by `forceShow == true` because Polymarket marks the
/// rotating top-nav tags (Trending hot topics like "Iran", "Israel",
/// stable category tags like "Sports" / "Crypto") with that flag —
/// non-displayable tags get hidden.
final polymarketParentTagsProvider =
    StreamProvider.autoDispose<List<Tag>>((ref) async* {
  // The last tag list paints at once; the live one replaces it.
  final cached = PolymarketFeedCache.instance.readTagRows(_kParentTagsKey);
  if (cached != null) {
    yield _tagsOfferedUnderPolicy(ref, cached.map(Tag.fromJson).toList());
  }
  // Gamma's `/tags` endpoint returns only `id/label/slug/createdAt/
  // updatedAt/requiresTranslation` — there is NO `eventCount` field
  // (the polybrainz `Tag.eventCount` always parses as null). Filtering
  // on `eventCount > 0` previously rejected EVERY tag and left the
  // dynamic top-tab row empty (the user's "no categories at all"
  // report).
  //
  // Workaround: derive a "popular categories" list by hitting
  // `/events` with no tag scope, aggregating which tags actually
  // appear on the currently-active events, and surfacing the top-N by
  // co-occurrence frequency. This is the same heuristic used for the
  // sub-pivot fallback (`_deriveRelatedFromCooccurrence`) and gives a
  // self-maintaining list of whatever Polymarket is actually showing
  // today.
  try {
    // `/events/keyset` (two 100-row pages) in place of the deprecated
    // offset-paged `/events`.
    final body = await PolymarketModel.fetchGammaKeyset(
      'events',
      {
        'active': 'true',
        'closed': 'false',
        'order': 'volume24hr',
        'ascending': 'false',
      },
      limit: 60,
      timeout: const Duration(seconds: 12),
    );

    final counts = <int, ({Tag tag, Map<String, dynamic> raw, int n})>{};
    for (final raw in body) {
      final tags = raw['tags'];
      if (tags is! List) continue;
      for (final t in tags) {
        if (t is! Map<String, dynamic>) continue;
        final id = int.tryParse(t['id']?.toString() ?? '');
        final slug = t['slug']?.toString();
        final label = t['label']?.toString();
        if (id == null || slug == null || label == null) continue;
        if (!_isPivotCandidate(slug)) continue; // strip rewards-*, admin slugs
        // Strip players / specific entities.
        if (!_looksCategorical(label, slug)) continue;
        final entry = counts[id];
        if (entry == null) {
          counts[id] = (tag: Tag.fromJson(t), raw: t, n: 1);
        } else {
          counts[id] = (tag: entry.tag, raw: entry.raw, n: entry.n + 1);
        }
      }
    }
    final ranked = counts.values.toList()..sort((a, b) => b.n.compareTo(a.n));
    final top = ranked.take(30).toList();
    unawaited(PolymarketFeedCache.instance
        .writeTagRows(_kParentTagsKey, top.map((r) => r.raw).toList()));
    yield _tagsOfferedUnderPolicy(ref, top.map((r) => r.tag).toList());
  } catch (_) {
    if (cached == null) yield const [];
  }
});

const String _kParentTagsKey = 'parent_tags';

/// The browse pills minus the ones whose tag names a category the policy
/// withdraws (Sports, Politics, Elections and every league), so a hidden
/// category has no empty pill left behind.
List<Tag> _tagsOfferedUnderPolicy(Ref ref, List<Tag> tags) {
  final policy = ref.watch(runtimeCapabilitiesProvider);
  return [
    for (final t in tags)
      if (polymarketTagOffered(t.slug ?? '', policy)) t
  ];
}

/// Heuristic: does this tag look like a top-level CATEGORY (Politics,
/// Sports, Iran, Geopolitics) versus a specific entity tag (a player
/// like `caitlin-clark`, a club like `viktoria-plzen`, an event like
/// `jerry-after-dark`)? Polymarket has thousands of "tags" but only a
/// few dozen are real top-nav categories.
///
/// Rules — kept simple and aggressive (false-negatives are fine; we
/// still discover specific entities via sub-pivot drill-in):
///   * Categories are SHORT — label ≤ 14 chars
///   * Categories are usually 1-2 words
///   * Slug must look like a category (no proper-noun cadence) —
///     reject slugs that contain two+ hyphens (typical of names like
///     `sam-bankman-fried`, `caitlin-clark`)
bool _looksCategorical(String label, String slug) {
  final trimmed = label.trim();
  if (trimmed.isEmpty) return false;
  if (trimmed.length > 14) return false;
  final wordCount = trimmed.split(RegExp(r'\s+')).length;
  if (wordCount > 2) return false;
  // 3+ hyphens in slug = almost always a multi-word proper noun
  // (`sam-bankman-fried`, `2026-fifa-world-cup`).
  if ('-'.allMatches(slug).length >= 2) return false;
  // Pure digits / starts with digit = year tag, edition number, etc.
  if (RegExp(r'^\d').hasMatch(slug)) return false;
  return true;
}

// (The existing `polymarketRelatedTagsProvider` further down the
// file is the sub-tag fetcher we use; the duplicate definition that
// was here is removed.)

/// Sample resolution (minutes per point) per CLOB `interval`. A flat
/// fidelity turned short windows into a handful of points; each window
/// gets enough samples to draw a real line (~60-240 points) without
/// pulling minute-level data for multi-month histories. Pure function
/// of the interval, so the (tokenId, interval) family key stays a
/// correct cache key.
int _fidelityForInterval(String interval) {
  switch (interval) {
    case '1h':
      return 1;
    case '6h':
      // One-minute points: a game fits in this range, and its event
      // markers are read against the odds minute by minute.
      return 1;
    case '1d':
      return 10;
    case '1w':
      return 60;
    case '1m':
      return 180;
    default: // 'max'
      return 720;
  }
}

/// A range's series must have at least this many points before its
/// default grain is kept.
const int _kHistoryMinPoints = 24;

/// Finer grains (minutes per point) to fall back on when a range's own
/// grain leaves too few points to draw: ALL reads 12-hour points, so a
/// market opened this morning came back as one point per outcome and the
/// chart had no line at all.
List<int> _finerFidelities(String interval) => switch (interval) {
      'max' || '1m' => const [60, 10],
      '1w' => const [10],
      '1d' => const [1],
      _ => const [],
    };

/// How far back each range reads; null for ALL (the market's whole life).
Duration? _rangeLookback(String interval) => switch (interval) {
      '1h' => const Duration(hours: 1),
      '6h' => const Duration(hours: 6),
      '1d' => const Duration(days: 1),
      '1w' => const Duration(days: 7),
      '1m' => const Duration(days: 30),
      _ => null,
    };

/// The grain a market [age] old can be read at first on [interval]: the
/// coarsest whose points over the market's life (or the range, when
/// shorter) reach [_kHistoryMinPoints], so a young market does not wait
/// on reads it is sure to throw away. Null when the range's own grain is
/// that one (or the age is unknown).
@visibleForTesting
int? polyHistoryFirstUsefulFidelity(String interval, Duration? age) {
  if (age == null || age.isNegative) return null;
  final lookback = _rangeLookback(interval);
  final span = lookback != null && lookback < age ? lookback : age;
  final ladder = [_fidelityForInterval(interval), ..._finerFidelities(interval)];
  for (final f in ladder) {
    if (span.inMinutes / f >= _kHistoryMinPoints) {
      return f == ladder.first ? null : f;
    }
  }
  return ladder.length > 1 ? ladder.last : null;
}

/// One range of one outcome's history through [read] (minutes per point
/// → points, null on failure): the range's own grain, then finer ones
/// while the series stays under [_kHistoryMinPoints] points and a finer
/// read has more. Old markets take one read, as before. Null only when
/// the first read failed.
///
/// With the market's [age], a market too young for the coarser grains to
/// draw starts at the first grain that can ([polyHistoryFirstUsefulFidelity]):
/// one read where the ladder took two or three in a row. Those coarser
/// reads hold fewer points than the minimum by construction, so the ladder
/// would have passed them; when the first read still comes back short,
/// the ladder runs as before.
Future<List<PolymarketPricePoint>?> readPolyHistoryAdaptive(
  String interval,
  Future<List<PolymarketPricePoint>?> Function(int fidelity) read, {
  Duration? age,
}) async {
  final first = polyHistoryFirstUsefulFidelity(interval, age);
  if (first != null) {
    final points = await read(first);
    final enough = first == _finerFidelities(interval).lastOrNull
        ? (points?.length ?? 0) >= 2
        : (points?.length ?? 0) >= _kHistoryMinPoints;
    if (points != null && enough) return points;
  }
  var points = await read(_fidelityForInterval(interval));
  if (points == null) return null;
  for (final fidelity in _finerFidelities(interval)) {
    if (points!.length >= _kHistoryMinPoints) break;
    final finer = await read(fidelity);
    if (finer == null || finer.length <= points.length) continue;
    points = finer;
  }
  return points;
}

/// Session cache of `prices-history` seeds per (token, range), so the
/// market sheet, the position sheet and a range picked again reuse what
/// was read instead of fetching on every open. The provider below is
/// autoDispose, so without this every sheet open and every range switch
/// went back to the network.
///
///   * Fresh for [ttlFor] (short ranges expire fast: their newest points
///     move); past that and up to [_kHistoryStaleMax] the old series is
///     still drawn at once while a refresh runs.
///   * Identical reads share one request (a tap prefetch and the chart
///     mounting 300 ms later, or two sheets on one token).
///   * A read that has not answered in [_kHistoryHedgeAfter] gets a second
///     identical request and the first answer wins; a failed read is
///     retried once. The Data API now and then holds a request open for
///     minutes, which used to leave the chart on the skeleton for the full
///     15 s timeout and then on "no history".
///   * Failed or empty reads are not kept.
class PolyPriceHistoryCache {
  PolyPriceHistoryCache._();

  static const int _maxEntries = 64;
  static const Duration _kHistoryHedgeAfter = Duration(milliseconds: 2500);
  static const Duration _kHistoryAttemptTimeout = Duration(seconds: 10);
  static const Duration _kHistoryStaleMax = Duration(minutes: 30);

  static final Map<String, ({List<PolymarketPricePoint> points, DateTime at})>
      _entries = {};
  static final Map<String, Future<List<PolymarketPricePoint>?>> _inFlight = {};

  static String _key(String tokenId, String interval) => '$tokenId|$interval';

  /// When each token's market opened, where a sheet knows it: lets a young
  /// market's history skip the grains too coarse to draw it
  /// ([readPolyHistoryAdaptive]).
  static final Map<String, DateTime> _openedAt = {};

  /// Notes when [tokenId]'s market opened (Gamma `startDate`).
  static void noteOpened(String tokenId, DateTime? openedAt) {
    if (tokenId.isEmpty || openedAt == null) return;
    if (_openedAt.length > 512) _openedAt.remove(_openedAt.keys.first);
    _openedAt[tokenId] = openedAt;
  }

  /// How long a read stays fresh. Roughly one bucket of the range's own
  /// grain, so a cached series is never visibly behind the live tape.
  static Duration ttlFor(String interval) {
    switch (interval) {
      case '1h':
        return const Duration(seconds: 30);
      case '6h':
        return const Duration(minutes: 1);
      case '1d':
        return const Duration(minutes: 2);
      case '1w':
        return const Duration(minutes: 5);
      case '1m':
        return const Duration(minutes: 15);
      default: // 'max'
        return const Duration(minutes: 30);
    }
  }

  static ({List<PolymarketPricePoint> points, DateTime at})? _entry(
      String tokenId, String interval) {
    final key = _key(tokenId, interval);
    final hit = _entries[key];
    if (hit == null) return null;
    if (DateTime.now().difference(hit.at) > _kHistoryStaleMax) {
      _entries.remove(key);
      return null;
    }
    return hit;
  }

  /// The cached series when it is still fresh.
  static List<PolymarketPricePoint>? fresh(String tokenId, String interval) {
    final hit = _entry(tokenId, interval);
    if (hit == null) return null;
    return DateTime.now().difference(hit.at) <= ttlFor(interval)
        ? hit.points
        : null;
  }

  /// The cached series, fresh or not (within [_kHistoryStaleMax]).
  static List<PolymarketPricePoint>? any(String tokenId, String interval) =>
      _entry(tokenId, interval)?.points;

  /// Warms the cache for a chart about to open: starts the read and, when
  /// this session has no copy, the read of the series an earlier session
  /// saved ([fromDisk]). No-op when fresh or already loading.
  static void prefetch(String tokenId, String interval) {
    if (tokenId.isEmpty || fresh(tokenId, interval) != null) return;
    unawaited(load(tokenId, interval));
    if (any(tokenId, interval) == null) {
      unawaited(fromDisk(tokenId, interval));
    }
  }

  static final Map<String, Future<List<PolymarketPricePoint>?>> _diskReads =
      {};

  /// The series an earlier session saved for (token, range), young enough
  /// to draw while the read runs ([PolyPriceHistoryDiskCache]); null when
  /// there is none. Read from disk once per session per series.
  static Future<List<PolymarketPricePoint>?> fromDisk(
      String tokenId, String interval) {
    final key = _key(tokenId, interval);
    if (_diskReads.length > 128) _diskReads.clear();
    return _diskReads[key] ??= PolyPriceHistoryDiskCache.read(tokenId, interval)
        .then((saved) => saved?.points);
  }

  /// Reads (or joins the read of) one series. Null when every attempt
  /// failed.
  static Future<List<PolymarketPricePoint>?> load(
      String tokenId, String interval) {
    final key = _key(tokenId, interval);
    final running = _inFlight[key];
    if (running != null) return running;
    final future = _hedged(tokenId, interval).then((points) {
      if (points != null && points.isNotEmpty) {
        _entries.remove(key);
        if (_entries.length >= _maxEntries) {
          _entries.remove(_entries.keys.first);
        }
        final kept = List<PolymarketPricePoint>.unmodifiable(points);
        _entries[key] = (points: kept, at: DateTime.now());
        _diskReads.remove(key);
        unawaited(PolyPriceHistoryDiskCache.write(tokenId, interval, kept));
        return kept;
      }
      return points;
      // A block, not an arrow: `remove` returns this very future, and a
      // future returned from whenComplete is waited for, so the read
      // would wait on itself and never answer.
    }).whenComplete(() {
      _inFlight.remove(key);
    });
    _inFlight[key] = future;
    return future;
  }

  /// At most two attempts: the second starts when the first fails or has
  /// not answered after [_kHistoryHedgeAfter]; the first non-null answer
  /// wins.
  static Future<List<PolymarketPricePoint>?> _hedged(
      String tokenId, String interval) {
    final done = Completer<List<PolymarketPricePoint>?>();
    var launched = 0;
    var settled = 0;
    Timer? hedge;
    void launch() {
      if (launched >= 2 || done.isCompleted) return;
      launched++;
      final model = PolymarketModel();
      final opened = _openedAt[tokenId];
      readPolyHistoryAdaptive(
        interval,
        (fidelity) => model.fetchPriceHistory(
          tokenId,
          interval: interval,
          fidelity: fidelity,
          timeout: _kHistoryAttemptTimeout,
        ),
        age: opened == null ? null : DateTime.now().difference(opened),
      ).then((points) {
        settled++;
        if (done.isCompleted) return;
        if (points != null) {
          hedge?.cancel();
          done.complete(points);
        } else if (launched < 2) {
          hedge?.cancel();
          launch();
        } else if (settled >= launched) {
          done.complete(null);
        }
      }).whenComplete(model.dispose);
    }

    launch();
    hedge = Timer(_kHistoryHedgeAfter, launch);
    return done.future;
  }
}

/// One range of one outcome's history. Returns synchronously from the
/// session cache when it can (no loading frame), shows a stale cached
/// series while it refreshes, and otherwise waits for the read — or, when
/// an earlier session saved this series and the disk answers first, draws
/// that one while the read runs.
final polymarketMarketHistoryProvider = FutureProvider.autoDispose
    .family<List<PolymarketPricePoint>, ({String tokenId, String interval})>(
        (ref, params) {
  final fresh = PolyPriceHistoryCache.fresh(params.tokenId, params.interval);
  if (fresh != null) return fresh;
  final stale = PolyPriceHistoryCache.any(params.tokenId, params.interval);
  final loading = PolyPriceHistoryCache.load(params.tokenId, params.interval);
  var disposed = false;
  ref.onDispose(() => disposed = true);
  if (stale != null) {
    unawaited(loading.then((points) {
      if (!disposed && points != null && points.isNotEmpty) {
        ref.invalidateSelf();
      }
    }));
    return stale;
  }
  final first = Completer<List<PolymarketPricePoint>>();
  var drewSaved = false;
  unawaited(loading.then((points) {
    if (!first.isCompleted) {
      first.complete(points ?? const <PolymarketPricePoint>[]);
    } else if (drewSaved &&
        !disposed &&
        points != null &&
        points.isNotEmpty) {
      ref.invalidateSelf();
    }
  }));
  unawaited(PolyPriceHistoryCache.fromDisk(params.tokenId, params.interval)
      .then((saved) {
    if (saved != null && saved.length >= 2 && !first.isCompleted) {
      drewSaved = true;
      first.complete(saved);
    }
  }));
  return first.future;
});

/// A live tick departing this far (ten points of chance, the width of a
/// book Polymarket no longer prices by its midpoint) from the point
/// before it, and as far from the tick after it…
const double kPolyLiveOutlierJump = 0.10;

/// Whether a live [tick] between [before] and [after] is a one-off: it
/// jumps at least [kPolyLiveOutlierJump] away from both, and [after] is
/// back within max(2 points, a quarter of the jump) of [before]. That is a
/// thin book's quote for an instant (an order lifted and put back), not a
/// move; a move that stays is kept, and so is the newest tick, which has
/// nothing after it yet and is the price the list shows.
bool polyLiveTickIsOutlier(
    {required double? before, required double tick, required double after}) {
  if (before == null) return false;
  final jump = (tick - before).abs();
  final back = (tick - after).abs();
  if (jump < kPolyLiveOutlierJump || back < kPolyLiveOutlierJump) return false;
  if ((tick - before).sign != (tick - after).sign) return false;
  final least = jump < back ? jump : back;
  final band = least / 4 > 0.02 ? least / 4 : 0.02;
  return (after - before).abs() <= band;
}

final polymarketLiveChartProvider = NotifierProvider.autoDispose.family<
    LiveChartNotifier,
    List<PolymarketPricePoint>,
    ({String tokenId, String interval})>(
  LiveChartNotifier.new,
);

class LiveChartNotifier extends AutoDisposeFamilyNotifier<
    List<PolymarketPricePoint>, ({String tokenId, String interval})> {
  final List<PolymarketPricePoint> _ticks = [];
  int? _lastTickAt;

  @override
  List<PolymarketPricePoint> build(({String tokenId, String interval}) arg) {
    final history =
        ref.watch(polymarketMarketHistoryProvider(arg)).valueOrNull ??
            const <PolymarketPricePoint>[];
    final tick = ref.watch(livePriceProvider.select((s) => (
          price: s.prices[arg.tokenId],
          at: s.updatedAtMs[arg.tokenId],
          live: s.live,
          // A book wider than 10¢ that has not traded has no price to
          // show (shown_price.dart): the list writes "—", and the chart
          // draws no tick for it.
          unpriced: s.unpriced.contains(arg.tokenId),
        )));
    final at = tick.at;
    final price = tick.price;
    if (tick.live &&
        !tick.unpriced &&
        at != null &&
        at != _lastTickAt &&
        price != null &&
        price.isFinite &&
        price >= 0 &&
        price <= 1) {
      _lastTickAt = at;
      final point = PolymarketPricePoint(
          timestamp: DateTime.fromMillisecondsSinceEpoch(at), price: price);
      // Coalesce bursts within one second, retaining real observation times.
      if (_ticks.isNotEmpty &&
          at ~/ 1000 == _ticks.last.timestamp.millisecondsSinceEpoch ~/ 1000) {
        _ticks[_ticks.length - 1] = point;
      } else {
        // The tick before this one was a one-off (a thin book's midpoint
        // for a moment, not a move): it is not drawn.
        if (_ticks.isNotEmpty) {
          final before = _ticks.length >= 2
              ? _ticks[_ticks.length - 2].price
              : history.lastOrNull?.price;
          if (polyLiveTickIsOutlier(
              before: before, tick: _ticks.last.price, after: price)) {
            _ticks.removeLast();
          }
        }
        _ticks.add(point);
      }
      if (_ticks.length > 1800) _ticks.removeAt(0);
    }
    final lastHistory = history.lastOrNull?.timestamp;
    return [
      ...history,
      ..._ticks.where(
          (p) => lastHistory == null || p.timestamp.isAfter(lastHistory)),
    ];
  }
}

class PolymarketPosition {
  final String marketId;
  final String marketQuestion;
  final String? marketImage;
  final String outcome;
  final double size;
  final double avgPrice;
  final double currentPrice;
  final double pnl;
  final double pnlPercent;
  final bool isResolved;
  final bool? won;
  final DateTime? createdAt;
  final DateTime? resolvedAt;
  final String? tokenId;
  final String? eventSlug;
  final String? endDateStr;

  const PolymarketPosition({
    required this.marketId,
    required this.marketQuestion,
    this.marketImage,
    required this.outcome,
    required this.size,
    required this.avgPrice,
    required this.currentPrice,
    required this.pnl,
    required this.pnlPercent,
    required this.isResolved,
    this.won,
    this.createdAt,
    this.resolvedAt,
    this.tokenId,
    this.eventSlug,
    this.endDateStr,
  });
}

// NOTE: the old `_isSettledLoss(Position)` heuristic — classify a position as a
// resolved LOSS (and show a Clear button) when `curPrice <= 0.02` AND the
// scheduled `endDate` has passed — was removed. It produced false positives on
// LIVE markets: a sports game routinely runs past its scheduled endDate
// (stoppage time, overtime, delayed kickoff), and a losing side can trade at
// ~$0 while the match is still in play, so a not-yet-resolved position was
// shown as clearable (e.g. Morocco 2-0 down to France with 10' left, ~0.0125%,
// offered "Clear"). Price/time can NEVER prove on-chain resolution.
//
// Genuine resolution is authoritative only from two sources we already trust:
// `redeemable == true` (winners the Data API has confirmed) and
// `closedPositions` (the settled list). Losers therefore stay ACTIVE until the
// Data API settles them — where the "worthless positions" dust group surfaces
// them muted with "clear once their markets resolve" — instead of being faked
// into a resolved/clear card from price alone.

/// Under this many shares a position is dust worth under a cent whatever
/// the result, such as what a "sell all" leaves behind: a position sold
/// down to it is gone, never open and never claimable (the trading
/// provider never makes a claim of it either).
const double kPolyDustShares = 0.01;

final polymarketActivePositionsProvider =
    Provider.autoDispose<List<PolymarketPosition>>((ref) {
  final state = ref.watch(polymarketTradingProvider).valueOrNull;
  if (state == null || !state.isAuthenticated) return [];
  return state.openPositions
      .where((p) => !p.redeemable && p.size >= kPolyDustShares)
      .map((p) => PolymarketPosition(
            marketId: p.conditionId,
            marketQuestion: p.title,
            marketImage: p.icon,
            outcome: p.outcome,
            size: p.size,
            avgPrice: p.avgPrice,
            currentPrice: p.curPrice,
            pnl: p.cashPnl,
            pnlPercent: p.percentPnl,
            isResolved: false,
            tokenId: p.asset,
            eventSlug: p.eventSlug,
            endDateStr: p.endDate,
          ))
      .toList();
});

/// Resolved positions that are still claimable on-chain (open positions
/// with `redeemable: true`). These are winners the user hasn't claimed
/// yet — surfaced on the home rail with a "Claim" button.
final polymarketClaimablePositionsProvider =
    Provider.autoDispose<List<PolymarketPosition>>((ref) {
  final state = ref.watch(polymarketTradingProvider).valueOrNull;
  if (state == null || !state.isAuthenticated) return [];
  return state.openPositions
      .where((p) => p.redeemable && p.size >= kPolyDustShares)
      .map((p) => PolymarketPosition(
            marketId: p.conditionId,
            marketQuestion: p.title,
            marketImage: p.icon,
            outcome: p.outcome,
            size: p.size,
            avgPrice: p.avgPrice,
            currentPrice: p.curPrice,
            pnl: p.cashPnl,
            pnlPercent: p.percentPnl,
            isResolved: true,
            won: p.curPrice >= 0.99,
            tokenId: p.asset,
            eventSlug: p.eventSlug,
            endDateStr: p.endDate,
          ))
      .toList();
});

final polymarketResolvedPositionsProvider =
    Provider.autoDispose<List<PolymarketPosition>>((ref) {
  final state = ref.watch(polymarketTradingProvider).valueOrNull;
  if (state == null || !state.isAuthenticated) return [];

  final results = <PolymarketPosition>[];

  results.addAll(state.openPositions
      .where((p) => p.redeemable)
      .map((p) => PolymarketPosition(
            marketId: p.conditionId,
            marketQuestion: p.title,
            marketImage: p.icon,
            outcome: p.outcome,
            size: p.size,
            avgPrice: p.avgPrice,
            currentPrice: p.curPrice,
            pnl: p.cashPnl,
            pnlPercent: p.percentPnl,
            isResolved: true,
            won: p.curPrice >= 0.99,
            tokenId: p.asset,
            eventSlug: p.eventSlug,
            endDateStr: p.endDate,
          )));

  // Settled LOSSES are NOT synthesized from price/endDate anymore (that faked
  // resolved cards for live markets — see the note above). A lost bet stays in
  // the active list until the Data API moves it to `closedPositions` below,
  // which is the only authoritative "this market resolved" signal for losers.
  results.addAll(state.closedPositions.map((p) => PolymarketPosition(
        marketId: p.conditionId,
        marketQuestion: p.title,
        marketImage: p.icon,
        outcome: p.outcome,
        size: p.size,
        avgPrice: p.avgPrice,
        currentPrice: p.won ? 1.0 : 0.0,
        pnl: p.cashPnl,
        pnlPercent: p.percentPnl,
        isResolved: true,
        won: p.won,
        resolvedAt: p.resolutionDate,
        tokenId: p.asset,
        eventSlug: p.eventSlug,
      )));

  return results;
});

final polymarketEventDetailsProvider = FutureProvider.autoDispose
    .family<PolymarketEvent?, String>((ref, slug) async {
  if (slug.isEmpty) return null;
  final model = PolymarketModel();
  ref.onDispose(() => model.dispose());
  return model.getEventDetailsBySlug(slug);
});

/// Generic / admin / rewards-bookkeeping tags that never make a category
/// of the tags counted off the events themselves
/// ([polymarketParentTagsProvider]). They co-occur on most events as
/// auto-attached metadata, so without this filter they'd dominate the
/// top-N list. (A pill's subcategory row does not go through this: it is
/// Gamma's related tags as they come, so `science` shows under Tech.)
const Set<String> _kSubPivotBlacklist = {
  'all',
  'games',
  'sports',
  'world',
  'business',
  'science',
  'breaking',
  'breaking-news',
  'instant',
  'trending',
  'live',
  'featured',
  'hot',
  'new',
  '2024-predictions',
  '2025-predictions',
  '2026-predictions',
  'macro-graph',
  'macro-single',
  'macro-recurring',
  // Bookkeeping and market-shape tags Polymarket attaches to many events;
  // never a category to browse ("Recurring", "5M", "Up or Down", …).
  'recurring',
  'hide-from-new',
  'up-or-down',
  'multi-strikes',
  'neg-risk',
  'hit-price',
  'crypto-prices',
  '5m',
  '15m',
  '1h',
  '4h',
  'hourly',
  'today',
  'daily',
  'weekly',
  'monthly',
  'yearly',
  'parlays',
};

bool _isPivotCandidate(String? slug) {
  if (slug == null || slug.isEmpty) return false;
  if (_kSubPivotBlacklist.contains(slug.toLowerCase())) return false;
  // Rewards/automation/admin slug families ("rewards-50-4pt5-20",
  // "rewards-automation-100-4-50", "active-rewards", etc).
  if (slug.startsWith('rewards-') ||
      slug.startsWith('rewards_') ||
      slug.startsWith('active-rewards') ||
      slug.startsWith('weekly-rewards')) {
    return false;
  }
  return true;
}

// ─────────────────────────── browse taxonomy ───────────────────────────
//
// The Predictions screen browses the way polymarket.com's mobile layout
// does: a fixed row of category pills, a row of subcategory chips under
// the categories that have them. Every list pages through Gamma's keyset
// cursors as the person scrolls.
//
// Where each piece comes from (verified against the live APIs):
//   * Topic pills: one stable Gamma tag slug each ([PolyPill.tagSlugs]).
//   * Politics, Geopolitics, Tech, Culture, Economy subcategories: Gamma
//     `/tags/{id}/related-tags/tags` with `status=active&omit_empty=true`,
//     in its order (the order and labels of polymarket.com's own row).
//   * Crypto subcategories and counts: polymarket.com's crypto page
//     (`/api/crypto/counts`). Windows are the tags 15M / 1H / 4H / today;
//     Weekly / Monthly / Yearly and the assets are those tags on crypto
//     events; Targets, Institutions, Industry and Protocol Metrics are
//     sections the site computes, read here as the tags their events
//     carry ([polyFixedSubSource]).
//   * Finance and Weather subcategories: the site's own lists, each a
//     Gamma tag (or a few) ([polyFixedSubSource]).
//   * Sports: Live, Futures, the leagues with the most 24 h volume (Gamma
//     `/sports`: name, logo, series id), then the sports, each its tag.
//   * Esports: the games, each its tag, with logos from Gamma `/sports`.
//   * Breaking: polymarket.com `/api/biggest-movers`, the list the site's
//     /breaking page draws, with its topic filter.
//   * New: `order=startDate` without the tags polymarket.com/new leaves out
//     (hide-from-new, recurring, games).

/// Gamma tag ids the New list leaves out, as polymarket.com/new does:
/// `hide-from-new`, `recurring` and `games`.
const List<String> _kNewExcludedTagIds = ['102169', '101757', '100639'];

/// Gamma's `games` tag: one match. Sports "Futures" is Sports without it.
const String _kGamesTagId = '100639';

/// The category pills, in the order the row shows them: polymarket.com's
/// own categories, one pill each, plus Live. Watchlist shows only while
/// something is starred.
enum PolyPill {
  watchlist,
  trending,
  breaking,
  newest,
  live,
  politics,
  sports,
  crypto,
  esports,
  finance,
  geopolitics,
  tech,
  culture,
  economy,
  weather,
  mentions,
  elections,
}

extension PolyPillX on PolyPill {
  /// Analytics value and route segment (`predictions/<key>`).
  String get key => switch (this) {
        PolyPill.watchlist => 'watchlist',
        PolyPill.trending => 'trending',
        PolyPill.breaking => 'breaking',
        PolyPill.newest => 'new',
        PolyPill.live => 'live',
        PolyPill.politics => 'politics',
        PolyPill.sports => 'sports',
        PolyPill.crypto => 'crypto',
        PolyPill.esports => 'esports',
        PolyPill.finance => 'finance',
        PolyPill.geopolitics => 'geopolitics',
        PolyPill.tech => 'tech',
        PolyPill.culture => 'culture',
        PolyPill.economy => 'economy',
        PolyPill.weather => 'weather',
        PolyPill.mentions => 'mentions',
        PolyPill.elections => 'elections',
      };

  /// The Gamma tag slug a topic pill lists (Culture is `pop-culture`,
  /// Mentions `mention-markets`); empty for the others.
  List<String> get tagSlugs => switch (this) {
        PolyPill.politics => const ['politics'],
        PolyPill.sports => const ['sports'],
        PolyPill.crypto => const ['crypto'],
        PolyPill.esports => const ['esports'],
        PolyPill.finance => const ['finance'],
        PolyPill.geopolitics => const ['geopolitics'],
        PolyPill.tech => const ['tech'],
        PolyPill.culture => const ['pop-culture'],
        PolyPill.economy => const ['economy'],
        PolyPill.weather => const ['weather'],
        PolyPill.mentions => const ['mention-markets'],
        PolyPill.elections => const ['elections'],
        _ => const [],
      };

  /// The Gamma tag whose related tags are this pill's subcategories
  /// (polymarket.com draws its sub-navigation from the same read); null
  /// for the pills whose subcategories are the site's own lists.
  int? get relatedTagId => switch (this) {
        PolyPill.politics => 2,
        PolyPill.geopolitics => 100265,
        PolyPill.tech => 1401,
        PolyPill.culture => 596,
        PolyPill.economy => 100328,
        _ => null,
      };

  bool get isTopic => tagSlugs.isNotEmpty;

  /// The subcategory a pill opens on: Sports opens on the games in play,
  /// as polymarket.com/sports does; everything else on All.
  String get defaultSub => this == PolyPill.sports ? 'live' : 'all';

  /// The pill a route segment names. The pills that were split keep
  /// their old segments (`world`, `tech-culture`).
  static PolyPill? fromKey(String key) {
    for (final p in PolyPill.values) {
      if (p.key == key) return p;
    }
    return switch (key) {
      'world' => PolyPill.geopolitics,
      'tech-culture' => PolyPill.tech,
      'pop-culture' => PolyPill.culture,
      _ => null,
    };
  }
}

/// Whether [pill] may be offered under [policy]: a pill whose capability
/// is withdrawn (polymarket.sports / polymarket.politics) is hidden.
/// Esports rows carry the `sports` tag, so they go with Sports.
bool polyPillOffered(PolyPill pill, RuntimeCapabilitiesService policy) =>
    switch (pill) {
      PolyPill.politics => polymarketTagOffered('politics', policy),
      PolyPill.elections => polymarketTagOffered('elections', policy),
      PolyPill.sports ||
      PolyPill.live ||
      PolyPill.esports =>
        polymarketTagOffered('sports', policy),
      _ => true,
    };

/// One subcategory chip. [key] is stable within its pill: a fixed name
/// ('all', '15m', 'live', 'futures', 'politics' …), `tag:<id>` for a
/// Gamma related tag or `series:<id>` for a sports league. [route] is the
/// readable segment of the deep-link key (`predictions/sports/nfl`).
class PolySub {
  final String key;
  final String route;

  /// Display label for a Gamma-provided chip; null for the fixed chips,
  /// whose labels are localised by the screen.
  final String? label;

  /// Open markets, when the source gives the number cheaply.
  final int? count;

  /// The chip's logo: a league's, a sport's or a game's (Gamma `/sports`)
  /// or a coin's (the one polymarket.com shows). Null for a text chip.
  final String? imageUrl;

  const PolySub(this.key,
      {String? route, this.label, this.count, this.imageUrl})
      : route = route ?? key;

  int? get tagId => key.startsWith('tag:') ? int.tryParse(key.substring(4)) : null;
  String? get seriesId => key.startsWith('series:') ? key.substring(7) : null;

  PolySub withCount(int? n) =>
      PolySub(key, route: route, label: label, count: n, imageUrl: imageUrl);
}

/// Where polymarket.com keeps the coin logos its Crypto row shows.
const String _kSiteLogos = 'https://polymarket.com/images/logos';

/// The Crypto chips in polymarket.com's order: the key, the site's
/// `/api/crypto/counts` key for it, and for a coin its name (a proper
/// name; the other chips are localised by the screen) and the logo the
/// site shows on its chip.
const List<({String key, String countKey, String? label, String? logo})>
    _kCryptoSubs = [
  (key: 'all', countKey: 'all', label: null, logo: null),
  (key: '5m', countKey: 'fiveM', label: null, logo: null),
  (key: '15m', countKey: 'fifteenM', label: null, logo: null),
  (key: '1h', countKey: 'hourly', label: null, logo: null),
  (key: '4h', countKey: 'fourhour', label: null, logo: null),
  (key: 'daily', countKey: 'daily', label: null, logo: null),
  (key: 'weekly', countKey: 'weekly', label: null, logo: null),
  (key: 'monthly', countKey: 'monthly', label: null, logo: null),
  (key: 'yearly', countKey: 'yearly', label: null, logo: null),
  (key: 'targets', countKey: 'targets', label: null, logo: null),
  (key: 'pre-market', countKey: 'pre-market', label: null, logo: null),
  (key: 'institutions', countKey: 'institutions', label: null, logo: null),
  (key: 'industry', countKey: 'industry', label: null, logo: null),
  (
    key: 'protocol-metrics',
    countKey: 'protocol-metrics',
    label: null,
    logo: null
  ),
  (
    key: 'bitcoin',
    countKey: 'bitcoin',
    label: 'Bitcoin',
    logo: '$_kSiteLogos/btc.png'
  ),
  (
    key: 'ethereum',
    countKey: 'ethereum',
    label: 'Ethereum',
    logo: '$_kSiteLogos/eth.png'
  ),
  (
    key: 'solana',
    countKey: 'solana',
    label: 'Solana',
    logo: '$_kSiteLogos/sol.png'
  ),
  (key: 'xrp', countKey: 'xrp', label: 'XRP', logo: '$_kSiteLogos/xrp.png'),
  (
    key: 'dogecoin',
    countKey: 'dogecoin',
    label: 'Dogecoin',
    logo: '$_kSiteLogos/doge.png'
  ),
  (
    key: 'bnb',
    countKey: 'bnb',
    label: 'BNB',
    logo:
        'https://polymarket-upload.s3.us-east-2.amazonaws.com/bnb%20logo-247a9f7a39.png'
  ),
  (
    key: 'microstrategy',
    countKey: 'microstrategy',
    label: 'Microstrategy',
    logo: '$_kSiteLogos/microstrategy.jpg'
  ),
];

/// Crypto chips that stay when the site's count for them is missing or
/// zero (All, and 5 Min, which is the live cards and no list).
const Set<String> _kCryptoAlwaysShown = {'all', '5m'};

/// Breaking's topic chips (polymarket.com/breaking's own filters).
const List<String> kPolyBreakingTopics = [
  'all',
  'politics',
  'world',
  'sports',
  'crypto',
  'finance',
  'tech',
  'culture',
];

/// Finance's chips in polymarket.com's order ("Earnings Calendar" is a
/// page of its own there, not a list, and is left out). `indicies` is
/// the site's own spelling of the slug; the chip reads "Indices".
const List<String> kPolyFinanceSubs = [
  'all',
  'daily',
  'weekly',
  'monthly',
  'stocks',
  'earnings',
  'indicies',
  'commodities',
  'forex',
  'privates',
  'acquisitions',
  'ipo',
  'fed-rates',
  'prediction-markets',
  'treasuries',
  'kpis',
];

/// Weather's chips in polymarket.com's order.
const List<String> kPolyWeatherSubs = [
  'all',
  'temperature',
  'precipitation',
  'drought',
  'global',
  'tornadoes',
  'hurricanes',
  'earthquakes',
  'volcanoes',
  'pandemics',
];

/// The sports of polymarket.com's Sports row, after its leagues. The key
/// is the site's path segment and the sport's Gamma tag ("Combat" is
/// `mma`).
const List<String> kPolySportGroups = [
  'soccer',
  'tennis',
  'cricket',
  'basketball',
  'baseball',
  'football',
  'hockey',
  'rugby',
  'table-tennis',
  'darts',
  'handball',
  'golf',
  'mma',
  'motorsports',
  'cycling',
  'chess',
];

/// How many leagues lead the Sports row before the sports (the site
/// features six).
const int _kSportsFeaturedLeagues = 6;

/// The games of polymarket.com's Esports row: the Gamma tag (also the
/// site's path segment), the name the site shows, and the game's code in
/// Gamma `/sports`, where its logo comes from.
const List<({String slug, String label, String sport})> kPolyEsportsGames = [
  (slug: 'league-of-legends', label: 'LoL', sport: 'lol'),
  (slug: 'cs2', label: 'CS2', sport: 'cs2'),
  (slug: 'rainbow-six-siege', label: 'Rainbow Six Siege', sport: 'r6siege'),
  (slug: 'dota-2', label: 'Dota 2', sport: 'dota2'),
  (
    slug: 'mobile-legends-bang-bang',
    label: 'Mobile Legends: Bang Bang',
    sport: 'mlbb'
  ),
  (slug: 'overwatch', label: 'Overwatch', sport: 'ow'),
  (slug: 'valorant', label: 'Valorant', sport: 'val'),
  (slug: 'honor-of-kings', label: 'Honor of Kings', sport: 'hok'),
  (slug: 'call-of-duty', label: 'Call of Duty', sport: 'codmw'),
  (slug: 'rocket-league', label: 'Rocket League', sport: 'rl'),
  (slug: 'starcraft-2', label: 'StarCraft II', sport: 'sc2'),
  (slug: 'starcraft-brood-war', label: 'StarCraft: Brood War', sport: 'sc'),
];

/// Where a fixed chip's list comes from: the Gamma tags read side by
/// side, and the tags every row must also carry. Null for a chip that is
/// not a tag list (All, Live, Futures, 5 Min, a related tag, a league).
///
/// All of these are plain `tag_slug` reads, which the Kute feed passes
/// on. The four Crypto sections are computed by polymarket.com's own
/// server; the tags here are the ones its sections' events carry.
({List<String> tags, List<String> require})? polyFixedSubSource(
    PolyPill pill, String sub) {
  ({List<String> tags, List<String> require}) of(List<String> tags,
          [List<String> require = const []]) =>
      (tags: tags, require: require);
  switch (pill) {
    case PolyPill.crypto:
      const crypto = ['crypto'];
      return switch (sub) {
        'weekly' => of(const ['weekly'], crypto),
        'monthly' => of(const ['monthly'], crypto),
        'yearly' => of(const ['yearly'], crypto),
        'daily' => of(const ['today']),
        'pre-market' => of(const ['pre-market']),
        'targets' =>
          of(const ['price-milestone', 'price-comparison'], crypto),
        'institutions' => of(const [
            'crypto-listings',
            'corporate-financials',
            'crypto-treasury',
            'gov-reserve',
          ], crypto),
        'industry' => of(const [
            'crypto-legal',
            'protocol-risk',
            'protocol-upgrade',
            'crypto-culture',
          ], crypto),
        'protocol-metrics' =>
          of(const ['network-stats', 'fees', 'open-interest'], crypto),
        'bitcoin' ||
        'ethereum' ||
        'solana' ||
        'xrp' ||
        'dogecoin' ||
        'bnb' ||
        'microstrategy' =>
          of([sub], crypto),
        _ => null,
      };
    case PolyPill.finance:
      const finance = ['finance'];
      return switch (sub) {
        'daily' || 'weekly' || 'monthly' => of([sub], finance),
        'ipo' => of(const ['ipos']),
        _ => sub != 'all' && kPolyFinanceSubs.contains(sub) ? of([sub]) : null,
      };
    case PolyPill.weather:
      return switch (sub) {
        'temperature' => of(const ['daily-temperature']),
        'precipitation' => of(const ['precipitation']),
        'drought' => of(const ['drought']),
        'global' => of(const ['climate']),
        'tornadoes' => of(const ['tornado', 'tornado-risk']),
        'hurricanes' => of(const ['hurricanes', 'hurricane']),
        'earthquakes' => of(const ['earthquakes', 'earthquake']),
        'volcanoes' => of(const ['volcanoes', 'volcano']),
        'pandemics' => of(const ['pandemics']),
        _ => null,
      };
    case PolyPill.sports:
      return kPolySportGroups.contains(sub) ? of([sub]) : null;
    case PolyPill.esports:
      return kPolyEsportsGames.any((g) => g.slug == sub) ? of([sub]) : null;
    default:
      return null;
  }
}

/// Every fixed chip key (the chips that are not a Gamma related tag or a
/// league), for deep links.
final Set<String> kPolyFixedSubKeys = {
  'live',
  'futures',
  for (final s in _kCryptoSubs) s.key,
  ...kPolyBreakingTopics,
  ...kPolyFinanceSubs,
  ...kPolyWeatherSubs,
  ...kPolySportGroups,
  for (final g in kPolyEsportsGames) g.slug,
};

/// The selected pill, and per pill its subcategory.
/// Lives for the session (not autoDispose), so leaving the screen or
/// opening a market comes back to the same list.
class PolyBrowseSelection {
  final PolyPill pill;
  final Map<PolyPill, String> subs;

  const PolyBrowseSelection({
    this.pill = PolyPill.trending,
    this.subs = const {},
  });

  String subOf(PolyPill p) => subs[p] ?? p.defaultSub;

  String get sub => subOf(pill);

  PolyFeedQuery get query => PolyFeedQuery(pill: pill, sub: sub);

  PolyBrowseSelection copyWith({PolyPill? pill, String? sub}) {
    final p = pill ?? this.pill;
    return PolyBrowseSelection(
      pill: p,
      subs: sub == null ? subs : {...subs, p: sub},
    );
  }
}

final polyBrowseSelectionProvider =
    StateProvider<PolyBrowseSelection>((ref) => const PolyBrowseSelection());

/// The selection a deep-link key names (`predictions/crypto/15m`). A
/// subcategory segment that is
/// not a fixed chip (a Gamma tag or a league) is kept as `route:<segment>`
/// for the screen to match against the chips it loads. Null when the key
/// is not a Predictions key.
PolyBrowseSelection? polyBrowseSelectionFromRouteKey(String key) {
  final parts = key.split('/').where((p) => p.isNotEmpty).toList();
  if (parts.length < 2 || parts.first != 'predictions') return null;
  final pill = PolyPillX.fromKey(parts[1]);
  if (pill == null) return null;
  var selection = PolyBrowseSelection(pill: pill);
  if (parts.length > 2) {
    final seg = parts[2];
    selection = selection.copyWith(
        sub: kPolyFixedSubKeys.contains(seg) ? seg : 'route:$seg');
  }
  return selection;
}

/// One list the screen can show.
class PolyFeedQuery {
  final PolyPill pill;
  final String sub;

  const PolyFeedQuery({required this.pill, this.sub = 'all'});

  /// Disk cache key, one per pill / subcategory. The tail is the market
  /// type and sort the key once carried, kept so the lists already on
  /// disk are still found.
  String get cacheKey => 'browse_${pill.key}_${sub.replaceAll(':', '-')}_all_'
      '${pill == PolyPill.newest ? 'new' : 'volume'}';

  @override
  bool operator ==(Object other) =>
      other is PolyFeedQuery && other.pill == pill && other.sub == sub;

  @override
  int get hashCode => Object.hash(pill, sub);
}

/// What a feed holds: the rows loaded so far, whether more can be read,
/// and whether a read is running.
class PolyFeedState {
  final List<PolymarketEvent> events;
  final bool loading;
  final bool loadingMore;
  final bool done;
  final bool failed;

  const PolyFeedState({
    this.events = const [],
    this.loading = false,
    this.loadingMore = false,
    this.done = false,
    this.failed = false,
  });

  PolyFeedState copyWith({
    List<PolymarketEvent>? events,
    bool? loading,
    bool? loadingMore,
    bool? done,
    bool? failed,
  }) =>
      PolyFeedState(
        events: events ?? this.events,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        done: done ?? this.done,
        failed: failed ?? this.failed,
      );
}

/// How a query is read: which Gamma keyset sources, with which filters
/// applied to the rows.
class _FeedSource {
  final Map<String, String> params;
  final Map<String, List<String>> multi;
  _FeedSource(this.params, [this.multi = const {}]);
  String? cursor;
  bool done = false;
}

enum _FeedKind { keyset, movers, live, watchlist, none }

class _FeedSpec {
  final _FeedKind kind;
  final List<_FeedSource> sources;

  /// Tags every row must carry (Weekly is `weekly` on crypto events).
  final List<String> requireTags;

  /// Up/Down windows: Gamma lists the windows ahead too; keep the ones
  /// that end soon. The sources come soonest to end first, so a source
  /// is finished at the first row past that horizon.
  final bool currentWindowsOnly;

  /// A sort Gamma cannot do, applied to each page as it lands (so rows
  /// already on screen never move).
  final Comparator<PolymarketEvent>? pageSort;

  const _FeedSpec(
    this.kind, {
    this.sources = const [],
    this.requireTags = const [],
    this.currentWindowsOnly = false,
    this.pageSort,
  });
}

int _byVolume(PolymarketEvent a, PolymarketEvent b) =>
    _hotnessScore(b).compareTo(_hotnessScore(a));

_FeedSpec _specFor(PolyFeedQuery q) {
  // The most traded first; New reads the newest first.
  final base = {
    'active': 'true',
    'closed': 'false',
    'order': q.pill == PolyPill.newest ? 'startDate' : 'volume24hr',
    'ascending': 'false',
  };
  // A Gamma tag (a topic chip, a "More" category) or a league: one source.
  final sub = PolySub(q.sub);
  if (q.pill != PolyPill.breaking && sub.tagId != null) {
    return _FeedSpec(_FeedKind.keyset,
        sources: [
          _FeedSource({...base, 'tag_id': '${sub.tagId}'})
        ]);
  }
  if (q.pill != PolyPill.breaking && sub.seriesId != null) {
    return _FeedSpec(_FeedKind.keyset,
        sources: [
          _FeedSource({...base, 'series_id': sub.seriesId!})
        ]);
  }
  switch (q.pill) {
    case PolyPill.breaking:
      return const _FeedSpec(_FeedKind.movers);
    case PolyPill.live:
      return const _FeedSpec(_FeedKind.live);
    case PolyPill.watchlist:
      return const _FeedSpec(_FeedKind.watchlist);
    case PolyPill.trending:
      return _FeedSpec(_FeedKind.keyset, sources: [_FeedSource(base)]);
    case PolyPill.newest:
      return _FeedSpec(_FeedKind.keyset, sources: [
        _FeedSource(base, {'exclude_tag_id': _kNewExcludedTagIds}),
      ]);
    default:
      break;
  }
  _FeedSpec tags(List<String> slugs,
          {List<String> require = const [], bool windows = false}) =>
      _FeedSpec(_FeedKind.keyset,
          sources: [
            for (final slug in slugs)
              _FeedSource({...base, 'tag_slug': slug}),
          ],
          requireTags: require,
          currentWindowsOnly: windows,
          // Two tags read side by side: each page is merged in sort order.
          pageSort: slugs.length > 1 ? _byVolume : null);

  if (q.pill == PolyPill.crypto && q.sub == '5m') {
    return const _FeedSpec(_FeedKind.none);
  }
  if (q.pill == PolyPill.crypto) {
    // Up/Down windows: the rounds in play first (one
    // per asset), then the ones ahead in the order they run, as
    // polymarket.com lists them. Gamma keeps rounds that ended months ago
    // as open, so the read starts at now (to the minute, so the feed can
    // cache it); the most traded first put a round four hours ahead on
    // top of the one being played.
    final windowTag = switch (q.sub) {
      '15m' => '15M',
      '1h' => '1H',
      '4h' => '4H',
      _ => null,
    };
    if (windowTag != null) {
      final now = DateTime.now().toUtc();
      final from = DateTime.utc(
          now.year, now.month, now.day, now.hour, now.minute);
      return _FeedSpec(_FeedKind.keyset,
          sources: [
            _FeedSource({
              'active': 'true',
              'closed': 'false',
              'order': 'endDate',
              'ascending': 'true',
              'end_date_min': from.toIso8601String(),
              'tag_slug': windowTag,
            }),
          ],
          currentWindowsOnly: true);
    }
  }
  if (q.pill == PolyPill.sports) {
    switch (q.sub) {
      case 'live':
        return const _FeedSpec(_FeedKind.live);
      case 'futures':
        return _FeedSpec(_FeedKind.keyset,
            sources: [
              _FeedSource({...base, 'tag_slug': 'sports'},
                  {'exclude_tag_id': const [_kGamesTagId]}),
            ]);
    }
  }
  final fixed = polyFixedSubSource(q.pill, q.sub);
  if (fixed != null) return tags(fixed.tags, require: fixed.require);
  return tags(q.pill.tagSlugs);
}

/// The first page is kept small so the first cards wait on a small read;
/// later pages are larger.
const int _kFeedFirstPage = 20;
const int _kFeedNextPage = 30;

/// A read that filters most rows away (Weekly crypto)
/// keeps reading pages until this many new rows show, or the list ends.
const int _kFeedMinNewRows = 8;
const int _kFeedMaxAutoPages = 4;

final RegExp _kFiveMinuteSlug = RegExp(r'-updown-5m-');

/// How far ahead an Up/Down window list shows rounds.
const Duration _kWindowHorizon = Duration(hours: 6);

/// The Gamma parameters of each source [query] reads, for the tests: the
/// order and filters a list asks the feed for.
@visibleForTesting
List<Map<String, String>> polyFeedSourceParams(PolyFeedQuery query) =>
    [for (final s in _specFor(query).sources) Map.of(s.params)];

/// One Predictions list, paged: the last first page this device saw is
/// drawn at once from disk, the live first page replaces it, and
/// [PolyFeedNotifier.loadMore] reads the next page on the same cursor
/// when the person nears the end.
final polyBrowseFeedProvider = NotifierProvider.autoDispose
    .family<PolyFeedNotifier, PolyFeedState, PolyFeedQuery>(
        PolyFeedNotifier.new);

class PolyFeedNotifier
    extends AutoDisposeFamilyNotifier<PolyFeedState, PolyFeedQuery> {
  late _FeedSpec _spec;
  final Set<String> _seen = {};
  int _generation = 0;

  @override
  PolyFeedState build(PolyFeedQuery arg) {
    // Kept for a while after the screen moves to another pill, so going
    // back shows the same rows (and scroll) without a reload.
    _cacheFor(ref, const Duration(minutes: 10));
    ref.watch(runtimeCapabilitiesProvider);
    _spec = _specFor(arg);
    // The watchlist reads again whenever a star changes.
    if (_spec.kind == _FeedKind.watchlist) ref.watch(polyWatchlistProvider);
    _seen.clear();
    final gen = ++_generation;
    ref.onDispose(() => _generation++);
    if (_spec.kind == _FeedKind.none) {
      return const PolyFeedState(done: true);
    }
    final cached = _cached();
    Future.microtask(() => _loadFirst(gen, hasCache: cached != null));
    return PolyFeedState(events: cached ?? const [], loading: true);
  }

  List<PolymarketEvent>? _cached() {
    final rows = PolymarketFeedCache.instance.readEvents(arg.cacheKey);
    if (rows == null) return null;
    final open = _offeredUnderPolicy(
        ref, rows.where((e) => !_isEventResolved(e)).toList());
    return open.isEmpty ? null : open;
  }

  List<PolymarketEvent> _keep(Iterable<PolymarketEvent> rows) {
    final now = DateTime.now();
    final out = <PolymarketEvent>[];
    for (final e in rows) {
      if (_kFiveMinuteSlug.hasMatch(e.slug.toLowerCase())) continue;
      if (_isEventResolved(e)) continue;
      if (_spec.requireTags.any((t) => !e.tags.contains(t))) continue;
      if (_spec.currentWindowsOnly) {
        final end = e.endDate;
        if (end == null || end.difference(now) > _kWindowHorizon) {
          continue;
        }
      }
      if (!_seen.add(e.id)) continue;
      out.add(e);
    }
    return _offeredUnderPolicy(ref, out);
  }

  Future<void> _loadFirst(int gen, {required bool hasCache}) async {
    try {
      final List<PolymarketEvent> rows;
      var done = false;
      switch (_spec.kind) {
        case _FeedKind.movers:
          rows = _keep(await _readMovers());
          done = true;
        case _FeedKind.live:
          rows = _keep(await _readLive());
          done = true;
        case _FeedKind.watchlist:
          rows = _keep(await _readWatchlist());
          done = true;
        case _FeedKind.keyset:
          final page = await _readPages(_kFeedFirstPage);
          rows = page.rows;
          done = page.done;
        case _FeedKind.none:
          return;
      }
      if (gen != _generation) return;
      state = PolyFeedState(events: rows, done: done);
      unawaited(PolymarketFeedCache.instance
          .writeEvents(arg.cacheKey, rows, max: _kFeedFirstPage));
    } catch (_) {
      if (gen != _generation) return;
      state = state.copyWith(loading: false, failed: true, done: true);
    }
  }

  /// Reads the next page; a no-op while a read runs or at the end.
  Future<void> loadMore() async {
    if (state.loading || state.loadingMore || state.done) return;
    if (_spec.kind != _FeedKind.keyset) return;
    final gen = _generation;
    state = state.copyWith(loadingMore: true);
    try {
      final page = await _readPages(_kFeedNextPage);
      if (gen != _generation) return;
      state = state.copyWith(
        events: [...state.events, ...page.rows],
        loadingMore: false,
        done: page.done,
      );
    } catch (_) {
      if (gen != _generation) return;
      // A failed later page keeps what is on screen; scrolling retries.
      state = state.copyWith(loadingMore: false);
    }
  }

  /// One page from every source still open, merged and filtered; keeps
  /// reading while filters leave fewer than [_kFeedMinNewRows] new rows.
  Future<({List<PolymarketEvent> rows, bool done})> _readPages(
      int size) async {
    final model = PolymarketModel();
    try {
      final out = <PolymarketEvent>[];
      for (var i = 0; i < _kFeedMaxAutoPages; i++) {
        final open = _spec.sources.where((s) => !s.done).toList();
        if (open.isEmpty) break;
        final pages = await Future.wait(open.map((s) async {
          final page = await PolymarketModel.readGammaKeysetPage(
            'events',
            s.params,
            limit: size,
            cursor: s.cursor,
            multi: s.multi,
          );
          s.cursor = page.next;
          s.done = page.next == null;
          final parsed = model.parseEventsRaw(page.rows);
          // Soonest to end first: nothing after the horizon is kept, so
          // there is nothing more to read.
          if (_spec.currentWindowsOnly &&
              parsed.any((e) =>
                  e.endDate != null &&
                  e.endDate!.difference(DateTime.now()) > _kWindowHorizon)) {
            s.done = true;
          }
          return parsed;
        }));
        final merged = _keep(pages.expand((p) => p));
        final pageSort = _spec.pageSort;
        if (pageSort != null) merged.sort(pageSort);
        out.addAll(merged);
        if (out.length >= _kFeedMinNewRows) break;
      }
      return (rows: out, done: _spec.sources.every((s) => s.done));
    } finally {
      model.dispose();
    }
  }

  Future<List<PolymarketEvent>> _readMovers() async {
    final model = PolymarketModel();
    try {
      final category = arg.sub == 'all' ? null : arg.sub;
      final movers = (await model.listBiggestMovers(
              limit: 40, category: category))
          .where((e) => e.outcomes.isNotEmpty)
          .toList();
      if (movers.isNotEmpty) return await _withEventDetails(model, movers);
      if (category != null) return movers;
      // The movers endpoint now and then answers empty; the most traded
      // markets keep the list from going blank.
      return (await model.listEvents(
              hot: true, order: 'volume24hr', limit: 50))
          .where((e) => e.outcomes.isNotEmpty)
          .toList();
    } finally {
      model.dispose();
    }
  }

  /// The movers ranking carries a market's question, prices and move, and
  /// nothing else. One read of the movers' own events (by slug, through
  /// the Kute feed) gives each card what every other list's card has: the
  /// end date, the category and the volume. A failed read keeps the rows
  /// as they came.
  Future<List<PolymarketEvent>> _withEventDetails(
      PolymarketModel model, List<PolymarketEvent> movers) async {
    final slugs = {
      for (final m in movers)
        if (m.slug.isNotEmpty) m.slug
    }.toList();
    if (slugs.isEmpty) return movers;
    try {
      final page = await PolymarketModel.readGammaKeysetPage(
        'events',
        const {},
        multi: {'slug': slugs},
        limit: slugs.length,
      );
      final bySlug = {
        for (final e in model.parseEventsRaw(page.rows)) e.slug: e,
      };
      return [
        for (final m in movers)
          if (bySlug[m.slug] case final parent?)
            PolymarketEvent(
              id: m.id,
              slug: m.slug,
              title: m.title,
              imageUrl: m.imageUrl ?? parent.imageUrl,
              volume: m.volume > 0 ? m.volume : parent.volume,
              volume24hr: parent.volume24hr,
              liquidity: m.liquidity > 0 ? m.liquidity : parent.liquidity,
              category: parent.category,
              startDate: parent.startDate,
              endDate: m.endDate ?? parent.endDate,
              active: m.active,
              closed: parent.closed,
              description: m.description ?? parent.description,
              conditionId: m.conditionId,
              outcomes: m.outcomes,
              negRisk: m.negRisk,
              oneDayPriceChange: m.oneDayPriceChange,
              tags: m.tags.isNotEmpty ? m.tags : parent.tags,
            )
          else
            m
      ];
    } catch (_) {
      return movers;
    }
  }

  /// The starred markets, newest star first: one read of their slugs
  /// (`events/keyset?slug=…&slug=…`, through the Kute feed).
  Future<List<PolymarketEvent>> _readWatchlist() async {
    final slugs = ref.read(polyWatchlistProvider);
    if (slugs.isEmpty) return const [];
    final model = PolymarketModel();
    try {
      final page = await PolymarketModel.readGammaKeysetPage(
        'events',
        const {},
        multi: {'slug': slugs},
        limit: slugs.length,
      );
      final bySlug = {
        for (final e in model.parseEventsRaw(page.rows)) e.slug: e,
      };
      return [
        for (final s in slugs)
          if (bySlug[s] != null) bySlug[s]!
      ];
    } finally {
      model.dispose();
    }
  }

  /// Games in play, as the Live pill has always read them.
  Future<List<PolymarketEvent>> _readLive() async {
    final model = PolymarketModel();
    try {
      final results = await Future.wait([
        model.listEvents(tag: TagSlug.sports, limit: 200),
        model.listEvents(hot: true, limit: 50),
      ]);
      final now = DateTime.now();
      final inPlay = [
        for (final e in [...results[0], ...results[1]])
          if (e.isInPlay) e
      ];
      inPlay.sort(
          (a, b) => _excitementScore(b, now).compareTo(_excitementScore(a, now)));
      return inPlay;
    } finally {
      model.dispose();
    }
  }
}

// ─────────────────────────── subcategory chips ───────────────────────────

const Duration _kSubsCacheWindow = Duration(minutes: 30);

/// Subcategory chips for Politics, Geopolitics, Tech, Culture and
/// Economy: Gamma's related tags of the pill's tag, in Gamma's order and
/// with Gamma's labels (polymarket.com's own row is this same read), each
/// with its open-event count. Empty for a pill with no such tag. Drawn
/// from disk first.
final polyTopicSubsProvider = StreamProvider.autoDispose
    .family<List<PolySub>, PolyPill>((ref, pill) async* {
  _cacheFor(ref, _kSubsCacheWindow);
  final tagId = pill.relatedTagId;
  if (tagId == null) {
    yield const [];
    return;
  }
  final key = 'related_${pill.key}';
  final policy = ref.watch(runtimeCapabilitiesProvider);
  final cached = PolymarketFeedCache.instance.readTagRows(key);
  if (cached != null) yield polyTopicSubsFromRows(cached, policy);
  try {
    final model = PolymarketModel();
    ref.onDispose(model.dispose);
    final rows = await model.fetchRelatedTags(tagId);
    unawaited(PolymarketFeedCache.instance.writeTagRows(key, rows));
    yield polyTopicSubsFromRows(rows, policy);
  } catch (_) {
    if (cached == null) yield const [];
  }
});

/// Related-tag rows as chips, in the rows' order: every tag with open
/// events that the policy offers, once.
List<PolySub> polyTopicSubsFromRows(
    List<Map<String, dynamic>> rows, RuntimeCapabilitiesService policy) {
  final seen = <String>{};
  return [
    for (final r in rows)
      if (r['id'] != null &&
          ((r['activeEventsCount'] as num?)?.toInt() ?? 0) > 0 &&
          polymarketTagOffered('${r['slug'] ?? ''}', policy) &&
          seen.add('${r['id']}'))
        PolySub('tag:${r['id']}',
            route: '${r['slug'] ?? r['id']}',
            label: '${r['label'] ?? r['slug']}'.trim(),
            count: (r['activeEventsCount'] as num?)?.toInt()),
  ];
}

/// Crypto's chips in the site's order with [counts] (the site's
/// `/api/crypto/counts`). With counts, a chip the site counts at zero
/// drops out, as on polymarket.com; without them every chip shows.
List<PolySub> polyCryptoSubsFromCounts(Map<String, dynamic>? counts) => [
      for (final s in _kCryptoSubs)
        if (counts == null ||
            _kCryptoAlwaysShown.contains(s.key) ||
            (int.tryParse('${counts[s.countKey] ?? ''}') ?? 1) > 0)
          PolySub(s.key,
              label: s.label,
              imageUrl: s.logo,
              count: int.tryParse('${counts?[s.countKey] ?? ''}')),
    ];

/// Crypto's chips with polymarket.com's counts (`/api/crypto/counts`, a
/// few hundred bytes). Without the counts the chips still show, unnumbered.
final polyCryptoSubsProvider =
    StreamProvider.autoDispose<List<PolySub>>((ref) async* {
  _cacheFor(ref, _kSubsCacheWindow);
  final cached =
      PolymarketFeedCache.instance.readTagRows('crypto_counts')?.firstOrNull;
  yield polyCryptoSubsFromCounts(cached);
  try {
    final model = PolymarketModel();
    ref.onDispose(model.dispose);
    final counts = await model.fetchCryptoCounts();
    if (counts == null) return;
    unawaited(
        PolymarketFeedCache.instance.writeTagRows('crypto_counts', [counts]));
    yield polyCryptoSubsFromCounts(counts);
  } catch (_) {}
});

/// Gamma `/sports` (every league: `{sport, name, image, series, tags}`),
/// read once for the league chips, the sports' own logos and the games'.
final _polySportsDirectoryProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  _cacheFor(ref, _kSubsCacheWindow);
  final model = PolymarketModel();
  ref.onDispose(model.dispose);
  return model.fetchSportsLeagues();
});

/// The leagues with the most 24 h volume on the first page of Sports,
/// most traded first, with their names and logos from Gamma `/sports`.
/// Drawn from disk first.
final polyLeagueRowsProvider =
    StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) async* {
  _cacheFor(ref, _kSubsCacheWindow);
  final cached = PolymarketFeedCache.instance.readTagRows('sports_leagues');
  yield cached ?? const [];
  try {
    final results = await Future.wait([
      ref.read(_polySportsDirectoryProvider.future),
      PolymarketModel.readGammaKeysetPage(
        'events',
        const {
          'active': 'true',
          'closed': 'false',
          'tag_slug': 'sports',
          'order': 'volume24hr',
          'ascending': 'false',
        },
        limit: 100,
      ).then((p) => p.rows),
    ]);
    final bySeries = {
      for (final l in results[0]) '${l['series']}': l,
    };
    final volume = <String, double>{};
    for (final e in results[1]) {
      final series = e['series'];
      if (series is! List || series.isEmpty || series.first is! Map) continue;
      final id = '${(series.first as Map)['id']}';
      if (!bySeries.containsKey(id)) continue;
      volume[id] =
          (volume[id] ?? 0) + ((e['volume24hr'] as num?)?.toDouble() ?? 0);
    }
    final ranked = volume.keys.toList()
      ..sort((a, b) => volume[b]!.compareTo(volume[a]!));
    final rows = [for (final id in ranked.take(14)) bySeries[id]!];
    unawaited(
        PolymarketFeedCache.instance.writeTagRows('sports_leagues', rows));
    yield rows;
  } catch (_) {}
});

PolySub _leagueSub(Map<String, dynamic> r) => PolySub('series:${r['series']}',
    route: '${r['sport'] ?? r['series']}',
    label: '${r['name'] ?? r['sport'] ?? ''}'.trim(),
    imageUrl: r['image'] as String?);

/// Gamma's `esports` tag id, as `/sports` lists it on a league's `tags`.
const String _kEsportsTagId = '64';

bool _isEsportsLeague(Map<String, dynamic> r) =>
    '${r['tags'] ?? ''}'.split(',').contains(_kEsportsTagId);

/// The most traded leagues as chips, esports included: what the Live
/// list names its groups from.
final polySportsLeaguesProvider = Provider.autoDispose<List<PolySub>>((ref) {
  final rows = ref.watch(polyLeagueRowsProvider).valueOrNull ?? const [];
  return [for (final r in rows) _leagueSub(r)];
});

/// The logo of each sport of [kPolySportGroups] that Gamma `/sports`
/// lists under its own name (Darts, Chess, Cycling), by the sport's key.
/// The site draws its own glyphs for the sports; the app shows a logo only
/// where the data carries one.
Map<String, String> polySportGroupLogos(List<Map<String, dynamic>> sports) => {
      for (final r in sports)
        if (kPolySportGroups.contains('${r['sport']}') &&
            r['image'] is String &&
            (r['image'] as String).isNotEmpty)
          '${r['sport']}': r['image'] as String,
    };

/// [polySportGroupLogos] from Gamma `/sports`, drawn from disk first.
final polySportGroupLogosProvider =
    StreamProvider.autoDispose<Map<String, String>>((ref) async* {
  _cacheFor(ref, _kSubsCacheWindow);
  final cached = PolymarketFeedCache.instance.readTagRows('sport_groups');
  if (cached != null) yield polySportGroupLogos(cached);
  try {
    final rows = [
      for (final r in await ref.read(_polySportsDirectoryProvider.future))
        if (kPolySportGroups.contains('${r['sport']}')) r
    ];
    unawaited(PolymarketFeedCache.instance.writeTagRows('sport_groups', rows));
    yield polySportGroupLogos(rows);
  } catch (_) {
    if (cached == null) yield const {};
  }
});

/// Sports chips, as polymarket.com's row reads: Live, Futures, the most
/// traded leagues (their logos from Gamma `/sports`; esports have a pill
/// of their own), then the sports, with [groupLogos] where there is one.
List<PolySub> polySportsSubsFromLeagues(
  List<Map<String, dynamic>> leagues, {
  Map<String, String> groupLogos = const {},
}) =>
    [
      const PolySub('live'),
      const PolySub('futures'),
      for (final r in leagues
          .where((r) => !_isEsportsLeague(r))
          .take(_kSportsFeaturedLeagues))
        _leagueSub(r),
      for (final sport in kPolySportGroups)
        PolySub(sport, imageUrl: groupLogos[sport]),
    ];

final polySportsSubsProvider = Provider.autoDispose<List<PolySub>>((ref) =>
    polySportsSubsFromLeagues(
      ref.watch(polyLeagueRowsProvider).valueOrNull ?? const [],
      groupLogos:
          ref.watch(polySportGroupLogosProvider).valueOrNull ?? const {},
    ));

/// Esports chips: All, then the games in the site's order, the games
/// with a match in play first. [logos] is each game's logo by its
/// `/sports` code, [live] the tags of the games in play.
List<PolySub> polyEsportsSubsFrom({
  Map<String, String> logos = const {},
  Set<String> live = const {},
}) {
  PolySub chip(({String slug, String label, String sport}) g) =>
      PolySub(g.slug, label: g.label, imageUrl: logos[g.sport]);
  return [
    const PolySub('all'),
    for (final g in kPolyEsportsGames)
      if (live.contains(g.slug)) chip(g),
    for (final g in kPolyEsportsGames)
      if (!live.contains(g.slug)) chip(g),
  ];
}

/// Esports chips with the games' logos (Gamma `/sports`) and the games in
/// play first (one read of the esports events Gamma flags live). The
/// logos are drawn from disk first.
final polyEsportsSubsProvider =
    StreamProvider.autoDispose<List<PolySub>>((ref) async* {
  _cacheFor(ref, _kSubsCacheWindow);
  Map<String, String> logosOf(List<Map<String, dynamic>> rows) => {
        for (final r in rows)
          if (r['image'] is String) '${r['sport']}': r['image'] as String,
      };
  final codes = {for (final g in kPolyEsportsGames) g.sport};
  final cached = PolymarketFeedCache.instance.readTagRows('esports_games');
  var logos = logosOf(cached ?? const []);
  yield polyEsportsSubsFrom(logos: logos);
  final model = PolymarketModel();
  ref.onDispose(model.dispose);
  try {
    final rows = [
      for (final l in await ref.read(_polySportsDirectoryProvider.future))
        if (codes.contains('${l['sport']}')) l
    ];
    if (rows.isNotEmpty) {
      unawaited(
          PolymarketFeedCache.instance.writeTagRows('esports_games', rows));
      logos = logosOf(rows);
      yield polyEsportsSubsFrom(logos: logos);
    }
  } catch (_) {}
  try {
    final page = await PolymarketModel.readGammaKeysetPage(
      'events',
      const {'tag_slug': 'esports', 'live': 'true', 'closed': 'false'},
      limit: 100,
    );
    final games = {for (final g in kPolyEsportsGames) g.slug};
    final live = <String>{
      for (final e in model.parseEventsRaw(page.rows))
        if (e.isInPlay) ...e.tags.where(games.contains),
    };
    if (live.isNotEmpty) yield polyEsportsSubsFrom(logos: logos, live: live);
  } catch (_) {}
});
