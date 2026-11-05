// lib/screens/share/cards/share_card_frame.dart
//
// THE SHARE CARD FRAME (founder, 1 November 2026: restrained premium, the
// Robinhood / Revolut / Apple Card share cards; refined the same day:
// "bigger numbers and such", no band left mostly empty, and one edgy
// line written on the card; 2 November 2026: "don't have the cards just
// black and white", the earlier colours back, and "Sal should have more
// expression there"; then, of the bitcoin gift: "this card looks bad":
// a dead gap under the amount, unreadable 55% text, a disc behind Sal
// like a blob, so the pass below). Every 4:5 share image, the brag cards,
// the P&L card and the claim screen's hero are this one layout, so the
// family reads as one:
//
//   * ONE solid background in the card's colour, no gradient, no glow
//     ([ShareCardPalette]: bitcoin orange, dollars green, predictions
//     blue, investing navy; a brag card green, red or navy by its tone),
//     the ink with its contrast on it. 4:5 at [kShareCardSize], captured
//     at [kShareCardPixelRatio] (1080 × 1350), [kShareCardPadding] all
//     round, the preview's clip at [kShareCardRadius].
//   * ONE LEFT EDGE: every line starts at the padding, the money cards'
//     amount too (a centred amount over left-set lines read as two
//     layouts).
//   * SAL, whole ([ShareCardFrame.pose], a still of the 3D Sal): lounging
//     on a win, a flop on a loss, the briefcase on a send, squinting at a
//     prediction (deadpan). Over a card whose graphic fills the middle he
//     sits at the top right ([kShareCardSalSize]); the caps line and the
//     identity leave him room ([kShareCardSalInset]) and a big number
//     right under them starts below his feet ([kShareCardSalBand]). On a
//     card with nothing filling its middle (a money card, a stock without
//     its chart) he STANDS ON THE RULE at the right, bigger
//     ([kShareCardSalFloorSize], smaller only when a tall number leaves
//     less room), filling the room under the number that was a dead gap.
//     He casts a soft shadow of his own silhouette
//     ([ShareCardPalette.salShadow]), so he never melts into the bitcoin
//     orange, his own colour (it replaced a deeper-orange disc).
//   * READABLE IN A SHARED IMAGE: the secondary ink is per ground
//     ([ShareCardPalette.mutedAlpha]: 4.5:1 where the ground allows it;
//     white tops out at 3.1:1 on the dollars green and 4.2:1 on the loss
//     red, so there it is near the full ink), no 12 px text.
//   * THREE BANDS. TOP: the caps line (13 w700, tracked 0.1 em, muted:
//     "ANA, A PICK FOR YOU", "FOR DANIEL", "MY PORTFOLIO"), then the
//     identity row ([ShareCardIdentity]: the logo 36 as a rounded square,
//     the name 18 w600, a muted meta "TSLA"). MIDDLE: the hero block, ONE
//     huge number ([ShareCardHeroNumber]: 64–80 by its length, a money
//     card's amount from 96 [kShareCardMoneyHeroMax], shrunk to the width
//     down to 48, w600, −2% tracking, tabular: the price, the amount or
//     the P&L) and the fact line under it (18, in the semantic colour or
//     muted: "+3.4% today", "All time"); under the top band beside Sal on
//     the rule, centred in the space left without him, or, on a card
//     whose graphic fills ([ShareCardFrame.graphicFills]: a chart, the
//     portfolio's rows, the prediction's speedometer with its own figure
//     under the hub, share_card_speedometer.dart), following the top band
//     with the graphic taking the rest. BOTTOM: the plain fact line
//     ("Long · $25", "$10 on Gen.G"), a hairline RULE (the floor Sal
//     stands on), the EDGY LINE ([ShareCardFrame.line]: 22 w700, the full
//     ink, the card's voice, at most two lines set even
//     [ShareCardBalancedText], deadpan and PG, share_card_copy.dart /
//     brag_lines.dart), a quiet line ("Claim it on Kute", 15 w600, muted),
//     then the footer.
//   * FOOTER ([ShareCardFooter]): the "kute." wordmark (22) on the left
//     (Sal's small face tile before it only on a card without a pose);
//     the code in a quiet capsule on the right ("CODE" muted, "JOAO42" in
//     the full ink, 13), big enough to type from the image.
//
// No text scaling and the light Material theme inside, whatever the app's
// mode: the preview is exactly the image. Sal's stills and face are
// decoded once ([ShareCardSal]) and read synchronously; the logos are the
// app's own widgets (HlCoinIcon, PolyCrestImage).

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/polymarket/components/poly_crest_image.dart'
    show PolyCrestImage;
import 'package:kute/screens/shared/sal_sprite.dart'
    show SalClip, SalSpriteCache;
import 'package:kute/theme/app_theme.dart';

/// A strong plain line's size ([ShareCardFrame.plainStrong]).
const double kShareCardPlainStrongSize = 24;

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

/// A card's colours: one solid background in the card's own colour (the
/// earlier cards' palette, founder, 2 November 2026: "yellow for bitcoin,
/// green for dollars and such"), the ink with its contrast, the muted ink
/// ([mutedAlpha] of it), the semantic up / down (the ink itself on a card
/// whose colour already says it), the tile behind a logo, the
/// speedometer's track.
@immutable
class ShareCardPalette {
  const ShareCardPalette({
    required this.background,
    required this.ink,
    required this.up,
    required this.down,
    required this.tile,
    required this.track,
    this.mutedAlpha = 0.75,
    this.hero,
    this.dot = AppColors.accent,
    this.hairline,
    this.salShadow = const Color(0x2E000000),
  });

