// lib/screens/portfolio/poly_position_events.dart
//
// The events behind the Predictions position cards (the Portfolio's and a
// Ledger's), read in one batch instead of one Gamma read per card.
//
//   * Every card asks for its event's slug ([polyPositionEventProvider]);
//     the Portfolio also asks for every position's slug at once
//     ([polyPortfolioEventsPrefetchProvider]), so cards below the fold are
//     in the same read. Asks made in the same frame go out together: one
//     `GET {backend}/api/v1/pm/feed/events?slug=…&slug=…` (the backend's
//     cached keyset feed, Gamma's `/events/keyset` when the backend does
//     not answer), at most [kPolyEventsBatchMax] slugs per read: Gamma
//     answers 422 "expected array length <= 100" past that.
//   * A batch's events are kept in memory for [kPolyEventsTtl]: opening the
//     Portfolio again within it reads nothing.
//   * An event the Predictions feed already holds (its snapshot on disk or
//     in this session's memory, PolymarketFeedCache) is drawn at once and
//     needs no read, unless it is a game whose snapshot is older than
//     [kPolyEventsTtl] (a game's state, live or over, moves; a market's
//     title and teams do not). Such a game is drawn from the snapshot and
//     replaced when the batch lands.
//   * A failed batch leaves its cards as they are (the market's own image
//     and title) and is not asked again until a card mounts again (the
//     next open) or [PolyPositionEvents.retry] is called (pull-to-refresh).
//
// Live scores do not come from here: the card joins the shared sports
// state for them.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show
        polymarketActivePositionsProvider,
        polymarketClaimablePositionsProvider;
import 'package:kute/services/polymarket/polymarket_feed_cache.dart';

/// How long a batch's events count as current.
const kPolyEventsTtl = Duration(seconds: 60);

/// The most slugs one read carries (Gamma's cap on a repeated `slug`, and
/// the backend feed's page size).
const kPolyEventsBatchMax = 100;

/// Reads the events of [slugs] (at most [kPolyEventsBatchMax]) in one
/// request. Throws when the read fails.
typedef PolyEventsBatchFetch = Future<List<PolymarketEvent>> Function(
    List<String> slugs);

/// An event the Predictions feed already holds, and when its snapshot was
/// saved (null when unknown).
typedef PolyFeedCachedEvent = ({PolymarketEvent event, DateTime? savedAt});

/// The default batch read: the backend's feed, Gamma's keyset list when
/// the backend does not answer.
Future<List<PolymarketEvent>> fetchPolyEventsBySlugs(List<String> slugs) async {
  if (slugs.isEmpty) return const [];
  final page = await PolymarketModel.readGammaKeysetPage(
    'events',
    const {},
    limit: slugs.length,
    multi: {'slug': slugs},
  );
  return PolymarketModel().parseEventsRaw(page.rows);
}

final polyEventsBatchFetchProvider =
    Provider<PolyEventsBatchFetch>((ref) => fetchPolyEventsBySlugs);

final polyEventsClockProvider =
    Provider<DateTime Function()>((ref) => DateTime.now);

/// Looks a slug up in the Predictions feed's own cache.
final polyFeedCacheLookupProvider =
    Provider<PolyFeedCachedEvent? Function(String slug)>(
        (ref) => _FeedCacheIndex.instance.lookup);

/// The feed snapshots (PolymarketFeedCache), indexed by slug. Snapshots
/// are read once a session (the cache memoises them); the index is
/// rebuilt when the feed has saved since.
class _FeedCacheIndex {
  _FeedCacheIndex._();
  static final instance = _FeedCacheIndex._();

  Map<String, PolyFeedCachedEvent> _bySlug = const {};
  String? _stamp;

  PolyFeedCachedEvent? lookup(String slug) {
    try {
      _refresh();
    } catch (e) {
      if (kDebugMode) debugPrint('[poly-position-events] feed cache: $e');
    }
    return _bySlug[slug];
  }

  void _refresh() {
    if (!Hive.isBoxOpen(PolymarketFeedCache.boxName)) return;
    final box = Hive.box<String>(PolymarketFeedCache.boxName);
    // The feed cache's index ({key: [savedAtMs, bytes]}) changes on every
    // save, so it doubles as the stamp of what was indexed.
    final rawIndex = box.get('_events_index');
    if (_stamp != null && rawIndex == _stamp) return;
    final savedAt = <String, DateTime>{};
    if (rawIndex != null) {
      final decoded = jsonDecode(rawIndex);
      if (decoded is Map<String, dynamic>) {
        decoded.forEach((k, v) {
          if (v is List && v.isNotEmpty && v.first is num) {
            savedAt[k] =
                DateTime.fromMillisecondsSinceEpoch((v.first as num).toInt());
          }
        });
      }
    }
    final out = <String, PolyFeedCachedEvent>{};
    for (final key in box.keys) {
      if (key is! String ||
          !(key.startsWith('browse_') || key.startsWith('tag_preview_'))) {
        continue;
      }
      final at = savedAt[key];
      for (final e in PolymarketFeedCache.instance.readEvents(key) ??
          const <PolymarketEvent>[]) {
        if (e.slug.isEmpty) continue;
        final had = out[e.slug];
        // The newest snapshot of an event wins.
        if (had == null ||
            (at != null && (had.savedAt == null || at.isAfter(had.savedAt!)))) {
          out[e.slug] = (event: e, savedAt: at);
        }
      }
    }
    _bySlug = out;
    _stamp = rawIndex ?? '';
  }
}

/// Whether the card's reading of [e] can go stale: a game's state (in
/// play, over, its score) moves; a market's title, teams and image do not.
/// A snapshot keeps no `eventMetadata`, so teams alone count as a game.
bool _gameLike(PolymarketEvent e) =>
    e.gameId != null || e.metadataGameId != null || e.teams.isNotEmpty;

