/// Web: reads the browser's pointer and touch signals for
/// browser_signals.dart.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'browser_signals.dart' show BrowserSignals;

bool _matches(String query) {
  try {
    final mql = globalContext.callMethod<JSObject?>(
        'matchMedia'.toJS, query.toJS);
    return (mql?['matches'] as JSBoolean?)?.toDart ?? false;
  } catch (_) {
    return false;
  }
}

BrowserSignals? readBrowserSignals() {
  try {
    final navigator = globalContext['navigator'] as JSObject?;
    final touchPoints =
        (navigator?['maxTouchPoints'] as JSNumber?)?.toDartInt ?? 0;
    final userAgent = (navigator?['userAgent'] as JSString?)?.toDart ?? '';
    return BrowserSignals(
      maxTouchPoints: touchPoints,
      coarsePointer: _matches('(pointer: coarse)'),
      noHover: _matches('(hover: none)'),
      userAgent: userAgent,
      standalone: _matches('(display-mode: standalone)') ||
          ((navigator?['standalone'] as JSBoolean?)?.toDart ?? false),
    );
  } catch (_) {
    return null;
  }
}
