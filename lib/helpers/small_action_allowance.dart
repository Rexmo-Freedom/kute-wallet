// lib/helpers/small_action_allowance.dart
//
// Small orders skip the Face ID / PIN step-up while the app is unlocked
// (D-11, widened by the founder decision of 2026-11-12: "for orders under
// 50 USD do not do Face ID or PIN checks, both for placing in Investing or
// in Predictions or selling").
//
//   * Local only (founder, 2026-11-12): always on, no remote switch. The
//     threshold is the constant [perActionCapCents] ($50); the backend
//     runtime policy, a missing or stale snapshot or a backend outage never
//     turn it on or off. Analytics never steer this either.
//   * An order qualifies when its USD amount (the stake, the margin, the
//     sell or close proceeds) is strictly UNDER [perActionCapCents].
//   * Session cap: at most [sessionCapCents] approved this way per unlocked
//     session, so an unlocked phone cannot be drained in many small orders.
//     [reset] runs on relock and cold start.
//   * Scope ([inScope]): Predictions buys and sells (market, limit, combos),
//     Investing market and limit orders, perp and spot (open, add, reduce,
//     close, sell), the close sheet's market and limit close, and margin
//     ADDED to an own isolated position. An order may carry a funding leg
//     only when every leg moves the person's own money into the order's own
//     venue (Dollars, Bitcoin via Dollars or straight to the own venue
//     deposit, the other venue's cash); the funding executors re-check the
//     own addresses before anything moves. Never sends, withdrawals, gifts,
//     Swap, Buy Bitcoin, destination or settings changes, leverage changes,
//     margin removal, Pro orders (scale, TWAP, triggers, trailing stops),
//     order edits or the Builder. Leverage above 1x always asks.
//   * Issues `AuthGrant(method: allowance)` bound to the exact order and its
//     funding caps; the executors still `AuthGrants.consume` it. The person
//     still taps Confirm: only the prompt is skipped.

import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/services/one_balance/hyperliquid_venue_funder.dart'
    show kFundUsdLimit, kFundVenueLimit, kFundVenueInvesting;

class SmallActionAllowance {
  static final SmallActionAllowance _instance = SmallActionAllowance();

  /// Test seam for the app-wide allowance.
  static SmallActionAllowance? debugInstance;

  /// App-wide allowance. Tests construct their own or set [debugInstance].
  static SmallActionAllowance get instance => debugInstance ?? _instance;

  /// Per-action threshold: orders strictly under $50 qualify. Local only,
  /// no remote value overrides it.
  static const int perActionCapCents = 5000;

  /// The most the allowance approves per unlocked session, in cents
  /// ($250). The one place to change it.
  static const int sessionCapCents = 25000;

  int _sessionSpentCents = 0;

  /// Cents approved by the allowance since the last [reset].
  int get sessionSpentCents => _sessionSpentCents;

  /// Clears the session total. Call on relock and cold start (after the
  /// session unlocks again the budget starts from zero).
  void reset() => _sessionSpentCents = 0;

  /// Whether [intent] is an order the allowance may approve. Pure scope
  /// check; the amount and the caps are applied by [tryIssue].
  static bool inScope(SensitiveIntent intent) {
    final limits = intent.limits;
    final kind = limits[IntentLimit.orderKind];
    switch (intent.action) {
      case SensitiveAction.pmBet:
        if (intent.venue != IntentVenue.polymarket) return false;
        if (limits[IntentLimit.side] != 'buy') return false;
        if (kind == PmGrants.kindCombo) return !_hasAnyFunding(limits);
        if (kind != null || limits.containsKey(IntentLimit.legs)) {
          return false;
        }
        return _fundingOwnOnly(limits, venue: _Venue.predictions);
      case SensitiveAction.pmSell:
        if (intent.venue != IntentVenue.polymarket) return false;
        if (limits[IntentLimit.side] != 'sell') return false;
        if (_hasAnyFunding(limits)) return false;
        if (kind == PmGrants.kindCombo) return true;
        return kind == null && !limits.containsKey(IntentLimit.legs);
      case SensitiveAction.hlOrder:
        if (intent.venue != IntentVenue.hyperliquid) return false;
        if (limits.containsKey(IntentLimit.legs)) return false;
        final leverage = limits[IntentLimit.leverage];
        if (leverage != null && leverage != 1) return false;
        switch (kind) {
          case HlIntents.kindPerp:
          case HlIntents.kindSpot:
          case HlIntents.kindLimit:
            return _fundingOwnOnly(limits, venue: _Venue.investing);
          case HlIntents.kindClose:
            return limits[IntentLimit.reduceOnly] == true &&
                !_hasAnyFunding(limits);
          case HlIntents.kindMargin:
            return limits['margin_direction'] == 'add' &&
                _fundingOwnOnly(limits, venue: _Venue.investing);
          default:
            return false;
        }
      default:
        return false;
    }
  }

  static const Set<String> _fundingKeys = {
    VenueLimit.fundingUsd,
    VenueLimit.fundingVenue,
    VenueLimit.directLegs,
    VenueLimit.fundBtc,
    kFundUsdLimit,
    kFundVenueLimit,
  };

  static bool _hasAnyFunding(Map<String, Object?> limits) =>
      _fundingKeys.any(limits.containsKey);

