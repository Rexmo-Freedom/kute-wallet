// The purchase that finishes a Buy bitcoin whose venue cash came home to
// Dollars first (founder case, 15 October 2026: the Investing leg went
// via Dollars, the Dollars landed and no bitcoin was bought). It runs in
// the background under the Buy's one approval, after the sheet has closed;
// it is recorded so a restart never loses it; and whenever it cannot
// finish on its own it waits on one tap, never silently.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/models/settlement_operation.dart' show SettlementFlow;
import 'package:kute/services/funding/settlement_runner.dart'
    show SettlementAuthorizationIntent, SettlementStepUpHook;
import 'package:kute/services/one_balance/dollars_to_bitcoin_purchase.dart';
import 'package:kute/services/one_balance/pending_bitcoin_purchase.dart';
import 'package:kute/services/tracking_service.dart';

const _ownSpark = 'spark1self';

/// The Buy's one approval for [usd] to the own Spark address.
AuthGrant _grant(double usd, {Duration ttl = AuthGrants.autofireTtl}) =>
    AuthGrants.issue(
      DirectLegGrants.buyBitcoin(
        walletId: 'w1',
        ownSpark: _ownSpark,
        route: kDollarsToBtcRoute.label,
        asset: 'USDB',
        totalUsd: usd,
        directLegs: null,
        ttl: ttl,
      ),
      method: AuthGrantMethod.biometric,
    );

/// The purchase's settlement as the runner asks its step-up for it.
SettlementAuthorizationIntent _auth(double usd) =>
    SettlementAuthorizationIntent(
      flow: SettlementFlow.moveDollarsToBtc,
      walletId: 'w1',
      destination: '$_ownSpark|v1',
      routeLabel: kDollarsToBtcRoute.label,
      amountIn: BigInt.from((usd * 1e6).round()),
      minReceive: BigInt.one,
      maxFeeBps: 100,
    );

/// The purchase, as the test answers it: records what was bought and
/// whether the step-up let it pay.
class _Buy {
  final calls = <double>[];
  final approved = <bool>[];
  Object? error;
  bool failAfterFunding = false;

  Future<void> call(double usd, SettlementStepUpHook stepUp,
      {required String moveId, required void Function() onFunding}) async {
    calls.add(usd);
    final ok = await stepUp(_auth(usd));
    approved.add(ok);
    if (!ok) throw StateError('declined');
    final e = error;
    if (e != null && !failAfterFunding) throw e;
    onFunding();
    if (e != null) throw e;
  }
}

