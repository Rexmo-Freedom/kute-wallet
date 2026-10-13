// lib/helpers/orchestra_pinned_decimals.dart
//
// Decimals the app trusts for the routes it moves money on. Pure: no
// Flutter, no tracking, so the route catalog model can compare live rows
// with the pin without importing the router. Re-exported by
// lib/helpers/orchestra_router.dart.

/// Decimals the app trusts for the routes it moves money on, keyed
/// `chain:ASSET` (chain lowercase, asset uppercase). The catalog is
/// served through Kute's backend and decimals scale every amount, so a
/// pinned pair never takes its decimals from the catalog.
const Map<String, int> kPinnedOrchestraDecimals = {
  'spark:BTC': 8,
  // The dollar account's own token. The live catalog says 6 and the
  // balance/transfer code has always assumed 6; pinning it keeps a
  // proxied catalog from rescaling the dollar leg of a swap.
  'spark:USDB': 6,
  'bitcoin:BTC': 8,
  'polygon:USDC.E': 6,
  'polygon:USDC': 6,
  'arbitrum:USDC': 6,
  'base:USDC': 6,
  'ethereum:USDC': 6,
  'optimism:USDC': 6,
  'solana:USDC': 6,
  'arbitrum:USDT': 6,
  'optimism:USDT': 6,
  'tron:USDT': 6,
  'plasma:USDT': 6,
  'hypercore:USDC': 8,
  'bsc:USDC': 18,
};

/// The [kPinnedOrchestraDecimals] key for ([chain], [asset]).
String orchestraPinKey(String chain, String asset) =>
    '${chain.trim().toLowerCase()}:${asset.trim().toUpperCase()}';

/// The pinned decimals for ([chain], [asset]), or null when unpinned.
int? pinnedOrchestraDecimals(String chain, String asset) =>
    kPinnedOrchestraDecimals[orchestraPinKey(chain, asset)];
