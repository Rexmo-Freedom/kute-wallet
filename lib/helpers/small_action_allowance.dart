// lib/helpers/small_action_allowance.dart
//
// D-11 small-bet step-up skip (Wallet Hardening Phase 1b, spec 4.1).
//
//   * Off by default. The per-action cap in cents is the backend runtime
//     policy's `security.smallActionAllowanceCents`, read from the current
//     fresh capabilities snapshot; no snapshot, a stale snapshot, a backend
//     outage or a value <= 0 means off. Analytics never steer this.
//   * Client clamps: at most 500 cents per action and 2,500 cents per
//     unlocked session. [reset] must be called on relock and cold start.
//   * Scope: Polymarket buys (`pmBet`) and Hyperliquid spot buys
//     (`hlOrder` with orderKind spot and side buy), paid from the
//     existing venue balance with no funding leg. Never withdrawals,
//     sends or destination changes.
//   * Issues `AuthGrant(method: allowance)`, which still goes through
//     `AuthGrants.consume`.

import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

/// Reads the current fresh runtime capabilities snapshot, or null when the
/// app has none it may act on.
typedef SnapshotReader = RuntimeCapabilities? Function();

RuntimeCapabilities? _currentSnapshot() =>
    RuntimeCapabilitiesService.instance.snapshot;

class SmallActionAllowance {
  SmallActionAllowance({SnapshotReader? readSnapshot})
      : _readSnapshot = readSnapshot ?? _currentSnapshot;

  /// App-wide allowance. Tests construct their own.
  static final SmallActionAllowance instance = SmallActionAllowance();

  static const int maxPerActionCents = 500;
  static const int maxPerSessionCents = 2500;

  final SnapshotReader _readSnapshot;

  int _sessionSpentCents = 0;

  /// Effective per-action cap after the client clamp, read from the
  /// current fresh runtime policy on every call. 0 means off.
  int get perActionCapCents {
    try {
      return clampCents(_readSnapshot()?.smallActionAllowanceCents);
    } catch (_) {
      return 0;
    }
  }

  bool get enabled => perActionCapCents > 0;

  /// Cents approved by the allowance since the last [reset].
  int get sessionSpentCents => _sessionSpentCents;

  /// Clamps a published cap to 0..[maxPerActionCents]; null or <= 0 is off.
  static int clampCents(int? cents) {
    if (cents == null || cents <= 0) return 0;
    return cents > maxPerActionCents ? maxPerActionCents : cents;
  }

  /// Clears the session total. Call on relock and cold start (after the
  /// session unlocks again the budget starts from zero).
  void reset() => _sessionSpentCents = 0;

  /// Whether [intent] is inside the D-11 scope. Pure scope check; caps
  /// are applied by [tryIssue].
  static bool inScope(
    SensitiveIntent intent, {
    required bool paidFromVenueBalance,
    required bool hasFundingLeg,
  }) {
    if (!paidFromVenueBalance || hasFundingLeg) return false;
    if (intent.limits.containsKey(IntentLimit.legs)) return false;
    switch (intent.action) {
      case SensitiveAction.pmBet:
        return intent.venue == 'polymarket';
      case SensitiveAction.hlOrder:
        final kind = intent.limits[IntentLimit.orderKind];
        final side = intent.limits[IntentLimit.side];
        return intent.venue == 'hyperliquid' &&
            kind is String &&
            kind.toLowerCase() == 'spot' &&
            side is String &&
            side.toLowerCase() == 'buy';
      default:
        return false;
    }
  }

  /// Issues an allowance grant and books [amountUsdCents] against the
  /// session, or returns null when the prompt is required.
  ///
  /// [amountUsdCents] is the USD value of `intent.amountMax`. For
  /// 6-decimal USD assets (USDC, USDC.e, PUSD) the base units are
  /// cross-checked so a mismatched value cannot slip a larger bet
  /// through.
  AuthGrant? tryIssue(
    SensitiveIntent intent, {
    required int amountUsdCents,
    required bool paidFromVenueBalance,
    required bool hasFundingLeg,
    required StepUpSessionState session,
  }) {
    final cap = perActionCapCents;
    if (cap <= 0 || !session.isSessionUnlocked) return null;
    if (!inScope(intent,
        paidFromVenueBalance: paidFromVenueBalance,
        hasFundingLeg: hasFundingLeg)) {
      return null;
    }
    if (amountUsdCents <= 0) return null;
    if (amountUsdCents > cap) return null;
    if (_sessionSpentCents + amountUsdCents > maxPerSessionCents) return null;
    if (_usdSixDecimals.contains(intent.asset.toUpperCase()) &&
        intent.amountMax > BigInt.from(amountUsdCents) * BigInt.from(10000)) {
      return null;
    }
    final grant = AuthGrants.issue(intent, method: AuthGrantMethod.allowance);
    _sessionSpentCents += amountUsdCents;
    return grant;
  }

  static const Set<String> _usdSixDecimals = {'USDC', 'USDC.E', 'PUSD'};
}
