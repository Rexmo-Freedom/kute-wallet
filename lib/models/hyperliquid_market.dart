// lib/models/hyperliquid_market.dart
//
// Trading-grade data classes for the Hyperliquid integration. The legacy
// `HyperliquidTicker` (hyperliquid_model.dart) only carries what the home
// rail sparkline needs; placing orders additionally requires the asset id
// on the order wire, szDecimals for size/price rounding, and leverage
// metadata. `HlMarket` is the browse/trade descriptor; the account structs
// (`HlPerpPosition`, `HlSpotBalance`, `HlOpenOrder`, `HlFill`,
// `HlAccountSnapshot`, `HlL2Book`) mirror the /info response shapes.
//
// Parsing lives HERE (static factories) rather than in the HTTP client so
// it is unit-testable against JSON fixtures without network plumbing —
// see test/models/hyperliquid_market_test.dart. All numeric fields arrive
// as strings on the Hyperliquid wire; we parse defensively with
// double.tryParse like the rest of the repo's models. Structural failures
// (wrong top-level shape) throw FormatException so providers can render
// error states; per-entry oddities are skipped.
//
// Three id systems, all load-bearing (mirrored from the Go backend
// internal/hyperliquid/markets.go so the direct-from-HL and backend paths
// agree byte-for-byte on asset ids):
//   * default perp assetId = POSITION in the meta universe list;
//   * HIP-3 perp assetId   = 100000 + dexIndex*10000 + indexInMeta, where
//     dexIndex is the builder dex's POSITION in the perpDexs list;
//   * spot assetId         = 10000 + the pair's `index` FIELD from spotMeta
//     (NOT its position in the list — they usually agree, but only the
//     field is authoritative).
// Spot markets keep a `wireCoin` (`@<index>` / canonical pair name) used
// for l2Book/candles/allMids keys, distinct from the display `coin`
// (base token name). HIP-3 coins are dex-qualified on the wire
// ("<dex>:WHEAT") but DISPLAY the bare base ("WHEAT"). Every WS/REST
// market-data call must use wireCoin.

import 'dart:math' as math;

import 'package:kute/constants/hyperliquid_constants.dart';

enum HlMarketKind { perp, spot }

/// 24-hour notional volume (USD) under which a market is called low
/// liquidity. Measured on the live lists (4 Oct 2026, a Sunday): it flags
/// the spot tokens nobody trades and the quiet builder-dex markets, and
/// is a factor of four under the quietest major stock perp.
const double kHlLowLiquidityDayVolumeUsd = 50000;

/// One tradable market (perp or USDC-quoted spot pair) with everything the
/// order path needs: wire ids, rounding metadata, leverage caps, and the
/// latest price/volume context.
class HlMarket {
  /// Display symbol. Perp: 'BTC'. Spot: base token name, e.g. 'TSLA'.
  final String coin;

  /// The coin string market-data endpoints expect (candleSnapshot, l2Book,
  /// allMids, trades). Perp: same as [coin]. Spot: the universe pair name —
  /// `@<index>` for most pairs, 'PURR/USDC' style for canonical ones.
  final String wireCoin;

  /// Order-wire asset id (`a` field). Perp: universe position. Spot:
  /// 10000 + pair `index` field.
  final int assetId;

  final HlMarketKind kind;

  /// Max decimals allowed on order sizes.
  final int szDecimals;

  /// Perp max leverage from meta; 1 for spot.
  final int maxLeverage;

  /// Margin mode from the perps `meta` universe entry: 'strictIsolated'
  /// (isolated only; margin cannot be removed) or 'noCross' (isolated
  /// only). Null when the venue omitted it (older payloads) and for spot.
  final String? marginMode;

  /// The deprecated `onlyIsolated` boolean, consulted only when
  /// [marginMode] is absent.
  final bool _onlyIsolatedLegacy;

  /// True when the perp only supports isolated margin. Derived from
  /// [marginMode] when present — the docs mark `onlyIsolated` deprecated
  /// ("means either strictIsolated or noCross") — else the legacy boolean.
  bool get onlyIsolated => marginMode != null
      ? isolatedOnlyMarginMode(marginMode)
      : _onlyIsolatedLegacy;

  /// True when isolated margin cannot be removed from a position.
  bool get isolatedMarginLocked => marginMode == 'strictIsolated';

  /// The two documented isolated-only margin modes.
  static bool isolatedOnlyMarginMode(String? mode) =>
      mode == 'strictIsolated' || mode == 'noCross';

  final double markPx;

  /// Book midpoint. Falls back to [markPx] when the ctx omits it (empty
  /// book) so consumers always have a usable reference price.
  final double midPx;
  final double prevDayPx;
  final double dayNtlVlm;

  /// Perps only (null for spot).
  final double? funding;
  final double? openInterest;

  /// Coarse browse category as resolved by the backend catalog:
  /// `crypto|stocks|commodities|fx|indices|preipo|other`. Defaults to
  /// 'crypto' so the direct-from-HL parse (which doesn't classify) still
  /// constructs sensibly; the markets provider re-tags direct spot pairs
  /// (stocks/commodities) via [copyWith] on the fallback path.
  final String category;

  /// The perp DEX this market belongs to. '' (empty) for the default HL
  /// perp dex + spot; a builder-dex name (e.g. 'unit') for HIP-3 markets.
  final String dex;

  /// True for HIP-3 (builder-deployed) perp markets.
  final bool isHip3;

  /// Coin-logo URL (backend-provided). When null the UI builds the HL CDN
  /// URL from the base coin, and falls back to a letter badge on a miss.
  final String? iconUrl;

