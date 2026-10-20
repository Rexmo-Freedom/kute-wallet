// lib/screens/shared/move_steps_view.dart
//
// A move's steps (move_steps.dart) on screen: the move's recorded graph
// brought up to date from what the wallet now knows (each leg's Activity
// row settling, the action's own step's row, the bitcoin counted by the
// wallet, a background purchase waiting on the person), shown by the one
// steps widget ([MoneyStepsView]) in its own look. Live while the move
// runs (the Move sheet, the Send screen) and in the move's Activity
// detail, where it stays as the record once done. A single move (one row:
// Add to Investments from Bitcoin, a purchase paid by Dollars alone, a
// venue's cash going home) reads its steps from its row
// ([SwapRowStepsSection]).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/helpers/orchestra_router.dart' show orchestraRowAmount;
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/swap_orders_provider.dart'
    show swapOrdersProvider;
import 'package:kute/screens/shared/money_steps_view.dart';
import 'package:kute/screens/shared/multi_source_move_activity.dart'
    show
        multiSourceMoveFinalRow,
        multiSourceMoveInitialDollarsRow,
        multiSourceMoveLegRow,
        multiSourceMoveLiveRows;
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/services/one_balance/move_steps.dart';
import 'package:kute/services/one_balance/multi_source_move.dart';
import 'package:kute/services/one_balance/pending_bitcoin_purchase.dart'
    show
        PendingBitcoinPurchase,
        bitcoinPurchaseMoveForDisplay,
        PendingBitcoinPurchaseStore,
        PendingPurchaseStage,
        bitcoinPurchaseFinisherProvider,
        pendingBitcoinPurchasesProvider;
import 'package:kute/services/orchestra/own_spark_arrivals.dart';
import 'package:kute/services/funding/settlement_store.dart';
import 'package:kute/services/hyperliquid/cctp_withdrawal.dart'
    show CctpLegProgress, cctpLegProgressOf, kCctpRowPrefix;
import 'package:kute/services/orchestra/standing_deposit_activity.dart'
    show
        kHypercoreCctpBtcRouteVersion,
        kHypercoreCctpPredictionsRouteVersion,
        kHypercoreCctpRouteVersion;

bool _rowFailed(SwapOrder d) =>
    OwnSparkArrivals.failedStatuses.contains(d.status);

/// Whether [row] is an Investing move by Circle CCTP (its Arbitrum leg
/// while no order exists, or the order it became).
bool isCctpMoveRow(SwapOrder row) =>
    row.id.startsWith(kCctpRowPrefix) ||
    const {
      kHypercoreCctpRouteVersion,
      kHypercoreCctpBtcRouteVersion,
      kHypercoreCctpPredictionsRouteVersion,
    }.contains(row.routeVersion);

/// Where the CCTP legs are read from (the app's settlement store).
final cctpLegStoreProvider = Provider<Future<SettlementStore> Function()>(
    (ref) => SettlementStore.shared);

/// A CCTP move's legs as its settlement record has them, read again every
/// few seconds while a detail shows them (the timer goes with the detail).
final cctpLegProgressProvider = FutureProvider.autoDispose
    .family<CctpLegProgress?, String>((ref, operationId) async {
  final again = Timer(const Duration(seconds: 4), ref.invalidateSelf);
  ref.onDispose(again.cancel);
  try {
    final store = await ref.read(cctpLegStoreProvider)();
    final op = await store.get(operationId);
    return op == null ? null : cctpLegProgressOf(op);
  } catch (_) {
    return null;
  }
});

