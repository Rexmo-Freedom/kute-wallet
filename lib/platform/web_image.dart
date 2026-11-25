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

  /// Tests: [url] loaded, [width] by [height].
  @visibleForTesting
  static void debugSeedLoaded(String url, {int width = 64, int height = 64}) {
    _failed.remove(url);
    _loaded[url] = WebImageLoad(width: width, height: height);
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

  /// Under a cover ([WebCovers]) at the last check: a cover change
  /// rebuilds only the images whose answer it changed.
  bool _covered = false;

  /// Holds one of [WebImageViews]' live views.
  bool _slot = false;

  /// Gave its view to an image on screen; waits for one of its own.
  bool _parked = false;

  /// Whether this image is laid out inside the window.
  bool _onScreen() {
    if (!mounted) return false;
    // A page kept mounted but not shown (another pill of an IndexedStack,
    // a route under the current one) has its tickers off.
    if (!TickerMode.of(context)) return false;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    final view = View.maybeOf(context);
    if (view == null) return false;
    final window = Offset.zero & (view.physicalSize / view.devicePixelRatio);
    return window.overlaps(box.localToGlobal(Offset.zero) & box.size);
  }

  @override
  void initState() {
    super.initState();
    if (_web) {
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
    WebImageViews._release(this);
    super.dispose();
  }

  /// A cover or a panel came, went or moved. Hundreds of images listen:
  /// each one rebuilds only when its own answer changes.
  void _coversChanged() {
    if (!mounted) return;
    final covered = WebCovers.covers(context);
    if (covered != _covered) setState(() => _covered = covered);
    _checkPanels();
  }

  /// Under a panel's rectangle (see [WebPanels]): measured after layout,
  /// as it needs this image's own place on the screen.
  bool _underPanel = false;
  bool _panelCheckPending = false;

  void _checkPanels() {
    if (WebPanels.isEmpty) {
      if (_underPanel) setState(() => _underPanel = false);
      return;
    }
    // One measure per frame, however many changes the frame brought (a
    // panel sliding in moves its rectangle every frame).
    if (_panelCheckPending) return;
    _panelCheckPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _panelCheckPending = false;
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

  /// A slot came free for this image ([WebImageViews]).
  void _granted() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = widget.placeholder ??
        SizedBox(width: widget.width, height: widget.height);
    final error = widget.error ?? placeholder;
    if (!_web || WebImagesOff.of(context)) return error;
    final ok = _ok;
    if (ok == null) return placeholder;
    if (!ok) return error;
    _covered = WebCovers.covers(context);
    if (_underPanel || _covered) {
      WebImageViews._release(this);
      return placeholder;
    }
    // Past the page's cap of live views: the stand-in (the row's letter
    // tile) until a view comes free.
    if (!WebImageViews._claim(this)) return error;
    return SizedBox(
      key: const ValueKey('web-network-img'),
      width: widget.width,
      height: widget.height,
      // The corners are the element's own (CSS border-radius), not a
      // Flutter clip: a clip around a platform view is a clipping element
      // the engine restyles on every frame, for every image.
      child: impl.imgView(widget.url, widget.fit, widget.borderRadius),
    );
  }
}

/// Whether the `<img>` path is taken: the web, or a test that asks for it.
bool get _web => kIsWeb || WebImageViews.debugForceWeb;

/// The live `<img>` views, web only, at most [cap] at once.
///
/// Why (founder, 25 November 2026, the Investing list on a laptop in six
/// columns: "extreme lag"): every `<img>` is a platform view, a DOM
/// element the engine positions, clips and composites over its canvas,
/// and a page that keeps hundreds of them slows every frame. A lazy list
/// builds only the rows near the viewport, so its views follow the
/// scroll; the cap bounds what is left (a very tall, very wide window, a
/// list that builds more than it shows). Past it an image draws its
/// stand-in (the row's letter tile) and waits; after each frame an image
/// waiting on screen takes a free view, or the view of an image built
/// off screen (a row in the list's cache, which nobody sees), so what is
/// on screen always has its pictures, a frame after it scrolls in at
/// worst.
abstract final class WebImageViews {
  /// The most `<img>` views alive at once.
  static int cap = kWebImageViewCap;

  static final Set<_WebNetworkImageState> _live = <_WebNetworkImageState>{};
  static final List<_WebNetworkImageState> _waiting =
      <_WebNetworkImageState>[];
  static bool _checkScheduled = false;

  /// How many views are alive now.
  static int get live => _live.length;

  /// How many images wait for a view.
  static int get waiting => _waiting.length;

  static bool _claim(_WebNetworkImageState image) {
    if (image._slot) return true;
    if (image._parked || _live.length >= cap) {
      if (!_waiting.contains(image)) _waiting.add(image);
      _scheduleCheck();
      return false;
    }
    _waiting.remove(image);
    _live.add(image);
    image._slot = true;
    return true;
  }

  static void _release(_WebNetworkImageState image) {
    _waiting.remove(image);
    if (!image._slot) return;
    image._slot = false;
    _live.remove(image);
    _scheduleCheck();
  }

  /// After the next frame (a claim or a release happens while the tree is
  /// built or torn down), and after every frame while images wait (a
  /// scroll brings them on screen): [_check].
  static void _scheduleCheck() {
    if (_waiting.isEmpty || _checkScheduled) return;
    _checkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      _check();
      _scheduleCheck();
    });
  }

  /// Hands the free views to the images waiting on screen, then the views
  /// of images off screen to the ones still waiting on screen. Images
  /// waiting off screen keep waiting.
  static void _check() {
    _waiting.removeWhere((image) => !image.mounted);
    if (_waiting.isEmpty) return;
    var free = cap - _live.length;
    List<_WebNetworkImageState>? offScreen;
    for (final image in List.of(_waiting)) {
      if (!image._onScreen()) continue;
      if (free <= 0) {
        offScreen ??= [
          for (final held in _live)
            if (!held._onScreen()) held
        ];
        if (offScreen.isEmpty) break;
        final held = offScreen.removeLast();
        held._parked = true;
        _release(held);
        held._granted();
      } else {
        free--;
      }
      _waiting.remove(image);
      image._parked = false;
      // Admitted ahead of anyone else building this frame.
      _live.add(image);
      image._slot = true;
      image._granted();
    }
  }

  /// Tests: take the `<img>` path off the web (the view is an empty box).
  @visibleForTesting
  static bool debugForceWeb = false;

  @visibleForTesting
  static void debugReset() {
    cap = kWebImageViewCap;
    _live.clear();
    _waiting.clear();
    _checkScheduled = false;
    debugForceWeb = false;
  }
}

/// [WebImageViews.cap]'s default. Measured on the Investing list on a
/// 2000 px wide window: six columns of about twenty rows on screen.
const int kWebImageViewCap = 160;
