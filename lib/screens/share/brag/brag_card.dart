// lib/screens/share/brag/brag_card.dart
//
// THE BRAG CARD (founder, 1 November 2026: "must look much better, much
// more fun. Sal should be like 'I am better'"). A 4:5 share image laid out
// at [kBragCardSize] logical pixels and captured at [kBragCardPixelRatio]
// (1080 × 1350, the feed size every network takes whole), in the share-
// card energy of Spotify Wrapped and Robinhood: full bleed, loud, one big
// number, the mascot as the hero.
//
//   * BACKGROUND: a saturated gradient that follows the tone
//     ([bragBackground]): deep green when up (brighter on a big win), deep
//     red when down, near-black when flat; a soft glow behind Sal. White
//     type throughout.
//   * HEADLINE: the result big and confident ("+$7.57"), the percent in a
//     white pill under it when there is one ("+42.1%"), a tiny period line
//     ("All time", "Since you bought").
//   * SAL, LARGE (about 40% of the card's height, [kBragSalHeight]) at the
//     bottom right: the tone's still (brag_sal.dart; smug, sunglasses only
//     on a big win, unbothered on a loss) with his one-liner in a white
//     speech bubble pointing at him (brag_lines.dart, PG).
//   * PORTFOLIO: "My portfolio" over "All time", the allocation ring small
//     in the top right corner (shares only, no legend), the top three open
//     positions as bold chips with their logos and results.
//   * POSITION: the market's logo and title, the side pill beside the
//     period line, the held side's line since the buy and Entry → Now in
//     the left column when the page has them.
//   * FOOTER: the "kute." wordmark over "Beat me on Kute", and the
//     sharer's referral code as a bold white chip.
//
// AMOUNTS (founder, 1 November 2026: "don't even give the option"): the
// card always shows the real amounts, with the percents where they exist.
//
// The card never reads a provider or the screen's scale: the same pixels
// at every size, so the preview is exactly the image (the coin icon's own
// scale is fitted back into its box).

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/share/brag/brag_data.dart';
import 'package:kute/screens/share/brag/brag_lines.dart';
import 'package:kute/screens/share/brag/brag_sal.dart';
import 'package:kute/theme/app_theme.dart';

/// The card's logical size: 4:5.
const Size kBragCardSize = Size(360, 450);

/// The capture's pixel ratio: [kBragCardSize] × 3 = 1080 × 1350.
const double kBragCardPixelRatio = 3;

/// Sal's height on the card: about 40% of it.
const double kBragSalHeight = 184;

/// The card's gradient for [tone], top left to bottom right.
List<Color> bragBackground(BragTone tone) => switch (tone) {
      BragTone.bigWin => const [Color(0xFF17B35E), Color(0xFF065A2E)],
      BragTone.win || BragTone.smallWin => const [
          Color(0xFF0E8A47),
          Color(0xFF04401F)
        ],
      BragTone.loss => const [Color(0xFFC8283C), Color(0xFF570B16)],
      BragTone.flat => const [Color(0xFF2A2A2E), Color(0xFF0B0B0D)],
    };

const String _font = 'Inter';
const Color _ink = Colors.white;
const Color _dark = Color(0xFF111214);

TextStyle _t(double size, FontWeight weight, Color color,
        {double spacing = 0, double height = 1.2, bool tabular = false}) =>
    TextStyle(
      fontFamily: _font,
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: spacing,
      height: height,
      decoration: TextDecoration.none,
      fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
    );

class BragCard extends StatelessWidget {
  const BragCard({
    super.key,
    required this.data,
    this.sal,
    this.lineSeed = 0,
  });

  final BragData data;

  /// The decoded still for the tone (BragSalStills); null: no Sal.
  final ui.Image? sal;

  /// Picks Sal's line in the tone's pool (bragLine).
  final int lineSeed;

