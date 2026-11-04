// lib/screens/share/brag/brag_card.dart
//
// THE BRAG CARD, restrained premium (founder, 1 November 2026: the
// Robinhood / Revolut / Apple Card share cards, then "bigger numbers and
// such" and an edgy line on the card; 2 November 2026: the earlier
// cards' colours back, Sal whole and in a mood, the predictions' own
// speedometer). A 4:5 share image at [kBragCardSize], captured at
// [kBragCardPixelRatio] (1080 × 1350), in the share cards' one layout
// (cards/share_card_frame.dart) on one solid colour by the result's tone
// ([bragPalette]: green for a win, red for a loss, navy when flat):
//
//   * PORTFOLIO: "MY PORTFOLIO", the all-time P&L huge, "All time", then
//     the all-time P&L line filling the space when there is one
//     (BragPortfolio.series, the stock card's chart), else the top three
//     open positions as rows spread over it (the REAL logo 28 through the
//     app's widgets, HlCoinIcon or PolyCrestImage; the name 17; the
//     percent 17 w600 at the right in its colour). No ring.
//   * INVESTING POSITION: the stock card with the P&L as the hero: "MY
//     POSITION", the market's logo, title and the side held ("Long"), the
//     P&L huge, "Since you bought · +42.1%", the line since the buy filling
//     the space when the page has read it, and the entry and the price now
//     as the plain fact line ("3,812.40 → 3,576.10").
//   * PREDICTION POSITION: the same top, then the open-position screen's
//     speedometer (cards/share_card_speedometer.dart): the needle at the
//     held side's chance now, the dot at the price paid, the P&L huge under
//     its hub and "Since you bought · +42.1%"; the price paid and now as
//     the plain fact line ("41¢ → 62¢").
//   * Sal at the top right in the tone's pose ([bragPose]: lounging on a
//     win, eyes shut on a big one, a flop on a loss), the EDGY LINE
//     (brag_lines.dart) over the footer: the wordmark and the sharer's
//     code.
//
// AMOUNTS (founder, 1 November 2026: "don't even give the option"): the
// card always shows the real amounts, with the percents where they exist.
//
// The card never reads a provider or the screen's scale: the same pixels
// at every size, so the preview is exactly the image.

import 'package:flutter/material.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/share/brag/brag_data.dart';
import 'package:kute/screens/share/brag/brag_lines.dart';
import 'package:kute/screens/share/cards/share_card_frame.dart';
import 'package:kute/screens/share/cards/share_card_speedometer.dart';
import 'package:kute/screens/shared/sal_sprite.dart' show SalClip;

/// The card's logical size: 4:5.
const Size kBragCardSize = kShareCardSize;

/// The capture's pixel ratio: [kBragCardSize] × 3 = 1080 × 1350.
const double kBragCardPixelRatio = kShareCardPixelRatio;

/// The card's colour by the result's tone: green for a win, red for a
/// loss, navy when flat.
ShareCardPalette bragPalette(BragData data) => switch (data.tone) {
      BragTone.bigWin ||
      BragTone.win ||
      BragTone.smallWin =>
        ShareCardPalette.win,
      BragTone.loss => ShareCardPalette.loss,
      BragTone.flat => ShareCardPalette.flat,
    };

/// Sal's pose by the tone: retired on a big win, lounging on any other
/// win (a small one too), a flop on a loss, a side-eye when flat.
ShareCardPose bragPose(BragData data) => switch (data.tone) {
      BragTone.bigWin => ShareCardPose.bigWin,
      BragTone.win || BragTone.smallWin => ShareCardPose.win,
      BragTone.loss => ShareCardPose.loss,
      BragTone.flat => ShareCardPose.flat,
    };

/// A result's colour on [p]: up, down, or muted when flat.
Color _signed(ShareCardPalette p, BragResult r) => r.up
    ? p.up
    : r.down
        ? p.down
        : p.muted;

/// A row's logo in the portfolio card.
const double kBragRowLogo = 28;

