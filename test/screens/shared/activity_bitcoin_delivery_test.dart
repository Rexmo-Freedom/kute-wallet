// Money coming home from Investments to Bitcoin is one Activity row: the
// move's (or the withdrawal's) own row, never a "Received ₿" Spark row
// beside it.
//
// The founder's report this pins: "Duplicated entries on double receives
// (one spark one withdrawal on transaction list) in deposit from
// investing". A move out of Investing to Bitcoin rides Circle CCTP and
// routinely lands well past the hour the receive matcher allowed after the
// row started; a Predictions leg was held to the two percent and half an
// hour of an unowned conversion; a row whose bitcoin figure was still 0
// claimed nothing even after the delivery reconciler had matched its
// receive; and the reconciler's match was never read by Activity at all.

import 'dart:io';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/helpers/swap_activity.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/screens/shared/multi_source_move_activity.dart';
import 'package:kute/services/orchestra/own_bitcoin_deliveries.dart';
import 'package:kute/screens/shared/transactions_builder.dart';
import 'package:kute/services/one_balance/multi_source_move.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart'
    show VenueCashFor;
import 'package:kute/services/one_balance/venue_funder.dart'
    show VenueCashDestination;
import 'package:kute/services/orchestra/own_spark_arrivals.dart';
import 'package:kute/services/orchestra/venue_arrivals.dart'
    show OrchestraOrderIds;
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode;
import 'package:kute/services/polymarket_spark_txs_service.dart';

const _self = 'sp1selfaddress';
final _t0 = DateTime.utc(2026, 10, 26, 12);

// The same Spark key under both spellings (address_guard_test.dart).
const _sparkG =
    'spark1pgssy7d7vel0nh9m4326qc54e6rskpczn07dktww9rv4nu5ptvt0s9uc489gg2';
const _spG = 'sp1pgssy7d7vel0nh9m4326qc54e6rskpczn07dktww9rv4nu5ptvt0s9ucez8h3s';

