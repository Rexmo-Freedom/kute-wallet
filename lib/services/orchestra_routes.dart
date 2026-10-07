/// Static Orchestra (Flashnet) route tables for Spark-wallet stablecoin
/// sends and receives, plus the network-code → Orchestra-chain mapper
/// and the shared vocabulary/attribution helpers for DISCOVERED Orchestra
/// orders (ones an accumulation address spawned server-side, found via
/// `getHistory` rather than created in-app).
///
/// Local address capabilities only. Callers must verify the exact directed
/// pair against the live Orchestra catalog and validate its quote. A catalog
/// entry alone does not prove that a reusable deposit address is supported.
library;

import 'package:hive_ce/hive.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/services/once_flags_service.dart';
import 'package:kute/services/security/address_guard.dart'
    show kEvmAddressChains;
import 'package:kute/services/tracking_service.dart';

/// Network code → Orchestra chain slug. Accepts both the short network
/// codes (TRX/ETH/SOL/…) and the chain slugs (tron/ethereum/solana/…)
/// since the destination picker feeds either form. Returns null for
/// chains Orchestra doesn't accept for sends. The caller must still
/// verify the exact live route.
String? networkCodeToOrchestraChain(String network) {
  final slug = network.trim().toLowerCase();
  if (kOrchestraSendableChains.contains(slug)) return slug;
  switch (network.toUpperCase()) {
    case 'TRX':
    case 'TRON':
      return 'tron';
    case 'BSC':
      return 'bsc';
    case 'ETH':
    case 'ETHEREUM':
      return 'ethereum';
    case 'ARBITRUM':
      return 'arbitrum';
    case 'OPTIMISM':
      return 'optimism';
    case 'POLYGON':
      return 'polygon';
    case 'SOL':
    case 'SOLANA':
      return 'solana';
    case 'BASE':
      return 'base';
    default:
      return null;
  }
}

/// Chains whose destination addresses have local format/checksum validation.
/// The live directed catalog must also support the exact asset pair. XRP and
/// TON sends remain excluded because the quote API lacks a destination memo.
const Set<String> kOrchestraSendableChains = {
  ...kEvmAddressChains,
  'bitcoin',
  'litecoin',
  'zcash',
  'tron',
  'solana',
  // The dollar account lives on this chain. Its addresses are the
  // bech32m ones the send screen already detects and labels, so the
  // address-family rule above is satisfied (see `_addressRailFamily`).
  'spark',
};

/// Source chains an Orchestra ACCUMULATION ADDRESS can be minted on.
///
/// The reusable deposit address is an account-model primitive: the
/// partner derives one standing address per (source chain, asset,
/// destination, recipient) tuple. Rails with no such address — UTXO
/// chains, Lightning invoices, tag/memo-addressed ledgers — have no
/// accumulation address to hand out, and Spark itself is the
/// destination rail rather than a deposit source. Asking for one on
/// those chains is refused upstream with
/// `invalid_request / Unsupported source chain: <slug>`, which is how
/// the dollar receive screen ended up offering a bitcoin row that
/// could never produce an address.
///
/// Measured against POST /api/v1/orchestra/accumulation-addresses on
/// 2026-09-24 for every chain in the live catalog. Minting succeeded
/// on exactly the slugs below; it was refused chain-wide on arc,
/// bitcoin, lightning, litecoin, sei, spark, ton, xrp and zcash.
/// Both receive directions (bitcoin and dollars) clip to this set, so
/// the picker, the route tables and the mint gate cannot disagree.
/// A chain the partner enables later is one line here.
///
/// Re-examined 2026-09-24 against Flashnet's own documentation, which
/// settles WHY arc and sei are refused although both are ordinary EVM
/// account-model chains: "Accumulation accepts supported Solana assets
/// or CONFIGURED deposit chains/assets"
/// (docs.flashnet.xyz/orchestra/legacy/reusable-addresses). The set is
/// per-partner configuration at Flashnet, not a property of the chain,
/// so arc and sei are a support request rather than a code change.
/// The same page marks this whole endpoint legacy: the current model
/// is PUT /v1/standing-deposit-addresses/{ref}, which answers with one
/// address PER SOURCE CHAIN and is the route to a wider offering. It
/// needs a server key and a backend endpoint, so it is not a change
/// this file can make alone.
///
/// This clips the RAIL, not the catalog: bitcoin genuinely routes to
/// dollars, just through the amount-bound quote/order primitive rather
/// than a reusable address.
///
/// NECESSARY BUT NO LONGER SUFFICIENT. A chain here can still refuse
/// an individual asset on it, and refuse it for one destination while
/// standing for the other, so the offering is clipped a second time by
/// [kOrchestraAccumulationDeniedPairs]. Ask that set, through
/// [orchestraCanAccumulatePair], before offering a row; this one only
/// answers the chain-wide question the quote mirror still needs.
const Set<String> kOrchestraAccumulationSourceChains = {
  'arbitrum',
  'avalanche',
  'base',
  'bsc',
  'ethereum',
  'hypercore',
  'hyperevm',
  'monad',
  'optimism',
  'plasma',
  'polygon',
  'solana',
  'tempo',
  'tron',
};

