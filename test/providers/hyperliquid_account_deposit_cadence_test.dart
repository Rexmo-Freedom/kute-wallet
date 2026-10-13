// While a HyperCore deposit is pending the account snapshot is polled
// every 4 s so the credit shows within one short poll; once the Orchestra
// row settles an account holding nothing is not polled at all (founder,
// 2026-10-13: no positions → no polling; events read it).
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/pending_pool_deposits_provider.dart';

class _CountingModel extends HyperliquidModel {
  int calls = 0;
  @override
  Future<HlAccountSnapshot> getPortfolioSnapshot(String address) async {
    calls++;
    return HlAccountSnapshot.empty;
  }
}

void main() {
  test('a pending deposit polls every 4 s; holding nothing, no poll at all',
      () {
    fakeAsync((async) {
      final model = _CountingModel();
      final pending = StateProvider<double>((_) => 0);
      final container = ProviderContainer(overrides: [
        hyperliquidAddressProvider.overrideWith(
            (_) async => '0x1111111111111111111111111111111111111111'),
        hyperliquidTradingModelProvider.overrideWithValue(model),
        pendingTradingDepositUsdProvider
            .overrideWith((ref) => ref.watch(pending)),
      ]);
      addTearDown(container.dispose);
      final sub = container.listen(hyperliquidAccountProvider, (_, __) {});
      addTearDown(sub.close);
      async.flushMicrotasks();
      expect(model.calls, 1, reason: 'initial load');
      final notifier = container.read(hyperliquidAccountProvider.notifier);
      expect(notifier.debugIntervalSecs, kHlNoPollIntervalSecs);

      // Nothing held: no read for minutes.
      async.elapse(const Duration(minutes: 5));
      expect(model.calls, 1);

      // A deposit starts: an immediate tick, then 4 s cadence.
      container.read(pending.notifier).state = 25;
      // Riverpod rebuilds dependents on its scheduler (a zero-delay timer).
      async.elapse(Duration.zero);
      expect(model.calls, 2, reason: 'forced tick on a new pending deposit');
      expect(notifier.debugIntervalSecs, kHlDepositPendingIntervalSecs);
      async.elapse(const Duration(seconds: 12));
      expect(model.calls, 2 + 3, reason: 'ticks at 4, 8, 12 s');

      // The credit lands (row settles): nothing held, no poll again.
      container.read(pending.notifier).state = 0;
      async.elapse(Duration.zero);
      expect(notifier.debugIntervalSecs, kHlNoPollIntervalSecs);
      final before = model.calls;
      async.elapse(const Duration(minutes: 5));
      expect(model.calls, before, reason: 'no periodic read when idle');
    });
  });
}
