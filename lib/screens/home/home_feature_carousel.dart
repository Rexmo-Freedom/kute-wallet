import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/capability_unavailable_sheet.dart';
import 'package:kute/services/investment_provider_availability.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';

Future<bool> checkPolymarketGeoblock(BuildContext context,
    {String capability = 'polymarket.trade',
    Iterable<String>? capabilities,
    Duration maxAge = Duration.zero}) async {
  late String message;
  var regionBlocked = false;
  final l10n = context.l10n;
  try {
    // At the tap the slip re-checks what it checked when it opened; a
    // policy fetched within [maxAge] is read rather than fetched again,
    // so the order is not held behind a round trip the book can move in.
    // [capabilities] names every gate a bet needs (opening predictions
    // plus its category gate); [capability] alone serves the exits.
    await RuntimeCapabilitiesService.instance
        .ensureAllAllowed(capabilities ?? [capability], maxAge: maxAge);
    return false;
  } on ProviderAvailabilityException catch (error) {
    message = error.availability.messageIn(l10n);
    regionBlocked =
        error.availability.status == ProviderAvailabilityStatus.restricted;
  } on CapabilityUnavailableException catch (error) {
    message = error.decision.messageIn(l10n);
    regionBlocked = error.decision.regionRestricted;
  }
  if (!context.mounted) return true;

  if (regionBlocked) {
    TrackingService.polymarketGeoblockedShown();
  } else {
    // Not a region block: the capability is switched off (policy / kill
    // switch). Same sheet, so it gets its own reason rather than being
    // counted as a geoblock. `capability` is a fixed id like
    // 'polymarket.trade', never user data.
    TrackingService.track('feature_unavailable_shown', params: {
      'feature': 'predictions',
      'capability': capability,
      'reason': 'capability_disabled',
      'surface': 'predictions_gate_sheet',
    });
  }
  // The shared unavailable sheet: "Not available in your region" with the
  // network / VPN sentence for a region block, "Predictions unavailable"
  // with the policy's own reason otherwise.
  unawaited(showCapabilityUnavailableSheet(
    context,
    message: message,
    regionRestricted: regionBlocked,
    title: l10n.gatePredictionsUnavailable,
  ));
  return true;
}
