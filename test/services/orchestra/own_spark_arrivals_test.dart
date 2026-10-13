// A delivery to the wallet's own Spark balance that completes, whoever
// wrote it (the status poller, the CCTP watcher adopting an order already
// done, a standing deposit found in history), refreshes the wallet at
// once for that asset, and its rows wait for that refresh before they say
// completed.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/breez/sdk_instance.dart' show ArrivalAsset;
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
  late List<Completer<void>> runs;

  setUp(() {
    OwnSparkArrivals.reset();
    OwnSparkArrivals.clock = () => _now;
    refreshes = [];
    runs = [];
    OwnSparkArrivals.refresh = (asset) {
      refreshes.add(asset);
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
}
