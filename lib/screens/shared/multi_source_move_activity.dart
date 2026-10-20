// lib/screens/shared/multi_source_move_activity.dart
//
// One Activity row per action that took money from more than one place
// (`MultiSourceMove`, lib/services/one_balance/multi_source_move.dart)
// stands for every leg, and the legs are listed inside its detail sheet
// (transactions_builder.dart). A move to Bitcoin reads as the Investments
// withdrawal row and a send as the Dollars send row
// ([multiSourceMoveStandardRow]); any other move as "Move $50 to …".
//
// Where it shows: the Dollars activity (and the Portfolio's Activity,
// which lists the dollar ledger) for every move, and the Bitcoin activity
// when Bitcoin is the destination. Wherever the row shows, the legs'
// own rows (the venue cash-outs, the CCTP moves, the action's own step)
// are not listed beside it. A move whose legs all landed in Dollars but
// whose own step (the purchase, the send) never went is not left Pending
// ([multiSourceMoveFinalStepMissing]): while Dollars hold the money its
// row says so (one tap finishes it); once that money was spent the move
// is dissolved ([multiSourceMoveFinish]): nothing reached where it was
// going, so it has no row anywhere and its legs show as their own rows on
// the surfaces that list them (owner decision October 2026, after "Move
// $20.23 to Bitcoin · Completed · The money stayed in Investments"). The
// record stays in its store. Pure, so the lists can be tested without a
// widget tree.

import 'dart:math' as math;

import 'package:kute/helpers/auth_grant.dart' show AuthGrants;
import 'package:kute/helpers/orchestra_router.dart' show orchestraRowAmount;
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart'
    show VenueCashFor;
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode;
import 'package:kute/screens/shared/pending_bitcoin_purchase_continue.dart'
    show legacyPurchaseUsd, pendingPurchaseWaitingUsd;
import 'package:kute/services/one_balance/money_steps.dart'
    show MoneyStepStatus;
import 'package:kute/services/one_balance/move_steps.dart' show MoveSteps;
import 'package:kute/services/one_balance/multi_source_move.dart';
import 'package:kute/services/one_balance/pending_bitcoin_purchase.dart'
    show
        BitcoinPurchaseFinisher,
        bitcoinPurchaseMoveForDisplay,
        PendingBitcoinPurchaseStore,
        PendingPurchaseStage;
import 'package:kute/services/orchestra/own_spark_arrivals.dart';
import 'package:kute/services/one_balance/venue_funder.dart'
    show VenueCashDestination;

/// The row standing for [move]; [legRows] are the Activity rows of its
/// legs and of the action's own step that the surface knows.
class MultiSourceMoveTransaction extends BaseTransaction {
  factory MultiSourceMoveTransaction({
    required MultiSourceMove move,
    required List<SwapOrderTransaction> legRows,
  }) =>
      MultiSourceMoveTransaction._(
          bitcoinPurchaseMoveForDisplay(move), legRows);

  MultiSourceMoveTransaction._(this.move, this.legRows)
      : super(
          id: move.id,
          timestamp: move.createdAt,
          isConfirmed: multiSourceMoveSettled(move, legRows),
        );

  final MultiSourceMove move;

  /// The rows of the move's legs and of its own step that the wallet
  /// holds, on whatever surface they would show.
  final List<SwapOrderTransaction> legRows;

  /// A leg failed and part of the amount is still where it was.
  bool get partial => move.partial;

  /// Every leg row the surface knows has settled.
  bool get complete => isConfirmed && !partial;

  /// A step of the move stopped ([multiSourceMoveStepFailed]): it needs
  /// the person, never Completed.
  bool get stepFailed =>
      multiSourceMoveStepFailed(move) ||
      (move.isParallelPurchase &&
          legRows.any((row) =>
              isMultiSourceMoveLeg(row, move) &&
              OwnSparkArrivals.failedStatuses.contains(row.details.status)));

  @override
  TransactionType get type => move.forAction == 'send'
      ? TransactionType.sent
      : TransactionType.received;

  @override
  num get amount => move.totalUsd;

  @override
  String get asset => 'USD';

