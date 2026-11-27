import 'dart:js_interop';
import 'dart:js_interop_unsafe';

Future<bool> requestPersistentStorage() async {
  try {
    final nav = globalContext['navigator'] as JSObject?;
    final storage = nav?['storage'] as JSObject?;
    if (storage == null || !storage.has('persist')) return false;
    final promise = storage.callMethod<JSPromise<JSBoolean>>('persist'.toJS);
    return (await promise.toDart).toDart;
  } catch (_) {
    return false;
  }
}
