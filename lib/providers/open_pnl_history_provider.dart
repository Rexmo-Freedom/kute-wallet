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
//   * [openPnlRangesProvider]: the ranges the line offers (every fixed
//     range shorter than its history, then ALL: [openPnlRanges]);
//   * [openPnlShownRangeProvider]: the range picked ([openPnlRangeProvider],
//     kept for the session), else ALL, the whole history; a range picked
//     that the line does not offer (as long as its history or longer) is
//     ALL.
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
import 'package:kute/models/portfolio_performance.dart'
    show
        PortfolioPerformanceVenue,
        PortfolioPnlPoint,
        PredictionsBook;
import 'package:kute/providers/portfolio_performance_provider.dart'
    show PortfolioPerformanceRequest, portfolioPerformanceDisplayProvider;
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

  /// How many ranges the line offers ([openPnlRanges]: the fixed ones
  /// shorter than its history, then ALL); null with nothing charted.
  int? get rangesOffered =>
      series == null ? null : openPnlRanges(oldestOpen, asOf).length;
}

/// The ranges a line offering [count] of them ([OpenPnlHistory
/// .rangesOffered]) shows in its row: the [count] - 1 shortest, then ALL
/// ([openPnlRanges] keeps them in that order); every range while the line
/// is read or with nothing charted.
List<BalanceRange> openPnlRangesOf(int? count) => count == null
    ? BalanceRange.values
    : [...BalanceRange.values.take(count - 1), BalanceRange.all];

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
  final end = now.toLocal();
  final oldest = openPnlOldest(legs, end);
  return OpenPnlHistory(
    asOf: now,
    legs: List.unmodifiable(legs),
    leftOut: Set.unmodifiable(leftOut),
    series: oldest == null
        ? null
        : openPnlGrid(
            changes: openPnlChanges(legs, end),
            first: openPnlLeadIn(oldest, end),
            now: end),
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

/// [range]'s points of the line (the Balance charts' bucket closes; a
/// range the line does not offer is ALL's whole line:
/// [openPnlRangeWindow]), computed once per range and history.
final openPnlWindowProvider = Provider.autoDispose
    .family<OpenPnlWindow?, BalanceRange>((ref, range) {
  final history = ref.watch(openPnlHistoryProvider.select((read) {
    final h = read.valueOrNull;
    return h?.series == null ? null : h;
  }));
  return history == null ? null : _windowOf(history, range);
});

OpenPnlWindow _windowOf(OpenPnlHistory h, BalanceRange range) {
  final shown = openPnlRangeWindow(
      series: h.series!, oldest: h.oldestOpen, now: h.asOf, range: range);
  return OpenPnlWindow(
      values: shown.values, times: shown.times, daily: shown.daily);
}

/// The range picked on the Positions chart, kept for the session; null
/// until one is picked ([openPnlShownRangeProvider] then shows ALL).
final openPnlRangeProvider = StateProvider<BalanceRange?>((ref) => null);

/// The ranges the Positions chart's row offers ([openPnlRanges]: the
/// fixed ones shorter than the line's history, then ALL); every range
/// while the history is read.
final openPnlRangesProvider = Provider.autoDispose<List<BalanceRange>>(
    (ref) => openPnlRangesOf(ref.watch(openPnlHistoryProvider
        .select((read) => read.valueOrNull?.rangesOffered))));

/// The range the Positions chart shows (and the Dollars Open P&L card):
/// the one picked, else ALL, the whole history (founder, 7 November 2026:
/// "use ALL like it was before"); a pick the line does not offer (as long
/// as its history or longer, [openPnlRangeShown]) is ALL.
final openPnlShownRangeProvider = Provider.autoDispose<BalanceRange>((ref) =>
    openPnlRangeShown(ref.watch(openPnlRangeProvider) ?? BalanceRange.all,
        ref.watch(openPnlRangesProvider)));

// ─────────────────────── the whole P&L history ───────────────────────
//
// The Portfolio's P&L and Activity heroes (and the P&L section's venue
// squares): the account's P&L over time from the same engine as the
// Positions chart (models/open_pnl_history.dart, "the whole P&L
// history"): every position's realised P&L stepping at its closes, sells,
// redeems and fees, plus what the positions held at each moment were
// winning or losing then, each from its own entry. Computed here, once per
// change of what was traded or is held, never on a frame:
//
//   * [_pnlFillLegsProvider]: every Hyperliquid perp's whole history from
//     the fills (hlPerpHistory) and the spot pairs' realised P&L
//     (hlSpotRealised); equal while the fills say the same;
//   * [_pnlLegsProvider]: the perps' prices (their coins' candles, read as
//     the Positions chart reads them and from the same cache: every coin
//     held now, and the [kPnlHistoryCurves] most recently traded of those
//     closed; an older closed one keeps its realised steps, unmarked
//     between them), the predictions and spot holdings open now taken from
//     the Positions chart's own history (its legs, its left-out ones);
//   * [pnlHistoryProvider] (per venue: both, or the P&L square picked):
//     those legs, every prediction's realised P&L as Polymarket books it
//     (polyRealisedLegs), and under them THE VENUE'S OWN P&L
//     (openPnlVenueLeg): at every moment a venue published its P&L the
//     line is that figure, what the positions charted do not carry
//     (funding, rewards, fills older than those the venue keeps, a cut
//     book, a closed prediction's swings before it was decided) held from
//     there to the next; with nothing of a venue's charted, its own line;
//     and the line on the grid;
//   * [pnlWindowProvider]: the points a range draws, per range and venue
//     (a range the line does not offer is ALL's whole line:
//     openPnlRangeWindow); [pnlRangesProvider]: the ranges it offers.
//
// The live figure is not here: the hero pins the line's last point to the
// P&L now it writes (the venues' own, the predictions at the live prices),
// so a tick moves that point alone, and the range's P&L in the line is that
// figure less the range's start.

/// How many CLOSED Hyperliquid coins are marked between their fills (the
/// most recently traded); every coin held now always is.
const int kPnlHistoryCurves = 8;

/// The fills' account of every perp and spot pair ([pnlFillLegs]);
/// [pending] while the fills are first read.
@immutable
class PnlFillLegs {
  const PnlFillLegs(
      {required this.perps, required this.spot, this.pending = false});

  static const none = PnlFillLegs(perps: {}, spot: {});

  /// Each perp coin's whole history, by coin.
  final Map<String, HlPerpHistory> perps;

  /// Each spot pair's realised steps, by the fills' coin.
  final Map<String, List<OpenPnlRealised>> spot;

  final bool pending;

  @override
  bool operator ==(Object other) {
    if (other is! PnlFillLegs || other.pending != pending) return false;
    if (other.perps.length != perps.length ||
        other.spot.length != spot.length) {
      return false;
    }
    for (final e in perps.entries) {
      final o = other.perps[e.key];
      if (o == null ||
          o.assumedEntry != e.value.assumedEntry ||
          !listEquals(o.steps, e.value.steps) ||
          !listEquals(o.realised, e.value.realised)) {
        return false;
      }
    }
    for (final e in spot.entries) {
      final o = other.spot[e.key];
      if (o == null || !listEquals(o, e.value)) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(pending, perps.length, spot.length);
}

/// The fills' account of the perps and spot pairs (see [PnlFillLegs]).
PnlFillLegs pnlFillLegs(
    Iterable<HlFill> fills, Map<String, (double, double)> openPerps) {
  final coins = <String>{
    for (final f in fills)
      if (f.sz > 0 && !hlFillIsSpot(f)) f.coin,
  };
  final perps = <String, HlPerpHistory>{};
  for (final coin in coins) {
    final open = openPerps[coin];
    final h = hlPerpHistory(
        coin: coin, fills: fills, szi: open?.$1, entryPx: open?.$2);
    if (h != null) perps[coin] = h;
  }
  return PnlFillLegs(perps: perps, spot: hlSpotRealised(fills));
}

final _pnlFillLegsProvider = Provider.autoDispose<PnlFillLegs>((ref) {
  if (!ref.watch(portfolioVenuesProvider.select((v) => v.trading))) {
    return PnlFillLegs.none;
  }
  final read = ref.watch(hyperliquidUserFillsProvider);
  if (!read.hasValue && !read.hasError) {
    return const PnlFillLegs(perps: {}, spot: {}, pending: true);
  }
  final fills = ref.watch(hyperliquidActivityFillsProvider);
  final open = ref.watch(openPnlBookProvider.select((b) => OpenPnlBook([
        for (final e in b.entries)
          if (e.kind == OpenPnlKind.perp) e,
      ])));
  return pnlFillLegs(fills, {
    for (final e in open.entries) e.id: (e.qty, e.entry),
  });
});

/// A charted position and the venue it is at.
typedef PnlVenueLeg = (PortfolioPerformanceVenue, OpenPnlLeg);

/// Every position of the account the engine can chart (see the section
/// header), both venues, before a venue is picked.
@immutable
class PnlLegs {
  const PnlLegs(
      {required this.asOf, required this.legs, required this.leftOut});

  final DateTime asOf;
  final List<PnlVenueLeg> legs;

  /// The positions open now whose line could not be read
  /// ([openPnlKeyPerp] and the others).
  final Set<String> leftOut;
}

/// A perp coin's candles over its whole history ([openPnlCandlePlan]
/// from [from]), the Positions chart's reads and cache.
Future<List<OpenPnlPrice>?> _hlCoinPrices(
    Ref ref, String coin, DateTime from, DateTime now, int bucket) {
  final plan = openPnlCandlePlan(now.difference(from));
  final reads = [
    for (final (interval, window) in plan)
      _capped(ref.watch(_openPnlCandlesProvider((
        wire: coin,
        interval: interval,
        windowHours: (window.inMinutes / 60).ceil(),
        bucket: bucket,
      )).future)),
  ];
  return Future.wait(reads).then((lists) {
    final first = lists.first;
    if (first == null || first.isEmpty) return null;
    var out = openPnlCandlePrices(first, now);
    for (final finer in lists.skip(1)) {
      if (finer != null && finer.isNotEmpty) {
        out = openPnlMergePrices(out, openPnlCandlePrices(finer, now));
      }
    }
    return out;
  });
}

final _pnlLegsProvider = FutureProvider.autoDispose<PnlLegs>((ref) async {
  // Every read is started before the first wait (see
  // openPnlHistoryProvider).
  final open = ref.watch(openPnlHistoryProvider);
  final fills = ref.watch(_pnlFillLegsProvider);
  if ((!open.hasValue && !open.hasError) || fills.pending) {
    return Completer<PnlLegs>().future;
  }
  final now = DateTime.now();
  _keepFor(ref, kOpenPnlKeep);
  var stale = false;
  ref.onDispose(() => stale = true);
  final bucket = now.millisecondsSinceEpoch ~/ kOpenPnlKeep.inMilliseconds;

  // The coins to mark: every one held now, then the most recently traded.
  final coins = fills.perps.keys.toList()
    ..sort((a, b) => fills.perps[b]!.steps.last.at
        .compareTo(fills.perps[a]!.steps.last.at));
  final marked = <String>{};
  var closed = 0;
  for (final coin in coins) {
    final held = fills.perps[coin]!.steps.last.qty != 0;
    if (held || closed++ < kPnlHistoryCurves) marked.add(coin);
  }
  final reads = <String, Future<List<OpenPnlPrice>?>>{
    for (final coin in marked)
      coin: _hlCoinPrices(
          ref, coin, fills.perps[coin]!.steps.first.at, now, bucket),
  };

  final legs = <PnlVenueLeg>[];
  final leftOut = <String>{};
  final positions = open.valueOrNull;
  // The predictions and holdings open now: the Positions chart's own.
  for (final leg in positions?.legs ?? const <OpenPnlLeg>[]) {
    if (leg.key.startsWith('pm:')) {
      legs.add((PortfolioPerformanceVenue.predictions, leg));
    } else if (leg.key.startsWith('spot:')) {
      legs.add((PortfolioPerformanceVenue.trading, leg));
    }
  }
  for (final key in positions?.leftOut ?? const <String>{}) {
    if (!key.startsWith('perp:')) leftOut.add(key);
  }
  // A perp held now with no fill on its coin: its line cannot be read.
  final book = ref.watch(openPnlBookProvider);
  for (final e in book.entries) {
    if (e.kind == OpenPnlKind.perp && !fills.perps.containsKey(e.id)) {
      leftOut.add(e.key);
    }
  }
  for (final coin in coins) {
    final h = fills.perps[coin]!;
    final read = reads[coin];
    final prices = read == null ? null : await read;
    if (stale) return Completer<PnlLegs>().future;
    final key = openPnlKeyPerp(coin);
    if (prices == null) {
      // Unmarked: its realised steps alone; held now, not charted.
      if (h.steps.last.qty != 0) leftOut.add(key);
      if (h.realised.isNotEmpty) {
        legs.add((
          PortfolioPerformanceVenue.trading,
          OpenPnlLeg(
              key: key,
              steps: const [],
              prices: const [],
              realised: h.realised),
        ));
      }
      continue;
    }
    legs.add((
      PortfolioPerformanceVenue.trading,
      OpenPnlLeg(key: key, steps: h.steps, prices: prices, realised: h.realised),
    ));
  }
  for (final MapEntry(key: coin, value: realised) in fills.spot.entries) {
    legs.add((
      PortfolioPerformanceVenue.trading,
      OpenPnlLeg(
          key: openPnlKeyRealised('spot:$coin'),
          steps: const [],
          prices: const [],
          realised: realised),
    ));
  }
  return PnlLegs(
    asOf: now,
    legs: List.unmodifiable(legs),
    leftOut: Set.unmodifiable(leftOut),
  );
});

/// The venue a left-out position's key is at.
PortfolioPerformanceVenue _venueOfKey(String key) => key.startsWith('pm:')
    ? PortfolioPerformanceVenue.predictions
    : PortfolioPerformanceVenue.trading;

/// What a venue's own P&L read gives the engine: its published points
/// and, on Predictions, the book (its realised P&L per position, and
/// whether it is whole).
@immutable
class _VenueRead {
  const _VenueRead(this.points, this.book);

  final List<PortfolioPnlPoint> points;
  final PredictionsBook? book;

  @override
  bool operator ==(Object other) =>
      other is _VenueRead &&
      identical(other.points, points) &&
      identical(other.book?.records, book?.records) &&
      other.book?.complete == book?.complete;

  @override
  int get hashCode => Object.hash(identityHashCode(points),
      identityHashCode(book?.records), book?.complete);
}

/// The account's P&L over time as the engine draws it, for [venue]
/// (null: both venues the account has; see the section header). Loading
/// while the fills, trades, prices or the venues' own P&L are read; an
/// error when the positions' reads failed outright.
final pnlHistoryProvider = Provider.autoDispose
    .family<AsyncValue<OpenPnlHistory>, PortfolioPerformanceVenue?>(
        (ref, venue) {
  final venues = ref.watch(portfolioVenuesProvider);
  final scope = [
    if (venues.trading &&
        (venue == null || venue == PortfolioPerformanceVenue.trading))
      PortfolioPerformanceVenue.trading,
    if (venues.predictions &&
        (venue == null || venue == PortfolioPerformanceVenue.predictions))
      PortfolioPerformanceVenue.predictions,
  ];
  final now = DateTime.now();
  if (scope.isEmpty) {
    return AsyncData(OpenPnlHistory(
        asOf: now, legs: const [], leftOut: const {}, series: null));
  }
  final reads = <PortfolioPerformanceVenue, _VenueRead?>{};
  var loading = false;
  for (final v in scope) {
    // The points and the book only: the live prices are the hero's.
    final read = ref.watch(portfolioPerformanceDisplayProvider(
            PortfolioPerformanceRequest(venue: v))
        .select((a) => (
              loading: !a.hasValue && !a.hasError,
              read: a.hasValue
                  ? _VenueRead(
                      a.requireValue.points, a.requireValue.predictions)
                  : null,
            )));
    if (read.loading) loading = true;
    reads[v] = read.read;
  }
  final all = ref.watch(_pnlLegsProvider);
  if (loading || (!all.hasValue && !all.hasError)) {
    return const AsyncLoading();
  }
  final engine = all.valueOrNull;
  final asOf = engine?.asOf ?? now;
  final legs = <OpenPnlLeg>[];
  for (final v in scope) {
    final read = reads[v];
    final own = <OpenPnlLeg>[
      for (final (at, leg) in engine?.legs ?? const <PnlVenueLeg>[])
        if (at == v) leg,
      if (v == PortfolioPerformanceVenue.predictions && read?.book != null)
        ...polyRealisedLegs(read!.book!.records),
    ];
    legs.addAll(own);
    // The venue's own P&L under its positions: its figure at every moment
    // it published one (openPnlVenueLeg); with nothing charted, its line.
    if (read != null) {
      final venueLeg = openPnlVenueLeg('venue:${v.name}', read.points, own);
      if (venueLeg != null) legs.add(venueLeg);
    }
  }
  final end = asOf.toLocal();
  final oldest = openPnlOldest(legs, end);
  return AsyncData(OpenPnlHistory(
    asOf: asOf,
    legs: List.unmodifiable(legs),
    leftOut: {
      for (final key in engine?.leftOut ?? const <String>{})
        if (scope.contains(_venueOfKey(key))) key,
    },
    series: oldest == null
        ? null
        : openPnlGrid(
            changes: openPnlChanges(legs, end),
            first: openPnlLeadIn(oldest, end),
            now: end),
  ));
});

/// What the P&L hero draws for [venue] (see [OpenPnlChartStatus]).
final pnlChartStatusProvider = Provider.autoDispose
    .family<OpenPnlChartStatus, PortfolioPerformanceVenue?>((ref, venue) {
  return ref.watch(pnlHistoryProvider(venue).select((read) {
    final h = read.valueOrNull;
    if (h == null) {
      return read.hasError
          ? OpenPnlChartStatus.none
          : OpenPnlChartStatus.loading;
    }
    return h.series == null
        ? OpenPnlChartStatus.none
        : OpenPnlChartStatus.chart;
  }));
});

/// The positions [venue]'s line leaves out (held now, their line not
/// read): the note under the chart.
final pnlLeftOutProvider = Provider.autoDispose
    .family<Set<String>, PortfolioPerformanceVenue?>((ref, venue) =>
        ref.watch(pnlHistoryProvider(venue)
            .select((read) => read.valueOrNull?.leftOut)) ??
        const <String>{});

/// One range's points of the whole P&L line for [venue] (null: both),
/// computed once per range, venue and history.
final pnlWindowProvider = Provider.autoDispose.family<OpenPnlWindow?,
    ({BalanceRange range, PortfolioPerformanceVenue? venue})>((ref, key) {
  final history = ref.watch(pnlHistoryProvider(key.venue).select((read) {
    final h = read.valueOrNull;
    return h?.series == null ? null : h;
  }));
  return history == null ? null : _windowOf(history, key.range);
});

/// The ranges the Portfolio screen's whole P&L line offers at most (the
/// redesign of 7 November 2026: 1W 1M 3M ALL, no 1Y), shortest first.
const List<BalanceRange> kPnlHistoryRanges = [
  BalanceRange.week,
  BalanceRange.month,
  BalanceRange.threeMonths,
  BalanceRange.all,
];

/// The ranges [venue]'s whole P&L line (null: both) offers in its row
/// ([openPnlRanges]: the fixed ones of [kPnlHistoryRanges] shorter than
/// its history, then ALL); all of them while it is read or with nothing
/// charted.
final pnlRangesProvider = Provider.autoDispose
    .family<List<BalanceRange>, PortfolioPerformanceVenue?>((ref, venue) => [
          for (final r in openPnlRangesOf(ref.watch(pnlHistoryProvider(venue)
              .select((read) => read.valueOrNull?.rangesOffered))))
            if (kPnlHistoryRanges.contains(r)) r,
        ]);
