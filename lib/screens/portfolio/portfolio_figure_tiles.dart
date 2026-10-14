// lib/screens/portfolio/portfolio_figure_tiles.dart
//
// The Portfolio's figures as one row of small equal tiles (founder
// requests, October 2026: "the 3 things in the portfolio must be side by
// side, not stretched" and "the open pnl, amount at stake and all that
// should all just be in one row"). The balance breakdown (Dollars,
// Investing, Predictions) and the statistics (open P&L, amount at stake,
// open positions; realised P&L, volume, count) are the same tiles, so the
// two rows read as one design: the position cards' caption over the
// position cards' figure, on the card surface.
//
// The tiles share the row's width equally and take the height of the
// tallest. A row that cannot give each tile [kPortfolioTileMinWidth]
// (more tiles than fit, a narrow screen) scrolls sideways instead: never
// a second row, never a clipped or ellipsised figure. Figures scale down
// to their tile's width (FittedBox), labels wrap.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/screens/polymarket/components/market_card.dart'
    show polyCardFigureStyle;
import 'package:kute/screens/shared/portfolio_position_card.dart'
    show portfolioCardCaptionStyle;
import 'package:kute/theme/app_theme.dart';

/// The narrowest a tile gets before the row scrolls instead.
double get kPortfolioTileMinWidth => 96.w;

/// The gap between two tiles.
double get kPortfolioTileGap => 8.w;

/// The tiles side by side, equal widths and heights (see the file header).
class PortfolioTileRow extends StatelessWidget {
  const PortfolioTileRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, constraints) {
      final gap = kPortfolioTileGap;
      final n = children.length;
      final share = (constraints.maxWidth - gap * (n - 1)) / n;
      final fits = share >= kPortfolioTileMinWidth;
      final width = fits ? share : kPortfolioTileMinWidth;
      final row = IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < n; i++) ...[
              if (i > 0) SizedBox(width: gap),
              SizedBox(width: width, child: children[i]),
            ],
          ],
        ),
      );
      if (fits) return row;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: row,
      );
    });
  }
}

/// One tile: the card surface (or none, inside a card of its own) around
/// [children], top-left aligned.
class PortfolioTile extends StatelessWidget {
  const PortfolioTile({
    super.key,
    required this.children,
    this.boxed = true,
  });

  final List<Widget> children;

  /// On the card surface; false inside a card that already is one.
  final bool boxed;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: EdgeInsets.all(boxed ? 12.w : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
    if (!boxed) return content;
    return DecoratedBox(
        decoration: AppDecorations.card(context), child: content);
  }
}

/// A tile's label: the position cards' caption, wrapping when long.
class PortfolioTileLabel extends StatelessWidget {
  const PortfolioTileLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: portfolioCardCaptionStyle(context.colors));
}

/// A tile's figure in the position cards' figure style, scaled down as
/// one block to the tile's width, never wrapped or cut. [child] replaces
/// the plain text (a rolling figure, a shimmer over it).
class PortfolioTileFigure extends StatelessWidget {
  const PortfolioTileFigure(this.text, {super.key, this.color, this.child});

  final String text;
  final Color? color;
  final Widget? child;

  /// The figure's style in [color] (the primary text colour by default).
  static TextStyle styleOf(BuildContext context, [Color? color]) =>
      polyCardFigureStyle(color ?? context.colors.textPrimary);

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: child ?? Text(text, style: styleOf(context, color)),
      );
}

/// A label over its figure, the unit both rows are made of.
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
