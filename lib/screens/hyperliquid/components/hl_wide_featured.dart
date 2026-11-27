// lib/screens/hyperliquid/components/hl_wide_featured.dart
//
// THE WIDE WEB INVESTING HOME'S FEATURED CARD (founder, 27 November 2026:
// "here on Investing and Predictions maybe have one big one"): on the web
// at MEDIUM and EXPANDED, Trending's featured set (the strip's four,
// [hlTrendingStrip], in its order) as ONE large card, the Predictions
// page's featured card's frame ([KuteWideFeaturedFrame]), previous / next
// stepping through them. The phones and the phone layout keep the four
// squares ([HlMovingNowStrip]).
//
//   * left: the logo (only one the web can draw, [hlLogoShown]: else the
//     name alone) and the name; the live price large with the day's move
//     beside it in the up / down colours, as the squares write it; then the
//     market screen's own Stats for the day, with its labels and
//     formatting ([hlMarketStats]' 24h Volume and Funding, the About
//     sheet's 24h High and Low), nothing about leverage;
//   * right: the market's line ([KuteLineChart], the app's line chart) over
//     the series the squares' sparklines draw (daily closes,
//     [hyperliquidSparklineProvider], already read for the strip) ending on
//     the live price, its endpoint dot marking it; dropped on a card under
//     [kKuteWideFeaturedChartMinWidth], as Predictions'.
//
// Data: the live mid of the shown market (the feed the squares watched),
// the cached sparkline, and the day's 1h candles of the shown market only
// (the About sheet's 24h High / Low key, autoDispose: released as soon as
// another market is shown or the card goes). No polling of its own.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/hyperliquid_model.dart'
    show rescaleCandlesToDisplay;
import 'package:kute/providers/hyperliquid_candles_provider.dart'
    show hyperliquidLiveCandlesProvider;
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_sparkline_provider.dart'
    show hyperliquidSparklineProvider;
import 'package:kute/screens/home/components/action_pill.dart'
    show greenColor, redColor;
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/hyperliquid/components/hl_market_card.dart'
    show hlArrowPct;
import 'package:kute/screens/hyperliquid/components/hl_market_stats.dart'
    show HlStat, formatHlFundingRate;
import 'package:kute/screens/hyperliquid/components/hl_moving_now_strip.dart'
    show kHlMovingNowSource;
import 'package:kute/screens/hyperliquid/market_detail_sheet.dart';
import 'package:kute/screens/shared/charts/kute_line_chart.dart';
import 'package:kute/screens/shared/kute_skeleton.dart'
    show KuteSkeleton, SkeletonBar, SkeletonCircle;
import 'package:kute/screens/shared/kute_wide_featured_frame.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/services/hyperliquid/hl_sparkline_cache.dart'
    show hlSparklineWithLivePrice;
import 'package:kute/theme/app_theme.dart';

/// The day's high and low of [m] from the About sheet's 1h x 24h candles
/// (hlAboutStats, market_detail_sheet.dart), rescaled onto display units;
/// null until they land.
({double hi, double lo})? _dayRange(WidgetRef ref, HlMarket m) {
  final raw = ref
      .watch(hyperliquidLiveCandlesProvider((
        wireCoin: m.wireCoin,
        interval: '1h',
        windowHours: 24,
        exact: false,
      )))
      .valueOrNull
      ?.candles;
  if (raw == null || raw.isEmpty) return null;
  final scaled = rescaleCandlesToDisplay(raw, m.midPx > 0 ? m.midPx : m.markPx);
  var hi = scaled.first.high, lo = scaled.first.low;
  for (final k in scaled) {
    if (k.high > hi) hi = k.high;
    if (k.low < lo) lo = k.low;
  }
  return hi > 0 && lo > 0 ? (hi: hi, lo: lo) : null;
}

/// Trending's featured set as one large card (see the file header).
/// [onTap] as [HlMovingNowStrip.onTap]; null opens the market page as a
/// square did.
class HlWideFeatured extends ConsumerStatefulWidget {
  const HlWideFeatured({
    super.key,
    required this.markets,
    this.onTap,
    this.chart = true,
  });

  final List<HlMarket> markets;
  final void Function(HlMarket market)? onTap;

  /// Tests: off leaves the chart, its series and the day's candles out.
  final bool chart;

  @override
  ConsumerState<HlWideFeatured> createState() => _HlWideFeaturedState();
}

class _HlWideFeaturedState extends ConsumerState<HlWideFeatured> {
  int _at = 0;

  @override
  void initState() {
    super.initState();
    _watch();
  }

  @override
  void didUpdateWidget(HlWideFeatured old) {
    super.didUpdateWidget(old);
    if (!identical(old.markets, widget.markets)) _watch();
  }

