import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/cash_app_payment_window_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('deadline updates the display without any provider response', () {
    fakeAsync((async) {
      final clock = async.getClock(DateTime.utc(2026, 9, 15));
      final deadline = clock.now().add(const Duration(seconds: 10));
      final notifier = CashAppDeadlineNotifier(
        deadline.millisecondsSinceEpoch,
        now: clock.now,
      );
      final states = <bool>[];
      notifier.addListener(states.add);
      expect(states, [false]);
      async.elapse(const Duration(milliseconds: 9999));
      expect(states, [false]);
      async.elapse(const Duration(milliseconds: 1));
      expect(states, [false, true]);
      expect(async.pendingTimers, isEmpty);
      notifier.dispose();
    });
  });

  test('resume recomputes the wall-clock deadline after time away', () {
    fakeAsync((async) {
      var now = DateTime.utc(2026, 9, 15);
      final notifier = CashAppDeadlineNotifier(
        now.add(const Duration(minutes: 10)).millisecondsSinceEpoch,
        now: () => now,
      );
      final states = <bool>[];
      notifier.addListener(states.add);
      now = now.add(const Duration(days: 1));
      notifier.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(states, [false, true]);
      expect(async.pendingTimers, isEmpty);
      notifier.dispose();
    });
  });

  test('reopening an already ended purchase needs no timer or network', () {
    fakeAsync((async) {
      final now = DateTime.utc(2026, 9, 15);
      final notifier = CashAppDeadlineNotifier(
        now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
        now: () => now,
      );
      final states = <bool>[];
      notifier.addListener(states.add);
      expect(states, [true]);
      expect(async.pendingTimers, isEmpty);
      notifier.dispose();
    });
  });

  test('missing expiry never invents a payment timeout', () {
    fakeAsync((async) {
      final notifier = CashAppDeadlineNotifier(null);
      final states = <bool>[];
      notifier.addListener(states.add);
      async.elapse(const Duration(days: 30));
      notifier.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(states, [false]);
      expect(async.pendingTimers, isEmpty);
      notifier.dispose();
    });
  });

  test('disposing a hidden purchase cancels its display timer', () {
    fakeAsync((async) {
      final now = DateTime.utc(2026, 9, 15);
      final notifier = CashAppDeadlineNotifier(
        now.add(const Duration(minutes: 10)).millisecondsSinceEpoch,
        now: () => now,
      );
      expect(async.pendingTimers, hasLength(1));
      notifier.dispose();
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('only a real return to the foreground rechecks old closed orders',
      () async {
    final binding = TestWidgetsFlutterBinding.instance;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final schedule = container.read(cashAppClosedWindowScheduleProvider);
    final old = SwapOrder(
      id: 'ord_old',
      coinFrom: 'BTC',
      networkFrom: 'LIGHTNING',
      coinTo: 'BTC',
      networkTo: 'SPARK',
      depositAddress: 'lnbc1invoice',
      depositAmount: '0.001',
      withdrawalAmount: '0.00099',
      status: 'unfulfilled',
      timestamp: 1000,
      withdrawalAddress: '',
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: '',
      provider: 'Orchestra',
      purchaseSource: 'cashapp',
    );
    expect(schedule.begin(old), isTrue);
    schedule.recordSuccess(old.id);
    await Future<void>.delayed(const Duration(milliseconds: 2));

    // A biometric prompt or the notification shade.
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(schedule.begin(old), isFalse);

    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      binding.handleAppLifecycleStateChanged(state);
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
    expect(schedule.begin(old), isTrue);
  });
}
