import 'package:kute/l10n/l10n.dart';
// lib/screens/hyperliquid/components/hl_market_card.dart
//
// The Investing browse lists' market card (Home and the Ledger tab).
//
// Layout: ONE row, about 72 px tall, on the app's card surface
// (AppDecorations.card):
//   * the market's logo, round (HlCoinIcon, glyph / letter fallback);
//   * the market's NAME ("Bitcoin", "Tesla"; the ticker when no name is
//     known) over a caption "TICKER · 40x" (a perp's max leverage) or
//     "TICKER · Spot"; the ticker is left out when the name already is
//     the ticker ("40x", "Spot");
//   * a small LINE sparkline (HlLineSparkline) of the daily closes, in the
//     up / down colour of the 24h change (neutral when flat or unknown),
//     from the device cache (one request per coin per UTC day; see
//     hyperliquid_sparkline_provider.dart), empty until the first lands;
//   * the LIVE price, always in the primary text colour, over the signed
//     24h % change in the up / down colour (a dash when unknown).
//
// A thinly traded market (HlMarket.isLowLiquidity) ends its caption with
// " · Low liquidity" (on a second caption line when one cannot hold it:
// never an ellipsis inside the caption), draws no sparkline (it would be
// a few carried-forward steps) and, with no 24h change to show, nothing
// under the price.
//
// No star, no volume line (the lists are ordered by volume), no kind
// badge (the caption says it), no Long/Short CTAs — those live only in
// the detail sheet. The whole card taps through to HlMarketDetailSheet.
//
// Live prices: the card registers its coin with the allMids watch-set on
// mount (idempotent, additive) — the screen releases the whole socket via
// its captured notifier reference on dispose, so the card must NOT unwatch.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_sparkline_provider.dart';
import 'package:kute/screens/home/components/action_pill.dart'
    show greenColor, redColor;
import 'package:kute/screens/hyperliquid/components/hl_charts.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/hyperliquid/market_detail_sheet.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/services/hyperliquid/hl_sparkline_cache.dart';
import 'package:kute/theme/app_theme.dart';

/// Browse card for one Hyperliquid market (perp or spot). Consumer-stateful
/// so it can watch this coin's live mid + tick direction and register the
/// coin with the live-prices watch-set on mount.
class HlMarketCard extends ConsumerStatefulWidget {
  final HlMarket market;

  /// Account-scoped callers supply their own navigation. The default
  /// opens the spending account's market detail screen.
  final VoidCallback? onTap;

  const HlMarketCard({super.key, required this.market, this.onTap});

  @override
  ConsumerState<HlMarketCard> createState() => _HlMarketCardState();
}

