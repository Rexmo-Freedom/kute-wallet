// lib/services/polymarket/poly_card_spark_store.dart
//
// The price history behind the Predictions list cards' tiny charts
// (founder, 12 November 2026: the leader's 7-day line on a card with many
// outcomes, the Yes line on a Yes/No card, the leader's win chance since
// kickoff on a game in play). The same `prices-history` series the market
// sheet's chart reads (PolyPriceHistoryCache: its session cache, its
// hedged read and its disk copy), asked for card by card with care for a
// long, fast-scrolling list:
//
//   * only cards that are built ask (the lists build lazily), and a card
//     disposed before its turn drops out of the queue;
//   * asks are collected for [PolyCardSparkStore.debounce] after the last
//     one, so a fling asks for nothing and a list that comes to rest asks
//     for the cards on screen in one batch, at most
//     [PolyCardSparkStore.maxInFlight] reads at a time (the endpoint takes
//     one token per read), the same token asked once whoever shows it;
//   * a series is kept in memory for [PolyCardSparkStore.freshFor] (2
//     minutes for a game in play's line) and not asked again in that time;
//     a series the session or the disk already holds is drawn at once;
//   * a card never waits: until its series lands it draws nothing.
//
// Public market data only: token ids, times and prices.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:kute/models/polymarket_model.dart';

/// Reads one token's series for one range (`1w`, `6h`); null on failure.
typedef PolyCardSparkRead = Future<List<PolymarketPricePoint>?> Function(
    String tokenId, String interval);

/// What the session already holds for a token and range, synchronously.
typedef PolyCardSparkPeek = List<PolymarketPricePoint>? Function(
    String tokenId, String interval);

class PolyCardSparkStore {
  PolyCardSparkStore({
    PolyCardSparkRead? fetch,
    PolyCardSparkRead? saved,
    PolyCardSparkPeek? session,
    DateTime Function()? now,
    this.maxInFlight = 3,
    this.debounce = const Duration(milliseconds: 400),
  })  : _fetch = fetch,
        _saved = saved,
        _session = session,
        _now = now ?? DateTime.now;

  /// A series this young is not asked for again.
  static const freshFor = Duration(minutes: 10);

  /// A game in play's line since kickoff moves by the minute.
  static const liveFreshFor = Duration(minutes: 2);

  /// After a failed read the token is not asked again sooner than this.
  static const retryAfter = Duration(minutes: 2);

  /// Series kept in memory; the least recently used go first.
  static const maxEntries = 160;

  /// The range a game in play's line is read from (the sheet's own game
  /// range: a whole match at one point a minute).
  static const liveInterval = '6h';

  static Duration freshForInterval(String interval) =>
      interval == liveInterval ? liveFreshFor : freshFor;

  final PolyCardSparkRead? _fetch;
  final PolyCardSparkRead? _saved;
  final PolyCardSparkPeek? _session;
  final DateTime Function() _now;
  final int maxInFlight;
  final Duration debounce;

  // Map and set literals keep insertion order: the oldest entry first.
  final Map<String, ({List<PolymarketPricePoint> points, DateTime at})>
      _memory = {};
  final Set<String> _queue = {};
  final Set<String> _inFlight = {};
  final Set<String> _diskAsked = {};
  final Map<String, DateTime> _failedAt = {};
  final Map<String, Set<void Function(List<PolymarketPricePoint>)>>
      _listeners = {};
  Timer? _timer;
  bool _disposed = false;

  /// Reads started (for the tests).
  @visibleForTesting
  int fetches = 0;

  /// Keys waiting for their batch.
  @visibleForTesting
  List<String> get queued => List.unmodifiable(_queue);

  /// Reads started and not answered.
  @visibleForTesting
  int get inFlight => _inFlight.length;

  static String keyOf(String tokenId, String interval) => '$tokenId|$interval';

  /// The series to draw for (token, range) now, fresh or not; null when
  /// there is none yet.
  List<PolymarketPricePoint>? cached(String tokenId, String interval) =>
      _memory[keyOf(tokenId, interval)]?.points;

  bool _fresh(String key, String interval) {
    final hit = _memory[key];
    return hit != null &&
        _now().difference(hit.at) < freshForInterval(interval);
  }

