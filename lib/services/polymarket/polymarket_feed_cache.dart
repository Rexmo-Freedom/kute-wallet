// lib/services/polymarket/polymarket_feed_cache.dart
//
// The last Predictions feed this device saw, on disk, so the screen paints
// at once on the next open while Gamma answers (the same design as the
// Hyperliquid list cache, hl_markets_disk_cache.dart). Parsed events are
// stored, not Gamma's JSON: a Gamma event carries every sub-market with its
// full description and weighs about 120 KB, while the parsed card is a few
// hundred bytes. Prices on a cached card are stale by definition; the live
// price feed and then the live feed replace them as soon as they land.
//
// Public market data only: events, outcomes, token ids and tags. Nothing
// about the person's account is ever written here.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/polymarket_model.dart';

class PolymarketFeedCache {
  PolymarketFeedCache._();
  static final instance = PolymarketFeedCache._();

  static const boxName = 'polymarket_feed_cache_v1';

  /// Older than this a snapshot is not worth painting (the Hyperliquid
  /// list cache's limit). Anything younger is drawn and then replaced.
  static const maxAge = Duration(days: 3);

  /// Event snapshots kept on disk, least recently saved dropped first. The
  /// box is read whole at launch, so it is kept bounded; a first page of
  /// twenty parsed cards is a few tens of KB, so this holds every pill
  /// plus the chips opened (and prefetched) lately.
  static const maxEventEntries = 48;
  static const maxEventBytes = 4 * 1024 * 1024;

  static const _version = 1;
  static const _indexKey = '_events_index';

  /// What was read or written this session, so a screen can ask on every
  /// build without touching the disk again.
  final Map<String, ({DateTime savedAt, List<PolymarketEvent> events})?>
      _events = {};
  final Map<String, ({DateTime savedAt, List<Map<String, dynamic>> rows})?>
      _tagRows = {};

