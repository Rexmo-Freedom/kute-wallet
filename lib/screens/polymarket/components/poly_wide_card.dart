// The wide web layout's Predictions card (founder, 26 November 2026, on
// the laptop's Predictions page: "on desktop this looks too much"): a
// calm, uniform grid of cards that each say less than the phone's card.
// The title on two lines at most, the two leading outcomes on one line
// each (the name on the left, the chance on the right), and "+N more"
// when the market has more. No bars, no sparkline, no move arrows; no
// picture (the web shows the name alone, see kPolyThumbsShown). The
// phone's card (market_card.dart) is untouched.

import 'package:flutter/material.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/screens/polymarket/components/market_card.dart'
    show polyCardTitleStyle;
import 'package:kute/services/polymarket/market_card_shape.dart';
import 'package:kute/theme/app_theme.dart';

/// The narrowest card of the wide grid (logical px).
const double kPolyWideCardMin = 280;

/// The gap between two cards of the wide grid, both ways.
const double kPolyWideCardGap = 16;

/// Every card's height in the wide grid: rows line up.
const double kPolyWideCardHeight = 168;

/// How many columns of [kPolyWideCardMin] cards fit a content [width].
int polyWideColumns(double width) {
  final n = ((width + kPolyWideCardGap) / (kPolyWideCardMin + kPolyWideCardGap))
      .floor();
  return n < 1 ? 1 : n;
}

class PolyWideCard extends StatelessWidget {
  const PolyWideCard({
    super.key,
    required this.title,
    required this.outcomes,
    this.livePrices = const {},
    required this.onTap,
    this.onTapDown,
  });

  final String title;
  final List<PolymarketOutcome> outcomes;
  final Map<String, double> livePrices;
  final VoidCallback onTap;
  final VoidCallback? onTapDown;

  double _price(PolymarketOutcome o) {
    final t = o.tokenId;
    return (t == null ? null : livePrices[t]) ?? o.price;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // A market of two sides (Yes / No, two teams) keeps its own order;
    // more outcomes show their two leaders.
    final top = outcomes.length == 2
        ? outcomes
        : polyCardTopOutcomes(outcomes, live: livePrices, count: 2);
    final more =
        polyRealOutcomes(outcomes, live: livePrices).length - top.length;
    final twoSided = outcomes.length == 2 && top.length == 2;
    final nameStyle = TextStyle(
        color: c.textSecondary, fontSize: 14, fontWeight: FontWeight.w500);
    final figureStyle = TextStyle(
      color: c.textPrimary,
      fontSize: 14,
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    Widget line(PolymarketOutcome o, int i) {
      final chance = twoSided && i == 1
          ? polyCardOtherSideChance(_price(top.first))
          : polyCardChance(_price(o));
      return Row(
        key: ValueKey('poly-wide-outcome-$i'),
        children: [
          Expanded(
            child: Text(o.name,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: nameStyle),
          ),
          const SizedBox(width: 12),
          Text(chance, style: figureStyle),
        ],
      );
    }

    return Container(
      key: const ValueKey('poly-wide-card'),
      decoration: AppDecorations.card(context),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onTapDown: onTapDown == null ? null : (_) => onTapDown!(),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: polyCardTitleStyle(c)),
                const Spacer(),
                for (var i = 0; i < top.length; i++) ...[
                  if (i > 0) const SizedBox(height: 6),
                  line(top[i], i),
                ],
                if (more > 0) ...[
                  const SizedBox(height: 8),
                  Text(context.l10n.polyCardMoreOutcomes(more),
                      style: TextStyle(
                          color: c.textTertiary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
