// lib/constants/hyperliquid_constants.dart
//
// Environment + on-chain constants for the Hyperliquid integration.
// Mirrors the shape of polymarket_constants.dart: static getters backed by
// dotenv where the value differs per environment, plain consts otherwise.
//
// Mainnet/testnet is a build-time flag (`HYPERLIQUID_TESTNET=true` in .env).
// Note the L1-action EIP-712 domain chainId is ALWAYS 1337 on both networks;
// mainnet vs testnet is disambiguated by the phantom-agent `source` field
// ('a' vs 'b') and, for user-signed actions, by the `hyperliquidChain` field.

import 'package:flutter_dotenv/flutter_dotenv.dart';

class HyperliquidConstants {
  HyperliquidConstants._();

  static bool get isMainnet {
    try {
      return (dotenv.env['HYPERLIQUID_TESTNET'] ?? '') != 'true';
    } catch (_) {
      // dotenv not initialized (unit tests) — default to mainnet shapes.
      return true;
    }
  }

  static String get apiBase => isMainnet
      ? 'https://api.hyperliquid.xyz'
      : 'https://api.hyperliquid-testnet.xyz';

  static Uri get infoUri => Uri.parse('$apiBase/info');
  static Uri get exchangeUri => Uri.parse('$apiBase/exchange');

  static String get wsUrl => isMainnet
      ? 'wss://api.hyperliquid.xyz/ws'
      : 'wss://api.hyperliquid-testnet.xyz/ws';

  /// Value of the `hyperliquidChain` field in user-signed actions.
  static String get hyperliquidChain => isMainnet ? 'Mainnet' : 'Testnet';

  /// L1-action EIP-712 domain chainId. Constant across environments.
  static const int l1ChainId = 1337;

  /// `signatureChainId` for user-signed actions: "the id of the chain used
  /// when signing in hexadecimal format; e.g. "0xa4b1" for Arbitrum", and
  /// every documented example uses 0xa4b1. `hyperliquidChain` is what scopes
  /// the signature to mainnet/testnet. The official Python SDK still
  /// hardcodes 0x66eee (Arbitrum Sepolia); the known-answer tests pass that
  /// value explicitly for the vectors it generated.
  /// https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
  static const int signatureChainId = 0xa4b1;
  static const String signatureChainIdHex = '0xa4b1';

  /// Exchange-enforced order minimum (notional, USD).
  static const double minOrderNotionalUsd = 10.0;

  // The builder (Kute's fee recipient), its per-order fee and the approval
  // cap are NOT app constants: they come only from the backend's
  // /api/v1/hl/builder (HyperliquidFundingService.getBuilder). With no valid
  // backend answer, orders carry no builder and no approval is requested.

  /// Spot asset ids on the order wire are 10000 + spot-pair index.
  static const int spotAssetIdOffset = 10000;
}
