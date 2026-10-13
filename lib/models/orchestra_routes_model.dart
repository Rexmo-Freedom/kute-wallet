// Typed model + parser for the Flashnet Orchestration route catalog
// (GET /v2/orchestration/routes — public, optional bearer). The catalog
// is the LIVE replacement for the hand-maintained tables in
// lib/services/orchestra_routes.dart: every asset Orchestra knows about,
// with the destinations it can reach in each quoting mode.
//
// Kept UI-free and Flutter-free so the parser is unit-testable against
// a fixture response (test/models/orchestra_routes_catalog_test.dart).

import 'package:kute/helpers/orchestra_pinned_decimals.dart'
    show pinnedOrchestraDecimals;
import 'package:kute/services/orchestra_routes.dart'
    show
        kOrchestraSendRoutes,
        kOrchestraReceiveRoutes,
        kOrchestraUsdReceiveRoutes,
        kOrchestraSendableChains,
        kOrchestraAccumulationDeniedPairs,
        kOrchestraQuoteReceiveChains,
        orchestraCanAccumulatePair,
        kOrchestraUsdAssetCode,
        kOrchestraUsdChain,
        orchestraChainDisplayName;

/// A catalog used for a money decision must be at most this old (F6).
const Duration kMoneyCatalogMaxAge = Duration(minutes: 15);

/// How old a backend-served catalog copy can be when it carries no fetch
/// time header (the backend caches the routes for 10 minutes).
const Duration kBackendCatalogCacheMaxAge = Duration(minutes: 10);

/// Route versions that keep the legacy (static fallback) requirement.
const Set<String> kLegacyRequirementRouteVersions = {
  'spark_arbitrum_bridge2_v0',
};

/// A directed Orchestra pair. Chains compare case-insensitively (stored
/// lowercase); assets compare case-insensitively but keep their spelling
/// ('USDC.e').
class RouteKey {
  RouteKey({
    required String fromChain,
    required String fromAsset,
    required String toChain,
    required String toAsset,
  })  : fromChain = fromChain.trim().toLowerCase(),
        fromAsset = fromAsset.trim(),
        toChain = toChain.trim().toLowerCase(),
        toAsset = toAsset.trim();

  final String fromChain;
  final String fromAsset;
  final String toChain;
  final String toAsset;

  /// Analytics label in the Phase 2 guard's shape, e.g.
  /// `spark_btc>polygon_usdc.e`. No amounts or addresses.
  String get label =>
      '${fromChain}_$fromAsset>${toChain}_$toAsset'.toLowerCase();

  bool involvesChain(String chain) {
    final c = chain.trim().toLowerCase();
    return fromChain == c || toChain == c;
  }

  @override
  bool operator ==(Object other) =>
      other is RouteKey &&
      other.fromChain == fromChain &&
      other.toChain == toChain &&
      other.fromAsset.toUpperCase() == fromAsset.toUpperCase() &&
      other.toAsset.toUpperCase() == toAsset.toUpperCase();

  @override
  int get hashCode => Object.hash(
      fromChain, fromAsset.toUpperCase(), toChain, toAsset.toUpperCase());

  @override
  String toString() => 'RouteKey($label)';
}

/// How much catalog evidence a route needs before money moves on it.
enum RouteRequirement {
  /// Today's hot routes: the static tables stay a fallback, because the
  /// quote and the Phase 2 guard gate payment.
  legacy,

  /// A live catalog no older than [kMoneyCatalogMaxAge] must list the
  /// exact directed pair.
  live,
}

/// [RouteRequirement.live] for a `bitcoin` or `hypercore` leg, a Ledger
/// wallet, or a versioned route other than the legacy versions (B2).
RouteRequirement routeRequirementFor(
  RouteKey key, {
  required bool ledgerWallet,
  String? routeVersion,
}) {
  if (ledgerWallet) return RouteRequirement.live;
  if (key.involvesChain('bitcoin') || key.involvesChain('hypercore')) {
    return RouteRequirement.live;
  }
  if (routeVersion != null &&
      !kLegacyRequirementRouteVersions.contains(routeVersion)) {
    return RouteRequirement.live;
  }
  return RouteRequirement.legacy;
}

enum RouteUnavailableReason {
  noLiveData('no_live_data'),
  stale('stale'),
  pairMissing('pair_missing'),
  decimalsMismatch('decimals_mismatch'),
  paused('paused');

  const RouteUnavailableReason(this.code);

  /// Analytics value.
  final String code;
}

class RouteAvailability {
  const RouteAvailability._(this.reason);

  const RouteAvailability.unsupported(RouteUnavailableReason this.reason);

