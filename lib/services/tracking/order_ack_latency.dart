// lib/services/tracking/order_ack_latency.dart
//
// `order_submit_ack_latency`: one event per venue order POST, measured
// from the moment the signed request leaves the device to the venue's
// acknowledgement (or the failure that stands in for it). Props are the
// venue, the categorical order kind and the outcome — never the order,
// its size, price, ids or the account.
import 'package:kute/services/tracking/latency_tracker.dart';

abstract final class OrderAckLatency {
  /// Emits one `order_submit_ack_latency` for a finished round-trip.
  /// [outcome] is 'ok' | 'rejected' | 'error' | 'timeout'.
  static void record({
    required String venue,
    required String orderKind,
    required int durationMs,
    required String outcome,
  }) =>
      LatencyTracker.record(LatencyKeys.orderSubmitAck, durationMs, params: {
        'venue': venue,
        'order_kind': orderKind,
        'outcome': outcome,
      });

  /// Categorical kind of a signed Hyperliquid exchange action, or null
  /// when the action is not an order submission (cancels, leverage,
  /// transfers…), which must not produce an order-ack measurement.
  ///
  /// 'market' | 'limit' | 'trigger' | 'tpsl' | 'scale' | 'twap' |
  /// 'trailing_stop' | 'modify'
  static String? hyperliquidOrderKind(Map<String, dynamic> action) {
    switch (action['type']) {
      case 'twapOrder':
        return 'twap';
      case 'trailingStop':
        return 'trailing_stop';
      case 'modify':
      case 'batchModify':
        return 'modify';
      case 'order':
        break;
      default:
        return null;
    }
    final grouping = action['grouping'];
    if (grouping == 'normalTpsl' || grouping == 'positionTpsl') return 'tpsl';
    final orders = action['orders'];
    if (orders is! List || orders.isEmpty) return 'limit';
    if (orders.length > 1) return 'scale';
    final first = orders.first;
    final type = first is Map ? first['t'] : null;
    if (type is Map && type.containsKey('trigger')) return 'trigger';
    final limit = type is Map ? type['limit'] : null;
    final tif = limit is Map ? limit['tif'] : null;
    return tif == 'Ioc' ? 'market' : 'limit';
  }
}
