import 'dart:math' as math;

import 'package:kute/models/hyperliquid_model.dart';

/// Cumulative VWAP from the start of the displayed candle window. This is
/// explicitly not an exchange-session VWAP: crypto trades around the clock
/// and the loaded window may start mid-session. Uses HLC3 and base volume.
List<double> hlWindowVwap(List<HyperliquidCandle> candles) {
  var weighted = 0.0;
  var volume = 0.0;
  return List.generate(candles.length, (i) {
    final bar = candles[i];
    final typical = (bar.high + bar.low + bar.close) / 3;
    if (!typical.isFinite || !bar.volume.isFinite || bar.volume < 0) {
      return double.nan;
    }
    weighted += typical * bar.volume;
    volume += bar.volume;
    return volume > 0 && weighted.isFinite && volume.isFinite
        ? weighted / volume
        : double.nan;
  }, growable: false);
}

/// Wilder RSI: seed with 14 price changes, then smooth gains and losses
/// by 1/period. Missing observations restart warm-up; flat markets are 50.
List<double> hlWilderRsi(List<HyperliquidCandle> candles, {int period = 14}) {
  if (period < 1) throw ArgumentError.value(period, 'period');
  final out = List<double>.filled(candles.length, double.nan);
  var gain = 0.0;
  var loss = 0.0;
  var changes = 0;
  for (var i = 1; i < candles.length; i++) {
    final delta = candles[i].close - candles[i - 1].close;
    if (!delta.isFinite) {
      gain = 0;
      loss = 0;
      changes = 0;
      continue;
    }
    final up = delta > 0 ? delta : 0.0;
    final down = delta < 0 ? -delta : 0.0;
    changes++;
    if (changes <= period) {
      gain += up / period;
      loss += down / period;
    } else {
      gain = (gain * (period - 1) + up) / period;
      loss = (loss * (period - 1) + down) / period;
    }
    if (changes >= period) {
      out[i] =
          loss == 0 ? (gain == 0 ? 50 : 100) : 100 - 100 / (1 + gain / loss);
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

List<double> _ema(List<double> values, int period) {
  final out = List<double>.filled(values.length, double.nan);
  final k = 2 / (period + 1);
  double? e;
  var seen = 0;
  for (var i = 0; i < values.length; i++) {
    final v = values[i];
    if (!v.isFinite) continue;
    seen++;
    e = e == null ? v : v * k + e * (1 - k);
    if (seen >= period) out[i] = e;
  }
  return out;
}

/// MACD 12/26/9 on closes: the line, its signal and the histogram.
({List<double> macd, List<double> signal, List<double> histogram}) hlMacd(
    List<HyperliquidCandle> candles,
    {int fast = 12, int slow = 26, int signal = 9}) {
  final closes = [for (final k in candles) k.close];
  final f = _ema(closes, fast);
  final s = _ema(closes, slow);
  final macd = List<double>.generate(
      closes.length, (i) => f[i].isFinite && s[i].isFinite ? f[i] - s[i] : double.nan);
  final sig = _ema(macd, signal);
  final hist = List<double>.generate(closes.length,
      (i) => macd[i].isFinite && sig[i].isFinite ? macd[i] - sig[i] : double.nan);
  return (macd: macd, signal: sig, histogram: hist);
}

/// Wilder ATR: true range smoothed by 1/period after a simple seed.
List<double> hlAtr(List<HyperliquidCandle> candles, {int period = 14}) {
  final out = List<double>.filled(candles.length, double.nan);
  double? atr;
  var sum = 0.0;
  for (var i = 1; i < candles.length; i++) {
    final k = candles[i], p = candles[i - 1];
    final tr = math.max(k.high - k.low,
        math.max((k.high - p.close).abs(), (k.low - p.close).abs()));
    if (i <= period) {
      sum += tr;
      if (i == period) {
        atr = sum / period;
        out[i] = atr;
      }
    } else {
      atr = (atr! * (period - 1) + tr) / period;
      out[i] = atr;
    }
  }
  return out;
}

/// Stochastic %K (period, smoothed by [smooth]) and %D (SMA of %K over
/// [dPeriod]), both 0..100.
({List<double> k, List<double> d}) hlStochastic(List<HyperliquidCandle> candles,
    {int period = 14, int smooth = 3, int dPeriod = 3}) {
  final n = candles.length;
  final raw = List<double>.filled(n, double.nan);
  for (var i = period - 1; i < n; i++) {
    var hi = double.negativeInfinity, lo = double.infinity;
    for (var j = i - period + 1; j <= i; j++) {
      hi = math.max(hi, candles[j].high);
      lo = math.min(lo, candles[j].low);
    }
    raw[i] = hi > lo ? (candles[i].close - lo) / (hi - lo) * 100 : 50;
  }
  List<double> sma(List<double> v, int p) {
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
  final k = sma(raw, smooth);
  return (k: k, d: sma(k, dPeriod));
}

/// Simple moving average of volume, on the volume scale.
List<double> hlVolumeSma(List<HyperliquidCandle> candles, {int period = 20}) {
  final out = List<double>.filled(candles.length, double.nan);
  var sum = 0.0;
  for (var i = 0; i < candles.length; i++) {
    sum += candles[i].volume;
    if (i >= period) sum -= candles[i - period].volume;
    if (i >= period - 1) out[i] = sum / period;
  }
  return out;
}
