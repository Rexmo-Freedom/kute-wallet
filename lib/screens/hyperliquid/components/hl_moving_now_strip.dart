// lib/screens/hyperliquid/components/hl_moving_now_strip.dart
//
// The strip of large cards above the Investing browse list (founder,
// November 2026: "big cards of the top ones on top", the way Revolut /
// Coinbase / Robinhood show the day's names). One horizontal,
// side-scrolling row of cards with no title over it.
//
// What it shows:
//   * Trending ([hlTrendingStrip]): the hyped names, stocks and shares
//     and commodities (founder, 1 November 2026: "stocks and shares are
//     the best to put there, and commodities. Do not repeat ones."),
//     ranked by [hlHypeScore], at least [kHlHypeCommoditiesMin]
//     commodities among the [kHlHypeCardMax], one card per underlying
//     ([hlUnderlyingKey]). With fewer than [kHlMoverCardMin] such
//     markets loaded (the builder dexes not read yet), the movers below.
//   * Every other category ([hlMovingNow]): its largest absolute 24h
//     changes, ties by volume, one card per underlying.
// Thin markets ([HlMarket.isLowLiquidity]) and markets with no 24h change
// to show are never on it. A market on the strip, or one on the same
// underlying, is not repeated in the list under it ([hlListUnderStrip]).
//
// Each card (HlMovingNowCard, a 148 square, the app's card surface at the
// grouped card's 20 radius, 14 padding; founder, 1 November 2026: the
// portrait cards read stretched): on top the logo (28) beside the
// market's name over its ticker, across the middle the row's line
// sparkline (36 tall, the row's stroke and colour), and at the bottom the
// live price (tabular, primary colour) left and the 24h change as the row
// writes it ("▲ 3.9%", coloured) right, on one baseline. Plain coloured
// text, no tinted chip (house rule: solid fills or neutral grey only). The whole card taps through
// to HlMarketDetailSheet, entry_source 'moving_now', on the app's press
// spring (KutePressable).
//
// The strip is only shown when at least [kHlMoverCardMin] markets
// qualify: a strip of one card reads as a mistake.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart'
    show HlBrowseTab, hlMarketMatchesTab;
import 'package:kute/providers/hyperliquid_sparkline_provider.dart';
import 'package:kute/screens/home/components/action_pill.dart'
    show greenColor, redColor;
import 'package:kute/screens/hyperliquid/components/hl_charts.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/hyperliquid/components/hl_market_card.dart'
    show hlArrowPct, kHlSparklineOpacity;
import 'package:kute/screens/hyperliquid/market_detail_sheet.dart';
import 'package:kute/screens/shared/kute_motion.dart' show KutePressable;
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/services/hyperliquid/hl_sparkline_cache.dart';
import 'package:kute/theme/app_theme.dart';

/// How many cards the strip shows at most.
const int kHlMoverCardMax = 5;

/// Under this many movers the strip is not shown at all.
const int kHlMoverCardMin = 3;

/// A card's side (the cards are square) and the gap between two, in
/// design units.
const double kHlMoverCardWidth = 148;
const double kHlMoverCardGap = 10;

/// The card's logo.
const double kHlMoverCardIcon = 28;

/// The card's sparkline: the card's inner width, this tall.
const double kHlMoverSparklineHeight = 36;

/// The card's inner padding, in design units.
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
/// ([hlUnderlyingKey]): of the markets on one underlying, the most traded
/// stays, at its own place in [ranked].
List<HlMarket> _onePerUnderlying(List<HlMarket> ranked) {
  final best = <String, HlMarket>{};
  for (final m in ranked) {
    final key = hlUnderlyingKey(m);
    final held = best[key];
    if (held == null || m.dayNtlVlm > held.dayNtlVlm) best[key] = m;
  }
  final keep = best.values.toSet();
  return [
    for (final m in ranked)
      if (keep.contains(m)) m
  ];
}

