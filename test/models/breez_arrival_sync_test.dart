import 'dart:async';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/breez/sdk_instance.dart';
import 'package:kute/models/breez/shared_sync.dart';
import 'package:mocktail/mocktail.dart';

class _Sdk extends Mock implements BreezSdk {}

void main() {
  group('syncUntilBalanceRises', () {
    late List<Duration> sleeps;
    late int syncs;
    late int reads;

    setUp(() {
      sleeps = [];
      syncs = 0;
      reads = 0;
    });

    Future<bool> run(List<Map<String, BigInt>> readings,
        {bool firstReadFails = false}) {
      return syncUntilBalanceRises(
        readBalances: () async {
          final i = reads++;
          if (firstReadFails && i == 0) throw Exception('offline');
          return readings[i < readings.length ? i : readings.length - 1];
        },
        sync: () async => syncs++,
        sleep: (d) async => sleeps.add(d),
      );
    }

    test('an arrival the cache already shows needs no sync', () async {
      final rose = await run([
        {'sats': BigInt.from(1000), 'usdb': BigInt.from(5000000)},
        {'sats': BigInt.from(1000), 'usdb': BigInt.from(11000000)},
      ]);
      expect(rose, isTrue);
      expect(syncs, 0);
      expect(sleeps, [kArrivalPollInterval]);
    });

    test('polls every 300 ms and stops at the reading that shows it',
        () async {
      final rose = await run([
        {'sats': BigInt.from(1000)},
        {'sats': BigInt.from(1000)},
        {'sats': BigInt.from(1000)},
        // A first dollar balance counts as a rise.
        {'sats': BigInt.from(1000), 'usdb': BigInt.from(6000000)},
      ]);
      expect(rose, isTrue);
      expect(syncs, 0);
      expect(sleeps, List.filled(3, const Duration(milliseconds: 300)));
    });

    test('syncs once after about 3 s of polling, then reads again', () async {
      final polls =
          kArrivalPollWindow.inMilliseconds ~/ kArrivalPollInterval.inMilliseconds;
      final rose = await run([
        for (var i = 0; i <= polls; i++) {'sats': BigInt.from(1000)},
        {'sats': BigInt.from(1500)},
      ]);
      expect(rose, isTrue);
      expect(syncs, 1);
      expect(sleeps, List.filled(polls, kArrivalPollInterval));
      // Baseline, each poll, and the read after the sync.
      expect(reads, polls + 2);
    });

    test('nothing rose: one sync, no retries', () async {
      final rose = await run([
        {'sats': BigInt.from(1000)},
      ]);
      expect(rose, isFalse);
      expect(syncs, 1);
    });

    test('a spend elsewhere is not an arrival', () async {
      final rose = await run([
        {'sats': BigInt.from(1000), 'usdb': BigInt.from(6000000)},
        {'sats': BigInt.from(900), 'usdb': BigInt.from(6000000)},
      ]);
      expect(rose, isFalse);
      expect(syncs, 1);
    });

    test('a bitcoin arrival does not end on dollars that rose meanwhile',
        () async {
      final polls =
          kArrivalPollWindow.inMilliseconds ~/ kArrivalPollInterval.inMilliseconds;
      final readings = [
        {'sats': BigInt.from(0), 'usdb': BigInt.from(5000000)},
        // A sweep's dollars land first: not this arrival.
        for (var i = 0; i < polls; i++)
          {'sats': BigInt.from(0), 'usdb': BigInt.from(9000000)},
        // The sync brings the bitcoin in.
        {'sats': BigInt.from(9300), 'usdb': BigInt.from(9000000)},
      ];
      final rose = await syncUntilBalanceRises(
        asset: ArrivalAsset.bitcoin,
        readBalances: () async =>
            readings[reads < readings.length ? reads++ : readings.length - 1],
        sync: () async => syncs++,
        sleep: (d) async => sleeps.add(d),
      );
      expect(rose, isTrue);
      expect(syncs, 1, reason: 'the dollar rise never stopped the wait');
      expect(sleeps, hasLength(polls));
    });

    test('a dollar arrival counts any token, never sats', () {
      expect(ArrivalAsset.dollars.counts('sats'), isFalse);
      expect(ArrivalAsset.dollars.counts('btkn1usdb'), isTrue);
      expect(ArrivalAsset.bitcoin.counts('btkn1usdb'), isFalse);
      expect(ArrivalAsset.any.counts('sats'), isTrue);
      expect(ArrivalAsset.bitcoin.merge(ArrivalAsset.dollars),
          ArrivalAsset.any);
      expect(ArrivalAsset.bitcoin.merge(ArrivalAsset.bitcoin),
          ArrivalAsset.bitcoin);
    });

    test('no baseline: one sync, nothing to compare', () async {
      final rose = await run([
        {'sats': BigInt.from(1000)},
      ], firstReadFails: true);
      expect(rose, isFalse);
      expect(syncs, 1);
      expect(sleeps, isEmpty);
    });
  });

  group('ArrivalRefreshQueue', () {
    test('an arrival reported mid-run gets a run of its own after it',
        () async {
      final started = <ArrivalAsset>[];
      final gates = <Completer<void>>[];
      final queue = ArrivalRefreshQueue((asset) {
        started.add(asset);
        final c = Completer<void>();
        gates.add(c);
        return c.future;
      });
      var firstDone = false;
      var secondDone = false;
      unawaited(queue
          .request(ArrivalAsset.dollars)
          .then((_) => firstDone = true));
      // The bitcoin lands while the dollar refresh runs: it must not
      // share that run (its baseline predates the bitcoin).
      unawaited(queue
          .request(ArrivalAsset.bitcoin)
          .then((_) => secondDone = true));
      unawaited(queue.request(ArrivalAsset.bitcoin));
      expect(started, [ArrivalAsset.dollars]);

      gates[0].complete();
      await pumpEventQueue();
      expect(started, [ArrivalAsset.dollars, ArrivalAsset.bitcoin],
          reason: 'one more run for every request made meanwhile');
      expect(secondDone, isFalse, reason: 'its own run has not finished');

      gates[1].completeError(StateError('sync failed'));
      await pumpEventQueue();
      expect(firstDone && secondDone, isTrue);
      expect(started, hasLength(2));

      // Idle again: the next request runs at once.
      unawaited(queue.request(ArrivalAsset.bitcoin));
      expect(started, hasLength(3));
      gates[2].complete();
      await pumpEventQueue();
    });

    test('requests for different assets mid-run merge into one run for any',
        () async {
      final started = <ArrivalAsset>[];
      final gates = <Completer<void>>[];
      final queue = ArrivalRefreshQueue((asset) {
        started.add(asset);
        final c = Completer<void>();
        gates.add(c);
        return c.future;
      });
      unawaited(queue.request(ArrivalAsset.bitcoin));
      unawaited(queue.request(ArrivalAsset.bitcoin));
      unawaited(queue.request(ArrivalAsset.dollars));
      gates[0].complete();
      await pumpEventQueue();
      expect(started, [ArrivalAsset.bitcoin, ArrivalAsset.any]);
      gates[1].complete();
      await pumpEventQueue();
    });
  });

  group('sharedSyncWallet', () {
    late _Sdk sdk;
    late List<Completer<SyncWalletResponse>> calls;

    setUpAll(() => registerFallbackValue(const SyncWalletRequest()));

    setUp(() {
      sdk = _Sdk();
      calls = [];
      when(() => sdk.syncWallet(request: any(named: 'request')))
          .thenAnswer((_) {
        final c = Completer<SyncWalletResponse>();
        calls.add(c);
        return c.future;
      });
    });

    test('concurrent callers share the one SDK call', () async {
      final a = sharedSyncWallet(sdk);
      final b = sharedSyncWallet(sdk);
      kickSharedSyncWallet(sdk);
      expect(identical(a, b), isTrue);
      expect(calls, hasLength(1));
      calls.single.complete(const SyncWalletResponse());
      await a;
      expect(sharedSyncInFlight(sdk), isFalse);
    });

    test('a caller timeout does not free the slot; the SDK answer does',
        () async {
      await expectLater(
          sharedSyncWallet(sdk).timeout(const Duration(milliseconds: 1)),
          throwsA(isA<TimeoutException>()));
      // The native call is still running: no second one starts.
      unawaited(sharedSyncWallet(sdk).catchError((Object _) {}));
      expect(calls, hasLength(1));
      expect(sharedSyncInFlight(sdk), isTrue);

      calls.single.complete(const SyncWalletResponse());
      await Future<void>.delayed(Duration.zero);
      expect(sharedSyncInFlight(sdk), isFalse);
      final next = sharedSyncWallet(sdk);
      expect(calls, hasLength(2));
      calls.last.complete(const SyncWalletResponse());
      await next;
    });

    test('the caller that awaited it can start the next one at once',
        () async {
      final first = sharedSyncWallet(sdk);
      calls.single.complete(const SyncWalletResponse());
      await first;
      final second = sharedSyncWallet(sdk);
      expect(identical(first, second), isFalse);
      expect(calls, hasLength(2));
      calls.last.complete(const SyncWalletResponse());
      await second;
    });

    test('a failure reaches awaiting callers and frees the slot', () async {
      final run = sharedSyncWallet(sdk);
      kickSharedSyncWallet(sdk);
      calls.single.completeError(Exception('operator down'));
      await expectLater(run, throwsA(isA<Exception>()));
      expect(sharedSyncInFlight(sdk), isFalse);
    });

    test('a failure nobody awaits is not unhandled', () async {
      kickSharedSyncWallet(sdk);
      calls.single.completeError(Exception('operator down'));
      await Future<void>.delayed(Duration.zero);
      expect(sharedSyncInFlight(sdk), isFalse);
    });

    test('each SDK handle has its own slot', () async {
      final other = _Sdk();
      when(() => other.syncWallet(request: any(named: 'request')))
          .thenAnswer((_) async => const SyncWalletResponse());
      final a = sharedSyncWallet(sdk);
      await sharedSyncWallet(other);
      expect(calls, hasLength(1));
      calls.single.complete(const SyncWalletResponse());
      await a;
    });
  });

  test('isSdkSyncLogLine picks the SDK sync step lines', () {
    expect(
        isSdkSyncLogLine(
            'sync_wallet_internal: Wallet sync completed in 1.2s'),
        isTrue);
    expect(isSdkSyncLogLine('Failed to query operator 3: Unavailable'), isTrue);
    expect(isSdkSyncLogLine('Received Synced event.'), isFalse);
  });
}
