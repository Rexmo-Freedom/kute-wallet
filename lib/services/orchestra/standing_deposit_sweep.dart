// lib/services/orchestra/standing_deposit_sweep.dart
//
// Every deposit the provider lists on a standing instruction this wallet
// holds reaches Activity, from the moment the provider observes it:
//
//   * a deposit that became an order (`orderId: ord_…`) gets that order's
//     row. The listing's link is the provider's own attribution for this
//     wallet's reference, so the order is not re-matched on its source
//     leg: Flashnet may bridge an EVM deposit before converting it (the
//     `relay-deposit` route component), and the order it then creates can
//     name another source chain and deposit address than the one the
//     person paid. It must still pay this instruction's own recipient;
//   * until that row exists (no order yet, or the order cannot be read),
//     the deposit has its own row (`sdep_…`, standing_deposit_activity.dart)
//     reading arriving, held, returned or failed.
//
// Background sync runs this for every reference on its standing sweep.

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:kute/models/orchestra_model.dart' show OrchestraOrder;
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/services/orchestra/standing_deposit_activity.dart';
import 'package:kute/services/orchestra/standing_deposit_store.dart';
import 'package:kute/services/orchestra_routes.dart'
    show orchestraExchangeStatus;
import 'package:kute/services/security/address_guard.dart'
    show sameSparkAddress;
import 'package:kute/services/tracking_service.dart';

/// Where the sweep reads and writes Activity rows.
abstract class StandingDepositRows {
  SwapOrder? find(String id);

  /// Inserts or replaces [row].
  Future<void> put(SwapOrder row);
  Future<void> remove(String id);
}

/// Whether [order] is the order the provider linked a deposit on
/// [record] to: the linked id, into the instruction's destination, paying
/// the instruction's own recipient. Source chain, source asset and
/// deposit address are not compared (see the file comment).
bool standingOrderBelongs(
    OrchestraOrder order, String orderId, StandingDepositRecord record) {
  bool same(String? actual, String expected) =>
      actual == null || actual.toLowerCase() == expected.toLowerCase();
  if (order.id != orderId ||
      record.chain != 'spark' ||
      !same(order.destinationChain, record.chain) ||
      !same(order.destinationAsset, record.asset)) {
    return false;
  }
  final to = order.recipientAddress;
  return to != null && to.isNotEmpty && sameSparkAddress(to, record.recipient);
}

class StandingDepositSweep {
  StandingDepositSweep({
    required this.rows,
    required this.deposits,
    required this.order,
    required this.discovered,
  });

  final StandingDepositRows rows;

  /// The provider's listing for one reference.
  final Future<List<Map<String, dynamic>>> Function(
      StandingDepositRecord record, bool Function() current) deposits;

  /// One order's status, or null when it cannot be read.
  final Future<OrchestraOrder?> Function(String orderId) order;

  /// First-insert attribution of an order row
  /// (`reportDiscoveredOrchestraOrder`).
  final void Function(SwapOrder row) discovered;

  /// Brings Activity in line with [record]'s deposits. [recipient] is the
  /// wallet's own Spark address today: orders are written only for an
  /// instruction that pays it, while every deposit row is written
  /// whichever recipient the instruction names (a stuck deposit is
  /// returned to its payer).
  Future<void> syncRecord({
    required StandingDepositRecord record,
    required String walletId,
    required String recipient,
    required bool Function() current,
  }) async {
    final listed = await deposits(record, current);
    final own = sameSparkAddress(recipient, record.recipient);
    for (final deposit in listed) {
      if (!current()) return;
      final orderId = standingDepositHasOrder(deposit)
          ? deposit['orderId'] as String
          : null;
      if (orderId != null && own && rows.find(orderId) == null) {
        await _recordOrder(
            deposit: deposit,
            orderId: orderId,
            record: record,
            walletId: walletId,
            current: current);
        if (!current()) return;
      }
      await _syncDepositRow(
          deposit: deposit,
          orderId: orderId,
          record: record,
          walletId: walletId);
    }
  }