  Box<String>? _box() {
    try {
      return Hive.isBoxOpen(boxName) ? Hive.box<String>(boxName) : null;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _read(String key) {
    final box = _box();
    if (box == null) return null;
    try {
      final raw = box.get(key);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> || decoded['v'] != _version) {
        return null;
      }
      return decoded;
    } catch (e) {
      if (kDebugMode) debugPrint('[pm-feed-cache] $key unreadable: $e');
      return null;
    }
  }

  static DateTime _savedAt(Map<String, dynamic> decoded) =>
      DateTime.fromMillisecondsSinceEpoch(
          (decoded['savedAt'] as num?)?.toInt() ?? 0);

  static bool _fresh(DateTime savedAt) =>
      DateTime.now().difference(savedAt) <= maxAge;

  /// Writes one snapshot; returns its encoded size, or null when it could
  /// not be written.
  Future<int?> _write(String key, Object rows, DateTime savedAt) async {
    final box = _box();
    if (box == null) return null;
    try {
      final encoded = jsonEncode({
        'v': _version,
        'savedAt': savedAt.millisecondsSinceEpoch,
        'rows': rows,
      });
      await box.put(key, encoded);
      return encoded.length;
    } catch (e) {
      if (kDebugMode) debugPrint('[pm-feed-cache] $key not saved: $e');
      return null;
    }
  }

  /// The cached events under [key], or null when there are none worth
  /// showing. Read from disk once per session; later calls are free, so a
  /// screen can call this while it builds.
  List<PolymarketEvent>? readEvents(String key) {
    if (!_events.containsKey(key)) _events[key] = _readEventsFromDisk(key);
    final hit = _events[key];
    if (hit == null || !_fresh(hit.savedAt)) return null;
    return hit.events;
  }

  ({DateTime savedAt, List<PolymarketEvent> events})? _readEventsFromDisk(
      String key) {
    final decoded = _read(key);
    final rows = decoded?['rows'];
    if (decoded == null || rows is! List) return null;
    final out = <PolymarketEvent>[];
    for (final r in rows) {
      if (r is! Map<String, dynamic>) continue;
      try {
        out.add(eventFromJson(r));
      } catch (_) {
        // One bad row must not cost the whole snapshot.
      }
    }
    return out.isEmpty ? null : (savedAt: _savedAt(decoded), events: out);
  }

  /// Saves [events] under [key] (at most [max] of them) and drops the
  /// oldest snapshots past [maxEventEntries] / [maxEventBytes].
  Future<void> writeEvents(String key, List<PolymarketEvent> events,
      {int max = 40}) async {
    if (events.isEmpty) return;
    final kept = events.take(max).toList(growable: false);
    final savedAt = DateTime.now();
    _events[key] = (savedAt: savedAt, events: kept);
    final bytes =
        await _write(key, kept.map(eventToJson).toList(), savedAt);
    if (bytes == null) return;
    // Sections save in parallel; one trim at a time keeps the index whole.
    final trim = _trimming.then((_) => _trimEvents(key, savedAt, bytes));
    _trimming = trim;
    await trim;
  }

  Future<void> _trimming = Future.value();

  /// Keeps the event snapshots within the caps, oldest out first. The
  /// index ({key: [savedAtMs, bytes]}) saves decoding every snapshot to
  /// learn its age; a snapshot from before the index counts as oldest.
  Future<void> _trimEvents(String key, DateTime savedAt, int bytes) async {
    final box = _box();
    if (box == null) return;
    try {
      final index = <String, List<int>>{};
      final raw = box.get(_indexKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          decoded.forEach((k, v) {
            if (v is List && v.length == 2 && v.every((n) => n is num)) {
              index[k] = [(v[0] as num).toInt(), (v[1] as num).toInt()];
            }
          });
        }
      }
      for (final k in box.keys) {
        if (k is! String || k == _indexKey || index.containsKey(k)) continue;
        if (k == key ||
            k.startsWith('tag_preview_') ||
            k.startsWith('browse_')) {
          index[k] = [0, box.get(k)?.length ?? 0];
        }
      }
      index[key] = [savedAt.millisecondsSinceEpoch, bytes];
      index.removeWhere((k, _) => !box.containsKey(k));

      final oldestFirst = index.keys.toList()
        ..sort((a, b) => index[a]![0].compareTo(index[b]![0]));
      var total = index.values.fold<int>(0, (sum, v) => sum + v[1]);
      final drop = <String>[];
      for (final k in oldestFirst) {
        if (index.length - drop.length <= maxEventEntries &&
            total <= maxEventBytes) {
          break;
        }
        if (k == key) continue;
        drop.add(k);
        total -= index[k]![1];
      }
      for (final k in drop) {
        index.remove(k);
        _events.remove(k);
      }
      if (drop.isNotEmpty) await box.deleteAll(drop);
      await box.put(_indexKey, jsonEncode(index));
    } catch (e) {
      if (kDebugMode) debugPrint('[pm-feed-cache] trim failed: $e');
    }
  }

  /// Raw Gamma tag rows, as the tag model parses them. Free after the
  /// first read, like [readEvents].
  List<Map<String, dynamic>>? readTagRows(String key) {
    if (!_tagRows.containsKey(key)) {
      final decoded = _read(key);
      final rows = decoded?['rows'];
      final out = rows is List
          ? rows.whereType<Map<String, dynamic>>().toList()
          : const <Map<String, dynamic>>[];
      _tagRows[key] = decoded == null || out.isEmpty
          ? null
          : (savedAt: _savedAt(decoded), rows: out);
    }
    final hit = _tagRows[key];
    if (hit == null || !_fresh(hit.savedAt)) return null;
    return hit.rows;
  }

  /// When the rows under [key] were saved, or null when there are none.
  DateTime? tagRowsSavedAt(String key) {
    if (readTagRows(key) == null) return null;
    return _tagRows[key]?.savedAt;
  }

  /// Forgets what this session read or wrote, for tests.
  @visibleForTesting
  void debugClearMemory() {
    _events.clear();
    _tagRows.clear();
  }

  Future<void> writeTagRows(
      String key, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    final savedAt = DateTime.now();
    _tagRows[key] = (savedAt: savedAt, rows: rows);
    await _write(key, rows, savedAt);
  }

