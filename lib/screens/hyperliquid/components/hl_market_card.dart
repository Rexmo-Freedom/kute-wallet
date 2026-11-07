// lib/screens/hyperliquid/components/hl_market_card.dart
//
// The Investing browse lists' market card (Home and the Ledger tab).
//
// Layout: ONE row, 56 px tall ([kHlMarketRowHeight]), on the app's card
// surface (AppDecorations.card); with [HlMarketCard.inGroup] a row of a
// grouped list card instead (market_groups.dart), the Investments lists'
// form. Calm since the declutter (founder, 1 November 2026: each row one
// or two things), no hairline between the rows of a group
// ([hlGroupRowDivider] is nothing):
//   * the market's logo (32), round (HlCoinIcon, glyph / letter fallback);
//     a symbol two venues list carries its venue's monogram on the logo;
//   * the market's NAME on one line ("Bitcoin", "Tesla"; the ticker when
//     no name is known). No ticker or "Spot" caption, no "Low liquidity"
//     note and no sparkline: the market page has all of that. Never a max
//     leverage: leverage is blocked in the app, so no row hints at it;
//   * the LIVE price, always in the primary text colour, written short
//     (formatHlListPrice: "$47.91", "$4,128.40", "$2.631", "$0.2051" —
//     four figures, two decimals at least; never the venue's five-figure
//     tick, which is the charts' and the slip's), over the 24h % change
//     as "▲ 0.4%" / "▼ 3.8%" in the up / down colour (no plus or minus
//     sign; "0.0%" when flat, a dash when unknown; nothing on a thinly
//     traded market with no change to show).
//
// Above the default list (Trending), the strip (hl_moving_now_strip.dart)
// shows the hyped names as large cards; the rows keep their own order
// under it.
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
import 'package:kute/providers/hyperliquid_markets_provider.dart'
    show HlMarketDirectory;
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/screens/home/components/action_pill.dart'
    show greenColor, redColor;
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/hyperliquid/market_detail_sheet.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/theme/app_theme.dart';

/// The row's logo.
const double kHlMarketRowIcon = 32;

/// The row's height, in design units.
const double kHlMarketRowHeight = 56;

/// Where a grouped row's text starts (the row's 16 inset, the logo and the
/// 12 gap after it): where a group's hairline would start, were one drawn.
double hlGroupRowIndent() => 16.w + kHlMarketRowIcon.w + 12.w;

/// Between two Investing rows of a group: nothing. The rows' own padding
/// separates them (Robinhood / Public / Coinbase draw no hairlines).
Widget hlGroupRowDivider(BuildContext context, double indent) =>
    const SizedBox.shrink();

/// Browse card for one Hyperliquid market (perp or spot). Consumer-stateful
/// so it can watch this coin's live mid + tick direction and register the
/// coin with the live-prices watch-set on mount.
class HlMarketCard extends ConsumerStatefulWidget {
  final HlMarket market;

  /// Account-scoped callers supply their own navigation. The default
  /// opens the spending account's market detail screen.
  final VoidCallback? onTap;

  /// A row of a grouped list card (Home Activity's group, see
  /// market_groups.dart): no card of its own, the row padding of the
  /// group's rows. The list draws the card and the hairlines.
  final bool inGroup;

  const HlMarketCard(
      {super.key, required this.market, this.onTap, this.inGroup = false});

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
    // Hyperliquid's own app names it, and a token that holds a stock
    // reads as that stock (NVDAX: Nvidia). The ticker when no name is
    // known.
    final name =
        hlFriendlyName(m.underlyingTicker) ?? m.unitAssetName ?? m.coin;
    // Two venues can list a perp under one symbol (ANTH on two builder
    // dexes): the logo then carries the venue's monogram, so the two rows
    // never read the same.
    final shared = HlMarketDirectory.sharesSymbol(m);
    final thin = m.isLowLiquidity;

    return HlListRow(
      inGroup: widget.inGroup,
      onTap: _openDetail,
      // The REAL coin/token logo (category glyph or letter badge on a
      // miss), cut round for this row.
      leading: HlVenueBadged(
        monogram: shared ? HlDexNames.monogramOf(m) : null,
        ring: c.surface,
        child: ClipOval(
          child: HlCoinIcon(
            coin: m.coin,
            wireCoin: m.wireCoin,
            category: m.category,
            iconUrl: m.iconUrl,
            size: kHlMarketRowIcon,
          ),
        ),
      ),
      name: name,
      figure: formatHlListPrice(price, decimalCap: m.pxDecimalCap),
      // No change to show on a thin market: the price stands alone,
      // centred, not over a lone dash.
      change: change != null || !thin
          ? (change == null ? '—' : hlArrowPct(change))
          : null,
      changeColor: changeColor,
    );
  }
}

