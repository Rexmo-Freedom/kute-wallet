// lib/services/polymarket/combos/combo_analytics.dart
//
// PostHog events for Polymarket Combos (parlays), on the flow model of the
// Notion playbook "Tracking a new feature":
//
//   combo_quote_requested → combo_quoted (result: quoted | no_quote | …)
//     → combo_quote_expired (window ran out unaccepted)
//   combo_placed | combo_failed (action: place)            BUY outcome
//   combo_close_quoted → combo_closed | combo_failed (action: close)
//   combo_claimed | combo_failed (action: claim)
//
// Exact amounts, categorical values only: never an rfq/quote id, a
// position or condition id, an address or a key. Combos on the Requester
// API carry no builder code, so there is no revenue here; money outcomes
// still count as money actions (completedMoneyEvents).

import 'package:kute/services/tracking_service.dart';

abstract final class ComboAnalytics {
  static double _r(double v, [int places = 2]) {
    if (!v.isFinite) return 0;
    final f = places == 2 ? 100 : 1000000;
    return (v * f).roundToDouble() / f;
  }

  static Map<String, Object> _base({String? entrySource, String? route}) => {
        'venue': 'polymarket',
        'wallet_kind': 'hot',
        if (entrySource != null) 'entry_source': entrySource,
        if (route != null) 'route': route,
      };

  static void quoteRequested({
    required String direction,
    required int legs,
    required double sizeUsd,
    required bool auto,
    String? entrySource,
  }) =>
      TrackingService.track('combo_quote_requested', params: {
        ..._base(entrySource: entrySource),
        'direction': direction,
        'legs': legs,
        'amount_usd': _r(sizeUsd),
        'auto_requote': auto,
      });

  /// [result]: quoted | no_quote | rate_limited | error.
  static void quoted({
    required String direction,
    required int legs,
    required String result,
    double? stakeUsd,
    double? payoutUsd,
    double? multiplier,
    double? feeUsd,
    int? windowMs,
    int? latencyMs,
    String? reasonCode,
    String? entrySource,
  }) =>
      TrackingService.track('combo_quoted', params: {
        ..._base(entrySource: entrySource),
        'direction': direction,
        'legs': legs,
        'result': result,
        if (stakeUsd != null) 'amount_usd': _r(stakeUsd),
        if (payoutUsd != null) 'payout_usd': _r(payoutUsd),
        if (multiplier != null) 'multiplier': _r(multiplier),
        if (feeUsd != null) 'fee_shown_usd': _r(feeUsd),
        if (windowMs != null) 'window_ms': windowMs,
        if (latencyMs != null) 'duration_ms': latencyMs,
        if (reasonCode != null) 'reason_code': reasonCode.toLowerCase(),
      });

  static void quoteExpired({
    required String direction,
    required int legs,
    required bool willRequote,
  }) =>
      TrackingService.track('combo_quote_expired', params: {
        ..._base(),
        'direction': direction,
        'legs': legs,
        'will_requote': willRequote,
      });

  /// A combo bet filled on chain.
  static void placed({
    required int legs,
    required double stakeUsd,
    required double payoutUsd,
    required double multiplier,
    required double feeUsd,
    required String route,
    String? entrySource,
  }) {
    TrackingService.markMoneyAction('bet', venue: 'polymarket');
    TrackingService.track('combo_placed', params: {
      ..._base(entrySource: entrySource, route: route),
      'legs': legs,
      'amount_usd': _r(stakeUsd),
      'payout_usd': _r(payoutUsd),
      'multiplier': _r(multiplier),
      'fee_shown_usd': _r(feeUsd),
      'builder_attributed': false,
    });
  }

  /// [action]: place | close | claim. [stage]: approvals | quote | sign |
  /// accept | execution | claim. [errorCategory] from TrackingService.
  static void failed({
    required String action,
    required String stage,
    required String errorCategory,
    int? legs,
    double? amountUsd,
    String? reasonCode,
  }) =>
      TrackingService.track('combo_failed', params: {
        ..._base(),
        'action': action,
        'stage': stage,
        'error_category': errorCategory,
        if (legs != null) 'legs': legs,
        if (amountUsd != null) 'amount_usd': _r(amountUsd),
        if (reasonCode != null) 'reason_code': reasonCode.toLowerCase(),
      });

  static void closeQuoted({
    required int legs,
    required String result,
    double? proceedsUsd,
    double? shares,
    double? feeUsd,
    String? reasonCode,
  }) =>
      TrackingService.track('combo_close_quoted', params: {
        ..._base(),
        'legs': legs,
        'result': result,
        if (proceedsUsd != null) 'amount_usd': _r(proceedsUsd),
        if (shares != null) 'shares': _r(shares, 6),
        if (feeUsd != null) 'fee_shown_usd': _r(feeUsd),
        if (reasonCode != null) 'reason_code': reasonCode.toLowerCase(),
      });

  /// A combo closed early (SELL RFQ filled): exact proceeds.
  static void closed({
    required int legs,
    required double proceedsUsd,
    required double shares,
    required double feeUsd,
    required String route,
  }) =>
      TrackingService.track('combo_closed', params: {
        ..._base(route: route),
        'legs': legs,
        'amount_usd': _r(proceedsUsd),
        'shares': _r(shares, 6),
        'fee_shown_usd': _r(feeUsd),
      });

  /// A settled combo redeemed through the Router. [trigger]: auto | manual.
  static void claimed({
    required int legs,
    required double payoutUsd,
    required double shares,
    required String trigger,
  }) =>
      TrackingService.track('combo_claimed', params: {
        ..._base(),
        'legs': legs,
        'amount_usd': _r(payoutUsd),
        'shares': _r(shares, 6),
        'won': payoutUsd > 0,
        'trigger': trigger,
      });
}
