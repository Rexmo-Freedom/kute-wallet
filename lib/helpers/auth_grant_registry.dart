// lib/helpers/auth_grant_registry.dart
//
// In-memory grant lifetimes (Wallet Hardening Phase 1b, spec 4.1
// "Lifetime" and "Autofire"). Nothing here is persisted: a cold start
// drops every grant, so a queued intent without a grant never fires and
// must be confirmed again (D-10).
//
//   * transient grants: 60 s default, single use;
//   * seed reveal: one reusable grant per wallet, revoked when the
//     screen that owns it is disposed;
//   * autofire: 30 min, keyed by pending intent id, consumed only
//     while the session is unlocked.

import 'dart:async';

import 'package:kute/helpers/auth_grant.dart';

/// Thrown by [AuthGrantRegistry.consumeAutofire] when the session is
/// locked. The grant is NOT consumed; the intent waits for unlock.
class GrantSessionLocked implements Exception {
  const GrantSessionLocked();
  @override
  String toString() => 'GrantSessionLocked';
}

/// Thrown when no grant exists for an autofire intent (for example after
/// a restart). The intent must never fire; ask the user to confirm again.
class GrantMissing implements Exception {
  const GrantMissing();
  @override
  String toString() => 'GrantMissing';
}

/// Called once per autofire grant that expired unconsumed. The caller
/// cancels the intent and emits `pending_intent_expired{venue}`.
typedef AutofireExpiredCallback = void Function(
    String intentId, String venue);

class AuthGrantRegistry {
  AuthGrantRegistry({DateTime Function()? clock})
      : _clock = clock ?? (() => AuthGrants.clock());

  /// App-wide registry. Tests construct their own.
  static final AuthGrantRegistry instance = AuthGrantRegistry();

  final DateTime Function() _clock;

  final List<AuthGrant> _transient = [];
  final Map<String, AuthGrant> _seedReveal = {};
  final Map<String, AuthGrant> _autofire = {};
  final Map<String, Timer> _autofireTimers = {};
  final List<AutofireExpiredCallback> _expiredListeners = [];

  // ── Transient (60 s) ───────────────────────────────────────────────

  /// Issues a single-use grant with `intent.ttl` (60 s by default).
  AuthGrant issue(SensitiveIntent intent, {required AuthGrantMethod method}) {
    final now = _clock();
    _transient.removeWhere((g) => g.consumed || g.revoked || g.isExpiredAt(now));
    final grant = AuthGrants.issue(intent, method: method, now: now);
    _transient.add(grant);
    return grant;
  }

  // ── Seed reveal (per wallet, screen scoped) ────────────────────────

  /// Issues the reusable seed reveal grant for `intent.walletId`,
  /// replacing (and revoking) any earlier one for that wallet.
  AuthGrant issueSeedReveal(SensitiveIntent intent,
      {required AuthGrantMethod method}) {
    if (intent.action != SensitiveAction.seedReveal) {
      throw ArgumentError.value(intent.action, 'action', 'not seedReveal');
    }
    final grant = AuthGrants.issue(
      intent.copyWith(ttl: AuthGrants.screenScopedTtl),
      method: method,
      singleUse: false,
      now: _clock(),
    );
    _seedReveal.remove(intent.walletId)?.revoke();
    _seedReveal[intent.walletId] = grant;
    return grant;
  }

  /// The live seed reveal grant for [walletId], or null.
  AuthGrant? seedRevealGrantFor(String walletId) {
    final g = _seedReveal[walletId];
    if (g == null) return null;
    if (g.revoked || g.isExpiredAt(_clock())) {
      _seedReveal.remove(walletId);
      return null;
    }
    return g;
  }

  /// Revokes [grant] when its owning screen is disposed. Only removes the
  /// registry entry if it is still that exact grant, so one screen's
  /// dispose never kills a grant another screen holds.
  void revokeSeedReveal(AuthGrant grant) {
    grant.revoke();
    if (identical(_seedReveal[grant.walletId], grant)) {
      _seedReveal.remove(grant.walletId);
    }
  }