  /// The venue's own friendly name for this market from
  /// `perpConciseAnnotations` (io:OAI → 'OPENAI', xyz:CL → 'WTIOIL'), or
  /// null. Search only: the ticker stays the displayed symbol.
  final String? annotatedName;

  /// For a Unit-bridged spot token, the asset it holds ('Bitcoin' for
  /// UBTC, from the venue's full name "Unit Bitcoin"); null otherwise.
  /// Hyperliquid's own app shows these tokens under the asset's name.
  final String? unitAssetName;

  /// The venue's search keywords for this market (xyz:XYZ100 → nasdaq,
  /// qqq; xyz:CL → crude). Search only.
  final List<String> keywords;

  const HlMarket({
    required this.coin,
    required this.wireCoin,
    required this.assetId,
    required this.kind,
    required this.szDecimals,
    required this.maxLeverage,
    required bool onlyIsolated,
    this.marginMode,
    required this.markPx,
    required this.midPx,
    required this.prevDayPx,
    required this.dayNtlVlm,
    this.funding,
    this.openInterest,
    this.category = 'crypto',
    this.dex = '',
    this.isHip3 = false,
    this.iconUrl,
    this.annotatedName,
    this.unitAssetName,
    this.keywords = const [],
  }) : _onlyIsolatedLegacy = onlyIsolated;

  /// Copy with select fields overridden. Used by the markets provider to
  /// re-tag the direct-from-HL fallback markets with a browse [category]
  /// (the direct parse can't classify tokenized equities/commodities).
  HlMarket copyWith({
    String? category,
    String? dex,
    bool? isHip3,
    String? iconUrl,
    String? annotatedName,
    List<String>? keywords,
  }) {
    return HlMarket(
      coin: coin,
      wireCoin: wireCoin,
      assetId: assetId,
      kind: kind,
      szDecimals: szDecimals,
      maxLeverage: maxLeverage,
      onlyIsolated: _onlyIsolatedLegacy,
      marginMode: marginMode,
      markPx: markPx,
      midPx: midPx,
      prevDayPx: prevDayPx,
      dayNtlVlm: dayNtlVlm,
      funding: funding,
      openInterest: openInterest,
      category: category ?? this.category,
      dex: dex ?? this.dex,
      isHip3: isHip3 ?? this.isHip3,
      iconUrl: iconUrl ?? this.iconUrl,
      annotatedName: annotatedName ?? this.annotatedName,
      unitAssetName: unitAssetName,
      keywords: keywords ?? this.keywords,
    );
  }

  /// HIP-3 (builder-deployed perp dex) asset-id formula:
  /// 100000 + dexIndex*10000 + indexInMeta, where dexIndex is the dex's
  /// POSITION in the perpDexs list. The default (crypto) perp dex is
  /// perpDexs index 0 and uses the plain meta index. Mirrors the backend
  /// (internal/hyperliquid/markets.go: hip3AssetIDBase / hip3DexIDStride).
  static const int hip3AssetIdBase = 100000;
  static const int hip3DexIdStride = 10000;

  /// The HL web-app coin icon for a base symbol:
  /// `https://app.hyperliquid.xyz/coins/<BASE>.svg` (mirrors the backend
  /// iconURL). The card falls back to a letter badge on a CDN miss.
  static String hlIconUrl(String base) =>
      'https://app.hyperliquid.xyz/coins/$base.svg';

  /// 'Bitcoin' for the token UBTC with the venue's full name "Unit
  /// Bitcoin"; null for a token that is not Unit-bridged.
  static String? hlUnitAssetName(String token, String? fullName) {
    if (token.length < 2 || !token.startsWith('U')) return null;
    final name = (fullName ?? '').trim();
    if (!name.startsWith('Unit ')) return null;
    final asset = name.substring(5).trim();
    return asset.isEmpty ? null : asset;
  }

  /// The HL web-app icon of a SPOT token: `coins/<NAME>_spot.svg`, where
  /// NAME is the name Hyperliquid's own app shows. A Unit-bridged token
  /// (UBTC "Unit Bitcoin", UFART "Unit Fartcoin") is shown there without
  /// its U, so its icon is `BTC_spot.svg`. Only the venue's own "Unit "
  /// full name strips the letter: HOP, RIP and WAR are tokens of their own.
  static String hlSpotIconUrl(String token, {String? fullName}) {
    final unit = token.length > 1 &&
        token.startsWith('U') &&
        (fullName ?? '').startsWith('Unit ');
    return 'https://app.hyperliquid.xyz/coins/'
        '${unit ? token.substring(1) : token}_spot.svg';
  }

  /// Strip a `<dex>:` HIP-3 prefix, returning the bare display base coin
  /// ("xyz:WHEAT" → "WHEAT", "BTC" → "BTC").
  static String baseCoin(String name) {
    final i = name.indexOf(':');
    return i >= 0 ? name.substring(i + 1) : name;
  }

  /// The `perpConciseAnnotations` key of the perp [base] on [dex] ('' =
  /// the default dex): 'dex:BASE' (dex lower case, base upper case) or
  /// 'BASE'. The venue annotates builder-dex coins dex-qualified
  /// (para:STX, flx:GAS); keying by the bare symbol let those tag the
  /// default dex's STX and GAS crypto perps as a stock and a commodity.
  static String annotationKey(String dex, String base) {
    final up = baseCoin(base).toUpperCase();
    return dex.isEmpty ? up : '${dex.toLowerCase()}:$up';
  }

