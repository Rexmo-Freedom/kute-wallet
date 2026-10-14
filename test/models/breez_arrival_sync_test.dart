import 'dart:async';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/breez/sdk_instance.dart';
import 'package:kute/models/breez/shared_sync.dart';
import 'package:mocktail/mocktail.dart';

class _Sdk extends Mock implements BreezSdk {}

class _Request extends Fake implements ConnectRequest {}

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

  group('a stale baseline', () {
    // The SDK's own payment event already put the dollars in the cache
    // before Orchestra reported the order done, so a reading taken when
    // the refresh starts includes them.
    final counted = {'sats': BigInt.from(1000), 'usdb': BigInt.from(11000000)};
    final before = {'sats': BigInt.from(1000), 'usdb': BigInt.from(5000000)};

    test('ends on the first reading: no 3 s wait, no sync', () {
      fakeAsync((async) {
        var reads = 0;
        var syncs = 0;
        bool? rose;
        syncUntilBalanceRises(
          asset: ArrivalAsset.dollars,
          baseline: before,
          readBalances: () async {
            reads++;
            return counted;
          },
          sync: () async => syncs++,
        ).then((r) => rose = r);
        async.flushMicrotasks();
        expect(rose, isTrue);
        expect(async.elapsed, Duration.zero);
        expect(reads, 1);
        expect(syncs, 0);
      });
    });

    test(
        'without the pre-send baseline the same arrival waited 3 s and '
        'synced', () {
      fakeAsync((async) {
        var syncs = 0;
        bool? rose;
        syncUntilBalanceRises(
          asset: ArrivalAsset.dollars,
          readBalances: () async => counted,
          sync: () async => syncs++,
        ).then((r) => rose = r);
        async.elapse(kArrivalPollWindow - const Duration(milliseconds: 1));
        expect(rose, isNull);
        async.elapse(const Duration(milliseconds: 1));
        expect(rose, isFalse);
        expect(syncs, 1);
      });
    });
  });

  group('ArrivalBalanceLog', () {
    final t0 = DateTime.utc(2026, 10, 14, 12);
    Map<String, BigInt> b(int sats, [int? usdb]) => {
          'sats': BigInt.from(sats),
          if (usdb != null) 'usdb': BigInt.from(usdb),
        };

    test('the baseline is the lowest balance in effect since then', () {
      final log = ArrivalBalanceLog();
      expect(log.baselineSince(t0), isNull, reason: 'nothing read yet');
      log.record(b(1000, 5), t0);
      // The order is placed at +10 s; a spend at +20 s, the arrival at
      // +30 s (the SDK's payment event), the refresh at +35 s.
      log.record(b(1000, 5), t0.add(const Duration(seconds: 15)));
      log.record(b(900, 5), t0.add(const Duration(seconds: 20)));
      log.record(b(900, 11), t0.add(const Duration(seconds: 30)));
      expect(
          log.baselineSince(t0.add(const Duration(seconds: 10))), b(900, 5));
      expect(
          log.baselineSince(t0.add(const Duration(seconds: 31))), b(900, 11),
          reason: 'nothing before the order counts');
      expect(log.baselineSince(t0.subtract(const Duration(hours: 1))),
          b(900, 5),
          reason: 'from before the log began: its first reading on');
    });

    test('a token first held after the order starts from zero', () {
      final log = ArrivalBalanceLog()
        ..record(b(1000), t0)
        ..record(b(1000, 6), t0.add(const Duration(seconds: 5)));
      expect(
          log.baselineSince(t0.add(const Duration(seconds: 1))), b(1000, 0));
    });

    test('keeps the reading in effect at the cutoff, drops older ones', () {
      final log = ArrivalBalanceLog(keep: const Duration(minutes: 1));
      log.record(b(1), t0);
      log.record(b(2), t0.add(const Duration(seconds: 10)));
      log.record(b(3), t0.add(const Duration(minutes: 2)));
      expect(log.baselineSince(t0.add(const Duration(minutes: 1))), b(2));
      expect(log.baselineSince(t0), b(2), reason: 'b(1) was dropped');
    });
  });

  group('ArrivalRefresher', () {
    late Map<String, BigInt> balances;
    late int reads;
    late int syncs;
    late int publishes;
    Completer<void>? syncGate;
    late ArrivalRefresher refresher;

    setUp(() {
      balances = {'sats': BigInt.from(1000), 'usdb': BigInt.from(5000000)};
      reads = 0;
      syncs = 0;
      publishes = 0;
      syncGate = null;
      refresher = ArrivalRefresher(
        readBalances: () async {
          reads++;
          return Map.of(balances);
        },
        sync: () async {
          syncs++;
          await syncGate?.future;
        },
        publish: () async => publishes++,
      );
    });

    test('an arrival reported mid-run joins it and ends on its own rise',
        () {
      fakeAsync((async) {
        bool? bitcoin;
        bool? dollars;
        refresher
            .request(asset: ArrivalAsset.bitcoin)
            .then((r) => bitcoin = r);
        async.elapse(const Duration(milliseconds: 650));
        final readsBefore = reads;
        refresher
            .request(
                asset: ArrivalAsset.dollars,
                baseline: {'usdb': BigInt.from(5000000)})
            .then((r) => dollars = r);
        async.flushMicrotasks();
        expect(reads, readsBefore + 1, reason: 'one reading for it at once');
        expect(dollars, isNull, reason: 'its dollars are not there yet');

        balances['usdb'] = BigInt.from(9000000);
        async.elapse(kArrivalPollInterval);
        expect(dollars, isTrue,
            reason: 'within one poll, not after the bitcoin run');
        expect(bitcoin, isNull, reason: 'the dollars are not its arrival');
        expect(publishes, 1);

        balances['sats'] = BigInt.from(9300);
        async.elapse(kArrivalPollInterval);
        expect(bitcoin, isTrue);
        expect(syncs, 0);
        expect(publishes, 2);
        expect(refresher.waiting, 0);
        // Idle: no more reads.
        final idle = reads;
        async.elapse(const Duration(seconds: 5));
        expect(reads, idle);
      });
    });

    test('requests share each reading: one read per tick, not per request',
        () {
      fakeAsync((async) {
        for (var i = 0; i < 3; i++) {
          refresher.request(asset: ArrivalAsset.bitcoin);
        }
        async.flushMicrotasks();
        expect(reads, 1);
        async.elapse(kArrivalPollInterval * 3);
        expect(reads, 4);
        expect(refresher.waiting, 3);
        async.elapse(kArrivalPollWindow);
        expect(syncs, 1, reason: 'requests due together share one sync');
        expect(refresher.waiting, 0);
      });
    });

    test('an arrival already counted ends at once while the poll syncs', () {
      fakeAsync((async) {
        syncGate = Completer<void>();
        bool? first;
        bool? second;
        refresher.request(asset: ArrivalAsset.bitcoin).then((r) => first = r);
        async.elapse(kArrivalPollWindow);
        expect(syncs, 1, reason: 'the bitcoin run is syncing');

        // Dollars the SDK event already counted.
        balances['usdb'] = BigInt.from(8000000);
        refresher
            .request(
                asset: ArrivalAsset.dollars,
                baseline: {'usdb': BigInt.from(5000000)})
            .then((r) => second = r);
        async.flushMicrotasks();
        expect(second, isTrue, reason: 'it does not wait for the sync');
        expect(first, isNull);

        syncGate!.complete();
        async.flushMicrotasks();
        expect(first, isFalse);
      });
    });

    test(
        'each request polls its own window from when it joined; a sync that '
        'started after it joined is its sync too', () {
      fakeAsync((async) {
        bool? second;
        refresher.request(asset: ArrivalAsset.bitcoin);
        async.elapse(const Duration(milliseconds: 1500));
        refresher
            .request(asset: ArrivalAsset.bitcoin)
            .then((r) => second = r);
        async.elapse(const Duration(milliseconds: 1500));
        expect(syncs, 1, reason: 'the first one is due');
        expect(second, isNull);
        // Its window is counted in the poll's ticks after it joined (the
        // tick under way when it joined is not one of them).
        async.elapse(const Duration(milliseconds: 1500));
        expect(syncs, 1);
        expect(second, isNull);
        async.elapse(kArrivalPollInterval);
        expect(second, isFalse);
        expect(syncs, 1,
            reason: 'the sync it saw already read what the operators hold');
      });
    });

    test('a request that joins while the sync runs gets a sync of its own',
        () {
      fakeAsync((async) {
        syncGate = Completer<void>();
        bool? second;
        refresher.request(asset: ArrivalAsset.bitcoin);
        async.elapse(kArrivalPollWindow);
        expect(syncs, 1);
        refresher
            .request(asset: ArrivalAsset.bitcoin)
            .then((r) => second = r);
        async.flushMicrotasks();
        syncGate!.complete();
        syncGate = null;
        async.elapse(kArrivalPollWindow + kArrivalPollInterval * 2);
        expect(second, isFalse);
        expect(syncs, 2);
      });
    });

    test(
        'an arrival the sync did not show is read late, without a sync, and '
        'published the moment it shows', () {
      fakeAsync((async) {
        bool? rose;
        refresher
            .request(
                asset: ArrivalAsset.dollars,
                baseline: {'usdb': BigInt.from(5000000)})
            .then((r) => rose = r);
        async.elapse(kArrivalPollWindow + kArrivalPollInterval);
        expect(rose, isFalse, reason: 'the request itself ends as before');
        expect(syncs, 1);
        expect(publishes, 1);
        expect(refresher.lateWaiting, 1);

        // The SDK writes the transfer into its cache after the sync, and
        // raises no event for it.
        balances['usdb'] = BigInt.from(17400000);
        async.elapse(kArrivalLateCheckInterval);
        expect(publishes, 2, reason: 'the late reading reached the UI');
        expect(refresher.lateWaiting, 0);
        expect(syncs, 1, reason: 'late reads never sync');
        final idle = reads;
        async.elapse(const Duration(minutes: 1));
        expect(reads, idle);
      });
    });

    test('late reads stop after half a minute', () {
      fakeAsync((async) {
        refresher.request(
            asset: ArrivalAsset.dollars,
            baseline: {'usdb': BigInt.from(5000000)});
        async.elapse(kArrivalPollWindow + kArrivalPollInterval);
        final before = reads;
        async.elapse(kArrivalLateCheckInterval * kArrivalLateChecks);
        expect(reads, before + kArrivalLateChecks);
        expect(refresher.lateWaiting, 0);
        async.elapse(const Duration(minutes: 1));
        expect(reads, before + kArrivalLateChecks);
        expect(publishes, 1);
        expect(syncs, 1);
      });
    });

    test('cancelAll ends every request with false', () {
      fakeAsync((async) {
        bool? r;
        refresher.request().then((v) => r = v);
        async.elapse(kArrivalPollInterval);
        refresher.cancelAll();
        async.flushMicrotasks();
        expect(r, isFalse);
        final after = reads;
        async.elapse(const Duration(seconds: 5));
        expect(reads, after, reason: 'the poll stopped');
      });
    });
  });

  group('SyncedReread', () {
    test('reads at once, then once more after the burst', () {
      fakeAsync((async) {
        var reads = 0;
        final reread = SyncedReread(() => reads++);
        reread.onSynced();
        expect(reads, 1, reason: 'no 1.2 s debounce before the first read');
        async.elapse(const Duration(milliseconds: 100));
        reread.onSynced();
        reread.onSynced();
        expect(reads, 1);
        async.elapse(kSyncedRereadSettle - const Duration(milliseconds: 1));
        expect(reads, 1);
        async.elapse(const Duration(milliseconds: 1));
        expect(reads, 2, reason: 'two reads for a burst of three');
        reread.onSynced();
        expect(reads, 3, reason: 'a later sync reads at once again');
        reread.dispose();
        async.elapse(const Duration(seconds: 1));
        expect(reads, 3);
      });
    });
  });

  group('BreezSdkSpark.syncAndRefresh', () {
    setUpAll(() {
      registerFallbackValue(const GetInfoRequest());
      registerFallbackValue(const SyncWalletRequest());
      registerFallbackValue(const ListPaymentsRequest());
    });

    test(
        'dollars the SDK payment event already counted end the refresh at '
        'once: no poll, no sync', () {
      fakeAsync((async) {
        final sdk = _Sdk();
        final events = StreamController<SdkEvent>.broadcast();
        addTearDown(events.close);
        var usdb = 5000000;
        var syncs = 0;
        final meta = TokenMetadata(
          identifier: 'btkn1usdb',
          issuerPublicKey: 'issuer',
          name: 'USDB',
          ticker: 'USDB',
          decimals: 6,
          maxSupply: BigInt.zero,
          isFreezable: false,
        );
        when(() => sdk.addEventListener()).thenAnswer((_) => events.stream);
        when(() => sdk.disconnect()).thenAnswer((_) async {});
        when(() => sdk.getInfo(request: any(named: 'request')))
            .thenAnswer((_) async => GetInfoResponse(
                  identityPubkey: 'id',
                  balanceSats: BigInt.from(1000),
                  tokenBalances: {
                    'btkn1usdb': TokenBalance(
                        balance: BigInt.from(usdb), tokenMetadata: meta),
                  },
                ));
        when(() => sdk.listPayments(request: any(named: 'request')))
            .thenAnswer((_) async => const ListPaymentsResponse(payments: []));
        when(() => sdk.syncWallet(request: any(named: 'request')))
            .thenAnswer((_) async {
          syncs++;
          return const SyncWalletResponse();
        });
        final wrapper =
            BreezSdkSpark.forTesting(connectSdk: (_) async => sdk);

        // The order is placed, then the wallet connects and reads $5.
        final orderPlaced =
            DateTime.now().subtract(const Duration(seconds: 1));
        wrapper.connect(req: _Request());
        async.flushMicrotasks();

        // The operators deliver $6: the SDK raises the payment and the
        // app publishes the new balance before Orchestra says done.
        usdb = 11000000;
        events.add(SdkEvent.paymentSucceeded(
          payment: Payment(
            id: 'rx',
            paymentType: PaymentType.receive,
            status: PaymentStatus.completed,
            amount: BigInt.from(6000000),
            fees: BigInt.zero,
            timestamp: BigInt.from(
                DateTime.now().millisecondsSinceEpoch ~/ 1000),
            method: PaymentMethod.token,
          ),
        ));
        async.flushMicrotasks();

        var done = false;
        wrapper
            .syncAndRefresh(asset: ArrivalAsset.dollars, since: orderPlaced)
            .then((_) => done = true);
        async.flushMicrotasks();
        expect(done, isTrue);
        expect(async.elapsed, Duration.zero);
        expect(syncs, 0);
        wrapper.disconnect();
        async.flushMicrotasks();
      });
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