  static const RouteAvailability available = RouteAvailability._(null);

  /// Null when available.
  final RouteUnavailableReason? reason;

  bool get isAvailable => reason == null;

  @override
  String toString() =>
      reason == null ? 'available' : 'unsupported(${reason!.code})';
}

/// A destination set in the routes response. Flashnet encodes it three
/// ways: the string "all" (every other asset), a plain list of asset ids,
/// or `{"except": [ids]}` (every other asset minus the listed ones).
class OrchestraRouteSet {
  final bool _all;
  final Set<String> _ids;
  final bool _isExcept;

  const OrchestraRouteSet._(this._all, this._ids, this._isExcept);

  const OrchestraRouteSet.none() : this._(false, const {}, false);

  factory OrchestraRouteSet.fromJson(dynamic json) {
    if (json is String && json.toLowerCase() == 'all') {
      return const OrchestraRouteSet._(true, {}, false);
    }
    if (json is List) {
      return OrchestraRouteSet._(
          false, json.map((e) => e.toString()).toSet(), false);
    }
    if (json is Map) {
      final except = json['except'];
      if (except is List) {
        return OrchestraRouteSet._(
            false, except.map((e) => e.toString()).toSet(), true);
      }
    }
    return const OrchestraRouteSet.none();
  }

  /// Whether [assetId] (e.g. 'spark:BTC') is a reachable destination.
  /// [selfId] is the owning asset's id — "all"/"except" never include
  /// the asset itself.
  bool contains(String assetId, {String? selfId}) {
    if (assetId == selfId) return false;
    if (_all) return true;
    if (_isExcept) return !_ids.contains(assetId);
    return _ids.contains(assetId);
  }

  /// True when this set can reach at least one destination.
  bool get isEmpty => !_all && !_isExcept && _ids.isEmpty;
}

/// Host that serves the catalog's `chainIcon` paths. The routes
/// response carries RELATIVE paths ('/chain-base.svg', '/btc.svg',
/// '/chain-tempo.png') that resolve against Flashnet's Orchestra web
/// app host — NOT the orchestration API host (verified live: the API
/// host 404s them, orchestra.flashnet.xyz serves them as image/svg+xml
/// / image/png).
const String kOrchestraChainIconBase = 'https://orchestra.flashnet.xyz';

/// Coin artwork is independent of network artwork. Use catalog metadata when
/// supplied, otherwise the brand assets served by Orchestra's own app. Unknown
/// symbols intentionally have no guessed URL.
String? orchestraAssetIconUrl(String asset, {String? assetIcon}) {
  final raw = assetIcon?.trim();
  if (raw != null && raw.isNotEmpty) {
    final uri = Uri.tryParse(raw);
    final resolved = uri == null
        ? null
        : Uri.parse('$kOrchestraChainIconBase/').resolveUri(uri);
    if (resolved != null &&
        resolved.scheme == 'https' &&
        resolved.host == 'orchestra.flashnet.xyz' &&
        resolved.userInfo.isEmpty &&
        !resolved.hasPort) {
      return resolved.toString();
    }
  }
  const paths = {
    'BTC': '/btc.svg',
    'USDC': '/usdc.svg',
    'USDC.E': '/usdc.svg',
    'USDT': '/usdt.svg',
    'USD₮0': '/usdt.svg',
    'USDT0': '/usdt.svg',
    'WBTC': '/wbtc.svg',
    'CBBTC': '/cbbtc.svg',
    'TBTC': '/tbtc.svg',
    'PYUSD': '/pyusd.svg',
    'DAI': '/dai.svg',
    // Verified served by the same host, September 2026. Without them
    // these coins drew as a lettered disc in the receive picker.
    'ETH': '/eth.svg',
    'USDE': '/usde.svg',
    'PATHUSD': '/pathusd.svg',
    // TON's own coin has no contract, so it fell back to the TON chain
    // mark. The host serves the coin's real artwork (200, and a
    // different file from /ton.svg), which is the truer mark.
    'GRAM': '/gram.svg',
    'SHX': '/icons/token/shx.svg',
    'HSUSD': '/hsusd.png',
    'USDG': '/usdg.png',
  };
  final path = paths[asset.trim().toUpperCase()];
  return path == null ? null : '$kOrchestraChainIconBase$path';
}

/// The three chains whose artwork path on [kOrchestraChainIconBase]
/// breaks the `/chain-<slug>.svg` convention (verified live against the
/// catalog, September 2026).
const Map<String, String> _kOrchestraChainIconPathOverrides = {
  'bitcoin': '/btc.svg',
  'ton': '/ton.svg',
  'tempo': '/chain-tempo.png',
};