  final Color background;
  final Color ink;
  final Color up;
  final Color down;
  final Color tile;

  /// The speedometer's empty track.
  final Color track;

  /// The wordmark's dot ("kute."): the app's orange, the ink on the
  /// bitcoin card (orange on orange would vanish).
  final Color dot;

  /// The edge on a light card; null on the others.
  final Color? hairline;

  /// The muted ink's opacity, per ground: as high as the small text needs
  /// to read in a shared image (4.5:1 where the ground allows it; the
  /// dollars green and the loss red cap white at 3.1:1 and 4.2:1, so
  /// there it is near the full ink).
  final double mutedAlpha;

  /// The soft shadow Sal's still casts behind him, so he never melts into
  /// a ground of his own colour (the bitcoin orange; founder, 2 November
  /// 2026: he vanished into it). It replaced the deeper-orange disc.
  final Color salShadow;

  /// The big number's colour when it is not the ink (the bitcoin claim
  /// hero's orange amount on the app's ink); null: the ink.
  final Color? hero;

  /// The secondary text: the caps line, the fact, the quiet line, the
  /// code's label ([mutedAlpha] of the ink).
  Color get muted => ink.withValues(alpha: mutedAlpha);

  /// The rule over the bottom band (the floor Sal stands on).
  Color get rule => ink.withValues(alpha: 0.22);

  /// The code's capsule.
  Color get capsule => ink.withValues(alpha: 0.12);

  /// Bitcoin: the app's bitcoin orange, near-black ink.
  static const ShareCardPalette bitcoin = ShareCardPalette(
    background: Color(0xFFF7931A),
    ink: Color(0xFF16110A),
    up: Color(0xFF16110A),
    down: Color(0xFF16110A),
    tile: Color(0x1F000000),
    track: Color(0x2E000000),
    dot: Color(0xFF16110A),
    salShadow: Color(0x8C5A2A00),
  );

  /// The bitcoin CLAIM HERO, the recipient's card (founder, 2 November
  /// 2026, of "DANIEL, A FRIEND SENT YOU" in black on the orange: "black
  /// text here does not look good. Find some other card colour", "just
  /// for this card"). One switch: the chosen option below; the bitcoin
  /// send card keeps [bitcoin].
  static const ShareCardPalette bitcoinClaim = bitcoinClaimInk;

  /// Option (a): the app's ink, white text, the amount in the bitcoin
  /// orange (7.1:1), Sal's orange popping on the dark.
  static const ShareCardPalette bitcoinClaimInk = ShareCardPalette(
    background: Color(0xFF1D2024),
    ink: Color(0xFFFFFFFF),
    up: Color(0xFFFFFFFF),
    down: Color(0xFFFFFFFF),
    tile: Color(0x1FFFFFFF),
    track: Color(0x29FFFFFF),
    mutedAlpha: 0.75,
    hero: AppColors.accent,
    salShadow: Color(0x80000000),
  );

  /// Option (b): a deep burnt orange, white text (5.8:1; the muted 85%
  /// at 4.7:1), still reading bitcoin.
  static const ShareCardPalette bitcoinClaimBurnt = ShareCardPalette(
    background: Color(0xFFA84808),
    ink: Color(0xFFFFFFFF),
    up: Color(0xFFFFFFFF),
    down: Color(0xFFFFFFFF),
    tile: Color(0x24FFFFFF),
    track: Color(0x33FFFFFF),
    mutedAlpha: 0.85,
    dot: Color(0xFFFFFFFF),
    salShadow: Color(0x664A1A00),
  );

  /// Option (c): a dark espresso, white text, the amount in the bitcoin
  /// orange (7.3:1).
  static const ShareCardPalette bitcoinClaimEspresso = ShareCardPalette(
    background: Color(0xFF2B1A10),
    ink: Color(0xFFFFFFFF),
    up: Color(0xFFFFFFFF),
    down: Color(0xFFFFFFFF),
    tile: Color(0x1FFFFFFF),
    track: Color(0x29FFFFFF),
    mutedAlpha: 0.75,
    hero: AppColors.accent,
    salShadow: Color(0x80000000),
  );

  /// Dollars: the app's one green ([AppColors.marketUp]: receipts, the
  /// coin, the badges), white ink.
  static const ShareCardPalette dollars = ShareCardPalette(
    background: AppColors.marketUp,
    ink: Color(0xFFFFFFFF),
    up: Color(0xFFFFFFFF),
    down: Color(0xFFFFFFFF),
    tile: Color(0x24FFFFFF),
    track: Color(0x33FFFFFF),
    mutedAlpha: 0.9,
    salShadow: Color(0x38003A1A),
  );

  /// Predictions: blue, white ink.
  static const ShareCardPalette prediction = ShareCardPalette(
    background: Color(0xFF2D5BE3),
    ink: Color(0xFFFFFFFF),
    up: Color(0xFFFFFFFF),
    down: Color(0xFFFFFFFF),
    tile: Color(0x24FFFFFF),
    track: Color(0x38FFFFFF),
    mutedAlpha: 0.85,
    salShadow: Color(0x38001060),
  );

  /// Investing: deep navy, white ink, the market's green and red.
  static const ShareCardPalette investment = ShareCardPalette(
    background: Color(0xFF141B2E),
    ink: Color(0xFFFFFFFF),
    up: Color(0xFF2BD47F),
    down: Color(0xFFFF5A6A),
    tile: Color(0xFF222A40),
    track: Color(0x29FFFFFF),
    mutedAlpha: 0.7,
    salShadow: Color(0x66000000),
  );

