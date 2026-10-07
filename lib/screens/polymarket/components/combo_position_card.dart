// A held Polymarket combo (parlay) as a portfolio card, in the frame and
// number placement of the other position cards: "Combo · N legs" on the
// left, its value on the right (ESTIMATED while open and labelled as such:
// there is no combo price feed; the profit or loss once settled or lost),
// then each leg with its status on its own line, and the stake, the payout
// if every remaining leg wins and the multiplier as three captioned
// figures. Tap opens ComboDetailSheet; a settled combo with a payout
// carries its "Claim $X" button (one tap, ComboClaimButton).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/polymarket/components/combo_copy.dart';
import 'package:kute/screens/polymarket/components/combo_detail_sheet.dart';
import 'package:kute/screens/polymarket/components/market_card.dart';
import 'package:kute/screens/shared/portfolio_position_card.dart';
import 'package:kute/services/polymarket/combos/combo_models.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

Color comboLegColor(BuildContext context, ComboLegOutcome o) => switch (o) {
      ComboLegOutcome.won => AppColors.success,
      ComboLegOutcome.lost => AppColors.marketDown,
      ComboLegOutcome.void_ => context.colors.textSecondary,
      ComboLegOutcome.open => context.colors.textTertiary,
    };

String comboLegStatusText(BuildContext context, ComboLegOutcome o) =>
    switch (o) {
      ComboLegOutcome.won => context.l10n.comboLegWon,
      ComboLegOutcome.lost => context.l10n.comboLegLost,
      ComboLegOutcome.void_ => context.l10n.comboLegVoid,
      ComboLegOutcome.open => context.l10n.comboLegOpen,
    };

class ComboPositionCard extends StatelessWidget {
  const ComboPositionCard({super.key, required this.position});
  final ComboPosition position;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final p = position;
    final settled = p.settledPayoutUsd;
    final lost = p.isLost;
    final value = lost ? 0.0 : (settled ?? p.estimatedValueUsd);
    final pnl = value - p.stakeUsd;
    final firstImage =
        p.legs.map((l) => l.imageUrl).whereType<String>().firstOrNull;

    // Small caption label above, the figure below: equal thirds.
    Widget metric(String label, String v, {bool end = false}) => Expanded(
          child: Column(
            crossAxisAlignment:
                end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: polyCardCaptionStyle(c)),
              SizedBox(height: 2.h),
              Text(v,
                  maxLines: 1,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
            ],
          ),
        );

    // The portfolio card's frame and number placement; the content is the
    // combo's own (legs, stake, payout, multiplier).
    return PortfolioCardFrame(
      onTap: () {
        HapticFeedback.selectionClick();
        TrackingService.track('open_investments_position_tapped',
            params: {'product': 'predictions', 'kind': 'combo'});
        ComboDetailSheet.show(context, conditionId: p.conditionId);
      },
      // A settled combo with a payout is claimed from the card in one tap.
      action: p.redeemable && (settled ?? 0) > 0
          ? ComboClaimButton(position: p, compact: true)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          LayoutBuilder(
            builder: (context, box) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PolyCardThumbnail(
                  title: l10n.comboLegsLabel(p.legsTotal),
                  imageUrl: firstImage,
                  category: '',
                  size: 40.w,
                  radius: 10.r,
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text(
                    l10n.comboLegsLabel(p.legsTotal),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: polyCardTitleStyle(c),
                  ),
                ),
                SizedBox(width: 12.w),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: box.maxWidth * 0.45),
                  // An open combo has no price feed: its value is an
                  // estimate and says so; a settled or lost one shows
                  // what it made or lost.
                  child: PortfolioCardValue(
                    value: formatHlUsd(value),
                    pnl: lost || settled != null
                        ? PortfolioCardValue.pnlText(
                            formatHlUsd(pnl.abs()), pnl)
                        : null,
                    up: pnl >= 0,
                    detail: l10n.comboEstimatedValue,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 12.h),
          // Each leg on its own line, written whole, with its state.
          for (final leg in p.legs) _LegLine(leg: leg),
          SizedBox(height: 6.h),
          Row(children: [
            metric(l10n.comboStake, formatHlUsd(p.stakeUsd)),
            metric(l10n.comboPotentialPayout,
                lost ? formatHlUsd(0) : formatHlUsd(p.potentialPayoutUsd)),
            metric(l10n.comboMultiplier,
                lost ? '-' : comboMultiplierText(p.multiplier),
                end: true),
          ]),
        ],
      ),
    );
  }
}

/// One leg as a plain line: its state's glyph and its name.
class _LegLine extends StatelessWidget {
  const _LegLine({required this.leg});
  final ComboLeg leg;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final o = leg.outcome;
    return Padding(
      padding: EdgeInsets.only(bottom: 6.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: 2.h),
            child: Icon(
              semanticLabel: comboLegStatusText(context, o),
              switch (o) {
                ComboLegOutcome.won => Icons.check_circle_rounded,
                ComboLegOutcome.lost => Icons.cancel_rounded,
                ComboLegOutcome.void_ => Icons.remove_circle_outline_rounded,
                ComboLegOutcome.open => Icons.circle_outlined,
              },
              size: 14.sp,
              color: comboLegColor(context, o),
            ),
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              leg.outcomeLabel.isEmpty || leg.outcomeLabel == 'Yes'
                  ? leg.title
                  : '${leg.title}: ${leg.outcomeLabel}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.1,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
