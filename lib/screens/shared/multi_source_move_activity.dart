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
// ([multiSourceMoveFinalStepMissing]): its row says where the money is.
// Pure, so the lists can be tested without a widget tree.

import 'dart:math' as math;

import 'package:kute/helpers/auth_grant.dart' show AuthGrants;
import 'package:kute/helpers/orchestra_router.dart' show orchestraRowAmount;
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart'
    show VenueCashFor;
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode;
import 'package:kute/services/one_balance/multi_source_move.dart';
import 'package:kute/services/orchestra/own_spark_arrivals.dart';
import 'package:kute/services/one_balance/venue_funder.dart'
    show VenueCashDestination;

/// The row standing for [move]; [legRows] are the Activity rows of its
/// legs and of the action's own step that the surface knows.
class MultiSourceMoveTransaction extends BaseTransaction {
  MultiSourceMoveTransaction({
    required this.move,
    required this.legRows,
  }) : super(
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
      other.legRows.length == legRows.length &&
      [for (final r in other.legRows) r.details.status].join() ==
          [for (final r in legRows) r.details.status].join();

  @override
  int get hashCode => Object.hash(super.hashCode, move.legs.length,
      move.finalOperationId, legRows.length);
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
  final status = tx.partial
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
  var btc = 0.0;
  for (final r in tx.legRows) {
    final d = r.details;
    if (d.coinTo.toUpperCase() != 'BTC' || d.networkTo.toUpperCase() != 'SPARK') {
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
  if (legRows.isEmpty) return false;
  for (final r in legRows) {
    if (!r.isComplete || OwnSparkArrivals.awaitingCredit(r.id)) return false;
  }
  for (final leg in move.okLegs) {
    if (!legRows.any((r) => _rowOf(r, leg.operationId, leg.quoteId))) {
      return false;
    }
  }
  final finalOp = move.finalOperationId;
  if (finalOp != null) {
    if (!legRows.any((r) => _rowOf(r, finalOp, null))) return false;
  } else if (move.destination == VenueCashDestination.bitcoin &&
      move.okLegs.any((l) => !l.direct)) {
    // Its dollars are home; the purchase has not gone yet.
    return false;
  }
  return true;
}

/// How long after a move started its own step (the purchase, the send)
/// may still go without the person: the one approval the action was given
/// lives this long ([AuthGrants.autofireTtl]), so past it nothing buys or
/// sends for the move unless the person asks again.
const Duration kMultiSourceMoveFinishWindow = AuthGrants.autofireTtl;

/// Whether [move]'s action has a step of its own after the legs: a send,
/// or the purchase of Bitcoin with what came home to Dollars.
bool multiSourceMoveHasFinalStep(MultiSourceMove move) =>
    move.forAction == VenueCashFor.send ||
    (move.destination == VenueCashDestination.bitcoin &&
        move.okLegs.any((l) => !l.direct));

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
  var usd = move.dollarsUsd;
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
/// went, or the action's own step did), and the surface is the dollar
/// ledger ([onlyUsdb]) or Bitcoin is where it went.
bool multiSourceMoveShows(MultiSourceMove move, {required bool onlyUsdb}) {
  if (move.okLegs.isEmpty && move.finalOperationId == null) return false;
  return onlyUsdb || move.destination == VenueCashDestination.bitcoin;
}

/// [rows] (newest first) with each of [moves]' legs folded into one row
/// for the move, at the time the move started. Moves of another wallet
/// ([walletId]) are left out. [everyRow] is the wallet's whole history
/// (default: [rows]): a move's row reads its legs from it, so it settles
/// on the legs a surface does not list too (a direct leg to Bitcoin on
/// the Dollars activity).
List<BaseTransaction> collapseMultiSourceMoves(
  List<BaseTransaction> rows,
  List<MultiSourceMove> moves, {
  required bool onlyUsdb,
  String? walletId,
  List<BaseTransaction>? everyRow,
}) {
  final shown = [
    for (final m in moves)
      if ((m.walletId == null || walletId == null || m.walletId == walletId) &&
          multiSourceMoveShows(m, onlyUsdb: onlyUsdb))
        m,
  ];
  if (shown.isEmpty) return rows;
  MultiSourceMove? ownerOf(SwapOrderTransaction row) =>
      shown.where((m) => isMultiSourceMoveLeg(row, m)).firstOrNull;
  final legsOf = {for (final m in shown) m.id: <SwapOrderTransaction>[]};
  final out = <BaseTransaction>[];
  for (final row in rows) {
    if (row is SwapOrderTransaction && ownerOf(row) != null) continue;
    out.add(row);
  }
  final seen = <String>{};
  for (final row in [...?everyRow, ...rows]) {
    if (row is! SwapOrderTransaction || !seen.add(row.id)) continue;
    final owner = ownerOf(row);
    if (owner != null) legsOf[owner.id]!.add(row);
  }
  for (final m in shown) {
    // In time order, the rows already there keeping theirs.
    var at = out.indexWhere((r) => r.timestamp.isBefore(m.createdAt));
    if (at < 0) at = out.length;
    out.insert(at, MultiSourceMoveTransaction(move: m, legRows: legsOf[m.id]!));
  }
  return out;
}

/// The Activity row ids of every leg of [moves] among [rows], for a list
/// that adds rows from elsewhere (the Portfolio's venue moves).
Set<String> multiSourceMoveLegIds(
    Iterable<SwapOrderTransaction> rows, List<MultiSourceMove> moves) {
  final ids = <String>{};
  for (final m in moves) {
    if (m.okLegs.isEmpty && m.finalOperationId == null) continue;
    for (final r in rows) {
      if (isMultiSourceMoveLeg(r, m)) ids.add(r.id);
    }
  }
  return ids;
}
