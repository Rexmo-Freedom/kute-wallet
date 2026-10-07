// lib/screens/hyperliquid/components/hl_coin_icon.dart
//
// The real coin/token logo for a Hyperliquid market — the leading icon on
// the Trading tab's browse cards (and anywhere else a market avatar is
// wanted). Renders the SVG logo from the backend-provided [iconUrl] when
// present, otherwise builds Hyperliquid's coin-CDN URL from the base coin:
//   https://app.hyperliquid.xyz/coins/<BASE>.svg
// where <BASE> strips any '<dex>:' builder-dex prefix and '/USDC' pair
// suffix (so 'unit:WHEAT' and 'PURR/USDC' both resolve to their base logo).
//
// The same CDN pattern covers the tokenized stock/commodity tokens; a miss
// (network error, timeout, 404, non-SVG body) falls back to the existing
// [HlLetterBadge] — the deterministic tinted letter avatar the tab shipped
// before, so a row is never blank.
//
// flutter_svg's SvgPicture has no error/timeout fallback callback for a
// network loader, so we fetch the bytes ourselves (with a timeout) and hand
// them to SvgPicture.memory. A small module-level cache (bytes on success,
// a failed-URL set on a miss) means each logo is fetched at most once per
// session and recycled cards / list scrolls don't re-hit the network.
//
// Many of the venue's logos are a RASTER wrapped in an SVG: a white rect
// filled with a <pattern> whose <image> is a base64 PNG. flutter_svg does
// not paint pattern fills, so those came out as a blank plate. The loader
// takes the first embedded image out of such a file and the icon draws it
// as an ordinary image; an SVG flutter_svg cannot parse at all is a miss
// and the next candidate is tried.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;

import 'package:kute/helpers/svg_class_styles.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart'
    show HlMarketDirectory;
import 'package:kute/theme/app_theme.dart';

import 'package:kute/screens/hyperliquid/components/hl_format.dart';

/// Base coin used to build the HL coin-logo CDN URL: strips any `dex:`
/// builder-dex prefix ('unit:WHEAT' → 'WHEAT') and '/…' pair suffix
/// ('PURR/USDC' → 'PURR').
String hlBaseCoin(String coin) {
  var base = coin.trim();
  final colon = base.indexOf(':');
  if (colon >= 0) base = base.substring(colon + 1);
  final slash = base.indexOf('/');
  if (slash >= 0) base = base.substring(0, slash);
  return base.trim();
}

/// The builder-perp symbol of the asset a spot token tracks, for tokens
/// Hyperliquid keeps no logo of their own for: the gold and silver
/// trackers and the index trackers. A token named like its perp (TSLA,
/// SPCX) needs no entry. Null when the token is not a tracker we know.
String? hlIconUnderlying(String coin) {
  final base = hlBaseCoin(coin).toUpperCase();
  const known = {
    'XAUT0': 'GOLD',
    'XAUT': 'GOLD',
    'PAXG': 'GOLD',
    'GLD': 'GOLD',
    'SLV': 'SILVER',
    'SPY': 'SP500',
    'USPYX': 'SP500',
    'QQQ': 'XYZ100',
  };
  final mapped = known[base];
  if (mapped != null) return mapped;
  // The app's own name for the symbol ("Tether Gold", "Silver").
  final name = (hlFriendlyName(base) ?? '').toLowerCase();
  if (RegExp(r'\bgold\b').hasMatch(name)) return 'GOLD';
  if (RegExp(r'\bsilver\b').hasMatch(name)) return 'SILVER';
  return null;
}

/// Above this a logo is not worth its decode: one spot token's SVG on the
/// venue's host is over a megabyte and would stall a list.
const int kHlIconMaxBytes = 300 * 1024;

/// An SVG that wraps a raster carries it as base64, which is a third
/// larger than the image and can be far larger than a vector logo. Up to
/// this much SVG text is read for those; the image taken out of it is
/// decoded at the icon's own pixel size.
const int kHlIconRasterSvgMaxBytes = 1536 * 1024;

/// Markup an SVG may carry around its one embedded image and still count
/// as a wrapped raster (the venue's are under 1 KB of rect and pattern).
const int kHlIconWrapperMarkupMax = 4096;

