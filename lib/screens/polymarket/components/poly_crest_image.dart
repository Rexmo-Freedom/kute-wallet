import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kute/helpers/polymarket_artwork.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/screens/polymarket/components/poly_category_icons.dart';
import 'package:kute/services/icon_cache/icon_disk_cache.dart' show IconCaches, runBounded;

/// The one widget every Polymarket image goes through: market and event
/// art, outcome and candidate images, team crests, flags, league logos.
///
/// Polymarket serves some of these as SVG, sometimes from a `.png` or an
/// extensionless URL, which raster widgets (`Image.network`,
/// `CachedNetworkImage`) draw as nothing. This one disk-caches the file and
/// decides from what was served: the SVG content type (the cache names the
/// file after it) or the bytes themselves (`<svg`), never the URL alone.
/// SVG goes to the vector renderer, anything else to the sized raster path.
/// When the image is missing or fails, it shows [fallback], or by default
/// the initials of [label] / the glyph of [category] — never an empty box.
class PolyCrestImage extends StatelessWidget {
  final String url;
  final double size;
  final double radius;
  final BoxFit fit;
  final Widget? fallback;

  /// Name behind the image (team, market, league), for the default
  /// fallback's initials.
  final String? label;

  /// Market category slug, for the default fallback's glyph.
  final String? category;
  final BaseCacheManager? cacheManager;

  const PolyCrestImage({
    super.key,
    required this.url,
    required this.size,
    required this.radius,
    this.fallback,
    this.label,
    this.category,
    this.fit = BoxFit.cover,
    this.cacheManager,
  });

  /// Render harnesses only: the cache every artwork without its own
  /// [cacheManager] reads from (local files, no network or database).
  @visibleForTesting
  static BaseCacheManager? debugCacheManager;

  static bool isSvgUrl(String url) =>
      Uri.tryParse(url)?.path.toLowerCase().endsWith('.svg') ?? false;

  @override
  Widget build(BuildContext context) {
    final normalized = polymarketArtworkUrl(url);
    final fb = fallback ??
        PolyArtworkFallback(size: size, label: label, category: category);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: normalized == null
          ? fb
          : _CachedArtwork(
              url: normalized,
              size: size,
              fit: fit,
              fallback: fb,
              cacheManager:
                  cacheManager ?? debugCacheManager ?? polyArtworkCacheManager,
            ),
    );
  }

  static final Set<String> _requested = {};

  /// Artwork resolved at once by [prefetch].
  static const int prefetchConcurrency = 6;

  /// Downloads (or reads from disk) and resolves [urls] in the background,
  /// [prefetchConcurrency] at a time, so the cards that show them draw
  /// the image on their first frame instead of an empty box. URLs already
  /// requested this session are skipped, so calling this whenever a list
  /// changes is cheap.
  static Future<void> prefetch(Iterable<String?> urls,
      {BaseCacheManager? cacheManager}) {
    if (!IconCaches.prefetchEnabled) return Future.value();
    final cm = cacheManager ?? debugCacheManager ?? polyArtworkCacheManager;
    final todo = <String>[];
    for (final raw in urls) {
      if (raw == null || raw.trim().isEmpty) continue;
      final u = polymarketArtworkUrl(raw);
      if (u != null && _requested.add(u)) todo.add(u);
    }
    return runBounded(todo, prefetchConcurrency,
        (u) => _CachedArtworkState._resolve(cm, u));
  }

  @visibleForTesting
  static void debugResetPrefetch() => _requested.clear();
}

/// The artwork the first [events] of a feed draw, best guess first: the
/// event image, its first outcomes' images and its teams' crests (the
/// card picks one of these). Feeds repeat crests, so repeats go.
List<String> polyFeedArtworkUrls(Iterable<PolymarketEvent> events,
    {int limit = 12}) {
  final out = <String>{};
  void add(String? u) {
    if (u != null && u.trim().isNotEmpty) out.add(u);
  }

  for (final e in events.take(limit)) {
    add(e.imageUrl);
    for (final o in e.outcomes.take(3)) {
      add(o.imageUrl);
    }
    for (final t in e.teams.take(2)) {
      add(t.logo);
    }
  }
  return out.toList();
}

