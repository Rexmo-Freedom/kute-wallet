// lib/screens/hyperliquid/components/hl_moving_now_strip.dart
//
// The four big squares above the Investing browse list (founder,
// November 2026: "big cards of the top ones on top", the way Revolut /
// Coinbase / Robinhood show the day's names; 2 November 2026: "do it like
// in the bitcoin screen, show 4 like that"). Two by two, the Bitcoin
// home's "Latest" squares (all_activity.dart [ActivitySquareGrid]), with
// no title over them. Still called the strip in the code.
//
// What it shows:
//   * Trending ([hlTrendingStrip]): the hyped names, stocks and shares
//     and commodities (founder, 1 November 2026: "stocks and shares are
//     the best to put there, and commodities. Do not repeat ones."),
//     ranked by [hlHypeScore], at least [kHlHypeCommoditiesMin]
//     commodities among the [kHlHypeCardMax], one card per underlying
//     ([hlUnderlyingKey]). With fewer than [kHlMoverCardMin] such
//     markets loaded (the builder dexes not read yet), Trending's movers
//     ([hlMovingNow]: the largest absolute 24h changes, ties by volume,
//     one card per underlying).
//   * Every other category or subcategory: no strip.
// Thin markets ([HlMarket.isLowLiquidity]) and markets with no 24h change
// to show are never on it. A market on the strip, or one on the same
// underlying, is not repeated in the list under it ([hlListUnderStrip]).
//
// Each square (HlMovingNowCard) is drawn as the home's Latest square:
// half the row less the 10 gap wide, [kActivitySquareHeight] tall at
// least, the grouped card's ground ([PremiumGroupContainer]), 14 padding.
// The logo (40, the Latest icon's size) at the top-left with the 24h
// change on its right as the row writes it ("▲ 3.9%", coloured, 13), and
// at the bottom the market's name quiet (13, secondary) over the live
// price (22 sp, bold, tabular), as a Latest square's action over its
// amount. No sparkline and no ticker line. Plain coloured text, no tinted
// chip (house rule: solid fills or neutral grey only). The whole square
// taps through to HlMarketDetailSheet, entry_source 'moving_now', on the
// app's press spring (KutePressable).
//
// Only the default view (Trending, no subcategory) has a strip (founder,
// 1 November 2026): a category or subcategory the person picks is the
// full plain list, nothing excluded from it.
//
// The squares are only shown when [kHlMoverCardMin] (four) markets
// qualify: a grid with a hole reads as a mistake.
//
// THE WATCHLIST WEARS THE SAME SQUARES (founder, 13 November 2026: "show
// [it] with the design of the 4 main squares after it is created"): on
// Investing's Watchlist the first markets of the list, in its order
// ([hlWatchlistSquareCount]: four from four, two for two or three, none
// for one, never a lone half square), as these squares, entry_source
// 'watchlist', each logo's usual fallback (the glyph or letter tile) where
// a market has no logo of its own ([HlMovingNowStrip.blankUntilLogo]
// false: a market the person picked is shown whatever its logo); the rest
// of the list as the rows under them (hyperliquid_screen.dart).
//
// Only markets with a logo of their own are on it (founder, 11 November
// 2026: "don't show Moving now without svg, means that they have low
// liquidity"): [hlStripWithLogos] keeps the ranking and its rules and
// leaves out a market whose logo is a known miss (CoinCap's guess at a
// ticker, a glyph or a letter tile is no logo); while logos that could
// still fill the squares are unknown, the squares' skeleton stands
// ([HlMovingNowStripSkeleton]), never letter tiles.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart'
    show HlBrowseSub, HlBrowseTab, hlMarketMatchesTab;
import 'package:kute/screens/home/components/action_pill.dart'
    show greenColor, redColor;
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/hyperliquid/components/hl_market_card.dart'
    show hlArrowPct;
import 'package:kute/screens/hyperliquid/market_detail_sheet.dart';
import 'package:kute/screens/shared/all_activity.dart'
    show ActivitySquareGrid;
import 'package:kute/screens/shared/animations/premium_group_container.dart';
import 'package:kute/screens/shared/kute_motion.dart' show KutePressable;
import 'package:kute/screens/shared/kute_skeleton.dart'
    show KuteSkeleton, SkeletonBar, SkeletonCircle;
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/screens/shared/transactions_builder.dart'
    show kActivitySquareHeight;
