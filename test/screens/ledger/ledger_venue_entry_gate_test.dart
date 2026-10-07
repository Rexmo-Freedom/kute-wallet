// Which Moves into a Ledger's own venue account answer to Ledger
// Predictions / Ledger Investing. New money in does; withdrawals (exits)
// and moves not pinned to a Ledger never do.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/ledger/ledger_investment_gate.dart';

void main() {
  test('new money into a Ledger venue account needs its Ledger capability',
      () {
    expect(
        ledgerVenueEntryCapability(
            ledgerWalletId: 'ledger', toPredictions: true, toInvesting: false),
        ledgerPredictionsCapability);
    expect(
        ledgerVenueEntryCapability(
            ledgerWalletId: 'ledger', toPredictions: false, toInvesting: true),
        ledgerInvestingCapability);
  });

  test('withdrawals and other moves need none', () {
    expect(
        ledgerVenueEntryCapability(
            ledgerWalletId: 'ledger', toPredictions: false, toInvesting: false),
        isNull);
    expect(
        ledgerVenueEntryCapability(
            ledgerWalletId: null, toPredictions: true, toInvesting: false),
        isNull);
  });

  test('without a readable policy the Ledger venues stay shut', () {
    expect(ledgerInvestmentAllowed(ledgerPredictionsCapability), isFalse);
    expect(ledgerInvestmentAllowed(ledgerInvestingCapability), isFalse);
  });
}
