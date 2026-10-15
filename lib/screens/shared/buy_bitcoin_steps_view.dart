// lib/screens/shared/buy_bitcoin_steps_view.dart
//
// A Buy bitcoin's steps (buy_bitcoin_steps.dart) on screen: the move's
// recorded graph brought up to date from what the wallet now knows (each
// leg's Activity row settling, the purchase's order, the bitcoin counted
// by the wallet, the background purchase waiting on the person), shown by
// the one steps widget ([MoneyStepsView]). Live in the Move sheet while
// the move runs and in the move's Activity detail, where it stays as the
// record once done.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/swap_orders_provider.dart'
    show swapOrdersProvider;
import 'package:kute/screens/shared/money_steps_view.dart';
import 'package:kute/screens/shared/multi_source_move_activity.dart'
    show
        multiSourceMoveFinalRow,
        multiSourceMoveLegRow,
        multiSourceMoveLiveRows;
import 'package:kute/services/one_balance/buy_bitcoin_steps.dart';
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/services/one_balance/multi_source_move.dart';
import 'package:kute/services/one_balance/pending_bitcoin_purchase.dart'
    show
        PendingBitcoinPurchase,
        PendingBitcoinPurchaseStore,
        PendingPurchaseStage,
        bitcoinPurchaseFinisherProvider,
        pendingBitcoinPurchasesProvider;
import 'package:kute/services/orchestra/own_spark_arrivals.dart';

bool _rowFailed(SwapOrder d) =>
    OwnSparkArrivals.failedStatuses.contains(d.status);

/// [move]'s steps as they stand: its graph ([BuyBitcoinSteps.of], mapped
/// from its legs for an older record) with what [rows] (the wallet's rows
/// for the move) say since. Only ever moves a step forward or names a
/// stop the rows show:
///
///  * a leg on its way is done once its row settled, failed if its order
///    failed;
///  * the purchase, once sent, is done when its order is (failed if it
///    failed); before that its [purchase] record says where it is:
///    buying (running), waiting on the person (stopped), or waiting for
///    Dollars while it runs ([purchaseRunning]);
///  * the arrival runs once everything before it is done and a delivery
///    to Bitcoin still waits for the wallet to count it, then is done.
///
/// Empty for a move that is not a Buy bitcoin.
MoneyStepGraph liveBuyBitcoinSteps(
  MultiSourceMove move,
  List<SwapOrderTransaction> rows, {
  PendingBitcoinPurchase? purchase,
  bool purchaseRunning = false,
}) {
  var g = BuyBitcoinSteps.of(move);
  if (g.isEmpty) return g;
  final delivering = <SwapOrderTransaction>[];

  for (final s in g.legs.toList()) {
    if (s.ref == null) continue;
    final leg = move.okLegs
        .where((l) => (l.operationId ?? l.quoteId) == s.ref)
        .lastOrNull;
    final row = leg == null ? null : multiSourceMoveLegRow(leg, rows);
    if (row == null) continue;
    if (s.route == MoneyRoute.direct) delivering.add(row);
    if (s.status != MoneyStepStatus.running) continue;
    if (row.details.isComplete) {
      g = g.update(s.id, (x) => x.copyWith(status: MoneyStepStatus.done));
    } else if (_rowFailed(row.details)) {
      g = g.update(
          s.id,
          (x) => x.copyWith(
              status: MoneyStepStatus.failed, reason: 'order_failed'));
    }
  }

  final buy = g.byId(BuyBitcoinSteps.buyId);
  if (buy != null && buy.status != MoneyStepStatus.skipped) {
    if (move.finalOperationId != null) {
      final row = multiSourceMoveFinalRow(move, rows);
      if (row != null) delivering.add(row);
      final status = row == null
          ? MoneyStepStatus.running
          : row.details.isComplete
              ? MoneyStepStatus.done
              : _rowFailed(row.details)
                  ? MoneyStepStatus.failed
                  : MoneyStepStatus.running;
      g = g.update(
          buy.id,
          (x) => x.copyWith(
              status: status,
              ref: move.finalOperationId,
              reason: status == MoneyStepStatus.failed ? 'order_failed' : null,
              clearReason: status != MoneyStepStatus.failed));
    } else if (purchase != null) {
      final status = switch (purchase.stage) {
        PendingPurchaseStage.buying ||
        PendingPurchaseStage.funding =>
          MoneyStepStatus.running,
        PendingPurchaseStage.waiting when purchaseRunning =>
          MoneyStepStatus.waiting,
        // Not running (after a restart no approval survives) or stopped:
        // it waits on the person's tap.
        _ => purchaseRunning ? MoneyStepStatus.running : MoneyStepStatus.failed,
      };
      g = g.update(
          buy.id,
          (x) => x.copyWith(
              status: status,
              reason:
                  status == MoneyStepStatus.failed ? 'needs_approval' : null,
              clearReason: status != MoneyStepStatus.failed));
    }
  }

  final arrive = g.byId(BuyBitcoinSteps.arriveId);
  if (arrive != null && !arrive.status.ended) {
    final ready = arrive.after.every((id) {
      final d = g.byId(id);
      return d == null || d.status.satisfies;
    });
    final anyDelivery = g.steps.any((s) =>
        s.id != arrive.id &&
        (s.kind == MoneyStepKind.buy || s.route == MoneyRoute.direct) &&
        s.status == MoneyStepStatus.done);
    if (ready && anyDelivery) {
      final counting =
          delivering.any((r) => OwnSparkArrivals.awaitingCredit(r.id));
      g = g.update(
          arrive.id,
          (x) => x.copyWith(
              status:
                  counting ? MoneyStepStatus.running : MoneyStepStatus.done));
    }
  }
  return g;
}

/// The lines of [graph] in the app's words, amounts in dollars.
List<MoneyStepLine> buyBitcoinStepLines(
        BuildContext context, MoneyStepGraph graph) =>
    moneyStepLines(context.l10n, graph, (usd) => '\$${usd.toStringAsFixed(2)}');

/// A Buy bitcoin's steps, live: [move] as the store holds it now, its
/// rows from the wallet's swap orders ([rows] are what the surface already
/// had; [followRows] false reads [rows] alone: the Move sheet, which
/// closes once every leg is submitted). Nothing for a move that is not a
/// Buy bitcoin.
class BuyBitcoinStepsSection extends ConsumerWidget {
  const BuyBitcoinStepsSection({
    super.key,
    required this.move,
    this.rows = const [],
    this.followRows = true,
  });

  final MultiSourceMove move;
  final List<SwapOrderTransaction> rows;
  final bool followRows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!BuyBitcoinSteps.describes(move)) return const SizedBox.shrink();
    ref.watch(pendingBitcoinPurchasesProvider);
    ref.watch(ownSparkArrivalsProvider);
    final live = followRows
        ? multiSourceMoveLiveRows(move, rows, ref.watch(swapOrdersProvider))
        : rows;
    final graph = liveBuyBitcoinSteps(
      move,
      live,
      purchase: PendingBitcoinPurchaseStore.get(move.id),
      purchaseRunning:
          ref.read(bitcoinPurchaseFinisherProvider).running(move.id),
    );
    if (graph.isEmpty) return const SizedBox.shrink();
    final lines = buyBitcoinStepLines(context, graph);
    if (lines.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: MoneyStepsView(lines: lines),
    );
  }
}
