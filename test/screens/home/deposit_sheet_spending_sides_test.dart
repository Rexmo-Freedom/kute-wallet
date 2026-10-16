// One balance: the spending wallet's Move sheet offers no venue side.
// "Deposit to Investing", "Deposit to Predictions" and the two venue
// withdrawals are gone for it, not disabled: a venue deposit or buy
// asked for on the spending wallet opens the Dollars deposit door (the
// same ways in as the Dollars deposit always offered), a venue
// withdrawal opens nothing. A Ledger keeps every one of its doors.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/home/components/deposit_sheet.dart';

void main() {
  const venueDeposits = [
    MoveLockedSide.depositToPredictions,
    MoveLockedSide.depositToHyperliquid,
    MoveLockedSide.buyToPredictions,
    MoveLockedSide.buyToHyperliquid,
  ];
  const venueWithdrawals = [
    MoveLockedSide.withdrawFromPredictions,
    MoveLockedSide.withdrawFromHyperliquid,
  ];

  group('the spending wallet', () {
    test('a venue deposit or buy opens the Dollars deposit door', () {
      for (final side in venueDeposits) {
        expect(spendingWalletLockedSide(side, ledger: false),
            MoveLockedSide.depositToUsd,
            reason: side.name);
      }
    });

    test('a venue withdrawal opens nothing', () {
      for (final side in venueWithdrawals) {
        expect(spendingWalletLockedSide(side, ledger: false), isNull,
            reason: side.name);
      }
    });

    test('the doors into Dollars and the fiat doors are untouched', () {
      for (final side in [
        MoveLockedSide.depositToUsd,
        MoveLockedSide.depositFromFiat,
        MoveLockedSide.withdrawToFiat,
      ]) {
        expect(spendingWalletLockedSide(side, ledger: false), side,
            reason: side.name);
      }
    });

    test('every side is answered', () {
      for (final side in MoveLockedSide.values) {
        final answer = spendingWalletLockedSide(side, ledger: false);
        expect(answer, anyOf(isNull, isA<MoveLockedSide>()), reason: side.name);
        expect(venueDeposits.contains(answer), isFalse, reason: side.name);
        expect(venueWithdrawals.contains(answer), isFalse, reason: side.name);
      }
    });
  });

  test('a Ledger keeps every one of its doors', () {
    for (final side in MoveLockedSide.values) {
      expect(spendingWalletLockedSide(side, ledger: true), side,
          reason: side.name);
    }
  });
}