/// Conventional artwork URL for [chain] on [kOrchestraChainIconBase]
/// (`/chain-<slug>.svg`, with the spellings in
/// [_kOrchestraChainIconPathOverrides]). Every chain in the live catalog
/// resolves this way, so it is the fallback for a row that carries no
/// `chainIcon` AND for the static-table rows, which have no catalog row
/// at all. Without it the pickers rendered every chain we ship no local
/// asset for (Base, Optimism, Plasma) as a lettered disc until the live
/// catalog landed. Null for an empty slug.
String? orchestraChainIconUrl(String chain) {
  final slug = chain.toLowerCase().trim();
  if (slug.isEmpty) return null;
  final path = _kOrchestraChainIconPathOverrides[slug] ?? '/chain-$slug.svg';
  return '$kOrchestraChainIconBase$path';
}

/// One asset row from the catalog.
class OrchestraRouteAsset {
  /// Canonical id, 'chain:asset' (e.g. 'spark:BTC', 'tron:USDT').
  final String id;
  final String chain;

  /// Asset code as Flashnet spells it ('USDC.e' keeps its casing).
  final String asset;
  final String displayName;
  final String displaySymbol;
  final String? contractAddress;
  final int decimals;

  /// False when a parsed row omitted or malformed its unit exponent.
  /// Display fallbacks must never authorize a money amount.
  final bool hasExplicitDecimals;

  bool get hasUsableDecimals =>
      hasExplicitDecimals && decimals >= 0 && decimals <= 18;
  final String chainDisplayName;

  /// Chain artwork as the API spells it — usually a relative path
  /// ('/chain-base.svg'). Null when the row carries none. Use
  /// [chainIconUrl] for a fetchable URL.
  final String? chainIcon;
  final String? assetIcon;

  /// The coin's own mark. A chain's native coin has no contract and no
  /// artwork of its own in the catalog, and its brand IS the chain's
  /// brand (MON on Monad, HYPE on HyperEVM), so the chain mark stands
  /// in rather than a lettered disc. A token with a contract keeps the
  /// disc: borrowing the chain's mark there would name the wrong thing.
  String? get assetIconUrl =>
      orchestraAssetIconUrl(asset, assetIcon: assetIcon) ??
      (contractAddress == null ? chainIconUrl : null);

  /// Destinations reachable from this asset, per quoting mode.
  final OrchestraRouteSet to;
  final OrchestraRouteSet exactOutTo;
  final OrchestraRouteSet fixedTo;

  const OrchestraRouteAsset({
    required this.id,
    required this.chain,
    required this.asset,
    required this.displayName,
    required this.displaySymbol,
    this.contractAddress,
    required this.decimals,
    this.hasExplicitDecimals = true,
    required this.chainDisplayName,
    this.chainIcon,
    this.assetIcon,
    required this.to,
    required this.exactOutTo,
    required this.fixedTo,
  });

  /// Fetchable URL for [chainIcon]: absolute values pass through,
  /// relative paths resolve against [kOrchestraChainIconBase]. Null
  /// when the row carries no artwork.
  String? get chainIconUrl {
    final raw = chainIcon?.trim();
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    return raw.startsWith('/')
        ? '$kOrchestraChainIconBase$raw'
        : '$kOrchestraChainIconBase/$raw';
  }

  factory OrchestraRouteAsset.fromJson(Map<String, dynamic> json) {
    final route = json['route'] as Map<String, dynamic>? ?? const {};
    final chain = json['chain']?.toString() ?? '';
    final asset = json['asset']?.toString() ?? '';
    final rawDecimals = json['decimals'];
    final validDecimals = rawDecimals is num &&
        rawDecimals.isFinite &&
        rawDecimals >= 0 &&
        rawDecimals <= 18 &&
        rawDecimals == rawDecimals.toInt();
    return OrchestraRouteAsset(
      id: json['id']?.toString() ?? '$chain:$asset',
      chain: chain,
      asset: asset,
      displayName: json['assetDisplayName']?.toString() ?? asset,
      displaySymbol: json['assetDisplaySymbol']?.toString() ?? asset,
      contractAddress: json['contractAddress']?.toString(),
      decimals: validDecimals ? rawDecimals.toInt() : 8,
      hasExplicitDecimals: validDecimals,
      chainDisplayName: json['chainDisplayName']?.toString() ?? chain,
      chainIcon: json['chainIcon']?.toString(),
      assetIcon: json['assetIcon']?.toString(),
      to: OrchestraRouteSet.fromJson(route['to']),
      exactOutTo: OrchestraRouteSet.fromJson(route['exactOutTo']),
      fixedTo: OrchestraRouteSet.fromJson(route['fixedTo']),
    );
  }
}