final RegExp _embeddedRaster = RegExp(
    r'''<image\b[^>]*?\bhref\s*=\s*["']data:image/(?:png|jpe?g|webp);base64,([^"']+)["']''',
    caseSensitive: false);

/// The first raster image embedded in an SVG document (`<image
/// href="data:image/png;base64,…">`, with or without the `xlink:` prefix;
/// PNG, JPEG or WebP), decoded, or null when the SVG embeds none or the
/// payload is not valid base64.
Uint8List? hlEmbeddedRaster(String svg) {
  final m = _embeddedRaster.firstMatch(svg);
  if (m == null) return null;
  try {
    final bytes =
        base64.decode(base64.normalize(m.group(1)!.replaceAll(RegExp(r'\s'), '')));
    return bytes.isEmpty ? null : bytes;
  } catch (_) {
    return null;
  }
}

/// Width divided by height of a PNG, read from its header, or null for
/// any other format (drawn as if square).
double? hlPngAspectRatio(Uint8List bytes) {
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (bytes.length < 24) return null;
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) return null;
  }
  int be(int at) =>
      (bytes[at] << 24) | (bytes[at + 1] << 16) | (bytes[at + 2] << 8) | bytes[at + 3];
  final w = be(16);
  final h = be(20);
  if (w <= 0 || h <= 0) return null;
  return w / h;
}

/// The same symbol on every OTHER builder dex ('mkts:US500' with dexes
/// xyz, km, mkts → ['xyz:US500', 'km:US500']), in the venue's dex order.
/// Hyperliquid keeps a logo per dex-qualified name and keeps it after a
/// dex's market is delisted, so a market whose own dex has no logo can
/// show one that only a dex with no live market of that symbol still
/// hosts. Empty for anything that is not a builder perp.
List<String> hlBuilderTwinWires(String wire, Iterable<String> dexes) {
  final colon = wire.indexOf(':');
  if (colon <= 0 || colon == wire.length - 1) return const [];
  final own = wire.substring(0, colon);
  final symbol = wire.substring(colon + 1);
  return [
    for (final dex in dexes)
      if (dex.isNotEmpty && dex != own) '$dex:$symbol',
  ];
}

/// Candidate logo URLs for a market, best first:
///   1. Hyperliquid's own coin CDN, keyed by the DEX-QUALIFIED wire name
///      (`xyz:TSLA`, `xyz:BRENTOIL`) for builder perps, the bare name for
///      the default dex (`BTC`), or the base token for spot (`PURR_spot`,
///      then `PURR`, then `PURR_USDC`). This
///      is exactly what the HL website uses — stripping the `dex:` prefix
///      (the old bug) hit the SPA's 200 HTML catch-all instead of a logo.
///   2. The logo of another market on the same asset ([siblingWires]):
///      for a builder perp the same symbol on another builder dex
///      (xyz:COPPER has none, flx:COPPER does); for a spot token the
///      builder perp of its symbol or of its underlying (XAUT0 and GLD
///      show xyz:GOLD, the TSLA token xyz:TSLA).
///   3. For stocks/indices HL doesn't host (e.g. SPY), a ticker-keyed stock
///      logo CDN (parqet) as a clean real-logo fallback.
/// Anything past these → the category glyph / letter badge.
List<String> hlCoinIconCandidates(
    String coin, String? wireCoin, String? category,
    {List<String> siblingWires = const []}) {
  final urls = <String>[];
  final wire = wireCoin?.trim();
  final isSpotWire = wire == null ||
      wire.isEmpty ||
      wire.startsWith('@') ||
      wire.contains('/');
  final hlName = isSpotWire ? hlBaseCoin(coin) : wire;
  // A spot pair ('@107', 'PURR/USDC'): Hyperliquid keeps a spot token's
  // logo at <TOKEN>_spot.svg, a few older ones at <TOKEN>_USDC.svg, and
  // the bare <TOKEN>.svg only when a perp of that name exists.
  final isSpotPair =
      wire != null && (wire.startsWith('@') || wire.contains('/'));
  if (hlName.isNotEmpty) {
    if (isSpotPair) {
      urls.add('https://app.hyperliquid.xyz/coins/${hlName}_spot.svg');
    }
    urls.add('https://app.hyperliquid.xyz/coins/$hlName.svg');
    if (isSpotPair) {
      urls.add('https://app.hyperliquid.xyz/coins/${hlName}_USDC.svg');
    }
  }
  for (final sibling in siblingWires) {
    urls.add('https://app.hyperliquid.xyz/coins/$sibling.svg');
  }
  if (category == 'stocks' || category == 'indices') {
    final ticker = hlBaseCoin(coin).toUpperCase();
    if (ticker.isNotEmpty) {
      urls.add('https://assets.parqet.com/logos/symbol/$ticker');
    }
  }
  return urls;
}