  /// The venue's category spellings folded onto the app's: lower case,
  /// 'stock' → 'stocks', 'commodity' → 'commodities', 'index' →
  /// 'indices'. The feed sends 'FX' beside 'fx' and 'stock' beside
  /// 'stocks'.
  static String normalizeCategory(String raw) {
    final c = raw.trim().toLowerCase();
    return switch (c) {
      'stock' => 'stocks',
      'commodity' => 'commodities',
      'index' => 'indices',
      _ => c,
    };
  }

  /// Category for a perp coin: its own annotation's category if present,
  /// else 'crypto' for the default dex, else 'other' for an unannotated
  /// builder dex coin (mirrors the backend categorizePerp).
  static String _categorizePerp(HlPerpAnnotation? annotation, bool isDefault) {
    final c = annotation?.category ?? '';
    if (c.isNotEmpty) return c;
    return isDefault ? 'crypto' : 'other';
  }

  bool get isSpot => kind == HlMarketKind.spot;

  /// 24h change at [px] (a live mid or mark) against [prevDayPx], as a
  /// fraction; 0 without a previous-day price. Lists that show a live
  /// price show the change of that same price, not the snapshot's.
  double dayChangeAt(double px) {
    if (prevDayPx <= 0 || px <= 0) return dayChangePct;
    return (px - prevDayPx) / prevDayPx;
  }

  /// [dayChangeAt], or null when there is no previous-day price to
  /// measure against (a pair that has not traded): the UI shows a dash,
  /// never 0% or −100%.
  ///
  /// A spot pair nobody traded in 24 h has no change to show either: its
  /// previous price is a stale mark. And when the book is so thin that the
  /// mid sits far from the mark (one resting order a multiple away), the
  /// change is measured at the mark, not at that mid.
  double? dayChangeAtOrNull(double px) {
    if (prevDayPx <= 0) return null;
    if (isSpot && dayNtlVlm <= 0) return null;
    var at = px > 0 ? px : markPx;
    if (markPx > 0 && (at - markPx).abs() / markPx > 0.5) at = markPx;
    if (at <= 0) return null;
    return (at - prevDayPx) / prevDayPx;
  }

  /// This market with live context numbers (activeAssetCtx). Identity,
  /// rounding metadata and classification are untouched.
  HlMarket withLiveCtx({
    required double markPx,
    double? midPx,
    required double prevDayPx,
    required double dayNtlVlm,
    double? funding,
    double? openInterest,
  }) {
    return HlMarket(
      coin: coin,
      wireCoin: wireCoin,
      assetId: assetId,
      kind: kind,
      szDecimals: szDecimals,
      maxLeverage: maxLeverage,
      onlyIsolated: _onlyIsolatedLegacy,
      marginMode: marginMode,
      markPx: markPx > 0 ? markPx : this.markPx,
      midPx: (midPx ?? 0) > 0 ? midPx! : this.midPx,
      prevDayPx: prevDayPx > 0 ? prevDayPx : this.prevDayPx,
      dayNtlVlm: dayNtlVlm,
      funding: isSpot ? this.funding : (funding ?? this.funding),
      openInterest: isSpot ? this.openInterest : (openInterest ?? this.openInterest),
      category: category,
      dex: dex,
      isHip3: isHip3,
      iconUrl: iconUrl,
      annotatedName: annotatedName,
      unitAssetName: unitAssetName,
      keywords: keywords,
    );
  }

  /// A thinly traded market: under [kHlLowLiquidityDayVolumeUsd] traded
  /// in the last 24 hours, a market with no trade at all included. The
  /// ONE rule behind the "Low liquidity" label on the browse card and the
  /// market header, and behind the chart opening on a coarser interval
  /// (hl_chart_opening.dart), so the three always agree.
  bool get isLowLiquidity => dayNtlVlm < kHlLowLiquidityDayVolumeUsd;

  /// Offer the venue's per-market limit, without an additional app cap.
  int get offeredMaxLeverage => math.max(1, maxLeverage);

  /// 24h change as a fraction (0.025 == +2.5%); 0 when prev-day price is
  /// unavailable so the UI can render "—" safely (same contract as
  /// HyperliquidTicker.dayChangePct).
  double get dayChangePct {
    if (prevDayPx <= 0) return 0;
    return (markPx - prevDayPx) / prevDayPx;
  }

  /// Max price decimals per the exchange tick rule:
  /// (6 - szDecimals) perps, (8 - szDecimals) spot.
  int get pxDecimalCap => math.max(0, (isSpot ? 8 : 6) - szDecimals);

