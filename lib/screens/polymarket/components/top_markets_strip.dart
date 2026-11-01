// The Top markets strip over the Predictions feed (founder, 1 November
// 2026: "big cards of the top ones on top", the way Polymarket's and
// Kalshi's apps feature their markets).
//
// A side-scrolling row of up to five large cards (240 by at least 170,
// 12 apart, 16 in from the edges, the list card's ground with the larger
// radius) for the plain Yes/No markets of the current category with the
// most volume in the last 24 hours ([polyTopMarkets]). A card is the
// market's image (40, rounded 10; the category glyph when it has none)
// beside the question (two lines, semibold), the Yes chance large with
// the word "chance" small beside it, the Yes / No price pills the list
// card uses ([PolySidePill]), and one caption line, when the market
// closes ("Closes Dec 2026"). The card opens the market as a list card
// does; a pill opens the slip on that side. The strip never shows while
// searching (search is its own screen) or on the Live lists.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/screens/polymarket/components/live_token_scope.dart';
import 'package:kute/screens/polymarket/components/market_card.dart';
import 'package:kute/screens/shared/kute_motion.dart';
import 'package:kute/services/polymarket/market_buy_quote.dart'
    show polymarketCentsLabel;
import 'package:kute/services/polymarket/market_card_shape.dart';
import 'package:kute/theme/app_theme.dart';

/// How many markets the strip features at most.
const int kPolyTopMarketsMax = 5;

/// Fewer than this and there is no strip: one big card over the list
/// would only repeat the list's first row.
const int kPolyTopMarketsMin = 2;

/// The card's width and least height.
const double kPolyTopMarketCardWidth = 240;
const double kPolyTopMarketCardHeight = 170;

/// The markets the strip features, most traded first: the plain Yes/No
/// markets of [events] (the list's own test, [polyCardIsYesNo]) that are
/// still open, by their last 24 hours' volume (`volume24hr`; the
/// lifetime volume when the feed has none), up to [max]. Equal volumes
/// keep the feed's order. Empty when fewer than [min] qualify.
/// The rows the feed under the strip keeps at least; with fewer, the
/// strip is not shown and every market is a row.
const int kPolyTopMarketsListKeeps = 3;

List<PolymarketEvent> polyTopMarkets(
  Iterable<PolymarketEvent> events, {
  int max = kPolyTopMarketsMax,
  int min = kPolyTopMarketsMin,
}) {
  final open = [
    for (final e in events)
      if (!e.ended && !e.closed && polyCardIsYesNo(e.outcomes)) e,
  ];
  if (open.length < min) return const [];
  double volumeOf(PolymarketEvent e) =>
      e.volume24hr > 0 ? e.volume24hr : e.volume;
  final indexed = [for (var i = 0; i < open.length; i++) i];
  indexed.sort((x, y) {
    final byVolume = volumeOf(open[y]).compareTo(volumeOf(open[x]));
    return byVolume != 0 ? byVolume : x.compareTo(y);
  });
  return [for (final i in indexed.take(max)) open[i]];
}

/// The strip: [markets] as [PolyTopMarketCard]s in one side-scrolling
/// row, every card as tall as the tallest. [onOpen] opens a market (its
/// card was tapped), [onOpenDown] is the finger coming down on a card
/// (the market page's history can start reading), [onPickSide] a Yes /
/// No pill ('yes' / 'no').
class PolyTopMarketsStrip extends StatelessWidget {
  final List<PolymarketEvent> markets;
  final ValueChanged<PolymarketEvent> onOpen;
  final ValueChanged<PolymarketEvent>? onOpenDown;
  final void Function(PolymarketEvent market, String side) onPickSide;

  const PolyTopMarketsStrip({
    super.key,
    required this.markets,
    required this.onOpen,
    this.onOpenDown,
    required this.onPickSide,
  });

