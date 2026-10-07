// lib/screens/shared/charts/kute_chart_crosshair.dart
//
// The scrub crosshair every chart shares (the balance and price charts,
// the Polymarket and Hyperliquid charts): a vertical hairline, a marker
// dot per series, and ONE scrub card beside the hairline at the top of
// the plot that says everything about the point under the finger: the
// value as the main figure, its change since the start of the window on
// screen (signed, in the up/down colours) and the date or time, in the
// app's language. The card is the only place the scrubbed point is
// written: no value bubble, no date chip, no header readout repeating it.
//
// The card sits on the right of the hairline and flips to its left near
// the right edge, always inside the chart. The layer fades in and out
// over 120ms (at once under reduced motion) and lives in its own
// RepaintBoundary, so scrub frames never re-raster the data canvas
// underneath.
//
// The hosting chart passes a [resolve] callback that maps the canvas size
// to concrete positions using the SAME geometry as its data painter, so
// the hairline and dots land exactly on the line. The painter never reads
// Theme; the card is a widget and takes the app's tokens and type.

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import 'package:kute/theme/app_theme.dart';

/// One per-series marker on the crosshair.
class KuteCrosshairDot {
  final double y;
  final Color color;

  const KuteCrosshairDot({required this.y, required this.color});
}

/// One line of a many-line chart in the scrub card: its colour, a short
/// name and its value.
class KuteScrubCardEntry {
  final Color color;
  final String label;
  final String value;

  const KuteScrubCardEntry(
      {required this.color, required this.label, required this.value});

  @override
  bool operator ==(Object other) =>
      other is KuteScrubCardEntry &&
      other.color == color &&
      other.label == label &&
      other.value == value;

  @override
  int get hashCode => Object.hash(color, label, value);
}

/// What the scrub card says about the point under the finger.
class KuteScrubCardData {
  /// The value, the card's main figure. Ignored when [entries] is set.
  final String value;

  /// The change since the start of the window on screen, already signed
  /// ("+$12.30 (+1.2%)"). Null leaves the line out.
  final String? change;

  /// Which way [change] went: above zero is the up colour, below zero the
  /// down colour, zero the quiet one.
  final int changeSign;

  /// The date or time, in the app's language.
  final String? time;

  /// Quiet extra lines that belong to this point only (a candle's open,
  /// high and low, what the wallet held that day, a game event).
  final List<String> details;

  /// A many-line chart's values, one row per line, in place of [value].
  final List<KuteScrubCardEntry> entries;

  const KuteScrubCardData({
    this.value = '',
    this.change,
    this.changeSign = 0,
    this.time,
    this.details = const [],
    this.entries = const [],
  });

  @override
  bool operator ==(Object other) =>
      other is KuteScrubCardData &&
      other.value == value &&
      other.change == change &&
      other.changeSign == changeSign &&
      other.time == time &&
      listEquals(other.details, details) &&
      listEquals(other.entries, entries);

  @override
  int get hashCode => Object.hash(value, change, changeSign, time,
      Object.hashAll(details), Object.hashAll(entries));
}

/// A fully-resolved crosshair frame for one canvas size.
class KuteCrosshairData {
  /// Hairline x position, in canvas px.
  final double x;
  final List<KuteCrosshairDot> dots;

  /// Bottom of the hairline / dot area (e.g. above a volume strip or the
  /// chart's bottom margin). Defaults to the full canvas height.
  final double? plotBottom;

  /// The scrub card. Null draws the hairline and dots alone.
  final KuteScrubCardData? card;

  const KuteCrosshairData({
    required this.x,
    required this.dots,
    this.plotBottom,
    this.card,
  });
}

/// Gap between the hairline and the card, and the card's distance from
/// the top of the plot.
const double kuteScrubCardGap = 10;
const double kuteScrubCardTop = 4;

/// The right-edge column a chart with price tags keeps for them (the
/// latest price, entry, liquidation, "Bought"): the scrub card goes to
/// the hairline's left rather than over it.
const double kuteScrubCardTagGutter = 96;

/// The reusable crosshair layer. Mount it as a `Positioned.fill` sibling
/// above the data painter; pass a non-null [resolve] while a scrub is
/// active and null when it ends; the layer keeps the last frame around
/// while it fades out.
class KuteChartCrosshair extends StatefulWidget {
  final KuteCrosshairData? Function(Size size)? resolve;

  /// Value-compared token that changes whenever the resolved output
  /// would (scrub index, series identity, theme); drives shouldRepaint.
  final Object? repaintKey;

  final bool isDark;
  final Color hairlineColor;

  const KuteChartCrosshair({
    super.key,
    required this.resolve,
    required this.repaintKey,
    required this.isDark,
    required this.hairlineColor,
    this.cardRightInset = 0,
  });

  /// Width at the right edge the card keeps clear of when it can (the
  /// chart's tag column, [kuteScrubCardTagGutter]).
  final double cardRightInset;

  @override
  State<KuteChartCrosshair> createState() => _KuteChartCrosshairState();
}

class _KuteChartCrosshairState extends State<KuteChartCrosshair> {
  // Last active frame, retained so the 120ms fade-out shows the final
  // scrub position instead of vanishing content.
  KuteCrosshairData? Function(Size size)? _lastResolve;
  Object? _lastKey;

