// The Top markets strip over the Predictions feed (founder, 1 November
// 2026: "big cards of the top ones on top", the way Polymarket's and
// Kalshi's apps feature their markets), on the default view (Trending,
// no subcategory) only: a category or subcategory the person picks is the
// full plain list, nothing excluded.
//
// A side-scrolling row of up to five large cards, the Investing strip's
// treatment (hl_moving_now_strip.dart; founder, 1 November 2026: bigger
// and calmer): two to a screen with the third peeking, about 150 tall, 10
// apart, 16 in from the edges, the list card's ground with the larger
// radius, for the plain Yes/No markets of the list with the most volume
// in the last 24 hours ([polyTopMarkets]). A card is the market's image
// (36, rounded 10; the category glyph when it has none) at the top-left,
// the question under it (two lines, semibold), and at the bottom who
// leads at what chance, large ("Yes · 62%", [polyRowLeader]). No pills,
// no closing date. The card opens the market as a list row does. The
// strip never shows while searching (search is its own screen) or on the
// Live lists.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/screens/polymarket/components/live_token_scope.dart';
import 'package:kute/screens/polymarket/components/market_card.dart';
import 'package:kute/screens/shared/kute_motion.dart';
import 'package:kute/services/polymarket/market_card_shape.dart';
import 'package:kute/theme/app_theme.dart';

/// How many markets the strip features at most.
const int kPolyTopMarketsMax = 5;

/// Fewer than this and there is no strip: one big card over the list
/// would only repeat the list's first row.
const int kPolyTopMarketsMin = 2;

/// The gap between two cards, how much less than half the row a card is
/// (so the third peeks), and a card's least height, in design units.
const double kPolyTopMarketCardGap = 10;
const double kPolyTopMarketCardPeek = 14;
const double kPolyTopMarketCardHeight = 150;

/// The card's image.
const double kPolyTopMarketCardImage = 36;

/// A strip card's width: half the screen less its 16 margins and the gap,
/// less [kPolyTopMarketCardPeek] so the third card peeks.
double polyTopMarketCardWidth() =>
    (1.sw - 32.w - kPolyTopMarketCardGap.w) / 2 - kPolyTopMarketCardPeek.w;

/// The markets the strip features, most traded first: the plain Yes/No
/// markets of [events] (the list's own test, [polyCardIsYesNo]) that are
/// still open, by their last 24 hours' volume (`volume24hr`; the
/// lifetime volume when the feed has none), up to [max]. Equal volumes
/// keep the feed's order. Empty when fewer than [min] qualify.
/// The rows the feed under the strip keeps at least; with fewer, the
/// strip is not shown and every market is a row.
const int kPolyTopMarketsListKeeps = 3;

/// Markets the default view (Trending at its default list) lists under
/// its strip (founder, 1 November 2026: a curated slice; the floating bar
/// searches everything). Any other category the person picks is listed
/// in full, page after page.
const int kPolyTrendingListRows = 6;

/// The markets listed under the strip: the first [kPolyTrendingListRows]
/// of [listed] on the default view, all of them on any other.
List<T> polyBrowseRowsShown<T>(bool defaultView, List<T> listed) =>
    defaultView && listed.length > kPolyTrendingListRows
        ? listed.sublist(0, kPolyTrendingListRows)
        : listed;

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
/// (the market page's history can start reading).
class PolyTopMarketsStrip extends StatelessWidget {
  final List<PolymarketEvent> markets;
  final ValueChanged<PolymarketEvent> onOpen;
  final ValueChanged<PolymarketEvent>? onOpenDown;

  const PolyTopMarketsStrip({
    super.key,
    required this.markets,
    required this.onOpen,
    this.onOpenDown,
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
              if (i > 0) SizedBox(width: kPolyTopMarketCardGap.w),
              PolyTopMarketCard(
                market: markets[i],
                onTap: () => onOpen(markets[i]),
                onTapDown:
                    onOpenDown == null ? null : () => onOpenDown!(markets[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One card of the strip. Its own ConsumerWidget watching only its
/// tokens' live prices, so a price tick repaints this card alone, and
/// registering them over the CLOB feed while it is on screen
/// ([LiveTokenScope]).
class PolyTopMarketCard extends ConsumerWidget {
  final PolymarketEvent market;
  final VoidCallback onTap;
  final VoidCallback? onTapDown;

  const PolyTopMarketCard({
    super.key,
    required this.market,
    required this.onTap,
    this.onTapDown,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final tokens = [
      for (final o in market.outcomes)
        if (o.tokenId != null && o.tokenId!.isNotEmpty) o.tokenId!,
    ];
    final live = <String, double>{
      for (final id in tokens)
        if (ref.watch(livePriceProvider.select((s) => s.prices[id]))
            case final p?)
          id: p,
    };
    final lead = polyRowLeader(context.l10n, market.outcomes, live: live);
    final radius = BorderRadius.circular(AppRadius.xl);

    return LiveTokenScope(
      tokens: tokens,
      child: Container(
        width: polyTopMarketCardWidth(),
        constraints: BoxConstraints(minHeight: kPolyTopMarketCardHeight.w),
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
                  PolyCardThumbnail(
                    title: market.title,
                    imageUrl: market.imageUrl,
                    category: market.category,
                    size: kPolyTopMarketCardImage.w,
                    radius: 10.r,
                  ),
                  SizedBox(height: 8.w),
                  Text(
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
                  const Spacer(),
                  SizedBox(height: 8.w),
                  if (lead != null)
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: RollingFigure(
                        identity: market.slug,
                        text: '${lead.name} · ${polyCardChance(lead.price)}',
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 22.sp,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.6,
                          height: 1.2,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
