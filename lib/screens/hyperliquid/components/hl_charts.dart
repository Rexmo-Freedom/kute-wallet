// lib/screens/hyperliquid/components/hl_charts.dart
//
// Reusable, self-contained chart widgets for the Hyperliquid Trading tab.
// No Riverpod dependency — callers pass in the candle data (see
// hyperliquid_candles_provider.dart for the live source) so these paint
// the same whether the bars are REST-seeded history or a live-ticking WS
// feed.
//
//   * [HlCandlestickChart] — the detail-sheet chart. A proper candlestick
//     chart: per-bar body (open→close, green up / red down) + high-low
//     wick, a dashed last-price line with a right-edge price tag, optional
//     volume bars along the bottom, and a touch-scrub crosshair (shared
//     KuteChartCrosshair layer: hairline + value bubble + bottom time
//     chip, with the richer readout staying in the header row). Line mode
//     renders through the shared chart engine (monotone cubic smoothing,
//     cached gradient fill, endpoint dot + live pulse) and supports the
//     animated timeframe morph via [HlCandlestickChart.morphKey]. Handles
//     1..N candles; empty shows a placeholder. Gestures outside editing
//     mode follow TradingView: drag pans, two fingers pinch to zoom, a
//     long press (then slide) shows the crosshair, a vertical drag on the
//     left price strip scales the axis.
//   * [HlLineSparkline] — the market-CARD mini chart. A clean line (up/down
//     colored vs first→last close) with a subtle gradient fill, min–max
//     normalized so crypto prices far from zero still read. This is what
//     the browse cards use.
//   * [HlLiveDot] — the small green "LIVE" pip reused wherever a live WS
//     feed is on.
//
// LIVE feel: when [HlCandlestickChart.isLive] the leading candle mutates
// in place as WS frames arrive (the provider upserts by open-time), so the
// rightmost bar visibly ticks; in line mode the endpoint additionally
// eases to each new price over 250ms instead of jumping.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart'
    show DragStartBehavior, kDoubleTapSlop, kDoubleTapTimeout;
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
// intl also exports a `TextDirection` (LTR/RTL) that shadows dart:ui's —
// hide it so the TextPainter below resolves the Flutter one.
import 'package:intl/intl.dart' hide TextDirection;

import 'package:kute/services/device_performance.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_indicator_series.dart';
import 'package:kute/models/chart_drawing.dart';
import 'package:kute/models/hyperliquid_market.dart' show HlFill;
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_opening.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/shared/charts/kute_chart_autoscale.dart';
import 'package:kute/screens/shared/charts/kute_chart_core.dart';
import 'package:kute/screens/shared/charts/kute_chart_crosshair.dart';
import 'package:kute/screens/shared/charts/kute_chart_drawings.dart';
import 'package:kute/screens/shared/charts/kute_chart_format.dart';
import 'package:kute/screens/shared/charts/kute_chart_signals.dart';
import 'package:kute/screens/shared/charts/kute_chart_trade_lines.dart';
import 'package:kute/screens/shared/charts/kute_chart_indicators.dart';
import 'package:kute/theme/app_theme.dart';

// ───────────────────────────── LIVE dot ─────────────────────────────

/// Small green pip + "LIVE" caption — the shared live-feed indicator (same
/// grammar as the order book's inline LIVE badge). The pip breathes on a
/// 1600ms loop (opacity + slight scale) so it matches the Polymarket
/// chart's live affordance; the loop is decorative, so it's gated off
/// under Reduce Motion, and the AnimatedBuilder + RepaintBoundary keep
/// the per-frame work confined to the tiny pip — never the chart canvas.
class HlLiveDot extends StatefulWidget {
  final String label;
  final Color color;
  const HlLiveDot(
      {super.key, this.label = 'LIVE', this.color = AppColors.marketUp});

  @override
  State<HlLiveDot> createState() => _HlLiveDotState();
}

