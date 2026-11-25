// Money coming home is one Activity row: the move's (or the conversion's)
// own row, never the plumbing transfer that delivered it listed beside it
// (founder, 4 November 2026: "Still repeated transaction on receive. It
// shows withdrawal and then shows the Spark receive also, especially with
// investment withdrawals and such. It's not hiding properly.").
//
// Each group reproduces a duplicate the lists still showed, in the
// Bitcoin home's pipeline (assembleActivityRows with allAccounts, the
// venue moves kept), then pins the fix:
//
//  * Investing → Bitcoin over Circle CCTP: Orchestra reports the order done
//    with no bitcoin figure, so no amount could match its receive and only
//    the reconciler's link could fold it, and the reconciler missed it
//    (held past its 90 minutes for screening; or it gave the row the
//    receive closest in time, another leg's delivery). The wallet's own
//    moves now also match their receive by the dollars that left for them
//    (the receive's fiat snapshot), and the reconciler does the same.
//  * Predictions → Bitcoin: the fees took more than the estimate's ten
//    percent on a small withdrawal, or the delivery landed after the
//    amount window: the same dollar match, six hours.
//  * Bitcoin → Dollars: the Dollars arrival landed past half an hour, or
//    under the quote's estimate by more than two percent while the order
//    was under way.
//  * Bitcoin out to Dollars, Investing or Predictions: the Spark (or
//    Dollars) transfer that paid for a conversion is the one its own
//    settlement record names; it folds in by that id before any amount or
//    time match.
//
// And the other side stays: money from outside (another value, before the
// move, an on-chain deposit, a value not known) keeps its row.

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/swap_activity.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/background_sync_provider.dart'
    show orchestraRowAwaitsDelivery;
import 'package:kute/screens/shared/transactions_builder.dart';
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

const _self = 'sp1selfaddress';
final _t0 = DateTime.utc(2026, 11, 3, 12);

/// Bitcoin at $70,000: what a receive was worth when it landed.
const double _price = 70000;
int _sats(double usd) => (usd / _price * 1e8).round();
double? _valued(SparkTransaction rx) => rx.amountSats.abs() / 1e8 * _price;

const _cctpBtc = 'hypercore_cctp_to_btc_v1';

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
  String? routeVersion,
  String? depositAddress,
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
      depositAddress: depositAddress ?? 'deposit-$id',
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
      routeVersion: routeVersion,
    ),
  );
}

