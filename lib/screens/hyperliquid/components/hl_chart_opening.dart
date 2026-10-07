// lib/screens/hyperliquid/components/hl_chart_opening.dart
//
// How a Hyperliquid chart OPENS, as pure logic (no widgets, no providers):
//
//   * the opening INTERVAL. The interval is one saved layout for every
//     market (hl_chart_intervals.dart), so a thinly traded market opened
//     on a short interval the user picked on Bitcoin was a flat
//     carry-forward line with one or two prints at the right edge. On
//     open, a LOW LIQUIDITY market (HlMarket.isLowLiquidity, the rule
//     behind its label) whose tape has too few traded bars in the opening
//     view steps up the ladder 1m → 5m → 15m → 1h → 4h → 1D until enough bars traded,
//     for that sheet only: the saved layout is not changed, and an
//     interval picked in the sheet is never stepped.
//   * the autoscale RANGE when one or two bars stand far outside the rest
//     of the visible tape: the scale fits the body of the tape instead of
//     squashing it into a line under a single spike. A tape without such
//     a bar is not touched (null: the caller keeps its full min/max fit).

import 'dart:math' as math;

import 'package:kute/models/hyperliquid_model.dart';

/// Bars the chart opens on (HlCandlestickChart's default view): the thin
/// test looks at exactly the bars the first frame would show.
const int kHlOpeningViewBars = 100;

/// A tape is thin when fewer than this share of the opening view's bars
/// traded …
const double kHlThinTradedShare = 0.30;

/// … or fewer than this many of them did.
const int kHlThinTradedBars = 20;

/// The ladder the opening interval climbs. 1W is never stepped to.
const List<String> kHlOpeningLadder = ['1m', '5m', '15m', '1h', '4h', '1d'];

/// Bars in the opening view of [candles] (its newest [viewBars]) and how
/// many of them had a trade.
({int visible, int traded}) hlTapeActivity(
  List<HyperliquidCandle> candles, {
  int viewBars = kHlOpeningViewBars,
}) {
  final n = candles.length;
  final start = math.max(0, n - viewBars);
  var traded = 0;
  for (var i = start; i < n; i++) {
    if (candles[i].volume > 0) traded++;
  }
  return (visible: n - start, traded: traded);
}

/// Too few traded bars in the opening view to read as a chart.
bool hlTapeIsThin(
  List<HyperliquidCandle> candles, {
  int viewBars = kHlOpeningViewBars,
}) {
  final a = hlTapeActivity(candles, viewBars: viewBars);
  return a.traded < kHlThinTradedBars ||
      a.traded < a.visible * kHlThinTradedShare;
}

/// The next interval up the opening ladder, or null at its top (1D) and
/// for an interval that is not on it (1W).
String? hlCoarserOpeningInterval(String interval) {
  final i = kHlOpeningLadder.indexOf(interval);
  if (i < 0 || i >= kHlOpeningLadder.length - 1) return null;
  return kHlOpeningLadder[i + 1];
}

/// One step of the opening ladder, taken when the tape of [interval] has
/// loaded. [previous] is the finer interval this one was stepped up from
/// and how many of its bars had traded.
///
///   * the coarser tape has FEWER traded bars than the finer one had (a
///     market listed days ago: coarser bars only merge what little there
///     is): back to the finer interval, settled;
///   * the tape is not thin, or the ladder is at its top: settled here;
///   * otherwise: the next interval up, not settled yet.
({String interval, bool settled}) hlOpeningStep({
  required String interval,
  required List<HyperliquidCandle> candles,
  ({String interval, int traded})? previous,
}) {
  final activity = hlTapeActivity(candles);
  if (previous != null && activity.traded < previous.traded) {
    return (interval: previous.interval, settled: true);
  }
  if (!hlTapeIsThin(candles)) return (interval: interval, settled: true);
  final coarser = hlCoarserOpeningInterval(interval);
  if (coarser == null) return (interval: interval, settled: true);
  return (interval: coarser, settled: false);
}

/// The opening interval of ONE chart, from open to settled: the saved
/// interval, stepped up while its tape is thin, and left alone for good
/// once the user picks an interval themselves. Held by the chart's host;
/// nothing here is saved.
class HlChartOpening {
  String? _stepped;
  bool _settled = false;
  ({String interval, int traded})? _previous;

  /// Decided: no further tape is looked at.
  bool get settled => _settled;

