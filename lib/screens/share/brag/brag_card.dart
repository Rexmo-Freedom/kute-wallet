// lib/screens/share/brag/brag_card.dart
//
// THE BRAG CARD (founder, 1 November 2026): a 4:5 share image, laid out
// at [kBragCardSize] logical pixels and captured at [kBragCardPixelRatio]
// (1080 × 1350, the feed size every network takes whole), in the premium
// share-your-trade style (Robinhood, Revolut): a light page, the app's
// Inter, 24 of margin all round, one big figure in the result colour.
//
//   * POSITION: the market's logo and title (two lines), the side pill
//     ("Long", "Yes", a candidate) beside the venue's name; the BIG result
//     in colour (the signed amount with its percent under it, or the
//     percent alone while amounts are hidden), Sal's face at its end; the
//     held side's thin line since the buy when the page has it (a dashed
//     line at the price paid); Entry → Now.
//   * PORTFOLIO: "My portfolio", the all-time P&L big in colour with the
//     past month under it and Sal beside it; the allocation ring with the
//     share of each part (percent only: a brag card never shows a
//     balance); the top three open positions with their results.
//
// Sal is sarcastic about it (founder): a WINK when the result is up, a
// SHAKE-NO when it is down, one key frame of each clip
// ([kBragWinkFrame], [kBragShakeNoFrame]: frame 0 of both is his neutral
// face) drawn from the decoded sheet ([SalSpriteCache]); no sheet, no Sal.
//
// AMOUNTS (founder, 1 November 2026: "don't even give the option"): the
// card always shows the real amounts, with the percents where they exist.
//
// The footer, both cards: the "kute." wordmark over "Trade it on Kute",
// and the sharer's referral code in a chip at the end when they have one.
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
import 'package:kute/screens/shared/sal_sprite.dart' show SalClip;
import 'package:kute/theme/app_theme.dart';

/// The card's logical size: 4:5.
const Size kBragCardSize = Size(360, 450);

/// The capture's pixel ratio: [kBragCardSize] × 3 = 1080 × 1350.
const double kBragCardPixelRatio = 3;

/// Sal's clips on the card and the frame of each that carries the face.
const String kBragWinkClip = 'wink';
const String kBragShakeNoClip = 'shake_no';
const int kBragWinkFrame = 12;
const int kBragShakeNoFrame = 5;

/// The clip for a result.
String bragSalClip(BragData data) => data.up ? kBragWinkClip : kBragShakeNoClip;

const String _font = 'Inter';

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
  });

  final BragData data;

  /// The decoded clip for [bragSalClip] (null: no Sal on the card).
  final SalClip? sal;

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExtension.light();
    final tint = data.up ? AppColors.marketUp : AppColors.marketDown;
    final theme = Theme.of(context);
    return Theme(
      // The card is always the light page, whatever the app's mode: the
      // icons inside read the light colours.
      data: theme.copyWith(brightness: Brightness.light, extensions: [c]),
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
        child: SizedBox.fromSize(
          size: kBragCardSize,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.alphaBlend(tint.withValues(alpha: 0.08), Colors.white),
                  Colors.white,
                  const Color(0xFFF7F7F5),
                ],
                stops: const [0, 0.55, 1],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: switch (data) {
                      final BragPosition p => _PositionBody(
                          data: p, sal: sal, c: c),
                      final BragPortfolio p => _PortfolioBody(
                          data: p, sal: sal, c: c),
                    },
                  ),
                  _Footer(code: data.referralCode, c: c),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Color _resultColor(BragResult r, AppColorsExtension c) => r.up
    ? AppColors.marketUp
    : r.down
        ? AppColors.marketDown
        : c.textPrimary;

/// Sal's face: one frame of [clip], drawn into [size].
class _SalFace extends StatelessWidget {
  const _SalFace({required this.clip, required this.frame, required this.size});

  final SalClip clip;
  final int frame;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        key: const ValueKey('brag-card-sal'),
        dimension: size,
        child: CustomPaint(painter: _SalPainter(clip, frame)),
      );
}

class _SalPainter extends CustomPainter {
  _SalPainter(this.clip, this.frame);

  final SalClip clip;
  final int frame;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      clip.image,
      // A pixel in from the cell's edges: the neighbour cells never bleed.
      clip.cell(frame).deflate(1),
      Offset.zero & size,
      Paint()
        ..filterQuality = FilterQuality.high
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_SalPainter old) => old.clip != clip || old.frame != frame;
}