import 'package:kute/theme/app_theme.dart';

/// How many squares the grid shows: two by two.
const int kHlMoverCardMax = 4;

/// Under this many movers the squares are not shown at all (no grid with
/// a hole).
const int kHlMoverCardMin = 4;

/// The square's logo: the home's Latest icon size.
const double kHlMoverCardIcon = 40;

/// The square's inner padding, in design units (the Latest square's).
const double _kPad = 14;

/// The [HlMarketDetailSheet] entry source a strip card reports.
const String kHlMovingNowSource = 'moving_now';

/// The rows the list under the strip keeps at least; with fewer, the
/// strip is not shown and every market is a row.
const int kHlMoverListKeeps = 3;

/// The 24h change a market is ranked on: the snapshot's own (the row's,
/// before any tick), so the strip does not reorder itself on every live
/// frame. Null when there is none to show.
double? _snapshotChange(HlMarket m) =>
    m.dayChangeAtOrNull(m.midPx > 0 ? m.midPx : m.markPx);

/// [ranked] (best first) with one market per underlying
/// ([hlUnderlyingKey]): of the markets on one underlying, its primary
/// listing stays ([hlPrimaryListings], the one search and the lists
/// show), at its own place in [ranked].
List<HlMarket> _onePerUnderlying(List<HlMarket> ranked) =>
    hlPrimaryListings(ranked);

/// The markets the strip shows for [markets] (a category's list): the
/// [max] with the largest absolute 24h change, ties broken by 24h
/// volume, then by their place in the list, one per underlying. A market
/// with no change to show (no previous-day price) or thinly traded
/// ([HlMarket.isLowLiquidity]) is left out. Empty, so no strip, under
/// [min] candidates.
///
/// [keep], when given, is asked of each market after the ranking (one per
/// underlying): one it refuses is left out and the next takes its place
/// ([hlStripWithLogos]).
List<HlMarket> hlMovingNow(
  List<HlMarket> markets, {
  int min = kHlMoverCardMin,
  int max = kHlMoverCardMax,
  bool Function(HlMarket market)? keep,
}) {
  final ranked = <({HlMarket m, double change, int index})>[];
  for (var i = 0; i < markets.length; i++) {
    final m = markets[i];
    if (m.isLowLiquidity) continue;
    final change = _snapshotChange(m);
    if (change == null) continue;
    ranked.add((m: m, change: change.abs(), index: i));
  }
  ranked.sort((a, b) {
    final c = b.change.compareTo(a.change);
    if (c != 0) return c;
    final v = b.m.dayNtlVlm.compareTo(a.m.dayNtlVlm);
    return v != 0 ? v : a.index.compareTo(b.index);
  });
  final unique = _onePerUnderlying([for (final r in ranked) r.m])
      .where(keep ?? (_) => true)
      .toList();
  if (unique.length < min) return const [];
  return unique.take(max).toList(growable: false);
}

/// How many squares the Trending grid shows at most.
const int kHlHypeCardMax = kHlMoverCardMax;

/// The commodities the Trending strip carries at least, when that many
/// qualify.
const int kHlHypeCommoditiesMin = 2;

/// The venue classes of the "Stocks and shares" group the Trending strip
/// draws on: equities, indices and pre-IPO companies.
const Set<String> kHlHypeStockClasses = {'stocks', 'indices', 'preipo'};

/// How hyped [m] is: its 24h notional volume, raised by its 24h move,
/// `volume × (1 + |change %| / 10)`, so a 10 % move counts as double the
/// volume and a liquid name with a real move leads. Null when it has no
/// 24h change to show.
double? hlHypeScore(HlMarket m) {
  final change = _snapshotChange(m);
  if (change == null) return null;
  return m.dayNtlVlm * (1 + (change * 100).abs() / 10);
}

/// True when [m] may be a card on the Trending strip: a stocks-and-shares
/// or commodities market of the Tradfi category, not thinly traded, with
/// a 24h change to show.
bool hlHypeCandidate(HlMarket m) =>
    hlMarketMatchesTab(m, HlBrowseTab.tradfi) &&
    (kHlHypeStockClasses.contains(m.category) ||
        m.category == 'commodities') &&
    !m.isLowLiquidity &&
    _snapshotChange(m) != null;