  @override
  Widget build(BuildContext context) {
    if (markets.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      key: const ValueKey('poly-top-markets-strip'),
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      clipBehavior: Clip.none,
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < markets.length; i++) ...[
              if (i > 0) SizedBox(width: 12.w),
              PolyTopMarketCard(
                market: markets[i],
                onTap: () => onOpen(markets[i]),
                onTapDown:
                    onOpenDown == null ? null : () => onOpenDown!(markets[i]),
                onPickSide: (side) => onPickSide(markets[i], side),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One card of the strip. Its own ConsumerWidget watching only its two
/// tokens' live prices, so a price tick repaints this card alone, and
/// registering them over the CLOB feed while it is on screen
/// ([LiveTokenScope]).
class PolyTopMarketCard extends ConsumerWidget {
  final PolymarketEvent market;
  final VoidCallback onTap;
  final VoidCallback? onTapDown;
  final ValueChanged<String> onPickSide;

  const PolyTopMarketCard({
    super.key,
    required this.market,
    required this.onTap,
    this.onTapDown,
    required this.onPickSide,
  });

  PolymarketOutcome? _side(String name) => market.outcomes
      .where((o) => o.name.trim().toLowerCase() == name)
      .firstOrNull;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l10n = context.l10n;
    final yes = _side('yes');
    final no = _side('no');
    final tokens = [
      for (final o in [yes, no])
        if (o?.tokenId != null && o!.tokenId!.isNotEmpty) o.tokenId!,
    ];
    double priceOf(PolymarketOutcome? o, double fallback) {
      if (o == null) return fallback;
      final id = o.tokenId;
      final live = id == null || id.isEmpty
          ? null
          : ref.watch(livePriceProvider.select((s) => s.prices[id]));
      return (live ?? o.price).clamp(0.0, 1.0);
    }

    final yesPrice = priceOf(yes, market.yesPrice);
    // The No side's own price when the feed has it, else what Yes leaves.
    final noPrice = priceOf(no, 1 - yesPrice);
    final end = market.endDate;
    final caption =
        end == null ? null : l10n.marketCloses(DateFormat('MMM yyyy').format(end));
    final radius = BorderRadius.circular(AppRadius.xl);

    return LiveTokenScope(
      tokens: tokens,
      child: Container(
        width: kPolyTopMarketCardWidth.w,
        constraints: BoxConstraints(minHeight: kPolyTopMarketCardHeight.h),
        decoration: AppDecorations.card(context).copyWith(borderRadius: radius),
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            onTap: onTap,
            onTapDown: onTapDown == null ? null : (_) => onTapDown!(),
            borderRadius: radius,
            child: Padding(
              padding: EdgeInsets.all(14.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PolyCardThumbnail(
                        title: market.title,
                        imageUrl: market.imageUrl,
                        category: market.category,
                        size: kPolyCardImage.w,
                        radius: 10.r,
                      ),
                      SizedBox(width: kPolyCardImageGap.w),
                      Expanded(
                        child: Text(
                          market.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 15.sp,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12.h),
                  // The chance, large, with the word small beside it on
                  // its baseline.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      RollingFigure(
                        identity: market.slug,
                        text: polyCardChance(yesPrice),
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 28.sp,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.6,
                          height: 1.0,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      SizedBox(width: 6.w),
                      Flexible(
                        child: Text(
                          l10n.predictionsChance,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  SizedBox(height: 12.h),
                  Row(
                    children: [
                      PolySidePill(
                        text: '${l10n.yes} ${polymarketCentsLabel(yesPrice)}',
                        color: AppColors.marketUp,
                        onTap: () => onPickSide('yes'),
                      ),
                      SizedBox(width: 6.w),
                      PolySidePill(
                        text: '${l10n.betNo} ${polymarketCentsLabel(noPrice)}',
                        color: AppColors.marketDown,
                        onTap: () => onPickSide('no'),
                      ),
                    ],
                  ),
                  if (caption != null) ...[
                    SizedBox(height: 8.h),
                    Text(
                      caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.textTertiary,
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.1,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
