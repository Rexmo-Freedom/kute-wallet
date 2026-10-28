// lib/services/portfolio/money_in_out.dart
//
// What the Bitcoin home's "In & out" tab is made of: the spending
// wallet's bitcoin that came in and went out, by period, in plain words.
//
// The input is the bitcoin ledger's own activity rows
// ([assembleActivityRows] with `keepVenueMoves`), so the tab counts
// exactly what Activity lists, once per user intent: a conversion's
// funding send or delivery receive is already folded behind the
// conversion row.
//
// Out (money that left the bitcoin balance):
//   * Sent to people: a settled Spark payment out (Lightning, Spark or
//     on-chain, whoever it paid), and a conversion that paid someone
//     else from bitcoin (a send delivered in another coin or on another
//     rail).
//   * Into Investments: bitcoin moved into Investing or Predictions.
//   * Into Dollars: bitcoin converted into the person's own Dollars.
//   * Fees: the network fee every settled Spark payment out paid, the
//     legs folded behind a conversion included (the amount a payment
//     counts never includes its fee).
// In (money that arrived in the bitcoin balance):
//   * From people: a settled Spark payment in, and a coin received from
//     outside that landed as bitcoin.
//   * From Investments: money home from Investing or Predictions.
//   * From Dollars: the person's own Dollars converted into bitcoin.
//   * Bought: an on-ramp purchase (Cash App).
//
// Only settled money counts: a completed payment, a finished conversion.
// Something in flight, failed, expired or refunded went nowhere. Dollar
// transfers and the venues' own rows are other ledgers' money: the
// conversion beside them is the move, in sats. Nothing here names a rail,
// an address or a counterparty.

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;

import 'package:kute/helpers/orchestra_router.dart' show orchestraRowAmount;
import 'package:kute/helpers/swap_activity.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode;

/// Which way the money moved. [analyticsName] is the event's `side`.
enum MoneySide {
  moneyIn('in'),
  moneyOut('out');

  const MoneySide(this.analyticsName);
  final String analyticsName;
}

/// Where the money went or came from, in plain words. People, Investments
/// and Dollars exist on both sides; Fees only goes out, Bought only comes
/// in.
enum MoneyCategory { people, investments, dollars, fees, bought }

/// The categories a side lists, in reading order.
List<MoneyCategory> moneyCategoriesOf(MoneySide side) => switch (side) {
      MoneySide.moneyOut => const [
          MoneyCategory.people,
          MoneyCategory.investments,
          MoneyCategory.dollars,
          MoneyCategory.fees,
        ],
      MoneySide.moneyIn => const [
          MoneyCategory.people,
          MoneyCategory.investments,
          MoneyCategory.dollars,
          MoneyCategory.bought,
        ],
    };

/// One amount of bitcoin that came in or went out.
class MoneyMove {
  final DateTime at;
  final MoneySide side;
  final MoneyCategory category;
  final int sats;

  const MoneyMove({
    required this.at,
    required this.side,
    required this.category,
    required this.sats,
  });

  @override
  String toString() => 'MoneyMove(${side.name}, ${category.name}, $sats)';
}

/// Every settled move of the bitcoin ledger's activity [rows]. Fees are
/// read from [everyRow] (the wallet's whole sorted list, the folded
/// funding legs included; [rows] when null). [classify] reads a
/// conversion's intent; tests pass their own.
List<MoneyMove> moneyMoves(
  Iterable<BaseTransaction> rows, {
  Iterable<BaseTransaction>? everyRow,
  SwapActivityKind Function(SwapOrder order) classify = swapActivityFor,
}) {
  final out = <MoneyMove>[];
  void add(DateTime at, MoneySide side, MoneyCategory category, num sats) {
    final whole = sats.isFinite ? sats.round() : 0;
    if (whole <= 0) return;
    out.add(MoneyMove(at: at, side: side, category: category, sats: whole));
  }

  for (final tx in rows) {
    if (tx is SparkTransaction) {
      if (!_sparkSettled(tx)) continue;
      add(
          tx.timestamp,
          tx.type == TransactionType.sent
              ? MoneySide.moneyOut
              : MoneySide.moneyIn,
          MoneyCategory.people,
          tx.amountSats);
    } else if (tx is SwapOrderTransaction) {
      for (final side in MoneySide.values) {
        final entry = _swapEntry(tx.details, side, classify);
        if (entry != null) add(tx.timestamp, side, entry.$1, entry.$2);
      }
    }
  }
  for (final tx in everyRow ?? rows) {
    if (tx is! SparkTransaction || tx.type != TransactionType.sent) continue;
    if (!_sparkSettled(tx)) continue;
    add(tx.timestamp, MoneySide.moneyOut, MoneyCategory.fees, tx.feeSats);
  }
  return out;
}

/// A Spark payment that completed. A cache-hydrated row (no SDK payload)
/// only knows whether it is pending.
bool _sparkSettled(SparkTransaction tx) {
  final live = tx.details;
  if (live == null) return !tx.isPending;
  return live.status == breez.PaymentStatus.completed;
}

