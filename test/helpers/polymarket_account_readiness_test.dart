import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/polymarket_account_readiness.dart';

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
    expect(identical(first, second), isTrue);
    expect(attempts, 2);
    repair.complete();
    await first;
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
