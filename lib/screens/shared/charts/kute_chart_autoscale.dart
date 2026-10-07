// lib/screens/shared/charts/kute_chart_autoscale.dart
//
// TradingView-style price autoscale for the native chart stack
// (Lightweight Charts `autoScale` semantics):
//
//   * the price scale fits the high/low of the bars that are ON SCREEN,
//     never the whole loaded tape, with a fixed share of the price area
//     kept empty above and below ([kuteAutoScaleMargin], ~10%);
//   * only the SERIES drives the fit. Price lines (entry, liquidation,
//     TP/SL, working orders) and drawings never widen it, so a far-away
//     liquidation line cannot squash the candles;
//   * live ticks inside an unchanged window only refit when price walks
//     out of the current range ([KuteAutoScaleTracker]), so the axis does
//     not jitter on every trade;
//   * min/max per window comes from [KuteRangeExtremes]: block extremes
//     built once per tape and patched on a leading-bar tick, so a pan or
//     a pinch queries O(n / 32 + 64) values instead of rescanning.
//
// Hosts animate between successive targets themselves (the HL chart uses
// an implicit tween), so the scale glides instead of jumping. Nothing
// here allocates per frame.

import 'dart:typed_data';

import 'package:kute/screens/shared/charts/kute_chart_core.dart';

/// Share of the price area kept empty above the visible high and below
/// the visible low.
const double kuteAutoScaleMargin = 0.1;

/// The autoscaled y-domain for visible data spanning [lo]..[hi] (already
/// in axis space: price, or ln(price) on a log axis). The data occupies
/// the middle (1 - 2 × margin) of the price area. A flat series gets a
/// ±1% band so it still has a non-zero span.
KuteYDomain kuteAutoScaleDomain(
  double lo,
  double hi, {
  double margin = kuteAutoScaleMargin,
}) {
  final range = hi - lo;
  if (!(range > 0)) {
    final pad = (hi.abs() * 0.01).clamp(1e-9, double.infinity).toDouble();
    return (minY: lo - pad, maxY: hi + pad);
  }
  final pad = range * margin / (1 - 2 * margin);
  return (minY: lo - pad, maxY: hi + pad);
}

/// Remembers the last fitted target so live ticks inside the same window
/// keep the scale still until price leaves it. A changed window (pan,
/// pinch, new bar, other interval) always refits.
class KuteAutoScaleTracker {
  Object? _windowKey;
  KuteYDomain? _target;

  /// The target domain for data [lo]..[hi] in the window identified by
  /// [windowKey] (any value-comparable token: first bar time, bar count,
  /// series kind, axis kind).
  ///
  /// [domain] replaces [kuteAutoScaleDomain] for a chart with its own
  /// fitting rule (a probability chart stays inside 0..1). A domain that
  /// rule pins to a bound is never "left" by data sitting on that bound.
  KuteYDomain fit(
    Object windowKey,
    double lo,
    double hi, {
    KuteYDomain Function(double lo, double hi)? domain,
  }) {
    final t = _target;
    if (t != null && windowKey == _windowKey) {
      // Hold while the data stays clear of the outer half of the margin.
      final hold = (t.maxY - t.minY) * kuteAutoScaleMargin * 0.5;
      if (domain == null) {
        if (lo >= t.minY + hold && hi <= t.maxY - hold) return t;
      } else {
        // Hold while a fresh fit would sit inside the one shown without
        // being much tighter: the data has neither walked out of the
        // scale nor left it loose around a line that has calmed down.
        final fresh = domain(lo, hi);
        final inside =
            fresh.minY >= t.minY - 1e-9 && fresh.maxY <= t.maxY + 1e-9;
        final loose = (fresh.maxY - fresh.minY) < (t.maxY - t.minY) * 0.6;
        if (inside && !loose) return t;
      }
    }
    _windowKey = windowKey;
    return _target = (domain ?? kuteAutoScaleDomain)(lo, hi);
  }

  void reset() {
    _windowKey = null;
    _target = null;
  }
}

