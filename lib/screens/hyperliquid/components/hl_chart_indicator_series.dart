// lib/screens/hyperliquid/components/hl_chart_indicator_series.dart
//
// The Advanced chart's indicator maths: pure functions over the candles
// the chart holds, no Flutter. Each follows TradingView's built-in of the
// same name (its Pine reference), so a trader comparing the two sees the
// same numbers once the series is warm:
//
//   * SMA, EMA (seeded with the SMA of its first `period` values, as
//     ta.ema), Wilder's RMA (ta.rma).
//   * Bollinger bands: SMA ± mult × population standard deviation.
//   * RSI (ta.rsi: RMA of gains and losses), MACD (three EMAs), Stoch RSI
//     (ta.stoch of the RSI, %K and %D as SMAs).
//   * ATR (ta.atr: RMA of the true range, the first bar's being its
//     high − low), Supertrend (ta.supertrend on hl2).
//   * OBV (ta.obv), anchored VWAP (ta.vwap on hlc3, restarting each UTC
//     day / week / month), the visible range's volume profile.
//   * Ichimoku as TradingView's built-in: conversion and base lines (the
//     Donchian midline over 9 and 26), the leading spans drawn 25 bars
//     ahead and the lagging line 25 behind (displacement − 1, its offsets).
//     The chart's x axis has no bars past the newest (a bar's x is its
//     index in the window), so the cloud is NOT projected past it: it is
//     cut at the last bar rather than misplaced. The lagging line ends
//     displacement − 1 bars before the last bar, as there.
//   * ADX with +DI and −DI as TradingView's Directional Movement Index.
//   * Pivot points, standard ("Traditional" in TradingView's Pivot Points
//     Standard), daily: the previous UTC day's high, low and close from
//     real daily candles, each day's levels drawn across that day's bars.
//   * Heikin Ashi bars.
//
// Every series is ALIGNED to the candles: index i is the value at bar i,
// double.nan through the warm-up and wherever an input is missing, so a
// painter gaps instead of drawing a ramp.

import 'dart:math' as math;

import 'package:kute/models/hyperliquid_model.dart';

List<double> _closes(List<HyperliquidCandle> candles) =>
    [for (final k in candles) k.close];

/// Simple moving average of [values] over [period]. A missing value
/// restarts the window.
List<double> hlSma(List<double> values, int period) {
  if (period < 1) throw ArgumentError.value(period, 'period');
  final out = List<double>.filled(values.length, double.nan);
  var sum = 0.0;
  var run = 0;
  for (var i = 0; i < values.length; i++) {
    final v = values[i];
    if (!v.isFinite) {
      sum = 0;
      run = 0;
      continue;
    }
    sum += v;
    run++;
    if (run > period) {
      sum -= values[i - period];
      run = period;
    }
    if (run == period) out[i] = sum / period;
  }
  return out;
}

/// The recursive average both EMA and RMA are: seeded with the SMA of the
/// first [period] values, then `alpha × value + (1 − alpha) × previous`.
/// A missing value restarts the seed.
List<double> _seededAverage(List<double> values, int period, double alpha) {
  if (period < 1) throw ArgumentError.value(period, 'period');
  final out = List<double>.filled(values.length, double.nan);
  double? prev;
  var seedSum = 0.0;
  var seedRun = 0;
  for (var i = 0; i < values.length; i++) {
    final v = values[i];
    if (!v.isFinite) {
      prev = null;
      seedSum = 0;
      seedRun = 0;
      continue;
    }
    final p = prev;
    if (p != null) {
      prev = alpha * v + (1 - alpha) * p;
      out[i] = prev;
      continue;
    }
    seedSum += v;
    seedRun++;
    if (seedRun == period) {
      prev = seedSum / period;
      out[i] = prev;
    }
  }
  return out;
}

/// Exponential moving average (alpha 2 / (period + 1)), as ta.ema.
List<double> hlEma(List<double> values, int period) =>
    _seededAverage(values, period, 2 / (period + 1));

/// Wilder's moving average (alpha 1 / period), as ta.rma.
List<double> hlRma(List<double> values, int period) =>
    _seededAverage(values, period, 1 / period);

