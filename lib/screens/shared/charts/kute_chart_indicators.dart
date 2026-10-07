// lib/screens/shared/charts/kute_chart_indicators.dart
//
// Pure-Dart indicator computations for the native chart stack — the
// replacement for the (deleted) TradingView WebView chart's in-page
// maths. Everything is computed from the candle CLOSES the chart
// already holds, so indicators work on every market, thin HIP-3 tapes
// included, with no JS bridge.
//
//   * SMA 20 / SMA 50, EMA 9 / EMA 21, Bollinger Bands (20, 2) — via
//     [KuteIndicatorEngine], which memoizes per (series content,
//     indicator) and patches ONLY the tail on a leading-bar live tick
//     (the common WS case). A reseed/backfill falls back to a full
//     recompute, bounded in practice by the ~150–400 bar tapes the HL
//     candle provider emits (full recompute stays trivial to ~2000).
//   * Log-scale price mapping — [KuteLogDrawingGeometry] extends the
//     shared drawings geometry so user drawings keep landing exactly on
//     the data when the host maps prices through ln().
//
// Series are ALIGNED to candle indices: index i of every returned list
// is indicator-at-bar-i, with double.nan during the warm-up window so
// painters can gap instead of drawing a bogus ramp.
//
// PALETTE (muted, works on both themes — documented here as the single
// source of truth):
//   SMA 20  amber   0xFFF59E0B      SMA 50  orange  0xFFEA580C
//   EMA 9   blue    0xFF3B82F6      EMA 21  purple  0xFFA855F7
//   BB      grey    0xFF94A3B8 (band fill at 0.06 alpha)
// All overlay polylines stroke at 1.5.
//
// Painters/engine here never read Theme — hosts pass what they need.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:kute/screens/shared/charts/kute_chart_drawings.dart';

// ───────────────────────────── palette ─────────────────────────────

const Color kuteIndSma20Color = Color(0xFFF59E0B); // amber
const Color kuteIndSma50Color = Color(0xFFEA580C); // orange
const Color kuteIndEma9Color = Color(0xFF3B82F6); // blue
const Color kuteIndEma21Color = Color(0xFFA855F7); // purple
const Color kuteIndBbColor = Color(0xFF94A3B8); // slate grey

/// Overlay polylines are deliberately thinner than the 2.0 data stroke.
const double kuteIndStrokeWidth = 1.5;

/// Soft Bollinger band fill alpha.
const double kuteIndBandFillAlpha = 0.06;

// ───────────────────────────── overlays ─────────────────────────────

/// One indicator polyline, aligned to candle indices (nan = warm-up gap).
class KuteIndicatorOverlay {
  final List<double> values;
  final Color color;
  final double strokeWidth;

  const KuteIndicatorOverlay({
    required this.values,
    required this.color,
    this.strokeWidth = kuteIndStrokeWidth,
  });
}

/// A band (Bollinger): upper + lower envelopes get a soft shared fill.
class KuteIndicatorBand {
  final List<double> upper;
  final List<double> lower;
  final Color color;

  const KuteIndicatorBand({
    required this.upper,
    required this.lower,
    required this.color,
  });
}

// ───────────────────────────── engine ─────────────────────────────

/// Lazily computed, memoized indicator series over one close series.
///
/// Call [sync] with the current closes each build; then ask for the
/// series you need ([sma], [ema], [bollinger]). Results are cached per
/// indicator and only recomputed when the closes actually changed —
/// and a leading-bar-only tick (same length, only the last close moved)
/// or a single append patches just the tail instead of recomputing the
/// whole series. [revision] bumps on every content change so hosts can
/// memoize whatever they derive from the series (e.g. overlay lists).
class KuteIndicatorEngine {
  List<double> _closes = const [];

  /// Bumped whenever [sync] sees changed content. Starts at 0.
  int _revision = 0;
  int get revision => _revision;

  /// key → aligned values. Keys: 'sma:P', 'ema:P', 'bb:P:M:u|m|l'.
  final Map<String, List<double>> _cache = {};

