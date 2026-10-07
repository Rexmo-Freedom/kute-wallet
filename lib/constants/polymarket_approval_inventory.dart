// lib/constants/polymarket_approval_inventory.dart
//
// Every spending approval a Polymarket account can hold (Wallet hardening
// Phase 2 D14 inventory). Deposit wallet onboarding sets exactly the ACTIVE
// lists, and the compromise revocation builder never touches anything
// outside the full (active + retired) maps.
// A legacy Safe holds a subset of the same list.
//
// There is no version or fingerprint here: onboarding reads each active
// entry on-chain and only submits the ones whose allowance is zero, so
// dropping an entry never re-prompts an existing user, and an approval a
// user already holds stays untouched until they run a revocation.

import 'package:kute/constants/polymarket_constants.dart';

abstract final class PolymarketApprovalInventoryConstants {
  // ── Active: set by onboarding, revoked on compromise ──────────────────

  /// USDC.e spenders (7).
  static const List<String> usdcESpenders = [
    PolymarketConstants.collateralOnrampAddress,
    PolymarketConstants.ctfAddress,
    PolymarketConstants.exchangeAddress,
    PolymarketConstants.negRiskExchangeAddress,
    PolymarketConstants.ctfCollateralAdapterAddress,
    PolymarketConstants.negRiskCtfCollateralAdapterAddress,
    PolymarketConstants.uniswapV3SwapRouter,
  ];

  /// pUSD spenders (3).
  static const List<String> pusdSpenders = [
    PolymarketConstants.exchangeAddress,
    PolymarketConstants.negRiskExchangeAddress,
    PolymarketConstants.collateralOfframpAddress,
  ];

  /// Native USDC spenders (1).
  static const List<String> usdcSpenders = [
    PolymarketConstants.uniswapV3SwapRouter,
  ];

  /// CTF outcome share operators (4).
  static const List<String> ctfOperators = [
    PolymarketConstants.exchangeAddress,
    PolymarketConstants.negRiskExchangeAddress,
    PolymarketConstants.ctfCollateralAdapterAddress,
    PolymarketConstants.negRiskCtfCollateralAdapterAddress,
  ];

  // ── Combos: set on the first combo, revoked on compromise ─────────────
  //
  // Combos (Positions Framework) trade on Exchange v3 and settle through
  // the Router; their positions are ERC-1155 ids on the PositionManager,
  // not CTF tokens. These are NOT in the onboarding lists: the combo flow
  // sets them once, in one gasless batch, the first time an account places,
  // closes or claims a combo (`PolymarketOnboardingService
  // .ensureComboApprovals`), so an account that never uses combos never
  // grants them.

  /// pUSD spenders for combos: Exchange v3 pulls the BUY stake.
  static const List<String> comboPusdSpenders = [
    PolymarketConstants.comboExchangeV3Address,
  ];

  /// PositionManager operators for combos: Exchange v3 moves combo shares
  /// on a SELL (early close), the Router burns them on a claim.
  static const List<String> comboPositionOperators = [
    PolymarketConstants.comboExchangeV3Address,
    PolymarketConstants.comboRouterAddress,
  ];

  // ── Retired: never set again, still revoked on compromise ─────────────
  //
  // The CLOB v1 Neg Risk Adapter is deprecated (relayer redeems to it ended
  // 2026-07-17). Accounts onboarded before that hold USDC.e, pUSD and CTF
  // approvals to it; they are harmless to leave in place but a revocation
  // must still be able to clear them.

  static const List<String> retiredUsdcESpenders = [
    PolymarketConstants.legacyNegRiskAdapterAddress,
  ];

  static const List<String> retiredPusdSpenders = [
    PolymarketConstants.legacyNegRiskAdapterAddress,
  ];

  static const List<String> retiredCtfOperators = [
    PolymarketConstants.legacyNegRiskAdapterAddress,
  ];

  /// What onboarding sets today, by token. Read by
  /// `_setDepositWalletApprovalsIfMissing`.
  static const Map<String, List<String>> activeErc20SpendersByToken = {
    PolymarketConstants.usdcEAddress: usdcESpenders,
    PolymarketConstants.pusdAddress: pusdSpenders,
    PolymarketConstants.usdcAddress: usdcSpenders,
  };

  static const Map<String, List<String>> activeOperatorsByToken = {
    PolymarketConstants.ctfAddress: ctfOperators,
  };

  /// Everything an account can hold, active and retired, by token. Read by
  /// the compromise revocation builder.
  static const Map<String, List<String>> erc20SpendersByToken = {
    PolymarketConstants.usdcEAddress: [
      ...usdcESpenders,
      ...retiredUsdcESpenders,
    ],
    PolymarketConstants.pusdAddress: [
      ...pusdSpenders,
      ...comboPusdSpenders,
      ...retiredPusdSpenders,
    ],
    PolymarketConstants.usdcAddress: usdcSpenders,
  };

  static const Map<String, List<String>> operatorsByToken = {
    PolymarketConstants.ctfAddress: [
      ...ctfOperators,
      ...retiredCtfOperators,
    ],
    PolymarketConstants.comboPositionManagerAddress: comboPositionOperators,
  };
}