/// Rejected (source chain, source asset, destination asset) deposit pairs.
/// The swap catalog supplies candidates, not reusable-address capability:
/// the legacy endpoint requires configured deposit chains/assets
/// (https://docs.flashnet.xyz/orchestra/legacy/reusable-addresses).
/// Apply observed rejections to both the picker and the cache/mint gate.
/// Unlisted pairs can still be refused by the provider; do not describe
/// catalog membership as proof that address creation will succeed.
const Set<String> kOrchestraAccumulationDeniedPairs = {
  // Offered by the catalogue, refused by the mint. Owner reports,
  // 2026-09-25: WBTC returned an internal error on the bitcoin receive
  // and cbBTC was refused as an unsupported source.
  'ethereum:WBTC:BTC',
  'ethereum:WBTC:USDB',
  'base:CBBTC:BTC',
  'base:CBBTC:USDB',
  // Receive dollars, 2026-09-27: the legacy mint returned
  // "Unsupported deposit source: tron:TRX". This does not establish
  // support for the separate BTC destination, so leave that unchanged.
  'tron:TRX:USDB',
};

/// Whether a pair passes known reusable-address restrictions. Callers
/// must also check the swap catalog and handle an upstream refusal.
bool orchestraCanAccumulatePair(
    String chain, String assetCode, String destinationAsset) {
  final slug = chain.trim().toLowerCase();
  if (!kOrchestraAccumulationSourceChains.contains(slug)) return false;
  final asset = _normalizeAsset(assetCode.trim());
  final dest = destinationAsset.trim().toUpperCase();
  return !kOrchestraAccumulationDeniedPairs.contains('$slug:$asset:$dest');
}

/// Source rails whose deposit and refund addresses the app can verify
/// for a one-time receive. A live directed `route.to` and explicit source
/// decimals are also required; this set alone does not certify a route.
/// The payer must provide a refund address they control on this chain.
///
/// Spark requires the sender to submit its deposit, and Lightning needs
/// a different refund/invoice contract. Address families without a
/// local checksum rule in `formatMatchesChain` remain excluded. Quotes
/// requiring a memo/tag are rejected by the quote guard unless the
/// request opts in (only the quoted receive screen, which displays,
/// persists and shares the memo) and the memo is valid for TON or XRP.
/// See https://docs.flashnet.xyz/orchestra/quotes.
const Set<String> kOrchestraQuoteReceiveChains = {
  'litecoin',
  'zcash',
  'ton',
  'xrp',
  ...kEvmAddressChains,
  'bitcoin',
  'tron',
  'solana',
};

/// Whether a receive on [chain] can be served by a one-off quote.
bool orchestraCanQuoteReceiveOn(String chain) =>
    kOrchestraQuoteReceiveChains.contains(chain.trim().toLowerCase());

/// Human display name for an Orchestra chain slug. Known brandings are
/// overridden; everything else is title-cased from the id, so a chain
/// Flashnet adds tomorrow still renders acceptably with no release.
/// Chain names are proper nouns — no l10n.
const Map<String, String> kOrchestraChainNameOverrides = {
  'ton': 'TON',
  'xrp': 'XRP',
  'hyperevm': 'HyperEVM',
  'hypercore': 'HyperCore',
  'bsc': 'BNB Smart Chain',
  'btc': 'Bitcoin',
};

