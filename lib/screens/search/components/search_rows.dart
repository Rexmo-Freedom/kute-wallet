// lib/screens/search/components/search_rows.dart
//
// THE SAL SHEET'S PARTS (founder, 31 October 2026: "it must be and look
// much better", "still too dense", then the tile idea judged "2019
// fintech"): a FLAT, typographic search. No cards, no boxes, no
// hairlines between rows: everything sits on the sheet's own surface and
// is told apart by type and air. One vocabulary for the home (Recent,
// Moving now, Trending predictions) and the results while typing
// (Predictions, Investing, Transactions).
//
//   * a BLOCK is a 13 sp w600 textPrimary title ([SearchBlockHeader]) with
//     a small textSecondary action at its end when it has one ("Clear",
//     "See all ›"), 12 px over its rows; blocks sit 28 apart
//     ([kSearchBlockGap]);
//   * ROWS stand 14 px apart with nothing drawn between them
//     ([SearchRowList], [kSearchRowGap]);
//   * a ROW is 56 px at least ([SearchListRow]): a 36 logo, a 16 w500
//     title (two lines in the results, one on the home), a 13
//     textSecondary line under it when there is one, and the figure at
//     the right in 16 w600 tabular; the market rows are this row with the
//     venue's own logo and figures: a prediction keeps its chance gauge
//     ([SearchPredictionRow], [SearchChanceGauge]), an Investing market
//     its 48 by 20 sparkline ([SearchInvestingRow]);
//   * "MOVING NOW" is a two-column grid of six flat rows, the ticker and
//     the day's move ([SearchMoverGrid], [SearchMoverRow]);
//   * the EMPTY state is Sal's `sad` face at 40 over one small centred
//     line ([SearchEmptyState]).
//
// Every row presses on the app's spring (KutePressable) and announces
// itself as one button.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart' show HlMarket, HlMarketKind;
import 'package:kute/models/polymarket_model.dart' show PolymarketEvent;
import 'package:kute/providers/hyperliquid_search_provider.dart'
    show HlMarketSearchResult;
import 'package:kute/providers/hyperliquid_sparkline_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show PolymarketPosition;
import 'package:kute/screens/hyperliquid/components/hl_charts.dart'
    show HlLineSparkline;
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart'
    show formatHlPrice, formatHlPct, formatHlUsd;
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/screens/shared/kute_dog_scenes.dart' show KuteDogGlance;
import 'package:kute/screens/shared/kute_motion.dart' show KutePressable;
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/services/hyperliquid/hl_sparkline_cache.dart'
    show hlSparklineWithLivePrice;
import 'package:kute/theme/app_theme.dart';

/// The sheet's gutters, the space between its blocks and between rows.
const double kSearchSheetGutter = 16;
const double kSearchBlockGap = 28;
const double kSearchRowGap = 14;

/// A row's least height, and its logo's side.
const double kSearchRowHeight = 56;
const double kSearchRowLogo = 36;

/// The sheet's height as a share of the screen, and the row at its top
/// with the drag handle and the close X (the composer line sits right
/// under it; search_morph.dart lands the pill there).
const double kSearchSheetFraction = 0.96;
const double kSearchSheetHandleRow = 56;

/// The space between the two columns of the "Moving now" grid.
const double kSearchGridGap = 12;

/// A block's title: 13 sp w600 textPrimary, with [trailing] (a small text
/// action) at the row's end. 12 px over its rows.
class SearchBlockHeader extends StatelessWidget {
  const SearchBlockHeader({super.key, required this.text, this.trailing});

  final String text;
  final Widget? trailing;

  /// The title's style.
  static TextStyle style(BuildContext context) => TextStyle(
        color: context.colors.textPrimary,
        fontSize: 13.sp,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      );

  /// The action's style: the title's size in textSecondary, not bold.
  static TextStyle actionStyle(BuildContext context) => TextStyle(
        color: context.colors.textSecondary,
        fontSize: 13.sp,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.2,
      );

  /// The space between the title's line and the rows, 12.
  static double gapBelow(BuildContext context) => 12.h;

