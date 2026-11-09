// lib/screens/shared/standing_orders_shell.dart
//
// The standing orders' hooks into the app shell (mounted once, in the
// app's Stack, drawing nothing):
//
//  * RESUME on start and on every unlock: the wallet's standing orders
//    are loaded and carried on (standing_orders_provider.dart).
//  * RESULT: an order filled plays the money-success haptic and Sal says
//    "Prediction placed" / "Order placed"; one that failed plays the
//    failure tap and Sal says where the money is (sal_notices.dart).
//  * PRICE MOVED past the approval: Sal says the new price with one tap
//    that opens the slip at it (its own Face ID places it, from the money
//    already on the venue), or the order is cancelled from its journey.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart' show PolymarketOutcome;
import 'package:kute/providers/auth_provider.dart' show sessionUnlockedProvider;
import 'package:kute/screens/polymarket/components/bet_slip_sheet.dart'
    show BetSlipSheet;
import 'package:kute/screens/shared/sal_notices.dart';
import 'package:kute/screens/shared/standing_order_journey.dart';
import 'package:kute/services/standing_orders/standing_orders_provider.dart';
import 'package:kute/services/success_feedback.dart'
    show moneyFailureFeedback, moneySuccessFeedback;

class StandingOrdersShell extends ConsumerStatefulWidget {
  const StandingOrdersShell({super.key});

  @override
  ConsumerState<StandingOrdersShell> createState() =>
      _StandingOrdersShellState();
}

class _StandingOrdersShellState extends ConsumerState<StandingOrdersShell> {
  StreamSubscription<StandingOrder>? _outcomes;
  final Set<String> _askedApproval = {};

  @override
  void initState() {
    super.initState();
    final notifier = ref.read(standingOrdersProvider.notifier);
    _outcomes = notifier.outcomes.listen(_onOutcome);
    ref.listenManual<bool>(sessionUnlockedProvider, (prev, next) {
      if (next && prev != true) _resume();
    });
    ref.listenManual<List<StandingOrder>>(standingOrdersProvider, (prev, next) {
      for (final o in next) {
        if (o.state == StandingOrderState.needsApproval &&
            _askedApproval.add(o.id)) {
          _askApproval(o);
        }
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(sessionUnlockedProvider)) _resume();
    });
  }

  void _resume() {
    unawaited(ref.read(standingOrdersProvider.notifier).resume());
  }

  @override
  void dispose() {
    _outcomes?.cancel();
    super.dispose();
  }

  void _onOutcome(StandingOrder order) {
    if (!mounted) return;
    final l10n = context.l10n;
    final predictions = order.venue == StandingOrderVenue.predictions;
    switch (order.state) {
      case StandingOrderState.filled:
        unawaited(moneySuccessFeedback());
        SalNotices.placed(context,
            message: predictions
                ? l10n.standingPredictionPlaced
                : l10n.standingOrderPlaced,
            detail: order.marketTitle);
      case StandingOrderState.failed:
        unawaited(moneyFailureFeedback());
        SalNotices.failed(context,
            message: predictions
                ? l10n.standingPredictionFailed
                : l10n.standingOrderFailed,
            detail: order.marketTitle,
            onTap: () => StandingOrderJourneySheet.show(context,
                standingOrderId: order.id));
      default:
        break;
    }
  }

  /// The price moved past what was approved: one tap opens the slip at
  /// the new price (the money is already on the venue; the slip's own
  /// Face ID places it), the standing order itself ends there.
  void _askApproval(StandingOrder order) {
    if (!mounted) return;
    final l10n = context.l10n;
    final price = order.movedToPrice ?? order.approvedPrice;
    SalNotices.pending(context,
        message: l10n.standingPriceMoved('${(price * 100).round()}%'),
        detail: order.marketTitle, onTap: () {
      if (!mounted) return;
      unawaited(ref.read(standingOrdersProvider.notifier).advance(
          order.id, StandingOrderState.failed,
          failureCode: 'price_moved', quiet: true));
      unawaited(BetSlipSheet.show(
        context,
        marketQuestion: order.marketTitle,
        marketSlug: order.eventSlug,
        marketImage: order.marketImage,
        outcomes: [
          PolymarketOutcome(
            name: order.sideLabel,
            price: price,
            tokenId: order.marketKey,
          ),
        ],
        marketEndAt: order.marketEndAt,
        marketCategory: order.marketCategory,
        negRisk: order.negRisk,
        initialAmountUsd: order.amountUsd,
        source: 'standing_order',
      ));
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
