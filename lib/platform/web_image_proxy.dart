/// Web only: pictures from hosts that send no CORS header, read through the
/// Kute backend's image routes so the page can draw them in its own canvas
/// (no `<img>` element, no platform view: on Safari each of those cost a
/// full-screen WebGL canvas).
///
/// The routes (public, `Access-Control-Allow-Origin: *`, long cache, 404
/// when the upstream has no such picture):
///   * `{BACKEND}/api/v1/img/pm/<file>` for
///     `https://polymarket-upload.s3.us-east-2.amazonaws.com/<file>`;
///   * `{BACKEND}/api/v1/img/hl/<FILE>.svg` for
///     `https://app.hyperliquid.xyz/coins/<FILE>.svg`.
/// No other host is covered: those pictures keep the web's rule (shown
/// only on an opened market's own screen).
///
/// Cheap by construction: a picture is asked for only when a widget that
/// shows it is built (a list builds its visible rows), at most
/// [WebImageProxy.parallel] at a time, its bytes kept in a cache bounded
/// by [WebImageProxy.cacheBytes], and a missing picture (404 or any
/// failure) remembered for the session so it is never asked again. The
/// phones never use this file (they load pictures directly).
library;

import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:kute/services/http/shared_http_client.dart';

const String _pmHost = 'polymarket-upload.s3.us-east-2.amazonaws.com';
const String _hlHost = 'app.hyperliquid.xyz';

abstract final class WebImageProxy {
  /// Requests at once.
  static const int parallel = 4;

  /// The most picture bytes kept (decoded pictures live in Flutter's own
  /// bounded image cache, decoded at their display size).
  static const int cacheBytes = 8 * 1024 * 1024;

  /// The backend's origin (`.env` BACKEND); `WEB_IMG_PROXY_BASE` overrides
  /// it (a local stub while the routes are not deployed). Null when
  /// neither is set.
  @visibleForTesting
  static String? Function() baseOverride = _base;

  static String? _base() {
    try {
      final raw = (dotenv.env['WEB_IMG_PROXY_BASE'] ?? dotenv.env['BACKEND'])
              ?.trim() ??
          '';
      if (raw.isEmpty) return null;
      return raw.replaceFirst(RegExp(r'/+$'), '');
    } catch (_) {
      return null;
    }
  }