  void _keep(String key, List<PolymarketPricePoint> points, DateTime at) {
    _memory.remove(key);
    _memory[key] = (points: points, at: at);
    while (_memory.length > maxEntries) {
      _memory.remove(_memory.keys.first);
    }
  }

  void _notify(String key, List<PolymarketPricePoint> points) {
    for (final l in List.of(_listeners[key] ??
        const <void Function(List<PolymarketPricePoint>)>{})) {
      l(points);
    }
  }

  /// A card showing (token, range): [onData] hears each series that lands
  /// for it (never during this call). The read is queued unless the
  /// series is fresh, on its way or failed moments ago. The returned
  /// function is the card going away: with no card left on the key, a
  /// read not yet started is dropped.
  VoidCallback watch(String tokenId, String interval,
      void Function(List<PolymarketPricePoint>) onData) {
    final key = keyOf(tokenId, interval);
    final set = _listeners.putIfAbsent(key, () => {});
    set.add(onData);
    if (!_memory.containsKey(key)) {
      // What the session already read (the sheet's chart), drawn at once
      // and refreshed like any other.
      final held = _session?.call(tokenId, interval);
      if (held != null && held.length >= 2) {
        _keep(key, held, DateTime.fromMillisecondsSinceEpoch(0));
      } else if (_saved != null && _diskAsked.add(key)) {
        // An earlier session's copy, while the read runs.
        unawaited(_saved(tokenId, interval).then((points) {
          if (_disposed || points == null || points.length < 2) return;
          if (_memory.containsKey(key)) return;
          _keep(key, points, DateTime.fromMillisecondsSinceEpoch(0));
          _notify(key, points);
        }).catchError((_) {}));
      }
    }
    _request(key, interval);
    return () {
      set.remove(onData);
      if (set.isNotEmpty) return;
      _listeners.remove(key);
      _queue.remove(key);
      if (_queue.isEmpty) {
        _timer?.cancel();
        _timer = null;
      }
    };
  }

  void _request(String key, String interval) {
    if (_fetch == null || _disposed) return;
    if (_fresh(key, interval)) return;
    if (_inFlight.contains(key) || _queue.contains(key)) return;
    final failed = _failedAt[key];
    if (failed != null && _now().difference(failed) < retryAfter) return;
    _queue.add(key);
    // The batch waits for the list to come to rest.
    _timer?.cancel();
    _timer = Timer(debounce, _pump);
  }

  void _pump() {
    _timer = null;
    if (_disposed) return;
    while (_inFlight.length < maxInFlight && _queue.isNotEmpty) {
      final key = _queue.first;
      _queue.remove(key);
      if (!_listeners.containsKey(key)) continue;
      _inFlight.add(key);
      unawaited(_run(key));
    }
  }

  Future<void> _run(String key) async {
    final split = key.lastIndexOf('|');
    final tokenId = key.substring(0, split);
    final interval = key.substring(split + 1);
    fetches++;
    List<PolymarketPricePoint>? points;
    try {
      points = await _fetch!(tokenId, interval);
    } catch (_) {
      points = null;
    }
    _inFlight.remove(key);
    if (_disposed) return;
    if (points == null || points.length < 2) {
      _failedAt[key] = _now();
    } else {
      _failedAt.remove(key);
      final kept = List<PolymarketPricePoint>.unmodifiable(points);
      _keep(key, kept, _now());
      _notify(key, kept);
    }
    // The rest of the batch, as reads free up.
    _pump();
  }

  /// The session is over: nothing more is asked or heard.
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _queue.clear();
    _listeners.clear();
  }
}

/// The values a card draws from [points]: those from [since] on (a game's
/// kickoff) and then [live], the figure the card shows, as the line's end.
List<double> polyCardSparkValues(List<PolymarketPricePoint>? points,
    {DateTime? since, double? live}) {
  if (points == null) return const [];
  final out = <double>[
    for (final p in points)
      if ((since == null || !p.timestamp.isBefore(since)) &&
          p.price.isFinite &&
          p.price >= 0 &&
          p.price <= 1)
        p.price,
  ];
  if (out.isEmpty) return const [];
  if (live != null && live.isFinite && live >= 0 && live <= 1) out.add(live);
  return out.length < 2 ? const [] : out;
}
