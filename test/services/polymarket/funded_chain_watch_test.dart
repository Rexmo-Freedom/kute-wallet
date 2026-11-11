// The funded bet's own chain watch (founder, 11 November 2026: "make sure
// we don't DDoS RPC and such"): 1 s for 30 s after funding, 4 s until
// 2 minutes, then nothing (the 15 s poll carries on); one shared ticker,
// one read in flight, a hard cap per bet, exponential backoff on errors,
// no reads while it may not read. Fake clock, fake reads.

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/polymarket/funded_chain_watch.dart';

ChainCollateral _c(int pusd, int usdce) => (
      pusd: BigInt.from(pusd),
      usdce: BigInt.from(usdce),
      endpoint: 0,
      rpcErrors: 0
    );

void main() {
  final t0 = DateTime.utc(2026, 11, 11, 17, 14);

  /// A watch on [async]'s clock; [read] defaults to an instant answer.
  ({FundedChainWatch watch, List<Duration> at, List<ChainCollateral> seen})
      make(FakeAsync async,
          {Future<ChainCollateral?> Function()? read,
          bool Function()? canRead,
          int maxReads = FundedChainWatch.maxReadsPerWaiter}) {
    final at = <Duration>[];
    final seen = <ChainCollateral>[];
    late FundedChainWatch watch;
    watch = FundedChainWatch(
      read: () {
        at.add(async.elapsed);
        return read?.call() ?? Future.value(_c(0, 0));
      },
      onRead: seen.add,
      canRead: canRead,
      clock: () => t0.add(async.elapsed),
      maxReads: maxReads,
    );
    return (watch: watch, at: at, seen: seen);
  }

  test('cadence: every second for 30 s, every 4 s until 2 min, then none',
      () {
    fakeAsync((async) {
      final w = make(async);
      w.watch.watch('bet', since: t0);
      async.elapse(const Duration(minutes: 5));
      final fast = w.at.where((d) => d < const Duration(seconds: 30));
      final slow = w.at.where((d) => d >= const Duration(seconds: 30));
      expect(fast, hasLength(30));
      for (var i = 1; i < fast.length; i++) {
        expect(fast.elementAt(i) - fast.elementAt(i - 1),
            const Duration(seconds: 1));
      }
      expect(slow.every((d) => d < const Duration(minutes: 2)), isTrue);
      for (var i = 1; i < slow.length; i++) {
        expect(slow.elementAt(i) - slow.elementAt(i - 1),
            const Duration(seconds: 4));
      }
      // ≈ 52 ticks in all, under the cap of 60, nothing after 2 minutes.
      expect(w.at.length, lessThanOrEqualTo(FundedChainWatch.maxReadsPerWaiter));
      expect(w.at.length, 30 + slow.length);
      expect(w.watch.active, isFalse);
    });
  });

  test('a bet funded a while ago starts on the slower cadence', () {
    fakeAsync((async) {
      final w = make(async);
      w.watch.watch('bet', since: t0.subtract(const Duration(seconds: 100)));
      async.elapse(const Duration(seconds: 30));
      // 100 s → 120 s at 4 s: 0, 4, 8, 12, 16.
      expect(w.at, [
        for (var s = 0; s < 20; s += 4) Duration(seconds: s),
      ]);
    });
  });

  test('the hard cap per bet: no more reads once spent', () {
    fakeAsync((async) {
      final w = make(async, maxReads: 5);
      w.watch.watch('bet', since: t0);
      async.elapse(const Duration(seconds: 20));
      expect(w.at, hasLength(5));
      expect(w.watch.active, isFalse);
    });
  });

  test('one read in flight: a slow answer delays the next tick', () {
    fakeAsync((async) {
      var inFlight = 0;
      var most = 0;
      final w = make(async, read: () async {
        inFlight++;
        most = most > inFlight ? most : inFlight;
        await Future<void>.delayed(const Duration(milliseconds: 2500));
        inFlight--;
        return _c(0, 0);
      });
      w.watch.watch('bet', since: t0);
      async.elapse(const Duration(seconds: 10));
      expect(most, 1);
      // 0, then 2.75 s (answer + the 250 ms gap), 5.5, 8.25.
      expect(w.at, const [
        Duration.zero,
        Duration(milliseconds: 2750),
        Duration(milliseconds: 5500),
        Duration(milliseconds: 8250),
      ]);
    });
  });

  test('a read that never answers in time backs off and still never '
      'overlaps', () {
    fakeAsync((async) {
      var inFlight = 0;
      var most = 0;
      final hang = Completer<ChainCollateral?>();
      var first = true;
      final w = make(async, read: () {
        inFlight++;
        most = most > inFlight ? most : inFlight;
        if (first) {
          first = false;
          return hang.future.whenComplete(() => inFlight--);
        }
        inFlight--;
        return Future.value(_c(0, 0));
      });
      w.watch.watch('bet', since: t0);
      async.elapse(const Duration(seconds: 25));
      // Timed out at 20 s, still out: nothing else went.
      expect(w.at, [Duration.zero]);
      hang.complete(null);
      async.elapse(const Duration(seconds: 2));
      expect(most, 1);
      expect(w.at.length, greaterThan(1));
    });
  });

  test('two waiting bets share one read', () {
    fakeAsync((async) {
      final w = make(async);
      w.watch.watch('a', since: t0);
      w.watch.watch('b', since: t0);
      async.elapse(const Duration(milliseconds: 9500));
      expect(w.at, hasLength(10));
      expect(w.watch.readsFor('a'), 10);
      expect(w.watch.readsFor('b'), 10);
      // A late bet takes the faster cadence of the two; still one read.
      w.watch.unwatch('a');
      w.watch.unwatch('b');
      expect(w.watch.active, isFalse);
      async.elapse(const Duration(seconds: 5));
      expect(w.at, hasLength(10));
    });
  });

  test('errors back off 1, 2, 4, 8, 15, 15 s; a good read resets it', () {
    fakeAsync((async) {
      var fail = true;
      final w = make(async, read: () async {
        if (fail) throw TimeoutException('rpc');
        return _c(0, 0);
      });
      w.watch.watch('bet', since: t0);
      async.elapse(const Duration(seconds: 46));
      expect(w.at, const [
        Duration.zero,
        Duration(seconds: 1),
        Duration(seconds: 3),
        Duration(seconds: 7),
        Duration(seconds: 15),
        Duration(seconds: 30),
        Duration(seconds: 45),
      ]);
      expect(w.watch.failures, 7);
      fail = false;
      async.elapse(const Duration(seconds: 20));
      expect(w.watch.backoff, Duration.zero);
      // The good read at 60 s; then back on the 4 s cadence (past 30 s),
      // not the backoff.
      expect(w.at.skip(7).take(2),
          const [Duration(seconds: 60), Duration(seconds: 64)]);
    });
  });

  test('no read while it may not (backgrounded without grace, locked)', () {
    fakeAsync((async) {
      var may = false;
      final w = make(async, canRead: () => may);
      w.watch.watch('bet', since: t0);
      async.elapse(const Duration(seconds: 10));
      expect(w.at, isEmpty);
      expect(w.watch.readsFor('bet'), 0);
      may = true;
      async.elapse(const Duration(milliseconds: 2500));
      expect(w.at, const [Duration(seconds: 11), Duration(seconds: 12)]);
    });
  });

  test('covered, placed, failed or cancelled: unwatched, no more reads', () {
    fakeAsync((async) {
      late FundedChainWatch watch;
      var reads = 0;
      watch = FundedChainWatch(
        read: () async {
          reads++;
          return _c(reads >= 3 ? 10 : 0, 0);
        },
        onRead: (c) {
          if (c.pusd > BigInt.zero) watch.unwatch('bet');
        },
        clock: () => t0.add(async.elapsed),
      );
      watch.watch('bet', since: t0);
      async.elapse(const Duration(seconds: 20));
      expect(reads, 3);
      expect(watch.active, isFalse);
      watch.watch('next', since: t0.add(async.elapsed));
      async.elapse(const Duration(milliseconds: 500));
      watch.clear();
      async.elapse(const Duration(seconds: 10));
      expect(reads, 4);
    });
  });
}
