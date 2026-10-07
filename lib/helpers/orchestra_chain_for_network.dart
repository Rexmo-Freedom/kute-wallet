import 'package:kute/helpers/orchestra_router.dart';
import 'package:kute/services/security/address_guard.dart'
    show kEvmAddressChains;

/// Orchestra chain slugs a stored swap row's network can name.
const Set<String> _kOrchestraChains = {
  'spark',
  'bitcoin',
  'lightning',
  'solana',
  'tron',
  ...kEvmAddressChains,
};

/// Row networks that are not spelled as their chain slug.
const Map<String, String> _kRowNetworkAliases = {
  'HYPERLIQUID': 'hypercore',
  'BITCOIN': 'bitcoin',
  'LN': 'lightning',
};

/// The Orchestra chain for a swap row's `networkFrom` or `networkTo`
/// (`SPARK` to `spark`, `POLYGON` to `polygon`, `HYPERCORE` to `hypercore`).
/// Returns null when the network names no single Orchestra chain, such as
/// `BTC`, which rows use for both Spark and on-chain bitcoin.
String? orchestraChainForNetwork(String network) {
  final upper = network.trim().toUpperCase();
  if (upper.isEmpty) return null;
  final alias = _kRowNetworkAliases[upper];
  if (alias != null) return alias;
  final chain = mapNetworkToChain(upper);
  return _kOrchestraChains.contains(chain) ? chain : null;
}

/// A raw Orchestra amount on a stored row, scaled with the decimals of its
/// chain so HyperCore USDC (8 decimals) is not read as 6. The amount is
/// denominated in the order's own [orderChain], so a known order chain wins;
/// the row's network is used when the order names none.
double orchestraRowAmountToDouble(
  String rawAmount,
  String asset, {
  required String network,
  String? orderChain,
}) {
  final chain =
      (orderChain == null ? null : orchestraChainForNetwork(orderChain)) ??
          orchestraChainForNetwork(network);
  return orchestraAmountToDouble(rawAmount, asset, chain: chain);
}

/// Exact receipt text using the same order-chain precedence as the balance
/// converter. Never truncate small deposits on eighteen-decimal routes.
String orchestraRowAmountToDecimalString(
  String rawAmount,
  String asset, {
  required String network,
  String? orderChain,
}) {
  final chain =
      (orderChain == null ? null : orchestraChainForNetwork(orderChain)) ??
          orchestraChainForNetwork(network);
  return orchestraAmountToDecimalString(rawAmount, asset, chain: chain);
}
