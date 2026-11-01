// lib/screens/share/cards/share_card_frame.dart
//
// THE SHARE CARD FRAME (founder, 1 November 2026: restrained premium, the
// Robinhood / Revolut / Apple Card share cards; refined the same day:
// "bigger numbers and such", no band left mostly empty, and one edgy
// line written on the card). Every 4:5 share image, the brag cards and
// the claim screen's hero are this one layout, so the family reads as
// one:
//
//   * ONE solid background, no gradient, no glow: near-black
//     ([ShareCardPalette.dark]: stocks, sends, brag) or white with a
//     hairline ([ShareCardPalette.light]: predictions). 4:5 at
//     [kShareCardSize], captured at [kShareCardPixelRatio] (1080 × 1350),
//     [kShareCardPadding] all round, the hairline and the preview's clip at
//     [kShareCardRadius].
//   * THREE BANDS. TOP: a small caps line (12, letter-spaced 0.12 em,
//     55%: "ANA, A PICK FOR YOU", "FOR DANIEL", "MY PORTFOLIO"), then the
//     identity row ([ShareCardIdentity]: the logo 36 as a rounded square,
//     the name 18 w600, a muted meta "TSLA"). MIDDLE: the hero block, ONE
//     huge number ([ShareCardHeroNumber]: 64–80 by its length, shrunk to
//     the width down to 48, w600, −2% tracking, tabular: the price, the
//     chance, the amount or the P&L) and the fact line under it (18, in
//     the semantic colour or 60% ink: "+3.4% today", "All time"); it is
//     centred in the space left, or, on a card whose graphic fills
//     ([ShareCardFrame.graphicFills]: a chart, the portfolio's rows), it
//     follows the top band and the graphic takes the rest. BOTTOM: the
//     one graphic (a 2 px line over a 6% area with an end dot,
//     [ShareCardSparkline]; the 10 px odds bar with both sides named,
//     [ShareCardOddsBar]), the plain fact line ("Long · $25", "$10 on
//     Gen.G"), the EDGY LINE ([ShareCardFrame.line]: 20 w600, 90% ink, at
//     most two lines, deadpan and PG, share_card_copy.dart /
//     brag_lines.dart), a quiet line ("Claim it on Kute"), then the
//     footer.
//   * A money card centres its amount and fills the space with its
//     asset's mark as a watermark ([ShareCardFrame.watermark]: the ₿ or $
//     glyph, ~70% of the card's height, 4%, bottom right, clipped).
//   * FOOTER ([ShareCardFooter]): Sal as a small mark (a 28 px rounded
//     tile with his 3D face, [ShareCardMark]) and the "kute." wordmark
//     (20) on the left; "CODE JOAO42" (12, letter-spaced, muted) on the
//     right.
//
// No text scaling and the light Material theme inside, whatever the app's
// mode: the preview is exactly the image. Sal's face is decoded once
// ([ShareCardSal]) and handed in; the logos are the app's own widgets
// (HlCoinIcon, PolyCrestImage).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/polymarket/components/poly_crest_image.dart'
    show PolyCrestImage;
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

/// The caps line's tracking: 0.12 em at 12.
const double kShareCardCapsSize = 12;

/// The hero number's sizes: 80 for a short figure ("47%"), 72, 64 for a
/// long one, never under [kShareCardHeroMin] when shrunk to fit.
const double kShareCardHeroMax = 80;
const double kShareCardHeroMin = 48;

/// The fact line under the hero number.
const double kShareCardFactSize = 18;

/// The edgy line's size.
const double kShareCardLineSize = 20;

/// The hero number's style at [size]: w600, −2% tracking, tabular.
TextStyle shareCardHeroStyle(double size, Color color) =>
    shareCardText(size, FontWeight.w600, color,
        spacing: -0.02 * size, height: 1.04, tabular: true);

/// The hero number's size before fitting: 80 up to five characters, 72
/// up to seven, else 64.
double shareCardHeroBase(String text) {
  final n = text.characters.length;
  if (n <= 5) return kShareCardHeroMax;
  if (n <= 7) return 72;
  return 64;
}

/// The hero number's size for [text] in [width]: its base
/// ([shareCardHeroBase], or [max] when smaller), shrunk so it fits, never
/// under [kShareCardHeroMin] (a FittedBox takes over below that, so it
/// never overflows).
double shareCardHeroSize(String text, double width, {double? max}) {
  var base = shareCardHeroBase(text);
  if (max != null && max < base) base = max;
  if (!width.isFinite || width <= 0) return base;
  final tp = TextPainter(
    text: TextSpan(text: text, style: shareCardHeroStyle(base, Colors.black)),
    maxLines: 1,
    textDirection: TextDirection.ltr,
  )..layout();
  final w = tp.width;
  tp.dispose();
  if (w <= width) return base;
  return math.max(kShareCardHeroMin, base * width / w);
}