  /// The chart is on a coarser interval than the saved one.
  bool get stepped => _stepped != null;

  /// The interval to load and paint, given the [saved] layout's.
  String intervalFor(String saved) => _stepped ?? saved;

  /// The tape of [intervalFor] has loaded. True when the interval moved
  /// (the caller loads that one next and calls this again); false when
  /// the opening is settled on the tape it was given.
  bool onTapeLoaded({
    required String saved,
    required List<HyperliquidCandle> candles,
  }) {
    if (_settled) return false;
    final current = intervalFor(saved);
    final step = hlOpeningStep(
      interval: current,
      candles: candles,
      previous: _previous,
    );
    _settled = step.settled;
    if (step.interval == current) return false;
    _previous = (interval: current, traded: hlTapeActivity(candles).traded);
    _stepped = step.interval == saved ? null : step.interval;
    return true;
  }

  /// Only a market the app calls low liquidity (HlMarket.isLowLiquidity,
  /// the rule behind its "Low liquidity" label) is ever stepped; any
  /// other opens on the saved interval without a look at its tape.
  void forMarket({required bool lowLiquidity}) {
    if (!lowLiquidity) _settled = true;
  }

  /// The tape could not be loaded: stay where the chart is.
  void settle() => _settled = true;

  /// The user picked an interval in this chart: it is theirs, the saved
  /// one included, and is never stepped.
  void userPicked() {
    _stepped = null;
    _settled = true;
  }

  /// Another market: decide again.
  void reset() {
    _stepped = null;
    _settled = false;
    _previous = null;
  }
}

// ───────────────────────── outlier-aware range ─────────────────────────

/// Fewer visible bars than this are always fitted whole.
const int kHlOutlierMinBars = 20;

/// The share of bars left outside the body band at each end (the 2nd and
/// 98th percentile: two bars of the 100 a chart opens on).
const double kHlOutlierTailShare = 0.02;

/// The full range must be more than this many times the body band …
const double kHlOutlierRangeFactor = 3.0;

/// … and a bar outside the band more than this many times the median
/// bar's range, before the scale leaves it out.
const double kHlOutlierBarFactor = 8.0;

/// The price range the autoscale should fit for [visible] when one or two
/// bars stand far outside everything else, or null when there is no such
/// bar (the caller keeps the full min/max, as before).
///
/// The range is the 2nd to 98th percentile band of the visible lows and
/// highs (of the closes when [asLine]), widened to hold the newest close,
/// so the price line is always on screen and a spike on the newest bar
/// still gets the whole scale. The bars left out are drawn clipped at the
/// plot's edge.
({double lo, double hi})? hlOutlierAwareRange(
  List<HyperliquidCandle> visible, {
  required bool asLine,
}) {
  final n = visible.length;
  if (n < kHlOutlierMinBars) return null;
  final lows = List<double>.filled(n, 0);
  final highs = List<double>.filled(n, 0);
  final ranges = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    final k = visible[i];
    lows[i] = asLine ? k.close : k.low;
    highs[i] = asLine ? k.close : k.high;
    ranges[i] = asLine
        ? (i == 0 ? 0 : (k.close - visible[i - 1].close).abs())
        : k.high - k.low;
  }
  final sortedLows = List<double>.of(lows)..sort();
  final sortedHighs = List<double>.of(highs)..sort();
  final fullLo = sortedLows.first;
  final fullHi = sortedHighs.last;
  final tail = math.max(1, (n * kHlOutlierTailShare).floor());
  final bandLo = sortedLows[tail];
  final bandHi = sortedHighs[n - 1 - tail];
  final band = bandHi - bandLo;
  // A flat body has no scale of its own to keep.
  if (!(band > 0)) return null;
  if (fullHi - fullLo <= band * kHlOutlierRangeFactor) return null;

  // Only a bar that is itself out of proportion is left out: a tape that
  // trended out of the band over many ordinary bars keeps its full fit.
  final sortedRanges = List<double>.of(ranges)..sort();
  final median = sortedRanges[n ~/ 2];
  var largest = 0.0;
  for (var i = 0; i < n; i++) {
    if ((lows[i] < bandLo || highs[i] > bandHi) && ranges[i] > largest) {
      largest = ranges[i];
    }
  }
  if (!(largest > median * kHlOutlierBarFactor)) return null;

  final last = visible.last.close;
  return (lo: math.min(bandLo, last), hi: math.max(bandHi, last));
}
