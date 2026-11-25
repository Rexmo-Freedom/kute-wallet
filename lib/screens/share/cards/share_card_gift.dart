// lib/screens/share/cards/share_card_gift.dart
//
// A PICK SENT IS A GIFT (founder, 7 November 2026, of "Send this
// investment" with Bitcoin's price huge on the card: "Make this more
// clear we are sending"). A prediction or an investment sent on a link
// (the sender's card and the Claim screen's hero; share_cards.dart) reads
// as the money cards do, the gift first:
//
//   * the caps line: "ANA, AN INVESTMENT FOR YOU", "ANA, A PREDICTION
//     FOR YOU" (the recipient's "DANIEL, A FRIEND SENT YOU"), on two
//     lines beside Sal rather than cut;
//   * THE AMOUNT SENT huge ("$50"), the money card's size, beside Sal at
//     the top right (he sits with the coin on his head, the gift's pose);
//   * right under it THE POSITION, one clear line in big type
//     ([ShareCardPositionLine]): "Short Bitcoin", "Long Tesla", "Yes ·
//     Lula to win", a yes/no pick "Yes"; the side word in its colour
//     ([ShareCardPalette.side]: the market's green and red on the navy,
//     mint and pink on the blue);
//   * then THE CONTEXT, smaller and secondary ([ShareCardGiftContext]):
//     the market's logo and name (an investment's ticker, its price and
//     "−0.2% today" at the right, the last 30 days' line under them; a
//     prediction's question, its speedometer small with the chance and
//     "Chance of Gen.G" beside it, [ShareCardSpeedometerRow]);
//   * the edgy line, the wordmark and the code, as every card.
//
// A market shared without a pick keeps the price (or the odds) as its
// hero; a dare keeps both sides.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:kute/screens/polymarket/components/position_speedometer.dart'
    show
        PolySpeedometerDialPainter,
        PolySpeedometerNeedlePainter,
        PolySpeedometerSweepPainter,
        polySpeedometerGeometry;
import 'package:kute/screens/share/cards/share_card_frame.dart';

/// A gift's position, split around its side word: "" + "Short" + "
/// Bitcoin", "" + "Yes" + " · Lula to win"; [up]: a Yes or a Long.
typedef ShareCardPosition = ({
  String before,
  String side,
  String after,
  bool up,
});

/// The position line's sizes: [kShareCardPositionSize] on one line, else
/// [kShareCardPositionSmall] on up to two.
const double kShareCardPositionSize = 26;
const double kShareCardPositionSmall = 21;

/// The context's title steps: smaller than an identity's (the context is
/// secondary), still whole on up to three lines.
const List<(double, int)> kShareCardGiftTitleSteps = [
  (16, 2),
  (15, 3),
  (14, 3),
];

/// The position under a gift's amount (see the file header).
class ShareCardPositionLine extends StatelessWidget {
  const ShareCardPositionLine({
    super.key,
    required this.position,
    required this.palette,
    this.textKey,
  });

  final ShareCardPosition position;
  final ShareCardPalette palette;
  final Key? textKey;

  TextStyle _style(double size) =>
      shareCardText(size, FontWeight.w800, palette.ink,
          spacing: -0.02 * size, height: 1.15, tabular: true);

  TextSpan _span(double size) {
    final base = _style(size);
    return TextSpan(style: base, children: [
      if (position.before.isNotEmpty) TextSpan(text: position.before),
      TextSpan(
          text: position.side,
          style: base.copyWith(color: palette.side(up: position.up))),
      if (position.after.isNotEmpty) TextSpan(text: position.after),
    ]);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        var size = kShareCardPositionSize;
        var lines = 1;
        if (box.maxWidth.isFinite) {
          final tp = TextPainter(
            text: _span(size),
            textDirection: Directionality.of(context),
            maxLines: 1,
          )..layout(maxWidth: box.maxWidth);
          if (tp.didExceedMaxLines) {
            size = kShareCardPositionSmall;
            lines = 2;
          }
          tp.dispose();
        }
        return Text.rich(
          _span(size),
          key: textKey,
          maxLines: lines,
          overflow: TextOverflow.ellipsis,
        );
      });
}