  /// A win to brag about: green, white ink.
  static const ShareCardPalette win = dollars;

  /// A loss owned: the app's one red ([AppColors.marketDown]), white ink.
  static const ShareCardPalette loss = ShareCardPalette(
    background: AppColors.marketDown,
    ink: Color(0xFFFFFFFF),
    up: Color(0xFFFFFFFF),
    down: Color(0xFFFFFFFF),
    tile: Color(0x24FFFFFF),
    track: Color(0x38FFFFFF),
    mutedAlpha: 0.88,
    salShadow: Color(0x3D4A0010),
  );

  /// Flat: the investing navy.
  static const ShareCardPalette flat = investment;

  /// [value]'s colour: up, down, or muted when within [flat] of zero or
  /// null.
  Color signed(double? value, {double flat = 0}) {
    if (value == null || value.abs() <= flat) return muted;
    return value > 0 ? up : down;
  }
}

/// Sal's pose on a card (founder, 2 November 2026: "Sal should have more
/// expression there", then "why is she so sad there", then on a paw-out
/// win: "Sal must be funny, not jolly, based Gen Z funny"): one
/// purpose-made still of the 3D Sal, whole, at the card's top right.
/// Sal is the only adult in the room: low-effort, unbothered poses and
/// deadpan, side-eye or suspicious lids; never a hop, a wave, a cheer or a
/// smile, never a sad slant. Rendered from the v5 rig (Kute Assets, Sal
/// 3D/v5 app, scripts/render_card_stills_v2.py), `card_<pose>@2x/@3x.webp`
/// in lib/assets/sal (the manifest's `card` group).
enum ShareCardPose {
  /// "Too easy": lounging on the floor, paws crossed, chin up, a
  /// heavy-lidded side-eye at the number. A win.
  win,

  /// Retired: lounging, eyes shut, chin up, the calmest dog alive. A big
  /// win.
  bigWin,

  /// "I'm going to bed": a flop, chin on the floor, ears flat, one eye open
  /// at the viewer. A loss, dry, never sad.
  loss,

  /// Sitting, a slow side-eye with one lid lower: "and?". Flat.
  flat,

  /// "Here, take it": standing with the briefcase and the coin, glasses
  /// on, a flat look. A send, a gift.
  send,

  /// Lounging with the gift, one gold coin, balanced upright on her head,
  /// a flat heavy-lidded stare: not even handing it over. The bitcoin
  /// claim hero only (founder, 2 November 2026, of [send] there: "this
  /// Sal isn't good also"; render_card_claim.py).
  claim,

  /// Sitting, a suspicious squint down at the odds, one lid lower. A
  /// prediction.
  predict;

  String get clip => 'card_${name.toLowerCase()}';
}

/// Sal's whole height on a card, his cell's side.
const double kShareCardSalSize = 128;

/// Decodes Sal for the cards once: his face (the `share` clip's first
/// frame, the small mark a card without a pose wears) and the pose
/// stills ([ShareCardPose]), at @3x, for a card that never loads anything
/// itself.
abstract final class ShareCardSal {
  static const String clip = 'share';
  static SalClip? _face;
  static final Map<ShareCardPose, SalClip> _poses = {};
  static Future<SalClip?>? _loading;

  /// The decoded face, or null until [load] has finished.
  static SalClip? peek() => _face;

  /// The decoded still of [pose], or null until [load] has finished.
  static SalClip? pose(ShareCardPose pose) => _poses[pose];

  /// Decodes the face and the poses (once); the face, or null when it
  /// cannot be read (a pose that cannot be read is left out).
  static Future<SalClip?> load() {
    final done = _face;
    if (done != null && _poses.length == ShareCardPose.values.length) {
      return Future.value(done);
    }
    return _loading ??= Future.wait([
      SalSpriteCache.clip(clip, 3),
      for (final p in ShareCardPose.values) SalSpriteCache.clip(p.clip, 3),
    ]).then((clips) {
      _face = clips.first;
      for (var i = 0; i < ShareCardPose.values.length; i++) {
        final c = clips[i + 1];
        if (c != null) _poses[ShareCardPose.values[i]] = c;
      }
      _loading = null;
      return _face;
    }, onError: (Object _) {
      _loading = null;
      return null;
    });
  }

  /// Tests: forget the decoded face and poses.
  static void debugReset() {
    _face = null;
    _poses.clear();
    _loading = null;
  }
}

/// The caps line's size (w700, tracked 0.1 em): big enough to read in a
/// shared image seen at phone width.
const double kShareCardCapsSize = 13;

/// The hero number's sizes: 80 for a short figure ("47%"), 72, 64 for a
/// long one, never under [kShareCardHeroMin] when shrunk to fit.
const double kShareCardHeroMax = 80;
const double kShareCardHeroMin = 48;

/// The fact line under the hero number.
const double kShareCardFactSize = 18;

/// The edgy line's size (w700, the full ink: the card's voice).
const double kShareCardLineSize = 22;

/// The quiet line's size ("Claim it on Kute", w600, muted).
const double kShareCardQuietSize = 15;

/// A money card's amount may run larger: it is the only thing on it.
const double kShareCardMoneyHeroMax = 96;

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

