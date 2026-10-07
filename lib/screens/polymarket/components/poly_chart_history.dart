// lib/screens/polymarket/components/poly_chart_history.dart
//
// Older price points for the Polymarket chart, loaded page by page as the
// user pans (or pinches out) past the oldest point on screen. The
// Polymarket twin of HlChartHistory.
//
// The live chart provider seeds each range (1H, 6H, 1D, 1W) from
// `prices-history?interval=` and keeps it ticking; this pager walks back
// from there with explicit `start`/`end` windows, one range-sized page at
// a time, and keeps the pages for the session per (token, range) so
// reopening a market or switching back to a range costs nothing.
//
// Limits: the API serves explicit windows only within 15 days of now, so
// paging stops at that horizon. 1M already reaches past it and ALL is the
// market's whole life, so neither pages. One request in flight per series,
// at least [PolyChartHistory.minGap] between two requests for one series
// (a multi-outcome chart pages every line on one pan), and a series stops
// asking once a page comes back empty.

import 'package:kute/models/polymarket_model.dart';

class _HistorySeries {
  List<PolymarketPricePoint> points = const [];
  bool loading = false;
  bool exhausted = false;
  DateTime lastRequest = DateTime(0);
}

class PolyChartHistory {
  PolyChartHistory._();

  static const Duration minGap = Duration(milliseconds: 1200);
  static const int maxPoints = 20000;

  /// How far back an explicit window may start (the API's 15-day cap,
  /// less a margin so a page never straddles it).
  static const Duration horizon = Duration(days: 15, minutes: -5);

  /// Series kept for the session; the oldest is dropped past this many.
  static const int _maxSeries = 24;

  static final Map<String, _HistorySeries> _series = {};

  static String _key(String tokenId, String interval) => '$tokenId|$interval';

  /// Page width and bucket for a range, or null when the range cannot page
  /// (1M and ALL). The bucket is the API's grain at or under the range's
  /// own resolution, so older pages are at least as dense as the seed.
  static ({Duration span, int bucketSeconds})? pageFor(String interval) {
    switch (interval) {
      case '1h':
        return (span: const Duration(hours: 1), bucketSeconds: 60);
      case '6h':
        return (span: const Duration(hours: 6), bucketSeconds: 60);
      case '1d':
        return (span: const Duration(days: 1), bucketSeconds: 300);
      case '1w':
        return (span: const Duration(days: 7), bucketSeconds: 1800);
      default:
        return null;
    }
  }

  static bool canPage(String interval) => pageFor(interval) != null;

  /// Points loaded before the live seed, ascending. The list identity only
  /// changes when a page lands, so hosts can memoize on it.
  static List<PolymarketPricePoint> older(String tokenId, String interval) =>
      _series[_key(tokenId, interval)]?.points ?? const [];

  /// Loads one page of points older than [beforeMs]. Returns how many new
  /// points arrived (0 while throttled, loading, past the horizon, or at
  /// the start of the market's history).
  static Future<int> loadOlder({
    required String tokenId,
    required String interval,
    required int beforeMs,
  }) async {
    final page = pageFor(interval);
    if (page == null) return 0;
    final key = _key(tokenId, interval);
    var series = _series.remove(key);
    if (series == null && _series.length >= _maxSeries) {
      _series.remove(_series.keys.first);
    }
    series ??= _HistorySeries();
    _series[key] = series; // most recently used last
    if (series.loading || series.exhausted) return 0;
    final now = DateTime.now();
    if (now.difference(series.lastRequest) < minGap) return 0;

    final have = series.points;
    final endMs = have.isNotEmpty &&
            have.first.timestamp.millisecondsSinceEpoch < beforeMs
        ? have.first.timestamp.millisecondsSinceEpoch
        : beforeMs;
    final floorMs = now.subtract(horizon).millisecondsSinceEpoch;
    final startMs = (endMs - page.span.inMilliseconds) < floorMs
        ? floorMs
        : endMs - page.span.inMilliseconds;
    if (startMs >= endMs - 1000) {
      series.exhausted = true;
      return 0;
    }
    series.lastRequest = now;
    series.loading = true;
    final model = PolymarketModel();
    try {
      final fetched = await model.getPriceHistoryWindow(
        tokenId,
        startSec: startMs ~/ 1000,
        endSec: endMs ~/ 1000,
        bucketSeconds: page.bucketSeconds,
      );
      // A failed page is retried on the next pull.
      if (fetched == null) return 0;
      final fresh = [
        for (final p in fetched)
          if (p.timestamp.millisecondsSinceEpoch < endMs) p
      ]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      if (fresh.isEmpty) {
        series.exhausted = true;
        return 0;
      }
      series.points = List.unmodifiable([...fresh, ...have]);
      if (series.points.length >= maxPoints || startMs == floorMs) {
        series.exhausted = true;
      }
      return fresh.length;
    } finally {
      series.loading = false;
      model.dispose();
    }
  }
}

/// A game's own window at one-minute grain, for the ranges that draw it
/// from coarser points: 1D is ten-minute points and ALL twelve-hour ones,
/// which turned a three-hour game into a few smooth bumps (or, on 1W and
/// longer, into too few points to draw at all). The API serves explicit
/// one-minute windows within fifteen days of now, which is how the
/// Momentum graph reads the same game.
///
/// Kept for the session per (token, window); a failed read is tried again
/// on the next open, at most once every [minGap].
class PolyGameWindowHistory {
  PolyGameWindowHistory._();