  /// Parse the decoded `metaAndAssetCtxs` response ([meta, ctxs]) for ONE
  /// perp dex. [dex] is '' for the default (crypto) dex, else the builder
  /// (HIP-3) dex name; [dexIndex] is its POSITION in the perpDexs list (used
  /// only for HIP-3 asset ids). [annotations] (keyed by [annotationKey])
  /// classifies each coin and carries its friendly name and keywords —
  /// pass the perpConciseAnnotations map so tradfi perps (fx/indices/…)
  /// tag correctly; a null map falls back to crypto/other. Delisted
  /// universe entries are skipped, but assetId stays the universe POSITION
  /// for every entry that survives (order-wire ids are positional). HIP-3
  /// coins arrive UNPREFIXED and are dex-qualified for the wire
  /// ("xyz:WHEAT") while displayed as the bare base ("WHEAT").
  static List<HlMarket> parsePerpList(
    dynamic decoded, {
    String dex = '',
    int dexIndex = 0,
    Map<String, HlPerpAnnotation>? annotations,
  }) {
    if (decoded is! List || decoded.length < 2) {
      throw const FormatException('unexpected metaAndAssetCtxs shape');
    }
    final meta = decoded[0];
    final ctxs = decoded[1];
    if (meta is! Map<String, dynamic> || ctxs is! List) {
      throw const FormatException('unexpected metaAndAssetCtxs shape');
    }
    final universe = (meta['universe'] as List?) ?? const [];
    final isDefault = dex.isEmpty;

    final out = <HlMarket>[];
    for (var i = 0; i < universe.length; i++) {
      final u = universe[i];
      if (u is! Map<String, dynamic>) continue;
      final rawName = (u['name'] as String?) ?? '';
      if (rawName.isEmpty) continue;
      if (u['isDelisted'] == true) continue;
      final c = (i < ctxs.length && ctxs[i] is Map<String, dynamic>)
          ? ctxs[i] as Map<String, dynamic>
          : const <String, dynamic>{};

      // Default dex: wire == display == name, assetId == universe position.
      // Builder (HIP-3) dex: dex-qualified wire + offset asset id, bare base
      // for display.
      final display = baseCoin(rawName);
      final String wire;
      final int assetId;
      if (isDefault) {
        wire = rawName;
        assetId = i;
      } else {
        wire = rawName.contains(':') ? rawName : '$dex:$rawName';
        assetId = hip3AssetIdBase + dexIndex * hip3DexIdStride + i;
      }

      final markPx = _toDouble(c['markPx']) ?? 0;
      final annotation = annotations?[annotationKey(dex, display)];
      out.add(HlMarket(
        coin: display,
        wireCoin: wire,
        assetId: assetId,
        kind: HlMarketKind.perp,
        szDecimals: _toInt(u['szDecimals']) ?? 0,
        maxLeverage: _toInt(u['maxLeverage']) ?? 1,
        onlyIsolated: u['onlyIsolated'] == true,
        marginMode: _marginMode(u['marginMode']),
        markPx: markPx,
        midPx: _toDouble(c['midPx']) ?? markPx,
        prevDayPx: _toDouble(c['prevDayPx']) ?? 0,
        dayNtlVlm: _toDouble(c['dayNtlVlm']) ?? 0,
        funding: _toDouble(c['funding']),
        openInterest: _toDouble(c['openInterest']),
        category: _categorizePerp(annotation, isDefault),
        dex: dex,
        isHip3: !isDefault,
        // HL hosts the logo under the DEX-QUALIFIED wire (coins/xyz:SPCX.svg);
        // the bare coins/SPCX.svg is the SPA's HTML catch-all. For the default
        // dex wire == display, so this is a no-op there.
        iconUrl: hlIconUrl(wire),
        annotatedName: annotation?.displayName,
        keywords: annotation?.keywords ?? const [],
      ));
    }
    return out;
  }

  /// Parse the decoded `spotMetaAndAssetCtxs` response ([spotMeta, ctxs]).
  /// Includes EVERY USDC-quoted pair (full universe, no allowlist); pairs
  /// whose base token can't be resolved are skipped.
  static List<HlMarket> parseSpotList(dynamic decoded) {
    if (decoded is! List || decoded.length < 2) {
      throw const FormatException('unexpected spotMetaAndAssetCtxs shape');
    }
    final meta = decoded[0];
    final ctxs = decoded[1];
    if (meta is! Map<String, dynamic> || ctxs is! List) {
      throw const FormatException('unexpected spotMetaAndAssetCtxs shape');
    }
    final tokens = (meta['tokens'] as List?) ?? const [];
    final universe = (meta['universe'] as List?) ?? const [];

    // token index → (name, szDecimals). USDC is token index 0 by protocol.
    final tokenNameByIndex = <int, String>{};
    final tokenFullNameByIndex = <int, String>{};
    final tokenSzDecimalsByIndex = <int, int>{};
    for (final t in tokens) {
      if (t is! Map<String, dynamic>) continue;
      final idx = _toInt(t['index']);
      if (idx == null) continue;
      final name = (t['name'] as String?) ?? '';
      if (name.isNotEmpty) tokenNameByIndex[idx] = name;
      final fullName = t['fullName'];
      if (fullName is String) tokenFullNameByIndex[idx] = fullName;
      final sz = _toInt(t['szDecimals']);
      if (sz != null) tokenSzDecimalsByIndex[idx] = sz;
    }

    // Each context names its pair in `coin`. The contexts are NOT in
    // universe order (the venue returns more contexts than listed pairs),
    // so reading them by position gave a pair another pair's previous-day
    // price and volume: a 24h change of −100% or +240,000%. Position is
    // only the fallback for a payload whose contexts carry no `coin`.
    final ctxByCoin = <String, Map<String, dynamic>>{};
    for (final c in ctxs) {
      if (c is! Map<String, dynamic>) continue;
      final coin = c['coin'];
      if (coin is String && coin.isNotEmpty) ctxByCoin[coin] = c;
    }

    final out = <HlMarket>[];
    for (var i = 0; i < universe.length; i++) {
      final u = universe[i];
      if (u is! Map<String, dynamic>) continue;
      final pairTokens = (u['tokens'] as List?) ?? const [];
      if (pairTokens.length < 2) continue;
      final baseIdx = _toInt(pairTokens[0]);
      final quoteIdx = _toInt(pairTokens[1]);
      // USDC-quoted only (quote token index 0). Non-USDC quotes (e.g.
      // USDH-quoted pairs) can't be traded against the user's USDC balance.
      if (baseIdx == null || quoteIdx != 0) continue;
      final pairIndex = _toInt(u['index']);
      if (pairIndex == null) continue;
      final baseName = tokenNameByIndex[baseIdx];
      if (baseName == null || baseName.isEmpty) continue;

      final pairName = (u['name'] as String?) ?? '';
      final Map<String, dynamic> c;
      if (ctxByCoin.isNotEmpty) {
        c = ctxByCoin[pairName.isNotEmpty ? pairName : '@$pairIndex'] ??
            const <String, dynamic>{};
      } else {
        c = (i < ctxs.length && ctxs[i] is Map<String, dynamic>)
            ? ctxs[i] as Map<String, dynamic>
            : const <String, dynamic>{};
      }

      final markPx = _toDouble(c['markPx']) ?? 0;
      out.add(HlMarket(
        coin: baseName,
        wireCoin: pairName.isNotEmpty ? pairName : '@$pairIndex',
        assetId: HyperliquidConstants.spotAssetIdOffset + pairIndex,
        kind: HlMarketKind.spot,
        szDecimals: tokenSzDecimalsByIndex[baseIdx] ?? 0,
        maxLeverage: 1,
        onlyIsolated: false,
        markPx: markPx,
        midPx: _toDouble(c['midPx']) ?? markPx,
        prevDayPx: _toDouble(c['prevDayPx']) ?? 0,
        dayNtlVlm: _toDouble(c['dayNtlVlm']) ?? 0,
        iconUrl: hlSpotIconUrl(baseName,
            fullName: tokenFullNameByIndex[baseIdx]),
        unitAssetName:
            hlUnitAssetName(baseName, tokenFullNameByIndex[baseIdx]),
      ));
    }
    return out;
  }

