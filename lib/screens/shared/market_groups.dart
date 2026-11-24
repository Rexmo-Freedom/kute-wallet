// The Investments market lists, grouped the way Home's Activity is (founder
// decision, October 2026, "style A"): runs of one-line markets share ONE
// card — Home's own grouped card (PremiumGroupContainer: surface, 20 radius,
// soft shadow), rows split by its inset hairline — while a market that
// needs a card of its own (a Predictions event with many outcomes, a game)
// stays its own card and breaks the run: group → card → group.
//
// Investing groups every market; Predictions groups its plain Yes/No
// markets. The lists use the sliver form (lazy: a category can hold a few
// hundred markets, each subscribed to live prices); the Ledger tab's short
// sections use the column form.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/platform/kute_layout.dart';
import 'package:kute/screens/shared/animations/premium_group_container.dart';
import 'package:kute/screens/shared/kute_motion.dart' show KuteStaggerIn;
import 'package:kute/theme/app_theme.dart';

/// A run of markets drawn as one grouped card, or one market as its own
/// card.
class MarketSegment<T> {
  const MarketSegment(this.items, {required this.grouped});

  final List<T> items;
  final bool grouped;
}

/// [items] in order, consecutive groupable ones ([groups]) gathered into
/// one segment, every other one a segment of its own.
List<MarketSegment<T>> marketSegments<T>(
    Iterable<T> items, bool Function(T item) groups) {
  final out = <MarketSegment<T>>[];
  List<T>? run;
  for (final item in items) {
    if (groups(item)) {
      if (run == null) {
        run = <T>[];
        out.add(MarketSegment(run, grouped: true));
      }
      run.add(item);
    } else {
      run = null;
      out.add(MarketSegment([item], grouped: false));
    }
  }
  return out;
}

/// The space between a group and a card of its own: room for the group's
/// soft shadow, which falls below it (Home's day groups have their date
/// between them).
double marketSegmentGap() => 16.h;

/// The hairline between two rows of a group: Home Activity's, starting
/// [indent] from the card's left edge (where the row's text starts). The
/// default [MarketGroupDivider]; a market list may pass its own (the
/// Investing rows draw none, the Predictions rows a fainter one).
Widget marketGroupDivider(BuildContext context, double indent) => Divider(
      color: context.colors.borderSubtle,
      height: 1,
      thickness: 0.5,
      indent: indent,
    );

/// What a list draws between two rows of a group, [indent] from the
/// card's left edge.
typedef MarketGroupDivider = Widget Function(
    BuildContext context, double indent);

/// A row of a group, its press ink clipped to the card's corners when it is
/// the first or the last row.
Widget _clipped(Widget row, {required bool first, required bool last}) {
  if (!first && !last) return row;
  final r = Radius.circular(PremiumGroupContainer.radius);
  return ClipRRect(
    borderRadius: BorderRadius.vertical(
      top: first ? r : Radius.zero,
      bottom: last ? r : Radius.zero,
    ),
    child: row,
  );
}

