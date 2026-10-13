// lib/services/orchestra/own_spark_arrivals.dart
//
// Money an Orchestra order delivers to the wallet's own Spark balance
// (bitcoin or dollars), whatever started it: a conversion on the Move
// sheet, a venue cash-out, a direct leg of a multi-source move, a Circle
// CCTP move adopted by its watcher, a standing deposit found in history.
// Every one of them is a swap order row reaching `success` with Spark as
// its destination, so the swap order store reports each transition here
// ([OwnSparkArrivals.rowsChanged]) and the wallet refreshes at once: the
// SDK's cached balance is polled, then synced if it has not risen, and
// the reading is published to the streams the balances follow
// (`BreezSdkSpark.syncAndRefresh`).
//
// Until that refresh has run, the row's money is not yet in the balance:
// [OwnSparkArrivals.awaitingCredit] keeps the Activity rows that stand for
// it (a multi-source move's one row among them) pending, so a row never
// says completed while the balance beside it does not show the money.

import 'dart:async';

import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/breez/sdk_instance.dart';
import 'package:kute/models/swap_order_model.dart';

abstract final class OwnSparkArrivals {
  /// Bumped whenever a row starts or stops awaiting its credit.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// A row first seen already delivered counts as an arrival only when it
  /// was created this recently (an order adopted under its real id, a
  /// standing deposit's order); older ones are history being loaded.
  static const Duration recentWindow = Duration(hours: 6);

  /// Refreshes the wallet for an arrival of [asset]. Test seam.
  static Future<void> Function(ArrivalAsset asset) refresh =
      (asset) => BreezSdkSpark().syncAndRefresh(asset: asset);

  /// Test seam: the clock [recentWindow] is measured with.
  static DateTime Function() clock = DateTime.now;

  static final Set<String> _awaiting = {};

  /// Whether row [rowId]'s delivery to Spark completed and the wallet has
  /// not refreshed for it yet.
  static bool awaitingCredit(String rowId) => _awaiting.contains(rowId);

  /// The swap order store changed from [before] to [after]: refresh the
  /// wallet for every delivery to Spark that just completed.
  static void rowsChanged(List<SwapOrder> before, List<SwapOrder> after) {
    for (final row in landedRows(before, after, now: clock())) {
      landed(row);
    }
  }

  /// Rows of [after] whose delivery to the wallet's own Spark balance
  /// completed since [before]: in `success` with Spark as the destination,
  /// and either pending in [before] or new and created within
  /// [recentWindow] of [now]. A row the delivery reconciler `settled` was
  /// matched to a receive the wallet already shows: not an arrival.
  @visibleForTesting
  static List<SwapOrder> landedRows(
    List<SwapOrder> before,
    List<SwapOrder> after, {
    required DateTime now,
  }) {
    final prior = {for (final r in before) r.id: r};
    return [
      for (final row in after)
        if (row.status == 'success' &&
            row.networkTo.toUpperCase() == 'SPARK' &&
            switch (prior[row.id]) {
              null => now
                      .difference(
                          DateTime.fromMillisecondsSinceEpoch(row.timestamp))
                      .abs() <
                  recentWindow,
              final SwapOrder was => !was.isComplete,
            })
          row,
    ];
  }

  /// Refreshes the wallet for [row]'s delivery; the row awaits its credit
  /// until that refresh has run. A second report while it runs is ignored.
  static void landed(SwapOrder row) {
    if (!_awaiting.add(row.id)) return;
    revision.value++;
    final asset = row.coinTo.toUpperCase() == 'BTC'
        ? ArrivalAsset.bitcoin
        : ArrivalAsset.dollars;
    Future<void> run;
    try {
      run = refresh(asset);
    } catch (_) {
      run = Future<void>.value();
    }
    unawaited(run.catchError((Object _) {}).whenComplete(() {
      if (_awaiting.remove(row.id)) revision.value++;
    }));
  }

  @visibleForTesting
  static void reset() {
    _awaiting.clear();
    refresh = (asset) => BreezSdkSpark().syncAndRefresh(asset: asset);
    clock = DateTime.now;
    revision.value++;
  }
}

/// Rebuilds whoever watches it when a row starts or stops awaiting its
/// credit ([OwnSparkArrivals.awaitingCredit]).
final ownSparkArrivalsProvider =
    NotifierProvider<OwnSparkArrivalsNotifier, int>(
        OwnSparkArrivalsNotifier.new);

class OwnSparkArrivalsNotifier extends Notifier<int> {
  @override
  int build() {
    void changed() => state = OwnSparkArrivals.revision.value;
    OwnSparkArrivals.revision.addListener(changed);
    ref.onDispose(() => OwnSparkArrivals.revision.removeListener(changed));
    return OwnSparkArrivals.revision.value;
  }
}
