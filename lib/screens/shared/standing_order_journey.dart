// lib/screens/shared/standing_order_journey.dart
//
// The money journey of a standing order (founder, 9 November 2026: "if
// we're clicking the placing order then we show the Sal animation that
// we already have, of the transfer and such"): the same steps the slip
// showed while it was open ([SlipFundingSteps] over the funded order's
// step graph: the walking Sal, the route, the checkpoints), on a sheet the
// person can leave at any time while the order goes on. Opens from the
// pending Activity row, the Overview's placing row and Sal's toasts (right
// after the accept the slip itself stays up, locked, with the same steps;
// bet_slip_sheet.dart). Cancel, the bar's own button, is offered while the
// order has not left for the venue.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart'
    show formatDollars;
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/slip_shortfall.dart'
    show SlipFundingSteps, fundedStopLine;
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/money_steps.dart' show MoneyPlace;
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/standing_orders/standing_orders_provider.dart';
import 'package:kute/theme/app_theme.dart';

class StandingOrderJourneySheet extends ConsumerWidget {
  const StandingOrderJourneySheet(
      {super.key, this.standingOrderId, this.venue, this.marketKey});

  /// The order by id, or the open one on [venue] and [marketKey] (the slip
  /// opens the journey the moment it closes, before the standing order
  /// has its id).
  final String? standingOrderId;
  final StandingOrderVenue? venue;
  final String? marketKey;

  static Future<void> show(BuildContext context,
      {String? standingOrderId, StandingOrderVenue? venue, String? marketKey}) {
    return showAppBottomSheet<void>(
      context: context,
      builder: (_) => AppBottomSheetContainer(
        child: StandingOrderJourneySheet(
            standingOrderId: standingOrderId, venue: venue, marketKey: marketKey),
      ),
    );
  }

  StandingOrder? _find(List<StandingOrder> all) {
    final id = standingOrderId;
    if (id != null) return all.where((o) => o.id == id).firstOrNull;
    StandingOrder? found;
    for (final o in all) {
      if (o.venue == venue && o.marketKey == marketKey && o.isOpen) found = o;
    }
    return found;
  }

  /// What the sheet says over the steps, by the order's state.
  static String titleFor(AppLocalizations l10n, StandingOrder order) {
    final predictions = order.venue == StandingOrderVenue.predictions;
    return switch (order.state) {
      StandingOrderState.filled =>
        predictions ? l10n.standingPredictionPlaced : l10n.standingOrderPlaced,
      StandingOrderState.failed =>
        predictions ? l10n.standingPredictionFailed : l10n.standingOrderFailed,
      StandingOrderState.cancelled => predictions
          ? l10n.standingPredictionCancelled
          : l10n.standingOrderCancelled,
      StandingOrderState.needsApproval =>
        l10n.standingPriceMoved(_percent(order.movedToPrice)),
      _ => predictions
          ? l10n.standingPlacingPrediction
          : l10n.standingPlacingOrder,
    };
  }

  static String _percent(double? price) =>
      price == null ? '' : '${(price * 100).round()}%';

  /// The step the standing state is at, in the slip's own two steps
  /// (getting ready, placing), when no funded record is there to say.
  static int activeStepFor(StandingOrderState state) => switch (state) {
        StandingOrderState.funding || StandingOrderState.funded => 0,
        StandingOrderState.posting ||
        StandingOrderState.posted ||
        StandingOrderState.needsApproval ||
        StandingOrderState.failed ||
        StandingOrderState.cancelled =>
          1,
        StandingOrderState.filled => 2,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = context.colors;
    final found = ref.watch(standingOrdersProvider.select(_find));
    final key = found?.marketKey ?? marketKey;
    final standingVenue = found?.venue ?? venue;
    if (key == null || standingVenue == null) {
      return SizedBox(height: 120.h);
    }
    final oneBalanceVenue = standingVenue == StandingOrderVenue.predictions
        ? OneBalanceVenue.predictions
        : OneBalanceVenue.investing;
    final progress = FundedOrdersNotifier.progressOn(
        ref.watch(fundedOrdersProvider), oneBalanceVenue, key, DateTime.now());
    // Before the standing order has its record (the slip just closed):
    // the funded order's own facts stand in, placing.
    final order = found ??
        StandingOrder(
          id: '',
          walletId: '',
          venue: standingVenue,
          marketKey: key,
          marketTitle: progress?.record.label.market ?? '',
          sideLabel: progress?.record.label.side ?? '',
          isBuy: true,
          size: 0,
          approvedPrice: 0,
          amountUsd: progress?.record.label.orderUsd ?? 0,
          orderKind: 'market',
          state: StandingOrderState.funding,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
    final to = standingVenue == StandingOrderVenue.predictions
        ? MoneyPlace.predictions
        : MoneyPlace.investing;
    final placeLine = standingVenue == StandingOrderVenue.predictions
        ? l10n.slipStepPlacingBet(
            formatDollars(order.amountUsd), order.sideLabel)
        : l10n.slipStepOpeningOrder(formatDollars(order.amountUsd),
            order.sideLabel, order.marketTitle);
    final readyLine = standingVenue == StandingOrderVenue.predictions
        ? l10n.slipStepPreparingPrediction
        : l10n.slipStepPreparingOrder;
    final Widget steps;
    if (progress != null) {
      final record = progress.record;
      steps = SlipFundingSteps(
        steps: [
          if (record.fromBitcoin)
            l10n.slipStepAddingToInvestments(formatDollars(record.addUsd)),
          readyLine,
          placeLine,
        ],
        active: progress.active,
        slow: record.slow,
        failed: progress.failed,
        graph: record.steps,
        money: formatDollars,
        from: record.fromBitcoin ? MoneyPlace.bitcoin : MoneyPlace.dollars,
        to: to,
        note: progress.failed
            ? fundedStopLine(l10n, record, formatDollars)
            : null,
      );
    } else {
      final failed = order.state == StandingOrderState.failed ||
          order.state == StandingOrderState.needsApproval;
      steps = SlipFundingSteps(
        steps: [readyLine, placeLine],
        active: activeStepFor(order.state),
        failed: failed,
        from: MoneyPlace.dollars,
        to: to,
        note: failed ? titleFor(l10n, order) : null,
      );
    }
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20.w, 18.h, 20.w, 12.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              titleFor(l10n, order),
              key: const ValueKey('standing-journey-title'),
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 18.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              order.marketTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.textSecondary, fontSize: 13.sp),
            ),
            SizedBox(height: 14.h),
            steps,
            // Cancel is the bar's own button, Sal working on it, while the
            // order has not left for the venue (founder, 10 November 2026:
            // "the cancel should be sal button"), as on the slip.
            if (order.canCancel && order.id.isNotEmpty)
              KuteBarContextScope(
                barContext: KuteBarContext.primary(
                  label: l10n.cancel,
                  onPrimary: () {
                    // The order is cancelled at once (its state changes
                    // before anything is persisted): the sheet closes now.
                    unawaited(ref
                        .read(standingOrdersProvider.notifier)
                        .cancel(order.id));
                    Navigator.of(context).pop();
                  },
                  busy: true,
                  tapWhileBusy: true,
                  busyLabel: l10n.cancel,
                  source: 'standing_order',
                  // Never waits on input.
                  disabledLabel: null,
                ),
                child: SizedBox(
                    key: const ValueKey('standing-journey-cancel'),
                    height: kuteBarScrollClearance.h),
              ),
          ],
        ),
      ),
    );
  }
}