/// A gift's context (see the file header): [logo], [name] and a muted
/// [meta] under it, [trailing] at the right (an investment's price and
/// today's change), then [below] filling the rest (the line, the
/// speedometer). The keys: `{prefix}-context`, `{prefix}-identity`,
/// `{prefix}-title-tail`, `{prefix}-meta`.
class ShareCardGiftContext extends StatelessWidget {
  const ShareCardGiftContext({
    super.key,
    required this.palette,
    required this.logo,
    required this.name,
    this.meta,
    this.trailing,
    this.below,
    this.keyPrefix = 'share-card',
  });

  final ShareCardPalette palette;
  final Widget logo;
  final String name;
  final String? meta;
  final Widget? trailing;
  final Widget? below;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final m = meta?.trim() ?? '';
    final identity = Row(
      key: ValueKey('$keyPrefix-identity'),
      children: [
        logo,
        const SizedBox(width: ShareCardIdentity.logoGap),
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            final w = box.maxWidth;
            final fit = shareCardTitleFit(name,
                narrow: w,
                wide: w,
                direction: Directionality.of(context),
                steps: kShareCardGiftTitleSteps);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  key: ValueKey('$keyPrefix-title-tail'),
                  maxLines: kShareCardGiftTitleSteps.last.$2,
                  overflow: TextOverflow.ellipsis,
                  style: shareCardTitleStyle(fit.size, palette.ink),
                ),
                if (m.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    m,
                    key: ValueKey('$keyPrefix-meta'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: shareCardText(13, FontWeight.w500, palette.muted,
                        height: 1.25),
                  ),
                ],
              ],
            );
          }),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 12),
          trailing!,
        ],
      ],
    );
    return Column(
      key: ValueKey('$keyPrefix-context'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        identity,
        if (below != null)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SizedBox.expand(child: below),
            ),
          ),
      ],
    );
  }
}

/// An investment's price and today's change at the right of a gift's
/// context: "$75,966.50" over "−0.2% today" in the change's colour.
class ShareCardPriceColumn extends StatelessWidget {
  const ShareCardPriceColumn({
    super.key,
    required this.palette,
    this.price,
    this.change,
    this.changeColor,
    this.keyPrefix = 'share-card',
  });

  final ShareCardPalette palette;
  final String? price;
  final String? change;
  final Color? changeColor;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (price != null)
            Text(
              price!,
              key: ValueKey('$keyPrefix-price'),
              maxLines: 1,
              style: shareCardText(16, FontWeight.w600, palette.ink,
                  spacing: -0.2, tabular: true),
            ),
          if (change != null) ...[
            SizedBox(height: price != null ? 2 : 0),
            Text(
              change!,
              key: ValueKey('$keyPrefix-fact'),
              maxLines: 1,
              style: shareCardText(
                  14, FontWeight.w600, changeColor ?? palette.muted,
                  spacing: -0.1, tabular: true),
            ),
          ],
        ],
      );
}

/// The prediction's speedometer, small, on a gift: the open-position
/// screen's dial (its own painters, as share_card_speedometer.dart draws
/// it) as large as the room allows up to [maxDial], the chance and its
/// caption beside it at the left edge. The keys: `{prefix}-speedometer`
/// (the dial), `{prefix}-chance`, `{prefix}-chance-caption`.
class ShareCardSpeedometerRow extends StatelessWidget {
  const ShareCardSpeedometerRow({
    super.key,
    required this.palette,
    required this.fraction,
    required this.figure,
    this.caption,
    this.keyPrefix = 'share-card',
  });

  final ShareCardPalette palette;

  /// Where the needle stands, 0 to 1.
  final double fraction;

  /// The chance ("47%").
  final String figure;

  /// "Chance of Gen.G"; null: none.
  final String? caption;
  final String keyPrefix;