  /// The route serving [url], or null when no route covers its host.
  static String? proxied(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.scheme != 'https') return null;
    final base = baseOverride();
    if (base == null) return null;
    // The path as the upstream has it (already percent-encoded).
    final path = uri.path;
    if (uri.host == _pmHost && path.length > 1) {
      return '$base/api/v1/img/pm$path';
    }
    if (uri.host == _hlHost &&
        path.startsWith('/coins/') &&
        path.toLowerCase().endsWith('.svg') &&
        path.length > '/coins/.svg'.length) {
      return '$base/api/v1/img/hl/${path.substring('/coins/'.length)}';
    }
    return null;
  }

  /// Whether the web can draw [url] through a route, as far as this
  /// session knows: covered and not already found missing.
  static bool drawable(String? url) =>
      (kIsWeb || debugWeb) &&
      url != null &&
      proxied(url) != null &&
      !_missing.contains(url);

  /// Tests: [drawable] off the web.
  @visibleForTesting
  static bool debugWeb = false;

  /// Whether [url] was found missing this session.
  static bool missing(String url) => _missing.contains(url);

  static final Set<String> _missing = {};
  static final LinkedHashMap<String, Uint8List> _bytes = LinkedHashMap();
  static int _held = 0;
  static final Map<String, Future<Uint8List?>> _inflight = {};
  static int _active = 0;
  static final List<Completer<void>> _queue = [];

  /// Reads the bytes behind [url] through its route. Null when no route
  /// covers it or it is missing (remembered).
  @visibleForTesting
  static Future<Uint8List?> Function(String proxiedUrl) fetch = _fetch;

  static Future<Uint8List?> _fetch(String proxiedUrl) async {
    final r = await SharedHttpClient.get(Uri.parse(proxiedUrl),
        kind: HttpCallKind.backgroundRead,
        timeout: const Duration(seconds: 10));
    return r.statusCode == 200 && r.bodyBytes.isNotEmpty ? r.bodyBytes : null;
  }

  /// The bytes of [url] already held, at once; null when not held.
  static Uint8List? held(String url) {
    final b = _bytes.remove(url);
    if (b != null) _bytes[url] = b;
    return b;
  }

  static Future<Uint8List?> load(String url) {
    final done = held(url);
    if (done != null) return Future.value(done);
    if (_missing.contains(url)) return Future.value(null);
    final route = proxied(url);
    if (route == null) return Future.value(null);
    return _inflight.putIfAbsent(url, () async {
      try {
        if (_active >= parallel) {
          final turn = Completer<void>();
          _queue.add(turn);
          await turn.future;
        }
        _active++;
        Uint8List? body;
        try {
          body = await fetch(route);
        } catch (_) {
          body = null;
        } finally {
          _active--;
          if (_queue.isNotEmpty) _queue.removeAt(0).complete();
        }
        if (body == null) {
          _missing.add(url);
          return null;
        }
        _keep(url, body);
        return body;
      } finally {
        _inflight.remove(url);
      }
    });
  }

  static void _keep(String url, Uint8List body) {
    if (body.length > cacheBytes) return;
    _bytes[url] = body;
    _held += body.length;
    while (_held > cacheBytes && _bytes.isNotEmpty) {
      final first = _bytes.keys.first;
      _held -= _bytes.remove(first)!.length;
    }
  }

  @visibleForTesting
  static void debugReset() {
    _missing.clear();
    _bytes.clear();
    _held = 0;
    _inflight.clear();
    _active = 0;
    _queue.clear();
    fetch = _fetch;
    baseOverride = _base;
    debugWeb = false;
  }
}

/// Whether [bytes] are an SVG document.
bool webImageIsSvg(Uint8List bytes) {
  final n = bytes.length < 256 ? bytes.length : 256;
  final head = String.fromCharCodes(bytes.sublist(0, n)).trimLeft().toLowerCase();
  return head.startsWith('<svg') ||
      (head.startsWith('<?xml') && head.contains('<svg'));
}

/// A picture read through [WebImageProxy] and drawn in the canvas at
/// [size], decoded at that size (device pixel ratio aware). [placeholder]
/// while it loads, [error] when it is missing.
class WebProxiedPicture extends StatefulWidget {
  const WebProxiedPicture({
    super.key,
    required this.url,
    required this.size,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.error,
  });

  final String url;
  final double size;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? error;

  @override
  State<WebProxiedPicture> createState() => _WebProxiedPictureState();
}

class _WebProxiedPictureState extends State<WebProxiedPicture> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant WebProxiedPicture old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _start();
  }

  void _start() {
    final url = widget.url;
    _bytes = WebImageProxy.held(url);
    _failed = WebImageProxy.missing(url);
    if (_bytes != null || _failed) return;
    WebImageProxy.load(url).then((b) {
      if (!mounted || widget.url != url) return;
      setState(() {
        _bytes = b;
        _failed = b == null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final box = SizedBox(width: widget.size, height: widget.size);
    if (_failed) return widget.error ?? box;
    final bytes = _bytes;
    if (bytes == null) return widget.placeholder ?? box;
    final px = (widget.size * MediaQuery.devicePixelRatioOf(context)).ceil();
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: webImageIsSvg(bytes)
          ? SvgPicture.memory(bytes,
              fit: widget.fit,
              placeholderBuilder: (_) => widget.placeholder ?? box)
          : Image.memory(bytes,
              fit: widget.fit,
              cacheWidth: px,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => widget.error ?? box),
    );
  }
}
