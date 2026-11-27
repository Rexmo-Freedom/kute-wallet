// lib/services/web_advanced_test.dart
//
// A TEMPORARY TEST SWITCH (founder, 27 November 2026: "on web just do a
// force enable there, we will roll it back once tested", for Advanced).
// The backend capability `trading.advanced` is off for everyone; this
// turns Advanced on in ONE BROWSER, the one that opened
//
//     https://app.kutewallet.com/#/?advanced=on      (…=off turns it back)
//
// and nowhere else: never on the phones, never for a visitor who did not
// open that link. While it is on in a browser:
//   * `trading.advanced` reads as allowed there (the entry and the check at
//     placement: RuntimeCapabilitiesService.decision);
//   * the Investing leverage cap reads as 1x, whatever the policy says
//     (leverage stays blocked: RuntimeCapabilitiesService.maxLeverage).
// Every other capability (the venues' trade, deposit and region rules)
// still answers to the backend policy.
//
// TO ROLL BACK: delete this file and its three uses (the router's root
// redirect, `decision` and `maxLeverage` in runtime_capabilities_service).

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;

import 'package:kute/platform/plain_web_storage.dart';

abstract final class WebAdvancedTest {
  static const String storageKey = 'kute_advanced_test';
  static const String query = 'advanced';

  /// Tests: stands for "this is the web".
  @visibleForTesting
  static bool? debugWeb;

  static bool get _web => debugWeb ?? kIsWeb;

  /// Whether this browser opened the test link.
  static bool get on => _web && PlainWebStorage.read(storageKey) == 'on';

  /// The root link's `advanced=on|off`; anything else changes nothing.
  static void readLink(String? value) {
    if (!_web) return;
    if (value == 'on' || value == 'off') {
      PlainWebStorage.write(storageKey, value!);
    }
  }
}