  @override
  bool operator ==(Object other) =>
      other is MultiSourceMoveTransaction &&
      maybeBaseEquals(other) &&
      other.move.legs.length == move.legs.length &&
      other.move.finalOperationId == move.finalOperationId &&
      other.move.initialDollarsOperationId == move.initialDollarsOperationId &&
      other.move.initialDollarsSentUsd == move.initialDollarsSentUsd &&
      other.move.isParallelPurchase == move.isParallelPurchase &&
      (!move.isParallelPurchase ||
          (other.partial == partial &&
              other.stepFailed == stepFailed &&
              other.move.remainingUsd == move.remainingUsd)) &&
      other.legRows.length == legRows.length &&
      [for (final r in other.legRows) r.details.status].join() ==
          [for (final r in legRows) r.details.status].join();

  @override
  int get hashCode => Object.hash(
      super.hashCode,
      move.legs.length,
      move.finalOperationId,
      move.initialDollarsOperationId,
      move.initialDollarsSentUsd,
      move.isParallelPurchase,
      move.isParallelPurchase ? partial : null,
      move.isParallelPurchase ? stepFailed : null,
      move.isParallelPurchase ? move.remainingUsd : null,
      legRows.length);
}

/// The existing Activity row [tx] reads as, or null when its kind has
/// none (a move into Dollars or a venue keeps the move's own row). One
/// balance: where the money came from is Investments, whichever venue
/// paid each leg (the legs are in the detail sheet).
///
///  * To Bitcoin: the Investments withdrawal to Bitcoin ("Withdraw · from
///    Investments · ₿received · from $spent", a `USDB → BTC` row on the
///    wallet's own Spark). Its bitcoin is what the move's rows delivered
///    to Bitcoin, `0` while none is known.
///  * A send that went: the send's own row (the Dollars send), for the
///    person's whole amount.
///
/// Its status is the move's: settled, needing attention after a failed
/// leg (`failed`), else on its way.
SwapOrderTransaction? multiSourceMoveStandardRow(
    MultiSourceMoveTransaction tx) {
  final move = tx.move;
  final status = tx.partial || tx.stepFailed
      ? 'failed'
      : tx.complete
          ? 'success'
          : 'exchanging';
  final at = move.createdAt.millisecondsSinceEpoch;
  SwapOrder? details;
  if (move.destination == VenueCashDestination.bitcoin) {
    details = SwapOrder(
      id: move.id,
      coinFrom: kOrchestraUsdAssetCode,
      networkFrom: 'SPARK',
      coinTo: 'BTC',
      networkTo: 'SPARK',
      depositAddress: '',
      depositAmount: move.spentUsd.toStringAsFixed(2),
      withdrawalAmount: multiSourceMoveBitcoin(tx).toStringAsFixed(8),
      status: status,
      timestamp: at,
      withdrawalAddress: '',
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: '',
      provider: 'Orchestra',
      walletId: move.walletId,
    );
  } else if (move.forAction == VenueCashFor.send &&
      move.finalOperationId != null) {
    final send = tx.legRows
        .where((r) =>
            _rowOf(r, move.finalOperationId, null) &&
            r.details.activityDirection == 'send')
        .firstOrNull;
    if (send != null) {
      details = send.details.copyWith(
        id: move.id,
        depositAmount: move.totalUsd.toStringAsFixed(2),
        status: status,
        timestamp: at,
      );
    }
  }
  if (details == null) return null;
  return SwapOrderTransaction(
    id: move.id,
    timestamp: move.createdAt,
    isConfirmed: tx.isConfirmed,
    details: details,
  );
}

/// The bitcoin [tx]'s rows delivered to the wallet's own Spark balance
/// (estimates until each order reports its own), in BTC.
double multiSourceMoveBitcoin(MultiSourceMoveTransaction tx) {
  if (tx.move.isParallelPurchase) {
    final totals = multiSourceMoveTotals(tx.move, tx.legRows);
    return totals.receivedBtc + totals.arrivingBtc;
  }
  var btc = 0.0;
  for (final r in tx.legRows) {
    final d = r.details;
    if (d.coinTo.toUpperCase() != 'BTC' ||
        d.networkTo.toUpperCase() != 'SPARK') {
      continue;
    }
    btc += orchestraRowAmount(d.withdrawalAmount, 'BTC');
  }
  return btc;
}

