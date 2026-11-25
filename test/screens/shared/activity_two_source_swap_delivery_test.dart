// A Swap from Dollars to Bitcoin that took money from two places is one
// Activity card, never the move and a "Received ₿" beside it.
//
// The founder's report this pins (11 November 2026, build 106): a Swap paid
// from Predictions cash and Dollars showed "Withdraw ₿35,152" and, as its
// own card, "Received +₿20,900": "a withdrawal transaction causes a spark
// transaction to appear duplicate".
//
// What went wrong: both sources go to Bitcoin at once, so two deliveries
// land within the minute. The Dollars one is there in seconds, and its
// order is reported done before the delivery reconciler looks. The
// reconciler then had only the Predictions leg still waiting and one
// receive on the table, the Dollars leg's: 68% of what the Predictions leg
// expected, inside the half to five quarters it accepts as the first leg
// of a split payout. It settled the Predictions leg on it and stored that
// link. Activity trusts a link, so the Dollars receive went to the
// Predictions leg, and when the Predictions delivery arrived no row had
// room for it.
//
// The fix has two halves (own_bitcoin_deliveries.dart):
//  * the reconciler never offers a row a receive that fits another of the
//    wallet's deliveries better ([receivesSpokenFor]);
//  * a link already crossed (stored by the earlier build) is read as what
//    it is ([crossedDeliveryLinks]): the receive goes to the row whose
//    exact figure it is, the other row claims its own by amount and time.
//
// No transfer id ties an Orchestra order to the Spark payment that
// delivered it (the order's status carries none once it is done), so this
// is amount and time, held tight: an exact figure, the wallet's own order,
// its own window. Money from outside keeps its row.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/helpers/swap_activity.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/background_sync_provider.dart'
    show orchestraRowAwaitsDelivery, rowWaitingAgainAfterCrossedLink;
import 'package:kute/screens/shared/all_activity.dart';
import 'package:kute/screens/shared/multi_source_move_activity.dart';
import 'package:kute/screens/shared/transactions_builder.dart';
import 'package:kute/services/one_balance/money_steps.dart'
    show MoneyStepStatus;
import 'package:kute/services/one_balance/move_steps.dart';
import 'package:kute/services/one_balance/multi_source_move.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart'
    show VenueCashFor;
import 'package:kute/services/one_balance/venue_funder.dart'
    show VenueCashDestination;
import 'package:kute/services/orchestra/own_bitcoin_deliveries.dart';
import 'package:kute/services/orchestra/own_spark_arrivals.dart';
import 'package:kute/services/orchestra/venue_arrivals.dart'
    show OrchestraOrderIds;
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode;
import 'package:kute/services/polymarket_spark_txs_service.dart';
import 'package:kute/services/transaction_cache_codec.dart';

const _self = 'sp1selfaddress';
final _t0 = DateTime.utc(2026, 11, 11, 16, 52);

SwapOrderTransaction _order(
  String id, {
  required String coinFrom,
  required String networkFrom,
  required String depositAmount,
  required String withdrawalAmount,
  required String operationId,
  String status = 'success',
  Duration after = Duration.zero,
}) {
  final ts = _t0.add(after);
  return SwapOrderTransaction(
    id: id,
    timestamp: ts,
    isConfirmed: status == 'success' || status == 'settled',
    details: SwapOrder(
      id: id,
      coinFrom: coinFrom,
      networkFrom: networkFrom,
      coinTo: 'BTC',
      networkTo: 'SPARK',
      depositAddress: 'deposit-$id',
      depositAmount: depositAmount,
      withdrawalAmount: withdrawalAmount,
      status: status,
      timestamp: ts.millisecondsSinceEpoch,
      withdrawalAddress: _self,
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: '',
      provider: 'Orchestra',
      walletId: 'spending',
      operationId: operationId,
    ),
  );
}

/// The Dollars leg: `spark:USDB → spark:BTC`, $11.73 for 14,252 sats. Its
/// order is done within seconds.
SwapOrderTransaction _dollarsLeg({
  String withdrawalAmount = '0.00014252',
  String status = 'success',
}) =>
    _order('ord_usd',
        coinFrom: kOrchestraUsdAssetCode,
        networkFrom: 'SPARK',
        depositAmount: '11.73',
        withdrawalAmount: withdrawalAmount,
        status: status,
        operationId: 'op-usd',
        after: const Duration(seconds: 4));

