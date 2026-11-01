// lib/screens/share/brag/brag_card.dart
//
// THE BRAG CARD, restrained premium (founder, 1 November 2026: the
// Robinhood / Revolut / Apple Card share cards). A 4:5 share image at
// [kBragCardSize], captured at [kBragCardPixelRatio] (1080 × 1350), in the
// share cards' one layout (cards/share_card_frame.dart) on near-black:
//
//   * PORTFOLIO: "MY PORTFOLIO", the all-time P&L big, "All time" muted,
//     the top three open positions as three plain rows (the logo 18, the
//     name, the percent at the right in its colour). No ring.
//   * POSITION: "MY POSITION", the market's logo, title and the side held
//     ("Long", "Gen.G"), the P&L big, "Since you bought · +42.1%" in the
//     result's colour, the held side's line since the buy (1.6 px) when
//     the page has read it.
//   * FOOTER: Sal's small mark, the wordmark and the sharer's code.
//
// Sal's one-liner is not on the image: it is the share message's line
// (brag_lines.dart, brag_preview_sheet.dart).
//
// AMOUNTS (founder, 1 November 2026: "don't even give the option"): the
// card always shows the real amounts, with the percents where they exist.
//
// The card never reads a provider or the screen's scale: the same pixels
// at every size, so the preview is exactly the image.

import 'package:flutter/material.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/share/brag/brag_data.dart';
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

class BragCard extends StatelessWidget {
  const BragCard({super.key, required this.data, this.mark});

  final BragData data;

  /// Sal's decoded face (ShareCardSal); null: the tile alone.
  final SalClip? mark;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    switch (data) {
      case final BragPortfolio d:
        final r = d.allTime;
        return ShareCardFrame(
          palette: _p,
          keyPrefix: 'brag-card',
          caps: d.title,
          number: r?.text ?? '—',
          fact: l10n.portfolioAllTime,
          graphic: d.top.isEmpty
              ? null
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < d.top.length; i++) ...[
                      if (i > 0) const SizedBox(height: 14),
                      _TopRow(key: ValueKey('brag-card-top-$i'), row: d.top[i]),
                    ],
                  ],
                ),
          graphicAtBottom: true,
          code: d.referralCode,
          mark: mark,
        );
      case final BragPosition d:
        final r = d.result;
        final pct = r.percent;
        final series = d.series;
        return ShareCardFrame(
          palette: _p,
          keyPrefix: 'brag-card',
          caps: l10n.bragMyPosition,
          identity: ShareCardIdentity(
            palette: _p,
            keyPrefix: 'brag-card',
            logo: ShareCardLogo(
              key: const ValueKey('brag-card-logo'),
              size: 26,
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
          factColor: _signed(r),
          graphic: series != null && series.length >= 2
              ? ShareCardSparkline(
                  key: const ValueKey('brag-card-chart'),
                  points: series,
                  color: r.up || r.down ? _signed(r) : _p.ink,
                )
              : null,
          graphicFills: true,
          code: d.referralCode,
          mark: mark,
        );
    }
  }
}

/// One of the top positions as a plain row: its logo (18), its name (a
/// prediction's named outcome, else the market) and its result (the
/// percent, else the amount) at the right in the result's colour.
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
          size: 18,
          title: row.title,
          investing: row.investing,
          palette: _p,
          coin: row.coin,
          wireCoin: row.wireCoin,
          iconUrl: row.iconUrl,
          category: row.category,
          imageUrl: row.imageUrl,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: shareCardText(14, FontWeight.w500, _p.ink, spacing: -0.1),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          pct != null ? bragPercent(pct) : r.text,
          maxLines: 1,
          style: shareCardText(14, FontWeight.w600, _signed(r),
              spacing: -0.1, tabular: true),
        ),
      ],
    );
  }
}