  static Map<String, dynamic> eventToJson(PolymarketEvent e) => {
        'id': e.id,
        'slug': e.slug,
        'title': e.title,
        'imageUrl': e.imageUrl,
        'volume': e.volume,
        'volume24hr': e.volume24hr,
        'liquidity': e.liquidity,
        'category': e.category,
        'startDate': e.startDate?.toIso8601String(),
        'gameStart': e.gameStart?.toIso8601String(),
        'startTime': e.startTime?.toIso8601String(),
        'finishedAt': e.finishedAt?.toIso8601String(),
        'endDate': e.endDate?.toIso8601String(),
        'active': e.active,
        'closed': e.closed,
        'description': e.description,
        'conditionId': e.conditionId,
        'outcomes': e.outcomes.map(_outcomeToJson).toList(),
        'streamUrl': e.streamUrl,
        'isLive': e.isLive,
        'gameId': e.gameId,
        'score': e.score,
        'period': e.period,
        'elapsed': e.elapsed,
        'ended': e.ended,
        'negRisk': e.negRisk,
        'teams': e.teams.map(_teamToJson).toList(),
        'isSyntheticBinary': e.isSyntheticBinary,
        'tags': e.tags,
        'oneDayPriceChange': e.oneDayPriceChange,
        'seriesId': e.seriesId,
      };

  static PolymarketEvent eventFromJson(Map<String, dynamic> j) =>
      PolymarketEvent(
        id: j['id'] as String,
        slug: j['slug'] as String,
        title: j['title'] as String,
        imageUrl: j['imageUrl'] as String?,
        volume: (j['volume'] as num?)?.toDouble() ?? 0,
        volume24hr: (j['volume24hr'] as num?)?.toDouble() ?? 0,
        liquidity: (j['liquidity'] as num?)?.toDouble() ?? 0,
        category: j['category'] as String? ?? '',
        startDate: _date(j['startDate']),
        gameStart: _date(j['gameStart']),
        startTime: _date(j['startTime']),
        finishedAt: _date(j['finishedAt']),
        endDate: _date(j['endDate']),
        active: j['active'] as bool? ?? true,
        closed: j['closed'] as bool? ?? false,
        description: j['description'] as String?,
        conditionId: j['conditionId'] as String? ?? '',
        outcomes: ((j['outcomes'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(_outcomeFromJson)
            .toList(),
        streamUrl: j['streamUrl'] as String?,
        isLive: j['isLive'] as bool? ?? false,
        gameId: (j['gameId'] as num?)?.toInt(),
        score: j['score'] as String?,
        period: j['period'] as String?,
        elapsed: j['elapsed'] as String?,
        ended: j['ended'] as bool? ?? false,
        negRisk: j['negRisk'] as bool? ?? false,
        teams: ((j['teams'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(_teamFromJson)
            .toList(),
        isSyntheticBinary: j['isSyntheticBinary'] as bool? ?? false,
        tags: [for (final t in (j['tags'] as List?) ?? const []) '$t'],
        oneDayPriceChange: (j['oneDayPriceChange'] as num?)?.toDouble(),
        seriesId: j['seriesId'] as String?,
      );

  static DateTime? _date(Object? v) =>
      v is String ? DateTime.tryParse(v) : null;

  static Map<String, dynamic> _outcomeToJson(PolymarketOutcome o) => {
        'gammaMarketId': o.gammaMarketId,
        'name': o.name,
        'price': o.price,
        'tokenId': o.tokenId,
        'noTokenId': o.noTokenId,
        'imageUrl': o.imageUrl,
        'volume': o.volume,
        'conditionId': o.conditionId,
        if (o.unpriced) 'unpriced': true,
      };

  static PolymarketOutcome _outcomeFromJson(Map<String, dynamic> j) =>
      PolymarketOutcome(
        gammaMarketId: j['gammaMarketId'] as String?,
        name: j['name'] as String? ?? '',
        price: (j['price'] as num?)?.toDouble() ?? 0,
        tokenId: j['tokenId'] as String?,
        noTokenId: j['noTokenId'] as String?,
        imageUrl: j['imageUrl'] as String?,
        volume: (j['volume'] as num?)?.toDouble(),
        conditionId: j['conditionId'] as String?,
        unpriced: j['unpriced'] == true,
      );

  static Map<String, dynamic> _teamToJson(PolymarketTeam t) => {
        'name': t.name,
        'logo': t.logo,
        'abbreviation': t.abbreviation,
        'alias': t.alias,
        'ordering': t.ordering,
      };

  static PolymarketTeam _teamFromJson(Map<String, dynamic> j) =>
      PolymarketTeam(
        name: j['name'] as String? ?? '',
        logo: j['logo'] as String?,
        abbreviation: j['abbreviation'] as String?,
        alias: j['alias'] as String?,
        ordering: j['ordering'] as String?,
      );
}
