// test/constants/polymarket_approval_inventory_test.dart
//
// The CLOB v1 Neg Risk Adapter is deprecated (relayer redeems to it ended
// 2026-07-17). Onboarding must never approve it again, but a compromise
// revocation must still be able to clear the approvals older accounts hold.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/constants/polymarket_approval_inventory.dart';
import 'package:kute/constants/polymarket_constants.dart';

void main() {
  const legacy = PolymarketConstants.legacyNegRiskAdapterAddress;

  test('onboarding never approves the deprecated Neg Risk Adapter', () {
    expect(PolymarketApprovalInventoryConstants.usdcESpenders,
        isNot(contains(legacy)));
    expect(PolymarketApprovalInventoryConstants.pusdSpenders,
        isNot(contains(legacy)));
    expect(PolymarketApprovalInventoryConstants.ctfOperators,
        isNot(contains(legacy)));
    for (final spenders in PolymarketApprovalInventoryConstants
        .activeErc20SpendersByToken.values) {
      expect(spenders, isNot(contains(legacy)));
    }
    for (final operators
        in PolymarketApprovalInventoryConstants.activeOperatorsByToken.values) {
      expect(operators, isNot(contains(legacy)));
    }
  });

  test('onboarding still sets both redeem adapters and the exchanges', () {
    const wanted = [
      PolymarketConstants.exchangeAddress,
      PolymarketConstants.negRiskExchangeAddress,
      PolymarketConstants.ctfCollateralAdapterAddress,
      PolymarketConstants.negRiskCtfCollateralAdapterAddress,
    ];
    expect(PolymarketApprovalInventoryConstants.ctfOperators, wanted);
    expect(PolymarketApprovalInventoryConstants.usdcESpenders,
        containsAll(wanted));
  });

  test('a revocation still clears the retired adapter approvals', () {
    final erc20 = PolymarketApprovalInventoryConstants.erc20SpendersByToken;
    final operators = PolymarketApprovalInventoryConstants.operatorsByToken;
    expect(erc20[PolymarketConstants.usdcEAddress], contains(legacy));
    expect(erc20[PolymarketConstants.pusdAddress], contains(legacy));
    expect(erc20[PolymarketConstants.usdcAddress], isNot(contains(legacy)));
    expect(operators[PolymarketConstants.ctfAddress], contains(legacy));
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
