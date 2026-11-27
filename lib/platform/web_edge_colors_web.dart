/// Web: writes the band colours (web_edge_colors.dart) to the page: the
/// html and body background (the bottom band) and `#kute-edge-top`.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

void setEdgeColors({required String top, required String bottom}) {
  try {
    final document = globalContext['document'] as JSObject;
    void paint(JSObject? element, String color) {
      if (element == null) return;
      (element['style'] as JSObject).callMethod<JSAny?>(
          'setProperty'.toJS, 'background-color'.toJS, color.toJS);
    }

    paint(document['documentElement'] as JSObject?, bottom);
    paint(document['body'] as JSObject?, bottom);
    paint(
        document.callMethod<JSObject?>(
            'getElementById'.toJS, 'kute-edge-top'.toJS),
        top);
  } catch (_) {}
}