/// The other markets on the same asset whose logo [coin] may show, from
/// the markets loaded so far: see [hlCoinIconCandidates].
List<String> hlIconSiblingWires(String coin, String? wireCoin, String? category) {
  final wire = wireCoin?.trim();
  if (wire == null || wire.isEmpty) return const [];
  if (wire.contains(':')) {
    // The live twins of the same asset class first, then the symbol on
    // every other builder dex the venue lists.
    final live = HlMarketDirectory.builderSiblings(wire);
    return [
      ...live,
      ...hlBuilderTwinWires(wire, HlMarketDirectory.builderDexes)
          .where((w) => !live.contains(w)),
    ];
  }
  if (!(wire.startsWith('@') || wire.contains('/'))) return const [];
  // A spot token: the builder perp of its own symbol (same asset class,
  // so the crypto STX never shows a stock's logo), then of its underlying.
  final base = hlBaseCoin(coin);
  final underlying = hlIconUnderlying(coin);
  // A Unit-bridged token (UZEC) has no logo of its own: the asset it
  // holds does, under the perp's name (ZEC).
  final held = HlMarketDirectory.byWire(wire)?.unitAssetName != null &&
          base.length > 1
      ? base.substring(1)
      : null;
  return [
    if (held != null) held,
    ...HlMarketDirectory.builderWiresFor(base, category: category),
    if (underlying != null) ...HlMarketDirectory.builderWiresFor(underlying),
  ];
}

/// A loaded logo: the SVG document itself, or the raster taken out of an
/// SVG that only wraps one. [aspect] is its width over height when known.
class HlIconArt {
  const HlIconArt({required this.bytes, required this.raster, this.aspect});
  final Uint8List bytes;
  final bool raster;
  final double? aspect;
}

/// What the icon draws for a downloaded SVG body, or null when it is not
/// a logo it can draw: too large, or neither a vector under
/// [kHlIconMaxBytes] nor a wrapped raster under
/// [kHlIconRasterSvgMaxBytes]. Vector logos get the two repairs
/// flutter_svg needs.
HlIconArt? hlIconArtFromSvg(Uint8List body) {
  if (body.isEmpty || body.length > kHlIconRasterSvgMaxBytes) return null;
  final text = utf8.decode(body, allowMalformed: true);
  // Only a file that is nothing but its image: a vector logo that also
  // embeds a small texture stays a vector.
  final embedded = _embeddedRaster.firstMatch(text);
  final wrapper = embedded != null &&
      text.length - embedded.group(1)!.length <= kHlIconWrapperMarkupMax;
  final raster = wrapper ? hlEmbeddedRaster(text) : null;
  if (raster != null) {
    return HlIconArt(
        bytes: raster, raster: true, aspect: hlPngAspectRatio(raster));
  }
  if (body.length > kHlIconMaxBytes) return null;
  // Two repairs, once, before the bytes are cached. Logos styled
  // through CSS classes (Zcash among them) lose every fill in
  // flutter_svg and arrive as a black silhouette. Logos wrapped
  // in an exporter's crop frame lose most of the mark, because
  // that frame carries a transform flutter_svg does not apply
  // (Meta came through as one arc of its loop).
  final repaired = Uint8List.fromList(
      utf8.encode(dropBoundingBoxClipPaths(inlineSvgClassStyles(text))));
  return HlIconArt(
      bytes: repaired, raster: false, aspect: svgAspectRatio(repaired));
}