/// The Trending strip: from [universe] (every market loaded), the [max]
/// most hyped ([hlHypeScore]) stocks-and-shares and commodities markets,
/// one per underlying (the most traded of them), with at least
/// [kHlHypeCommoditiesMin] commodities when that many qualify: the
/// best-ranked stocks give way to the best-ranked commodities. Best
/// first. With fewer than [min] qualifying underlyings (the builder
/// dexes not read), the movers of [trending] (the Trending list)
/// instead, as every other category ([hlMovingNow]); or, with
/// [fallback] false (the builder dexes still on their way), no strip.
/// [keep] as [hlMovingNow]'s.
List<HlMarket> hlTrendingStrip(
  List<HlMarket> universe,
  List<HlMarket> trending, {
  int min = kHlMoverCardMin,
  int max = kHlHypeCardMax,
  bool fallback = true,
  bool Function(HlMarket market)? keep,
}) {
  final scored = <({HlMarket m, double hype, int index})>[];
  for (var i = 0; i < universe.length; i++) {
    final m = universe[i];
    if (!hlHypeCandidate(m)) continue;
    scored.add((m: m, hype: hlHypeScore(m)!, index: i));
  }
  scored.sort((a, b) {
    final h = b.hype.compareTo(a.hype);
    if (h != 0) return h;
    final v = b.m.dayNtlVlm.compareTo(a.m.dayNtlVlm);
    return v != 0 ? v : a.index.compareTo(b.index);
  });
  final unique = _onePerUnderlying([for (final s in scored) s.m])
      .where(keep ?? (_) => true)
      .toList();
  if (unique.length < min) {
    return fallback ? hlMovingNow(trending, min: min, keep: keep) : const [];
  }

  bool isCommodity(HlMarket m) => m.category == 'commodities';
  final commodities = unique.where(isCommodity).toList();
  final wantCommodities = math.min(
      math.min(kHlHypeCommoditiesMin, commodities.length), max);
  final picked = unique.take(max).toList();
  var have = picked.where(isCommodity).length;
  // Too few commodities in the top: the lowest-ranked stocks make room
  // for the next commodities.
  var next = 0;
  while (have < wantCommodities) {
    while (picked.contains(commodities[next])) {
      next++;
    }
    final drop = picked.lastIndexWhere((m) => !isCommodity(m));
    picked[drop] = commodities[next];
    have++;
  }
  final rank = {for (var i = 0; i < unique.length; i++) unique[i]: i};
  picked.sort((a, b) => rank[a]!.compareTo(rank[b]!));
  return picked;
}

/// The strip [choose] makes ([hlTrendingStrip] or [hlMovingNow], given
/// its `keep`) with only markets that have a logo of their own
/// ([HlIconAvailability.of]):
///   * [best]: the strip if every logo not known yet turned out to be
///     one, the most it could be;
///   * [pending]: the markets of [best] whose logo is not known yet,
///     settled with [HlIconAvailability.ensure];
///   * [shown]: the strip of the known logos alone, drawn meanwhile when
///     it has its four;
///   * [loading]: no strip of known logos yet, but [best] could be one:
///     the squares' skeleton stands, never letter tiles.
/// Every logo known: [shown] is the strip, or nothing under four.
({
  List<HlMarket> shown,
  List<HlMarket> best,
  List<HlMarket> pending,
  bool loading,
}) hlStripWithLogos(
  List<HlMarket> Function(bool Function(HlMarket market) keep) choose, {
  HlLogoStatus Function(HlMarket market) status = HlIconAvailability.of,
}) {
  final known = <HlMarket, HlLogoStatus>{};
  HlLogoStatus of(HlMarket m) => known.putIfAbsent(m, () => status(m));
  final best = choose((m) => of(m) != HlLogoStatus.miss);
  final pending = [
    for (final m in best)
      if (of(m) == HlLogoStatus.unknown) m,
  ];
  final shown = pending.isEmpty
      ? best
      : choose((m) => of(m) == HlLogoStatus.hit);
  return (
    shown: shown,
    best: best,
    pending: pending,
    loading: shown.isEmpty && best.isNotEmpty,
  );
}

/// Rows the default view (Trending) lists under its
/// strip (founder, 1 November 2026: the home of Investing is a curated
/// slice; the floating bar searches everything). Any other category the
/// person picks is listed in full: they asked for it.
const int kHlTrendingListRows = 6;