/// Whether [row] is one of [move]'s legs (or its own step).
bool isMultiSourceMoveLeg(SwapOrderTransaction row, MultiSourceMove move) {
  final ids = move.linkedIds;
  final op = row.details.operationId;
  return ids.contains(row.id) || (op != null && ids.contains(op));
}

/// The Activity row standing for [leg] among [rows] (the row its
/// settlement operation or quote wrote), or null while none is known.
/// When the leg has both its CCTP row and the Orchestra order the
/// standing address turned it into, the order; else the newest.
SwapOrderTransaction? multiSourceMoveLegRow(
        MultiSourceMoveLeg leg, List<SwapOrderTransaction> rows) =>
    _bestRow([
      for (final r in rows)
        if (_rowOf(r, leg.operationId, leg.quoteId)) r,
    ]);

/// The row of [move]'s own step (the send, the purchase) among [rows],
/// or null before it went.
SwapOrderTransaction? multiSourceMoveFinalRow(
        MultiSourceMove move, List<SwapOrderTransaction> rows) =>
    _bestRow([
      for (final r in rows)
        if (_rowOf(r, move.finalOperationId, null)) r,
    ]);

/// The separately submitted initial Dollars → Bitcoin order. It remains
/// associated when a later purchase uses Dollars arriving from another leg.
SwapOrderTransaction? multiSourceMoveInitialDollarsRow(
        MultiSourceMove move, List<SwapOrderTransaction> rows) =>
    _bestRow([
      for (final r in rows)
        if (_rowOf(r, move.initialDollarsOperationId, null)) r,
    ]);

SwapOrderTransaction? _bestRow(List<SwapOrderTransaction> rows) {
  if (rows.isEmpty) return null;
  int rank(SwapOrderTransaction r) => r.id.startsWith('cctp-') ? 1 : 0;
  rows.sort((a, b) {
    final byKind = rank(a).compareTo(rank(b));
    return byKind != 0 ? byKind : b.timestamp.compareTo(a.timestamp);
  });
  return rows.first;
}

/// [snapshot] (the rows a surface handed the move) brought up to date
/// from [orders] (the wallet's swap orders as they stand now): a row the
/// store holds replaces its snapshot, and a row of the move the snapshot
/// did not have yet (an order a CCTP move just became) joins it.
List<SwapOrderTransaction> multiSourceMoveLiveRows(MultiSourceMove move,
    List<SwapOrderTransaction> snapshot, List<SwapOrder> orders) {
  final byId = {for (final r in snapshot) r.id: r};
  for (final o in orders) {
    final row = SwapOrderTransaction(
      id: o.id,
      timestamp: DateTime.fromMillisecondsSinceEpoch(o.timestamp),
      isConfirmed: o.isComplete,
      details: o,
    );
    if (byId.containsKey(o.id) || isMultiSourceMoveLeg(row, move)) {
      byId[o.id] = row;
    }
  }
  return byId.values.toList();
}

bool _rowOf(SwapOrderTransaction row, String? operationId, String? quoteId) =>
    (operationId != null &&
        (row.details.operationId == operationId ||
            row.id == operationId ||
            row.id == 'cctp-$operationId')) ||
    (quoteId != null && row.id == quoteId);

