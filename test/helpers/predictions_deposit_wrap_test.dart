// A completed deposit into Predictions is converted to pUSD from the
// background sync whatever paid for it, and only for the active account's
// own Predictions wallet.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/predictions_deposit_wrap.dart';
import 'package:kute/models/swap_order_model.dart';

import 'source_scan.dart';

const _pm = '0x00000000000000000000000000000000000000aa';

SwapOrder _row({
  required String coinFrom,
  required String networkFrom,
  String coinTo = 'USDC',
  String networkTo = 'POLYGON',
  String status = 'success',
  String walletId = 'spend',
  String to = _pm,
  String? purchaseSource,
  String id = 'ord_1',
}) =>
    SwapOrder(
      id: id,
      coinFrom: coinFrom,
      networkFrom: networkFrom,
      coinTo: coinTo,
      networkTo: networkTo,
      depositAddress: 'dep',
      depositAmount: '1',
      withdrawalAmount: '25.00',
      status: status,
      timestamp: 0,
      withdrawalAddress: to,
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: '',
      provider: 'Orchestra',
      purchaseSource: purchaseSource,
      walletId: walletId,
    );

bool _needs(SwapOrder row, {Iterable<SwapOrder> orders = const []}) =>
    predictionsDepositNeedsWrap(row,
        activeWalletId: 'spend', predictionsAddress: _pm, orders: orders);

void main() {
  final sources = {
    'Bitcoin (Spark)': _row(coinFrom: 'BTC', networkFrom: 'SPARK'),
    'Dollars': _row(coinFrom: 'USDB', networkFrom: 'SPARK'),
    'Cash App (Lightning)': _row(
        coinFrom: 'BTC',
        networkFrom: 'LIGHTNING',
        coinTo: 'USDC.e',
        purchaseSource: 'cashapp'),
    'Investing': _row(coinFrom: 'USDC', networkFrom: 'HYPERCORE'),
  };

  for (final entry in sources.entries) {
    test('${entry.key}: converted once the order completes', () {
      expect(isPredictionsDepositOrder(entry.value), isTrue);
      expect(_needs(entry.value), isTrue);
      // Not before it completes.
      for (final status in ['exchanging', 'pending', 'refunded', 'expired']) {
        expect(_needs(entry.value.copyWith(status: status)), isFalse,
            reason: status);
      }
    });
  }

  test('only into the active account\'s own Predictions wallet', () {
    final row = sources['Bitcoin (Spark)']!;
    expect(_needs(row.copyWith(walletId: 'other')), isFalse);
    expect(_needs(row.copyWith(withdrawalAddress: '0xdead')), isFalse);
    // Address case does not matter.
    expect(_needs(row.copyWith(withdrawalAddress: _pm.toUpperCase())), isTrue);
    expect(
        predictionsDepositNeedsWrap(row,
            activeWalletId: 'spend', predictionsAddress: null, orders: []),
        isFalse);
  });

  test('not a deposit into Predictions: nothing to convert', () {
    final toSpark =
        _row(coinFrom: 'USDC.e', networkFrom: 'POLYGON', networkTo: 'SPARK',
            coinTo: 'BTC');
    expect(isPredictionsDepositOrder(toSpark), isFalse);
    expect(_needs(toSpark), isFalse);
  });

  test('never while a withdrawal out of Predictions is on its way', () {
    final row = sources['Dollars']!;
    final withdrawing = _row(
        id: 'ord_w',
        coinFrom: 'USDC.e',
        networkFrom: 'POLYGON',
        coinTo: 'BTC',
        networkTo: 'SPARK',
        status: 'exchanging');
    expect(_needs(row, orders: [row, withdrawing]), isFalse);
    expect(_needs(row, orders: [row, withdrawing.copyWith(status: 'success')]),
        isTrue);
  });

  test('the background sync converts on every completed order, not only '
      'Cash App', () {
    final code = stripComments(
        File('lib/providers/background_sync_provider.dart').readAsStringSync());
    // Both status pollers hand a newly completed row to the converter.
    expect(
        RegExp(r"mappedStatus == 'success'\) \{\s*unawaited\(_finishPredictionsDeposit\(updated\)\);")
            .allMatches(code)
            .length,
        2);
    expect(code, contains('notifier.wrapIncomingUsdcEToPusd();'));
  });
}
