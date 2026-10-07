// lib/services/hyperliquid/hl_sparkline_cache.dart
//
// The daily closes behind the Investing cards' sparklines, kept on the
// device so a card draws its line at once and the venue is asked for a
// coin's 90 daily candles at most once per UTC day.
//
// Daily candles only change once a day: the last one is today's, still
// forming, and the card already redraws that point from the live price
// it shows. So a series fetched today is reused as is, all day, on every
// open; a series from an earlier UTC day is drawn at once and refetched
// behind it (one request per coin per UTC day, plus one at first sight).
//
// Requests only start for cards that are built (the lists build lazily),
// at most [HlSparklineStore.maxInFlight] at a time; a card scrolled away
// before its turn drops out of the queue.
//
// Disk: the 'hyperliquid_sparklines_v1' Hive box (public market data),
// keyed by wire coin, one compact string per coin: 'v1;<utcDay>;<closes>'.
// Bounded to the [HlSparklineStore.maxEntries] most recent coins and
// [HlSparklineStore.retentionDays] days. Thin markets draw no line and
// never ask (the card does not watch them).

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';

/// Days since the epoch, in UTC: the day a daily candle belongs to.
int hlUtcDay(DateTime t) =>
    t.toUtc().millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;

/// One coin's cached sparkline: its daily closes (oldest first) and the
/// UTC day they were fetched on.
@immutable
class HlSparkline {
  final List<double> closes;
  final int day;
  const HlSparkline({required this.closes, required this.day});
}

/// The closes a card plots: the series with its live end. A series
/// fetched today ends on today's forming candle, whose close is replaced
/// by [livePrice]; an older series (refetch pending) gets today's live
/// price appended as its last point. Nothing else is touched.
///
/// UNIT GUARD: spot pair candles come back in RAW pair units (UBTC's
/// closes are ~0.00007 while the card shows ~110k). When the magnitudes
/// disagree by more than 2x the whole series is rescaled onto the live
/// price's units first (a pure linear factor: the shape is kept), rather
/// than splicing the live price onto raw closes ("flat line then a
/// rocket at the end").
List<double> hlSparklineWithLivePrice(
  List<double> closes,
  double livePrice, {
  bool appendLive = false,
}) {
  // Non-positive closes (a candle that failed to parse) would pin the
  // line's min to zero.
  var out = closes.where((v) => v > 0).toList();
  // One daily candle (listed under a day ago): the line needs two points.
  if (out.length == 1) out = [out.first, out.first];
  if (out.isEmpty || livePrice <= 0) return out;
  final ratio = livePrice / out.last;
  if (ratio < 0.5 || ratio > 2.0) {
    return out.map((v) => v * ratio).toList(growable: false);
  }
  if (appendLive) {
    out.add(livePrice);
  } else {
    out[out.length - 1] = livePrice;
  }
  return out;
}

/// Fetches one coin's daily closes (oldest first); empty on failure.
typedef HlSparklineFetch = Future<List<double>> Function(String wireCoin);

class HlSparklineStore {
  HlSparklineStore({
    required HlSparklineFetch fetch,
    DateTime Function()? now,
    this.maxInFlight = 4,
    this.boxName = defaultBoxName,
  })  : _fetch = fetch,
        _now = now ?? DateTime.now;

  static const defaultBoxName = 'hyperliquid_sparklines_v1';

  /// Coins kept on disk; the oldest fetches go first beyond it.
  static const maxEntries = 300;

  /// A series older than this is not drawn and is dropped from disk.
  static const retentionDays = 30;

  /// After a failed (or empty) answer, the coin is not asked again
  /// sooner than this in the session.
  static const retryAfter = Duration(minutes: 15);

  final HlSparklineFetch _fetch;
  final DateTime Function() _now;
  final int maxInFlight;
  final String boxName;

  final Map<String, HlSparkline> _memory = {};
  final Set<String> _missing = {};
  final Queue<String> _queue = Queue();
  final Set<String> _inFlight = {};
  final Map<String, DateTime> _failedAt = {};
  final Map<String, Set<void Function(HlSparkline)>> _listeners = {};
  bool _pruned = false;

  int get _today => hlUtcDay(_now());

  /// Requests started and not yet answered.
  @visibleForTesting
  int get inFlight => _inFlight.length;

  /// Coins waiting for a free slot.
  @visibleForTesting
  List<String> get queued => List.unmodifiable(_queue);

  Box<String>? _box() {
    try {
      return Hive.isBoxOpen(boxName) ? Hive.box<String>(boxName) : null;
    } catch (_) {
      return null;
    }
  }

  /// The series to draw for [wire] right now (memory, else disk), or null.
  /// A series past [retentionDays] is not drawn.
  HlSparkline? cached(String wire) {
    var s = _memory[wire];
    if (s == null && !_missing.contains(wire)) {
      s = _readDisk(wire);
      if (s == null) {
        _missing.add(wire);
      } else {
        _memory[wire] = s;
      }
    }
    if (s == null || _today - s.day > retentionDays) return null;
    return s;
  }