/// The position events read so far, by slug.
class PolyPositionEvents extends Notifier<Map<String, PolymarketEvent>> {
  /// When each slug was last answered (found or not).
  final Map<String, DateTime> _answeredAt = {};
  final Set<String> _failed = {};
  final Set<String> _inFlight = {};
  final Set<String> _pending = {};
  final Set<String> _retry = {};
  bool _scheduled = false;
  bool _disposed = false;

  @override
  Map<String, PolymarketEvent> build() {
    ref.onDispose(() => _disposed = true);
    return const {};
  }

  /// The event to draw for [slug] now: a batch's (even past its window,
  /// until the next one lands), else the feed's snapshot.
  PolymarketEvent? peek(String slug) =>
      state[slug] ?? ref.read(polyFeedCacheLookupProvider)(slug)?.event;

  /// Asks for the events of [slugs]. Asks made before the next microtask
  /// go out as one batch. A slug whose last batch failed is asked again
  /// only with [retry].
  void want(Iterable<String> slugs, {bool retry = false}) {
    for (final s in slugs) {
      final slug = s.trim();
      if (slug.isEmpty) continue;
      _pending.add(slug);
      if (retry) _retry.add(slug);
    }
    if (_pending.isEmpty || _scheduled) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      unawaited(_flush());
    });
  }

  /// Asks again for every slug whose batch failed (pull-to-refresh).
  void retry() => want(_failed.toList(), retry: true);

  Future<void> _flush() async {
    if (_disposed) return;
    final asked = _pending.toList();
    final retry = Set.of(_retry);
    _pending.clear();
    _retry.clear();

    final now = ref.read(polyEventsClockProvider)();
    final lookup = ref.read(polyFeedCacheLookupProvider);
    final fromFeed = <String, PolymarketEvent>{};
    final need = <String>[];
    for (final slug in asked) {
      if (_inFlight.contains(slug)) continue;
      if (_failed.contains(slug) && !retry.contains(slug)) continue;
      final answered = _answeredAt[slug];
      if (answered != null && now.difference(answered) < kPolyEventsTtl) {
        continue;
      }
      final cached = lookup(slug);
      if (cached != null) {
        if (state[slug] == null) fromFeed[slug] = cached.event;
        final at = cached.savedAt;
        final current = !_gameLike(cached.event) ||
            (at != null && now.difference(at) < kPolyEventsTtl);
        if (current) {
          _failed.remove(slug);
          continue;
        }
      }
      need.add(slug);
    }
    if (fromFeed.isNotEmpty) state = {...state, ...fromFeed};
    if (need.isEmpty) return;

    final fetch = ref.read(polyEventsBatchFetchProvider);
    await Future.wait([
      for (var i = 0; i < need.length; i += kPolyEventsBatchMax)
        _read(fetch,
            need.sublist(i, (i + kPolyEventsBatchMax).clamp(0, need.length))),
    ]);
  }

  Future<void> _read(PolyEventsBatchFetch fetch, List<String> slugs) async {
    _inFlight.addAll(slugs);
    try {
      final events = await fetch(slugs);
      if (_disposed) return;
      final at = ref.read(polyEventsClockProvider)();
      final wanted = slugs.toSet();
      final found = <String, PolymarketEvent>{
        for (final e in events)
          if (wanted.contains(e.slug)) e.slug: e,
      };
      // A slug Gamma does not know is answered too: asking again within
      // the window would read nothing new.
      for (final slug in slugs) {
        _answeredAt[slug] = at;
        _failed.remove(slug);
      }
      if (found.isNotEmpty) state = {...state, ...found};
    } catch (e) {
      if (_disposed) return;
      _failed.addAll(slugs);
      if (kDebugMode) {
        debugPrint('[poly-position-events] batch of ${slugs.length} '
            'failed: $e');
      }
    } finally {
      _inFlight.removeAll(slugs);
    }
  }
}

final polyPositionEventsProvider =
    NotifierProvider<PolyPositionEvents, Map<String, PolymarketEvent>>(
        PolyPositionEvents.new);

/// The event of one position card: drawn at once from what is held (a
/// batch's or the feed's), replaced when the batch lands. A card mounting
/// (the provider being created) asks for its slug, failed or not.
final polyPositionEventProvider =
    Provider.autoDispose.family<PolymarketEvent?, String>((ref, slug) {
  if (slug.isEmpty) return null;
  final fetched = ref.watch(polyPositionEventsProvider.select((m) => m[slug]));
  final notifier = ref.read(polyPositionEventsProvider.notifier);
  notifier.want([slug], retry: true);
  return fetched ?? notifier.peek(slug);
});

/// The slugs of the Portfolio's positions, as one stable key, so a
/// positions poll that changes only amounts asks nothing again.
final _portfolioEventSlugsProvider = Provider.autoDispose<String>((ref) {
  final slugs = <String>{
    for (final p in [
      ...ref.watch(polymarketClaimablePositionsProvider),
      ...ref.watch(polymarketActivePositionsProvider),
    ])
      if ((p.eventSlug ?? '').trim().isNotEmpty) p.eventSlug!.trim(),
  }.toList()
    ..sort();
  return slugs.join('\n');
});

/// Asks for every Portfolio position's event in one batch when the
/// Portfolio opens (and when its set of positions changes), so the cards
/// below the fold need no read of their own.
final polyPortfolioEventsPrefetchProvider = Provider.autoDispose<void>((ref) {
  final key = ref.watch(_portfolioEventSlugsProvider);
  if (key.isEmpty) return;
  ref
      .read(polyPositionEventsProvider.notifier)
      .want(key.split('\n'), retry: true);
});
