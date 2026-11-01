// lib/screens/share/cards/share_card_frame.dart
//
// THE SHARE CARD FRAME (founder, 1 November 2026: restrained premium, the
// Robinhood / Revolut / Apple Card share cards; the first look, with its
// speech bubble, glows, pills and posing Sal, read as cheap). Every 4:5
// share image, the brag cards and the claim screen's hero are this one
// layout, so the family reads as one:
//
//   * ONE solid background, no gradient, no glow: near-black
//     ([ShareCardPalette.dark]: stocks, sends, brag) or white with a
//     hairline ([ShareCardPalette.light]: predictions). 4:5 at
//     [kShareCardSize], captured at [kShareCardPixelRatio] (1080 × 1350),
//     [kShareCardPadding] all round, the hairline and the preview's clip at
//     [kShareCardRadius].
//   * TOP: a small caps line, 11, letter-spaced, 55% ("ANA, A PICK FOR
//     YOU", "FOR DANIEL", "MY PORTFOLIO"); then the identity row
//     ([ShareCardIdentity]): the logo 26 as a rounded square, the name 15
//     w600 and a muted meta ("TSLA").
//   * ONE big number (40, w600, tabular, tight): the price, the chance, the
//     amount or the P&L, and one fact line under it in the semantic colour
//     or muted ("+3.4% today", "in bitcoin · ₿12,000", "All time").
//   * At most ONE thin graphic: a 1.6 px line ([ShareCardSparkline]) or a
//     6 px odds bar with its two outcomes under it ([ShareCardOddsBar]).
//   * One plain fact line when needed ("$10 on Gen.G", "Long · $25").
//   * FOOTER ([ShareCardFooter]): Sal as a small mark (a 22 px rounded
//     tile with his 3D face, [ShareCardMark]) and the "kute." wordmark on
//     the left; "CODE JOAO42" in small caps, muted, on the right.
//
// No text scaling and the light Material theme inside, whatever the app's
// mode: the preview is exactly the image. The card never loads anything:
// Sal's face is decoded once ([ShareCardSal]) and handed in.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/shared/sal_sprite.dart'
    show SalClip, SalSpriteCache;
import 'package:kute/theme/app_theme.dart';

/// The card's logical size: 4:5.
const Size kShareCardSize = Size(360, 450);

/// The capture's pixel ratio: [kShareCardSize] × 3 = 1080 × 1350.
const double kShareCardPixelRatio = 3;

/// The margin all round.
const double kShareCardPadding = 24;

/// The card's corner (the hairline, and the preview's clip at 360 wide).
const double kShareCardRadius = 24;

const String kShareCardFont = 'Inter';

/// Glyphs Inter lacks (Japanese): the system's own CJK face first.
const List<String> kShareCardFallback = ['Hiragino Sans'];

/// The card's text style: Inter, no decoration, tabular figures on ask.
TextStyle shareCardText(double size, FontWeight weight, Color color,
        {double spacing = 0, double height = 1.2, bool tabular = false}) =>
    TextStyle(
      fontFamily: kShareCardFont,
      fontFamilyFallback: kShareCardFallback,
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: spacing,
      height: height,
      decoration: TextDecoration.none,
      fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
    );

/// A card's colours: one background, the ink, the muted ink (55%), the
/// semantic up / down, the tile behind a logo or Sal, the hairline.
@immutable
class ShareCardPalette {
  const ShareCardPalette({
    required this.background,
    required this.ink,
    required this.up,
    required this.down,
    required this.tile,
    required this.track,
    this.hairline,
  });

  final Color background;
  final Color ink;
  final Color up;
  final Color down;
  final Color tile;

  /// The odds bar's empty part.
  final Color track;

  /// The edge on a white card; null on the dark one.
  final Color? hairline;

  Color get muted => ink.withValues(alpha: 0.55);

  /// Near-black: stocks, sends, brag.
  static const ShareCardPalette dark = ShareCardPalette(
    background: Color(0xFF0E0F12),
    ink: Color(0xFFFFFFFF),
    up: Color(0xFF2BD47F),
    down: Color(0xFFFF5A6A),
    tile: Color(0xFF1D1F24),
    track: Color(0x24FFFFFF),
  );

  /// White with a hairline: predictions.
  static const ShareCardPalette light = ShareCardPalette(
    background: Color(0xFFFFFFFF),
    ink: Color(0xFF0E0F12),
    up: Color(0xFF0B9A55),
    down: Color(0xFFE0334A),
    tile: Color(0xFFF1F2F4),
    track: Color(0xFFE9EAED),
    hairline: Color(0x1A0E0F12),
  );

