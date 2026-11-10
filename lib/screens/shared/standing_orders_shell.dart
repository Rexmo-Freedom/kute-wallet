// lib/screens/shared/standing_orders_shell.dart
//
// The standing orders' hooks into the app shell (mounted once, in the
// app's Stack beside the navigator, drawing nothing):
//
//  * RESUME on start and on every unlock: the wallet's standing orders
//    are loaded and carried on (standing_orders_provider.dart).
//  * NOTHING WHILE IT PLACES (founder, 10 November 2026, on 2.2.0 (98): no
//    "thinking" placing indicator once the slip is gone): the order's one
//    card on the Dollars Overview says Placing, and its journey keeps
//    Cancel (standing_order_journey.dart).
//  * RESULT: an order filled plays the money-success haptic and Sal says
//    "Prediction placed" / "Order placed"; one that failed plays the
//    failure tap and Sal says where the money is; one the person
//    cancelled, Sal says so (standing_order_toasts.dart).
//  * PRICE MOVED past the approval: Sal says the new price with one tap
//    that opens the slip at it (its own Face ID places it, from the money
//    already on the venue), or the order is cancelled from the toast or
//    its journey.
//
// This widget's context sits beside the navigator, with no overlay and no
// navigator above it: the toasts draw on the root overlay and the sheets
// open from the root navigator (root_navigator.dart), never from here.
// That context was the 2.2.0 (95) toasts' silence ("Sal toast did not
// show").

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/helpers/root_navigator.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart' show PolymarketOutcome;
import 'package:kute/providers/auth_provider.dart' show sessionUnlockedProvider;
import 'package:kute/screens/polymarket/components/bet_slip_sheet.dart'
    show BetSlipSheet;
import 'package:kute/screens/shared/sal_toast.dart';
import 'package:kute/screens/shared/standing_order_toasts.dart';
import 'package:kute/services/standing_orders/standing_orders_provider.dart';

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
    ref.listenManual<List<StandingOrder>>(standingOrdersProvider, _onOrders);
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

  void _onOrders(List<StandingOrder>? prev, List<StandingOrder> next) {
    if (!mounted) return;
    final before = {for (final o in prev ?? const <StandingOrder>[]) o.id: o};
    final l10n = context.l10n;
    for (final o in next) {
      final was = before[o.id];
      if (o.state == StandingOrderState.needsApproval &&
          _askedApproval.add(o.id)) {
        _askApproval(o);
        continue;
      }
      if (was == null || was.state == o.state) continue;
      if (o.state == StandingOrderState.cancelled) {
        StandingOrderToasts.cancelled(context, l10n, o);
      }
    }
  }

  void _onOutcome(StandingOrder order) {
    if (!mounted) return;
    final l10n = context.l10n;
    // The toast plays the success beat or the failure tap as it lands.
    switch (order.state) {
      case StandingOrderState.filled:
        StandingOrderToasts.placed(context, l10n, order);
      case StandingOrderState.failed:
        StandingOrderToasts.failed(context, l10n, order);
      default:
        break;
    }
  }

  /// The price moved past what was approved: one tap opens the slip at
  /// the new price (the money is already on the venue; the slip's own
  /// Face ID places it), the standing order itself ends there. Cancel in
  /// the pill cancels it.
  void _askApproval(StandingOrder order) {
    if (!mounted) return;
    final l10n = context.l10n;
    final container = ProviderScope.containerOf(context, listen: false);
    final price = order.movedToPrice ?? order.approvedPrice;
    SalToast.show(
      context,
      tag: StandingOrderToasts.tagOf(order),
      message: l10n.standingPriceMoved('${(price * 100).round()}%'),
      detail: order.marketTitle,
      tone: SalToastTone.pending,
      sticky: true,
      actionLabel: l10n.cancel,
      onAction: () => unawaited(
          container.read(standingOrdersProvider.notifier).cancel(order.id)),
      onTap: () {
        unawaited(container.read(standingOrdersProvider.notifier).advance(
            order.id, StandingOrderState.failed,
            failureCode: 'price_moved', quiet: true));
        final root = kuteRootContext();
        if (root == null) return;
        unawaited(BetSlipSheet.show(
          root,
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
      },
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
