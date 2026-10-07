// lib/services/venue_analytics.dart
//
// Product analytics for the two venues (Predictions = Polymarket, Investing =
// Hyperliquid). TrackingService stays the only sink and scrubber; this file
// holds the venue-specific context those events carry:
//
//   * What KIND of bet it is: a small registry of the Polymarket markets the
//     person has looked at (category, top event tags, sports league, live,
//     resolution date), keyed by every public id a later event may carry
//     (outcome token ids, condition ids, event slug/id). Persisted, capped, so
//     a sell or a redeem days later still knows it was an NBA game.
//   * What kind of trade it is: Hyperliquid asset_class (crypto | stock |
//     commodity | fx | index) and dex (main | builder dex name), keyed by coin.
//   * The ticket settings behind an order (slippage, order type, limit price,
//     TP/SL, entry surface…), staged by the slip right before it submits and
//     merged into the outcome event the provider fires, so every placed /
//     failed event carries them without threading them through every call.
//   * Deduped setting changes ("how people set up trading screens") and the
//     time-in-flow bucket abandon events carry.
//
// Only public market data and what the person chose. Never balances, keys,
// addresses, order ids or raw errors.

import 'dart:async';

import 'package:hive_ce/hive.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/services/tracking_service.dart';

class VenueAnalytics {
  VenueAnalytics._();

  static const String boxName = 'venue_analytics';
  static const String _pmKindsKey = 'pm_kinds';
  static const String _ledgerBetsKey = 'ledger_pending_bets';
  static const int _pmKindMax = 400;

  // ─── Polymarket: kind of bet ─────────────────────────────────────

  /// Tags that say nothing about the bet (feed plumbing, recency, the
  /// top-level category itself). Excluded from `event_tags`.
  static const Set<String> _genericTags = {
    'all', 'featured', 'trending', 'new', 'hide-from-new', 'recurring',
    'breaking-news', 'daily', 'weekly', 'monthly', 'yearly', 'hourly',
    'up-or-down', 'games', 'sports', 'politics', 'crypto', 'cryptocurrency',
    'pop-culture', 'culture', 'economy', 'economics', 'business', 'world',
    'tech', 'science', 'finance', 'mentions', 'earn-4', 'rewards',
  };

  /// Sports league / competition tags, normalised to one label each.
  static const Map<String, String> _leagues = {
    'nba': 'nba', 'wnba': 'wnba', 'nfl': 'nfl', 'mlb': 'mlb', 'nhl': 'nhl',
    'ncaab': 'ncaab', 'cbb': 'ncaab', 'ncaaf': 'ncaaf', 'cfb': 'ncaaf',
    'epl': 'epl', 'premier-league': 'epl', 'ucl': 'ucl',
    'champions-league': 'ucl', 'uel': 'uel', 'europa-league': 'uel',
    'la-liga': 'la_liga', 'laliga': 'la_liga', 'serie-a': 'serie_a',
    'bundesliga': 'bundesliga', 'ligue-1': 'ligue_1', 'mls': 'mls',
    'liga-mx': 'liga_mx', 'eredivisie': 'eredivisie', 'fifa-world-cup':
        'world_cup', 'world-cup': 'world_cup', 'euro-2028': 'euro',
    'copa-america': 'copa_america', 'ufc': 'ufc', 'mma': 'mma',
    'boxing': 'boxing', 'tennis': 'tennis', 'atp': 'atp', 'wta': 'wta',
    'f1': 'f1', 'formula-1': 'f1', 'golf': 'golf', 'pga': 'pga',
    'cricket': 'cricket', 'ipl': 'ipl', 'esports': 'esports',
    'counter-strike': 'cs2', 'cs2': 'cs2', 'csgo': 'cs2',
    'league-of-legends': 'lol', 'lol': 'lol', 'dota-2': 'dota2',
    'valorant': 'valorant', 'soccer': 'soccer', 'football': 'soccer',
    'basketball': 'basketball', 'baseball': 'baseball', 'hockey': 'hockey',
    'chess': 'chess',
  };

