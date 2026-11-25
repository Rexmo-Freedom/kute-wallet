// A withdrawal home to Bitcoin is one Activity row however many Spark
// transfers delivered it (founder, 1 November 2026: "a $9.71 withdraw from
// Dollars plus a Received ₿12,212 a couple of minutes later").
//
// The rule (own_bitcoin_deliveries.dart): the reconciler's links first,
// every linked leg folding into its row; then amount and time inside the
// row's window, one receive close to the figure, else the set of legs
// adding up to it, else one receive within the estimate's band. A receive
// the row has no room left for keeps its own row.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/swap_activity.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/screens/shared/transactions_builder.dart';
import 'package:kute/services/orchestra/own_bitcoin_deliveries.dart';
import 'package:kute/services/orchestra/own_spark_arrivals.dart';
import 'package:kute/services/orchestra/venue_arrivals.dart'
    show OrchestraOrderIds;
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode;
import 'package:kute/services/polymarket_spark_txs_service.dart';

const _self = 'sp1selfaddress';
final _t0 = DateTime.utc(2026, 11, 1, 12);

/// "Withdraw · from Dollars": $9.71 into bitcoin, the quote's 12,212 sats.
SwapOrderTransaction _withdraw({
  String id = 'ord_buy',
  String withdrawalAmount = '0.00012212',
  String status = 'exchanging',
  String? routeVersion,
  Duration after = Duration.zero,
}) {
  final ts = _t0.add(after);
  return SwapOrderTransaction(
    id: id,
    timestamp: ts,
    isConfirmed: false,
    details: SwapOrder(
      id: id,
      coinFrom: kOrchestraUsdAssetCode,
      networkFrom: 'SPARK',
      coinTo: 'BTC',
      networkTo: 'SPARK',
      depositAddress: 'deposit-$id',
      depositAmount: '9.71',
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
      operationId: 'op-$id',
      routeVersion: routeVersion,
    ),
  );
}

SparkTransaction _rx(String id, int sats, Duration after) =>
    SparkTransaction.fromCache(
      id: id,
      timestamp: _t0.add(after),
      isConfirmed: true,
      amountSats: sats,
      sparkType: SparkTransactionType.spark,
      direction: TransactionType.received,
      pending: false,
    );

List<String> _rows(List<BaseTransaction> rows,
    {Map<String, OrchestraDeliveryLink> links = const {}}) {
  final sorted = [...rows]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  return [
    for (final r in assembleActivityRows(
      sorted,
      ownAddresses: const {_self},
      isHardwareOrWatchOnly: false,
      onlyUsdb: false,
      classify: (o) => o.id.startsWith('ord_hl')
          ? SwapActivityKind.investingWithdrawal
          : SwapActivityKind.dollarWithdrawal,
      walletId: 'spending',
      deliveryLinks: links,
    ))
      r.id,
  ];
}

Map<String, String> _claimed(List<SwapOrderTransaction> rows,
        List<SparkTransaction> receives,
        {Map<String, OrchestraDeliveryLink> links = const {}}) =>
    ownBitcoinDeliveryReceives(rows, receives,
        ownAddresses: const {_self},
        classify: (_) => SwapActivityKind.dollarWithdrawal,
        links: links);

