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

/// The routes that cover the whole page under them once they are up (the
/// detail sheets, KuteSheetPageRoute), web only.
///
/// Why: an `<img>` is a platform view, a DOM element over Flutter's canvas.
/// A route that is not opaque (the sheets are not: the page dims under them
/// as they rise) leaves the page under it painted, with all of its `<img>`
/// elements, and CanvasKit keeps at most eight canvases to draw what lies
/// over them; past that it folds the sheet's pictures into a canvas under
/// the later images. On a laptop the Investing list's logos (two dozen)
/// then showed through a market page (the Brent oil and silver marks over
/// its chart). So an image whose page is under a sheet that is fully up
/// draws its Flutter placeholder instead of its `<img>` (nobody sees the
/// page under a full sheet), and gets its `<img>` back the moment the
/// sheet starts to close.
abstract final class WebCovers {
  static final Set<Route<dynamic>> _up = <Route<dynamic>>{};

  /// Changes whenever a cover comes or goes.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  /// [route] is fully up (true) or closing or gone (false).
  static void set(Route<dynamic> route, bool up) {
    final changed = up ? _up.add(route) : _up.remove(route);
    if (changed) changes.value++;
  }

  /// Whether something [context] draws sits under a cover: a route that
  /// encloses it (at any level of nested navigators) is not the current
  /// one of its navigator, and a cover other than that route is up in
  /// that navigator.
  static bool covers(BuildContext context) {
    if (_up.isEmpty) return false;
    BuildContext? at = context;
    for (var depth = 0; at != null && depth < 8; depth++) {
      final route = ModalRoute.of(at);
      if (route == null) return false;
      final navigator = route.navigator;
      if (!route.isCurrent &&
          _up.any((c) => !identical(c, route) && c.navigator == navigator)) {
        return true;
      }
      at = navigator?.context;
    }
    return false;
  }

  @visibleForTesting
  static void debugReset() {
    _up.clear();
    changes.value = 0;
  }
}

/// The panels that stand over a page still in view (a laptop's centred
/// panel and side panel, a short sheet on a narrower window), web only.
///
/// Why: the same canvas limit as [WebCovers], but here the page under the
/// panel stays in view around it, so its images cannot all step aside.
/// Founder, 24 November 2026, of a bet slip opened from a Predictions card
/// on a laptop, a portrait and two team logos from the page drawn over the
/// slip's buttons and keypad: "this is wrong and broken". So an image
/// steps aside (its placeholder) only while its own rectangle is under a
/// panel's; the rest of the dimmed page keeps its pictures. An image
/// inside a panel yields only to a panel opened after its own.
abstract final class WebPanels {
  static final List<WebPanelCoverState> _order = <WebPanelCoverState>[];
  static final Map<WebPanelCoverState, Rect> _rects =
      <WebPanelCoverState, Rect>{};

  static bool get isEmpty => _rects.isEmpty;

  static void _set(WebPanelCoverState panel, Rect rect) {
    final was = _rects[panel];
    if (was != null &&
        (was.left - rect.left).abs() < 1 &&
        (was.top - rect.top).abs() < 1 &&
        (was.right - rect.right).abs() < 1 &&
        (was.bottom - rect.bottom).abs() < 1) {
      return;
    }
    if (was == null) _order.add(panel);
    _rects[panel] = rect;
    WebCovers.changes.value++;
  }

  static void _remove(WebPanelCoverState panel) {
    _order.remove(panel);
    if (_rects.remove(panel) != null) WebCovers.changes.value++;
  }

  /// Whether a panel stands over [image] (global coordinates). [inside]:
  /// the panel the image itself is drawn in, if any.
  static bool hides(Rect image, {WebPanelCoverState? inside}) {
    final from = inside == null ? 0 : _order.indexOf(inside) + 1;
    for (var i = from; i < _order.length; i++) {
      final rect = _rects[_order[i]];
      if (rect != null && rect.overlaps(image)) return true;
    }
    return false;
  }

  @visibleForTesting
  static void debugReset() {
    _order.clear();
    _rects.clear();
  }
}

/// Wraps the surface of a panel that stands over a page still in view
/// (see [WebPanels]). Off the web it is its [child] and nothing else.
class WebPanelCover extends StatefulWidget {
  const WebPanelCover({super.key, required this.child});

  final Widget child;

  @override
  State<WebPanelCover> createState() => WebPanelCoverState();
}

class WebPanelCoverState extends State<WebPanelCover> {
  Animation<double>? _animation;
  Rect? _rect;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!kIsWeb) return;
    final animation = ModalRoute.of(context)?.animation;
    if (!identical(animation, _animation)) {
      _animation?.removeListener(_measure);
      _animation = animation?..addListener(_measure);
    }
  }

  @override
  void dispose() {
    _animation?.removeListener(_measure);
    if (kIsWeb) WebPanels._remove(this);
    super.dispose();
  }

  /// Where the panel is now. While it comes in (a side panel slides, a
  /// sheet rises) the rectangle only grows, so nothing shows through the
  /// way; once it is up, it is the panel's own.
  void _measure() {
    if (!mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final now = box.localToGlobal(Offset.zero) & box.size;
    final moving = _animation != null &&
        _animation!.status != AnimationStatus.completed;
    final rect = moving && _rect != null ? _rect!.expandToInclude(now) : now;
    _rect = rect;
    WebPanels._set(this, rect);
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return widget.child;
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
        return false;
      },
      child: SizeChangedLayoutNotifier(child: widget.child),
    );
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
    if (kIsWeb) {
      WebCovers.changes.addListener(_coversChanged);
      // An image that appears while a panel is already up (a list that
      // loads under it).
      if (!WebPanels.isEmpty) _checkPanels();
    }
    _start();
  }

  @override
  void dispose() {
    WebCovers.changes.removeListener(_coversChanged);
    super.dispose();
  }

  void _coversChanged() {
    if (!mounted) return;
    setState(() {});
    _checkPanels();
  }

  /// Under a panel's rectangle (see [WebPanels]): measured after layout,
  /// as it needs this image's own place on the screen.
  bool _underPanel = false;

  void _checkPanels() {
    if (WebPanels.isEmpty) {
      if (_underPanel) setState(() => _underPanel = false);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      var under = false;
      final box = context.findRenderObject();
      if (!WebPanels.isEmpty &&
          box is RenderBox &&
          box.attached &&
          box.hasSize) {
        under = WebPanels.hides(
          box.localToGlobal(Offset.zero) & box.size,
          inside: context.findAncestorStateOfType<WebPanelCoverState>(),
        );
      }
      if (under != _underPanel) setState(() => _underPanel = under);
    });
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
    if (_underPanel || WebCovers.covers(context)) return placeholder;
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