/// Whether [move]'s money is where it was going: every leg that went has
/// its row and that row has settled; a move to Bitcoin that brought money
/// home to Dollars first has bought it too (its own step went and
/// settled); and no row's delivery to the wallet's own Spark balance is
/// still waiting for the balance to show it
/// ([OwnSparkArrivals.awaitingCredit]: Orchestra reports an order done as
/// it sends, a moment before the wallet counts it). [legRows] are the
/// rows the wallet holds for the move.
bool multiSourceMoveSettled(
    MultiSourceMove move, List<SwapOrderTransaction> legRows) {
  move = bitcoinPurchaseMoveForDisplay(move);
  if (move.isParallelPurchase) {
    final latest = {for (final leg in move.legs) leg.venue: leg};
    if (latest.values.any((leg) => leg.uncertain)) return false;
    for (final step in MoveSteps.of(move).steps.where(MoveSteps.isVenueLeg)) {
      // Accepted steps keep running in storage while live rows report their
      // settlement. A source with no submission proof is still unresolved.
      if (step.ref == null &&
          (step.status == MoneyStepStatus.running ||
              step.status == MoneyStepStatus.waiting)) {
        return false;
      }
    }
  }
  if (legRows.isEmpty) return false;
  for (final r in legRows) {
    if (!r.isComplete || OwnSparkArrivals.awaitingCredit(r.id)) return false;
  }
  for (final leg in move.okLegs) {
    if (!legRows.any((r) => _rowOf(r, leg.operationId, leg.quoteId))) {
      return false;
    }
  }
  final initialOp = move.initialDollarsOperationId;
  if (initialOp != null && !legRows.any((r) => _rowOf(r, initialOp, null))) {
    return false;
  }
  final initial = MoveSteps.of(move).byId(MoveSteps.initialDollarsId);
  if (initial != null &&
      initialOp == null &&
      initial.status != MoneyStepStatus.skipped) {
    return false;
  }
  final finalOp = move.finalOperationId;
  if (finalOp != null) {
    if (!legRows.any((r) => _rowOf(r, finalOp, null))) return false;
  } else if (move.destination == VenueCashDestination.bitcoin &&
      move.okLegs.any((l) => !l.direct) &&
      multiSourceMoveHasFinalStep(move)) {
    // Its dollars are home; the purchase has not gone yet.
    return false;
  } else if (multiSourceMoveOnwardOwed(move)) {
    // Its legs landed, but Dollars never went on into the venue: the move
    // is not where it was going (founder, 15 October 2026: "Completed"
    // with "Dollars → Investing" still waiting).
    return false;
  }
  return true;
}

/// Whether [move] is into a venue and its own step (Dollars going on into
/// it) is owed: its graph has one that is not skipped and nothing went
/// for it.
bool multiSourceMoveOnwardOwed(MultiSourceMove move) {
  if (move.finalOperationId != null) return false;
  if (move.destination != VenueCashDestination.investing &&
      move.destination != VenueCashDestination.predictions) {
    return false;
  }
  final fin = MoveSteps.finalOf(MoveSteps.of(move));
  return fin != null && fin.status != MoneyStepStatus.skipped;
}

/// Whether a step of [move] stopped: a failed step that no Retry replaced
/// (a failed leg, the move's own step stopped with its order).
bool multiSourceMoveStepFailed(MultiSourceMove move) =>
    MoveSteps.of(bitcoinPurchaseMoveForDisplay(move)).steps.any((s) =>
        s.status == MoneyStepStatus.failed &&
        s.reason != MoveSteps.replacedReason);

/// How long after a move started its own step (the purchase, the send)
/// may still go without the person: the one approval the action was given
/// lives this long ([AuthGrants.autofireTtl]), so past it nothing buys or
/// sends for the move unless the person asks again.
const Duration kMultiSourceMoveFinishWindow = AuthGrants.autofireTtl;

/// Whether [move]'s action has a step of its own after the legs: a send,
/// the purchase of Bitcoin with what came home to Dollars, or Dollars
/// going on into a venue for an order.
bool multiSourceMoveHasFinalStep(MultiSourceMove move) {
  move = bitcoinPurchaseMoveForDisplay(move);
  final fin = MoveSteps.finalOf(MoveSteps.of(move));
  if (move.destination == VenueCashDestination.bitcoin &&
      fin?.status == MoneyStepStatus.skipped) {
    return false;
  }
  return move.forAction == VenueCashFor.send ||
      (move.destination == VenueCashDestination.bitcoin &&
          move.okLegs.any((l) => !l.direct)) ||
      (move.finalOperationId == null &&
          move.okLegs.isNotEmpty &&
          multiSourceMoveOnwardOwed(move));
}

/// Whether every leg of [move] went and has landed: each has its row, the
/// row has settled and its delivery is counted. False when a leg failed
/// (that move needs its Retry) or when no leg went.
bool multiSourceMoveLegsLanded(
    MultiSourceMove move, List<SwapOrderTransaction> rows) {
  if (move.okLegs.isEmpty || move.failedLegs.isNotEmpty) return false;
  for (final leg in move.okLegs) {
    final row = multiSourceMoveLegRow(leg, rows);
    if (row == null ||
        !row.isComplete ||
        OwnSparkArrivals.awaitingCredit(row.id)) {
      return false;
    }
  }
  return true;
}

