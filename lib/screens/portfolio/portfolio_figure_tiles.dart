// lib/screens/portfolio/portfolio_figure_tiles.dart
//
// The Portfolio's figures as one low row (founder requests, October 2026:
// "the 3 things in the portfolio must be side by side, not stretched",
// "the open pnl, amount at stake and all that should all just be in one
// row", then "these cards on the top are too much elongated ... maybe
// smaller numbers"). The balance breakdown (Dollars, Investing,
// Predictions) and the statistics (open P&L, amount at stake, open
// positions; realised P&L, volume, count) are the same row, so the two
// read as one design.
//
// One card ([AppDecorations.card], the position cards' surface) split
// into equal columns by hairlines (the market Stats block's 0.5 pt
// `borderSubtle` rule, hl_market_stats.dart), each column a small caption
// over a secondary-size figure in tabular digits. Inside a card that is
// already one (a Ledger's Statistics) the row draws no card of its own,
// only the columns and hairlines.
//
// The columns share the row's width equally and take the height of the
// tallest. A row that cannot give each column [kPortfolioTileMinWidth]
// (more columns than fit, a narrow screen) scrolls sideways inside its
// card instead: never a second row, never a clipped or ellipsised figure.
// Figures and captions scale down to their column's width (FittedBox),
// never wrapped.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/theme/app_theme.dart';

/// The narrowest a column gets before the row scrolls instead.
double get kPortfolioTileMinWidth => 88.w;

/// A column's inner padding, sideways and up and down.
double get kPortfolioTilePadX => 10.w;
double get kPortfolioTilePadY => 12.h;

/// A caption: what a figure is, a column's secondary line.
TextStyle portfolioTileCaptionStyle(AppColorsExtension c) => TextStyle(
      color: c.textTertiary,
      fontSize: 12.sp,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.1,
      height: 1.25,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

/// The columns side by side in one card (or none, [boxed] false), equal
/// widths and heights, hairlines between them (see the file header).
class PortfolioTileRow extends StatelessWidget {
  const PortfolioTileRow({
    super.key,
    required this.children,
    this.boxed = true,
  });

  final List<Widget> children;

  /// On the card surface; false inside a card that already is one.
  final bool boxed;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    final n = children.length;
    final padX = kPortfolioTilePadX;
    final padY = boxed ? kPortfolioTilePadY : 0.0;
    // Inside a card the outer columns sit on the card's own padding.
    EdgeInsets padOf(int i) => EdgeInsets.fromLTRB(!boxed && i == 0 ? 0 : padX,
        padY, !boxed && i == n - 1 ? 0 : padX, padY);
    Widget hairline() => Container(
          width: 0.5,
          margin: EdgeInsets.symmetric(vertical: boxed ? 12.h : 2.h),
          color: context.isDark ? c.border : c.borderSubtle,
        );

    final row = LayoutBuilder(builder: (context, constraints) {
      final fits = constraints.maxWidth / n >= kPortfolioTileMinWidth;
      Widget cell(int i) => Padding(padding: padOf(i), child: children[i]);
      if (fits) {
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < n; i++) ...[
                if (i > 0) hairline(),
                Expanded(child: cell(i)),
              ],
            ],
          ),
        );
      }
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < n; i++) ...[
                if (i > 0) hairline(),
                SizedBox(width: kPortfolioTileMinWidth, child: cell(i)),
              ],
            ],
          ),
        ),
      );
    });
    if (!boxed) return row;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: AppDecorations.card(context),
      child: row,
    );
  }
}

/// One column: [children] stacked, top-left aligned. The row gives it its
/// padding and the hairline beside it.
class PortfolioTile extends StatelessWidget {
  const PortfolioTile({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: children,
      );
}

/// A one-line text scaled down to its column's width, never wrapped or
/// cut.
class PortfolioTileFit extends StatelessWidget {
  const PortfolioTileFit({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: child,
      );
}

/// A column's caption ([portfolioTileCaptionStyle]), on one line.
class PortfolioTileLabel extends StatelessWidget {
  const PortfolioTileLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => PortfolioTileFit(
      child: Text(text,
          maxLines: 1,
          softWrap: false,
          style: portfolioTileCaptionStyle(context.colors)));
}

/// A column's figure at the app's secondary figure size (16, semibold,
/// tabular), scaled down as one block to the column's width, never
/// wrapped or cut. [child] replaces the plain text (a rolling figure, a
/// shimmer over it).
class PortfolioTileFigure extends StatelessWidget {
  const PortfolioTileFigure(this.text, {super.key, this.color, this.child});

  final String text;
  final Color? color;
  final Widget? child;

  /// The figure's style in [color] (the primary text colour by default).
  static TextStyle styleOf(BuildContext context, [Color? color]) => TextStyle(
        color: color ?? context.colors.textPrimary,
        fontSize: 16.sp,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        height: 1.2,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  @override
  Widget build(BuildContext context) => PortfolioTileFit(
      child: child ??
          Text(text,
              maxLines: 1, softWrap: false, style: styleOf(context, color)));
}

/// A caption over its figure, the statistics' column.
class PortfolioTileStat extends StatelessWidget {
  const PortfolioTileStat({
    super.key,
    required this.label,
    required this.figure,
  });

  final String label;
  final Widget figure;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          PortfolioTileLabel(label),
          SizedBox(height: 4.h),
          figure,
        ],
      );
}