/// Bollinger bands on closes: the SMA over [period] ± [mult] population
/// standard deviations (ta.stdev), as TradingView's built-in.
({List<double> upper, List<double> basis, List<double> lower}) hlBollinger(
    List<HyperliquidCandle> candles,
    {int period = 20,
    double mult = 2}) {
  final closes = _closes(candles);
  final basis = hlSma(closes, period);
  final n = closes.length;
  final upper = List<double>.filled(n, double.nan);
  final lower = List<double>.filled(n, double.nan);
  for (var i = 0; i < n; i++) {
    final m = basis[i];
    if (!m.isFinite) continue;
    var v = 0.0;
    for (var j = i - period + 1; j <= i; j++) {
      final d = closes[j] - m;
      v += d * d;
    }
    final sd = math.sqrt(v / period);
    upper[i] = m + mult * sd;
    lower[i] = m - mult * sd;
  }
  return (upper: upper, basis: basis, lower: lower);
}

/// RSI as ta.rsi: Wilder averages (RMA) of the close's gains and losses
/// over [period]; the first value is at bar [period]. A market that did
/// not move over the whole window reads 50.
List<double> hlRsi(List<double> closes, {int period = 14}) {
  if (period < 1) throw ArgumentError.value(period, 'period');
  final n = closes.length;
  final up = List<double>.filled(n, double.nan);
  final down = List<double>.filled(n, double.nan);
  for (var i = 1; i < n; i++) {
    final d = closes[i] - closes[i - 1];
    if (!d.isFinite) continue;
    up[i] = d > 0 ? d : 0.0;
    down[i] = d < 0 ? -d : 0.0;
  }
  final g = hlRma(up, period);
  final l = hlRma(down, period);
  return List<double>.generate(n, (i) {
    final gi = g[i], li = l[i];
    if (!gi.isFinite || !li.isFinite) return double.nan;
    if (li == 0) return gi == 0 ? 50 : 100;
    return 100 - 100 / (1 + gi / li);
  }, growable: false);
}

/// RSI of the candles' closes.
List<double> hlWilderRsi(List<HyperliquidCandle> candles, {int period = 14}) =>
    hlRsi(_closes(candles), period: period);

/// MACD on closes as ta.macd: EMA(fast) − EMA(slow), its EMA(signal) and
/// the histogram between them.
({List<double> macd, List<double> signal, List<double> histogram}) hlMacd(
    List<HyperliquidCandle> candles,
    {int fast = 12,
    int slow = 26,
    int signal = 9}) {
  final closes = _closes(candles);
  final f = hlEma(closes, fast);
  final s = hlEma(closes, slow);
  final macd = List<double>.generate(closes.length,
      (i) => f[i].isFinite && s[i].isFinite ? f[i] - s[i] : double.nan,
      growable: false);
  final sig = hlEma(macd, signal);
  final hist = List<double>.generate(
      closes.length,
      (i) => macd[i].isFinite && sig[i].isFinite
          ? macd[i] - sig[i]
          : double.nan,
      growable: false);
  return (macd: macd, signal: sig, histogram: hist);
}

/// Stochastic RSI as TradingView's built-in: the RSI's position in its
/// own [stochPeriod] range (0..100), %K its SMA over [smoothK] and %D the
/// SMA of %K over [smoothD]. An RSI that did not move over the window has
/// no position (a gap), as there.
({List<double> k, List<double> d}) hlStochRsi(
  List<HyperliquidCandle> candles, {
  int rsiPeriod = 14,
  int stochPeriod = 14,
  int smoothK = 3,
  int smoothD = 3,
}) {
  final rsi = hlRsi(_closes(candles), period: rsiPeriod);
  final n = rsi.length;
  final raw = List<double>.filled(n, double.nan);
  for (var i = stochPeriod - 1; i < n; i++) {
    var hi = double.negativeInfinity, lo = double.infinity;
    var ok = true;
    for (var j = i - stochPeriod + 1; j <= i; j++) {
      final v = rsi[j];
      if (!v.isFinite) {
        ok = false;
        break;
      }
      if (v > hi) hi = v;
      if (v < lo) lo = v;
    }
    if (ok && hi > lo) raw[i] = (rsi[i] - lo) / (hi - lo) * 100;
  }
  final k = _smaStrict(raw, smoothK);
  return (k: k, d: _smaStrict(k, smoothD));
}