/// What the action's own step takes from Dollars: the person's amount,
/// less what went straight to the destination.
double multiSourceMoveOnwardUsd(MultiSourceMove move) =>
    _floorCents(math.max(0, move.totalUsd - move.directDeliveredUsd));

/// What is in Dollars for [move]'s own step: Dollars' own part plus what
/// each leg that came home landed (its row's received dollars, else what
/// it was expected to land).
double multiSourceMoveLandedInDollarsUsd(
    MultiSourceMove move, List<SwapOrderTransaction> rows) {
  var usd = move.hasParallelDollars ? 0.0 : move.dollarsUsd;
  for (final leg in move.okLegs) {
    if (leg.direct) continue;
    final d = multiSourceMoveLegRow(leg, rows)?.details;
    var got = 0.0;
    if (d != null && d.isComplete && _dollarCoin(d.coinTo)) {
      got = d.isOrchestra
          ? orchestraRowAmount(d.withdrawalAmount, d.coinTo)
          : double.tryParse(d.withdrawalAmount) ?? 0;
    }
    usd += got > 0 ? got : leg.arrivingUsd;
  }
  return _floorCents(usd);
}

/// Whether [move]'s own step never happened although its money is home:
/// it has one ([multiSourceMoveHasFinalStep]), every leg landed in Dollars
/// ([multiSourceMoveLegsLanded]), nothing went for the step, and the time
/// it could still go on its own is over ([kMultiSourceMoveFinishWindow]
/// from [now]). A move an older build made, whose purchase was tied to
/// the open sheet, and a purchase the background finisher gave up on.
bool multiSourceMoveFinalStepMissing(
        MultiSourceMove move, List<SwapOrderTransaction> rows,
        {required DateTime now}) =>
    move.finalOperationId == null &&
    multiSourceMoveHasFinalStep(move) &&
    !now.isBefore(move.createdAt.add(kMultiSourceMoveFinishWindow)) &&
    multiSourceMoveLegsLanded(move, rows);

/// What finishing [move]'s missing step moves: what landed in Dollars for
/// it, never more than the step's own amount.
double multiSourceMoveMissingStepUsd(
        MultiSourceMove move, List<SwapOrderTransaction> rows) =>
    math.min(multiSourceMoveLandedInDollarsUsd(move, rows),
        multiSourceMoveOnwardUsd(move));

/// Where a move stands when its legs are home but its own step (the
/// purchase of Bitcoin, the send) did not go: its money is in Dollars and
/// waits on the person ([usd], what one tap finishes), or that money was
/// spent since and the move is [dissolved]: nothing reached where it was
/// going, so the move has no row and its legs are listed as their own.
class MultiSourceMoveFinish {
  const MultiSourceMoveFinish.waiting(double this.usd, {required this.legacy});
  const MultiSourceMoveFinish.dissolved()
      : usd = null,
        legacy = false;

  /// What one tap finishes; null when [dissolved].
  final double? usd;

  /// The move has no purchase record (an older build tied the purchase
  /// to the open sheet): the tap makes one from the move.
  final bool legacy;

  bool get dissolved => usd == null;
}