String orchestraChainDisplayName(String chainId) {
  final id = chainId.toLowerCase().trim();
  if (id.isEmpty) return chainId;
  final override = kOrchestraChainNameOverrides[id];
  if (override != null) return override;
  return id
      .split(RegExp(r'[-_\s]+'))
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

/// Route catalog for the Spark-BTC swap legs: asset code (normalized,
/// uppercase) → Orchestra chain slugs. Built either from the static
/// tables below (offline fallback) or derived from Flashnet's live
/// routes payload (orchestra_supported_routes_provider.dart installs
/// the derived tables here on every successful fetch).
class OrchestraRouteCatalog {
  final Map<String, Set<String>> send;
  final Map<String, Set<String>> receive;

  /// Same shape as [receive], but anchored on the DOLLAR balance
  /// instead of bitcoin: which chains each asset can be received FROM
  /// when the money is to land as dollars. Bitcoin is a real key here
  /// (bitcoin in, dollars out is an ordinary route), which is why this
  /// is its own table rather than a flag on [receive]. Empty on a
  /// catalog with no live data; the helper that reads it falls back to
  /// [kOrchestraUsdReceiveRoutes] rather than to nothing, so the dollar
  /// receive still has an offering before the catalog lands.
  final Map<String, Set<String>> usdReceive;

  /// Exact reusable source token -> chains, without folding USDC.e into USDC.
  /// Null retains the pre-catalog fallback. An empty map is authoritative:
  /// no reusable source is currently offered for that destination.
  final Map<String, Set<String>>? receiveExact;
  final Map<String, Set<String>>? usdReceiveExact;

  const OrchestraRouteCatalog({
    required this.send,
    required this.receive,
    this.usdReceive = const {},
    this.receiveExact,
    this.usdReceiveExact,
  });

  bool get isEmpty => send.isEmpty && receive.isEmpty && usdReceive.isEmpty;
}

/// Live catalog cache. Set (once fetched) by
/// `orchestraSupportedRoutesProvider`; every helper below prefers it
/// over the static tables so ALL call sites — offering grids AND
/// dispatch routing — agree on the same source of truth without
/// threading a ref through every picker. Null (never fetched / fetch
/// failed) keeps the deliberately conservative static tables in force.
OrchestraRouteCatalog? _liveCatalog;

/// Ignore a degenerate legacy table, but retain explicitly provided exact
/// maps even when empty: a valid catalog can withdraw its last receive pair.
void setLiveOrchestraRouteCatalog(OrchestraRouteCatalog catalog) {
  if (catalog.isEmpty &&
      catalog.receiveExact == null &&
      catalog.usdReceiveExact == null) {
    return;
  }
  _liveCatalog = catalog;
}

Map<String, Set<String>> get _effectiveSendRoutes =>
    _liveCatalog?.send ?? kOrchestraSendRoutes;

Map<String, Set<String>> get _effectiveReceiveRoutes =>
    _liveCatalog?.receive ?? kOrchestraReceiveRoutes;

/// Falls back to [kOrchestraUsdReceiveRoutes] so the dollar receive is
/// offerable before the live catalog lands. The fallback is the same
/// known-good set the bitcoin direction falls back to, clipped the same
/// way, so the picker and this gate cannot disagree.
Map<String, Set<String>> get _effectiveUsdReceiveRoutes =>
    _liveCatalog?.usdReceive ?? kOrchestraUsdReceiveRoutes;

/// SEND direction: BTC-on-Spark → stablecoin destinations Orchestra can
/// deliver, keyed by normalized asset code, valued in Orchestra chain
/// slugs. Note the asymmetry vs [kOrchestraReceiveRoutes]: USDT on
/// Ethereum/Solana/Polygon is NOT a btc-to-stablecoin destination.
/// 'plasma' is listed per the docs but unreachable today: the network
/// pickers have no Plasma network code, so the mapper never yields it.
///
/// STATIC FALLBACK: used only until the live Flashnet catalog loads
/// (see [setLiveOrchestraRouteCatalog]). 'bsc' is deliberately ABSENT
/// even though Flashnet routes it: BSC-pegged USDT/USDC are 18-decimal
/// tokens, and the static amount fallback assumes the ticker-standard
/// 6, so offering bsc offline would mis-scale amounts a trillion-fold.
/// The live catalog reintroduces bsc safely — it carries per-asset
/// decimals the amount helpers read (see orchestra_router.dart).
const Map<String, Set<String>> kOrchestraSendRoutes = {
  'USDT': {'arbitrum', 'optimism', 'tron', 'plasma'},
  // Polygon covers both native USDC and bridged USDC.e.
  'USDC': {'ethereum', 'arbitrum', 'optimism', 'base', 'polygon', 'solana'},
  // The dollar account's token. Orchestra routes bitcoin into it and
  // back out of it as a first-class asset, and it is 6 decimals like
  // the other dollars, so the static amount fallback is correct here.
  'USDB': {'spark'},
};

/// RECEIVE direction: stablecoin sources Orchestra accumulation
/// addresses accept for BTC-on-Spark delivery. Same deliberate 'bsc'
/// omission as [kOrchestraSendRoutes].
const Map<String, Set<String>> kOrchestraReceiveRoutes = {
  'USDT': {'ethereum', 'arbitrum', 'optimism', 'tron', 'plasma'},
  'USDC': {'solana', 'base', 'ethereum', 'arbitrum', 'optimism', 'polygon'},
  'USDB': {'spark'},
};

/// RECEIVE direction anchored on the DOLLAR balance: which chains each
/// asset can be received FROM when the money is to land as dollars.
///
/// STATIC FALLBACK, and deliberately not a guess. Every row here is a
/// row [kOrchestraReceiveRoutes] already vouches for on the bitcoin
/// side, minus the dollar account's own token: Spark is the destination
/// rail, never a deposit source, so it can't be its own source. The
/// bitcoin row is the one addition, and it is the rail
/// [kOrchestraQuoteReceiveChains] exists for: bitcoin into dollars is
/// served by a one-off quoted address rather than a standing one, which
/// the offering marks before the tap.
///
/// Same deliberate 'bsc' omission as the tables above: BSC-pegged
/// dollars are 18-decimal tokens and only the live catalog carries the
/// per-asset decimals that make them safe to offer.
const Map<String, Set<String>> kOrchestraUsdReceiveRoutes = {
  'USDT': {'ethereum', 'arbitrum', 'optimism', 'tron', 'plasma'},
  'USDC': {'solana', 'base', 'ethereum', 'arbitrum', 'optimism', 'polygon'},
  'BTC': {'bitcoin'},
};

/// The chain and asset code of the dollar account's own token. It is a
/// first-class Orchestra asset: the live catalog routes it to nearly
/// every other asset and chain, and back. The user never sees either
/// string — every surface that shows this pair says "USD" / dollars.
const String kOrchestraUsdChain = 'spark';
const String kOrchestraUsdAssetCode = 'USDB';

/// Whether ([chain], [assetCode]) is the dollar account's own token, so
/// a picker can label the row in plain dollars instead of the catalog's
/// internal spelling.
bool isOrchestraUsdRoute(String chain, String assetCode) =>
    chain.trim().toLowerCase() == kOrchestraUsdChain &&
    assetCode.trim().toUpperCase() == kOrchestraUsdAssetCode;

/// Whether ([chain], [assetCode]) is a venue's own rail rather than a
/// network a person sends to or receives from: HyperCore is the
/// Investing account, and bridged USDC (and its pUSD wrapper) on Polygon
/// is the Predictions account's collateral. The backend classifies every
/// route with such a leg as a venue deposit or withdrawal (its own gate,
/// its own fee), so it is never a plain send or receive.
///
/// These routes stay open, because the Move sheet and the venue funding
/// and withdrawal services select them directly. They are only kept out
/// of the lists a person picks from: the receive "also accepts" lists
/// (bitcoin and dollars), the send destination pickers and the lines
/// that summarise them. Native USDC on Polygon is an ordinary network
/// and stays offered.
bool isVenueInternalRoute(String chain, String assetCode) {
  final slug = chain.trim().toLowerCase();
  if (slug == 'hypercore' || slug == 'hyperliquid') return true;
  if (slug != 'polygon') return false;
  final code = assetCode.trim().toUpperCase();
  return code == 'USDC.E' || code == 'PUSD';
}

/// 'USDC.E' (bridged USDC on Polygon) rides the USDC routes.
String _normalizeAsset(String assetCode) {
  final code = assetCode.toUpperCase();
  return code == 'USDC.E' ? 'USDC' : code;
}

/// Resolves [network] — a short network code ('TRX', 'ETH', …) OR a raw
/// Orchestra chain slug ('ton', 'sei', …; the catalog-driven receive
/// picker feeds slugs directly) — against [routes] for [assetCode].
/// Membership in the route table is the real gate, so an unmapped
/// code that isn't itself a listed slug still returns null.
String? _chainForOnTable(
    String assetCode, String network, Map<String, Set<String>> routes,
    {bool exactAsset = false}) {
  final code =
      exactAsset ? assetCode.trim().toUpperCase() : _normalizeAsset(assetCode);
  final chains = routes[code];
  if (chains == null || chains.isEmpty) return null;
  final mapped = networkCodeToOrchestraChain(network);
  if (mapped != null && chains.contains(mapped)) return mapped;
  final raw = network.toLowerCase().trim();
  return chains.contains(raw) ? raw : null;
}

/// Orchestra chain slug for a Spark-BTC → (asset, network) send, or null
/// when Orchestra doesn't support the route (the send is not offered).
String? orchestraSendChainFor(String assetCode, String network) =>
    _chainForOnTable(assetCode, network, _effectiveSendRoutes);

/// Orchestra chain slug for an (asset, network) → BTC-on-Spark receive,
/// or null when Orchestra doesn't support the route (not offered).
/// Accepts short network codes AND raw catalog chain slugs — the
/// two-pane receive picker hands the slug straight from the catalog.
String? orchestraReceiveChainFor(String assetCode, String network) =>
    _accumulable(
        _chainForOnTable(assetCode, network,
            _liveCatalog?.receiveExact ?? _effectiveReceiveRoutes,
            exactAsset: _liveCatalog?.receiveExact != null),
        assetCode,
        'BTC');

/// Drops a resolved chain the accumulation rail cannot mint [assetCode]
/// on. Both receive lookups pass through here so a route the tables
/// still carry (a stale live catalog, the static fallback) can never
/// reach the mint and come back as "couldn't create a deposit address".
/// The asset is part of the question, not only the chain: see
/// [kOrchestraAccumulationDeniedPairs].
String? _accumulable(
        String? chain, String assetCode, String destinationAsset) =>
    chain != null &&
            orchestraCanAccumulatePair(chain, assetCode, destinationAsset)
        ? chain
        : null;

/// Orchestra chain slug for an (asset, network) → DOLLARS receive, or
/// null when the live catalog doesn't carry the route (or hasn't landed
/// yet, or the pair has no reusable deposit address — see
/// [kOrchestraAccumulationDeniedPairs], which is why bitcoin itself is not a
/// source on this rail even though the catalog routes it). The dollar
/// destination mints through the same endpoint as the bitcoin one, but
/// under its OWN half of that set: a source proven into bitcoin is not
/// thereby proven into dollars.
String? orchestraUsdReceiveChainFor(String assetCode, String network) =>
    _accumulable(
        _chainForOnTable(assetCode, network,
            _liveCatalog?.usdReceiveExact ?? _effectiveUsdReceiveRoutes,
            exactAsset: _liveCatalog?.usdReceiveExact != null),
        assetCode,
        kOrchestraUsdAssetCode);

/// The receive-route lookup for whichever balance the money is to land
/// in: bitcoin (the default everywhere else) or the dollar balance.
/// One door so the deposit-address mint, the picker and the staleness
/// gate can never disagree about which table decides.
String? orchestraReceiveChainForDestination(
  String assetCode,
  String network, {
  required String destinationAsset,
}) =>
    destinationAsset.trim().toUpperCase() == kOrchestraUsdAssetCode
        ? orchestraUsdReceiveChainFor(assetCode, network)
        : orchestraReceiveChainFor(assetCode, network);

/// True when [assetCode] is an asset Orchestra can swap at all (either
/// direction). Orchestra is the only swap provider, so this is the ONLY
/// asset catalog swap UIs may offer: asset grids, destination pickers
/// and search results
/// must filter through this before rendering an alt-coin option.
bool orchestraSupportsSwapAsset(String assetCode) {
  final code = _normalizeAsset(assetCode);
  return _effectiveSendRoutes.containsKey(code) ||
      _effectiveReceiveRoutes.containsKey(code);
}

/// Asset code to hand Orchestra for a picked asset. The only
/// divergence is bridged USDC on Polygon, which Flashnet tracks as
/// 'USDC.e' — the contract matters: a quote opened for one variant
/// won't see a deposit of the other (see deposit_sheet.dart's USDC.e note).
String orchestraAssetCodeFor(String assetCode) {
  final code = assetCode.toUpperCase();
  return code == 'USDC.E' ? 'USDC.e' : code;
}

/// Flashnet order status → the swap-order status vocabulary the
/// shared tx UI understands. Single source of truth for the two order-
/// DISCOVERY paths — confirm_receive's on-screen history poller and
/// background sync's accumulation-address sweep — so a row reads
/// identically no matter which path recorded it. Same table background
/// sync's getStatus pollers use inline (background_sync_provider.dart);
/// keep the three in step if Flashnet grows a new status.
const Map<String, String> kOrchestraStatusToExchangeStatus = {
  'created': 'wait',
  'awaiting_payment': 'wait',
  'waiting_for_payment': 'wait',
  'pending_payment': 'wait',
  'awaiting_deposit': 'wait',
  'waiting': 'wait',
  'expired': 'expired',
  'cancelled': 'expired',
  'canceled': 'expired',
  'processing': 'exchanging',
  'confirming': 'confirmation',
  'bridging': 'exchanging',
  'swapping': 'exchanging',
  'awaiting_approval': 'confirmation',
  'delivering': 'sending',
  'completed': 'success',
  'complete': 'success',
  'success': 'success',
  'settled': 'success',
  'done': 'success',
  'failed': 'expired',
  'refunding': 'overdue',
  'refunded': 'refunded',
};

/// Maps a raw Flashnet status to the exchange-status vocabulary.
/// Lowercase/trim FIRST — Flashnet casing has varied ('COMPLETED'), and
/// an unmapped terminal value falling through raw would leave a row
/// stuck on PENDING forever. Unknown statuses pass through lowercased so
/// the row still renders something truthful.
String orchestraExchangeStatus(String rawStatus) {
  final raw = rawStatus.toLowerCase().trim();
  return kOrchestraStatusToExchangeStatus[raw] ?? raw;
}

/// Cash App onramps start as `processing` before anyone pays the invoice.
/// Only confirmed deposit evidence promotes that ambiguous state to processing
/// in the purchase UI. An unfulfilled order can still accept a late deposit,
/// and once a payment was received no unpaid status is stored for it.
String cashAppExchangeStatus(String rawStatus, {bool paymentReceived = false}) {
  final raw = rawStatus.trim().toLowerCase();
  if (raw == 'processing' && !paymentReceived) return 'pending';
  final mapped = orchestraExchangeStatus(rawStatus);
  return paymentReceived && kCashAppUnpaidStatuses.contains(mapped)
      ? 'exchanging'
      : mapped;
}

/// Terminal check on the MAPPED status. Deliberately NOT
/// `OrchestraOrder.isTerminal`: that getter compares the raw status
/// case-SENSITIVELY against Flashnet's spellings, so 'COMPLETED' (or the
/// 'settled'/'done' variants) reads as non-terminal there. 'overdue'
/// (refund in flight) is excluded — funds are still moving.
bool orchestraExchangeStatusIsTerminal(String mappedStatus) =>
    mappedStatus == 'success' ||
    mappedStatus == 'settled' ||
    mappedStatus == 'expired' ||
    mappedStatus == 'refunded';

/// One-shot analytics + backend attribution for a freshly RECORDED
/// discovered Orchestra order. Call exactly once, at the moment the
/// exchange row is first inserted into the exchange store.
///
/// WHY a single shared rule: both the receive screen's history poller
/// and background sync's accumulation sweep can discover the same
/// order. Whichever path inserts the row first owns attribution by
/// calling this; the other path skips the id via its known-ids guard,
/// so nothing double-reports. (A same-instant race between the two
/// pollers is tolerable: the backend UPSERTs on provider_order_id and
/// PostHog dedups, per background_sync_provider's terminal mirror.)
///
/// Split by state at discovery:
///  - Non-terminal → a 'pending' provider_events row only. The
///    pending→terminal transition (and its swapCompleted/revenue
///    analytics) stays with background sync's getStatus poller, which
///    is why discoverers must NOT flip stored rows terminal themselves.
///  - Terminal success → the same fan-out background sync fires on
///    pending→success (swapCompleted internally upserts the
///    provider_events row to 'completed' and emits the AppsFlyer
///    purchase signal when a real order id is passed, plus the GA4
///    revenue event). No feeUsd spread here: the order settled at some
///    earlier, unknown BTC price, so marking it to the live rate would
///    fabricate a fee.
///  - Terminal failure/refund → swapFailed, which mirrors the failure
///    to provider_events.
void reportDiscoveredOrchestraOrder(SwapOrder exchange) {
  final status = exchange.status;
  final fromAmount = double.tryParse(exchange.depositAmount);
  final toAmount = double.tryParse(exchange.withdrawalAmount);
  if (exchange.isCashAppPurchase) {
    // The backend owns authoritative order persistence and earned revenue.
    // Client analytics describe the purchase funnel, never infer profit from
    // the difference between Lightning in and Bitcoin out.
    if (orchestraExchangeStatusIsTerminal(status)) {
      final usd = double.tryParse(exchange.purchaseFiatUsd ?? '');
      final ok = status == 'success' || status == 'settled';
      // Overlapping syncs can both see this order go terminal.
      if (!claimOrderTerminalAnalytics(exchange.id, success: ok)) return;
      if (ok) {
        // Sats only for a bitcoin delivery; a dollar/venue leg is not sats.
        final sats = exchange.coinTo.toUpperCase() == 'BTC' &&
                toAmount != null &&
                toAmount.isFinite &&
                toAmount > 0
            ? (toAmount * 1e8).round()
            : null;
        TrackingService.cashAppBuyCompleted(
          amountUsd: usd,
          orderId: exchange.id,
          amountSats: sats,
          currency: usd != null ? 'USD' : null,
          amountFiat: usd,
          // The Spark spending wallet is the hot wallet; an on-chain
          // delivery's wallet kind is not known from the row alone.
          walletKind:
              exchange.networkTo.toUpperCase() == 'SPARK' ? 'hot' : null,
        );
      } else {
        TrackingService.cashAppBuyFailed(amountUsd: usd, reason: status);
      }
    }
    return;
  }
  if (!orchestraExchangeStatusIsTerminal(status)) {
    // History only ever returns real ord_… ids (never q_ quotes), so
    // registering here is safe — the ord_ gate is belt-and-braces
    // against a partner id-format change creating rows the completion
    // upsert could never reconcile with.
    if (exchange.id.startsWith('ord_')) {
      // ignore: unawaited_futures
      AffiliateService.logProviderEvent(
        provider: 'orchestra',
        providerOrderId: exchange.id,
        status: 'pending',
        sourceAsset: exchange.coinFrom,
        sourceAmount: fromAmount,
        destinationAsset: exchange.coinTo,
        destinationAmount: toAmount,
      );
    }
    return;
  }
  final ok = status == 'success' || status == 'settled';
  // Overlapping syncs (and the screen poller) can both reach this for the
  // same order; the persisted claim lets exactly one emit.
  if (!claimOrderTerminalAnalytics(exchange.id, success: ok)) return;
  // USD-equivalent legs. Discovery flows are stablecoin → BTC, so the
  // deposit side is USD-pegged; mirror background sync's fallback order
  // anyway in case the vocabulary widens.
  final usdIn = isOrchestraUsdLikeCoin(exchange.coinFrom) ? fromAmount : null;
  final usdOut = isOrchestraUsdLikeCoin(exchange.coinTo) ? toAmount : null;
  final usdLeg = usdIn ?? usdOut ?? 0.0;
  if (ok) {
    TrackingService.swapCompleted(
      fromCoin: exchange.coinFrom,
      toCoin: exchange.coinTo,
      provider: 'orchestra',
      fromAmount: fromAmount,
      toAmount: toAmount,
      amountUsd: usdLeg > 0 ? usdLeg : null,
      amountOutUsd: usdOut,
      fromNetwork: exchange.networkFrom,
      toNetwork: exchange.networkTo,
      venue: orchestraOrderVenue(exchange),
      providerOrderId: exchange.id,
    );
    // GA4 revenue — value is the USD-equivalent leg.
    if (usdLeg > 0) {
      TrackingService.revenueEventCompleted(
        transactionId: exchange.id,
        provider: 'orchestra',
        valueUsd: usdLeg,
        sourceAsset: exchange.coinFrom,
        destinationAsset: exchange.coinTo,
      );
    }
  } else {
    // 'expired' (Flashnet 'failed') or 'refunded' — same reason string
    // background sync passes on its pending→failure transition.
    TrackingService.swapFailed(
      fromCoin: exchange.coinFrom,
      toCoin: exchange.coinTo,
      provider: 'orchestra',
      reason: status,
      fromAmount: fromAmount,
      amountUsd: usdLeg > 0 ? usdLeg : null,
      fromNetwork: exchange.networkFrom,
      toNetwork: exchange.networkTo,
      venue: orchestraOrderVenue(exchange),
      providerOrderId: exchange.id,
    );
  }
}

/// Coins whose amount is read as USD for analytics: dollar stablecoins
/// (including the Spark dollar token USDB). EUR/GBP/CHF are NOT dollars.
bool isOrchestraUsdLikeCoin(String coin) {
  final c = coin.toUpperCase();
  return c == 'USDC' ||
      c == 'USDC.E' ||
      c == 'USDT' ||
      c == 'DAI' ||
      c == 'USD' ||
      c == 'USDB';
}

/// The venue an Orchestra order funds or drains, for swap analytics:
/// HyperCore is Investing ('hyperliquid'), Polygon USDC is Predictions
/// ('polymarket'), anything else stays in the wallet.
String orchestraOrderVenue(SwapOrder e) {
  bool hyper(String n) {
    final c = n.toLowerCase();
    return c == 'hypercore' || c == 'hyperliquid';
  }

  if (hyper(e.networkFrom) || hyper(e.networkTo)) return 'hyperliquid';
  if (isPolymarketDepositOrder(e) || isPolymarketWithdrawOrder(e)) {
    return 'polymarket';
  }
  return 'wallet';
}

/// An order delivering Polygon USDC (a Predictions deposit).
bool isPolymarketDepositOrder(SwapOrder e) =>
    e.networkTo.toUpperCase() == 'POLYGON' &&
    e.coinTo.toUpperCase().startsWith('USDC');

/// An order paid from Polygon USDC (a Predictions withdrawal).
bool isPolymarketWithdrawOrder(SwapOrder e) =>
    e.networkFrom.toUpperCase() == 'POLYGON' &&
    e.coinFrom.toUpperCase().startsWith('USDC');

/// Claims the single terminal analytics emit for [orderId]'s [success]
/// outcome. Overlapping syncs (a BackgroundSyncService restart, a direct
/// settings sync, the receive-screen poller) can each see the same order
/// go terminal; the persisted flag lets exactly one of them report it.
/// The key is local only and carries the one-way order reference, never
/// the raw id. Fails open when the flag box is not open yet (early boot,
/// unit tests), so a real outcome is never silently dropped.
bool claimOrderTerminalAnalytics(String orderId, {required bool success}) {
  if (orderId.isEmpty) return true;
  if (!Hive.isBoxOpen(OnceFlagsService.boxName)) return true;
  return OnceFlagsService.claimOnce('swap_terminal:'
      '${TrackingService.orderRef(orderId)}:${success ? 'success' : 'failed'}');
}

/// Terminal analytics for an unpaid Cash App order whose payment window
/// closed ('unfulfilled' or past its invoice expiry). Such an order never
/// reaches a mapped terminal status, so without this it has no terminal
/// event at all. Fires once per order (persisted flag keyed by the
/// one-way order reference). A late payment still reports its own
/// cashapp_buy_completed through the normal terminal path.
void reportCashAppPaymentWindowEnded(SwapOrder exchange) {
  if (!exchange.cashAppPaymentWindowClosed) return;
  if (!OnceFlagsService.claimOnce(
      'cashapp_window_ended:${TrackingService.orderRef(exchange.id)}')) {
    return;
  }
  final usd = double.tryParse(exchange.purchaseFiatUsd ?? '');
  TrackingService.track('cashapp_payment_window_ended', params: {
    'venue': 'cashapp',
    'order_id': exchange.id, // one-way ref, see sanitizeParams
    'provider_status':
        exchange.status == 'unfulfilled' ? 'unfulfilled' : 'expired_locally',
    if (usd != null && usd.isFinite) 'amount_bucket': TrackingService.usdBucket(usd),
  });
}