/// Range min/max over a series. Values are grouped in blocks of 32 with
/// each block's extremes cached, so a query over [start, end) reads the
/// partial blocks at the edges plus one pair per whole block between.
///
/// [sync] rebuilds every block for a new tape, and only the last block
/// when the tape kept its length and its earlier bars (the live-tick
/// case: the provider replaces the leading bar in place).
class KuteRangeExtremes<T> {
  KuteRangeExtremes({required this.lowOf, required this.highOf});

  final double Function(T) lowOf;
  final double Function(T) highOf;

  static const int _block = 32;

  List<T>? _src;
  int _len = 0;
  Float64List _blockLo = Float64List(0);
  Float64List _blockHi = Float64List(0);

  /// Sample bars used to tell a leading-bar tick from a new tape.
  double _firstLo = double.nan, _firstHi = double.nan;
  double _midLo = double.nan, _midHi = double.nan;
  double _penLo = double.nan, _penHi = double.nan;

  void sync(List<T> data) {
    if (identical(data, _src)) return;
    final n = data.length;
    final tickOnly = n == _len &&
        n >= 3 &&
        lowOf(data[0]) == _firstLo &&
        highOf(data[0]) == _firstHi &&
        lowOf(data[n >> 1]) == _midLo &&
        highOf(data[n >> 1]) == _midHi &&
        lowOf(data[n - 2]) == _penLo &&
        highOf(data[n - 2]) == _penHi;
    _src = data;
    if (tickOnly) {
      _rebuildBlock(data, (n - 1) ~/ _block);
      return;
    }
    _len = n;
    final blocks = (n + _block - 1) ~/ _block;
    if (_blockLo.length != blocks) {
      _blockLo = Float64List(blocks);
      _blockHi = Float64List(blocks);
    }
    for (var b = 0; b < blocks; b++) {
      _rebuildBlock(data, b);
    }
    if (n >= 3) {
      _firstLo = lowOf(data[0]);
      _firstHi = highOf(data[0]);
      _midLo = lowOf(data[n >> 1]);
      _midHi = highOf(data[n >> 1]);
      _penLo = lowOf(data[n - 2]);
      _penHi = highOf(data[n - 2]);
    } else {
      _firstLo = _firstHi = _midLo = _midHi = _penLo = _penHi = double.nan;
    }
  }

  void _rebuildBlock(List<T> data, int b) {
    final from = b * _block;
    final to = from + _block < data.length ? from + _block : data.length;
    var lo = double.infinity, hi = double.negativeInfinity;
    for (var i = from; i < to; i++) {
      final l = lowOf(data[i]);
      final h = highOf(data[i]);
      if (l.isFinite && l < lo) lo = l;
      if (h.isFinite && h > hi) hi = h;
    }
    _blockLo[b] = lo;
    _blockHi[b] = hi;
  }

  /// Min low and max high over bars [start, end) of the last synced tape,
  /// or null when the range is empty or holds no finite value.
  ({double lo, double hi})? query(int start, int end) {
    final data = _src;
    if (data == null) return null;
    if (start < 0) start = 0;
    if (end > data.length) end = data.length;
    if (end <= start) return null;
    var lo = double.infinity, hi = double.negativeInfinity;
    void scan(int from, int to) {
      for (var i = from; i < to; i++) {
        final l = lowOf(data[i]);
        final h = highOf(data[i]);
        if (l.isFinite && l < lo) lo = l;
        if (h.isFinite && h > hi) hi = h;
      }
    }

    final firstFull = (start + _block - 1) ~/ _block;
    final lastFull = end ~/ _block; // exclusive
    if (firstFull >= lastFull) {
      scan(start, end);
    } else {
      scan(start, firstFull * _block);
      for (var b = firstFull; b < lastFull; b++) {
        if (_blockLo[b] < lo) lo = _blockLo[b];
        if (_blockHi[b] > hi) hi = _blockHi[b];
      }
      scan(lastFull * _block, end);
    }
    if (!lo.isFinite || !hi.isFinite) return null;
    return (lo: lo, hi: hi);
  }
}