/// [move]'s [MultiSourceMoveFinish], or null when the move is on its
/// normal course (its own step went or is still going, a leg is on its
/// way, or a leg failed and Retry is offered). The one decision the row,
/// the detail and the lists ([collapseMultiSourceMoves],
/// [multiSourceMoveLegIds]) read, so they never disagree.
///
///  * A purchase record that waits on the person: the one-tap continue
///    for what Dollars can buy ([pendingPurchaseWaitingUsd]).
///  * A purchase [finisher] is running, or one handed to the send: still
///    Pending.
///  * Every leg landed, the step never went, and its time to go on its
///    own is over ([multiSourceMoveFinalStepMissing]): waiting while
///    Dollars hold all of it (one tap buys it; a send says it did not
///    go), else dissolved.
///
/// [dollars] is the Dollars balance, null while it is not known yet
/// (`usdBalanceReadingProvider`): Dollars are then taken to hold the
/// money, so a balance that has not loaded never dissolves a move.
MultiSourceMoveFinish? multiSourceMoveFinish(
  MultiSourceMove move,
  List<SwapOrderTransaction> legRows, {
  required BitcoinPurchaseFinisher finisher,
  required double? dollars,
  required DateTime now,
}) {
  if (move.finalOperationId != null || move.partial) return null;
  if (!multiSourceMoveHasFinalStep(move)) return null;
  // A parallel leg already sent to Bitcoin is still an actual withdrawal,
  // even if a later Dollars remainder can no longer be purchased.
  MultiSourceMoveFinish? missingFunds() => move.isParallelPurchase &&
          (move.initialDollarsOperationId != null ||
              move.okLegs.any((leg) => leg.direct))
      ? null
      : const MultiSourceMoveFinish.dissolved();
  if (move.destination == VenueCashDestination.bitcoin) {
    if (finisher.running(move.id)) return null;
    final record = PendingBitcoinPurchaseStore.get(move.id);
    final waiting = pendingPurchaseWaitingUsd(
        finisher, move.id, dollars ?? record?.usd ?? 0);
    if (waiting != null) {
      return MultiSourceMoveFinish.waiting(waiting,
          legacy: record?.legacy ?? false);
    }
    if (record != null) {
      // The record owns the step until it waits on the person with its
      // money gone.
      if (record.stage == PendingPurchaseStage.funding) return null;
      final over =
          !now.isBefore(move.createdAt.add(kMultiSourceMoveFinishWindow));
      return over && multiSourceMoveLegsLanded(move, legRows)
          ? missingFunds()
          : null;
    }
  }
  if (!multiSourceMoveFinalStepMissing(move, legRows, now: now)) return null;
  final missing = multiSourceMoveMissingStepUsd(move, legRows);
  final usd = legacyPurchaseUsd(missing, dollars ?? missing);
  return usd != null
      ? MultiSourceMoveFinish.waiting(usd, legacy: true)
      : missingFunds();
}

/// What a move's Activity detail states once for the whole move, from its
/// rows ([multiSourceMoveTotals]).
class MultiSourceMoveTotals {
  const MultiSourceMoveTotals({
    required this.sentUsd,
    this.receivedUsd = 0,
    this.receivedBtc = 0,
    this.arrivingUsd = 0,
    this.arrivingBtc = 0,
    this.feesUsd = 0,
  });

  /// What the move spent ([MultiSourceMove.spentUsd]).
  final double sentUsd;

  /// What landed where the money went, in dollars and in bitcoin.
  final double receivedUsd;
  final double receivedBtc;

  /// What is still on its way there (estimates until each row lands).
  final double arrivingUsd;
  final double arrivingBtc;

  /// Every leg's and the own step's fee that is known in dollars (both
  /// sides dollars, settled): what left less what landed.
  final double feesUsd;

  bool get anyReceived => receivedUsd >= 0.01 || receivedBtc > 0;
  bool get anyArriving => arrivingUsd >= 0.01 || arrivingBtc > 0;

  /// Sent is worth its own line: what arrived is bitcoin, nothing arrived
  /// yet, or it is not what arrived plus the fees.
  bool get showSent =>
      receivedBtc > 0 ||
      arrivingBtc > 0 ||
      !anyReceived ||
      (sentUsd - receivedUsd - feesUsd).abs() >= 0.01;
}

