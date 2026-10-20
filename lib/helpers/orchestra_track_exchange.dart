import 'package:kute/handlers/response_handlers.dart';
import 'package:kute/helpers/orchestra_legacy_status_rules.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/services/orchestra/onetime_receive.dart'
    show isOneTimeReceiveQuoteRow;

/// "Track this exchange" opens an Orchestra order on Flashnet's public
/// explorer. The explorer only shows orders: a quote id (`q_…`) is answered
/// with "id must be an order id". A row is written under its quote id and
/// background sync moves it to the order id once a status read returns one,
/// so a row tapped in between still holds the quote. The tap then asks for
/// the order the quote became (the status read background sync uses), moves
/// the row to it and opens that; with no order yet, nothing opens.

/// The explorer page of an Orchestra order.
Uri orchestraExplorerUri(String orderId) =>
    Uri.https('orchestra.flashnet.xyz', '/explorer/$orderId');

/// The id the explorer opens for a row id, or null when the row holds no
/// order id: a quote (`q_…`), a synthetic placeholder (`acu-…`) or a CCTP
/// move not yet an order (`cctp-…`). A legacy bare uuid gets `ord_`.
String? orchestraExplorerOrderId(String rowId) {
  if (rowId.isEmpty ||
      rowId.startsWith('q_') ||
      rowId.startsWith('acu-') ||
      rowId.startsWith('cctp-')) {
    return null;
  }
  return rowId.startsWith('ord_') ? rowId : 'ord_$rowId';
}

/// Whether a quote row can still have become an order the tap could find.
/// An expired quote and a one-time receive still waiting for its deposit
/// have none, so they offer no explorer button.
bool orchestraTrackResolvable(SwapOrder row) =>
    row.id.startsWith('q_') &&
    row.status != 'expired' &&
    !(isOneTimeReceiveQuoteRow(row) && row.status == 'wait');

/// The order id to open for [row]: its own, or for a quote row the order
/// the quote became, read at tap time. A found order is handed to [store]
/// as the row under its order id (every other field kept), so the record
/// no longer holds the quote. Null when the quote has no order yet or the
/// read failed: nothing must open then.
Future<String?> resolveOrchestraTrackOrderId(
  SwapOrder row, {
  required Future<Result<OrchestraOrder>> Function(String quoteId) read,
  required Future<void> Function(SwapOrder replacement, OrchestraOrder order)
      store,
}) async {
  final known = orchestraExplorerOrderId(row.id);
  if (known != null) return known;
  if (!row.id.startsWith('q_')) return null;
  final Result<OrchestraOrder> result;
  try {
    result = await read(row.id);
  } catch (_) {
    return null;
  }
  if (classifyOrchestraStatusRead(result) != OrchestraStatusReadKind.order) {
    return null;
  }
  final order = result.data!;
  final orderId = legacyReplacementOrderId(row.id, order);
  if (orderId == null) return null;
  try {
    await store(legacyRowWithOrderId(row, orderId), order);
  } catch (_) {
    // The order is known: open it. Background sync moves the row later.
  }
  return orchestraExplorerOrderId(orderId);
}

/// The stored row an open detail sheet shows for [snapshot], the row it was
/// opened with. Background sync moves a quote row to its order id, possibly
/// while the sheet is open, so the sheet follows it: the same id first;
/// then a Cash App purchase by its invoice, and any other quote row by the
/// deposit address and creation time the moved row keeps. The snapshot
/// when the store has neither (a row not kept in the swap store).
SwapOrder liveSwapOrderRow(SwapOrder snapshot, List<SwapOrder> orders) {
  final same = orders.where((o) => o.id == snapshot.id).firstOrNull;
  if (same != null) return same;
  if (snapshot.depositAddress.isEmpty) return snapshot;
  if (snapshot.isCashAppPurchase) {
    return orders
            .where((o) => o.depositAddress == snapshot.depositAddress)
            .firstOrNull ??
        snapshot;
  }
  if (!snapshot.id.startsWith('q_')) return snapshot;
  return orders
          .where((o) =>
              o.depositAddress == snapshot.depositAddress &&
              o.timestamp == snapshot.timestamp &&
              !o.id.startsWith('q_'))
          .firstOrNull ??
      snapshot;
}
