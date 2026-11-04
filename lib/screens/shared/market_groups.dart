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
List<Widget> marketGroupSlivers<T>(
  BuildContext context, {
  required List<T> items,
  required bool Function(T item) groups,
  required Widget Function(T item, bool inGroup) build,
  required double dividerIndent,
  MarketGroupDivider divider = marketGroupDivider,
  double? gap,
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
              s == 0
                  ? KuteStaggerIn(index: i, child: build(rows[i], true))
                  : build(rows[i], true),
              first: i == 0,
              last: i == rows.length - 1),
        ),
      );
    } else {
      body = SliverToBoxAdapter(child: build(seg.items.single, false));
    }
    slivers.add(SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      sliver: body,
    ));
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