/// Chains whose tokens are admitted by name rather than wholesale.
///
/// Robinhood Chain lists a long tail of meme coins and tokenized stocks
/// next to its core assets. Only the chain's own coin, its dollars and
/// the HOOD token are offered there; every other token on it is dropped
/// when the catalog is built, so a token the provider adds later stays
/// out of every picker until it is named here. The Hyperliquid HOOD
/// perpetual is a separate market and is not affected.
const Map<String, Set<String>> kOrchestraChainAssetAllowlist = {
  'robinhood': {'ETH', 'USDC', 'USDT', 'USDG', 'HOOD'},
};

/// Whether ([chain], [asset]) may appear in the app at all. A chain with
/// no allowlist admits every asset; an allowlisted chain admits only the
/// assets it names (case-insensitive).
bool orchestraAssetOffered(String chain, String asset) {
  final allowed = kOrchestraChainAssetAllowlist[chain.trim().toLowerCase()];
  return allowed == null || allowed.contains(asset.trim().toUpperCase());
}

/// Where a catalog instance came from — surfaced so callers (and debug
/// overlays) can tell a live catalog from the persisted or static
/// fallbacks.
enum OrchestraCatalogSource { live, cached, static_ }

/// 'USDC.E' (bridged Polygon USDC) rides the USDC vocabulary, matching
/// the static tables' normalization.
String _normalizeCode(String code) {
  final c = code.toUpperCase();
  return c == 'USDC.E' ? 'USDC' : c;
}

/// Ticker-keyed decimals fallback for when no live catalog row matches.
/// Only correct on the chains the STATIC route tables offer — which is
/// exactly why 'bsc' was removed from those tables: BSC-pegged USDC /
/// USDT are 18-decimal tokens, so bsc routes may only be offered by the
/// live catalog, which carries the real per-asset decimals.
const Map<String, int> _kFallbackAssetDecimals = {
  'BTC': 8,
  'USDC': 6,
  'USDC.E': 6,
  'USDT': 6,
  // The dollar account's own token — a first-class Orchestra asset that
  // the live catalog routes to nearly every other asset and chain, and
  // back. 6 decimals, like the other dollars.
  'USDB': 6,
  'ETH': 18,
  'SOL': 9,
};

/// Decimals for [asset] when no (chain, asset) catalog row is available.
int fallbackOrchestraAssetDecimals(String asset) =>
    _kFallbackAssetDecimals[asset.toUpperCase()] ?? 8;

/// The parsed catalog plus the send/receive queries the swap surfaces
/// need. All queries fall back to the static tables when the catalog
/// carries no usable data (empty, or no Spark-BTC anchor asset), so a
/// malformed live response degrades to exactly the behavior the app
/// shipped with.
class OrchestraRoutesCatalog {
  final List<OrchestraRouteAsset> assets;

  /// Local time the response arrived.
  final DateTime? fetchedAt;
  final OrchestraCatalogSource source;

  /// The response came from Kute's backend proxy, which serves a cached
  /// copy, rather than Flashnet's public host.
  final bool fromBackend;

  /// When the backend fetched its copy from Flashnet, from the response
  /// header, in local time. Null when absent.
  final DateTime? upstreamFetchedAt;

  /// Every row passes [orchestraAssetOffered] here, whichever way the
  /// catalog was built (live, persisted, or by hand in a test), so no
  /// list, picker, search or route query downstream can see a row the
  /// app has chosen not to offer.
  OrchestraRoutesCatalog({
    required List<OrchestraRouteAsset> assets,
    required this.fetchedAt,
    required this.source,
    this.fromBackend = false,
    this.upstreamFetchedAt,
  }) : assets = assets
            .where((a) => orchestraAssetOffered(a.chain, a.asset))
            .toList(growable: false);

  factory OrchestraRoutesCatalog.fromJson(
    Map<String, dynamic> json, {
    required OrchestraCatalogSource source,
    DateTime? fetchedAt,
    bool fromBackend = false,
    DateTime? upstreamFetchedAt,
  }) {
    final raw = json['assets'];
    final assets = raw is List
        ? raw
            .whereType<Map<String, dynamic>>()
            .map(OrchestraRouteAsset.fromJson)
            .where((a) => a.id.isNotEmpty && a.chain.isNotEmpty)
            .toList()
        : <OrchestraRouteAsset>[];
    return OrchestraRoutesCatalog(
      assets: assets,
      fetchedAt: fetchedAt,
      source: source,
      fromBackend: fromBackend,
      upstreamFetchedAt: upstreamFetchedAt,
    );
  }

