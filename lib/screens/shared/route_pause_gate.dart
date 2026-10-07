// lib/screens/shared/route_pause_gate.dart
//
// UI gate for the remote pause switches (Wallet hardening Phase 5 plan
// B13, F16). Call it only where a NEW operation starts. Never call it for
// pending operations, status checks, refunds or balance reads.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/services/release/route_pause_policy.dart';
import 'package:kute/services/tracking_service.dart';

/// Returns true when a new operation on [route] may start. When the
/// switch is known to be on, shows why, emits `route_paused_shown` and
/// returns false. Unknown is not paused.
Future<bool> ensureRouteNotPaused(
  BuildContext context,
  PausableRoute route,
) async {
  final policy = ProviderScope.containerOf(context, listen: false)
      .read(routePausePolicyProvider);
  if (!await policy.isPaused(route)) return true;
  TrackingService.routePausedShown(route.analyticsName);
  if (context.mounted) {
    showMessageSnackBarInfo(
      context: context,
      message: context.l10n.routePausedBody,
    );
  }
  return false;
}
