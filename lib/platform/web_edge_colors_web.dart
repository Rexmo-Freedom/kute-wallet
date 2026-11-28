/// Web: hands the band colours (web_edge_colors.dart) to Safari.
///
/// Measured in the simulator (iOS 27 Safari) on the running app: the bands
/// behind the status bar and the toolbar take the colour of a full-width
/// fixed element at least 8 px tall lying at that edge OVER the page (one
/// behind the Flutter view, or thinner, is not read), and Safari reads it
/// again only when such an element is INSERTED. A new colour on the same
/// element, or on the body, is ignored once the app has started. So each
/// change replaces that edge's strip (`#kute-edge-top`,
/// `#kute-edge-bottom`) with a new element in the new colour. Once read,
/// the band keeps its colour after the strip turns transparent, so a strip
/// is shown for [_shown] only (8 px in exactly the colour the app draws at
/// that edge, no taps) and never sits over the app's own buttons.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

const String _style = 'position:fixed;left:0;right:0;height:8px;'
    'z-index:2;pointer-events:none;';

/// How long a new strip stays visible: long enough for Safari to read it
/// (measured: one frame is), short enough not to be seen.
const Duration _shown = Duration(milliseconds: 80);

String? _top;
String? _bottom;

void setEdgeColors({required String top, required String bottom}) {
  try {
    final document = globalContext['document'] as JSObject;
    final body = document['body'] as JSObject?;
    if (body == null) return;
    void strip(String id, String edge, String color) {
      final old =
          document.callMethod<JSObject?>('getElementById'.toJS, id.toJS);
      final div =
          document.callMethod<JSObject>('createElement'.toJS, 'div'.toJS);
      div['id'] = id.toJS;
      div.callMethod<JSAny?>(
          'setAttribute'.toJS, 'aria-hidden'.toJS, 'true'.toJS);
      (div['style'] as JSObject)['cssText'] =
          '$_style$edge:0;background-color:$color;'.toJS;
      old?.callMethod<JSAny?>('remove'.toJS);
      body.callMethod<JSAny?>('appendChild'.toJS, div);
      Timer(_shown, () {
        try {
          (div['style'] as JSObject)['opacity'] = '0'.toJS;
        } catch (_) {}
      });
    }

    // Only an edge whose colour changed is replaced (an insertion is what
    // Safari reads).
    if (top != _top) {
      _top = top;
      strip('kute-edge-top', 'top', top);
    }
    if (bottom != _bottom) {
      _bottom = bottom;
      strip('kute-edge-bottom', 'bottom', bottom);
    }
    keepPageBackground();
  } catch (_) {}
}

/// THE PAGE'S OWN BACKGROUND IS THE BAND COLOUR ON iOS 26. Safari there
/// paints its bars from the body's background colour, and a transparent
/// body gives BLACK bars in dark mode (white in light, so it only showed
/// in dark; founder's iPhone, 27 November 2026: black bars above and under
/// a dark PIN screen). The body does go transparent once the app runs:
/// the splash's removal (web/splash.js) and the engine's own body style
/// both write it, after this file last set the colour.
///
/// So the html and body background is the app's bottom edge colour, set
/// as `!important` (a later plain `background: transparent` cannot undo
/// it) and looked at again on every pass, not only when the colour
/// changes. Nothing is written when it already holds.
void keepPageBackground() {
  final color = _bottom;
  if (color == null) return;
  try {
    final document = globalContext['document'] as JSObject;
    for (final el in [
      document['documentElement'] as JSObject?,
      document['body'] as JSObject?,
    ]) {
      final style = el?['style'] as JSObject?;
      if (style == null) continue;
      final now = style
          .callMethod<JSString?>(
              'getPropertyValue'.toJS, 'background-color'.toJS)
          ?.toDart;
      final priority = style
          .callMethod<JSString?>(
              'getPropertyPriority'.toJS, 'background-color'.toJS)
          ?.toDart;
      if (now == color && priority == 'important') continue;
      style.callMethod<JSAny?>('setProperty'.toJS, 'background-color'.toJS,
          color.toJS, 'important'.toJS);
    }
  } catch (_) {}
}
