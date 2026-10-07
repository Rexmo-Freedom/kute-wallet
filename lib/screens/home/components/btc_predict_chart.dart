import 'dart:math' as math;

import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/polymarket_provider.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:kute/screens/shared/kute_skeleton.dart';

class BtcPredictChart extends ConsumerStatefulWidget {
  final double height;

  /// The series to draw, from the card's [CryptoPredictState]
  /// (Polymarket's Chainlink TWAP, or the whole fallback series while
  /// that is silent). Null draws the skeleton.
  final List<BtcPriceSnapshot>? externalHistory;
  final double? externalPriceToBeat;

  /// Start of the live 5-minute round (the event's windowStartTime).
  /// When set, the plotted time window is clipped to the round: left
  /// edge = round start, right edge = latest tick, so the curve fills
  /// the full card width from the first seconds of a round instead of
  /// bunching into the tail of a fixed 5-minute span. Null falls back
  /// to the trailing data span (capped at 5 minutes).
  final DateTime? roundStart;

  /// When true, renders the pulsing "● Live" pill above the chart.
  /// Default off — only the Instant tab callsite opts in. Other surfaces
  /// (Crypto tab banners, market-detail sheet) keep the cleaner look
  /// without the redundant Live indicator.
  final bool showLiveIndicator;

  /// The chart's own compact "Price to beat" row. The Predictions hero
  /// renders the target itself, so it passes false to avoid the
  /// double-printed price the old banner shipped with.
  final bool showHeader;

  const BtcPredictChart({
    super.key,
    this.height = 140,
    this.externalHistory,
    this.externalPriceToBeat,
    this.roundStart,
    this.showLiveIndicator = false,
    this.showHeader = true,
  });

  @override
  ConsumerState<BtcPredictChart> createState() => _BtcPredictChartState();
}

