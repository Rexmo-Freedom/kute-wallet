// lib/screens/hyperliquid/components/hl_moving_now_strip.dart
//
// "Moving now": the strip of large cards above the Investing browse list
// (founder, November 2026: "big cards of the top ones on top", the way
// Revolut / Coinbase / Robinhood show the day's movers). One horizontal,
// side-scrolling row of [kHlMoverCardMax] cards at most, one per market
// with the largest absolute 24h change in the category on screen
// ([hlMovingNow]: ties by volume; thin markets left out, their change is
// noise), under a small "Moving now" title. The list keeps its own order
// under the strip, so a market can be both on a card and in a row.
//
// Each card (HlMovingNowCard, about 150 × 186, the app's card surface at
// the grouped card's 20 radius): the logo (36) top-left, the market's
// name over its ticker, the row's line sparkline across the card's width
// (40 tall, the row's stroke and colour), and at the bottom the live
// price (tabular, primary colour) over the 24h change as the row writes
// it ("▲ 3.9%", coloured). Plain coloured text, no tinted chip (house
// rule: solid fills or neutral grey only). The whole card taps through
// to HlMarketDetailSheet, entry_source 'moving_now', on the app's press
// spring (KutePressable).
//
// The strip is only shown when at least [kHlMoverCardMin] markets have a
// known change: a strip of one card reads as a mistake.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
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

/// A card's width and the gap between two, in design units.
const double kHlMoverCardWidth = 150;
const double kHlMoverCardGap = 12;

/// The card's logo.
const double kHlMoverCardIcon = 36;

/// The card's sparkline: the card's inner width, this tall.
const double kHlMoverSparklineHeight = 40;

/// The card's inner padding, in design units.
const double _kPad = 12;

/// The [HlMarketDetailSheet] entry source a strip card reports.
const String kHlMovingNowSource = 'moving_now';

/// The markets the strip shows for [markets] (a category's list): the
/// [max] with the largest absolute 24h change, ties broken by 24h
/// volume, then by their place in the list. A market with no change to
/// show (no previous-day price) or thinly traded ([HlMarket.isLowLiquidity])
/// is left out. Empty, so no strip, under [min] candidates.
List<HlMarket> hlMovingNow(
  List<HlMarket> markets, {
  int min = kHlMoverCardMin,
  int max = kHlMoverCardMax,
}) {
  final ranked = <({HlMarket m, double change, int index})>[];
  for (var i = 0; i < markets.length; i++) {
    final m = markets[i];
    if (m.isLowLiquidity) continue;
    // The snapshot's own change (the row's, before any tick), so the
    // strip does not reorder itself on every live frame.
    final change = m.dayChangeAtOrNull(m.midPx > 0 ? m.midPx : m.markPx);
    if (change == null) continue;
    ranked.add((m: m, change: change.abs(), index: i));
  }
  if (ranked.length < min) return const [];
  ranked.sort((a, b) {
    final c = b.change.compareTo(a.change);
    if (c != 0) return c;
    final v = b.m.dayNtlVlm.compareTo(a.m.dayNtlVlm);
    return v != 0 ? v : a.index.compareTo(b.index);
  });
  return [for (final r in ranked.take(max)) r.m];
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
      fontSize: 12.sp,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.1,
      height: 1.2,
    );

/// The strip's card height: the card's content at the viewer's text
/// size, so no card overflows at an accessibility size and none has
/// slack to spare at the default one.
double hlMovingNowCardHeight(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context);
  double line(double sp) => scaler.scale(sp.sp) * 1.2;
  return _kPad.h * 2 +
      kHlMoverCardIcon.w +
      8.h +
      line(15) +
      line(12) +
      6.h +
      kHlMoverSparklineHeight.h +
      6.h +
      line(15) +
      line(12) +
      // A pixel of slack for rounding.
      2;
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
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 10.h),
          child: Text(
            context.l10n.investingMovingNow,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
            ),
          ),
        ),
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
              padding: EdgeInsets.symmetric(horizontal: _kPad.w, vertical: _kPad.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                  SizedBox(height: 8.h),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _nameStyle(context),
                  ),
                  // An empty caption keeps its line, so every card's
                  // sparkline and price sit at the same height.
                  Text(
                    caption.isEmpty ? ' ' : caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _captionStyle(context),
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
                  RollingNumberText(
                    text: formatHlListPrice(price, decimalCap: m.pxDecimalCap),
                    style: _nameStyle(context).copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  RollingNumberText(
                    text: change == null ? '—' : hlArrowPct(change),
                    style: _captionStyle(context).copyWith(
                      color: changeColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
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
