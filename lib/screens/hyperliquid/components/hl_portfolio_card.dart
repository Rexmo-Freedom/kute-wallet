// An Investing holding or resting order on the Portfolio (the spending
// wallet's and a Ledger's), in the Investing list card's language on the
// portfolio cards' shared frame:
//   * the market's logo, round (HlCoinIcon);
//   * the market's NAME over one short caption that says what is held
//     ("Short 1x · Liq 106% away", "UBTC · Spot", "TSLA · Buy"); on a
//     position the liquidation's distance alone takes a colour as the mark
//     closes in;
//   * on the right the money in a position (what closing it now gives
//     back) with the profit or loss under it (PortfolioCardValue), or an
//     order's price;
//   * under them, quiet caption lines only where a row needs them (a
//     holding's size, an order's price and what is left of it).
//
// Display only: every figure and every action is the caller's.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/hyperliquid/components/hl_liquidation_distance.dart';
import 'package:kute/screens/shared/portfolio_position_card.dart';
import 'package:kute/theme/app_theme.dart';

class HlPortfolioCard extends StatelessWidget {
  /// The market's display symbol and wire coin, for its logo.
  final String coin;
  final String? wireCoin;
  final String? iconUrl;
  final String? category;

  /// What the market is called ("Bitcoin"; the ticker when no name is
  /// known).
  final String name;

  /// What is held ("Short 1x", "UBTC · Spot", "TSLA · Buy").
  final String caption;

  /// The right-hand figure (the value with its P&L, an order's price);
  /// held to under half the card, scaling down past that. Null when the
  /// row has no number to lead with.
  final Widget? trailing;

  /// Caption lines under the row.
  final List<String> footer;

  /// A position's liquidation price: how far the [mark] is from it ends
  /// the caption ("Short 1x · Liq 106% away"), the distance alone in the
  /// warning / down colour as it closes in ([hlLiqDistanceColor]). The
  /// price itself is on the position screen.
  final double? liquidation;
  final double? mark;

  /// Anything the row adds under its captions (an order's fill bar).
  final Widget? below;
  final VoidCallback? onTap;

  /// The row's own button (an order's Cancel), under the content.
  final Widget? action;

  /// The gap under the card; a list that spaces its own rows passes zero.
  final EdgeInsetsGeometry? margin;

  const HlPortfolioCard({
    super.key,
    required this.coin,
    this.wireCoin,
    this.iconUrl,
    this.category,
    required this.name,
    required this.caption,
    this.trailing,
    this.footer = const [],
    this.liquidation,
    this.mark,
    this.below,
    this.onTap,
    this.action,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lines = footer.where((s) => s.isNotEmpty).toList();
    final distance = mark == null
        ? null
        : hlLiquidationDistance(mark: mark!, liq: liquidation);
    final captionStyle = TextStyle(
      color: c.textSecondary,
      fontSize: 13.sp,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.1,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return PortfolioCardFrame(
      onTap: onTap,
      action: action,
      margin: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          LayoutBuilder(
            builder: (context, box) => Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // The REAL coin/token logo (category glyph or letter badge
                // on a miss), cut round as on the list card.
                ClipOval(
                  child: HlCoinIcon(
                    coin: coin,
                    wireCoin: wireCoin,
                    iconUrl: iconUrl,
                    category: category,
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
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.settingsTitle(context),
                      ),
                      SizedBox(height: 2.h),
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(text: caption),
                          if (distance != null) ...[
                            TextSpan(
                                text: ' · ${context.l10n.hlChartLiq} '),
                            TextSpan(
                              text: context.l10n
                                  .hlLiqAway(formatHlLiqDistance(distance)),
                              style: TextStyle(
                                  color: hlLiqDistanceColor(distance, c)),
                            ),
                          ],
                        ]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: captionStyle,
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  SizedBox(width: 12.w),
                  ConstrainedBox(
                    constraints:
                        BoxConstraints(maxWidth: box.maxWidth * 0.45),
                    child: trailing,
                  ),
                ],
              ],
            ),
          ),
          for (var i = 0; i < lines.length; i++) ...[
            SizedBox(height: i == 0 ? 12.h : 4.h),
            Text(
              lines[i],
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: portfolioCardCaptionStyle(c),
            ),
          ],
          if (below != null) below!,
        ],
      ),
    );
  }
}