/// The disk cache Polymarket artwork lives in: its own, so the feed's
/// many crests and portraits do not push each other (and every other
/// cached image) out of the shared default cache's 200 files. Images
/// rarely change; a month before one is checked again.
final BaseCacheManager polyArtworkCacheManager = CacheManager(Config(
  'polyArtwork',
  stalePeriod: const Duration(days: 30),
  maxNrOfCacheObjects: 1000,
));

/// The stand-in for a missing or broken Polymarket image: the initials of
/// [label] on a tint, or the category glyph when there is no label.
class PolyArtworkFallback extends StatelessWidget {
  final double size;
  final String? label;
  final String? category;

  const PolyArtworkFallback(
      {super.key, required this.size, this.label, this.category});

  static String initialsOf(String label) {
    const skip = {'the', 'fc', 'cf', 'sc', 'ec', 'vs', 'vs.', 'will'};
    final words = label
        .split(RegExp(r'[\s\-:/]+'))
        .where((w) => w.isNotEmpty && !skip.contains(w.toLowerCase()))
        .toList();
    if (words.isEmpty) return '';
    if (words.length == 1) {
      final w = words.first;
      return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
    }
    return words.take(2).map((w) => w[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = polyCategoryTint(category, scheme.onSurfaceVariant);
    final initials = label == null ? '' : initialsOf(label!.trim());
    return Container(
      width: size,
      height: size,
      color: tint.withValues(alpha: 0.16),
      alignment: Alignment.center,
      child: initials.isNotEmpty
          ? Text(
              initials,
              maxLines: 1,
              style: TextStyle(
                color: tint,
                fontSize: size * 0.36,
                fontWeight: FontWeight.w800,
                height: 1.0,
              ),
            )
          : Icon(polyCategoryGlyph(category), color: tint, size: size * 0.5),
    );
  }
}

class _CachedArtwork extends StatefulWidget {
  final String url;
  final double size;
  final BoxFit fit;
  final Widget fallback;
  final BaseCacheManager cacheManager;

  const _CachedArtwork({
    required this.url,
    required this.size,
    required this.fit,
    required this.fallback,
    required this.cacheManager,
  });

  @override
  State<_CachedArtwork> createState() => _CachedArtworkState();
}

typedef _Artwork = ({File file, Uint8List? svg});

class _CachedArtworkState extends State<_CachedArtwork> {
  /// URLs whose SVG flutter_svg cannot parse this session. The parser
  /// throws (an `hsl(285de…)` fill, a `transform="none"`) from inside the
  /// picture's isolate, past `errorBuilder`, so a document is proven to
  /// parse once before it is ever handed to [SvgPicture]; a failure is
  /// remembered so the next row shows the fallback without parsing again.
  static final Set<String> _unparseableSvg = {};

  /// Resolutions per cache, by URL: in flight, or done. A card that
  /// mounts after its artwork resolved (a scroll back, the prefetch got
  /// there first) draws it on its first frame, with no empty box and no
  /// second file read or parse. A failure is not kept, so the next mount
  /// tries again, as it always did.
  static final Expando<Map<String, Future<_Artwork>>> _pending = Expando();
  static final Expando<Map<String, _Artwork>> _resolved = Expando();

  late Future<_Artwork> _artwork;
  _Artwork? _initial;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(_CachedArtwork old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url || old.cacheManager != widget.cacheManager) {
      _start();
    }
  }

  void _start() {
    _initial = (_resolved[widget.cacheManager] ??= {})[widget.url];
    _artwork = _initial != null
        ? Future.value(_initial!)
        : _resolve(widget.cacheManager, widget.url);
  }

  static Future<_Artwork> _resolve(BaseCacheManager cm, String url) {
    final done = (_resolved[cm] ??= {})[url];
    if (done != null) return Future.value(done);
    final pending = _pending[cm] ??= {};
    return pending.putIfAbsent(url, () async {
      try {
        final art = await _load(cm, url);
        _resolved[cm]![url] = art;
        return art;
      } finally {
        pending.remove(url);
      }
    });
  }

  static Future<_Artwork> _load(BaseCacheManager cm, String url) async {
    if (_unparseableSvg.contains(url)) {
      throw const FormatException('Artwork SVG does not parse');
    }
    final file = await cm.getSingleFile(url);
    final length = await file.length();
    final prefix = BytesBuilder(copy: false);
    await for (final bytes in file.openRead(0, length.clamp(0, 4096))) {
      prefix.add(bytes);
    }
    final head = prefix.takeBytes();
    final text = utf8.decode(head, allowMalformed: true);
    // The cache names the file after the served content type
    // (image/svg+xml -> .svg); the bytes cover a mislabelled response.
    final servedSvg = file.path.toLowerCase().endsWith('.svg');
    final looksSvg = RegExp(r'<svg(?:\s|>)', caseSensitive: false).hasMatch(text);
    final looksRaster = _isRasterSignature(head);
    if (looksSvg || (servedSvg && !looksRaster)) {
      // Crests are small. Reject oversized SVG documents before retaining or
      // parsing their full XML; raster files stay on the sized FileImage path.
      if (length > 2 * 1024 * 1024) {
        throw const FormatException('Artwork exceeds SVG size limit');
      }
      final bytes = await file.readAsBytes();
      if (!await _svgParses(bytes)) {
        _unparseableSvg.add(url);
        throw const FormatException('Artwork SVG does not parse');
      }
      return (file: file, svg: bytes);
    }
    return (file: file, svg: null);
  }

  /// True when flutter_svg can parse [bytes]. Parsed here, where a throw
  /// is caught, rather than inside the picture, where it is not.
  static Future<bool> _svgParses(Uint8List bytes) async {
    try {
      final info = await vg.loadPicture(SvgBytesLoader(bytes), null);
      info.picture.dispose();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// PNG, JPEG, GIF or WebP magic bytes.
  static bool _isRasterSignature(List<int> b) {
    bool at(int i, List<int> sig) {
      if (b.length < i + sig.length) return false;
      for (var j = 0; j < sig.length; j++) {
        if (b[i + j] != sig[j]) return false;
      }
      return true;
    }

    return at(0, const [0x89, 0x50, 0x4E, 0x47]) || // PNG
        at(0, const [0xFF, 0xD8, 0xFF]) || // JPEG
        at(0, const [0x47, 0x49, 0x46]) || // GIF
        (at(0, const [0x52, 0x49, 0x46, 0x46]) &&
            at(8, const [0x57, 0x45, 0x42, 0x50])); // WebP
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Artwork>(
      future: _artwork,
      initialData: _initial,
      builder: (context, snap) {
        if (snap.hasError) return widget.fallback;
        // Until the future lands, only what is already resolved for THIS
        // url draws (the builder keeps the previous url's data meanwhile).
        final artwork = snap.connectionState == ConnectionState.done
            ? snap.data
            : _initial;
        if (artwork == null) {
          return SizedBox(width: widget.size, height: widget.size);
        }
        final data = artwork.svg;
        if (data != null) {
          return SvgPicture.memory(
            data,
            width: widget.size,
            height: widget.size,
            fit: widget.fit,
            placeholderBuilder: (_) =>
                SizedBox(width: widget.size, height: widget.size),
            errorBuilder: (_, __, ___) => widget.fallback,
          );
        }
        // FileImage keys Flutter's decoded-image cache by file path, so the
        // same provider crest in several rows is decoded only once.
        return Image.file(
          artwork.file,
          width: widget.size,
          height: widget.size,
          fit: widget.fit,
          cacheWidth:
              (widget.size * MediaQuery.devicePixelRatioOf(context)).round(),
          errorBuilder: (_, __, ___) => widget.fallback,
          gaplessPlayback: false,
        );
      },
    );
  }
}

/// Market artwork on completed-order receipts, with the product mark as fallback.
class PolyReceiptArtwork extends StatelessWidget {
  const PolyReceiptArtwork({super.key, this.url});
  final String? url;
  @override
  Widget build(BuildContext context) => PolyCrestImage(
      url: url ?? '',
      size: 44,
      radius: 12,
      fallback: SvgPicture.asset('lib/assets/polymarket-logo.svg',
          width: 44, height: 44));
}
