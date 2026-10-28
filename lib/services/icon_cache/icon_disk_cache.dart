// lib/services/icon_cache/icon_disk_cache.dart
//
// The logos the market lists draw (Hyperliquid coin SVGs, the coin and
// chain marks of the Send/Receive grids) kept on disk between launches.
//
// Why: flutter_svg has no disk cache, and the loaders in front of it kept
// their bytes in memory only, so every cold start downloaded every logo
// again. Worse, a Hyperliquid market whose own logo does not exist walks
// a chain of candidates (its dex, its twins on other dexes, a stock-logo
// host), and the misses were forgotten too: a stock row re-probed up to
// ten URLs one after the other on every launch before its logo showed.
//
// What is kept, per URL:
//   * a hit: the bytes the icon draws, AFTER the loader's repairs and
//     parse check, so a cached logo is never processed twice;
//   * a miss: only a definitive one (the venue's HTML catch-all, a 404,
//     an SVG flutter_svg cannot parse). A timeout or a transport error is
//     never written, so a bad network never hides a logo for days.
// Hits are served for [hitTtl] and then served stale while the caller
// refreshes them; misses expire after [missTtl], so a logo the venue adds
// later shows up within days.
//
// The index (url -> kind, saved-at, last-used) is one small JSON file,
// read once when the cache opens and written debounced; the bytes are one
// file per URL, named by its SHA-1. The last-used times give the list of
// logos to warm into memory on the next launch, which is what makes a
// second cold start draw its icons on the first frame.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha1;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// What the cache knows about one URL.
enum IconCacheKind {
  /// A vector document (the bytes are the repaired SVG).
  svg,

  /// A raster (PNG/JPEG/WebP) the loader took out of the response.
  raster,

  /// A definitive miss: nothing at this URL to draw.
  miss,
}

/// One index row: what is cached and whether it is still fresh.
@immutable
class IconCacheEntry {
  const IconCacheEntry(
      {required this.kind, required this.savedAt, required this.fresh});
  final IconCacheKind kind;
  final DateTime savedAt;

  /// False once a hit is past the cache's hitTtl (still served, refreshed
  /// by the caller) or a miss is past its missTtl (ignored).
  final bool fresh;

  bool get isMiss => kind == IconCacheKind.miss;
}