/// Whether [tab] at [sub] is the default view, the one view with a strip
/// (Trending at its default list).
bool hlBrowseIsDefaultView(HlBrowseTab tab, HlBrowseSub sub) =>
    tab == HlBrowseTab.trending && sub == HlBrowseSub.all;

/// The rows listed under the strip: the first
/// [kHlTrendingListRows] of [rest] on the default view (Trending at its
/// default list), all of [rest] on any other.
List<T> hlBrowseRowsShown<T>(bool defaultView, List<T> rest) =>
    defaultView && rest.length > kHlTrendingListRows
        ? rest.sublist(0, kHlTrendingListRows)
        : rest;

/// The list under a strip of [strip]: [markets] less the strip's markets
/// and any other market on the same underlying (founder, 1 November
/// 2026: the strip's names are not repeated). Null when that would leave
/// fewer than [kHlMoverListKeeps] rows: then there is no strip and every
/// market is a row.
List<HlMarket>? hlListUnderStrip(List<HlMarket> markets, List<HlMarket> strip) {
  if (strip.isEmpty) return markets;
  final onStrip = {for (final m in strip) '${m.kind.name}:${m.wireCoin}'};
  final underlyings = {for (final m in strip) hlUnderlyingKey(m)};
  final rest = [
    for (final m in markets)
      if (!onStrip.contains('${m.kind.name}:${m.wireCoin}') &&
          !underlyings.contains(hlUnderlyingKey(m)))
        m,
  ];
  return rest.length < kHlMoverListKeeps ? null : rest;
}

/// The square's text: the change, the name and the price, with the line
/// heights the square's height is computed from (the Latest square's).
TextStyle _nameStyle(BuildContext context) => TextStyle(
      color: context.colors.textSecondary,
      fontSize: 13.sp,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.1,
      height: 1.25,
    );

TextStyle _priceStyle(BuildContext context) => TextStyle(
      color: context.colors.textPrimary,
      fontSize: 22.sp,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.6,
      height: 1.2,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

TextStyle _changeStyle(BuildContext context) => TextStyle(
      color: context.colors.textSecondary,
      fontSize: 13.sp,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
      height: 1.2,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

/// A square's height: [kActivitySquareHeight] (the Latest square's), or
/// its content at the viewer's text size when that is taller, so no
/// square overflows at an accessibility size.
double hlMovingNowCardHeight(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context);
  final content = _kPad.w * 2 +
      kHlMoverCardIcon.w +
      10.w +
      scaler.scale(13.sp) * 1.25 +
      4.h +
      scaler.scale(22.sp) * 1.2 +
      // A pixel of slack for rounding.
      2;
  final least = kActivitySquareHeight.w;
  return content > least ? content : least;
}

/// How many of a Watchlist of [count] markets are squares (see the file
/// header): full rows of two only, four at most; the rest are rows.
int hlWatchlistSquareCount(int count) => count >= kHlMoverCardMax
    ? kHlMoverCardMax
    : count >= 2
        ? 2
        : 0;

/// The four squares, two by two, one per market in [markets] (the strip's
/// own order: [hlTrendingStrip] / [hlMovingNow]; the Watchlist's).
class HlMovingNowStrip extends StatelessWidget {
  final List<HlMarket> markets;

  /// Account-scoped callers supply their own navigation, per market. The
  /// default opens the spending account's market detail sheet.
  final void Function(HlMarket market)? onTap;

  /// The market page's entry source for a tap ([kHlMovingNowSource]; the
  /// Watchlist's 'watchlist').
  final String source;

  /// A blank plate where a market has no logo (Moving now, whose markets
  /// all have one); false: the logo's usual glyph or letter tile (the
  /// Watchlist, see the file header).
  final bool blankUntilLogo;

  const HlMovingNowStrip({
    super.key,
    required this.markets,
    this.onTap,
    this.source = kHlMovingNowSource,
    this.blankUntilLogo = true,
  });

  @override
  Widget build(BuildContext context) {
    // No title over the squares (founder, 1 November 2026): they simply
    // open the list.
    final tap = onTap;
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 4.h),
      child: ActivitySquareGrid(children: [
        for (final m in markets.take(kHlMoverCardMax))
          HlMovingNowCard(
            key: ValueKey('hl-mover-${m.kind.name}-${m.wireCoin}'),
            market: m,
            source: source,
            blankUntilLogo: blankUntilLogo,
            onTap: tap == null ? null : () => tap(m),
          ),
      ]),
    );
  }
}