  /// The static-table fallback of last resort, expressed in catalog
  /// form so every caller sees one shape.
  factory OrchestraRoutesCatalog.fromStatic() => OrchestraRoutesCatalog(
      assets: const [],
      fetchedAt: null,
      source: OrchestraCatalogSource.static_);

  /// BTC on Spark — the anchor every send starts from and every receive
  /// lands on. Null when the catalog has no usable data.
  OrchestraRouteAsset? get sparkBtc {
    for (final a in assets) {
      if (a.chain.toLowerCase() == 'spark' && a.asset.toUpperCase() == 'BTC') {
        return a;
      }
    }
    return null;
  }

  /// True when live/cached data is present and anchored; false → every
  /// query answers from the static tables.
  bool get hasLiveData => assets.isNotEmpty && sparkBtc != null;

  /// The data age a money decision uses: the backend's upstream fetch
  /// time when known, otherwise a backend copy counts as
  /// [kBackendCatalogCacheMaxAge] older than its arrival. Null for cached
  /// and static catalogs, which are never live.
  DateTime? get effectiveFetchedAt {
    final arrived = fetchedAt;
    if (source != OrchestraCatalogSource.live || arrived == null) return null;
    if (!fromBackend) return arrived;
    final upstream = upstreamFetchedAt;
    if (upstream != null) {
      return upstream.isBefore(arrived) ? upstream : arrived;
    }
    return arrived.subtract(kBackendCatalogCacheMaxAge);
  }

  /// Whether this is a live catalog no older than [maxAge] at [now]. A
  /// fetch time more than a minute in the future (a clock change) is not
  /// fresh.
  bool isFresh(DateTime now, {Duration maxAge = kMoneyCatalogMaxAge}) {
    final at = effectiveFetchedAt;
    if (at == null || !hasLiveData) return false;
    final age = now.difference(at);
    if (age < const Duration(minutes: -1)) return false;
    return age <= maxAge;
  }

  /// The row for exactly ([chain], [asset]), case-insensitive, with no
  /// USDC.e normalization.
  OrchestraRouteAsset? find(String chain, String asset) {
    final c = chain.trim().toLowerCase();
    final a = asset.trim().toUpperCase();
    for (final row in assets) {
      if (row.chain.toLowerCase() == c && row.asset.toUpperCase() == a) {
        return row;
      }
    }
    return null;
  }

  /// Whether the catalog lists the exact directed pair: the source row's
  /// `to` set contains the destination row. `exactOutTo` and `fixedTo`
  /// are not used.
  bool supports(RouteKey key) {
    final from = find(key.fromChain, key.fromAsset);
    final to = find(key.toChain, key.toAsset);
    if (from == null || to == null) return false;
    return from.to.contains(to.id, selfId: from.id);
  }

  /// Whether money may move on [key] under [req] (B2). [paused] is the
  /// remote pause switch for the route (P5.16), known true only.
  RouteAvailability availability(
    RouteKey key, {
    required RouteRequirement req,
    required DateTime now,
    bool paused = false,
  }) {
    if (paused) {
      return const RouteAvailability.unsupported(RouteUnavailableReason.paused);
    }
    if (req == RouteRequirement.live) {
      if (!hasLiveData) {
        return const RouteAvailability.unsupported(
            RouteUnavailableReason.noLiveData);
      }
      if (!isFresh(now)) {
        return const RouteAvailability.unsupported(
            RouteUnavailableReason.stale);
      }
      if (!supports(key)) {
        return const RouteAvailability.unsupported(
            RouteUnavailableReason.pairMissing);
      }
    } else if (hasLiveData && !supports(key)) {
      return const RouteAvailability.unsupported(
          RouteUnavailableReason.pairMissing);
    }
    for (final row in [
      find(key.fromChain, key.fromAsset),
      find(key.toChain, key.toAsset),
    ]) {
      if (row == null) continue;
      final pin = pinnedOrchestraDecimals(row.chain, row.asset);
      if (!row.hasUsableDecimals || (pin != null && pin != row.decimals)) {
        return const RouteAvailability.unsupported(
            RouteUnavailableReason.decimalsMismatch);
      }
    }
    return RouteAvailability.available;
  }

  /// Chains that BTC-on-Spark can SEND [assetCode] to (the live
  /// equivalent of kOrchestraSendRoutes[code]).
  Set<String> sendChainsFor(String assetCode) {
    if (!hasLiveData) {
      return kOrchestraSendRoutes[_normalizeCode(assetCode)] ?? const {};
    }
    final btc = sparkBtc!;
    final code = _normalizeCode(assetCode);
    // Only the anchor row itself is excluded, not its whole chain: the
    // dollar account's token sits on the same chain as the anchor and
    // is a real destination.
    return assets
        .where((a) =>
            _normalizeCode(a.asset) == code &&
            a.id != btc.id &&
            btc.to.contains(a.id, selfId: btc.id))
        .map((a) => a.chain.toLowerCase())
        .toSet();
  }

