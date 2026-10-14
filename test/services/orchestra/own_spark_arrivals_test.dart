// A delivery to the wallet's own Spark balance that completes, whoever
// wrote it (the status poller, the CCTP watcher adopting an order already
// done, a standing deposit found in history), refreshes the wallet at
// once for that asset, and its rows wait for that refresh before they say
// completed.

import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/breez/sdk_instance.dart'
    show ArrivalAsset, ArrivalRefresher, kArrivalPollWindow;
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/services/orchestra/own_spark_arrivals.dart';

final _now = DateTime.utc(2026, 10, 13, 17, 56);

SwapOrder _row(
  String id, {
  String status = 'exchanging',
  String from = 'USDC',
  String fromNet = 'POLYGON',
  String to = 'BTC',
  String toNet = 'SPARK',
  Duration age = const Duration(minutes: 1),
}) =>
    SwapOrder(
      id: id,
      coinFrom: from,
      networkFrom: fromNet,
      coinTo: to,
      networkTo: toNet,
      depositAddress: 'dep',
      depositAmount: '7.78',
      withdrawalAmount: '0.00009300',
      status: status,
      timestamp: _now.subtract(age).millisecondsSinceEpoch,
      withdrawalAddress: 'sp1self',
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: '',
      provider: 'Orchestra',
      walletId: 'w1',
    );