  Future<void> _recordOrder({
    required Map<String, dynamic> deposit,
    required String orderId,
    required StandingDepositRecord record,
    required String walletId,
    required bool Function() current,
  }) async {
    final chain = deposit['chain'];
    final asset = deposit['asset'];
    if (chain is! String || asset is! String) return;
    OrchestraOrder? found;
    try {
      found = await order(orderId);
    } catch (_) {
      return; // The deposit's own row stands in until the next sweep.
    }
    if (!current() || found == null) return;
    if (!standingOrderBelongs(found, orderId, record)) return;
    final amount = deposit['amount'];
    final row = standingOrderRow(
        record: record,
        orderId: orderId,
        chain: chain,
        asset: asset,
        depositAddress: record.addressFor(chain) ?? '',
        // What the person sent, as the provider observed it on the chain
        // they paid; the order's own leg may be a bridged one.
        amountIn: amount != null ? '$amount' : (found.amountIn ?? '0'),
        amountOut: found.amountOut ?? '0',
        status: orchestraExchangeStatus(found.status),
        timestamp: DateTime.tryParse(found.createdAt)?.millisecondsSinceEpoch ??
            DateTime.now().millisecondsSinceEpoch,
        recipient: record.recipient,
        walletId: walletId);
    if (rows.find(orderId) != null) return;
    await rows.put(row);
    discovered(row);
  }

  Future<void> _syncDepositRow({
    required Map<String, dynamic> deposit,
    required String? orderId,
    required StandingDepositRecord record,
    required String walletId,
  }) async {
    final rowId = stuckStandingDepositRowId(deposit);
    if (rowId == null) return;
    final existing = rows.find(rowId);
    // The order's own row (and its refund) represents the deposit now.
    if (orderId != null && rows.find(orderId) != null) {
      if (existing != null) await rows.remove(rowId);
      return;
    }
    final row = standingDepositRow(
        deposit: deposit,
        record: record,
        walletId: walletId,
        recipient: record.recipient,
        existing: existing);
    if (row == null) return;
    if (existing != null &&
        existing.status == row.status &&
        existing.depositAmount == row.depositAmount) {
      return;
    }
    await rows.put(row);
    trackStandingDepositStatus(
        row: row,
        previousStatus: existing?.status,
        record: record,
        linkedOrder: orderId != null,
        code: deposit['code']);
  }
}

/// `standing_deposit_status`: a deposit on a reusable address got its
/// Activity row or changed status. Exact amount; never an address, an id
/// or provider text beyond its machine code.
@visibleForTesting
void trackStandingDepositStatus({
  required SwapOrder row,
  required String? previousStatus,
  required StandingDepositRecord record,
  required bool linkedOrder,
  Object? code,
}) {
  final investing =
      StandingDepositStore.isInvestingWithdrawalLabel(record.label);
  TrackingService.track('standing_deposit_status', params: {
    'status': row.status,
    'previous_status': previousStatus ?? 'none',
    'source_chain': row.networkFrom.toLowerCase(),
    'source_asset': row.coinFrom,
    'destination_asset': record.asset,
    if (double.tryParse(row.depositAmount) case final amount?) 'amount': amount,
    'linked_order': linkedOrder,
    'instruction': investing ? 'investing_withdrawal' : 'receive',
    if (code is String && code.isNotEmpty && code.length <= 64)
      'provider_code': code,
  });
}

/// Whether the person was just given a reusable deposit address, so its
/// deposits are watched on every screen, not only where the full sync
/// runs (Home and the wallet detail). Armed by
/// `ReusableDepositAddressService.resolve` each time an address is shown;
/// a deposit observed meanwhile keeps its own pending row, which keeps
/// the sync running on its own.
abstract final class ReceiveAddressWatch {
  /// How long after an address was shown its deposits are watched.
  static const Duration window = Duration(hours: 6);

  /// How often the deposit-address sweeps run while watched.
  static const Duration cadence = Duration(seconds: 30);

  static DateTime? _shownAt;

  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  /// An address was shown just now.
  static void shown() => _shownAt = clock();

  static bool get watching {
    final at = _shownAt;
    if (at == null) return false;
    final age = clock().difference(at);
    return age >= Duration.zero && age < window;
  }

  @visibleForTesting
  static void reset() {
    _shownAt = null;
    clock = DateTime.now;
  }
}

/// How long the standing sweep waits between runs: [ReceiveAddressWatch.cadence]
/// while an address was just shown or a deposit is on its way, a minute
/// otherwise.
Duration standingSweepInterval(
        {required bool watching, required bool inFlight}) =>
    watching || inFlight
        ? ReceiveAddressWatch.cadence
        : const Duration(minutes: 1);