  @override
  Widget build(BuildContext context) {
    final active = widget.resolve != null;
    if (active) {
      _lastResolve = widget.resolve;
      _lastKey = widget.repaintKey;
    }
    final resolve = _lastResolve;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: active ? 1.0 : 0.0,
        duration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        // Faded out: the last frame leaves the tree.
        onEnd: () {
          if (widget.resolve == null && _lastResolve != null && mounted) {
            setState(() => _lastResolve = null);
          }
        },
        child: resolve == null
            ? const SizedBox.shrink()
            : LayoutBuilder(builder: (context, constraints) {
                final size = constraints.biggest;
                final data = resolve(size);
                final card = data?.card;
                return Stack(
                  children: [
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: KuteCrosshairPainter(
                            data: data,
                            repaintKey: _lastKey,
                            isDark: widget.isDark,
                            hairlineColor: widget.hairlineColor,
                          ),
                        ),
                      ),
                    ),
                    if (data != null && card != null)
                      Positioned.fill(
                        child: CustomSingleChildLayout(
                          delegate: _ScrubCardLayout(
                              x: data.x.clamp(0.0, size.width).toDouble(),
                              rightInset: widget.cardRightInset),
                          child: KuteScrubCard(data: card),
                        ),
                      ),
                  ],
                );
              }),
      ),
    );
  }
}

/// Puts the card beside the hairline at the top of the plot: on its right,
/// on its left when the right has no room, always inside the chart.
class _ScrubCardLayout extends SingleChildLayoutDelegate {
  _ScrubCardLayout({required this.x, this.rightInset = 0});
  final double x;
  final double rightInset;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: math.min(240.0, constraints.maxWidth),
        maxHeight: math.max(0.0, constraints.maxHeight - kuteScrubCardTop),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var left = x + kuteScrubCardGap;
    // On the right only when it clears the edge (and the tag column a
    // chart keeps there); otherwise on the left, when that side fits.
    final leftSide = x - kuteScrubCardGap - childSize.width;
    if (left + childSize.width > size.width - rightInset && leftSide >= 0 ||
        left + childSize.width > size.width) {
      left = leftSide;
    }
    left = left
        .clamp(0.0, math.max(0.0, size.width - childSize.width))
        .toDouble();
    return Offset(left, kuteScrubCardTop);
  }

  @override
  bool shouldRelayout(covariant _ScrubCardLayout old) =>
      old.x != x || old.rightInset != rightInset;
}

/// The scrub card: the app's floating-card surface (white on light with a
/// soft shadow, the elevated surface on dark), its hairline border, the
/// app's type. No tint, no icon, nothing the line itself already says.
class KuteScrubCard extends StatelessWidget {
  const KuteScrubCard({super.key, required this.data});

  final KuteScrubCardData data;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDark = context.isDark;
    const tabular = [FontFeature.tabularFigures()];
    final changeColor = data.changeSign > 0
        ? AppColors.marketUp
        : (data.changeSign < 0 ? AppColors.marketDown : c.textSecondary);
    final quiet = TextStyle(
      color: c.textSecondary,
      fontSize: 11.5,
      fontWeight: FontWeight.w500,
      height: 1.25,
      fontFeatures: tabular,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
      decoration: BoxDecoration(
        color: isDark ? c.surfaceElevated : c.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border, width: 1),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (data.entries.isEmpty)
            Text(
              data.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                height: 1.2,
                fontFeatures: tabular,
              ),
            )
          else
            for (final e in data.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 1),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration:
                          BoxDecoration(color: e.color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    if (e.label.isNotEmpty) ...[
                      Flexible(
                        child: Text(
                          e.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: quiet.copyWith(fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      e.value,
                      maxLines: 1,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                        fontFeatures: tabular,
                      ),
                    ),
                  ],
                ),
              ),
          if (data.change != null) ...[
            const SizedBox(height: 2),
            Text(
              data.change!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: changeColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.25,
                fontFeatures: tabular,
              ),
            ),
          ],
          for (final d in data.details) ...[
            const SizedBox(height: 2),
            Text(d, maxLines: 1, overflow: TextOverflow.ellipsis, style: quiet),
          ],
          if (data.time != null && data.time!.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              data.time!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: quiet.copyWith(color: c.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

/// The hairline and the dots of one resolved frame.
class KuteCrosshairPainter extends CustomPainter {
  final KuteCrosshairData? data;
  final Object? repaintKey;
  final bool isDark;
  final Color hairlineColor;

  KuteCrosshairPainter({
    required this.data,
    required this.repaintKey,
    required this.isDark,
    required this.hairlineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final d = data;
    if (d == null) return;

    final x = d.x.clamp(0.0, size.width).toDouble();
    final plotBottom =
        (d.plotBottom ?? size.height).clamp(0.0, size.height).toDouble();

    // Vertical hairline.
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, plotBottom),
      Paint()
        ..color = hairlineColor.withValues(alpha: 0.35)
        ..strokeWidth = 1.0,
    );

    // Dots.
    final core = isDark ? Colors.black : Colors.white;
    for (final dot in d.dots) {
      final y = dot.y.clamp(0.0, plotBottom).toDouble();
      canvas.drawCircle(Offset(x, y), 4.5, Paint()..color = dot.color);
      canvas.drawCircle(Offset(x, y), 2.0, Paint()..color = core);
    }
  }

  @override
  bool shouldRepaint(covariant KuteCrosshairPainter old) =>
      old.repaintKey != repaintKey ||
      old.isDark != isDark ||
      old.hairlineColor != hairlineColor ||
      old.data?.x != data?.x;
}
