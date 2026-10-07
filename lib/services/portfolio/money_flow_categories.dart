// lib/services/portfolio/money_flow_categories.dart
//
// What the Breakdown tab's donut is made of, on Home (the spending
// wallet's bitcoin) and on Dollars: where the money went, or where it
// came from, all time, by kind.
//
// The input is the ledger's own activity rows ([assembleActivityRows]
// with `keepVenueMoves`), so the donut counts exactly what Activity lists,
// once per user intent: a conversion's funding send or settle receive is
// already folded behind the conversion row, a dollar transfer that paid
// a swap behind the swap.
//
//   * Bitcoin (sats): Spark payments by rail (Lightning, Spark, on-chain;
//     an on-chain receive counts once claimed), and every conversion with
//     a bitcoin leg on the side that moved: to or from Investing,
//     Predictions or Dollars, a send to another coin, a coin received
//     from outside, a Cash App purchase.
//   * Dollars (US dollars): dollar transfers (Spark), and every conversion
//     with a dollar leg on the side that moved: to or from Investing,
//     Predictions or Bitcoin, a dollar-funded send by the rail it was
//     delivered on, a coin received into dollars, a Cash App purchase.
//
// Only settled money counts: a completed payment, a finished conversion.
// Something still in flight, failed, expired or refunded is not money
// that went anywhere. A Predictions row on the venue's side (in dollars,
// on the Polymarket account) never counts: the conversion beside it is
// the move, in the ledger's unit. Fees are not a category: a payment
// counts its amount.
//
// The Spark payment list is the SDK's whole on-device history and the
// conversions are the app's own order store, so the split is all time.

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;

import 'package:kute/helpers/orchestra_router.dart' show orchestraRowAmount;
import 'package:kute/helpers/swap_activity.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode;
import 'package:kute/services/portfolio/portfolio_categories.dart'
    show kPortfolioOtherCategory;

/// Which balance a Breakdown donut is about.
enum MoneyFlowLedger { bitcoin, dollars }

/// Which way the money moved.
enum MoneyFlowDirection { sent, received }

/// The categories' keys: public slugs, also the analytics `category`.
abstract final class MoneyFlowCategory {
  static const lightning = 'lightning';
  static const spark = 'spark';
  static const onchain = 'onchain';
  static const investing = 'investing';
  static const predictions = 'predictions';

  /// Bitcoin moved into or out of the person's own dollars.
  static const dollars = 'dollars';

  /// Dollars moved into or out of the person's own bitcoin.
  static const bitcoin = 'bitcoin';

  /// A coin other than bitcoin and dollars, sent or received.
  static const otherCrypto = 'other_crypto';
  static const cashApp = 'cash_app';
  static const other = kPortfolioOtherCategory;
}