  /// Tag → market_category, checked in order (first hit wins).
  static const List<(String, Set<String>)> _categoryTags = [
    ('sports', {'sports', 'esports'}),
    ('crypto', {'crypto', 'cryptocurrency', 'bitcoin', 'ethereum', 'solana',
      'crypto-prices', 'xrp', 'memecoins'}),
    ('politics', {'politics', 'elections', 'us-politics', 'us-election',
      'global-elections', 'trump', 'congress', 'midterms'}),
    ('geopolitics', {'geopolitics', 'world', 'ukraine', 'israel', 'middle-east',
      'china', 'russia', 'iran'}),
    ('economics', {'economy', 'economics', 'fed', 'fed-rates', 'inflation',
      'finance', 'business', 'stocks', 'earnings', 'ipos', 'recession',
      'commodities'}),
    ('tech', {'tech', 'ai', 'science', 'space', 'openai', 'big-tech'}),
    ('culture', {'pop-culture', 'culture', 'entertainment', 'movies', 'music',
      'awards', 'oscars', 'celebrities', 'tv', 'gaming', 'youtube', 'mentions',
      'tweet-markets'}),
    ('weather', {'weather', 'climate', 'hurricanes'}),
  ];

  static final Map<String, _PmKind> _pmKinds = <String, _PmKind>{};
  static Box<dynamic>? _box;
  static Future<void>? _opening;
  static Timer? _persistTimer;

  /// Opens the persisted registry (lazy, idempotent, never throws). Called
  /// by every remember; call it early where a later event may need a kind
  /// recorded in an earlier session (the trading provider's build).
  static Future<void> warmUp() {
    return _opening ??= () async {
      try {
        final box = Hive.isBoxOpen(boxName)
            ? Hive.box<dynamic>(boxName)
            : await Hive.openBox<dynamic>(boxName);
        _box = box;
        final raw = box.get(_pmKindsKey);
        if (raw is Map) {
          for (final e in raw.entries) {
            final k = _PmKind.fromJson(e.value);
            if (k != null) _pmKinds.putIfAbsent(e.key.toString(), () => k);
          }
        }
        final bets = box.get(_ledgerBetsKey);
        if (bets is Map) {
          for (final e in bets.entries) {
            final v = e.value;
            if (v is Map) {
              _ledgerPendingBets.putIfAbsent(e.key.toString(),
                  () => {for (final p in v.entries) p.key.toString(): p.value});
            }
          }
        }
      } catch (_) {/* Hive not ready (tests): memory only */}
    }();
  }

  /// Records what kind of market this is under each public id a later
  /// event may carry. [ids] are token ids, condition ids, the event slug
  /// and id; empty ones are skipped.
  ///
  /// [eventId], [slug] and [eventTitle] name the parent event (public
  /// Gamma data), so a later slip, bet, sale or claim on one of its
  /// markets can say which event it belongs to ([pmEventParams]). Left
  /// out, what an earlier call recorded for these ids is kept.
  static void rememberPolymarket({
    required Iterable<String?> ids,
    required String category,
    List<String> tags = const [],
    String? slug,
    DateTime? endDate,
    bool isLive = false,
    String? eventId,
    String? eventTitle,
  }) {
    _PmKind? known;
    for (final id in ids) {
      if (id == null || id.isEmpty) continue;
      known = _pmKinds[id];
      if (known != null) break;
    }
    String? pick(String? given, String? before) =>
        given != null && given.trim().isNotEmpty ? given.trim() : before;
    final title = pick(eventTitle, known?.eventTitle);
    final kind = _PmKind(
      category: marketCategory(category, tags),
      tags: eventTags(tags),
      league: sportsLeague(category, tags, slug),
      endMs: endDate?.millisecondsSinceEpoch,
      live: isLive,
      eventId: pick(eventId, known?.eventId),
      eventSlug: pick(slug, known?.eventSlug),
      eventTitle: title == null ? null : title80(title),
    );
    var changed = false;
    for (final id in ids) {
      if (id == null || id.isEmpty) continue;
      _pmKinds.remove(id); // re-insert = most recent
      _pmKinds[id] = kind;
      changed = true;
    }
    if (!changed) return;
    while (_pmKinds.length > _pmKindMax) {
      _pmKinds.remove(_pmKinds.keys.first);
    }
    unawaited(warmUp());
    _schedulePersist();
  }