/// The Predictions leg: `polygon:USDC.e → spark:BTC`, $17.20, the quote's
/// 21,100 sats until its order reports the 20,900 it delivered.
SwapOrderTransaction _predictionsLeg({
  String withdrawalAmount = '0.00020900',
  String status = 'success',
}) =>
    _order('ord_pm',
        coinFrom: 'USDC',
        networkFrom: 'POLYGON',
        depositAmount: '17.20',
        withdrawalAmount: withdrawalAmount,
        status: status,
        operationId: 'op-pm',
        after: const Duration(seconds: 12));

SparkTransaction _received(String id, int sats, Duration after,
        {SparkTransactionType type = SparkTransactionType.spark}) =>
    SparkTransaction.fromCache(
      id: id,
      timestamp: _t0.add(after),
      isConfirmed: true,
      amountSats: sats,
      sparkType: type,
      direction: TransactionType.received,
      pending: false,
    );

final _rxUsd = _received('rx_usd', 14252, const Duration(seconds: 6));
final _rxPm = _received('rx_pm', 20900, const Duration(seconds: 50));

/// The Swap as the app records it: the Predictions leg straight to
/// Bitcoin, Dollars' own part bought beside it.
MultiSourceMove _swapMove() {
  final legs = MultiSourceMove(
    id: 'msm_1',
    walletId: 'spending',
    forAction: VenueCashFor.buyBitcoin,
    destination: VenueCashDestination.bitcoin,
    totalUsd: 28.93,
    dollarsUsd: 11.73,
    createdAt: _t0,
    legs: [
      MultiSourceMoveLeg(
        venue: OneBalanceVenue.predictions,
        usd: 17.20,
        arrivingUsd: 17.03,
        route: VenueCashRoute.direct,
        ok: true,
        at: _t0,
        operationId: 'op-pm',
      ),
    ],
  );
  return legs.copyWith(
    initialDollarsOperationId: 'op-usd',
    initialDollarsSentUsd: 11.73,
    parallelPurchase: true,
    // Dollars' own purchase, sent: its step carries its operation.
    steps: MoveSteps.initialDollarsState(
        MoveSteps.withInitialDollars(MoveSteps.of(legs), 11.73),
        MoneyStepStatus.running,
        operationId: 'op-usd'),
  );
}

const _kinds = {
  'ord_usd': SwapActivityKind.dollarWithdrawal,
  'ord_pm': SwapActivityKind.predictionsWithdrawal,
};

SwapActivityKind _classify(SwapOrder o) =>
    _kinds[o.id] ?? classifySwapActivity(o);

/// The link the earlier build stored: the Dollars leg's receive, tied to
/// the Predictions leg while it expected the quote's 21,100 sats.
const _crossedLink = {
  'rx_usd': OrchestraDeliveryLink(
      orderId: 'ord_pm', operationId: 'op-pm', expectedSats: 21100),
};

/// One list's rows, newest first: the Bitcoin tab's ledger (default), the
/// dollar ledger ([onlyUsdb]: the Dollars activity and the Portfolio's),
/// or every account at once ([allAccounts]: the Bitcoin home's Latest and
/// All activity).
List<BaseTransaction> _surface(
  List<BaseTransaction> rows, {
  bool onlyUsdb = false,
  bool allAccounts = false,
  Map<String, OrchestraDeliveryLink>? links = const {},
  List<MultiSourceMove>? moves,
}) {
  final sorted = [...rows]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  return assembleActivityRows(
    sorted,
    ownAddresses: const {_self},
    isHardwareOrWatchOnly: false,
    onlyUsdb: onlyUsdb,
    allAccounts: allAccounts,
    keepVenueMoves: allAccounts,
    classify: _classify,
    moves: moves ?? [_swapMove()],
    walletId: 'spending',
    deliveryLinks: links,
  );
}

List<String> _ids(List<BaseTransaction> rows) => [for (final r in rows) r.id];

/// The Bitcoin home's cards: every account's rows, in the Bitcoin scope.
List<String> _homeLatest(List<BaseTransaction> rows,
        {Map<String, OrchestraDeliveryLink>? links = const {}}) =>
    [
      for (final e in activityInScope(
          mergeAllActivity(
              walletRows: _surface(rows, allAccounts: true, links: links)),
          ActivityScope.bitcoin,
          classify: _classify))
        e.tx!.id,
    ];