/// The four squares while their logos are still unknown
/// ([hlStripWithLogos]): each square's ground at its height, the logo's
/// circle and the name and price bars where they will land, shimmering.
class HlMovingNowStripSkeleton extends StatelessWidget {
  const HlMovingNowStripSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final decoration = PremiumGroupContainer.decorationOf(context);
    final height = hlMovingNowCardHeight(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 4.h),
      child: KuteSkeleton(
        child: ActivitySquareGrid(children: [
          for (var i = 0; i < kHlMoverCardMax; i++)
            Container(
              height: height,
              decoration: decoration,
              padding: EdgeInsets.all(_kPad.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonCircle(kHlMoverCardIcon.w),
                  const Spacer(),
                  SkeletonBar(64.w, 12.h),
                  SizedBox(height: 8.h),
                  SkeletonBar(96.w, 20.h),
                ],
              ),
            ),
        ]),
      ),
    );
  }
}

/// One square of the grid. Consumer-stateful like the row, so it can
/// watch its coin's live mid and register the coin with the live-prices
/// watch-set on mount (released wholesale by the screen; never unwatched
/// here).
class HlMovingNowCard extends ConsumerStatefulWidget {
  final HlMarket market;
  final VoidCallback? onTap;

  /// As [HlMovingNowStrip.source] and [HlMovingNowStrip.blankUntilLogo].
  final String source;
  final bool blankUntilLogo;

  const HlMovingNowCard({
    super.key,
    required this.market,
    this.onTap,
    this.source = kHlMovingNowSource,
    this.blankUntilLogo = true,
  });

  @override
  ConsumerState<HlMovingNowCard> createState() => _HlMovingNowCardState();
}

class _HlMovingNowCardState extends ConsumerState<HlMovingNowCard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(hyperliquidLivePricesProvider.notifier).watchCoins(
        [widget.market.coin],
        wire: {widget.market.coin: widget.market.wireCoin},
      );
    });
  }

  void _open() {
    HapticFeedback.mediumImpact();
    if (widget.onTap != null) {
      widget.onTap!();
    } else {
      // hyperliquid_market_viewed fires once, from the sheet, with this
      // grid as its entry source.
      HlMarketDetailSheet.show(context,
          market: widget.market, source: widget.source);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = widget.market;

    // The live price and its change, as the row reads them.
    final liveMid = ref.watch(hyperliquidLiveMidProvider(m.coin));
    final price = liveMid ?? (m.midPx > 0 ? m.midPx : m.markPx);
    final change = m.dayChangeAtOrNull(price);
    final changeColor = change == null || change == 0
        ? c.textSecondary
        : change > 0
            ? greenColor
            : redColor;

    final name =
        hlFriendlyName(m.underlyingTicker) ?? m.unitAssetName ?? m.coin;

    final decoration = PremiumGroupContainer.decorationOf(context);
    final radius = decoration.borderRadius as BorderRadius?;
    return KutePressable(
      child: Container(
        height: hlMovingNowCardHeight(context),
        decoration: decoration,
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            onTap: _open,
            borderRadius: radius,
            child: Padding(
              padding: EdgeInsets.all(_kPad.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipOval(
                        // A blank plate until the logo paints, never the
                        // letter tile or a glyph (only markets with a
                        // logo are on the strip); the Watchlist's keep
                        // the logo's usual fallback.
                        child: HlCoinIcon(
                          coin: m.coin,
                          wireCoin: m.wireCoin,
                          category: m.category,
                          iconUrl: m.iconUrl,
                          size: kHlMoverCardIcon,
                          placeholder: widget.blankUntilLogo
                              ? Container(
                                  width: kHlMoverCardIcon.w,
                                  height: kHlMoverCardIcon.w,
                                  color: c.surfaceElevated,
                                )
                              : null,
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: Align(
                          alignment: Alignment.topRight,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.topRight,
                            child: RollingNumberText(
                              text: change == null ? '—' : hlArrowPct(change),
                              style: _changeStyle(context)
                                  .copyWith(color: changeColor),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _nameStyle(context),
                  ),
                  SizedBox(height: 4.h),
                  // A price too wide for the square (BTC's) shrinks rather
                  // than overflow it.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: RollingNumberText(
                      text: formatHlListPrice(price,
                          decimalCap: m.pxDecimalCap),
                      style: _priceStyle(context),
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