  // ── Autofire (30 min, D-10) ────────────────────────────────────────

  /// Stores the confirm-time grant for a pending intent. The intent must
  /// bind market (destination), side, amountMax, maxSlippageBps and,
  /// for Hyperliquid, leverage. The ttl is forced to 30 min.
  AuthGrant issueAutofire(String intentId, SensitiveIntent intent,
      {required AuthGrantMethod method}) {
    if (intent.action != SensitiveAction.pmBet &&
        intent.action != SensitiveAction.hlOrder) {
      throw ArgumentError.value(intent.action, 'action', 'not autofire');
    }
    _dropAutofire(intentId, revoke: true);
    final grant = AuthGrants.issue(
      intent.copyWith(ttl: AuthGrants.autofireTtl),
      method: method,
      now: _clock(),
    );
    _autofire[intentId] = grant;
    _autofireTimers[intentId] = Timer(AuthGrants.autofireTtl, sweepExpired);
    return grant;
  }

  /// Whether a live, unconsumed autofire grant exists for [intentId].
  bool hasAutofireGrant(String intentId) {
    sweepExpired();
    final g = _autofire[intentId];
    return g != null && !g.consumed && !g.revoked;
  }

  /// Consumes the autofire grant for [intentId] against [actual].
  ///
  /// Throws [GrantSessionLocked] (grant kept) when locked,
  /// [GrantMissing] when none exists, and otherwise whatever
  /// [AuthGrants.consume] throws. A consumed, expired, revoked or
  /// drifted grant is dropped; the caller cancels the intent and asks the
  /// user to confirm again.
  AuthGrant consumeAutofire(
    String intentId,
    SensitiveIntent actual, {
    required StepUpSessionState session,
  }) {
    sweepExpired();
    final grant = _autofire[intentId];
    if (grant == null) throw const GrantMissing();
    if (!session.isSessionUnlocked) throw const GrantSessionLocked();
    try {
      AuthGrants.consume(grant, actual, now: _clock());
    } finally {
      _dropAutofire(intentId, revoke: false);
    }
    return grant;
  }

  /// Cancels the grant for an intent the user or app cancelled.
  void cancelAutofire(String intentId) => _dropAutofire(intentId, revoke: true);

  void addAutofireExpiredListener(AutofireExpiredCallback cb) =>
      _expiredListeners.add(cb);

  void removeAutofireExpiredListener(AutofireExpiredCallback cb) =>
      _expiredListeners.remove(cb);

  /// Drops expired autofire grants and notifies listeners once each.
  /// Runs on each grant's timer and before every autofire lookup.
  void sweepExpired() {
    final now = _clock();
    final expired = <MapEntry<String, AuthGrant>>[
      for (final e in _autofire.entries)
        if (e.value.isExpiredAt(now)) e,
    ];
    for (final e in expired) {
      _dropAutofire(e.key, revoke: true);
      for (final cb in List.of(_expiredListeners)) {
        cb(e.key, e.value.venue);
      }
    }
  }

  void _dropAutofire(String intentId, {required bool revoke}) {
    _autofireTimers.remove(intentId)?.cancel();
    final g = _autofire.remove(intentId);
    if (revoke) g?.revoke();
  }

  // ── Bulk ───────────────────────────────────────────────────────────

  /// Revokes transient and seed reveal grants. Autofire grants survive
  /// by default: D-10 keeps them for 30 min and they only fire while
  /// unlocked. Whether relock calls this is a wiring decision.
  void revokeAll({bool includeAutofire = false}) {
    for (final g in _transient) {
      g.revoke();
    }
    _transient.clear();
    for (final g in _seedReveal.values) {
      g.revoke();
    }
    _seedReveal.clear();
    if (includeAutofire) {
      for (final id in List.of(_autofire.keys)) {
        _dropAutofire(id, revoke: true);
      }
    }
  }
}
