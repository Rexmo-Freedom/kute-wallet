/// Network images on web, through the browser's own `<img>` element.
///
/// Flutter web (CanvasKit) reads an image's bytes with fetch()/XHR before it
/// can draw it, and that needs the host to send CORS headers. The hosts the
/// app's logos and pictures come from (Hyperliquid's coin images, CoinCap,
/// parqet, Polymarket's S3 bucket, the coin artwork host) send none, so on
/// web every one of those failed and the rows fell back to letter tiles.
/// An `<img>` element shows a cross-origin image (raster or SVG) without
/// CORS; Dart just cannot read its pixels.
///
/// So on web:
///   * [WebNetworkImage] draws a URL as an `<img>` platform view, with the
///     size, box fit, clip, placeholder and error widget of the call site.
///     One view factory is shared by every image; a view exists only once
///     the image has loaded (while it loads, and when it fails, the plain
///     Flutter placeholder or error widget is drawn instead), and a list
///     row scrolled off screen disposes its view as any widget would.
///   * [WebImageLoader] loads a URL into an off-screen `<img>` (onload /
///     onerror, no fetch) and remembers the outcome for the session, so the
///     logo probes ([HlIconAvailability] and friends) settle on web and a
///     recycled row knows at once whether its image exists.
///
/// The phones never use any of this: every call site asks `kIsWeb` first
/// and keeps its own native path.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';

import 'web_image_native.dart' if (dart.library.js_interop) 'web_image_web.dart'
    as impl;

/// What loading a URL into an `<img>` gave: its natural size, when the
/// browser knows one (an SVG with only a viewBox may report none).
@immutable
class WebImageLoad {
  const WebImageLoad({required this.width, required this.height});
  final int width;
  final int height;

  /// Width over height, or null when the browser reports no natural size.
  double? get aspect => width > 0 && height > 0 ? width / height : null;
}

/// Loads URLs into off-screen `<img>` elements (web only) and remembers
/// which loaded and which failed, for the session.
abstract final class WebImageLoader {
  static final Map<String, WebImageLoad> _loaded = {};
  static final Set<String> _failed = {};
  static final Map<String, Future<WebImageLoad?>> _inflight = {};

  /// The natural size of [url] when it already loaded this session.
  static WebImageLoad? loaded(String url) => _loaded[url];

  /// True when [url] already failed to load this session.
  static bool failed(String url) => _failed.contains(url);

  /// Loads [url] in an `<img>`: its natural size once it decoded, null when
  /// it failed (an error, a body that is not an image such as an HTML page,
  /// or no answer within [timeout]). One load per URL in flight; the
  /// outcome is kept for the session. Null at once off the web.
  static Future<WebImageLoad?> load(String url,
      {Duration timeout = const Duration(seconds: 10)}) {
    if (!kIsWeb) return Future.value(null);
    final done = _loaded[url];
    if (done != null) return Future.value(done);
    if (_failed.contains(url)) return Future.value(null);
    return _inflight.putIfAbsent(url, () async {
      try {
        final load = await impl.loadImage(url, timeout);
        if (load == null) {
          _failed.add(url);
        } else {
          _loaded[url] = load;
        }
        return load;
      } finally {
        _inflight.remove(url);
      }
    });
  }

  /// Loads [urls] in the background, [concurrency] at a time.
  static Future<void> prefetch(Iterable<String> urls,
      {int concurrency = 6}) async {
    final queue = urls.toList();
    var next = 0;
    Future<void> worker() async {
      while (next < queue.length) {
        await load(queue[next++]);
      }
    }

    await Future.wait([
      for (var i = 0; i < concurrency && i < queue.length; i++) worker(),
    ]);
  }

  @visibleForTesting
  static void debugReset() {
    _loaded.clear();
    _failed.clear();
    _inflight.clear();
  }
}

/// Below this widget, [WebNetworkImage] draws its error widget instead of an
/// `<img>`: a subtree that is captured to pixels (a share card's
/// RepaintBoundary.toImage) cannot hold a platform view, and its stand-in is
/// what the captured picture would show anyway.
class WebImagesOff extends InheritedWidget {
  const WebImagesOff({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WebImagesOff>() != null;

  @override
  bool updateShouldNotify(WebImagesOff oldWidget) => false;
}

/// A network image drawn by the browser's `<img>` element (web only; see the
/// library comment). [width] and [height] are the box it fills, [fit] is
/// applied as the element's object-fit. [placeholder] shows while it loads
/// (default: an empty box of that size) and [error] when it fails (default:
/// the placeholder).
class WebNetworkImage extends StatefulWidget {
  const WebNetworkImage({
    super.key,
    required this.url,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholder,
    this.error,
  });

  final String url;
  final double width;
  final double height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? placeholder;
  final Widget? error;

  @override
  State<WebNetworkImage> createState() => _WebNetworkImageState();
}

class _WebNetworkImageState extends State<WebNetworkImage> {
  bool? _ok;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant WebNetworkImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _start();
  }

  void _start() {
    final url = widget.url;
    if (WebImageLoader.loaded(url) != null) {
      _ok = true;
      return;
    }
    if (WebImageLoader.failed(url)) {
      _ok = false;
      return;
    }
    _ok = null;
    WebImageLoader.load(url).then((load) {
      if (!mounted || widget.url != url) return;
      setState(() => _ok = load != null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = widget.placeholder ??
        SizedBox(width: widget.width, height: widget.height);
    final error = widget.error ?? placeholder;
    if (!kIsWeb || WebImagesOff.of(context)) return error;
    final ok = _ok;
    if (ok == null) return placeholder;
    if (!ok) return error;
    Widget image = SizedBox(
      width: widget.width,
      height: widget.height,
      child: impl.imgView(widget.url, widget.fit),
    );
    final radius = widget.borderRadius;
    if (radius != null) {
      image = ClipRRect(borderRadius: radius, child: image);
    }
    return image;
  }
}