void main() {
  late List<ArrivalAsset> refreshes;
  late List<DateTime> sinces;
  late List<Completer<void>> runs;
  late int rereads;

  setUp(() {
    OwnSparkArrivals.reset();
    OwnSparkArrivals.clock = () => _now;
    rereads = 0;
    OwnSparkArrivals.reread = () async => rereads++;
    refreshes = [];
    sinces = [];
    runs = [];
    OwnSparkArrivals.refresh = (arrival) {
      refreshes.add(arrival.asset);
      sinces.add(arrival.since);
      final c = Completer<void>();
      runs.add(c);
      return c.future;
    };
  });
  tearDown(OwnSparkArrivals.reset);

  group('landedRows', () {
    List<String> landed(List<SwapOrder> before, List<SwapOrder> after) =>
        OwnSparkArrivals.landedRows(before, after, now: _now)
            .map((r) => r.id)
            .toList();

    test('a pending delivery to Spark that completes has landed', () {
      expect(landed([_row('ord_pm')], [_row('ord_pm', status: 'success')]),
          ['ord_pm']);
    });

    test('a recent row first seen already done has landed (CCTP adoption, '
        'quote id moved to its order)', () {
      expect(
          landed([_row('cctp-op1')], [_row('ord_hl', status: 'success')]),
          ['ord_hl']);
    });

    test('history, other destinations, failures and repeats have not', () {
      expect(
          landed([], [
            _row('ord_old',
                status: 'success', age: const Duration(days: 2)),
          ]),
          isEmpty,
          reason: 'loaded history is not an arrival');
      expect(
          landed([_row('ord_poly', toNet: 'POLYGON')],
              [_row('ord_poly', toNet: 'POLYGON', status: 'success')]),
          isEmpty,
          reason: 'a venue deposit lands elsewhere');
      expect(landed([_row('ord_r')], [_row('ord_r', status: 'refunded')]),
          isEmpty);
      expect(
          landed([_row('ord_d', status: 'success')],
              [_row('ord_d', status: 'success')]),
          isEmpty,
          reason: 'already reported');
      expect(landed([_row('ord_s')], [_row('ord_s', status: 'settled')]),
          isEmpty,
          reason: 'the receive it was matched to is already shown');
    });
  });

  group('landed', () {
    test('refreshes for the asset that arrived and awaits until it ran',
        () async {
      var revisions = 0;
      void bump() => revisions++;
      OwnSparkArrivals.revision.addListener(bump);
      addTearDown(() => OwnSparkArrivals.revision.removeListener(bump));

      OwnSparkArrivals.rowsChanged([
        _row('ord_btc'),
        _row('ord_usd', from: 'USDC', to: 'USDB'),
      ], [
        _row('ord_btc', status: 'success'),
        _row('ord_usd', from: 'USDC', to: 'USDB', status: 'success'),
      ]);
      expect(refreshes, [ArrivalAsset.bitcoin, ArrivalAsset.dollars]);
      // Measured from before the order's money moved: a balance the SDK
      // event already raised still counts as this arrival.
      final created =
          _now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch;
      expect(sinces.map((d) => d.millisecondsSinceEpoch), [created, created]);
      expect(OwnSparkArrivals.awaitingCredit('ord_btc'), isTrue);
      expect(OwnSparkArrivals.awaitingCredit('ord_usd'), isTrue);

      // A second report while the refresh runs starts no other.
      OwnSparkArrivals.landed(_row('ord_btc', status: 'success'));
      expect(refreshes, hasLength(2));

      runs.first.complete();
      await pumpEventQueue();
      expect(OwnSparkArrivals.awaitingCredit('ord_btc'), isFalse);
      expect(OwnSparkArrivals.awaitingCredit('ord_usd'), isTrue);
      runs.last.completeError(StateError('offline'));
      await pumpEventQueue();
      expect(OwnSparkArrivals.awaitingCredit('ord_usd'), isFalse,
          reason: 'a failed refresh never pins a row pending');
      expect(revisions, greaterThanOrEqualTo(4));
    });
  });

  group('the swap order store reports every writer', () {
    late Directory tmp;
    late Box<SwapOrder> box;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('own_spark_arrivals_test');
      Hive.init(tmp.path);
      if (!Hive.isAdapterRegistered(31)) {
        Hive.registerAdapter(SwapOrderAdapter());
      }
      box = await Hive.openBox<SwapOrder>(kSwapOrdersBoxName);
      await box.clear();
    });

    tearDown(() async {
      await Hive.close();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('loaded history is the baseline; a completion refreshes once',
        () async {
      final done = _row('ord_done',
          status: 'success', age: const Duration(minutes: 5));
      await box.put(done.id, done);
      final notifier = SwapOrdersNotifier();
      await pumpEventQueue();
      expect(refreshes, isEmpty, reason: 'rows already there are history');

      // A direct Predictions → Bitcoin leg, polled to completion.
      await notifier.addExchange(_row('ord_pm'));
      await notifier.updateExchange(_row('ord_pm', status: 'success'));
      await pumpEventQueue();
      expect(refreshes, [ArrivalAsset.bitcoin]);

      // The CCTP watcher puts its order row already done and drops the
      // placeholder.
      await notifier.addExchange(_row('cctp-op'));
      await box.put('ord_hl', _row('ord_hl', status: 'success'));
      await notifier.deleteExchange('cctp-op');
      await pumpEventQueue();
      expect(refreshes, [ArrivalAsset.bitcoin, ArrivalAsset.bitcoin]);
      for (final r in runs) {
        r.complete();
      }
      await pumpEventQueue();
    });
  });

  group('every Spark order that ends refreshes its balance', () {
    // A Rebalance's Predictions leg: USDC.e on Polygon home to Dollars.
    SwapOrder sweep(String id, {String status = 'exchanging'}) => _row(id,
        from: 'USDC', fromNet: 'POLYGON', to: 'USDB', status: status);

    test(
        'a Predictions → Dollars sweep reaching success refreshes Dollars '
        'once', () {
      OwnSparkArrivals.rowsChanged(
          [sweep('ord_sweep')], [sweep('ord_sweep', status: 'success')]);
      expect(refreshes, [ArrivalAsset.dollars]);
      expect(OwnSparkArrivals.awaitingCredit('ord_sweep'), isTrue);
      // The status poller writes the same row again: no second refresh.
      OwnSparkArrivals.rowsChanged([sweep('ord_sweep', status: 'success')],
          [sweep('ord_sweep', status: 'success')]);
      expect(refreshes, hasLength(1));
      expect(rereads, 0);
    });

    test('a CCTP standing-address arrival refreshes Dollars once', () {
      // The Investing leg: the CCTP watcher (or the standing sweep) puts
      // the standing address's order already done and drops its
      // placeholder.
      final placeholder = _row('cctp-op1',
          from: 'USDC',
          fromNet: 'HYPERCORE',
          to: 'USDB',
          age: const Duration(minutes: 18));
      final order = _row('ord_standing',
          from: 'USDC',
          fromNet: 'HYPERCORE',
          to: 'USDB',
          status: 'success',
          age: const Duration(minutes: 18));
      OwnSparkArrivals.rowsChanged([placeholder], [order]);
      expect(refreshes, [ArrivalAsset.dollars]);
      expect(sinces.single,
          DateTime.fromMillisecondsSinceEpoch(order.timestamp),
          reason: 'measured from before the CCTP move left Investing');
    });

    test(
        'legs ending in one change share one refresh per asset, from the '
        'oldest', () {
      final a = sweep('ord_a');
      final b = _row('ord_b',
          from: 'USDC',
          fromNet: 'HYPERCORE',
          to: 'USDB',
          age: const Duration(minutes: 3));
      final c = _row('ord_c', from: 'USDC', fromNet: 'POLYGON', to: 'BTC');
      OwnSparkArrivals.rowsChanged([a, b, c], [
        sweep('ord_a', status: 'success'),
        _row('ord_b',
            from: 'USDC',
            fromNet: 'HYPERCORE',
            to: 'USDB',
            status: 'success',
            age: const Duration(minutes: 3)),
        _row('ord_c',
            from: 'USDC', fromNet: 'POLYGON', to: 'BTC', status: 'success'),
      ]);
      expect(refreshes, [ArrivalAsset.dollars, ArrivalAsset.bitcoin],
          reason: 'bitcoin arrivals still refresh bitcoin');
      expect(sinces.first, DateTime.fromMillisecondsSinceEpoch(b.timestamp));
      for (final id in ['ord_a', 'ord_b', 'ord_c']) {
        expect(OwnSparkArrivals.awaitingCredit(id), isTrue);
      }
    });

    test('a burst of three legs landing one after the other costs one sync',
        () {
      fakeAsync((async) {
        var syncs = 0;
        final refresher = ArrivalRefresher(
          // Nothing shows yet: the worst case, every leg waits its window.
          readBalances: () async =>
              {'sats': BigInt.from(1000), 'usdb': BigInt.from(5000000)},
          sync: () async => syncs++,
          publish: () async {},
        );
        OwnSparkArrivals.refresh = (arrival) => refresher.request(
            asset: arrival.asset, baseline: {'usdb': BigInt.from(5000000)});
        var rows = [sweep('ord_1'), sweep('ord_2'), sweep('ord_3')];
        for (var i = 0; i < 3; i++) {
          final next = [...rows];
          next[i] = sweep('ord_${i + 1}', status: 'success');
          OwnSparkArrivals.rowsChanged(rows, next);
          rows = next;
          async.elapse(const Duration(milliseconds: 400));
        }
        async.elapse(kArrivalPollWindow * 2);
        expect(syncs, 1);
        expect(refresher.waiting, 0);
        for (final id in ['ord_1', 'ord_2', 'ord_3']) {
          expect(OwnSparkArrivals.awaitingCredit(id), isFalse);
        }
        refresher.cancelAll();
      });
    });

    test('a refund back to Spark is an arrival of what was paid', () {
      // Dollars → Predictions, refunded to the wallet's own Spark address.
      final out = _row('ord_out',
          from: 'USDB', fromNet: 'SPARK', to: 'USDC', toNet: 'POLYGON');
      OwnSparkArrivals.rowsChanged([out], [
        _row('ord_out',
            from: 'USDB',
            fromNet: 'SPARK',
            to: 'USDC',
            toNet: 'POLYGON',
            status: 'refunded'),
      ]);
      expect(refreshes, [ArrivalAsset.dollars]);
      expect(rereads, 0);
    });

    test('a Spark-paid order that ends, or a settled delivery, re-reads once',
        () {
      fakeAsync((async) {
        SwapOrder paid(String id, String status) => _row(id,
            from: 'BTC',
            fromNet: 'SPARK',
            to: 'USDC',
            toNet: 'POLYGON',
            status: status);
        OwnSparkArrivals.rowsChanged(
            [paid('ord_x', 'exchanging')], [paid('ord_x', 'expired')]);
        OwnSparkArrivals.rowsChanged(
            [paid('ord_y', 'exchanging')], [paid('ord_y', 'success')]);
        OwnSparkArrivals.rowsChanged(
            [sweep('ord_s')], [sweep('ord_s', status: 'settled')]);
        expect(rereads, 0);
        async.elapse(OwnSparkArrivals.rereadDelay);
        expect(rereads, 1, reason: 'one re-read for the three');
        expect(refreshes, isEmpty, reason: 'nothing to poll or sync for');

        // A delivery to Spark that failed returns its money to the
        // source chain: no Spark balance moves.
        OwnSparkArrivals.rowsChanged(
            [sweep('ord_f')], [sweep('ord_f', status: 'expired')]);
        async.elapse(const Duration(seconds: 1));
        expect(rereads, 1);
        expect(refreshes, isEmpty);
      });
    });
  });
}