class _HlLiveDotState extends State<HlLiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) {
      if (_pulse.isAnimating) _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (_, __) {
              // Triangle wave 0→1→0 for a smooth breathe, no snap at loop.
              final v = _pulse.value;
              final breathe = v < 0.5 ? v * 2 : 2 - v * 2;
              return Transform.scale(
                scale: 0.92 + breathe * 0.16,
                child: Container(
                  width: 6.w,
                  height: 6.w,
                  decoration: BoxDecoration(
                    color:
                        widget.color.withValues(alpha: 0.55 + breathe * 0.45),
                    shape: BoxShape.circle,
                  ),
                ),
              );
            },
          ),
        ),
        SizedBox(width: 4.w),
        Text(
          widget.label,
          style: TextStyle(
            color: c.textSecondary,
            fontSize: 12.sp,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────── shared geometry ───────────────────────────

/// A price-axis domain in axis space (price, or ln(price) when [log]):
/// the scale every layer of one frame maps through. The host animates it
/// between autoscale targets, or holds a manual one.
typedef HlPriceDomain = ({double lo, double hi, bool log});

/// Height of the price area once the volume strip and its gap are taken
/// off the bottom.
double _hlPriceAreaHeight(double height, bool showVolume) =>
    showVolume ? height * 0.80 : height;

/// Price-area layout + y-domain for one paint/resolve pass. Both the data
/// painter and the crosshair/pulse resolvers derive their coordinates from
/// this single computation so overlays land exactly on the line/candles.
/// [domain] is the host's shown (autoscaled or manual) domain; without it
/// the domain is fitted to [candles] with the autoscale margins. A morph
/// series always fits itself, since its tween is the animation.
({double priceH, double loP, double rangeP, bool log}) _hlPriceGeometry({
  required List<HyperliquidCandle> candles,
  required bool renderAsLine,
  required bool showVolume,
  required double height,
  bool logScale = false,
  double? leadingClose,
  List<double>? morphSeries,
  HlPriceDomain? domain,
}) {
  final priceH = _hlPriceAreaHeight(height, showVolume);
  final morphing = morphSeries != null && morphSeries.isNotEmpty;
  if (domain != null && !morphing) {
    final span = domain.hi - domain.lo;
    return (
      priceH: priceH,
      loP: domain.lo,
      rangeP: span > 0 ? span : 1.0,
      log: domain.log,
    );
  }

  // Line mode spans the close series (a tighter, card-like range); candle
  // mode spans the wicks.
  double lo, hi;
  if (morphing) {
    lo = morphSeries.first;
    hi = morphSeries.first;
    for (final v in morphSeries) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
  } else if (renderAsLine) {
    lo = candles.first.close;
    hi = candles.first.close;
    final n = candles.length;
    for (var i = 0; i < n; i++) {
      final v = (i == n - 1 && leadingClose != null)
          ? leadingClose
          : candles[i].close;
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
  } else {
    lo = candles.first.low;
    hi = candles.first.high;
    for (final k in candles) {
      if (k.low < lo) lo = k.low;
      if (k.high > hi) hi = k.high;
    }
  }
  // Log price axis: fit the domain in ln space (prices are strictly
  // positive on every HL market; a non-positive lo falls back to linear
  // so the mapping can never blow up).
  final useLog = logScale && lo > 0;
  if (useLog) {
    lo = kuteLogPrice(lo);
    hi = kuteLogPrice(hi);
  }
  final fitted = kuteAutoScaleDomain(lo, hi);
  final rangeP =
      (fitted.maxY - fitted.minY) > 0 ? (fitted.maxY - fitted.minY) : 1.0;
  return (priceH: priceH, loP: fitted.minY, rangeP: rangeP, log: useLog);
}

/// Price → domain-space value for the shared geometry: identity on a
/// linear axis, ln() on a log axis.
double _hlMapPrice(double v, bool log) => log ? kuteLogPrice(v) : v;

// ───────────────────────────── fill markers ─────────────────────────────

/// One of the user's own fills resolved to a marker position on the plot:
/// the fill, the bar whose time bucket holds it, and the centre of the
/// small ▲/▼ glyph in canvas px. Produced by [hlResolveFillMarkers] for
/// both the data painter (drawing) and the host (tap hit-testing) so the
/// two can never disagree about where a marker sits.
class HlFillMarker {
  final HlFill fill;
  final int barIndex;
  final Offset center;

  const HlFillMarker({
    required this.fill,
    required this.barIndex,
    required this.center,
  });
}

/// Half-size of the fill marker glyph, in px. Deliberately small: the
/// marker only says "something happened here"; the tooltip carries the
/// detail.
const double hlFillMarkerRadius = 4.0;

/// Touch radius (px) inside which a tap on the plot picks a fill marker.
const double hlFillMarkerHitRadius = 18.0;

/// Maps the user's fills onto the plotted tape. The x position is found by
/// locating the BAR whose bucket contains the fill's timestamp — never by
/// linear time→index arithmetic, which is wrong the moment the tape has
/// gaps (thin markets return only traded buckets, so bar i does NOT sit at
/// firstT + i×bucket). Fills outside the tape or with no price are
/// skipped. Buys sit just below the execution price and sells just above
/// it, so an entry and an exit sharing a candle at nearly the same price
/// both stay visible. Returns an empty list for a tape under two bars.
List<HlFillMarker> hlResolveFillMarkers({
  required List<HyperliquidCandle> candles,
  required List<HlFill> fills,
  required Size size,
  required bool renderAsLine,
  required bool showVolume,
  bool logScale = false,
  double? leadingClose,
  HlPriceDomain? domain,
}) {
  final n = candles.length;
  if (fills.isEmpty || n < 2 || size.width <= 0 || size.height <= 0) {
    return const [];
  }
  final geom = _hlPriceGeometry(
    candles: candles,
    renderAsLine: renderAsLine,
    showVolume: showVolume,
    height: size.height,
    logScale: logScale,
    leadingClose: renderAsLine ? leadingClose : null,
    domain: domain,
  );
  final priceH = geom.priceH;
  double toY(double v) =>
      priceH * (1 - (_hlMapPrice(v, geom.log) - geom.loP) / geom.rangeP);
  final slot = size.width / n;
  final firstT = candles.first.openTime.millisecondsSinceEpoch;
  final lastT = candles.last.openTime.millisecondsSinceEpoch;
  var bucketMs = candles.last.closeTime.millisecondsSinceEpoch - lastT;
  if (bucketMs <= 0) {
    bucketMs = lastT - candles[n - 2].openTime.millisecondsSinceEpoch;
  }
  if (bucketMs <= 0) bucketMs = 1;
  // The marker keeps its whole glyph inside the price area.
  final minY = hlFillMarkerRadius + 1;
  final maxY = math.max(minY, priceH - hlFillMarkerRadius - 1);
  final out = <HlFillMarker>[];
  for (final f in fills) {
    if (f.px <= 0 || !f.px.isFinite) continue;
    if (f.time < firstT || f.time > lastT + bucketMs) continue;
    // Binary search: the last bar whose openTime <= fill time.
    var lo = 0, hi = n - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (candles[mid].openTime.millisecondsSinceEpoch <= f.time) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    final mx = (lo + 0.5) * slot;
    final my = (toY(f.px) + (f.isBuy ? 8.0 : -8.0)).clamp(minY, maxY);
    out.add(HlFillMarker(fill: f, barIndex: lo, center: Offset(mx, my)));
  }
  return out;
}

/// The marker nearest to [position] within [hlFillMarkerHitRadius], plus
/// every other marker on the same bar (an entry and an exit inside one
/// candle read as one event with two lines). Ordered by fill time. Empty
/// when nothing is close enough.
List<HlFillMarker> hlHitTestFillMarkers(
  List<HlFillMarker> markers,
  Offset position,
) {
  HlFillMarker? nearest;
  var best = hlFillMarkerHitRadius;
  for (final m in markers) {
    final d = (m.center - position).distance;
    if (d <= best) {
      best = d;
      nearest = m;
    }
  }
  if (nearest == null) return const [];
  final group = [
    for (final m in markers)
      if (m.barIndex == nearest.barIndex) m
  ]..sort((a, b) => a.fill.time.compareTo(b.fill.time));
  return group;
}

/// Stable identity for a fill across host rebuilds (the fills list is
/// often re-created with equal content), so an open tooltip keeps
/// pointing at the same trade.
Object hlFillIdentity(HlFill f) =>
    f.tradeId ?? (f.time, f.px, f.side, f.sz);

/// A small filled triangle (▲ buy / ▼ sell) with a background-coloured
/// halo so it stays legible over the line/candles in either theme.
void hlPaintFillMarker(Canvas canvas, Offset o, bool buy, Color col,
    Color halo) {
  const r = hlFillMarkerRadius;
  final path = Path();
  if (buy) {
    path.moveTo(o.dx, o.dy - r);
    path.lineTo(o.dx - r, o.dy + r);
    path.lineTo(o.dx + r, o.dy + r);
  } else {
    path.moveTo(o.dx, o.dy + r);
    path.lineTo(o.dx - r, o.dy - r);
    path.lineTo(o.dx + r, o.dy - r);
  }
  path.close();
  canvas.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeJoin = StrokeJoin.round
      ..color = halo,
  );
  canvas.drawPath(path, Paint()..color = col);
}

/// 4-6 "nice" price levels inside [lo, hi] (both in real price space).
/// Linear axes use the classic 1/2/5 nice-step ladder; a log axis whose
/// window spans a wide ratio switches to 1-2-5 per decade so the levels
/// stay visually even in ln space. Returns an ascending list, possibly
/// empty on a degenerate range. The Polymarket chart labels its
/// probability scale with the same ladder.
List<double> hlNiceLevels(double lo, double hi, {bool log = false}) {
  if (!(hi > lo) || !lo.isFinite || !hi.isFinite) return const [];
  if (log && lo > 0 && hi / lo > 4) {
    final out = <double>[];
    var decade = math.pow(10.0, (math.log(lo) / math.ln10).floor()).toDouble();
    const mults = [1.0, 2.0, 5.0];
    // Bounded: at most ~12 decades of iteration for any sane price.
    var guard = 0;
    while (decade <= hi && guard < 48) {
      for (final m in mults) {
        final v = decade * m;
        if (v >= lo && v <= hi) out.add(v);
      }
      decade *= 10;
      guard++;
    }
    if (out.length > 6) {
      final stride = (out.length / 5.0).ceil();
      final thinned = <double>[
        for (var i = 0; i < out.length; i += stride) out[i]
      ];
      if (thinned.length >= 3) return thinned;
    }
    if (out.length >= 3) return out;
    // Too few decade marks in a narrow window — fall through to linear.
  }
  final rawStep = (hi - lo) / 4;
  if (rawStep <= 0 || !rawStep.isFinite) return const [];
  final mag =
      math.pow(10.0, (math.log(rawStep) / math.ln10).floor()).toDouble();
  final norm = rawStep / mag;
  final double step;
  if (norm < 1.5) {
    step = mag;
  } else if (norm < 3) {
    step = 2 * mag;
  } else if (norm < 7) {
    step = 5 * mag;
  } else {
    step = 10 * mag;
  }
  final out = <double>[];
  var v = (lo / step).ceilToDouble() * step;
  var guard = 0;
  while (v <= hi + step * 1e-6 && guard < 12) {
    out.add(v);
    v += step;
    guard++;
  }
  return out;
}

/// The y-axis price scale layer: 4-6 nice-number labels hugging the LEFT
/// edge of the price area with faint full-width hairlines at those
/// levels. Drawn INSIDE the plot (no gutter is reserved), so the price
/// geometry every other layer shares is untouched and drawings /
/// crosshair / markers stay in register. The host fades this layer:
/// always on in Advanced mode, scrub-only otherwise.
class _HlPriceScalePainter extends CustomPainter {
  final List<HyperliquidCandle> candles;
  final bool renderAsLine;
  final bool showVolume;
  final bool logScale;
  final double? leadingClose;
  final List<double>? morphSeries;
  final int? decimalCap;
  final Color labelColor;
  final Color hairlineColor;

  /// The shown (autoscaled or manual) domain; the labels follow it.
  final HlPriceDomain? domain;

  _HlPriceScalePainter({
    required this.candles,
    required this.renderAsLine,
    required this.showVolume,
    required this.logScale,
    required this.leadingClose,
    required this.morphSeries,
    required this.decimalCap,
    required this.labelColor,
    required this.hairlineColor,
    this.domain,
  });

  /// Laid-out TextPainters keyed by (text, color, fontSize) — scale
  /// labels repeat heavily between frames. Bounded defensively.
  static final Map<(String, int, double), TextPainter> _tpCache = {};

  static TextPainter _tp(String text, Color color, double fontSize) {
    if (_tpCache.length > 96) _tpCache.clear();
    return _tpCache.putIfAbsent(
      (text, color.toARGB32(), fontSize),
      () => TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: kuteChartFontFamily,
            color: color,
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;
    final geom = _hlPriceGeometry(
      candles: candles,
      renderAsLine: renderAsLine,
      showVolume: showVolume,
      height: size.height,
      logScale: logScale,
      leadingClose: renderAsLine ? leadingClose : null,
      morphSeries: renderAsLine ? morphSeries : null,
      domain: domain,
    );
    final priceH = geom.priceH;
    if (priceH <= 0) return;
    // Domain bounds back in real price space for level picking.
    final loPrice = geom.log ? math.exp(geom.loP) : geom.loP;
    final hiPrice =
        geom.log ? math.exp(geom.loP + geom.rangeP) : geom.loP + geom.rangeP;
    final levels = hlNiceLevels(loPrice, hiPrice, log: geom.log);
    if (levels.isEmpty) return;

    final linePaint = Paint()
      ..color = hairlineColor.withValues(alpha: 0.05)
      ..strokeWidth = 1.0;
    final fontSize = 10.5.sp;
    for (final level in levels) {
      final y = priceH *
          (1 - (_hlMapPrice(level, geom.log) - geom.loP) / geom.rangeP);
      if (y < 0 || y > priceH) continue;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
      final tp = _tp(
          formatHlPrice(level, decimalCap: decimalCap), labelColor, fontSize);
      final ty = (y - tp.height - 2)
          .clamp(0.0, math.max(0.0, priceH - tp.height))
          .toDouble();
      tp.paint(canvas, Offset(2, ty));
    }
  }

  @override
  bool shouldRepaint(covariant _HlPriceScalePainter old) =>
      old.candles != candles ||
      old.renderAsLine != renderAsLine ||
      old.showVolume != showVolume ||
      old.logScale != logScale ||
      old.leadingClose != leadingClose ||
      !identical(old.morphSeries, morphSeries) ||
      old.decimalCap != decimalCap ||
      old.labelColor != labelColor ||
      old.hairlineColor != hairlineColor ||
      old.domain != domain;
}

// ─────────────────────────── candlestick chart ───────────────────────────

/// How the price series is drawn. The line family shares the line
/// painter (with, without, or with a two-tone fill); the candle family
/// shares the bar painter. Heikin Ashi transforms the candles first.
enum HlChartStyle {
  candles,
  hollow,
  bars,
  heikinAshi,
  line,
  area,
  baseline;

  bool get isLine => this == line || this == area || this == baseline;

  /// Area is the default everywhere a style is missing or unknown.
  static HlChartStyle fromName(String? name) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return area;
  }
}

/// Live candlestick chart for one market + timeframe. [candles] are
/// ascending by open-time; [isLive] toggles the LIVE pip. [timeframeLabel]
/// (e.g. '1d') labels the idle "past X%" summary. [decimalCap] bounds the
/// price-tag precision (HlMarket.pxDecimalCap). [morphKey] is the
/// timeframe identity — when it changes and fresh candles arrive, line
/// mode tweens the old series into the new one instead of hard-snapping.
class HlCandlestickChart extends StatefulWidget {
  final List<HyperliquidCandle> candles;
  final bool isLive;
  final int? decimalCap;
  final double height;
  final String? timeframeLabel;
  final bool showVolume;

  /// When true the price area renders a clean LINE (across each candle's
  /// close) instead of candlestick bodies — same last-price line/tag,
  /// touch crosshair, and optional volume strip. Defaults to candlesticks.
  final bool renderAsLine;

  /// The user's OWN fills for this market, drawn as buy/sell markers on the
  /// price at their fill time+price so a trader sees where they got in/out.
  /// Empty → no markers.
  final List<HlFill> fills;

  /// The user's OPEN position's average entry price on this market — drawn
  /// as a muted dashed horizontal reference with a right-edge "Entry" tag
  /// (both line and candle modes). Null/<=0 → no line.
  final double? entryPx;

  /// Side of that open position (colours the entry line: long = marketUp,
  /// short = marketDown). Ignored when [entryPx] is null.
  final bool entryIsLong;

  /// Identity of the plotted window (timeframe). A change arms the
  /// line-mode morph; null disables morphing.
  final String? morphKey;

  /// Canonical venue + market identity, distinct from the timeframe.
  /// A new market must never inherit a pointer draft or selection preview.
  final String? marketKey;

  /// The user's saved drawings for this market (trendlines, levels, rays,
  /// rectangles) — always rendered (view-only outside drawing mode).
  final List<ChartDrawing> drawings;

  /// Advanced drawing mode: pan/scrub is suspended and pans/taps place,
  /// select or edit drawings instead. The host owns the toolbar + state.
  final bool drawingMode;

  /// When true the plot takes whatever height the parent column leaves
  /// after the fixed rows (scrub label, date axis, indicator panes), so
  /// editing mode never has to guess at those rows' heights. The parent
  /// must be bounded.
  final bool fillHeight;

  /// The armed tool (drawing mode only). Null = select/edit mode.
  final ChartDrawingTool? armedTool;

  /// ARGB of the armed color choice; null = theme neutral.
  final int? armedColorValue;

  /// Currently selected drawing (handles shown, drawing mode only).
  final String? selectedDrawingId;

  /// Called once when a tap/drag finishes placing a new drawing.
  final ValueChanged<ChartDrawing>? onDrawingPlaced;

  /// Called when a tap selects (id) or deselects (null) a drawing.
  final ValueChanged<String?>? onDrawingSelected;

  /// Called ONCE at the end of a handle drag with the adjusted drawing.
  final ValueChanged<ChartDrawing>? onDrawingUpdated;

  final ValueChanged<ChartDrawingPoint>? onTextRequested;
  final bool magnet;

  /// Active indicator keys ('ma' = SMA 20/50, 'ema' = EMA 9/21, 'bb' =
  /// Bollinger 20,2). Other keys are ignored here — the host maps 'vol'
  /// onto [showVolume] and 'log' onto [logScale]. Computed lazily and
  /// memoized (see KuteIndicatorEngine); rendered as thin polylines in
  /// the data painter layer using the documented shared palette.
  final Set<String> indicators;

  /// Log price axis: y maps ln(price) instead of price. Flows through
  /// the ONE shared geometry, so candles/line, overlays, drawings,
  /// crosshair, entry line and fill markers all stay in register.
  final bool logScale;

  /// Drawing style. [renderAsLine] is honoured for older callers; a
  /// line-family [style] also renders as a line.
  final HlChartStyle style;

  /// The user's own position and working orders on this market, drawn as
  /// tagged horizontal price lines (entry, liquidation, limits, TP/SL).
  /// Always rendered; editable lines can be dragged to a new price.
  final List<ChartTradeLine> tradeLines;

  /// Called once when an editable trade line is dropped at a new price.
  /// The host owns what that means (review, step-up, modify order).
  final void Function(String id, double price)? onTradeLineMoved;

  /// Called when a trade line's tag is tapped.
  final ValueChanged<String>? onTradeLineTapped;

  /// Optional marks about the market (Predictions odds levels, macro and
  /// funding dates, large trades, an open-interest caption). Empty by
  /// default: the chart then draws exactly what it always has.
  final ChartSignals signals;

  /// Called when a signal's tag is tapped, with its id.
  final ValueChanged<String>? onSignalTapped;

  const HlCandlestickChart({
    super.key,
    required this.candles,
    this.isLive = false,
    this.decimalCap,
    this.height = 240,
    this.timeframeLabel,
    this.showVolume = true,
    this.renderAsLine = false,
    this.fills = const [],
    this.entryPx,
    this.entryIsLong = true,
    this.morphKey,
    this.marketKey,
    this.drawings = const [],
    this.drawingMode = false,
    this.armedTool,
    this.armedColorValue,
    this.selectedDrawingId,
    this.onDrawingPlaced,
    this.onDrawingSelected,
    this.onDrawingUpdated,
    this.onTextRequested,
    this.magnet = false,
    this.indicators = const {},
    this.logScale = false,
    this.tradeLines = const [],
    this.onTradeLineMoved,
    this.onTradeLineTapped,
    this.signals = ChartSignals.none,
    this.onSignalTapped,
    this.style = HlChartStyle.area,
    this.onMoreHistoryWanted,
    this.fillHeight = false,
    this.onAutoScaleChanged,
    this.onVisibleSpanChanged,
    this.footer,
    this.summaryBelow = false,
    this.showSummary = true,
  });

  /// Shown right under the plot (and any indicator panes), above the
  /// summary row when [summaryBelow]: the host's timeframe pills, so they
  /// stay attached to the chart.
  final Widget? footer;

  /// Put the summary / scrub readout row (with the LIVE dot) under the
  /// plot and [footer] instead of above it, so the plot starts at the top.
  final bool summaryBelow;

  /// False drops the summary / scrub readout row entirely, so editing
  /// mode gives that height to the plot (the host's top bar names the
  /// market instead).
  final bool showSummary;

  /// Reports the time span on screen (first visible bar to the end of
  /// the last) whenever it changes, so the host can map a candle view
  /// onto the nearest line range.
  final ValueChanged<Duration>? onVisibleSpanChanged;

  /// Called when the price scale switches between autoscale (true) and a
  /// manual scale the user dragged on the price axis (false).
  final ValueChanged<bool>? onAutoScaleChanged;

  /// Called when a pinch zooms out past the loaded tape or a pan slides
  /// past its oldest bar, so the host can load older bars in front of
  /// it. Only the visible slice changes meanwhile; the request is
  /// best-effort and throttled here to one per 700ms.
  final VoidCallback? onMoreHistoryWanted;

  @override
  State<HlCandlestickChart> createState() => _HlCandlestickChartState();
}

class _HlCandlestickChartState extends State<HlCandlestickChart>
    with TickerProviderStateMixin {
  int? _touchIndex;

  // ── viewport (every style, every mode) ───────────────────────────
  /// How many of the loaded bars are on screen (null = the newest
  /// [_defaultViewBars]) and how many of the newest bars sit off the right
  /// edge. Set by a drag, a two-finger pinch or slide. A new interval or
  /// market starts from the default; a style change keeps the view.
  int? _viewBars;
  int _viewEndOffset = 0;
  List<HyperliquidCandle>? _tapeSource;
  int? _tapeBars;
  int _tapeOffset = 0;
  List<HyperliquidCandle>? _tapeCache;

  /// Raw pointers on the chart, for the pinch. Two of them zoom; the
  /// drawing gesture that the first one started is cancelled the moment
  /// the second lands, and every one-finger handler stays quiet until
  /// all fingers lift.
  final Map<int, Offset> _pointers = {};
  bool _pinching = false;
  double? _pinchStartDistance;
  double? _pinchStartFocalX;
  int? _pinchStartBars;
  int _pinchStartOffset = 0;
  DateTime _lastHistoryRequest = DateTime(0);

  static const int _minViewBars = 12;

  // ── price scale (TradingView-style autoscale) ─────────────────────
  /// Autoscale on: the scale fits the bars on screen. Off after the user
  /// drags the price axis; the Auto pill or a double tap turns it back on.
  bool _autoScale = true;
  HlPriceDomain? _manualDomain;

  /// The domain painted in the last frame (mid-animation included), so
  /// gestures map touches exactly as the user sees them.
  HlPriceDomain? _shownDomain;

  /// Bumped when the scale must jump instead of glide (another market).
  int _scaleEpoch = 0;
  final KuteAutoScaleTracker _scaleTracker = KuteAutoScaleTracker();
  final KuteRangeExtremes<HyperliquidCandle> _wickExtremes =
      KuteRangeExtremes(lowOf: (k) => k.low, highOf: (k) => k.high);
  final KuteRangeExtremes<HyperliquidCandle> _closeExtremes =
      KuteRangeExtremes(lowOf: (k) => k.close, highOf: (k) => k.close);

  /// The outlier-aware range of the bars on screen, kept per tape slice
  /// (its identity is stable across rebuilds) so a frame does not re-sort.
  List<HyperliquidCandle>? _outlierSource;
  bool _outlierLine = false;
  ({double lo, double hi})? _outlierRange;

  /// Price-axis drag (manual scale), editing mode only: a vertical drag
  /// on the left label strip squeezes or stretches the scale.
  static const double _axisStripWidth = 48.0;
  bool _axisDragging = false;
  double _axisStartY = 0;
  HlPriceDomain? _axisStartDomain;

  /// Second tap of a double tap (restores autoscale).
  DateTime _lastTapAt = DateTime(0);
  Offset _lastTapPos = Offset.zero;

  /// One-finger pan of the viewport in editing mode: with no tool armed
  /// and no drawing under the finger, a drag scrolls the chart back and
  /// forth in time instead of doing nothing.
  bool _panningView = false;
  double _panStartX = 0;
  int _panStartOffset = 0;
  int _panBars = 0;

  /// Index in [_styledFull] of the first bar on screen.
  int _tapeStart = 0;
  int _tapeCacheStart = 0;

  /// The candles on screen: the loaded tape (styled), or the viewport's
  /// slice of it. Sliced once per (tape, range) so identity stays stable
  /// across rebuilds and the per-identity caches downstream keep working.
  List<HyperliquidCandle> get _tape {
    final source = _styledFull;
    final bars = _effectiveViewBars;
    final offset = bars == null ? 0 : _viewEndOffset;
    if (bars == null) {
      _tapeStart = 0;
      return source;
    }
    if (identical(_tapeSource, source) &&
        _tapeBars == bars &&
        _tapeOffset == offset &&
        _tapeCache != null) {
      _tapeStart = _tapeCacheStart;
      return _tapeCache!;
    }
    final total = source.length;
    final end = (total - offset).clamp(0, total);
    final start = (end - bars).clamp(0, end);
    _tapeSource = source;
    _tapeBars = bars;
    _tapeOffset = offset;
    _tapeStart = start;
    _tapeCacheStart = start;
    _tapeCache =
        start == 0 && end == total ? source : source.sublist(start, end);
    return _tapeCache!;
  }

  /// Bars on screen (pinch to zoom, drag to pan, on every chart and in
  /// every mode). Every style opens on the newest [_defaultViewBars] bars
  /// of its interval, as TradingView does; the style only changes how a
  /// bar is drawn.
  int? get _effectiveViewBars => _viewBars ?? _defaultViewBars;

  /// The newest bar is on screen (the live edge).
  bool get _atLiveEdge => _viewEndOffset == 0;

  /// Normal-mode one-finger gesture state: a drag that starts on the left
  /// price-label strip scales the axis when it goes vertical and pans
  /// when it goes sideways; anywhere else it pans.
  bool _axisCandidate = false;
  Offset _gestureStart = Offset.zero;

  static const int _defaultViewBars = 100;

  /// The visible span last reported to the host.
  Duration? _reportedSpan;

  void _onPointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 2) {
      final points = _pointers.values.toList();
      _cancelDrawingGesture();
      _dismissFillTip();
      // A second finger turns an order-line drag into a pinch; the line
      // goes back where it was, nothing is moved.
      _tradeDrag = null;
      _tradeDragGeom = null;
      if (!widget.drawingMode) _drawingCandles = null;
      _axisCandidate = false;
      _axisDragging = false;
      _panningView = false;
      _pinching = true;
      _pinchStartDistance = (points[0] - points[1]).distance;
      _pinchStartFocalX = (points[0].dx + points[1].dx) / 2;
      _pinchStartBars = math.min(
          _effectiveViewBars ?? widget.candles.length, widget.candles.length);
      _pinchStartOffset = _viewEndOffset;
      setState(() => _touchIndex = null);
    }
  }

  void _onPointerMove(PointerMoveEvent e, double chartWidth) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;
    if (!_pinching || _pointers.length < 2) return;
    final points = _pointers.values.take(2).toList();
    final distance = (points[0] - points[1]).distance;
    final focalX = (points[0].dx + points[1].dx) / 2;
    final startDistance = _pinchStartDistance ?? distance;
    final startBars = _pinchStartBars ?? widget.candles.length;
    if (startDistance <= 0 || startBars <= 0) return;
    final total = widget.candles.length;
    // Fingers apart → fewer bars (zoom in); together → more (zoom out).
    final scale = (distance / startDistance).clamp(0.05, 20.0);
    var bars = (startBars / scale).round().clamp(_minViewBars, total);
    // Sliding both fingers pans the window by whole bars.
    final slot = chartWidth > 0 ? chartWidth / bars : 0.0;
    final panBars = slot > 0
        ? ((focalX - (_pinchStartFocalX ?? focalX)) / slot).round()
        : 0;
    final maxOffset = (total - bars).clamp(0, total);
    var offset = (_pinchStartOffset + panBars).clamp(0, maxOffset);
    // Zooming out with the whole tape already on screen, or sliding past
    // its oldest bar, is a request for more history; the host answers by
    // loading older bars in front of the tape.
    if (bars >= total && scale < 0.98) _requestMoreHistory();
    if (offset == maxOffset && _pinchStartOffset + panBars > maxOffset) {
      _requestMoreHistory();
    }
    if (bars >= total) offset = 0;
    // Kept as a count even when it spans the whole tape, so a longer
    // tape arriving from the host keeps the same bars on screen and the
    // pinch that is still in progress grows the view from there.
    if (bars != (_viewBars ?? total) || offset != _viewEndOffset) {
      setState(() {
        _viewBars = bars;
        _viewEndOffset = offset;
      });
    }
  }

  void _onPointerUp(int pointer) {
    _pointers.remove(pointer);
    if (_pointers.isEmpty && _pinching) {
      _pinching = false;
      _pinchStartDistance = null;
      _pinchStartFocalX = null;
      _pinchStartBars = null;
    }
  }

  void _resetViewport() {
    _viewBars = null;
    _viewEndOffset = 0;
    _pointers.clear();
    _pinching = false;
    _panningView = false;
  }

  /// Asks the host for a longer tape, at most once every 700ms.
  void _requestMoreHistory() {
    if (widget.onMoreHistoryWanted == null) return;
    final now = DateTime.now();
    if (now.difference(_lastHistoryRequest).inMilliseconds > 700) {
      _lastHistoryRequest = now;
      widget.onMoreHistoryWanted!.call();
    }
  }

  void _onViewPanUpdate(double x, double chartWidth) {
    final total = widget.candles.length;
    final bars = _panBars.clamp(1, total == 0 ? 1 : total);
    final slot = chartWidth > 0 ? chartWidth / bars : 0.0;
    if (slot <= 0 || total == 0) return;
    final panBars = ((x - _panStartX) / slot).round();
    final maxOffset = (total - bars).clamp(0, total);
    final offset = (_panStartOffset + panBars).clamp(0, maxOffset);
    // Dragging right with the oldest loaded bar already on screen is a
    // request for older history.
    if (offset == maxOffset &&
        panBars > 0 &&
        _panStartOffset + panBars > maxOffset) {
      _requestMoreHistory();
    }
    final current = math.min(_effectiveViewBars ?? total, total);
    if (offset != _viewEndOffset || bars != current) {
      setState(() {
        _viewBars = bars;
        _viewEndOffset = offset;
      });
    }
  }

  // ─────────────────────────── price scale ───────────────────────────

  /// The domain a frozen gesture (drawing or trade-line drag) maps
  /// through. The series holds it until the finger lifts, so live ticks
  /// never rescale the chart under a dragged handle or line.
  HlPriceDomain? get _frozenDomain {
    final g = _tradeDragGeom ?? _dragGeometry;
    if (g == null) return null;
    return (lo: g.loP, hi: g.loP + g.rangeP, log: g is KuteLogDrawingGeometry);
  }

  /// Where the price scale should sit for [visible] (the bars on screen):
  /// a frozen gesture's domain, the manual one, or the autoscale fit of
  /// the visible series. Price lines never take part in the fit.
  HlPriceDomain _scaleTarget(List<HyperliquidCandle> visible) {
    final frozen = _frozenDomain;
    if (frozen != null) return frozen;
    final manual = _manualDomain;
    if (!_autoScale && manual != null) return manual;
    final line = _asLine;
    final ext = line ? _closeExtremes : _wickExtremes;
    ext.sync(_styledFull);
    final r = ext.query(_tapeStart, _tapeStart + visible.length);
    var lo = r?.lo ?? visible.last.close;
    var hi = r?.hi ?? visible.last.close;
    // One or two bars far outside the rest of the tape (a stray print on
    // a thin market) would squash everything else into a line: fit the
    // body of the tape and let that bar clip at the plot's edge. Null for
    // an ordinary tape, which keeps the full fit above.
    if (!identical(_outlierSource, visible) || _outlierLine != line) {
      _outlierSource = visible;
      _outlierLine = line;
      _outlierRange = hlOutlierAwareRange(visible, asLine: line);
    }
    final body = _outlierRange;
    if (body != null) {
      lo = body.lo;
      hi = body.hi;
    }
    final useLog = widget.logScale && lo > 0;
    if (useLog) {
      lo = kuteLogPrice(lo);
      hi = kuteLogPrice(hi);
    }
    final fit = _scaleTracker.fit(
      (
        visible.first.openTime.millisecondsSinceEpoch,
        visible.length,
        line,
        useLog,
        widget.style == HlChartStyle.heikinAshi,
      ),
      lo,
      hi,
    );
    return (lo: fit.minY, hi: fit.maxY, log: useLog);
  }

  /// Back to autoscale (the Auto pill or a double tap).
  void _restoreAutoScale() {
    if (_autoScale) return;
    HapticFeedback.selectionClick();
    setState(() {
      _autoScale = true;
      _manualDomain = null;
      _scaleTracker.reset();
    });
    widget.onAutoScaleChanged?.call(true);
  }

  /// Forget any manual scale without telling the host (a new market or
  /// axis kind, not a user choice). [jump] skips the glide.
  void _resetScale({bool jump = false}) {
    _autoScale = true;
    _manualDomain = null;
    _axisDragging = false;
    _axisStartDomain = null;
    _scaleTracker.reset();
    if (jump) {
      _scaleEpoch++;
      _shownDomain = null;
    }
  }

  /// True on the second tap of a double tap. Detected by hand so single
  /// taps (markers, tags, drawings) keep firing at once.
  bool _isDoubleTap(Offset pos) {
    final now = DateTime.now();
    final hit = now.difference(_lastTapAt) < kDoubleTapTimeout &&
        (pos - _lastTapPos).distance < kDoubleTapSlop;
    _lastTapAt = hit ? DateTime(0) : now;
    _lastTapPos = pos;
    return hit;
  }

  /// Vertical drag on the price axis: down squeezes the scale (more price
  /// per pixel), up stretches it, about the middle of the shown domain.
  void _onAxisDrag(double y, Size size) {
    final d0 = _axisStartDomain;
    final priceH = _hlPriceAreaHeight(size.height, widget.showVolume);
    if (d0 == null || priceH <= 0) return;
    final f = math.exp((y - _axisStartY) / priceH * 1.6);
    final mid = (d0.lo + d0.hi) / 2;
    final half = (d0.hi - d0.lo) / 2 * f;
    if (!half.isFinite || half <= 0) return;
    final wasAuto = _autoScale;
    setState(() {
      _autoScale = false;
      _manualDomain = (lo: mid - half, hi: mid + half, log: d0.log);
    });
    if (wasAuto) widget.onAutoScaleChanged?.call(false);
  }

  bool get _asLine => _isLine(widget);

  /// Whether [chart] paints as a line. Compare old and new widgets with
  /// this, never the effective [_asLine] against the old widget's raw
  /// [HlCandlestickChart.renderAsLine]: with the default area style those
  /// always differ, so every parent rebuild (every live tick) read as a
  /// line/candle toggle and dropped the drawing under the finger.
  static bool _isLine(HlCandlestickChart chart) =>
      chart.renderAsLine || chart.style.isLine;

  /// Heikin Ashi bars derived once per candle-list identity.
  List<HyperliquidCandle>? _haSource;
  List<HyperliquidCandle>? _haCandles;

  /// The whole loaded tape as painted (Heikin Ashi derived over all of
  /// it, so the first visible bar does not depend on where the view
  /// starts). The viewport slices this.
  List<HyperliquidCandle> get _styledFull => _styled(widget.candles);

  /// The candles every layer paints: the real tape, or its Heikin Ashi
  /// transform, so geometry, drawings, trade lines and the crosshair all
  /// agree on one series.
  List<HyperliquidCandle> _styled(List<HyperliquidCandle> candles) {
    if (widget.style != HlChartStyle.heikinAshi) return candles;
    if (!identical(_haSource, candles)) {
      _haSource = candles;
      _haCandles = hlHeikinAshi(candles);
    }
    return _haCandles!;
  }

  DateTime _lastHaptic = DateTime(0);
  bool _reduceMotion = false;

  // ── drawing-mode interaction state ────────────────────────────────
  /// In-progress two-point placement (tap-drag). Committed on pan end.
  ChartDrawing? _draft;

  /// Live handle-drag copy of the selected drawing — rendered instead of
  /// the original; the host is notified ONCE on pan end so Hive isn't
  /// hit per drag frame.
  ChartDrawing? _edited;
  int _dragPointIndex = -1;
  KuteDrawingGeometry? _dragGeometry;
  List<HyperliquidCandle>? _drawingCandles;
  Offset? _dragStartPosition;
  Offset _handleOffset = Offset.zero;
  ChartDrawing? _draggedOriginal;
  bool _draggingBody = false;

  // ── trade lines (position + working orders) ──────────────────────
  /// Tag rects from the last trade-lines paint, for drag hit-testing.
  final List<ChartTradeLineHit> _tradeHits = [];

  /// Tag rects from the last signals paint, for tap hit-testing.
  final List<ChartSignalHit> _signalHits = [];

  /// The line under the finger, already at the finger's price.
  ChartTradeLine? _tradeDrag;
  KuteDrawingGeometry? _tradeDragGeom;

  // ── fill-marker tooltip ──────────────────────────────────────────
  /// Identities (hlFillIdentity) of the fills whose marker was tapped;
  /// empty = no tooltip. Kept as identities, not positions, so live ticks
  /// re-anchor the card to wherever the marker moves. Auto-dismissed by
  /// [_fillTipTimer], a tap elsewhere, a scrub/pan, a pinch or a market
  /// change.
  Set<Object> _fillTip = const {};
  Timer? _fillTipTimer;
  static const Duration _fillTipLifetime = Duration(seconds: 4);

  /// The candles every plot layer paints this frame.
  List<HyperliquidCandle> get _plotCandles => _drawingCandles ?? _tape;

  List<HlFillMarker> _fillMarkers(Size size, List<HyperliquidCandle> candles) {
    if (widget.fills.isEmpty || candles.length < 2) return const [];
    return hlResolveFillMarkers(
      candles: candles,
      fills: widget.fills,
      size: size,
      renderAsLine: _asLine,
      showVolume: widget.showVolume,
      logScale: widget.logScale,
      leadingClose: candles.last.close,
      domain: _shownDomain,
    );
  }

  /// A tap on the plot: opens the tooltip for the nearest fill marker
  /// within [hlFillMarkerHitRadius] (all fills on that bar together), or
  /// closes an open one when the tap lands elsewhere. Returns true when
  /// a marker was hit so the caller stops looking for other targets.
  bool _onFillMarkerTap(Offset pos, Size size) {
    final candles = _plotCandles;
    final hit = _morphActive
        ? const <HlFillMarker>[]
        : hlHitTestFillMarkers(_fillMarkers(size, candles), pos);
    if (hit.isEmpty) {
      _dismissFillTip();
      return false;
    }
    HapticFeedback.selectionClick();
    _fillTipTimer?.cancel();
    _fillTipTimer = Timer(_fillTipLifetime, _dismissFillTip);
    setState(() {
      _fillTip = {for (final m in hit) hlFillIdentity(m.fill)};
      _touchIndex = null;
    });
    return true;
  }

  void _dismissFillTip() {
    _fillTipTimer?.cancel();
    _fillTipTimer = null;
    if (_fillTip.isEmpty || !mounted) return;
    setState(() => _fillTip = const {});
  }

  /// The tooltip's rows, formatted once per build (never in a paint pass):
  /// "Bought 0.012 BTC at $64,120.00" over "Open Long · $769.44 · 29 Sep,
  /// 14:32". One entry per fill on the tapped bar, oldest first.
  List<HlFillTooltipEntry> _fillTipEntries(AppColorsExtension c) {
    if (_fillTip.isEmpty) return const [];
    final picked = [
      for (final f in widget.fills)
        if (_fillTip.contains(hlFillIdentity(f))) f
    ]..sort((a, b) => a.time.compareTo(b.time));
    final timeFmt = DateFormat('d MMM, HH:mm');
    return [
      for (final f in picked)
        HlFillTooltipEntry(
          identity: hlFillIdentity(f),
          color: f.isBuy ? AppColors.marketUp : AppColors.marketDown,
          title: context.l10n.hlChartFillTitle(
              f.isBuy
                  ? context.l10n.hlChartBoughtSize(formatHlSize(f.sz))
                  : context.l10n.hlChartSoldSize(formatHlSize(f.sz)),
              f.coin.isEmpty ? '' : ' ${f.coin}',
              formatHlPrice(f.px, decimalCap: widget.decimalCap)),
          detail: [
            if (f.dir.trim().isNotEmpty) f.dir.trim(),
            formatHlUsd(f.px * f.sz),
            timeFmt.format(DateTime.fromMillisecondsSinceEpoch(f.time)),
          ].join(' · '),
          detailColor: c.textSecondary,
        ),
    ];
  }

  /// Cached bar open-times for the drawings geometry, keyed on the candle
  /// list identity so live rebuilds don't re-allocate it.
  List<int>? _geomTimes;
  List<HyperliquidCandle>? _geomTimesSource;

  // ── indicators (SMA/EMA/BB) ───────────────────────────────────────
  /// Memoized indicator maths over the closes. Live ticks patch only
  /// the tail; the derived overlay lists below rebuild only when the
  /// engine's revision or the active indicator set changes, so the
  /// painter's identity-based shouldRepaint keeps working.
  final KuteIndicatorEngine _indEngine = KuteIndicatorEngine();
  List<KuteIndicatorOverlay> _indOverlays = const [];
  KuteIndicatorBand? _indBand;
  List<double> _rsi = const [];
  List<double> _volumeMa = const [];
  ({List<double> macd, List<double> signal, List<double> histogram})? _macd;
  List<double> _atr = const [];
  ({List<double> k, List<double> d})? _stoch;
  int _indStamp = 0;

  /// The same series cut to the bars on screen (see [_sliceIndicators]).
  Object? _sliceKey;
  List<KuteIndicatorOverlay> _visOverlays = const [];
  KuteIndicatorBand? _visBand;
  List<double> _visRsi = const [];
  List<double> _visVolumeMa = const [];
  ({List<double> macd, List<double> signal, List<double> histogram})? _visMacd;
  List<double> _visAtr = const [];
  ({List<double> k, List<double> d})? _visStoch;
  int _indBuiltRev = -1;
  Set<String>? _indBuiltKeys;
  List<HyperliquidCandle>? _indSyncedCandles;

  /// Live endpoint pulse ring for line mode — same 1600ms loop as the
  /// Polymarket chart. Runs only while live + line mode + motion allowed.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  /// Timeframe morph (line mode): old closes tween into the new window's
  /// closes over 280ms easeOutCubic once the new data lands.
  late final AnimationController _morph = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  late final Animation<double> _morphCurve = CurvedAnimation(
    parent: _morph,
    curve: Curves.easeOutCubic,
  );

  List<double>? _pendingMorphFrom;
  List<double>? _morphFromRs;
  List<double>? _morphToRs;
  List<double>? _morphTargetRaw;

  bool get _morphActive => _morphFromRs != null && _morph.value < 1.0;

  @override
  void initState() {
    super.initState();
    _morph.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _morphFromRs = null;
        _morphToRs = null;
        _morphTargetRaw = null;
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.of(context).disableAnimations;
  }

  @override
  void dispose() {
    _fillTipTimer?.cancel();
    _pulse.dispose();
    _morph.dispose();
    super.dispose();
  }

  /// Crosshair scrub at [dx] (outside editing mode it starts with a long
  /// press, TradingView style, so a plain drag can pan the chart).
  void _scrubAt(double dx, double chartWidth, int dataLen) {
    if (dataLen == 0) return;
    // A scrub takes over the plot: the marker tooltip gets out of its way.
    _dismissFillTip();
    final x = dx.clamp(0.0, chartWidth);
    final idx = (x / chartWidth * dataLen).floor().clamp(0, dataLen - 1);
    if (idx != _touchIndex) {
      // Throttled to ~10/s — an un-throttled selectionClick per index
      // change buzzes continuously on a fast scrub across dense candles.
      final now = DateTime.now();
      if (now.difference(_lastHaptic).inMilliseconds > 100) {
        HapticFeedback.selectionClick();
        _lastHaptic = now;
      }
      setState(() => _touchIndex = idx);
    }
  }

  // ─────────────────────── normal-mode drag ───────────────────────────

  /// One finger dragging outside editing mode: an order-line tag drags
  /// that line (set up in [_onTradePanDown]); the left price strip scales
  /// the axis on a vertical drag; anything else pans the chart in time.
  void _onNormalPanStart(DragStartDetails d, Size size) {
    if (_tradeDrag != null) return;
    _dismissFillTip();
    final pos = d.localPosition;
    final priceH = _hlPriceAreaHeight(size.height, widget.showVolume);
    final total = widget.candles.length;
    _gestureStart = pos;
    _axisCandidate =
        pos.dx <= _axisStripWidth && pos.dy <= priceH && _shownDomain != null;
    _panningView = !_axisCandidate;
    _panStartX = pos.dx;
    _panStartOffset = _viewEndOffset;
    _panBars = math.min(_effectiveViewBars ?? total, total);
  }

  void _onNormalPanUpdate(DragUpdateDetails d, Size size) {
    if (_tradeDrag != null) {
      _onTradePanUpdate(d);
      return;
    }
    if (_axisCandidate) {
      final delta = d.localPosition - _gestureStart;
      _axisCandidate = false;
      if (delta.dy.abs() > delta.dx.abs()) {
        setState(() {
          _axisDragging = true;
          _axisStartY = _gestureStart.dy;
          _axisStartDomain = _shownDomain;
        });
      } else {
        _panningView = true;
      }
    }
    if (_axisDragging) {
      _onAxisDrag(d.localPosition.dy, size);
    } else if (_panningView) {
      _onViewPanUpdate(d.localPosition.dx, size.width);
    }
  }

  void _onNormalPanEnd() {
    if (_tradeDrag != null) {
      _onTradePanEnd();
      return;
    }
    _panningView = false;
    _axisCandidate = false;
    if (_axisDragging) {
      setState(() {
        _axisDragging = false;
        _axisStartDomain = null;
      });
    }
  }

  // ─────────────────────── trade-line gestures ─────────────────────────

  ChartTradeLine? _tradeLineById(String id) {
    for (final l in widget.tradeLines) {
      if (l.id == id) return l;
    }
    return null;
  }

  /// Outside drawing mode a pan normally scrubs. A pan that starts on an
  /// editable trade line's tag drags that line instead; the tape and its
  /// price mapping are frozen for the gesture like a drawing drag.
  void _onTradePanDown(DragDownDetails d, Size size) {
    if (widget.tradeLines.isEmpty || widget.onTradeLineMoved == null) return;
    final hit = kuteHitTestTradeTags(_tradeHits, d.localPosition);
    if (hit == null) return;
    final line = _tradeLineById(hit.id);
    if (line == null || !line.editable) return;
    final geom = _drawingGeometry(size);
    if (geom == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _tradeDrag = line;
      _tradeDragGeom = geom;
      _drawingCandles = _tape;
    });
  }

  void _onTradePanUpdate(DragUpdateDetails d) {
    final geom = _tradeDragGeom;
    final line = _tradeDrag;
    if (geom == null || line == null) return;
    final y = d.localPosition.dy.clamp(0.0, geom.priceH).toDouble();
    final price = geom.priceForY(y);
    if (!price.isFinite || price <= 0) return;
    setState(() => _tradeDrag = line.withPrice(price));
  }

  void _onTradePanEnd() {
    final line = _tradeDrag;
    final original = line == null ? null : _tradeLineById(line.id);
    setState(() {
      _tradeDrag = null;
      _tradeDragGeom = null;
      _drawingCandles = null;
    });
    if (line == null || original == null) return;
    if ((line.price - original.price).abs() <= original.price * 1e-6) return;
    widget.onTradeLineMoved?.call(line.id, line.price);
  }

  void _onTradeTapUp(TapUpDetails d, Size size) {
    if (_isDoubleTap(d.localPosition) && !_autoScale) {
      _restoreAutoScale();
      return;
    }
    final hit = widget.tradeLines.isEmpty
        ? null
        : kuteHitTestTradeTags(_tradeHits, d.localPosition);
    if (hit != null && widget.onTradeLineTapped != null) {
      HapticFeedback.selectionClick();
      widget.onTradeLineTapped!(hit.id);
      return;
    }
    // A market signal's tag (a Predictions level, a macro date).
    final signal = widget.signals.isEmpty || widget.onSignalTapped == null
        ? null
        : kuteHitTestSignalTags(_signalHits, d.localPosition);
    if (signal != null) {
      HapticFeedback.selectionClick();
      widget.onSignalTapped!(signal.id);
      return;
    }
    // One of the user's own fill markers: open its tooltip (or close the
    // open one when the tap lands on empty plot).
    if (_onFillMarkerTap(d.localPosition, size)) return;
    // A drawing tapped outside drawing mode: hand its id to the host,
    // which opens Advanced with it selected, so editing a shape never
    // starts with hunting for the mode toggle.
    if (widget.drawings.isEmpty || widget.onDrawingSelected == null) return;
    final geom = _drawingGeometry(size);
    if (geom == null || d.localPosition.dy > geom.priceH) return;
    final drawing = kuteHitTestDrawings(widget.drawings, geom, d.localPosition);
    if (drawing == null) return;
    HapticFeedback.selectionClick();
    widget.onDrawingSelected!(drawing);
  }

  // ─────────────────────── drawing-mode gestures ───────────────────────

  static String _newDrawingId() =>
      DateTime.now().microsecondsSinceEpoch.toString();

  /// Chart-coordinate mapper for the drawings layer + gestures, built
  /// from the SAME price geometry the data painter uses. Null mid-morph
  /// (the morph line's x space is resampled) and on an empty tape.
  KuteDrawingGeometry? _drawingGeometry(
    Size size, {
    double? leadingClose,
    List<double>? morphSeries,
  }) {
    if (_dragGeometry != null) return _dragGeometry;
    final candles = _drawingCandles ?? _tape;
    if (candles.isEmpty) return null;
    if (morphSeries != null) return null;
    final geom = _hlPriceGeometry(
      candles: candles,
      renderAsLine: _asLine,
      showVolume: widget.showVolume,
      height: size.height,
      logScale: widget.logScale,
      leadingClose: _asLine ? leadingClose : null,
      domain: _shownDomain,
    );
    if (!identical(_geomTimesSource, candles)) {
      _geomTimesSource = candles;
      _geomTimes = [for (final k in candles) k.openTime.millisecondsSinceEpoch];
    }
    final times = _geomTimes!;
    var bucketMs = candles.last.closeTime.millisecondsSinceEpoch - times.last;
    if (bucketMs <= 0 && times.length >= 2) {
      bucketMs = times.last - times[times.length - 2];
    }
    if (bucketMs <= 0) bucketMs = 60000;
    // Log axis: the price⇄y mapping goes through ln/exp so drawings
    // stored in real prices stay glued to the log-mapped data.
    if (geom.log) {
      return KuteLogDrawingGeometry(
        timesMs: times,
        width: size.width,
        priceH: geom.priceH,
        loP: geom.loP,
        rangeP: geom.rangeP,
        bucketMs: bucketMs,
      );
    }
    return KuteDrawingGeometry(
      timesMs: times,
      width: size.width,
      priceH: geom.priceH,
      loP: geom.loP,
      rangeP: geom.rangeP,
      bucketMs: bucketMs,
    );
  }

  ChartDrawingPoint _pointAt(KuteDrawingGeometry geom, Offset pos) {
    final x = pos.dx.clamp(0.0, geom.width);
    final y = pos.dy.clamp(0.0, geom.priceH > 0 ? geom.priceH : 0.0);
    final candles = _drawingCandles ?? _tape;
    if (widget.magnet && candles.isNotEmpty && geom.width > 0) {
      final index = (x / geom.width * candles.length).floor().clamp(
            0,
            candles.length - 1,
          );
      final candle = candles[index];
      final prices = [
        candle.open,
        candle.high,
        candle.low,
        candle.close,
      ].where((price) => price.isFinite && price > 0).toList();
      if (prices.isNotEmpty) {
        prices.sort(
          (a, b) => (geom.yForPrice(a) - y).abs().compareTo(
                (geom.yForPrice(b) - y).abs(),
              ),
        );
        return ChartDrawingPoint(
          timeMs: candle.openTime.millisecondsSinceEpoch,
          price: prices.first,
        );
      }
    }
    return ChartDrawingPoint(
      timeMs: geom.timeForX(x),
      price: geom.priceForY(y),
    );
  }

  ChartDrawing? _selectedDrawing() {
    final id = widget.selectedDrawingId;
    if (id == null) return null;
    for (final d in widget.drawings) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// The drawings actually painted: mid-handle-drag, the edited copy
  /// replaces the original so the drag tracks the finger live.
  List<ChartDrawing> _effectiveDrawings() {
    final edited = _edited;
    if (edited == null) return widget.drawings;
    return [for (final d in widget.drawings) d.id == edited.id ? edited : d];
  }

  void _resetDrawingInteraction() {
    _draft = null;
    _edited = null;
    _dragPointIndex = -1;
    _dragGeometry = null;
    _drawingCandles = null;
    _dragStartPosition = null;
    _handleOffset = Offset.zero;
    _draggedOriginal = null;
    _draggingBody = false;
  }

  void _cancelDrawingGesture() {
    _panningView = false;
    if (_axisDragging) {
      setState(() {
        _axisDragging = false;
        _axisStartDomain = null;
      });
    }
    if (_dragGeometry == null && _draft == null && _edited == null) return;
    setState(_resetDrawingInteraction);
  }

  void _onDrawPanDown(DragDownDetails d, Size size) {
    final geom = _drawingGeometry(size);
    if (geom == null || d.localPosition.dy > geom.priceH) return;
    // Freeze the tape and its exact price/time mapping for this pointer.
    // Live ticks must not autoscale the chart underneath a dragged handle.
    setState(() {
      _dragGeometry = geom;
      _drawingCandles = _tape;
      _dragStartPosition = d.localPosition;
    });
  }

  void _onDrawTapUp(TapUpDetails d, Size size) {
    if (_isDoubleTap(d.localPosition) &&
        !_autoScale &&
        widget.armedTool == null) {
      _cancelDrawingGesture();
      _restoreAutoScale();
      return;
    }
    final geom = _drawingGeometry(size);
    final point = geom == null ? null : _pointAt(geom, d.localPosition);
    _cancelDrawingGesture();
    if (geom == null || point == null || d.localPosition.dy > geom.priceH) {
      return;
    }
    final pos = d.localPosition;
    final tool = widget.armedTool;
    if (tool == ChartDrawingTool.text) {
      widget.onTextRequested?.call(point);
      return;
    }
    if (tool != null && chartDrawingPointCount(tool) == 1) {
      final drawing = ChartDrawing(
        id: _newDrawingId(),
        tool: tool,
        points: [point],
        colorValue: widget.armedColorValue,
      );
      if (!drawing.isValid) return;
      HapticFeedback.selectionClick();
      widget.onDrawingPlaced?.call(drawing);
      return;
    }
    if (tool != null) return;
    // Select mode: a fill marker under the finger opens its tooltip
    // instead of (de)selecting drawings.
    if (_onFillMarkerTap(pos, size)) return;
    final hit = kuteHitTestDrawings(widget.drawings, geom, pos);
    if (hit != widget.selectedDrawingId) {
      if (hit != null) HapticFeedback.selectionClick();
      widget.onDrawingSelected?.call(hit);
    }
  }

  void _onDrawPanStart(DragStartDetails d, Size size) {
    _dismissFillTip();
    final geom = _dragGeometry;
    if (geom == null) return;
    // onPanStart normally arrives only after touch slop. Use the original
    // down point so short lines and small handles do not jump or miss.
    final pos = _dragStartPosition ?? d.localPosition;
    final tool = widget.armedTool;
    if (tool == ChartDrawingTool.text) return;
    if (tool != null) {
      final point = _pointAt(geom, pos);
      // One-anchor tools place on tap; a drag still previews them at the
      // finger. Two- and three-anchor tools drag out their second anchor;
      // the third (channel offset, stop level) is derived on release and
      // adjusted by its handle afterwards.
      final count = chartDrawingPointCount(tool);
      setState(
        () => _draft = ChartDrawing(
          id: _newDrawingId(),
          tool: tool,
          points: [for (var i = 0; i < count; i++) point],
          colorValue: widget.armedColorValue,
        ),
      );
      return;
    }
    var selected = _selectedDrawing();
    var handle =
        selected == null ? null : kuteHitTestHandle(selected, geom, pos);
    if (handle == null) {
      final hit = kuteHitTestDrawings(widget.drawings, geom, pos);
      if (hit == null && pos.dx <= _axisStripWidth) {
        // The price axis (left label strip): a vertical drag scales it
        // by hand and turns autoscale off.
        final start = _shownDomain ??
            (
              lo: geom.loP,
              hi: geom.loP + geom.rangeP,
              log: geom is KuteLogDrawingGeometry
            );
        setState(() {
          _resetDrawingInteraction();
          _axisDragging = true;
          _axisStartY = pos.dy;
          _axisStartDomain = start;
        });
        return;
      }
      if (hit == null) {
        // Empty chart under the finger: scroll the viewport. The frozen
        // tape and geometry of the drag are released so the chart moves
        // with the finger.
        setState(() {
          _resetDrawingInteraction();
          _panningView = true;
          _panStartX = pos.dx;
          _panStartOffset = _viewEndOffset;
          _panBars = math.min(_effectiveViewBars ?? widget.candles.length,
              widget.candles.length);
        });
        return;
      }
      selected = widget.drawings.firstWhere((drawing) => drawing.id == hit);
      handle = kuteHitTestHandle(selected, geom, pos);
    }
    if (selected == null) return;
    final drawing = selected;
    setState(() {
      _edited = drawing;
      _draggedOriginal = drawing;
      _dragPointIndex = handle ?? -1;
      _draggingBody = handle == null;
      _handleOffset = handle == null
          ? Offset.zero
          : geom.offsetFor(drawing.points[handle]) - pos;
    });
    if (drawing.id != widget.selectedDrawingId) {
      widget.onDrawingSelected?.call(drawing.id);
    }
  }

  void _onDrawPanUpdate(DragUpdateDetails d, Size size) {
    if (_axisDragging) {
      _onAxisDrag(d.localPosition.dy, size);
      return;
    }
    if (_panningView) {
      _onViewPanUpdate(d.localPosition.dx, size.width);
      return;
    }
    final geom = _dragGeometry;
    if (geom == null) return;
    if (_draft != null) {
      final point = _pointAt(geom, d.localPosition);
      final draft = _draft!;
      final index = chartDrawingPointCount(draft.tool) == 1 ? 0 : 1;
      setState(() => _draft = _seedThirdAnchor(draft.withPoint(index, point)));
    } else if (_edited != null && _draggingBody) {
      var delta = d.localPosition - _dragStartPosition!;
      final offsets = [
        for (final point in _draggedOriginal!.points) geom.offsetFor(point),
      ];
      final left = offsets.map((p) => p.dx).reduce(math.min);
      final right = offsets.map((p) => p.dx).reduce(math.max);
      final top = offsets.map((p) => p.dy).reduce(math.min);
      final bottom = offsets.map((p) => p.dy).reduce(math.max);
      // Keep a visible shape intact at the plot edge; clamping each anchor
      // separately would squash the shape as the finger moves past the edge.
      delta = Offset(
        left >= 0 && right <= geom.width
            ? delta.dx.clamp(-left, geom.width - right)
            : delta.dx,
        top >= 0 && bottom <= geom.priceH
            ? delta.dy.clamp(-top, geom.priceH - bottom)
            : delta.dy,
      );
      setState(
        () => _edited = _draggedOriginal!.copyWith(
          points: [
            for (final offset in offsets)
              ChartDrawingPoint(
                timeMs: geom.timeForX(offset.dx + delta.dx),
                price: geom.priceForY(offset.dy + delta.dy),
              ),
          ],
        ),
      );
    } else if (_edited != null && _dragPointIndex >= 0) {
      final point = _pointAt(geom, d.localPosition + _handleOffset);
      setState(() => _edited = _edited!.withPoint(_dragPointIndex, point));
    }
  }

  /// The third anchor a drag cannot express, derived from the first two:
  /// a channel's parallel rail sits below the base by a tenth of the
  /// base's own move (or 1% of price on a flat base); a position's stop
  /// mirrors the target through the entry, so it starts at 1:1.
  ChartDrawing _seedThirdAnchor(ChartDrawing draft) {
    if (chartDrawingPointCount(draft.tool) < 3) return draft;
    final a = draft.points[0], b = draft.points[1];
    switch (draft.tool) {
      case ChartDrawingTool.parallelChannel:
        final move = (b.price - a.price).abs();
        final offset = move > 0 ? move * 0.35 : a.price * 0.01;
        return draft.withPoint(
            2, ChartDrawingPoint(timeMs: b.timeMs, price: b.price - offset));
      case ChartDrawingTool.longPosition:
      case ChartDrawingTool.shortPosition:
        final stop = a.price - (b.price - a.price);
        return draft.withPoint(
            2,
            ChartDrawingPoint(
                timeMs: a.timeMs, price: stop > 0 ? stop : a.price * 0.5));
      default:
        return draft;
    }
  }

  void _onDrawPanEnd(Size size) {
    if (_axisDragging) {
      setState(() {
        _axisDragging = false;
        _axisStartDomain = null;
      });
      return;
    }
    if (_panningView) {
      _panningView = false;
      return;
    }
    final draft = _draft;
    final edited = _edited;
    final geom = _dragGeometry;
    _cancelDrawingGesture();
    if (draft != null) {
      if (geom == null || !draft.isValid) return;
      if (chartDrawingPointCount(draft.tool) >= 2) {
        final a = geom.offsetFor(draft.points[0]);
        final b = geom.offsetFor(draft.points[1]);
        if ((a - b).distance < 8) return;
      }
      HapticFeedback.selectionClick();
      widget.onDrawingPlaced?.call(draft);
    } else if (edited != null && edited.isValid) {
      widget.onDrawingUpdated?.call(edited);
    }
  }

  @override
  void didUpdateWidget(covariant HlCandlestickChart old) {
    super.didUpdateWidget(old);
    if (widget.marketKey != old.marketKey) {
      _resetDrawingInteraction();
      _fillTipTimer?.cancel();
      _fillTipTimer = null;
      _fillTip = const {};
      _touchIndex = null;
      _geomTimes = null;
      _geomTimesSource = null;
      _indSyncedCandles = null;
      _pendingMorphFrom = null;
      _morphFromRs = null;
      _morphToRs = null;
      _morphTargetRaw = null;
      _morph.value = 1;
      _sliceKey = null;
      _resetScale(jump: true);
      _resetViewport();
      return;
    }
    if (widget.logScale != old.logScale) _resetScale(jump: true);
    if (widget.drawingMode != old.drawingMode && !widget.drawingMode) {
      // Leaving editing mode keeps the view the user panned to.
      _pointers.clear();
      _pinching = false;
      _panningView = false;
    }
    if (widget.morphKey != old.morphKey) {
      // Another interval opens on its newest bars; a style change keeps
      // the view, like TradingView.
      _resetViewport();
    } else if (_viewEndOffset > 0 &&
        !identical(widget.candles, old.candles) &&
        old.candles.isNotEmpty &&
        widget.candles.isNotEmpty) {
      // Scrolled back in time: new live bars must not drag the view
      // along, so the offset from the newest bar grows with them.
      final oldLast = old.candles.last.openTime.millisecondsSinceEpoch;
      var added = 0;
      for (var i = widget.candles.length - 1;
          i >= 0 &&
              widget.candles[i].openTime.millisecondsSinceEpoch > oldLast;
          i--) {
        added++;
      }
      if (added > 0 && added < widget.candles.length) {
        _viewEndOffset += added;
      }
    }
    if (_touchIndex != null && _touchIndex! >= _tape.length) {
      _touchIndex = null;
    }
    if (widget.drawingMode != old.drawingMode ||
        widget.armedTool != old.armedTool ||
        widget.morphKey != old.morphKey ||
        _asLine != _isLine(old) ||
        widget.style != old.style ||
        widget.logScale != old.logScale ||
        widget.showVolume != old.showVolume ||
        widget.magnet != old.magnet ||
        widget.height != old.height) {
      _touchIndex = null;
      _resetDrawingInteraction();
    }
    if (widget.drawingMode) {
      _pendingMorphFrom = null;
      _morph.value = 1;
      return;
    }
    // Toggling line ⇄ candles mid-morph: finish the morph immediately —
    // the candle painter has no morph representation.
    if (_asLine != _isLine(old) && _morphActive) {
      _morph.value = 1.0;
    }
    // Arm the timeframe morph with the outgoing window's shape. The new
    // window's data may still be loading (the host keeps the old candles
    // up meanwhile) — the tween starts when fresh candles actually land.
    // Only a chart showing its whole tape morphs: the tween runs over the
    // full series, which a zoomed or panned view does not show.
    if (widget.morphKey != null &&
        widget.morphKey != old.morphKey &&
        _effectiveViewBars == null &&
        old.candles.length >= 2) {
      _pendingMorphFrom = [for (final k in old.candles) k.close];
    }
    if (!identical(widget.candles, old.candles) && widget.candles.length >= 2) {
      final closes = [for (final k in widget.candles) k.close];
      if (_pendingMorphFrom != null) {
        if (_asLine &&
            !_reduceMotion &&
            !kuteSameSeries(_pendingMorphFrom!, closes)) {
          final n = kuteMorphSampleCount(
            _pendingMorphFrom!.length,
            closes.length,
          );
          _morphFromRs = kuteResampleSeries(_pendingMorphFrom!, n);
          _morphToRs = kuteResampleSeries(closes, n);
          _morphTargetRaw = closes;
          _morph.forward(from: 0);
        }
        _pendingMorphFrom = null;
      } else if (_morphActive &&
          _morphTargetRaw != null &&
          !kuteSameSeries(_morphTargetRaw!, closes)) {
        // Live tick mid-morph: retarget the tween instead of fighting it.
        _morphToRs = kuteResampleSeries(closes, _morphToRs!.length);
        _morphTargetRaw = closes;
      }
    }
  }

  /// Indicators are computed over the WHOLE loaded tape (so a panned
  /// view never restarts their warm-up at its left edge) and then sliced
  /// to the bars on screen; the slices are what every layer paints and
  /// what the panes autoscale to. VWAP stays a displayed-window measure.
  void _syncIndicators(List<HyperliquidCandle> visible) {
    _syncFullIndicators(_styledFull);
    // A frozen gesture keeps the slices it started with, in step with
    // its frozen candles.
    if (_drawingCandles != null) return;
    _sliceIndicators(visible, _tapeStart);
  }

  /// (Re)build the indicator series for the active [widget.indicators]
  /// over [candles] (the full tape). A no-op unless the closes content
  /// (engine revision) or the set identity changed, so live rebuilds
  /// reuse the exact same lists.
  void _syncFullIndicators(List<HyperliquidCandle> candles) {
    final wanted = widget.indicators;
    if (identical(_indSyncedCandles, candles) &&
        identical(_indBuiltKeys, wanted)) {
      return;
    }
    _indSyncedCandles = candles;
    const candleKeys = {'vwap', 'rsi', 'macd', 'atr', 'stoch', 'volma'};
    final active = wanted.contains('ma') ||
        wanted.contains('ema') ||
        wanted.contains('bb') ||
        wanted.any(candleKeys.contains);
    if (!active || candles.isEmpty) {
      _indOverlays = const [];
      _indBand = null;
      _rsi = const [];
      _volumeMa = const [];
      _macd = null;
      _atr = const [];
      _stoch = null;
      _indBuiltKeys = wanted;
      _indStamp++;
      return;
    }
    _indEngine.sync([for (final k in candles) k.close]);
    if (!wanted.any(candleKeys.contains) &&
        _indEngine.revision == _indBuiltRev &&
        identical(_indBuiltKeys, wanted)) {
      return;
    }
    final overlays = <KuteIndicatorOverlay>[];
    KuteIndicatorBand? band;
    if (wanted.contains('bb')) {
      final b = _indEngine.bollinger(20, 2);
      band = KuteIndicatorBand(
        upper: b.upper,
        lower: b.lower,
        color: kuteIndBbColor,
      );
      overlays
        ..add(KuteIndicatorOverlay(values: b.upper, color: kuteIndBbColor))
        ..add(KuteIndicatorOverlay(values: b.middle, color: kuteIndBbColor))
        ..add(KuteIndicatorOverlay(values: b.lower, color: kuteIndBbColor));
    }
    if (wanted.contains('ma')) {
      overlays
        ..add(
          KuteIndicatorOverlay(
            values: _indEngine.sma(20),
            color: kuteIndSma20Color,
          ),
        )
        ..add(
          KuteIndicatorOverlay(
            values: _indEngine.sma(50),
            color: kuteIndSma50Color,
          ),
        );
    }
    if (wanted.contains('ema')) {
      overlays
        ..add(
          KuteIndicatorOverlay(
            values: _indEngine.ema(9),
            color: kuteIndEma9Color,
          ),
        )
        ..add(
          KuteIndicatorOverlay(
            values: _indEngine.ema(21),
            color: kuteIndEma21Color,
          ),
        );
    }
    _rsi = wanted.contains('rsi') ? hlWilderRsi(candles) : const [];
    _volumeMa = wanted.contains('volma') ? hlVolumeSma(candles) : const [];
    _macd = wanted.contains('macd') ? hlMacd(candles) : null;
    _atr = wanted.contains('atr') ? hlAtr(candles) : const [];
    _stoch = wanted.contains('stoch') ? hlStochastic(candles) : null;
    _indOverlays = overlays;
    _indBand = band;
    _indBuiltRev = _indEngine.revision;
    _indBuiltKeys = wanted;
    _indStamp++;
  }

  /// Cut the full-tape indicator series down to bars [start, start +
  /// visible.length). Rebuilt only when the series or the window change.
  void _sliceIndicators(List<HyperliquidCandle> visible, int start) {
    final end = start + visible.length;
    final wantVwap = widget.indicators.contains('vwap');
    final key = (_indStamp, start, end, wantVwap ? visible : null);
    if (key == _sliceKey) return;
    _sliceKey = key;
    List<double> cut(List<double> v) {
      if (start == 0 && end == v.length) return v;
      if (start >= v.length) return const [];
      return v.sublist(start, math.min(end, v.length));
    }

    _visOverlays = [
      for (final o in _indOverlays)
        KuteIndicatorOverlay(
          values: cut(o.values),
          color: o.color,
          strokeWidth: o.strokeWidth,
        ),
      if (wantVwap && visible.isNotEmpty)
        KuteIndicatorOverlay(
          values: hlWindowVwap(visible),
          color: const Color(0xFF14B8A6),
        ),
    ];
    final band = _indBand;
    _visBand = band == null
        ? null
        : KuteIndicatorBand(
            upper: cut(band.upper),
            lower: cut(band.lower),
            color: band.color,
          );
    _visRsi = cut(_rsi);
    _visVolumeMa = cut(_volumeMa);
    final macd = _macd;
    _visMacd = macd == null
        ? null
        : (
            macd: cut(macd.macd),
            signal: cut(macd.signal),
            histogram: cut(macd.histogram),
          );
    _visAtr = cut(_atr);
    final stoch = _stoch;
    _visStoch = stoch == null ? null : (k: cut(stoch.k), d: cut(stoch.d));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final candles = _drawingCandles ?? _tape;
    _reduceMotion = MediaQuery.of(context).disableAnimations;
    _syncIndicators(candles);

    if (candles.isEmpty) {
      if (_pulse.isAnimating) _pulse.stop();
      return SizedBox(
        height: (widget.height + 34).h,
        child: Center(
          child: Text(
            context.l10n.chartNoData,
            style: TextStyle(color: c.textTertiary, fontSize: 13.sp),
          ),
        ),
      );
    }

    final ti = _touchIndex;
    final scrubbing = ti != null && ti >= 0 && ti < candles.length;

    // Price scale target for the bars on screen. The painted domain
    // glides to it (180ms) so pans, pinches and new highs never jump;
    // a manual drag, a frozen gesture or Reduce Motion apply it at once.
    final scaleTarget = _scaleTarget(candles);
    final scaleInstant =
        _reduceMotion || _axisDragging || _frozenDomain != null;

    final span = _visibleSpan(candles);
    if (span != _reportedSpan && _drawingCandles == null) {
      _reportedSpan = span;
      final report = widget.onVisibleSpanChanged;
      if (report != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _reportedSpan == span) report(span);
        });
      }
    }
    // The idle summary names the window: the host's range for a line
    // chart, the visible span for a candle chart.
    // A zoomed or panned view names its own span, not the range.
    final summaryLabel =
        (identical(candles, _styledFull) ? widget.timeframeLabel : null) ??
            _spanLabel(span);

    final first = candles.first.close;
    final last = candles.last.close;
    final changeUp = last >= first;
    final accent = changeUp ? AppColors.marketUp : AppColors.marketDown;
    final isDark = context.isDark;

    // The live-pulse loop is decorative and only meaningful behind the
    // line-mode endpoint dot — keep it off everywhere else.
    final wantPulse =
        widget.isLive && _asLine && _atLiveEdge && !_reduceMotion;
    if (wantPulse && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (!wantPulse && _pulse.isAnimating) {
      _pulse.stop();
    }

    // The scrub card is written here, never inside a paint pass: the
    // price, its change since the first bar on screen, the time and a
    // "You bought here" style hint when the bar holds one of the user's
    // own fills.
    KuteScrubCardData? scrubCard;
    if (scrubbing) {
      final close = candles[ti].close;
      final hint = _fillHintForIndex(candles, ti);
      final pct = ti == 0 || first <= 0 ? null : (close - first) / first * 100;
      scrubCard = KuteScrubCardData(
        value: formatHlPrice(close, decimalCap: widget.decimalCap),
        change: pct == null ? null : kuteSignedPercent(pct),
        changeSign: pct == null ? 0 : kutePercentDirection(pct),
        time: kuteChartDayTime(
            candles[ti].closeTime.toLocal(), kuteChartLocale(context)),
        details: [if (hint != null) hint],
      );
    }

    // ── Scrub / summary label row (with the LIVE dot) ─────────────────
    final summaryRow =
        SizedBox(
          height: 34.h,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The scrubbed bar is written on the scrub card alone; the
              // row keeps the change over the window meanwhile.
              Expanded(
                child: (candles.length >= 2 && first > 0)
                        ? Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              // The Predictions chart's words for it,
                              // in the app's language.
                              summaryLabel == null
                                  ? formatHlPct((last - first) / first)
                                  : context.l10n.polyChartChangePast(
                                      formatHlPct((last - first) / first),
                                      summaryLabel.toLowerCase()),
                              style: TextStyle(
                                color: accent,
                                fontSize: 13.sp,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
              ),
              if (widget.isLive)
                Padding(
                  padding: EdgeInsets.only(top: 2.h),
                  child: const HlLiveDot(),
                ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showSummary && !widget.summaryBelow) ...[
          summaryRow,
          SizedBox(height: 4.h),
        ],

        // ── Chart ─────────────────────────────────────────────────────
        // AnimatedContainer so the Advanced-mode height expansion eases
        // (~250ms) instead of snapping; reduce-motion renders instantly.
        _plotBox(AnimatedContainer(
          duration: (_reduceMotion || widget.drawingMode)
              ? Duration.zero
              : const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          height: widget.fillHeight ? null : widget.height.h,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final chartSize = Size(w, constraints.maxHeight);
              final drawing = widget.drawingMode;
              return Listener(
                // Flutter reports a canceled, already-accepted pan as onPanEnd.
                // Discard first at the raw pointer boundary so it cannot commit.
                onPointerCancel: (e) {
                  _onPointerUp(e.pointer);
                  if (drawing) _cancelDrawingGesture();
                },
                // Raw pointers feed the two-finger pinch; the gesture
                // detector below keeps every one-finger job.
                onPointerDown: _onPointerDown,
                onPointerMove: (e) => _onPointerMove(e, w),
                onPointerUp: (e) => _onPointerUp(e.pointer),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  dragStartBehavior: DragStartBehavior.down,
                  onPanDown: (d) {
                    if (_pinching) return;
                    drawing
                        ? _onDrawPanDown(d, chartSize)
                        : _onTradePanDown(d, chartSize);
                  },
                  onTapUp: (d) {
                    if (_pinching) return;
                    drawing
                        ? _onDrawTapUp(d, chartSize)
                        : _onTradeTapUp(d, chartSize);
                  },
                  onPanStart: (d) {
                    if (_pinching) return;
                    drawing
                        ? _onDrawPanStart(d, chartSize)
                        : _onNormalPanStart(d, chartSize);
                  },
                  onPanUpdate: (d) {
                    if (_pinching) return;
                    drawing
                        ? _onDrawPanUpdate(d, chartSize)
                        : _onNormalPanUpdate(d, chartSize);
                  },
                  onPanEnd: (_) {
                    if (_pinching) return;
                    drawing ? _onDrawPanEnd(chartSize) : _onNormalPanEnd();
                  },
                  onPanCancel: () {
                    if (_pinching) return;
                    drawing ? _cancelDrawingGesture() : _onNormalPanEnd();
                  },
                  // Outside editing mode the crosshair is a long press
                  // (then slide), so a plain drag pans and two fingers
                  // zoom without fighting the scrub.
                  onLongPressStart: drawing
                      ? null
                      : (d) {
                          if (_pinching) return;
                          HapticFeedback.selectionClick();
                          _scrubAt(d.localPosition.dx, w, candles.length);
                        },
                  onLongPressMoveUpdate: drawing
                      ? null
                      : (d) {
                          if (_pinching) return;
                          _scrubAt(d.localPosition.dx, w, candles.length);
                        },
                  onLongPressEnd: drawing
                      ? null
                      : (_) => setState(() => _touchIndex = null),
                  onLongPressCancel: drawing
                      ? null
                      : () {
                          if (_touchIndex != null) {
                            setState(() => _touchIndex = null);
                          }
                        },
                  // The price domain glides to each new autoscale target
                  // (see scaleTarget above). Inside it, live-tick endpoint
                  // smoothing (line mode): the tween is keyed on the
                  // leading close, so each WS tick eases the endpoint to
                  // its new position over 250ms.
                  child: TweenAnimationBuilder<Offset>(
                    key: ValueKey((_scaleEpoch, scaleTarget.log)),
                    tween: Tween<Offset>(
                      begin: Offset(scaleTarget.lo, scaleTarget.hi),
                      end: Offset(scaleTarget.lo, scaleTarget.hi),
                    ),
                    duration: scaleInstant
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    builder: (context, scaleValue, _) =>
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: last, end: last),
                    duration: (_reduceMotion || widget.drawingMode || !_asLine)
                        ? Duration.zero
                        : const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    builder: (context, lead, _) => AnimatedBuilder(
                      animation: _morph,
                      builder: (context, __) {
                        // The domain every layer of this frame maps
                        // through; gestures read it back.
                        final HlPriceDomain domain = (
                          lo: scaleValue.dx,
                          hi: scaleValue.dy,
                          log: scaleTarget.log,
                        );
                        _shownDomain = domain;
                        final morphing = _morphActive && _asLine;
                        final morphSeries = morphing
                            ? kuteLerpSeries(
                                _morphFromRs!,
                                _morphToRs!,
                                _morphCurve.value,
                              )
                            : null;
                        final leadingClose =
                            (_asLine && !morphing) ? lead : null;
                        return Stack(
                          children: [
                            Positioned.fill(
                              child: RepaintBoundary(
                                child: CustomPaint(
                                  painter: _HlCandlePainter(
                                    candles: candles,
                                    upColor: AppColors.marketUp,
                                    downColor: AppColors.marketDown,
                                    gridColor: c.border,
                                    labelBg:
                                        isDark ? Colors.black : Colors.white,
                                    labelFg: c.textPrimary,
                                    decimalCap: widget.decimalCap,
                                    showVolume: widget.showVolume,
                                    renderAsLine: _asLine,
                                    fills: widget.fills,
                                    entryPx: widget.entryPx,
                                    entryIsLong: widget.entryIsLong,
                                    leadingClose: leadingClose,
                                    morphSeries: morphSeries,
                                    overlays: _visOverlays,
                                    band: _visBand,
                                    logScale: widget.logScale,
                                    style: widget.style,
                                    volumeMa: _visVolumeMa,
                                    domain: domain,
                                  ),
                                ),
                              ),
                            ),
                            // ── Price scale (left-edge labels + faint
                            // hairlines). Always on in Advanced mode; outside
                            // it, it rides the crosshair's 120ms fade while
                            // the user scrubs. Painted INSIDE the plot so the
                            // shared price geometry never shifts.
                            Positioned.fill(
                              child: IgnorePointer(
                                child: AnimatedOpacity(
                                  opacity: (widget.drawingMode ||
                                          scrubbing ||
                                          !_autoScale ||
                                          _axisDragging)
                                      ? 1.0
                                      : 0.0,
                                  duration: _reduceMotion
                                      ? Duration.zero
                                      : const Duration(milliseconds: 120),
                                  curve: Curves.easeOut,
                                  child: RepaintBoundary(
                                    child: CustomPaint(
                                      size: Size.infinite,
                                      painter: _HlPriceScalePainter(
                                        candles: candles,
                                        renderAsLine: _asLine,
                                        showVolume: widget.showVolume,
                                        logScale: widget.logScale,
                                        leadingClose: leadingClose,
                                        morphSeries: morphSeries,
                                        decimalCap: widget.decimalCap,
                                        labelColor: c.textTertiary,
                                        hairlineColor: c.textPrimary,
                                        domain: domain,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // ── User drawings (trendlines/levels/rays/rects) —
                            // above the data, below the pulse + crosshair.
                            // Mounted only when there is something to show, so
                            // the common no-drawings case adds zero layers.
                            if (widget.drawings.isNotEmpty ||
                                _draft != null ||
                                _edited != null)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: RepaintBoundary(
                                    child: CustomPaint(
                                      painter: KuteChartDrawingsPainter(
                                        drawings: _effectiveDrawings(),
                                        draft: _draft,
                                        selectedId: widget.drawingMode
                                            ? widget.selectedDrawingId
                                            : null,
                                        neutralColor: c.textSecondary,
                                        handleCore: isDark
                                            ? Colors.black
                                            : Colors.white,
                                        resolveGeometry: (size) =>
                                            _drawingGeometry(
                                          size,
                                          leadingClose: leadingClose,
                                          morphSeries: morphSeries,
                                        ),
                                        repaintKey: (
                                          candles.length,
                                          candles.first.openTime
                                              .millisecondsSinceEpoch,
                                          last,
                                          leadingClose,
                                          morphSeries != null,
                                          _asLine,
                                          widget.showVolume,
                                          widget.logScale,
                                          isDark,
                                          domain,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            // ── Position + working orders: tagged price
                            // lines, above drawings, below the crosshair.
                            if (widget.tradeLines.isNotEmpty ||
                                _tradeDrag != null)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: RepaintBoundary(
                                    child: CustomPaint(
                                      painter: KuteChartTradeLinesPainter(
                                        lines: widget.tradeLines,
                                        dragging: _tradeDrag,
                                        hits: _tradeHits,
                                        palette: ChartTradeLinePalette(
                                          up: AppColors.marketUp,
                                          down: AppColors.marketDown,
                                          warning: AppColors.warning,
                                          neutral: c.textSecondary,
                                          tagBackground: isDark
                                              ? Colors.black
                                              : Colors.white,
                                          tagText: isDark
                                              ? Colors.black
                                              : Colors.white,
                                        ),
                                        // One format for every tag: the
                                        // decimals of the price now.
                                        formatPrice: (p) => formatHlPriceLike(
                                            p, candles.last.close,
                                            decimalCap: widget.decimalCap),
                                        resolveGeometry: (size) =>
                                            _tradeDragGeom ??
                                            _drawingGeometry(
                                              size,
                                              leadingClose: leadingClose,
                                              morphSeries: morphSeries,
                                            ),
                                        latestTags: (size, geom) =>
                                            _latestTags(geom, candles,
                                                leadingClose, morphSeries),
                                        repaintKey: (
                                          candles.length,
                                          candles.first.openTime
                                              .millisecondsSinceEpoch,
                                          last,
                                          leadingClose,
                                          morphSeries != null,
                                          _asLine,
                                          widget.showVolume,
                                          widget.logScale,
                                          isDark,
                                          domain,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            // ── Market signals (off unless the host hands
                            // some in): quiet levels, dates, rings and a
                            // caption, above the trade lines.
                            if (!widget.signals.isEmpty)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: RepaintBoundary(
                                    child: CustomPaint(
                                      painter: KuteChartSignalsPainter(
                                        signals: widget.signals,
                                        hits: _signalHits,
                                        palette: ChartSignalPalette(
                                          neutral: c.textSecondary,
                                          up: AppColors.marketUp,
                                          down: AppColors.marketDown,
                                          tagBackground: isDark
                                              ? Colors.black
                                              : Colors.white,
                                        ),
                                        resolveGeometry: (size) =>
                                            _drawingGeometry(
                                          size,
                                          leadingClose: leadingClose,
                                          morphSeries: morphSeries,
                                        ),
                                        repaintKey: (
                                          candles.length,
                                          candles.first.openTime
                                              .millisecondsSinceEpoch,
                                          last,
                                          leadingClose,
                                          morphSeries != null,
                                          _asLine,
                                          widget.showVolume,
                                          widget.logScale,
                                          isDark,
                                          domain,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            // ── Fill-marker tooltip: the tapped fill(s)
                            // as a clamped card anchored to the marker,
                            // above the trade lines and below the
                            // crosshair. Mounted only while one is open.
                            if (_fillTip.isNotEmpty && morphSeries == null)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: RepaintBoundary(
                                    child: CustomPaint(
                                      size: Size.infinite,
                                      painter: HlFillTooltipPainter(
                                        entries: _fillTipEntries(c),
                                        resolve: (size) => (
                                          markers: [
                                            for (final m in _fillMarkers(
                                                size, candles))
                                              if (_fillTip.contains(
                                                  hlFillIdentity(m.fill)))
                                                m
                                          ],
                                          plotBottom: _hlPriceGeometry(
                                            candles: candles,
                                            renderAsLine: _asLine,
                                            showVolume: widget.showVolume,
                                            height: size.height,
                                            logScale: widget.logScale,
                                          ).priceH,
                                        ),
                                        isDark: isDark,
                                        dividerColor: c.border,
                                        repaintKey: (
                                          _fillTip,
                                          candles.length,
                                          candles.first.openTime
                                              .millisecondsSinceEpoch,
                                          last,
                                          _asLine,
                                          widget.showVolume,
                                          widget.logScale,
                                          isDark,
                                          domain,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (_asLine && widget.isLive && _atLiveEdge)
                              Positioned.fill(
                                child: RepaintBoundary(
                                  child: CustomPaint(
                                    willChange: true,
                                    painter: KutePulseDecorPainter(
                                      pulse: _pulse,
                                      dataSets: [
                                        morphSeries ??
                                            [
                                              candles.first.close,
                                              leadingClose ?? last,
                                            ],
                                      ],
                                      colors: [accent],
                                      visible: !scrubbing,
                                      resolve: (size) => _pulsePoints(
                                        size,
                                        candles,
                                        accent,
                                        leadingClose,
                                        morphSeries,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            Positioned.fill(
                              child: KuteChartCrosshair(
                                resolve: !scrubbing
                                    ? null
                                    : (size) => _crosshairData(
                                          size,
                                          candles,
                                          ti,
                                          scrubCard,
                                        ),
                                repaintKey: (
                                  ti,
                                  candles.length,
                                  candles.first.openTime.millisecondsSinceEpoch,
                                  last,
                                  _asLine,
                                  widget.logScale,
                                  isDark,
                                  domain,
                                ),
                                isDark: isDark,
                                hairlineColor: c.border,
                                cardRightInset: kuteScrubCardTagGutter,
                              ),
                            ),
                            // ── Auto: the scale was set by hand; one tap
                            // (or a double tap on the plot) fits the
                            // visible bars again.
                            if (!_autoScale)
                              Positioned(
                                left: 4,
                                top: math.max(
                                  0.0,
                                  _hlPriceAreaHeight(chartSize.height,
                                          widget.showVolume) -
                                      30,
                                ),
                                child: HlAutoScalePill(
                                  onTap: _restoreAutoScale,
                                  background: isDark
                                      ? Colors.black.withValues(alpha: 0.85)
                                      : Colors.white.withValues(alpha: 0.9),
                                  border: c.border,
                                  text: c.textPrimary,
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                  ),
                ),
              );
            },
          ),
        )),
        // Editing shows where on the calendar the window sits: a few
        // dates under the plot at the bars they belong to, in a form
        // that suits the window's span.
        if (widget.drawingMode && candles.isNotEmpty) _dateAxis(c, candles),
        if (widget.indicators.contains('rsi'))
          _pane(
            c,
            context.l10n.chartRsiLabel,
            _HlPanePainter(
              series: [(_visRsi, kuteIndEma21Color)],
              levels: const [30, 70],
              fixedRange: (0, 100),
              selectedIndex: _touchIndex,
              labelColor: c.textTertiary,
            ),
          ),
        if (widget.indicators.contains('macd') && _visMacd != null)
          _pane(
            c,
            'MACD 12/26/9',
            _HlPanePainter(
              series: [
                (_visMacd!.macd, kuteIndEma9Color),
                (_visMacd!.signal, kuteIndSma50Color),
              ],
              histogram: _visMacd!.histogram,
              histogramUp: AppColors.marketUp,
              histogramDown: AppColors.marketDown,
              levels: const [0],
              selectedIndex: _touchIndex,
              labelColor: c.textTertiary,
            ),
          ),
        if (widget.indicators.contains('stoch') && _visStoch != null)
          _pane(
            c,
            'Stochastic 14/3/3',
            _HlPanePainter(
              series: [
                (_visStoch!.k, kuteIndEma9Color),
                (_visStoch!.d, kuteIndSma50Color),
              ],
              levels: const [20, 80],
              fixedRange: (0, 100),
              selectedIndex: _touchIndex,
              labelColor: c.textTertiary,
            ),
          ),
        if (widget.indicators.contains('atr'))
          _pane(
            c,
            'ATR 14',
            _HlPanePainter(
              series: [(_visAtr, kuteIndBbColor)],
              selectedIndex: _touchIndex,
              labelColor: c.textTertiary,
            ),
          ),
        if (widget.footer != null) widget.footer!,
        if (widget.showSummary && widget.summaryBelow) ...[
          SizedBox(height: 8.h),
          summaryRow,
        ],
      ],
    );
  }

  /// Time on screen: first visible bar's open to the last bar's close.
  static Duration _visibleSpan(List<HyperliquidCandle> candles) {
    if (candles.isEmpty) return Duration.zero;
    final lastK = candles.last;
    var bucket = lastK.closeTime.difference(lastK.openTime);
    if (bucket <= Duration.zero && candles.length >= 2) {
      bucket = lastK.openTime.difference(candles[candles.length - 2].openTime);
    }
    if (bucket < Duration.zero) bucket = Duration.zero;
    return lastK.openTime.difference(candles.first.openTime) + bucket;
  }

  /// Compact span name for the summary ("past 3d"); null under a minute.
  static String? _spanLabel(Duration span) {
    final minutes = span.inMinutes;
    if (minutes < 1) return null;
    if (minutes < 120) return '${minutes}m';
    final hours = span.inHours;
    if (hours < 48) return '${hours}h';
    final days = span.inDays;
    if (days < 60) return '${days}d';
    if (days < 730) return '${(days / 30.4).round()}mo';
    return '${(days / 365).round()}y';
  }

  /// The plot, flexed to the remaining height when [HlCandlestickChart.fillHeight].
  Widget _plotBox(Widget plot) =>
      widget.fillHeight ? Expanded(child: plot) : plot;

  /// Dates under the plot for the visible window. Four labels at fixed
  /// fractions of the width, each naming the bar under it; a window
  /// under two days shows the clock time, with the day on the first
  /// label, and a longer window shows dates.
  Widget _dateAxis(AppColorsExtension c, List<HyperliquidCandle> candles) {
    final span = candles.last.openTime.difference(candles.first.openTime);
    final intraday = span < const Duration(days: 2);
    final multiYear = span > const Duration(days: 365);
    final style = TextStyle(
      color: c.textTertiary,
      fontSize: 10.sp,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final locale = kuteChartLocale(context);
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final n = candles.length;
      final labels = <Widget>[];
      for (final fraction in const [0.08, 0.36, 0.64, 0.92]) {
        final index = (fraction * n).floor().clamp(0, n - 1);
        final time = candles[index].openTime.toLocal();
        final text = intraday
            ? (fraction == 0.08
                ? kuteChartDayTime(time, locale)
                : kuteChartClock(time, locale))
            : multiYear
                ? DateFormat.yMMM(locale).format(time)
                : DateFormat.MMMd(locale).format(time);
        // Bar centre; the label is centred on it and kept on screen.
        final x = ((index + 0.5) * w / n).clamp(0.0, w);
        labels.add(Positioned(
          left: (x - 40.w).clamp(0.0, w - 80.w),
          width: 80.w,
          top: 0,
          child: Text(text, textAlign: TextAlign.center, style: style),
        ));
      }
      return SizedBox(
        height: 16.h,
        width: double.infinity,
        child: Stack(clipBehavior: Clip.none, children: labels),
      );
    });
  }

  /// One indicator pane under the chart: a caption and a small painter.
  Widget _pane(AppColorsExtension c, String label, CustomPainter painter) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 8.h),
          Text(label,
              style: TextStyle(color: c.textSecondary, fontSize: 12.sp)),
          SizedBox(
            height: 76.h,
            width: double.infinity,
            child: CustomPaint(painter: painter),
          ),
        ],
      );

  List<KutePulsePoint> _pulsePoints(
    Size size,
    List<HyperliquidCandle> candles,
    Color color,
    double? leadingClose,
    List<double>? morphSeries,
  ) {
    if (candles.isEmpty) return const [];
    final geom = _hlPriceGeometry(
      candles: candles,
      renderAsLine: true,
      showVolume: widget.showVolume,
      height: size.height,
      logScale: widget.logScale,
      leadingClose: leadingClose,
      morphSeries: morphSeries,
      domain: _shownDomain,
    );
    final n = morphSeries?.length ?? candles.length;
    final slot = size.width / n;
    final v = morphSeries != null
        ? morphSeries.last
        : (leadingClose ?? candles.last.close);
    final y =
        geom.priceH * (1 - (_hlMapPrice(v, geom.log) - geom.loP) / geom.rangeP);
    return [KutePulsePoint(Offset((n - 0.5) * slot, y), color)];
  }

  /// "You bought/sold here" readout hint when the scrubbed bar's time
  /// bucket contains one of the user's own fills — the same bar the
  /// painter's binary search maps that fill's marker to. Cheap: one pass
  /// over the (small, rarely-changing) fills list, only while scrubbing.
  String? _fillHintForIndex(List<HyperliquidCandle> candles, int ti) {
    final fills = widget.fills;
    if (fills.isEmpty) return null;
    final n = candles.length;
    if (n < 2) return null;
    final openMs = candles[ti].openTime.millisecondsSinceEpoch;
    int endMs;
    if (ti < n - 1) {
      endMs = candles[ti + 1].openTime.millisecondsSinceEpoch;
    } else {
      var bucketMs = candles[ti].closeTime.millisecondsSinceEpoch - openMs;
      if (bucketMs <= 0) {
        bucketMs = openMs - candles[ti - 1].openTime.millisecondsSinceEpoch;
      }
      if (bucketMs <= 0) bucketMs = 1;
      endMs = openMs + bucketMs + 1;
    }
    var bought = false;
    var sold = false;
    for (final f in fills) {
      if (f.time < openMs || f.time >= endMs) continue;
      if (f.isBuy) {
        bought = true;
      } else {
        sold = true;
      }
      if (bought && sold) break;
    }
    final l10n = context.l10n;
    if (bought && sold) return l10n.hlChartYouTraded;
    if (bought) return l10n.hlChartYouBought;
    if (sold) return l10n.hlChartYouSold;
    return null;
  }

  /// The live price's tag as the data painter draws it (its line and its
  /// slot at the right edge): the trade tags keep off it.
  List<KuteLatestTag> _latestTags(
    KuteDrawingGeometry geom,
    List<HyperliquidCandle> candles,
    double? leadingClose,
    List<double>? morphSeries,
  ) {
    if (candles.isEmpty) return const [];
    final lastK = candles.last;
    final value = morphSeries != null && morphSeries.isNotEmpty
        ? morphSeries.last
        : (_asLine ? (leadingClose ?? lastK.close) : lastK.close);
    final y = geom.yForPrice(value);
    if (!y.isFinite) return const [];
    final ly = y.clamp(0.0, geom.priceH).toDouble();
    final tp = _HlCandlePainter._cachedTp(
      formatHlPrice(lastK.close, decimalCap: widget.decimalCap),
      Colors.white,
      10.5.sp,
      FontWeight.w800,
    );
    final h = tp.height + 2.5.h * 2;
    return [
      (
        y: ly,
        top: (ly - h / 2).clamp(0.0, math.max(0.0, geom.priceH - h)).toDouble(),
        height: h,
      ),
    ];
  }

  KuteCrosshairData? _crosshairData(
    Size size,
    List<HyperliquidCandle> candles,
    int ti,
    KuteScrubCardData? card,
  ) {
    if (ti < 0 || ti >= candles.length) return null;
    final geom = _hlPriceGeometry(
      candles: candles,
      renderAsLine: _asLine,
      showVolume: widget.showVolume,
      height: size.height,
      logScale: widget.logScale,
      domain: _shownDomain,
    );
    final slot = size.width / candles.length;
    final k = candles[ti];
    final up = k.close >= k.open;
    final color = up ? AppColors.marketUp : AppColors.marketDown;
    final y = geom.priceH *
        (1 - (_hlMapPrice(k.close, geom.log) - geom.loP) / geom.rangeP);
    return KuteCrosshairData(
      x: (ti + 0.5) * slot,
      dots: [
        KuteCrosshairDot(y: y.clamp(0.0, geom.priceH), color: color),
      ],
      plotBottom: geom.priceH,
      card: card,
    );
  }
}

/// The small "Auto" pill shown over the bottom left of the price area
/// while the scale is manual. Colours come from the host. Shared with the
/// Polymarket chart so both price scales restore the same way.
class HlAutoScalePill extends StatelessWidget {
  const HlAutoScalePill({
    super.key,
    required this.onTap,
    required this.background,
    required this.border,
    required this.text,
  });

  final VoidCallback onTap;
  final Color background;
  final Color border;
  final Color text;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 4.h),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(6.r),
          border: Border.all(color: border, width: 0.5),
        ),
        child: Text(
          'Auto',
          style: TextStyle(
            color: text,
            fontSize: 11.sp,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// Candlestick painter: high-low wick + open→close body per candle,
/// low-alpha volume bars along the bottom, a dashed last-price line with a
/// right-edge price tag, and the user's own fill markers. Line mode renders
/// through the shared chart engine (monotone cubic path, cached gradient
/// fill, 2.0 round-cap stroke, endpoint dot) and honours [morphSeries]
/// (timeframe tween) / [leadingClose] (live-tick endpoint easing). The
/// scrub crosshair lives in the shared KuteChartCrosshair layer, so this
/// canvas never repaints during a scrub. Prices are min–max normalized
/// across the highs/lows with a small vertical pad; grid-free per the
/// app's unified chart language.
class _HlCandlePainter extends CustomPainter {
  final List<HyperliquidCandle> candles;
  final Color upColor;
  final Color downColor;
  final Color gridColor;
  final Color labelBg;
  final Color labelFg;
  final int? decimalCap;
  final bool showVolume;
  final bool renderAsLine;
  final List<HlFill> fills;

  /// Open-position average entry price (null → no entry line) + its side.
  final double? entryPx;
  final bool entryIsLong;

  /// Line mode only: tweened leading close (live-tick smoothing). The
  /// last point of the line is drawn at this value; the price tag keeps
  /// the settled close.
  final double? leadingClose;

  /// Line mode only: the mid-morph series of an animated timeframe
  /// transition. When set, the line is drawn from these values (evenly
  /// spaced) instead of the candles; fill markers are skipped for the
  /// morph's ~280ms since their x mapping is bucket-based.
  final List<double>? morphSeries;

  /// Native indicator overlays (SMA/EMA/BB polylines, see
  /// kute_chart_indicators.dart for maths + palette) and the optional
  /// Bollinger band fill. Lists are memoized by the host, so identity
  /// comparison suffices for shouldRepaint.
  final List<KuteIndicatorOverlay> overlays;
  final KuteIndicatorBand? band;

  /// Log price axis (ln-mapped y). Flows into the shared geometry so
  /// every painted element stays in register.
  final bool logScale;

  /// Bar/line variant to paint.
  final HlChartStyle style;

  /// Volume moving average on the volume scale, nan = warm-up; empty
  /// when off.
  final List<double> volumeMa;

  /// The shown (autoscaled or manual) price domain.
  final HlPriceDomain? domain;

  _HlCandlePainter({
    required this.candles,
    required this.upColor,
    required this.downColor,
    required this.gridColor,
    required this.labelBg,
    required this.labelFg,
    required this.decimalCap,
    required this.showVolume,
    required this.renderAsLine,
    required this.fills,
    this.entryPx,
    this.entryIsLong = true,
    this.leadingClose,
    this.morphSeries,
    this.overlays = const [],
    this.band,
    this.logScale = false,
    this.style = HlChartStyle.area,
    this.volumeMa = const [],
    this.domain,
  });

  /// Laid-out TextPainters keyed by (text, color, fontSize) — the rail
  /// labels and last-price tag re-layout identical text on every paint
  /// otherwise (flagged: paint-time allocation). Static so the cache
  /// survives painter re-creation across frames; bounded defensively.
  static final Map<(String, int, double), TextPainter> _tpCache = {};

  static TextPainter _cachedTp(
      String text, Color color, double fontSize, FontWeight weight) {
    if (_tpCache.length > 64) _tpCache.clear();
    return _tpCache.putIfAbsent(
      (text, color.toARGB32(), fontSize),
      () => TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: kuteChartFontFamily,
            color: color,
            fontSize: fontSize,
            fontWeight: weight,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = candles.length;
    if (n == 0) return;
    final w = size.width;
    final h = size.height;

    final geom = _hlPriceGeometry(
      candles: candles,
      renderAsLine: renderAsLine,
      showVolume: showVolume,
      height: h,
      logScale: logScale,
      leadingClose: renderAsLine ? leadingClose : null,
      morphSeries: renderAsLine ? morphSeries : null,
      domain: domain,
    );
    final priceH = geom.priceH;
    final loP = geom.loP;
    final rangeP = geom.rangeP;
    final logMap = geom.log;
    double toY(double v) =>
        priceH * (1 - (_hlMapPrice(v, logMap) - loP) / rangeP);

    var maxVol = 0.0;
    for (final k in candles) {
      if (k.volume > maxVol) maxVol = k.volume;
    }

    final slot = w / n;
    final bodyW = (slot * 0.62).clamp(1.0, 22.0);

    // ── Volume strip (both modes) ────────────────────────────────────
    if (showVolume && maxVol > 0 && priceH < h) {
      // Hairline baseline under the strip anchors the bars visually.
      canvas.drawLine(
        Offset(0, h - 0.25),
        Offset(w, h - 0.25),
        Paint()
          ..color = gridColor.withValues(alpha: 0.35)
          ..strokeWidth = 0.5,
      );
      const volRadius = Radius.circular(1.5);
      final volAreaH = h * 0.16;
      // Autoscaled to the visible bars: maxVol spans only what is on
      // screen. Two paints for the whole strip, not one per bar.
      final volUp = Paint()..color = upColor.withValues(alpha: 0.28);
      final volDown = Paint()..color = downColor.withValues(alpha: 0.28);
      for (var i = 0; i < n; i++) {
        final k = candles[i];
        final vh = (k.volume / maxVol) * volAreaH;
        // Zero/near-zero buckets: nothing to show — skip the draw call.
        if (vh < 0.5) continue;
        final cx = (i + 0.5) * slot;
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(cx - bodyW / 2, h - vh, bodyW, vh),
            topLeft: volRadius,
            topRight: volRadius,
          ),
          k.close >= k.open ? volUp : volDown,
        );
      }
      if (volumeMa.isNotEmpty) {
        final ma = Path();
        var on = false;
        for (var i = 0; i < math.min(n, volumeMa.length); i++) {
          final v = volumeMa[i];
          if (!v.isFinite) {
            on = false;
            continue;
          }
          final p = Offset((i + 0.5) * slot, h - (v / maxVol) * volAreaH);
          if (on) {
            ma.lineTo(p.dx, p.dy);
          } else {
            ma.moveTo(p.dx, p.dy);
            on = true;
          }
        }
        canvas.drawPath(
            ma,
            Paint()
              ..color = kuteIndSma20Color.withValues(alpha: 0.9)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2);
      }
    }

    // A manual price scale can push the series past the price area; keep
    // it off the volume strip and the edges.
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, w, priceH));
    if (renderAsLine) {
      // ── Shared-engine line: monotone cubic across the closes ───────
      final lineUp = candles.last.close >= candles.first.close;
      final lineCol = lineUp ? upColor : downColor;

      final series = morphSeries;
      final List<Offset> pts;
      if (series != null && series.length >= 2) {
        final m = series.length;
        final slotM = w / m;
        pts = List<Offset>.generate(
          m,
          (i) => Offset((i + 0.5) * slotM, toY(series[i])),
          growable: false,
        );
      } else {
        pts = List<Offset>.generate(
          n,
          (i) => Offset(
            (i + 0.5) * slot,
            toY(i == n - 1 && leadingClose != null
                ? leadingClose!
                : candles[i].close),
          ),
          growable: false,
        );
      }
      final path = kuteMonotonePath(pts);

      if (style == HlChartStyle.baseline) {
        // Two-tone fill either side of the window's first close: above
        // it in the up colour, below it in the down colour.
        final baseY = toY(candles.first.close).clamp(0.0, priceH);
        final fill = Path.from(path)
          ..lineTo(pts.last.dx, baseY)
          ..lineTo(pts.first.dx, baseY)
          ..close();
        canvas.save();
        canvas.clipRect(Rect.fromLTWH(0, 0, w, baseY));
        canvas.drawPath(fill, Paint()..color = upColor.withValues(alpha: 0.16));
        canvas.restore();
        canvas.save();
        canvas.clipRect(Rect.fromLTWH(0, baseY, w, priceH - baseY));
        canvas.drawPath(
            fill, Paint()..color = downColor.withValues(alpha: 0.16));
        canvas.restore();
        canvas.drawLine(
            Offset(0, baseY),
            Offset(w, baseY),
            Paint()
              ..color = gridColor
              ..strokeWidth = 1);
      } else if (style != HlChartStyle.line) {
        // Subtle gradient fill under the line (shared spec, shader
        // cached), dropped to the price-area floor.
        final fill = Path.from(path)
          ..lineTo(pts.last.dx, priceH)
          ..lineTo(pts.first.dx, priceH)
          ..close();
        canvas.drawPath(
            fill, Paint()..shader = kuteFillShader(w, priceH, lineCol));
      }
      canvas.drawPath(path, kuteStrokePaint(lineCol));

      // Endpoint dot (the live pulse rides its own decor layer).
      kuteDrawEndpointDot(canvas, pts.last, lineCol,
          isDark: labelBg == Colors.black);
    } else {
      // ── Candlestick bodies + wicks ─────────────────────────────────
      final wickPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, bodyW * 0.14)
        ..strokeCap = StrokeCap.round;
      final wickUp = upColor.withValues(alpha: 0.9);
      final wickDown = downColor.withValues(alpha: 0.9);
      final bodyUp = Paint()..color = upColor;
      final bodyDown = Paint()..color = downColor;
      final stem = Paint()
        ..strokeWidth = math.max(1.0, bodyW * 0.18)
        ..strokeCap = StrokeCap.round;
      final hollowUp = Paint()
        ..color = upColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, bodyW * 0.16);

      for (var i = 0; i < n; i++) {
        final k = candles[i];
        final cx = (i + 0.5) * slot;
        final up = k.close >= k.open;
        final col = up ? upColor : downColor;

        final openY = toY(k.open);
        final closeY = toY(k.close);
        if (style == HlChartStyle.bars) {
          // OHLC bar: the range as a stem, open as a left tick, close as
          // a right tick.
          stem.color = col;
          canvas.drawLine(
              Offset(cx, toY(k.high)), Offset(cx, toY(k.low)), stem);
          canvas.drawLine(
              Offset(cx - bodyW / 2, openY), Offset(cx, openY), stem);
          canvas.drawLine(
              Offset(cx, closeY), Offset(cx + bodyW / 2, closeY), stem);
          continue;
        }

        // Wick (high → low).
        canvas.drawLine(
          Offset(cx, toY(k.high)),
          Offset(cx, toY(k.low)),
          wickPaint..color = up ? wickUp : wickDown,
        );

        // Body (open → close). Floor to 2px so single-trade zero-range
        // buckets (common on thin HIP-3 markets) read as candles, not
        // stray dashes.
        final top = math.min(openY, closeY);
        final bottom = math.max(openY, closeY);
        final bodyH = math.max(bottom - top, 2.0);
        final rrect = RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - bodyW / 2, top, bodyW, bodyH),
          Radius.circular(math.min(2.0, bodyW / 3)),
        );
        if (style == HlChartStyle.hollow && up) {
          // Hollow: an up candle is an outline, a down candle stays filled.
          canvas.drawRRect(rrect, hollowUp);
        } else {
          canvas.drawRRect(rrect, up ? bodyUp : bodyDown);
        }
      }

      // The old right-edge hi/mid/lo rails are gone — the left-edge
      // price scale layer (_HlPriceScalePainter) carries the spatial
      // context now, in both candle and line modes.
    }
    canvas.restore();

    // ── Indicator overlays (SMA/EMA/BB) ──────────────────────────────
    // Thin polylines over the data, clipped to the price area (a BB
    // envelope can exceed the candle domain). Skipped mid-morph — the
    // morph line's x space is resampled, so bucket-aligned overlays
    // would drift for its ~280ms.
    if (overlays.isNotEmpty && morphSeries == null) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, w, priceH));
      final b = band;
      if (b != null) kutePaintIndicatorBandFill(canvas, b, slot, toY);
      for (final o in overlays) {
        kutePaintIndicatorLine(canvas, o, slot, toY);
      }
      canvas.restore();
    }

    // ── Average entry line (open position on this market) ────────────
    // A muted dashed horizontal reference at the position's entry price
    // with a small right-edge "Entry" tag, long = up colour / short =
    // down colour — both line and candle modes. Skipped when the entry
    // sits outside the visible price window: a clamped line would lie
    // about where the price actually is. Painted before the last-price
    // tag so that tag stays on top when the two collide.
    final entry = entryPx;
    if (entry != null && entry > 0) {
      final ey = toY(entry);
      if (ey >= 0 && ey <= priceH) {
        final entryCol = entryIsLong ? upColor : downColor;
        final mutedCol = entryCol.withValues(alpha: 0.45);
        final entryPaint = Paint()
          ..color = mutedCol
          ..strokeWidth = 1.0;
        for (double x = 0; x < w; x += 9) {
          canvas.drawLine(
              Offset(x, ey), Offset(math.min(x + 4.5, w), ey), entryPaint);
        }
        // "Entry" tag: same geometry as the last-price tag but muted — a
        // background-coloured pill with a hairline in the side colour.
        final etp = _cachedTp(
          'Entry',
          entryCol.withValues(alpha: 0.9),
          10.sp,
          FontWeight.w700,
        );
        final ePadH = 5.w;
        final ePadV = 2.5.h;
        final eW = etp.width + ePadH * 2;
        final eH = etp.height + ePadV * 2;
        final eY =
            (ey - eH / 2).clamp(0.0, math.max(0.0, priceH - eH)).toDouble();
        final eRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(w - eW, eY, eW, eH),
          Radius.circular(4.r),
        );
        canvas.drawRRect(
            eRect, Paint()..color = labelBg.withValues(alpha: 0.85));
        canvas.drawRRect(
          eRect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0
            ..color = mutedCol,
        );
        etp.paint(canvas, Offset(w - eW + ePadH, eY + ePadV));
      }
    }

    // ── The user's own fill markers (buys ▲ / sells ▼) ───────────────
    // Small glyphs at each fill's time+price (see hlResolveFillMarkers for
    // the mapping); the detail lives in the tap tooltip. Painted BEFORE
    // the last-price tag so the tag always stays on top of them, and
    // skipped mid-morph because the morph line's x space is resampled.
    if (fills.isNotEmpty && n >= 2 && morphSeries == null) {
      final markers = hlResolveFillMarkers(
        candles: candles,
        fills: fills,
        size: size,
        renderAsLine: renderAsLine,
        showVolume: showVolume,
        logScale: logScale,
        leadingClose: leadingClose,
        domain: domain,
      );
      for (final m in markers) {
        final buy = m.fill.isBuy;
        hlPaintFillMarker(
            canvas, m.center, buy, buy ? upColor : downColor, labelBg);
      }
    }

    // ── Last-price line + right-edge tag ─────────────────────────────
    final lastK = candles.last;
    // Colour by the last candle's direction for candles, the overall line
    // direction (first→last) when rendering as a line.
    final lastUp = renderAsLine
        ? candles.last.close >= candles.first.close
        : lastK.close >= lastK.open;
    final lineColor = lastUp ? upColor : downColor;
    final lyValue = morphSeries != null && morphSeries!.isNotEmpty
        ? morphSeries!.last
        : (renderAsLine ? (leadingClose ?? lastK.close) : lastK.close);
    final ly = toY(lyValue).clamp(0.0, priceH);

    final dashPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.55)
      ..strokeWidth = 1.0;
    for (double x = 0; x < w; x += 6) {
      canvas.drawLine(Offset(x, ly), Offset(math.min(x + 3, w), ly), dashPaint);
    }

    // Contrast text picked by the pill fill's luminance — the market
    // tokens are dark enough for white today, but a caller-supplied
    // light up/down color shouldn't silently ship white-on-light.
    final tagFg =
        lineColor.computeLuminance() > 0.55 ? Colors.black : Colors.white;
    final tag = _cachedTp(
      formatHlPrice(lastK.close, decimalCap: decimalCap),
      tagFg,
      10.5.sp,
      FontWeight.w800,
    );
    final tagPadH = 5.w;
    final tagPadV = 2.5.h;
    final tagW = tag.width + tagPadH * 2;
    final tagH = tag.height + tagPadV * 2;
    var tagY = ly - tagH / 2;
    tagY = tagY.clamp(0.0, math.max(0.0, priceH - tagH));
    final tagRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w - tagW, tagY, tagW, tagH),
      Radius.circular(4.r),
    );
    canvas.drawRRect(tagRect, Paint()..color = lineColor);
    tag.paint(canvas, Offset(w - tagW + tagPadH, tagY + tagPadV));

    // Crosshair on scrub lives in the shared KuteChartCrosshair layer; the
    // fill-marker tooltip in HlFillTooltipPainter.
  }

  @override
  bool shouldRepaint(covariant _HlCandlePainter old) =>
      old.candles != candles ||
      !_sameFills(old.fills, fills) ||
      old.entryPx != entryPx ||
      old.style != style ||
      !identical(old.volumeMa, volumeMa) ||
      old.entryIsLong != entryIsLong ||
      old.leadingClose != leadingClose ||
      !_sameMorph(old.morphSeries, morphSeries) ||
      old.upColor != upColor ||
      old.downColor != downColor ||
      old.gridColor != gridColor ||
      old.labelBg != labelBg ||
      old.labelFg != labelFg ||
      old.showVolume != showVolume ||
      old.renderAsLine != renderAsLine ||
      !identical(old.overlays, overlays) ||
      !identical(old.band, band) ||
      old.logScale != logScale ||
      old.domain != domain;

  static bool _sameMorph(List<double>? a, List<double>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    return kuteSameSeries(a, b);
  }

  /// Cheap fills equality for shouldRepaint: identity, else same length
  /// with matching first/last timestamps. Fills change rarely (a new one
  /// appends); a host rebuilding a same-content list must not force a
  /// full canvas re-raster every live tick.
  static bool _sameFills(List<HlFill> a, List<HlFill> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    if (a.isEmpty) return true;
    for (var i = 0; i < a.length; i++) {
      if (a[i].time != b[i].time ||
          a[i].px != b[i].px ||
          a[i].side != b[i].side ||
          a[i].sz != b[i].sz ||
          a[i].tradeId != b[i].tradeId) {
        return false;
      }
    }
    return true;
  }
}

// ───────────────────────── fill-marker tooltip ──────────────────────────

/// One row pair of the fill tooltip: a bold coloured [title] ("Bought
/// 0.012 BTC at $64,120.00") over a muted [detail] ("Open Long · $769.44 ·
/// 29 Sep, 14:32"). Text is formatted by the host in build, never in
/// paint.
class HlFillTooltipEntry {
  final Object identity;
  final String title;
  final String detail;
  final Color color;
  final Color detailColor;

  const HlFillTooltipEntry({
    required this.identity,
    required this.title,
    required this.detail,
    required this.color,
    required this.detailColor,
  });
}

/// The resolved anchor frame for one canvas size: the selected markers'
/// positions and the bottom of the price area (the card never overlaps
/// the volume strip).
typedef HlFillTooltipFrame = ({List<HlFillMarker> markers, double plotBottom});

/// The fill-marker tooltip layer: a ring on each selected marker plus one
/// rounded card (same grammar as the crosshair bubble and trade-line tags:
/// theme-core background, thin accent border, 6px radius) listing the
/// fills on that bar. The card prefers to sit above the marker, drops
/// below when there is no room, and is clamped inside the plot on every
/// side so it can never be cut at an edge. Colours are passed in by the
/// host; this painter never reads Theme.
class HlFillTooltipPainter extends CustomPainter {
  final List<HlFillTooltipEntry> entries;
  final HlFillTooltipFrame Function(Size size) resolve;
  final bool isDark;
  final Color dividerColor;

  /// Value-compared token that changes whenever the resolved output
  /// would (selection, tape identity, theme) — drives shouldRepaint.
  final Object? repaintKey;

  HlFillTooltipPainter({
    required this.entries,
    required this.resolve,
    required this.isDark,
    required this.dividerColor,
    required this.repaintKey,
  });

  static const double _padH = 9.0;
  static const double _padV = 7.0;
  static const double _lineGap = 2.0;
  static const double _entryGap = 6.0;
  static const double _gapFromMarker = 8.0;
  static const double _edgeInset = 2.0;
  static const double _titleSize = 11.5;
  static const double _detailSize = 10.5;

  /// Laid-out TextPainters keyed by (text, color, fontSize); bounded.
  static final Map<(String, int, double), TextPainter> _tpCache = {};

  static TextPainter _tp(
      String text, Color color, double fontSize, FontWeight weight) {
    if (_tpCache.length > 64) _tpCache.clear();
    return _tpCache.putIfAbsent(
      (text, color.toARGB32(), fontSize),
      () => TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: kuteChartFontFamily,
            color: color,
            fontSize: fontSize,
            fontWeight: weight,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(),
    );
  }

  /// The card rectangle for [entries] anchored to [markers] inside a
  /// [size] canvas whose price area ends at [plotBottom]. Exposed so the
  /// clamping is unit-testable without rasterising.
  static Rect layoutCard({
    required List<HlFillTooltipEntry> entries,
    required List<HlFillMarker> markers,
    required Size size,
    required double plotBottom,
  }) {
    var contentW = 0.0;
    var contentH = 0.0;
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final t = _tp(e.title, e.color, _titleSize, FontWeight.w800);
      final d = _tp(e.detail, e.detailColor, _detailSize, FontWeight.w600);
      contentW = math.max(contentW, math.max(t.width, d.width));
      contentH += t.height + _lineGap + d.height;
      if (i > 0) contentH += _entryGap;
    }
    final cardW = math.min(contentW + _padH * 2, size.width - _edgeInset * 2);
    final cardH = contentH + _padV * 2;
    final bottom = plotBottom.clamp(0.0, size.height).toDouble();

    var anchorX = size.width / 2;
    var topY = 0.0;
    var lowY = 0.0;
    if (markers.isNotEmpty) {
      anchorX = 0;
      topY = double.infinity;
      lowY = double.negativeInfinity;
      for (final m in markers) {
        anchorX += m.center.dx;
        topY = math.min(topY, m.center.dy - hlFillMarkerRadius);
        lowY = math.max(lowY, m.center.dy + hlFillMarkerRadius);
      }
      anchorX /= markers.length;
    }
    final x = (anchorX - cardW / 2)
        .clamp(
            _edgeInset, math.max(_edgeInset, size.width - cardW - _edgeInset))
        .toDouble();
    // Above the marker by default; below when the top would be cut off.
    var y = topY - _gapFromMarker - cardH;
    if (y < _edgeInset) y = lowY + _gapFromMarker;
    y = y
        .clamp(_edgeInset, math.max(_edgeInset, bottom - cardH - _edgeInset))
        .toDouble();
    return Rect.fromLTWH(x, y, cardW, cardH);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (entries.isEmpty) return;
    final frame = resolve(size);
    final markers = frame.markers;
    final core = isDark ? Colors.black : Colors.white;

    // Rings on the selected markers, so the card visibly belongs to them.
    for (final m in markers) {
      final ring = _entryColor(m, entries.first.color);
      canvas.drawCircle(
        m.center,
        hlFillMarkerRadius + 4.5,
        Paint()..color = ring.withValues(alpha: 0.16),
      );
      canvas.drawCircle(
        m.center,
        hlFillMarkerRadius + 4.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = ring.withValues(alpha: 0.9),
      );
    }

    final card = layoutCard(
      entries: entries,
      markers: markers,
      size: size,
      plotBottom: frame.plotBottom,
    );
    final accent = entries.length == 1 ||
            entries.every((e) => e.color == entries.first.color)
        ? entries.first.color
        : dividerColor;
    final rrect = RRect.fromRectAndRadius(card, const Radius.circular(6));
    canvas.drawRRect(
      rrect,
      Paint()..color = core.withValues(alpha: 0.94),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = accent.withValues(alpha: 0.7),
    );

    // Text, clipped to the card so a very long row can never spill out.
    canvas.save();
    canvas.clipRRect(rrect);
    var y = card.top + _padV;
    final x = card.left + _padH;
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      if (i > 0) {
        y += _entryGap / 2;
        canvas.drawLine(
          Offset(card.left + _padH, y),
          Offset(card.right - _padH, y),
          Paint()
            ..color = dividerColor.withValues(alpha: 0.6)
            ..strokeWidth = 1.0,
        );
        y += _entryGap / 2;
      }
      final t = _tp(e.title, e.color, _titleSize, FontWeight.w800);
      t.paint(canvas, Offset(x, y));
      y += t.height + _lineGap;
      final d = _tp(e.detail, e.detailColor, _detailSize, FontWeight.w600);
      d.paint(canvas, Offset(x, y));
      y += d.height;
    }
    canvas.restore();
  }

  Color _entryColor(HlFillMarker m, Color fallback) {
    final id = hlFillIdentity(m.fill);
    for (final e in entries) {
      if (e.identity == id) return e.color;
    }
    return fallback;
  }

  @override
  bool shouldRepaint(covariant HlFillTooltipPainter old) =>
      old.repaintKey != repaintKey ||
      old.isDark != isDark ||
      old.dividerColor != dividerColor ||
      old.entries.length != entries.length;
}

// ───────────────────────────── line sparkline ─────────────────────────────

/// Clean line sparkline for the market CARDS — the Trading tab's browse-card
/// mini chart. [closes] are ascending close prices; the stroke is colored
/// up/down vs the first→last close, drawn edge-to-edge with no fill. Min–max
/// normalized with a small vertical pad (crypto prices sit far from zero, so
/// a zero baseline would read flat). Renders nothing until there are ≥2
/// points so a card never jumps.
class HlLineSparkline extends StatelessWidget {
  final List<double> closes;
  final double width;
  final double height;
  final Color? upColor;
  final Color? downColor;

  const HlLineSparkline({
    super.key,
    required this.closes,
    this.width = 56,
    this.height = 26,
    this.upColor,
    this.downColor,
  });

  /// Build from raw candles — uses each candle's close.
  factory HlLineSparkline.fromCandles(
    List<HyperliquidCandle> candles, {
    Key? key,
    double width = 56,
    double height = 26,
    Color? upColor,
    Color? downColor,
  }) {
    return HlLineSparkline(
      key: key,
      closes: candles.map((k) => k.close).toList(growable: false),
      width: width,
      height: height,
      upColor: upColor,
      downColor: downColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width.w,
      height: height.h,
      child: _sparklineData(closes).length < 2
          ? null
          : CustomPaint(
              painter: _HlLineSparklinePainter(
                data: _sparklineData(closes),
                upColor: upColor ?? AppColors.marketUp,
                downColor: downColor ?? AppColors.marketDown,
              ),
            ),
    );
  }
}

class _HlLineSparklinePainter extends CustomPainter {
  final List<double> data;
  final Color upColor;
  final Color downColor;

  _HlLineSparklinePainter({
    required this.data,
    required this.upColor,
    required this.downColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final n = data.length;
    if (n < 2) return;
    final w = size.width;
    final h = size.height;

    var min = data.first, max = data.first;
    for (final v in data) {
      if (v < min) min = v;
      if (v > max) max = v;
    }
    final range = max - min;

    // Small vertical pad so the extremes don't kiss the top/bottom edges.
    const padFrac = 0.12;
    double toY(double v) {
      final norm = range > 0 ? (v - min) / range : 0.5;
      return h * (padFrac + (1 - 2 * padFrac) * (1 - norm));
    }

    double toX(int i) => (i / (n - 1)) * w;

    final up = data.last >= data.first;
    final color = up ? upColor : downColor;

    final line = Path();
    for (var i = 0; i < n; i++) {
      final x = toX(i);
      final y = toY(data[i]);
      if (i == 0) {
        line.moveTo(x, y);
      } else {
        line.lineTo(x, y);
      }
    }

    // The line only — no gradient fill (the card wants a clean edge-to-edge
    // stroke, no shade under it).
    canvas.drawPath(line, kuteStrokePaint(color));
  }

  @override
  bool shouldRepaint(covariant _HlLineSparklinePainter old) =>
      old.data != data || old.upColor != upColor || old.downColor != downColor;
}

/// A small oscillator pane: one or more series, optional histogram and
/// guide levels, autoscaled to the visible values (bounded oscillators
/// such as RSI and stochastic never pad past [fixedRange]). The scrubbed
/// value of the first series is shown at the top right.
class _HlPanePainter extends CustomPainter {
  const _HlPanePainter({
    required this.series,
    required this.selectedIndex,
    required this.labelColor,
    this.histogram,
    this.histogramUp,
    this.histogramDown,
    this.levels = const [],
    this.fixedRange,
  });

  final List<(List<double>, Color)> series;
  final List<double>? histogram;
  final Color? histogramUp, histogramDown;
  final List<double> levels;
  final (double, double)? fixedRange;
  final int? selectedIndex;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty || size.width <= 0) return;
    final n = series.first.$1.length;
    if (n == 0) return;
    // Autoscaled to the visible values (and the guide levels, so 30/70
    // or 20/80 stay in view); a bounded oscillator never pads past its
    // natural range.
    var lo = double.infinity;
    var hi = double.negativeInfinity;
    for (final (values, _) in series) {
      for (final v in values) {
        if (!v.isFinite) continue;
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
    }
    for (final v in histogram ?? const <double>[]) {
      if (!v.isFinite) continue;
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    for (final l in levels) {
      if (l < lo) lo = l;
      if (l > hi) hi = l;
    }
    final bounds = fixedRange;
    if (!lo.isFinite || !hi.isFinite) {
      if (bounds == null) return;
      lo = bounds.$1;
      hi = bounds.$2;
    }
    if (hi <= lo) hi = lo + 1;
    final pad = (hi - lo) * 0.08;
    lo -= pad;
    hi += pad;
    if (bounds != null) {
      lo = math.max(lo, bounds.$1);
      hi = math.min(hi, bounds.$2);
    }
    double toY(double v) => size.height * (1 - (v - lo) / (hi - lo));
    final slot = size.width / n;

    final guide = Paint()
      ..color = labelColor.withValues(alpha: 0.25)
      ..strokeWidth = 0.5;
    for (final level in levels) {
      final y = toY(level);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), guide);
      final label = TextPainter(
        text: TextSpan(
          text: level == level.roundToDouble()
              ? level.toInt().toString()
              : level.toStringAsFixed(2),
          style: TextStyle(
            fontFamily: kuteChartFontFamily,
            color: labelColor,
            fontSize: 10,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(2, y - label.height));
    }

    final hist = histogram;
    if (hist != null) {
      final zero = toY(0).clamp(0.0, size.height);
      final barW = math.max(1.0, slot * 0.6);
      for (var i = 0; i < math.min(n, hist.length); i++) {
        final v = hist[i];
        if (!v.isFinite) continue;
        final y = toY(v);
        final color = (v >= 0 ? histogramUp : histogramDown) ?? labelColor;
        canvas.drawRect(
            Rect.fromLTRB((i + 0.5) * slot - barW / 2, math.min(y, zero),
                (i + 0.5) * slot + barW / 2, math.max(y, zero)),
            Paint()..color = color.withValues(alpha: 0.45));
      }
    }

    for (final (values, color) in series) {
      final path = Path();
      var connected = false;
      for (var i = 0; i < math.min(n, values.length); i++) {
        final value = values[i];
        if (!value.isFinite) {
          connected = false;
          continue;
        }
        final x = (i + 0.5) * slot;
        final y = toY(value);
        if (connected) {
          path.lineTo(x, y);
        } else {
          path.moveTo(x, y);
          connected = true;
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    final values = series.first.$1;
    final index = selectedIndex ?? values.length - 1;
    if (index >= 0 && index < values.length && values[index].isFinite) {
      final v = values[index];
      final label = TextPainter(
        text: TextSpan(
          text:
              v.abs() >= 100 ? v.toStringAsFixed(1) : v.toStringAsPrecision(4),
          style: TextStyle(
            fontFamily: kuteChartFontFamily,
            color: series.first.$2,
            fontSize: 11,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(size.width - label.width, 0));
    }
  }

  @override
  bool shouldRepaint(covariant _HlPanePainter old) {
    if (old.series.length != series.length) return true;
    for (var i = 0; i < series.length; i++) {
      if (!identical(old.series[i].$1, series[i].$1)) return true;
    }
    return !identical(old.histogram, histogram) ||
        selectedIndex != old.selectedIndex ||
        labelColor != old.labelColor;
  }
}

/// The points a list-row sparkline paints. A low-end phone paints about
/// four dozen closes at most (a dozen rows are on screen, each repainting
/// on a live tick); other devices paint them all.
List<double> _sparklineData(List<double> closes) {
  if (!DevicePerformance.isLowEnd || closes.length <= 48) return closes;
  final step = (closes.length / 48).ceil();
  return [
    for (var i = 0; i < closes.length; i += step) closes[i],
    if ((closes.length - 1) % step != 0) closes.last,
  ];
}