/// THE INVESTING LIST ROW, drawn on its own (see the file header): the
/// [leading] logo ([kHlMarketRowIcon], already sized and cut round), the
/// [name] alone on one line in the settings-title style, and at the end
/// the [figure] in the same style over the [change] ("▲ 3.4%", 13, in
/// [changeColor]; null: the figure alone). [kHlMarketRowHeight] tall at
/// least, 16 at the sides; with [inGroup] a row of a grouped list card
/// (the list draws the card), else on the app's card surface. Shared by
/// [HlMarketCard] and the Portfolio screen's position rows
/// (position_rows.dart), so the two lists read the same.
class HlListRow extends StatelessWidget {
  const HlListRow({
    super.key,
    required this.leading,
    required this.name,
    required this.figure,
    this.change,
    this.changeColor,
    this.onTap,
    this.onLongPress,
    this.inGroup = false,
    this.nameKey,
    this.figureKey,
    this.changeKey,
  });

  final Widget leading;
  final String name;
  final String figure;
  final String? change;
  final Color? changeColor;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool inGroup;

  /// Keys on the name, the figure and the change (the tests read them).
  final Key? nameKey;
  final Key? figureKey;
  final Key? changeKey;

  @override
  Widget build(BuildContext context) {
    final titleStyle = AppTextStyles.settingsTitle(context);
    final change = this.change;
    // In a group the list draws the card; the row keeps its ink.
    final grouped = inGroup;
    final radius = grouped ? null : BorderRadius.circular(AppRadius.lg);
    return Container(
      decoration: grouped ? null : AppDecorations.card(context),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: radius,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: kHlMarketRowHeight.w),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 6.h),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  leading,
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Text(
                      name,
                      key: nameKey,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle,
                    ),
                  ),
                  SizedBox(width: 12.w),
                  // A fixed minimum width, right-aligned, so the prices
                  // line up down the list; a longer price widens it,
                  // never wraps.
                  ConstrainedBox(
                    constraints: BoxConstraints(minWidth: 84.w),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Always the primary text colour: the digits roll
                        // on a tick, the colour belongs to the change.
                        RollingNumberText(
                          key: figureKey,
                          text: figure,
                          style: titleStyle.copyWith(
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ],
                          ),
                        ),
                        if (change != null) ...[
                          SizedBox(height: 2.h),
                          _ChangeText(
                            key: changeKey,
                            text: change,
                            color: changeColor ??
                                context.colors.textSecondary,
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
      ),
    );
  }
}

/// A 24h change (a fraction) as the row writes it: an arrow glyph for the
/// direction and the unsigned size, "▲ 0.4%" / "▼ 3.8%" (the glyphs the
/// transaction rows and slip tiles already use); "0.0%" alone when flat.
String hlArrowPct(double change) {
  final pct = (change.abs() * 100).toStringAsFixed(1);
  if (change == 0) return '$pct%';
  return '${change > 0 ? '▲' : '▼'} $pct%';
}

/// 24h % change under the price — plain coloured TEXT (marketUp /
/// marketDown via greenColor / redColor), no tinted box: tinted chips are
/// rejected app-wide (solid fills or neutral grey only; coloured text on a
/// neutral surface is fine). [text] arrives from [hlArrowPct] ('▲ 1.2%' /
/// '▼ 0.8%'). Rolls its digits like the position card's PnL line so a
/// 30 s universe refresh ticks instead of snapping.
class _ChangeText extends StatelessWidget {
  final String text;
  final Color color;
  const _ChangeText({super.key, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return RollingNumberText(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: 13.sp,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.1,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// A market's logo with its venue's mark: a small solid ink disc at the
/// lower right holding the venue's first letter, ringed in [ring] (the
/// row's surface) so it lifts off the logo. Neutral, never tinted: it
/// tells two same-symbol rows apart without shouting. Null [monogram]
/// draws the logo alone.
class HlVenueBadged extends StatelessWidget {
  final String? monogram;
  final Color ring;
  final Widget child;

  const HlVenueBadged(
      {super.key, required this.monogram, required this.ring, required this.child});

  @override
  Widget build(BuildContext context) {
    final mark = monogram;
    if (mark == null) return child;
    final c = context.colors;
    final d = 16.sp;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: -3.sp,
          bottom: -3.sp,
          child: Container(
            key: const ValueKey('hl-venue-badge'),
            width: d,
            height: d,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.textPrimary,
              shape: BoxShape.circle,
              border: Border.all(color: ring, width: 1.5),
            ),
            child: Text(
              mark,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                color: c.background,
                fontSize: 8.5.sp,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
