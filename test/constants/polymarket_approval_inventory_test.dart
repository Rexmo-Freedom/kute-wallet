// test/constants/polymarket_approval_inventory_test.dart
//
// The CLOB v1 Neg Risk Adapter is labelled deprecated (relayer redeems to it
// ended 2026-07-17), but the CLOB still refuses neg-risk orders without pUSD
// and CTF approvals to it ("the allowance is not enough -> spender: 0xd91E…").
// Onboarding approves it for pUSD and CTF again; only its USDC.e approval stays
// retired, and a compromise revocation must still be able to clear it.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/constants/polymarket_approval_inventory.dart';
import 'package:kute/constants/polymarket_constants.dart';

void main() {
  const legacy = PolymarketConstants.legacyNegRiskAdapterAddress;

  test('onboarding approves the Neg Risk Adapter for pUSD and CTF, not USDC.e',
      () {
    expect(PolymarketApprovalInventoryConstants.pusdSpenders, contains(legacy));
    expect(PolymarketApprovalInventoryConstants.ctfOperators, contains(legacy));
    expect(PolymarketApprovalInventoryConstants.usdcESpenders,
        isNot(contains(legacy)));
    expect(
        PolymarketApprovalInventoryConstants
            .activeErc20SpendersByToken[PolymarketConstants.pusdAddress],
        contains(legacy));
    expect(
        PolymarketApprovalInventoryConstants
            .activeOperatorsByToken[PolymarketConstants.ctfAddress],
        contains(legacy));
  });

  test('onboarding still sets both redeem adapters and the exchanges', () {
    const wanted = [
      PolymarketConstants.exchangeAddress,
      PolymarketConstants.negRiskExchangeAddress,
      PolymarketConstants.ctfCollateralAdapterAddress,
      PolymarketConstants.negRiskCtfCollateralAdapterAddress,
    ];
    expect(PolymarketApprovalInventoryConstants.ctfOperators, containsAll(wanted));
    expect(PolymarketApprovalInventoryConstants.usdcESpenders,
        containsAll(wanted));
  });

  test('a revocation clears every adapter approval, active or retired', () {
    final erc20 = PolymarketApprovalInventoryConstants.erc20SpendersByToken;
    final operators = PolymarketApprovalInventoryConstants.operatorsByToken;
    expect(erc20[PolymarketConstants.usdcEAddress], contains(legacy));
    expect(erc20[PolymarketConstants.pusdAddress], contains(legacy));
    expect(erc20[PolymarketConstants.usdcAddress], isNot(contains(legacy)));
    expect(operators[PolymarketConstants.ctfAddress], contains(legacy));
    // Each address appears once: active and retired lists never overlap.
    for (final list in [...erc20.values, ...operators.values]) {
      expect(list.toSet().length, list.length);
    }
    // The revocation maps are the active lists plus the retired ones —
    // nothing else, so no call ever targets an unlisted spender.
    expect(
      erc20[PolymarketConstants.usdcEAddress],
      [
        ...PolymarketApprovalInventoryConstants.usdcESpenders,
        ...PolymarketApprovalInventoryConstants.retiredUsdcESpenders,
      ],
    );
    expect(
      operators[PolymarketConstants.ctfAddress],
      [
        ...PolymarketApprovalInventoryConstants.ctfOperators,
        ...PolymarketApprovalInventoryConstants.retiredCtfOperators,
      ],
    );
  });
}