/// A CCTP move's legs as sub-steps under its line: HyperCore's withdrawal
/// ("HyperCore → Circle"), Circle's mint on Arbitrum ("Circle → Arbitrum")
/// and Orchestra's order ("Arbitrum → [destination]"), each done on its
/// own. The network names are proper nouns; the line is the compact one.
List<MoneyStepLine> cctpLegLines(
  AppLocalizations l10n,
  CctpLegProgress p, {
  required String destination,
  required bool rowDone,
  required bool rowFailed,
  String Function(double usd)? money,
  String idPrefix = 'cctp',
}) {
  final fmt = money ?? (usd) => '\$${usd.toStringAsFixed(2)}';
  final MoneyStepStatus burn;
  if (p.burned) {
    burn = MoneyStepStatus.done;
  } else if (p.failed || rowFailed) {
    burn = MoneyStepStatus.failed;
  } else {
    burn = MoneyStepStatus.running;
  }
  final MoneyStepStatus mint;
  if (p.minted) {
    mint = MoneyStepStatus.done;
  } else if (p.burned) {
    mint = MoneyStepStatus.running;
  } else {
    mint = MoneyStepStatus.waiting;
  }
  final MoneyStepStatus order;
  if (rowDone) {
    order = MoneyStepStatus.done;
  } else if (rowFailed && p.burned) {
    order = MoneyStepStatus.failed;
  } else if (p.minted || p.ordered) {
    order = MoneyStepStatus.running;
  } else {
    order = MoneyStepStatus.waiting;
  }
  // Each sub-leg is a waypoint on the leg's road (money_steps_view): the
  // place it reaches ([MoneyStepLine.hop]), its amount beside it, and the
  // short words the status line says while it runs.
  return [
    MoneyStepLine(
        l10n.moneyStepCompact('HyperCore', 'Circle', fmt(p.sentUsd)), burn,
        sub: true,
        id: '$idPrefix:burn',
        hop: 'Circle',
        amount: fmt(p.sentUsd),
        brief: 'HyperCore → Circle'),
    MoneyStepLine(
        l10n.moneyStepCompact('Circle', 'Arbitrum', fmt(p.mintUsd)), mint,
        sub: true,
        id: '$idPrefix:mint',
        hop: 'Arbitrum',
        amount: fmt(p.mintUsd),
        brief: 'Circle → Arbitrum'),
    MoneyStepLine(
        l10n.moneyStepCompact('Arbitrum', destination, fmt(p.mintUsd)), order,
        sub: true,
        id: '$idPrefix:order',
        hop: destination,
        amount: fmt(p.mintUsd),
        brief: 'Arbitrum → $destination'),
  ];
}

/// The destination name of a CCTP move's row.
String _cctpDestinationName(AppLocalizations l10n, SwapOrder row) {
  final place = MoveSteps.placeOfAsset(row.coinTo, row.networkTo);
  return moneyPlaceName(l10n, place ?? MoneyPlace.dollars);
}

/// [lines] with a CCTP move's legs under the line of each step whose row
/// ([rowOf]) is one.
List<MoneyStepLine> _withCctpLegs(WidgetRef ref, AppLocalizations l10n,
    List<MoneyStepLine> lines, SwapOrder? Function(String? lineId) rowOf) {
  final out = <MoneyStepLine>[];
  for (final line in lines) {
    out.add(line);
    if (line.sub) continue;
    final row = rowOf(line.id);
    final operationId = row?.operationId;
    if (row == null || operationId == null || !isCctpMoveRow(row)) continue;
    final progress =
        ref.watch(cctpLegProgressProvider(operationId)).valueOrNull;
    if (progress == null) continue;
    out.addAll(cctpLegLines(l10n, progress,
        destination: _cctpDestinationName(l10n, row),
        rowDone: row.isComplete,
        rowFailed: _rowFailed(row),
        idPrefix: 'cctp:${line.id}'));
  }
  return out;
}

/// [move]'s steps as they stand: its graph ([MoveSteps.of], mapped from
/// its legs for an older record) with what [rows] (the wallet's rows for
/// the move) say since. Only ever moves a step forward or names a stop the
/// rows show:
///
///  * a leg on its way is done once its row settled, failed if its order
///    failed;
///  * the action's own step (the purchase, the send, Dollars going on into
///    the venue), once sent, is done when its row is (failed if it
///    failed); before that a purchase's [purchase] record says where it
///    is: buying (running), waiting on the person (stopped), or waiting
///    for Dollars while it runs ([purchaseRunning]);
///  * the arrival runs once everything before it is done and a delivery
///    to Bitcoin still waits for the wallet to count it, then is done.
MoneyStepGraph liveMoveSteps(
  MultiSourceMove move,
  List<SwapOrderTransaction> rows, {
  PendingBitcoinPurchase? purchase,
  bool purchaseRunning = false,
}) {
  move = bitcoinPurchaseMoveForDisplay(move);
  var g = MoveSteps.of(move);
  if (g.isEmpty) return g;
  final delivering = <SwapOrderTransaction>[];

  for (final s in g.steps.where(MoveSteps.isVenueLeg).toList()) {
    if (s.ref == null) continue;
    final leg = move.legs
        .where((l) => (l.operationId ?? l.quoteId) == s.ref)
        .lastOrNull;
    final row = s.id == MoveSteps.initialDollarsId
        ? multiSourceMoveInitialDollarsRow(move, rows)
        : leg == null
            ? null
            : multiSourceMoveLegRow(leg, rows);
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

  final fin = MoveSteps.finalOf(g);
  if (fin != null && fin.status != MoneyStepStatus.skipped) {
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
          fin.id,
          (x) => x.copyWith(
              status: status,
              ref: move.finalOperationId,
              reason: status == MoneyStepStatus.failed ? 'order_failed' : null,
              clearReason: status != MoneyStepStatus.failed));
    } else if (purchase != null && fin.id == MoveSteps.buyId) {
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
          fin.id,
          (x) => x.copyWith(
              status: status,
              reason:
                  status == MoneyStepStatus.failed ? 'needs_approval' : null,
              clearReason: status != MoneyStepStatus.failed));
    }
  }

  final arrive = g.byId(MoveSteps.arriveId);
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