SwapOrderTransaction _swap(
  String id, {
  String coinFrom = 'USDC',
  String networkFrom = 'HYPERCORE',
  String coinTo = 'BTC',
  String networkTo = 'SPARK',
  String depositAmount = '20.00',
  required String withdrawalAmount,
  String status = 'exchanging',
  Duration after = Duration.zero,
  String? operationId,
  String withdrawalAddress = _self,
}) {
  final ts = _t0.add(after);
  return SwapOrderTransaction(
    id: id,
    timestamp: ts,
    isConfirmed: false,
    details: SwapOrder(
      id: id,
      coinFrom: coinFrom,
      networkFrom: networkFrom,
      coinTo: coinTo,
      networkTo: networkTo,
      depositAddress: 'deposit-$id',
      depositAmount: depositAmount,
      withdrawalAmount: withdrawalAmount,
      status: status,
      timestamp: ts.millisecondsSinceEpoch,
      withdrawalAddress: withdrawalAddress,
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

UsdbTokenTransaction _dollars(String id, double usd, Duration after,
        {required breez.PaymentType type}) =>
    UsdbTokenTransaction(
      id: id,
      timestamp: _t0.add(after),
      isConfirmed: true,
      details: breez.Payment(
        id: id,
        paymentType: type,
        status: breez.PaymentStatus.completed,
        amount: BigInt.from((usd * 1e6).round()),
        fees: BigInt.zero,
        timestamp:
            BigInt.from(_t0.add(after).millisecondsSinceEpoch ~/ 1000),
        method: breez.PaymentMethod.token,
        details: breez.PaymentDetails.token(
          metadata: breez.TokenMetadata(
            identifier: 'btkn1usdb',
            issuerPublicKey: 'issuer',
            name: 'USDB',
            ticker: 'USDB',
            decimals: 6,
            maxSupply: BigInt.zero,
            isFreezable: false,
          ),
          txHash: 'tx-$id',
          txType: breez.TokenTransactionType.transfer,
        ),
      ),
    );

MultiSourceMoveLeg _leg(OneBalanceVenue venue, String op,
        {double usd = 20, bool direct = true}) =>
    MultiSourceMoveLeg(
      venue: venue,
      usd: usd,
      arrivingUsd: usd * 0.99,
      route: direct ? VenueCashRoute.direct : VenueCashRoute.viaDollars,
      ok: true,
      at: _t0,
      operationId: op,
    );

MultiSourceMove _move(
  List<MultiSourceMoveLeg> legs, {
  String forAction = VenueCashFor.buyBitcoin,
  VenueCashDestination destination = VenueCashDestination.bitcoin,
  double dollarsUsd = 0,
  String? finalOp,
}) =>
    MultiSourceMove(
      id: 'msm_1',
      walletId: 'spending',
      forAction: forAction,
      destination: destination,
      totalUsd: legs.fold<double>(0, (s, l) => s + l.usd) + dollarsUsd,
      dollarsUsd: dollarsUsd,
      createdAt: _t0,
      legs: legs,
      finalOperationId: finalOp,
    );

const _kinds = {
  'ord_hl': SwapActivityKind.investingWithdrawal,
  'ord_pm': SwapActivityKind.predictionsWithdrawal,
  'ord_hl_usd': SwapActivityKind.investingWithdrawal,
  'ord_buy': SwapActivityKind.dollarWithdrawal,
  'ord_fund': SwapActivityKind.predictionsDeposit,
};

/// One surface's rows, newest first, as `TransactionList` assembles them.
List<BaseTransaction> _surface(
  List<BaseTransaction> rows, {
  List<MultiSourceMove> moves = const [],
  bool onlyUsdb = false,
  Map<String, OrchestraDeliveryLink>? links = const {},
  Set<String> own = const {_self},
}) {
  final sorted = [...rows]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  return assembleActivityRows(
    sorted,
    ownAddresses: own,
    isHardwareOrWatchOnly: false,
    onlyUsdb: onlyUsdb,
    classify: (o) => _kinds[o.id] ?? classifySwapActivity(o),
    moves: moves,
    walletId: 'spending',
    deliveryLinks: links,
  );
}

List<String> _ids(List<BaseTransaction> rows) => [for (final r in rows) r.id];

void main() {
  setUp(() {
    OwnSparkArrivals.reset();
    OrchestraOrderIds.debugReset();
  });

  group('one move from Investing to Bitcoin', () {
    // The CCTP leg: Orchestra's order, its delivery landing 75 minutes
    // after the move started (past the old hour).
    final hl = _swap('ord_hl',
        withdrawalAmount: '0.00019900',
        status: 'success',
        operationId: 'op-hl');
    final arrived = _received('rx_hl', 19900, const Duration(minutes: 75));
    final move = _move([_leg(OneBalanceVenue.investing, 'op-hl')]);

    test('is the move\'s one row on Bitcoin, its receive inside it', () {
      final rows = _surface([hl, arrived], moves: [move]);
      expect(_ids(rows), ['msm_1']);
      final parent = rows.single as MultiSourceMoveTransaction;
      expect(parent.legRows.map((r) => r.id), ['ord_hl']);
      expect(parent.complete, isTrue);
      expect(multiSourceMoveBitcoin(parent), closeTo(0.000199, 1e-9));
    });

    test('without a move record the withdrawal is still one row', () {
      expect(_ids(_surface([hl, arrived])), ['ord_hl']);
    });

    test('the Dollars ledger lists the move once and never the receive', () {
      expect(_ids(_surface([hl, arrived], moves: [move], onlyUsdb: true)),
          ['msm_1']);
    });

    test('a delivery landing within the hour still folds in', () {
      final early = _received('rx_hl', 19800, const Duration(minutes: 6));
      expect(_ids(_surface([hl, early], moves: [move])), ['msm_1']);
    });

    test('an estimate up to ten percent off still claims its receive', () {
      final estimate = _swap('ord_hl',
          withdrawalAmount: '0.00021000', operationId: 'op-hl');
      final landed = _received('rx_hl', 19300, const Duration(minutes: 90));
      expect(_ids(_surface([estimate, landed], moves: [move])), ['msm_1']);
    });
  });

  group('a leg whose bitcoin figure is not known yet', () {
    final pending = _swap('ord_hl', withdrawalAmount: '0', operationId: 'op-hl');
    final arrived = _received('rx_hl', 19900, const Duration(minutes: 40));
    final move = _move([_leg(OneBalanceVenue.investing, 'op-hl')]);

    test('claims nothing by amount: the receive stays until it is linked', () {
      expect(_ids(_surface([pending, arrived], moves: [move])),
          ['rx_hl', 'msm_1']);
    });

    test('the reconciler\'s link folds it in, by the row\'s operation', () {
      // Linked while the row still had its quote id.
      final links = {
        'rx_hl': const OrchestraDeliveryLink(
            orderId: 'q_hl', operationId: 'op-hl'),
      };
      expect(_ids(_surface([pending, arrived], moves: [move], links: links)),
          ['msm_1']);
    });

    test('or by the order its quote became', () {
      OrchestraOrderIds.record('q_hl', 'ord_hl');
      final noOp = _swap('ord_hl', withdrawalAmount: '0');
      final links = {'rx_hl': const OrchestraDeliveryLink(orderId: 'q_hl')};
      expect(_ids(_surface([noOp, arrived], links: links)), ['ord_hl']);
    });

    test('a link to a row that is not listed hides nothing', () {
      final links = {
        'rx_hl': const OrchestraDeliveryLink(
            orderId: 'ord_gone', operationId: 'op-gone'),
      };
      expect(_ids(_surface([arrived], links: links)), ['rx_hl']);
    });
  });

  group('a move from Investing and Predictions to Bitcoin', () {
    final hl = _swap('ord_hl',
        withdrawalAmount: '0.00019900',
        status: 'success',
        operationId: 'op-hl');
    // The Predictions leg's figure is the quote's estimate; it lands 3%
    // under it, 45 minutes later.
    final pm = _swap('ord_pm',
        coinFrom: 'USDC.e',
        networkFrom: 'POLYGON',
        withdrawalAmount: '0.00010000',
        operationId: 'op-pm',
        after: const Duration(seconds: 5));
    final rxHl = _received('rx_hl', 19900, const Duration(minutes: 80));
    final rxPm = _received('rx_pm', 9700, const Duration(minutes: 45));
    final move = _move([
      _leg(OneBalanceVenue.investing, 'op-hl'),
      _leg(OneBalanceVenue.predictions, 'op-pm', usd: 10),
    ]);

    test('is one row, both legs inside it, neither receive beside it', () {
      final rows = _surface([hl, pm, rxHl, rxPm], moves: [move]);
      expect(_ids(rows), ['msm_1']);
      final parent = rows.single as MultiSourceMoveTransaction;
      expect(parent.legRows.map((r) => r.id),
          unorderedEquals(['ord_hl', 'ord_pm']));
      expect(parent.complete, isFalse,
          reason: 'the Predictions order has not reported its end yet');
    });

    test('each leg claims its own receive, never both one', () {
      final claimed = ownBitcoinDeliveryReceives(
        [hl, pm],
        [rxHl, rxPm],
        ownAddresses: const {_self},
        classify: (o) => _kinds[o.id]!,
      );
      expect(claimed, {'rx_hl': 'ord_hl', 'rx_pm': 'ord_pm'});
    });
  });

  group('the receive lands before the move knows its leg', () {
    final hl = _swap('ord_hl',
        withdrawalAmount: '0.00019900',
        status: 'success',
        operationId: 'op-hl');
    final arrived = _received('rx_hl', 19900, const Duration(minutes: 20));

    test('it stands behind the order\'s row, then behind the move\'s', () {
      // Started, no leg recorded yet: the order is its own row.
      final started = _move(const []);
      expect(_ids(_surface([hl, arrived], moves: [started])), ['ord_hl']);
      // The leg is recorded: one row for the move, the receive still in.
      final recorded = started.copyWith(
          legs: [_leg(OneBalanceVenue.investing, 'op-hl')]);
      expect(_ids(_surface([hl, arrived], moves: [recorded])), ['msm_1']);
    });
  });

  group('a restart keeps the link', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('activity_bitcoin_delivery');
      Hive.init(dir.path);
      await Hive.openBox<String>('orchestra_delivery_spark_txs');
    });

    tearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('the stored link is read back and folds the receive in', () async {
      PolymarketSparkTxsService.tagOrchestraDelivery('rx_hl',
          orderId: 'q_hl', operationId: 'op-hl');
      // An older tag names no row: still a delivery for analytics, but
      // nothing for Activity to fold into.
      PolymarketSparkTxsService.tagOrchestraDelivery('rx_old');
      await Hive.close();
      Hive.init(dir.path);
      await Hive.openBox<String>('orchestra_delivery_spark_txs');

      expect(PolymarketSparkTxsService.orchestraDeliverySnapshot(),
          {'rx_hl', 'rx_old'});
      final links = PolymarketSparkTxsService.orchestraDeliveryLinks();
      expect(links.keys, ['rx_hl']);
      expect(links['rx_hl']!.operationId, 'op-hl');

      // The row moved from its quote id to the order id meanwhile, and its
      // bitcoin figure is still unknown: the stored link alone folds it.
      final hl = _swap('ord_hl', withdrawalAmount: '0', operationId: 'op-hl');
      final arrived = _received('rx_hl', 19900, const Duration(minutes: 30));
      final move = _move([_leg(OneBalanceVenue.investing, 'op-hl')]);
      expect(_ids(_surface([hl, arrived], moves: [move], links: null)),
          ['msm_1']);
    });
  });

  group('money from outside keeps its row', () {
    final hl = _swap('ord_hl',
        withdrawalAmount: '0.00019900',
        status: 'success',
        operationId: 'op-hl');
    final move = _move([_leg(OneBalanceVenue.investing, 'op-hl')]);
    final delivery = _received('rx_hl', 19900, const Duration(minutes: 30));

    test('another amount, the same hour', () {
      final gift = _received('rx_gift', 50000, const Duration(minutes: 31),
          type: SparkTransactionType.lightning);
      expect(_ids(_surface([hl, delivery, gift], moves: [move])),
          ['rx_gift', 'msm_1']);
    });

    test('the same amount twice: only one is the delivery', () {
      final twin = _received('rx_twin', 19900, const Duration(hours: 3));
      expect(_ids(_surface([hl, delivery, twin], moves: [move])),
          ['rx_twin', 'msm_1']);
    });

    test('the same amount before the move started', () {
      final before = _received('rx_before', 19900, const Duration(minutes: -30));
      expect(_ids(_surface([hl, before], moves: [move])), ['msm_1', 'rx_before']);
    });

    test('a genuine receive with no move or withdrawal beside it', () {
      expect(_ids(_surface([delivery])), ['rx_hl']);
    });

    test('a failed withdrawal claims nothing', () {
      final failed = _swap('ord_hl',
          withdrawalAmount: '0.00019900',
          status: 'refunded',
          operationId: 'op-hl');
      expect(_ids(_surface([failed, delivery])), ['rx_hl', 'ord_hl']);
    });

    test('a withdrawal to someone else\'s Spark address claims nothing', () {
      final foreign = _swap('ord_hl',
          withdrawalAmount: '0.00019900',
          status: 'success',
          withdrawalAddress: _sparkG);
      expect(_ids(_surface([foreign, delivery])), ['rx_hl', 'ord_hl']);
    });

    test('a bitcoin delivery on-chain is never a Spark receive', () {
      final ledger = _swap('ord_hl',
          networkTo: 'BITCOIN',
          withdrawalAmount: '0.00019900',
          status: 'success',
          withdrawalAddress: 'bc1qledger');
      expect(_ids(_surface([ledger, delivery])), ['rx_hl', 'ord_hl']);
    });
  });

  group('either spelling of the own Spark address', () {
    test('settlesToOwnAddress decodes sp1 and spark1 alike', () {
      expect(settlesToOwnAddress(_sparkG, const {_spG}), isTrue);
      expect(settlesToOwnAddress(_spG.toUpperCase(), const {_spG}), isTrue);
      expect(settlesToOwnAddress('bc1qother', const {_spG}), isFalse);
      expect(settlesToOwnAddress('', const {_spG}), isFalse);
    });

    test('a one-time receive settling to the other spelling is one row', () {
      // Not a venue withdrawal: only the settle address proves it is ours.
      final receive = _swap('ord_rx',
          coinFrom: 'ETH',
          networkFrom: 'ETHEREUM',
          withdrawalAmount: '0.00050000',
          status: 'success',
          withdrawalAddress: _sparkG);
      final landed = _received('rx_eth', 50000, const Duration(minutes: 50));
      expect(_ids(_surface([receive, landed], own: const {_spG})), ['ord_rx']);
    });
  });

  group('a move to Bitcoin through Dollars', () {
    // Investing home to Dollars (landing 50 minutes on), then the purchase.
    final home = _swap('ord_hl_usd',
        coinTo: kOrchestraUsdAssetCode,
        withdrawalAmount: '19.90',
        status: 'success',
        operationId: 'op-hl');
    final landedUsd = _dollars('usd_in', 19.90, const Duration(minutes: 50),
        type: breez.PaymentType.receive);
    final buy = _swap('ord_buy',
        coinFrom: kOrchestraUsdAssetCode,
        networkFrom: 'SPARK',
        depositAmount: '19.90',
        withdrawalAmount: '0.00019700',
        status: 'success',
        operationId: 'op-buy',
        after: const Duration(minutes: 55));
    final spentUsd = _dollars('usd_out', 19.90, const Duration(minutes: 55),
        type: breez.PaymentType.send);
    final landedBtc = _received('rx_btc', 19700, const Duration(minutes: 56));
    final move = _move(
        [_leg(OneBalanceVenue.investing, 'op-hl', direct: false)],
        finalOp: 'op-buy');
    final all = [home, landedUsd, buy, spentUsd, landedBtc];

    test('is one row on Dollars', () {
      expect(_ids(_surface(all, moves: [move], onlyUsdb: true)), ['msm_1']);
    });

    test('is one row on Bitcoin', () {
      final rows = _surface(all, moves: [move]);
      expect(_ids(rows), ['msm_1']);
      expect((rows.single as MultiSourceMoveTransaction).complete, isTrue);
    });
  });

  group('a move\'s own step recorded under its quote id', () {
    // Dollars into Predictions for a bet: the funder returned no operation
    // id, so the move kept the quote id while the row moved to the order.
    final fund = _swap('ord_fund',
        coinFrom: kOrchestraUsdAssetCode,
        networkFrom: 'SPARK',
        coinTo: 'USDC.e',
        networkTo: 'POLYGON',
        withdrawalAmount: '19.80',
        status: 'success',
        operationId: 'op-fund',
        withdrawalAddress: '0xsafe');
    final move = _move([
      _leg(OneBalanceVenue.investing, 'op-hl', direct: false),
    ], destination: VenueCashDestination.predictions,
        forAction: VenueCashFor.predictions, finalOp: 'q_fund');
    final home = _swap('ord_hl_usd',
        coinTo: kOrchestraUsdAssetCode,
        withdrawalAmount: '19.90',
        status: 'success',
        operationId: 'op-hl');

    final stored = settlementQuoteIdOf;
    tearDown(() => settlementQuoteIdOf = stored);

    test('finds its row through the settlement record, after a restart', () {
      settlementQuoteIdOf = (op) => op == 'op-fund' ? 'q_fund' : null;
      final rows = _surface([home, fund], moves: [move], onlyUsdb: true);
      expect(_ids(rows), ['msm_1']);
      expect((rows.single as MultiSourceMoveTransaction).isConfirmed, isTrue);
    });

    test('or through the order this session saw the quote become', () {
      settlementQuoteIdOf = (_) => null;
      OrchestraOrderIds.record('q_fund', 'ord_fund');
      expect(_ids(_surface([home, fund], moves: [move], onlyUsdb: true)),
          ['msm_1']);
    });
  });
}