  static bool _prefixEqual(List<double> a, List<double> b, int upTo) {
    for (var i = 0; i < upTo; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Adopt [closes] as the current series. Cheap no-op when unchanged.
  void sync(List<double> closes) {
    final old = _closes;
    final n = closes.length;
    if (n == old.length) {
      if (n == 0 || (closes[n - 1] == old[n - 1] &&
          _prefixEqual(closes, old, n - 1))) {
        return; // identical content
      }
      final tailOnly = _prefixEqual(closes, old, n - 1);
      _closes = closes;
      if (tailOnly) {
        _patchIndex(n - 1);
      } else {
        _cache.clear();
      }
    } else if (n == old.length + 1 &&
        old.isNotEmpty &&
        _prefixEqual(closes, old, old.length)) {
      // One appended bar: extend every cached series by its new point.
      _closes = closes;
      for (final entry in _cache.entries) {
        entry.value.add(_valueAt(entry.key, n - 1));
      }
    } else {
      _closes = closes;
      _cache.clear();
    }
    _revision++;
  }

  /// Simple moving average over [period] closes.
  List<double> sma(int period) => _series('sma:$period');

  /// Exponential moving average (k = 2 / (period + 1)), seeded on the
  /// first close, shown from index period-1 (nan before) — matching the
  /// convention the old WebView chart used.
  List<double> ema(int period) => _series('ema:$period');

  /// Bollinger Bands: SMA(period) middle ± [mult] population std-devs.
  ({List<double> upper, List<double> middle, List<double> lower}) bollinger(
      int period, double mult) {
    return (
      upper: _series('bb:$period:$mult:u'),
      middle: _series('bb:$period:$mult:m'),
      lower: _series('bb:$period:$mult:l'),
    );
  }

  List<double> _series(String key) =>
      _cache.putIfAbsent(key, () => _computeFull(key));

  List<double> _computeFull(String key) {
    final n = _closes.length;
    final out = List<double>.filled(n, double.nan, growable: true);
    for (var i = 0; i < n; i++) {
      out[i] = _valueAt(key, i);
    }
    return out;
  }

  /// Recompute index [i] of every cached series in place (tail patch).
  void _patchIndex(int i) {
    for (final entry in _cache.entries) {
      entry.value[i] = _valueAt(entry.key, i);
    }
  }

  /// Indicator value at index [i] for [key], using cached neighbours
  /// where the recurrence allows (EMA reads its own i-1 from the cache).
  double _valueAt(String key, int i) {
    final parts = key.split(':');
    final period = int.parse(parts[1]);
    switch (parts[0]) {
      case 'sma':
        return _smaAt(i, period);
      case 'ema':
        return _emaAt(key, i, period);
      case 'bb':
        final mult = double.parse(parts[2]);
        final m = _smaAt(i, period);
        if (m.isNaN) return double.nan;
        var v = 0.0;
        for (var j = i - period + 1; j <= i; j++) {
          final d = _closes[j] - m;
          v += d * d;
        }
        final sd = math.sqrt(v / period);
        switch (parts[3]) {
          case 'u':
            return m + mult * sd;
          case 'l':
            return m - mult * sd;
          default:
            return m;
        }
    }
    return double.nan;
  }

  double _smaAt(int i, int period) {
    if (i < period - 1) return double.nan;
    var sum = 0.0;
    for (var j = i - period + 1; j <= i; j++) {
      sum += _closes[j];
    }
    return sum / period;
  }

  double _emaAt(String key, int i, int period) {
    // O(1) recurrence off the cached i-1 value when it's usable; the
    // warm-up window (where the aligned list holds nan) recomputes the
    // seed chain from index 0 — bounded by the period.
    final k = 2 / (period + 1);
    final cached = _cache[key];
    if (i >= period && cached != null && cached.length > i - 1) {
      final prev = cached[i - 1];
      if (prev.isFinite) return _closes[i] * k + prev * (1 - k);
    }
    var e = _closes[0];
    for (var j = 1; j <= i; j++) {
      e = _closes[j] * k + e * (1 - k);
    }
    return i >= period - 1 ? e : double.nan;
  }
}

// ───────────────────────── log-scale geometry ─────────────────────────

/// Map a price for a log-scale y axis. Guards non-positive input so a
/// zero/negative tick can never produce -inf.
double kuteLogPrice(double v) => math.log(v > 0 ? v : 1e-12);

/// Drawings geometry variant for a LOG price axis: the host stores loP /
/// rangeP in ln space and this maps price ⇄ y through ln/exp, so saved
/// drawings (stored in real prices) land exactly on the log-mapped data.
class KuteLogDrawingGeometry extends KuteDrawingGeometry {
  const KuteLogDrawingGeometry({
    required super.timesMs,
    required super.width,
    required super.priceH,
    required super.loP,
    required super.rangeP,
    required super.bucketMs,
  });

  @override
  double yForPrice(double price) =>
      priceH * (1 - (kuteLogPrice(price) - loP) / rangeP);

  @override
  double priceForY(double y) =>
      math.exp(loP + (1 - y / priceH) * rangeP);
}

// ───────────────────────── overlay painting ─────────────────────────

/// Paint one aligned indicator polyline: x follows the host's bar layout
/// (bar i center at (i + 0.5) × slot), nan values gap the line. [toY]
/// is the host's price→pixel mapper (log-aware when the host is).
void kutePaintIndicatorLine(
  Canvas canvas,
  KuteIndicatorOverlay overlay,
  double slot,
  double Function(double v) toY,
) {
  final values = overlay.values;
  final paint = Paint()
    ..color = overlay.color
    ..style = PaintingStyle.stroke
    ..strokeWidth = overlay.strokeWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  Path? path;
  for (var i = 0; i < values.length; i++) {
    final v = values[i];
    if (!v.isFinite) {
      if (path != null) canvas.drawPath(path, paint);
      path = null;
      continue;
    }
    final x = (i + 0.5) * slot;
    final y = toY(v);
    if (path == null) {
      path = Path()..moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
  }
  if (path != null) canvas.drawPath(path, paint);
}

/// Paint the soft fill between a band's upper and lower envelopes (the
/// envelopes themselves are drawn as normal overlay lines by the host).
void kutePaintIndicatorBandFill(
  Canvas canvas,
  KuteIndicatorBand band,
  double slot,
  double Function(double v) toY,
) {
  final n = math.min(band.upper.length, band.lower.length);
  Path? path;
  var runStart = -1;
  void closeRun(int end) {
    if (path == null) return;
    for (var i = end - 1; i >= runStart; i--) {
      path!.lineTo((i + 0.5) * slot, toY(band.lower[i]));
    }
    path!.close();
    canvas.drawPath(
      path!,
      Paint()..color = band.color.withValues(alpha: kuteIndBandFillAlpha),
    );
    path = null;
  }

  for (var i = 0; i < n; i++) {
    final u = band.upper[i];
    final l = band.lower[i];
    if (!u.isFinite || !l.isFinite) {
      closeRun(i);
      continue;
    }
    final x = (i + 0.5) * slot;
    if (path == null) {
      runStart = i;
      path = Path()..moveTo(x, toY(u));
    } else {
      path!.lineTo(x, toY(u));
    }
  }
  closeRun(n);
}