  @override
  Widget build(BuildContext context) => Padding(
        // 12 under the line: the header's own padding, or the action's
        // (SearchBlockAction pads its label by the same 12 above and
        // below, and the row is as tall as the action, the two labels
        // centred on one line).
        padding:
            EdgeInsets.only(bottom: trailing == null ? gapBelow(context) : 0),
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

/// A header's trailing action ("Clear", "See all ›"): small textSecondary,
/// a chevron after it when [chevron].
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
            // A ~40 pt target on a 13 sp word, the 12 below doubling as the
            // header's gap to its rows (SearchBlockHeader).
            padding: EdgeInsets.symmetric(
                horizontal: 4.w, vertical: SearchBlockHeader.gapBelow(context)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: SearchBlockHeader.actionStyle(context)),
                if (chevron)
                  Icon(Icons.chevron_right_rounded,
                      size: 16.sp, color: c.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A block's rows, 14 px of air between them and nothing drawn.
class SearchRowList extends StatelessWidget {
  const SearchRowList({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: kSearchRowGap.h,
        children: children,
      );
}

/// A row of the sheet: [leading] (36), [title] on up to [titleLines]
/// lines, [subtitle] under it, [trailing] at the end. At least 56 tall,
/// flat on the sheet (no inset of its own: the list wears the gutters).
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
    this.padding,
  });

  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final int titleLines;
  final VoidCallback onTap;
  final String? semanticLabel;

  /// The row's inset; none by default.
  final EdgeInsetsGeometry? padding;

  /// The title's style (16 w500) and the line under it (13 textSecondary).
  static TextStyle titleStyle(BuildContext context) => TextStyle(
        color: context.colors.textPrimary,
        fontSize: 16.sp,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.3,
        height: 1.2,
      );
  static TextStyle subtitleStyle(BuildContext context) => TextStyle(
        color: context.colors.textSecondary,
        fontSize: 13.sp,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.1,
      );

  /// A figure at a row's end: 16 w600, tabular.
  static TextStyle figureStyle(BuildContext context, {Color? color}) =>
      TextStyle(
        color: color ?? context.colors.textPrimary,
        fontSize: 16.sp,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
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
              padding: padding ?? EdgeInsets.zero,
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

/// An event's picture at a row's size, or a blank square.
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

/// The chance gauge the Predictions list's rows wear (market_card.dart):
/// a half ring, 40 by 24 with a 4 stroke, its track in the border colour
/// and the chance's share of it in the primary text colour (neutral: a
/// chance is not good or bad).
class SearchChanceGauge extends StatelessWidget {
  const SearchChanceGauge({super.key, required this.chance});

  /// 0 to 1.
  final double chance;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      width: 40.w,
      height: 24.h,
      child: CustomPaint(
        painter: _HalfRingPainter(
          fraction: chance,
          track: c.border,
          fill: c.textPrimary,
          stroke: 4,
        ),
      ),
    );
  }
}

/// The gauge's ring: the upper half of a circle, open at the bottom, the
/// track whole and the fill from the left end for [fraction] of it.
class _HalfRingPainter extends CustomPainter {
  final double fraction;
  final Color track;
  final Color fill;
  final double stroke;
  const _HalfRingPainter({
    required this.fraction,
    required this.track,
    required this.fill,
    required this.stroke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final r = (size.width - stroke) / 2;
    final rect = Rect.fromCircle(
        center: Offset(size.width / 2, size.height - stroke / 2), radius: r);
    Paint paint(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, math.pi, math.pi, false, paint(track));
    final sweep = math.pi * fraction.clamp(0.0, 1.0);
    if (sweep > 0) canvas.drawArc(rect, math.pi, sweep, false, paint(fill));
  }

  @override
  bool shouldRepaint(covariant _HalfRingPainter old) =>
      old.fraction != fraction ||
      old.track != track ||
      old.fill != fill ||
      old.stroke != stroke;
}

/// A prediction market: its picture, the question on [titleLines] lines
/// (two in the results, one on the home), the chance gauge and the chance
/// in 16 w600 at the right.
class SearchPredictionRow extends StatelessWidget {
  const SearchPredictionRow({
    super.key,
    required this.event,
    required this.onTap,
    this.titleLines = 2,
    this.padding,
  });

  final PolymarketEvent event;
  final VoidCallback onTap;
  final int titleLines;

  /// The row's inset ([SearchListRow.padding]).
  final EdgeInsetsGeometry? padding;

  /// The leading chance, 0 to 1 (null without prices).
  static double? chanceFractionOf(PolymarketEvent event) {
    if (event.outcomes.isEmpty) return null;
    return event.outcomes.map((o) => o.price).reduce(math.max);
  }

  /// The leading chance ("62%"), null without prices.
  static String? chanceOf(PolymarketEvent event) {
    final fraction = chanceFractionOf(event);
    return fraction == null ? null : '${(fraction * 100).round()}%';
  }

  @override
  Widget build(BuildContext context) {
    final fraction = chanceFractionOf(event);
    final chance = chanceOf(event);
    return SearchListRow(
      leading: searchEventLogo(context, event.imageUrl),
      title: event.displayTitle,
      titleLines: titleLines,
      padding: padding,
      trailing: fraction == null || chance == null
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SearchChanceGauge(chance: fraction),
                SizedBox(width: 8.w),
                Text(chance, style: SearchListRow.figureStyle(context)),
              ],
            ),
      semanticLabel: chance == null
          ? event.displayTitle
          : '${event.displayTitle}, $chance',
      onTap: onTap,
    );
  }
}

