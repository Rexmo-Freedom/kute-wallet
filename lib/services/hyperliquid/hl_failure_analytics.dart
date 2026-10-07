// What an Investing (Hyperliquid) order failure carries to PostHog beside
// its reason: the step it ended at (a closed `stage`), and for an exchange
// rejection a closed `refusal_class` plus the exchange's own words
// (`venue_refusal`, cleaned by VenueAnalytics.refusalText: no addresses,
// hex or numbers, 120 characters at most). Never keys, addresses, order
// ids, signatures or typed text.

import 'dart:async';

import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';
import 'package:kute/services/venue_analytics.dart';

/// A closed class for the exchange's rejection text.
String hlRefusalClass(String reason) {
  final t = reason.toLowerCase();
  if (t.contains('insufficient margin') ||
      t.contains('insufficient spot balance') ||
      t.contains('insufficient balance')) {
    return 'insufficient_margin';
  }
  if (t.contains('minimum value')) return 'below_min_notional';
  if (t.contains('could not immediately match')) return 'ioc_no_match';
  if (t.contains('post only')) return 'post_only_would_match';
  if (t.contains('tick size') || t.contains('divisible')) return 'invalid_tick';
  if (t.contains('invalid size') || t.contains('size must')) {
    return 'invalid_size';
  }
  if (t.contains('reduce only')) return 'reduce_only';
  if (t.contains('too many') || t.contains('rate limit')) {
    return 'rate_limited';
  }
  if (t.contains('does not exist')) return 'unknown_signer';
  if (t.contains('nonce')) return 'nonce';
  if (t.contains('away from the reference price') ||
      t.contains('price too far') ||
      t.contains('oracle')) {
    return 'price_too_far';
  }
  if (t.contains('open interest')) return 'oi_cap';
  if (t.contains('leverage')) return 'leverage';
  if (t.contains('trigger')) return 'trigger';
  return 'other';
}

/// The step an Investing order failure ended at, as one closed word.
String hlFailureStage(Object error) {
  if (error is ReauthRequired) return 'reauth';
  if (error is GrantRevoked) return 'user_declined';
  if (error is AuthGrantException) return 'grant_expired';
  if (error is HyperliquidSignatureRejectedException) return 'sign';
  if (error is HyperliquidRejectedException) return 'submit';
  if (error is TimeoutException) return 'timeout';
  if (HyperliquidExchangeService.isOfflineError(error)) return 'network';
  if (error is HyperliquidApiException) return 'submit';
  return 'unknown';
}

/// The properties an Investing order failure adds for [error].
Map<String, Object> hlFailureParams(Object error) => {
      'stage': hlFailureStage(error),
      if (error is HyperliquidRejectedException) ...{
        'refusal_class': hlRefusalClass(error.reason),
        'venue_refusal': VenueAnalytics.refusalText(error.reason),
      },
      if (error is HyperliquidApiException) 'http_status': error.statusCode,
    };
