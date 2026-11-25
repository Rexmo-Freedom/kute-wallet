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
// Branta's payee lookup (services/branta) is offline in every test: a
// verifier that answers `unknown` at once, so no widget test reaches the
// network or leaves a timer behind. Branta's own tests install fakes.

import 'dart:async';

import 'package:branta/branta.dart' show VerifyResult, VerifyStatus;
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/services/branta/branta_payee_service.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  SalSpriteCache.debugSetManifest(null);
  BrantaPayeeService.shared = BrantaPayeeService(
    verifier: (_) async =>
        const VerifyResult(status: VerifyStatus.unknown, verifyUrl: ''),
  );
  await testMain();
}
