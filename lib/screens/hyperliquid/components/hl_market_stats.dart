// lib/screens/hyperliquid/components/hl_market_stats.dart
//
// The "Stats" block of an Investing market: label / value pairs in two
// columns, the label on the left in the secondary text style and the
// value on the right, hairline dividers between rows, no card around
// them. Standalone on purpose: it takes a plain list of [HlStat], so the
// market sheet and (later) the position sheet can both feed it.
//
// [hlMarketStats] builds the pairs of a market from what the app already
// holds for it (the market row plus the sheet's live context): nothing
// here asks the venue for anything.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/shared/kute_motion.dart';
import 'package:kute/theme/app_theme.dart';

/// One label / value pair.
class HlStat {
  final String label;
  final String value;
  const HlStat(this.label, this.value);
}

/// An hourly funding rate as the app writes it ('+0.0013%', '-0.0100%').
String formatHlFundingRate(double rate) =>
    '${rate >= 0 ? '+' : ''}${(rate * 100).toStringAsFixed(4)}%';

/// The pairs of [m], in order. A perp: 24h volume, open interest,
/// funding, maximum leverage, mark. A spot token: 24h volume, mark. A
/// value the venue has not given is left out, never shown as a zero the
/// market does not have (24h volume aside: no trade in a day is a fact).
List<HlStat> hlMarketStats(AppLocalizations l10n, HlMarket m) => [
      HlStat(l10n.hl24hVolume, formatHlCompactUsd(m.dayNtlVlm)),
      if (!m.isSpot && m.openInterest != null && m.markPx > 0)
        HlStat(l10n.hlOpenInterest,
            formatHlCompactUsd(m.openInterest! * m.markPx)),
      if (!m.isSpot && m.funding != null)
        HlStat(l10n.hlFunding, formatHlFundingRate(m.funding!)),
      // The leverage this app will actually offer on the ticket.
      if (!m.isSpot && m.offeredMaxLeverage > 1)
        HlStat(l10n.chartMaxLeverage, '${m.offeredMaxLeverage}×'),
      if (m.markPx > 0)
        HlStat(l10n.hlMark,
            formatHlPrice(m.markPx, decimalCap: m.pxDecimalCap)),
    ];

/// A titled block of [stats] in two columns. An odd count leaves the last
/// cell empty; an empty list draws nothing.
class HlStatsSection extends StatelessWidget {
  final String title;
  final List<HlStat> stats;

  const HlStatsSection({super.key, required this.title, required this.stats});

  @override
  Widget build(BuildContext context) {
    // Figures that land after the sheet opens (a day's high and low, the
    // spread) ease the block to its new height, and a cell that fills in
    // fades in. A value that changes in place never fades.
    return AnimatedSize(
      duration: kuteMotion(context, kArrivalDuration),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: stats.isEmpty ? const SizedBox.shrink() : _block(context),
    );
  }

  Widget _block(BuildContext context) {
    final c = context.colors;
    final rows = (stats.length + 1) ~/ 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 17.sp,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        SizedBox(height: 4.h),
        for (var r = 0; r < rows; r++)
          Row(
            children: [
              Expanded(
                child: ArrivalSwitcher(
                  state: stats[r * 2].label,
                  animateSize: false,
                  child:
                      _StatCell(stat: stats[r * 2], divider: r < rows - 1),
                ),
              ),
              SizedBox(width: 20.w),
              Expanded(
                child: ArrivalSwitcher(
                  state:
                      r * 2 + 1 < stats.length ? stats[r * 2 + 1].label : '',
                  animateSize: false,
                  child: r * 2 + 1 < stats.length
                      ? _StatCell(
                          stat: stats[r * 2 + 1], divider: r < rows - 1)
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _StatCell extends StatelessWidget {
  final HlStat stat;

  /// A hairline under the cell: every row but the last.
  final bool divider;
  const _StatCell({required this.stat, required this.divider});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.symmetric(vertical: 12.h),
      decoration: BoxDecoration(
        border: divider
            ? Border(bottom: BorderSide(color: c.borderSubtle, width: 0.5))
            : null,
      ),
      child: Row(
        children: [
          // The label gives way; the value is never cut.
          Expanded(
            child: Text(
              stat.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 13.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(width: 8.w),
          Text(
            stat.value,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 14.sp,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
