// lib/providers/hyperliquid_funding_history_provider.dart
//
// One perp's hourly funding history for the Investing chart's Funding
// pane (hl_chart_funding_pane.dart), read only while that pane is on and
// kept for the session per market (WIRE coin, so a builder market reads
// "xyz:XYZ100").
//
//   * The chart asks for the time its first bar on screen opens ([want]);
//     what is missing is read in whole pages of [kHlFundingPage] (one
//     `fundingHistory` answer holds at most 500 hours, about 20.8 days),
//     newest first on open, older ones as the person pans back, never
//     further back than [kHlFundingLookback].
//   * One read at a time. A failed read leaves what was read and is not
//     retried for [kHlFundingRetry]; with nothing read the pane says it
//     could not load.
//   * No polling: the newest hour is read again only once a new one has
//     settled (on the hour), when the chart next asks.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/services/hyperliquid/insights/hl_flow_signals.dart'
    show HlFundingPoint;

/// Reads [coin]'s settlements in [startMs, endMs], oldest first; throws on
/// a failed request.
typedef HlFundingFetch = Future<List<HlFundingPoint>> Function(
    String coin, int startMs, int endMs);

/// The venue's reader (overridden in tests).
final hlFundingFetchProvider = Provider<HlFundingFetch>((ref) {
  final model = ref.watch(hyperliquidTradingModelProvider);
  return (coin, startMs, endMs) => model.getFundingHistoryRange(
      coin: coin, startMs: startMs, endMs: endMs, maxPages: 12);
});

const int _kHourMs = 3600 * 1000;

/// One read's span: a little under the 500 hours one answer holds.
const Duration kHlFundingPage = Duration(hours: 480);

/// How far back the pane reads (about nine pages from now).
const Duration kHlFundingLookback = Duration(days: 180);

/// How long a failed read waits before the chart's next ask tries again.
const Duration kHlFundingRetry = Duration(seconds: 30);

/// Where a market's funding history stands.
enum HlFundingLoad {
  /// Nothing read yet, or a read is under way with nothing to show.
  loading,

  /// Read (possibly empty: a market with no settlement yet).
  ready,

  /// The first read failed; nothing to show.
  error,
}

class HlFundingHistory {
  const HlFundingHistory({
    this.points = const [],
    this.fromMs,
    this.toMs,
    this.load = HlFundingLoad.loading,
    this.busy = false,
  });

  /// Settlements, oldest first, one per `time`.
  final List<HlFundingPoint> points;

  /// The span read so far, both ends inclusive (null: nothing read).
  final int? fromMs, toMs;
  final HlFundingLoad load;

  /// A read is under way.
  final bool busy;

  HlFundingHistory copyWith({
    List<HlFundingPoint>? points,
    int? fromMs,
    int? toMs,
    HlFundingLoad? load,
    bool? busy,
  }) =>
      HlFundingHistory(
        points: points ?? this.points,
        fromMs: fromMs ?? this.fromMs,
        toMs: toMs ?? this.toMs,
        load: load ?? this.load,
        busy: busy ?? this.busy,
      );
}

/// [a] and [b] (each oldest first) as one list, oldest first, one point
/// per `time` ([b]'s wins).
List<HlFundingPoint> hlMergeFunding(
    List<HlFundingPoint> a, List<HlFundingPoint> b) {
  if (b.isEmpty) return a;
  if (a.isEmpty) {
    final sorted = [...b]..sort((x, y) => x.timeMs.compareTo(y.timeMs));
    return List.unmodifiable(_dedupe(sorted));
  }
  final byTime = <int, HlFundingPoint>{
    for (final p in a) p.timeMs: p,
    for (final p in b) p.timeMs: p,
  };
  final keys = byTime.keys.toList()..sort();
  return List.unmodifiable([for (final k in keys) byTime[k]!]);
}

List<HlFundingPoint> _dedupe(List<HlFundingPoint> sorted) {
  final out = <HlFundingPoint>[];
  for (final p in sorted) {
    if (out.isNotEmpty && out.last.timeMs == p.timeMs) {
      out[out.length - 1] = p;
    } else {
      out.add(p);
    }
  }
  return out;
}

class HlFundingHistoryNotifier
    extends FamilyNotifier<HlFundingHistory, String> {
  /// The clock (tests set it).
  DateTime Function() now = DateTime.now;

  int? _wantedFrom;
  DateTime? _failedAt;
  int? _tailAskedHour;

  @override
  HlFundingHistory build(String arg) => const HlFundingHistory();

  /// The chart's first bar on screen opens at [fromMs]: read what is
  /// missing from there (within [kHlFundingLookback]) to now.
  void want(int fromMs) {
    final nowMs = now().millisecondsSinceEpoch;
    final floor = nowMs - kHlFundingLookback.inMilliseconds;
    final from = math.max(floor, math.min(fromMs, nowMs));
    _wantedFrom = _wantedFrom == null ? from : math.min(_wantedFrom!, from);
    unawaited(_next());
  }

  Future<void> _next() async {
    if (state.busy) return;
    final failed = _failedAt;
    if (failed != null && now().difference(failed) < kHlFundingRetry) return;
    final wanted = _wantedFrom;
    if (wanted == null) return;
    final nowMs = now().millisecondsSinceEpoch;
    final from = state.fromMs, to = state.toMs;

    int start, end;
    if (from == null || to == null) {
      // The first read: back to the bar asked for, at least one page.
      start = math.min(wanted, nowMs - kHlFundingPage.inMilliseconds);
      end = nowMs;
    } else if (wanted < from - _kHourMs) {
      // Older: whole pages, so a slow pan does not read hour by hour.
      start = math.min(wanted, from - kHlFundingPage.inMilliseconds);
      end = from - 1;
    } else {
      // The newest hour, once a new one has settled since the last read.
      final settled = nowMs ~/ _kHourMs * _kHourMs;
      if (settled <= to || _tailAskedHour == settled) return;
      _tailAskedHour = settled;
      start = to + 1;
      end = nowMs;
    }
    final floor = nowMs - kHlFundingLookback.inMilliseconds;
    start = math.max(start, math.min(floor, end));
    if (start > end) return;

    state = state.copyWith(busy: true);
    try {
      final page = await ref.read(hlFundingFetchProvider)(arg, start, end);
      _failedAt = null;
      state = HlFundingHistory(
        points: hlMergeFunding(state.points, page),
        fromMs: from == null ? start : math.min(from, start),
        toMs: to == null ? end : math.max(to, end),
        load: HlFundingLoad.ready,
      );
    } catch (_) {
      _failedAt = now();
      state = state.copyWith(
        busy: false,
        load: state.fromMs == null ? HlFundingLoad.error : state.load,
      );
      return;
    }
    // Asked for more meanwhile: read on.
    if (_wantedFrom != null && _wantedFrom! < (state.fromMs ?? 0) - _kHourMs) {
      unawaited(_next());
    }
  }
}

/// A perp's funding history for the session, keyed by WIRE coin.
final hlFundingHistoryProvider = NotifierProvider.family<
    HlFundingHistoryNotifier, HlFundingHistory, String>(
  HlFundingHistoryNotifier.new,
);