/// True when flutter_svg can parse [bytes]. A document it cannot parse
/// would throw inside the picture at paint time, with no way back to the
/// next candidate.
Future<bool> _svgParses(Uint8List bytes) async {
  try {
    final info = await vg.loadPicture(SvgBytesLoader(bytes), null);
    info.picture.dispose();
    return true;
  } catch (_) {
    return false;
  }
}

// Module-level cache — survives card recycling / list scrolls.
final Map<String, HlIconArt> _hlSvgCache = {};
final Set<String> _hlSvgFailed = {};
final Map<String, Future<HlIconArt?>> _hlSvgInflight = {};

/// True when [bytes] is an actual SVG document, not the HL SPA's HTML
/// catch-all (a missing-icon path returns 200 text/html, which would
/// otherwise cache + fail to render).
bool _looksLikeSvg(String contentType, Uint8List bytes) {
  if (contentType.contains('svg')) return true;
  if (contentType.contains('html')) return false;
  final head = String.fromCharCodes(bytes.take(256)).trimLeft().toLowerCase();
  return head.startsWith('<svg') ||
      (head.startsWith('<?xml') && head.contains('<svg'));
}

/// Width divided by height of an SVG's own canvas, read from its viewBox
/// (or its width and height attributes), or null when neither is present.
///
/// It decides how a logo fills its box. The prediction cards cover, so
/// their crests reach every edge, and a Hyperliquid mark that is square
/// should look exactly the same size beside one. A mark that is NOT
/// square cannot cover without being cropped to a fragment, which is how
/// Meta came through as a single arc, so those are contained instead.
double? svgAspectRatio(Uint8List bytes) {
  final head = utf8.decode(bytes.take(2048).toList(), allowMalformed: true);
  final viewBox = RegExp(r'viewBox\s*=\s*"([^"]+)"', caseSensitive: false)
      .firstMatch(head);
  if (viewBox != null) {
    final parts = viewBox
        .group(1)!
        .trim()
        .split(RegExp(r'[\s,]+'))
        .map(double.tryParse)
        .toList();
    if (parts.length == 4 &&
        parts[2] != null &&
        parts[3] != null &&
        parts[2]! > 0 &&
        parts[3]! > 0) {
      return parts[2]! / parts[3]!;
    }
  }
  double? attr(String name) {
    final m = RegExp('$name' r'\s*=\s*"([0-9.]+)', caseSensitive: false)
        .firstMatch(head);
    return m == null ? null : double.tryParse(m.group(1)!);
  }

  final w = attr('width');
  final h = attr('height');
  if (w != null && h != null && w > 0 && h > 0) return w / h;
  return null;
}

Future<HlIconArt?> _loadHlSvg(String url) {
  final cached = _hlSvgCache[url];
  if (cached != null) return Future.value(cached);
  if (_hlSvgFailed.contains(url)) return Future.value(null);
  return _hlSvgInflight.putIfAbsent(url, () async {
    try {
      final resp =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      final ct = (resp.headers['content-type'] ?? '').toLowerCase();
      // A missing logo answers 200 with the web app's HTML shell, not a
      // 404: only a real SVG of a sane size counts. A miss is remembered
      // for the session and the next candidate is tried.
      if (resp.statusCode == 200 && _looksLikeSvg(ct, resp.bodyBytes)) {
        final art = hlIconArtFromSvg(resp.bodyBytes);
        if (art != null && (art.raster || await _svgParses(art.bytes))) {
          _hlSvgCache[url] = art;
          return art;
        }
      }
      _hlSvgFailed.add(url);
      return null;
    } catch (_) {
      _hlSvgFailed.add(url);
      return null;
    } finally {
      _hlSvgInflight.remove(url);
    }
  });
}

/// Try each candidate URL in order; first that yields a real logo wins.
Future<HlIconArt?> _loadFirstSvg(List<String> urls) async {
  for (final u in urls) {
    final art = await _loadHlSvg(u);
    if (art != null) return art;
  }
  return null;
}

