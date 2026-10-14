// lib/services/orchestra/own_spark_arrivals.dart
//
// The one place the wallet's own Spark balances (bitcoin and Dollars)
// refresh when an Orchestra order touching them ends, whatever started
// it: a conversion on the Move sheet, a venue cash-out, a sweep or the
// Portfolio's Rebalance, a direct leg of a multi-source move, a Circle
// CCTP move adopted by its watcher, a standing deposit found in history, a
// purchase, a receive. Every one of them is a swap order row, and the
// swap order store reports every change of its rows here
// ([OwnSparkArrivals.rowsChanged]), whoever wrote it:
//
//  * money delivered to Spark (`success`, Spark the destination) and
//    money returned to Spark (`refunded`, Spark the source) are
//    arrivals: the wallet refreshes at once for that asset, measured
//    from the balance before the order's money moved: money the SDK's
//    own payment event already counted ends the refresh on its first
//    reading; otherwise the SDK's cached balance is polled, then synced
//    if it has not risen, read late a few times if it still has not, and
//    every reading that shows it is published to the streams the balances
//    follow (`BreezSdkSpark.syncAndRefresh`);
//  * an order paid from Spark that ended (done or failed), and a delivery
//    the reconciler matched to a receive the wallet already shows
//    (`settled`), re-read the wallet once, no poll, no sync
//    (`BreezSdkSpark.rereadWalletData`): the SDK's cache already has it.
//
// The legs of one change (several rows ending together) share one refresh
// per asset, measured from the oldest of them; refreshes that follow one
// another share the SDK sync (ArrivalRefresher), and re-reads within
// [OwnSparkArrivals.rereadDelay] share one. Plain Spark receives and the
// wallet's own sends refresh on the SDK's payment events; nothing here
// polls on its own.
//
// Until an arrival's refresh has run, the row's money is not yet in the
// balance: [OwnSparkArrivals.awaitingCredit] keeps the Activity rows that
// stand for it (a multi-source move's one row among them) pending, so a
// row never says completed while the balance beside it does not show the
// money.

import 'dart:async';

import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/breez/sdk_instance.dart';
import 'package:kute/models/swap_order_model.dart';

/// One delivery to refresh for: the balance it lands in and when its
/// money could first have moved (the order's creation).
typedef OwnSparkArrival = ({ArrivalAsset asset, DateTime since});

abstract final class OwnSparkArrivals {
  /// Bumped whenever a row starts or stops awaiting its credit.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// A row first seen already ended counts only when it was created this
  /// recently (an order adopted under its real id, a standing deposit's
  /// order); older ones are history being loaded.
  static const Duration recentWindow = Duration(hours: 6);

  /// Statuses an order that did not deliver ends in.
  static const Set<String> failedStatuses = {
    'expired',
    'refunded',
    'canceled',
    'cancelled',
    'failed',
  };

  /// Refreshes the wallet for [arrival]. Test seam.
  static Future<void> Function(OwnSparkArrival arrival) refresh =
      _refreshWallet;

  static Future<void> _refreshWallet(OwnSparkArrival arrival) => BreezSdkSpark()
      .syncAndRefresh(asset: arrival.asset, since: arrival.since);

  /// Re-reads the wallet once, no poll, no sync. Test seam.
  static Future<void> Function() reread = _rereadWallet;

  static Future<void> _rereadWallet() => BreezSdkSpark().rereadWalletData();

  /// Re-reads asked for within this share one.
  static Duration rereadDelay = const Duration(milliseconds: 300);

  /// Test seam: the clock [recentWindow] is measured with.
  static DateTime Function() clock = DateTime.now;

  static final Set<String> _awaiting = {};
  static Timer? _rereadTimer;

  /// Whether row [rowId]'s delivery to Spark completed and the wallet has
  /// not refreshed for it yet.
  static bool awaitingCredit(String rowId) => _awaiting.contains(rowId);

  static bool _onSpark(String network) => network.toUpperCase() == 'SPARK';

  static ArrivalAsset _assetOf(String coin) =>
      coin.toUpperCase() == 'BTC' ? ArrivalAsset.bitcoin : ArrivalAsset.dollars;

  static bool _ended(SwapOrder row) =>
      row.isComplete || failedStatuses.contains(row.status);

  /// Whether [row]'s end changes a Spark balance: it delivered to Spark,
  /// or it was paid from Spark (done, failed or refunded).
  static bool _touchesSpark(SwapOrder row) =>
      (row.isComplete && _onSpark(row.networkTo)) || _onSpark(row.networkFrom);

