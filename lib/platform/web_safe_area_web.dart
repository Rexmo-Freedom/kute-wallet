/// Web: reads `env(safe-area-inset-*)` through a hidden probe element (see
/// web_safe_area.dart).
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/widgets.dart';

JSObject? _probe;

JSObject _ensureProbe() {
  final existing = _probe;
  if (existing != null) return existing;
  final document = globalContext['document'] as JSObject;
  final probe =
      document.callMethod<JSObject>('createElement'.toJS, 'div'.toJS);
  final style = probe['style'] as JSObject;
  void set(String name, String value) =>
      style.callMethod<JSAny?>('setProperty'.toJS, name.toJS, value.toJS);
  set('position', 'fixed');
  set('top', '0');
  set('left', '0');
  set('width', '0');
  set('height', '0');
  set('visibility', 'hidden');
  set('pointer-events', 'none');
  set('padding-top', 'env(safe-area-inset-top, 0px)');
  set('padding-right', 'env(safe-area-inset-right, 0px)');
  set('padding-bottom', 'env(safe-area-inset-bottom, 0px)');
  set('padding-left', 'env(safe-area-inset-left, 0px)');
  (document['body'] as JSObject)
      .callMethod<JSAny?>('appendChild'.toJS, probe);
  return _probe = probe;
}

EdgeInsets safeAreaInsets() {
  try {
    final computed = globalContext.callMethod<JSObject>(
        'getComputedStyle'.toJS, _ensureProbe());
    double read(String name) {
      final value = computed
          .callMethod<JSString>('getPropertyValue'.toJS, name.toJS)
          .toDart;
      return double.tryParse(value.replaceAll('px', '').trim()) ?? 0;
    }

    return EdgeInsets.fromLTRB(read('padding-left'), read('padding-top'),
        read('padding-right'), read('padding-bottom'));
  } catch (_) {
    return EdgeInsets.zero;
  }
}