  /// Chains from which [assetCode] can be RECEIVED into BTC-on-Spark
  /// (the live equivalent of kOrchestraReceiveRoutes[code]).
  Set<String> receiveChainsFor(String assetCode) {
    if (!hasLiveData) {
      return kOrchestraReceiveRoutes[_normalizeCode(assetCode)] ?? const {};
    }
    final btcId = sparkBtc!.id;
    final code = _normalizeCode(assetCode);
    // Anchor row only — see [sendChainsFor].
    return assets
        .where((a) =>
            _normalizeCode(a.asset) == code &&
            a.id != btcId &&
            a.to.contains(btcId, selfId: a.id))
        .map((a) => a.chain.toLowerCase())
        .toSet();
  }

  /// Decimals for [asset] on [chain]. The live catalog carries per-row
  /// decimals (chain matters: BSC-pegged USDC is 18, Polygon USDC is
  /// 6), so an exact (chain, asset) row wins; anything unresolved falls
  /// back to the ticker table via [fallbackOrchestraAssetDecimals].
  /// Case-insensitive on both keys; 'USDC.e' matches literally before
  /// normalization so the bridged variant reads its own row.
  int decimalsFor(String chain, String asset) {
    final c = chain.toLowerCase();
    final code = asset.toUpperCase();
    for (final a in assets) {
      if (a.chain.toLowerCase() == c && a.asset.toUpperCase() == code) {
        return a.decimals;
      }
    }
    // Bridged/normalized variant (e.g. asked for 'USDC' where the
    // catalog row spells 'USDC.e', or vice versa).
    final normalized = _normalizeCode(asset);
    for (final a in assets) {
      if (a.chain.toLowerCase() == c && _normalizeCode(a.asset) == normalized) {
        return a.decimals;
      }
    }
    return fallbackOrchestraAssetDecimals(asset);
  }

  /// Live equivalent of orchestraSupportsSwapAsset(): true when
  /// Orchestra can move [assetCode] in either direction against
  /// BTC-on-Spark. Swap asset grids / pickers / search results should
  /// filter through this once wired.
  bool supportsSwapAsset(String assetCode) {
    if (!hasLiveData) {
      final code = _normalizeCode(assetCode);
      return kOrchestraSendRoutes.containsKey(code) ||
          kOrchestraReceiveRoutes.containsKey(code);
    }
    return sendChainsFor(assetCode).isNotEmpty ||
        receiveChainsFor(assetCode).isNotEmpty;
  }

  /// Live equivalent of orchestraSendChainFor(): the chain slug for a
  /// BTC-on-Spark → (asset, chain) send, or null when unsupported.
  String? sendChainFor(String assetCode, String chainSlug) =>
      sendChainsFor(assetCode).contains(chainSlug.toLowerCase())
          ? chainSlug.toLowerCase()
          : null;

  /// Live equivalent of orchestraReceiveChainFor().
  String? receiveChainFor(String assetCode, String chainSlug) =>
      receiveChainsFor(assetCode).contains(chainSlug.toLowerCase())
          ? chainSlug.toLowerCase()
          : null;

  /// Every non-BTC asset code the catalog knows, normalized. Dropping
  /// BTC is enough to drop the anchor and its native twins; the chain
  /// is not filtered, so the dollar account's token (which shares the
  /// anchor's chain) keeps its place in the derived tables.
  Set<String> get _codes => assets
      .map((a) => _normalizeCode(a.asset))
      .where((c) => c != 'BTC')
      .toSet();

  /// Send table in the static tables' shape (code → chain slugs),
  /// clipped to [kOrchestraSendableChains]: the send flow validates
  /// recipient addresses per address family, so it may only offer
  /// chains the app can actually check and dispatch to. Fed into
  /// `setLiveOrchestraRouteCatalog` so the legacy helpers answer live.
  Map<String, Set<String>> get sendRouteTable => _routeTable(sendChainsFor,
      allow: (_, chain) => kOrchestraSendableChains.contains(chain));

