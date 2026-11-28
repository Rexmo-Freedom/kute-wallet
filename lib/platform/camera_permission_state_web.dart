/// Web: the browser's stored answer for the camera on this site
/// (`navigator.permissions.query({name: 'camera'})`): `granted`, `denied`
/// or `prompt`; `unknown` when the browser has no such query or it fails.
/// Read only: it never asks for the camera.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

Future<String> cameraPermissionState() async {
  try {
    final navigator = globalContext['navigator'] as JSObject?;
    final permissions = navigator?['permissions'] as JSObject?;
    if (permissions == null) return 'unknown';
    final descriptor = JSObject()..['name'] = 'camera'.toJS;
    final status = await permissions
        .callMethod<JSPromise<JSObject>>('query'.toJS, descriptor)
        .toDart
        .timeout(const Duration(seconds: 2));
    final state = (status['state'] as JSString?)?.toDart;
    return switch (state) {
      'granted' || 'denied' || 'prompt' => state!,
      _ => 'unknown',
    };
  } catch (_) {
    return 'unknown';
  }
}
