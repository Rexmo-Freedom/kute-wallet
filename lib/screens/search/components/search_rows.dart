// lib/screens/search/components/search_rows.dart
//
// THE SAL SHEET'S PARTS (founder, 31 October 2026: "it must be and look
// much better"): one vocabulary for everything the sheet lists, whether
// it is the home (Recent, Moving now, Trending predictions) or the
// results while typing (Investing, Predictions, Transactions).
//
//   * a BLOCK is a 12 sp textSecondary header, with a trailing action when
//     it has one ("Clear", "See all ›"), over ONE soft card
//     ([SearchBlockHeader], [SearchSheetCard]): the card is surfaceLight
//     on the sheet's surface at the lists' 16 corner, a hairline between
//     its rows, 12 px padding where it holds chips instead of rows;
//   * a ROW is 44 px at least, a 32 logo, a 15 w500 title on up to two
//     lines, a 12 textSecondary line under it when there is one, and the
//     figure at the right in w600 ([SearchListRow]); the market rows
//     ([SearchPredictionRow], [SearchInvestingRow], [SearchPositionRow])
//     are this row with the venue's own logo and figures;
//   * a CHIP in "Moving now" is a 36 px surfaceElevated pill: the logo at
//     20, the ticker w600, the day's move coloured ([SearchMoverChip]);
//   * the EMPTY state is Sal's `sad` face at 40 over one small centred
//     line ([SearchEmptyState]).
//
// Every row presses on the app's spring (KutePressable) and announces
// itself as one button.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart' show HlMarket, HlMarketKind;
import 'package:kute/models/polymarket_model.dart' show PolymarketEvent;
import 'package:kute/providers/hyperliquid_search_provider.dart'
    show HlMarketSearchResult;
import 'package:kute/providers/polymarket_browse_provider.dart'
    show PolymarketPosition;
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart'
    show formatHlPrice, formatHlPct, formatHlUsd;
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/screens/shared/kute_dog_scenes.dart' show KuteDogGlance;
import 'package:kute/screens/shared/kute_motion.dart' show KutePressable;
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/theme/app_theme.dart';

/// The sheet's gutters and the space between its blocks.
const double kSearchSheetGutter = 16;
const double kSearchBlockGap = 20;

/// A row's least height, and its logo's side.
const double kSearchRowHeight = 44;
const double kSearchRowLogo = 32;

/// A block's header: 12 sp textSecondary, with [trailing] (a small text
/// action) at the row's end. Sits 8 px over its card.
class SearchBlockHeader extends StatelessWidget {
  const SearchBlockHeader({super.key, required this.text, this.trailing});

  final String text;
  final Widget? trailing;