/// A tasteful fallback glyph for a market that has no CDN logo. Hyperliquid's
/// coin CDN only ships logos for the major crypto perps, so most builder
/// (HIP-3) markets — oil, wheat, tokenized stocks/indices — would otherwise
/// show a bare letter. We instead pick a category / symbol glyph so a WHEAT
/// or BRENTOIL row reads at a glance. Returns null → caller uses the letter
/// badge (right for obscure crypto with no logo). Matched on the coin symbol
/// first (catches oil/gold/wheat regardless of category), then [category].
({IconData icon, Color color})? hlFallbackGlyph(String coin, String? category) {
  final u = hlBaseCoin(coin).toUpperCase();
  const amber = Color(0xFFD9A400);
  const slate = Color(0xFF64748B);
  const blue = Color(0xFF3B82F6);
  const teal = Color(0xFF0EA57C);
  const green = Color(0xFF16A34A);

  bool has(List<String> ss) => ss.any(u.contains);
  // ── Commodities by symbol ──
  if (has(['OIL', 'CRUDE', 'WTI', 'BRENT', 'GAS', 'NATGAS'])) {
    return (icon: Icons.local_gas_station_rounded, color: slate);
  }
  if (has(['GOLD', 'XAU', 'XAUT', 'PAXG']) || u == 'GLD') {
    return (icon: Icons.workspace_premium_rounded, color: amber);
  }
  if (has(['SILVER', 'XAG']) || u == 'SLV') {
    return (icon: Icons.workspace_premium_outlined, color: slate);
  }
  if (has(['WHEAT', 'CORN', 'SOY', 'GRAIN', 'COFFEE', 'SUGAR', 'COCOA'])) {
    return (icon: Icons.grass_rounded, color: green);
  }
  // ── By category ──
  switch (category) {
    case 'commodities':
      return (icon: Icons.inventory_2_rounded, color: amber);
    case 'indices':
      return (icon: Icons.query_stats_rounded, color: blue);
    case 'stocks':
      return (icon: Icons.apartment_rounded, color: teal);
    case 'fx':
      return (icon: Icons.currency_exchange_rounded, color: green);
    case 'rates':
      return (icon: Icons.percent_rounded, color: blue);
    case 'preipo':
      return (icon: Icons.rocket_launch_rounded, color: blue);
  }
  return null; // crypto / unknown → letter badge
}

/// Coin logo for a Hyperliquid market, on the same rounded square
/// plate the prediction cards use. Shows a fallback (category
/// glyph or letter badge) while the SVG loads, swaps to the logo on
/// success, and keeps the fallback on any miss. Most builder-market tokens
/// have no CDN logo, so the category glyph is what users usually see.
class HlCoinIcon extends StatefulWidget {
  /// Display symbol (perp name / spot base token) — drives the fallback
  /// and the CDN URL.
  final String coin;

  /// Dex-qualified wire name (`xyz:TSLA` / `BTC` / `@142`). Needed to build
  /// the CORRECT HL coin-CDN URL — the logo lives under the wire name, not
  /// the stripped base.
  final String? wireCoin;

  /// Optional explicit logo URL override; used verbatim when set.
  final String? iconUrl;

  /// Market category ('commodities'|'indices'|'stocks'|'fx'|'preipo'|…) —
  /// picks the fallback glyph when there's no logo.
  final String? category;

  final double size;

  const HlCoinIcon({
    super.key,
    required this.coin,
    this.wireCoin,
    this.iconUrl,
    this.category,
    this.size = 44,
  });

  @override
  State<HlCoinIcon> createState() => _HlCoinIconState();
}

class _HlCoinIconState extends State<HlCoinIcon> {
  // The candidate list for the current market (identity + load coordination).
  List<String> _urls = const [];
  HlIconArt? _art;