  /// Parse the backend catalog response — the FULL merged universe (default
  /// perps + HIP-3/builder perp dexes + spot), already categorized +
  /// calculated server-side. Accepts either `{ "markets": [...] }` or a bare
  /// list. Entries missing a display coin are skipped. Order-wire metadata
  /// (szDecimals/marginMode) is parsed when present but defaults sensibly —
  /// for coins that also live in the direct-HL universe the detail/order path
  /// re-resolves the authoritative descriptor via `hyperliquidMarketProvider`.
  static List<HlMarket> parseCatalog(dynamic decoded) {
    final List raw;
    if (decoded is Map<String, dynamic>) {
      final m = decoded['markets'];
      raw = m is List ? m : const [];
    } else if (decoded is List) {
      raw = decoded;
    } else {
      return const [];
    }
    final out = <HlMarket>[];
    for (final e in raw) {
      if (e is! Map<String, dynamic>) continue;
      final m = _fromBackendJson(e);
      if (m != null) out.add(m);
    }
    return out;
  }

  static String? _marginMode(dynamic v) {
    if (v is! String) return null;
    final s = v.trim();
    return s.isEmpty ? null : s;
  }

  /// The market as the on-disk list cache stores it: the backend catalogue
  /// shape, so one reader serves both.
  Map<String, dynamic> toCacheJson() => {
        'coin': coin,
        'wireCoin': wireCoin,
        'assetId': assetId,
        'kind': kind == HlMarketKind.spot ? 'spot' : 'perp',
        'szDecimals': szDecimals,
        'maxLeverage': maxLeverage,
        'onlyIsolated': _onlyIsolatedLegacy,
        if (marginMode != null) 'marginMode': marginMode,
        'markPx': markPx,
        'midPx': midPx,
        'prevDayPx': prevDayPx,
        'dayNtlVlm': dayNtlVlm,
        if (funding != null) 'funding': funding,
        if (openInterest != null) 'openInterest': openInterest,
        'category': category,
        'dex': dex,
        'isHip3': isHip3,
        if (iconUrl != null) 'iconUrl': iconUrl,
        if (annotatedName != null) 'annotatedName': annotatedName,
        if (unitAssetName != null) 'unitAssetName': unitAssetName,
        if (keywords.isNotEmpty) 'keywords': keywords,
      };

  static HlMarket? fromCacheJson(Map<String, dynamic> j) =>
      _fromBackendJson(j);

  static HlMarket? _fromBackendJson(Map<String, dynamic> j) {
    final coin = (j['coin'] as String?)?.trim() ?? '';
    if (coin.isEmpty) return null;
    final kind = (j['kind'] as String?)?.toLowerCase() == 'spot'
        ? HlMarketKind.spot
        : HlMarketKind.perp;
    final wire = (j['wireCoin'] as String?)?.trim();

    final markPx = _toDouble(j['markPx']) ?? 0;
    // Prefer the explicit prev-day price; otherwise back it out of the
    // server-computed 24h change so [dayChangePct] still renders.
    var prevDayPx = _toDouble(j['prevDayPx']) ?? 0;
    if (prevDayPx <= 0) {
      final chg = _toDouble(j['dayChangePct']);
      if (chg != null && chg != 0 && markPx > 0) {
        prevDayPx = markPx / (1 + chg);
      }
    }

    var category = HlMarket.normalizeCategory((j['category'] as String?) ?? '');
    if (category.isEmpty) {
      category = j['isStock'] == true ? 'stocks' : 'crypto';
    }

    final iconUrl = (j['iconUrl'] as String?)?.trim();

    return HlMarket(
      coin: coin,
      wireCoin: (wire != null && wire.isNotEmpty) ? wire : coin,
      assetId: _toInt(j['assetId']) ?? 0,
      kind: kind,
      szDecimals: _toInt(j['szDecimals']) ?? 0,
      maxLeverage: _toInt(j['maxLeverage']) ?? 1,
      onlyIsolated: j['onlyIsolated'] == true,
      marginMode: _marginMode(j['marginMode']),
      markPx: markPx,
      midPx: _toDouble(j['midPx']) ?? markPx,
      prevDayPx: prevDayPx,
      dayNtlVlm: _toDouble(j['dayNtlVlm']) ?? 0,
      funding: _toDouble(j['funding']),
      openInterest: _toDouble(j['openInterest']),
      category: category,
      dex: (j['dex'] as String?)?.trim() ?? '',
      isHip3: j['isHip3'] == true,
      iconUrl: (iconUrl != null && iconUrl.isNotEmpty) ? iconUrl : null,
      unitAssetName: (j['unitAssetName'] as String?)?.trim().isNotEmpty == true
          ? (j['unitAssetName'] as String).trim()
          : null,
      annotatedName: (j['annotatedName'] as String?)?.trim().isNotEmpty == true
          ? (j['annotatedName'] as String).trim()
          : null,
      keywords: [
        for (final k in (j['keywords'] as List?) ?? const [])
          if (k is String && k.trim().isNotEmpty) k.trim(),
      ],
    );
  }
}

