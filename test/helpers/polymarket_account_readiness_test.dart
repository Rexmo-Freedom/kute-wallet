import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/polymarket_account_readiness.dart';
import 'package:kute/services/polymarket/placement_waits.dart';

void main() {
  test('knowing the account address still requires setup before readiness',
      () async {
    final readiness = PolymarketAccountReadiness();
    final deployment = Completer<void>();
    var setupCalls = 0;
    Future<void> initialize() {
      setupCalls++;
      return deployment.future;
    }

    final first = readiness.ensure(
      scope: 'wallet:0xPredictedAddress',
      isCurrent: () => true,
      initialize: initialize,
    );
    final second = readiness.ensure(
      scope: 'wallet:0xPredictedAddress',
      isCurrent: () => true,
      initialize: initialize,
    );
    expect(identical(first, second), isTrue);
    expect(setupCalls, 1);
    var completed = false;
    first.then((_) => completed = true);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    deployment.complete();
    await Future.wait([first, second]);
    expect(completed, isTrue);

    await readiness.ensure(
      scope: 'wallet:0xPredictedAddress',
      isCurrent: () => true,
      initialize: initialize,
    );
    expect(setupCalls, 1);
  });

  test('failed deployment remains retryable', () async {
    final readiness = PolymarketAccountReadiness();
    var attempts = 0;
    Future<void> setup() async {
      if (++attempts == 1) throw StateError('network unavailable');
    }

    await expectLater(
      readiness.ensure(
          scope: 'wallet:a', isCurrent: () => true, initialize: setup),
      throwsStateError,
    );
    await readiness.ensure(
        scope: 'wallet:a', isCurrent: () => true, initialize: setup);
    expect(attempts, 2);
  });

  test('forced repair reruns setup and concurrent repairs share one operation',
      () async {
    final readiness = PolymarketAccountReadiness();
    var attempts = 0;
    await readiness.ensure(
      scope: 'wallet:a',
      isCurrent: () => true,
      initialize: () async => attempts++,
    );
    final repair = Completer<void>();
    final first = readiness.ensure(
      scope: 'wallet:a',
      isCurrent: () => true,
      force: true,
      initialize: () {
        attempts++;
        return repair.future;
      },
    );
    final second = readiness.ensure(
      scope: 'wallet:a',
      isCurrent: () => true,
      force: true,
      initialize: () async => attempts++,
    );
    // One repair runs; the second caller waits on it.
    expect(attempts, 2);
    repair.complete();
    await Future.wait([first, second]);
  });

  group('a forced repair of a ready account', () {
    Future<PolymarketAccountReadiness> ready() async {
      final readiness = PolymarketAccountReadiness();
      await readiness.ensure(
          scope: 'wallet:a', isCurrent: () => true, initialize: () async {});
      return readiness;
    }

    test('leaves the account ready for every other bet while it runs',
        () async {
      final readiness = await ready();
      final repair = Completer<void>();
      final forced = readiness.ensure(
          scope: 'wallet:a',
          isCurrent: () => true,
          force: true,
          initialize: () => repair.future);
      expect(readiness.isReady, isTrue);
      var setups = 0;
      // Another market's placement does not join or wait on it.
      await readiness.ensure(
          scope: 'wallet:a',
          isCurrent: () => true,
          initialize: () async => setups++);
      expect(setups, 0);
      repair.complete();
      await forced;
      expect(readiness.isReady, isTrue);
    });

    test('releases its callers after the repair window, still ready', () {
      fakeAsync((async) {
        PolymarketAccountReadiness.now = async.getClock(DateTime(2026)).now;
        addTearDown(() => PolymarketAccountReadiness.now = DateTime.now);
        late PolymarketAccountReadiness readiness;
        ready().then((r) => readiness = r);
        async.flushMicrotasks();
        final hung = Completer<void>();
        Object? first, joined;
        readiness
            .ensure(
                scope: 'wallet:a',
                isCurrent: () => true,
                force: true,
                initialize: () => hung.future)
            .catchError((Object e) {
          first = e;
        });
        async.elapse(const Duration(seconds: 60));
        var repairs = 0;
        readiness
            .ensure(
                scope: 'wallet:a',
                isCurrent: () => true,
                force: true,
                initialize: () async => repairs++)
            .catchError((Object e) {
          joined = e;
        });
        expect(repairs, 0, reason: 'joins the running repair');
        // The joiner is held only for what is left of the window.
        async.elapse(const Duration(seconds: 31));
        expect(first, isA<TimeoutException>());
        expect(joined, isA<TimeoutException>());
        expect(readiness.isReady, isTrue);
        // Past the window a new forced repair starts its own.
        readiness.ensure(
            scope: 'wallet:a',
            isCurrent: () => true,
            force: true,
            initialize: () async => repairs++);
        async.flushMicrotasks();
        expect(repairs, 1);
        hung.complete();
        async.flushMicrotasks();
      });
    });

    test('that fails withdraws readiness, so the next placement runs setup',
        () async {
      final readiness = await ready();
      await expectLater(
          readiness.ensure(
              scope: 'wallet:a',
              isCurrent: () => true,
              force: true,
              initialize: () async => throw StateError('relayer refused')),
          throwsStateError);
      expect(readiness.isReady, isFalse);
      var setups = 0;
      await readiness.ensure(
          scope: 'wallet:a',
          isCurrent: () => true,
          initialize: () async => setups++);
      expect(setups, 1);
      expect(readiness.isReady, isTrue);
    });

    test('is bounded by the placement setup wait', () {
      expect(PolymarketAccountReadiness.repairWindow,
          PolymarketPlacementWaits.setup);
    });
  });

  test('a replaced account cannot inherit or publish another account setup',
      () async {
    final readiness = PolymarketAccountReadiness();
    var active = 'wallet:a';
    final oldSetup = Completer<void>();
    final old = readiness.ensure(
      scope: 'wallet:a',
      isCurrent: () => active == 'wallet:a',
      initialize: () => oldSetup.future,
    );
    final oldRejected = expectLater(old, throwsStateError);
    active = 'wallet:b';
    var newSetups = 0;
    await readiness.ensure(
      scope: 'wallet:b',
      isCurrent: () => active == 'wallet:b',
      initialize: () async => newSetups++,
    );
    oldSetup.complete();
    await oldRejected;
    await readiness.ensure(
      scope: 'wallet:b',
      isCurrent: () => active == 'wallet:b',
      initialize: () async => newSetups++,
    );
    expect(newSetups, 1);
  });

  test('an already stale or locked account never begins setup', () async {
    final readiness = PolymarketAccountReadiness();
    var called = false;
    await expectLater(
      readiness.ensure(
        scope: 'wallet:a',
        isCurrent: () => false,
        initialize: () async => called = true,
      ),
      throwsStateError,
    );
    expect(called, isFalse);
  });

  test(
      'a setup stuck past the join window is not waited on forever: the '
      'next caller starts its own', () async {
    var clock = DateTime(2026, 10, 5, 12);
    PolymarketAccountReadiness.now = () => clock;
    addTearDown(() => PolymarketAccountReadiness.now = DateTime.now);
    final readiness = PolymarketAccountReadiness();
    final stuck = Completer<void>();
    var setupCalls = 0;
    final first = readiness.ensure(
      scope: 'wallet',
      isCurrent: () => true,
      initialize: () {
        setupCalls++;
        return stuck.future;
      },
    );
    // Within the window a second caller shares it.
    clock = clock.add(const Duration(minutes: 1));
    final joined = readiness.ensure(
        scope: 'wallet', isCurrent: () => true, initialize: () async {});
    expect(identical(first, joined), isTrue);
    expect(setupCalls, 1);
    // Past it, a fresh setup runs and its success makes the account ready.
    clock = clock.add(PolymarketAccountReadiness.joinWindow);
    await readiness.ensure(
      scope: 'wallet',
      isCurrent: () => true,
      initialize: () async {
        setupCalls++;
      },
    );
    expect(setupCalls, 2);
    expect(readiness.isReady, isTrue);
    stuck.complete();
    await first;
    expect(readiness.isReady, isTrue);
  });
}