/// SMA that is missing wherever its window holds a missing value (Pine's
/// ta.sma over a series with na in it), with no restart.
List<double> _smaStrict(List<double> v, int p) {
  final o = List<double>.filled(v.length, double.nan);
  for (var i = p - 1; i < v.length; i++) {
    var s = 0.0;
    var ok = true;
    for (var j = i - p + 1; j <= i; j++) {
      if (!v[j].isFinite) {
        ok = false;
        break;
      }
      s += v[j];
    }
    if (ok) o[i] = s / p;
  }
  return o;
}

/// The true range of each bar (ta.tr(true)): the first bar's is its
/// high − low.
List<double> hlTrueRange(List<HyperliquidCandle> candles) =>
    List<double>.generate(candles.length, (i) {
      final k = candles[i];
      if (i == 0) return k.high - k.low;
      final pc = candles[i - 1].close;
      return math.max(
          k.high - k.low, math.max((k.high - pc).abs(), (k.low - pc).abs()));
    }, growable: false);

/// ATR as ta.atr: Wilder's average of the true range; the first value is
/// at bar period − 1.
List<double> hlAtr(List<HyperliquidCandle> candles, {int period = 14}) =>
    hlRma(hlTrueRange(candles), period);

/// Supertrend as ta.supertrend(factor, atrPeriod) on hl2. [line] is the
/// trailing stop; [up] is true where the trend is up (the line under the
/// price), false where it is down, null through the ATR's warm-up.
({List<double> line, List<bool?> up}) hlSupertrend(
  List<HyperliquidCandle> candles, {
  int period = 10,
  double factor = 3,
}) {
  final n = candles.length;
  final atr = hlAtr(candles, period: period);
  final line = List<double>.filled(n, double.nan);
  final up = List<bool?>.filled(n, null);
  var prevLower = double.nan, prevUpper = double.nan, prevLine = double.nan;
  for (var i = 0; i < n; i++) {
    final a = atr[i];
    if (!a.isFinite) continue;
    final k = candles[i];
    final src = (k.high + k.low) / 2;
    var lower = src - factor * a;
    var upper = src + factor * a;
    final pl = prevLower.isFinite ? prevLower : 0.0;
    final pu = prevUpper.isFinite ? prevUpper : 0.0;
    final prevClose = i > 0 ? candles[i - 1].close : double.nan;
    // The bands only tighten while the price stays on their side.
    if (!(lower > pl || prevClose < pl)) lower = pl;
    if (!(upper < pu || prevClose > pu)) upper = pu;
    bool trendUp;
    if (i == 0 || !atr[i - 1].isFinite) {
      trendUp = false;
    } else if (prevLine == pu) {
      trendUp = k.close > upper;
    } else {
      trendUp = !(k.close < lower);
    }
    line[i] = trendUp ? lower : upper;
    up[i] = trendUp;
    prevLower = lower;
    prevUpper = upper;
    prevLine = line[i];
  }
  return (line: line, up: up);
}

/// On-balance volume as ta.obv: the running total of each bar's volume,
/// added on an up close and taken off on a down close; 0 at the first bar.
List<double> hlObv(List<HyperliquidCandle> candles) {
  final out = List<double>.filled(candles.length, double.nan);
  var total = 0.0;
  for (var i = 0; i < candles.length; i++) {
    if (i > 0) {
      final d = candles[i].close - candles[i - 1].close;
      final v = candles[i].volume;
      if (d.isFinite && v.isFinite) {
        if (d > 0) total += v;
        if (d < 0) total -= v;
      }
    }
    out[i] = total;
  }
  return out;
}

/// When a VWAP starts over.
enum HlVwapAnchor { day, week, month }

/// The anchor TradingView's session VWAP comes closest to for bars
/// [barMs] long: a UTC day for intraday bars (crypto's session), a week
/// for daily bars and a month for anything longer.
HlVwapAnchor hlVwapAnchorFor(int barMs) {
  if (barMs < const Duration(days: 1).inMilliseconds) return HlVwapAnchor.day;
  if (barMs < const Duration(days: 7).inMilliseconds) return HlVwapAnchor.week;
  return HlVwapAnchor.month;
}

