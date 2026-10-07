import 'package:kute/services/security/address_guard.dart';
// lib/services/orchestra_usd_send_routes.dart
//
// The SEND table anchored on the DOLLAR balance.
//
// Everything else in the app derives its send offering from the bitcoin
// anchor: `OrchestraRoutesCatalog.sendChainsFor` walks out of `spark:BTC`
// and answers "where can bitcoin go". The dollar account needs the same
// question asked of its own row — "where can DOLLARS go" — and the answer
// is a different set, so it gets its own walk rather than a flag on the
// bitcoin one.
//
// Two rules this file exists to keep:
//
//  1. LIVE CATALOG ONLY. The static fallback tables in
//     orchestra_routes.dart describe the bitcoin anchor; their single
//     'USDB': {'spark'} row is there so history and the bitcoin leg
//     resolve, not because it is the dollar send offering. Guessing
//     offline would put destinations in front of the user that the
//     router cannot quote, so without live data the list is EMPTY and
//     the dollar send sheet says it is not ready.
//  2. ONLY CHAINS WHOSE ADDRESSES WE CAN CHECK. A send takes a typed
//     recipient, so the offering is clipped to
//     [kOrchestraSendableChains] — the same clip the bitcoin send table
//     takes — and every row is matched against the typed address's own
//     family before it may be picked.
//
// No UI and no Riverpod here on purpose: the sheet passes the catalog in,
// which keeps this pure and testable.

import 'package:kute/helpers/scanned_address.dart'
    show bareRecipientAddress, evmPaymentChainId, kEvmChainIdSlugs;
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/services/orchestra_routes.dart'
    show
        isVenueInternalRoute,
        kOrchestraSendableChains,
        kOrchestraUsdAssetCode,
        kOrchestraUsdChain,
        orchestraChainDisplayName;

/// One destination the dollar balance can be sent to: an asset on a
/// chain, as the live catalog spells them.
class UsdSendDestination {
  /// Asset code exactly as Flashnet spells it ('USDC.e' keeps its
  /// casing) — this is what the quote must be handed.
  final String assetCode;
  final String displayName;
  final String displaySymbol;

  /// Chain slug, lowercase.
  final String chain;
  final String chainDisplayName;
  final int decimals;
  final String? chainIconUrl;
  final String? assetIconUrl;

  const UsdSendDestination({
    required this.assetCode,
    required this.displayName,
    required this.displaySymbol,
    required this.chain,
    required this.chainDisplayName,
    required this.decimals,
    this.chainIconUrl,
    this.assetIconUrl,
  });

  /// Stable key for selection state.
  String get id => '$chain:$assetCode';
}

/// Every (asset, chain) pair the DOLLAR balance can be sent to, as
/// picker rows, sorted by symbol then chain. Venue rails
/// ([isVenueInternalRoute]) are never among them.
///
/// Empty when [catalog] has no live data, or when it carries no dollar
/// row — see rule 1 at the top of this file. Nothing on Spark is
/// offered: not the dollar row itself (a send to your own asset on your
/// own chain is not a swap) and, for now, no Spark recipient at all.
List<UsdSendDestination> usdSendDestinations(OrchestraRoutesCatalog catalog) {
  if (!catalog.hasLiveData) return const <UsdSendDestination>[];
  final source = catalog.find(kOrchestraUsdChain, kOrchestraUsdAssetCode);
  if (source == null) return const <UsdSendDestination>[];
  final rows = <UsdSendDestination>[];
  for (final a in catalog.assets) {
    if (a.id == source.id || !a.hasUsableDecimals) continue;
    final chain = a.chain.toLowerCase();
    // The address-family clip: a typed recipient is only safe on a chain
    // whose addresses [usdSendAddressFamily] can recognise.
    if (!kOrchestraSendableChains.contains(chain)) continue;
    // Investing's and Predictions' own rails are reached by the venue
    // flows, never picked as a destination for a typed recipient.
    if (isVenueInternalRoute(chain, a.asset)) continue;
    // No Spark recipients for now (owner decision, October 2026): a
    // dollar send goes to another network or not at all.
    if (chain == kOrchestraUsdChain) continue;
    if (!source.to.contains(a.id, selfId: source.id)) continue;
    rows.add(UsdSendDestination(
      assetCode: a.asset,
      displayName: a.displayName,
      displaySymbol: a.displaySymbol,
      chain: chain,
      chainDisplayName: a.chainDisplayName.isNotEmpty
          ? a.chainDisplayName
          : orchestraChainDisplayName(chain),
      decimals: a.decimals,
      chainIconUrl: a.chainIconUrl,
      assetIconUrl: a.assetIconUrl,
    ));
  }
  rows.sort((a, b) {
    final bySymbol =
        a.displaySymbol.toLowerCase().compareTo(b.displaySymbol.toLowerCase());
    if (bySymbol != 0) return bySymbol;
    return a.chainDisplayName
        .toLowerCase()
        .compareTo(b.chainDisplayName.toLowerCase());
  });
  return rows;
}

/// The rail family a typed recipient belongs to, or `'unknown'`.
///
/// Deliberately a copy of the send stepper's rule rather than a call
/// into it: that helper is private to a 9,000 line screen this sheet
/// must not depend on, and the whole point of the dollar send is that it
/// shares no code with the bitcoin send path. The order matters — Spark
/// before the base58 buckets (Spark addresses are long bech32m strings),
/// and Tron before Solana (a `T…` address is base58 too).
String usdSendAddressFamily(String raw) => orchestraAddressFamily(raw);