/// The hero number's size for [text] in [width]: its base ([base], else
/// [shareCardHeroBase], or [max] when smaller), shrunk so it fits, never
/// under [kShareCardHeroMin] (a FittedBox takes over below that, so it
/// never overflows).
double shareCardHeroSize(String text, double width,
    {double? max, double? base}) {
  base ??= shareCardHeroBase(text);
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
    this.base,
    this.center = false,
  });

  final String text;
  final Color color;
  final Key? textKey;
  final double? max;

  /// The size to start from, whatever the length (a money card's amount,
  /// [kShareCardMoneyHeroMax]); null: [shareCardHeroBase].
  final double? base;
  final bool center;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (_, box) {
        final size =
            shareCardHeroSize(text, box.maxWidth, max: max, base: base);
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
    this.numberBase,
    this.fact,
    this.factColor,
    this.factSize = kShareCardFactSize,
    this.center = false,
    this.watermark,
    this.graphic,
    this.graphicFills = false,
    this.graphicBelowSal = false,
    this.plain,
    this.plainStrong = false,
    this.line,
    this.quiet,
    this.code,
    this.mark,
    this.pose,
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

  /// The big number's size to start from, whatever its length (a money
  /// card's amount, [kShareCardMoneyHeroMax]); null: by its length.
  final double? numberBase;

  /// The fact line under it; null: none.
  final String? fact;

  /// The fact line's colour; the muted ink by default.
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

  /// A filling graphic with no number over it starts under Sal's feet at
  /// the top right (a market's chart, whose labels sit at its right).
  final bool graphicBelowSal;

  /// One plain fact line under the graphic.
  final String? plain;

  /// [plain] as the card's second statement, big and in the full ink (a
  /// prediction sent with money: "$5 on Yes"), not a quiet fact.
  final bool plainStrong;

  /// The edgy line (20, w600, 90% ink, two lines at most).
  final String? line;

  /// A quiet muted line over the footer ("Claim it on Kute").
  final String? quiet;

  /// The sharer's referral code; null: none.
  final String? code;

  /// Sal's decoded face ([ShareCardSal]) for the footer's small mark,
  /// worn only by a card without a [pose]; null: the tile alone.
  final SalClip? mark;

  /// Sal, whole, at the top right in this pose ([ShareCardSal.pose]); the
  /// footer then has no mark. His place is kept while the still decodes,
  /// so the layout never moves.
  final ShareCardPose? pose;

  /// The keys' prefix: `{prefix}-bg`, `{prefix}-caps`, `{prefix}-hero`,
  /// `{prefix}-number`, `{prefix}-fact`, `{prefix}-graphic`,
  /// `{prefix}-plain`, `{prefix}-edge`, `{prefix}-quiet`,
  /// `{prefix}-watermark`, `{prefix}-footer`, `{prefix}-mark`,
  /// `{prefix}-wordmark`, `{prefix}-code`, `{prefix}-sal`.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = palette;
    final sal = pose;
    // Sal stands on the bottom band's rule at the right when nothing fills
    // the middle (a money card, a card without a chart); over a chart, the
    // rows or the speedometer he stays at the top right.
    final salOnFloor = sal != null && !graphicFills && graphic == null;
    final textAlign = center ? TextAlign.center : TextAlign.start;
    // Without a graphic the plain fact joins the hero block.
    final plainInHero = graphic == null && plain != null;
    final plainText = plain == null
        ? null
        : Text(
            plain!,
            key: ValueKey('$keyPrefix-plain'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: textAlign,
            style: plainStrong
                ? shareCardText(kShareCardPlainStrongSize, FontWeight.w800,
                    p.ink,
                    spacing: -0.4, tabular: true)
                : shareCardText(16, FontWeight.w600, p.ink,
                    spacing: -0.2, tabular: true),
          );
    // Beside Sal on the floor the lines under the number keep clear of
    // him, a long one shrunk a touch rather than cut.
    Widget besideSal(Widget child) => salOnFloor
        ? Padding(
            padding:
                const EdgeInsetsDirectional.only(end: kShareCardSalFloorInset),
            child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: child))
        : child;
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
                    color: p.hero ?? p.ink,
                    max: numberMax,
                    base: numberBase,
                    center: center,
                  ),
                ),
              if (fact != null) ...[
                SizedBox(height: number != null ? 6 : 0),
                besideSal(Text(
                  fact!,
                  key: ValueKey('$keyPrefix-fact'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: textAlign,
                  style: shareCardText(
                      factSize, FontWeight.w500, factColor ?? p.muted,
                      spacing: -0.2, tabular: true),
                )),
              ],
              if (plainInHero) ...[
                SizedBox(height: number != null || fact != null ? 14 : 0),
                besideSal(plainText!),
              ],
            ],
          );
    final keyedGraphic = graphic == null
        ? null
        : KeyedSubtree(key: ValueKey('$keyPrefix-graphic'), child: graphic!);
    // TOP: the caps line and the identity, clear of Sal at the top right
    // (the title set around him, the lines under his band the full
    // width; he sits smaller when the title needs his room, see
    // shareCardSalTopSize); a big number right under them starts below
    // him.
    final salTop = sal != null && !salOnFloor;
    final salSize = salTop
        ? shareCardSalTopSize(identity?.name,
            direction: Directionality.of(context))
        : kShareCardSalSize;
    final capsText = Text(
      caps.toUpperCase(),
      key: ValueKey('$keyPrefix-caps'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: shareCardText(kShareCardCapsSize, FontWeight.w700, p.muted,
          spacing: kShareCardCapsSize * 0.1, height: 1.2),
    );
    Widget top = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (salTop)
          Padding(
            padding: EdgeInsetsDirectional.only(
                end: shareCardSalFloat(salSize).width),
            child: capsText,
          )
        else
          capsText,
        if (identity != null) ...[
          const SizedBox(height: kShareCardIdentityGap),
          if (salTop)
            ShareCardTitleFloat(
              height: shareCardSalFloat(salSize).height,
              width: shareCardSalFloat(salSize).width,
              child: identity!,
            )
          else
            identity!,
        ],
      ],
    );
    final salBand = salTop &&
        (number != null || graphicBelowSal) &&
        !center &&
        graphicFills;
    if (salTop) {
      if (salBand) {
        top = ConstrainedBox(
          constraints: BoxConstraints(minHeight: shareCardSalBand(salSize)),
          child: Align(alignment: Alignment.topLeft, child: top),
        );
      }
    }
    final hasBottom = line != null || quiet != null;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        top,
        // MIDDLE: the hero block.
        if (graphicFills) ...[
          if (hero != null) ...[
            // Under Sal's band the band itself is the air.
            SizedBox(
                height: salBand
                    ? 8
                    : identity != null
                        ? 16
                        : 26),
            hero,
          ],
          Expanded(
            child: keyedGraphic == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: SizedBox.expand(child: keyedGraphic),
                  ),
          ),
        ] else ...[
          // The hero block right under the top band (Sal fills the room
          // under it at the right), or centred in the space left.
          Expanded(
            child: LayoutBuilder(builder: (context, box) {
              final heroTop = salOnFloor
                  ? (identity != null ? 20.0 : 24.0)
                  : 12.0;
              // Sal as big as the room between the number and the rule
              // holds (his ears clear of it), within his floor sizes.
              var salSize = kShareCardSalFloorSize;
              if (salOnFloor && box.maxHeight.isFinite) {
                final numberBottom = heroTop +
                    (number == null
                        ? 0
                        : shareCardHeroSize(number!, box.maxWidth,
                                max: numberMax, base: numberBase) *
                            1.04);
                final feet = box.maxHeight +
                    (hasBottom ? kShareCardRuleAbove : 0) +
                    kShareCardSalFeet;
                salSize = ((feet - numberBottom - 6) /
                        (1 - kShareCardSalHeadroom))
                    .clamp(kShareCardSalFloorMin, kShareCardSalFloorSize)
                    .toDouble();
              }
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  if (hero != null)
                    Positioned.fill(
                      child: Padding(
                        padding: EdgeInsets.only(
                            top: heroTop, bottom: salOnFloor ? 0 : 12),
                        child: Align(
                          alignment: salOnFloor
                              ? AlignmentDirectional.topStart
                              : center
                                  ? Alignment.center
                                  : AlignmentDirectional.centerStart,
                          child: hero,
                        ),
                      ),
                    ),
                  if (salOnFloor)
                    // His feet on the rule (the still's own soft contact
                    // shadow under them).
                    PositionedDirectional(
                      end: kShareCardSalFloorEnd - kShareCardPadding,
                      bottom: (hasBottom ? -kShareCardRuleAbove : 0) -
                          kShareCardSalFeet,
                      width: salSize,
                      height: salSize,
                      child: ShareCardSalStill(
                          key: ValueKey('$keyPrefix-sal'),
                          pose: sal,
                          shadow: p.salShadow),
                    ),
                ],
              );
            }),
          ),
          if (keyedGraphic != null) keyedGraphic,
        ],
        // BOTTOM: the plain fact, the rule, the edgy line, the quiet line,
        // the footer.
        if (plain != null && !plainInHero) ...[
          const SizedBox(height: 10),
          plainText!,
        ],
        if (hasBottom) ...[
          SizedBox(
              height: plain != null && !plainInHero
                  ? 10
                  : kShareCardRuleAbove),
          SizedBox(
            height: 1,
            child:
                ColoredBox(key: ValueKey('$keyPrefix-rule'), color: p.rule),
          ),
          const SizedBox(height: kShareCardRuleGap),
        ],
        if (line != null)
          ShareCardBalancedText(
            line!,
            textKey: ValueKey('$keyPrefix-edge'),
            maxLines: 2,
            style: shareCardText(kShareCardLineSize, FontWeight.w700, p.ink,
                spacing: -0.5, height: 1.12),
          ),
        if (quiet != null) ...[
          SizedBox(height: line != null ? 6 : 0),
          Text(
            quiet!,
            key: ValueKey('$keyPrefix-quiet'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: shareCardText(
                kShareCardQuietSize, FontWeight.w600, p.muted,
                spacing: -0.2),
          ),
        ],
        SizedBox(height: hasBottom ? 16 : 18),
        ShareCardFooter(
            key: ValueKey('$keyPrefix-footer'),
            palette: p,
            code: code,
            mark: mark,
            showMark: sal == null,
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
                      if (salTop)
                        PositionedDirectional(
                          top: kShareCardSalTop,
                          end: kShareCardSalEnd,
                          width: salSize,
                          height: salSize,
                          child: ShareCardSalStill(
                              key: ValueKey('$keyPrefix-sal'),
                              pose: sal,
                              shadow: p.salShadow),
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

/// Sal's cell at the top right: its top and end offsets from the card's
/// edge (his render's own transparent margin sits in the card's padding).
const double kShareCardSalTop = -6;
const double kShareCardSalEnd = 0;

/// The room the caps line and the identity leave at their end for Sal at
/// the top right (his full size; see [shareCardSalFloat]).
const double kShareCardSalInset = 84;

/// Sal at the top right when the title needs his room: a long title
/// sets its first two lines beside him and the rest under his feet at
/// the full width ([shareCardSalTopSize]).
const double kShareCardSalCompactSize = 104;

/// The space between the caps line and the identity row.
const double kShareCardIdentityGap = 12;

/// How far down Sal's silhouette reaches in his cell (his paws and his
/// shadow), and where it starts across it, as fractions of the cell.
const double kShareCardSalDogBottom = 0.89;
const double kShareCardSalDogLeft = 0.22;

/// The space the title keeps from Sal.
const double kShareCardSalTitleGap = 8;

/// Sal's band over the identity row when his cell is [size] at the top
/// right: how far down from the row's top he reaches and how much of its
/// end he takes ([ShareCardTitleFloat]).
({double height, double width}) shareCardSalFloat(double size) {
  final rowTop =
      kShareCardPadding + kShareCardCapsSize * 1.2 + kShareCardIdentityGap;
  final bottom = kShareCardSalTop + size * kShareCardSalDogBottom;
  final left = kShareCardSize.width -
      kShareCardSalEnd -
      size * (1 - kShareCardSalDogLeft);
  return (
    height: math.max(0, bottom - rowTop),
    width: kShareCardSize.width -
        kShareCardPadding -
        left +
        kShareCardSalTitleGap,
  );
}

/// Sal's cell at the top right for a card titled [title]: his full size
/// while the title reads whole on two lines at 18 beside him, else the
/// compact one, so the lines under him take the full width.
double shareCardSalTopSize(String? title,
    {TextDirection direction = TextDirection.ltr}) {
  final t = title?.trim() ?? '';
  if (t.isEmpty) return kShareCardSalSize;
  final wide = kShareCardSize.width -
      kShareCardPadding * 2 -
      ShareCardIdentity.logoSide -
      ShareCardIdentity.logoGap;
  final full = shareCardSalFloat(kShareCardSalSize);
  final fit = shareCardTitleFit(t,
      narrow: wide - full.width,
      wide: wide,
      floatHeight: full.height,
      direction: direction);
  return fit.fits && fit.size == kShareCardTitleSteps.first.$1
      ? kShareCardSalSize
      : kShareCardSalCompactSize;
}

/// The top band's height when a big number follows it at the left, so
/// the number starts under Sal's feet (his full size; see
/// [shareCardSalBand]).
const double kShareCardSalBand = 80;

/// The top band's height under Sal's cell of [size] at the top right:
/// [kShareCardSalBand] at his full size, less when he sits compact.
double shareCardSalBand(double size) =>
    kShareCardSalBand - (kShareCardSalSize - size) * 0.86;

/// Sal standing on the bottom band's rule (a card with nothing filling
/// its middle): his cell's side (the 384 px still at 3× pixels, barely
/// enlarged), its end offset from the card's edge, how far his feet sit
/// above the cell's bottom, and the room the lines under the number leave
/// him.
const double kShareCardSalFloorSize = 148;

/// The smallest Sal on the floor, when a tall number leaves less room.
const double kShareCardSalFloorMin = 104;

/// The transparent room over Sal's ears in his cell (a fraction of it).
const double kShareCardSalHeadroom = 0.1;
const double kShareCardSalFloorEnd = 4;
const double kShareCardSalFeet = 3;
const double kShareCardSalFloorInset = 108;

/// The space over the rule (under the middle band) and under it (over
/// the edgy line).
const double kShareCardRuleAbove = 14;
const double kShareCardRuleGap = 12;

/// A wrapped line set in two even lines rather than a long one and an
/// orphan ("47% says I'm early, not / wrong."): the narrowest width that
/// keeps its line count (never under its longest word), found by halving;
/// one line as is.
class ShareCardBalancedText extends StatelessWidget {
  const ShareCardBalancedText(this.text,
      {super.key, required this.style, this.maxLines = 2, this.textKey});

  final String text;
  final TextStyle style;
  final int maxLines;

  /// The Text's own key.
  final Key? textKey;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final full = box.maxWidth;
        var width = full;
        if (full.isFinite && full > 0) {
          final dir = Directionality.of(context);
          int lines(double w) {
            final tp = TextPainter(
              text: TextSpan(text: text, style: style),
              textDirection: dir,
              maxLines: maxLines + 1,
            )..layout(maxWidth: w);
            final n = tp.computeLineMetrics().length;
            tp.dispose();
            return n;
          }

          final n = lines(full);
          if (n > 1 && n <= maxLines) {
            // Never narrower than its longest word, which would then break
            // inside ("Mu / stererkennung").
            final probe = TextPainter(
              text: TextSpan(text: text, style: style),
              textDirection: dir,
            )..layout();
            final word = probe.minIntrinsicWidth;
            probe.dispose();
            var lo = math.min(full, math.max(full * 0.5, word.ceilToDouble()));
            var hi = full;
            while (hi - lo > 2) {
              final mid = (lo + hi) / 2;
              if (lines(mid) <= n) {
                hi = mid;
              } else {
                lo = mid;
              }
            }
            width = hi;
          }
        }
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: SizedBox(
            width: width.isFinite ? width : null,
            child: Text(
              text,
              key: textKey,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        );
      });
}

/// Sal's still ([ShareCardSal.pose]) filling its box; nothing while it
/// decodes.
class ShareCardSalStill extends StatelessWidget {
  const ShareCardSalStill({super.key, required this.pose, this.shadow});

  final ShareCardPose pose;

  /// The soft shadow behind his silhouette ([ShareCardPalette.salShadow]);
  /// null: none.
  final Color? shadow;

  @override
  Widget build(BuildContext context) {
    final still = ShareCardSal.pose(pose);
    if (still == null) return const SizedBox.expand();
    return CustomPaint(
        size: Size.infinite, painter: _StillPainter(still, shadow));
  }
}

/// The shadow's blur and its drop, as fractions of Sal's cell.
const double kShareCardSalShadowBlur = 0.035;
const double kShareCardSalShadowDrop = 0.03;

class _StillPainter extends CustomPainter {
  _StillPainter(this.still, this.shadow);

  final SalClip still;
  final Color? shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final dst = Offset.zero & size;
    final s = shadow;
    if (s != null && s.a > 0) {
      // His own silhouette in the shadow's colour, blurred and dropped a
      // touch: a soft edge that lifts him off any ground.
      final sigma = size.width * kShareCardSalShadowBlur;
      canvas.drawImageRect(
          still.image,
          still.cell(0),
          dst.shift(Offset(0, size.height * kShareCardSalShadowDrop)),
          Paint()
            ..filterQuality = FilterQuality.high
            ..colorFilter = ColorFilter.mode(s, BlendMode.srcIn)
            ..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma));
    }
    canvas.drawImageRect(still.image, still.cell(0), dst,
        Paint()..filterQuality = FilterQuality.high);
  }

  @override
  bool shouldRepaint(_StillPainter old) =>
      !identical(old.still, still) || old.shadow != shadow;
}