/// The least height a row of the portfolio card takes, and a row whose
/// name takes two lines.
const double kBragRowHeight = 32;
const double kBragRowHeightTwoLines = 44;

/// A row's name and result sizes, and the smaller size a long name steps
/// down to on two lines.
const double kBragRowNameSize = 17;
const double kBragRowNameSmall = 15;

/// A row's name set in [width]: one line at [kBragRowNameSize] when it
/// fits, else two at [kBragRowNameSmall] (cut only after those two).
({double size, int lines}) bragRowNameFit(String name, double width) {
  if (!width.isFinite || width <= 0) {
    return (size: kBragRowNameSize, lines: 1);
  }
  TextPainter measure(double size) => TextPainter(
        text: TextSpan(
            text: name,
            style: shareCardText(size, FontWeight.w500, Colors.white,
                spacing: -0.2)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width);
  final one = measure(kBragRowNameSize);
  final fits = one.computeLineMetrics().length <= 1;
  one.dispose();
  return fits
      ? (size: kBragRowNameSize, lines: 1)
      : (size: kBragRowNameSmall, lines: 2);
}

class BragCard extends StatelessWidget {
  const BragCard({super.key, required this.data, this.mark, this.lineSeed = 0});

  final BragData data;

  /// Sal's decoded face (ShareCardSal); null: the tile alone.
  final SalClip? mark;

  /// Picks the edgy line (bragEdge): the preview's random seed.
  final int lineSeed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final line = bragEdge(l10n, data, lineSeed);
    final p = bragPalette(data);
    final pose = bragPose(data);
    switch (data) {
      case final BragPortfolio d:
        final r = d.allTime;
        final series = d.series;
        final hasChart = series != null && series.length >= 2;
        return ShareCardFrame(
          palette: p,
          keyPrefix: 'brag-card',
          caps: d.title,
          number: r?.text ?? '—',
          fact: l10n.portfolioAllTime,
          graphic: hasChart
              ? ShareCardSparkline(
                  key: const ValueKey('brag-card-chart'),
                  points: series,
                  color: r != null && (r.up || r.down) ? _signed(p, r) : p.ink,
                )
              : d.top.isEmpty
                  ? null
                  // As many of the top three as the space holds (a
                  // two-line edgy line leaves room for two).
                  : LayoutBuilder(
                      builder: (context, box) {
                        // Each row as tall as its name needs (a long
                        // market title on two lines, never cut while it
                        // can be read), as many as fit.
                        var n = 0;
                        var used = 0.0;
                        for (final row in d.top) {
                          final h = bragRowNameFit(
                                          _TopRow.nameOf(row),
                                          _TopRow.nameWidth(
                                              row, box.maxWidth))
                                      .lines >
                                  1
                              ? kBragRowHeightTwoLines
                              : kBragRowHeight;
                          if (n > 0 &&
                              box.maxHeight.isFinite &&
                              used + h > box.maxHeight) {
                            break;
                          }
                          used += h;
                          n++;
                        }
                        return Column(
                          key: const ValueKey('brag-card-rows'),
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            for (var i = 0; i < n; i++)
                              _TopRow(
                                  key: ValueKey('brag-card-top-$i'),
                                  row: d.top[i],
                                  palette: p),
                          ],
                        );
                      },
                    ),
          graphicFills: hasChart || d.top.isNotEmpty,
          line: line,
          code: d.referralCode,
          mark: mark,
          pose: pose,
        );
      case final BragPosition d:
        final r = d.result;
        final pct = r.percent;
        final series = d.series;
        final hasChart = series != null && series.length >= 2;
        final entry = d.entryText?.trim();
        final now = d.nowText?.trim();
        final fact = pct == null
            ? l10n.bragSinceYouBought
            : '${l10n.bragSinceYouBought} · ${bragPercent(pct)}';
        final factColor = r.up || r.down ? _signed(p, r) : null;
        // A prediction: the open-position screen's speedometer, the P&L
        // under its hub.
        final chance = d.investing ? null : d.chance;
        return ShareCardFrame(
          palette: p,
          keyPrefix: 'brag-card',
          caps: l10n.bragMyPosition,
          identity: ShareCardIdentity(
            palette: p,
            keyPrefix: 'brag-card',
            logo: ShareCardLogo(
              key: const ValueKey('brag-card-logo'),
              size: 36,
              title: d.title,
              investing: d.investing,
              palette: p,
              coin: d.coin,
              wireCoin: d.wireCoin,
              iconUrl: d.iconUrl,
              category: d.category,
              imageUrl: d.imageUrl,
            ),
            name: d.title,
            meta: d.side,
          ),
          number: chance == null ? r.text : null,
          fact: chance == null ? fact : null,
          factColor: factColor,
          graphic: chance != null
              ? ShareCardSpeedometer(
                  palette: p,
                  keyPrefix: 'brag-card',
                  fraction: chance,
                  entry: d.entryValue,
                  figure: r.text,
                  figureMax: 72,
                  caption: fact,
                  captionColor: factColor,
                )
              : hasChart
                  ? ShareCardSparkline(
                      key: const ValueKey('brag-card-chart'),
                      points: series,
                      color: r.up || r.down ? _signed(p, r) : p.ink,
                    )
                  : null,
          graphicFills: chance != null || hasChart,
          // What it cost and what it is now: "3,812.40 → 3,576.10".
          plain: entry != null && now != null ? '$entry → $now' : null,
          line: line,
          code: d.referralCode,
          mark: mark,
          pose: pose,
        );
    }
  }
}

