// test/flutter_test_config.dart
//
// Runs before every test file (flutter_test picks this up for the whole
// test/ tree). The 3D Sal sprite sheets (lib/assets/sal) are real assets
// that a widget test would otherwise load through the root bundle after
// about a second of wall clock; once loaded, every looping SalSprite on
// screen (the floating bar's pill, a Share button's face) ticks for ever
// and a later pumpAndSettle in the same file times out. The manifest is
// nulled here, so sprites draw their fallback unless a test installs its
// own synthetic clips (the sal_* tests do).
//
// THE DEFAULT WINDOW IS A PHONE (kute_layout.dart): flutter_test's own
// default view is 800 x 600, which the app now reads as a tablet window
// (MEDIUM: centred columns, sheets capped at 480). Every test starts on
// a 430 x 932 phone instead, the design's own size; a test that sets its
// own size (tester.view.physicalSize) keeps it.
//
// Branta's payee lookup (services/branta) is offline in every test: a
// verifier that answers `unknown` at once, so no widget test reaches the
// network or leaves a timer behind. Branta's own tests install fakes.

import 'dart:async';

import 'dart:ui' show Size;

import 'package:branta/branta.dart' show VerifyResult, VerifyStatus;
import 'package:flutter/foundation.dart' show BindingBase;
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/services/branta/branta_payee_service.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  SalSpriteCache.debugSetManifest(null);
  BrantaPayeeService.shared = BrantaPayeeService(
    verifier: (_) async =>
        const VerifyResult(status: VerifyStatus.unknown, verifyUrl: ''),
  );
  setUp(() {
    // Only where a widget binding is already up (a file with widget
    // tests): a plain Dart test keeps running with no binding at all.
    if (BindingBase.debugBindingType() == null) return;
    final binding = WidgetsBinding.instance;
    if (binding is! TestWidgetsFlutterBinding) return;
    final view = binding.platformDispatcher.implicitView!;
    view.physicalSize = const Size(430 * 3, 932 * 3);
    view.devicePixelRatio = 3;
  });
  await testMain();
}
