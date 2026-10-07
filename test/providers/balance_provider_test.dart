import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/balance_model.dart';

void main() {
  group('WalletBalance', () {
    test('empty factory creates zero balances', () {
      final balance = WalletBalance.empty();
      expect(balance.onChainBtcBalance, 0);
      expect(balance.sparkBitcoinbalance, 0);
      expect(balance.usdbBalance, 0);
    });

    test('isEmpty true when both BTC balances zero', () {
      final balance = WalletBalance.empty();
      expect(balance.isEmpty, true);
    });

    test('isEmpty false when onChainBtcBalance > 0', () {
      final balance = WalletBalance(
        onChainBtcBalance: 100,
        sparkBitcoinbalance: 0,
      );
      expect(balance.isEmpty, false);
    });

    test('isEmpty false when sparkBitcoinbalance > 0', () {
      final balance = WalletBalance(
        onChainBtcBalance: 0,
        sparkBitcoinbalance: 500,
      );
      expect(balance.isEmpty, false);
    });

    test('isEmpty ignores usdbBalance', () {
      final balance = WalletBalance(
        onChainBtcBalance: 0,
        sparkBitcoinbalance: 0,
        usdbBalance: 1000,
      );
      expect(balance.isEmpty, true);
    });

    test('copyWith updates onChainBtcBalance', () {
      final original = WalletBalance.empty();
      final updated = original.copyWith(onChainBtcBalance: 5000);
      expect(updated.onChainBtcBalance, 5000);
      expect(updated.sparkBitcoinbalance, 0);
      expect(updated.usdbBalance, 0);
    });

    test('copyWith updates sparkBitcoinbalance', () {
      final original = WalletBalance.empty();
      final updated = original.copyWith(sparkBitcoinbalance: 3000);
      expect(updated.sparkBitcoinbalance, 3000);
      expect(updated.onChainBtcBalance, 0);
    });

    test('copyWith updates usdbBalance', () {
      final original = WalletBalance.empty();
      final updated = original.copyWith(usdbBalance: 999);
      expect(updated.usdbBalance, 999);
    });

    test('copyWith preserves unmodified fields', () {
      final original = WalletBalance(
        onChainBtcBalance: 100,
        sparkBitcoinbalance: 200,
        usdbBalance: 300,
      );
      final updated = original.copyWith(onChainBtcBalance: 999);
      expect(updated.onChainBtcBalance, 999);
      expect(updated.sparkBitcoinbalance, 200);
      expect(updated.usdbBalance, 300);
    });

    test('default usdbBalance is 0', () {
      final balance = WalletBalance(
        onChainBtcBalance: 10,
        sparkBitcoinbalance: 20,
      );
      expect(balance.usdbBalance, 0);
    });
  });

  group('BalanceChange', () {
    test('holds asset and amount', () {
      final change = BalanceChange(asset: 'BTC', amount: 50000);
      expect(change.asset, 'BTC');
      expect(change.amount, 50000);
    });

    test('negative amount for outgoing', () {
      final change = BalanceChange(asset: 'BTC', amount: -10000);
      expect(change.amount, -10000);
    });
  });
}
