/// The page's safe-area insets on web (`env(safe-area-inset-*)`).
///
/// Flutter web reports no view padding: MediaQuery's padding is zero in a
/// browser, so SafeArea pads nothing. With `viewport-fit=cover` (needed for
/// a full-screen app added to an iPhone's Home Screen) the page reaches
/// under the home indicator and, in landscape, the sensor housing. The app
/// root (app_widget.dart) folds these insets into MediaQuery's padding and
/// viewPadding on web, so every existing SafeArea respects them.
///
/// Native never calls this: [webSafeAreaInsets] is zero there and the
/// call site asks `kIsWeb` first.
library;

import 'package:flutter/widgets.dart';

import 'web_safe_area_native.dart'
    if (dart.library.js_interop) 'web_safe_area_web.dart' as impl;

/// The current safe-area insets in logical pixels (CSS px); zero off web.
EdgeInsets webSafeAreaInsets() => impl.safeAreaInsets();

/// [data] with the web safe-area insets folded into its padding and
/// viewPadding (the larger of the two on each side).
MediaQueryData withWebSafeArea(MediaQueryData data) {
  final insets = webSafeAreaInsets();
  if (insets == EdgeInsets.zero) return data;
  EdgeInsets atLeast(EdgeInsets p) => EdgeInsets.fromLTRB(
        p.left > insets.left ? p.left : insets.left,
        p.top > insets.top ? p.top : insets.top,
        p.right > insets.right ? p.right : insets.right,
        p.bottom > insets.bottom ? p.bottom : insets.bottom,
      );
  // The keyboard's inset already covers the bottom: no double padding.
  final padding = atLeast(data.padding);
  return data.copyWith(
    padding: data.viewInsets.bottom > 0
        ? padding.copyWith(bottom: data.padding.bottom)
        : padding,
    viewPadding: atLeast(data.viewPadding),
  );
}
