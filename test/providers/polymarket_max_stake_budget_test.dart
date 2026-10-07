import 'package:flutter_test/flutter_test.dart';
import 'package:kute/providers/pending_polymarket_bet_provider.dart';
import 'package:kute/providers/polymarket_bet_controller.dart';

void main() {
  test('a typed stake has no spend-all budget and is never re-fitted', () {
    expect(PolymarketBetController.maxStakeBudget(null, 80), isNull);
  });

  test('a Max stake is fitted to the cash at the tap, capped by the balance',
      () {
    expect(PolymarketBetController.maxStakeBudget(50, 80), 50);
    // Cash left since the tap: never size above what the account holds.
    expect(PolymarketBetController.maxStakeBudget(50, 30), 30);
    expect(PolymarketBetController.maxStakeBudget(50, 0), isNull);
  });

  test('the spend-all budget survives preparation copies', () {
    const intent = PendingBetIntent(
      tokenId: 't',
      amount: 49.5,
      slippagePct: 1,
      marketQuestion: 'q',
      outcomeName: 'Yes',
      expectedPrice: 0.5,
      spendAllBudgetUsd: 50,
    );
    final fitted = intent.copyWith(amount: 48.9);
    expect(fitted.amount, 48.9);
    expect(fitted.spendAllBudgetUsd, 50);
    expect(intent.copyWith().amount, 49.5);
  });
}