/// The list as slivers, at the lists' 16 side inset: each group one card
/// behind a lazy list of its rows, each other market its own card, [gap]
/// ([marketSegmentGap] by default) between them. [build] draws a market
/// as a group row (`inGroup`) or as its own card; [divider] what sits
/// between two rows of a group.
///
/// WIDE (kute_layout.dart: MEDIUM and EXPANDED), the list lays out by its
/// own width: a list as wide as a phone column is the phone's list; a
/// wider one (the Dollars page's left pane on a laptop) is the same list
/// in [marketGridColumns] columns side by side, each column the phone's
/// list of its share of the markets (dealt in order to the shortest
/// column, so the first markets stay along the top), its groups and its
/// own cards as on a phone. No row is stretched across the pane. A phone
/// is untouched: the slivers below, as they always were.
List<Widget> marketGroupSlivers<T>(
  BuildContext context, {
  required List<T> items,
  required bool Function(T item) groups,
  required Widget Function(T item, bool inGroup) build,
  required double dividerIndent,
  MarketGroupDivider divider = marketGroupDivider,
  double? gap,
  double minColumnWidth = kMarketGridMinColumn,
  bool alignedGrid = false,
}) {
  List<Widget> column(List<T> items, EdgeInsets inset, {bool stagger = true}) =>
      _marketGroupColumnSlivers<T>(context,
          items: items,
          groups: groups,
          build: build,
          dividerIndent: dividerIndent,
          divider: divider,
          gap: gap,
          inset: inset,
          stagger: stagger);
  if (!KuteLayout.isWide(context)) {
    return column(items, EdgeInsets.symmetric(horizontal: 16.w));
  }
  return [
    SliverLayoutBuilder(builder: (context, constraints) {
      final count = alignedGrid
          ? marketGridAlignedColumns(constraints.crossAxisExtent)
          : marketGridColumns(constraints.crossAxisExtent,
              minColumn: minColumnWidth);
      if (count <= 1 || items.length < 2) {
        return SliverMainAxisGroup(
            slivers: column(items, EdgeInsets.symmetric(horizontal: 16.w)));
      }
      final dealt =
          marketGridDeal(items, count, weight: (item) => groups(item) ? 1 : 3);
      // Equal columns: the list's 16 at its sides, the gutter between.
      return SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: 16.w),
        sliver: SliverCrossAxisGroup(slivers: [
          for (var c = 0; c < count; c++) ...[
            if (c > 0)
              const SliverConstrainedCrossAxis(
                maxExtent: kMarketGridGutter,
                sliver: SliverToBoxAdapter(child: SizedBox.shrink()),
              ),
            SliverCrossAxisExpanded(
              flex: 1,
              sliver: SliverMainAxisGroup(slivers: [
                ...column(dealt[c], EdgeInsets.zero, stagger: c == 0),
                // A column left with nothing still holds its share.
                if (dealt[c].isEmpty)
                  const SliverToBoxAdapter(child: SizedBox.shrink()),
              ]),
            ),
          ],
        ]),
      );
    }),
  ];
}

/// The gap between two columns of a wide list ([marketGroupSlivers]).
const double kMarketGridGutter = 16;

/// The narrowest a column of a wide list may be by default: an Investing
/// row reads whole at it. A list of bigger cards passes its own (the
/// Predictions cards: the narrowest phone's card, 288).
const double kMarketGridMinColumn = 240;

/// How many columns a market list [width] wide is drawn in: one up to a
/// phone column and a little more (MEDIUM's 560 column among them), two
/// from 640, three from 840 (the Dollars page's left pane on a 1440
/// laptop), and never so many that a column is under [minColumn] (the
/// list's 16 at its sides and the gutters out).
int marketGridColumns(double width, {double minColumn = kMarketGridMinColumn}) {
  final byWidth = width >= 840
      ? 3
      : width >= 640
          ? 2
          : 1;
  final fit =
      ((width - 32 + kMarketGridGutter) / (minColumn + kMarketGridGutter))
          .floor();
  return fit < 1 ? 1 : (fit < byWidth ? fit : byWidth);
}

/// The narrowest list column of the Dollars page's grid on EXPANDED
/// ([marketGridAlignedColumns]): an Investing row and a Predictions card
/// (the narrowest phone's, 288) both read whole at it.
const double kMarketGridAlignedMinColumn = 288;

/// The narrowest square of the grid ([marketSquaresPerRow]): a phone's
/// square (half the 430 design less its gutters, about 194), less a little.
const double kMarketSquareMinWide = 190;

/// THE DOLLARS PAGE'S ONE GRID (round two, 25 November 2026: "two grids
/// that don't line up"). On EXPANDED every block of a pill in the left
/// pane stands on the same outer edges, the list's 16 inside the pane,
/// [kMarketGridGutter] between columns:
///
///   * the squares (Investing's movers, Predictions' top markets, the
///     Overview's positions) four in a row when four fit at
///     [kMarketSquareMinWide], else two by two ([marketSquaresPerRow]);
///   * the lists in four columns when four hold
///     [kMarketGridAlignedMinColumn], else two, else one
///     ([marketGridAlignedColumns]): never three, so a list column always
///     starts on a square's edge (four squares over two columns, two over
///     two, two over one).
int marketGridAlignedColumns(double width) {
  final fit = ((width - 32 + kMarketGridGutter) /
          (kMarketGridAlignedMinColumn + kMarketGridGutter))
      .floor();
  return fit >= 4
      ? 4
      : fit >= 2
          ? 2
          : 1;
}