class _BtcPredictChartState extends ConsumerState<BtcPredictChart>
    with SingleTickerProviderStateMixin {
  late AnimationController _tickCtrl;

  @override
  void initState() {
    super.initState();
    // 3-second decorative loop — phase source for the decor paint
    // layer (dot pulse, ambient jitter, dashed-line breathing) and the
    // "Live" pill. It never rebuilds the chart itself: the decorative
    // painter subscribes via `repaint:` and rasters in its own tiny
    // layer.
    // The .repeat() is deferred to build() so we can honour
    // reduce-motion (MediaQuery isn't available here): the loop is
    // purely decorative — gating it removes no data.
    _tickCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
  }

  @override
  void dispose() {
    _tickCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    // Decorative looping motion (pulsing dot, ambient dot jitter,
    // dashed-target breathing) only — gate it on
    // reduce-motion. The live chart still updates on every provider
    // tick, so no data is lost; we just stop the per-frame animation.
    if (reduceMotion) {
      if (_tickCtrl.isAnimating) _tickCtrl.stop();
    } else {
      if (!_tickCtrl.isAnimating) _tickCtrl.repeat();
    }

    final history = widget.externalHistory ?? const <BtcPriceSnapshot>[];
    final priceToBeat = widget.externalPriceToBeat;

    final isAbove = priceToBeat != null &&
        history.isNotEmpty &&
        history.last.price >= priceToBeat;
    final accentColor = isAbove ? AppColors.marketUp : AppColors.marketDown;

    // Pulse value from the looping controller (0→1→0→1…)
    // Map the linear 0→1 to a triangle wave for smooth pulsing
    double pulseValue() {
      final v = _tickCtrl.value;
      return v < 0.5 ? v * 2 : 2 - v * 2;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Price to beat label
        if (widget.showHeader && priceToBeat != null)
          Padding(
            padding: EdgeInsets.only(bottom: 6.h),
            child: Row(
              children: [
                Text(
                  context.l10n.btcPredictPriceToBeat,
                  style: TextStyle(
                    color: c.textTertiary,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(width: 6.w),
                Text(
                  '\$${NumberFormat('#,##0.00', 'en_US').format(priceToBeat)}',
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),

        // Live indicator. The pulsing "● Live" pill only renders when
        // [showLiveIndicator] is set (Instant tab only). The chart is
        // view-only: no scrub readout (user decision, September 2026).
        if (widget.showLiveIndicator)
          SizedBox(
            height: 18.h,
            // RepaintBoundary so the per-frame dot pulse re-rasters
            // only this tiny pill, never the surrounding screen layer.
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _tickCtrl,
                builder: (_, __) => Row(
                  children: [
                    Container(
                      width: 6.sp,
                      height: 6.sp,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(
                            alpha: 0.5 + pulseValue() * 0.5),
                        shape: BoxShape.circle,
                      ),
                    ),
                    SizedBox(width: 4.w),
                    Text(
                      context.l10n.liveBadge,
                      style: TextStyle(
                        // accent-contrast: the green/red brand accent on the
                        // chart background fails ~4.5:1 for this small status
                        // word. The pulsing dot beside it keeps the semantic
                        // up/down colour, so the label itself can read clearly.
                        color: c.textSecondary,
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Chart area — the data layer with the decorative live dot /
        // target-line layer stacked above it.
        if (history.length >= 2)
          LayoutBuilder(builder: (context, constraints) {
            // Latest "target" price the leading edge should draw toward.
            // TweenAnimationBuilder is keyed on this — whenever it
            // changes, the tween restarts from its current value and
            // smoothly interpolates over `_priceTweenDuration` so the
            // line "draws" toward the new price instead of snapping.
            final targetPrice = history.last.price;
            // Glide over the gap between the last two points: about a
            // second on Polymarket's Chainlink feed, a quarter second on
            // the Binance fallback. Clamped so a long gap never drags.
            final gapMs = history.last.timestamp
                .difference(history[history.length - 2].timestamp)
                .inMilliseconds
                .clamp(260, 900);
            // View-only (user decision, September 2026): the live crypto
            // chart takes no touches, so no scrub, crosshair or haptics,
            // and a drag over it scrolls the page instead.
            return IgnorePointer(
              child: TweenAnimationBuilder<double>(
                // Use the actual price as the tween "key" — Flutter's
                // TweenAnimationBuilder restarts whenever `tween.end`
                // changes, animating from the previous painted value.
                tween: Tween<double>(begin: targetPrice, end: targetPrice),
                // Decorative "draw toward the new price" smoothing —
                // the leading edge still lands on the live price either
                // way, so snap it under reduce-motion.
                // The tween lasts about one tick gap and eases only
                // gently, so the line is always moving toward the next
                // point rather than restarting a long ease on every tick.
                duration: reduceMotion
                    ? Duration.zero
                    : Duration(milliseconds: gapMs),
                curve: Curves.easeOut,
                builder: (context, tweenedPrice, _) {
                  return SizedBox(
                    width: double.infinity,
                    height: widget.height,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Data layer: curve, fill, target-split colouring
                        // and crosshair. Repaints only when the data (or
                        // scrub position) actually changes — see the
                        // painter's shouldRepaint. The RepaintBoundary
                        // keeps sibling per-frame layers from dragging
                        // this canvas into their rasters.
                        RepaintBoundary(
                          child: CustomPaint(
                            size: Size.infinite,
                            painter: _BtcLiveChartPainter(
                              snapshots: history,
                              priceToBeat: priceToBeat,
                              labelColor: c.textTertiary,
                              isDark: context.isDark,
                              tweenedLeadingPrice: tweenedPrice,
                              roundStart: widget.roundStart,
                            ),
                          ),
                        ),
                        // Decorative layer: pulsing live dot (+ ambient
                        // jitter) and the breathing dashed target line.
                        // Driven straight by the repeat controller via
                        // the painter's `repaint:` hook — the per-frame
                        // work is confined to this tiny raster layer,
                        // with zero widget rebuilds.
                        RepaintBoundary(
                          child: CustomPaint(
                            size: Size.infinite,
                            willChange: true,
                            painter: _BtcChartDecorPainter(
                              targetLabel: context.l10n.target,
                              snapshots: history,
                              priceToBeat: priceToBeat,
                              labelColor: c.textTertiary,
                              isDark: context.isDark,
                              tweenedLeadingPrice: tweenedPrice,
                              tick: _tickCtrl,
                              roundStart: widget.roundStart,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          })
        else
          SizedBox(
            height: widget.height,
            child: SkeletonLineChart(padding: EdgeInsets.zero),
          ),
      ],
    );
  }
}

/// Shared time-window + y-scale math for the chart's two paint
/// layers. The data painter (curve, fill, crosshair) and the
/// decorative painter (live dot, target line) raster separately,
/// but the dot/target must land exactly on the curve — so both
/// derive their coordinates from this single computation.
///
/// The window is anchored to the LATEST SNAPSHOT's timestamp, not
/// wall-clock now: identical data therefore produces identical
/// geometry (and an identical frame), which is what lets the data
/// layer skip repaints entirely between provider ticks.
class _ChartGeometry {
  final List<BtcPriceSnapshot> visible;
  final DateTime windowStart;
  final double windowMs;
  final double minVal;
  final double range;
  final double chartW;
  final double chartH;

  static const double rightMargin = 65;
  static const double bottomMargin = 18;

  // Cap on the plotted span, not a fixed width: the window covers the
  // round's elapsed time so far, capped to a SLIDING recent window.
  // 60s (not the full 5-minute round): with the whole round on screen
  // the late-round tape crawled and dense live ticks still bunched at
  // the right edge (user report, twice) — a one-minute window keeps
  // the sweep visibly moving all round long.
  static const _maxWindow = Duration(seconds: 60);

  const _ChartGeometry._({
    required this.visible,
    required this.windowStart,
    required this.windowMs,
    required this.minVal,
    required this.range,
    required this.chartW,
    required this.chartH,
  });

  /// Returns null when there isn't enough data (or canvas) to draw.
  static _ChartGeometry? compute({
    required List<BtcPriceSnapshot> snapshots,
    required double tweenedLeadingPrice,
    required double? priceToBeat,
    required Size size,
    DateTime? roundStart,
  }) {
    if (snapshots.length < 2) return null;

    final chartW = size.width - rightMargin;
    final chartH = size.height - bottomMargin;
    if (chartW <= 0 || chartH <= 0) return null;

    // Time window: right edge = latest snapshot, left edge = the round
    // start (or the earliest snapshot), capped at [_maxWindow] back —
    // a sliding recent window once the round is older than that. The
    // window spans only ELAPSED time, so the curve always fills the
    // full drawn width — a fixed full-round width bunched dense live
    // ticks into a sliver at the right edge. Still anchored to data
    // rather than DateTime.now() so a quiet stretch costs zero
    // repaints; the trade-off is that the curve scrolls per provider
    // tick instead of per frame.
    final windowStart = effectiveWindowStart(snapshots, roundStart);
    // Floor at 1s: sub-second spans (first ticks after a rollover
    // wipe) would otherwise thrash points across the full width.
    final windowMs = math.max(
      snapshots.last.timestamp
          .difference(windowStart)
          .inMilliseconds
          .toDouble(),
      1000.0,
    );

    // Filter to visible snapshots (within the time window)
    final visible =
        snapshots.where((s) => !s.timestamp.isBefore(windowStart)).toList();
    if (visible.isEmpty) return null;

    // --- Y-axis scale ---
    // Polymarket-web style: fit the y-range TIGHTLY to the visible
    // price movement so a $20 wiggle on $77k BTC reads as a dramatic
    // curve, not a flat line drowned in whitespace. We deliberately
    // do NOT extend the range to include `priceToBeat` — when the
    // dashed reference line falls outside, the painter clamps it
    // to the chart edge so it's still visible without compressing
    // the curve.
    final prices = visible.map((s) => s.price).toList();
    if (priceToBeat != null) prices.add(tweenedLeadingPrice);
    var minVal = prices.reduce(math.min);
    var maxVal = prices.reduce(math.max);
    final naturalRange = maxVal - minVal;

    // Floor the visible range so a perfectly flat sub-second window
    // doesn't divide-by-zero. $2 floor at any price, scaling up
    // slightly with price to keep proportional feel on tiny coins
    // (~0.005% of price). For BTC at $77k → ~$3.85 floor.
    final midPrice = (minVal + maxVal) / 2;
    final minRange = math.max(2.0, midPrice * 0.00005);
    if (naturalRange < minRange) {
      minVal = midPrice - minRange / 2;
      maxVal = midPrice + minRange / 2;
    }

    // Tight 8% padding (4% top, 4% bottom) — just enough headroom
    // so the curve doesn't kiss the edges, no more.
    final rangePad = (maxVal - minVal) * 0.08;
    minVal -= rangePad;
    maxVal += rangePad;
    final range = maxVal - minVal;
    if (range == 0) return null;

    return _ChartGeometry._(
      visible: visible,
      windowStart: windowStart,
      windowMs: windowMs,
      minVal: minVal,
      range: range,
      chartW: chartW,
      chartH: chartH,
    );
  }

  /// Left edge of the plotted time window: the round start when it is
  /// known and already holds at least two ticks, otherwise the
  /// earliest snapshot — never more than [_maxWindow] before the
  /// latest tick. Right after a rollover (or for a pre-staged future
  /// round) the round itself has fewer than two ticks, so fall back
  /// to the trailing data span rather than paint a blank plot.
  /// Requires `snapshots.length >= 2`.
  static DateTime effectiveWindowStart(
      List<BtcPriceSnapshot> snapshots, DateTime? roundStart) {
    final cap = snapshots.last.timestamp.subtract(_maxWindow);
    var start = snapshots.first.timestamp;
    if (start.isBefore(cap)) start = cap;
    if (roundStart != null && roundStart.isAfter(start)) {
      final penultimate = snapshots[snapshots.length - 2].timestamp;
      if (!roundStart.isAfter(penultimate)) start = roundStart;
    }
    return start;
  }

  /// time → X position
  double timeToX(DateTime t) {
    final ms = t.difference(windowStart).inMilliseconds.toDouble();
    return (ms / windowMs) * chartW;
  }

  /// price → Y position
  double priceToY(double price) {
    return chartH - ((price - minVal) / range) * chartH;
  }
}

/// Data layer: price curve, gradient fill, green/red target split
/// and the touch crosshair. Deliberately contains NO per-frame
/// decoration — that lives in [_BtcChartDecorPainter] — so this
/// (comparatively expensive) canvas only repaints when the data,
/// tween or scrub position actually changes.
class _BtcLiveChartPainter extends CustomPainter {
  final List<BtcPriceSnapshot> snapshots;
  final double? priceToBeat;
  final Color labelColor;
  final bool isDark;
  final DateTime? roundStart;

  /// Smoothly-tweened price the leading edge is currently drawing
  /// toward — interpolates from the previous price to the latest
  /// `snapshots.last.price` over ~500ms via TweenAnimationBuilder.
  /// Used to render the right-edge line + dot Y position so price
  /// jumps "draw" rather than snap.
  final double tweenedLeadingPrice;

  static const Color _green = AppColors.marketUp;
  static const Color _red = AppColors.marketDown;

  /// Fill gradient shaders are pure functions of (size, colour) —
  /// cached so repaints don't re-allocate a LinearGradient + shader
  /// every time. Tiny: two colours × the handful of sizes the chart
  /// is ever laid out at; cleared defensively if it somehow grows.
  static final Map<(double, double, Color), Shader> _fillShaderCache = {};

  _BtcLiveChartPainter({
    required this.snapshots,
    this.priceToBeat,
    required this.labelColor,
    required this.isDark,
    required this.tweenedLeadingPrice,
    this.roundStart,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final geom = _ChartGeometry.compute(
      snapshots: snapshots,
      tweenedLeadingPrice: tweenedLeadingPrice,
      priceToBeat: priceToBeat,
      size: size,
      roundStart: roundStart,
    );
    if (geom == null) return;
    final chartW = geom.chartW;
    final chartH = geom.chartH;
    final visible = geom.visible;

    // Unified chart language: no Y-axis grid/labels — just the
    // curve, the target reference line, and the live dot. The
    // detail header above carries the live price; touching the
    // chart still shows a crosshair tooltip.

    // --- Build points from time-based positions ---
    // The newest snapshot sits exactly at the right edge (the window
    // is anchored to it) and its vertex is drawn at the tweened
    // leading price below, so skip it here — keeping both would
    // paint a vertical seam at the edge while the tween is mid-way.
    final points = <Offset>[];
    final historical =
        visible.length > 1 ? visible.sublist(0, visible.length - 1) : visible;
    for (final snap in historical) {
      final x = geom.timeToX(snap.timestamp).clamp(0.0, chartW);
      final y = geom.priceToY(snap.price);
      points.add(Offset(x, y));
    }

    // Extend the line to the right edge at the tweened "leading" price.
    // The tween smoothly interpolates from the previous price toward
    // the latest snapshot's price, so the line visibly *draws* into
    // each new tick instead of snapping.
    final rightEdgeY = geom.priceToY(tweenedLeadingPrice);
    points.add(Offset(chartW, rightEdgeY));

    // --- Build the line path: midpoint quadratic smoothing, so sparse
    // histories (CoinGecko-seeded non-BTC assets) render as one smooth
    // curve instead of the angular segments-and-cliff look. ---
    final path = Path()..moveTo(points[0].dx, points[0].dy);
    if (points.length == 2) {
      path.lineTo(points[1].dx, points[1].dy);
    } else {
      for (int i = 1; i < points.length - 1; i++) {
        final mid = Offset(
          (points[i].dx + points[i + 1].dx) / 2,
          (points[i].dy + points[i + 1].dy) / 2,
        );
        path.quadraticBezierTo(points[i].dx, points[i].dy, mid.dx, mid.dy);
      }
      path.lineTo(points.last.dx, points.last.dy);
    }

    // --- Fill path (under the line) ---
    final fillPath = Path.from(path)
      ..lineTo(chartW, chartH)
      ..lineTo(points.first.dx, chartH)
      ..close();

    // --- Draw with green/red split at target ---
    if (priceToBeat != null) {
      final targetY = geom.priceToY(priceToBeat!).clamp(0.0, chartH);
      final isWholeAbove = geom.priceToY(priceToBeat!) >= chartH;
      final isWholeBelow = geom.priceToY(priceToBeat!) <= 0;

      if (isWholeAbove) {
        _drawFill(canvas, fillPath, chartW, chartH, _green);
        _drawStroke(canvas, path, _green);
      } else if (isWholeBelow) {
        _drawFill(canvas, fillPath, chartW, chartH, _red);
        _drawStroke(canvas, path, _red);
      } else {
        canvas.save();
        canvas.clipRect(Rect.fromLTRB(0, 0, chartW, targetY));
        _drawFill(canvas, fillPath, chartW, chartH, _green);
        _drawStroke(canvas, path, _green);
        canvas.restore();

        canvas.save();
        canvas.clipRect(Rect.fromLTRB(
            0, targetY, chartW, chartH + _ChartGeometry.bottomMargin));
        _drawFill(canvas, fillPath, chartW, chartH, _red);
        _drawStroke(canvas, path, _red);
        canvas.restore();
      }
    } else {
      _drawFill(canvas, fillPath, chartW, chartH, _green);
      _drawStroke(canvas, path, _green);
    }

    // Dashed target reference line + pulsing live dot are painted
    // by _BtcChartDecorPainter in the per-frame layer above.

    // Time labels suppressed for the unified clean style — the
    // window length is implicit in the surrounding UI.
  }

  void _drawStroke(Canvas canvas, Path path, Color color) {
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _drawFill(
      Canvas canvas, Path fillPath, double w, double h, Color color) {
    if (_fillShaderCache.length > 16) _fillShaderCache.clear();
    final shader = _fillShaderCache.putIfAbsent(
      (w, h, color),
      () => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.15),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
    canvas.drawPath(fillPath, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant _BtcLiveChartPainter old) {
    // The provider always emits a fresh List on new data (and the
    // geometry is derived purely from it), so identity comparison
    // is a correct — and cheap — change check.
    return old.snapshots != snapshots ||
        old.tweenedLeadingPrice != tweenedLeadingPrice ||
        old.priceToBeat != priceToBeat ||
        old.labelColor != labelColor ||
        old.isDark != isDark ||
        old.roundStart != roundStart;
  }
}

/// Decorative per-frame layer: the pulsing live dot (+ ambient
/// jitter) and the breathing dashed "Target" line. Split out of
/// [_BtcLiveChartPainter] and driven directly by the chart's repeat
/// controller via `super(repaint:)`, so the ~60fps loop only
/// re-rasters this tiny transparent layer — no widget rebuilds and
/// no full-chart repaints.
class _BtcChartDecorPainter extends CustomPainter {
  final List<BtcPriceSnapshot> snapshots;
  final double? priceToBeat;
  final Color labelColor;
  final bool isDark;
  final DateTime? roundStart;

  /// Same tweened leading price the data painter draws toward, so
  /// the dot rides the exact same right-edge vertex as the curve.
  final double tweenedLeadingPrice;

  /// The chart's looping 3-second controller. Read inside [paint]
  /// for the pulse/jitter phase; also the `repaint:` listenable
  /// that schedules the per-frame repaints (idle when stopped
  /// under reduce-motion).
  final Animation<double> tick;

  static const Color _green = AppColors.marketUp;
  static const Color _red = AppColors.marketDown;

  // Geometry depends only on the canvas size for a given painter
  // instance (all data fields are final) — cache it so the
  // per-frame repaints don't redo the window/scale scan.
  _ChartGeometry? _geom;
  Size? _geomSize;

  // 'Target' badge label: laid out once per colour, not per frame.
  static TextPainter? _targetTp;
  static Color? _targetTpColor;
  static String? _targetTpText;

  /// The badge word, in the app language.
  final String targetLabel;

  _BtcChartDecorPainter({
    required this.targetLabel,
    required this.snapshots,
    required this.priceToBeat,
    required this.labelColor,
    required this.isDark,
    required this.tweenedLeadingPrice,
    required this.tick,
    this.roundStart,
  }) : super(repaint: tick);

  @override
  void paint(Canvas canvas, Size size) {
    if (_geom == null || _geomSize != size) {
      _geomSize = size;
      _geom = _ChartGeometry.compute(
        snapshots: snapshots,
        tweenedLeadingPrice: tweenedLeadingPrice,
        priceToBeat: priceToBeat,
        size: size,
        roundStart: roundStart,
      );
    }
    final geom = _geom;
    if (geom == null) return;
    final chartW = geom.chartW;
    final chartH = geom.chartH;

    // Pulse value from the looping controller (0→1→0→1…) — the
    // same triangle-wave mapping the widget uses for the Live pill.
    final v = tick.value;
    final pulse = v < 0.5 ? v * 2 : 2 - v * 2;

    // --- Dashed target reference line ---
    // When priceToBeat falls outside the (tightly-fitted) y-range
    // we clamp the dashed line to the chart edge instead of
    // expanding the range. The badge stays visible so the user
    // always sees the reference, even when the curve is far
    // above/below it.
    if (priceToBeat != null) {
      final refY = geom.priceToY(priceToBeat!).clamp(0.0, chartH);
      // Opacity breathes between ~0.4 and ~0.7 — subtle motion that
      // signals "live" without strobing.
      _drawTargetLine(canvas, chartW, refY, 0.4 + pulse * 0.3);
    }

    // --- Live dot at right edge (animated pulse + ambient jitter) ---
    // Ambient ±0.5px jitter — applied ONLY to the leading dot, never to
    // the historical line. Keeps the front of the chart feeling alive
    // during quiet stretches.
    final dotJitterY = math.sin(v * 2 * math.pi) * 0.5;
    final rightEdgeY = geom.priceToY(tweenedLeadingPrice);
    final livePt = Offset(chartW, rightEdgeY + dotJitterY);
    final isAbove = priceToBeat != null && tweenedLeadingPrice >= priceToBeat!;
    final dotColor = priceToBeat != null ? (isAbove ? _green : _red) : _green;

    // Pulsing glow
    canvas.drawCircle(
      livePt,
      4 + pulse * 3,
      Paint()..color = dotColor.withValues(alpha: 0.15 + pulse * 0.1),
    );
    canvas.drawCircle(livePt, 3, Paint()..color = dotColor);
    // Theme-aware core.
    canvas.drawCircle(
        livePt, 1.5, Paint()..color = isDark ? Colors.black : Colors.white);
  }

  void _drawTargetLine(
      Canvas canvas, double chartW, double refY, double opacity) {
    final dashColor = labelColor.withValues(alpha: opacity.clamp(0.0, 1.0));
    final dashPaint = Paint()
      ..color = dashColor
      ..strokeWidth = 1.0;

    for (double x = 0; x < chartW; x += 8) {
      canvas.drawLine(
        Offset(x, refY),
        Offset(math.min(x + 4, chartW), refY),
        dashPaint,
      );
    }

    // "Target" badge
    final badgePaint = Paint()..color = labelColor.withValues(alpha: 0.1);
    final badgeRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(chartW + 4, refY - 9, 56, 18),
      const Radius.circular(4),
    );
    canvas.drawRRect(badgeRect, badgePaint);

    if (_targetTp == null ||
        _targetTpColor != labelColor ||
        _targetTpText != targetLabel) {
      _targetTpText = targetLabel;
      _targetTpColor = labelColor;
      _targetTp = TextPainter(
        text: TextSpan(
          text: targetLabel,
          style: TextStyle(
            color: labelColor.withValues(alpha: 0.7),
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    }
    final tp = _targetTp!;
    tp.paint(canvas, Offset(chartW + 4 + (56 - tp.width) / 2, refY - 7));
  }

  @override
  bool shouldRepaint(covariant _BtcChartDecorPainter old) {
    // Per-frame motion arrives via the `repaint:` listenable, so
    // this only needs to catch actual data / theme / scrub changes.
    return old.snapshots != snapshots ||
        old.priceToBeat != priceToBeat ||
        old.labelColor != labelColor ||
        old.isDark != isDark ||
        old.tweenedLeadingPrice != tweenedLeadingPrice ||
        old.roundStart != roundStart;
  }
}