  /// The builder-dex list the candidates were built from. A market still
  /// on its fallback resolves again when the venue's list has grown (it
  /// lands after the cached markets on a cold start).
  int _dexEpoch = 0;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant HlCoinIcon old) {
    super.didUpdateWidget(old);
    if (old.coin != widget.coin ||
        old.wireCoin != widget.wireCoin ||
        old.iconUrl != widget.iconUrl ||
        old.category != widget.category ||
        (_art == null && _dexEpoch != HlMarketDirectory.dexEpoch)) {
      _resolve();
    }
  }

  void _resolve() {
    final override = widget.iconUrl?.trim();
    // The explicit [iconUrl] is a PREFERRED candidate, not the only one — a
    // stale/bad override falls through to the CDN candidates (and then the
    // glyph/letter), so a row is never blank. Deduped so we never fetch the
    // same URL twice.
    final wire = widget.wireCoin;
    _dexEpoch = HlMarketDirectory.dexEpoch;
    final candidates = hlCoinIconCandidates(
        widget.coin, wire, widget.category,
        siblingWires: hlIconSiblingWires(
            widget.coin, wire, widget.category));
    _urls = [
      if (override != null && override.isNotEmpty) override,
      ...candidates.where((u) => u != override),
    ];
    _art = null;
    if (_urls.isEmpty) return;
    // Serve synchronously from cache when the winning candidate is already
    // loaded (no letter-fallback flicker). Scan in priority order, skipping
    // candidates known to have failed: the first LIVE candidate that's cached
    // is exactly what a fresh async load would resolve to. This fixes a fresh
    // instance (e.g. the detail-sheet header) showing the letter badge while a
    // list row already rendered the real logo — the winning logo is often a
    // LATER candidate (HL doesn't host stock/index logos, so the parqet CDN
    // wins), which the old "first candidate only" check never served.
    for (final u in _urls) {
      if (_hlSvgFailed.contains(u)) continue;
      final cached = _hlSvgCache[u];
      if (cached != null) {
        _art = cached;
        return;
      }
      // First not-yet-resolved candidate has priority — let the async load
      // decide rather than jumping to a lower-priority cached logo.
      break;
    }
    final urls = _urls;
    _loadFirstSvg(urls).then((art) {
      if (!mounted || !identical(urls, _urls) || art == null) return;
      setState(() => _art = art);
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final art = _art;
    if (art != null) {
      final c = context.colors;
      // A square mark covers, so it reaches every edge and reads at
      // the same size as a prediction crest beside it. A mark that
      // is not square is contained, because covering one crops it
      // to a fragment.
      final aspect = art.aspect;
      final fit = art.raster
          ? (aspect != null && (aspect - 1).abs() > 0.2
              ? BoxFit.contain
              : BoxFit.cover)
          : (aspect == null || (aspect - 1).abs() > 0.2
              ? BoxFit.contain
              : BoxFit.cover);
      return Container(
        width: size.w,
        height: size.w,
        // A rounded square plate, the same one the prediction crests
        // sit on. It is a fill, not a stroke: nothing is drawn around
        // the logo. Without it a mark whose own artwork is a circle,
        // which most coin logos are, read as a circle in a list of
        // squares.
        decoration: BoxDecoration(
          color: c.surfaceLight,
          borderRadius: BorderRadius.circular(size.w * 0.25),
        ),
        clipBehavior: Clip.antiAlias,
        // The logo alone, with nothing drawn behind or around it. A
        // filled plate under it read as a border, worst on the marks
        // that already carry their own square background.
        //
        // Contain, not cover: these marks come from the venue and are
        // not all square, and a wide one under cover was scaled until
        // it filled the box and then cropped, which left a fragment of
        // the logo. The rounded clip stays, so a mark that does fill
        // its box keeps the same silhouette as every other row.
        child: art.raster
            // The raster an SVG only wrapped, decoded at the icon's own
            // pixel size (the originals are photo-sized).
            ? Image.memory(
                art.bytes,
                fit: fit,
                cacheWidth:
                    (size.w * MediaQuery.devicePixelRatioOf(context)).ceil(),
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => _fallback(context),
              )
            : SvgPicture.memory(
                art.bytes,
                fit: fit,
                placeholderBuilder: (_) => _fallback(context),
              ),
      );
    }
    // Loading (fetch in flight) or a definitive miss → the fallback.
    return _fallback(context);
  }

  /// Category/symbol glyph when we have one (oil, gold, wheat, index,
  /// stock…), otherwise the deterministic tinted letter badge.
  Widget _fallback(BuildContext context) {
    final glyph = hlFallbackGlyph(widget.coin, widget.category);
    if (glyph == null) {
      return HlLetterBadge(coin: widget.coin, size: widget.size);
    }
    final size = widget.size;
    return Container(
      width: size.w,
      height: size.w,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size.w * 0.25),
        color: glyph.color.withValues(alpha: 0.14),
      ),
      alignment: Alignment.center,
      child: Icon(glyph.icon, color: glyph.color, size: (size * 0.5).sp),
    );
  }
}