  /// The set's coins into the live-prices watch-set, as each square did on
  /// mount (released wholesale by the screen).
  void _watch() {
    final markets = widget.markets;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || markets.isEmpty) return;
      ref.read(hyperliquidLivePricesProvider.notifier).watchCoins(
        [for (final m in markets) m.coin],
        wire: {for (final m in markets) m.coin: m.wireCoin},
      );
    });
  }

  void _open(HlMarket m) {
    HapticFeedback.mediumImpact();
    final tap = widget.onTap;
    if (tap != null) {
      tap(m);
    } else {
      HlMarketDetailSheet.show(context, market: m, source: kHlMovingNowSource);
    }
  }

  @override
  Widget build(BuildContext context) {
    final markets = widget.markets;
    if (markets.isEmpty) return const SizedBox.shrink();
    final at = _at.clamp(0, markets.length - 1);
    final m = markets[at];
    final c = context.colors;
    final l10n = context.l10n;

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
    final range = widget.chart ? _dayRange(ref, m) : null;
    final stats = [
      HlStat(l10n.hl24hVolume, formatHlCompactUsd(m.dayNtlVlm)),
      if (range != null) ...[
        HlStat(l10n.hl24hHigh,
            formatHlPrice(range.hi, decimalCap: m.pxDecimalCap)),
        HlStat(l10n.hl24hLow,
            formatHlPrice(range.lo, decimalCap: m.pxDecimalCap)),
      ],
      if (!m.isSpot && m.funding != null)
        HlStat(l10n.hlFunding, formatHlFundingRate(m.funding!)),
    ];

    final series = widget.chart
        ? ref.watch(hyperliquidSparklineProvider(m.wireCoin))
        : null;
    final closes = series == null
        ? const <double>[]
        : hlSparklineWithLivePrice(series.closes, price);

    return KuteWideFeaturedFrame(
      keyPrefix: 'hl-wide-featured',
      count: markets.length,
      onStep: (step) => setState(
          () => _at = (at + step + markets.length) % markets.length),
      onTap: () => _open(m),
      header: Row(
        key: ValueKey('hl-wide-featured-${m.kind.name}-${m.wireCoin}'),
        children: [
          // Web: no logo it can draw, just the name.
          if (hlLogoShown(m.coin, m.wireCoin, m.iconUrl, m.category)) ...[
            ClipOval(
              key: const ValueKey('hl-wide-featured-logo'),
              child: HlCoinIcon(
                coin: m.coin,
                wireCoin: m.wireCoin,
                category: m.category,
                iconUrl: m.iconUrl,
                size: 48,
                placeholder: Container(
                    width: 48, height: 48, color: c.surfaceElevated),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(name,
                key: const ValueKey('hl-wide-featured-name'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  height: 1.25,
                )),
          ),
        ],
      ),
      figures: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: RollingNumberText(
                  key: const ValueKey('hl-wide-featured-price'),
                  text: formatHlListPrice(price, decimalCap: m.pxDecimalCap),
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.8,
                    height: 1.2,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            RollingNumberText(
              key: const ValueKey('hl-wide-featured-change'),
              text: change == null ? '—' : hlArrowPct(change),
              style: TextStyle(
                color: changeColor,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
                height: 1.2,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _HlFeaturedStats(stats: stats),
      ],
      foot: const SizedBox.shrink(),
      chart: !widget.chart
          ? null
          : (height) => SizedBox(
                key: ValueKey('hl-wide-featured-chart-${m.wireCoin}'),
                height: height,
                child: closes.length < 2
                    ? null
                    : KuteLineChart(
                        values: closes,
                        lineColor: closes.last >= closes.first
                            ? AppColors.marketUp
                            : AppColors.marketDown,
                        // A live tick moves the end; no morph per tick.
                        animateChanges: false,
                        zoomable: false,
                        showScale: true,
                        // The charts' price format.
                        scaleLabel: (level, _) => formatHlPrice(level,
                            decimalCap: m.pxDecimalCap),
                      ),
              ),
    );
  }
}

/// The day's Stats in one row, the label over the value in the market
/// screen's Stats tile styles (hl_market_stats.dart), no dividers.
class _HlFeaturedStats extends StatelessWidget {
  const _HlFeaturedStats({required this.stats});

  final List<HlStat> stats;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      key: const ValueKey('hl-wide-featured-stats'),
      children: [
        for (var i = 0; i < stats.length; i++) ...[
          if (i > 0) const SizedBox(width: 16),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(stats[i].label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    )),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(stats[i].value,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      )),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// The card's place while the set's logos are still unknown (the squares'
/// skeleton's moment, [HlMovingNowStripSkeleton]): the card at its height,
/// the logo, the name and the price where they will land, shimmering.
class HlWideFeaturedSkeleton extends StatelessWidget {
  const HlWideFeaturedSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return KuteSkeleton(
      child: Container(
        key: const ValueKey('hl-wide-featured-skeleton'),
        height: kKuteWideFeaturedHeight,
        decoration: AppDecorations.card(context),
        padding: const EdgeInsets.all(20),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonCircle(48),
            Spacer(),
            SkeletonBar(160, 32),
            SizedBox(height: 14),
            SkeletonBar(280, 32),
          ],
        ),
      ),
    );
  }
}
