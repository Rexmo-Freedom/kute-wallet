// lib/screens/share/brag/pnl_share_card.dart
//
// THE P&L CARD (founder, 2 November 2026: "On share and brag portfolio we
// should say share portfolio on the bottom. PnL should say [something
// else]: share and brag should be different"). The P&L Charts section's
// bar is "Share P&L" and shares this card: what the P&L chart shows for
// the range picked ([BragPnl], brag_data.dart), in the share cards' one
// layout (cards/share_card_frame.dart) and the brag card's colours, mood
// and edgy line (brag_card.dart: bragPalette, bragPose; brag_lines.dart),
// composed from the frame's pieces, never a layout of its own:
//
//   * the caps: "MY P&L · 1M" ("MY P&L · INVESTING · 1M" with one venue
//     picked in "By venue");
//   * the P&L over the range huge, signed, then the range as the chart
//     names it ("Past month") in the result's colour; no percent (no
//     provider gives a P&L a base, see BragPnl);
//   * the line over the range filling the space (the chart's own
//     points, thinned), in the result's colour.
//
// Like the brag card it never reads a provider or the screen's scale: the
// same pixels at every size, so the preview is exactly the image.

import 'package:flutter/material.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/portfolio_performance.dart'
    show PortfolioPerformanceVenue;
import 'package:kute/screens/share/brag/brag_card.dart'
    show bragPalette, bragPose;
import 'package:kute/screens/share/brag/brag_data.dart';
import 'package:kute/screens/share/brag/brag_lines.dart';
import 'package:kute/screens/share/cards/share_card_frame.dart';
import 'package:kute/screens/shared/charts/kute_trend_window.dart'
    show kuteTrendPeriodLabel;
import 'package:kute/screens/shared/sal_sprite.dart' show SalClip;

class PnlShareCard extends StatelessWidget {
  const PnlShareCard(
      {super.key, required this.data, this.mark, this.lineSeed = 0});

  final BragPnl data;

  /// Sal's decoded face (ShareCardSal); null: the tile alone.
  final SalClip? mark;

  /// Picks the edgy line (bragEdge): the preview's random seed.
  final int lineSeed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = bragPalette(data);
    final r = data.result;
    final series = data.series;
    final hasChart = series != null && series.length >= 2;
    final moved = r != null && (r.up || r.down);
    final tone = !moved
        ? null
        : r.up
            ? p.up
            : p.down;
    final venue = switch (data.venue) {
      null => null,
      PortfolioPerformanceVenue.trading => l10n.trading,
      PortfolioPerformanceVenue.predictions => l10n.predictions,
    };
    return ShareCardFrame(
      palette: p,
      keyPrefix: 'pnl-card',
      caps: [l10n.bragMyPnl, if (venue != null) venue, data.range.label]
          .join(' · '),
      number: r?.text ?? '—',
      fact: kuteTrendPeriodLabel(l10n, data.range),
      factColor: tone,
      graphic: hasChart
          ? ShareCardSparkline(
              key: const ValueKey('pnl-card-chart'),
              points: series,
              color: tone ?? p.ink,
            )
          : null,
      graphicFills: hasChart,
      line: bragEdge(l10n, data, lineSeed),
      code: data.referralCode,
      mark: mark,
      pose: bragPose(data),
    );
  }
}