void main() {
  setUp(() {
    OwnSparkArrivals.reset();
    OrchestraOrderIds.debugReset();
  });

  group('both deliveries landed', () {
    final rows = <BaseTransaction>[
      _dollarsLeg(),
      _predictionsLeg(),
      _rxUsd,
      _rxPm,
    ];

    test('the Bitcoin home shows one card, ₿35,152, no Received beside it',
        () {
      expect(_homeLatest(rows), ['msm_1']);
      final card = _surface(rows, allAccounts: true).single
          as MultiSourceMoveTransaction;
      expect(card.complete, isTrue);
      expect(multiSourceMoveBitcoin(card), closeTo(0.00035152, 1e-10));
      expect(card.legRows.map((r) => r.id),
          unorderedEquals(['ord_usd', 'ord_pm']));
    });

    test('and so does every other list', () {
      expect(_ids(_surface(rows)), ['msm_1'], reason: 'the Bitcoin tab');
      expect(_ids(_surface(rows, allAccounts: true)), ['msm_1'],
          reason: 'All activity');
      expect(_ids(_surface(rows, onlyUsdb: true)), ['msm_1'],
          reason: 'the Dollars activity and the Portfolio\'s');
    });

    test('each leg claims its own receive', () {
      expect(
        ownBitcoinDeliveryReceives(
          [_dollarsLeg(), _predictionsLeg()],
          [_rxUsd, _rxPm],
          ownAddresses: const {_self},
          classify: _classify,
        ),
        {'rx_usd': 'ord_usd', 'rx_pm': 'ord_pm'},
      );
    });
  });

  group('while the Predictions leg is still on its way', () {
    final waiting =
        _predictionsLeg(withdrawalAmount: '0.00021100', status: 'exchanging');

    test('one card: the Dollars receive is inside the move', () {
      final rows = <BaseTransaction>[_dollarsLeg(), waiting, _rxUsd];
      expect(_homeLatest(rows), ['msm_1']);
      expect(_ids(_surface(rows)), ['msm_1']);
      final card = _surface(rows).single as MultiSourceMoveTransaction;
      expect(card.complete, isFalse);
    });

    test('and when its delivery lands before its order says so', () {
      final rows = <BaseTransaction>[_dollarsLeg(), waiting, _rxUsd, _rxPm];
      expect(_homeLatest(rows), ['msm_1']);
    });
  });

  group('the reconciler settles a leg on its own delivery only', () {
    final waiting =
        _predictionsLeg(withdrawalAmount: '0.00021100', status: 'exchanging');
    // The Dollars order is done and nothing is linked to it yet.
    final dollars = ownDeliveryFigureOf(_dollarsLeg().details, linked: {})!;

    test('the Dollars leg knows its figure and waits for its receive', () {
      expect(dollars.rowId, 'ord_usd');
      expect(dollars.sats, 14252);
      // Once a receive is linked to it, it speaks for nothing more.
      expect(
          ownDeliveryFigureOf(_dollarsLeg().details, linked: {'op-usd'}),
          isNull);
      // A leg that failed, or one paying someone else, never does.
      expect(
          ownDeliveryFigureOf(_dollarsLeg(status: 'refunded').details,
              linked: {}),
          isNull);
      expect(
          ownDeliveryFigureOf(
              _dollarsLeg().details.copyWith(activityDirection: 'send'),
              linked: {}),
          isNull);
    });

    test('alone, the Predictions leg would take the Dollars receive', () {
      // What the earlier build did: 14,252 of an expected 21,100 reads as
      // the first leg of a split payout.
      expect(
          reconcilerDeliveryLegs(
              targetSats: 21100,
              rowAt: waiting.timestamp,
              receives: [_rxUsd])?.map((rx) => rx.id),
          ['rx_usd']);
    });

    test('the Dollars receive is spoken for, so it does not', () {
      final spoken = receivesSpokenFor(
          rowId: 'ord_pm',
          targetSats: 21100,
          others: [dollars],
          receives: [_rxUsd]);
      expect(spoken, {'rx_usd'});
      expect(
          reconcilerDeliveryLegs(
              targetSats: 21100,
              rowAt: waiting.timestamp,
              receives: [
                for (final rx in [_rxUsd])
                  if (!spoken.contains(rx.id)) rx,
              ]),
          isNull);
    });

    test('its own delivery is not spoken for and settles it', () {
      expect(
          receivesSpokenFor(
              rowId: 'ord_pm',
              targetSats: 21100,
              others: [dollars],
              receives: [_rxUsd, _rxPm]),
          {'rx_usd'});
      expect(
          reconcilerDeliveryLegs(
              targetSats: 21100,
              rowAt: waiting.timestamp,
              receives: [_rxPm])?.map((rx) => rx.id),
          ['rx_pm']);
    });

    test('a leg whose figure is not known takes no sibling\'s receive', () {
      expect(
          receivesSpokenFor(
              rowId: 'ord_hl',
              targetSats: 0,
              others: [dollars],
              receives: [_rxUsd, _rxPm]),
          {'rx_usd'});
    });

    test('a receive far from every other figure is left to the row', () {
      final other = _received('rx_other', 17000, const Duration(seconds: 20));
      expect(
          receivesSpokenFor(
              rowId: 'ord_pm',
              targetSats: 21100,
              others: [dollars],
              receives: [other]),
          isEmpty);
    });

    test('a receive outside the other row\'s window is left to the row', () {
      final late = _received('rx_late', 14252, const Duration(hours: 3));
      expect(
          receivesSpokenFor(
              rowId: 'ord_pm',
              targetSats: 21100,
              others: [dollars],
              receives: [late]),
          isEmpty);
    });

    test('two legs expecting the same amount: neither is held back', () {
      final twin = (
        rowId: 'ord_twin',
        sats: 21100,
        rowAt: _t0,
        window: kOwnDeliveryArrivalWindow,
      );
      expect(
          receivesSpokenFor(
              rowId: 'ord_pm',
              targetSats: 21100,
              others: [twin],
              receives: [_rxPm]),
          isEmpty);
    });
  });

  group('a link the earlier build crossed (the founder\'s phone)', () {
    final rows = <BaseTransaction>[
      _dollarsLeg(),
      _predictionsLeg(),
      _rxUsd,
      _rxPm,
    ];

    test('is read as crossed: the receive is the Dollars leg\'s', () {
      final crossed = crossedDeliveryLinks(
          [_dollarsLeg(), _predictionsLeg()], [_rxUsd, _rxPm],
          links: _crossedLink);
      expect(crossed, hasLength(1));
      expect(crossed.single.receiveId, 'rx_usd');
      expect(crossed.single.fromRow, 'ord_pm');
      expect(crossed.single.toRow, 'ord_usd');
      expect(crossed.single.sats, 14252);
      expect(crossed.single.expectedSats, 21100);
    });

    test('one card on every list, no Received +₿20,900', () {
      expect(_homeLatest(rows, links: _crossedLink), ['msm_1']);
      expect(_ids(_surface(rows, links: _crossedLink)), ['msm_1']);
      expect(_ids(_surface(rows, allAccounts: true, links: _crossedLink)),
          ['msm_1']);
      expect(_ids(_surface(rows, onlyUsdb: true, links: _crossedLink)),
          ['msm_1']);
      expect(
        ownBitcoinDeliveryReceives(
          [_dollarsLeg(), _predictionsLeg()],
          [_rxUsd, _rxPm],
          ownAddresses: const {_self},
          classify: _classify,
          links: _crossedLink,
        ),
        {'rx_usd': 'ord_usd', 'rx_pm': 'ord_pm'},
      );
    });

    test('also while the leg still reads the receive it was settled on', () {
      // The reconciler wrote the Dollars receive's figure on the
      // Predictions leg and called it settled.
      final settled =
          _predictionsLeg(withdrawalAmount: '0.00014252', status: 'settled');
      final stuck = <BaseTransaction>[_dollarsLeg(), settled, _rxUsd, _rxPm];
      expect(_homeLatest(stuck, links: _crossedLink), ['msm_1']);
      // Before its own delivery lands, still one card.
      expect(
          _homeLatest([_dollarsLeg(), settled, _rxUsd], links: _crossedLink),
          ['msm_1']);
    });

    test('a link to the right row is left alone', () {
      const right = {
        'rx_usd': OrchestraDeliveryLink(
            orderId: 'ord_usd', operationId: 'op-usd', expectedSats: 14252),
        'rx_pm': OrchestraDeliveryLink(
            orderId: 'ord_pm', operationId: 'op-pm', expectedSats: 21100),
      };
      expect(
          crossedDeliveryLinks(
              [_dollarsLeg(), _predictionsLeg()], [_rxUsd, _rxPm],
              links: right),
          isEmpty);
      expect(_homeLatest(rows, links: right), ['msm_1']);
    });

    test('a payout split across transfers is not a crossed link', () {
      // One withdrawal of 60,000 sats delivered as 39,000 and 21,000,
      // both linked to it, beside a leg of 20,900 still without a receive.
      final big = _order('ord_big',
          coinFrom: kOrchestraUsdAssetCode,
          networkFrom: 'SPARK',
          depositAmount: '49.40',
          withdrawalAmount: '0.00060000',
          operationId: 'op-big');
      final first = _received('rx_first', 39000, const Duration(seconds: 20));
      final rest = _received('rx_rest', 21000, const Duration(seconds: 40));
      const split = {
        'rx_first': OrchestraDeliveryLink(
            orderId: 'ord_big', operationId: 'op-big', expectedSats: 60000),
        'rx_rest': OrchestraDeliveryLink(
            orderId: 'ord_big', operationId: 'op-big', expectedSats: 60000),
      };
      expect(
          crossedDeliveryLinks([big, _predictionsLeg()], [first, rest],
              links: split),
          isEmpty);
    });

    test('a row that has a receive of its own takes nothing over', () {
      // The Dollars leg's delivery is on the list, unlinked and closer to
      // its order than the linked one: the receive linked to the
      // Predictions leg is not the Dollars leg's.
      final other = _received('rx_other', 14252, const Duration(seconds: 5));
      expect(
          crossedDeliveryLinks(
              [_dollarsLeg(), _predictionsLeg()], [_rxUsd, other, _rxPm],
              links: _crossedLink),
          isEmpty);
    });

    test('a row someone else\'s money goes to takes nothing over', () {
      expect(
          crossedDeliveryLinks(
              [_dollarsLeg(), _predictionsLeg()], [_rxUsd, _rxPm],
              links: _crossedLink, owns: (ex) => ex.id != 'ord_usd'),
          isEmpty);
    });
  });

  group('the reconciler puts a crossed link right', () {
    // The Predictions leg as the earlier build left it: settled on the
    // Dollars receive, reading its 14,252 sats.
    final settled =
        _predictionsLeg(withdrawalAmount: '0.00014252', status: 'settled');
    CrossedDeliveryLink crossedFor(SwapOrderTransaction pm) =>
        crossedDeliveryLinks([_dollarsLeg(), pm], [_rxUsd, _rxPm],
                links: _crossedLink,
                owns: (ex) => ex.details.activityDirection != 'send')
            .single;

    test('the leg waits again for what it said it would deliver', () {
      final waiting =
          rowWaitingAgainAfterCrossedLink(settled.details, crossedFor(settled))!;
      expect(waiting.id, 'ord_pm');
      expect(waiting.status, 'exchanging');
      expect(waiting.withdrawalAmount, '0.00021100');
      expect(waiting.shouldPollOrchestra, isTrue);
      // Its own delivery then settles it, on the same pass.
      expect(
          orchestraRowAwaitsDelivery(waiting,
              linked: {'ord_usd', 'op-usd'}, now: _t0),
          isTrue);
      expect(
          reconcilerDeliveryLegs(
              targetSats: orchestraBtcFieldToSats(waiting.withdrawalAmount),
              rowAt: DateTime.fromMillisecondsSinceEpoch(waiting.timestamp),
              receives: [_rxPm])?.map((rx) => rx.id),
          ['rx_pm']);
    });

    test('a leg Orchestra itself reported done keeps its figure', () {
      final done = _predictionsLeg();
      expect(rowWaitingAgainAfterCrossedLink(done.details, crossedFor(done)),
          isNull);
    });

    test('a leg that no longer reads the crossed receive is left alone', () {
      final other =
          _predictionsLeg(withdrawalAmount: '0.00020900', status: 'settled');
      expect(rowWaitingAgainAfterCrossedLink(other.details, crossedFor(other)),
          isNull);
    });

    test('a quote row or an unrecorded expectation is left alone', () {
      final crossed = crossedFor(settled);
      expect(
          rowWaitingAgainAfterCrossedLink(
              settled.details.copyWith(id: 'q_pm'), crossed),
          isNull);
      expect(
          rowWaitingAgainAfterCrossedLink(settled.details, (
            receiveId: crossed.receiveId,
            fromRow: crossed.fromRow,
            toRow: crossed.toRow,
            sats: crossed.sats,
            expectedSats: null,
          )),
          isNull);
    });
  });

  group('money from outside keeps its row', () {
    final legs = <BaseTransaction>[_dollarsLeg(), _predictionsLeg()];

    test('someone sending the same ₿20,900 a few minutes later', () {
      final gift = _received('rx_gift', 20900, const Duration(minutes: 4));
      expect(_homeLatest([...legs, _rxUsd, _rxPm, gift]),
          ['rx_gift', 'msm_1']);
      expect(_homeLatest([...legs, _rxUsd, _rxPm, gift], links: _crossedLink),
          ['rx_gift', 'msm_1']);
    });

    test('someone sending the same ₿14,252 as the Dollars leg', () {
      final gift = _received('rx_gift', 14252, const Duration(minutes: 4));
      expect(_homeLatest([...legs, _rxUsd, _rxPm, gift]),
          ['rx_gift', 'msm_1']);
      expect(_homeLatest([...legs, _rxUsd, _rxPm, gift], links: _crossedLink),
          ['rx_gift', 'msm_1']);
    });

    test('the same amount over Lightning, received before the Swap', () {
      final before = _received('rx_before', 20900,
          const Duration(minutes: -30),
          type: SparkTransactionType.lightning);
      expect(_homeLatest([...legs, _rxUsd, _rxPm, before]),
          ['msm_1', 'rx_before']);
    });

    test('the same amount the next day', () {
      final later = _received('rx_later', 20900, const Duration(hours: 20));
      expect(_homeLatest([...legs, _rxUsd, _rxPm, later]),
          ['rx_later', 'msm_1']);
    });

    test('an unlinked receive is never read as a crossed link', () {
      final gift = _received('rx_gift', 14252, const Duration(minutes: 4));
      expect(
          crossedDeliveryLinks([_dollarsLeg(), _predictionsLeg()], [gift],
              links: const {}),
          isEmpty);
    });
  });

  group('after a restart', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('two_source_swap_delivery');
      Hive.init(dir.path);
      await Hive.openBox<String>('orchestra_delivery_spark_txs');
    });

    tearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    /// The wallet's rows and the move, written to storage and read back
    /// the way a cold start does.
    Future<(List<BaseTransaction>, MultiSourceMove)> reload(
        List<SwapOrderTransaction> orders,
        List<SparkTransaction> receives) async {
      final stored = TransactionCacheCodec.encode(Transaction.empty().copyWith(
        swapOrderTransactions: orders,
        sparkTransactions: receives,
      ));
      final move = _swapMove().toJson();
      await Hive.close();
      Hive.init(dir.path);
      await Hive.openBox<String>('orchestra_delivery_spark_txs');
      final loaded = TransactionCacheCodec.decode(stored)!;
      return (
        loaded.allTransactionsSorted,
        MultiSourceMove.fromJson(move)!,
      );
    }

    test('one card, the receives folded in by amount and time alone',
        () async {
      final (rows, move) = await reload(
          [_dollarsLeg(), _predictionsLeg()], [_rxUsd, _rxPm]);
      expect(rows.whereType<SparkTransaction>(), hasLength(2));
      expect(_ids(_surface(rows, allAccounts: true, links: null, moves: [move])),
          ['msm_1']);
      expect(_ids(_surface(rows, links: null, moves: [move])), ['msm_1']);
    });

    test('one card, with the crossed link read back from storage', () async {
      PolymarketSparkTxsService.tagOrchestraDelivery('rx_usd',
          orderId: 'ord_pm', operationId: 'op-pm', expectedSats: 21100);
      final (rows, move) = await reload(
          [_dollarsLeg(), _predictionsLeg()], [_rxUsd, _rxPm]);
      final stored = PolymarketSparkTxsService.orchestraDeliveryLinks();
      expect(stored.keys, ['rx_usd']);
      expect(stored['rx_usd']!.operationId, 'op-pm');
      expect(_ids(_surface(rows, allAccounts: true, links: null, moves: [move])),
          ['msm_1']);
      expect(_ids(_surface(rows, links: null, moves: [move])), ['msm_1']);
      expect(_ids(_surface(rows, onlyUsdb: true, links: null, moves: [move])),
          ['msm_1']);
    });

    test('someone else\'s ₿20,900 still shows after it', () async {
      PolymarketSparkTxsService.tagOrchestraDelivery('rx_usd',
          orderId: 'ord_pm', operationId: 'op-pm', expectedSats: 21100);
      final gift = _received('rx_gift', 20900, const Duration(minutes: 4));
      final (rows, move) = await reload(
          [_dollarsLeg(), _predictionsLeg()], [_rxUsd, _rxPm, gift]);
      expect(_ids(_surface(rows, allAccounts: true, links: null, moves: [move])),
          ['rx_gift', 'msm_1']);
    });
  });
}