  /// Whether [intent] binds a funding leg (for the allowance event).
  static bool hasFundingLeg(SensitiveIntent intent) =>
      _hasAnyFunding(intent.limits);

  /// No funding leg, or every bound leg moves the person's own money into
  /// [venue] for this order: the Dollars move names that venue, the
  /// venue-cash legs go to it, and the Bitcoin leg goes via the own Dollars
  /// (or straight to the own deposit of that venue). Which addresses are
  /// the person's own is re-checked by the funding executors before
  /// anything moves ([BitcoinLegGrants], [DirectLegGrants]).
  static bool _fundingOwnOnly(Map<String, Object?> limits,
      {required _Venue venue}) {
    if (!_hasAnyFunding(limits)) return true;
    final (usdKey, venueKey, venueValue, otherUsd, otherVenue) =
        switch (venue) {
      _Venue.predictions => (
          VenueLimit.fundingUsd,
          VenueLimit.fundingVenue,
          IntentVenue.polymarket,
          kFundUsdLimit,
          kFundVenueLimit,
        ),
      _Venue.investing => (
          kFundUsdLimit,
          kFundVenueLimit,
          kFundVenueInvesting,
          VenueLimit.fundingUsd,
          VenueLimit.fundingVenue,
        ),
    };
    if (limits.containsKey(otherUsd) || limits.containsKey(otherVenue)) {
      return false;
    }
    if (limits.containsKey(usdKey) != limits.containsKey(venueKey)) {
      return false;
    }
    if (limits.containsKey(venueKey) && limits[venueKey] != venueValue) {
      return false;
    }
    if (limits.containsKey(VenueLimit.directLegs)) {
      final direct = limits[VenueLimit.directLegs];
      if (direct is! Map || direct['to'] != venue.code) return false;
    }
    if (limits.containsKey(VenueLimit.fundBtc)) {
      final btc = limits[VenueLimit.fundBtc];
      if (btc is! Map || btc['route'] != BitcoinLegGrants.route) return false;
      final to = btc['to'];
      if (to is! String || to.trim().isEmpty) return false;
      final straight = btc['direct'];
      if (straight != null &&
          (straight is! Map ||
              straight['route'] !=
                  BitcoinLegGrants.directRouteOf(venue.code))) {
        return false;
      }
    }
    return true;
  }

  /// Approves [intent] without a prompt and books [amountUsdCents] against
  /// the session, or returns null when the prompt is required.
  ///
  /// [amountUsdCents] is the order's USD amount (stake, margin, sell or
  /// close proceeds), rounded up. Where the intent itself states a USD
  /// amount it is cross-checked, so a mismatched value cannot slip a
  /// larger order through. [issue] makes the grant (the registry's
  /// transient or autofire store); by default a plain single-use grant.
  AuthGrant? tryIssue(
    SensitiveIntent intent, {
    required int amountUsdCents,
    required StepUpSessionState session,
    AuthGrant Function(SensitiveIntent intent)? issue,
  }) {
    if (!session.isSessionUnlocked) return null;
    if (!inScope(intent)) return null;
    if (amountUsdCents <= 0 || amountUsdCents >= perActionCapCents) {
      return null;
    }
    if (_sessionSpentCents + amountUsdCents > sessionCapCents) return null;
    if (!_amountMatches(intent, amountUsdCents)) return null;
    final AuthGrant grant;
    try {
      grant = issue != null
          ? issue(intent)
          : AuthGrants.issue(intent, method: AuthGrantMethod.allowance);
    } on ArgumentError {
      return null;
    }
    if (grant.method != AuthGrantMethod.allowance) return null;
    _sessionSpentCents += amountUsdCents;
    return grant;
  }

  /// The intent's own USD figures never exceed the stated cents.
  static bool _amountMatches(SensitiveIntent intent, int cents) {
    final micros = BigInt.from(cents) * BigInt.from(10000);
    final limits = intent.limits;
    if (_usdSixDecimals.contains(intent.asset.toUpperCase()) &&
        intent.amountMax > micros) {
      return false;
    }
    if (intent.action == SensitiveAction.hlOrder &&
        limits[VenueLimit.sizeUnit] == 'usd' &&
        intent.amountMax > micros) {
      return false;
    }
    if (intent.action == SensitiveAction.pmSell) {
      // A combo close binds the least it must pay out.
      final minReceive = limits[IntentLimit.minReceive];
      if (minReceive is BigInt && minReceive > micros) return false;
      // A plain sell binds its shares (1e8) and its lowest price: it pays
      // at least shares x price, which must fit the stated cents.
      if (limits[IntentLimit.orderKind] == null) {
        final worst = limits[IntentLimit.limitPrice];
        if (worst is! num || !worst.isFinite || worst < 0) return false;
        final floorCents = intent.amountMax.toDouble() / 1e8 * worst * 100;
        if (floorCents > cents + 1e-6) return false;
      }
    }
    return true;
  }

  static const Set<String> _usdSixDecimals = {'USDC', 'USDC.E', 'PUSD'};
}

enum _Venue {
  predictions('predictions'),
  investing('investing');

  const _Venue(this.code);

  /// The `VenueCashDestination` / `OneBalanceVenue` name.
  final String code;
}