  /// Makes sure [wire] has today's series: nothing when it already has,
  /// is on its way, or failed moments ago; otherwise queued.
  void request(String wire) {
    final s = cached(wire);
    if (s != null && s.day >= _today) return;
    if (_inFlight.contains(wire) || _queue.contains(wire)) return;
    final failed = _failedAt[wire];
    if (failed != null && _now().difference(failed) < retryAfter) return;
    _queue.add(wire);
    _pump();
  }

  /// The card for [wire] is gone: if its request has not started, it is
  /// dropped (a request in flight completes and is cached).
  void cancel(String wire) => _queue.remove(wire);

  /// Calls [onData] whenever a new series for [wire] lands.
  VoidCallback listen(String wire, void Function(HlSparkline) onData) {
    final set = _listeners.putIfAbsent(wire, () => {});
    set.add(onData);
    return () {
      set.remove(onData);
      if (set.isEmpty) _listeners.remove(wire);
    };
  }

  void _pump() {
    while (_inFlight.length < maxInFlight && _queue.isNotEmpty) {
      final wire = _queue.removeFirst();
      _inFlight.add(wire);
      unawaited(_run(wire));
    }
  }

  Future<void> _run(String wire) async {
    List<double> closes;
    try {
      closes = await _fetch(wire);
    } catch (_) {
      closes = const [];
    }
    _inFlight.remove(wire);
    if (closes.isEmpty) {
      _failedAt[wire] = _now();
    } else {
      _failedAt.remove(wire);
      final s = HlSparkline(closes: List.unmodifiable(closes), day: _today);
      _memory[wire] = s;
      _missing.remove(wire);
      _writeDisk(wire, s);
      for (final l in List.of(_listeners[wire] ?? const <void Function(HlSparkline)>{})) {
        l(s);
      }
    }
    _pump();
  }

  // ── Disk ────────────────────────────────────────────────────────────

  static String encode(HlSparkline s) => 'v1;${s.day};${s.closes.join(',')}';

  static HlSparkline? decode(String raw) {
    final parts = raw.split(';');
    if (parts.length != 3 || parts[0] != 'v1') return null;
    final day = int.tryParse(parts[1]);
    if (day == null || parts[2].isEmpty) return null;
    final closes = <double>[];
    for (final v in parts[2].split(',')) {
      final d = double.tryParse(v);
      if (d == null) return null;
      closes.add(d);
    }
    return HlSparkline(closes: List.unmodifiable(closes), day: day);
  }

  static int? _dayOf(String raw) {
    final a = raw.indexOf(';');
    final b = a < 0 ? -1 : raw.indexOf(';', a + 1);
    return b < 0 ? null : int.tryParse(raw.substring(a + 1, b));
  }

  HlSparkline? _readDisk(String wire) {
    final box = _box();
    if (box == null) return null;
    _pruneOnce(box);
    try {
      final raw = box.get(wire);
      return raw == null ? null : decode(raw);
    } catch (e) {
      if (kDebugMode) debugPrint('[hl-spark] $wire unreadable: $e');
      return null;
    }
  }

  void _writeDisk(String wire, HlSparkline s) {
    final box = _box();
    if (box == null) return;
    try {
      unawaited(box.put(wire, encode(s)).then((_) {
        if (box.length > maxEntries) prune(box);
      }, onError: (Object e) {
        if (kDebugMode) debugPrint('[hl-spark] $wire not saved: $e');
      }));
    } catch (e) {
      if (kDebugMode) debugPrint('[hl-spark] $wire not saved: $e');
    }
  }

  void _pruneOnce(Box<String> box) {
    if (_pruned) return;
    _pruned = true;
    prune(box);
  }

  /// Drops series past [retentionDays] (and unreadable rows), then the
  /// oldest beyond [maxEntries].
  @visibleForTesting
  void prune(Box<String> box) {
    try {
      final today = _today;
      final drop = <dynamic>[];
      final kept = <MapEntry<dynamic, int>>[];
      for (final key in box.keys) {
        final raw = box.get(key);
        final day = raw == null ? null : _dayOf(raw);
        if (day == null || today - day > retentionDays) {
          drop.add(key);
        } else {
          kept.add(MapEntry(key, day));
        }
      }
      if (kept.length > maxEntries) {
        kept.sort((a, b) => b.value.compareTo(a.value));
        drop.addAll(kept.skip(maxEntries).map((e) => e.key));
      }
      if (drop.isEmpty) return;
      for (final k in drop) {
        _memory.remove(k);
      }
      unawaited(box.deleteAll(drop).catchError((_) {}));
    } catch (e) {
      if (kDebugMode) debugPrint('[hl-spark] prune failed: $e');
    }
  }
}