/// A card's title as it is set: its [size], the [head] set beside Sal
/// (the lines whose top is in his band, at the narrow width) and the
/// [tail] under him at the full width, [lines] in all; [fits] when it is
/// whole within its step's lines (else the last step, cut at the end).
typedef ShareCardTitleFit = ({
  double size,
  String head,
  String tail,
  int headLines,
  int lines,
  bool fits,
});

/// The sizes a card's title steps down through, each with the lines it
/// may take (founder, 2 November 2026: "try to not cut titles"): 18 on
/// two lines, 16, 15, then 14 (still w600 and readable at phone width) on
/// three; cut with an ellipsis only after three lines at 14.
const List<(double, int)> kShareCardTitleSteps = [
  (18, 2),
  (16, 3),
  (15, 3),
  (14, 3),
];

/// The title's line height, a fraction of its size.
const double kShareCardTitleHeight = 1.2;

/// The room over a title line's glyphs in its box.
const double kShareCardTitleLeading = 2;

/// The title's style at [size].
TextStyle shareCardTitleStyle(double size, Color color) =>
    shareCardText(size, FontWeight.w600, color,
        spacing: size >= 18 ? -0.3 : -0.2, height: kShareCardTitleHeight);

/// [text] set as a card's title (see [ShareCardTitleFit]): [narrow] wide
/// for the lines whose top is within [floatHeight] (beside Sal at the top
/// right), [wide] for the lines under him; the first of
/// [kShareCardTitleSteps] it fits whole, else the last one.
ShareCardTitleFit shareCardTitleFit(
  String text, {
  required double narrow,
  required double wide,
  double floatHeight = 0,
  TextDirection direction = TextDirection.ltr,
}) {
  ShareCardTitleFit? last;
  for (final (size, maxLines) in kShareCardTitleSteps) {
    final style = shareCardTitleStyle(size, const Color(0xFFFFFFFF));
    final lh = size * kShareCardTitleHeight;
    final beside = floatHeight <= 0 || narrow >= wide
        ? 0
        // A line's box starts with its leading over the glyphs: one whose
        // top is within that of Sal's band is under him.
        : math.max(0, ((floatHeight - kShareCardTitleLeading) / lh).ceil());
    int count(String t, double w) {
      if (t.isEmpty) return 0;
      final tp = TextPainter(
          text: TextSpan(text: t, style: style), textDirection: direction)
        ..layout(maxWidth: math.max(1, w));
      final n = tp.computeLineMetrics().length;
      tp.dispose();
      return n;
    }

    String head = text;
    String tail = '';
    int headLines;
    int lines;
    if (beside == 0) {
      headLines = 0;
      head = '';
      tail = text;
      lines = count(text, wide);
    } else {
      final tp = TextPainter(
          text: TextSpan(text: text, style: style), textDirection: direction)
        ..layout(maxWidth: math.max(1, narrow));
      final metrics = tp.computeLineMetrics();
      if (metrics.length <= beside) {
        headLines = metrics.length;
        lines = metrics.length;
      } else {
        // The end of the last line beside Sal: from its start, whose
        // position is never ambiguous.
        final m = metrics[beside - 1];
        final start = tp.getPositionForOffset(Offset(0, m.baseline));
        final end = tp.getLineBoundary(start).end;
        head = text.substring(0, end).trimRight();
        tail = text.substring(end).trimLeft();
        headLines = beside;
        lines = beside + count(tail, wide);
      }
      tp.dispose();
    }
    last = (
      size: size,
      head: head,
      tail: tail,
      headLines: headLines,
      lines: lines,
      fits: lines <= maxLines,
    );
    if (last.fits) return last;
  }
  return last!;
}