/// Amount per category for [direction] on [ledger], all time, from the
/// ledger's activity [rows]. Nothing worth zero is kept. [classify] reads
/// a conversion's intent; tests pass their own.
Map<String, double> moneyFlowCategories(
  Iterable<BaseTransaction> rows, {
  required MoneyFlowLedger ledger,
  required MoneyFlowDirection direction,
  SwapActivityKind Function(SwapOrder order) classify = swapActivityFor,
}) {
  final out = <String, double>{};
  void add(String key, double amount) {
    if (!amount.isFinite || amount <= 0) return;
    out[key] = (out[key] ?? 0) + amount;
  }

  final wantSent = direction == MoneyFlowDirection.sent;
  for (final tx in rows) {
    switch (ledger) {
      case MoneyFlowLedger.bitcoin:
        if (tx is SparkTransaction) {
          if ((tx.type == TransactionType.sent) != wantSent) continue;
          if (!_sparkSettled(tx)) continue;
          add(_railOf(tx.sparkType), tx.amountSats.toDouble());
        } else if (tx is SwapOrderTransaction) {
          final entry = _swapEntry(tx.details, 'BTC',
              wantSent: wantSent, classify: classify);
          if (entry != null) add(entry.$1, entry.$2 * 1e8);
        }
      case MoneyFlowLedger.dollars:
        if (tx is UsdbTokenTransaction) {
          final sent = tx.details.paymentType == breez.PaymentType.send;
          if (sent != wantSent) continue;
          if (tx.details.status != breez.PaymentStatus.completed) continue;
          add(MoneyFlowCategory.spark, tx.amount.toInt() / 1e6);
        } else if (tx is SwapOrderTransaction) {
          final entry = _swapEntry(tx.details, kOrchestraUsdAssetCode,
              wantSent: wantSent, classify: classify);
          if (entry != null) add(entry.$1, entry.$2);
        }
    }
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

String _railOf(SparkTransactionType type) => switch (type) {
      SparkTransactionType.lightning => MoneyFlowCategory.lightning,
      SparkTransactionType.spark => MoneyFlowCategory.spark,
      SparkTransactionType.bitcoin => MoneyFlowCategory.onchain,
    };

/// The category and the amount (in [coin], human units) of a conversion
/// on the [coin] ledger's [wantSent] side, or null when it did not move
/// that ledger that way or has not settled.
(String, double)? _swapEntry(
  SwapOrder order,
  String coin, {
  required bool wantSent,
  required SwapActivityKind Function(SwapOrder order) classify,
}) {
  if (!order.isComplete) return null;
  final from = order.coinFrom.toUpperCase();
  final to = order.coinTo.toUpperCase();
  // Bitcoin to bitcoin or dollars to dollars across rails is a send or a
  // receive of the same money; only its own side counts.
  final leg = wantSent ? from : to;
  if (leg != coin) return null;
  final amount = wantSent
      ? _legAmount(order, order.depositAmount, order.coinFrom)
      : _legAmount(order, order.withdrawalAmount, order.coinTo);
  if (amount <= 0) return null;

  if (order.isCashAppPurchase) {
    // New money arriving; its Lightning deposit leg is the rail, not the
    // person's bitcoin leaving.
    return wantSent ? null : (MoneyFlowCategory.cashApp, amount);
  }
  final kind = classify(order);
  // A send pays someone else, whatever it delivers; a receive is money
  // from outside, whatever paid it. Neither is the person's own other end.
  if (wantSent && kind == SwapActivityKind.receive) return null;
  if (!wantSent && kind == SwapActivityKind.send) return null;
  final counterpart = wantSent ? to : from;
  final String key;
  if (wantSent) {
    key = switch (kind) {
      SwapActivityKind.predictionsDeposit => MoneyFlowCategory.predictions,
      SwapActivityKind.investingDeposit => MoneyFlowCategory.investing,
      SwapActivityKind.send => _railOfNetwork(order.networkTo, order.coinTo),
      _ => _ownBalance(counterpart),
    };
  } else {
    key = switch (kind) {
      SwapActivityKind.predictionsWithdrawal => MoneyFlowCategory.predictions,
      SwapActivityKind.investingWithdrawal => MoneyFlowCategory.investing,
      SwapActivityKind.receive =>
        _railOfNetwork(order.networkFrom, order.coinFrom),
      _ => _ownBalance(counterpart),
    };
  }
  return (key, amount);
}

/// Where a send was delivered or a receive came from, by its rail: the
/// bitcoin rails and Spark (a dollar address is a Spark address) keep
/// their names; any other coin is "other crypto".
String _railOfNetwork(String network, String coin) {
  final c = coin.toUpperCase();
  final n = network.toUpperCase();
  if (c == 'BTC') {
    if (n == 'LIGHTNING') return MoneyFlowCategory.lightning;
    if (n == 'SPARK') return MoneyFlowCategory.spark;
    return MoneyFlowCategory.onchain;
  }
  if (c == kOrchestraUsdAssetCode) return MoneyFlowCategory.spark;
  return MoneyFlowCategory.otherCrypto;
}

/// A conversion between the person's own balances with no venue intent:
/// named by the balance at the other end.
String _ownBalance(String counterpartCoin) => switch (counterpartCoin) {
      kOrchestraUsdAssetCode => MoneyFlowCategory.dollars,
      'BTC' => MoneyFlowCategory.bitcoin,
      _ => MoneyFlowCategory.otherCrypto,
    };

/// A conversion leg in human units, read the way its activity row reads
/// it.
double _legAmount(SwapOrder order, String raw, String coin) {
  final value = order.isOrchestra
      ? orchestraRowAmount(raw, coin)
      : (double.tryParse(raw) ?? 0);
  return value.isFinite ? value : 0;
}
