import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/models/orchestra_route_limits.dart';
import 'package:kute/services/one_balance/buy_bitcoin_steps.dart';
import 'package:kute/services/one_balance/dollars_to_bitcoin_minimum.dart';
import 'package:kute/services/one_balance/dollars_to_bitcoin_purchase.dart';
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/services/one_balance/multi_source_move.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/pending_bitcoin_purchase.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/screens/shared/multi_source_move_activity.dart';
import 'package:kute/screens/shared/move_steps_view.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/models/transactions_model.dart';

final at = DateTime.utc(2026, 10, 16);
MultiSourceMove move({bool failed = false, String? finalOperation}) {
  var graph = BuyBitcoinSteps.planned(
      legs: [(venue: OneBalanceVenue.predictions, usd: 3.52, direct: true)],
      onwardUsd: 0.42,
      totalUsd: 3.94,
      at: at);
  graph = BuyBitcoinSteps.legRecorded(
      graph,
      MultiSourceMoveLeg(
          venue: OneBalanceVenue.predictions,
          usd: 3.52,
          arrivingUsd: 3.5,
          route: VenueCashRoute.direct,
          ok: true,
          at: at,
          operationId: 'source'));
  if (failed) graph = BuyBitcoinSteps.buyStopped(graph, 'error', at: at);
  if (finalOperation != null) {
    graph = BuyBitcoinSteps.buySent(graph, finalOperation);
  }
  return MultiSourceMove(
      id: 'move',
      forAction: BuyBitcoinSteps.forAction,
      destination: VenueCashDestination.bitcoin,
      totalUsd: 3.94,
      dollarsUsd: 0.42,
      createdAt: at,
      legs: [
        MultiSourceMoveLeg(
            venue: OneBalanceVenue.predictions,
            usd: 3.52,
            arrivingUsd: 3.5,
            route: VenueCashRoute.direct,
            ok: true,
            at: at,
            operationId: 'source')
      ],
      finalOperationId: finalOperation,
      steps: graph);
}

AuthGrant grant() => AuthGrants.issue(
    DirectLegGrants.buyBitcoin(
        walletId: 'wallet',
        ownSpark: 'self',
        route: kDollarsToBtcRoute.label,
        asset: 'USDB',
        totalUsd: 3.94,
        directLegs: null,
        ttl: AuthGrants.autofireTtl),
    method: AuthGrantMethod.biometric);
SwapOrderTransaction row(String status) => SwapOrderTransaction(
    id: 'source',
    timestamp: at,
    isConfirmed: status == 'success',
    details: SwapOrder(
        id: 'source',
        coinFrom: 'USDC.e',
        networkFrom: 'POLYGON',
        coinTo: 'BTC',
        networkTo: 'SPARK',
        depositAddress: '',
        depositAmount: '3.52',
        withdrawalAmount: '0.000035',
        status: status,
        timestamp: at.millisecondsSinceEpoch,
        withdrawalAddress: 'self',
        depositMin: '0',
        depositMax: '0',
        rate: '0',
        refundAddress: '',
        provider: 'Orchestra',
        operationId: 'source'));