  @override
  Widget build(BuildContext context) {
    final tone = data.tone;
    final line = bragLine(context.l10n, tone, lineSeed);
    final theme = Theme.of(context);
    return Theme(
      // The light colours for the icons inside, whatever the app's mode.
      data: theme.copyWith(
          brightness: Brightness.light,
          extensions: [AppColorsExtension.light()]),
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
        child: SizedBox.fromSize(
          size: kBragCardSize,
          child: DecoratedBox(
            key: const ValueKey('brag-card-bg'),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: bragBackground(tone),
              ),
            ),
            child: Stack(
              children: [
                // The glow behind Sal.
                Positioned(
                  right: -80,
                  bottom: -10,
                  width: 340,
                  height: 340,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(colors: [
                        Colors.white.withValues(alpha: 0.22),
                        Colors.white.withValues(alpha: 0),
                      ]),
                    ),
                  ),
                ),
                if (sal != null)
                  Positioned(
                    right: 4,
                    bottom: 60,
                    height: kBragSalHeight,
                    width: kBragSalHeight * kBragSalAspect,
                    child: RawImage(
                      key: ValueKey(bragSalWearsShades(tone)
                          ? 'brag-card-sal-shades'
                          : 'brag-card-sal'),
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
                      Expanded(
                        child: switch (data) {
                          final BragPosition p =>
                            _PositionBody(data: p, line: line),
                          final BragPortfolio p =>
                            _PortfolioBody(data: p, line: line),
                        },
                      ),
                      _Footer(code: data.referralCode),
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

/// The left column beside Sal: the card's width less the margins and
/// Sal, a little under him.
const double _kColumnWidth = 360 - 44 - kBragSalHeight * kBragSalAspect + 18;

// ─── Headline ────────────────────────────────────────────────────────

/// The big result with its percent pill.
class _Headline extends StatelessWidget {
  const _Headline({required this.result});

  final BragResult? result;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final pct = r?.percent;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              r?.text ?? '—',
              key: const ValueKey('brag-card-result'),
              maxLines: 1,
              style: _t(64, FontWeight.w800, _ink,
                  spacing: -2.6, height: 1.0, tabular: true),
            ),
          ),
        ),
        if (pct != null) ...[
          const SizedBox(width: 10),
          Container(
            key: const ValueKey('brag-card-percent'),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            decoration: BoxDecoration(
              color: _ink,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(
              bragPercent(pct),
              maxLines: 1,
              style: _t(17, FontWeight.w800, _dark,
                  spacing: -0.4, height: 1.1, tabular: true),
            ),
          ),
        ],
      ],
    );
  }
}

/// The small caps period line ("ALL TIME").
Widget _period(String text, {Key? key}) => Text(
      text.toUpperCase(),
      key: key,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style:
          _t(11, FontWeight.w700, _ink.withValues(alpha: 0.75), spacing: 1.2),
    );

// ─── Sal's line ──────────────────────────────────────────────────────

/// Sal's one-liner in a white speech bubble, its tail at the right
/// pointing down at him.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final long = text.length > 24;
    return CustomPaint(
      painter: _BubblePainter(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
        child: Text(
          text,
          key: const ValueKey('brag-card-line'),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: _t(long ? 15 : 20, FontWeight.w800, _dark,
              spacing: long ? -0.3 : -0.6, height: 1.15),
        ),
      ),
    );
  }
}

class _BubblePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = _ink;
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

// ─── Position ────────────────────────────────────────────────────────

class _PositionBody extends StatelessWidget {
  const _PositionBody({required this.data, required this.line});

