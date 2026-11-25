// lib/screens/shared/desk_lists.dart
//
// The list pages on EXPANDED (round three; founder, 25 November 2026:
// "lots of screens are vertical only. It must be all occupying full screen
// when we can"): Activity, the prediction history, a market category, a
// match's markets, a Ledger's portfolio. Each spans the window and lays
// its EXISTING rows and cards out in columns, never one row stretched
// across 1400 px:
//
//   * a list of day cards (the day's name over its rows on one card,
//     ActivityDaySection) in masonry columns ([ActivityDayColumns]): each
//     day whole, dealt in order to the shortest column, so Today stands
//     top left and the next days along the top;
//   * a market list in columns ([deskMarketColumnSlivers]), each column
//     the phone's list of its share of the markets;
//   * cards of their own in a grid ([SliverKuteGrid] at
//     [kDeskListCellMin], no gap: each card keeps its 16 inset).
//
// Every list card keeps its phone inset of 16 at both sides, so a page
// pads its scroll view by the gutter less that inset ([deskListPadding])
// and the cards stand 32 apart, their outer edges on the page gutter. Off EXPANDED none of this is used.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/platform/kute_wide_frames.dart';
import 'package:kute/screens/shared/market_groups.dart';
import 'package:kute/screens/shared/transactions_builder.dart'
    show ActivityDaySection;

/// A list card's own inset at each side (PremiumGroupContainer, the
/// market lists, the portfolio cards).
double get kDeskListInset => 16.w;

/// The narrowest cell of a list page's columns: a readable column
/// ([kuteWideColumnMin]) with the card's inset at both sides.
double get kDeskListCellMin => kuteWideColumnMin + 2 * kDeskListInset;

/// A list page's scroll padding at its sides on EXPANDED: the page gutter
/// less the cards' own inset.
EdgeInsets deskListPadding() =>
    EdgeInsets.symmetric(horizontal: kuteWideGutter - kDeskListInset);

/// How many columns of cells a list page [width] wide (its padding out)
/// lays out: two to four.
int deskListColumns(double width) =>
    kuteColumnsFor(width, min: kDeskListCellMin, gap: 0, max: 4);

/// A list page's own column rule for the day cards under it
/// ([ActivityDayColumns], [DeskFirstColumn]) in place of
/// [deskListColumns]: the Bitcoin home's left pane, whose cards stay a
/// comfortable width beside the goals (bitcoin_home_panes.dart).
class DeskListColumnRule extends InheritedWidget {
  const DeskListColumnRule(
      {super.key, required this.columnsFor, required super.child});

  /// How many columns a list [width] wide lays out.
  final int Function(double width) columnsFor;

  /// The rule [context] is under, else [deskListColumns].
  static int Function(double width) of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<DeskListColumnRule>()
          ?.columnsFor ??
      deskListColumns;

  @override
  bool updateShouldNotify(DeskListColumnRule oldWidget) =>
      columnsFor != oldWidget.columnsFor;
}

/// The back button on the page's left gutter, for an AppBar's `leading`
/// on EXPANDED (with [kDeskLeadingWidth]).
class DeskGutterLeading extends StatelessWidget {
  const DeskGutterLeading({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: kuteWideGutter - 2),
        child: Align(alignment: Alignment.centerLeft, child: child),
      );
}

/// An AppBar's `leadingWidth` with [DeskGutterLeading].
const double kDeskLeadingWidth = kuteWideGutter + 40;

/// [child] (a note or a card over a list) at the width of the list's
/// first column, on its left edge: never stretched across the page.
class DeskFirstColumn extends StatelessWidget {
  const DeskFirstColumn({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final n = DeskListColumnRule.of(context)(box.maxWidth);
        return Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: box.maxWidth / n, child: child),
        );
      });
}

/// Day cards (each the day's name over its rows, [ActivityDaySection]) in
/// masonry columns: each day whole, dealt in order to the shortest column
/// ([marketGridDeal], weighed by its rows), so the newest days run along
/// the top. [leading] (the standing orders, a retry) sits over the first
/// column at its width. [weights] when [sections] are wrapped (their row
/// counts plus two); else read off each [ActivityDaySection].
class ActivityDayColumns extends StatelessWidget {
  const ActivityDayColumns({
    super.key,
    required this.sections,
    this.weights,
    this.leading = const [],
  });

  final List<Widget> sections;
  final List<int>? weights;
  final List<Widget> leading;

  int _weight(int i) {
    final w = weights;
    if (w != null && i < w.length) return w[i];
    final s = sections[i];
    return s is ActivityDaySection ? s.rows.length + 2 : 3;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final n = DeskListColumnRule.of(context)(box.maxWidth);
        final cell = box.maxWidth / n;
        final dealt = marketGridDeal<int>(
            [for (var i = 0; i < sections.length; i++) i], n,
            weight: _weight);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final l in leading) SizedBox(width: cell, child: l),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final column in dealt)
                  SizedBox(
                    width: cell,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [for (final i in column) sections[i]],
                    ),
                  ),
              ],
            ),
          ],
        );
      });
}

/// A market list ([marketGroupSlivers]) in [deskListColumns] columns side
/// by side, each the phone's list of its share of the markets (dealt in
/// order to the shortest column: a grouped row weighs one, a card of its
/// own three), its groups and cards keeping their 16 inset.
List<Widget> deskMarketColumnSlivers<T>(
  BuildContext context, {
  required List<T> items,
  required bool Function(T item) groups,
  required Widget Function(T item, bool inGroup) build,
  required double dividerIndent,
  MarketGroupDivider divider = marketGroupDivider,
}) =>
    [
      SliverLayoutBuilder(builder: (context, constraints) {
        final n = deskListColumns(constraints.crossAxisExtent);
        final dealt =
            marketGridDeal(items, n, weight: (item) => groups(item) ? 1 : 3);
        return SliverCrossAxisGroup(slivers: [
          for (final column in dealt)
            SliverCrossAxisExpanded(
              flex: 1,
              sliver: SliverMainAxisGroup(slivers: [
                if (column.isEmpty)
                  const SliverToBoxAdapter(child: SizedBox.shrink())
                else
                  ...marketGroupSlivers<T>(
                    context,
                    items: column,
                    groups: groups,
                    build: build,
                    dividerIndent: dividerIndent,
                    divider: divider,
                  ),
              ]),
            ),
        ]);
      }),
    ];
