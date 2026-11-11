// lib/screens/shared/standing_orders_section.dart
//
// The standing orders in flight at the top of an Activity list: each one
// the row its venue already draws for a bet on its way ([PlacingBetRow];
// an Investing order on the same [PortfolioPositionRow]), its step as the
// facts, the stake as the number. A tap opens the order's money journey
// ([StandingOrderJourneySheet]), where it can be cancelled before it
// leaves for the venue. Nothing new is drawn.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart'
    show formatDollars;
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/placing_polymarket_bet_provider.dart'
    show PlacingBet, PlacingBetStatus;
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart'
    show formatHlSize, hlFriendlyName;
import 'package:kute/screens/portfolio/components/position_rows.dart'
    show PlacingBetRow, PortfolioPositionRow, kPortfolioRowImage;
import 'package:kute/screens/shared/standing_order_journey.dart';
import 'package:kute/services/standing_orders/standing_orders_provider.dart';

/// What the row says of a standing order's state, in the venue's words.
String standingOrderRowStatus(AppLocalizations l10n, StandingOrder order) {
  final predictions = order.venue == StandingOrderVenue.predictions;
  return switch (order.state) {
    StandingOrderState.needsApproval =>
      l10n.standingPriceMoved('${((order.movedToPrice ?? 0) * 100).round()}%'),
    StandingOrderState.filled =>
      predictions ? l10n.standingPredictionPlaced : l10n.standingOrderPlaced,
    StandingOrderState.failed =>
      predictions ? l10n.standingPredictionFailed : l10n.standingOrderFailed,
    _ => predictions
        ? l10n.standingPlacingPrediction
        : l10n.standingPlacingOrder,
  };
}

/// What the Dollars Overview's one card says of a standing order, in the
/// compact words (dollars_activity_tab.dart): Placing from the accept
/// until it fills (the money moving included), waiting for the person
/// when the price moved. Filled: nothing (null), the card is the
/// position's own, as the Portfolio lists it (founder, 11 November 2026,
/// on 2.2.0 (103): "don't say prediction placed or order placed, after it
/// is placed, show the same card as in the portfolio").
String? standingOrderStageLine(AppLocalizations l10n, StandingOrder order) =>
    switch (order.state) {
      StandingOrderState.needsApproval => l10n.standingStageApproval,
      StandingOrderState.filled => null,
      _ => l10n.standingStagePlacing,
    };

/// The standing orders still in flight, newest first; nothing when there
/// are none.
class StandingOrdersSection extends ConsumerWidget {
  const StandingOrdersSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(standingOrdersProvider
        .select((all) => [for (final o in all) if (o.isOpen) o]));
    if (open.isEmpty) return const SizedBox.shrink();
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final o in open.reversed)
          GestureDetector(
            key: ValueKey('standing-row-${o.id}'),
            behavior: HitTestBehavior.opaque,
            onTap: () => StandingOrderJourneySheet.show(context,
                standingOrderId: o.id),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: StandingOrderRow(order: o, status: standingOrderRowStatus(l10n, o)),
            ),
          ),
      ],
    );
  }
}

/// One standing order as the venue's own row (in whatever shape the
/// layout above asks: Activity's line, the Overview's square or card),
/// the very row its position will list as: the market, the side, and the
/// money in it (the stake, then the fill's own figures once filled,
/// [StandingOrder.placedUsd]).
class StandingOrderRow extends StatelessWidget {
  const StandingOrderRow(
      {super.key, required this.order, required this.status, this.onTap});

  final StandingOrder order;

  /// The order's word in place of the position's own line; null (filled)
  /// and the row reads as the listed position will.
  final String? status;

  /// Null: the row taps through nothing of its own (Activity wraps it).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    switch (order.venue) {
      case StandingOrderVenue.predictions:
        return PlacingBetRow(
          bet: PlacingBet(
            placementId: order.id,
            tokenId: order.marketKey,
            marketQuestion: order.marketTitle,
            eventSlug: order.eventSlug,
            marketImage: order.marketImage,
            outcomeName: order.sideLabel,
            amount: order.placedUsd,
            shares: order.filledSize ?? order.size,
            avgPrice: order.approvedPrice,
            status: order.state == StandingOrderState.failed
                ? PlacingBetStatus.failed
                : PlacingBetStatus.placing,
            startedAt: order.createdAt,
            stepLabel: status,
          ),
          showStep: status != null,
          onTap: onTap,
        );
      case StandingOrderVenue.investing:
        final l10n = context.l10n;
        // The side as the listed row says it (HlPositionRow, HlSpotRow).
        final side = order.marketKind == 'spot'
            ? l10n.investingSpot
            : order.isBuy
                ? l10n.longLabel
                : l10n.shortLabel;
        return PortfolioPositionRow(
          leading: ClipOval(
            // The logo under the coin the venue holds it by, as the
            // listed row (a builder dex's perp: "xyz:NVDA").
            child: HlCoinIcon(
                coin: order.marketKey,
                wireCoin:
                    order.marketKind == 'spot' ? null : order.positionCoin,
                size: kPortfolioRowImage.w),
          ),
          // The listed row's name for the coin where it has one.
          title: hlFriendlyName(order.marketKey) ?? order.marketTitle,
          subtitle: status != null
              ? '$side · $status'
              // Filled: the listed row's own line (HlPositionRow,
              // HlSpotRow).
              : order.marketKind == 'spot'
                  ? '${formatHlSize(order.filledSize ?? order.size)} '
                      '${order.marketKey} · $side'
                  : '$side · ${formatHlSize(order.filledSize ?? order.size)} '
                      '${order.marketKey}',
          chip: side,
          value: formatDollars(order.placedUsd),
          onTap: onTap,
        );
    }
  }
}