/// An Investing market from the search: the coin's logo, its name over
/// its ticker ("TSLA · Spot" for a spot token), the 48 by 20 sparkline
/// the Investing cards draw (hyperliquid_sparkline_provider.dart) and,
/// at the right, the price in 16 w600 over the day's move.
class SearchInvestingRow extends ConsumerWidget {
  const SearchInvestingRow(
      {super.key, required this.result, required this.onTap});

  final HlMarketSearchResult result;
  final VoidCallback onTap;

  /// The sparkline's size.
  static const double sparklineWidth = 48;
  static const double sparklineHeight = 20;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final r = result;
    final name = (r.name?.trim().isNotEmpty ?? false) ? r.name!.trim() : r.coin;
    final spot = r.kind == HlMarketKind.spot;
    final ticker = [
      if (name != r.coin) r.coin,
      if (spot) context.l10n.investingSpot,
    ].join(' · ');
    final change = r.dayChangePct;
    final changeColor = change == 0
        ? c.textSecondary
        : (change > 0 ? AppColors.marketUp : AppColors.marketDown);
    final series = ref.watch(hyperliquidSparklineProvider(r.wireCoin));
    final closes = series == null
        ? const <double>[]
        : hlSparklineWithLivePrice(series.closes, r.markPx);
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
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The line alone, coloured by the day's move; its place is kept
          // while the series loads.
          HlLineSparkline(
            closes: closes,
            width: sparklineWidth,
            height: sparklineHeight,
            upColor: change >= 0 ? changeColor : AppColors.marketUp,
            downColor: change >= 0 ? AppColors.marketDown : changeColor,
            baseline: false,
          ),
          SizedBox(width: 12.w),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatHlPrice(r.markPx, decimalCap: r.pxDecimalCap),
                  style: SearchListRow.figureStyle(context)),
              SizedBox(height: 2.h),
              Text(formatHlPct(change),
                  style: SearchListRow.subtitleStyle(context).copyWith(
                      color: changeColor, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// One of the person's own prediction positions: the market's picture,
/// its question, "Your position · Yes" under it, the value in 16 w600
/// over the profit or loss (or "Settled") at the right.
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
    final pnlColor = pnl == 0
        ? c.textSecondary
        : (pnl > 0 ? AppColors.marketUp : AppColors.marketDown);
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

/// A "Moving now" row, flat: the logo at 36, the ticker (16 w500), the
/// day's move in 16 w600 coloured at the right. 56 tall, half the sheet
/// wide in the grid.
class SearchMoverRow extends StatelessWidget {
  const SearchMoverRow({super.key, required this.market, required this.onTap});

  final HlMarket market;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final change = market.markPx / market.prevDayPx - 1;
    final move = formatHlPct(change);
    return SearchListRow(
      leading: HlCoinIcon(
          coin: market.coin,
          wireCoin: market.wireCoin,
          iconUrl: market.iconUrl,
          category: market.category,
          size: kSearchRowLogo),
      title: market.coin,
      titleLines: 1,
      trailing: Text(
        move,
        style: SearchListRow.figureStyle(context,
            color: change >= 0 ? AppColors.marketUp : AppColors.marketDown),
      ),
      semanticLabel: '${market.coin}, $move',
      onTap: onTap,
    );
  }
}

/// "Moving now": [markets] (six at most) in two columns of flat rows, 14
/// between the grid's rows and 12 between its columns; an odd last row
/// leaves its second cell empty.
class SearchMoverGrid extends StatelessWidget {
  const SearchMoverGrid(
      {super.key, required this.markets, required this.onTap});

  final List<HlMarket> markets;
  final void Function(HlMarket market) onTap;

  /// How many the grid shows.
  static const int count = 6;

  @override
  Widget build(BuildContext context) {
    final shown = markets.take(count).toList();
    final rows = <Widget>[];
    for (var i = 0; i < shown.length; i += 2) {
      rows.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
              child: SearchMoverRow(
                  market: shown[i], onTap: () => onTap(shown[i]))),
          SizedBox(width: kSearchGridGap.w),
          Expanded(
            child: i + 1 < shown.length
                ? SearchMoverRow(
                    market: shown[i + 1], onTap: () => onTap(shown[i + 1]))
                : const SizedBox.shrink(),
          ),
        ],
      ));
    }
    return SearchRowList(children: rows);
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