/// Where Sal sits over the identity row at the top right, for its title
/// to set around him ([shareCardTitleFit]): the [height] from the row's
/// top his band reaches down to and the [width] he takes at its end.
/// Provided by [ShareCardFrame]; none: the row's full width.
class ShareCardTitleFloat extends InheritedWidget {
  const ShareCardTitleFloat({
    super.key,
    required this.height,
    required this.width,
    required super.child,
  });

  final double height;
  final double width;

  static ShareCardTitleFloat? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShareCardTitleFloat>();

  @override
  bool updateShouldNotify(ShareCardTitleFloat old) =>
      old.height != height || old.width != width;
}

/// The identity row: [logo] (36, a rounded square), [name] and a muted
/// [meta] under it. The name is never cut while it can be read whole
/// ([shareCardTitleFit]): 18 on two lines, 16 to 14 on three, the lines
/// beside Sal ([ShareCardTitleFloat]) clear of him, the lines under him
/// the full width; an ellipsis only after three lines at 14.
class ShareCardIdentity extends StatelessWidget {
  const ShareCardIdentity({
    super.key,
    required this.palette,
    required this.logo,
    required this.name,
    this.meta,
    this.keyPrefix = 'share-card',
  });

  final ShareCardPalette palette;
  final Widget logo;
  final String name;
  final String? meta;
  final String keyPrefix;

