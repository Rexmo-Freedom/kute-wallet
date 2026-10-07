// Polymarket on-chain constants on Polygon mainnet (chain id 137).
//
// V2 protocol (CTFv2 + pUSD), live since 2026-04-28 ~11:00 UTC.
// Replaces V1 addresses — see https://docs.polymarket.com/v2-migration
//
// Only immutable protocol facts live here: contract addresses, chain id,
// EIP-712 domains and token decimals. The app signs against these, so they
// are never fetched from a server. Business settings (fees, the builder
// code) come from the backend at runtime.
//
// Wallet model (V2 deposit wallet, POLY_1271):
//   - Each account trades from a Polymarket deposit wallet: an ERC-1967
//     proxy minted by the DepositWallet factory below, owned by the user's
//     key and signing orders as POLY_1271 (signature type 3). The legacy
//     Gnosis Safe path is kept only to read and exit older wallets.
//   - The Predictions balance sits in the deposit wallet as pUSD, the
//     V2 Exchange collateral, and orders are signed against it directly.
//   - Funding arrives as USDC.e (an Orchestra conversion from bitcoin) and
//     is wrapped 1:1 to pUSD through CollateralOnramp.wrap() on arrival;
//     withdrawals unwrap through CollateralOfframp back to USDC.e.
//
// pUSD is a 1:1 ERC-20 wrapper of USDC.e — atomic, no slippage, no fee.

class PolymarketConstants {
  PolymarketConstants._();

  // Network
  static const int polygonChainId = 137;
  static const String polygonRpc = 'https://polygon-bor-rpc.publicnode.com';

  // V2 Exchange contracts (CTFv2)
  static const String exchangeAddress =
      '0xE111180000d2663C0091e4f400237545B87B996B';
  static const String negRiskExchangeAddress =
      '0xe2222d279d744050d28e00520010520000310F59';

  // Neg Risk Adapter (CLOB v1) — DEPRECATED. Listed by Polymarket as
  // "Neg Risk Adapter (CLOB v1, deprecated)"; relayer redeems aimed at it
  // stopped on 2026-07-17 and the SDK no longer requests approvals to it.
  // Nothing in the app calls or approves this contract any more. It is kept
  // ONLY so the compromise-revocation inventory can still clear the
  // approvals older accounts granted to it (see
  // polymarket_approval_inventory.dart). Neg-risk redeem/split/merge go
  // through `negRiskCtfCollateralAdapterAddress` below.
  static const String legacyNegRiskAdapterAddress =
      '0xd91E80cF2E7be2e162c6513ceD06f1dD0dA35296';

  // Collateral
  // pUSD: signed-order collateral on V2 Exchange. Wrapped 1:1 from USDC.e.
  static const String pusdAddress =
      '0xC011a7E12a19f7B1f670d46F03B03f3342E82DFB';
  // USDC.e: bridged USDC, the token pUSD wraps. Sits transiently in the
  //         wallet between a deposit or payout and its pUSD wrap/unwrap.
  static const String usdcEAddress =
      '0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174';
  // USDC: Circle's native USDC on Polygon (CCTP). Swapped to USDC.e via
  //       Uniswap (below) where a flow holds native USDC.
  static const String usdcAddress =
      '0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359';

  // Uniswap V3 SwapRouter02 on Polygon (deadlineless variant). Used for the
  // same-chain USDC ↔ USDC.e leg via the 0.01 % fee-tier pool.
  static const String uniswapV3SwapRouter =
      '0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45';
  // 0.01 % fee tier on Uniswap V3, encoded in hundredths of a bip (1e-6).
  // The USDC/USDC.e pool on Polygon uses this tier — canonical stable-stable.
  static const int usdcUsdceFeeTier = 100;
  // CollateralOnramp: wrap(address asset, address to, uint256 amount).
  // Converts USDC.e → pUSD 1:1. Mints pUSD to `to`, debits asset from msg.sender.
  // Caller must approve(USDC.e, this) first.
  static const String collateralOnrampAddress =
      '0x93070a847efEf7F70739046A929D47a521F5B8ee';
  // CollateralOfframp: unwrap(address asset, address to, uint256 amount).
  // Converts pUSD → USDC.e 1:1. Burns pUSD from msg.sender, sends asset to `to`.
  // pUSD doesn't need an explicit approval here (the offramp burns msg.sender's pUSD directly).
  static const String collateralOfframpAddress =
      '0x2957922Eb93258b93368531d39fAcCA3B4dC5854';