  /// Receive table, same shape as [sendRouteTable], clipped to
  /// the catalogue, minus [kOrchestraAccumulationDeniedPairs]. Receiving
  /// means handing out a
  /// REUSABLE deposit address, and that primitive exists only where
  /// Flashnet has configured the ASSET on the CHAIN for the
  /// DESTINATION — a row for bitcoin, Lightning, XRP or Spark is a
  /// route the mint refuses, and so is an unconfigured asset on a
  /// chain that otherwise works (`ethereum:WBTC`). Neither must reach
  /// a picker. This table is the BITCOIN-anchored one, so it asks the
  /// bitcoin half; [usdReceiveRouteTable] asks the dollar half.
  Map<String, Set<String>> get receiveRouteTable => _routeTable(
      receiveChainsFor,
      allow: (code, chain) => orchestraCanAccumulatePair(chain, code, 'BTC'));

  /// The receive table anchored on the DOLLAR balance instead of
  /// bitcoin: asset code (normalized) → chains that asset can be
  /// received from when the money is to land as dollars. Built off the
  /// same [receiveOptions] rows the picker renders, so the offering and
  /// the mint gate can never disagree. Bitcoin keeps its place here —
  /// it is an ordinary source for a dollar receive, not a native rail.
  /// Empty without live data: this getter exists to be INSTALLED as the
  /// live table, and the static answer lives in
  /// [kOrchestraUsdReceiveRoutes] instead.
  Map<String, Set<String>> get usdReceiveRouteTable {
    if (!hasLiveData) return const {};
    final table = <String, Set<String>>{};
    for (final option in receiveOptions(
      destinationChain: kOrchestraUsdChain,
      destinationAsset: kOrchestraUsdAssetCode,
    )) {
      table
          .putIfAbsent(_normalizeCode(option.assetCode), () => <String>{})
          .add(option.chain);
    }
    return table;
  }

  /// Exact reusable source membership for cache reuse and retirement. Display
  /// grouping may fold token variants; deposit instructions must not.
  Map<String, Set<String>> exactAccumulationRouteTable({
    required String destinationAsset,
  }) {
    if (!hasLiveData) return const {};
    final table = <String, Set<String>>{};
    for (final option in receiveOptions(destinationAsset: destinationAsset)) {
      if (!option.reusableAddress) continue;
      table
          .putIfAbsent(option.assetCode.trim().toUpperCase(), () => <String>{})
          .add(option.chain);
    }
    return table;
  }

  /// [allow] is asked per (normalized asset code, chain slug) rather
  /// than per chain: the receive side is gated on the pair, not on the
  /// chain alone (see [orchestraCanAccumulatePair]).
  Map<String, Set<String>> _routeTable(Set<String> Function(String) chainsFor,
      {required bool Function(String code, String chain) allow}) {
    if (!hasLiveData) return const {};
    final table = <String, Set<String>>{};
    for (final code in _codes) {
      final chains = chainsFor(code).where((c) => allow(code, c)).toSet();
      if (chains.isNotEmpty) table[code] = chains;
    }
    return table;
  }

