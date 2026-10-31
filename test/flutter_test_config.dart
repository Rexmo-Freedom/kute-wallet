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

import 'dart:async';

import 'package:kute/screens/shared/sal_sprite.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  SalSpriteCache.debugSetManifest(null);
  await testMain();
}
