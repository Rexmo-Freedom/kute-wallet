import 'dart:js_interop';
import 'dart:js_interop_unsafe';

Future<bool> immediateMediation() async {
  try {
    final pkc = globalContext['PublicKeyCredential'] as JSObject?;
    if (pkc == null || !pkc.has('getClientCapabilities')) return false;
    final caps = await pkc
        .callMethod<JSPromise<JSObject?>>('getClientCapabilities'.toJS)
        .toDart
        .timeout(const Duration(seconds: 2));
    return (caps?['immediateGet'] as JSBoolean?)?.toDart ?? false;
  } catch (_) {
    return false;
  }
}