  // Conditional Tokens (CTF) — outcome share token
  static const String ctfAddress =
      '0x4D97DCd97eC945f40cF65F87097ACe5EA0476045';

  // CtfCollateralAdapter (deployed by Polymarket 2026-04-29).
  // Standard (non-NegRisk) markets redeem through this adapter. Thin
  // wrapper around the legacy CTF: derives positionIds from
  // `(pUSD, conditionId)`, pulls the user's outcome tokens from
  // msg.sender (the Safe), calls CTF.redeemPositions internally with
  // USDC.e as the collateral param, then wraps the USDC.e payout
  // back into pUSD and sends to msg.sender.
  //
  // Source: github.com/Polymarket/ctf-exchange-v2/src/adapters/
  //   CtfCollateralAdapter.sol (the parent class of
  //   NegRiskCtfCollateralAdapter below).
  //
  // External signature: redeemPositions(address, bytes32, bytes32
  // _conditionId, uint256[]). Same external shape as the legacy
  // CTF.redeemPositions (selector 0x01b7037c) — but the address
  // and uint256[] args are interface-compat placeholders, only
  // `_conditionId` is used.
  static const String ctfCollateralAdapterAddress =
      '0xAdA100Db00Ca00073811820692005400218FcE1f';

  // NegRiskCtfCollateralAdapter (deployed by Polymarket 2026-04-30).
  // NegRisk markets redeem through this adapter, NOT the deprecated
  // `legacyNegRiskAdapterAddress` at 0xd91E…. The adapter is a wrapper
  // that derives positionIds internally from `(WRAPPED_COLLATERAL,
  // conditionId)`, pulls the user's outcome tokens from msg.sender
  // (the Safe), calls the legacy adapter to do the redeem, and wraps
  // the USDC.e payout into pUSD for return.
  //
  // Source: github.com/Polymarket/ctf-exchange-v2/src/adapters/
  //   NegRiskCtfCollateralAdapter.sol
  //
  // `redeemPositions(address, bytes32, bytes32 _conditionId, uint256[])`
  // — same external signature as CTF.redeemPositions, selector
  // 0x01b7037c. Only `_conditionId` is used; the other args are
  // interface-compat placeholders.
  static const String negRiskCtfCollateralAdapterAddress =
      '0xadA2005600Dec949baf300f4C6120000bDB6eAab';

  // Gnosis Safe proxy factory (Polymarket Contract Proxy Factory) — LEGACY V1
  // Kept for reading deployment state of pre-V2 wallets. New wallets go
  // through the DepositWallet contracts below.
  static const String safeFactoryAddress =
      '0xaacFeEa03eb1561C4e67d661e40682Bd20E3541b';

  // ──────────────────────────────────────────────────────────────────
  // V2 Deposit Wallet (POLY_1271) — the canonical Polymarket V2 wallet
  // ──────────────────────────────────────────────────────────────────
  // Polymarket V2 retired the Gnosis Safe path for new wallets. The
  // CLOB rejects orders with `maker = SafeProxy` ("maker address not
  // allowed, please use the deposit wallet flow"). The replacement is
  // a lightweight ERC-1967 minimal proxy deployed by a dedicated
  // factory, configured to sign orders via POLY_1271 (sigType=3).
  //
  // Source: `@polymarket/builder-relayer-client@0.0.9 dist/config/index.js`
  static const String depositWalletFactoryAddress =
      '0x00000000000Fb5C9ADea0298D729A0CB3823Cc07';
  // Legacy UUPS implementation. Only used to derive the pre-beacon
  // deposit-wallet address for existing-user detection (see the NOTE below).
  static const String depositWalletImplementationAddress =
      '0x58CA52ebe0DadfdF531Cde7062e76746de4Db1eB';
  // Deposit Wallet Beacon (documented at docs.polymarket.com/resources/
  // contracts). Current wallets are beacon proxies pointing here. Recorded
  // for reference only: the app never derives against it, it asks the
  // factory via `predictWalletAddress(owner)` instead.
  static const String depositWalletBeaconAddress =
      '0x7A18EDfe055488A3128f01F563e5B479D92ffc3a';

