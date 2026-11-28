import 'dart:js_interop';
import 'dart:js_interop_unsafe';

String? userAgent() {
  try {
    final nav = globalContext['navigator'] as JSObject?;
    return (nav?['userAgent'] as JSString?)?.toDart;
  } catch (_) {
    return null;
  }
}