/// One coin's `perpConciseAnnotations` record: its category (normalised by
/// [HlMarket.normalizeCategory]), the venue's friendly name and its search
/// keywords. Keyed by [HlMarket.annotationKey].
class HlPerpAnnotation {
  final String category;
  final String? displayName;
  final List<String> keywords;

  const HlPerpAnnotation({
    required this.category,
    this.displayName,
    this.keywords = const [],
  });

  /// Decodes the `[[coin, {category, displayName, keywords}], ...]` wire
  /// shape. Malformed entries are skipped.
  static Map<String, HlPerpAnnotation> parseList(dynamic decoded) {
    final out = <String, HlPerpAnnotation>{};
    if (decoded is! List) return out;
    for (final pair in decoded) {
      if (pair is! List || pair.length < 2) continue;
      final coin = pair[0];
      final meta = pair[1];
      if (coin is! String || coin.isEmpty || meta is! Map) continue;
      final sep = coin.indexOf(':');
      final dex = sep > 0 ? coin.substring(0, sep) : '';
      final name = (meta['displayName'] as String?)?.trim();
      out[HlMarket.annotationKey(dex, coin)] = HlPerpAnnotation(
        category: HlMarket.normalizeCategory(
            (meta['category'] as String?) ?? ''),
        displayName: (name == null || name.isEmpty) ? null : name,
        keywords: [
          for (final k in (meta['keywords'] as List?) ?? const [])
            if (k is String && k.trim().isNotEmpty) k.trim(),
        ],
      );
    }
    return out;
  }
}

/// One open perp position from `clearinghouseState.assetPositions`.
class HlPerpPosition {
  final String coin;

  /// Signed size: positive = long, negative = short.
  final double szi;
  final double entryPx;
  final double positionValue;
  final double unrealizedPnl;
  final double returnOnEquity;

  /// Null when the position has no liquidation price (e.g. tiny cross).
  final double? liquidationPx;
  final double marginUsed;

  /// 'cross' | 'isolated'.
  final String leverageType;
  final int leverageValue;
  final int maxLeverage;

  /// Funding accrued since this position opened (clearinghouseState
  /// `cumFunding.sinceOpen`). POSITIVE = the position has PAID funding,
  /// negative = received. Null on WS forms that omit cumFunding.
  final double? fundingSinceOpen;

  const HlPerpPosition({
    required this.coin,
    required this.szi,
    required this.entryPx,
    required this.positionValue,
    required this.unrealizedPnl,
    required this.returnOnEquity,
    required this.liquidationPx,
    required this.marginUsed,
    required this.leverageType,
    required this.leverageValue,
    required this.maxLeverage,
    this.fundingSinceOpen,
  });

  bool get isLong => szi > 0;
  bool get isCross => leverageType == 'cross';

  /// Accepts either an `assetPositions` element (position nested under
  /// 'position') or the bare position map (WS forms send it unwrapped).
  factory HlPerpPosition.fromJson(Map<String, dynamic> json) {
    final p = (json['position'] is Map<String, dynamic>)
        ? json['position'] as Map<String, dynamic>
        : json;
    final leverage = (p['leverage'] is Map<String, dynamic>)
        ? p['leverage'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return HlPerpPosition(
      coin: (p['coin'] as String?) ?? '',
      szi: _toDouble(p['szi']) ?? 0,
      entryPx: _toDouble(p['entryPx']) ?? 0,
      positionValue: _toDouble(p['positionValue']) ?? 0,
      unrealizedPnl: _toDouble(p['unrealizedPnl']) ?? 0,
      returnOnEquity: _toDouble(p['returnOnEquity']) ?? 0,
      liquidationPx: _toDouble(p['liquidationPx']),
      marginUsed: _toDouble(p['marginUsed']) ?? 0,
      leverageType: (leverage['type'] as String?) ?? 'cross',
      leverageValue: _toInt(leverage['value']) ?? 1,
      maxLeverage: _toInt(p['maxLeverage']) ?? 1,
      fundingSinceOpen: (p['cumFunding'] is Map<String, dynamic>)
          ? _toDouble((p['cumFunding'] as Map<String, dynamic>)['sinceOpen'])
          : null,
    );
  }
}

/// One spot token balance from `spotClearinghouseState.balances`.
class HlSpotBalance {
  final String coin;
  final double total;

  /// Amount locked in resting orders.
  final double hold;

