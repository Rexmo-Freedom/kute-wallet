// Resting (unfilled) GTC limit orders for the active Polymarket account.
//
// Polls `getOpenOrders()` on a short interval so the user sees fill
// progress (size_matched climbing) and orders disappear as they fill or
// are cancelled. autoDispose — stops polling when nothing watches it
// (i.e. the user isn't on a screen that shows open orders).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart' show Order;

import 'package:kute/providers/polymarket_trading_provider.dart';

const _kPollInterval = Duration(seconds: 8);

final polymarketOpenOrdersProvider =
    StreamProvider.autoDispose<List<Order>>((ref) {
  // Recreate the stream when the account changes; never carry one wallet's
  // reserved balance into another wallet's ticket.
  ref.watch(polymarketTradingProvider.select((state) => (
        state.valueOrNull?.walletAddress,
        state.valueOrNull?.proxyWalletAddress,
      )));
  final notifier = ref.read(polymarketTradingProvider.notifier);
  final controller = StreamController<List<Order>>();
  Timer? timer;
  var disposed = false;
  ref.onDispose(() {
    disposed = true;
    timer?.cancel();
    unawaited(controller.close());
  });
  Future<void> poll() async {
    try {
      final orders =
          await notifier.getOpenOrders().timeout(const Duration(seconds: 8));
      if (!disposed) controller.add(orders);
    } catch (error, stack) {
      if (!disposed) controller.addError(error, stack);
    } finally {
      // A transient authenticated read used to terminate async* permanently,
      // leaving "Balance unavailable" until the ticket was reopened.
      if (!disposed) timer = Timer(_kPollInterval, poll);
    }
  }

  unawaited(poll());
  return controller.stream;
});
