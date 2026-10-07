// lib/screens/polymarket/components/poly_market_stats.dart
//
// What sits under a Predictions market's chart and outcomes: the "Rules
// and resolution" row, which opens the app's shared bottom sheet with the
// market's stats (24h volume, volume, liquidity), its rules text, how it
// resolves and what people wrote under it. The stats live inside that
// sheet (owner decision), not on the market screen.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/screens/polymarket/components/market_comments.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/components/sheet_detail_row.dart';
import 'package:kute/theme/app_theme.dart';

/// One label / value pair.
class PolyStat {
  final String label;
  final String value;
  const PolyStat(this.label, this.value);
}

/// The pairs of a market, in order: 24h volume, total volume, liquidity,
/// when it ends (or ended). A figure Polymarket has not given is left
/// out, never shown as a zero or an estimate. [money] is the app's
/// compact money formatter; [locale] writes the date.
List<PolyStat> polyMarketStats(
  AppLocalizations l10n, {
  required double volume24hr,
  required double volume,
  required double liquidity,
  required DateTime? endDate,
  required bool ended,
  required String Function(double) money,
  String? locale,
}) =>
    [
      if (volume24hr > 0) PolyStat(l10n.bet24hVolume, money(volume24hr)),
      if (volume > 0) PolyStat(l10n.betTotalVolume, money(volume)),
      if (liquidity > 0) PolyStat(l10n.betLiquidity, money(liquidity)),
      if (endDate != null)
        PolyStat(ended ? l10n.polyStatEnded : l10n.polyStatEnds,
            DateFormat.yMMMd(locale).format(endDate.toLocal())),
    ];

/// The one row under the outcomes: "Rules and resolution", opening
/// [showPolyRulesSheet]. [label] names another sheet opened the same way
/// (the open position's "Closing conditions").
class PolyRulesRow extends StatelessWidget {
  final VoidCallback onTap;
  final String? label;
  const PolyRulesRow({super.key, required this.onTap, this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 14.h),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: c.borderSubtle, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label ?? context.l10n.polyRulesAndResolution,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.settingsTitle(context),
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: c.textTertiary, size: 22.sp),
          ],
        ),
      ),
    );
  }
}

/// The market's [stats], its rules, how it resolves and what people wrote
/// under it, on the app's shared bottom sheet. The comments are read only
/// while the sheet is open.
Future<void> showPolyRulesSheet(BuildContext context, PolymarketEvent event,
    {List<PolyStat> stats = const []}) {
  return showAppBottomSheet<void>(
    context: context,
    builder: (_) => PolyRulesSheet(event: event, stats: stats),
  );
}

class PolyRulesSheet extends StatelessWidget {
  final PolymarketEvent event;

  /// The market's figures ([polyMarketStats]), first on the sheet under
  /// their own heading, each on the sheet's detail row. Empty draws no
  /// heading.
  final List<PolyStat> stats;
  const PolyRulesSheet(
      {super.key, required this.event, this.stats = const []});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final description = event.description?.trim() ?? '';
    final end = event.endDate;
    final eventId = int.tryParse(event.id);
    Widget heading(String text) => Padding(
          padding: EdgeInsets.only(bottom: 6.h),
          child: Text(
            text,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 17.sp,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
        );
    return AppBottomSheetContainer(
      maxHeight: 0.85,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBottomSheetHeader(
            title: l10n.polyRulesAndResolution,
            trailing: IconButton(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 24.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (stats.isNotEmpty) ...[
                    heading(l10n.polyStatsTitle),
                    for (final stat in stats)
                      SheetDetailRow(label: stat.label, value: stat.value),
                    SizedBox(height: 20.h),
                  ],
                  if (description.isNotEmpty) ...[
                    heading(l10n.betAbout),
                    Text(
                      description,
                      style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w500,
                        height: 1.5,
                        letterSpacing: -0.1,
                      ),
                    ),
                    SizedBox(height: 20.h),
                  ],
                  heading(l10n.betResolution),
                  SheetDetailRow(
                      label: l10n.betMarketCreated,
                      value: l10n.betTradingIsOpen),
                  SheetDetailRow(
                      label: l10n.betTradingActive,
                      value: l10n.betBuyAndSellShares),
                  SheetDetailRow(
                    label: l10n.betMarketCloses,
                    value: end == null
                        ? l10n.betDateTbd
                        : DateFormat.yMMMd(
                                Localizations.localeOf(context).toString())
                            .format(end.toLocal()),
                  ),
                  SheetDetailRow(
                      label: l10n.betResolution, value: l10n.betWinnersPaid),
                  if (eventId != null) ...[
                    SizedBox(height: 20.h),
                    heading(l10n.predictNewsTab),
                    PolyMarketComments(eventId: eventId),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
