// lib/screens/share/cards/share_card_speedometer.dart
//
// THE SPEEDOMETER ON A PREDICTION CARD (founder, 2 November 2026: "on the
// predictions show our speedometer that we have for the open predictions,
// it's much better"). The open-position screen's dial
// (position_speedometer.dart), drawn still at the card's scale by its own
// painters: the thin track with its three ticks, the sweep from the left
// end to the needle, the price paid as a dot when there is one, the needle
// with its hub and grab knob; then, under the hub and centred as on the
// screen, the figure huge (the chance on a pick, the P&L on a brag) and
// its caption ("Chance of Gen.G").
//
// The colours are the card's: the track and the ticks in the card's ink
// at low strength, the sweep, the needle and the knob in the ink, the
// rings in the card's background. The dial takes the width the space
// allows, its figure growing with it (up to [ShareCardSpeedometer.
// figureMax]), so it fills the card's middle band without overflowing.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:kute/screens/polymarket/components/position_speedometer.dart'
    show
        PolySpeedometerDialPainter,
        PolySpeedometerNeedlePainter,
        PolySpeedometerSweepPainter,
        polySpeedometerGeometry;
import 'package:kute/screens/share/cards/share_card_frame.dart';

/// The widest the dial is drawn on a card.
const double kShareSpeedometerMaxWidth = 300;

/// The narrowest, however little room there is.
const double kShareSpeedometerMinWidth = 132;

class ShareCardSpeedometer extends StatelessWidget {
  const ShareCardSpeedometer({
    super.key,
    required this.palette,
    required this.fraction,
    required this.figure,
    this.caption,
    this.captionColor,
    this.entry,
    this.figureMax = kShareCardHeroMax,
    this.keyPrefix = 'share-card',
  });

  final ShareCardPalette palette;

  /// Where the needle stands, 0 to 1 (the held side's chance).
  final double fraction;

  /// The big text under the hub ("47%", "+$36.90").
  final String figure;

  /// The line under it ("Chance of Gen.G"); null: none.
  final String? caption;

  /// The caption's colour; the muted ink by default.
  final Color? captionColor;

  /// The price paid, 0 to 1, as a dot on the track; null: none.
  final double? entry;

  /// The figure's largest size.
  final double figureMax;

  /// The keys: `{prefix}-speedometer`, `{prefix}-number`, `{prefix}-fact`.
  final String keyPrefix;

  static const double _gap = 6;
  static const double _captionSize = 16;
  static const double _captionGap = 6;

  /// The figure's size on a dial [width] wide.
  double _figureSize(double width) =>
      (width * 0.26).clamp(kShareCardHeroMin * 0.8, figureMax).toDouble();

  /// The dial's own box height at [width] (polySpeedometerGeometry).
  static double _arcHeight(double width) =>
      polySpeedometerGeometry(width).size.height;

  double _height(double width) =>
      _arcHeight(width) +
      _gap +
      _figureSize(width) * 1.04 +
      (caption == null ? 0 : _captionGap + _captionSize * 1.2);

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final f = fraction.clamp(0.0, 1.0).toDouble();
    final e = entry != null && entry! > 0 && entry! < 1 ? entry : null;
    return LayoutBuilder(builder: (context, box) {
      final maxW = box.maxWidth.isFinite ? box.maxWidth : kShareCardSize.width;
      var width = math.min(maxW, kShareSpeedometerMaxWidth);
      if (box.maxHeight.isFinite) {
        while (width > kShareSpeedometerMinWidth &&
            _height(width) > box.maxHeight) {
          width -= 2;
        }
      }
      final g = polySpeedometerGeometry(width);
      final needle = AlwaysStoppedAnimation<double>(f);
      final figureSize = _figureSize(width);
      return Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: maxW,
            child: Column(
              key: ValueKey('$keyPrefix-speedometer'),
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.fromSize(
                  size: g.size,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CustomPaint(
                        painter: PolySpeedometerDialPainter(
                          geometry: g,
                          entry: e,
                          trackColor: p.track,
                          tickColor: p.muted,
                          entryColor: p.ink.withValues(alpha: 0.8),
                          ringColor: p.background,
                        ),
                      ),
                      CustomPaint(
                        painter: PolySpeedometerSweepPainter(
                          geometry: g,
                          needle: needle,
                          color: p.ink,
                          entry: e,
                          entryColor: p.ink.withValues(alpha: 0.8),
                          ringColor: p.background,
                        ),
                      ),
                      CustomPaint(
                        painter: PolySpeedometerNeedlePainter(
                          geometry: g,
                          needle: needle,
                          color: p.ink,
                          ringColor: p.background,
                        ),
                      ),
                    ],
                  ),
                ),
                // The hub's own room under the centre line is in the box;
                // the figure follows it, centred, as on the screen.
                const SizedBox(height: _gap),
                SizedBox(
                  width: maxW,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      figure,
                      key: ValueKey('$keyPrefix-number'),
                      maxLines: 1,
                      softWrap: false,
                      textAlign: TextAlign.center,
                      style: shareCardHeroStyle(figureSize, p.ink),
                    ),
                  ),
                ),
                if (caption != null) ...[
                  const SizedBox(height: _captionGap),
                  Text(
                    caption!,
                    key: ValueKey('$keyPrefix-fact'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: shareCardText(_captionSize, FontWeight.w500,
                        captionColor ?? p.muted,
                        spacing: -0.2, tabular: true),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    });
  }
}