  /// [value]'s colour: up, down, or muted when within [flat] of zero or
  /// null.
  Color signed(double? value, {double flat = 0}) {
    if (value == null || value.abs() <= flat) return muted;
    return value > 0 ? up : down;
  }
}

/// The odds bar's fill on a prediction card.
const Color kShareOddsBlue = Color(0xFF2F6BFF);

/// Decodes Sal's face once (the `share` clip's first frame, the sheet at
/// @3x) for a card that never loads anything itself.
abstract final class ShareCardSal {
  static const String clip = 'share';
  static SalClip? _face;
  static Future<SalClip?>? _loading;

  /// The decoded face, or null until [load] has finished.
  static SalClip? peek() => _face;

  /// Decodes the face (once); null when it cannot be read.
  static Future<SalClip?> load() {
    final done = _face;
    if (done != null) return Future.value(done);
    return _loading ??= SalSpriteCache.clip(clip, 3).then((c) {
      _face = c;
      _loading = null;
      return c;
    }, onError: (Object _) {
      _loading = null;
      return null;
    });
  }

  /// Tests: forget the decoded face.
  static void debugReset() {
    _face = null;
    _loading = null;
  }
}

/// The 4:5 card: one background and the layout (see the file header).
class ShareCardFrame extends StatelessWidget {
  const ShareCardFrame({
    super.key,
    required this.palette,
    required this.caps,
    this.identity,
    this.number,
    this.fact,
    this.factColor,
    this.graphic,
    this.graphicFills = false,
    this.graphicAtBottom = false,
    this.plain,
    this.code,
    this.mark,
    this.keyPrefix = 'share-card',
  });

  final ShareCardPalette palette;

  /// The small caps line at the top (uppercased here).
  final String caps;

  /// The logo, the name and the meta.
  final ShareCardIdentity? identity;

  /// The one big number; null: none.
  final String? number;

  /// The fact line under it; null: none.
  final String? fact;

  /// The fact line's colour; muted by default.
  final Color? factColor;

  /// The one graphic (a line, the odds bar, the portfolio's rows), in the
  /// space between the number and the footer.
  final Widget? graphic;

  /// The graphic takes the whole space (a line); else it sits at the top
  /// of it (the odds bar) or, with [graphicAtBottom], at its bottom (the
  /// portfolio's rows).
  final bool graphicFills;
  final bool graphicAtBottom;

  /// One plain fact line over the footer.
  final String? plain;

  /// The sharer's referral code; null: none.
  final String? code;

  /// Sal's decoded face ([ShareCardSal]); null: the tile alone.
  final SalClip? mark;

