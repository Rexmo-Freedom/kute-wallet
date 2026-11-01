// lib/screens/share/cards/share_card_frame.dart
//
// THE SHARE CARD FRAME (founder, 1 November 2026: "all shares, stocks,
// predictions and even sending bitcoin outside should have a card like
// the brag card"). The pieces every 4:5 share image is made of, taken out
// of the brag card (brag/brag_card.dart) so the family reads as one:
//
//   * [ShareCardFrame]: the card at [kShareCardSize] (captured at
//     [kShareCardPixelRatio], 1080 × 1350), a full-bleed gradient, a soft
//     glow behind Sal, Sal large at the bottom right, the body above the
//     footer. The light theme inside whatever the app's mode, no text
//     scaling (the preview is exactly the image).
//   * [ShareCardBubble]: Sal's one-liner in a white speech bubble whose
//     tail points down at him.
//   * [ShareCardFooter]: the "kute." wordmark over a call to action, and
//     the sharer's referral code as a bold white chip.
//   * [ShareCardLogo]: a market's logo (the coin icon on Investing, the
//     market's picture on a prediction, else its first letter).
//   * [ShareCardChip]: the white call-to-action chip ("Claim on Kute").
//   * [ShareCardHeadline]: the clear fact in white, the numbers in it
//     emphasised.
//   * [ShareCardLinePainter]: the smooth price / chance line with its
//     soft fill.
//   * [ShareCardSal]: decodes Sal's stills once, for a card that never
//     loads anything itself.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/theme/app_theme.dart';

/// The card's logical size: 4:5.
const Size kShareCardSize = Size(360, 450);

/// The capture's pixel ratio: [kShareCardSize] × 3 = 1080 × 1350.
const double kShareCardPixelRatio = 3;

/// A Sal still's width over its height (brag_smug and its siblings).
const double kShareCardSalAspect = 635 / 720;

/// The stills a card may draw.
const String kShareSalSmug = 'lib/assets/sal/brag_smug.webp';
const String kShareSalShades = 'lib/assets/sal/brag_shades.webp';
const String kShareSalUnbothered = 'lib/assets/sal/brag_unbothered.webp';

const String kShareCardFont = 'Inter';
const Color kShareCardInk = Colors.white;
const Color kShareCardDark = Color(0xFF111214);

/// The card's text style: Inter, no decoration, tabular figures on ask.
TextStyle shareCardText(double size, FontWeight weight, Color color,
        {double spacing = 0, double height = 1.2, bool tabular = false}) =>
    TextStyle(
      fontFamily: kShareCardFont,
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: spacing,
      height: height,
      decoration: TextDecoration.none,
      fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
    );

/// Decodes Sal's stills once (see the file header).
class ShareCardSal {
  ShareCardSal._();

  static final Map<String, ui.Image> _decoded = {};
  static final Map<String, Future<ui.Image?>> _loading = {};

  /// The decoded still at [asset], or null until [load] has finished.
  static ui.Image? peek(String asset) => _decoded[asset];

  /// Decodes [asset] (once); null when it cannot be read.
  static Future<ui.Image?> load(String asset) {
    final done = _decoded[asset];
    if (done != null) return Future.value(done);
    return _loading[asset] ??= () async {
      try {
        final data = await rootBundle.load(asset);
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        final frame = await codec.getNextFrame();
        codec.dispose();
        _decoded[asset] = frame.image;
        return frame.image;
      } catch (_) {
        return null;
      } finally {
        _loading.remove(asset)?.ignore();
      }
    }();
  }

  /// Every still a card may draw.
  static Future<void> loadAll() => Future.wait(
      [kShareSalSmug, kShareSalShades, kShareSalUnbothered].map(load));

  /// Tests: forget every decoded still.
  static void debugReset() {
    _decoded.clear();
    _loading.clear();
  }
}

/// The 4:5 card: the gradient, the glow, Sal and the footer around [body].
class ShareCardFrame extends StatelessWidget {
  const ShareCardFrame({
    super.key,
    required this.colors,
    required this.body,
    required this.cta,
    this.code,
    this.sal,
    this.salKey,
    this.salHeight = 184,
    this.salBottom = 60,
    this.glow,
    this.keyPrefix = 'share-card',
    this.background,
  });

  /// The gradient, top left to bottom right.
  final List<Color> colors;

  /// Everything above the footer.
  final Widget body;

  /// The footer's call to action under the wordmark.
  final String cta;

  /// The sharer's referral code (the footer chip); null: no chip.
  final String? code;

  /// Sal's decoded still; null: no Sal.
  final ui.Image? sal;
  final Key? salKey;
  final double salHeight;
  final double salBottom;

  /// The glow behind Sal; white by default.
  final Color? glow;

  /// The keys' prefix: `{prefix}-bg`, `{prefix}-wordmark`, `{prefix}-cta`,
  /// `{prefix}-code`.
  final String keyPrefix;