/// How many squares stand in a row of the grid ([marketGridAlignedColumns])
/// in a content [width] (the list's 16 already out): four when each is at
/// least [kMarketSquareMinWide], else two.
int marketSquaresPerRow(double width) =>
    (width - kMarketGridGutter * 3) / 4 >= kMarketSquareMinWide ? 4 : 2;

/// [items] dealt into [count] columns, in order, each to the column
/// standing shortest so far ([weight]: a grouped row 1, a card of its own
/// about three), the first column on a tie: the first markets fill the
/// top row, left to right, and the columns end near each other.
List<List<T>> marketGridDeal<T>(List<T> items, int count,
    {required int Function(T item) weight}) {
  final out = [for (var c = 0; c < count; c++) <T>[]];
  final height = List<int>.filled(count, 0);
  for (final item in items) {
    var best = 0;
    for (var c = 1; c < count; c++) {
      if (height[c] < height[best]) best = c;
    }
    out[best].add(item);
    height[best] += weight(item);
  }
  return out;
}

/// One column of [marketGroupSlivers]: the phone's slivers, [inset] at its
/// sides.
List<Widget> _marketGroupColumnSlivers<T>(
  BuildContext context, {
  required List<T> items,
  required bool Function(T item) groups,
  required Widget Function(T item, bool inGroup) build,
  required double dividerIndent,
  required MarketGroupDivider divider,
  required double? gap,
  required EdgeInsets inset,
  required bool stagger,
}) {
  final space = gap ?? marketSegmentGap();
  final slivers = <Widget>[];
  final segments = marketSegments(items, groups);
  for (var s = 0; s < segments.length; s++) {
    final seg = segments[s];
    if (s > 0) {
      slivers.add(SliverToBoxAdapter(child: SizedBox(height: space)));
    }
    final Widget body;
    if (seg.grouped) {
      final rows = seg.items;
      body = DecoratedSliver(
        decoration: PremiumGroupContainer.decorationOf(context),
        sliver: SliverList.separated(
          itemCount: rows.length,
          separatorBuilder: (context, _) => divider(context, dividerIndent),
          // The first card's first rows arrive staggered on first paint.
          itemBuilder: (_, i) => _clipped(
              s == 0 && stagger
                  ? KuteStaggerIn(index: i, child: build(rows[i], true))
                  : build(rows[i], true),
              first: i == 0,
              last: i == rows.length - 1),
        ),
      );
    } else {
      body = SliverToBoxAdapter(child: build(seg.items.single, false));
    }
    slivers.add(SliverPadding(padding: inset, sliver: body));
  }
  return slivers;
}

/// The same list as plain widgets for a short list in a column (the
/// Ledger tab's sections), at the same 16 side inset, [gap] between
/// segments.
List<Widget> marketGroupColumn<T>(
  BuildContext context, {
  required List<T> items,
  required bool Function(T item) groups,
  required Widget Function(T item, bool inGroup) build,
  required double dividerIndent,
  MarketGroupDivider divider = marketGroupDivider,
  double? gap,
}) {
  final space = gap ?? marketSegmentGap();
  final out = <Widget>[];
  final segments = marketSegments(items, groups);
  for (var s = 0; s < segments.length; s++) {
    final seg = segments[s];
    if (s > 0) out.add(SizedBox(height: space));
    if (seg.grouped) {
      final rows = seg.items;
      out.add(PremiumGroupContainer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) divider(context, dividerIndent),
              build(rows[i], true),
            ],
          ],
        ),
      ));
    } else {
      out.add(Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w),
        child: build(seg.items.single, false),
      ));
    }
  }
  return out;
}
