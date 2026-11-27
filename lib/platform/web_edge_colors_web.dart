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
      // The page's own background as well, for a browser that reads it.
      for (final el in [document['documentElement'] as JSObject?, body]) {
        (el?['style'] as JSObject?)?.callMethod<JSAny?>(
            'setProperty'.toJS, 'background-color'.toJS, bottom.toJS);
      }
    }
  } catch (_) {}
}
