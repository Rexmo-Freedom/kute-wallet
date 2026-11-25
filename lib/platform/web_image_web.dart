/// Web: images through the browser's `<img>` element, no fetch() (see
/// web_image.dart).
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/widgets.dart';

import 'web_image.dart' show WebImageLoad;

// The SDK floor (3.2) predates extension types, so the element is
// driven through js_interop_unsafe's property access.
JSObject _newImg() =>
    (globalContext['Image'] as JSFunction).callAsConstructor<JSObject>();

int _natural(JSObject img, String name) =>
    (img[name] as JSNumber?)?.toDartInt ?? 0;

Future<WebImageLoad?> loadImage(String url, Duration timeout) {
  final completer = Completer<WebImageLoad?>();
  final img = _newImg();
  Timer? timer;
  void finish(WebImageLoad? result) {
    if (completer.isCompleted) return;
    timer?.cancel();
    img['onload'] = null;
    img['onerror'] = null;
    completer.complete(result);
  }

  img['onload'] = ((JSAny? _) => finish(WebImageLoad(
      width: _natural(img, 'naturalWidth'),
      height: _natural(img, 'naturalHeight')))).toJS;
  img['onerror'] = ((JSAny? _) => finish(null)).toJS;
  timer = Timer(timeout, () {
    finish(null);
    // Stops the download; the element is dropped with this closure.
    img['src'] = ''.toJS;
  });
  img['decoding'] = 'async'.toJS;
  img['src'] = url.toJS;
  return completer.future;
}

const String _viewType = 'kute-network-img';
bool _registered = false;

String _objectFit(BoxFit fit) => switch (fit) {
      BoxFit.cover => 'cover',
      BoxFit.contain => 'contain',
      BoxFit.fill => 'fill',
      BoxFit.fitWidth => 'contain',
      BoxFit.fitHeight => 'contain',
      BoxFit.none => 'none',
      BoxFit.scaleDown => 'scale-down',
    };

void _register() {
  if (_registered) return;
  _registered = true;
  ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId,
      {Object? params}) {
    final map = params is Map ? params : const {};
    final img = _newImg();
    img['alt'] = ''.toJS;
    img['draggable'] = false.toJS;
    img['decoding'] = 'async'.toJS;
    final style = img['style'] as JSObject;
    style['width'] = '100%'.toJS;
    style['height'] = '100%'.toJS;
    style['display'] = 'block'.toJS;
    style['objectFit'] = ((map['fit'] as String?) ?? 'cover').toJS;
    final radius = map['radius'] as String?;
    if (radius != null) style['borderRadius'] = radius.toJS;
    style['pointerEvents'] = 'none'.toJS;
    style['userSelect'] = 'none'.toJS;
    img['src'] = ((map['src'] as String?) ?? '').toJS;
    return img;
  });
}

/// [radius] as CSS: each corner's horizontal / vertical radii.
String? _cssRadius(BorderRadius? r) {
  if (r == null || r == BorderRadius.zero) return null;
  String px(double v) => '${v.toStringAsFixed(2)}px';
  return '${px(r.topLeft.x)} ${px(r.topRight.x)} ${px(r.bottomRight.x)} '
      '${px(r.bottomLeft.x)} / ${px(r.topLeft.y)} ${px(r.topRight.y)} '
      '${px(r.bottomRight.y)} ${px(r.bottomLeft.y)}';
}

Widget imgView(String url, BoxFit fit, BorderRadius? radius) {
  _register();
  final css = _cssRadius(radius);
  return HtmlElementView(
    key: ValueKey('$url|${fit.name}|$css'),
    viewType: _viewType,
    creationParams: {
      'src': url,
      'fit': _objectFit(fit),
      if (css != null) 'radius': css,
    },
    hitTestBehavior: PlatformViewHitTestBehavior.transparent,
  );
}
