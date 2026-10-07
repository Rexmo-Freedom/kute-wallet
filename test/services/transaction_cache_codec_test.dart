import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/cash_app_status.dart';
import 'package:kute/helpers/cash_app_destination.dart';
import 'package:kute/helpers/orchestra_legacy_status_rules.dart';
import 'package:kute/helpers/orchestra_chain_for_network.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/services/transaction_cache_codec.dart';

SwapOrder _cashAppRow({required String status, required int expiresAt}) =>
    SwapOrder(
      id: 'ord_cash',
      coinFrom: 'BTC',
      networkFrom: 'LIGHTNING',
      coinTo: 'BTC',
      networkTo: 'SPARK',
      depositAddress: 'lnbc1stale',
      depositAmount: '0.00100000',
      withdrawalAmount: '0.00099000',
      status: status,
      timestamp: expiresAt - const Duration(minutes: 10).inMilliseconds,
      withdrawalAddress: 'spark1destination',
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: '',
      provider: 'Orchestra',
      walletId: 'wallet_spending',
      purchaseSource: 'cashapp',
      purchaseFiatUsd: '55.00',
      expiresAt: expiresAt,
    );

SwapOrder _roundTrip(SwapOrder order) {
  final decoded = TransactionCacheCodec.decode(TransactionCacheCodec.encode(
    Transaction(
      bitcoinTransactions: const [],
      sparkTransactions: const [],
      sparkUnclaimedDeposits: const [],
      swapOrderTransactions: [
        SwapOrderTransaction(
          id: order.id,
          timestamp: order.createdAt,
          details: order,
          isConfirmed: false,
        ),
      ],
    ),
  ));
  expect(decoded, isNotNull);
  return decoded!.swapOrderTransactions.single.details;
}

void main() {
  test('venue deposits keep their destination and payment lifecycle on restart',
      () {
    final deadline = DateTime.now()
        .subtract(const Duration(minutes: 1))
        .millisecondsSinceEpoch;
    for (final venue in [
      (
        asset: 'USDC.e',
        network: 'POLYGON',
        rawAmount: '54500000',
        destination: CashAppDestination.predictions,
      ),
      (
        asset: 'USDC',
        network: 'HYPERCORE',
        rawAmount: '5450000000',
        destination: CashAppDestination.investing,
      ),
    ]) {
      final quote =
          _cashAppRow(status: 'pending', expiresAt: deadline).copyWith(
        id: 'q_venue',
        coinTo: venue.asset,
        networkTo: venue.network,
        withdrawalAddress: '0xrecipient',
        routeVersion: 'cashapp_${venue.network.toLowerCase()}_v1',
      );
      final restored = _roundTrip(quote);
      expect(cashAppDestination(restored), venue.destination);
      expect(restored.cashAppPaymentWindowClosed, isTrue);
      expect(restored.shouldPollOrchestra, isTrue);
      final delivered =
          _roundTrip(legacyRowWithOrderId(restored, 'ord_venue').copyWith(
              status: 'success',
              withdrawalAmount: orchestraRowAmountToDouble(
                venue.rawAmount,
                restored.coinTo,
                network: restored.networkTo,
              ).toStringAsFixed(8)));
      expect(delivered.withdrawalAmount, '54.50000000');
      expect(cashAppDestination(delivered), venue.destination);
      expect(delivered.isComplete, isTrue);
      expect(delivered.walletId, 'wallet_spending');
      expect(delivered.withdrawalAddress, '0xrecipient');
      expect(delivered.purchaseFiatUsd, '55.00');
      expect(delivered.purchaseSource, 'cashapp');
      expect(delivered.routeVersion, quote.routeVersion);
    }
  });

  test('unpaid Cash App row past its deadline cold starts as window ended', () {
    final deadline =
        DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch;
    final row = _roundTrip(_cashAppRow(status: 'pending', expiresAt: deadline));

    expect(row.status, 'pending');
    expect(row.purchaseSource, 'cashapp');
    expect(row.purchaseFiatUsd, '55.00');
    expect(row.expiresAt, deadline);
    expect(row.provider, 'Orchestra');
    expect(row.walletId, 'wallet_spending');
    expect(row.isCashAppPurchase, isTrue);
    expect(row.cashAppPaymentWindowClosed, isTrue);
    expect(row.isPending, isFalse);
    expect(row.shouldPollOrchestra, isTrue);
    expect(cashAppStatusLabel(row, lookupAppLocalizations(const Locale('en'))),
        'Payment window ended');
  });

  test('stored statuses are restored as saved', () {
    final deadline =
        DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch;
    for (final status in [
      'wait',
      'pending',
      'unfulfilled',
      'exchanging',
      'overdue',
      'settled',
    ]) {
      expect(
          _roundTrip(_cashAppRow(status: status, expiresAt: deadline)).status,
          status);
    }
  });
}