  /// [rememberPolymarket] for a whole event: every outcome's token and
  /// condition ids, plus the event's slug and id.
  ///
  /// One outcome opened as its own Yes/No screen is a stand-in event (its
  /// id and title are the outcome's): it keeps the parent event's id and
  /// title, recorded when the parent was opened and found again through
  /// the slug and the tokens the two share.
  static void rememberPolymarketEvent(PolymarketEvent e) {
    rememberPolymarket(
      ids: [
        e.id,
        e.slug,
        e.conditionId,
        for (final o in e.outcomes) ...[o.tokenId, o.noTokenId, o.conditionId],
      ],
      category: e.category,
      tags: e.tags,
      slug: e.slug,
      endDate: e.endDate,
      isLive: e.isInPlay || (e.isLive && e.hasStarted && !e.ended),
      // Gamma event ids are numbers; a card built without one (a crypto
      // round's shell carries its slug there) has no event id to give.
      eventId: !e.isSyntheticBinary && _kGammaId.hasMatch(e.id) ? e.id : null,
      eventTitle: e.isSyntheticBinary ? null : e.title,
    );
  }

  static final RegExp _kGammaId = RegExp(r'^\d+$');

  /// A market or event title as analytics carries it: its first 80
  /// characters.
  static String title80(String title) {
    final t = title.trim();
    return t.length > 80 ? t.substring(0, 80) : t;
  }

  /// The parent event of a market, as public Gamma data: `event_id`,
  /// `event_slug` and (with [title]) `event_title` (80 characters), each
  /// only when known. A value the caller gives wins; the rest comes from
  /// what the registry recorded for the first of [ids] it knows.
  static Map<String, Object> pmEventParams(
    Iterable<String?> ids, {
    String? eventId,
    String? eventSlug,
    String? eventTitle,
    bool title = true,
  }) {
    _PmKind? kind;
    for (final id in ids) {
      if (id == null || id.isEmpty) continue;
      kind = _pmKinds[id];
      if (kind != null) break;
    }
    String? pick(String? given, String? known) =>
        given != null && given.trim().isNotEmpty ? given.trim() : known;
    final id = pick(eventId, kind?.eventId);
    final slug = pick(eventSlug, kind?.eventSlug);
    final name = pick(eventTitle, kind?.eventTitle);
    return {
      if (id != null && id.isNotEmpty) 'event_id': id,
      if (slug != null && slug.isNotEmpty) 'event_slug': slug,
      if (title && name != null && name.isNotEmpty)
        'event_title': title80(name),
    };
  }

  /// Fetches the event behind [slug] when none of [ids] is known yet, so a
  /// sell or claim on a position from an earlier session still knows its
  /// kind by the time it completes. Best effort, never throws.
  static Future<void> ensurePolymarket(
      {required String? slug, Iterable<String?> ids = const []}) async {
    if (slug == null || slug.isEmpty) return;
    if (knowsPolymarket(slug) || ids.any(knowsPolymarket)) return;
    await warmUp();
    if (knowsPolymarket(slug) || ids.any(knowsPolymarket)) return;
    final model = PolymarketModel();
    try {
      final e = await model
          .getEventDetailsBySlug(slug)
          .timeout(const Duration(seconds: 10));
      if (e != null) {
        rememberPolymarketEvent(e);
        final extra = [for (final id in ids) if (id != null) id];
        if (extra.isNotEmpty && !extra.any(knowsPolymarket)) {
          rememberPolymarket(
            ids: extra,
            category: e.category,
            tags: e.tags,
            slug: e.slug,
            endDate: e.endDate,
            isLive: e.isInPlay,
          );
        }
      }
    } catch (_) {
    } finally {
      model.dispose();
    }
  }