  /// What the venue records as paid for this balance, USDC
  /// (`spotClearinghouseState.balances[].entryNtl`). Null or 0 when it
  /// has no cost on record (received by transfer, or USDC itself).
  final double? entryNtl;

  const HlSpotBalance({
    required this.coin,
    required this.total,
    required this.hold,
    this.entryNtl,
  });

  double get available => math.max(0, total - hold);

  /// The recorded cost, when there is one.
  double? get costBasis =>
      entryNtl != null && entryNtl!.isFinite && entryNtl! > 0 ? entryNtl : null;

  factory HlSpotBalance.fromJson(Map<String, dynamic> json) => HlSpotBalance(
        coin: (json['coin'] as String?) ?? '',
        total: _toDouble(json['total']) ?? 0,
        hold: _toDouble(json['hold']) ?? 0,
        entryNtl: _toDouble(json['entryNtl']),
      );
}

/// One resting order from `frontendOpenOrders`.
class HlOpenOrder {
  final String coin;
  final int oid;
  final bool isBuy; // side == 'B'
  final double limitPx;

  /// Remaining size.
  final double sz;
  final double origSz;

  /// Placement time, epoch ms.
  final int timestamp;
  final String? cloid;
  final bool reduceOnly;

  /// 'Limit', 'Stop Market', ... (frontendOpenOrders only).
  final String orderType;
  final bool isTrigger;
  final double? triggerPx;

  bool get isTrailingStop => orderType == 'Trailing Stop Market';

  const HlOpenOrder({
    required this.coin,
    required this.oid,
    required this.isBuy,
    required this.limitPx,
    required this.sz,
    required this.origSz,
    required this.timestamp,
    required this.cloid,
    required this.reduceOnly,
    required this.orderType,
    required this.isTrigger,
    required this.triggerPx,
    this.tif = 'Gtc',
    this.isPositionTpsl = false,
  });

  /// Time in force as the venue reports it ('Gtc', 'Alo', 'Ioc'); a
  /// modify re-sends it so a post-only order stays post-only.
  final String tif;

  /// A take-profit or stop-loss attached to the whole position rather
  /// than a fixed size (frontendOpenOrders `isPositionTpsl`).
  final bool isPositionTpsl;

  /// 'tp' or 'sl' for a trigger the venue names as such, else null.
  String? get tpsl {
    final name = orderType.toLowerCase();
    if (name.startsWith('take profit')) return 'tp';
    if (name.startsWith('stop')) return 'sl';
    return null;
  }

  /// A trigger that fires a market order rather than resting a limit.
  bool get isMarketTrigger => orderType.toLowerCase().endsWith('market');

  factory HlOpenOrder.fromJson(Map<String, dynamic> json) => HlOpenOrder(
        coin: (json['coin'] as String?) ?? '',
        oid: _toInt(json['oid']) ?? 0,
        isBuy: json['side'] == 'B',
        limitPx: _toDouble(json['limitPx']) ?? 0,
        sz: _toDouble(json['sz']) ?? 0,
        origSz: _toDouble(json['origSz']) ?? 0,
        timestamp: _toInt(json['timestamp']) ?? 0,
        cloid: json['cloid'] as String?,
        reduceOnly: json['reduceOnly'] == true,
        orderType: (json['orderType'] as String?) ?? '',
        isTrigger: json['isTrigger'] == true,
        triggerPx:
            json['isTrigger'] == true ? _toDouble(json['triggerPx']) : null,
        tif: const {'Gtc', 'Alo', 'Ioc'}.contains(json['tif'])
            ? json['tif'] as String
            : 'Gtc',
        isPositionTpsl: json['isPositionTpsl'] == true,
      );
}

/// One fill from `userFills` (REST) or the `userFills` WS channel.
class HlFill {
  final String coin;
  final double px;
  final double sz;

  /// 'B' (buy) | 'A' (sell/ask).
  final String side;

  /// Epoch ms.
  final int time;
  final double closedPnl;
  final double fee;
  final String feeToken;
  final int oid;
  final String hash;

  /// Human direction label, e.g. 'Open Long', 'Close Short', 'Buy'.
  final String dir;
  final String? cloid;
  final String? tradeId;
  final double? builderFee;
  final double? startPosition;
  final bool liquidated;
  final bool accountingComplete;

  /// True when this fill took liquidity (a market order, a marketable
  /// limit, a triggered stop); false when a RESTING order was filled.
  /// Null on payloads without the field.
  final bool? crossed;

  const HlFill({
    required this.coin,
    required this.px,
    required this.sz,
    required this.side,
    required this.time,
    required this.closedPnl,
    required this.fee,
    required this.feeToken,
    required this.oid,
    required this.hash,
    required this.dir,
    required this.cloid,
    this.tradeId,
    this.builderFee,
    this.startPosition,
    this.liquidated = false,
    this.accountingComplete = false,
    this.crossed,
  });

  bool get isBuy => side == 'B';

