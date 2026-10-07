// A Cash App purchase is paid over Lightning, but that leg is plumbing.
// The bitcoin ledger keeps only purchases that deliver bitcoin; a dollar
// purchase belongs to the Dollars screen alone.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/screens/shared/transactions_builder.dart';
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode;

SwapOrder _order({required String coinTo, required String networkTo}) =>
    SwapOrder(
      id: 'o-$coinTo',
      coinFrom: 'BTC',
      coinTo: coinTo,
      networkFrom: 'LIGHTNING',
      networkTo: networkTo,
      depositAddress: 'lnbc1...',
      depositAmount: '0.0001',
      withdrawalAmount: '1',
      status: 'pending',
      timestamp: 0,
      withdrawalAddress: 'sp1...',
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: '',
      provider: 'Orchestra',
      purchaseSource: 'cashapp',
      purchaseFiatUsd: '10.00',
    );

void main() {
  test('a dollar purchase is dollars only', () {
    final dollars = _order(coinTo: kOrchestraUsdAssetCode, networkTo: 'SPARK');
    expect(orchestraTouchesDollars(dollars), isTrue);
    expect(orchestraTouchesBitcoin(dollars), isFalse);
  });

  test('a bitcoin purchase stays in the bitcoin ledger', () {
    final btc = _order(coinTo: 'BTC', networkTo: 'SPARK');
    expect(orchestraTouchesDollars(btc), isFalse);
    expect(orchestraTouchesBitcoin(btc), isTrue);
  });

  test('an ordinary conversion out of dollars into bitcoin touches both', () {
    final swap = SwapOrder(
      id: 'swap',
      coinFrom: kOrchestraUsdAssetCode,
      coinTo: 'BTC',
      networkFrom: 'SPARK',
      networkTo: 'SPARK',
      depositAddress: 'sp1...',
      depositAmount: '10',
      withdrawalAmount: '0.0001',
      status: 'success',
      timestamp: 0,
      withdrawalAddress: 'sp1...',
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: '',
      provider: 'Orchestra',
    );
    expect(orchestraTouchesDollars(swap), isTrue);
    expect(orchestraTouchesBitcoin(swap), isTrue);
  });
}
