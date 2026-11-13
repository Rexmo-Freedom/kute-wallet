// OrderPollGate: polling steps aside while an order runs and can never stay
// paused.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/polymarket/order_poll_gate.dart';

void main() {
  tearDown(OrderPollGate.debugReset);

  test('open by default', () => expect(OrderPollGate.paused, isFalse));

  test('paused while the order runs, open when it succeeds', () async {
    final seen = await OrderPollGate.during(() async {
      await Future<void>.delayed(Duration.zero);
      return OrderPollGate.paused;
    });
    expect(seen, isTrue);
    expect(OrderPollGate.paused, isFalse);
  });

  test('open after the order throws', () async {
    await expectLater(
        OrderPollGate.during<void>(() async => throw StateError('refused')),
        throwsStateError);
    expect(OrderPollGate.paused, isFalse);
  });

  test('open after the order throws synchronously', () async {
    await expectLater(
        OrderPollGate.during<void>(() => throw StateError('refused')),
        throwsStateError);
    expect(OrderPollGate.paused, isFalse);
  });

  test('ladder rungs one after another each hold and release', () async {
    for (var i = 0; i < 3; i++) {
      await OrderPollGate.during(
          () async => expect(OrderPollGate.paused, true));
      expect(OrderPollGate.paused, isFalse);
    }
  });

  test('an overlapping hold keeps it paused until the last one ends', () async {
    final finish = Completer<void>();
    final first = OrderPollGate.during(() => finish.future);
    await OrderPollGate.during(() async {
      expect(OrderPollGate.paused, isTrue);
    });
    expect(OrderPollGate.paused, isTrue);
    finish.complete();
    await first;
    expect(OrderPollGate.paused, isFalse);
  });

  test('the app leaving the screen opens it while the order still runs',
      () async {
    final order = OrderPollGate.during(() async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    });
    expect(OrderPollGate.paused, isTrue);
    OrderPollGate.appBackgrounded();
    expect(OrderPollGate.paused, isFalse);
    await order;
    expect(OrderPollGate.paused, isFalse);
  });

  test('a leaked hold stops counting after maxHold', () async {
    var now = DateTime(2026, 11, 9);
    OrderPollGate.debugSetClock(() => now);
    final neverEnds = OrderPollGate.during(
        () => Future<void>.delayed(const Duration(milliseconds: 5)));
    expect(OrderPollGate.paused, isTrue);
    now = now.add(OrderPollGate.maxHold + const Duration(seconds: 1));
    expect(OrderPollGate.paused, isFalse);
    await neverEnds;
  });
}