/// The markets the strip shows for [markets] (a category's list): the
/// [max] with the largest absolute 24h change, ties broken by 24h
/// volume, then by their place in the list, one per underlying. A market
/// with no change to show (no previous-day price) or thinly traded
/// ([HlMarket.isLowLiquidity]) is left out. Empty, so no strip, under
/// [min] candidates.
List<HlMarket> hlMovingNow(
  List<HlMarket> markets, {
  int min = kHlMoverCardMin,
  int max = kHlMoverCardMax,
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
  final unique = _onePerUnderlying([for (final r in ranked) r.m]);
  if (unique.length < min) return const [];
  return unique.take(max).toList(growable: false);
}

/// How many cards the Trending strip shows at most.
const int kHlHypeCardMax = 6;

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
List<HlMarket> hlTrendingStrip(
  List<HlMarket> universe,
  List<HlMarket> trending, {
  int min = kHlMoverCardMin,
  int max = kHlHypeCardMax,
  bool fallback = true,
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
  final unique = _onePerUnderlying([for (final s in scored) s.m]);
  if (unique.length < min) {
    return fallback ? hlMovingNow(trending, min: min) : const [];
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

/// Rows the default view (Trending) lists under its
/// strip (founder, 1 November 2026: the home of Investing is a curated
/// slice; the floating bar searches everything). Any other category the
/// person picks is listed in full: they asked for it.
const int kHlTrendingListRows = 6;

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

/// The card's text: the name, the ticker caption, the price and the
/// change, with the line heights the strip's height is computed from.
TextStyle _nameStyle(BuildContext context) => TextStyle(
      color: context.colors.textPrimary,
      fontSize: 15.sp,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
      height: 1.2,
    );

TextStyle _captionStyle(BuildContext context) => TextStyle(
      color: context.colors.textSecondary,
      fontSize: 11.sp,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.1,
      height: 1.2,
    );

TextStyle _changeStyle(BuildContext context) =>
    _captionStyle(context).copyWith(fontSize: 12.sp);

/// The strip's card height: the card's side ([kHlMoverCardWidth], square),
/// or its content at the viewer's text size when that is taller, so no
/// card overflows at an accessibility size.
double hlMovingNowCardHeight(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context);
  double line(double sp) => scaler.scale(sp.sp) * 1.2;
  final top = line(15) + line(11);
  final content = _kPad.w * 2 +
      (top > kHlMoverCardIcon.w ? top : kHlMoverCardIcon.w) +
      8.w +
      // The sparkline scales its height by the screen's height
      // ([HlLineSparkline]); on a phone that is the same as its width.
      kHlMoverSparklineHeight.h +
      8.w +
      line(15) +
      // A pixel of slack for rounding.
      2;
  final side = kHlMoverCardWidth.w;
  return content > side ? content : side;
}

/// "Moving now" and its row of cards, one per market in [markets] (the
/// strip's own order: [hlMovingNow]).
class HlMovingNowStrip extends StatelessWidget {
  final List<HlMarket> markets;

  /// Account-scoped callers supply their own navigation, per market. The
  /// default opens the spending account's market detail sheet.
  final void Function(HlMarket market)? onTap;

  const HlMovingNowStrip({super.key, required this.markets, this.onTap});

  @override
  Widget build(BuildContext context) {
    // No title over the strip (founder, 1 November 2026): the cards
    // simply open the list.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: 4.h),
        SizedBox(
          height: hlMovingNowCardHeight(context),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            // The cards' soft shadow may spill out of the row; the screen
            // edge clips the row itself.
            clipBehavior: Clip.none,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            itemCount: markets.length,
            separatorBuilder: (_, __) => SizedBox(width: kHlMoverCardGap.w),
            itemBuilder: (context, i) {
              final m = markets[i];
              final tap = onTap;
              return HlMovingNowCard(
                key: ValueKey('hl-mover-${m.kind.name}-${m.wireCoin}'),
                market: m,
                onTap: tap == null ? null : () => tap(m),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// One large card of the strip. Consumer-stateful like the row, so it can
/// watch its coin's live mid and register the coin with the live-prices
/// watch-set on mount (released wholesale by the screen; never unwatched
/// here).
class HlMovingNowCard extends ConsumerStatefulWidget {
  final HlMarket market;
  final VoidCallback? onTap;

  const HlMovingNowCard({super.key, required this.market, this.onTap});

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
      // strip as its entry source.
      HlMarketDetailSheet.show(context,
          market: widget.market, source: kHlMovingNowSource);
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

    final name = hlFriendlyName(m.coin) ?? m.unitAssetName ?? m.coin;
    final caption = [
      if (name != m.coin) m.coin,
      if (m.isSpot) context.l10n.investingSpot,
    ].join(' · ');

    // The daily closes with their live end, as the row plots them.
    final spark = ref.watch(hyperliquidSparklineProvider(m.wireCoin));
    final closes = spark == null
        ? const <double>[]
        : hlSparklineWithLivePrice(
            spark.closes,
            price,
            appendLive: spark.day < hlUtcDay(DateTime.now()),
          );
    final lineColor = changeColor.withValues(alpha: kHlSparklineOpacity);

    final radius = BorderRadius.circular(AppRadius.xl);
    final inner = (kHlMoverCardWidth - _kPad * 2).w;
    final tabular = const [FontFeature.tabularFigures()];
    return KutePressable(
      child: Container(
        width: kHlMoverCardWidth.w,
        decoration:
            AppDecorations.card(context).copyWith(borderRadius: radius),
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
                  // The logo beside the name over its ticker.
                  Row(
                    children: [
                      ClipOval(
                        child: HlCoinIcon(
                          coin: m.coin,
                          wireCoin: m.wireCoin,
                          category: m.category,
                          iconUrl: m.iconUrl,
                          size: kHlMoverCardIcon,
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _nameStyle(context),
                            ),
                            // An empty caption keeps its line, so every
                            // card's rows sit at the same height.
                            Text(
                              caption.isEmpty ? ' ' : caption,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _captionStyle(context),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  HlLineSparkline(
                    closes: closes,
                    width: kHlMoverCardWidth - _kPad * 2,
                    height: kHlMoverSparklineHeight,
                    strokeWidth: 1.2,
                    baseline: false,
                    upColor: lineColor,
                    downColor: lineColor,
                  ),
                  const Spacer(),
                  // The price left, the change right, on one baseline. A
                  // price too wide for the card (BTC's) shrinks the row
                  // rather than overflow it.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: inner),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          RollingNumberText(
                            text: formatHlListPrice(price,
                                decimalCap: m.pxDecimalCap),
                            style: _nameStyle(context)
                                .copyWith(fontFeatures: tabular),
                          ),
                          SizedBox(width: 6.w),
                          RollingNumberText(
                            text: change == null ? '—' : hlArrowPct(change),
                            style: _changeStyle(context).copyWith(
                              color: changeColor,
                              fontFeatures: tabular,
                            ),
                          ),
                        ],
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