/// The one huge number, sized to its width ([shareCardHeroSize]); the
/// Text itself carries [textKey].
class ShareCardHeroNumber extends StatelessWidget {
  const ShareCardHeroNumber({
    super.key,
    required this.text,
    required this.color,
    this.textKey,
    this.max,
    this.center = false,
  });

  final String text;
  final Color color;
  final Key? textKey;
  final double? max;
  final bool center;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (_, box) {
        final size = shareCardHeroSize(text, box.maxWidth, max: max);
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: center ? Alignment.center : Alignment.centerLeft,
          child: Text(
            text,
            key: textKey,
            maxLines: 1,
            softWrap: false,
            style: shareCardHeroStyle(size, color),
          ),
        );
      });
}

/// The 4:5 card: one background and the layout (see the file header).
class ShareCardFrame extends StatelessWidget {
  const ShareCardFrame({
    super.key,
    required this.palette,
    required this.caps,
    this.identity,
    this.number,
    this.numberMax,
    this.fact,
    this.factColor,
    this.factSize = kShareCardFactSize,
    this.center = false,
    this.watermark,
    this.graphic,
    this.graphicFills = false,
    this.plain,
    this.line,
    this.quiet,
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

  /// The big number's largest size (null: by its length).
  final double? numberMax;

  /// The fact line under it; null: none.
  final String? fact;

  /// The fact line's colour; 60% ink by default.
  final Color? factColor;
  final double factSize;

  /// The hero block centred across the card (a money card).
  final bool center;

  /// A glyph drawn huge and faint at the bottom right (a money card's ₿
  /// or $).
  final String? watermark;

  /// The one graphic (a line, the odds bar, the portfolio's rows).
  final Widget? graphic;

  /// The graphic takes the space left (a line, the rows) and the hero
  /// block follows the top band; else the hero block is centred in the
  /// space left and the graphic sits under it at its own height.
  final bool graphicFills;

  /// One plain fact line under the graphic.
  final String? plain;

  /// The edgy line (20, w600, 90% ink, two lines at most).
  final String? line;

  /// A quiet muted line over the footer ("Claim it on Kute").
  final String? quiet;

  /// The sharer's referral code; null: none.
  final String? code;

  /// Sal's decoded face ([ShareCardSal]); null: the tile alone.
  final SalClip? mark;

  /// The keys' prefix: `{prefix}-bg`, `{prefix}-caps`, `{prefix}-hero`,
  /// `{prefix}-number`, `{prefix}-fact`, `{prefix}-graphic`,
  /// `{prefix}-plain`, `{prefix}-edge`, `{prefix}-quiet`,
  /// `{prefix}-watermark`, `{prefix}-footer`, `{prefix}-mark`,
  /// `{prefix}-wordmark`, `{prefix}-code`.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = palette;
    // Without a graphic the plain fact joins the hero block, so the block
    // sits centred between the identity and the bottom band.
    final plainInHero = graphic == null && plain != null;
    final plainText = plain == null
        ? null
        : Text(
            plain!,
            key: ValueKey('$keyPrefix-plain'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: center ? TextAlign.center : TextAlign.start,
            style: shareCardText(15, FontWeight.w500, p.ink,
                spacing: -0.1, tabular: true),
          );
    final hero = (number == null && fact == null && !plainInHero)
        ? null
        : Column(
            key: ValueKey('$keyPrefix-hero'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment:
                center ? CrossAxisAlignment.center : CrossAxisAlignment.stretch,
            children: [
              if (number != null)
                SizedBox(
                  key: ValueKey('$keyPrefix-number-box'),
                  width: double.infinity,
                  child: ShareCardHeroNumber(
                    textKey: ValueKey('$keyPrefix-number'),
                    text: number!,
                    color: p.ink,
                    max: numberMax,
                    center: center,
                  ),
                ),
              if (fact != null) ...[
                SizedBox(height: number != null ? 6 : 0),
                Text(
                  fact!,
                  key: ValueKey('$keyPrefix-fact'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: center ? TextAlign.center : TextAlign.start,
                  style: shareCardText(factSize, FontWeight.w500,
                      factColor ?? p.ink.withValues(alpha: 0.6),
                      spacing: -0.2, tabular: true),
                ),
              ],
              if (plainInHero) ...[
                SizedBox(height: number != null || fact != null ? 14 : 0),
                plainText!,
              ],
            ],
          );
    final keyedGraphic = graphic == null
        ? null
        : KeyedSubtree(key: ValueKey('$keyPrefix-graphic'), child: graphic!);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // TOP: the caps line and the identity.
        Text(
          caps.toUpperCase(),
          key: ValueKey('$keyPrefix-caps'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: shareCardText(kShareCardCapsSize, FontWeight.w600, p.muted,
              spacing: kShareCardCapsSize * 0.12, height: 1.2),
        ),
        if (identity != null) ...[
          const SizedBox(height: 12),
          identity!,
        ],
        // MIDDLE: the hero block.
        if (graphicFills) ...[
          if (hero != null) ...[
            SizedBox(height: identity != null ? 16 : 26),
            hero,
          ],
          Expanded(
            child: keyedGraphic == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: SizedBox.expand(child: keyedGraphic),
                  ),
          ),
        ] else ...[
          Expanded(
            child: hero == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Align(
                      alignment:
                          center ? Alignment.center : Alignment.centerLeft,
                      child: hero,
                    ),
                  ),
          ),
          if (keyedGraphic != null) keyedGraphic,
        ],
        // BOTTOM: the plain fact, the edgy line, the quiet line, the footer.
        if (plain != null && !plainInHero) ...[
          const SizedBox(height: 12),
          plainText!,
        ],
        if (line != null) ...[
          // Right under a centred hero block, the block's own margin is
          // the space, so it sits mid-way.
          SizedBox(
              height: plain != null && !plainInHero
                  ? 10
                  : !graphicFills && graphic == null && hero != null
                      ? 0
                      : 16),
          Text(
            line!,
            key: ValueKey('$keyPrefix-edge'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: shareCardText(kShareCardLineSize, FontWeight.w600,
                p.ink.withValues(alpha: 0.9),
                spacing: -0.4, height: 1.18),
          ),
        ],
        if (quiet != null) ...[
          const SizedBox(height: 10),
          Text(
            quiet!,
            key: ValueKey('$keyPrefix-quiet'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: shareCardText(14, FontWeight.w500, p.muted, spacing: -0.1),
          ),
        ],
        const SizedBox(height: 18),
        ShareCardFooter(
            key: ValueKey('$keyPrefix-footer'),
            palette: p,
            code: code,
            mark: mark,
            keyPrefix: keyPrefix),
      ],
    );
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
              child: ClipRect(
                // Inter for any text a logo's stand-in draws.
                child: DefaultTextStyle(
                  style: shareCardText(14, FontWeight.w500, p.ink),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (watermark != null)
                        Positioned(
                          right: -kShareCardSize.width * 0.16,
                          bottom: -kShareCardSize.height * 0.14,
                          child: Text(
                            watermark!,
                            key: ValueKey('$keyPrefix-watermark'),
                            maxLines: 1,
                            softWrap: false,
                            style: shareCardText(kShareCardSize.height * 0.8,
                                FontWeight.w700, p.ink.withValues(alpha: 0.04),
                                height: 1.0),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(kShareCardPadding),
                        child: body,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The identity row: [logo] (36, a rounded square), [name] (18, w600) and
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
    return Row(
      key: ValueKey('$keyPrefix-identity'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        logo,
        const SizedBox(width: 12),
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
                style: shareCardText(18, FontWeight.w600, palette.ink,
                    spacing: -0.3, height: 1.2),
              ),
              if (m.isNotEmpty) ...[
                const SizedBox(height: 1),
                Text(
                  m,
                  key: ValueKey('$keyPrefix-meta'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: shareCardText(14, FontWeight.w500, palette.muted,
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

/// A market's logo as a rounded square, through the app's own logo
/// widgets: the coin icon on an Investing market (HlCoinIcon), the
/// market's picture, crest or portrait on a prediction (PolyCrestImage,
/// which shows the app's own stand-in when there is none). Never a letter
/// tile of the card's own.
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
    this.round = false,
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

  /// A circle (a crest at the odds bar's end) instead of a rounded square.
  final bool round;

  @override
  Widget build(BuildContext context) {
    final r = round ? size / 2 : size * 0.27;
    final Widget child;
    if (investing) {
      child = ColoredBox(
        key: const ValueKey('share-card-logo-coin'),
        color: palette.tile,
        child: FittedBox(
          child: HlCoinIcon(
            coin: coin ?? title,
            wireCoin: wireCoin,
            iconUrl: iconUrl,
            category: category,
            size: size,
          ),
        ),
      );
    } else {
      child = PolyCrestImage(
        key: const ValueKey('share-card-logo-poly'),
        url: imageUrl ?? '',
        size: size,
        radius: r,
        label: title,
      );
    }
    return SizedBox.square(
        dimension: size,
        child: ClipRRect(borderRadius: BorderRadius.circular(r), child: child));
  }
}

/// Sal as a small mark: a 28 px rounded tile with his 3D face.
class ShareCardMark extends StatelessWidget {
  const ShareCardMark(
      {super.key, required this.palette, this.face, this.size = 28});

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
          child:
              face == null ? null : CustomPaint(painter: _FacePainter(face!)),
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
    final word = shareCardText(20, FontWeight.w700, palette.ink,
        spacing: -0.6, height: 1.0);
    final c = code?.trim() ?? '';
    return Row(
      children: [
        ShareCardMark(
            key: ValueKey('$keyPrefix-mark'), palette: palette, face: mark),
        const SizedBox(width: 9),
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
                  style: shareCardText(12, FontWeight.w600, palette.muted,
                      spacing: 12 * 0.12, tabular: true),
                ),
        ),
      ],
    );
  }
}

/// A 2 px smooth line through [points] (a price, a P&L) over a very
/// faint area (6% of the line's colour), ending on a dot.
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
    this.strokeWidth = 2,
    this.fillAlpha = 0.06,
    this.dotRadius = 4,
  });

  final List<double> points;
  final Color color;
  final double strokeWidth;
  final double fillAlpha;
  final double dotRadius;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2 || size.height < 8) return;
    var lo = points.reduce(math.min);
    var hi = points.reduce(math.max);
    if (hi - lo < 1e-9) {
      hi += 0.5;
      lo -= 0.5;
    }
    // Room for the end dot at the right and the top.
    final pad = math.max(strokeWidth, dotRadius + 1);
    double y(double v) =>
        pad + (1 - (v - lo) / (hi - lo)) * (size.height - 2 * pad);
    double x(int i) => i / (points.length - 1) * (size.width - pad);
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
    if (fillAlpha > 0) {
      final area = Path.from(line)
        ..lineTo(pts.last.dx, size.height)
        ..lineTo(pts.first.dx, size.height)
        ..close();
      canvas.drawPath(
          area,
          Paint()
            ..color = color.withValues(alpha: fillAlpha)
            ..style = PaintingStyle.fill);
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
    if (dotRadius > 0) {
      canvas.drawCircle(pts.last, dotRadius, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(ShareCardLinePainter old) =>
      old.points != points || old.color != color;
}

/// The 10 px odds bar, rounded, [fraction] (0–1) filled in [color], with
/// both sides named and their percents over it: [left] and [leftValue]
/// ("Gen.G 47%") in the bar's colour, [right] and [rightValue] ("T1 53%")
/// muted, a long name shortened before its percent ever is; the two
/// crests (20, round) at the bar's ends when both are there.
class ShareCardOddsBar extends StatelessWidget {
  const ShareCardOddsBar({
    super.key,
    required this.palette,
    required this.fraction,
    required this.left,
    this.leftValue,
    this.right,
    this.rightValue,
    this.leftImage,
    this.rightImage,
    this.color = kShareOddsBlue,
  });

  final ShareCardPalette palette;
  final double fraction;
  final String left;
  final String? leftValue;
  final String? right;
  final String? rightValue;
  final Widget? leftImage;
  final Widget? rightImage;
  final Color color;

  static const double barHeight = 10;
  static const double crestSize = 20;

  @override
  Widget build(BuildContext context) {
    final f = fraction.clamp(0.0, 1.0);
    final filled = (f * 1000).round();
    final crests = leftImage != null && rightImage != null;
    final bar = SizedBox(
      key: const ValueKey('share-card-odds-bar'),
      height: barHeight,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(barHeight / 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (filled > 0)
              Expanded(flex: filled, child: ColoredBox(color: color)),
            if (filled > 0 && filled < 1000) const SizedBox(width: 3),
            if (filled < 1000)
              Expanded(
                  flex: 1000 - filled, child: ColoredBox(color: palette.track)),
          ],
        ),
      ),
    );
    final style =
        shareCardText(16, FontWeight.w600, color, spacing: -0.2, tabular: true);
    Widget side(String name, String? value, TextStyle s, Key key) => Row(
          key: key,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(name,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: s),
            ),
            if (value != null) Text(' $value', maxLines: 1, style: s),
          ],
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          key: const ValueKey('share-card-odds-labels'),
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
                child: side(left, leftValue, style,
                    const ValueKey('share-card-odds-left'))),
            if (right != null) ...[
              const SizedBox(width: 16),
              Flexible(
                  child: side(
                      right!,
                      rightValue,
                      style.copyWith(color: palette.muted),
                      const ValueKey('share-card-odds-right'))),
            ],
          ],
        ),
        const SizedBox(height: 10),
        if (crests)
          Row(
            children: [
              SizedBox.square(dimension: crestSize, child: leftImage),
              const SizedBox(width: 8),
              Expanded(child: bar),
              const SizedBox(width: 8),
              SizedBox.square(dimension: crestSize, child: rightImage),
            ],
          )
        else
          bar,
      ],
    );
  }
}
