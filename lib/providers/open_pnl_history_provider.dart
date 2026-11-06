// lib/providers/open_pnl_history_provider.dart
//
// The Portfolio's Positions chart: the open positions' P&L over time,
// each from its own entry (models/open_pnl_history.dart has the
// arithmetic; components/portfolio_hero.dart draws it). Computed here,
// once per change of what is held, never on a frame:
//
//   * [openPnlBookProvider]: the positions open now, without their live
//     prices (equal while none opens, closes or changes size, so an
//     account poll or a price tick lays nothing again);
//   * the Investing positions' stretches from the account's fills
//     ([hyperliquidActivityFillsProvider]; equal while they say the same,
//     so the fills' minute refresh lays nothing again);
//   * [openPnlHistoryProvider]: the Predictions stretches from the trade
//     history, each leg's prices (Hyperliquid candles, the Polymarket
//     price history the position screens read, [OpenPnlSources]) and the
//     grid ([openPnlSeries]) once. A position whose open or prices cannot
//     be read is left out ([OpenPnlHistory.leftOut]) and the rest charted.
//     Kept five minutes after the chart goes (another section and back
//     draws at once), read again every five minutes while it is up;
//   * [openPnlWindowProvider]: the points a range draws, per range;
//   * [openPnlShownRangeProvider]: the range picked ([openPnlRangeProvider],
//     kept for the session), else the shortest that covers the oldest open
//     position's entry.
//
// The live figure is not here: the chart puts the open P&L now
// (portfolioOpenPnl, the hero's own figure, the left-out positions left
// out) on the last point, so a tick moves that point alone.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/balance_history.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/models/open_pnl_history.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart'
    show hyperliquidSpotMarketsProvider, hyperliquidTradingModelProvider;
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart'
    show hyperliquidActivityFillsProvider, hyperliquidUserFillsProvider;
import 'package:kute/providers/hyperliquid_trading_provider.dart'
    show hyperliquidDisplayTradingProvider;
import 'package:kute/providers/polymarket_browse_provider.dart'
    show polymarketActivePositionsProvider, polymarketMarketHistoryProvider;
import 'package:kute/providers/polymarket_trading_provider.dart'
    show polymarketTradingProvider;
import 'package:kute/screens/polymarket/components/position_journey.dart'
    show polyJourneyInterval;
import 'package:kute/screens/portfolio/portfolio_filters.dart'
    show portfolioVenuesProvider;
import 'package:kute/screens/shared/charts/kute_trend_window.dart'
    show kuteTrendWindow;

/// What an open position is.
enum OpenPnlKind { perp, spot, prediction }

/// One position open now, without its live price: what the chart needs
/// to find its stretches and its prices.
@immutable
class OpenPnlEntry {
  const OpenPnlEntry({
    required this.kind,
    required this.key,
    required this.id,
    required this.wire,
    required this.qty,
    required this.entry,
    this.firstEntry,
    this.displayPx,
  });

  final OpenPnlKind kind;

  /// [openPnlKeyPerp], [openPnlKeySpot] or [openPnlKeyPrediction].
  final String key;

  /// The perp's coin, the holding's token, the prediction's token.
  final String id;

  /// The coin the venue's candles answer to (a perp's coin, a spot pair's
  /// wire coin); the token for a prediction.
  final String wire;

  /// Signed for a perp (a short is negative); shares, units otherwise.
  final double qty;

  /// The average entry (a holding's recorded cost over its units).
  final double entry;

  /// A prediction's first entry (`first_entry_at`), when its trade history
  /// does not reach its first buy.
  final DateTime? firstEntry;

  /// A spot holding's mid when read, for the candles' unit guard. Not
  /// part of equality: a new mid is no new position.
  final double? displayPx;

  @override
  bool operator ==(Object other) =>
      other is OpenPnlEntry &&
      other.kind == kind &&
      other.key == key &&
      other.wire == wire &&
      other.qty == qty &&
      other.entry == entry &&
      other.firstEntry == firstEntry;

  @override
  int get hashCode => Object.hash(kind, key, wire, qty, entry, firstEntry);
}

/// The positions open now ([OpenPnlEntry]), in the order read.
@immutable
class OpenPnlBook {
  const OpenPnlBook(this.entries);

  static const empty = OpenPnlBook([]);

  final List<OpenPnlEntry> entries;

  bool get isEmpty => entries.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is OpenPnlBook && listEquals(other.entries, entries);

