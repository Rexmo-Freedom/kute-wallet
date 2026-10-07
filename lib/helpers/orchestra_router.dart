import 'package:kute/helpers/orchestra_pinned_decimals.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:kute/models/orchestra_routes_model.dart'
    show OrchestraRoutesCatalog, fallbackOrchestraAssetDecimals;
import 'package:kute/services/tracking_service.dart';
export 'package:kute/helpers/orchestra_pinned_decimals.dart'
    show kPinnedOrchestraDecimals, orchestraPinKey, pinnedOrchestraDecimals;

/// Maps app network names to Orchestra chain identifiers.
const kNetworkToChain = {
  'SOL': 'solana',
  'ETH': 'ethereum',
  'MATIC': 'polygon',
  'POLYGON': 'polygon',
  'ARB': 'arbitrum',
  'ARBITRUM': 'arbitrum',
  'BASE': 'base',
  'OP': 'optimism',
  'OPTIMISM': 'optimism',
  'TRX': 'tron',
  'TRON': 'tron',
};

/// Maps an app network name to an Orchestra chain identifier.
String mapNetworkToChain(String network) {
  return kNetworkToChain[network.toUpperCase()] ?? network.toLowerCase();
}

/// Last-installed live routes catalog, decimals authority. Set by
/// orchestra_supported_routes_provider on every successful fetch (and
/// on the persisted-cache load), mirroring the
/// setLiveOrchestraRouteCatalog bridge in orchestra_routes.dart, so
/// the module-level amount helpers below answer with chain-aware
/// decimals without threading a ref through every call site.
OrchestraRoutesCatalog? _decimalsCatalog;

String _pinKey(String chain, String asset) => orchestraPinKey(chain, asset);

/// Pinned pairs whose live catalog row carries different decimals.
final Set<String> _decimalsMismatches = {};

/// True when the installed catalog disagrees with the pin for this pair.
/// The quote gate treats such a route as unavailable.
bool orchestraDecimalsMismatch(String chain, String asset) =>
    _decimalsMismatches.contains(_pinKey(chain, asset));

@visibleForTesting
void resetOrchestraDecimalsForTest() {
  _decimalsCatalog = null;
  _decimalsMismatches.clear();
}

/// Install the live catalog as the decimals source. Catalogs without
/// usable data are ignored — the ticker fallback stays in force.
void setOrchestraDecimalsCatalog(OrchestraRoutesCatalog catalog) {
  if (!catalog.hasLiveData) return;
  _decimalsCatalog = catalog;
  final mismatches = <String>{};
  for (final row in catalog.assets) {
    final key = _pinKey(row.chain, row.asset);
    final pin = kPinnedOrchestraDecimals[key];
    if (pin != null && row.decimals != pin) mismatches.add(key);
  }
  for (final key in mismatches.difference(_decimalsMismatches)) {
    final sep = key.indexOf(':');
    TrackingService.orchestraDecimalsMismatch(
      chain: key.substring(0, sep),
      asset: key.substring(sep + 1),
    );
  }
  _decimalsMismatches
    ..clear()
    ..addAll(mismatches);
}

/// Decimals for an Orchestra [asset], chain-aware when [chain] is given.
/// Pinned pairs always answer with [kPinnedOrchestraDecimals]; other
/// pairs use the live catalog once it has landed (the ticker alone is
/// ambiguous: BSC USDC is 18 decimals, not 6). Without a chain, or
/// before the catalog loads, falls back to the ticker table.
int orchestraAssetDecimals(String asset, {String? chain}) {
  if (chain != null && chain.isNotEmpty) {
    final pinned = pinnedOrchestraDecimals(chain, asset);
    if (pinned != null) return pinned;
  }
  final catalog = _decimalsCatalog;
  if (chain != null && chain.isNotEmpty && catalog != null) {
    return catalog.decimalsFor(chain, asset);
  }
  return fallbackOrchestraAssetDecimals(asset);
}

/// Converts a raw Orchestra amount (smallest unit) to a human-readable
/// double. Pass [chain] wherever the call site knows it (quote/estimate
/// legs) so per-chain decimals from the live catalog apply.
double orchestraAmountToDouble(String rawAmount, String asset,
    {String? chain}) {
  final decimals = orchestraAssetDecimals(asset, chain: chain);
  final raw = double.tryParse(rawAmount) ?? 0;
  return raw / _pow10(decimals);
}

/// An Orchestra amount as an activity row reads it. Amounts arrive either
/// in the asset's smallest units (the Flashnet API) or already
/// human-readable (our own polling conversion); a value above
/// 10^(decimals-2) is read as smallest units.
double orchestraRowAmount(String rawAmount, String coin) {
  final parsed = double.tryParse(rawAmount) ?? 0;
  final decimals = orchestraAssetDecimals(coin);
  final threshold = decimals > 2 ? _pow10(decimals - 2) : 10.0;
  return parsed > threshold ? orchestraAmountToDouble(rawAmount, coin) : parsed;
}

/// Formats integer base units without rounding through a floating-point value.
String orchestraAmountToDecimalString(String rawAmount, String asset,
    {String? chain}) {
  final raw = rawAmount.trim();
  if (!RegExp(r'^\d+$').hasMatch(raw)) return '0';
  final decimals = orchestraAssetDecimals(asset, chain: chain);
  final digits = BigInt.parse(raw).toString().padLeft(decimals + 1, '0');
  if (decimals == 0) return digits;
  final split = digits.length - decimals;
  final fraction = digits.substring(split).replaceFirst(RegExp(r'0+$'), '');
  return fraction.isEmpty
      ? digits.substring(0, split)
      : '${digits.substring(0, split)}.$fraction';
}

/// Converts a human-readable amount to Orchestra raw units (smallest
/// unit). Same chain-aware decimals resolution as
/// [orchestraAmountToDouble].
String doubleToOrchestraAmount(double amount, String asset,
    {String? chain}) {
  final decimals = orchestraAssetDecimals(asset, chain: chain);
  return (amount * _pow10(decimals)).round().toString();
}

double _pow10(int exp) {
  double result = 1;
  for (int i = 0; i < exp; i++) {
    result *= 10;
  }
  return result;
}
