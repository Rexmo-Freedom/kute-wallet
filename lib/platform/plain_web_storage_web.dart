/// Web: the page's localStorage (plain_web_storage.dart).
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

JSObject? get _storage => globalContext['localStorage'] as JSObject?;

String? read(String key) =>
    (_storage?.callMethod<JSString?>('getItem'.toJS, key.toJS))?.toDart;

void write(String key, String value) {
  _storage?.callMethod<JSAny?>('setItem'.toJS, key.toJS, value.toJS);
}
