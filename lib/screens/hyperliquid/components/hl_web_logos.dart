// Web only: the Investing logos shipped with the web build
// (tool/web_hl_logos.dart writes build/web/logos/hl/ and its index.json).
//
// The logo hosts send no CORS headers, so the page cannot read a logo from
// them; it could only show it as an `<img>` platform view, and on Safari
// each one costs a full-screen WebGL canvas (the Dollars home reloaded on
// phones). The shipped copy is on the app's own origin: HlCoinIcon reads
// its bytes and draws it in the canvas, exactly as the phones draw a
// downloaded logo. A logo the index lacks (a market listed after the
// build) is a miss, and the market shows its monogram. The phones never
// use this file.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import 'package:kute/services/http/shared_http_client.dart';

/// Where the index sits, relative to the page.
const String kHlWebLogoIndex = 'logos/hl/index.json';

abstract final class HlWebLogos {
  static Map<String, String>? _index;
  static Future<Map<String, String>>? _loading;

  /// Reads the index (once per page; a failed read is tried again on the
  /// next ask). Overridable for tests.
  @visibleForTesting
  static Future<String?> Function() loadIndex = _loadIndex;

  static Future<String?> _loadIndex() async {
    final http.Response r = await SharedHttpClient.get(
        Uri.base.resolve(kHlWebLogoIndex),
        kind: HttpCallKind.backgroundRead,
        timeout: const Duration(seconds: 8));
    return r.statusCode == 200 ? r.body : null;
  }

  static Future<Map<String, String>> _ensure() {
    final index = _index;
    if (index != null) return Future.value(index);
    return _loading ??= () async {
      try {
        final text = await loadIndex();
        final decoded = text == null ? null : jsonDecode(text);
        final map = <String, String>{
          if (decoded is Map)
            for (final e in decoded.entries)
              if (e.key is String && e.value is String)
                e.key as String: e.value as String,
        };
        if (text != null) _index = map;
        return map;
      } catch (_) {
        return const <String, String>{};
      } finally {
        _loading = null;
      }
    }();
  }

  /// Reads the index ahead (web boot), so [hasAny] answers on a list's
  /// first frame. Never throws.
  static Future<void> preload() => _ensure();

  /// Whether the index has been read.
  static bool get ready => _index != null;

  /// Whether the build shipped a copy of any of [remoteUrls]. False until
  /// the index has been read ([preload]).
  static bool hasAny(Iterable<String> remoteUrls) {
    final index = _index;
    return index != null && remoteUrls.any(index.containsKey);
  }

  /// The same-origin URL of the shipped copy of [remoteUrl], or null when
  /// the build has none.
  static Future<String?> localUrlFor(String remoteUrl) async {
    final path = (await _ensure())[remoteUrl];
    return path == null ? null : Uri.base.resolve(path).toString();
  }

  @visibleForTesting
  static void debugSetIndex(Map<String, String> index) {
    _index = Map.of(index);
    _loading = null;
  }

  @visibleForTesting
  static void debugReset() {
    _index = null;
    _loading = null;
    loadIndex = _loadIndex;
  }
}
