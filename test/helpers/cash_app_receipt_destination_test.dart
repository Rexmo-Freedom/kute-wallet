import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/cash_app_destination.dart';
import 'package:kute/models/swap_order_model.dart';

SwapOrder _deposit({String asset = 'USDC.e', String network = 'POLYGON'}) =>
    SwapOrder(
      id: 'ord_cash_app',
      coinFrom: 'BTC',
      networkFrom: 'LIGHTNING',
      coinTo: asset,
      networkTo: network,
      depositAddress: 'lnbc1invoice',
      depositAmount: '0.001',
      withdrawalAmount: '55.00',
      status: 'success',
      timestamp: 1,
      withdrawalAddress: '0xRecipient',
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: '',
      provider: 'Orchestra',
      walletId: 'spending',
      purchaseSource: 'cashapp',
    );

void main() {
  test('receipt destination follows the persisted delivery chain and asset',
      () {
    expect(cashAppDestination(_deposit()), CashAppDestination.predictions);
    expect(cashAppDestination(_deposit(asset: 'USDC.E', network: 'polygon')),
        CashAppDestination.predictions);
    expect(cashAppDestination(_deposit(asset: 'USDC', network: 'hypercore')),
        CashAppDestination.investing);
    expect(cashAppDestination(_deposit(asset: 'BTC', network: 'SPARK')),
        CashAppDestination.spending);
    expect(cashAppDestination(_deposit(asset: 'BTC', network: 'BITCOIN')),
        CashAppDestination.bitcoinWallet);
    expect(cashAppDestination(_deposit(asset: 'USDC', network: 'ARBITRUM')),
        isNull);
    expect(cashAppDestination(_deposit().copyWith(purchaseSource: 'other')),
        isNull);
  });

  group('completed Cash App deposit wrap', () {
    bool canWrap(SwapOrder order,
            {String? wallet = 'spending',
            String? recipient = '0xrecipient',
            List<SwapOrder> orders = const []}) =>
        cashAppNeedsPredictionsWrap(order,
            activeWalletId: wallet,
            predictionsAddress: recipient,
            orders: orders);

    test('requires completed USDC.e delivery into the active PM account', () {
      final deposit = _deposit();
      expect(canWrap(deposit), isTrue);
      expect(canWrap(deposit.copyWith(status: 'sending')), isFalse);
      expect(canWrap(deposit, wallet: 'different'), isFalse);
      expect(canWrap(deposit, recipient: '0xOther'), isFalse);
      expect(canWrap(deposit, recipient: null), isFalse);
      expect(canWrap(deposit.copyWith(coinTo: 'USDC')), isFalse);
      expect(canWrap(_deposit(asset: 'USDC', network: 'HYPERCORE')), isFalse);
    });

    test('does not wrap while the same account is withdrawing collateral', () {
      final deposit = _deposit();
      final withdrawal = deposit.copyWith(
        id: 'ord_withdrawal',
        coinFrom: 'USDC.e',
        networkFrom: 'POLYGON',
        coinTo: 'BTC',
        networkTo: 'SPARK',
        purchaseSource: '',
        status: 'sending',
      );
      expect(canWrap(deposit, orders: [withdrawal]), isFalse);
      expect(canWrap(deposit, orders: [withdrawal.copyWith(status: 'success')]),
          isTrue);
      expect(canWrap(deposit, orders: [withdrawal.copyWith(walletId: 'other')]),
          isTrue);
    });
  });
}
