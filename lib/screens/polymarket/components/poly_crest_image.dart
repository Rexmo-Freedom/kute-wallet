import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kute/helpers/polymarket_artwork.dart';
import 'package:kute/screens/polymarket/components/poly_category_icons.dart';

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
              cacheManager: cacheManager ?? DefaultCacheManager(),
            ),
    );
  }
}

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

class _CachedArtworkState extends State<_CachedArtwork> {
  late Future<({File file, Uint8List? svg})> _artwork;

  @override
  void initState() {
    super.initState();
    _artwork = _load();
  }

  @override
  void didUpdateWidget(_CachedArtwork old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url || old.cacheManager != widget.cacheManager) {
      _artwork = _load();
    }
  }

  Future<({File file, Uint8List? svg})> _load() async {
    final file = await widget.cacheManager.getSingleFile(widget.url);
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
      return (file: file, svg: await file.readAsBytes());
    }
    return (file: file, svg: null);
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
    return FutureBuilder<({File file, Uint8List? svg})>(
      future: _artwork,
      builder: (context, snap) {
        if (snap.hasError) return widget.fallback;
        final artwork = snap.data;
        if (snap.connectionState != ConnectionState.done || artwork == null) {
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