void main() {
  late Directory dir;
  late DateTime now;
  late double dollars;
  late List<(String, Map<String, Object>?)> events;

  BitcoinPurchaseFinisher finisher(_Buy buy) => BitcoinPurchaseFinisher(
        readDollars: () => dollars,
        buy: buy.call,
        clock: () => now,
        sleep: (d) async {
          now = now.add(d);
          // The dollars that came home land after two minutes.
          if (now.isAfter(DateTime(2026, 10, 15, 12, 2))) dollars = 25.71;
        },
      );

  Map<String, Object>? event(String name) =>
      events.where((e) => e.$1 == name).last.$2;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('kute_pending_purchase');
    Hive.init(dir.path);
    await Hive.openBox('settings');
    PendingBitcoinPurchaseStore.reload();
    now = DateTime(2026, 10, 15, 12);
    AuthGrants.clock = () => now;
    dollars = 0;
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });
  tearDown(() async {
    TrackingService.debugTrackObserver = null;
    AuthGrants.clock = DateTime.now;
    PendingBitcoinPurchaseStore.reset();
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test(
      'founder case: the leg came home to Dollars, the sheet is gone, the '
      'Dollars land and the bitcoin is still bought under the same approval',
      () async {
    final buy = _Buy();
    final f = finisher(buy);
    final grant = _grant(20.23);
    final run = f.start(moveId: 'msm_1', usd: 20.23, grant: grant);
    // Recorded at once, running: nothing waits on the person.
    expect(PendingBitcoinPurchaseStore.get('msm_1'), isNotNull);
    expect(f.running('msm_1'), isTrue);
    expect(f.waitingOnApproval('msm_1'), isNull);
    expect(await run, PendingPurchaseEnd.bought);
    // Bought exactly what the purchase takes from Dollars, once, and the
    // Buy's own approval let it pay (no second prompt).
    expect(buy.calls, [20.23]);
    expect(buy.approved, [true]);
    expect(grant.consumed, isTrue);
    expect(PendingBitcoinPurchaseStore.get('msm_1'), isNull);
    expect(event('move_purchase_finished'), {
      'outcome': 'bought',
      'amount_usd': 20.23,
      'waited_ms': greaterThanOrEqualTo(120000),
      'resumed': false,
    });
  });

  test(
      'the approval runs out before the Dollars land: nothing is bought, '
      'the purchase waits on one tap', () async {
    final buy = _Buy();
    final f = finisher(buy);
    final grant = _grant(20.23, ttl: const Duration(minutes: 1));
    expect(await f.start(moveId: 'msm_1', usd: 20.23, grant: grant),
        PendingPurchaseEnd.needsApproval);
    expect(buy.calls, isEmpty);
    expect(grant.revoked, isTrue);
    final waiting = f.waitingOnApproval('msm_1')!;
    expect(waiting.usd, 20.23);
    expect(waiting.stage, PendingPurchaseStage.needsApproval);
    expect(event('move_purchase_finished')!['outcome'], 'needs_approval');
    expect(event('move_purchase_finished')!['reason'], 'dollars_not_landed');
  });

  test(
      'restart: the record survives, no approval does; one tap with a fresh '
      'approval buys it', () async {
    final firstBuy = _Buy();
    // The app dies while the dollars are still coming home: its wait
    // never wakes again.
    final first = BitcoinPurchaseFinisher(
      readDollars: () => dollars,
      buy: firstBuy.call,
      clock: () => now,
      sleep: (_) => Completer<void>().future,
    );
    unawaited(first.start(
        moveId: 'msm_1', usd: 20.23, grant: _grant(20.23), walletId: 'w1'));
    expect(PendingBitcoinPurchaseStore.get('msm_1')!.stage,
        PendingPurchaseStage.waiting);

    // A new launch: the box is read again, a new finisher has no grant.
    PendingBitcoinPurchaseStore.reload();
    dollars = 25.71;
    final buy = _Buy();
    final second = finisher(buy);
    final waiting = second.waitingOnApproval('msm_1');
    expect(waiting, isNotNull, reason: 'it says so, never silent');
    expect(waiting!.usd, 20.23);
    expect(waiting.walletId, 'w1');
    expect(buy.calls, isEmpty, reason: 'nothing moves without a tap');

    final fresh = _grant(20.23);
    expect(
        await second.start(
            moveId: 'msm_1', usd: 20.23, grant: fresh, resumed: true),
        PendingPurchaseEnd.bought);
    expect(buy.calls, [20.23]);
    expect(firstBuy.calls, isEmpty, reason: 'bought once, after the restart');
    expect(PendingBitcoinPurchaseStore.get('msm_1'), isNull);
    expect(event('move_purchase_finished')!['resumed'], isTrue);
  });

  test('a purchase that stops before anything left Dollars waits on a tap',
      () async {
    dollars = 30;
    final buy = _Buy()..error = StateError('quote rejected');
    final f = finisher(buy);
    expect(await f.start(moveId: 'msm_1', usd: 20.23, grant: _grant(20.23)),
        PendingPurchaseEnd.needsApproval);
    expect(f.waitingOnApproval('msm_1'), isNotNull);
  });

  test(
      'once the dollars were handed to the send it is never offered again: '
      'the settlement owns the order', () async {
    dollars = 30;
    final buy = _Buy()
      ..error = StateError('outcome unknown')
      ..failAfterFunding = true;
    final f = finisher(buy);
    expect(await f.start(moveId: 'msm_1', usd: 20.23, grant: _grant(20.23)),
        PendingPurchaseEnd.handedToSettlement);
    expect(f.waitingOnApproval('msm_1'), isNull);
    expect(PendingBitcoinPurchaseStore.get('msm_1'), isNull);
  });

  test('a record marked funding before a restart is never offered again',
      () async {
    PendingBitcoinPurchaseStore.put(PendingBitcoinPurchase(
        moveId: 'msm_1',
        usd: 20.23,
        createdAt: now,
        stage: PendingPurchaseStage.funding));
    PendingBitcoinPurchaseStore.reload();
    expect(finisher(_Buy()).waitingOnApproval('msm_1'), isNull);
  });

  test('a second start joins the running purchase; it is bought once',
      () async {
    final buy = _Buy();
    final f = finisher(buy);
    final again = _grant(20.23);
    final a = f.start(moveId: 'msm_1', usd: 20.23, grant: _grant(20.23));
    final b = f.start(moveId: 'msm_1', usd: 20.23, grant: again);
    expect(again.revoked, isTrue);
    await Future.wait([a, b]);
    expect(buy.calls, hasLength(1));
  });

  test('the approval pays only its own purchase: no more, not elsewhere',
      () async {
    final grant = _grant(20.23);
    final stepUp = approvedPurchaseStepUp(grant);
    expect(await stepUp(_auth(25)), isFalse, reason: 'more than approved');
    final elsewhere = SettlementAuthorizationIntent(
      flow: SettlementFlow.moveDollarsToBtc,
      walletId: 'w1',
      destination: 'spark1other|v1',
      routeLabel: kDollarsToBtcRoute.label,
      amountIn: BigInt.from(20230000),
      minReceive: BigInt.one,
      maxFeeBps: 100,
    );
    expect(await stepUp(elsewhere), isFalse, reason: 'not the own address');
    expect(await stepUp(_auth(20.23)), isTrue);
    expect(await stepUp(_auth(20.23)), isFalse, reason: 'single use');
  });
}
