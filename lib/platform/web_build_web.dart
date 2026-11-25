/// Web: `window.kuteWebBuild`, set by flutter_bootstrap.js. See
/// web_build.dart.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

String? webBuildId() {
  final id = globalContext['kuteWebBuild']?.dartify();
  return id is String ? id : null;
}