  @override
  int get hashCode => Object.hashAll(entries);
}

/// The positions the hero's open P&L counts (portfolioOpenPnl): every
/// open prediction, every perp, every spot holding with a recorded cost
/// whose market is known.
final openPnlBookProvider = Provider.autoDispose<OpenPnlBook>((ref) {
  final venues = ref.watch(portfolioVenuesProvider);
  final entries = <OpenPnlEntry>[];
  if (venues.predictions) {
    for (final p in ref.watch(polymarketActivePositionsProvider)) {
      // One without a token is counted in the figure but has no history
      // to read: it is left out of the chart.
      final token = p.tokenId ?? '';
      entries.add(OpenPnlEntry(
        kind: OpenPnlKind.prediction,
        key: openPnlKeyPrediction(
            tokenId: p.tokenId, marketId: p.marketId, outcome: p.outcome),
        id: token,
        wire: token,
        qty: p.size,
        entry: p.avgPrice,
        firstEntry: p.createdAt,
      ));
    }
  }
  if (venues.trading) {
    final state = ref.watch(hyperliquidDisplayTradingProvider).valueOrNull;
    if (state != null) {
      for (final p in state.positions) {
        entries.add(OpenPnlEntry(
          kind: OpenPnlKind.perp,
          key: openPnlKeyPerp(p.coin),
          id: p.coin,
          wire: p.coin,
          qty: p.szi,
          entry: p.entryPx,
        ));
      }
      final spot = state.spotBalances
          .where((b) => b.coin != 'USDC' && b.total > 0 && b.costBasis != null)
          .toList();
      if (spot.isNotEmpty) {
        final markets =
            ref.watch(hyperliquidSpotMarketsProvider).valueOrNull ??
                const <HlMarket>[];
        for (final b in spot) {
          final m = markets.where((m) => m.coin == b.coin).firstOrNull;
          if (m == null || !(m.midPx > 0)) continue;
          entries.add(OpenPnlEntry(
            kind: OpenPnlKind.spot,
            key: openPnlKeySpot(b.coin),
            id: b.coin,
            wire: m.wireCoin,
            qty: b.total,
            entry: b.costBasis! / b.total,
            displayPx: m.midPx,
          ));
        }
      }
    }
  }
  return OpenPnlBook(entries);
});

/// The Investing positions' stretches from the fills, by key (null: not
/// charted); [pending] while the fills are first read.
@immutable
class OpenPnlFillSteps {
  const OpenPnlFillSteps(this.steps, {this.pending = false});

  static const none = OpenPnlFillSteps({});

  final Map<String, List<OpenPnlStep>?> steps;
  final bool pending;

