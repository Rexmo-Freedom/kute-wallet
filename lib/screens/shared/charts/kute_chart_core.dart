// lib/screens/shared/charts/kute_chart_core.dart
//
// The shared line/area chart engine. Extracted from the best patterns of
// the three hand-rolled charts (Polymarket market_chart, Hyperliquid
// hl_charts line mode, BtcPredictChart):
//
//   * y-domain fitting — probability semantics (market_chart's fitYDomain)
//     and price semantics (min-max with proportional pad);
//   * ONE smoothing algorithm — monotone cubic (no overshoot on step-like
//     prediction data), generalized to arbitrary x spacing;
//   * one gradient fill spec — vertical, 0.14 → 0.0 alpha, with the shader
//     cached by (w, h, color) like btc_predict_chart's _fillShaderCache;
//   * stroke 2.0 with round caps/joins, the endpoint dot spec, and the
//     expanding live-pulse ring;
//   * cheap series-equality helpers for shouldRepaint;
//   * the two-layer architecture: charts keep their data painter behind a
//     RepaintBoundary and put the per-frame live pulse in
//     [KutePulseDecorPainter], driven purely via `repaint:` so the ~60fps
//     loop re-rasters only that tiny transparent layer;
//   * morph resampling helpers for animated timeframe transitions.
//
// Painters here never read Theme/MediaQuery — all colors and flags are
// passed in by the hosting widget.

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The face of the text the charts paint themselves (scales, value tags,
/// crosshair readouts, marker counts, trade-line and signal tags, drawing
/// labels): the app's own, Inter, from the files bundled with the app
/// (pubspec `fonts:`), the same face the text around a chart is set in.
/// A painter's text has no theme to inherit from; naming no family left
/// it in the system face (San Francisco on an iPhone, Roboto on Android)
/// beside Inter everywhere else.
String? kuteChartFontFamily = 'Inter';

/// Fitted y-domain for one paint pass.
typedef KuteYDomain = ({double minY, double maxY});

/// Vertical padding fraction applied inside the drawable height so the
/// stroke never kisses the top/bottom edges.
const double kuteEdgePad = 0.04;

/// Fit a probability (0..1) y-domain to the visible data with ~15%
/// padding, clamped to [0, 1] — the Polymarket chart semantics. A 3%
/// longshot or an 88% favourite trades in a narrow band; a fixed 0..1
/// axis leaves the line hugging one edge. Data that already spans most
/// of the range keeps the full 0..1 domain so big swings stay in
/// proportion.
KuteYDomain kuteFitProbabilityDomain(double dataMin, double dataMax) {
  if (dataMax <= dataMin) {
    // Flat line: a slim band centred on the value.
    final mid = dataMin.clamp(0.0, 1.0);
    return (
      minY: (mid - 0.02).clamp(0.0, 1.0),
      maxY: (mid + 0.02).clamp(0.0, 1.0),
    );
  }
  final range = dataMax - dataMin;
  if (range > 0.6) return (minY: 0.0, maxY: 1.0);
  final pad = math.max(range * 0.15, 0.005);
  return (
    minY: (dataMin - pad).clamp(0.0, 1.0),
    maxY: (dataMax + pad).clamp(0.0, 1.0),
  );
}

/// Fit a price y-domain: min-max with a 6% pad (floored so a perfectly
/// flat series still has a non-zero span) — the Hyperliquid semantics.
KuteYDomain kuteFitPriceDomain(double dataMin, double dataMax) {
  var pad = (dataMax - dataMin) * 0.06;
  if (pad <= 0) pad = (dataMax.abs() * 0.01).clamp(1e-9, double.infinity);
  return (minY: dataMin - pad, maxY: dataMax + pad);
}

/// Map a value to a y pixel inside a drawable height [drawH] (already
/// net of any bottom margin / volume strip), honoring [kuteEdgePad].
double kuteValueToY(
  double v,
  double drawH, {
  required double minY,
  required double maxY,
  double edgePad = kuteEdgePad,
}) {
  final span = maxY - minY;
  final n = span > 0 ? ((v - minY) / span).clamp(0.0, 1.0) : 0.5;
  return drawH * (1 - edgePad) - n * drawH * (1 - 2 * edgePad);
}

/// Build a monotone-cubic (Fritsch-Carlson style tangents) path through
/// [pts]. Monotone cubic never overshoots between samples, so step-like
/// prediction/price data keeps its plateaus instead of ringing the way
/// Catmull-Rom does. Points must be in ascending-x order.
Path kuteMonotonePath(List<Offset> pts) {
  final path = Path();
  final n = pts.length;
  if (n == 0) return path;
  path.moveTo(pts[0].dx, pts[0].dy);
  if (n == 1) return path;
  if (n == 2) {
    path.lineTo(pts[1].dx, pts[1].dy);
    return path;
  }

  final dx = List.generate(n - 1, (i) => pts[i + 1].dx - pts[i].dx);
  final dy = List.generate(n - 1, (i) => pts[i + 1].dy - pts[i].dy);
  final m = List.generate(n - 1, (i) => dx[i] != 0 ? dy[i] / dx[i] : 0.0);

  final tangents = List<double>.filled(n, 0);
  tangents[0] = m[0];
  tangents[n - 1] = m[n - 2];
  for (int i = 1; i < n - 1; i++) {
    if (m[i - 1] * m[i] <= 0) {
      tangents[i] = 0;
    } else {
      tangents[i] = (m[i - 1] + m[i]) / 2;
    }
  }
  // Fritsch-Carlson's limiter: where a tangent is more than three times
  // its segment's slope, both ends of the segment are scaled back onto
  // the circle of radius 3. Without it a short steep step (a live tick a
  // second after a ten-minute history point) handed its slope to the
  // long flat segment before it, whose curve then shot far past both of
  // its points and out of the plot.
  for (int i = 0; i < n - 1; i++) {
    if (m[i] == 0) {
      tangents[i] = 0;
      tangents[i + 1] = 0;
      continue;
    }
    final a = tangents[i] / m[i];
    final b = tangents[i + 1] / m[i];
    final h = a * a + b * b;
    if (h > 9) {
      final tau = 3 / math.sqrt(h);
      tangents[i] = tau * a * m[i];
      tangents[i + 1] = tau * b * m[i];
    }
  }

  for (int i = 0; i < n - 1; i++) {
    final d = dx[i] / 3;
    path.cubicTo(
      pts[i].dx + d,
      pts[i].dy + tangents[i] * d,
      pts[i + 1].dx - d,
      pts[i + 1].dy - tangents[i + 1] * d,
      pts[i + 1].dx,
      pts[i + 1].dy,
    );
  }
  return path;
}

/// Fill gradient shaders are pure functions of (size, colour) — cached so
/// repaints don't re-allocate a LinearGradient + shader every frame
/// (btc_predict_chart's _fillShaderCache pattern). Tiny: a handful of
/// sizes per chart × a few colours; cleared defensively if it grows.
final Map<(double, double, int), Shader> _fillShaderCache = {};

/// The one gradient fill spec: vertical, [color] at 0.14 alpha fading to
/// fully transparent at the bottom of the drawable rect.
Shader kuteFillShader(double w, double h, Color color) {
  if (_fillShaderCache.length > 24) _fillShaderCache.clear();
  return _fillShaderCache.putIfAbsent(
    (w, h, color.toARGB32()),
    () => LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        color.withValues(alpha: 0.14),
        color.withValues(alpha: 0.0),
      ],
    ).createShader(Rect.fromLTWH(0, 0, w, h)),
  );
}