/// The lines of [graph] in the app's words, amounts in dollars. The send
/// (a leg from Dollars that leaves the wallet) reads "Sending $50.00",
/// then "Sent $50.00".
List<MoneyStepLine> moveStepLines(AppLocalizations l10n, MoneyStepGraph graph,
    {String Function(double usd)? money}) {
  final fmt = money ?? (usd) => '\$${usd.toStringAsFixed(2)}';
  final lines = moneyStepLines(l10n, graph, fmt);
  final send = graph.byId(MoveSteps.sendId);
  if (send == null) return lines;
  return [
    for (final line in lines)
      line.id == MoveSteps.sendId
          ? MoneyStepLine(
              switch (send.status) {
                MoneyStepStatus.done => l10n.moneyStepSent(fmt(send.usd)),
                MoneyStepStatus.failed => l10n.moneyStepMoveFailed(
                    fmt(send.usd), l10n.portfolioBalanceDollars),
                _ => l10n.moneyStepSending(fmt(send.usd)),
              },
              line.status,
              sub: line.sub,
              id: line.id)
          : line,
  ];
}

bool _dollarCoin(String coin) {
  final upper = coin.toUpperCase();
  return upper == 'USDC' ||
      upper == 'USDC.E' ||
      upper == 'USDT' ||
      upper == 'PUSD' ||
      upper == 'USDB';
}

/// The dollars each step of [move] landed, by step id: a leg's or the own
/// step's row once it settled into dollars (what arrived, not what left).
/// A step whose row is not settled, or settled into bitcoin, has none.
Map<String, double> moveStepLandedUsd(MultiSourceMove move,
    MoneyStepGraph graph, List<SwapOrderTransaction> rows) {
  double? landed(SwapOrderTransaction? row) {
    final d = row?.details;
    if (d == null || !d.isComplete || !_dollarCoin(d.coinTo)) return null;
    final got = d.isOrchestra
        ? orchestraRowAmount(d.withdrawalAmount, d.coinTo)
        : double.tryParse(d.withdrawalAmount) ?? 0;
    return got > 0 ? (got * 100).round() / 100 : null;
  }

  final out = <String, double>{};
  for (final s in graph.steps) {
    final ref = s.ref;
    if (ref == null) continue;
    SwapOrderTransaction? row;
    if (MoveSteps.finalIds.contains(s.id)) {
      row = multiSourceMoveFinalRow(move, rows);
    } else if (MoveSteps.isVenueLeg(s)) {
      final leg = move.okLegs
          .where((l) => (l.operationId ?? l.quoteId) == ref)
          .lastOrNull;
      row = leg == null ? null : multiSourceMoveLegRow(leg, rows);
    }
    final usd = landed(row);
    if (usd != null) out[s.id] = usd;
  }
  return out;
}

/// [graph] as the compact lines of a move's Activity detail: one per step,
/// "Investing → Dollars · $20.69" (what landed once known, else what the
/// step moves), its icon saying where it is. The purchase reads "Dollars →
/// Bitcoin · $8.00", the send "Dollars → [sendTo] · $50.00"; the arrival
/// and a route change keep their own words.
List<MoneyStepLine> moveStepCompactLines(
  AppLocalizations l10n,
  MoneyStepGraph graph, {
  Map<String, double> landedUsd = const {},
  String? sendTo,
  String Function(double usd)? money,
}) {
  final fmt = money ?? (usd) => '\$${usd.toStringAsFixed(2)}';
  final full = moveStepLines(l10n, graph, money: fmt);
  final byId = {for (final s in graph.steps) s.id: s};
  return [
    for (final line in full)
      if (byId[line.id] case final s?)
        switch (s) {
          _ when s.status == MoneyStepStatus.fellBack => line,
          _ when s.kind == MoneyStepKind.arrive => line,
          _ when s.kind == MoneyStepKind.buy || s.kind == MoneyStepKind.leg =>
            MoneyStepLine(
                s.id == MoveSteps.sendId && sendTo == null
                    ? line.text
                    : l10n.moneyStepCompact(
                        moneyPlaceName(l10n, s.from ?? MoneyPlace.dollars),
                        s.id == MoveSteps.sendId
                            ? sendTo!
                            : moneyPlaceName(l10n, s.to ?? MoneyPlace.dollars),
                        fmt(landedUsd[s.id] ?? s.usd)),
                line.status,
                sub: line.sub,
                id: line.id,
                // Done, the status line says only the amount: the
                // stations above already name where it went.
                brief: line.status != MoneyStepStatus.done ||
                        (s.id == MoveSteps.sendId && sendTo == null)
                    ? null
                    : fmt(landedUsd[s.id] ?? s.usd)),
          _ => line,
        }
      else
        line,
  ];
}

