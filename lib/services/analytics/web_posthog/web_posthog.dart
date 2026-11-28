/// Web only: PostHog without posthog-js. See web_posthog_client.dart.
///
/// [WebPosthog.install] swaps `posthog_flutter`'s web platform for the
/// pure-Dart client before PostHog's setup. A no-op on iOS, Android and
/// desktop, where the plugin's native SDKs stay exactly as they are.
library;

import 'package:flutter/foundation.dart';

import 'web_posthog_native.dart'
    if (dart.library.js_interop) 'web_posthog_web.dart' as impl;

abstract final class WebPosthog {
  static bool _installed = false;

  /// Call once at web boot, before anything calls `Posthog()`.
  static void install() {
    if (!kIsWeb || _installed) return;
    _installed = true;
    impl.installWebPosthog();
  }
}