  /// The Spark balance money arrives in when [row] ends as it did: what it
  /// delivered to Spark, or what a refund returned to Spark. Null when
  /// nothing arrives (a spend, a failure, a settled delivery the balance
  /// already shows).
  @visibleForTesting
  static ArrivalAsset? arrivalAssetOf(SwapOrder row) {
    if (row.status == 'success' && _onSpark(row.networkTo)) {
      return _assetOf(row.coinTo);
    }
    if (row.status == 'refunded' && _onSpark(row.networkFrom)) {
      return _assetOf(row.coinFrom);
    }
    return null;
  }

  /// Rows of [after] that touch a Spark balance ([_touchesSpark]) and
  /// ended since [before]: ended now and either not ended in [before], or
  /// new and created within [recentWindow] of [now].
  @visibleForTesting
  static List<SwapOrder> endedRows(
    List<SwapOrder> before,
    List<SwapOrder> after, {
    required DateTime now,
  }) {
    final prior = {for (final r in before) r.id: r};
    return [
      for (final row in after)
        if (_ended(row) &&
            _touchesSpark(row) &&
            switch (prior[row.id]) {
              null => now
                      .difference(
                          DateTime.fromMillisecondsSinceEpoch(row.timestamp))
                      .abs() <
                  recentWindow,
              final SwapOrder was => !_ended(was),
            })
          row,
    ];
  }

  /// Rows of [after] whose money just arrived in a Spark balance
  /// ([arrivalAssetOf]): delivered to Spark, or refunded to it.
  @visibleForTesting
  static List<SwapOrder> landedRows(
    List<SwapOrder> before,
    List<SwapOrder> after, {
    required DateTime now,
  }) =>
      [
        for (final row in endedRows(before, after, now: now))
          if (arrivalAssetOf(row) != null) row,
      ];

  /// The swap order store changed from [before] to [after]: one refresh
  /// per asset for the money that just arrived on Spark (the oldest row's
  /// creation is the baseline), else one re-read for the Spark orders that
  /// just ended.
  static void rowsChanged(List<SwapOrder> before, List<SwapOrder> after) {
    final ended = endedRows(before, after, now: clock());
    if (ended.isEmpty) return;
    final arrivals = <ArrivalAsset, List<SwapOrder>>{};
    for (final row in ended) {
      final asset = arrivalAssetOf(row);
      if (asset != null) (arrivals[asset] ??= []).add(row);
    }
    if (arrivals.isEmpty) {
      // An arrival's refresh publishes every balance anyway.
      _scheduleReread();
      return;
    }
    for (final MapEntry(key: asset, value: rows) in arrivals.entries) {
      _land(asset, rows);
    }
  }

  /// Refreshes the wallet for [row]'s delivery; the row awaits its credit
  /// until that refresh has run. A second report while it runs is ignored.
  static void landed(SwapOrder row) =>
      _land(arrivalAssetOf(row) ?? _assetOf(row.coinTo), [row]);

  static void _land(ArrivalAsset asset, List<SwapOrder> rows) {
    final fresh = [
      for (final row in rows)
        if (_awaiting.add(row.id)) row,
    ];
    if (fresh.isEmpty) return;
    revision.value++;
    final since = fresh.map((r) => r.timestamp).reduce((a, b) => a < b ? a : b);
    Future<void> run;
    try {
      run = refresh((
        asset: asset,
        since: DateTime.fromMillisecondsSinceEpoch(since),
      ));
    } catch (_) {
      run = Future<void>.value();
    }
    unawaited(run.catchError((Object _) {}).whenComplete(() {
      var changed = false;
      for (final row in fresh) {
        changed = _awaiting.remove(row.id) || changed;
      }
      if (changed) revision.value++;
    }));
  }

  static void _scheduleReread() {
    if (_rereadTimer != null) return;
    // No wallet connected: nothing to read (and no timer left behind).
    if (identical(reread, _rereadWallet) && BreezSdkSpark().instance == null) {
      return;
    }
    _rereadTimer = Timer(rereadDelay, () {
      _rereadTimer = null;
      try {
        unawaited(reread().catchError((Object _) {}));
      } catch (_) {}
    });
  }

  @visibleForTesting
  static void reset() {
    _awaiting.clear();
    _rereadTimer?.cancel();
    _rereadTimer = null;
    refresh = _refreshWallet;
    reread = _rereadWallet;
    rereadDelay = const Duration(milliseconds: 300);
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