  /// Drawn over the gradient, under everything else (a card's accent).
  final Widget? background;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glowColor = glow ?? Colors.white;
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
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors,
              ),
            ),
            child: Stack(
              children: [
                if (background != null) Positioned.fill(child: background!),
                // The glow behind Sal.
                Positioned(
                  right: -80,
                  bottom: -10,
                  width: 340,
                  height: 340,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(colors: [
                        glowColor.withValues(alpha: 0.22),
                        glowColor.withValues(alpha: 0),
                      ]),
                    ),
                  ),
                ),
                if (sal != null)
                  Positioned(
                    right: 4,
                    bottom: salBottom,
                    height: salHeight,
                    width: salHeight * kShareCardSalAspect,
                    child: RawImage(
                      key: salKey,
                      image: sal,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: body),
                      ShareCardFooter(
                          code: code, cta: cta, keyPrefix: keyPrefix),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sal's one-liner in a white speech bubble, its tail at the right
/// pointing down at him.
class ShareCardBubble extends StatelessWidget {
  const ShareCardBubble({
    super.key,
    required this.text,
    this.textKey = const ValueKey('share-card-line'),
    this.maxLines = 3,
  });

  final String text;
  final Key textKey;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final long = text.length > 24;
    return CustomPaint(
      painter: _BubblePainter(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
        child: Text(
          text,
          key: textKey,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: shareCardText(long ? 15 : 20, FontWeight.w800, kShareCardDark,
              spacing: long ? -0.3 : -0.6, height: 1.15),
        ),
      ),
    );
  }
}

class _BubblePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = kShareCardInk;
    final body =
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16));
    // The tail: from the right edge near the bottom, out toward Sal.
    final tail = Path()
      ..moveTo(size.width - 2, size.height - 26)
      ..lineTo(size.width + 18, size.height + 8)
      ..lineTo(size.width - 26, size.height - 1)
      ..close();
    final shape = Path()
      ..addRRect(body)
      ..addPath(tail, Offset.zero);
    canvas.drawShadow(shape, Colors.black.withValues(alpha: 0.6), 5, false);
    canvas.drawRRect(body, paint);
    canvas.drawPath(tail, paint);
  }

  @override
  bool shouldRepaint(_BubblePainter old) => false;
}

/// The white call-to-action chip with an arrow.
class ShareCardChip extends StatelessWidget {
  const ShareCardChip({super.key, required this.label, this.accent});

  final String label;

  /// The arrow's colour; the card's dark ink by default.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 7, 9, 7),
      decoration: BoxDecoration(
        color: kShareCardInk,
        borderRadius: BorderRadius.circular(100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: shareCardText(12.5, FontWeight.w800, kShareCardDark,
                  spacing: -0.2),
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.arrow_forward_rounded,
              size: 14, color: accent ?? kShareCardDark),
        ],
      ),
    );
  }
}

/// A white pill with dark text ("Long", "Yes · 47%").
class ShareCardPill extends StatelessWidget {
  const ShareCardPill({
    super.key,
    required this.text,
    this.size = 12,
    this.color,
    this.fill,
  });

  final String text;
  final double size;
  final Color? color;
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: size * 0.85, vertical: size * 0.3),
      decoration: BoxDecoration(
        color: fill ?? kShareCardInk,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: shareCardText(size, FontWeight.w800, color ?? kShareCardDark,
            spacing: -0.2, height: 1.15, tabular: true),
      ),
    );
  }
}

/// The headline: the clear fact, white, with [emphasis] (the numbers in
/// it, as they appear in [text]) larger and heavier.
class ShareCardHeadline extends StatelessWidget {
  const ShareCardHeadline({
    super.key,
    required this.text,
    this.emphasis = const [],
    this.size = 26,
    this.maxLines = 3,
    this.emphasisColor,
  });

  final String text;
  final List<String> emphasis;
  final double size;
  final int maxLines;
  final Color? emphasisColor;