/// [move]'s totals from [rows] (the wallet's rows for the move): what
/// landed where it went (the legs straight there, the own step's row, and
/// for a move home to Dollars every leg), what is still on its way, and
/// the fees known in dollars across every row. Pure.
MultiSourceMoveTotals multiSourceMoveTotals(
    MultiSourceMove move, List<SwapOrderTransaction> rows) {
  move = bitcoinPurchaseMoveForDisplay(move);
  double amount(SwapOrder d, String raw, String coin) =>
      d.isOrchestra ? orchestraRowAmount(raw, coin) : double.tryParse(raw) ?? 0;
  var receivedUsd = 0.0, receivedBtc = 0.0, arrivingUsd = 0.0;
  var arrivingBtc = 0.0, fees = 0.0;
  final homeIsDestination = move.destination == VenueCashDestination.dollars &&
      move.forAction != VenueCashFor.send;
  final counted = <String>{};
  void count(SwapOrder d, {required bool atDestination}) {
    if (!counted.add(d.operationId ?? d.id)) return;
    final landed = d.isComplete && !OwnSparkArrivals.awaitingCredit(d.id);
    final got = amount(d, d.withdrawalAmount, d.coinTo);
    if (landed && _dollarCoin(d.coinFrom) && _dollarCoin(d.coinTo)) {
      final fee = amount(d, d.depositAmount, d.coinFrom) - got;
      if (fee >= 0.005) fees += fee;
    }
    if (!atDestination || got <= 0) return;
    final btc = d.coinTo.toUpperCase() == 'BTC';
    if (!btc && !_dollarCoin(d.coinTo)) return;
    if (landed) {
      btc ? receivedBtc += got : receivedUsd += got;
    } else if (!OwnSparkArrivals.failedStatuses.contains(d.status)) {
      btc ? arrivingBtc += got : arrivingUsd += got;
    }
  }

  for (final leg in move.okLegs) {
    final row = multiSourceMoveLegRow(leg, rows);
    if (row != null) {
      count(row.details, atDestination: leg.direct || homeIsDestination);
    }
  }
  final initial = multiSourceMoveInitialDollarsRow(move, rows);
  if (initial != null) count(initial.details, atDestination: true);
  final fin = multiSourceMoveFinalRow(move, rows);
  if (fin != null) count(fin.details, atDestination: true);
  double cents(double v) => (v * 100).round() / 100;
  return MultiSourceMoveTotals(
    sentUsd: move.spentUsd,
    receivedUsd: cents(receivedUsd),
    receivedBtc: receivedBtc,
    arrivingUsd: cents(arrivingUsd),
    arrivingBtc: arrivingBtc,
    feesUsd: cents(fees),
  );
}

/// The Orchestra orders of [move] among [rows], legs first then its own
/// step: what a "Track this exchange" can open. A CCTP move not yet an
/// order counts once the Arbitrum address Circle mints to is known: the
/// one-time quote's deposit address (the button opens it on Arbiscan).
List<SwapOrder> multiSourceMoveOrders(
    MultiSourceMove move, List<SwapOrderTransaction> rows) {
  final out = <SwapOrder>[];
  bool trackable(SwapOrder d) =>
      d.isOrchestra &&
      d.id.isNotEmpty &&
      (!d.id.startsWith('cctp-') ||
          RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(d.depositAddress)) &&
      !d.isStuckStandingDeposit;
  for (final leg in move.okLegs) {
    final d = multiSourceMoveLegRow(leg, rows)?.details;
    if (d != null && trackable(d) && !out.any((o) => o.id == d.id)) {
      out.add(d);
    }
  }
  final initial = multiSourceMoveInitialDollarsRow(move, rows)?.details;
  if (initial != null &&
      trackable(initial) &&
      !out.any((o) => o.id == initial.id)) {
    out.add(initial);
  }
  final fin = multiSourceMoveFinalRow(move, rows)?.details;
  if (fin != null && trackable(fin) && !out.any((o) => o.id == fin.id)) {
    out.add(fin);
  }
  return out;
}

/// Whether a move is dissolved ([MultiSourceMoveFinish.dissolved]), given
/// the rows of its legs the list knows.
typedef MultiSourceMoveDissolved = bool Function(
    MultiSourceMove move, List<SwapOrderTransaction> legRows);

double _floorCents(num usd) =>
    usd.isFinite && usd > 0 ? ((usd * 100) + 1e-6).floor() / 100 : 0;

bool _dollarCoin(String coin) {
  final upper = coin.toUpperCase();
  return upper == 'USDC' ||
      upper == 'USDC.E' ||
      upper == 'USDT' ||
      upper == 'PUSD' ||
      upper == kOrchestraUsdAssetCode;
}

/// Whether [move] has a row on a surface: something moved for it (a leg
/// went, or the action's own step did) or its legs are still being
/// submitted ([multiSourceMoveSubmitting]), and the surface is the dollar
/// ledger ([onlyUsdb]) or Bitcoin is where it went.
bool multiSourceMoveShows(MultiSourceMove move,
    {required bool onlyUsdb, DateTime? now}) {
  if (move.okLegs.isEmpty &&
      move.finalOperationId == null &&
      move.initialDollarsOperationId == null &&
      !multiSourceMoveSubmitting(move, now: now ?? DateTime.now())) {
    return false;
  }
  return onlyUsdb || move.destination == VenueCashDestination.bitcoin;
}