bool usdSendChainAcceptsAddress(String chain, String address) =>
    kOrchestraSendableChains.contains(chain.trim().toLowerCase()) &&
    formatMatchesChain(chain, address.trim(), mainnet: true) ==
        AddressFormatMatch.ok;

/// Exact base units for a typed dollar amount, parsed from the STRING
/// the keypad produced rather than through a double.
///
/// `19.99` is not representable in binary floating point, and
/// `(19.99 * 1e6).round()` has already been the wrong number in other
/// people's wallets. The digits the user typed are the digits that move:
/// the integer part and the fractional part are read as integers and
/// combined, and anything past [decimals] places is refused rather than
/// silently truncated into a different amount.
///
/// Returns null when [typed] is not a plain decimal number.
BigInt? usdBaseUnitsFromTyped(String typed, {int decimals = 6}) {
  final t = typed.trim();
  if (t.isEmpty) return BigInt.zero;
  if (!RegExp(r'^\d*(\.\d*)?$').hasMatch(t)) return null;
  final dot = t.indexOf('.');
  final whole = dot < 0 ? t : t.substring(0, dot);
  final frac = dot < 0 ? '' : t.substring(dot + 1);
  if (frac.length > decimals) return null;
  final wholeUnits = whole.isEmpty ? BigInt.zero : BigInt.parse(whole);
  final fracUnits =
      frac.isEmpty ? BigInt.zero : BigInt.parse(frac.padRight(decimals, '0'));
  return wholeUnits * BigInt.from(10).pow(decimals) + fracUnits;
}

/// What a pasted, scanned or typed recipient means for a dollar send.
///
/// The bitcoin send's recognition, read against the DOLLAR table: the
/// payload is reduced to its bare address the same way
/// ([bareRecipientAddress]), classified by the same address families
/// ([usdSendAddressFamily]), and matched against the destinations the
/// dollar balance can actually reach, so a recipient can only ever land
/// on a route the dollar send already offers.
class UsdRecipientMatch {
  const UsdRecipientMatch({
    required this.address,
    required this.family,
    required this.chainId,
    required this.candidates,
  });

  /// The bare address the field shows and the send uses.
  final String address;

  /// The address family (`evm`, `spark`, `tron`, `solana`, `bitcoin`,
  /// …), or `'unknown'`.
  final String family;

  /// The EIP-155 chain id an `ethereum:` request named, if any.
  final int? chainId;

  /// Every destination this recipient can receive on, in table order.
  final List<UsdSendDestination> candidates;

  bool get isEmpty => address.isEmpty;

  /// The address is a known kind of address.
  bool get recognised => family != 'unknown';

  /// The destination the recipient settles without asking: the only
  /// candidate, or, when every candidate is on one chain (a Solana
  /// address, an `ethereum:` request naming Base), that chain's dollar
  /// coin — USDC, else USDT. Null when the person has to choose (a bare
  /// EVM address with no default to land on) or when nothing fits.
  UsdSendDestination? get autoPick {
    if (candidates.isEmpty) return null;
    if (candidates.length == 1) return candidates.single;
    final chains = {for (final d in candidates) d.chain};
    if (chains.length != 1) return null;
    for (final code in const ['USDC', 'USDT']) {
      for (final d in candidates) {
        if (d.assetCode.toUpperCase() == code) return d;
      }
    }
    return null;
  }

  /// Whether [d] is among [candidates].
  bool accepts(UsdSendDestination d) => candidates.any((c) => c.id == d.id);
}

/// Whether [destination] can receive at [address]: the address is of the
/// destination chain's own family and, when the request named an EVM
/// chain id ([chainId]), that chain is the destination's.
bool usdSendDestinationAccepts(UsdSendDestination destination, String address,
    {int? chainId}) {
  if (!usdSendChainAcceptsAddress(destination.chain, address)) return false;
  if (chainId == null) return true;
  return kEvmChainIdSlugs[chainId] == destination.chain;
}

/// Reads [raw] (a bare address or a payment request) against
/// [destinations]. An `ethereum:…@chainId` request narrows the match to
/// that chain; a chain id the app cannot route to matches nothing.
UsdRecipientMatch matchUsdRecipient(
  String raw,
  List<UsdSendDestination> destinations,
) {
  final address = bareRecipientAddress(raw);
  final chainId = evmPaymentChainId(raw);
  if (address.isEmpty) {
    return UsdRecipientMatch(
        address: '', family: 'unknown', chainId: chainId, candidates: const []);
  }
  final family = usdSendAddressFamily(address);
  final candidates = <UsdSendDestination>[
    if (family != 'unknown')
      for (final d in destinations)
        if (usdSendDestinationAccepts(d, address, chainId: chainId)) d,
  ];
  return UsdRecipientMatch(
    address: address,
    family: family,
    chainId: chainId,
    candidates: candidates,
  );
}

/// The destination Send dollars starts on: USDC on Arbitrum (owner
/// decision, October 2026), so a bare EVM address lands there without a
/// network question. Null when [offered] does not carry it (the route is
/// missing from the catalog or the runtime policy withdraws it), and the
/// send then asks as before.
UsdSendDestination? usdSendDefaultDestination(
        List<UsdSendDestination> offered) =>
    offered
        .where(
            (d) => d.chain == 'arbitrum' && d.assetCode.toUpperCase() == 'USDC')
        .firstOrNull;
