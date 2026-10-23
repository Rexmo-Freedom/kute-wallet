// Founder report (20 October 2026, prediction funded from Bitcoin straight
// into Predictions): the Activity detail said "Processing" with the
// journey's Bitcoin → Predictions still running and "Track this exchange"
// answered "still processing" (the row still held its q_ quote id) while
// the deposit wallet had already received the USDC.e and converted it.
//
//  * an order id learned anywhere (the flow's background submit, the
//    reconciler's retry, a status read) is followed by every status read
//    of the quote, and the reconciler moves a linked quote row to it;
//  * money the app saw land in its venue shows the journey's arrival done
//    while Orchestra's status still lags (the row keeps that status);
//  * a move running longer than expected says so after 1.5 times its
//    estimate, 90 s without one.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/orchestra_routes_model.dart' show RouteKey;
import 'package:kute/models/settlement_operation.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/settlement_reconciler_provider.dart'
    show
        SettlementActivityRows,
        SettlementReconcilerDriver,
        settlementRowOrderId;
import 'package:kute/services/funding/settlement_registration.dart';
import 'package:kute/services/funding/settlement_stage.dart';
import 'package:kute/services/funding/settlement_store.dart';
import 'package:kute/services/http/shared_http_client.dart';
import 'package:kute/services/hyperliquid/hyperliquid_websocket.dart';
import 'package:kute/services/one_balance/bitcoin_to_dollars_leg.dart'
    show orchestraLegStatus;
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/services/one_balance/move_steps.dart';
import 'package:kute/services/one_balance/slow_move.dart';
import 'package:kute/services/orchestra/venue_arrivals.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

import '../../helpers/runtime_policy_fixture.dart';

const _wallet = '0x0088aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
final _at = DateTime(2026, 10, 20, 18, 5);

/// The direct Bitcoin → Predictions leg's row, as the flow writes it.
SwapOrder _deposit({
  String id = 'q_direct',
  String status = 'exchanging',
  String usd = '4.67',
  String? operationId = 'op-direct',
  DateTime? at,
  String wallet = _wallet,
}) =>
    SwapOrder(
      id: id,
      coinFrom: 'BTC',
      networkFrom: 'SPARK',
      coinTo: 'USDC',
      networkTo: 'POLYGON',
      depositAddress: 'spark1deposit',
      depositAmount: '0.00005705',
      withdrawalAmount: usd,
      status: status,
      timestamp: (at ?? _at).millisecondsSinceEpoch,
      withdrawalAddress: wallet,
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: 'spark1own',
      provider: 'Orchestra',
      walletId: 'spending',
      operationId: operationId,
    );

const _hl = '0x00bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

/// A Move sheet deposit into Investing, as the funding service writes it
/// (Bitcoin or Dollars from Spark → USDC on HyperCore, to the own account).
SwapOrder _investing({
  String id = 'ord_hl',
  String from = 'BTC',
  String usd = '24.80',
  String status = 'exchanging',
  String? operationId = 'op-hl',
  DateTime? at,
  String account = _hl,
}) =>
    SwapOrder(
      id: id,
      coinFrom: from,
      networkFrom: 'SPARK',
      coinTo: 'USDC',
      networkTo: 'HYPERCORE',
      depositAddress: 'spark1deposit',
      depositAmount: from == 'BTC' ? '0.00025000' : '25.00',
      withdrawalAmount: usd,
      status: status,
      timestamp: (at ?? _at).millisecondsSinceEpoch,
      withdrawalAddress: account,
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: 'spark1own',
      provider: 'Orchestra',
      walletId: 'spending',
      operationId: operationId,
    );

HlAccountSnapshot _snap(double perp, double spotUsdc,
        {List<HlPerpPosition> positions = const []}) =>
    HlAccountSnapshot(
      accountValue: perp,
      withdrawable: perp,
      totalMarginUsed: 0,
      positions: positions,
      spotBalances: [HlSpotBalance(coin: 'USDC', total: spotUsdc, hold: 0)],
    );