  /// The widest the dial is drawn here, and the narrowest. In a tight
  /// band (a long question under two caps lines) the dial would be a
  /// blob: the Predictions list's own half-ring gauge instead
  /// ([kShareCardRingSize]), the chance and its caption on one line
  /// beside it.
  static const double maxDial = 132;
  static const double minDial = 72;

  static const double _captionSize = 14;

  /// The chance over its caption: the room it takes at the smallest
  /// figure (24).
  static const double _stackedHeight = 24 * 1.04 + 2 + _captionSize * 1.2;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final f = fraction.clamp(0.0, 1.0).toDouble();
    return LayoutBuilder(builder: (context, box) {
      final h = box.maxHeight.isFinite ? box.maxHeight : 80.0;
      final compact = h < _stackedHeight + 2;
      var w =
          math.min(maxDial, box.maxWidth.isFinite ? box.maxWidth / 2 : maxDial);
      while (w > minDial && polySpeedometerGeometry(w).size.height > h) {
        w -= 2;
      }
      final g = polySpeedometerGeometry(w);
      final needle = AlwaysStoppedAnimation<double>(f);
      final figureSize =
          compact ? 20.0 : (g.size.height * 0.5).clamp(24.0, 34.0).toDouble();
      final figureText = Text(
        figure,
        key: ValueKey('$keyPrefix-chance'),
        maxLines: 1,
        style: shareCardHeroStyle(figureSize, p.ink),
      );
      Widget? captionText(int lines) => caption == null
          ? null
          : Text(
              caption!,
              key: ValueKey('$keyPrefix-chance-caption'),
              maxLines: lines,
              overflow: TextOverflow.ellipsis,
              style: shareCardText(_captionSize, FontWeight.w500, p.muted,
                  spacing: -0.1, height: 1.2),
            );
      final dial = compact
          ? SizedBox.fromSize(
              key: ValueKey('$keyPrefix-speedometer'),
              size: kShareCardRingSize,
              child: CustomPaint(
                painter: _HalfRingPainter(
                    fraction: f, track: p.track, fill: p.ink, stroke: 4),
              ),
            )
          : SizedBox.fromSize(
              key: ValueKey('$keyPrefix-speedometer'),
              size: g.size,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(
                    painter: PolySpeedometerDialPainter(
                      geometry: g,
                      entry: null,
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
                      entry: null,
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
            );
      final caption1 = captionText(1);
      final caption2 = captionText(2);
      final row = Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          dial,
          SizedBox(width: compact ? 10 : 14),
          if (compact) ...[
            figureText,
            if (caption1 != null) ...[
              const SizedBox(width: 8),
              Flexible(child: caption1),
            ],
          ] else
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  figureText,
                  if (caption2 != null) ...[
                    const SizedBox(height: 2),
                    caption2,
                  ],
                ],
              ),
            ),
        ],
      );
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: SizedBox(
              width: box.maxWidth.isFinite ? box.maxWidth : null, child: row),
        ),
      );
    });
  }
}

/// The half-ring gauge's size in a tight band (the Predictions list's own
/// gauge, search_rows.dart, at the card's scale).
const Size kShareCardRingSize = Size(44, 24);

/// The gauge's ring: the upper half of a circle, open at the bottom, the
/// track whole and the fill from the left end for [fraction] of it.
class _HalfRingPainter extends CustomPainter {
  const _HalfRingPainter({
    required this.fraction,
    required this.track,
    required this.fill,
    required this.stroke,
  });

  final double fraction;
  final Color track;
  final Color fill;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final r = (size.width - stroke) / 2;
    final rect = Rect.fromCircle(
        center: Offset(size.width / 2, size.height - stroke / 2), radius: r);
    Paint paint(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, math.pi, math.pi, false, paint(track));
    final sweep = math.pi * fraction.clamp(0.0, 1.0);
    if (sweep > 0) canvas.drawArc(rect, math.pi, sweep, false, paint(fill));
  }

  @override
  bool shouldRepaint(_HalfRingPainter old) =>
      old.fraction != fraction ||
      old.track != track ||
      old.fill != fill ||
      old.stroke != stroke;
}