void main() {
  setUp(() {
    MultiSourceMoveStore.reset();
    PendingBitcoinPurchaseStore.reset();
  });
  test(
      'sub-dollar remainder needs no limits, quote, address, prepare or approval',
      () async {
    var reads = 0;
    final minimum = DollarsToBitcoinMinimum(fetch: (_) async {
      fail('dust must not request limits');
    });
    T read<T>(ProviderListenable<T> provider) {
      reads++;
      if (identical(provider, dollarsToBitcoinMinimumProvider)) {
        return minimum as T;
      }
      fail('must stop before address, quote, prepare or send');
    }

    await expectLater(
        buyBitcoinFromDollars(read,
            amountBaseUnits: BigInt.from(420000), usd: 0.42, stepUp: (_) async {
          fail('no approval for dust');
        }),
        throwsA(isA<DollarsToBitcoinBelowMinimum>()));
    expect(reads, 1);
  });
  test(
      'exact-in source units and both USD minimums use largest bound, inclusive edge',
      () async {
    final minimum = DollarsToBitcoinMinimum(fetch: (route) async {
      expect(route.label, kDollarsToBtcRoute.label);
      return OrchestraRouteLimits(
          orderMinUsdCents: 200,
          exactInMinUsdCents: 300,
          exactInMinBaseUnits: BigInt.from(3500001));
    });
    await expectLater(minimum.check(BigInt.from(3500000)),
        throwsA(isA<DollarsToBitcoinBelowMinimum>()));
    await minimum.check(BigInt.from(3500001));
    expect(
        DollarsToBitcoinMinimum.belowLimits(BigInt.from(1000000), null), false);
    expect(
        DollarsToBitcoinMinimum.belowLimits(BigInt.from(999999), null), true);
  });
  test('shared minimum read is single flight and caches success or failure',
      () async {
    var now = at;
    var calls = 0;
    final response = Completer<OrchestraRouteLimits?>();
    final minimum = DollarsToBitcoinMinimum(
        clock: () => now,
        fetch: (_) {
          calls++;
          return response.future;
        });
    final a = minimum.check(BigInt.from(2000000));
    final b = minimum.check(BigInt.from(2000000));
    expect(calls, 1);
    response.complete(const OrchestraRouteLimits(orderMinUsdCents: 100));
    await Future.wait([a, b]);
    await minimum.check(BigInt.from(2000000));
    expect(calls, 1);
    now = now.add(const Duration(minutes: 10));
    await minimum.check(BigInt.from(2000000));
    expect(calls, 2);
    var failedReads = 0;
    final offline = DollarsToBitcoinMinimum(
        clock: () => now,
        fetch: (_) async {
          failedReads++;
          throw StateError('offline');
        });
    await offline.check(BigInt.from(2000000));
    await offline.check(BigInt.from(2000000));
    expect(failedReads, 1);
    now = now.add(const Duration(minutes: 1));
    await offline.check(BigInt.from(2000000));
    expect(failedReads, 2);
  });
  test('unknown limits do not invent a minimum or hide quote enforcement',
      () async {
    await DollarsToBitcoinMinimum(
            fetch: (_) async => throw StateError('offline'))
        .check(BigInt.from(1000000));
  });
  test(
      'background dust is skipped, persisted pending removed, direct leg stays live',
      () async {
    MultiSourceMoveStore.start(move());
    var calls = 0;
    final finisher = BitcoinPurchaseFinisher(
        readDollars: () => 0.42,
        buy: (_, __, {required moveId, required onFunding}) async {
          calls++;
        });
    expect(await finisher.start(moveId: 'move', usd: 0.42, grant: grant()),
        PendingPurchaseEnd.skipped);
    expect(calls, 0);
    expect(PendingBitcoinPurchaseStore.get('move'), isNull);
    final saved = MultiSourceMoveStore.get('move')!;
    expect(saved.steps.byId('buy')!.status, MoneyStepStatus.skipped);
    expect(saved.spentUsd, 3.52);
    expect(multiSourceMoveStepFailed(saved), false);
    expect(multiSourceMoveSettled(saved, [row('exchanging')]), false);
    expect(multiSourceMoveSettled(saved, [row('success')]), true);
    expect(multiSourceMoveTotals(saved, [row('success')]).sentUsd, 3.52);
    final live = liveMoveSteps(saved, [row('success')]);
    expect(live.byId('arrive')!.status, MoneyStepStatus.done);
    // A second idempotent skip never subtracts the remainder again.
    expect(BuyBitcoinSteps.buySkipped(saved.steps).byId('arrive')!.usd,
        saved.steps.byId('arrive')!.usd);
  });
  test('live-minimum background rejection skips before waiting or buying',
      () async {
    MultiSourceMoveStore.start(move());
    final finisher = BitcoinPurchaseFinisher(
        readDollars: () => 0,
        preflight: (_) async => throw const DollarsToBitcoinBelowMinimum(),
        buy: (_, __, {required moveId, required onFunding}) async {
          fail('must not buy');
        },
        sleep: (_) async {
          fail('must not wait for known dust');
        });
    expect(await finisher.start(moveId: 'move', usd: 1.5, grant: grant()),
        PendingPurchaseEnd.skipped);
    expect(PendingBitcoinPurchaseStore.get('move'), isNull);
  });
  test('funding already begun is never downgraded to harmless dust', () async {
    MultiSourceMoveStore.start(move(finalOperation: 'already_sent'));
    final finisher = BitcoinPurchaseFinisher(
        readDollars: () => 5,
        buy: (_, __, {required moveId, required onFunding}) async {
          onFunding();
          throw const DollarsToBitcoinBelowMinimum();
        });
    expect(await finisher.start(moveId: 'move', usd: 2, grant: grant()),
        PendingPurchaseEnd.handedToSettlement);
    final saved = MultiSourceMoveStore.get('move')!;
    expect(saved.steps.byId('buy')!.status, MoneyStepStatus.running);
    expect(saved.spentUsd, 3.94);
  });
  test(
      'legacy failed unsent dust normalizes only with no active or sent purchase',
      () {
    final old = move(failed: true);
    expect(bitcoinPurchaseMoveForDisplay(old).steps.byId('buy')!.status,
        MoneyStepStatus.skipped);
    expect(multiSourceMoveStepFailed(old), false);
    expect(multiSourceMoveTotals(old, [row('success')]).sentUsd, 3.52);
    expect(
        MultiSourceMoveTransaction(move: old, legRows: [row('success')])
            .move
            .spentUsd,
        3.52);
    PendingBitcoinPurchaseStore.put(PendingBitcoinPurchase(
        moveId: 'move',
        usd: 0.42,
        createdAt: at,
        stage: PendingPurchaseStage.funding));
    expect(bitcoinPurchaseMoveForDisplay(old).steps.byId('buy')!.status,
        MoneyStepStatus.failed);
    expect(multiSourceMoveStepFailed(old), true);
    expect(
        bitcoinPurchaseMoveForDisplay(move(finalOperation: 'sent'))
            .steps
            .byId('buy')!
            .status,
        MoneyStepStatus.running);
  });
}