/// The one stroke spec: 2.0 wide (unless overridden), round caps/joins.
Paint kuteStrokePaint(Color color, {double width = 2.0}) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

/// The endpoint dot spec: a filled dot in the series colour with a small
/// theme-aware core (a hardcoded white core vanished on light themes).
void kuteDrawEndpointDot(Canvas canvas, Offset center, Color color,
    {required bool isDark, double radius = 4}) {
  canvas.drawCircle(center, radius, Paint()..color = color);
  canvas.drawCircle(center, radius / 2,
      Paint()..color = isDark ? Colors.black : Colors.white);
}

/// Expanding translucent ring behind a live endpoint dot. [t] is the
/// 0 → 1 pulse phase; the ring grows and fades as it goes.
void kuteDrawLivePulse(Canvas canvas, Offset center, Color color, double t) {
  final r = 4 + 9 * t;
  final alpha = (1 - t) * 0.4;
  if (alpha <= 0) return;
  canvas.drawCircle(center, r, Paint()..color = color.withValues(alpha: alpha));
}

/// Cheap series-equality early-out for shouldRepaint: identical list, or
/// same length with matching first/last samples (providers emit fresh list
/// instances per tick; when the visible series content hasn't changed the
/// repaint buys nothing).
bool kuteSameSeries(List<double> a, List<double> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  if (a.isEmpty) return true;
  return a.first == b.first && a.last == b.last;
}

