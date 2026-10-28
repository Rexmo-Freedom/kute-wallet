// lib/services/funding/settlement_registration.dart
//
// Follows a deposit submit the settlement runner finishes after its flow
// returned ([SettlementPlan.registerInBackground]). The flow wrote its
// Activity row under the quote id; the moment the submit returns the
// provider order id, the row moves to it, so status polling reads the order
// at once instead of waiting for the quote-id poll to find it.

import 'dart:async';

import 'package:kute/helpers/orchestra_legacy_status_rules.dart'
    show legacyRowWithOrderId, replaceOrchestraRowId;
import 'package:kute/models/affiliate_model.dart' show AffiliateService;
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/swap_orders_provider.dart'
    show swapOrdersProvider;
import 'package:kute/providers/transactions_provider.dart'
    show walletTransactionCacheProvider;
import 'package:kute/services/background_sync_service.dart';
import 'package:kute/services/funding/owned_address_resolver.dart'
    show ProviderReader;
import 'package:kute/services/funding/settlement_runner.dart';
import 'package:kute/services/orchestra/venue_arrivals.dart'
    show OrchestraOrderIds;

/// Where the Activity row lives, as callbacks so the move is testable.
class OrchestraActivityRows {
  const OrchestraActivityRows({
    required this.rows,
    required this.add,
    required this.delete,
    required this.uncache,
    required this.cache,
    this.logPending,
  });

  /// Every swap order row the app holds.
  final List<SwapOrder> Function() rows;
  final Future<void> Function(SwapOrder row) add;
  final Future<void> Function(String id) delete;

  /// Drops a row id from the Activity cache the screens render.
  final void Function(String id) uncache;

  /// Writes a row into the Activity cache the screens render.
  final void Function(SwapOrder row) cache;

  /// Registers the real order with the backend as pending (revenue
  /// attribution), as the creation site does for a registered order.
  final void Function(SwapOrder row)? logPending;

  factory OrchestraActivityRows.of(ProviderReader read) =>
      OrchestraActivityRows(
        rows: () => read(swapOrdersProvider),
        add: read(swapOrdersProvider.notifier).addExchange,
        delete: read(swapOrdersProvider.notifier).deleteExchange,
        uncache: read(walletTransactionCacheProvider.notifier).removeSwapOrder,
        cache: (row) =>
            read(walletTransactionCacheProvider.notifier).mergeSwapOrder(row),
        logPending: (row) {
          // ignore: unawaited_futures
          AffiliateService.logProviderEvent(
            provider: 'orchestra',
            providerOrderId: row.id,
            status: 'pending',
            sourceAsset: row.coinFrom,
            sourceAmount: double.tryParse(row.depositAmount),
            destinationAsset: row.coinTo,
            destinationAmount: double.tryParse(row.withdrawalAmount),
          );
        },
      );
}

/// Moves the row held under [quoteId] to [orderId]: the new row is written
/// before the quote row is deleted, so a kill between the writes leaves a
/// polled row. Returns the new row, or null when there was nothing to move
/// (the status poll already moved it, or the row is gone).
Future<SwapOrder?> adoptRegisteredOrchestraRow({
  required String quoteId,
  required String orderId,
  required OrchestraActivityRows rows,
}) async {
  if (orderId.isEmpty || orderId == quoteId || orderId.startsWith('q_')) {
    return null;
  }
  // Status reads of the quote (a leg still watched under it) read the
  // order from now on, whether or not a row is moved here.
  OrchestraOrderIds.record(quoteId, orderId);
  SwapOrder? row;
  for (final candidate in rows.rows()) {
    if (candidate.id == quoteId) {
      row = candidate;
      break;
    }
  }
  if (row == null) return null;
  final replacement = legacyRowWithOrderId(row, orderId);
  await replaceOrchestraRowId(
    oldId: quoteId,
    replacement: replacement,
    add: rows.add,
    delete: rows.delete,
  );
  rows.uncache(quoteId);
  rows.cache(replacement);
  // A row already closed is reported by the terminal mirror instead.
  if (replacement.shouldPollOrchestra) rows.logPending?.call(replacement);
  return replacement;
}

/// Runs [action] with the id an order is reported under: at once for a run
/// that registered inline, otherwise when its background registration
/// ends, with the order id it returned or the quote id when it returned
/// none (the same id an unregistered run reports). Never throws.
void withSettlementOrderId(
  SettlementRunResult run,
  void Function(String orderId) action,
) {
  final quoteId = run.quote.quoteId;
  final registration = run.registration;
  void fire(String? orderId) {
    try {
      action(orderId == null || orderId.isEmpty ? quoteId : orderId);
    } catch (_) {}
  }

  if (registration == null) {
    fire(run.orderId);
    return;
  }
  unawaited(registration.then(fire).catchError((Object _) => fire(null)));
}

/// When [run]'s background registration returns an order id, moves its
/// Activity row to it and asks for a sync, so the row's status is read
/// from the order straight away. [read] must outlive the calling screen
/// (a provider's reader or the root container's). Never throws.
void followSettlementRegistration(
  ProviderReader read,
  SettlementRunResult run, {
  void Function(String orderId)? onRegistered,
}) {
  final registration = run.registration;
  if (registration == null) return;
  final quoteId = run.quote.quoteId;
  unawaited(registration.then((orderId) async {
    if (orderId == null || orderId.isEmpty) return;
    try {
      await adoptRegisteredOrchestraRow(
        quoteId: quoteId,
        orderId: orderId,
        rows: OrchestraActivityRows.of(read),
      );
      onRegistered?.call(orderId);
      BackgroundSyncService().syncNow();
    } catch (_) {
      // The status poll moves the row from the quote id on its own.
    }
  }).catchError((Object _) {}));
}
