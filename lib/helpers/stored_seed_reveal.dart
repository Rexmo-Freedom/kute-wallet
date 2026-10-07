import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/providers/auth_provider.dart';
import 'package:kute/screens/shared/pin_gate_sheet.dart';

/// Reads a stored wallet's seed for a screen that already ran its own gate.
/// When a PIN-encrypted copy needs the PIN and none is held, the PIN sheet
/// collects it once and the read runs again.
Future<SeedRead> readStoredSeedInteractive(
  BuildContext context,
  WidgetRef ref,
  String walletId, {
  required String pinTitle,
  required String analyticsSurface,
}) async {
  final auth = ref.read(authModelProvider);
  final first = await auth.readMnemonic(walletId,
      access: SeedAccess.interactive, session: ref.read(seedSessionProvider));
  if (first is! SeedLocked || !context.mounted) return first;
  var verified = false;
  await PinGateSheet.show(
    context,
    title: pinTitle,
    onVerified: () => verified = true,
    analyticsSurface: analyticsSurface,
  );
  if (!verified || !context.mounted) return first;
  return auth.readMnemonic(walletId,
      access: SeedAccess.interactive, session: ref.read(seedSessionProvider));
}