  /// The logo's side and the gap after it.
  static const double logoSide = 36;
  static const double logoGap = 12;

  @override
  Widget build(BuildContext context) {
    final m = meta?.trim() ?? '';
    final float = ShareCardTitleFloat.of(context);
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth - logoSide - logoGap;
      final narrow = wide - (float?.width ?? 0);
      final fit = shareCardTitleFit(name,
          narrow: narrow,
          wide: wide,
          floatHeight: float?.height ?? 0,
          direction: Directionality.of(context));
      final maxLines = kShareCardTitleSteps.last.$2;
      final style = shareCardTitleStyle(fit.size, palette.ink);
      // The meta under the title: beside Sal while his band reaches it.
      final metaTop = fit.lines * fit.size * kShareCardTitleHeight + 1;
      final metaBeside = float != null && metaTop < float.height;
      final title = Column(
        key: ValueKey('$keyPrefix-title'),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (fit.head.isNotEmpty)
            SizedBox(
              width: narrow,
              child: Text(
                fit.head,
                key: ValueKey('$keyPrefix-title-head'),
                maxLines: fit.headLines,
                overflow: fit.tail.isEmpty && !fit.fits
                    ? TextOverflow.ellipsis
                    : TextOverflow.clip,
                style: style,
              ),
            ),
          if (fit.tail.isNotEmpty)
            Text(
              fit.tail,
              key: ValueKey('$keyPrefix-title-tail'),
              maxLines: math.max(1, maxLines - fit.headLines),
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
        ],
      );
      return Row(
        key: ValueKey('$keyPrefix-identity'),
        // A title over two lines hangs from the logo's top.
        crossAxisAlignment: fit.lines > 2
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          logo,
          const SizedBox(width: logoGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                title,
                if (m.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  SizedBox(
                    width: metaBeside ? narrow : wide,
                    child: Text(
                      m,
                      key: ValueKey('$keyPrefix-meta'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: shareCardText(14, FontWeight.w500, palette.muted,
                          height: 1.25),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    });
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

/// The footer mark's side.
const double kShareCardMarkSize = 28;

/// The referral code's size in its capsule.
const double kShareCardCodeSize = 13;

/// Sal as a small mark: a 28 px rounded tile with his 3D face.
class ShareCardMark extends StatelessWidget {
  const ShareCardMark(
      {super.key,
      required this.palette,
      this.face,
      this.size = kShareCardMarkSize});

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
    this.showMark = true,
    this.keyPrefix = 'share-card',
  });

  final ShareCardPalette palette;
  final String? code;
  final SalClip? mark;

  /// The small mark before the wordmark (off when Sal stands on the card).
  final bool showMark;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final word = shareCardText(22, FontWeight.w700, palette.ink,
        spacing: -0.7, height: 1.0);
    final c = code?.trim() ?? '';
    return Row(
      children: [
        // The mark's height kept without it, so the bands never move.
        SizedBox(height: kShareCardMarkSize, width: showMark ? null : 0),
        if (showMark) ...[
          ShareCardMark(
              key: ValueKey('$keyPrefix-mark'), palette: palette, face: mark),
          const SizedBox(width: 9),
        ],
        Text.rich(
          key: ValueKey('$keyPrefix-wordmark'),
          TextSpan(children: [
            TextSpan(text: 'kute', style: word),
            TextSpan(text: '.', style: word.copyWith(color: palette.dot)),
          ]),
        ),
        const SizedBox(width: 12),
        // The code in a quiet capsule: the label muted, the code itself
        // in the full ink, big enough to type from a shared image.
        Expanded(
          child: c.isEmpty
              ? const SizedBox.shrink()
              : Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: DecoratedBox(
                    key: ValueKey('$keyPrefix-code-capsule'),
                    decoration: BoxDecoration(
                      color: palette.capsule,
                      borderRadius: BorderRadius.circular(kShareCardMarkSize),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      child: Text.rich(
                        key: ValueKey('$keyPrefix-code'),
                        TextSpan(children: [
                          TextSpan(
                              text: context.l10n.bragCodeLabel.toUpperCase(),
                              style: shareCardText(
                                  kShareCardCodeSize, FontWeight.w600,
                                  palette.muted,
                                  spacing: kShareCardCodeSize * 0.08,
                                  height: 1.0)),
                          const TextSpan(text: '  '),
                          TextSpan(
                              text: c.toUpperCase(),
                              style: shareCardText(
                                  kShareCardCodeSize, FontWeight.w700,
                                  palette.ink,
                                  spacing: kShareCardCodeSize * 0.08,
                                  height: 1.0,
                                  tabular: true)),
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
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
