// lib/screens/hyperliquid/components/hl_liquidation_distance.dart
//
// How far a position is from its liquidation price, said the same way on
// the position screen and the Portfolio card: "$78,400 · 12% away".
//
//   * distance = |mark − liquidation| / mark;
//   * written with one decimal under 10% ("7.4% away") and whole above
//     ("12% away");
//   * only the distance takes a colour: neutral normally, the app's
//     warning (amber) inside the liquidation-risk alert's first step
//     ([kHlLiquidationRiskDistance], 10%), the down (red) colour inside
//     its second ([kHlLiquidationRiskUrgent], 5%). The thresholds ARE the
//     alert's, so the colour turns when the banner fires.
//
// Pure apart from the text and the position screen's row: nothing here
// reads or asks the venue.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_trade_alerts_provider.dart'
    show kHlLiquidationRiskDistance, kHlLiquidationRiskUrgent;
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/screens/shared/portfolio_position_card.dart'
    show portfolioCardCaptionStyle;
import 'package:kute/screens/shared/position_rows_card.dart';
import 'package:kute/theme/app_theme.dart';

/// The liquidation price the venue reports for [p], or null when it
/// reports none (a position with no risk of liquidation).
double? hlLiquidationPrice(HlPerpPosition p) {
  final liq = p.liquidationPx;
  return liq != null && liq.isFinite && liq > 0 ? liq : null;
}

/// The mark the distance is measured from: the live mid when there is
/// one, else the venue's snapshot (notional / size), else the entry.
double hlPositionMark(HlPerpPosition p, {double? liveMid}) {
  if (liveMid != null && liveMid.isFinite && liveMid > 0) return liveMid;
  final size = p.szi.abs();
  return size > 0 ? p.positionValue.abs() / size : p.entryPx;
}

/// |mark − liquidation| / mark, or null without either.
double? hlLiquidationDistance({required double mark, required double? liq}) {
  if (liq == null || !liq.isFinite || liq <= 0) return null;
  if (!mark.isFinite || mark <= 0) return null;
  return (mark - liq).abs() / mark;
}

/// "7.4%" under 10%, "12%" above.
String formatHlLiqDistance(double distance) {
  final pct = distance * 100;
  return pct < 10 ? '${pct.toStringAsFixed(1)}%' : '${pct.round()}%';
}

/// The distance's colour: null (the line's own, neutral) normally, the
/// warning colour inside 10%, the down colour inside 5%.
Color? hlLiqDistanceColor(double distance, AppColorsExtension c) {
  if (distance <= kHlLiquidationRiskUrgent) return AppColors.marketDown;
  if (distance <= kHlLiquidationRiskDistance) return c.warning;
  return null;
}

/// "$78,400 · 12% away" (with [label] in front when given: "Liq $78,400 ·
/// 12% away"), the distance alone coloured by [hlLiqDistanceColor].
/// Without a liquidation price: [noLiquidation] in [quietStyle] when
/// given, else nothing.
class HlLiquidationText extends StatelessWidget {
  const HlLiquidationText({
    super.key,
    required this.liquidation,
    required this.mark,
    required this.style,
    this.label,
    this.decimalCap,
    this.textAlign,
    this.maxLines,
    this.noLiquidation = false,
    this.quietStyle,
  });

  final double? liquidation;
  final double mark;
  final TextStyle style;
  final String? label;
  final int? decimalCap;
  final TextAlign? textAlign;
  final int? maxLines;

  /// Write "No liquidation price" when the venue reports none.
  final bool noLiquidation;
  final TextStyle? quietStyle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final distance = hlLiquidationDistance(mark: mark, liq: liquidation);
    if (liquidation == null || liquidation! <= 0) {
      if (!noLiquidation) return const SizedBox.shrink();
      return Text(l10n.hlNoLiquidationPrice,
          textAlign: textAlign, maxLines: maxLines, style: quietStyle ?? style);
    }
    final price = formatHlPrice(liquidation!, decimalCap: decimalCap);
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: label == null ? price : '$label $price'),
        if (distance != null) ...[
          const TextSpan(text: ' · '),
          TextSpan(
            text: l10n.hlLiqAway(formatHlLiqDistance(distance)),
            style:
                TextStyle(color: hlLiqDistanceColor(distance, context.colors)),
          ),
        ],
      ]),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      style: style,
    );
  }
}

/// The position screen's Liquidation row: "Liquidation" on the left,
/// "$78,400 · 12% away" on the right ("No liquidation price" in the
/// caption style when the venue reports none), and, when [onAddMargin]
/// is given (an isolated position the app can move margin on), the small
/// "Add margin" pill right beside it.
PositionRow hlLiquidationRow(
  BuildContext context, {
  required double? liquidation,
  required double mark,
  int? decimalCap,
  VoidCallback? onAddMargin,
}) {
  final c = context.colors;
  final l10n = context.l10n;
  return PositionRow(
    l10n.hlLiquidation,
    '',
    child: HlLiquidationText(
      liquidation: liquidation,
      mark: mark,
      decimalCap: decimalCap,
      textAlign: TextAlign.right,
      style: positionRowValueStyle(c),
      noLiquidation: true,
      quietStyle: portfolioCardCaptionStyle(c),
    ),
    action: onAddMargin == null
        ? null
        : KutePill(
            key: const ValueKey('hl-add-margin'),
            label: l10n.hlMarginAdd,
            icon: Icons.add_rounded,
            selected: true,
            onTap: () {
              HapticFeedback.selectionClick();
              onAddMargin();
            },
          ),
  );
}