/// One of the top positions as a row: its real logo (28), its name (a
/// prediction's named outcome, else the market, 17) and its result (the
/// percent, else the amount, 17 w600) at the right in the result's colour.
class _TopRow extends StatelessWidget {
  const _TopRow({super.key, required this.row, required this.palette});

  final BragTopPosition row;
  final ShareCardPalette palette;

  /// A named outcome ("Gen.G") says more than the long question; a Yes
  /// or No does not.
  static bool _named(BragTopPosition row) {
    final side = row.side;
    return side != null &&
        side.isNotEmpty &&
        !row.investing &&
        !const {'yes', 'no'}.contains(side.trim().toLowerCase());
  }

  /// The name the row writes.
  static String nameOf(BragTopPosition row) =>
      _named(row) ? row.side! : row.title;

  /// The result the row writes at the right.
  static String resultOf(BragTopPosition row) {
    final pct = row.result.percent;
    return pct != null ? bragPercent(pct) : row.result.text;
  }

  /// The name's width in a row [width] wide: less the logo, the gaps and
  /// the result.
  static double nameWidth(BragTopPosition row, double width) {
    final tp = TextPainter(
      text: TextSpan(
          text: resultOf(row),
          style: shareCardText(kBragRowNameSize, FontWeight.w600, Colors.white,
              spacing: -0.2, tabular: true)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final w = width - kBragRowLogo - 24 - tp.width;
    tp.dispose();
    return w;
  }

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final r = row.result;
    final name = nameOf(row);
    return LayoutBuilder(builder: (context, box) {
      final fit = bragRowNameFit(name, nameWidth(row, box.maxWidth));
      return Row(
        children: [
          ShareCardLogo(
            size: kBragRowLogo,
            title: name,
            investing: row.investing,
            palette: p,
            coin: row.coin,
            wireCoin: row.wireCoin,
            iconUrl: row.iconUrl,
            category: row.category,
            imageUrl: row.imageUrl,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              maxLines: fit.lines,
              overflow: TextOverflow.ellipsis,
              style: shareCardText(fit.size, FontWeight.w500, p.ink,
                  spacing: -0.2, height: fit.lines > 1 ? 1.15 : 1.2),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            resultOf(row),
            maxLines: 1,
            style: shareCardText(kBragRowNameSize, FontWeight.w600,
                _signed(p, r),
                spacing: -0.2, tabular: true),
          ),
        ],
      );
    });
  }
}
