// Uniswap V3 SwapRouter02 helpers for same-chain stablecoin conversions
// inside the Polymarket Safe. Used by:
//   - Bet path:     USDC → USDC.e (so we can wrap to pUSD for the V2 order)
//   - Winnings path: USDC.e → USDC (so the user's USDC sub-balance updates
//                                    after pUSD is unwrapped post-sell)
//
// The 0.01 % fee tier USDC/USDC.e pool on Polygon is the canonical
// stable-stable route. Slippage tolerance is set to 10 bps (0.10 %) — far
// wider than the pool's typical drift (well under 1 bps for liquid stables)
// so a transient liquidity hiccup doesn't revert the bet flow.
//
// All calls use SwapRouter02's deadlineless `exactInputSingle`. The Safe
// signs the calldata via the existing `submitSafeTx` path — gasless via
// the Polymarket relayer.

import 'package:kute/constants/polymarket_constants.dart';

class DexSwapService {
  DexSwapService._();

  /// Allowed slippage on the swap, in basis points. 10 = 0.10 %.
  static const int slippageBps = 10;

  static final RegExp _evmAddressRe = RegExp(r'^[0-9a-fA-F]{40}$');

  /// True iff [raw] is a syntactically valid 20-byte EVM address
  /// (`0x` optional). Use this to gate user-supplied destinations in the
  /// UI before they ever reach a send path.
  static bool isValidEvmAddress(String raw) {
    final hex = (raw.startsWith('0x') || raw.startsWith('0X'))
        ? raw.substring(2)
        : raw;
    return _evmAddressRe.hasMatch(hex);
  }

  /// Validate [raw] as an EVM address and return its 32-byte ABI-encoded
  /// form (64 lowercase hex chars, left-padded). Throws [FormatException]
  /// on anything that isn't exactly a 20-byte hex address.
  ///
  /// CRITICAL: every ABI encoder below left-pads the recipient to 64
  /// chars. A malformed/short input (e.g. a pasted tx hash or truncated
  /// address) would otherwise be silently zero-padded into a DIFFERENT
  /// but well-formed address and funds would be sent somewhere nobody
  /// controls. Validate here so no malformed calldata can ever be built.
  static String abiEncodeAddress(String raw) {
    final hex = (raw.startsWith('0x') || raw.startsWith('0X'))
        ? raw.substring(2)
        : raw;
    if (!_evmAddressRe.hasMatch(hex)) {
      throw FormatException('Invalid EVM address', raw);
    }
    return hex.toLowerCase().padLeft(64, '0');
  }

  /// Function selector for SwapRouter02's
  /// `exactInputSingle((address,address,uint24,address,uint256,uint256,uint160))`.
  /// Note SwapRouter02 dropped the deadline param vs the original V3
  /// SwapRouter — the selectors are different. This is the SwapRouter02
  /// (deadlineless) selector.
  static const String _selectorExactInputSingle = '04e45aaf';

  /// Encode `swap(tokenIn → tokenOut, amountIn, recipient)` for
  /// SwapRouter02. Returns hex calldata (no `0x` prefix) ready for
  /// `submitSafeTx`. `recipient` is who receives `tokenOut` — pass the
  /// Safe address.
  static String encodeSwap({
    required String tokenIn,
    required String tokenOut,
    required String recipient,
    required BigInt amountIn,
  }) {
    // amountOutMinimum = amountIn × (1 - slippageBps / 10000). For stables
    // this is essentially amountIn × 0.999 — preserves precision and bails
    // if the pool would somehow strip more than 0.10 %.
    final slippageNumerator = BigInt.from(10000 - slippageBps);
    final amountOutMin = amountIn * slippageNumerator ~/ BigInt.from(10000);

    final tokenInHex = abiEncodeAddress(tokenIn);
    final tokenOutHex = abiEncodeAddress(tokenOut);
    final feeHex = PolymarketConstants.usdcUsdceFeeTier
        .toRadixString(16)
        .padLeft(64, '0');
    // Validates the recipient — a malformed destination throws here
    // rather than being silently zero-padded into a different address.
    final recipientHex = abiEncodeAddress(recipient);
    final amountInHex = amountIn.toRadixString(16).padLeft(64, '0');
    final amountOutMinHex = amountOutMin.toRadixString(16).padLeft(64, '0');
    // sqrtPriceLimitX96 = 0 disables the price-limit guard. For a
    // stable-stable swap with our slippage minimum already enforced,
    // this is fine.
    final sqrtPriceLimitHex = '0'.padLeft(64, '0');

    return '$_selectorExactInputSingle'
        '$tokenInHex'
        '$tokenOutHex'
        '$feeHex'
        '$recipientHex'
        '$amountInHex'
        '$amountOutMinHex'
        '$sqrtPriceLimitHex';
  }

  /// Encode swap from native USDC → USDC.e (the bet path's first step).
  static String encodeUsdcToUsdce({
    required BigInt amount,
    required String recipient,
  }) {
    return encodeSwap(
      tokenIn: PolymarketConstants.usdcAddress,
      tokenOut: PolymarketConstants.usdcEAddress,
      recipient: recipient,
      amountIn: amount,
    );
  }

  /// Encode swap from USDC.e → native USDC (the winnings path's last step).
  static String encodeUsdceToUsdc({
    required BigInt amount,
    required String recipient,
  }) {
    return encodeSwap(
      tokenIn: PolymarketConstants.usdcEAddress,
      tokenOut: PolymarketConstants.usdcAddress,
      recipient: recipient,
      amountIn: amount,
    );
  }
}