  /// Every (asset, chain) pair Orchestra can RECEIVE into
  /// [destinationAsset] on [destinationChain], as picker-ready rows.
  /// The default destination is BTC-on-Spark.
  ///
  /// Native bitcoin sources remain in the Bitcoin receive UI. Bitcoin
  /// into dollars is a one-time swap. Spark and Lightning sources need
  /// different payer/refund contracts and are never external-deposit
  /// rows here. One-time rows require catalog membership and usable
  /// source units; the static fallback offers only reusable candidates.
  List<OrchestraReceiveOption> receiveOptions({
    String destinationChain = 'spark',
    String destinationAsset = 'BTC',
  }) {
    const nativeChains = {'spark', 'bitcoin', 'lightning'};
    final destChain = destinationChain.trim().toLowerCase();
    final destAsset = destinationAsset.trim().toUpperCase();
    final destIsBitcoin = destChain == 'spark' && destAsset == 'BTC';
    final destIsDollars =
        destChain == kOrchestraUsdChain && destAsset == kOrchestraUsdAssetCode;
    if (!destIsBitcoin && !destIsDollars) return const [];
    final options = <OrchestraReceiveOption>[];
    if (hasLiveData) {
      final destRow =
          destIsBitcoin ? sparkBtc! : find(destChain, destinationAsset);
      if (destRow == null || !destRow.hasUsableDecimals) {
        return const <OrchestraReceiveOption>[];
      }
      final destinationPin =
          pinnedOrchestraDecimals(destRow.chain, destRow.asset);
      if (destinationPin != null && destinationPin != destRow.decimals) {
        return const <OrchestraReceiveOption>[];
      }
      final btcId = destRow.id;
      for (final a in assets) {
        final chain = a.chain.toLowerCase();
        if (!a.hasUsableDecimals) continue;
        final pin = pinnedOrchestraDecimals(chain, a.asset);
        if (pin != null && pin != a.decimals) continue;
        // External payers cannot complete Spark's sender-submitted
        // funding flow; Lightning uses a separate invoice/refund model.
        if (chain == 'spark' || chain == 'lightning') continue;
        if (destIsBitcoin &&
            nativeChains.contains(chain) &&
            a.asset.toUpperCase() == 'BTC') {
          continue;
        }
        // The swap catalog does not certify reusable-address support.
        // Apply known source/destination restrictions before offering
        // a deposit pair; the mint can still refuse an unconfigured pair.
        final reusable = orchestraCanAccumulatePair(chain, a.asset, destAsset);
        // One-time quotes must not replace the app's native BTC rails.
        final oneOff = !reusable &&
            kOrchestraQuoteReceiveChains.contains(chain) &&
            !(destIsBitcoin && nativeChains.contains(chain));
        if (!reusable && !oneOff) continue;
        if (!a.to.contains(btcId, selfId: a.id)) continue;
        options.add(OrchestraReceiveOption(
          assetCode: a.asset,
          displayName: a.displayName,
          displaySymbol: a.displaySymbol,
          chain: chain,
          chainDisplayName: a.chainDisplayName.isNotEmpty
              ? a.chainDisplayName
              : orchestraChainDisplayName(chain),
          decimals: a.decimals,
          chainIconUrl: a.chainIconUrl ?? orchestraChainIconUrl(chain),
          assetIconUrl: a.assetIconUrl,
          reusableAddress: reusable,
        ));
      }
    } else {
      const staticNames = {
        'USDT': 'Tether USD',
        'USDC': 'USD Coin',
        'BTC': 'Bitcoin',
      };
      final table =
          destIsBitcoin ? kOrchestraReceiveRoutes : kOrchestraUsdReceiveRoutes;
      table.forEach((code, chains) {
        for (final chain in chains) {
          if (destIsBitcoin &&
              nativeChains.contains(chain) &&
              code.toUpperCase() == 'BTC') {
            continue;
          }
          // Exactly the live branch's rail clip. It also drops the
          // static USDB-on-Spark row: Spark is the destination rail,
          // never a deposit source.
          final reusable = orchestraCanAccumulatePair(chain, code, destAsset);
          // One-time routes need explicit per-asset units and directed
          // catalog membership; static ticker guesses cannot offer them.
          if (!reusable) continue;
          options.add(OrchestraReceiveOption(
            assetCode: code,
            displayName: staticNames[code] ?? code,
            displaySymbol: code,
            chain: chain,
            chainDisplayName: orchestraChainDisplayName(chain),
            decimals: fallbackOrchestraAssetDecimals(code),
            // The static tables carry no artwork field; the host's
            // conventional path still serves every chain they list.
            chainIconUrl: orchestraChainIconUrl(chain),
            reusableAddress: reusable,
          ));
        }
      });
    }
    options.sort((a, b) {
      final bySymbol = a.displaySymbol
          .toLowerCase()
          .compareTo(b.displaySymbol.toLowerCase());
      if (bySymbol != 0) return bySymbol;
      return a.chainDisplayName
          .toLowerCase()
          .compareTo(b.chainDisplayName.toLowerCase());
    });
    return options;
  }
}

/// A source asset that can reach the requested Spark balance, through
/// either a reusable address candidate or a guarded one-time quote.
class OrchestraReceiveOption {
  /// Asset code as Flashnet spells it ('USDC.e' keeps its casing) —
  /// this is what accumulation-address creation must be handed.
  final String assetCode;
  final String displayName;
  final String displaySymbol;

  /// Chain slug, lowercase (the value quote/address APIs take).
  final String chain;
  final String chainDisplayName;
  final int decimals;

  /// Absolute URL for the chain's artwork: the catalog's `chainIcon`
  /// (the API's only image field — there is no per-coin artwork), else
  /// the host's conventional path via [orchestraChainIconUrl]. Set on
  /// the static fallback too, so the picker shows real marks before
  /// the live catalog lands.
  final String? chainIconUrl;
  final String? assetIconUrl;

  /// True selects a reusable-address candidate, subject to the mint's
  /// current support. False requires a fresh amount-bound quote and a
  /// refund address the user controls on the source chain. Quoted
  /// instructions expire and must never be cached as reusable addresses.
  /// The two behave differently
  /// enough that the row says so and the flow branches on it.
  final bool reusableAddress;

  const OrchestraReceiveOption({
    required this.assetCode,
    required this.displayName,
    required this.displaySymbol,
    required this.chain,
    required this.chainDisplayName,
    required this.decimals,
    this.chainIconUrl,
    this.assetIconUrl,
    this.reusableAddress = true,
  });
}
