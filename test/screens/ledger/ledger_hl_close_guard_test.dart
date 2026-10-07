import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/ledger/ledger_hyperliquid_account_provider.dart';
import 'package:kute/screens/ledger/hyperliquid/ledger_hl_execution_target.dart';

HlPerpPosition position(double size, {String coin = 'BTC'}) =>
    HlPerpPosition.fromJson({'coin': coin, 'szi': size});

LedgerHlAccount account(
  HlPerpPosition live, {
  String walletId = 'ledger-a',
  String address = '0xABC',
  Set<LedgerHlReadCategory> failures = const {},
}) {
  final snapshot = HlAccountSnapshot(
      accountValue: 100,
      withdrawable: 0,
      totalMarginUsed: 100,
      positions: [live],
      spotBalances: const []);
  return LedgerHlAccount(
      walletId: walletId,
      address: address,
      account: live.coin.contains(':') ? HlAccountSnapshot.empty : snapshot,
      dexAccounts: live.coin.contains(':') ? {'xyz': snapshot} : const {},
      partialFailures: failures);
}

void main() {
  void validate(
    LedgerHlAccount current, {
    HlPerpPosition? reviewed,
    double quantity = 1,
    String? paired = '0xabc',
  }) =>
      validateLedgerHlClosePosition(
          current: current,
          walletId: 'ledger-a',
          pairedAddress: '0xABC',
          currentPairedAddress: paired,
          position: reviewed ?? position(2),
          quantity: quantity);

  test('close remains bound to the reviewed Ledger wallet and address', () {
    expect(() => validate(account(position(2))), returnsNormally);
    expect(() => validate(account(position(2), walletId: 'spending')),
        throwsStateError);
    expect(() => validate(account(position(2), address: '0xDEF')),
        throwsStateError);
    expect(
        () => validate(account(position(2)), paired: null), throwsStateError);
    expect(() => validate(account(position(2)), paired: '0xDEF'),
        throwsStateError);
  });

  test('cannot close a disappeared, flipped or smaller position', () {
    for (final size in [0.0, -2.0, 0.5, double.nan]) {
      expect(() => validate(account(position(size))), throwsStateError);
    }
    expect(() => validate(account(position(2, coin: 'ETH'))), throwsStateError);
    for (final qty in [0.0, -1.0, 3.0, double.infinity, double.nan]) {
      expect(() => validate(account(position(2)), quantity: qty),
          throwsStateError);
    }
  });

  test('HIP-3 close matches the full wire coin and its account read', () {
    final reviewed = position(-2, coin: 'xyz:XYZ100');
    expect(
        () => validate(account(reviewed), reviewed: reviewed), returnsNormally);
    expect(
        () => validate(account(position(-2, coin: 'other:XYZ100')),
            reviewed: reviewed),
        throwsStateError);
    expect(
        () => validate(
            account(reviewed, failures: {LedgerHlReadCategory.hip3Dexes}),
            reviewed: reviewed),
        throwsStateError);
  });

  test('unrelated history failures do not block reducing a position', () {
    expect(
        () => validate(account(position(2), failures: {
              LedgerHlReadCategory.fills,
              LedgerHlReadCategory.openOrders,
            })),
        returnsNormally);
    expect(
        () => validate(account(position(2), failures: {
              LedgerHlReadCategory.account,
            })),
        throwsStateError);
  });
}
