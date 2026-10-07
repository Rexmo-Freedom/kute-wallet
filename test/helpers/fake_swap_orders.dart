// In-memory swap rows for widget tests: the real notifier opens its Hive
// box on creation. [set] replaces the rows, as background sync does when
// an order moves on.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/swap_order_model.dart';

class FakeSwapOrders extends StateNotifier<List<SwapOrder>>
    implements SwapOrdersNotifier {
  FakeSwapOrders([super.state = const []]);

  void set(List<SwapOrder> rows) => state = rows;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// An Orchestra deposit into a pool: [network] 'POLYGON' (Predictions) or
/// 'HYPERCORE' (Investing), [usd] the estimated dollars arriving.
SwapOrder poolDepositRow({
  required String id,
  required String network,
  required double usd,
  String status = 'exchanging',
  DateTime? at,
}) =>
    SwapOrder(
      id: id,
      coinFrom: 'USDB',
      networkFrom: 'SPARK',
      coinTo: 'USDC',
      networkTo: network,
      depositAddress: 'deposit',
      depositAmount: usd.toStringAsFixed(2),
      withdrawalAmount: usd.toStringAsFixed(2),
      status: status,
      timestamp: (at ?? DateTime.now()).millisecondsSinceEpoch,
      withdrawalAddress: 'recipient',
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: 'refund',
      provider: 'Orchestra',
    );