bool kuteSameSeriesSets(List<List<double>> a, List<List<double>> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (!kuteSameSeries(a[i], b[i])) return false;
  }
  return true;
}

// ───────────────────────── morph (timeframe tween) ─────────────────────────

/// Point count both series get resampled to before a morph lerp: enough to
/// preserve shape, capped at 300 so a Max-window series doesn't drag a
/// thousand-point lerp through every animation frame.
int kuteMorphSampleCount(int aLen, int bLen) =>
    math.max(2, math.min(math.max(aLen, bLen), 300));

/// Linearly resample [src] to exactly [n] points across its index space.
List<double> kuteResampleSeries(List<double> src, int n) {
  if (src.isEmpty) return List.filled(n, 0);
  if (src.length == 1) return List.filled(n, src.first);
  if (src.length == n) return List.of(src);
  final out = List<double>.filled(n, 0);
  final scale = (src.length - 1) / (n - 1);
  for (int i = 0; i < n; i++) {
    final pos = i * scale;
    final lo = pos.floor();
    final hi = math.min(lo + 1, src.length - 1);
    final f = pos - lo;
    out[i] = src[lo] + (src[hi] - src[lo]) * f;
  }
  return out;
}

/// Point-wise lerp of two equal-length series.
List<double> kuteLerpSeries(List<double> a, List<double> b, double t) {
  assert(a.length == b.length);
  if (t <= 0) return a;
  if (t >= 1) return b;
  return List<double>.generate(
      a.length, (i) => a[i] + (b[i] - a[i]) * t,
      growable: false);
}

// ─────────────────────────── pulse decor layer ───────────────────────────

/// One live endpoint the decor layer pulses behind.
class KutePulsePoint {
  final Offset center;
  final Color color;
  const KutePulsePoint(this.center, this.color);
}

/// Decor layer: the expanding live-pulse ring behind each line's endpoint
/// dot. Kept OUT of the data painters (the BtcPredictChart two-layer
/// pattern) and driven directly by the chart's repeat controller via
/// `repaint:` — the ~60fps loop re-rasters only this tiny transparent
/// layer, never the line canvas. [resolve] maps the canvas size to the
/// endpoint positions using the same geometry as the data painter, so
/// the rings land exactly on the dots.
class KutePulseDecorPainter extends CustomPainter {
  final Animation<double> pulse;
  final List<KutePulsePoint> Function(Size size) resolve;

  /// Change-detection inputs for shouldRepaint (per-frame motion arrives
  /// via `repaint:`, so these only catch actual data/palette changes).
  final List<List<double>> dataSets;
  final List<Color> colors;

  /// Scrubbing swaps the endpoint affordance for the crosshair, so the
  /// hosting chart passes false while a scrub is active.
  final bool visible;

  KutePulseDecorPainter({
    required this.pulse,
    required this.resolve,
    required this.dataSets,
    required this.colors,
    this.visible = true,
  }) : super(repaint: pulse);

  @override
  void paint(Canvas canvas, Size size) {
    if (!visible) return;
    final t = pulse.value;
    for (final p in resolve(size)) {
      kuteDrawLivePulse(canvas, p.center, p.color, t);
    }
  }

  @override
  bool shouldRepaint(covariant KutePulseDecorPainter old) =>
      !kuteSameSeriesSets(old.dataSets, dataSets) ||
      old.colors != colors ||
      old.visible != visible;
}