  final BragPosition data;
  final String line;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _Logo(
              key: const ValueKey('brag-card-logo'),
              size: 38,
              title: data.title,
              investing: data.investing,
              coin: data.coin,
              wireCoin: data.wireCoin,
              iconUrl: data.iconUrl,
              category: data.category,
              imageUrl: data.imageUrl,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                data.title,
                key: const ValueKey('brag-card-title'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    _t(15.5, FontWeight.w800, _ink, spacing: -0.3, height: 1.2),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Container(
              key: const ValueKey('brag-card-side'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: _ink,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                data.side,
                maxLines: 1,
                style: _t(12, FontWeight.w800, _dark, spacing: -0.1),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _period(
                  '${data.investing ? l10n.trading : l10n.predictions}'
                  ' · ${l10n.bragSinceYouBought}',
                  key: const ValueKey('brag-card-period')),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _Headline(result: data.result),
        const SizedBox(height: 16),
        Expanded(
          child: SizedBox(
            width: _kColumnWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: _Bubble(text: line),
                ),
                if (data.series != null)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 14, bottom: 8),
                      child: SizedBox(
                        key: const ValueKey('brag-card-chart'),
                        width: double.infinity,
                        child: CustomPaint(
                          painter: _LinePainter(
                              points: data.series!, entry: data.entryValue),
                        ),
                      ),
                    ),
                  )
                else
                  const Spacer(),
                if (data.entryText != null || data.nowText != null)
                  _EntryNow(entry: data.entryText, now: data.nowText),
                const SizedBox(height: 14),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EntryNow extends StatelessWidget {
  const _EntryNow({required this.entry, required this.now});

  final String? entry;
  final String? now;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Widget figure(String label, String value) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label.toUpperCase(),
                style: _t(9.5, FontWeight.w700, _ink.withValues(alpha: 0.72),
                    spacing: 1)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  maxLines: 1,
                  style: _t(16, FontWeight.w800, _ink,
                      spacing: -0.3, tabular: true)),
            ),
          ],
        );
    return Container(
      key: const ValueKey('brag-card-entry-now'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          if (entry != null) Expanded(child: figure(l10n.bragEntry, entry!)),
          if (entry != null && now != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text('→',
                  style: _t(16, FontWeight.w700, _ink.withValues(alpha: 0.72))),
            ),
          if (now != null) Expanded(child: figure(l10n.bragNow, now!)),
        ],
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({required this.points, required this.entry});

  final List<double> points;
  final double? entry;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2 || size.height < 8) return;
    var lo = points.reduce(math.min);
    var hi = points.reduce(math.max);
    if (entry != null) {
      lo = math.min(lo, entry!);
      hi = math.max(hi, entry!);
    }
    if (hi - lo < 1e-9) {
      hi += 0.5;
      lo -= 0.5;
    }
    const pad = 7.0;
    double y(double v) =>
        pad + (1 - (v - lo) / (hi - lo)) * (size.height - 2 * pad);
    double x(int i) => i / (points.length - 1) * (size.width - pad);
    final line = Path()..moveTo(x(0), y(points.first));
    for (var i = 1; i < points.length; i++) {
      line.lineTo(x(i), y(points[i]));
    }
    final fill = Path.from(line)
      ..lineTo(x(points.length - 1), size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(0, size.height),
            [_ink.withValues(alpha: 0.28), _ink.withValues(alpha: 0)]),
    );
    if (entry != null) {
      final ey = y(entry!);
      final dash = Paint()
        ..color = _ink.withValues(alpha: 0.5)
        ..strokeWidth = 1;
      for (double dx = 0; dx < size.width; dx += 7) {
        canvas.drawLine(
            Offset(dx, ey), Offset(math.min(dx + 3.5, size.width), ey), dash);
      }
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    final end = Offset(x(points.length - 1), y(points.last));
    canvas.drawCircle(end, 6.5, Paint()..color = _ink.withValues(alpha: 0.3));
    canvas.drawCircle(end, 3.6, Paint()..color = _ink);
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.points != points || old.entry != entry;
}

// ─── Portfolio ───────────────────────────────────────────────────────

class _PortfolioBody extends StatelessWidget {
  const _PortfolioBody({required this.data, required this.line});