/// A Spark transfer as the cache holds it (no payment details).
SparkTransaction _spark(String id, int sats, Duration after,
        {TransactionType direction = TransactionType.received,
        SparkTransactionType type = SparkTransactionType.spark}) =>
    SparkTransaction.fromCache(
      id: id,
      timestamp: _t0.add(after),
      isConfirmed: true,
      amountSats: sats,
      sparkType: type,
      direction: direction,
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
        timestamp: BigInt.from(_t0.add(after).millisecondsSinceEpoch ~/ 1000),
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

MultiSourceMove _moveHome(String op, {double usd = 20}) => MultiSourceMove(
      id: 'msm_1',
      walletId: 'spending',
      forAction: VenueCashFor.withdraw,
      destination: VenueCashDestination.bitcoin,
      totalUsd: usd,
      dollarsUsd: 0,
      createdAt: _t0,
      legs: [
        MultiSourceMoveLeg(
          venue: OneBalanceVenue.investing,
          usd: usd,
          arrivingUsd: usd * 0.99,
          route: VenueCashRoute.direct,
          ok: true,
          at: _t0,
          operationId: op,
        ),
      ],
    );

const _kinds = {
  'ord_hl': SwapActivityKind.investingWithdrawal,
  'ord_hl_usd': SwapActivityKind.investingWithdrawal,
  'ord_pm': SwapActivityKind.predictionsWithdrawal,
  'ord_buy': SwapActivityKind.dollarWithdrawal,
  'ord_sell': SwapActivityKind.dollarDeposit,
  'ord_to_hl': SwapActivityKind.investingDeposit,
  'ord_to_pm': SwapActivityKind.predictionsDeposit,
};

/// The Bitcoin home's rows, newest first (all_activity.dart's pipeline).
List<String> _rows(
  List<BaseTransaction> rows, {
  List<MultiSourceMove> moves = const [],
  ReceivedUsd? receivedUsd = _valued,
  Map<String, String> funding = const {},
}) {
  final sorted = [...rows]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  return [
    for (final r in assembleActivityRows(
      sorted,
      ownAddresses: const {_self},
      isHardwareOrWatchOnly: false,
      onlyUsdb: false,
      allAccounts: true,
      keepVenueMoves: true,
      classify: (o) => _kinds[o.id] ?? classifySwapActivity(o),
      moves: moves,
      walletId: 'spending',
      deliveryLinks: const {},
      receivedUsd: receivedUsd ?? (_) => null,
      fundingPaymentOf: (op) => funding[op],
    ))
      r.id,
  ];
}

void main() {
  setUp(() {
    OwnSparkArrivals.reset();
    OrchestraOrderIds.debugReset();
  });

  group('Investing → Bitcoin over Circle CCTP, no bitcoin figure', () {
    // $20 out of Investing; Orchestra reported the order done and never
    // said how much bitcoin it delivered.
    final hl = _swap('ord_hl',
        withdrawalAmount: '0',
        status: 'success',
        operationId: 'op-hl',
        routeVersion: _cctpBtc);
    final move = _moveHome('op-hl');
    // What landed: $19.70 of bitcoin, 40 minutes on.
    final delivered =
        _spark('rx_hl', _sats(19.70), const Duration(minutes: 40));

    test('reproduced: without a link the receive stood beside the move', () {
      // Nothing to go by but amount and time: the duplicate.
      expect(_rows([hl, delivered], moves: [move], receivedUsd: null),
          ['rx_hl', 'msm_1']);
    });

    test('its receive folds in by the dollars that left for it', () {
      expect(_rows([hl, delivered], moves: [move]), ['msm_1']);
      expect(_rows([hl, delivered]), ['ord_hl']);
    });

    test('held for screening two and a half hours: still one row', () {
      final late = _spark('rx_hl', _sats(19.60), const Duration(minutes: 150));
      expect(_rows([hl, late], moves: [move]), ['msm_1']);
    });

    test('past its day the receive keeps its row', () {
      final days = _spark('rx_hl', _sats(19.70), const Duration(hours: 25));
      expect(_rows([hl, days], moves: [move]), ['rx_hl', 'msm_1']);
    });

    test('money from outside of another value keeps its row', () {
      final gift = _spark('rx_gift', _sats(5), const Duration(minutes: 20),
          type: SparkTransactionType.lightning);
      expect(_rows([hl, delivered, gift], moves: [move]), ['rx_gift', 'msm_1']);
      // Alone, before the delivery lands, the gift is still not taken.
      expect(_rows([hl, gift], moves: [move]), ['rx_gift', 'msm_1']);
    });

    test('the delivery, not a gift of a near value, when both landed', () {
      final gift = _spark('rx_gift', _sats(21.50), const Duration(minutes: 10));
      expect(_rows([hl, gift, delivered], moves: [move]), ['rx_gift', 'msm_1']);
    });

    test('the same value before the move started keeps its row', () {
      final before =
          _spark('rx_before', _sats(19.70), const Duration(minutes: -30));
      expect(_rows([hl, before], moves: [move]), ['msm_1', 'rx_before']);
    });

    test('an on-chain deposit of the same value is never the delivery', () {
      final deposit = _spark(
          'rx_deposit', _sats(19.70), const Duration(minutes: 40),
          type: SparkTransactionType.bitcoin);
      expect(_rows([hl, deposit], moves: [move]), ['rx_deposit', 'msm_1']);
    });

    test('a receive whose dollar value is not known is never matched by it',
        () {
      expect(
          _rows([hl, delivered],
              moves: [move], receivedUsd: (rx) => rx.id == 'rx_hl' ? null : 1),
          ['rx_hl', 'msm_1']);
    });

    test('a failed withdrawal claims nothing', () {
      final failed = _swap('ord_hl',
          withdrawalAmount: '0',
          status: 'refunded',
          operationId: 'op-hl',
          routeVersion: _cctpBtc);
      expect(_rows([failed, delivered]), ['rx_hl', 'ord_hl']);
    });

    test('a withdrawal paid to someone else claims nothing', () {
      final foreign = _swap('ord_hl',
          withdrawalAmount: '0',
          status: 'success',
          routeVersion: _cctpBtc,
          withdrawalAddress:
              'spark1pgssy7d7vel0nh9m4326qc54e6rskpczn07dktww9rv4nu5ptvt0s9uc489gg2');
      expect(_rows([foreign, delivered]), ['rx_hl', 'ord_hl']);
    });
  });

  group('the reconciler, for a row with no bitcoin figure', () {
    final rxPm = _spark('rx_pm', _sats(9.70), const Duration(minutes: 3));
    final rxHl = _spark('rx_hl', _sats(19.70), const Duration(minutes: 40));

    test('reproduced: it took the receive closest in time, another leg\'s', () {
      expect(
          reconcilerDeliveryLegs(
                  targetSats: 0, rowAt: _t0, receives: [rxPm, rxHl])!
              .single
              .id,
          'rx_pm');
    });

    test('now the receive the dollars that left buy', () {
      expect(
          reconcilerDeliveryLegs(
                  targetSats: 0,
                  rowAt: _t0,
                  receives: [rxPm, rxHl],
                  sentUsd: 20,
                  receivedUsd: _valued)!
              .single
              .id,
          'rx_hl');
      // Only money from outside of another value: nothing.
      expect(
          reconcilerDeliveryLegs(
              targetSats: 0,
              rowAt: _t0,
              receives: [rxPm],
              sentUsd: 20,
              receivedUsd: _valued),
          isNull);
    });

    test('a CCTP leg held for screening is still settled within its day', () {
      final late = _spark('rx_hl', _sats(19.70), const Duration(minutes: 130));
      expect(
          reconcilerDeliveryLegs(targetSats: 0, rowAt: _t0, receives: [late]),
          isNull,
          reason: 'the 90 minutes of the reconciler\'s window');
      expect(
          reconcilerDeliveryLegs(
                  targetSats: 0,
                  rowAt: _t0,
                  receives: [late],
                  window: kOwnCctpDeliveryArrivalWindow,
                  sentUsd: 20,
                  receivedUsd: _valued)!
              .single
              .id,
          'rx_hl');
    });

    test('a done CCTP leg with no figure is looked at for a day', () {
      final cctp = _swap('ord_hl',
          withdrawalAmount: '0',
          status: 'success',
          operationId: 'op-hl',
          routeVersion: _cctpBtc);
      final other = _swap('ord_pm',
          coinFrom: 'USDC.e',
          networkFrom: 'POLYGON',
          withdrawalAmount: '0',
          status: 'success',
          operationId: 'op-pm');
      bool awaits(SwapOrderTransaction r, Duration at) =>
          orchestraRowAwaitsDelivery(r.details,
              linked: const {}, now: _t0.add(at));
      expect(awaits(cctp, const Duration(hours: 7)), isTrue);
      expect(awaits(cctp, const Duration(hours: 25)), isFalse);
      expect(awaits(other, const Duration(hours: 7)), isFalse);
    });
  });

  group('Predictions → Bitcoin', () {
    test('reproduced and fixed: fees took more than the estimate\'s band', () {
      // $3 out of Predictions: the quote said 4,200 sats, the fixed fees
      // of a small move left 3,650 (13% under).
      final pm = _swap('ord_pm',
          coinFrom: 'USDC.e',
          networkFrom: 'POLYGON',
          depositAmount: '3.00',
          withdrawalAmount: '0.00004200',
          operationId: 'op-pm');
      final landed = _spark('rx_pm', 3650, const Duration(minutes: 4));
      expect(_rows([pm, landed], receivedUsd: null), ['rx_pm', 'ord_pm']);
      expect(_rows([pm, landed]), ['ord_pm']);
    });

    test('reproduced and fixed: landed two hours on', () {
      final pm = _swap('ord_pm',
          coinFrom: 'USDC.e',
          networkFrom: 'POLYGON',
          withdrawalAmount: '0.00028000',
          status: 'success',
          operationId: 'op-pm');
      final landed = _spark('rx_pm', 27900, const Duration(hours: 2));
      expect(_rows([pm, landed], receivedUsd: null), ['rx_pm', 'ord_pm']);
      expect(_rows([pm, landed]), ['ord_pm']);
      // Past six hours it keeps its row.
      final later = _spark('rx_pm', 27900, const Duration(hours: 7));
      expect(_rows([pm, later]), ['rx_pm', 'ord_pm']);
    });

    test('the estimate\'s match still comes first', () {
      final pm = _swap('ord_pm',
          coinFrom: 'USDC.e',
          networkFrom: 'POLYGON',
          withdrawalAmount: '0.00028000',
          operationId: 'op-pm');
      final landed = _spark('rx_pm', 27800, const Duration(minutes: 3));
      // A gift of a near value an hour on stays a gift.
      final gift = _spark('rx_gift', 27500, const Duration(hours: 1));
      expect(_rows([pm, landed, gift]), ['rx_gift', 'ord_pm']);
    });
  });

  group('Dollars → Bitcoin', () {
    final buy = _swap('ord_buy',
        coinFrom: kOrchestraUsdAssetCode,
        networkFrom: 'SPARK',
        withdrawalAmount: '0.00028000',
        status: 'success',
        operationId: 'op-buy');
    final paid = _dollars('usd_out', 20.00, const Duration(seconds: 10),
        type: breez.PaymentType.send);
    final landed = _spark('rx_buy', 27800, const Duration(minutes: 1));

    test('one row: its Dollars transfer and its receive inside it', () {
      expect(_rows([buy, paid, landed]), ['ord_buy']);
    });

    test('the transfer its record names folds in by id, whatever it cost', () {
      // The token transfer carried Orchestra's fee on top (3% over the
      // figure): no amount match, the record's id alone.
      final dearer = _dollars('usd_out', 20.60, const Duration(seconds: 10),
          type: breez.PaymentType.send);
      expect(_rows([buy, dearer, landed]), ['usd_out', 'ord_buy']);
      expect(_rows([buy, dearer, landed], funding: {'op-buy': 'usd_out'}),
          ['ord_buy']);
    });

    test('a slipped delivery folds in by its dollars', () {
      // 12% under the quote's figure, an hour on.
      final slipped = _spark('rx_buy', 24600, const Duration(hours: 1));
      final quoted = _swap('ord_buy',
          coinFrom: kOrchestraUsdAssetCode,
          networkFrom: 'SPARK',
          withdrawalAmount: '0.00028000',
          operationId: 'op-buy');
      expect(_rows([quoted, paid, slipped], receivedUsd: null),
          ['rx_buy', 'ord_buy']);
      expect(_rows([quoted, paid, slipped]), ['ord_buy']);
    });
  });

  group('Bitcoin → Dollars', () {
    final sell = _swap('ord_sell',
        coinFrom: 'BTC',
        networkFrom: 'SPARK',
        coinTo: kOrchestraUsdAssetCode,
        depositAmount: '0.00030000',
        withdrawalAmount: '19.80',
        status: 'success',
        operationId: 'op-sell',
        depositAddress: 'sp1orchestradeposit');
    final paid = _spark('tx_paid', 30000, const Duration(seconds: 20),
        direction: TransactionType.sent);

    test('reproduced and fixed: Dollars landing 45 minutes on', () {
      final landed = _dollars('usd_in', 19.80, const Duration(minutes: 45),
          type: breez.PaymentType.receive);
      expect(_rows([sell, paid, landed]), ['ord_sell']);
    });

    test('reproduced and fixed: Dollars 3% under the estimate, under way', () {
      final underWay = _swap('ord_sell',
          coinFrom: 'BTC',
          networkFrom: 'SPARK',
          coinTo: kOrchestraUsdAssetCode,
          depositAmount: '0.00030000',
          withdrawalAmount: '19.80',
          operationId: 'op-sell');
      final landed = _dollars('usd_in', 19.20, const Duration(minutes: 2),
          type: breez.PaymentType.receive);
      expect(_rows([underWay, paid, landed]), ['ord_sell']);
    });

    test('done, it holds the delivered figure to the cent', () {
      final other = _dollars('usd_in', 19.20, const Duration(minutes: 45),
          type: breez.PaymentType.receive);
      expect(_rows([sell, paid, other]), ['usd_in', 'ord_sell']);
    });

    test('Dollars from outside before the conversion keep their row', () {
      final before = _dollars('usd_before', 19.80, const Duration(minutes: -45),
          type: breez.PaymentType.receive);
      expect(_rows([sell, paid, before]), ['ord_sell', 'usd_before']);
    });

    test('of two arrivals the conversion takes one, the closest', () {
      final landed = _dollars('usd_in', 19.80, const Duration(minutes: 45),
          type: breez.PaymentType.receive);
      final twin = _dollars('usd_twin', 19.80, const Duration(hours: 2),
          type: breez.PaymentType.receive);
      expect(_rows([sell, paid, landed, twin]), ['usd_twin', 'ord_sell']);
    });
  });

  group('Bitcoin out to Investing and Predictions', () {
    SwapOrderTransaction out(String id, String coinTo, String networkTo) =>
        _swap(id,
            coinFrom: 'BTC',
            networkFrom: 'SPARK',
            coinTo: coinTo,
            networkTo: networkTo,
            depositAmount: '0.00030000',
            withdrawalAmount: '19.80',
            status: 'success',
            operationId: 'op-$id',
            depositAddress: 'sp1orchestradeposit',
            withdrawalAddress: '0xvenue');

    test('reproduced and fixed: the send twelve minutes after the row', () {
      // Approving took a while; the cached row has no destination to
      // read, and the amount match looks ten minutes either side.
      final toHl = out('ord_to_hl', 'USDC', 'HYPERCORE');
      final paid = _spark('tx_paid', 30000, const Duration(minutes: 12),
          direction: TransactionType.sent);
      expect(_rows([toHl, paid]), ['tx_paid', 'ord_to_hl']);
      expect(_rows([toHl, paid], funding: {'op-ord_to_hl': 'tx_paid'}),
          ['ord_to_hl']);
    });

    test('into Predictions the same way', () {
      final toPm = out('ord_to_pm', 'USDC.e', 'POLYGON');
      final paid = _spark('tx_paid', 30150, const Duration(minutes: 1),
          direction: TransactionType.sent);
      expect(_rows([toPm, paid], funding: {'op-ord_to_pm': 'tx_paid'}),
          ['ord_to_pm']);
    });

    test('a send the record does not name keeps its row', () {
      final toHl = out('ord_to_hl', 'USDC', 'HYPERCORE');
      final paid = _spark('tx_paid', 30000, const Duration(seconds: 5),
          direction: TransactionType.sent);
      final another = _spark('tx_friend', 30000, const Duration(hours: 3),
          direction: TransactionType.sent);
      expect(_rows([toHl, paid, another], funding: {'op-ord_to_hl': 'tx_paid'}),
          ['tx_friend', 'ord_to_hl']);
    });
  });

  group('Investing → Dollars over Circle CCTP', () {
    test('the arrival under the row\'s figure (Orchestra\'s fee) folds in', () {
      // The row says what reached Orchestra ($19.90); $19.78 landed in
      // Dollars 50 minutes on, the order still under way.
      final home = _swap('ord_hl_usd',
          coinTo: kOrchestraUsdAssetCode,
          withdrawalAmount: '19.90',
          operationId: 'op-hl',
          routeVersion: 'hypercore_cctp_to_usdb_v1');
      final landed = _dollars('usd_in', 19.78, const Duration(minutes: 50),
          type: breez.PaymentType.receive);
      expect(_rows([home, landed]), ['ord_hl_usd']);
    });
  });
}