void main() {
  setUp(() {
    OwnSparkArrivals.reset();
    OrchestraOrderIds.debugReset();
  });

  group('the Activity list', () {
    test('single leg: the receive folds into the withdrawal', () {
      final w = _withdraw();
      final rx = _rx('rx_1', 12212, const Duration(minutes: 2));
      expect(_rows([w, rx]), ['ord_buy']);
    });

    test('multi-leg: two transfers adding up to the withdrawal fold in', () {
      final w = _withdraw();
      final a = _rx('rx_a', 6000, const Duration(minutes: 2));
      final b = _rx('rx_b', 6212, const Duration(minutes: 3));
      expect(_rows([w, a, b]), ['ord_buy']);
      expect(_claimed([w], [a, b]), {'rx_a': 'ord_buy', 'rx_b': 'ord_buy'});
    });

    test('multi-leg: a big leg inside the estimate band does not leave the '
        'small one behind', () {
      // 11,000 alone is within ten percent of 12,212; with 1,212 beside it
      // the two add up exactly, so both are the delivery.
      final w = _withdraw();
      final a = _rx('rx_a', 11000, const Duration(minutes: 2));
      final b = _rx('rx_b', 1212, const Duration(minutes: 2, seconds: 20));
      expect(_rows([w, a, b]), ['ord_buy']);
    });

    test('three legs, each a third', () {
      final w = _withdraw(withdrawalAmount: '0.00030000');
      final legs = [
        _rx('rx_1', 10000, const Duration(minutes: 1)),
        _rx('rx_2', 10000, const Duration(minutes: 2)),
        _rx('rx_3', 9900, const Duration(minutes: 4)),
      ];
      expect(_rows([w, ...legs]), ['ord_buy']);
    });

    test('delayed leg: the second transfer lands an hour later, in the '
        'window', () {
      final w = _withdraw();
      final a = _rx('rx_a', 8000, const Duration(minutes: 2));
      final b = _rx('rx_b', 4212, const Duration(minutes: 75));
      expect(_rows([w, a, b]), ['ord_buy']);
    });

    test('a Circle CCTP leg lands hours later and still folds in', () {
      final w = _withdraw(
          id: 'ord_hl',
          withdrawalAmount: '0.00012212',
          status: 'success',
          routeVersion: 'hypercore_cctp_to_btc_v1');
      final rx = _rx('rx_late', 12212, const Duration(hours: 5));
      expect(_rows([w, rx]), ['ord_hl']);
    });

    test('an unrelated receive of the same amount is NOT folded', () {
      final w = _withdraw();
      final delivery = _rx('rx_1', 12212, const Duration(minutes: 2));
      // A friend pays the same amount twenty minutes later: the
      // withdrawal already has its money.
      final friend = _rx('rx_friend', 12212, const Duration(minutes: 20));
      expect(_rows([w, delivery, friend]), ['rx_friend', 'ord_buy']);
      // And past the window, alone, it is never the delivery.
      final later = _rx('rx_later', 12212, const Duration(hours: 3));
      expect(_rows([w, later]), ['rx_later', 'ord_buy']);
      // Nor the same amount before the withdrawal started.
      final before = _rx('rx_before', 12212, const Duration(minutes: -30));
      expect(_rows([w, before]), ['ord_buy', 'rx_before']);
    });

    test('an unrelated receive is NOT folded beside a linked delivery', () {
      final w = _withdraw(withdrawalAmount: '0.00012212', status: 'settled');
      final delivery = _rx('rx_1', 12212, const Duration(minutes: 2));
      final friend = _rx('rx_friend', 12212, const Duration(minutes: 5));
      final links = {
        'rx_1': const OrchestraDeliveryLink(
            orderId: 'ord_buy', operationId: 'op-ord_buy', expectedSats: 12212),
      };
      expect(_rows([w, delivery, friend], links: links),
          ['rx_friend', 'ord_buy']);
    });

    test('a CCTP leg hours later is held to the exact figure', () {
      final w = _withdraw(
          id: 'ord_hl',
          status: 'success',
          routeVersion: 'hypercore_cctp_to_btc_v1');
      // Eight percent off, five hours on: someone else's money.
      final rx = _rx('rx_other', 11240, const Duration(hours: 5));
      expect(_rows([w, rx]), ['rx_other', 'ord_hl']);
    });
  });

  group('the reconciler\'s links', () {
    test('every leg linked to the row folds in, whenever it landed', () {
      final w = _withdraw(withdrawalAmount: '0.00012212', status: 'settled');
      final a = _rx('rx_a', 6000, const Duration(minutes: 2));
      final b = _rx('rx_b', 6212, const Duration(hours: 4));
      final links = {
        'rx_a': const OrchestraDeliveryLink(orderId: 'ord_buy'),
        'rx_b': const OrchestraDeliveryLink(operationId: 'op-ord_buy'),
      };
      expect(_rows([w, a, b], links: links), ['ord_buy']);
    });

    test('a row settled on its first leg takes the rest of the figure it '
        'was matched against', () {
      // The reconciler settled the row on 8,000 (its figure now), linked
      // against the quote's 12,212: the 4,212 that follows is the rest.
      final w = _withdraw(withdrawalAmount: '0.00008000', status: 'settled');
      final a = _rx('rx_a', 8000, const Duration(minutes: 2));
      final b = _rx('rx_b', 4212, const Duration(minutes: 40));
      final links = {
        'rx_a': const OrchestraDeliveryLink(
            orderId: 'ord_buy', operationId: 'op-ord_buy', expectedSats: 12212),
      };
      expect(_rows([w, a, b], links: links), ['ord_buy']);
      // Without the recorded figure, nothing says more was coming.
      final bare = {
        'rx_a': const OrchestraDeliveryLink(
            orderId: 'ord_buy', operationId: 'op-ord_buy'),
      };
      expect(_rows([w, a, b], links: bare), ['rx_b', 'ord_buy']);
    });

    test('the expectation is stored with the link and read back', () {
      final parsed =
          OrchestraDeliveryLink.parse(['1', 'ord_buy', 'op-ord_buy', '12212']);
      expect(parsed!.expectedSats, 12212);
      expect(OrchestraDeliveryLink.parse(['1', 'ord_buy', 'op'])!.expectedSats,
          isNull);
    });
  });

  group('the reconciler\'s pick', () {
    final at = _t0;

    test('one receive close to the figure', () {
      final legs = reconcilerDeliveryLegs(
          targetSats: 12212,
          rowAt: at,
          receives: [
            _rx('rx_1', 12212, const Duration(minutes: 2)),
            _rx('rx_2', 500, const Duration(minutes: 3)),
          ]);
      expect(legs!.map((r) => r.id), ['rx_1']);
    });

    test('a split payout: every leg, so the row reads the total', () {
      final legs = reconcilerDeliveryLegs(
          targetSats: 12212,
          rowAt: at,
          receives: [
            _rx('rx_a', 6000, const Duration(minutes: 2)),
            _rx('rx_b', 6212, const Duration(minutes: 3)),
          ]);
      expect(legs!.map((r) => r.id), unorderedEquals(['rx_a', 'rx_b']));
    });

    test('the first leg of a split payout alone settles the row', () {
      final legs = reconcilerDeliveryLegs(
          targetSats: 12212,
          rowAt: at,
          receives: [_rx('rx_a', 8000, const Duration(minutes: 2))]);
      expect(legs!.map((r) => r.id), ['rx_a']);
    });

    test('the rest of a split payout is held to the exact remainder', () {
      expect(
          reconcilerDeliveryLegs(
              targetSats: 4212,
              rowAt: at,
              band: false,
              receives: [_rx('rx_x', 3000, const Duration(minutes: 30))]),
          isNull);
      expect(
          reconcilerDeliveryLegs(
                  targetSats: 4212,
                  rowAt: at,
                  band: false,
                  receives: [_rx('rx_b', 4212, const Duration(minutes: 30))])!
              .map((r) => r.id),
          ['rx_b']);
    });

    test('nothing outside the window', () {
      expect(
          reconcilerDeliveryLegs(
              targetSats: 12212,
              rowAt: at,
              receives: [_rx('rx_1', 12212, const Duration(hours: 2))]),
          isNull);
    });
  });
}