  @override
  Widget build(BuildContext context) {
    final plain = shareCardText(size, FontWeight.w700, kShareCardInk,
        spacing: -0.6, height: 1.15);
    final strong = plain.copyWith(
      fontSize: size * 1.18,
      fontWeight: FontWeight.w800,
      color: emphasisColor ?? kShareCardInk,
      letterSpacing: -0.9,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Text.rich(
      TextSpan(children: shareCardEmphasise(text, emphasis, plain, strong)),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// [text] as spans with every occurrence of [tokens] in [strong].
List<TextSpan> shareCardEmphasise(
    String text, List<String> tokens, TextStyle plain, TextStyle strong) {
  final wanted = tokens.where((t) => t.isNotEmpty).toList();
  final spans = <TextSpan>[];
  var i = 0;
  while (i < text.length) {
    var at = -1;
    var hit = '';
    for (final t in wanted) {
      final j = text.indexOf(t, i);
      if (j >= 0 && (at < 0 || j < at)) {
        at = j;
        hit = t;
      }
    }
    if (at < 0) {
      spans.add(TextSpan(text: text.substring(i), style: plain));
      break;
    }
    if (at > i) spans.add(TextSpan(text: text.substring(i, at), style: plain));
    spans.add(TextSpan(text: hit, style: strong));
    i = at + hit.length;
  }
  return spans;
}

/// A market's logo: the coin icon on an Investing market, the market's
/// picture on a prediction, else its first letter.
class ShareCardLogo extends StatelessWidget {
  const ShareCardLogo({
    super.key,
    required this.size,
    required this.title,
    required this.investing,
    this.round = false,
    this.coin,
    this.wireCoin,
    this.iconUrl,
    this.category,
    this.imageUrl,
  });

  final double size;
  final String title;
  final bool investing;
  final bool round;
  final String? coin;
  final String? wireCoin;
  final String? iconUrl;
  final String? category;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(round ? size / 2 : size * 0.26);
    final Widget fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: round ? const Color(0xFFEDEDED) : kShareCardInk,
        borderRadius: radius,
      ),
      child: Text(
        title.isEmpty ? '?' : title.characters.first.toUpperCase(),
        style: shareCardText(size * 0.45, FontWeight.w800, kShareCardDark),
      ),
    );
    final Widget child;
    if (investing && coin != null) {
      child = FittedBox(
        child: HlCoinIcon(
          coin: coin!,
          wireCoin: wireCoin,
          iconUrl: iconUrl,
          category: category,
          size: size,
        ),
      );
    } else if (imageUrl case final url? when url.isNotEmpty) {
      child = ClipRRect(
        borderRadius: radius,
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback,
        ),
      );
    } else {
      child = fallback;
    }
    return SizedBox.square(dimension: size, child: child);
  }
}

/// The footer: the wordmark over [cta], and the referral code chip.
class ShareCardFooter extends StatelessWidget {
  const ShareCardFooter({
    super.key,
    required this.code,
    required this.cta,
    this.codeLabel,
    this.keyPrefix = 'share-card',
  });

  final String? code;
  final String cta;

  /// The small label in the code chip; "Code" in the app's language by
  /// default.
  final String? codeLabel;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final mark =
        shareCardText(26, FontWeight.w800, kShareCardInk, spacing: -0.8, height: 1.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(height: 0.8, color: kShareCardInk.withValues(alpha: 0.22)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text.rich(
                    key: ValueKey('$keyPrefix-wordmark'),
                    TextSpan(children: [
                      TextSpan(text: 'kute', style: mark),
                      TextSpan(
                          text: '.',
                          style: mark.copyWith(color: AppColors.accent)),
                    ]),
                  ),
                  const SizedBox(height: 3),
                  Text(cta,
                      key: ValueKey('$keyPrefix-cta'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: shareCardText(12.5, FontWeight.w700,
                          kShareCardInk.withValues(alpha: 0.85))),
                ],
              ),
            ),
            if (code != null)
              Container(
                key: ValueKey('$keyPrefix-code'),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: kShareCardInk,
                  borderRadius: BorderRadius.circular(100),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Text.rich(TextSpan(children: [
                  TextSpan(
                      text: '${(codeLabel ?? context.l10n.bragCodeLabel).toUpperCase()}  ',
                      style: shareCardText(
                          10, FontWeight.w700, const Color(0xFF6B6B70),
                          spacing: 1)),
                  TextSpan(
                      text: code,
                      style: shareCardText(17, FontWeight.w900, kShareCardDark,
                          spacing: 0.6)),
                ])),
              ),
          ],
        ),
      ],
    );
  }
}

/// The smooth line of [points] (a price, a chance) with a soft fill under
/// it and a dot at its live end, in [color].
class ShareCardLinePainter extends CustomPainter {
  ShareCardLinePainter({
    required this.points,
    this.color = kShareCardInk,
    this.strokeWidth = 2.6,
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
    const pad = 7.0;
    double y(double v) =>
        pad + (1 - (v - lo) / (hi - lo)) * (size.height - 2 * pad);
    double x(int i) => i / (points.length - 1) * (size.width - pad);
    final pts = [
      for (var i = 0; i < points.length; i++) Offset(x(i), y(points[i]))
    ];
    // Catmull-Rom through the points as cubic Béziers: the in-page
    // chart's smooth line.
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 0; i < pts.length - 1; i++) {
      final p0 = pts[math.max(0, i - 1)];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = pts[math.min(pts.length - 1, i + 2)];
      final c1 = p1 + (p2 - p0) / 6;
      final c2 = p2 - (p3 - p1) / 6;
      // Keep the control points inside the plot so a swing never
      // overshoots past the edge.
      double clampY(double v) => v.clamp(1.0, size.height - 1);
      line.cubicTo(c1.dx, clampY(c1.dy), c2.dx, clampY(c2.dy), p2.dx, p2.dy);
    }
    final fill = Path.from(line)
      ..lineTo(pts.last.dx, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(0, size.height),
            [color.withValues(alpha: 0.28), color.withValues(alpha: 0)]),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    final end = pts.last;
    canvas.drawCircle(end, 6.5, Paint()..color = color.withValues(alpha: 0.3));
    canvas.drawCircle(end, 3.6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(ShareCardLinePainter old) =>
      old.points != points || old.color != color;
}
