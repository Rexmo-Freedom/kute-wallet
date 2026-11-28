// lib/services/web_advanced_test.dart
//
// TEMPORARY: ADVANCED IS ON IN THE WEB APP, WHATEVER THE BACKEND SAYS
// (founder, 27 November 2026: "don't activate advanced on backend, just on
// web, literally don't read the value from backend, just have it
// activated ... we will roll it back once tested").
//
// The backend capability `trading.advanced` stays off, so the phone apps
// keep Advanced withheld. On the web the app does not read it:
//   * `trading.advanced` reads as allowed for every web visitor (the entry
//     and the check at placement: RuntimeCapabilitiesService.decision);
//   * the Investing leverage cap reads as 1x (leverage stays blocked:
//     RuntimeCapabilitiesService.maxLeverage).
// Every other capability (the venues' trade, deposit and region rules)
// still answers to the backend policy. While this is in, the backend's
// Advanced switch cannot turn Advanced off on the web: only a new build
// can.
//
// TO ROLL BACK: delete this file and its three uses (`decision`,
// `_unavailableDecision` and `maxLeverage` in
// runtime_capabilities_service.dart), rebuild, deploy.

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;

abstract final class WebAdvancedTest {
  /// Tests: stands for "this is the web".
  @visibleForTesting
  static bool? debugWeb;

  /// True on the web, always; never on the phones.
  static bool get on => debugWeb ?? kIsWeb;
}
