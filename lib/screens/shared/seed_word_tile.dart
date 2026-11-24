// lib/screens/shared/seed_word_tile.dart
//
// One numbered recovery-phrase word tile. Shared by the Settings seed
// words screen and the backup-wallet reveal step so both grids read as
// the same component instead of two drifting copies.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/platform/kute_wide_frames.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/theme/app_theme.dart';

class SeedWordTile extends StatelessWidget {
  /// 1-based position of the word in the phrase.
  final int index;
  final String word;

  const SeedWordTile({super.key, required this.index, required this.word});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: c.borderSubtle, width: 0.5),
      ),
      child: Row(
        children: [
          SizedBox(width: 14.w),
          Text(
            '$index.',
            style: TextStyle(
              color: c.textTertiary,
              fontSize: 14.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(width: 8.w),
          Flexible(
            child: Text(
              word,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 15.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── EXPANDED (round three; founder, 25 November 2026: "it must be all
// occupying full screen when we can") ─────────────────────────────────
//
// The backup and recovery pages (backup reveal and verify, the Settings
// seed words, the seed entry, the restore list) on a window of 900 and up:
// the page spans the window inside its gutters (kuteWidePadding), the
// explanation, warnings and actions in a readable [kuteSeedSideWidth]
// column on the left, the words (or the entry fields, the wallets) across
// the rest as a grid of the existing tiles. One scroll; its end keeps the
// floating bar's clearance so nothing sits under the bar. MEDIUM and the
// phone never build it.

/// The explanation and actions column beside the words on EXPANDED.
const double kuteSeedSideWidth = 400;

/// How many word tiles across a grid of [width] holds on EXPANDED: four
/// (12 words 4 x 3, 24 words 4 x 6) from about 560, else three.
int kuteSeedColumnsFor(double width) => width >= 560 ? 4 : 3;

/// A word tile's height in the EXPANDED grids.
const double kuteSeedTileHeight = 56;

/// The left gutter's back button and the title beside it on EXPANDED (as
/// Settings): the AppBar's `leadingWidth` and the leading's left pad.
double kuteSeedLeadingWidth(BuildContext context) =>
    kuteWidePadding(context).left + 40;

/// [leading] padded onto the page's left gutter (EXPANDED).
Widget kuteSeedLeading(BuildContext context, Widget leading) => Padding(
      padding: EdgeInsets.only(left: kuteWidePadding(context).left - 2),
      child: Align(alignment: Alignment.centerLeft, child: leading),
    );

/// The EXPANDED page: [side] (explanation, warnings, actions) in a
/// [kuteSeedSideWidth] column on the left, [main] (the words) across the
/// rest, under one scroll padded to the window's gutters and clear of the
/// floating bar at its end.
class KuteSeedWidePage extends StatelessWidget {
  const KuteSeedWidePage({
    super.key,
    required this.side,
    required this.main,
    this.top = 8,
    this.physics,
  });

  final Widget side;
  final Widget main;
  final double top;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    final pad = kuteWidePadding(context);
    return SingleChildScrollView(
      physics: physics,
      padding: EdgeInsets.fromLTRB(
          pad.left, top, pad.right, kuteBarScrollClearance + 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: kuteSeedSideWidth, child: side),
          const SizedBox(width: kuteWideGap),
          Expanded(child: main),
        ],
      ),
    );
  }
}

/// [count] tiles from [itemBuilder] as the EXPANDED words grid: four (or
/// three) across the width it is given, each [kuteSeedTileHeight] tall.
class KuteSeedWordGrid extends StatelessWidget {
  const KuteSeedWordGrid({
    super.key,
    required this.count,
    required this.itemBuilder,
    this.height = kuteSeedTileHeight,
  });

  final int count;
  final IndexedWidgetBuilder itemBuilder;
  final double height;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => GridView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: kuteSeedColumnsFor(constraints.maxWidth),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          mainAxisExtent: height,
        ),
        itemCount: count,
        itemBuilder: itemBuilder,
      ),
    );
  }
}