/// The bars' length, from their open times (the smallest step between
/// two bars, so a gap in a thin market does not stretch it).
int hlBarMs(List<HyperliquidCandle> candles) {
  if (candles.length < 2) {
    if (candles.isEmpty) return const Duration(hours: 1).inMilliseconds;
    final k = candles.first;
    return math.max(
        60000, k.closeTime.difference(k.openTime).inMilliseconds);
  }
  var best = 1 << 62;
  final last = math.min(candles.length, 50);
  for (var i = 1; i < last; i++) {
    final d = candles[i].openTime.millisecondsSinceEpoch -
        candles[i - 1].openTime.millisecondsSinceEpoch;
    if (d > 0 && d < best) best = d;
  }
  return best == 1 << 62 ? 60000 : best;
}

int _anchorPeriod(DateTime openTime, HlVwapAnchor anchor) {
  final t = openTime.toUtc();
  switch (anchor) {
    case HlVwapAnchor.day:
      return t.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
    case HlVwapAnchor.week:
      // Days since the epoch (a Thursday), so weeks start on Monday.
      final day = t.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
      return (day + 3) ~/ 7;
    case HlVwapAnchor.month:
      return t.year * 12 + t.month;
  }
}

/// Anchored VWAP as ta.vwap(hlc3) with an anchor timeframe: the volume-
/// weighted average typical price since the start of the bar's UTC day,
/// week or month ([anchor]; by default from the bars' length,
/// [hlVwapAnchorFor]). Missing until the period has traded.
List<double> hlAnchoredVwap(List<HyperliquidCandle> candles,
    {HlVwapAnchor? anchor}) {
  final a = anchor ?? hlVwapAnchorFor(hlBarMs(candles));
  final out = List<double>.filled(candles.length, double.nan);
  var weighted = 0.0;
  var volume = 0.0;
  int? period;
  for (var i = 0; i < candles.length; i++) {
    final k = candles[i];
    final p = _anchorPeriod(k.openTime, a);
    if (p != period) {
      period = p;
      weighted = 0;
      volume = 0;
    }
    final typical = (k.high + k.low + k.close) / 3;
    if (typical.isFinite && k.volume.isFinite && k.volume >= 0) {
      weighted += typical * k.volume;
      volume += k.volume;
    }
    if (volume > 0) out[i] = weighted / volume;
  }
  return out;
}

/// The volume traded at each price over a set of bars: [rows] equal price
/// rows from [lo] to [hi], each row's volume split into the part traded
/// on up bars ([up]) and on down bars ([down]). [poc] is the row with the
/// most volume (the point of control) and [vaLow]..[vaHigh] the rows of
/// the value area around it.
class HlVolumeProfile {
  const HlVolumeProfile({
    required this.lo,
    required this.hi,
    required this.up,
    required this.down,
    required this.poc,
    required this.vaLow,
    required this.vaHigh,
  });

  final double lo, hi;
  final List<double> up, down;
  final int poc, vaLow, vaHigh;

  int get rows => up.length;
  double get rowHeight => (hi - lo) / rows;
  double total(int row) => up[row] + down[row];

  /// The middle price of [row].
  double priceAt(int row) => lo + (row + 0.5) * rowHeight;

  double get maxRow {
    var m = 0.0;
    for (var i = 0; i < rows; i++) {
      m = math.max(m, total(i));
    }
    return m;
  }
}