/// Whether [move] was approved and its legs are still being submitted:
/// the Move sheet closes on submit (a Buy bitcoin from Investments), so
/// the move's row is up, Pending, from that moment, before any leg has an
/// outcome. A leg (or the move's own Dollars part) with no outcome yet is
/// a running step with no submission and no reason; it counts while the
/// move's approval lives ([kMultiSourceMoveFinishWindow]), so a record a
/// crash cut short is never Pending forever.
bool multiSourceMoveSubmitting(MultiSourceMove move, {required DateTime now}) {
  if (!now.isBefore(move.createdAt.add(kMultiSourceMoveFinishWindow))) {
    return false;
  }
  return move.steps.steps.any((s) =>
      (MoveSteps.isVenueLeg(s) || s.id == MoveSteps.initialDollarsId) &&
      s.status == MoneyStepStatus.running &&
      s.ref == null &&
      s.reason == null);
}

/// [rows] (newest first) with each of [moves]' legs folded into one row
/// for the move, at the time the move started. Moves of another wallet
/// ([walletId]) are left out. [everyRow] is the wallet's whole history
/// (default: [rows]): a move's row reads its legs from it, so it settles
/// on the legs a surface does not list too (a direct leg to Bitcoin on
/// the Dollars activity). A move [dissolved] says is over with nothing
/// delivered has no row, and its legs stay in [rows] as their own.
List<BaseTransaction> collapseMultiSourceMoves(
  List<BaseTransaction> rows,
  List<MultiSourceMove> moves, {
  required bool onlyUsdb,
  String? walletId,
  List<BaseTransaction>? everyRow,
  MultiSourceMoveDissolved? dissolved,
}) {
  final candidates = [
    for (final m in moves)
      if ((m.walletId == null || walletId == null || m.walletId == walletId) &&
          multiSourceMoveShows(m, onlyUsdb: onlyUsdb))
        m,
  ];
  if (candidates.isEmpty) return rows;
  final legsOf = {
    for (final m in candidates) m.id: <SwapOrderTransaction>[],
  };
  final seen = <String>{};
  for (final row in [...?everyRow, ...rows]) {
    if (row is! SwapOrderTransaction || !seen.add(row.id)) continue;
    final owner =
        candidates.where((m) => isMultiSourceMoveLeg(row, m)).firstOrNull;
    if (owner != null) legsOf[owner.id]!.add(row);
  }
  final shown = [
    for (final m in candidates)
      if (dissolved == null || !dissolved(m, legsOf[m.id]!)) m,
  ];
  if (shown.isEmpty) return rows;
  final out = <BaseTransaction>[
    for (final row in rows)
      if (row is! SwapOrderTransaction ||
          !shown.any((m) => isMultiSourceMoveLeg(row, m)))
        row,
  ];
  for (final m in shown) {
    // In time order, the rows already there keeping theirs.
    var at = out.indexWhere((r) => r.timestamp.isBefore(m.createdAt));
    if (at < 0) at = out.length;
    out.insert(at, MultiSourceMoveTransaction(move: m, legRows: legsOf[m.id]!));
  }
  return out;
}

/// The Activity row ids of every leg of [moves] among [rows], for a list
/// that adds rows from elsewhere (the Portfolio's venue moves). The legs
/// of a move [dissolved] says is over with nothing delivered are left
/// out: they are listed as their own rows.
Set<String> multiSourceMoveLegIds(
    Iterable<SwapOrderTransaction> rows, List<MultiSourceMove> moves,
    {MultiSourceMoveDissolved? dissolved}) {
  final ids = <String>{};
  for (final m in moves) {
    if (m.okLegs.isEmpty &&
        m.finalOperationId == null &&
        m.initialDollarsOperationId == null) {
      continue;
    }
    final legs = [
      for (final r in rows)
        if (isMultiSourceMoveLeg(r, m)) r,
    ];
    if (dissolved != null && dissolved(m, legs)) continue;
    ids.addAll(legs.map((r) => r.id));
  }
  return ids;
}
