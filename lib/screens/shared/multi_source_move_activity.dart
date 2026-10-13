// lib/screens/shared/multi_source_move_activity.dart
//
// One Activity row per action that took money from more than one place
// (`MultiSourceMove`, lib/services/one_balance/multi_source_move.dart):
// "Send $50" or "Move $50 to Bitcoin" stands for every leg, and the legs
// are listed inside its detail sheet (transactions_builder.dart).
//
// Where it shows: the Dollars activity (and the Portfolio's Activity,
// which lists the dollar ledger) for every move, and the Bitcoin activity
// when Bitcoin is the destination. Wherever the row shows, the legs'
// own rows (the venue cash-outs, the CCTP moves, the action's own step)
// are not listed beside it. Pure, so the lists can be tested without a
// widget tree.

import 'package:kute/models/transactions_model.dart';
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

/// Whether [row] is one of [move]'s legs (or its own step).
bool isMultiSourceMoveLeg(SwapOrderTransaction row, MultiSourceMove move) {
  final ids = move.linkedIds;
  final op = row.details.operationId;
  return ids.contains(row.id) || (op != null && ids.contains(op));
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