/// The volume profile of [candles] in [rows] rows between their lowest
/// low and highest high. Each bar's volume is spread evenly over its own
/// low..high (TradingView's visible-range profile works from lower-
/// timeframe bars; spreading a bar's volume over its range is the usual
/// stand-in when only the bar is known). The value area grows from the
/// point of control one row at a time toward the busier neighbour until
/// it holds [valueArea] of the volume. Null without volume.
HlVolumeProfile? hlVolumeProfile(
  List<HyperliquidCandle> candles, {
  int rows = 24,
  double valueArea = 0.70,
}) {
  if (rows < 1 || candles.isEmpty) return null;
  var lo = double.infinity, hi = double.negativeInfinity;
  for (final k in candles) {
    if (!k.low.isFinite || !k.high.isFinite) continue;
    lo = math.min(lo, k.low);
    hi = math.max(hi, k.high);
  }
  if (!lo.isFinite || !hi.isFinite) return null;
  if (hi <= lo) hi = lo + (lo.abs() * 1e-6 + 1e-12);
  final step = (hi - lo) / rows;
  final up = List<double>.filled(rows, 0);
  final down = List<double>.filled(rows, 0);
  var total = 0.0;
  int rowOf(double p) => ((p - lo) / step).floor().clamp(0, rows - 1);
  for (final k in candles) {
    final v = k.volume;
    if (!v.isFinite || v <= 0 || !k.low.isFinite || !k.high.isFinite) {
      continue;
    }
    final side = k.close >= k.open ? up : down;
    total += v;
    final range = k.high - k.low;
    if (range <= 0) {
      side[rowOf(k.close)] += v;
      continue;
    }
    final first = rowOf(k.low), last = rowOf(k.high);
    for (var r = first; r <= last; r++) {
      final rLo = lo + r * step, rHi = rLo + step;
      final overlap = math.min(rHi, k.high) - math.max(rLo, k.low);
      if (overlap > 0) side[r] += v * overlap / range;
    }
  }
  if (total <= 0) return null;
  var poc = 0;
  for (var r = 1; r < rows; r++) {
    if (up[r] + down[r] > up[poc] + down[poc]) poc = r;
  }
  var a = poc, b = poc;
  var inArea = up[poc] + down[poc];
  while (inArea < total * valueArea && (a > 0 || b < rows - 1)) {
    final above = b < rows - 1 ? up[b + 1] + down[b + 1] : -1.0;
    final below = a > 0 ? up[a - 1] + down[a - 1] : -1.0;
    if (above >= below) {
      b++;
      inArea += above;
    } else {
      a--;
      inArea += below;
    }
  }
  return HlVolumeProfile(
    lo: lo,
    hi: hi,
    up: up,
    down: down,
    poc: poc,
    vaLow: a,
    vaHigh: b,
  );
}

/// The midline of the highest high and the lowest low over [period] bars,
/// as TradingView's Ichimoku `donchian(len)`. One pass (two monotonic
/// queues), missing through the first [period] − 1 bars.
List<double> hlDonchianMid(List<HyperliquidCandle> candles, int period) {
  if (period < 1) throw ArgumentError.value(period, 'period');
  final n = candles.length;
  final out = List<double>.filled(n, double.nan);
  final highs = List<int>.filled(n, 0);
  final lows = List<int>.filled(n, 0);
  var hHead = 0, hTail = 0, lHead = 0, lTail = 0;
  for (var i = 0; i < n; i++) {
    final k = candles[i];
    while (hTail > hHead && candles[highs[hTail - 1]].high <= k.high) {
      hTail--;
    }
    highs[hTail++] = i;
    while (lTail > lHead && candles[lows[lTail - 1]].low >= k.low) {
      lTail--;
    }
    lows[lTail++] = i;
    if (highs[hHead] <= i - period) hHead++;
    if (lows[lHead] <= i - period) lHead++;
    if (i >= period - 1) {
      out[i] = (candles[highs[hHead]].high + candles[lows[lHead]].low) / 2;
    }
  }
  return out;
}

/// Ichimoku as TradingView's built-in, every series as it is DRAWN at each
/// bar: [spanA] and [spanB] are the values computed displacement − 1 bars
/// earlier (missing through their warm-up), [lagging] the close
/// displacement − 1 bars later (missing over the newest of them).
({
  List<double> conversion,
  List<double> base,
  List<double> spanA,
  List<double> spanB,
  List<double> lagging,
}) hlIchimoku(
  List<HyperliquidCandle> candles, {
  int conversion = 9,
  int base = 26,
  int spanB = 52,
  int displacement = 26,
}) {
  final n = candles.length;
  final conv = hlDonchianMid(candles, conversion);
  final bas = hlDonchianMid(candles, base);
  final lead2 = hlDonchianMid(candles, spanB);
  final shift = displacement - 1;
  final a = List<double>.filled(n, double.nan);
  final b = List<double>.filled(n, double.nan);
  final lag = List<double>.filled(n, double.nan);
  for (var i = 0; i < n; i++) {
    final j = i - shift;
    if (j >= 0) {
      a[i] = (conv[j] + bas[j]) / 2;
      b[i] = lead2[j];
    }
    if (i + shift < n) lag[i] = candles[i + shift].close;
  }
  return (conversion: conv, base: bas, spanA: a, spanB: b, lagging: lag);
}

