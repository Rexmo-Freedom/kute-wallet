import 'package:kute/models/orchestra_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─── Estimate ───────────────────────────────────────────────────────

// ─── Create Onramp (Cash App Buy) ──────────────────────────────────

// ─── Order Status ──────────────────────────────────────────────────

// ─── Pay Links ─────────────────────────────────────────────────────

// ─── In-memory Orchestra Orders (session tracking) ─────────────────

class OrchestraOrdersNotifier extends StateNotifier<List<OrchestraOrder>> {
  OrchestraOrdersNotifier() : super([]);

  void addOrder(OrchestraOrder order) {
    state = [order, ...state];
  }

  void updateOrder(OrchestraOrder updated) {
    state = state.map((o) => o.id == updated.id ? updated : o).toList();
  }

  List<OrchestraOrder> get pendingOrders =>
      state.where((o) => !o.isTerminal).toList();
}

final orchestraOrdersProvider =
    StateNotifierProvider<OrchestraOrdersNotifier, List<OrchestraOrder>>((ref) {
  return OrchestraOrdersNotifier();
});