  final BragPortfolio data;
  final String line;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.title,
                    key: const ValueKey('brag-card-title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _t(18, FontWeight.w800, _ink, spacing: -0.4),
                  ),
                  const SizedBox(height: 3),
                  _period(l10n.portfolioAllTime,
                      key: const ValueKey('brag-card-period')),
                ],
              ),
            ),
            if (data.slices.isNotEmpty)
              SizedBox.square(
                key: const ValueKey('brag-card-allocation'),
                dimension: 40,
                child: CustomPaint(painter: _RingPainter(slices: data.slices)),
              ),
          ],
        ),
        const SizedBox(height: 14),
        _Headline(result: data.allTime),
        const SizedBox(height: 18),
        Expanded(
          child: SizedBox(
            width: _kColumnWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: _Bubble(text: line),
                ),
                const Spacer(),
                for (var i = 0; i < data.top.length; i++) ...[
                  if (i > 0) const SizedBox(height: 7),
                  _TopChip(key: ValueKey('brag-card-top-$i'), row: data.top[i]),
                ],
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One of the top positions as a bold chip: its logo, its name (a
/// prediction's named outcome, else the market) and its result (the
/// percent, else the amount) in the result's colour.
class _TopChip extends StatelessWidget {
  const _TopChip({super.key, required this.row});

  final BragTopPosition row;

  @override
  Widget build(BuildContext context) {
    final r = row.result;
    final pct = r.percent;
    final side = row.side;
    // A named outcome ("Gen.G") says more than the long question; a Yes
    // or No does not.
    final named = side != null &&
        side.isNotEmpty &&
        !row.investing &&
        !const {'yes', 'no'}.contains(side.trim().toLowerCase());
    final name = named ? side : row.title;
    return Container(
      height: 34,
      padding: const EdgeInsets.fromLTRB(5, 5, 11, 5),
      decoration: BoxDecoration(
        color: _ink,
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
        children: [
          _Logo(
            size: 24,
            round: true,
            title: row.title,
            investing: row.investing,
            coin: row.coin,
            wireCoin: row.wireCoin,
            iconUrl: row.iconUrl,
            category: row.category,
            imageUrl: row.imageUrl,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _t(13, FontWeight.w700, _dark, spacing: -0.2),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            pct != null ? bragPercent(pct) : r.text,
            maxLines: 1,
            style: _t(
                13.5,
                FontWeight.w800,
                r.up
                    ? const Color(0xFF0E8A47)
                    : r.down
                        ? const Color(0xFFC8283C)
                        : _dark,
                spacing: -0.3,
                tabular: true),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.slices});

  final List<BragSlice> slices;

  static double _alpha(BragSlicePart part) => switch (part) {
        BragSlicePart.investing => 1.0,
        BragSlicePart.predictions => 0.62,
        BragSlicePart.dollars => 0.32,
      };

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 7.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    canvas.drawArc(
        rect,
        0,
        math.pi * 2,
        false,
        Paint()
          ..color = _ink.withValues(alpha: 0.14)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke);
    final shown = [
      for (var i = 0; i < slices.length; i++)
        if (slices[i].share > 0.001) i
    ];
    final gap = shown.length > 1 ? 0.12 : 0.0;
    var start = -math.pi / 2;
    for (final i in shown) {
      final sweep = slices[i].share * math.pi * 2;
      canvas.drawArc(
        rect,
        start + gap / 2,
        math.max(0.0, sweep - gap),
        false,
        Paint()
          ..color = _ink.withValues(alpha: _alpha(slices[i].part))
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.slices != slices;
}

// ─── Shared ──────────────────────────────────────────────────────────

/// A market's logo: the coin icon on an Investing position, the market's
/// picture on a prediction, else its first letter.
class _Logo extends StatelessWidget {
  const _Logo({
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
        color: round ? const Color(0xFFEDEDED) : _ink,
        borderRadius: radius,
      ),
      child: Text(
        title.isEmpty ? '?' : title.characters.first.toUpperCase(),
        style: _t(size * 0.45, FontWeight.w800, _dark),
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

class _Footer extends StatelessWidget {
  const _Footer({required this.code});

  final String? code;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final mark = _t(26, FontWeight.w800, _ink, spacing: -0.8, height: 1.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(height: 0.8, color: _ink.withValues(alpha: 0.22)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text.rich(
                    key: const ValueKey('brag-card-wordmark'),
                    TextSpan(children: [
                      TextSpan(text: 'kute', style: mark),
                      TextSpan(
                          text: '.',
                          style: mark.copyWith(color: AppColors.accent)),
                    ]),
                  ),
                  const SizedBox(height: 3),
                  Text(l10n.bragBeatMeOnKute,
                      key: const ValueKey('brag-card-cta'),
                      style: _t(
                          12.5, FontWeight.w700, _ink.withValues(alpha: 0.85))),
                ],
              ),
            ),
            if (code != null)
              Container(
                key: const ValueKey('brag-card-code'),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: _ink,
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
                      text: '${l10n.bragCodeLabel.toUpperCase()}  ',
                      style: _t(10, FontWeight.w700, const Color(0xFF6B6B70),
                          spacing: 1)),
                  TextSpan(
                      text: code,
                      style: _t(17, FontWeight.w900, _dark, spacing: 0.6)),
                ])),
              ),
          ],
        ),
      ],
    );
  }
}
