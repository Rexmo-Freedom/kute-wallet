// Loads the @breeztech/breez-sdk-spark wasm module (its `web` build).
//
// The host page either exposes the module itself, as a Promise of the
// initialized module namespace on `globalThis.breezSdkSpark`:
//
//   <script type="module">
//     import init, * as breez from './breez_sdk_spark/index.js';
//     globalThis.breezSdkSpark = init().then(() => breez);
//   </script>
//
// or ships the npm package's `web/` directory at [defaultModuleUrl] (relative
// to the page base URL), which is imported on first use.

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Where the npm package's `web/index.js` is served, relative to the page.
const String defaultModuleUrl = 'breez_sdk_spark/index.js';

const String _globalName = 'breezSdkSpark';

@JS('document.baseURI')
external String? get _baseUri;

@JS('URL')
extension type _Url._(JSObject _) implements JSObject {
  external _Url(String url, String base);
  external String get href;
}

JSObject? _module;
Future<JSObject>? _loading;

/// The initialized wasm module namespace. Throws if [loadBreezWasm] has not
/// completed.
JSObject get breezModule {
  final m = _module;
  if (m == null) {
    throw StateError('Breez SDK wasm is not loaded: await BreezSdkSparkLib.init() first');
  }
  return m;
}

/// Loads and initializes the wasm module once.
Future<JSObject> loadBreezWasm({String? moduleUrl}) {
  final m = _module;
  if (m != null) return Future.value(m);
  return _loading ??= _load(moduleUrl).then(
    (m) => _module = m,
    onError: (Object e, StackTrace st) {
      _loading = null;
      Error.throwWithStackTrace(e, st);
    },
  );
}

Future<JSObject> _load(String? moduleUrl) async {
  final provided = globalContext.getProperty<JSAny?>(_globalName.toJS);
  if (provided != null && !provided.isUndefinedOrNull && moduleUrl == null) {
    final resolved = provided.instanceOfString('Promise')
        ? await (provided as JSPromise<JSAny?>).toDart
        : provided;
    return resolved as JSObject;
  }
  final url = _Url(moduleUrl ?? defaultModuleUrl, _baseUri ?? '').href;
  final module = await importModule(url.toJS).toDart;
  final init = module.getProperty<JSAny?>('default'.toJS);
  if (init != null && init.typeofEquals('function')) {
    final p = (init as JSFunction).callAsFunction();
    if (p != null && p.instanceOfString('Promise')) await (p as JSPromise<JSAny?>).toDart;
  }
  globalContext.setProperty(_globalName.toJS, module);
  return module;
}
