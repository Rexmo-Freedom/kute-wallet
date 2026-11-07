// lib/screens/hyperliquid/components/hl_chart_interval_sheet.dart
//
// The Advanced chart's Interval sheet, behind the interval button in its
// top bar (founder, 5 November 2026: "Intervals should also be the
// squares"). The intervals of [kHlCandleIntervals] (1m 5m 1h 1D 1W) as
// the Chart sheet's square cards ([HlSquareBox]: the app's one soft
// card, the action cards' own), three to a row and the last
// row's two centred under them, no orphan: the interval big ("5m"), what
// one bar spans ("5 minutes") and a line on what it is good for
// ("Today's swings"). A tap picks the interval and closes the sheet; the
// chosen one wears the CTA-coloured outline. The market chart's own
// interval row (KuteChartRangeRow) is inline pills, not a sheet.
//
// A picker: the floating Sal bar hides while it is up.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_intervals.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_sheet.dart'
    show HlSquareBox;
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/theme/app_theme.dart';

/// Cards in a row of the Interval sheet.
const int kHlIntervalColumns = 3;

const double _kGap = 10;

/// Opens the Interval sheet with [current] chosen; the interval tapped,
/// or null when the sheet is closed without one.
Future<HlCandleInterval?> showHlIntervalSheet(
  BuildContext context, {
  required HlCandleInterval current,
}) =>
    showAppBottomSheet<HlCandleInterval>(
      context: context,
      builder: (_) => HlIntervalSheet(current: current.interval),
    );

/// What one bar of [iv] spans ("5 minutes").
String hlIntervalMeaning(AppLocalizations l10n, HlCandleInterval iv) =>
    switch (iv.interval) {
      '1m' => l10n.chartIntervalMinute,
      '5m' => l10n.chartIntervalFiveMinutes,
      '1d' => l10n.chartIntervalDay,
      '1w' => l10n.chartIntervalWeek,
      _ => l10n.chartIntervalHour,
    };

/// What [iv] is good for: about what its chart opens on (~100 bars).
String hlIntervalHint(AppLocalizations l10n, HlCandleInterval iv) =>
    switch (iv.interval) {
      '1m' => l10n.chartIntervalMinuteHint,
      '5m' => l10n.chartIntervalFiveMinutesHint,
      '1d' => l10n.chartIntervalDayHint,
      '1w' => l10n.chartIntervalWeekHint,
      _ => l10n.chartIntervalHourHint,
    };

class HlIntervalSheet extends StatelessWidget {
  const HlIntervalSheet({super.key, required this.current});

  /// The chosen interval ('1m' … '1w').
  final String current;

  @override
  Widget build(BuildContext context) {
    // A picker: the floating bar is away while it is up.
    return KuteBarContextScope(
      barContext: const KuteBarContext.hidden(),
      child: AppBottomSheetContainer(
        maxHeight: 0.8,
        child: Column(
          key: const ValueKey('hl-interval-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppBottomSheetHeader(
              title: context.l10n.chartInterval,
              compact: true,
              // The app's one close (kute_back_button.dart).
              trailing: const AppBottomSheetCloseButton(
                  key: ValueKey('hl-interval-sheet-close')),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 8),
                child: _IntervalGrid(
                  current: current,
                  onPick: (iv) => Navigator.of(context).pop(iv),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [kHlCandleIntervals] in rows of [kHlIntervalColumns] equal squares; a
/// short last row keeps the cards' width and sits centred.
class _IntervalGrid extends StatelessWidget {
  const _IntervalGrid({required this.current, required this.onPick});

  final String current;
  final ValueChanged<HlCandleInterval> onPick;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final cell = (constraints.maxWidth - (kHlIntervalColumns - 1) * _kGap) /
          kHlIntervalColumns;
      // Square: as tall as wide, never under the option cards' 112.
      final side = math.max(112.0, cell);
      final cards = [
        for (final iv in kHlCandleIntervals)
          _IntervalCard(
            iv: iv,
            picked: iv.interval == current,
            minHeight: side,
            onTap: () => onPick(iv),
          ),
      ];
      final rows = <Widget>[];
      for (var i = 0; i < cards.length; i += kHlIntervalColumns) {
        final row =
            cards.sublist(i, math.min(i + kHlIntervalColumns, cards.length));
        if (rows.isNotEmpty) rows.add(const SizedBox(height: _kGap));
        rows.add(IntrinsicHeight(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = 0; j < row.length; j++) ...[
                if (j > 0) const SizedBox(width: _kGap),
                SizedBox(width: cell, child: row[j]),
              ],
            ],
          ),
        ));
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      );
    });
  }
}

/// One interval: its label big, what a bar spans, what it is good for.
class _IntervalCard extends StatelessWidget {
  const _IntervalCard({
    required this.iv,
    required this.picked,
    required this.minHeight,
    required this.onTap,
  });

  final HlCandleInterval iv;
  final bool picked;
  final double minHeight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final hintStyle = TextStyle(
      color: c.textTertiary,
      fontSize: 12.sp,
      fontWeight: FontWeight.w500,
      height: 1.3,
    );
    // Two lines kept for every hint, so a card whose hint takes one line
    // is as tall as one whose hint takes two, in every row.
    final hintBox =
        MediaQuery.textScalerOf(context).scale(hintStyle.fontSize!) * 1.3 * 2 +
            1;
    return Semantics(
      button: true,
      selected: picked,
      child: GestureDetector(
        key: ValueKey('hl-interval-card-${iv.interval}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: HlSquareBox(
          picked: picked,
          minHeight: minHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                iv.label,
                maxLines: 1,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 26.sp,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                  height: 1.1,
                ),
              ),
              const Spacer(),
              Text(
                hlIntervalMeaning(l10n, iv),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 2),
              SizedBox(
                height: hintBox,
                child: Text(
                  hlIntervalHint(l10n, iv),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: hintStyle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
