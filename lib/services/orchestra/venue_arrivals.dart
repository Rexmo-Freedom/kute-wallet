// lib/services/orchestra/venue_arrivals.dart
//
// Two things the app learns about an Orchestra leg before (or without) its
// own status read saying so.
//
//  * [OrchestraOrderIds]: the order a quote became. A leg is written under
//    its quote id (`q_…`) and every status read of it asks Orchestra by
//    quote. The order id is often known elsewhere first: the deposit
//    submit that registered it (the flow's own, in the background, or the
//    settlement reconciler's retry), a status read that returned it. Each
//    of them records it here, and a status read of the quote reads the
//    order instead (`orchestraLegStatus`), so a leg never depends on the
//    quote lookup alone once the order is known.
//
//  * [VenueArrivals]: a leg's money seen in its destination by the app
//    itself (the venue credited the order it funds; the Predictions
//    deposit wallet's USDC.e converted to pUSD), while Orchestra's own
//    status still says it is on its way. The row keeps Orchestra's status
//    (its detail still says "Processing"); only the journey's arrival
//    shows done ([MoveSteps.ofRow]'s `arrived`).

import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/swap_order_model.dart';

/// The order each quote became, as far as this process learned it.
abstract final class OrchestraOrderIds {
  static final Map<String, String> _byQuote = {};

  /// Records that [quoteId] became [orderId]. Ignores anything that is not
  /// a quote id moving to a real (non-quote) id.
  static void record(String quoteId, String? orderId) {
    if (!quoteId.startsWith('q_') ||
        orderId == null ||
        orderId.isEmpty ||
        orderId == quoteId ||
        orderId.startsWith('q_')) {
      return;
    }
    _byQuote[quoteId] = orderId;
  }

  /// The order [id] became when it is a quote with a known order, else
  /// [id] itself.
  static String resolve(String id) => _byQuote[id] ?? id;

  /// The order [quoteId] became, or null when none is known.
  static String? orderOf(String quoteId) => _byQuote[quoteId];

  @visibleForTesting
  static void debugReset() => _byQuote.clear();
}

/// Rows whose money the app saw land in its destination.
abstract final class VenueArrivals {
  /// Bumped whenever a row is marked.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Row ids, quote ids and operation ids marked as arrived.
  static final Set<String> _keys = {};

  /// How long before an observed arrival a deposit row may have been
  /// created to be matched to it.
  static const Duration matchWindow = Duration(minutes: 90);

  /// Marks [row] as arrived: under its id, its operation and, for a quote,
  /// the order it became (a row moves from the quote id to the order id
  /// and keeps its operation).
  static void mark(SwapOrder row) => markIds([
        row.id,
        if (row.operationId != null) row.operationId!,
        if (OrchestraOrderIds.orderOf(row.id) case final order?) order,
      ]);

  /// Marks every one of [ids] (row ids, quote ids, operation ids).
  static void markIds(Iterable<String> ids) {
    var added = false;
    for (final id in ids) {
      if (id.isEmpty) continue;
      if (_keys.add(id)) added = true;
      final order = OrchestraOrderIds.orderOf(id);
      if (order != null && _keys.add(order)) added = true;
    }
    if (added) revision.value++;
  }

  /// Whether [row]'s money was seen in its destination.
  static bool arrived(SwapOrder row) =>
      _keys.contains(row.id) ||
      (row.operationId != null && _keys.contains(row.operationId)) ||
      _keys.contains(OrchestraOrderIds.resolve(row.id));

  /// The pending Predictions deposit row [usd] of USDC.e landing in
  /// [wallet] at [at] stands for, or null when none fits: still on its way
  /// by Orchestra's status, delivering to [wallet], created within
  /// [matchWindow] before [at], its estimate within 10% of [usd]. The
  /// closest estimate wins; one arrival marks one row.
  static SwapOrder? matchPredictionsArrival(
    Iterable<SwapOrder> rows, {
    required String wallet,
    required double usd,
    required DateTime at,
  }) {
    if (usd <= 0 || wallet.isEmpty) return null;
    SwapOrder? best;
    double? bestGap;
    for (final row in rows) {
      final asset = row.coinTo.trim().toUpperCase();
      if (!row.isOrchestra ||
          row.networkTo.trim().toUpperCase() != 'POLYGON' ||
          (asset != 'USDC' && asset != 'USDC.E') ||
          !row.shouldPollOrchestra ||
          row.withdrawalAddress.toLowerCase() != wallet.toLowerCase() ||
          arrived(row)) {
        continue;
      }
      final created = DateTime.fromMillisecondsSinceEpoch(row.timestamp);
      final age = at.difference(created);
      if (age.isNegative || age > matchWindow) continue;
      final est = double.tryParse(row.withdrawalAmount) ?? 0;
      if (est <= 0) continue;
      final gap = (usd - est).abs() / est;
      if (gap > 0.10) continue;
      if (bestGap == null || gap < bestGap) {
        bestGap = gap;
        best = row;
      }
    }
    return best;
  }

  /// [usd] of USDC.e landed in the Predictions deposit [wallet] (seen when
  /// it was converted to pUSD): marks the deposit row it stands for
  /// ([matchPredictionsArrival]). Returns the row marked, or null.
  static SwapOrder? predictionsArrived(
    Iterable<SwapOrder> rows, {
    required String wallet,
    required double usd,
    DateTime? at,
  }) {
    final row = matchPredictionsArrival(rows,
        wallet: wallet, usd: usd, at: at ?? DateTime.now());
    if (row != null) mark(row);
    return row;
  }

  @visibleForTesting
  static void debugReset() {
    _keys.clear();
    revision.value++;
  }
}

/// Rebuilds its watchers when a row is marked as arrived.
final venueArrivalsProvider =
    NotifierProvider<VenueArrivalsNotifier, int>(VenueArrivalsNotifier.new);

class VenueArrivalsNotifier extends Notifier<int> {
  @override
  int build() {
    void changed() => state = VenueArrivals.revision.value;
    VenueArrivals.revision.addListener(changed);
    ref.onDispose(() => VenueArrivals.revision.removeListener(changed));
    return VenueArrivals.revision.value;
  }
}