/// ADX with its directional lines as TradingView's Directional Movement
/// Index: +DM and −DM (the bigger of the high's rise and the low's fall,
/// the other 0) over the true range ([ta.tr], missing on the first bar),
/// each with Wilder's RMA over [length] and the ratio ×100 held across a
/// bar with no range (fixnan); ADX is the RMA over [smoothing] of
/// |+DI − −DI| / (+DI + −DI) ×100. +DI and −DI start at bar [length], ADX
/// at bar [length] + [smoothing] − 1.
({List<double> adx, List<double> plusDi, List<double> minusDi}) hlAdx(
  List<HyperliquidCandle> candles, {
  int length = 14,
  int smoothing = 14,
}) {
  final n = candles.length;
  final tr = List<double>.filled(n, double.nan);
  final plusDm = List<double>.filled(n, double.nan);
  final minusDm = List<double>.filled(n, double.nan);
  for (var i = 1; i < n; i++) {
    final k = candles[i], prev = candles[i - 1];
    final up = k.high - prev.high;
    final down = prev.low - k.low;
    plusDm[i] = up > down && up > 0 ? up : 0.0;
    minusDm[i] = down > up && down > 0 ? down : 0.0;
    tr[i] = math.max(k.high - k.low,
        math.max((k.high - prev.close).abs(), (k.low - prev.close).abs()));
  }
  final atr = hlRma(tr, length);
  final plusRma = hlRma(plusDm, length);
  final minusRma = hlRma(minusDm, length);
  final plus = List<double>.filled(n, double.nan);
  final minus = List<double>.filled(n, double.nan);
  final dx = List<double>.filled(n, double.nan);
  var lastPlus = double.nan, lastMinus = double.nan;
  for (var i = 0; i < n; i++) {
    final a = atr[i];
    if (!a.isFinite) continue;
    if (a > 0) {
      lastPlus = 100 * plusRma[i] / a;
      lastMinus = 100 * minusRma[i] / a;
    }
    plus[i] = lastPlus;
    minus[i] = lastMinus;
    if (!lastPlus.isFinite || !lastMinus.isFinite) continue;
    final sum = lastPlus + lastMinus;
    dx[i] = (lastPlus - lastMinus).abs() / (sum == 0 ? 1 : sum);
  }
  final adx = hlRma(dx, smoothing);
  return (
    adx: [for (final v in adx) v * 100],
    plusDi: plus,
    minusDi: minus,
  );
}

/// One day's standard pivot points.
class HlPivotLevels {
  const HlPivotLevels({
    required this.p,
    required this.r1,
    required this.r2,
    required this.r3,
    required this.s1,
    required this.s2,
    required this.s3,
  });

  final double p, r1, r2, r3, s1, s2, s3;

  /// From the day before's [high], [low] and [close], as TradingView's
  /// Pivot Points Standard, type Traditional.
  factory HlPivotLevels.of(double high, double low, double close) {
    final p = (high + low + close) / 3;
    return HlPivotLevels(
      p: p,
      r1: p * 2 - low,
      s1: p * 2 - high,
      r2: p + (high - low),
      s2: p - (high - low),
      r3: p * 2 + (high - 2 * low),
      s3: p * 2 - (2 * high - low),
    );
  }
}

/// Bars of a longer interval show this many bars of the newest day's
/// levels: a day there is a bar or less, with no span of its own to draw.
const int kHlPivotLongBarSpan = 10;

int _utcDay(DateTime t) =>
    t.toUtc().millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;

