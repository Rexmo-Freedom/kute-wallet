// lib/screens/shared/buy_bitcoin_steps_view.dart
//
// A Buy bitcoin's steps on screen. Every move shows its steps the same
// way now (move_steps_view.dart: one model, one widget); these names stay
// for the Buy bitcoin's callers and tests.

import 'package:flutter/widgets.dart' show BuildContext;
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/screens/shared/money_steps_view.dart' show MoneyStepLine;
import 'package:kute/screens/shared/move_steps_view.dart';
import 'package:kute/services/one_balance/buy_bitcoin_steps.dart';
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/services/one_balance/multi_source_move.dart';
import 'package:kute/services/one_balance/pending_bitcoin_purchase.dart'
    show PendingBitcoinPurchase;

/// [move]'s steps as they stand ([liveMoveSteps]); empty for a move that
/// is not a Buy bitcoin.
MoneyStepGraph liveBuyBitcoinSteps(
  MultiSourceMove move,
  List<SwapOrderTransaction> rows, {
  PendingBitcoinPurchase? purchase,
  bool purchaseRunning = false,
}) =>
    BuyBitcoinSteps.describes(move)
        ? liveMoveSteps(move, rows,
            purchase: purchase, purchaseRunning: purchaseRunning)
        : MoneyStepGraph.empty;

/// The lines of [graph] in the app's words, amounts in dollars.
List<MoneyStepLine> buyBitcoinStepLines(
        BuildContext context, MoneyStepGraph graph) =>
    moveStepLines(context.l10n, graph);

/// A Buy bitcoin's steps, live: the one move steps section.
typedef BuyBitcoinStepsSection = MoveStepsSection;
