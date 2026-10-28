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

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_trade_alerts_provider.dart'
    show kHlLiquidationRiskDistance, kHlLiquidationRiskUrgent;
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/hyperliquid/components/hl_isolated_margin.dart'
    show hlPositionMargin;
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

/// What [p] loses if the price reaches its liquidation price and the
/// position closes there, for the position screen's risk line: an
/// isolated position's whole margin (what is at stake in it), a cross
/// position's loss at that price against its entry ((entry − liquidation)
/// × size, the size signed). Null when the venue reports no liquidation
/// price or the figure is not a loss: the line is then not written.
double? hlLossAtLiquidation(HlPerpPosition p) {
  final liq = hlLiquidationPrice(p);
  if (liq == null || p.szi == 0 || !(p.entryPx > 0)) return null;
  final loss = p.isCross ? (p.entryPx - liq) * p.szi : hlPositionMargin(p);
  return loss.isFinite && loss > 0 ? loss : null;
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

/// The position screen's Liquidation tile: "Liquidation", the price large
/// and "12% away" under it, the distance alone coloured
/// ([hlLiqDistanceColor]); "No liquidation price" quietly when the venue
/// reports none.
class HlLiquidationTile extends StatelessWidget {
  const HlLiquidationTile({
    super.key,
    required this.liquidation,
    required this.mark,
    this.decimalCap,
  });

  final double? liquidation;
  final double mark;
  final int? decimalCap;

  static const tileKey = ValueKey('hl-position-liquidation');

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final liq = liquidation;
    final distance = hlLiquidationDistance(mark: mark, liq: liq);
    return PositionStatTile(
      key: tileKey,
      label: l10n.hlLiquidation,
      value: liq == null || liq <= 0
          ? Text(l10n.hlNoLiquidationPrice,
              maxLines: 1, style: portfolioCardCaptionStyle(c))
          : Text(formatHlPrice(liq, decimalCap: decimalCap),
              maxLines: 1, style: positionTileValueStyle(c)),
      caption: distance == null
          ? null
          : Text(
              l10n.hlLiqAway(formatHlLiqDistance(distance)),
              maxLines: 1,
              style: positionTileCaptionStyle(c,
                  color: hlLiqDistanceColor(distance, c)),
            ),
    );
  }
}