  /// The longest window read (the Momentum graph's own cap).
  static const Duration maxSpan = Duration(hours: 8);
  static const Duration minGap = Duration(seconds: 4);
  static const int _maxSeries = 24;

  static final Map<String, List<PolymarketPricePoint>> _series = {};
  static final Map<String, DateTime> _asked = {};
  static final Set<String> _loading = {};

  /// A window is the same read while its ends fall in the same minutes; a
  /// game in play ([endMs] null) is one window however long it has run.
  static String _key(String tokenId, int startMs, int? endMs) =>
      '$tokenId|${startMs ~/ 60000}|${endMs == null ? 'live' : endMs ~/ 60000}';

  /// Whether [startMs]..[endMs] (now when null) can be read at one-minute
  /// grain: no longer than [maxSpan] and inside the API's horizon.
  static bool canRead(int startMs, int? endMs, {DateTime? now}) {
    final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final end = endMs ?? nowMs;
    if (end <= startMs || end - startMs > maxSpan.inMilliseconds) return false;
    return startMs > nowMs - PolyChartHistory.horizon.inMilliseconds;
  }

  /// The window's points once read, ascending; null before that.
  static List<PolymarketPricePoint>? points(
          String tokenId, int startMs, int? endMs) =>
      _series[_key(tokenId, startMs, endMs)];

  /// Reads the window unless it is read, being read or was just asked
  /// for. True when points arrived.
  static Future<bool> load(String tokenId, int startMs, int? endMs) async {
    final key = _key(tokenId, startMs, endMs);
    if (_series.containsKey(key) || _loading.contains(key)) return false;
    if (!canRead(startMs, endMs)) return false;
    final now = DateTime.now();
    final asked = _asked[key];
    if (asked != null && now.difference(asked) < minGap) return false;
    _asked[key] = now;
    _loading.add(key);
    final model = PolymarketModel();
    try {
      final fetched = await model.getPriceHistoryWindow(
        tokenId,
        startSec: startMs ~/ 1000,
        endSec: (endMs ?? now.millisecondsSinceEpoch) ~/ 1000 + 60,
        bucketSeconds: 60,
      );
      if (fetched == null || fetched.length < 2) return false;
      if (_series.length >= _maxSeries) _series.remove(_series.keys.first);
      _series[key] = List.unmodifiable(
          [...fetched]..sort((a, b) => a.timestamp.compareTo(b.timestamp)));
      return true;
    } finally {
      _loading.remove(key);
      model.dispose();
    }
  }
}

/// [coarse] with its stretch between the first and the last of [fine]
/// replaced by [fine]: a range's own points before and after a game, the
/// game itself minute by minute. Both ascending; either may be empty.
List<PolymarketPricePoint> mergeFineWindow(
  List<PolymarketPricePoint> coarse,
  List<PolymarketPricePoint> fine,
) {
  if (fine.isEmpty) return coarse;
  if (coarse.isEmpty) return fine;
  final from = fine.first.timestamp, to = fine.last.timestamp;
  return [
    for (final p in coarse)
      if (p.timestamp.isBefore(from)) p,
    ...fine,
    for (final p in coarse)
      if (p.timestamp.isAfter(to)) p,
  ];
}

/// The range a game's chart opens on: the shortest that holds the game
/// from its kickoff [start] to [now]; null (ALL) before kickoff or once it
/// is nearly a week old. The chart then zooms to the game itself inside
/// it (polyGameWindow).
String? polyGameOpeningRange(DateTime start, DateTime now) {
  final age = now.difference(start);
  return age.isNegative
      ? null
      : age < const Duration(minutes: 50)
          ? '1h'
          : age < const Duration(hours: 5, minutes: 30)
              ? '6h'
              : age < const Duration(hours: 23)
                  ? '1d'
                  : age < const Duration(days: 6, hours: 12)
                      ? '1w'
                      : null;
}

/// When [event]'s market opened, for its chart's range: Gamma's
/// `startDate`, except on a game, where it may be the kickoff instead.
DateTime? polyChartOpenedAt(PolymarketEvent event) =>
    event.gameId == null && event.metadataGameId == null
        ? event.startDate
        : null;

/// How long the 1M range reaches back.
const Duration kPolyMonthRange = Duration(days: 30);

/// The range a Predictions chart opens on, and keeps (there is no range
/// row to pick another): the CLOB `prices-history` interval it reads
/// ('1h', '6h', '1d', '1w', '1m' or 'max', the market's whole life).
///
///   * A game that has kicked off ([gameStart] at or before [now]): the
///     shortest range holding kickoff to now ([polyGameOpeningRange]),
///     which the chart zooms to the game; ALL once it is a week old.
///   * A game in play whose kickoff is not known ([inPlay]): 1D.
///   * A short round (5 / 15 minute Up or Down, [shortMarket]), a resolved
///     market, or a market opened ([openedAt]) under a month ago, a week
///     old or younger among them: ALL, its whole life.
///   * Anything else: the last month (1M). A market whose age is unknown
///     reads 1M too, which holds all of a younger one's history.
String polyChartAutoRange({
  required DateTime now,
  DateTime? gameStart,
  bool inPlay = false,
  DateTime? openedAt,
  bool shortMarket = false,
  bool resolved = false,
}) {
  if (gameStart != null && !gameStart.isAfter(now)) {
    return polyGameOpeningRange(gameStart, now) ?? 'max';
  }
  if (inPlay) return '1d';
  if (shortMarket || resolved) return 'max';
  if (openedAt != null && now.difference(openedAt) < kPolyMonthRange) {
    return 'max';
  }
  return '1m';
}