/// A move's steps, live: [move] as the store holds it now, its rows from
/// the wallet's swap orders ([rows] are what the surface already had;
/// [followRows] false reads [rows] alone: a sheet that closes once every
/// leg is submitted). Nothing for a move with no steps. [compact] is the
/// Activity detail's form ([moveStepCompactLines]; [sendTo] names where a
/// send went). [failureHaptic] false: the surface plays the failure tap
/// for the same stop itself (`MoneyStepsView.failureHaptic`).
class MoveStepsSection extends ConsumerWidget {
  const MoveStepsSection({
    super.key,
    required this.move,
    this.rows = const [],
    this.followRows = true,
    this.compact = false,
    this.sendTo,
    this.failureHaptic = true,
  });

  final MultiSourceMove move;
  final List<SwapOrderTransaction> rows;
  final bool followRows;
  final bool compact;
  final String? sendTo;
  final bool failureHaptic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(pendingBitcoinPurchasesProvider);
    ref.watch(ownSparkArrivalsProvider);
    final live = followRows
        ? multiSourceMoveLiveRows(move, rows, ref.watch(swapOrdersProvider))
        : rows;
    final graph = liveMoveSteps(
      move,
      live,
      purchase: PendingBitcoinPurchaseStore.get(move.id),
      purchaseRunning:
          ref.read(bitcoinPurchaseFinisherProvider).running(move.id),
    );
    if (graph.isEmpty) return const SizedBox.shrink();
    final display = bitcoinPurchaseMoveForDisplay(move);
    final lines = _withCctpLegs(
        ref,
        context.l10n,
        compact
            ? moveStepCompactLines(context.l10n, graph,
                landedUsd: moveStepLandedUsd(move, graph, live), sendTo: sendTo)
            : moveStepLines(context.l10n, graph), (id) {
      final s = id == null ? null : graph.byId(id);
      if (s == null || !MoveSteps.isVenueLeg(s) || s.ref == null) return null;
      final leg = display.legs
          .where((l) => (l.operationId ?? l.quoteId) == s.ref)
          .lastOrNull;
      return leg == null ? null : multiSourceMoveLegRow(leg, live)?.details;
    });
    if (lines.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: MoneyStepsView(
          lines: lines,
          graph: graph,
          toLabel: sendTo,
          failureHaptic: failureHaptic),
    );
  }
}

/// [row] as the wallet holds it now (the background sync swaps a quote id
/// for the order id while a detail is open: matched by its operation too).
SwapOrder liveSwapRow(SwapOrder row, List<SwapOrder> orders) =>
    orders.where((o) => o.id == row.id).firstOrNull ??
    (row.operationId == null
        ? null
        : orders.where((o) => o.operationId == row.operationId).firstOrNull) ??
    row;

/// A single move's steps, from its row ([MoveSteps.ofRow]), live as the
/// row moves on, in the Activity detail's compact form: one line for the
/// move ("Bitcoin → Dollars · $9.87", the purchase "Dollars → Bitcoin ·
/// $5.00"), then the arrival when Bitcoin receives it. Nothing for a row that is not a move between
/// the person's own balances.
class SwapRowStepsSection extends ConsumerWidget {
  const SwapRowStepsSection({super.key, required this.row});

  final SwapOrder row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(ownSparkArrivalsProvider);
    final live = liveSwapRow(row, ref.watch(swapOrdersProvider));
    final graph = MoveSteps.ofRow(live,
        counting: OwnSparkArrivals.awaitingCredit(live.id));
    if (graph.isEmpty) return const SizedBox.shrink();
    // What landed, once the row settled into dollars.
    final got = live.isComplete && _dollarCoin(live.coinTo)
        ? orchestraRowAmount(live.withdrawalAmount, live.coinTo)
        : 0.0;
    final first = graph.steps.first.id;
    final lines = _withCctpLegs(
        ref,
        context.l10n,
        moveStepCompactLines(context.l10n, graph, landedUsd: {
          if (got > 0) first: (got * 100).round() / 100,
        }),
        (id) => id == first ? live : null);
    if (lines.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: MoneyStepsView(lines: lines, graph: graph),
    );
  }
}