  // EIP-712 domain for the DepositWallet's Batch / Call typed data. Each
  // batched approval/transfer is signed under this domain with the wallet
  // address as the verifyingContract.
  static const String depositWalletDomainName = 'DepositWallet';
  static const String depositWalletDomainVersion = '1';

  // Solady LibClone ERC-1967 byte constants — used by the offline
  // CREATE2 address derivation in `deriveDepositWallet`. Lifted verbatim
  // from `builder-relayer-client/dist/builder/derive.js`.
  static const String erc1967Const1 =
      'cc3735a920a3ca505d382bbc545af43d6000803e6038573d6000fd5b3d6000f3';
  static const String erc1967Const2 =
      '5155f3363d3d373d3d363d7f360894a13ba1a3210667c828492db98dca3e2076';
  // 10-byte prefix: `0x61003d3d8160233d3973` with the args-length nibble
  // OR-ed in at byte 1 (see _initCodeHashErc1967 in the onboarding service).
  static const String erc1967Prefix = '61003d3d8160233d3973';
  // NOTE: we no longer hand-derive the *current* deposit-wallet variant. The
  // factory was upgraded (~2026-07-07) from UUPS to beacon proxies, which
  // silently invalidated a local CREATE2 derivation. Instead the onboarding
  // service asks the factory itself via `predictWalletAddress(owner)` (one
  // eth_call) so the address is always whatever the factory mints today — no
  // per-variant init-code constants to keep in sync. The UUPS constants above
  // are kept ONLY to derive the legacy address for existing-user detection.

  // ──────────────────────────────────────────────────────────────────
  // Combos (Positions Framework, not the CLOB)
  // ──────────────────────────────────────────────────────────────────
  // A combo is one YES position over 2–50 legs, traded by RFQ and settled
  // on Exchange v3. Combo positions are ERC-1155 ids on the PositionManager,
  // not CTF tokens. Source: docs.polymarket.com/resources/contracts
  // ("Combos Contracts") and /trading/combos/*; the same addresses ship in
  // @polymarket/client's mainnet environment.
  static const String comboExchangeV3Address =
      '0xe3333700cA9d93003F00f0F71f8515005F6c00Aa';
  // Router (`redeem(bytes31,uint256,uint256)`, split, merge) — the docs
  // also call it the Collateral Return Router.
  static const String comboRouterAddress =
      '0x12121212006e4CD160D18e3f00711DA5c3372600';
  static const String comboPositionManagerAddress =
      '0x006F54F7f9A22e0000CC2AB60031000000ae9fEF';
  static const String comboCombinatorialModuleAddress =
      '0x30000034706C7d8e12009DAB006Be20000c031A8';
  static const String comboAutoRedeemerAddress =
      '0xa1200000d0002264C9a1698e001292D00E1b00af';

  // Exchange v3 EIP-712 domain version. Same "Polymarket CTF Exchange"
  // name and Order struct as V2; only the version and the contract change,
  // and v3 order timestamps are Unix SECONDS (V2 uses milliseconds).
  static const String comboExchangeEip712DomainVersion = '3';

  // Common
  static const String zeroAddress =
      '0x0000000000000000000000000000000000000000';
  static const String bytes32Zero =
      '0x0000000000000000000000000000000000000000000000000000000000000000';
  static const String maxUint256Hex =
      'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';

  // EIP-712 Exchange domain version. Bumped from "1" to "2" at the V2 cutover.
  // ClobAuthDomain (used for L1 API key derivation) stays at "1" — do not change.
  static const String exchangeEip712DomainVersion = '2';

  // There is deliberately no builder code here. The V2 order's `builder`
  // field is a business setting served only by the backend
  // (GET /api/v1/pm/builder-code, see PolymarketBuilderCodeResolver); when
  // none is available orders are signed with [bytes32Zero], meaning no
  // attribution and no builder fee.
}