/// The category and the sats of a conversion on [side] of the bitcoin
/// ledger, or null when it did not move bitcoin that way or has not
/// settled.
(MoneyCategory, double)? _swapEntry(
  SwapOrder order,
  MoneySide side,
  SwapActivityKind Function(SwapOrder order) classify,
) {
  if (!order.isComplete) return null;
  final wantOut = side == MoneySide.moneyOut;
  final leg = (wantOut ? order.coinFrom : order.coinTo).toUpperCase();
  if (leg != 'BTC') return null;
  final btc = wantOut
      ? _legAmount(order, order.depositAmount, order.coinFrom)
      : _legAmount(order, order.withdrawalAmount, order.coinTo);
  final sats = btc * 1e8;
  if (sats <= 0) return null;

  if (order.isCashAppPurchase) {
    // New money arriving; its Lightning deposit leg is the rail, not the
    // person's bitcoin leaving.
    return wantOut ? null : (MoneyCategory.bought, sats);
  }
  final kind = classify(order);
  // A send pays someone else, whatever it delivers; a receive is money
  // from outside, whatever paid it. Neither is the person's own other end.
  if (wantOut && kind == SwapActivityKind.receive) return null;
  if (!wantOut && kind == SwapActivityKind.send) return null;
  final counterpart = (wantOut ? order.coinTo : order.coinFrom).toUpperCase();
  final category = switch (kind) {
    SwapActivityKind.purchase => wantOut ? null : MoneyCategory.bought,
    SwapActivityKind.send || SwapActivityKind.receive => MoneyCategory.people,
    SwapActivityKind.investingDeposit ||
    SwapActivityKind.investingWithdrawal ||
    SwapActivityKind.predictionsDeposit ||
    SwapActivityKind.predictionsWithdrawal =>
      MoneyCategory.investments,
    SwapActivityKind.dollarDeposit ||
    SwapActivityKind.dollarWithdrawal =>
      MoneyCategory.dollars,
    // A conversion with no recorded intent: the person's own Dollars
    // when the other end is dollars, anything else left or arrived from
    // outside.
    SwapActivityKind.swap => counterpart == kOrchestraUsdAssetCode
        ? MoneyCategory.dollars
        : MoneyCategory.people,
  };
  return category == null ? null : (category, sats);
}

/// A conversion leg in human units, read the way its activity row reads
/// it.
double _legAmount(SwapOrder order, String raw, String coin) {
  final value = order.isOrchestra
      ? orchestraRowAmount(raw, coin)
      : (double.tryParse(raw) ?? 0);
  return value.isFinite ? value : 0;
}

/// A period's length: a calendar month or a calendar year.
enum MoneyPeriodKind { month, year }

/// One calendar month or year, local time: [start] inclusive, [end]
/// exclusive.
class MoneyPeriod {
  final MoneyPeriodKind kind;
  final DateTime start;

  const MoneyPeriod._(this.kind, this.start);

  /// The period [offset] periods before the one [now] is in (0 = this
  /// month or this year).
  factory MoneyPeriod.back(MoneyPeriodKind kind, DateTime now, int offset) {
    final local = now.toLocal();
    return switch (kind) {
      MoneyPeriodKind.month =>
        MoneyPeriod._(kind, DateTime(local.year, local.month - offset)),
      MoneyPeriodKind.year => MoneyPeriod._(kind, DateTime(local.year - offset)),
    };
  }

  DateTime get end => switch (kind) {
        MoneyPeriodKind.month => DateTime(start.year, start.month + 1),
        MoneyPeriodKind.year => DateTime(start.year + 1),
      };

  bool contains(DateTime at) {
    final local = at.toLocal();
    return !local.isBefore(start) && local.isBefore(end);
  }

  @override
  bool operator ==(Object other) =>
      other is MoneyPeriod && other.kind == kind && other.start == start;

  @override
  int get hashCode => Object.hash(kind, start);
}

/// How many periods the bars show: six months, or the years since the
/// first move (this year alone for a wallet that started this year, five
/// at most): never a row of empty years before the wallet existed.
int moneyPeriodCount(
    MoneyPeriodKind kind, DateTime now, Iterable<MoneyMove> moves) {
  if (kind == MoneyPeriodKind.month) return 6;
  var first = now.toLocal().year;
  for (final m in moves) {
    final y = m.at.toLocal().year;
    if (y < first) first = y;
  }
  return (now.toLocal().year - first + 1).clamp(1, 5);
}

/// A period's money in and out, by category.
class MoneyTotals {
  final Map<MoneyCategory, int> moneyIn;
  final Map<MoneyCategory, int> moneyOut;

  const MoneyTotals(this.moneyIn, this.moneyOut);

  int get totalIn => moneyIn.values.fold(0, (s, v) => s + v);
  int get totalOut => moneyOut.values.fold(0, (s, v) => s + v);
  bool get isEmpty => totalIn == 0 && totalOut == 0;

  Map<MoneyCategory, int> of(MoneySide side) =>
      side == MoneySide.moneyIn ? moneyIn : moneyOut;

  int totalOf(MoneySide side) =>
      side == MoneySide.moneyIn ? totalIn : totalOut;

  /// [side]'s categories with money in them, largest first (ties in
  /// reading order).
  List<MapEntry<MoneyCategory, int>> rowsOf(MoneySide side) {
    final order = moneyCategoriesOf(side);
    return [
      for (final c in order)
        if ((of(side)[c] ?? 0) > 0) MapEntry(c, of(side)[c]!),
    ]..sort((a, b) {
        final byAmount = b.value.compareTo(a.value);
        return byAmount != 0
            ? byAmount
            : order.indexOf(a.key).compareTo(order.indexOf(b.key));
      });
  }
}

/// [moves] summed over [period].
MoneyTotals moneyTotals(Iterable<MoneyMove> moves, MoneyPeriod period) {
  final moneyIn = <MoneyCategory, int>{};
  final moneyOut = <MoneyCategory, int>{};
  for (final m in moves) {
    if (!period.contains(m.at)) continue;
    final into = m.side == MoneySide.moneyIn ? moneyIn : moneyOut;
    into[m.category] = (into[m.category] ?? 0) + m.sats;
  }
  return MoneyTotals(moneyIn, moneyOut);
}
