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

  /// pUSD spenders (5).
  static const List<String> pusdSpenders = [
    PolymarketConstants.exchangeAddress,
    PolymarketConstants.negRiskExchangeAddress,
    PolymarketConstants.collateralOfframpAddress,
    // The CLOB still checks a pUSD allowance to the v1 Neg Risk Adapter
    // before it accepts a neg-risk BUY ("the allowance is not enough ->
    // spender: 0xd91E…, allowance: 0"), although Polymarket lists the
    // adapter as deprecated. Without it every 3-way market buy is refused.
    PolymarketConstants.legacyNegRiskAdapterAddress,
    // Protocol V2 markets (binary and neg-risk) and combos: ExchangeV3
    // pulls the BUY stake and fees. docs.polymarket.com/migrate/
    // polymarket-v2/api-integrations ("Approve V2 Trading"); also in
    // @polymarket/client setupTradingApprovals.
    PolymarketConstants.comboExchangeV3Address,
  ];

  /// Native USDC spenders (1).
  static const List<String> usdcSpenders = [
    PolymarketConstants.uniswapV3SwapRouter,
  ];

  /// CTF outcome share operators (5).
  static const List<String> ctfOperators = [
    PolymarketConstants.exchangeAddress,
    PolymarketConstants.negRiskExchangeAddress,
    PolymarketConstants.ctfCollateralAdapterAddress,
    PolymarketConstants.negRiskCtfCollateralAdapterAddress,
    // Same CLOB check on the share side of neg-risk orders (sells).
    PolymarketConstants.legacyNegRiskAdapterAddress,
  ];

  /// PositionManager (Protocol V2 positions and combos) operators (2):
  /// ExchangeV3 moves shares on a SELL, the Router burns them on a claim
  /// (`redeem`). docs.polymarket.com/migrate/polymarket-v2 (api- and
  /// contract-integrations); both are in @polymarket/client
  /// setupTradingApprovals.
  static const List<String> positionManagerOperators = [
    PolymarketConstants.comboExchangeV3Address,
    PolymarketConstants.comboRouterAddress,
  ];

  // ── Combos ────────────────────────────────────────────────────────────
  //
  // Combos (Positions Framework) trade on Exchange v3 and settle through
  // the Router, like every Protocol V2 market, so their approvals are the
  // V2 entries of the active lists above: onboarding sets them for every
  // account, and `PolymarketOnboardingService.ensureComboApprovals` only
  // re-checks them before a combo (a no-op once set).

  /// pUSD spenders a combo needs: Exchange v3 pulls the BUY stake.
  static const List<String> comboPusdSpenders = [
    PolymarketConstants.comboExchangeV3Address,
  ];

  /// PositionManager operators a combo needs.
  static const List<String> comboPositionOperators = positionManagerOperators;

  // ── Retired: never set again, still revoked on compromise ─────────────
  //
  // The CLOB v1 Neg Risk Adapter is labelled deprecated (relayer redeems to
  // it ended 2026-07-17), but the CLOB still requires pUSD and CTF approvals
  // to it for neg-risk orders, so those two are active again (above). Only
  // its USDC.e approval is retired: accounts onboarded before then hold it,
  // and a revocation must still be able to clear it.

  static const List<String> retiredUsdcESpenders = [
    PolymarketConstants.legacyNegRiskAdapterAddress,
  ];

  static const List<String> retiredPusdSpenders = [];

  static const List<String> retiredCtfOperators = [];

  /// What onboarding sets today, by token. Read by
  /// `_setDepositWalletApprovalsIfMissing`.
  static const Map<String, List<String>> activeErc20SpendersByToken = {
    PolymarketConstants.usdcEAddress: usdcESpenders,
    PolymarketConstants.pusdAddress: pusdSpenders,
    PolymarketConstants.usdcAddress: usdcSpenders,
  };

  static const Map<String, List<String>> activeOperatorsByToken = {
    PolymarketConstants.ctfAddress: ctfOperators,
    PolymarketConstants.comboPositionManagerAddress: positionManagerOperators,
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
      ...retiredPusdSpenders,
    ],
    PolymarketConstants.usdcAddress: usdcSpenders,
  };

  static const Map<String, List<String>> operatorsByToken = {
    PolymarketConstants.ctfAddress: [
      ...ctfOperators,
      ...retiredCtfOperators,
    ],
    PolymarketConstants.comboPositionManagerAddress: positionManagerOperators,
  };
}
