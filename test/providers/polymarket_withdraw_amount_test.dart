import 'package:flutter_test/flutter_test.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/services/security/wallet_guard_exception.dart';

void main() {
  group('clampWithdrawMicroUsdc', () {
    test('an amount inside the balance is sent as requested', () {
      expect(
          PolymarketTradingNotifier.clampWithdrawMicroUsdc(
              BigInt.from(5000000), BigInt.from(6000000)),
          BigInt.from(5000000));
    });

    test('sub-cent overage clamps to the balance', () {
      expect(
          PolymarketTradingNotifier.clampWithdrawMicroUsdc(
              BigInt.from(6000003), BigInt.from(6000000)),
          BigInt.from(6000000));
    });

    test('a material shortfall or an empty wallet throws', () {
      expect(
          () => PolymarketTradingNotifier.clampWithdrawMicroUsdc(
              BigInt.from(6010001), BigInt.from(6000000)),
          throwsException);
      expect(
          () => PolymarketTradingNotifier.clampWithdrawMicroUsdc(
              BigInt.from(1), BigInt.zero),
          throwsException);
    });
  });

  group('checkExactWithdrawMicroUsdc', () {
    test('a covered quoted amount is sent exactly', () {
      expect(
          PolymarketTradingNotifier.checkExactWithdrawMicroUsdc(
              BigInt.from(6000000), BigInt.from(6000000)),
          BigInt.from(6000000));
    });

    test('a quoted amount the balance cannot cover never clamps', () {
      for (final quoted in [BigInt.from(6000003), BigInt.zero]) {
        expect(
            () => PolymarketTradingNotifier.checkExactWithdrawMicroUsdc(
                quoted, BigInt.from(6000000)),
            throwsA(isA<WalletGuardException>().having((e) => e.reason,
                'reason', WalletGuardReason.amountMismatch)),
            reason: '$quoted');
      }
    });
  });
}
