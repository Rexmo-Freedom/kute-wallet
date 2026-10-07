// Persisted store of past Outlogic fiat orders. The Outlogic on/off
// ramp itself is gone (bank transfers are coming soon via a new rail);
// this Hive-backed read-only store remains so users still see their
// past fiat purchases and sells as transaction-history rows. Rows are
// consumed by the background sync (RawTransactionData.outlogicOrders →
// OutlogicTransaction) and rendered by the activity feed / search.

import 'dart:convert';

import 'package:kute/models/outlogic_model.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive_ce.dart';

const _hiveBoxName = 'outlogicOrders';

final outlogicOrdersProvider =
    StateNotifierProvider<OutlogicOrdersNotifier, List<OutlogicOrder>>((ref) {
  return OutlogicOrdersNotifier();
});

class OutlogicOrdersNotifier extends StateNotifier<List<OutlogicOrder>> {
  OutlogicOrdersNotifier() : super([]) {
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    final box = await Hive.openBox<String>(_hiveBoxName);
    final orders = box.values
        .map((jsonStr) {
          try {
            return OutlogicOrder.fromJson(
                jsonDecode(jsonStr) as Map<String, dynamic>);
          } catch (e) {
            // Skip the corrupt row (preserve original behavior) but report
            // the swallowed deserialize so we notice silent data drift.
            TrackingService.recordCrash(e, null,
                reason: 'outlogic_order_deserialize');
            return null;
          }
        })
        .whereType<OutlogicOrder>()
        .toList();
    orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    state = orders;
  }
}