  /// The header's text style, shared with its trailing action.
  static TextStyle style(BuildContext context) => TextStyle(
        color: context.colors.textSecondary,
        fontSize: 12.sp,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
      );

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(left: 4.w, right: 4.w, bottom: 8.h),
        child: Row(
          children: [
            Expanded(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style(context)),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

/// A header's trailing action ("Clear", "See all ›"): the header's own
/// style in textPrimary, a chevron after it when [chevron].
class SearchBlockAction extends StatelessWidget {
  const SearchBlockAction(
      {super.key,
      required this.label,
      required this.onTap,
      this.chevron = false});

  final String label;
  final VoidCallback onTap;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: label,
      child: KutePressable(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Padding(
            // A 44 pt target on a 12 sp word.
            padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 10.h),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: SearchBlockHeader.style(context)
                        .copyWith(color: c.textPrimary)),
                if (chevron)
                  Icon(Icons.chevron_right_rounded,
                      size: 16.sp, color: c.textPrimary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The one soft card of a block: its [children] stacked with a hairline
/// between them, inset to the title's start ([dividerInset]); [padding]
/// instead for a card that holds chips.
class SearchSheetCard extends StatelessWidget {
  const SearchSheetCard({
    super.key,
    required this.children,
    this.padding,
    this.dividerInset,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry? padding;
  final double? dividerInset;

  /// The card's surface, shared by the preview card of a context screen.
  static BoxDecoration decoration(BuildContext context) {
    final c = context.colors;
    return AppDecorations.card(context,
        color: c.surfaceLight, borderColor: c.borderSubtle);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final inset = dividerInset ?? (12.w + kSearchRowLogo + 12.w);
    return Container(
      decoration: decoration(context),
      clipBehavior: Clip.antiAlias,
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, child) in children.indexed) ...[
            if (i > 0 && padding == null)
              Padding(
                padding: EdgeInsets.only(left: inset),
                child: Container(height: 0.5, color: c.borderSubtle),
              ),
            child,
          ],
        ],
      ),
    );
  }
}

/// A row of the sheet: [leading] (32), [title] on up to [titleLines]
/// lines, [subtitle] under it, [trailing] at the end. At least 44 tall.
class SearchListRow extends StatelessWidget {
  const SearchListRow({
    super.key,
    required this.title,
    required this.onTap,
    this.leading,
    this.subtitle,
    this.trailing,
    this.titleLines = 2,
    this.semanticLabel,
  });

  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final int titleLines;
  final VoidCallback onTap;
  final String? semanticLabel;

  /// The title's style (15 w500) and the line under it (12 textSecondary).
  static TextStyle titleStyle(BuildContext context) => TextStyle(
        color: context.colors.textPrimary,
        fontSize: 15.sp,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.2,
        height: 1.25,
      );
  static TextStyle subtitleStyle(BuildContext context) => TextStyle(
        color: context.colors.textSecondary,
        fontSize: 12.sp,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.1,
      );

  /// A figure at a row's end: 15 w600, tabular.
  static TextStyle figureStyle(BuildContext context, {Color? color}) =>
      TextStyle(
        color: color ?? context.colors.textPrimary,
        fontSize: 15.sp,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel ?? (subtitle == null ? title : '$title, $subtitle'),
      excludeSemantics: semanticLabel != null,
      child: KutePressable(
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: kSearchRowHeight),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
              child: Row(
                children: [
                  if (leading != null) ...[
                    SizedBox(
                        width: kSearchRowLogo,
                        height: kSearchRowLogo,
                        child: Center(child: leading)),
                    SizedBox(width: 12.w),
                  ],
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            maxLines: titleLines,
                            overflow: TextOverflow.ellipsis,
                            style: titleStyle(context)),
                        if (subtitle != null && subtitle!.isNotEmpty) ...[
                          SizedBox(height: 2.h),
                          Text(subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: subtitleStyle(context)),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    SizedBox(width: 12.w),
                    trailing!,
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

/// An event's picture at a row's size, or the card's blank square.
Widget searchEventLogo(BuildContext context, String? imageUrl,
    {double size = kSearchRowLogo}) {
  if (imageUrl != null && imageUrl.isNotEmpty) {
    return PolyCrestImage(url: imageUrl, size: size, radius: size / 4);
  }
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
        color: context.colors.surfaceElevated,
        borderRadius: BorderRadius.circular(size / 4)),
  );
}

/// A prediction market: its picture, the question on two lines, the
/// leading chance in w600 at the right.
class SearchPredictionRow extends StatelessWidget {
  const SearchPredictionRow(
      {super.key, required this.event, required this.onTap});

  final PolymarketEvent event;
  final VoidCallback onTap;

  /// The leading chance ("62%"), null without prices.
  static String? chanceOf(PolymarketEvent event) {
    if (event.outcomes.isEmpty) return null;
    final price = event.outcomes.map((o) => o.price).reduce(math.max);
    return '${(price * 100).round()}%';
  }

  @override
  Widget build(BuildContext context) {
    final chance = chanceOf(event);
    return SearchListRow(
      leading: searchEventLogo(context, event.imageUrl),
      title: event.title,
      trailing: chance == null
          ? null
          : Text(chance, style: SearchListRow.figureStyle(context)),
      semanticLabel: chance == null ? event.title : '${event.title}, $chance',
      onTap: onTap,
    );
  }
}

/// An Investing market from the search: the coin's logo, its name over
/// its ticker ("TSLA · Spot" for a spot token), the price in w600 over
/// the day's move at the right.
class SearchInvestingRow extends StatelessWidget {
  const SearchInvestingRow(
      {super.key, required this.result, required this.onTap});

  final HlMarketSearchResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = result;
    final name = (r.name?.trim().isNotEmpty ?? false) ? r.name!.trim() : r.coin;
    final spot = r.kind == HlMarketKind.spot;
    final ticker = [
      if (name != r.coin) r.coin,
      if (spot) context.l10n.investingSpot,
    ].join(' · ');
    final change = r.dayChangePct;
    final changeColor =
        change == 0 ? c.textSecondary : (change > 0 ? AppColors.marketUp : AppColors.marketDown);
    return SearchListRow(
      leading: HlCoinIcon(
          coin: r.coin,
          wireCoin: r.wireCoin,
          iconUrl: r.iconUrl,
          category: r.category,
          size: kSearchRowLogo),
      title: name,
      titleLines: 1,
      subtitle: ticker.isEmpty ? null : ticker,
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(formatHlPrice(r.markPx, decimalCap: r.pxDecimalCap),
              style: SearchListRow.figureStyle(context)),
          SizedBox(height: 2.h),
          Text(formatHlPct(change),
              style: SearchListRow.subtitleStyle(context)
                  .copyWith(color: changeColor, fontWeight: FontWeight.w600)),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// One of the person's own prediction positions: the market's picture,
/// its question, "Your position · Yes" under it, the value in w600 over
/// the profit or loss (or "Settled") at the right.
class SearchPositionRow extends StatelessWidget {
  const SearchPositionRow({
    super.key,
    required this.position,
    required this.price,
    required this.onTap,
  });

  final PolymarketPosition position;

  /// The held outcome's price now (live when the feed has it).
  final double price;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final p = position;
    final value = p.size * price;
    final pnl = (price - p.avgPrice) * p.size;
    final pnlColor =
        pnl == 0 ? c.textSecondary : (pnl > 0 ? AppColors.marketUp : AppColors.marketDown);
    return SearchListRow(
      leading: searchEventLogo(context, p.marketImage),
      title: p.marketQuestion,
      subtitle: l10n.searchYourPosition(p.outcome),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(formatHlUsd(value), style: SearchListRow.figureStyle(context)),
          SizedBox(height: 2.h),
          Text(
            p.isResolved
                ? l10n.activitySettled
                : '${pnl >= 0 ? '+' : '−'}${formatHlUsd(pnl.abs())}',
            style: SearchListRow.subtitleStyle(context).copyWith(
                color: p.isResolved ? c.textSecondary : pnlColor,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// A "Moving now" chip: a 36 px surfaceElevated pill with the logo at 20,
/// the ticker in w600 and the day's move coloured.
class SearchMoverChip extends StatelessWidget {
  const SearchMoverChip({super.key, required this.market, required this.onTap});

  final HlMarket market;
  final VoidCallback onTap;

  static const double height = 36;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final change = market.markPx / market.prevDayPx - 1;
    final up = change >= 0;
    final pct = (change.abs() * 100).toStringAsFixed(1);
    return Semantics(
      button: true,
      label: '${market.coin}, ${up ? '+' : '-'}$pct%',
      excludeSemantics: true,
      child: KutePressable(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Container(
            height: height,
            padding: EdgeInsets.symmetric(horizontal: 10.w),
            decoration: BoxDecoration(
              color: c.surfaceElevated,
              borderRadius: BorderRadius.circular(height / 2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                HlCoinIcon(
                    coin: market.coin,
                    wireCoin: market.wireCoin,
                    iconUrl: market.iconUrl,
                    category: market.category,
                    size: 20),
                SizedBox(width: 6.w),
                Text(
                  market.coin,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                  ),
                ),
                SizedBox(width: 6.w),
                Text(
                  '${up ? '▲' : '▼'} $pct%',
                  style: TextStyle(
                    color: up ? AppColors.marketUp : AppColors.marketDown,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
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

/// Nothing found: Sal's `sad` face at 40 over one small centred line.
class SearchEmptyState extends StatelessWidget {
  const SearchEmptyState({super.key, required this.text, this.sad = true});

  final String text;

  /// Sal's face over the line; false for a line alone ("Searching…").
  final bool sad;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 8.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (sad) ...[
              SalSprite(
                clip: 'sad',
                size: 40,
                fallback: KuteDogGlance(size: 40, color: c.textTertiary),
              ),
              SizedBox(height: 10.h),
            ],
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 13.sp,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
