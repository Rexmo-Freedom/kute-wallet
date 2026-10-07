import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:kute/providers/swap_orders_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/helpers/svg_class_styles.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// The mark the person's dollars wear: the tab chip, the USD account
/// hero, the dollar leg of a Move. One constant so the three never drift
/// apart. The file keeps the token's own name; what it draws is a plain
/// dollar disc, and the only word beside it is ever "USD".
const String kUsdMarkAsset = 'lib/assets/usdb-logo.svg';

/// The same for bitcoin: the purchase door on the Bitcoin screen and
/// the bitcoin leg of a Move wear this one mark, the way the dollar
/// balance wears [kUsdMarkAsset].
const String kBitcoinMarkAsset = 'lib/assets/bitcoin-icon.svg';

const _localAssets = <String, String>{
  'BTC': 'lib/assets/bitcoin-logo.png',
  'Lightning': 'lib/assets/Bitcoin_lightning_logo.png',
  'Spark': 'lib/assets/spark-logo.svg',
  'USDB': 'lib/assets/usdb-logo.svg',
  'Predictions': 'lib/assets/polymarket-logo.svg',
  'Trading': 'lib/assets/hyperliquid-logo.svg',
  'EUR': 'lib/assets/eur-icon.svg',
  // The dollar balance wears ONE mark everywhere (owner decision):
  // the shared [kUsdMarkAsset], never a second dollar disc of our own.
  'USD': kUsdMarkAsset,
  'GBP': 'lib/assets/gbp-icon.svg',
  'CHF': 'lib/assets/chf-icon.svg',
  'BRL': 'lib/assets/brl-icon.svg',
  'JPY': 'lib/assets/jpy-icon.svg',
  'CAD': 'lib/assets/cad-icon.svg',
  'AUD': 'lib/assets/aud-icon.svg',
  // Catalog coins a shipped asset serves better than a fetch. Most of
  // the catalog's big names (ETH, USDT, USDC, BNB, SOL, XRP, TRX, LTC,
  // POL) already resolve locally through [kTopCoins] just below, so
  // only the spellings that miss BOTH tables are listed here.
  //
  // Tether's zero-fee variant is the same brand, spelled two ways by
  // the catalog and by our own code.
  'USD₮0': 'lib/assets/usdt.svg',
  'USDT0': 'lib/assets/usdt.svg',
  // Wrapped BNB wears BNB's mark. The artwork host serves no wbnb.svg
  // (404, checked September 2026), so without this the row drew a
  // lettered disc.
  'WBNB': 'lib/assets/bnb.svg',
};

const _monochromeAssets = <String>{'Spark'};

/// USD-pegged tickers, for the artwork fallback. Deliberately a name
/// test: the catalogue adds dollars faster than a hand-kept list.
bool _isDollarTicker(String upper) {
  if (upper == 'DAI' || upper == 'PYUSD') return true;
  if (upper.startsWith('USD') || upper.endsWith('USD')) return true;
  return upper.startsWith('US\u20AE');
}

final assetIconUrlProvider = Provider.family<String?, String>((ref, code) {
  if (_localAssets.containsKey(code)) return _localAssets[code];
  final normalized = code.trim().toUpperCase() == 'USDC.E'
      ? 'USDC'
      : code.trim().toUpperCase();
  final local = kTopCoins.where((coin) => coin.code.toUpperCase() == normalized);
  if (local.isNotEmpty) return local.first.svgAsset;
  final catalog = ref.watch(orchestraSupportedRoutesProvider);
  final icons = catalog.assets
      .where((asset) => asset.asset.toUpperCase() == code.trim().toUpperCase())
      .map((asset) => asset.assetIconUrl)
      .whereType<String>()
      .toSet();
  final resolved =
      icons.length == 1 ? icons.first : orchestraAssetIconUrl(code);
  if (resolved != null) return resolved;
  // A dollar with no artwork anywhere wears the plain dollar disc rather
  // than a lettered one. It is not a brand mark and does not pretend to
  // be: it says the one true thing about the coin, and the ticker sits
  // under it. Anything that is not a dollar keeps the letter.
  return _isDollarTicker(normalized) ? kUsdMarkAsset : null;
});

class AssetIcon extends ConsumerWidget {
  final String assetCode;
  final double size;
  const AssetIcon({super.key, required this.assetCode, required this.size});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localUrl = ref.watch(assetIconUrlProvider(assetCode));

    if (localUrl != null) {
      if (localUrl.startsWith('http')) {
        return _NetworkIcon(url: localUrl, size: size, code: assetCode);
      }
      if (localUrl.endsWith('.svg')) {
        final isMono = _monochromeAssets.contains(assetCode);
        final tint = isMono ? context.colors.textPrimary : null;
        return SizedBox(
          width: size,
          height: size,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(size / 2),
            child: SvgPicture.asset(
              localUrl,
              width: size,
              height: size,
              colorFilter: tint != null
                  ? ColorFilter.mode(tint, BlendMode.srcIn)
                  : null,
            ),
          ),
        );
      }
      if (localUrl.endsWith('.png') || localUrl.endsWith('.jpg')) {
        return SizedBox(
          width: size,
          height: size,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(size / 2),
            // Decode at display size: the bundled logos are up to
            // 2000 px, 16 MB each as bitmaps on a low-memory phone.
            child: Image.asset(localUrl,
                width: size,
                height: size,
                cacheWidth:
                    (size * MediaQuery.devicePixelRatioOf(context)).round()),
          ),
        );
      }
    }

    return _FallbackIcon(code: assetCode, size: size);
  }
}