Widget? _sal(BragData data, SalClip? clip, double size) {
  if (clip == null) return null;
  return _SalFace(
      clip: clip,
      frame: data.up ? kBragWinkFrame : kBragShakeNoFrame,
      size: size);
}

// ─── Position ────────────────────────────────────────────────────────

class _PositionBody extends StatelessWidget {
  const _PositionBody({
    required this.data,
    required this.sal,
    required this.c,
  });

  final BragPosition data;
  final SalClip? sal;
  final AppColorsExtension c;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final r = data.result;
    final color = _resultColor(r, c);
    final pct = r.percent;
    // The big figure: the amount when shown, else the percent, else the
    // masked amount; the percent under the amount when both show.
    final String big = r.text;
    final String? under = pct != null ? bragPercent(pct) : null;
    final face = _sal(data, sal, 84);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _Logo(data: data, c: c),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                data.title,
                key: const ValueKey('brag-card-title'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: _t(18, FontWeight.w700, c.textPrimary,
                    spacing: -0.3, height: 1.22),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            _Pill(
              key: const ValueKey('brag-card-side'),
              text: data.side,
              fill: c.textPrimary,
              ink: Colors.white,
            ),
            const SizedBox(width: 8),
            Text(
              data.investing ? l10n.trading : l10n.predictions,
              style: _t(13, FontWeight.w600, c.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      big,
                      key: const ValueKey('brag-card-result'),
                      maxLines: 1,
                      style: _t(54, FontWeight.w800, color,
                          spacing: -2, height: 1.05, tabular: true),
                    ),
                  ),
                  if (under != null) ...[
                    const SizedBox(height: 6),
                    _Pill(
                      key: const ValueKey('brag-card-percent'),
                      text: under,
                      fill: color.withValues(alpha: 0.12),
                      ink: color,
                      size: 15,
                    ),
                  ],
                ],
              ),
            ),
            if (face != null) ...[const SizedBox(width: 8), face],
          ],
        ),
        // The line takes the room left (none drawn without a series).
        Expanded(
          child: data.series == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: SizedBox(
                    key: const ValueKey('brag-card-line'),
                    width: double.infinity,
                    child: CustomPaint(
                      painter: _LinePainter(
                        points: data.series!,
                        entry: data.entryValue,
                        color: color,
                        guide: c.textTertiary,
                      ),
                    ),
                  ),
                ),
        ),
        if (data.entryText != null || data.nowText != null)
          _EntryNow(entry: data.entryText, now: data.nowText, c: c),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.data, required this.c});

  final BragPosition data;
  final AppColorsExtension c;

  static const double size = 46;

  @override
  Widget build(BuildContext context) {
    final Widget fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        data.title.isEmpty ? '?' : data.title.characters.first.toUpperCase(),
        style: _t(20, FontWeight.w700, c.textSecondary),
      ),
    );
    final Widget child;
    if (data.investing && data.coin != null) {
      child = FittedBox(
        child: HlCoinIcon(
          coin: data.coin!,
          wireCoin: data.wireCoin,
          iconUrl: data.iconUrl,
          category: data.category,
          size: size,
        ),
      );
    } else if (data.imageUrl case final url? when url.isNotEmpty) {
      child = ClipRRect(
        borderRadius: BorderRadius.circular(12),
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
    return SizedBox.square(
        key: const ValueKey('brag-card-logo'), dimension: size, child: child);
  }
}

class _EntryNow extends StatelessWidget {
  const _EntryNow({required this.entry, required this.now, required this.c});