/// The standard pivots to draw on [bars], from real [daily] candles (both
/// ascending): at each bar, its UTC day's levels, from the last daily
/// candle before that day. The bars of a day draw one flat stretch, the
/// first bar of the next left empty so the stretches never join. Bars of
/// a day or longer have no day of their own: the newest day's levels over
/// the newest [kHlPivotLongBarSpan] bars. Missing where no earlier daily
/// candle is known.
({
  List<double> p,
  List<double> r1,
  List<double> r2,
  List<double> r3,
  List<double> s1,
  List<double> s2,
  List<double> s3,
}) hlDailyPivots(
  List<HyperliquidCandle> bars,
  List<HyperliquidCandle> daily,
) {
  final n = bars.length;
  List<double> empty() => List<double>.filled(n, double.nan);
  final p = empty(), r1 = empty(), r2 = empty(), r3 = empty();
  final s1 = empty(), s2 = empty(), s3 = empty();
  void put(int i, HlPivotLevels l) {
    p[i] = l.p;
    r1[i] = l.r1;
    r2[i] = l.r2;
    r3[i] = l.r3;
    s1[i] = l.s1;
    s2[i] = l.s2;
    s3[i] = l.s3;
  }

  HlPivotLevels of(HyperliquidCandle k) =>
      HlPivotLevels.of(k.high, k.low, k.close);

  if (n > 0 && daily.isNotEmpty) {
    if (hlBarMs(bars) >= Duration.millisecondsPerDay) {
      // The newest day either tape knows; the daily candle before it.
      final newest = daily.last.openTime.isBefore(bars.last.closeTime)
          ? _utcDay(daily.last.openTime)
          : _utcDay(bars.last.closeTime);
      var prev = daily.length - 1;
      while (prev >= 0 && _utcDay(daily[prev].openTime) >= newest) {
        prev--;
      }
      if (prev >= 0) {
        final levels = of(daily[prev]);
        final from = math.max(0, n - kHlPivotLongBarSpan);
        for (var i = from; i < n; i++) {
          put(i, levels);
        }
      }
    } else {
      // Both ascending: one walk along the daily candles.
      var next = 0; // the first daily candle not before the bar's day
      int? day;
      HlPivotLevels? levels;
      for (var i = 0; i < n; i++) {
        final d = _utcDay(bars[i].openTime);
        final first = d != day;
        if (first) {
          day = d;
          while (next < daily.length &&
              _utcDay(daily[next].openTime) < d) {
            next++;
          }
          levels = next > 0 ? of(daily[next - 1]) : null;
        }
        // The first bar of a day after another one stays empty.
        if (first && i > 0) continue;
        final l = levels;
        if (l != null) put(i, l);
      }
    }
  }
  return (p: p, r1: r1, r2: r2, r3: r3, s1: s1, s2: s2, s3: s3);
}

/// [bars] merged into one bar per UTC day: what the Chart sheet's Pivots
/// card previews from (the chart itself reads real daily candles).
List<HyperliquidCandle> hlDailyFromBars(List<HyperliquidCandle> bars) {
  final out = <HyperliquidCandle>[];
  int? day;
  for (final k in bars) {
    final d = _utcDay(k.openTime);
    if (d == day) {
      final last = out.last;
      out[out.length - 1] = HyperliquidCandle(
        openTime: last.openTime,
        closeTime: k.closeTime,
        open: last.open,
        high: math.max(last.high, k.high),
        low: math.min(last.low, k.low),
        close: k.close,
        volume: last.volume + k.volume,
      );
    } else {
      day = d;
      out.add(k);
    }
  }
  return out;
}

/// Heikin Ashi bars derived from real candles: each bar's close is the
/// average of the real OHLC, its open the midpoint of the previous HA
/// bar, high/low the extremes of real high/low and the HA open/close.
/// Time and volume are the real bar's, so everything keyed by index
/// (drawings, fills, trade lines) stays in register.
List<HyperliquidCandle> hlHeikinAshi(List<HyperliquidCandle> candles) {
  if (candles.isEmpty) return candles;
  final out = <HyperliquidCandle>[];
  double? prevOpen, prevClose;
  for (final k in candles) {
    final close = (k.open + k.high + k.low + k.close) / 4;
    final open = prevOpen == null || prevClose == null
        ? (k.open + k.close) / 2
        : (prevOpen + prevClose) / 2;
    final high = math.max(k.high, math.max(open, close));
    final low = math.min(k.low, math.min(open, close));
    out.add(HyperliquidCandle(
      openTime: k.openTime,
      closeTime: k.closeTime,
      open: open,
      high: high,
      low: low,
      close: close,
      volume: k.volume,
    ));
    prevOpen = open;
    prevClose = close;
  }
  return out;
}