  static bool knowsPolymarket(String? id) =>
      id != null && id.isNotEmpty && _pmKinds.containsKey(id);

  /// The kind-of-bet properties for the first of [ids] the registry knows:
  /// market_category, event_tags (≤3), sports_league + is_live (sports
  /// only) and time_to_resolution_bucket. Falls back to [fallbackCategory]
  /// (the caller's coarse category) when the market was never seen.
  static Map<String, Object> pmKindParams(Iterable<String?> ids,
      {String? fallbackCategory}) {
    _PmKind? kind;
    for (final id in ids) {
      if (id == null || id.isEmpty) continue;
      kind = _pmKinds[id];
      if (kind != null) break;
    }
    if (kind == null) {
      final cat = fallbackCategory?.trim().toLowerCase();
      return {
        'market_category': (cat == null || cat.isEmpty) ? 'unknown' : cat,
      };
    }
    final sports = kind.category == 'sports';
    return {
      'market_category': kind.category,
      if (kind.tags.isNotEmpty) 'event_tags': kind.tags,
      if (sports && kind.league != null) 'sports_league': kind.league!,
      if (sports) 'is_live': kind.live,
      'time_to_resolution_bucket': resolutionBucket(kind.endMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(kind.endMs!)),
    };
  }

  /// market_category from the event's tags, else its coarse [category].
  static String marketCategory(String? category, List<String> tags) {
    final set = tags.map((t) => t.toLowerCase()).toSet();
    if (set.any(_leagues.containsKey)) return 'sports';
    for (final (name, match) in _categoryTags) {
      if (set.any(match.contains)) return name;
    }
    final c = (category ?? '').trim().toLowerCase();
    if (c.isEmpty) return 'other';
    if (c == 'science') return 'tech';
    return c;
  }

  /// Up to three descriptive tag slugs (public Gamma data), generic and
  /// plumbing tags removed, in the event's own order.
  static List<String> eventTags(List<String> tags) {
    final out = <String>[];
    for (final t in tags) {
      final s = t.trim().toLowerCase();
      if (s.isEmpty || _genericTags.contains(s) || out.contains(s)) continue;
      if (s.length > 40) continue;
      out.add(s);
      if (out.length == 3) break;
    }
    return out;
  }

  /// The league a sports market belongs to, from its tags, else its slug's
  /// prefix (Gamma sports slugs lead with it: `nba-lal-bos-2026-10-21`).
  static String? sportsLeague(
      String? category, List<String> tags, String? slug) {
    for (final t in tags) {
      final l = _leagues[t.toLowerCase()];
      // A generic sport name is a last resort; a real league beats it.
      if (l != null &&
          !const {'soccer', 'basketball', 'baseball', 'hockey'}.contains(l)) {
        return l;
      }
    }
    final prefix = (slug ?? '').split('-').first.toLowerCase();
    final fromSlug = _leagues[prefix];
    if (fromSlug != null) return fromSlug;
    for (final t in tags) {
      final l = _leagues[t.toLowerCase()];
      if (l != null) return l;
    }
    return null;
  }

  /// How far off resolution is: ended | <1h | 1-24h | 1-7d | 7-30d | 30d+ |
  /// unknown.
  static String resolutionBucket(DateTime? end, {DateTime? now}) {
    if (end == null) return 'unknown';
    final left = end.difference(now ?? DateTime.now());
    if (left.isNegative) return 'ended';
    if (left < const Duration(hours: 1)) return '<1h';
    if (left < const Duration(hours: 24)) return '1-24h';
    if (left < const Duration(days: 7)) return '1-7d';
    if (left < const Duration(days: 30)) return '7-30d';
    return '30d+';
  }

  static void _schedulePersist() {
    if (_persistTimer != null) return;
    _persistTimer = Timer(const Duration(seconds: 2), () {
      _persistTimer = null;
      final box = _box;
      if (box == null) return;
      try {
        unawaited(box.put(_pmKindsKey, {
          for (final e in _pmKinds.entries) e.key: e.value.toJson(),
        }).catchError((_) {}));
      } catch (_) {}
    });
  }

