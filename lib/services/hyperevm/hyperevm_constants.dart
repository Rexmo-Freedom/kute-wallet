// lib/services/hyperevm/hyperevm_constants.dart
//
// Every address, decimal and gas figure the spending wallet's Investing
// moves use on HyperEVM. Each one was checked against an official source
// on 2026-10-12 before money moved through it:
//
//  - Chain id 999 and the RPC endpoint: Hyperliquid docs, HyperEVM page
//    (https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/hyperevm).
//  - Native USDC 0xb883…630f: Circle's USDC contract list
//    (https://developers.circle.com/stablecoins/usdc-contract-addresses).
//  - CoreDepositWallet 0x6B9E…0A24: Circle's HyperCore contract list
//    (https://developers.circle.com/cctp/references/hypercore-contract-addresses),
//    and HyperCore's own `spotMeta`, which names it as USDC's linked EVM
//    contract (`evm_extra_wei_decimals` -2: 8 decimals on HyperCore, 6 on
//    HyperEVM). Read on chain: `token()` is the USDC above and
//    `tokenSystemAddress()` is 0x2000…0000.
//  - System addresses: Hyperliquid docs, "HyperCore <> HyperEVM transfers"
//    (a token's system address is 0x20 followed by its index; HYPE uses
//    0x2222…2222). USDC is token 0, so its system address is 0x2000…0000,
//    which Circle's withdrawal guide also names.
//  - Deposit call: Circle's CoreDepositWallet interface and source
//    (github.com/circlefin/hyperevm-circle-contracts, src/CoreDepositWallet.sol):
//    `depositWithAuth(amount, validAfter, validBefore, nonce, v, r, s,
//    destinationDex)`; dex 0 is perpetuals, `type(uint32).max` is spot.
//    Sending USDC straight to the contract does NOT deposit and the funds
//    are lost: nothing in this app may ever transfer to that address.
//  - USDC's EIP-712 domain ("USDC", version "2") and its separator were
//    read on chain (`name()`, `version()`, `DOMAIN_SEPARATOR()`).

/// HyperEVM mainnet.
class HyperEvmChain {
  HyperEvmChain._();

  static const int chainId = 999;

  /// Circle's native USDC on HyperEVM. Six decimals.
  static const String usdc = '0xb88339CB7199b77E23DB6E890353E22632Ba630f';
  static const int usdcDecimals = 6;

  /// Circle's CoreDepositWallet: the only way USDC moves from HyperEVM to
  /// HyperCore. A plain transfer to this address is lost for good.
  static const String coreDepositWallet =
      '0x6B9E773128f453f5c2C60935Ee2DE2CBc5390A24';

  /// HyperCore's USDC system address (token index 0). A `sendAsset` to it
  /// from HyperCore pays native USDC out of the CoreDepositWallet to the
  /// sender's own HyperEVM address.
  static const String usdcSystemAddress =
      '0x2000000000000000000000000000000000000000';

  /// HYPE's system address. HYPE sent here on HyperEVM is credited to the
  /// sender's HyperCore spot balance; a HyperCore `sendAsset` of HYPE to it
  /// pays native HYPE on HyperEVM.
  static const String hypeSystemAddress =
      '0x2222222222222222222222222222222222222222';

  /// `DOMAIN_SEPARATOR()` of the USDC contract, read on chain. The app
  /// computes the same value itself and checks the live one before it
  /// signs an authorization, so an upgraded token can never be signed for
  /// with stale terms.
  static const String usdcDomainSeparator =
      '0x70a72998ad787d1a9152a8f88ccfe0766b1cb293b6b4011b34523035da10b0a3';
  static const String usdcEip712Name = 'USDC';
  static const String usdcEip712Version = '2';

  /// CoreDepositWallet destination dexes.
  static const int perpsDex = 0;
  static const int spotDex = 0xFFFFFFFF;

  /// HYPE carries 18 decimals on HyperEVM and 8 on HyperCore; a HyperEVM
  /// amount below 10^10 wei does not reach HyperCore (it is burned), so
  /// every HYPE transfer to HyperCore is a whole multiple of this.
  static final BigInt hypeCoreQuantumWei = BigInt.from(10).pow(10);

  /// One HYPE in wei.
  static final BigInt hypeWei = BigInt.from(10).pow(18);

