/// What the platform says about the camera permission when a scan was
/// refused, for the diagnostic event (`scanner_camera_refused`): on the web
/// the browser's own answer (`granted`, `denied`, `prompt`), `unknown`
/// where it cannot be asked (the phones answer through permission_handler
/// elsewhere).
library;

export 'camera_permission_state_native.dart'
    if (dart.library.js_interop) 'camera_permission_state_web.dart';