  // ─── Polymarket: Ledger bets confirmed later ─────────────────────

  static final Map<String, Map<String, Object?>> _ledgerPendingBets = {};

  /// A Ledger bet whose submission is still unconfirmed: remember what was
  /// entered so the "check status" that later confirms it can report the
  /// placed bet once. One per Ledger wallet (the device allows one).
  static void rememberLedgerPendingBet(
      String walletId, Map<String, Object?> bet) {
    _ledgerPendingBets[walletId] = bet;
    _persistLedgerBets();
  }

  /// Takes (and forgets) the pending bet for [walletId]: a second status
  /// check that confirms the same order finds nothing, so it reports once.
  static Map<String, Object?>? takeLedgerPendingBet(String walletId) {
    final bet = _ledgerPendingBets.remove(walletId);
    if (bet != null) _persistLedgerBets();
    return bet;
  }

  static void forgetLedgerPendingBet(String walletId) {
    if (_ledgerPendingBets.remove(walletId) != null) _persistLedgerBets();
  }

  static void _persistLedgerBets() {
    unawaited(() async {
      try {
        await warmUp();
        await _box?.put(_ledgerBetsKey, {
          for (final e in _ledgerPendingBets.entries) e.key: e.value,
        });
      } catch (_) {}
    }());
  }

  // ─── Hyperliquid: kind of trade ──────────────────────────────────

  static final Map<String, (String, String)> _hlMarkets = {};

  /// Records each market's asset class and dex under its display coin
  /// (per kind) and wire coin. Cheap; called with the browse universe.
  static void rememberHlMarket({
    required String coin,
    required String wireCoin,
    required bool isSpot,
    required String category,
    required String dex,
  }) {
    final v = (assetClass(category), dex.isEmpty ? 'main' : dex);
    final c = coin.toUpperCase();
    _hlMarkets[isSpot ? 'spot:$c' : 'perp:$c'] = v;
    if (wireCoin.isNotEmpty) _hlMarkets['wire:${wireCoin.toUpperCase()}'] = v;
  }

  static void rememberHlMarkets(Iterable<HlMarket> markets) {
    for (final m in markets) {
      rememberHlMarket(
        coin: m.coin,
        wireCoin: m.wireCoin,
        isSpot: m.isSpot,
        category: m.category,
        dex: m.dex,
      );
    }
  }

  /// asset_class + dex for [coin] (display or wire). Unknown coins default
  /// to crypto on the main dex, which is what the default dex lists.
  static Map<String, Object> hlAssetParams(String coin, {String? kind}) {
    final c = coin.toUpperCase();
    final hit = _hlMarkets['wire:$c'] ??
        (kind == 'spot' ? _hlMarkets['spot:$c'] : _hlMarkets['perp:$c']) ??
        _hlMarkets['perp:$c'] ??
        _hlMarkets['spot:$c'];
    if (hit != null) return {'asset_class': hit.$1, 'dex': hit.$2};
    if (c.contains(':')) {
      return {'asset_class': 'unknown', 'dex': c.split(':').first.toLowerCase()};
    }
    return {'asset_class': 'crypto', 'dex': 'main'};
  }

  /// Browse category → asset_class.
  static String assetClass(String category) {
    switch (category.trim().toLowerCase()) {
      case 'crypto':
        return 'crypto';
      case 'stocks':
      case 'stock':
      case 'preipo':
        return 'stock';
      case 'commodities':
      case 'commodity':
        return 'commodity';
      case 'fx':
      case 'forex':
        return 'fx';
      case 'rates':
        return 'rates';
      case 'indices':
      case 'index':
        return 'index';
      default:
        return 'other';
    }
  }

  // ─── Ticket settings staged for the outcome event ────────────────

  static const Duration _stageTtl = Duration(minutes: 3);
  static final Map<String, (DateTime, Map<String, Object>)> _staged = {};