class IconDiskCache {
  IconDiskCache._(
    this.dir, {
    required this.hitTtl,
    required this.missTtl,
    required this.maxEntries,
    required this.flushDelay,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// The folder holding the index and the bytes.
  final Directory dir;

  /// How long a hit is fresh. Logos rarely change.
  final Duration hitTtl;

  /// How long a definitive miss is believed.
  final Duration missTtl;

  /// Rows kept at most; the least recently used go first.
  final int maxEntries;

  /// How long index changes wait before they are written together.
  final Duration flushDelay;

  final DateTime Function() _clock;

  /// url -> [kind index, savedAt ms, usedAt ms].
  final Map<String, List<int>> _index = {};
  Timer? _flushTimer;
  bool _dirty = false;
  Future<void>? _writing;

  static const String _indexName = 'index.json';
  static const int _version = 1;

  /// Opens (creating when needed) the cache in [dir]. Never throws: an
  /// unreadable index starts empty.
  static Future<IconDiskCache> open(
    Directory dir, {
    Duration hitTtl = const Duration(days: 30),
    Duration missTtl = const Duration(days: 3),
    int maxEntries = 3000,
    Duration flushDelay = const Duration(seconds: 2),
    DateTime Function()? clock,
  }) async {
    final cache = IconDiskCache._(dir,
        hitTtl: hitTtl,
        missTtl: missTtl,
        maxEntries: maxEntries,
        flushDelay: flushDelay,
        clock: clock);
    await cache._load();
    return cache;
  }

  Future<void> _load() async {
    try {
      await dir.create(recursive: true);
      final file = File('${dir.path}/$_indexName');
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map || decoded['v'] != _version) return;
      final rows = decoded['e'];
      if (rows is! Map) return;
      for (final MapEntry(:key, :value) in rows.entries) {
        if (key is! String || value is! List || value.length != 3) continue;
        final row = value.whereType<int>().toList();
        if (row.length != 3 || row[0] < 0 || row[0] >= 3) continue;
        _index[key] = row;
      }
    } catch (_) {
      _index.clear();
    }
    _prune();
  }

  /// Expired misses go, and past [maxEntries] the least recently used
  /// rows (and their bytes) go.
  void _prune() {
    final now = _clock().millisecondsSinceEpoch;
    final expired = [
      for (final e in _index.entries)
        if (e.value[0] == IconCacheKind.miss.index &&
            now - e.value[1] > missTtl.inMilliseconds)
          e.key
    ];
    for (final url in expired) {
      _index.remove(url);
    }
    var changed = expired.isNotEmpty;
    if (_index.length > maxEntries) {
      final byUse = _index.entries.toList()
        ..sort((a, b) => a.value[2].compareTo(b.value[2]));
      for (final e in byUse.take(_index.length - maxEntries)) {
        _index.remove(e.key);
        if (e.value[0] != IconCacheKind.miss.index) {
          _deleteQuietly(_blob(e.key));
        }
      }
      changed = true;
    }
    if (changed) _markDirty();
  }

  /// What the cache holds for [url], or null when it holds nothing (an
  /// expired miss counts as nothing).
  IconCacheEntry? lookup(String url) {
    final row = _index[url];
    if (row == null) return null;
    final kind = IconCacheKind.values[row[0]];
    final age = _clock().millisecondsSinceEpoch - row[1];
    if (kind == IconCacheKind.miss) {
      if (age > missTtl.inMilliseconds) return null;
      return IconCacheEntry(
          kind: kind,
          savedAt: DateTime.fromMillisecondsSinceEpoch(row[1]),
          fresh: true);
    }
    return IconCacheEntry(
        kind: kind,
        savedAt: DateTime.fromMillisecondsSinceEpoch(row[1]),
        fresh: age <= hitTtl.inMilliseconds);
  }

  /// The cached bytes of [url], or null when there are none (a miss, or
  /// a file the OS cleared from the caches folder: that row is dropped).
  Future<Uint8List?> read(String url) async {
    final row = _index[url];
    if (row == null || row[0] == IconCacheKind.miss.index) return null;
    try {
      return await _blob(url).readAsBytes();
    } catch (_) {
      _index.remove(url);
      _markDirty();
      return null;
    }
  }

  /// Keeps [bytes] as the logo at [url]. [flush] waits for it.
  Future<void> putHit(String url, Uint8List bytes, {bool raster = false}) {
    final write = _writeHit(url, bytes, raster);
    _pendingHits.add(write);
    return write.whenComplete(() => _pendingHits.remove(write));
  }

  final Set<Future<void>> _pendingHits = {};

  Future<void> _writeHit(String url, Uint8List bytes, bool raster) async {
    try {
      await dir.create(recursive: true);
      final target = _blob(url);
      final tmp = File('${target.path}.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(target.path);
    } catch (_) {
      return; // A full disk only costs the next launch a download.
    }
    final now = _clock().millisecondsSinceEpoch;
    _index[url] = [
      (raster ? IconCacheKind.raster : IconCacheKind.svg).index,
      now,
      now,
    ];
    _markDirty();
  }

  /// Remembers that [url] has nothing to draw.
  void putMiss(String url) {
    final now = _clock().millisecondsSinceEpoch;
    final old = _index[url];
    if (old != null && old[0] != IconCacheKind.miss.index) {
      _deleteQuietly(_blob(url));
    }
    _index[url] = [IconCacheKind.miss.index, now, now];
    _markDirty();
  }

  /// Notes that [url] was drawn now, for the next launch's warm list.
  /// Rewrites the index at most once a minute per URL.
  void touch(String url) {
    final row = _index[url];
    if (row == null) return;
    final now = _clock().millisecondsSinceEpoch;
    if (now - row[2] < 60 * 1000) return;
    row[2] = now;
    _markDirty();
  }

  /// Cached logos (not misses), most recently drawn first.
  List<String> recentHits(int limit) {
    final hits = [
      for (final e in _index.entries)
        if (e.value[0] != IconCacheKind.miss.index) e
    ]..sort((a, b) => b.value[2].compareTo(a.value[2]));
    return [for (final e in hits.take(limit)) e.key];
  }

  /// Every URL with a definitive miss that is still believed.
  List<String> freshMisses() {
    final now = _clock().millisecondsSinceEpoch;
    return [
      for (final e in _index.entries)
        if (e.value[0] == IconCacheKind.miss.index &&
            now - e.value[1] <= missTtl.inMilliseconds)
          e.key
    ];
  }

  int get length => _index.length;

  void _markDirty() {
    _dirty = true;
    _flushTimer?.cancel();
    _flushTimer = Timer(flushDelay, () => unawaited(flush()));
  }

  /// Writes the index now (atomically: a temp file renamed over it),
  /// after any logo still being written.
  Future<void> flush() async {
    if (_pendingHits.isNotEmpty) await Future.wait(_pendingHits.toList());
    _flushTimer?.cancel();
    _flushTimer = null;
    final pending = _writing;
    if (pending != null) await pending;
    if (!_dirty) return;
    _dirty = false;
    final json = jsonEncode({'v': _version, 'e': _index});
    final write = () async {
      try {
        await dir.create(recursive: true);
        final tmp = File('${dir.path}/$_indexName.tmp');
        await tmp.writeAsString(json, flush: true);
        await tmp.rename('${dir.path}/$_indexName');
      } catch (_) {
        _dirty = true;
      }
    }();
    _writing = write;
    await write;
    _writing = null;
  }

  File _blob(String url) =>
      File('${dir.path}/${sha1.convert(utf8.encode(url))}');

  static void _deleteQuietly(File f) {
    f.delete().then((_) {}, onError: (_) {});
  }
}

/// The app's two icon caches, opened once at boot ([init]). Both stay null
/// where nothing opened them (widget tests), and every loader then works
/// from memory and the network exactly as before.
abstract final class IconCaches {
  /// Hyperliquid coin and stock logos (HlCoinIcon).
  static Future<IconDiskCache?>? hyperliquid;

  /// Coin and chain marks served as SVG (SafeSvgNetwork).
  static Future<IconDiskCache?>? artwork;

  /// Whether background prefetching runs. On once boot opened the caches
  /// ([init]); off in widget and provider tests, where a list landing
  /// must not start downloads nobody asked for.
  static bool prefetchEnabled = false;

  /// Opens both caches under the app's caches folder (which the OS may
  /// clear under storage pressure: the icons are then just downloaded
  /// again). Idempotent. Never throws.
  static void init() {
    if (hyperliquid != null) return;
    final root = () async {
      try {
        return await getApplicationCacheDirectory();
      } catch (_) {
        return await getTemporaryDirectory();
      }
    }();
    Future<IconDiskCache?> openAt(String name) async {
      try {
        final base = await root;
        return await IconDiskCache.open(Directory('${base.path}/icons/$name'));
      } catch (e) {
        if (kDebugMode) debugPrint('IconCaches: $name unavailable ($e)');
        return null;
      }
    }

    hyperliquid = openAt('hyperliquid');
    artwork = openAt('artwork');
    prefetchEnabled = true;
  }

  /// Tests: point the caches at given instances (or back to none), and
  /// switch prefetching on or off.
  @visibleForTesting
  static void debugSet(
      {IconDiskCache? hyperliquid,
      IconDiskCache? artwork,
      bool prefetch = false}) {
    IconCaches.hyperliquid =
        hyperliquid == null ? null : Future.value(hyperliquid);
    IconCaches.artwork = artwork == null ? null : Future.value(artwork);
    prefetchEnabled = prefetch;
  }

  /// Resolves [future] to its cache, or null when it failed to open.
  static Future<IconDiskCache?> resolve(Future<IconDiskCache?>? future) async {
    if (future == null) return null;
    try {
      return await future;
    } catch (_) {
      return null;
    }
  }
}

/// Runs [task] over [items] with at most [concurrency] running at once,
/// in order. Resolves when all are done; a task's error is swallowed (one
/// logo failing must not stop the others).
Future<void> runBounded<T>(
    Iterable<T> items, int concurrency, Future<void> Function(T) task) async {
  final queue = items.toList();
  var next = 0;
  Future<void> worker() async {
    while (next < queue.length) {
      final item = queue[next++];
      try {
        await task(item);
      } catch (_) {}
    }
  }

  final n = concurrency < 1 ? 1 : concurrency;
  await Future.wait([
    for (var i = 0; i < n && i < queue.length; i++) worker(),
  ]);
}

/// Counters for the debug log and the tests: where icons came from this
/// session.
abstract final class IconLoadStats {
  static int network = 0;
  static int disk = 0;

  @visibleForTesting
  static void reset() {
    network = 0;
    disk = 0;
  }
}