  final String? entry;
  final String? now;
  final AppColorsExtension c;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Widget figure(String label, String value) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label.toUpperCase(),
                style: _t(10.5, FontWeight.w600, c.textTertiary, spacing: 0.8)),
            const SizedBox(height: 4),
            Text(value,
                maxLines: 1,
                style: _t(17, FontWeight.w700, c.textPrimary,
                    spacing: -0.3, tabular: true)),
          ],
        );
    return Container(
      key: const ValueKey('brag-card-entry-now'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.borderSubtle, width: 0.8),
      ),
      child: Row(
        children: [
          if (entry != null) Expanded(child: figure(l10n.bragEntry, entry!)),
          if (entry != null && now != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('\u2192',
                  style: _t(18, FontWeight.w600, c.textTertiary)),
            ),
          if (now != null) Expanded(child: figure(l10n.bragNow, now!)),
        ],
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.points,
    required this.entry,
    required this.color,
    required this.guide,
  });

  final List<double> points;
  final double? entry;
  final Color color;
  final Color guide;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
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
    const pad = 6.0;
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
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, size.height),
          [color.withValues(alpha: 0.18), color.withValues(alpha: 0)],
        ),
    );
    if (entry != null) {
      final ey = y(entry!);
      final dash = Paint()
        ..color = guide
        ..strokeWidth = 1;
      for (double dx = 0; dx < size.width; dx += 7) {
        canvas.drawLine(
            Offset(dx, ey), Offset(math.min(dx + 3.5, size.width), ey), dash);
      }
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    final end = Offset(x(points.length - 1), y(points.last));
    canvas.drawCircle(end, 6, Paint()..color = color.withValues(alpha: 0.2));
    canvas.drawCircle(end, 3.4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.points != points || old.entry != entry || old.color != color;
}

// ─── Portfolio ───────────────────────────────────────────────────────

Color bragSliceColor(AppColorsExtension c, BragSlicePart part) =>
    switch (part) {
      // The Portfolio ring's own colours (balancesCategoryColor).
      BragSlicePart.dollars => c.chartCategorical[0],
      BragSlicePart.investing => c.chartCategorical[1],
      BragSlicePart.predictions => c.chartCategorical[2],
    };

class _PortfolioBody extends StatelessWidget {
  const _PortfolioBody({
    required this.data,
    required this.sal,
    required this.c,
  });

  final BragPortfolio data;
  final SalClip? sal;
  final AppColorsExtension c;

  String _money(BragResult r) => r.text;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final face = _sal(data, sal, 76);
    final allTime = data.allTime;
    final month = data.month;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.title,
                    key: const ValueKey('brag-card-title'),
                    style:
                        _t(19, FontWeight.w800, c.textPrimary, spacing: -0.4),
                  ),
                  const SizedBox(height: 8),
                  Text(l10n.portfolioAllTime.toUpperCase(),
                      style: _t(10.5, FontWeight.w600, c.textTertiary,
                          spacing: 0.8)),
                  const SizedBox(height: 2),
                  if (allTime != null)
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _money(allTime),
                        key: const ValueKey('brag-card-result'),
                        maxLines: 1,
                        style: _t(42, FontWeight.w800, _resultColor(allTime, c),
                            spacing: -1.6, height: 1.05, tabular: true),
                      ),
                    )
                  else
                    Text('—',
                        key: const ValueKey('brag-card-result'),
                        style: _t(42, FontWeight.w800, c.textTertiary,
                            height: 1.05)),
                  if (month != null) ...[
                    const SizedBox(height: 6),
                    Text.rich(
                      key: const ValueKey('brag-card-month'),
                      TextSpan(children: [
                        TextSpan(
                            text: '${l10n.chartPeriodPastMonth}  ',
                            style: _t(13, FontWeight.w500, c.textSecondary)),
                        TextSpan(
                            text: month.up
                                ? '▲ '
                                : month.down
                                    ? '▼ '
                                    : '',
                            style: _t(
                                11, FontWeight.w700, _resultColor(month, c))),
                        TextSpan(
                            text: _money(month),
                            style: _t(
                                13, FontWeight.w700, _resultColor(month, c),
                                tabular: true)),
                      ]),
                    ),
                  ],
                ],
              ),
            ),
            if (face != null) ...[const SizedBox(width: 8), face],
          ],
        ),
        if (data.slices.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(
            key: const ValueKey('brag-card-allocation'),
            children: [
              SizedBox.square(
                dimension: 66,
                child: CustomPaint(
                  painter: _RingPainter(
                    slices: data.slices,
                    colors: [
                      for (final s in data.slices) bragSliceColor(c, s.part)
                    ],
                    track: c.surfaceLight,
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final s in data.slices)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.5),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: bragSliceColor(c, s.part),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                switch (s.part) {
                                  BragSlicePart.investing => l10n.trading,
                                  BragSlicePart.predictions => l10n.predictions,
                                  BragSlicePart.dollars =>
                                    l10n.portfolioBalanceDollars,
                                },
                                style: _t(13, FontWeight.w500, c.textSecondary),
                              ),
                            ),
                            Text(
                              _sharePercent(s.share),
                              style: _t(13, FontWeight.w700, c.textPrimary,
                                  tabular: true),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
        const Spacer(),
        if (data.top.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(l10n.bragTopPositions.toUpperCase(),
              style: _t(10.5, FontWeight.w600, c.textTertiary, spacing: 0.8)),
          const SizedBox(height: 6),
          Container(
            key: const ValueKey('brag-card-top'),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.borderSubtle, width: 0.8),
            ),
            child: Column(
              children: [
                for (var i = 0; i < data.top.length; i++) ...[
                  if (i > 0) Container(height: 0.6, color: c.borderSubtle),
                  _TopRow(
                      key: ValueKey('brag-card-top-$i'),
                      row: data.top[i],
                      c: c),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
      ],
    );
  }
}

/// A share as the Portfolio legend writes it (balancesPercent).
String _sharePercent(double share) {
  if (!share.isFinite || share <= 0) return '0%';
  final pct = share * 100;
  if (pct < 1) return '<1%';
  if (pct > 99 && pct < 100) return '>99%';
  return '${pct.round()}%';
}

class _TopRow extends StatelessWidget {
  const _TopRow({
    super.key,
    required this.row,
    required this.c,
  });

  final BragTopPosition row;
  final AppColorsExtension c;

  @override
  Widget build(BuildContext context) {
    final r = row.result;
    final color = _resultColor(r, c);
    final pct = r.percent;
    final String figure = pct != null ? bragPercent(pct) : r.text;
    return SizedBox(
      height: 31,
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                if (row.side case final side? when side.isNotEmpty)
                  TextSpan(
                      text: '$side · ',
                      style: _t(13, FontWeight.w700, c.textPrimary)),
                TextSpan(
                    text: row.title,
                    style: _t(13, FontWeight.w500, c.textPrimary)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          if (pct != null) ...[
            Text(r.text,
                style: _t(12, FontWeight.w500, c.textSecondary, tabular: true)),
            const SizedBox(width: 8),
          ],
          Text(figure, style: _t(13.5, FontWeight.w700, color, tabular: true)),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(
      {required this.slices, required this.colors, required this.track});

  final List<BragSlice> slices;
  final List<Color> colors;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 11.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    canvas.drawArc(
        rect,
        0,
        math.pi * 2,
        false,
        Paint()
          ..color = track
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke);
    final shown = [
      for (var i = 0; i < slices.length; i++)
        if (slices[i].share > 0.001) i
    ];
    final gap = shown.length > 1 ? 0.06 : 0.0;
    var start = -math.pi / 2;
    for (final i in shown) {
      final sweep = slices[i].share * math.pi * 2;
      final drawn = math.max(0.0, sweep - gap);
      canvas.drawArc(
        rect,
        start + gap / 2,
        drawn,
        false,
        Paint()
          ..color = colors[i]
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.slices != slices || old.colors != colors;
}

// ─── Shared ──────────────────────────────────────────────────────────

class _Pill extends StatelessWidget {
  const _Pill({
    super.key,
    required this.text,
    required this.fill,
    required this.ink,
    this.size = 13,
  });

  final String text;
  final Color fill;
  final Color ink;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        padding:
            EdgeInsets.symmetric(horizontal: size * 0.8, vertical: size * 0.35),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _t(size, FontWeight.w700, ink, spacing: -0.1, tabular: true),
        ),
      );
}

class _Footer extends StatelessWidget {
  const _Footer({required this.code, required this.c});

  final String? code;
  final AppColorsExtension c;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final mark =
        _t(24, FontWeight.w800, c.textPrimary, spacing: -0.6, height: 1.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(height: 0.8, color: c.borderSubtle),
        const SizedBox(height: 14),
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
                  const SizedBox(height: 4),
                  Text(l10n.bragTradeItOnKute,
                      style: _t(12, FontWeight.w500, c.textSecondary)),
                ],
              ),
            ),
            if (code != null)
              Container(
                key: const ValueKey('brag-card-code'),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.35),
                      width: 0.8),
                ),
                child: Text.rich(TextSpan(children: [
                  TextSpan(
                      text: '${l10n.bragCodeLabel.toUpperCase()}  ',
                      style: _t(10, FontWeight.w600, c.textSecondary,
                          spacing: 0.8)),
                  TextSpan(
                      text: code,
                      style:
                          _t(14, FontWeight.w800, c.textPrimary, spacing: 0.4)),
                ])),
              ),
          ],
        ),
      ],
    );
  }
}
