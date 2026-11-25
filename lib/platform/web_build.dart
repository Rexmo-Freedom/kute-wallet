/// The id of the running web build: the BUILD that
/// `dart run tool/web_pwa_stamp.dart` writes into flutter_bootstrap.js,
/// which sets `window.kuteWebBuild` before the app starts. Null off web and
/// on an unstamped build.
library;

export 'web_build_native.dart'
    if (dart.library.js_interop) 'web_build_web.dart';
