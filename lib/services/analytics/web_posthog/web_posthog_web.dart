/// The browser side of [WebPosthogEnv]: user agent, screen size, location,
/// page-hide hooks and `sendBeacon` through `dart:js_interop`, the identity
/// in the plain IndexedDB store (through secure storage, whose web platform
/// routes `analytics_*` keys there: vault_keys.dart). No script is loaded.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:package_info_plus/package_info_plus.dart';
// The plugin's documented extension point for a platform implementation.
// ignore: implementation_imports
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';

import 'package:kute/services/analytics/web_posthog/web_posthog_client.dart';
import 'package:kute/services/analytics/web_posthog/web_posthog_platform.dart';
import 'package:kute/services/secure_storage.dart';

void installWebPosthog() {
  PosthogFlutterPlatformInterface.instance =
      WebPosthogPlatform(WebPosthogClient(env: _BrowserEnv()));
}

class _BrowserEnv implements WebPosthogEnv {
  JSObject get _window => globalContext;
  JSObject? _obj(JSObject o, String name) {
    final v = o.getProperty<JSAny?>(name.toJS);
    return v == null ? null : v as JSObject;
  }

  JSObject? get _navigator => _obj(_window, 'navigator');
  JSObject? get _document => _obj(_window, 'document');

  @override
  String get userAgent {
    try {
      return _navigator?.getProperty<JSString?>('userAgent'.toJS)?.toDart ?? '';
    } catch (_) {
      return '';
    }
  }

  int? _screen(String name) {
    try {
      final s = _obj(_window, 'screen');
      return s?.getProperty<JSNumber?>(name.toJS)?.toDartInt;
    } catch (_) {
      return null;
    }
  }

  @override
  int? get screenWidth => _screen('width');

  @override
  int? get screenHeight => _screen('height');

  @override
  String get locationHref {
    try {
      final loc = _obj(_window, 'location');
      return loc?.getProperty<JSString?>('href'.toJS)?.toDart ?? '';
    } catch (_) {
      return '';
    }
  }

  @override
  void listenPageLifecycle({
    required void Function() onHidden,
    required void Function() onVisible,
  }) {
    final doc = _document;
    if (doc != null) {
      doc.callMethod<JSAny?>(
          'addEventListener'.toJS,
          'visibilitychange'.toJS,
          ((JSAny? _) {
            final state =
                doc.getProperty<JSString?>('visibilityState'.toJS)?.toDart;
            if (state == 'hidden') {
              onHidden();
            } else if (state == 'visible') {
              onVisible();
            }
          }).toJS);
    }
    _window.callMethod<JSAny?>('addEventListener'.toJS, 'pagehide'.toJS,
        ((JSAny? _) => onHidden()).toJS);
  }

  @override
  bool sendBeacon(String url, String body) {
    try {
      final nav = _navigator;
      if (nav == null || !nav.has('sendBeacon')) return false;
      // A string body goes as text/plain: a "simple" request, no preflight.
      final ok =
          nav.callMethod<JSBoolean?>('sendBeacon'.toJS, url.toJS, body.toJS);
      return ok?.toDart ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> readValue(String key) => secureStorage.read(key: key);

  @override
  Future<void> writeValue(String key, String value) =>
      secureStorage.write(key: key, value: value);

  @override
  Future<({String version, String build})?> appVersion() async {
    final info = await PackageInfo.fromPlatform();
    return (version: info.version, build: info.buildNumber);
  }
}
