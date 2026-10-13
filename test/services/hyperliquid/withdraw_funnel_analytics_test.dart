// The Investing withdrawal funnel's PostHog properties: exact amounts only
// (no `amount_bucket`) and a `route` on every outcome, including the
// settlement reconciler's direct-route failure.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/settlement_operation.dart';
import 'package:kute/providers/settlement_reconciler_provider.dart'
    show SettlementReconcilerDriver;
import 'package:kute/services/funding/settlement_stage.dart';
import 'package:kute/services/funding/spark_hypercore_funding_service.dart'
    show kHypercoreToSparkUsdRoute;
import 'package:kute/services/tracking_service.dart';

void main() {
  final events = <(String, Map<String, Object>?)>[];

  setUp(() {
    events.clear();
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });
  tearDown(() => TrackingService.debugTrackObserver = null);

  Map<String, Object> only(String name) =>
      events.singleWhere((e) => e.$1 == name).$2!;

  test('submitted sends the exact amount and the route, never a bucket', () {
    TrackingService.hyperliquidWithdrawSubmitted(
      amountUsd: 12.34,
      route: 'cctp',
      destination: 'usd',
      walletKind: 'hot',
      purpose: 'manual_move',
    );
    final p = only('hyperliquid_withdraw_submitted');
    expect(p['amount_usd'], 12.34);
    expect(p['route'], 'cctp');
    expect(p['purpose'], 'manual_move');
    expect(p.containsKey('amount_bucket'), isFalse);
  });

  test('initiated, completed and failed carry no bucket either', () {
    TrackingService.hyperliquidWithdrawInitiated(
        amountUsd: 7.5, destination: 'btc', purpose: 'sweep');
    TrackingService.hyperliquidWithdrawCompleted(
        amountUsd: 7.5, route: 'direct');
    TrackingService.hyperliquidWithdrawFailed(
        reason: 'failed', route: 'cctp', amountUsd: 7.5);
    for (final name in const [
      'hyperliquid_withdraw_initiated',
      'hyperliquid_withdraw_completed',
      'hyperliquid_withdraw_failed',
    ]) {
      final p = only(name);
      expect(p['amount_usd'], 7.5, reason: name);
      expect(p.containsKey('amount_bucket'), isFalse, reason: name);
      expect(p['route'], isNotNull, reason: name);
    }
    expect(only('hyperliquid_withdraw_initiated')['route'], 'direct');
  });

  group('the reconciler\'s direct-route outcomes', () {
    SettlementOperation op(String id) => SettlementOperation(
          operationId: id,
          walletId: 'w',
          accountKind: SettlementAccountKind.hlHot,
          flow: SettlementFlow.investingToSparkUsdDirect,
          route: kHypercoreToSparkUsdRoute,
          amountInBaseUnits: '500000000',
          stage: SettlementStage.funded,
          createdAt: DateTime.utc(2026, 10, 13),
          updatedAt: DateTime.utc(2026, 10, 13),
        );
    final driver = SettlementReconcilerDriver(sessionUnlocked: () => false);

    test('failed carries route direct, as completed does', () {
      driver.reportVenueTerminal(
          op('op-failed'), SettlementStage.failed, 'hot', 5);
      driver.reportVenueTerminal(
          op('op-settled'), SettlementStage.settled, 'hot', 5);
      final failed = only('hyperliquid_withdraw_failed');
      expect(failed['route'], 'direct');
      expect(failed['destination'], 'usd');
      expect(failed['amount_usd'], 5);
      expect(failed.containsKey('amount_bucket'), isFalse);
      expect(only('hyperliquid_withdraw_completed')['route'], 'direct');
    });
  });
}