  /// Every address that must never receive a plain ERC-20 transfer from
  /// this app: the CoreDepositWallet (funds are stuck) and the system
  /// addresses (a USDC transfer there is not how this app moves USDC).
  static final Set<String> forbiddenTransferRecipients = {
    coreDepositWallet.toLowerCase(),
    usdcSystemAddress.toLowerCase(),
    hypeSystemAddress.toLowerCase(),
  };
}

/// HyperCore tokens, in the `tokenName:tokenId` form `sendAsset` takes
/// (Hyperliquid docs, exchange endpoint). Ids read from `spotMeta`.
class HyperCoreTokens {
  HyperCoreTokens._();

  static const String usdc = 'USDC:0x6d1e7cde53ba9467b783cb7c530ce054';
  static const String hype = 'HYPE:0x0d01dc56dcaaca66ad901c959b4011ec';

  /// HyperCore USDC and HYPE both use eight decimals.
  static const int decimals = 8;

  /// `sendAsset` source/destination for the spot balance; '' is the
  /// default perpetuals dex.
  static const String spotDex = 'spot';
  static const String perpsDex = '';
}

/// Gas the Investing moves spend, and the float that pays for it.
///
/// Per move, from the Hyperliquid docs and measured calls:
///  - HyperCore → HyperEVM costs 200,000 gas at the next block's base fee,
///    charged in HYPE from the sender's HyperCore spot balance (Hyperliquid
///    docs, "How to use the HyperEVM": moving from Spot to the EVM costs
///    gas paid in HYPE on HyperCore). A withdrawal pays this once.
///  - The ERC-20 transfer to the provider is about 60,000 gas on HyperEVM.
///  - `depositWithAuth` is about 150,000 gas on HyperEVM. A deposit pays
///    this once.
///  - Moving part of the float from HyperEVM to HyperCore is a plain value
///    transfer to 0x2222…2222, about 30,000 gas.
///
/// What $1 of HYPE lasts, at 0.13 gwei and HYPE at $87.6 (2026-10-12):
/// $1 buys about 0.0113 HYPE after the $0.01 provider fee. A withdrawal
/// burns 260,000 gas (3.4e13 wei, about $0.003) and a deposit 150,000
/// (2.0e13 wei, about $0.0017), so the float covers about 330 withdrawals,
/// about 580 deposits, or about 400 moves of a mix. If gas spikes 8×,
/// that falls to about 40–70 moves.
class HyperEvmGas {
  HyperEvmGas._();

  static final BigInt coreToEvm = BigInt.from(200000);
  static final BigInt erc20Transfer = BigInt.from(60000);
  static final BigInt depositToCore = BigInt.from(150000);
  static final BigInt hypeToCore = BigInt.from(30000);

  /// A side of the float is topped up when it holds less than this many
  /// of its largest transaction.
  static const int thresholdTransactions = 5;

  /// Thresholds price gas at twice the current price, and never below
  /// this floor, so a quiet moment does not leave the float thin.
  static final BigInt thresholdGasPriceFloorWei = BigInt.from(500000000);

  /// Above this the network is in a spike and no move starts: the move
  /// would cost many times what it shows, and the float would drain.
  static final BigInt maxGasPriceWei = BigInt.from(5000000000);

  /// The float purchase: $1 of HYPE, bought from Dollars first and from
  /// Bitcoin when Dollars are short. Its cost is folded into the move's
  /// total fee (never a separate line) and is never Kute revenue.
  static final BigInt floatUsdMicros = BigInt.from(1000000);
  static const double floatUsd = 1.0;

  /// What a funding balance must hold beyond the move itself before it
  /// pays for the float: the $1 plus a margin for rounding and fees.
  static final BigInt floatSourceMicros = BigInt.from(1050000);

  /// Orchestra's smallest BTC source amount on these routes.
  static const int minFloatSats = 1200;

  /// How the float splits between the two sides, by the gas each side
  /// spends over one withdrawal and one deposit: HyperCore pays 200,000
  /// (the withdrawal's HyperCore → HyperEVM step) and HyperEVM 210,000
  /// (60,000 for the withdrawal's transfer plus 150,000 for the deposit),
  /// so HyperCore gets 200/410 of each purchase, about 49%.
  static const int coreShareNumerator = 200;
  static const int coreShareDenominator = 410;
}