  /// The keys' prefix: `{prefix}-bg`, `{prefix}-caps`, `{prefix}-number`,
  /// `{prefix}-fact`, `{prefix}-plain`, `{prefix}-graphic`,
  /// `{prefix}-mark`, `{prefix}-wordmark`, `{prefix}-code`.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = palette;
    return Theme(
      // The light colours for the icons inside, whatever the app's mode.
      data: theme.copyWith(
          brightness: Brightness.light,
          extensions: [AppColorsExtension.light()]),
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
        child: SizedBox.fromSize(
          size: kShareCardSize,
          child: DecoratedBox(
            key: ValueKey('$keyPrefix-bg'),
            decoration: BoxDecoration(color: p.background),
            position: DecorationPosition.background,
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(kShareCardRadius),
                border: p.hairline == null
                    ? null
                    : Border.all(color: p.hairline!, width: 1),
              ),
              child: Padding(
                padding: const EdgeInsets.all(kShareCardPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      caps.toUpperCase(),
                      key: ValueKey('$keyPrefix-caps'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: shareCardText(11, FontWeight.w600, p.muted,
                          spacing: 1.4, height: 1.2),
                    ),
                    if (identity != null) ...[
                      const SizedBox(height: 16),
                      identity!,
                    ],
                    if (number != null) ...[
                      SizedBox(height: identity != null ? 30 : 22),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          number!,
                          key: ValueKey('$keyPrefix-number'),
                          maxLines: 1,
                          style: shareCardText(40, FontWeight.w600, p.ink,
                              spacing: -1.4, height: 1.05, tabular: true),
                        ),
                      ),
                    ],
                    if (fact != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        fact!,
                        key: ValueKey('$keyPrefix-fact'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: shareCardText(
                            14, FontWeight.w500, factColor ?? p.muted,
                            spacing: -0.1, tabular: true),
                      ),
                    ],
                    Expanded(
                      child: graphic == null
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: EdgeInsets.only(
                                  top: graphicFills || graphicAtBottom ? 22 : 30),
                              child: KeyedSubtree(
                                key: ValueKey('$keyPrefix-graphic'),
                                child: graphicFills
                                    ? SizedBox.expand(child: graphic)
                                    : Align(
                                        alignment: graphicAtBottom
                                            ? Alignment.bottomLeft
                                            : Alignment.topLeft,
                                        child: graphic),
                              ),
                            ),
                    ),
                    if (plain != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        plain!,
                        key: ValueKey('$keyPrefix-plain'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: shareCardText(14, FontWeight.w500, p.ink,
                            spacing: -0.1, tabular: true),
                      ),
                    ],
                    const SizedBox(height: 20),
                    ShareCardFooter(
                        palette: p,
                        code: code,
                        mark: mark,
                        keyPrefix: keyPrefix),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The identity row: [logo] (26, a rounded square), [name] (15, w600) and
/// a muted [meta] under it.
class ShareCardIdentity extends StatelessWidget {
  const ShareCardIdentity({
    super.key,
    required this.palette,
    required this.logo,
    required this.name,
    this.meta,
    this.nameMaxLines = 1,
    this.keyPrefix = 'share-card',
  });

  final ShareCardPalette palette;
  final Widget logo;
  final String name;
  final String? meta;
  final int nameMaxLines;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final m = meta?.trim() ?? '';
    final single = m.isEmpty && nameMaxLines == 1;
    return Row(
      crossAxisAlignment:
          single ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        logo,
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                key: ValueKey('$keyPrefix-title'),
                maxLines: nameMaxLines,
                overflow: TextOverflow.ellipsis,
                style: shareCardText(15, FontWeight.w600, palette.ink,
                    spacing: -0.2, height: 1.25),
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
          ),
        ),
      ],
    );
  }
}

/// A market's logo as a rounded square: the coin icon on an Investing
/// market, the market's picture on a prediction, else its first letter on
/// the palette's tile.
class ShareCardLogo extends StatelessWidget {
  const ShareCardLogo({
    super.key,
    required this.size,
    required this.title,
    required this.investing,
    required this.palette,
    this.coin,
    this.wireCoin,
    this.iconUrl,
    this.category,
    this.imageUrl,
  });

  final double size;
  final String title;
  final bool investing;
  final ShareCardPalette palette;
  final String? coin;
  final String? wireCoin;
  final String? iconUrl;
  final String? category;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.27);
    final Widget fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: palette.tile,
      child: Text(
        title.isEmpty ? '?' : title.characters.first.toUpperCase(),
        style: shareCardText(size * 0.46, FontWeight.w600, palette.ink),
      ),
    );
    final Widget child;
    if (investing && coin != null) {
      child = ColoredBox(
        color: palette.tile,
        child: FittedBox(
          child: HlCoinIcon(
            coin: coin!,
            wireCoin: wireCoin,
            iconUrl: iconUrl,
            category: category,
            size: size,
          ),
        ),
      );
    } else if (imageUrl case final url? when url.isNotEmpty) {
      child = Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      );
    } else {
      child = fallback;
    }
    return SizedBox.square(
        dimension: size, child: ClipRRect(borderRadius: radius, child: child));
  }
}

/// A plain glyph logo ("₿" on bitcoin orange, "$" on Kute green).
class ShareCardGlyphLogo extends StatelessWidget {
  const ShareCardGlyphLogo(
      {super.key, required this.glyph, required this.color, this.size = 26});

  final String glyph;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(size * 0.27)),
        child: Text(glyph,
            style: shareCardText(size * 0.56, FontWeight.w700, Colors.white,
                height: 1.0)),
      );
}

/// Sal as a small mark: a 22 px rounded tile with his 3D face.
class ShareCardMark extends StatelessWidget {
  const ShareCardMark(
      {super.key, required this.palette, this.face, this.size = 22});

  final ShareCardPalette palette;
  final SalClip? face;
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.28),
        child: Container(
          width: size,
          height: size,
          color: palette.tile,
          child: face == null ? null : CustomPaint(painter: _FacePainter(face!)),
        ),
      );
}

class _FacePainter extends CustomPainter {
  _FacePainter(this.face);

  final SalClip face;