  @override
  bool operator ==(Object other) {
    if (other is! OpenPnlFillSteps || other.pending != pending) return false;
    if (other.steps.length != steps.length) return false;
    for (final e in steps.entries) {
      if (!other.steps.containsKey(e.key)) return false;
      final a = e.value, b = other.steps[e.key];
      if (a == null || b == null ? a != b : !listEquals(a, b)) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(pending, steps.length);
}

final _openPnlFillStepsProvider =
    Provider.autoDispose<OpenPnlFillSteps>((ref) {
  final book = ref.watch(openPnlBookProvider);
  final hl = book.entries.where((e) => e.kind != OpenPnlKind.prediction);
  if (hl.isEmpty) return OpenPnlFillSteps.none;
  final read = ref.watch(hyperliquidUserFillsProvider);
  if (!read.hasValue && !read.hasError) {
    return const OpenPnlFillSteps({}, pending: true);
  }
  final fills = ref.watch(hyperliquidActivityFillsProvider);
  return OpenPnlFillSteps({
    for (final e in hl)
      e.key: e.kind == OpenPnlKind.perp
          ? hlPerpOpenSteps(
              coin: e.id, szi: e.qty, entryPx: e.entry, fills: fills)
          : hlSpotOpenSteps(
              coins: {e.wire, e.id},
              total: e.qty,
              avgCost: e.entry,
              fills: fills),
  });
});

/// Where the chart reads what it cannot compute: the Predictions trade
/// history and each market's prices. Each answers null when the read
/// failed. Tests give their own.
class OpenPnlSources {
  const OpenPnlSources({
    required this.activity,
    required this.candles,
    required this.polyHistory,
  });

  /// The account's Polymarket trades (the Data API's recent activity).
  final Future<List<Activity>?> Function(Ref ref) activity;

  /// One Hyperliquid market's candles at [interval] over the trailing
  /// [window].
  final Future<List<HyperliquidCandle>?> Function(
      Ref ref, String wire, String interval, Duration window) candles;

  /// One outcome token's price history at the position screens' range
  /// [interval] ('1h' … 'max').
  final Future<List<PolymarketPricePoint>?> Function(
      Ref ref, String tokenId, String interval) polyHistory;
}

final openPnlSourcesProvider = Provider<OpenPnlSources>((ref) =>
    OpenPnlSources(
      activity: (ref) async {
        final address = ref.watch(polymarketTradingProvider
            .select((s) => s.valueOrNull?.proxyWalletAddress));
        if (address == null || address.isEmpty) return const <Activity>[];
        final model = PolymarketModel();
        try {
          return await model.getUserActivityOrThrow(address);
        } catch (_) {
          return null;
        } finally {
          model.dispose();
        }
      },
      candles: (ref, wire, interval, window) async {
        final list = await ref
            .read(hyperliquidTradingModelProvider)
            .getCandles(coin: wire, interval: interval, window: window);
        return list.isEmpty ? null : list;
      },
      // The position screens' own cache (session and disk), so a position
      // opened there and here reads its history once.
      polyHistory: (ref, tokenId, interval) => ref.watch(
          polymarketMarketHistoryProvider(
                  (tokenId: tokenId, interval: interval))
              .future),
    ));

/// How long a read may take before its position is left out.
const Duration kOpenPnlReadCap = Duration(seconds: 15);

/// How long the history is kept once the chart goes, and how often it is
/// read again while it is up.
const Duration kOpenPnlKeep = Duration(minutes: 5);

typedef _CandleKey = ({
  String wire,
  String interval,
  int windowHours,
  int bucket,
});

/// One market's candles, kept [kOpenPnlKeep] after the last reader (the
/// key's bucket moves every [kOpenPnlKeep], so a later read is fresh).
final _openPnlCandlesProvider = FutureProvider.autoDispose
    .family<List<HyperliquidCandle>?, _CandleKey>((ref, key) {
  _keepFor(ref, kOpenPnlKeep);
  return ref.watch(openPnlSourcesProvider).candles(
      ref, key.wire, key.interval, Duration(hours: key.windowHours));
});

void _keepFor(Ref ref, Duration keep) {
  final link = ref.keepAlive();
  Timer? drop;
  ref.onCancel(() => drop = Timer(keep, link.close));
  ref.onResume(() => drop?.cancel());
  ref.onDispose(() => drop?.cancel());
}

/// The open positions' history as charted (see the file header).
@immutable
class OpenPnlHistory {
  const OpenPnlHistory({
    required this.asOf,
    required this.legs,
    required this.leftOut,
    required this.series,
  });

  /// When it was laid: the line's end.
  final DateTime asOf;

  /// The positions charted.
  final List<OpenPnlLeg> legs;

  /// The keys of the positions open now that are not charted (their open
  /// or their prices could not be read).
  final Set<String> leftOut;

  /// The line on the Balance charts' grid; null with nothing charted.
  final BalanceSeries? series;

  /// When the oldest position charted was opened.
  DateTime? get oldestOpen => openPnlOldest(legs, asOf);
}

/// [future] or null once it fails or takes longer than [kOpenPnlReadCap].
Future<T?> _capped<T>(Future<T?> future) => future
    .then<T?>((v) => v, onError: (Object _) => null)
    .timeout(kOpenPnlReadCap, onTimeout: () => null);

/// The account's Polymarket trades, read once per history (null: the read
/// failed), kept as the history is.
final _openPnlTradesProvider =
    FutureProvider.autoDispose<List<Activity>?>((ref) {
  // Read again when a prediction opens, closes or changes size: the new
  // trade is then in the history.
  ref.watch(openPnlBookProvider.select((b) => OpenPnlBook([
        for (final e in b.entries)
          if (e.kind == OpenPnlKind.prediction) e,
      ])));
  _keepFor(ref, kOpenPnlKeep);
  return _capped(ref.watch(openPnlSourcesProvider).activity(ref));
});

/// A Hyperliquid leg's prices: [plan]'s reads ([openPnlCandlePlan]), the
/// first the whole history (without it, no line), the finer ones laid
/// over its end.
Future<List<OpenPnlPrice>?> _hlPrices(Ref ref, OpenPnlEntry e,
    List<OpenPnlStep> steps, DateTime now, int bucket) {
  final plan = openPnlCandlePlan(now.difference(steps.first.at));
  final reads = [
    for (final (interval, window) in plan)
      _capped(ref.watch(_openPnlCandlesProvider((
        wire: e.wire,
        interval: interval,
        windowHours: (window.inMinutes / 60).ceil(),
        bucket: bucket,
      )).future)),
  ];
  return Future.wait(reads).then((lists) {
    final first = lists.first;
    if (first == null || first.isEmpty) return null;
    // A spot pair's candles in its raw units are put on the mid's scale.
    List<OpenPnlPrice> prices(List<HyperliquidCandle> c) => openPnlCandlePrices(
        e.displayPx == null ? c : rescaleCandlesToDisplay(c, e.displayPx!),
        now);
    var out = prices(first);
    for (final finer in lists.skip(1)) {
      if (finer != null && finer.isNotEmpty) {
        out = openPnlMergePrices(out, prices(finer));
      }
    }
    return out;
  });
}

/// A prediction's prices: the position screens' history of the held
/// token over the shortest range reaching back to its first buy, and past
/// a week the last week too, laid over its end.
Future<List<OpenPnlPrice>?> _pmPrices(Ref ref, OpenPnlSources sources,
    OpenPnlEntry e, List<OpenPnlStep> steps, DateTime now) {
  final age = now.difference(steps.first.at);
  final intervals = <String>{
    polyJourneyInterval(age + const Duration(minutes: 30)),
    if (age > const Duration(days: 6, hours: 20)) '1w',
  };
  final reads = [
    for (final interval in intervals)
      _capped(sources.polyHistory(ref, e.id, interval)),
  ];
  return Future.wait(reads).then((lists) {
    final first = lists.first;
    if (first == null) return null;
    List<OpenPnlPrice> prices(List<PolymarketPricePoint> points) => [
          for (final p in [...points]
            ..sort((a, b) => a.timestamp.compareTo(b.timestamp)))
            if (p.price.isFinite && p.price >= 0)
              (p.timestamp.toLocal(), p.price),
        ];
    var out = prices(first);
    for (final finer in lists.skip(1)) {
      if (finer != null && finer.isNotEmpty) {
        out = openPnlMergePrices(out, prices(finer));
      }
    }
    // No point at all on a position older than a couple of hours: the
    // history was not read; never a flat line in its place.
    if (out.isEmpty && age > const Duration(hours: 2)) return null;
    return out;
  });
}

final openPnlHistoryProvider =
    FutureProvider.autoDispose<OpenPnlHistory>((ref) async {
  // Every read is started before the first wait, so a rebuilt provider
  // never reads through an outdated ref.
  final book = ref.watch(openPnlBookProvider);
  final now = DateTime.now();
  if (book.isEmpty) {
    return OpenPnlHistory(
        asOf: now, legs: const [], leftOut: const {}, series: null);
  }
  final fillSteps = ref.watch(_openPnlFillStepsProvider);
  final predictions =
      book.entries.where((e) => e.kind == OpenPnlKind.prediction).toList();
  final trades =
      predictions.isEmpty ? null : ref.watch(_openPnlTradesProvider);
  // The fills or the trades still on their way: loading until they land
  // (this runs again then).
  if (fillSteps.pending ||
      (trades != null && !trades.hasValue && !trades.hasError)) {
    return Completer<OpenPnlHistory>().future;
  }
  final sources = ref.watch(openPnlSourcesProvider);
  _keepFor(ref, kOpenPnlKeep);
  var listened = true;
  ref.onCancel(() => listened = false);
  ref.onResume(() {
    listened = true;
    if (DateTime.now().difference(now) >= kOpenPnlKeep) ref.invalidateSelf();
  });
  final again = Timer(kOpenPnlKeep, () {
    if (listened) ref.invalidateSelf();
  });
  // Rebuilt or gone before the reads land: no grid is laid for nothing.
  var stale = false;
  ref.onDispose(() {
    stale = true;
    again.cancel();
  });

  final activity = trades?.valueOrNull;
  final bucket = now.millisecondsSinceEpoch ~/ kOpenPnlKeep.inMilliseconds;
  final steps = <String, List<OpenPnlStep>?>{};
  final reads = <String, Future<List<OpenPnlPrice>?>>{};
  for (final e in book.entries) {
    List<OpenPnlStep>? s;
    if (e.kind == OpenPnlKind.prediction) {
      s = activity == null || e.id.isEmpty
          ? null
          : polyOpenSteps(
              tokenId: e.id,
              size: e.qty,
              avgPrice: e.entry,
              activities: activity);
      // Without its trades: its first entry, today's shares and average
      // price throughout (the position screen's journey line does the
      // same).
      final since = e.firstEntry?.toLocal();
      if (s == null &&
          e.id.isNotEmpty &&
          since != null &&
          !since.isAfter(now)) {
        s = [OpenPnlStep(since, e.qty, e.entry)];
      }
    } else {
      s = fillSteps.steps[e.key];
    }
    steps[e.key] = s;
    if (s == null) continue;
    reads[e.key] = e.kind == OpenPnlKind.prediction
        ? _pmPrices(ref, sources, e, s, now)
        : _hlPrices(ref, e, s, now, bucket);
  }

  final legs = <OpenPnlLeg>[];
  final leftOut = <String>{};
  for (final e in book.entries) {
    final s = steps[e.key];
    final read = reads[e.key];
    final prices = read == null ? null : await read;
    if (stale) return Completer<OpenPnlHistory>().future;
    if (s == null || prices == null) {
      leftOut.add(e.key);
      continue;
    }
    legs.add(OpenPnlLeg(key: e.key, steps: s, prices: prices));
  }
  return OpenPnlHistory(
    asOf: now,
    legs: List.unmodifiable(legs),
    leftOut: Set.unmodifiable(leftOut),
    series: openPnlSeries(legs, now),
  );
});

/// What the chart shows on Positions.
enum OpenPnlChartStatus {
  /// Nothing open, or nothing that could be charted: no chart.
  none,

  /// The history is being read: the chart's shapes.
  loading,

  /// A line.
  chart,
}

final openPnlChartStatusProvider =
    Provider.autoDispose<OpenPnlChartStatus>((ref) {
  if (ref.watch(openPnlBookProvider.select((b) => b.isEmpty))) {
    return OpenPnlChartStatus.none;
  }
  return ref.watch(openPnlHistoryProvider.select((read) {
    final h = read.valueOrNull;
    if (h == null) {
      return read.hasError ? OpenPnlChartStatus.none : OpenPnlChartStatus.loading;
    }
    return h.series == null ? OpenPnlChartStatus.none : OpenPnlChartStatus.chart;
  }));
});

/// The points one range draws: its values and moments, and whether its
/// buckets are days (or coarser), so a moment is written as a day.
@immutable
class OpenPnlWindow {
  const OpenPnlWindow(
      {required this.values, required this.times, required this.daily});

  final List<double> values;
  final List<DateTime> times;
  final bool daily;
}

/// [range]'s points of the line (the Balance charts' bucket closes,
/// kuteTrendWindow), computed once per range and history.
final openPnlWindowProvider = Provider.autoDispose
    .family<OpenPnlWindow?, BalanceRange>((ref, range) {
  final series = ref.watch(
      openPnlHistoryProvider.select((read) => read.valueOrNull?.series));
  if (series == null) return null;
  final span = series.spanFor(range);
  final shown = kuteTrendWindow(series, span);
  return OpenPnlWindow(
    values: shown.values,
    times: shown.times,
    daily: series.strideFor(span) * series.cellMinutes >= 1440,
  );
});

/// The range picked on the Positions chart, kept for the session; null
/// until one is picked ([openPnlShownRangeProvider] then picks).
final openPnlRangeProvider = StateProvider<BalanceRange?>((ref) => null);

/// The range the Positions chart shows: the one picked, else the shortest
/// that covers the oldest open position's entry ([openPnlDefaultRange]).
final openPnlShownRangeProvider = Provider.autoDispose<BalanceRange>((ref) {
  final picked = ref.watch(openPnlRangeProvider);
  if (picked != null) return picked;
  final at = ref.watch(openPnlHistoryProvider.select((read) {
    final h = read.valueOrNull;
    return h == null ? null : (oldest: h.oldestOpen, asOf: h.asOf);
  }));
  final oldest = at?.oldest;
  return oldest == null
      ? BalanceRange.all
      : openPnlDefaultRange(oldest, at!.asOf);
});
