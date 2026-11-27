/// Plain, non-secret, per-browser values (the page's localStorage): a
/// dismissed notice and the like. Never a secret (seed_vault.dart: no
/// secret lives in localStorage). Off the web nothing is stored and every
/// read is null.
library;

import 'package:flutter/foundation.dart';

import 'plain_web_storage_native.dart'
    if (dart.library.js_interop) 'plain_web_storage_web.dart' as impl;

abstract final class PlainWebStorage {
  /// Tests: an in-memory store in place of the browser's.
  @visibleForTesting
  static Map<String, String>? debugValues;

  static String? read(String key) {
    final debug = debugValues;
    if (debug != null) return debug[key];
    try {
      return impl.read(key);
    } catch (_) {
      return null;
    }
  }

  static void write(String key, String value) {
    final debug = debugValues;
    if (debug != null) {
      debug[key] = value;
      return;
    }
    try {
      impl.write(key, value);
    } catch (_) {}
  }
}