class _HlMarketCardState extends ConsumerState<HlMarketCard> {
  @override
  void initState() {
    super.initState();
    // Register this card's coin with the allMids watch-set the moment it
    // scrolls into view — additive + idempotent, released wholesale by the
    // screen's `unwatchAll` on dispose (this card must never unwatch).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // The wire alias makes spot ('@N') and HIP-3 ('dex:COIN') cards
      // stream too — their allMids keys never match the display name.
      ref.read(hyperliquidLivePricesProvider.notifier).watchCoins(
        [widget.market.coin],
        wire: {widget.market.coin: widget.market.wireCoin},
      );
    });
  }

  void _openDetail() {
    HapticFeedback.mediumImpact();
    final m = widget.market;
    // hyperliquid_market_viewed fires once, from HlMarketDetailSheet.show.
    if (widget.onTap != null) {
      widget.onTap!();
    } else {
      HlMarketDetailSheet.show(context, market: m);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = widget.market;

    final liveMid = ref.watch(hyperliquidLiveMidProvider(m.coin));
    final price = liveMid ?? (m.midPx > 0 ? m.midPx : m.markPx);
    // The change of the live price on the card (the snapshot's 24h % can
    // be minutes old for a builder-dex market).
    // Null without a previous-day price: a dash, never 0% or −100%.
    final change = m.dayChangeAtOrNull(price);
    // Up, down, or neutral when flat or unknown. The line and the change
    // share it, so the two never disagree; the price never takes it.
    final changeColor = change == null || change == 0
        ? c.textSecondary
        : change > 0
            ? greenColor
            : redColor;

    // What the market is called: the asset's own name, and a Unit-bridged
    // token reads as the asset it holds (UBTC: Bitcoin), the way
    // Hyperliquid's own app names it. The ticker when no name is known.
    final name = hlFriendlyName(m.coin) ?? m.unitAssetName ?? m.coin;
    // What the market is: how far a perp can be geared, or that a spot
    // token is held outright. A spot market and a perp for the same
    // underlying can share a list, and this line tells them apart. The
    // ticker leads it, unless the title already is the ticker (a market
    // with no name of its own): it is not said twice.
    final kind = m.isSpot
        ? context.l10n.investingSpot
        : '${m.offeredMaxLeverage}x';
    final caption = name == m.coin ? kind : '${m.coin} · $kind';
    // A thinly traded market says so, and draws no sparkline: its line is
    // a few carried-forward steps, and the room goes to the caption.
    final thin = m.isLowLiquidity;

    // Daily closes for the line sparkline, from the device cache: drawn at
    // once when this coin was seen before, fetched at most once per UTC
    // day (hyperliquid_sparkline_provider.dart). Keyed by the wire coin,
    // which is what candleSnapshot takes for perps, HIP-3 and spot alike.
    // A thin market draws no line, so it asks for no candles either.
    final spark =
        thin ? null : ref.watch(hyperliquidSparklineProvider(m.wireCoin));
    // Live tail: the series' last close is today's forming candle, so the
    // live price replaces it and the line ticks with the price. A series
    // from an earlier day (today's on its way) gets the live price as a
    // new last point instead. Spot closes in raw pair units are rescaled
    // onto the price's units (see hlSparklineWithLivePrice).
    final closes = spark == null
        ? const <double>[]
        : hlSparklineWithLivePrice(
            spark.closes,
            price,
            appendLive: spark.day < hlUtcDay(DateTime.now()),
          );

    final titleStyle = AppTextStyles.settingsTitle(context);
    final captionStyle = TextStyle(
      color: c.textSecondary,
      fontSize: 13.sp,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.1,
    );

    return Container(
      decoration: AppDecorations.card(context),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          onTap: _openDetail,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // The REAL coin/token logo (category glyph or letter badge
                // on a miss), cut round for this row.
                ClipOval(
                  child: HlCoinIcon(
                    coin: m.coin,
                    wireCoin: m.wireCoin,
                    category: m.category,
                    iconUrl: m.iconUrl,
                    size: 36,
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle,
                      ),
                      SizedBox(height: 2.h),
                      if (!thin)
                        Text(
                          caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: captionStyle,
                        )
                      else
                        _ThinCaption(
                          caption: caption,
                          note: context.l10n.investingLowLiquidity,
                          style: captionStyle,
                        ),
                    ],
                  ),
                ),
                // The line only, no fill and no axes. Empty (same width,
                // so the prices stay aligned) until the candles land. A
                // thin market has none: see [thin].
                if (!thin) ...[
                  SizedBox(width: 12.w),
                  HlLineSparkline(
                    closes: closes,
                    width: 64,
                    height: 28,
                    upColor: changeColor,
                    downColor: changeColor,
                  ),
                ],
                SizedBox(width: 12.w),
                // A fixed minimum width, right-aligned, so the prices line
                // up down the list; a longer price widens it, never wraps.
                ConstrainedBox(
                  constraints: BoxConstraints(minWidth: 84.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Always the primary text colour: the digits roll on
                      // a tick, the colour belongs to the change below.
                      RollingNumberText(
                        text: formatHlPrice(price, decimalCap: m.pxDecimalCap),
                        style: titleStyle.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      // No change to show on a thin market: the price
                      // stands alone, centred, not over a lone dash.
                      if (change != null || !thin) ...[
                        SizedBox(height: 2.h),
                        _ChangeText(
                          text: change == null ? '—' : formatHlPct(change),
                          color: changeColor,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A thin market's caption: "TSLA · Spot · Low liquidity" on one line
/// when it fits, and otherwise the note on a second line of its own. An
/// ellipsis can only ever fall at the very end of the first line, never
/// inside the caption.
class _ThinCaption extends StatelessWidget {
  final String caption;
  final String note;
  final TextStyle style;
  const _ThinCaption({
    required this.caption,
    required this.note,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    final whole = '$caption · $note';
    return LayoutBuilder(builder: (context, box) {
      final painter = TextPainter(
        // Measured in the face the line is drawn in.
        text: TextSpan(
            text: whole, style: DefaultTextStyle.of(context).style.merge(style)),
        maxLines: 1,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final fits = painter.width <= box.maxWidth;
      painter.dispose();
      if (fits) {
        return Text(whole, maxLines: 1, softWrap: false, style: style);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(caption,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
          Text(note,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
        ],
      );
    });
  }
}

/// Signed 24h % change under the price — plain coloured TEXT (marketUp /
/// marketDown via greenColor / redColor), no tinted box: tinted chips are
/// rejected app-wide (solid fills or neutral grey only; coloured text on a
/// neutral surface is fine). [text] arrives already signed from
/// [formatHlPct] ('+1.2%' / '−0.8%'). Rolls its digits like the position
/// card's PnL line so a 30 s universe refresh ticks instead of snapping.
class _ChangeText extends StatelessWidget {
  final String text;
  final Color color;
  const _ChangeText({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return RollingNumberText(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: 13.sp,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