SettlementOperation _op(String? orderId) => SettlementOperation(
      operationId: 'op-direct',
      walletId: 'spending',
      accountKind: SettlementAccountKind.sparkHot,
      flow: SettlementFlow.moveBtcToPredictions,
      route: RouteKey(
          fromChain: 'spark',
          fromAsset: 'BTC',
          toChain: 'polygon',
          toAsset: 'USDC.e'),
      amountInBaseUnits: '5705',
      stage: SettlementStage.funded,
      orderId: orderId,
      createdAt: _at,
      updatedAt: _at,
    );

void main() {
  setUp(() {
    OrchestraOrderIds.debugReset();
    VenueArrivals.debugReset();
  });

  group('the order a quote became', () {
    test('is followed once known; quotes and blanks never count', () {
      expect(OrchestraOrderIds.resolve('q_direct'), 'q_direct');
      OrchestraOrderIds.record('q_direct', 'q_other');
      OrchestraOrderIds.record('q_direct', '');
      OrchestraOrderIds.record('ord_x', 'ord_y');
      expect(OrchestraOrderIds.resolve('q_direct'), 'q_direct');
      OrchestraOrderIds.record('q_direct', 'ord_direct');
      expect(OrchestraOrderIds.resolve('q_direct'), 'ord_direct');
      expect(OrchestraOrderIds.resolve('ord_direct'), 'ord_direct');
    });

    test(
        'a linked quote row moves to the order its operation registered '
        '(the reconciler\'s retry), never otherwise', () {
      expect(settlementRowOrderId(_deposit(), _op('ord_direct')), 'ord_direct');
      expect(settlementRowOrderId(_deposit(), _op(null)), isNull);
      expect(
          settlementRowOrderId(_deposit(id: 'ord_direct'), _op('ord_direct')),
          isNull);
      expect(settlementRowOrderId(_deposit(), _op('q_direct')), isNull);
    });

    test('moving a row records the order for the quote\'s status reads',
        () async {
      final rows = <SwapOrder>[_deposit()];
      final moved = await adoptRegisteredOrchestraRow(
        quoteId: 'q_direct',
        orderId: 'ord_direct',
        rows: OrchestraActivityRows(
          rows: () => rows,
          add: (r) async => rows.add(r),
          delete: (id) async => rows.removeWhere((r) => r.id == id),
          uncache: (_) {},
          cache: (_) {},
        ),
      );
      expect(moved?.id, 'ord_direct');
      expect(rows.map((r) => r.id), ['ord_direct']);
      expect(rows.single.operationId, 'op-direct');
      expect(OrchestraOrderIds.resolve('q_direct'), 'ord_direct');
    });

    test(
        'the reconciler\'s pass moves the linked quote row to the order its '
        'operation holds', () async {
      final tmp = await Directory.systemTemp.createTemp('venue_adopt_');
      Hive.init(tmp.path);
      addTearDown(() async {
        await Hive.close();
        await tmp.delete(recursive: true);
      });
      final store = SettlementStore(
        box: await Hive.openBox<String>('operations'),
        quarantine: await Hive.openBox<String>('quarantine'),
      );
      // The stage does not matter to the row: a record starts quoted.
      await store
          .create(_op('ord_direct').copyWith(stage: SettlementStage.quoted));
      final rows = _Rows([_deposit()]);
      final driver = SettlementReconcilerDriver(
        // Locked: no backend read or submit runs, the rows still follow.
        sessionUnlocked: () => false,
        store: () async => store,
        clock: () => _at,
        activityRows: rows,
      );
      await driver.runOnce();
      expect(rows.adopted, [('q_direct', 'ord_direct')]);
      expect(rows.expired, isEmpty);
      expect(rows.removed, isEmpty);
    });

    group('a leg\'s status read', () {
      late Directory tmp;
      late List<Map<String, String>> reads;

      setUp(() async {
        tmp = await Directory.systemTemp.createTemp('venue_arrivals_');
        Hive.init(tmp.path);
        dotenv.loadFromString(envString: 'BACKEND=https://backend.test');
        AffiliateService.debugSessionToken = 'test-session';
        RuntimeCapabilitiesService.debugInstance = runtimePolicyFixture();
        reads = [];
        SharedHttpClient.debugOverride = MockClient((request) async {
          if (!request.url.path.endsWith('/status')) {
            return http.Response('', 404);
          }
          final q = request.url.queryParameters;
          reads.add(q);
          // The quote lookup lags: no order behind the quote yet.
          if (q['quoteId'] == 'q_direct') {
            return http.Response(jsonEncode({'order': null}), 200);
          }
          if (q['quoteId'] == 'q_found') {
            return http.Response(
                jsonEncode({
                  'order': {
                    'id': 'ord_found',
                    'quoteId': 'q_found',
                    'status': 'processing'
                  }
                }),
                200);
          }
          if (q['id'] == 'ord_direct') {
            return http.Response(
                jsonEncode({
                  'order': {
                    'id': 'ord_direct',
                    'quoteId': 'q_direct',
                    'status': 'completed'
                  }
                }),
                200);
          }
          return http.Response('', 404);
        });
      });

      tearDown(() async {
        SharedHttpClient.debugOverride = null;
        AffiliateService.debugSessionToken = null;
        RuntimeCapabilitiesService.debugInstance?.dispose();
        RuntimeCapabilitiesService.debugInstance = null;
        await Hive.close();
        await tmp.delete(recursive: true);
      });

      test('reads the order once known, not the lagging quote', () async {
        expect(await orchestraLegStatus('q_direct'), isNull);
        OrchestraOrderIds.record('q_direct', 'ord_direct');
        expect(await orchestraLegStatus('q_direct'), 'completed');
        expect(reads.last, {'id': 'ord_direct'});
      });

      test('a quote read that returns its order records it', () async {
        expect(await orchestraLegStatus('q_found'), 'processing');
        expect(OrchestraOrderIds.resolve('q_found'), 'ord_found');
      });
    });
  });

  group('an arrival the app saw', () {
    test('follows the row from its quote id to its order id', () {
      final quoteRow = _deposit();
      VenueArrivals.mark(quoteRow);
      expect(VenueArrivals.arrived(quoteRow), isTrue);
      // Moved to its order id: the operation is kept.
      expect(VenueArrivals.arrived(_deposit(id: 'ord_direct')), isTrue);
      // Another deposit is not marked.
      expect(
          VenueArrivals.arrived(
              _deposit(id: 'ord_other', operationId: 'op-other')),
          isFalse);
    });

    test(
        'USDC.e converted in the deposit wallet marks the deposit it stands '
        'for: same wallet, close amount, recent, still on its way', () {
      final rows = [
        _deposit(id: 'q_old', operationId: 'op-old',
            at: _at.subtract(const Duration(hours: 3))),
        _deposit(id: 'q_done', operationId: 'op-done', status: 'success'),
        _deposit(
            id: 'q_elsewhere',
            operationId: 'op-elsewhere',
            wallet: '0x0000000000000000000000000000000000000001'),
        _deposit(id: 'q_big', operationId: 'op-big', usd: '25.00'),
        _deposit(),
      ];
      final marked = VenueArrivals.predictionsArrived(rows,
          wallet: _wallet.toUpperCase().replaceFirst('0X', '0x'),
          usd: 4.673137,
          at: _at.add(const Duration(minutes: 4)));
      expect(marked?.id, 'q_direct');
      expect(VenueArrivals.arrived(rows.last), isTrue);
      for (final other in rows.take(4)) {
        expect(VenueArrivals.arrived(other), isFalse, reason: other.id);
      }
      // One arrival marks one row: nothing else fits a second time.
      expect(
          VenueArrivals.predictionsArrived(rows,
              wallet: _wallet,
              usd: 4.673137,
              at: _at.add(const Duration(minutes: 5))),
          isNull);
    });

    test(
        'the Activity journey shows the arrival done; the row keeps '
        'Orchestra\'s status', () {
      final row = _deposit(id: 'ord_direct');
      final running = MoveSteps.ofRow(row);
      expect(running.steps.single.status, MoneyStepStatus.running);
      final arrived = MoveSteps.ofRow(row, arrived: true);
      expect(arrived.steps.single.status, MoneyStepStatus.done);
      expect(row.status, 'exchanging');
      // A failed order stays failed whatever was seen.
      expect(
          MoveSteps.ofRow(row.copyWith(status: 'refunded'), arrived: true)
              .steps
              .single
              .status,
          MoneyStepStatus.failed);
    });
  });

  group('a move into Investing from the Move sheet (no order run)', () {
    test(
        'the venue\'s ledger credit marks the Bitcoin deposit\'s row arrived: '
        'same account, close amount, recent, still on its way', () async {
      final rows = [
        _investing(id: 'ord_old', operationId: 'op-old',
            at: _at.subtract(const Duration(hours: 2))),
        _investing(id: 'ord_done', operationId: 'op-done', status: 'success'),
        _investing(
            id: 'ord_elsewhere',
            operationId: 'op-elsewhere',
            account: '0x0000000000000000000000000000000000000002'),
        _investing(id: 'ord_big', operationId: 'op-big', usd: '80.00'),
        _investing(),
      ];
      // The live frame on the venue's user socket (never the history one).
      final ws = HyperliquidWebSocket(url: 'wss://example.invalid');
      addTearDown(ws.dispose);
      final frames = <HlLedgerUpdatesMessage>[];
      final sub = ws.messages.listen((m) {
        if (m is HlLedgerUpdatesMessage) frames.add(m);
      }, onError: (Object _) {});
      addTearDown(sub.cancel);
      ws.debugReceive('{"channel":"userNonFundingLedgerUpdates","data":'
          '{"user":"$_hl","nonFundingLedgerUpdates":[{"time":1,"hash":"0x1",'
          '"delta":{"type":"send","user":"0x00cc","destination":"$_hl",'
          '"token":"USDC","amount":"24.912","usdcValue":"24.912"}}]}}');
      await Future<void>.delayed(Duration.zero);
      expect(frames.single.isSnapshot, isFalse);
      expect(frames.single.credits, [24.912]);

      final marked = VenueArrivals.investingArrived(rows,
          account: _hl.toUpperCase().replaceFirst('0X', '0x'),
          usd: frames.single.credits.single,
          at: _at.add(const Duration(minutes: 3)));
      expect(marked?.id, 'ord_hl');
      expect(VenueArrivals.arrived(rows.last), isTrue);
      for (final other in rows.take(4)) {
        expect(VenueArrivals.arrived(other), isFalse, reason: other.id);
      }
      // The journey shows the arrival done; the row keeps Orchestra's
      // status until it says so.
      final journey =
          MoveSteps.ofRow(rows.last, arrived: VenueArrivals.arrived(rows.last));
      expect(journey.steps.single.status, MoneyStepStatus.done);
      expect(rows.last.status, 'exchanging');
    });

    test('a Dollars deposit is marked the same way', () {
      final row = _investing(id: 'ord_usd', from: 'USDB', usd: '25.00');
      expect(
          VenueArrivals.investingArrived([row],
                  account: _hl, usd: 24.98, at: _at.add(const Duration(minutes: 1)))
              ?.id,
          'ord_usd');
      expect(VenueArrivals.arrived(row), isTrue);
    });

    test(
        'the account read after the credit (cash up, nothing held) is the '
        'same credit: one row marked, never a second', () {
      final first = _investing(id: 'ord_a', operationId: 'op-a', usd: '24.80');
      final second = _investing(id: 'ord_b', operationId: 'op-b', usd: '26.00');
      final rows = [first, second];
      final at = _at.add(const Duration(minutes: 2));
      expect(
          VenueArrivals.investingArrived(rows, account: _hl, usd: 24.9, at: at)
              ?.id,
          'ord_a');
      final rise =
          VenueArrivals.investingCreditBetween(_snap(10, 0), _snap(10, 24.9));
      expect(rise, closeTo(24.9, 1e-9));
      expect(
          VenueArrivals.investingArrived(rows,
              account: _hl, usd: rise!, at: at.add(const Duration(seconds: 5))),
          isNull);
      expect(VenueArrivals.arrived(second), isFalse);
      // Without the socket, the read alone marks it.
      VenueArrivals.debugReset();
      expect(
          VenueArrivals.investingArrived(rows, account: _hl, usd: rise, at: at)
              ?.id,
          'ord_a');
    });

    test('an account read with a position held is never taken as a credit',
        () {
      const position = HlPerpPosition(
        coin: 'BTC',
        szi: 0.001,
        entryPx: 100000,
        positionValue: 100,
        unrealizedPnl: 25,
        returnOnEquity: 0.25,
        liquidationPx: null,
        marginUsed: 100,
        leverageType: 'cross',
        leverageValue: 1,
        maxLeverage: 40,
      );
      expect(
          VenueArrivals.investingCreditBetween(
              _snap(10, 0, positions: [position]),
              _snap(35, 0, positions: [position])),
          isNull);
      // Cash down (a withdrawal) is not a credit either.
      expect(VenueArrivals.investingCreditBetween(_snap(35, 0), _snap(10, 0)),
          isNull);
    });

    test('withdrawals and outgoing sends on the ledger credit nothing', () {
      expect(
          hlLedgerCreditUsd({
            'delta': {'type': 'withdraw', 'usdc': '5'}
          }, _hl),
          isNull);
      expect(
          hlLedgerCreditUsd({
            'delta': {
              'type': 'send',
              'user': _hl,
              'destination': '0x0000000000000000000000000000000000000003',
              'token': 'USDC',
              'amount': '5'
            }
          }, _hl),
          isNull);
      expect(
          hlLedgerCreditUsd({
            'delta': {'type': 'deposit', 'usdc': '12.5'}
          }, _hl),
          12.5);
      expect(
          hlLedgerCreditUsd({
            'delta': {
              'type': 'internalTransfer',
              'user': '0x0000000000000000000000000000000000000004',
              'destination': _hl,
              'usdc': '7.25'
            }
          }, _hl),
          7.25);
    });
  });

  test('longer than expected: 1.5x the estimate, else 90 s', () {
    expect(slowMoveAfter(), const Duration(seconds: 90));
    expect(slowMoveAfter(estimate: const Duration(minutes: 5)),
        const Duration(minutes: 7, seconds: 30));
    expect(moveIsSlow(_at, _at.add(const Duration(seconds: 89))), isFalse);
    expect(moveIsSlow(_at, _at.add(const Duration(seconds: 90))), isTrue);
    expect(
        moveIsSlow(_at, _at.add(const Duration(seconds: 100)),
            estimate: const Duration(minutes: 1, seconds: 20)),
        isFalse);
    expect(
        moveIsSlow(_at, _at.add(const Duration(seconds: 120)),
            estimate: const Duration(minutes: 1, seconds: 20)),
        isTrue);
  });
}

class _Rows implements SettlementActivityRows {
  _Rows(this.rows);
  final List<SwapOrder> rows;
  final adopted = <(String, String)>[];
  final expired = <String>[];
  final removed = <String>[];

  @override
  List<SwapOrder> pendingLinked() => rows;

  @override
  Future<void> adopt(SwapOrder row, String orderId) async =>
      adopted.add((row.id, orderId));

  @override
  Future<void> markExpired(SwapOrder row) async => expired.add(row.id);

  @override
  Future<void> remove(SwapOrder row) async => removed.add(row.id);
}
