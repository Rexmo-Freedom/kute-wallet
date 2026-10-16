// A pull-to-refresh's full update (performUserRefresh, run by
// refresh_everything_provider) is never dropped: performFullUpdate returns
// at once while the 2 s loop's sync is running, so a pull that landed
// during one did nothing at all, not even its Predictions refresh. The
// user refresh waits for that sync and runs a fresh one, and a sync stuck
// "in progress" never makes it a no-op.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/balance_model.dart';
import 'package:kute/providers/background_sync_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';

class _CountingSync extends BackgroundSyncNotifier {
  var syncs = 0;
  @override
  Future<WalletBalance> performSync() async {
    syncs++;
    return WalletBalance.empty();
  }
}

class _CountingPredictions extends PolymarketTradingNotifier {
  static var refreshes = 0;
  @override
  Future<PolymarketTradingState> build() async =>
      const PolymarketTradingState();
  @override
  Future<void> refresh() async => refreshes++;
}

void main() {
  setUp(() {
    BackgroundSyncNotifier.bootHoldLimit = const Duration(milliseconds: 20);
    BackgroundSyncNotifier.userRefreshWaitLimit = const Duration(seconds: 5);
    _CountingPredictions.refreshes = 0;
  });
  tearDown(() {
    BackgroundSyncNotifier.bootHoldLimit = const Duration(seconds: 15);
    BackgroundSyncNotifier.userRefreshWaitLimit = const Duration(seconds: 20);
  });

  ProviderContainer container() {
    final c = ProviderContainer(overrides: [
      backgroundSyncNotifierProvider.overrideWith(_CountingSync.new),
      updateCurrencyProvider.overrideWith((ref) async {}),
      polymarketTradingProvider.overrideWith(_CountingPredictions.new),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test(
      'a pull during a running sync did nothing (the gap); the user refresh '
      'waits for it and runs its own', () async {
    final c = container();
    final notifier =
        c.read(backgroundSyncNotifierProvider.notifier) as _CountingSync;
    c.read(backgroundSyncInProgressProvider.notifier).state = true;

    await notifier.performFullUpdate();
    expect(notifier.syncs, 0, reason: 'dropped while the loop syncs');
    expect(_CountingPredictions.refreshes, 0);

    final pull = notifier.performUserRefresh();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(notifier.syncs, 0, reason: 'waits for the running sync');
    c.read(backgroundSyncInProgressProvider.notifier).state = false;
    await pull;
    expect(notifier.syncs, 1, reason: 'then reads everything afresh');
    expect(c.read(backgroundSyncInProgressProvider), isFalse);
    expect(_CountingPredictions.refreshes, 0,
        reason: 'Predictions are refreshed beside it by the caller');
  });

  test('a sync stuck "in progress" never makes a pull a no-op', () async {
    BackgroundSyncNotifier.userRefreshWaitLimit =
        const Duration(milliseconds: 200);
    final c = container();
    final notifier =
        c.read(backgroundSyncNotifierProvider.notifier) as _CountingSync;
    c.read(backgroundSyncInProgressProvider.notifier).state = true;
    await notifier.performUserRefresh();
    expect(notifier.syncs, 1);
  });

  test('the background loop keeps its Predictions refresh', () async {
    final c = container();
    final notifier =
        c.read(backgroundSyncNotifierProvider.notifier) as _CountingSync;
    await notifier.performFullUpdate(force: false);
    expect(notifier.syncs, 1);
    expect(_CountingPredictions.refreshes, 1);
  });
}