  /// The ticket that is about to submit on [venue] for [key] (a token id
  /// or a coin): its settings and entry surface. The outcome helpers merge
  /// it, so the placed / failed event carries what was chosen. Replaces any
  /// earlier staging for the same key.
  static void stage(String venue, String key, Map<String, Object> params) {
    if (key.isEmpty) return;
    _staged['$venue|${key.toUpperCase()}'] = (DateTime.now(), params);
  }

  static Map<String, Object> staged(String venue, String? key) {
    if (key == null || key.isEmpty) return const {};
    final k = '$venue|${key.toUpperCase()}';
    final hit = _staged[k];
    if (hit == null) return const {};
    if (DateTime.now().difference(hit.$1) > _stageTtl) {
      _staged.remove(k);
      return const {};
    }
    return hit.$2;
  }

  static void unstage(String venue, String? key) {
    if (key == null || key.isEmpty) return;
    _staged.remove('$venue|${key.toUpperCase()}');
  }

  // ─── Setting changes, flows ──────────────────────────────────────

  static final Map<String, String> _lastSetting = {};

  /// One event per real change of a screen setting: the same value twice
  /// in a row (a rebuild, a re-tap of the selected chip) is dropped.
  /// [scope] separates independent copies of a setting (per coin, per
  /// ticket). Returns whether it was sent.
  static bool settingChanged(
    String event, {
    required String setting,
    required Object value,
    String? scope,
    Map<String, Object> extra = const {},
  }) {
    final key = '$event|$setting|${scope ?? ''}';
    final v = value.toString();
    if (_lastSetting[key] == v) return false;
    _lastSetting[key] = v;
    TrackingService.track(event, params: {
      'setting': setting,
      'value': value,
      ...extra,
    });
    return true;
  }

  /// Forget a scope's last values (a fresh ticket starts from defaults, so
  /// its first change must be sent even if an old ticket ended there).
  static void resetSettings(String scope) {
    _lastSetting.removeWhere((k, _) => k.endsWith('|$scope'));
  }

  /// Coarse time spent in a flow, for abandon/outcome events.
  static String timeInFlowBucket(Duration d) {
    final s = d.inSeconds;
    if (s < 10) return '<10s';
    if (s < 30) return '10-30s';
    if (s < 120) return '30s-2m';
    if (s < 600) return '2-10m';
    return '10m+';
  }

  /// Slippage percent → basis points (integer).
  static int bps(double pct) => (pct * 100).round();

  static void debugReset() {
    _pmKinds.clear();
    _hlMarkets.clear();
    _staged.clear();
    _lastSetting.clear();
    _ledgerPendingBets.clear();
    _persistTimer?.cancel();
    _persistTimer = null;
  }
}

class _PmKind {
  const _PmKind({
    required this.category,
    required this.tags,
    required this.league,
    required this.endMs,
    required this.live,
    this.eventId,
    this.eventSlug,
    this.eventTitle,
  });

  final String category;
  final List<String> tags;
  final String? league;
  final int? endMs;
  final bool live;

  /// The parent event: its Gamma id, slug and title (80 characters).
  final String? eventId;
  final String? eventSlug;
  final String? eventTitle;

  Map<String, Object?> toJson() => {
        'c': category,
        't': tags,
        'l': league,
        'e': endMs,
        'v': live,
        if (eventId != null) 'i': eventId,
        if (eventSlug != null) 's': eventSlug,
        if (eventTitle != null) 'n': eventTitle,
      };

  static _PmKind? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final c = raw['c'];
    if (c is! String) return null;
    final t = raw['t'];
    return _PmKind(
      category: c,
      tags: t is List ? [for (final x in t) x.toString()] : const [],
      league: raw['l'] as String?,
      endMs: raw['e'] as int?,
      live: raw['v'] == true,
      eventId: raw['i'] as String?,
      eventSlug: raw['s'] as String?,
      eventTitle: raw['n'] as String?,
    );
  }
}