  factory HlFill.fromJson(Map<String, dynamic> json) => HlFill(
        coin: (json['coin'] as String?) ?? '',
        px: _toDouble(json['px']) ?? 0,
        sz: _toDouble(json['sz']) ?? 0,
        side: (json['side'] as String?) ?? '',
        time: _toInt(json['time']) ?? 0,
        closedPnl: _toDouble(json['closedPnl']) ?? 0,
        fee: _toDouble(json['fee']) ?? 0,
        feeToken: (json['feeToken'] as String?) ?? '',
        oid: _toInt(json['oid']) ?? 0,
        hash: (json['hash'] as String?) ?? '',
        dir: (json['dir'] as String?) ?? '',
        cloid: json['cloid'] as String?,
        tradeId: json['tid']?.toString(),
        builderFee: _toDouble(json['builderFee']),
        startPosition: _toDouble(json['startPosition']),
        liquidated: json['liquidation'] != null,
        accountingComplete: ['startPosition', 'sz', 'closedPnl', 'fee']
            .every((key) => _toDouble(json[key])?.isFinite == true),
        crossed: json['crossed'] is bool ? json['crossed'] as bool : null,
      );
}

/// Combined account view: perp clearinghouse summary + positions + spot
/// balances. Built from `clearinghouseState` (+ optional
/// `spotClearinghouseState`).
class HlAccountSnapshot {
  /// Perp account equity (margin summary accountValue), USD.
  final double accountValue;

  /// Perp USDC available for withdrawal / new isolated margin.
  final double withdrawable;
  final double totalMarginUsed;

  /// Maintenance margin every cross position currently requires, USD
  /// (clearinghouseState `crossMaintenanceMarginUsed`). The liquidation
  /// estimate for a new cross order subtracts it from the equity.
  final double crossMaintenanceMarginUsed;
  final List<HlPerpPosition> positions;
  final List<HlSpotBalance> spotBalances;

  /// Builder (HIP-3) dexes where this account holds anything: equity,
  /// margin or a position. Resting orders on a builder dex need margin
  /// there, so these are the dexes whose orders must be read (the venue
  /// returns a builder dex's orders only when that dex is named).
  final Set<String> activeDexes;

  const HlAccountSnapshot({
    required this.accountValue,
    required this.withdrawable,
    required this.totalMarginUsed,
    this.crossMaintenanceMarginUsed = 0,
    required this.positions,
    required this.spotBalances,
    this.activeDexes = const {},
  });

  /// True when this (single-dex) snapshot holds equity, margin or a
  /// position.
  bool get hasActivity =>
      accountValue > 0 || totalMarginUsed > 0 || positions.isNotEmpty;

  static const empty = HlAccountSnapshot(
    accountValue: 0,
    withdrawable: 0,
    totalMarginUsed: 0,
    positions: [],
    spotBalances: [],
  );

  factory HlAccountSnapshot.fromJson({
    required Map<String, dynamic> perpState,
    Map<String, dynamic>? spotState,
  }) {
    final marginSummary = (perpState['marginSummary'] is Map<String, dynamic>)
        ? perpState['marginSummary'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final positions = <HlPerpPosition>[];
    for (final raw in (perpState['assetPositions'] as List?) ?? const []) {
      if (raw is! Map<String, dynamic>) continue;
      final pos = HlPerpPosition.fromJson(raw);
      if (pos.coin.isEmpty || pos.szi == 0) continue; // flat — not a position
      positions.add(pos);
    }
    final balances = <HlSpotBalance>[];
    for (final raw in (spotState?['balances'] as List?) ?? const []) {
      if (raw is! Map<String, dynamic>) continue;
      final bal = HlSpotBalance.fromJson(raw);
      if (bal.coin.isEmpty) continue;
      balances.add(bal);
    }
    return HlAccountSnapshot(
      accountValue: _toDouble(marginSummary['accountValue']) ?? 0,
      withdrawable: _toDouble(perpState['withdrawable']) ?? 0,
      totalMarginUsed: _toDouble(marginSummary['totalMarginUsed']) ?? 0,
      crossMaintenanceMarginUsed:
          _toDouble(perpState['crossMaintenanceMarginUsed']) ?? 0,
      positions: positions,
      spotBalances: balances,
    );
  }
}

/// One price level of the L2 book.
class HlL2Level {
  final double px;
  final double sz;

  /// Number of orders at this level.
  final int n;

  const HlL2Level({required this.px, required this.sz, required this.n});

  factory HlL2Level.fromJson(Map<String, dynamic> json) => HlL2Level(
        px: _toDouble(json['px']) ?? 0,
        sz: _toDouble(json['sz']) ?? 0,
        n: _toInt(json['n']) ?? 0,
      );
}

/// L2 book snapshot — same shape from REST `l2Book` and the WS `l2Book`
/// channel: {coin, time, levels: [[bids...], [asks...]]}. Bids and asks are
/// both sorted best-first by the exchange.
class HlL2Book {
  final String coin;
  final int time;
  final List<HlL2Level> bids;
  final List<HlL2Level> asks;

  const HlL2Book({
    required this.coin,
    required this.time,
    required this.bids,
    required this.asks,
  });

  double? get bestBid => bids.isEmpty ? null : bids.first.px;
  double? get bestAsk => asks.isEmpty ? null : asks.first.px;
  double? get midPx {
    final b = bestBid, a = bestAsk;
    if (b == null || a == null || b <= 0 || a <= 0) return null;
    return (b + a) / 2;
  }

  factory HlL2Book.fromJson(Map<String, dynamic> json) {
    final levels = (json['levels'] as List?) ?? const [];
    List<HlL2Level> side(int i) {
      if (i >= levels.length || levels[i] is! List) return const [];
      return (levels[i] as List)
          .whereType<Map<String, dynamic>>()
          .map(HlL2Level.fromJson)
          .toList();
    }

    return HlL2Book(
      coin: (json['coin'] as String?) ?? '',
      time: _toInt(json['time']) ?? 0,
      bids: side(0),
      asks: side(1),
    );
  }
}

// ─────────────────────────── parse helpers ────────────────────────────

double? _toDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

int? _toInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}
