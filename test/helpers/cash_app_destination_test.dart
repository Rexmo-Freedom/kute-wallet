import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/cash_app_destination.dart';
import 'package:kute/models/orchestra_model.dart';

void main() {
  OrchestraOnrampResponse response(String output) => OrchestraOnrampResponse(
        orderId: 'ord_deposit',
        quoteId: 'q_deposit',
        depositAddress: 'lnbc_test',
        paymentLinks: OrchestraPaymentLinks(cashApp: '', shortUrl: ''),
        amountIn: '100000',
        estimatedOut: output,
        expiresAt: '2030-01-01T00:00:00Z',
      );

  test('Cash App venue deposits keep their asset, chain and owner', () {
    for (final entry in [
      (CashAppDestination.investing, '1234000000', 'HYPERCORE', 'USDC'),
      (CashAppDestination.predictions, '12340000', 'POLYGON', 'USDC.e'),
    ]) {
      final order = cashAppDepositOrder(
        order: response(entry.$2),
        destination: entry.$1,
        recipient: '0x1111111111111111111111111111111111111111',
        fiatUsd: 13,
        walletId: 'spending-owner',
        createdAt: DateTime.utc(2026),
      );
      expect(order.coinTo, entry.$4);
      expect(order.networkTo, entry.$3);
      expect(order.withdrawalAmount, '12.34000000');
      expect(order.depositAmount, '0.00100000');
      expect(order.walletId, 'spending-owner');
      expect(order.purchaseSource, 'cashapp');
      expect(order.purchaseFiatUsd, '13.00');
      expect(order.routeVersion, isNotNull);
      expect(order.status, 'pending');
    }
  });

  test('existing Bitcoin purchases retain Bitcoin delivery and units', () {
    for (final destination in [
      CashAppDestination.spending,
      CashAppDestination.bitcoinWallet,
    ]) {
      final order = cashAppDepositOrder(
        order: response('99000'),
        destination: destination,
        recipient: 'bitcoin-test-recipient',
        fiatUsd: 10,
        walletId: 'wallet',
        createdAt: DateTime.utc(2026),
      );
      expect(order.coinTo, 'BTC');
      expect(order.networkTo, destination.chain.toUpperCase());
      expect(order.withdrawalAmount, '0.00099000');
      expect(order.routeVersion, isNull);
    }
  });

  test('missing destination cannot create a trackable deposit', () {
    expect(
      () => cashAppDepositOrder(
        order: response('1000000000'),
        destination: CashAppDestination.investing,
        recipient: '',
        fiatUsd: 10,
        walletId: 'wallet',
        createdAt: DateTime.utc(2026),
      ),
      throwsStateError,
    );
  });

  test('venue conversion cost compares fiat with native USD units, not sats',
      () {
    for (final entry in [
      (CashAppDestination.investing, '1234000000'),
      (CashAppDestination.predictions, '12340000'),
    ]) {
      final cost = cashAppQuotedCost(
          destination: entry.$1,
          amountIn: '16000',
          estimatedOut: entry.$2,
          fiatUsd: 13);
      expect(cost.usd, closeTo(0.66, 0.000001));
      expect(cost.sats, isNull);
    }
  });

  test('Bitcoin conversion cost stays in sats and invalid quotes stay unknown',
      () {
    expect(
        cashAppQuotedCost(
            destination: CashAppDestination.bitcoinWallet,
            amountIn: '16000',
            estimatedOut: '15500',
            fiatUsd: 13),
        (usd: null, sats: 500.0));
    for (final destination in CashAppDestination.values) {
      expect(
          cashAppQuotedCost(
              destination: destination,
              amountIn: '16000',
              estimatedOut: 'invalid',
              fiatUsd: 13),
          (usd: null, sats: null));
    }
  });
}