bool _isSvgUrl(String url) {
  return Uri.tryParse(url)?.path.toLowerCase().endsWith('.svg') ?? false;
}

class _NetworkIcon extends StatelessWidget {
  final String url;
  final double size;
  final String code;
  const _NetworkIcon(
      {required this.url, required this.size, required this.code});

  @override
  Widget build(BuildContext context) {
    if (_isSvgUrl(url)) {
      return SizedBox(
        width: size,
        height: size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(size / 2),
          child: SafeSvgNetwork(
            url: url,
            width: size,
            height: size,
            fallback: _FallbackIcon(code: code, size: size),
          ),
        ),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: CachedNetworkImage(
          imageUrl: url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          memCacheWidth:
              (size * MediaQuery.of(context).devicePixelRatio).round(),
          placeholder: (ctx, url) => SizedBox(width: size, height: size),
          errorWidget: (ctx, url, err) => _FallbackIcon(code: code, size: size),
        ),
      ),
    );
  }
}

class SafeSvgNetwork extends StatefulWidget {
  final String url;
  final double width;
  final double height;
  final Widget fallback;
  const SafeSvgNetwork({
    super.key,
    required this.url,
    required this.width,
    required this.height,
    required this.fallback,
  });

  @override
  State<SafeSvgNetwork> createState() => _SafeSvgNetworkState();
}

class _SafeSvgNetworkState extends State<SafeSvgNetwork> {
  /// Session-wide SVG body cache, shared by every SafeSvgNetwork.
  /// Picker rows repeat the same handful of chain/coin icon URLs many
  /// times over — without this each row (and each rebuild) refetched
  /// the same bytes. An empty-string value marks a KNOWN failure so a
  /// bad URL is fetched at most once per session (the widget renders
  /// its fallback instantly instead of re-hitting the network).
  static final Map<String, String> _cache = {};

  /// In-flight fetches, deduped by URL so N rows mounting together
  /// spawn one request.
  static final Map<String, Future<String>> _inflight = {};

  String? _svgData;
  bool _loading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant SafeSvgNetwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A list slot that flips to a different icon (filter / search
    // change in the pickers) reuses this State: restart for the new
    // URL instead of keeping the previous chain's mark, or a stale
    // failure, on screen.
    if (oldWidget.url != widget.url) {
      _svgData = null;
      _hasError = false;
      _loading = true;
      _start();
    }
  }

  void _start() {
    final cached = _cache[widget.url];
    if (cached != null) {
      // Synchronous hit — no loading frame, no network.
      _loading = false;
      if (cached.isEmpty) {
        _hasError = true;
      } else {
        _svgData = cached;
      }
      return;
    }
    _fetchSvg();
  }

  static Future<String> _fetchBody(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') {
      return '';
    }
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      // Decode the bytes ourselves: `response.body` falls back to
      // latin1 when the content-type carries no charset (image/svg+xml
      // never does), which mangles any non-ASCII glyph in the markup.
      final body = response.statusCode == 200
          ? utf8.decode(response.bodyBytes, allowMalformed: true)
          : '';
      if (body.trimLeft().startsWith('<') && body.contains('<svg')) {
        // The same two repairs the local marks needed. These files are
        // Illustrator exports that carry their colours in a <style>
        // block as CSS classes, which flutter_svg does not apply, so
        // every path fell back to black and the coin drew as a dark
        // blob. The crop frames go for the same reason they did there.
        return dropBoundingBoxClipPaths(inlineSvgClassStyles(body));
      }
      if (kDebugMode) {
        debugPrint('SafeSvgNetwork: $url -> HTTP ${response.statusCode} '
            '${response.headers['content-type'] ?? ''}');
      }
      return '';
    } catch (e) {
      if (kDebugMode) debugPrint('SafeSvgNetwork: $url -> $e');
      return '';
    }
  }

  Future<void> _fetchSvg() async {
    final url = widget.url;
    final future = _inflight.putIfAbsent(url, () async {
      final body = await _fetchBody(url);
      _cache[url] = body;
      _inflight.remove(url);
      return body;
    });
    final body = await future;
    // The widget may have moved on to another URL while this one was
    // in flight; that fetch owns the state now.
    if (!mounted || widget.url != url) return;
    setState(() {
      _loading = false;
      if (body.isEmpty) {
        _hasError = true;
      } else {
        _svgData = body;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return widget.fallback;
    if (_hasError || _svgData == null) return widget.fallback;
    return SvgPicture.string(
      _svgData!,
      width: widget.width,
      height: widget.height,
      // A body that fetched fine but flutter_svg cannot parse (vendor
      // features it does not support) must still degrade to the
      // caller's fallback instead of a blank box.
      errorBuilder: (ctx, error, stack) => widget.fallback,
    );
  }
}

class _FallbackIcon extends StatelessWidget {
  final String code;
  final double size;
  const _FallbackIcon({required this.code, required this.size});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final letter = code.isNotEmpty ? code[0].toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.surfaceLight,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          color: c.textSecondary,
          fontSize: size * 0.4,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
