import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/balance_model.dart';

void main() {
  group('WalletBalance', () {
    test('empty factory', () {
      final b = WalletBalance.empty();
      expect(b.onChainBtcBalance, 0);
      expect(b.sparkBitcoinbalance, 0);
      expect(b.usdbBalance, 0);
    });

    test('isEmpty true when all zero', () {
      final b = WalletBalance.empty();
      expect(b.isEmpty, isTrue);
    });

    test('isEmpty false when onChainBtcBalance > 0', () {
      final b = WalletBalance(onChainBtcBalance: 100, sparkBitcoinbalance: 0);
      expect(b.isEmpty, isFalse);
    });

    test('isEmpty false when sparkBitcoinbalance > 0', () {
      final b = WalletBalance(onChainBtcBalance: 0, sparkBitcoinbalance: 100);
      expect(b.isEmpty, isFalse);
    });

    test('isEmpty ignores usdbBalance', () {
      final b = WalletBalance(
        onChainBtcBalance: 0,
        sparkBitcoinbalance: 0,
        usdbBalance: 1000000,
      );
      expect(b.isEmpty, isTrue);
    });

    test('copyWith overrides onChainBtcBalance', () {
      final b = WalletBalance(onChainBtcBalance: 100, sparkBitcoinbalance: 200);
      final copy = b.copyWith(onChainBtcBalance: 500);
      expect(copy.onChainBtcBalance, 500);
      expect(copy.sparkBitcoinbalance, 200);
      expect(copy.usdbBalance, 0);
    });

    test('copyWith overrides sparkBitcoinbalance', () {
      final b = WalletBalance(onChainBtcBalance: 100, sparkBitcoinbalance: 200);
      final copy = b.copyWith(sparkBitcoinbalance: 999);
      expect(copy.sparkBitcoinbalance, 999);
      expect(copy.onChainBtcBalance, 100);
    });

    test('copyWith overrides usdbBalance', () {
      final b = WalletBalance.empty();
      final copy = b.copyWith(usdbBalance: 5000000);
      expect(copy.usdbBalance, 5000000);
    });

    test('copyWith preserves all when no args', () {
      final b = WalletBalance(
        onChainBtcBalance: 1,
        sparkBitcoinbalance: 2,
        usdbBalance: 3,
      );
      final copy = b.copyWith();
      expect(copy.onChainBtcBalance, 1);
      expect(copy.sparkBitcoinbalance, 2);
      expect(copy.usdbBalance, 3);
    });

    test('default usdbBalance is 0', () {
      final b = WalletBalance(onChainBtcBalance: 0, sparkBitcoinbalance: 0);
      expect(b.usdbBalance, 0);
    });

    group('balance calculations', () {
      test('total BTC balance is sum of onChain and spark', () {
        final b = WalletBalance(
          onChainBtcBalance: 50000,
          sparkBitcoinbalance: 30000,
        );
        final totalBtcSats = b.onChainBtcBalance + b.sparkBitcoinbalance;
        expect(totalBtcSats, 80000);
      });

      test('total BTC balance with only onChain', () {
        final b = WalletBalance(
          onChainBtcBalance: 100000000, // 1 BTC in satoshis
          sparkBitcoinbalance: 0,
        );
        final totalBtcSats = b.onChainBtcBalance + b.sparkBitcoinbalance;
        expect(totalBtcSats, 100000000);
      });

      test('total BTC balance with only spark', () {
        final b = WalletBalance(
          onChainBtcBalance: 0,
          sparkBitcoinbalance: 250000000, // 2.5 BTC
        );
        final totalBtcSats = b.onChainBtcBalance + b.sparkBitcoinbalance;
        expect(totalBtcSats, 250000000);
      });

      test('BTC and USDB balances are independent', () {
        final b = WalletBalance(
          onChainBtcBalance: 100000,
          sparkBitcoinbalance: 200000,
          usdbBalance: 5000000, // 5 USDB (6 decimals)
        );
        expect(b.onChainBtcBalance + b.sparkBitcoinbalance, 300000);
        expect(b.usdbBalance, 5000000);
      });
    });

    group('satoshi/BTC conversions', () {
      test('1 BTC equals 100,000,000 satoshis', () {
        const int oneBtcInSats = 100000000;
        final b = WalletBalance(
          onChainBtcBalance: oneBtcInSats,
          sparkBitcoinbalance: 0,
        );
        expect(b.onChainBtcBalance, 100000000);
        expect(b.onChainBtcBalance / 100000000.0, 1.0);
      });

      test('0.5 BTC equals 50,000,000 satoshis', () {
        final b = WalletBalance(
          onChainBtcBalance: 50000000,
          sparkBitcoinbalance: 0,
        );
        expect(b.onChainBtcBalance / 100000000.0, 0.5);
      });

      test('1 satoshi converts to 0.00000001 BTC', () {
        final b = WalletBalance(
          onChainBtcBalance: 1,
          sparkBitcoinbalance: 0,
        );
        expect(b.onChainBtcBalance / 100000000.0, 0.00000001);
      });

      test('21 million BTC in satoshis (max supply)', () {
        // 21,000,000 BTC = 2,100,000,000,000,000 satoshis
        const int maxSupplySats = 2100000000000000;
        final b = WalletBalance(
          onChainBtcBalance: maxSupplySats,
          sparkBitcoinbalance: 0,
        );
        expect(b.onChainBtcBalance / 100000000.0, 21000000.0);
      });

      test('combined balance converts correctly to BTC', () {
        final b = WalletBalance(
          onChainBtcBalance: 75000000, // 0.75 BTC
          sparkBitcoinbalance: 25000000, // 0.25 BTC
        );
        final totalBtc =
            (b.onChainBtcBalance + b.sparkBitcoinbalance) / 100000000.0;
        expect(totalBtc, 1.0);
      });
    });

    group('USDB base units (6 decimals)', () {
      test('1 USDB equals 1,000,000 base units', () {
        final b = WalletBalance(
          onChainBtcBalance: 0,
          sparkBitcoinbalance: 0,
          usdbBalance: 1000000,
        );
        expect(b.usdbBalance / 1000000.0, 1.0);
      });

      test('0.01 USDB equals 10,000 base units', () {
        final b = WalletBalance(
          onChainBtcBalance: 0,
          sparkBitcoinbalance: 0,
          usdbBalance: 10000,
        );
        expect(b.usdbBalance / 1000000.0, 0.01);
      });

      test('smallest USDB unit is 0.000001', () {
        final b = WalletBalance(
          onChainBtcBalance: 0,
          sparkBitcoinbalance: 0,
          usdbBalance: 1,
        );
        expect(b.usdbBalance / 1000000.0, 0.000001);
      });
    });

    group('zero balances', () {
      test('empty factory produces all zero balances', () {
        final b = WalletBalance.empty();
        expect(b.onChainBtcBalance, 0);
        expect(b.sparkBitcoinbalance, 0);
        expect(b.usdbBalance, 0);
        expect(b.isEmpty, isTrue);
      });

      test('explicit zero construction', () {
        final b = WalletBalance(
          onChainBtcBalance: 0,
          sparkBitcoinbalance: 0,
          usdbBalance: 0,
        );
        expect(b.isEmpty, isTrue);
        expect(b.onChainBtcBalance + b.sparkBitcoinbalance, 0);
      });

      test('zero onChain with non-zero spark is not empty', () {
        final b = WalletBalance(
          onChainBtcBalance: 0,
          sparkBitcoinbalance: 1,
        );
        expect(b.isEmpty, isFalse);
      });

      test('zero spark with non-zero onChain is not empty', () {
        final b = WalletBalance(
          onChainBtcBalance: 1,
          sparkBitcoinbalance: 0,
        );
        expect(b.isEmpty, isFalse);
      });

      test('zero BTC balances with non-zero USDB is still empty per isEmpty', () {
        final b = WalletBalance(
          onChainBtcBalance: 0,
          sparkBitcoinbalance: 0,
          usdbBalance: 999999999,
        );
        // isEmpty only checks BTC balances, not USDB
        expect(b.isEmpty, isTrue);
      });
    });

    group('large values and overflow protection', () {
      test('handles max 64-bit signed int for onChainBtcBalance', () {
        // Dart int is 64-bit on VM
        const largeValue = 9223372036854775807; // max int64
        final b = WalletBalance(
          onChainBtcBalance: largeValue,
          sparkBitcoinbalance: 0,
        );
        expect(b.onChainBtcBalance, largeValue);
        expect(b.isEmpty, isFalse);
      });

      test('handles max 64-bit signed int for sparkBitcoinbalance', () {
        const largeValue = 9223372036854775807;
        final b = WalletBalance(
          onChainBtcBalance: 0,
          sparkBitcoinbalance: largeValue,
        );
        expect(b.sparkBitcoinbalance, largeValue);
        expect(b.isEmpty, isFalse);
      });

      test('handles max 64-bit signed int for usdbBalance', () {
        const largeValue = 9223372036854775807;
        final b = WalletBalance(
          onChainBtcBalance: 0,
          sparkBitcoinbalance: 0,
          usdbBalance: largeValue,
        );
        expect(b.usdbBalance, largeValue);
      });

      test('handles realistic large BTC balance (1000 BTC)', () {
        const thousandBtc = 100000000000; // 1000 BTC in sats
        final b = WalletBalance(
          onChainBtcBalance: thousandBtc,
          sparkBitcoinbalance: thousandBtc,
        );
        expect(b.onChainBtcBalance + b.sparkBitcoinbalance, 200000000000);
      });

      test('handles negative values without error', () {
        // While semantically invalid, the model does not enforce non-negative
        final b = WalletBalance(
          onChainBtcBalance: -1,
          sparkBitcoinbalance: -1,
          usdbBalance: -1,
        );
        expect(b.onChainBtcBalance, -1);
        expect(b.sparkBitcoinbalance, -1);
        expect(b.usdbBalance, -1);
      });
    });

    group('multiple wallet balances', () {
      test('multiple wallets can be aggregated', () {
        final wallet1 = WalletBalance(
          onChainBtcBalance: 100000,
          sparkBitcoinbalance: 50000,
          usdbBalance: 1000000,
        );
        final wallet2 = WalletBalance(
          onChainBtcBalance: 200000,
          sparkBitcoinbalance: 75000,
          usdbBalance: 2000000,
        );
        final wallet3 = WalletBalance(
          onChainBtcBalance: 300000,
          sparkBitcoinbalance: 100000,
          usdbBalance: 3000000,
        );

        final wallets = [wallet1, wallet2, wallet3];

        final totalOnChain =
            wallets.fold<int>(0, (sum, w) => sum + w.onChainBtcBalance);
        final totalSpark =
            wallets.fold<int>(0, (sum, w) => sum + w.sparkBitcoinbalance);
        final totalUsdb =
            wallets.fold<int>(0, (sum, w) => sum + w.usdbBalance);

        expect(totalOnChain, 600000);
        expect(totalSpark, 225000);
        expect(totalUsdb, 6000000);
      });

      test('mixed empty and non-empty wallets', () {
        final wallets = [
          WalletBalance.empty(),
          WalletBalance(onChainBtcBalance: 500000, sparkBitcoinbalance: 0),
          WalletBalance.empty(),
        ];

        final nonEmpty = wallets.where((w) => !w.isEmpty).toList();
        expect(nonEmpty.length, 1);
        expect(nonEmpty.first.onChainBtcBalance, 500000);
      });

      test('each wallet is independent after copyWith', () {
        final original = WalletBalance(
          onChainBtcBalance: 100,
          sparkBitcoinbalance: 200,
          usdbBalance: 300,
        );
        final modified = original.copyWith(onChainBtcBalance: 999);

        expect(original.onChainBtcBalance, 100);
        expect(modified.onChainBtcBalance, 999);
        // Verify original is not mutated
        expect(original.sparkBitcoinbalance, 200);
        expect(modified.sparkBitcoinbalance, 200);
      });
    });

    group('copyWith combinations', () {
      test('copyWith all fields at once', () {
        final b = WalletBalance.empty();
        final copy = b.copyWith(
          onChainBtcBalance: 111,
          sparkBitcoinbalance: 222,
          usdbBalance: 333,
        );
        expect(copy.onChainBtcBalance, 111);
        expect(copy.sparkBitcoinbalance, 222);
        expect(copy.usdbBalance, 333);
      });

      test('copyWith two fields, one preserved', () {
        final b = WalletBalance(
          onChainBtcBalance: 10,
          sparkBitcoinbalance: 20,
          usdbBalance: 30,
        );
        final copy = b.copyWith(onChainBtcBalance: 99, usdbBalance: 99);
        expect(copy.onChainBtcBalance, 99);
        expect(copy.sparkBitcoinbalance, 20); // preserved
        expect(copy.usdbBalance, 99);
      });

      test('chained copyWith calls', () {
        final b = WalletBalance.empty()
            .copyWith(onChainBtcBalance: 100)
            .copyWith(sparkBitcoinbalance: 200)
            .copyWith(usdbBalance: 300);
        expect(b.onChainBtcBalance, 100);
        expect(b.sparkBitcoinbalance, 200);
        expect(b.usdbBalance, 300);
      });

      test('copyWith to zero makes isEmpty true', () {
        final b = WalletBalance(
          onChainBtcBalance: 500,
          sparkBitcoinbalance: 600,
          usdbBalance: 700,
        );
        final zeroed = b.copyWith(
          onChainBtcBalance: 0,
          sparkBitcoinbalance: 0,
        );
        expect(zeroed.isEmpty, isTrue);
        // usdbBalance is still 700 but isEmpty ignores it
        expect(zeroed.usdbBalance, 700);
      });
    });
  });

  group('BalanceChange', () {
    test('fields', () {
      final bc = BalanceChange(asset: 'btc', amount: 50000);
      expect(bc.asset, 'btc');
      expect(bc.amount, 50000);
    });

    test('negative amount', () {
      final bc = BalanceChange(asset: 'usdb', amount: -1000);
      expect(bc.amount, -1000);
    });

    test('zero amount', () {
      final bc = BalanceChange(asset: 'btc', amount: 0);
      expect(bc.amount, 0);
      expect(bc.asset, 'btc');
    });

    test('large positive amount', () {
      final bc = BalanceChange(asset: 'btc', amount: 2100000000000000);
      expect(bc.amount, 2100000000000000);
    });

    test('different asset types', () {
      final btcChange = BalanceChange(asset: 'btc', amount: 100);
      final usdbChange = BalanceChange(asset: 'usdb', amount: 200);
      final sparkChange = BalanceChange(asset: 'spark', amount: 300);

      expect(btcChange.asset, 'btc');
      expect(usdbChange.asset, 'usdb');
      expect(sparkChange.asset, 'spark');
    });

    test('empty asset string', () {
      final bc = BalanceChange(asset: '', amount: 100);
      expect(bc.asset, '');
    });

    test('multiple balance changes can be collected', () {
      final changes = [
        BalanceChange(asset: 'btc', amount: 50000),
        BalanceChange(asset: 'btc', amount: -20000),
        BalanceChange(asset: 'usdb', amount: 1000000),
      ];

      final btcNet = changes
          .where((c) => c.asset == 'btc')
          .fold<int>(0, (sum, c) => sum + c.amount);
      expect(btcNet, 30000);

      final usdbNet = changes
          .where((c) => c.asset == 'usdb')
          .fold<int>(0, (sum, c) => sum + c.amount);
      expect(usdbNet, 1000000);
    });
  });
}
