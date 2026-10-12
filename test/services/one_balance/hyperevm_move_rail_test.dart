import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/settlement_operation.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/services/funding/settlement_runner.dart';
import 'package:kute/services/funding/spark_hypercore_funding_service.dart';
import 'package:kute/services/hyperevm/hyperevm_bridge.dart';
import 'package:kute/services/one_balance/hyperevm_move_rail.dart';
import 'package:kute/services/one_balance/venue_funder.dart';

import '../hyperevm/hyperevm_fakes.dart';

void main() {
  late ProviderContainer container;
  late FakeReader reader;
  late StreamController<void> credited;
  final asked = <RouteKey>[];

  setUp(() {
    container = ProviderContainer(overrides: [
      hyperliquidAddressProvider.overrideWith((_) async => kEoa),
    ]);
    addTearDown(container.dispose);
    reader = FakeReader()
      ..perpUsdc = coreUsdc(12.5)
      ..spotUsdc = coreUsdc(2.25);
    credited = StreamController<void>.broadcast();
    addTearDown(credited.close);
    asked.clear();
  });

  HyperEvmMoveRail rail(
          {HyperEvmRouteBounds? bounds, bool noEstimate = false}) =>
      HyperEvmMoveRail(
        container.read,
        reader: reader,
        credited: credited.stream,
        estimate: (route, amount) async {
          asked.add(route);
          if (noEstimate) return null;
          return OrchestraEstimate.fromJson({
            'estimatedOut': route.toAsset == 'USDC' ? '24900000' : '24850000',
            'feeAmount': '25000',
            'totalFeeAmount': '25000',
            'totalFeeAmountUsd': '0.025',
            'feeBps': 10,
          });
        },
        limits: (_) async => bounds,
      );

  test('withdrawable is perpetuals plus spot, or the one unified balance',
      () async {
    expect(await rail().withdrawableUsd(), 14.75);
    reader.mode = HyperCoreAccountMode.unified;
    expect(await rail().withdrawableUsd(), 2.25);
  });

  test('estimates ask the HyperEVM routes and fold the float in as fixed',
      () async {
    final deposit = await rail().estimate(usd: 25, deposit: true);
    expect(asked.single, kSparkUsdToHyperEvmRoute);
    expect(deposit.arrivingUsd, 24.9);
    expect(deposit.feeUsd, 0.025);
    expect(deposit.fixedCostUsd, 0, reason: 'the float is healthy');
    expect(deposit.minUsd, kHyperEvmMinMoveUsd);
    reader
      ..evmHypeWei = BigInt.zero
      ..spotHype = BigInt.zero;
    final withdraw = await rail(bounds: (minUsd: 0.8, maxUsd: 135300))
        .estimate(usd: 25, deposit: false);
    expect(asked.last, kHyperEvmToSparkUsdRoute);
    expect(withdraw.arrivingUsd, 24.85);
    expect(withdraw.fixedCostUsd, 1, reason: 'this move buys the float');
    expect(withdraw.maxUsd, 135300);
  });

  test('no estimate is a route the rail cannot carry', () async {
    await expectLater(rail(noEstimate: true).estimate(usd: 5, deposit: true),
        throwsA(isA<RouteUnavailable>()));
  });

  test('the minimum is the live floor, else the 80 cents Orchestra sets',
      () async {
    expect(await rail().minimumUsd(deposit: true), kHyperEvmMinMoveUsd);
    expect(
        await rail(bounds: (minUsd: 1.5, maxUsd: null))
            .minimumUsd(deposit: false),
        1.5);
  });

  test('a sweep is accepted only for the dollar route home', () async {
    SettlementAuthorizationIntent intent(RouteKey route) =>
        SettlementAuthorizationIntent(
          flow: SettlementFlow.investingToSparkUsdDirect,
          walletId: 'w',
          destination: 'sprt1self|v',
          routeLabel: route.label,
          amountIn: BigInt.from(1000000),
          minReceive: BigInt.from(990000),
          maxFeeBps: 10,
        );
    final hook = rail().stepUpFor(SweepAuthorization.automatic);
    expect(await hook(intent(kHyperEvmToSparkUsdRoute)), isTrue);
    expect(await hook(intent(kHyperEvmToSparkRoute)), isFalse);
    expect(await hook(intent(kSparkUsdToHyperEvmRoute)), isFalse);
  });

  test('a move\'s purpose reaches the funding service, both ways', () async {
    final service = _CapturingService(container.read);
    final rail = HyperEvmMoveRail(
      ProviderContainer(overrides: [
        hyperliquidAddressProvider.overrideWith((_) async => kEoa),
        sparkHypercoreFundingServiceProvider.overrideWithValue(service),
      ]).read,
      reader: reader,
      credited: credited.stream,
      estimate: (_, __) async => null,
      limits: (_) async => null,
    );
    await expectLater(
        rail.depositDollars(
            usd: 10,
            amountBaseUnits: BigInt.from(10000000),
            purpose: 'order_funding'),
        throwsA(isA<RouteUnavailable>()));
    await expectLater(
        rail.withdrawToDollars(
            usd: 10,
            auth: SweepAuthorization.automatic,
            purpose: 'rollout_sweep'),
        throwsA(isA<RouteUnavailable>()));
    expect(
        service.purposes, ['deposit:order_funding', 'withdraw:rollout_sweep']);
  });

  test('credited relays the sweeper\'s signal', () async {
    final seen = <void>[];
    final sub = rail().credited.listen(seen.add);
    credited.add(null);
    credited.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(seen.length, 2);
    await sub.cancel();
  });
}

/// Records the purpose each move arrives with and stops there (the stop
/// is what the rail reports as a route it cannot carry).
class _CapturingService extends SparkHypercoreFundingService {
  _CapturingService(super.read);

  final purposes = <String>[];

  @override
  Future<DirectHypercoreResult> depositFromSpark({
    required SparkFundingAsset asset,
    required BigInt amountBaseUnits,
    double? amountUsd,
    void Function()? onFundingStarted,
    SettlementStepUpHook? stepUp,
    bool registerInBackground = false,
    String purpose = 'manual_move',
  }) async {
    purposes.add('deposit:$purpose');
    throw const HypercoreFundingUnavailable(
        HypercoreFundingUnavailableReason.flagOff);
  }

  @override
  Future<DirectHypercoreResult> withdrawToSpark({
    required double usd,
    SparkFundingAsset destination = SparkFundingAsset.bitcoin,
    required SettlementStepUpHook stepUp,
    bool registerInBackground = false,
    String purpose = 'manual_move',
  }) async {
    purposes.add('withdraw:$purpose');
    throw const HypercoreFundingUnavailable(
        HypercoreFundingUnavailableReason.flagOff);
  }
}
