// lib/screens/share/brag/brag_card.dart
//
// THE BRAG CARD, restrained premium (founder, 1 November 2026: the
// Robinhood / Revolut / Apple Card share cards, then "bigger numbers and
// such" and an edgy line on the card). A 4:5 share image at
// [kBragCardSize], captured at [kBragCardPixelRatio] (1080 × 1350), in the
// share cards' one layout (cards/share_card_frame.dart) on near-black:
//
//   * PORTFOLIO: "MY PORTFOLIO", the all-time P&L huge, "All time", then
//     the all-time P&L line filling the space when there is one
//     (BragPortfolio.series, the stock card's chart), else the top three
//     open positions as rows spread over it (the REAL logo 28 through the
//     app's widgets, HlCoinIcon or PolyCrestImage; the name 17; the
//     percent 17 w600 at the right in its colour). No ring.
//   * POSITION: the stock card with the P&L as the hero: "MY POSITION",
//     the market's logo, title and the side held ("Long", "Gen.G"), the
//     P&L huge, "Since you bought · +42.1%" in the result's colour, the
//     held side's line since the buy filling the space when the page has
//     read it, and the entry and the price now as the plain fact line
//     ("3,812.40 → 3,576.10").
//   * The EDGY LINE (brag_lines.dart) over the footer: Sal's small mark,
//     the wordmark and the sharer's code.
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
import 'package:kute/screens/shared/sal_sprite.dart' show SalClip;

/// The card's logical size: 4:5.
const Size kBragCardSize = kShareCardSize;

/// The capture's pixel ratio: [kBragCardSize] × 3 = 1080 × 1350.
const double kBragCardPixelRatio = kShareCardPixelRatio;

const ShareCardPalette _p = ShareCardPalette.dark;

/// A result's colour: up, down, or muted when flat.
Color _signed(BragResult r) => r.up
    ? _p.up
    : r.down
        ? _p.down
        : _p.muted;

/// A row's logo in the portfolio card.
const double kBragRowLogo = 28;

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
    switch (data) {
      case final BragPortfolio d:
        final r = d.allTime;
        final series = d.series;
        final hasChart = series != null && series.length >= 2;
        return ShareCardFrame(
          palette: _p,
          keyPrefix: 'brag-card',
          caps: d.title,
          number: r?.text ?? '—',
          fact: l10n.portfolioAllTime,
          graphic: hasChart
              ? ShareCardSparkline(
                  key: const ValueKey('brag-card-chart'),
                  points: series,
                  color: r != null && (r.up || r.down) ? _signed(r) : _p.ink,
                )
              : d.top.isEmpty
                  ? null
                  : Column(
                      key: const ValueKey('brag-card-rows'),
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        for (var i = 0; i < d.top.length; i++)
                          _TopRow(
                              key: ValueKey('brag-card-top-$i'), row: d.top[i]),
                      ],
                    ),
          graphicFills: hasChart || d.top.isNotEmpty,
          line: line,
          code: d.referralCode,
          mark: mark,
        );
      case final BragPosition d:
        final r = d.result;
        final pct = r.percent;
        final series = d.series;
        final hasChart = series != null && series.length >= 2;
        final entry = d.entryText?.trim();
        final now = d.nowText?.trim();
        return ShareCardFrame(
          palette: _p,
          keyPrefix: 'brag-card',
          caps: l10n.bragMyPosition,
          identity: ShareCardIdentity(
            palette: _p,
            keyPrefix: 'brag-card',
            logo: ShareCardLogo(
              key: const ValueKey('brag-card-logo'),
              size: 36,
              title: d.title,
              investing: d.investing,
              palette: _p,
              coin: d.coin,
              wireCoin: d.wireCoin,
              iconUrl: d.iconUrl,
              category: d.category,
              imageUrl: d.imageUrl,
            ),
            name: d.title,
            meta: d.side,
          ),
          number: r.text,
          fact: pct == null
              ? l10n.bragSinceYouBought
              : '${l10n.bragSinceYouBought} · ${bragPercent(pct)}',
          factColor: r.up || r.down ? _signed(r) : null,
          graphic: hasChart
              ? ShareCardSparkline(
                  key: const ValueKey('brag-card-chart'),
                  points: series,
                  color: r.up || r.down ? _signed(r) : _p.ink,
                )
              : null,
          graphicFills: hasChart,
          // What it cost and what it is now: "3,812.40 → 3,576.10".
          plain: entry != null && now != null ? '$entry → $now' : null,
          line: line,
          code: d.referralCode,
          mark: mark,
        );
    }
  }
}

/// One of the top positions as a row: its real logo (28), its name (a
/// prediction's named outcome, else the market, 17) and its result (the
/// percent, else the amount, 17 w600) at the right in the result's colour.
class _TopRow extends StatelessWidget {
  const _TopRow({super.key, required this.row});

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
    return Row(
      children: [
        ShareCardLogo(
          size: kBragRowLogo,
          title: named ? side : row.title,
          investing: row.investing,
          palette: _p,
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: shareCardText(17, FontWeight.w500, _p.ink, spacing: -0.2),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          pct != null ? bragPercent(pct) : r.text,
          maxLines: 1,
          style: shareCardText(17, FontWeight.w600, _signed(r),
              spacing: -0.2, tabular: true),
        ),
      ],
    );
  }
}