  @override
  void paint(Canvas canvas, Size size) {
    // The face's own cell, a touch larger than the tile so the render's
    // margin does not read as a frame.
    final dst = (Offset.zero & size).inflate(size.width * 0.06);
    canvas.drawImageRect(face.image, face.cell(0), dst,
        Paint()..filterQuality = FilterQuality.high);
  }

  @override
  bool shouldRepaint(_FacePainter old) => !identical(old.face, face);
}

/// The footer: Sal's mark and the wordmark, the referral code at the
/// right.
class ShareCardFooter extends StatelessWidget {
  const ShareCardFooter({
    super.key,
    required this.palette,
    required this.code,
    this.mark,
    this.keyPrefix = 'share-card',
  });

  final ShareCardPalette palette;
  final String? code;
  final SalClip? mark;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final word = shareCardText(17, FontWeight.w700, palette.ink,
        spacing: -0.5, height: 1.0);
    final c = code?.trim() ?? '';
    return Row(
      children: [
        ShareCardMark(
            key: ValueKey('$keyPrefix-mark'), palette: palette, face: mark),
        const SizedBox(width: 8),
        Text.rich(
          key: ValueKey('$keyPrefix-wordmark'),
          TextSpan(children: [
            TextSpan(text: 'kute', style: word),
            TextSpan(text: '.', style: word.copyWith(color: AppColors.accent)),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: c.isEmpty
              ? const SizedBox.shrink()
              : Text(
                  '${context.l10n.bragCodeLabel} $c'.toUpperCase(),
                  key: ValueKey('$keyPrefix-code'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: shareCardText(11, FontWeight.w600, palette.muted,
                      spacing: 1.4, tabular: true),
                ),
        ),
      ],
    );
  }
}

/// A 1.6 px smooth line through [points] (a price, a P&L), no fill.
class ShareCardSparkline extends StatelessWidget {
  const ShareCardSparkline(
      {super.key, required this.points, required this.color});

  final List<double> points;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: ShareCardLinePainter(points: points, color: color));
}

/// The line under [ShareCardSparkline].
class ShareCardLinePainter extends CustomPainter {
  ShareCardLinePainter({
    required this.points,
    required this.color,
    this.strokeWidth = 1.6,
  });

  final List<double> points;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2 || size.height < 8) return;
    var lo = points.reduce(math.min);
    var hi = points.reduce(math.max);
    if (hi - lo < 1e-9) {
      hi += 0.5;
      lo -= 0.5;
    }
    final pad = strokeWidth;
    double y(double v) =>
        pad + (1 - (v - lo) / (hi - lo)) * (size.height - 2 * pad);
    double x(int i) => pad + i / (points.length - 1) * (size.width - 2 * pad);
    final pts = [
      for (var i = 0; i < points.length; i++) Offset(x(i), y(points[i]))
    ];
    // Catmull-Rom through the points as cubic Béziers, the control points
    // kept inside the plot so a swing never overshoots the edge.
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    double clampY(double v) => v.clamp(pad, size.height - pad);
    for (var i = 0; i < pts.length - 1; i++) {
      final p0 = pts[math.max(0, i - 1)];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = pts[math.min(pts.length - 1, i + 2)];
      final c1 = p1 + (p2 - p0) / 6;
      final c2 = p2 - (p3 - p1) / 6;
      line.cubicTo(c1.dx, clampY(c1.dy), c2.dx, clampY(c2.dy), p2.dx, p2.dy);
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(ShareCardLinePainter old) =>
      old.points != points || old.color != color;
}

/// A 6 px odds bar, [fraction] (0–1) filled, with [left] (the outcome)
/// and [right] (the other side) under it.
class ShareCardOddsBar extends StatelessWidget {
  const ShareCardOddsBar({
    super.key,
    required this.palette,
    required this.fraction,
    required this.left,
    this.right,
    this.color = kShareOddsBlue,
  });

  final ShareCardPalette palette;
  final double fraction;
  final String left;
  final String? right;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final f = fraction.clamp(0.0, 1.0);
    final filled = (f * 1000).round();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 6,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (filled > 0)
                  Expanded(flex: filled, child: ColoredBox(color: color)),
                if (filled > 0 && filled < 1000) const SizedBox(width: 2),
                if (filled < 1000)
                  Expanded(
                      flex: 1000 - filled,
                      child: ColoredBox(color: palette.track)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(left,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: shareCardText(12, FontWeight.w600, palette.ink)),
            ),
            if (right != null) ...[
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(right!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: shareCardText(12, FontWeight.w500, palette.muted)),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
