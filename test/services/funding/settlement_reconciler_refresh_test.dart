// A move the settlement reconciler sees end (its status read turning
// settled or refunded) refreshes the cash accounts at both of its ends at
// once, through MoveSettledRefresh, instead of leaving them to their polls.
// Driven end to end: a record at `submitted`, the provider's answer, one
// reconcile pass.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/orchestra_routes_model.dart' show RouteKey;
import 'package:kute/models/settlement_operation.dart';
import 'package:kute/providers/settlement_reconciler_provider.dart'
    show SettlementReconcilerDriver;
import 'package:kute/services/funding/settlement_stage.dart';
import 'package:kute/services/funding/settlement_store.dart';
import 'package:kute/services/http/shared_http_client.dart';
import 'package:kute/services/one_balance/money_movement_route.dart';
import 'package:kute/services/one_balance/move_settled_refresh.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';

import '../../helpers/runtime_policy_fixture.dart';

final _at = DateTime(2026, 10, 30, 9, 15);

/// A record the provider already holds, one status read from its end.
SettlementOperation _op(SettlementFlow flow, {required String orderId}) =>
    SettlementOperation(
      operationId: 'op-$orderId',
      walletId: 'w',
      accountKind: SettlementAccountKind.sparkHot,
      flow: flow,
      route: RouteKey(
          fromChain: 'spark',
          fromAsset: 'BTC',
          toChain: 'spark',
          toAsset: 'USDB'),
      amountInBaseUnits: '5705',
      stage: SettlementStage.submitted,
      orderId: orderId,
      // A recovered record may start at a stage past broadcasting.
      recoveredFrom: 'test',
      createdAt: _at,
      updatedAt: _at,
    );

void main() {
  late Directory tmp;
  late SettlementStore store;
  late Map<String, String> statusById;
  late List<(Set<MoneyMovementAccount>, String)> seen;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('reconciler_refresh_');
    Hive.init(tmp.path);
    store = SettlementStore(
      box: await Hive.openBox<String>('operations'),
      quarantine: await Hive.openBox<String>('quarantine'),
    );
    dotenv.loadFromString(envString: 'BACKEND=https://backend.test');
    AffiliateService.debugSessionToken = 'test-session';
    RuntimeCapabilitiesService.debugInstance = runtimePolicyFixture();
    TrackingService.debugTrackObserver = (_, __) {};
    statusById = {};
    SharedHttpClient.debugOverride = MockClient((request) async {
      if (!request.url.path.endsWith('/status')) {
        return http.Response('', 404);
      }
      final id = request.url.queryParameters['id'];
      final status = statusById[id];
      if (status == null) return http.Response('', 404);
      return http.Response(
          jsonEncode({
            'order': {'id': id, 'quoteId': 'q_$id', 'status': status}
          }),
          200);
    });
    MoveSettledRefresh.debugReset();
    seen = [];
    MoveSettledRefresh.debugObserver = (accounts, source) =>
        seen.add((accounts, source));
  });

  tearDown(() async {
    MoveSettledRefresh.debugReset();
    SharedHttpClient.debugOverride = null;
    AffiliateService.debugSessionToken = null;
    TrackingService.debugTrackObserver = null;
    RuntimeCapabilitiesService.debugInstance?.dispose();
    RuntimeCapabilitiesService.debugInstance = null;
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  SettlementReconcilerDriver driver() => SettlementReconcilerDriver(
        sessionUnlocked: () => true,
        store: () async => store,
        clock: () => _at,
      );

  Future<SettlementOperation> stored(String operationId) async =>
      (await store.all()).singleWhere((o) => o.operationId == operationId);

  test('a settled move refreshes both of its ends once', () async {
    await store.create(_op(SettlementFlow.moveBtcToUsdc, orderId: 'ord_a'));
    statusById['ord_a'] = 'completed';
    await driver().runOnce();
    expect((await stored('op-ord_a')).stage, SettlementStage.settled);
    expect(seen, hasLength(1));
    expect(seen.single.$1,
        {MoneyMovementAccount.bitcoin, MoneyMovementAccount.dollars});
    expect(seen.single.$2, 'reconciler');
    // Terminal: the next pass reads nothing and refreshes nothing.
    await driver().runOnce();
    expect(seen, hasLength(1));
  });

  test('a refund refreshes the source too', () async {
    await store.create(
        _op(SettlementFlow.moveUsdToPredictions, orderId: 'ord_r'));
    statusById['ord_r'] = 'refunded';
    await driver().runOnce();
    expect((await stored('op-ord_r')).stage, SettlementStage.refunded);
    expect(seen, hasLength(1));
    expect(seen.single.$1,
        {MoneyMovementAccount.dollars, MoneyMovementAccount.predictions});
    expect(seen.single.$2, 'reconciler');
  });

  test('a move still in flight refreshes nothing', () async {
    await store.create(_op(SettlementFlow.moveBtcToUsdc, orderId: 'ord_p'));
    statusById['ord_p'] = 'processing';
    await driver().runOnce();
    expect((await stored('op-ord_p')).stage, SettlementStage.processing);
    expect(seen, isEmpty);
  });

  test('a Ledger flow touches no cash account, so nothing is refreshed',
      () async {
    await store.create(
        _op(SettlementFlow.ledgerBtcToInvesting, orderId: 'ord_l'));
    statusById['ord_l'] = 'completed';
    await driver().runOnce();
    expect((await stored('op-ord_l')).stage, SettlementStage.settled);
    expect(seen, isEmpty);
  });
}
