// lib/helpers/require_fresh_auth.dart
//
// Step-up authentication v2 (Wallet Hardening Phase 1b, spec 4.1).
//
// Actions that move funds out or reveal key material ALWAYS demand a fresh
// proof of presence. The unlocked session only proves someone unlocked the
// app once, not that the person holding the phone now is the owner, so
// browsing rides the session and spending never does.
//
// [requireFreshAuthGrant] returns an [AuthGrant] bound to the
// [SensitiveIntent] the user reviewed. The executor re-derives the intent
// it is about to submit and calls `AuthGrants.check` on laddered retries
// and `AuthGrants.consume` on the final submit. Drift throws
// `ReauthRequired`; callers then use [showStepUpReviewAgain] (C8).
//
// Prompt policy (D-D, D-14):
//   * `biometricOnly: true` always, so the phone passcode never approves.
//   * A cancelled, failed or unavailable Face ID or fingerprint prompt falls
//     back to the Kute PIN sheet, never to a denial. Lockout and
//     unavailable codes show the C7 subtitle.
//   * iOS: when the biometry domain state hash differs from the stored one
//     (a face or finger was added), the Kute PIN comes first, then the
//     biometric. Only a biometric success stores the new hash.
//   * Kute biometrics off, nothing enrolled, or no passcode: the PIN sheet.
//   * A dismissed PIN sheet denies. Phase 1a makes the sheet counted: at
//     the threshold it locks the app (D-13), which also denies.
//
// The D-11 small-action allowance is tried before any prompt when the
// caller passes a [SmallActionContext].
//
// The Polymarket short-round fast-bet window (`FastBetWindow`) is tried
// first when the caller passes an eligible [FastBetRequest]; a prompt
// that approves such an order opens a fresh window.
//
// Privacy: events carry the action type, method, reason class and a
// bucketed USD value only. Never the digest, the bound intent, the
// canonical JSON, amounts or addresses.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/auth_grant_registry.dart';
import 'package:kute/helpers/biometry_domain_state.dart';
import 'package:kute/helpers/privacy_cover_bridge.dart';
import 'package:kute/helpers/small_action_allowance.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/auth_provider.dart'
    show appLockedProvider, sessionAuthProvider, sessionUnlockedProvider;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/pin_gate_sheet.dart';
import 'package:kute/screens/shared/step_up_review_again_sheet.dart';
import 'package:kute/services/polymarket/fast_bet_window.dart';
import 'package:kute/services/tracking_service.dart';

/// Inputs for the D-11 small-action allowance. Only Polymarket buys and
/// Hyperliquid spot buys paid from the venue balance ever qualify; the
/// allowance re-checks the scope itself.
class SmallActionContext {
  const SmallActionContext({
    required this.amountUsdCents,
    required this.paidFromVenueBalance,
    required this.hasFundingLeg,
  });

  /// USD value of `intent.amountMax`, in cents.
  final int amountUsdCents;
  final bool paidFromVenueBalance;
  final bool hasFundingLeg;
}

/// Session state for the allowance and autofire grants, backed by the
/// Phase 1a session (`sessionUnlockedProvider`: a verified unlock and the
/// lock overlay down). Read live on every access, so a grant held across a
/// relock sees the lock.
final stepUpSessionStateProvider = Provider<StepUpSessionState>(
  (ref) => _RiverpodStepUpSession(ref),
);

class _RiverpodStepUpSession implements StepUpSessionState {
  const _RiverpodStepUpSession(this._ref);

  final Ref _ref;

  @override
  bool get isSessionUnlocked {
    try {
      return _ref.read(sessionUnlockedProvider);
    } catch (_) {
      return false;
    }
  }
}

/// Step-up v2. Returns a grant bound to [intent], or null when the user
/// declined. [reason] names the action (the `stepUpReason*` copy) and is
/// shown in the OS prompt and as the PIN sheet title. [amountUsd] is only
/// ever bucketed for events.
///
/// Seed reveal intents get the screen-scoped reusable grant
/// (`AuthGrantRegistry.issueSeedReveal`); the owning screen revokes it on
/// dispose.
///
/// [autofireIntentId] stores the grant as the 30 min autofire grant for
/// that pending intent (D-10, `AuthGrantRegistry.issueAutofire`) instead
/// of a 60 s transient one. The allowance is never used for autofire.
Future<AuthGrant?> requireFreshAuthGrant(
  BuildContext context,
  WidgetRef ref, {
  required SensitiveIntent intent,
  required String reason,
  double? amountUsd,
  SmallActionContext? smallAction,
  String? autofireIntentId,
  FastBetRequest? fastBet,
}) async {
  final actionType = intent.action.name;

  // The short-round fast-bet window: a prompt in the last 10 minutes
  // already approved short-round orders here (see `FastBetWindow`).
  final fast = autofireIntentId == null && (fastBet?.eligible ?? false)
      ? fastBet
      : null;
  if (fast != null) {
    final windowGrant = FastBetWindow.instance.tryIssue(
      intent,
      request: fast,
      amountUsdCents: smallAction?.amountUsdCents ?? 0,
      session: _readSession(ref),
      sessionUnlocked: _readUnlocked(ref),
    );
    if (windowGrant != null) return windowGrant;
  }

  if (smallAction != null && autofireIntentId == null) {
    final allowed = SmallActionAllowance.instance.tryIssue(
      intent,
      amountUsdCents: smallAction.amountUsdCents,
      paidFromVenueBalance: smallAction.paidFromVenueBalance,
      hasFundingLeg: smallAction.hasFundingLeg,
      session: ref.read(stepUpSessionStateProvider),
    );
    if (allowed != null) {
      TrackingService.track('step_up_small_action_allowed', params: {
        'action_type': actionType,
        'amount_bucket':
            TrackingService.usdBucket(smallAction.amountUsdCents / 100),
        'session_bucket': TrackingService.usdBucket(
            SmallActionAllowance.instance.sessionSpentCents / 100),
      });
      return allowed;
    }
  }

  final method = await _runPromptPolicy(
    context,
    ref,
    reason: reason,
    actionType: actionType,
  );
  if (method == null) return null;

  final AuthGrant grant;
  try {
    if (autofireIntentId != null) {
      grant = AuthGrantRegistry.instance
          .issueAutofire(autofireIntentId, intent, method: method);
    } else if (intent.action == SensitiveAction.seedReveal) {
      grant =
          AuthGrantRegistry.instance.issueSeedReveal(intent, method: method);
    } else {
      grant = AuthGrantRegistry.instance.issue(intent, method: method);
    }
  } on ArgumentError {
    // A malformed intent is a programming error. Never approve it.
    _trackDenied(actionType, 'invalid_intent');
    return null;
  }
  _trackAuth(method, actionType: actionType, amountUsd: amountUsd);
  if (fast != null) {
    FastBetWindow.instance.open(
      intent,
      request: fast,
      method: method,
      session: _readSession(ref),
      sessionUnlocked: _readUnlocked(ref),
    );
  }
  return grant;
}

/// The unlocked session object (compared by identity), or null.
Object? _readSession(WidgetRef ref) {
  try {
    return ref.read(sessionAuthProvider);
  } catch (_) {
    return null;
  }
}

bool _readUnlocked(WidgetRef ref) {
  try {
    return ref.read(sessionUnlockedProvider);
  } catch (_) {
    return false;
  }
}

/// C8. What is about to be submitted drifted from what the user approved:
/// emits `step_up_reauth_required` and shows "Review again". Nothing was
/// sent. Pass `ReauthRequired.primaryFieldClass` as [field].
Future<void> showStepUpReviewAgain(
  BuildContext context, {
  required SensitiveAction action,
  required DriftField field,
}) async {
  TrackingService.track('step_up_reauth_required', params: {
    'action_type': action.name,
    'field_class': field.name,
  });
  if (!context.mounted) return;
  await StepUpReviewAgainSheet.show(context, actionType: action.name);
}

/// The seed reveal intent for one wallet. Nothing but the wallet is bound:
/// the grant only says the user freshly approved showing that wallet's
/// words on this screen.
SensitiveIntent seedRevealIntent(String walletId) => SensitiveIntent(
      action: SensitiveAction.seedReveal,
      walletId: walletId,
      venue: 'local',
      asset: 'SEED',
      amountMax: BigInt.zero,
    );

/// Seed reveal step-up (spec 4.1 Keys). Reuses the live screen-scoped grant
/// for [walletId] when one exists (`seedRevealGrantFor`), otherwise prompts
/// with the `stepUpReasonRevealSeed` copy. The screen that receives the
/// grant calls `AuthGrantRegistry.instance.revokeSeedReveal` on dispose.
/// Returns null when the user declined.
Future<AuthGrant?> requireSeedRevealGrant(
  BuildContext context,
  WidgetRef ref, {
  required String walletId,
}) async {
  final live = AuthGrantRegistry.instance.seedRevealGrantFor(walletId);
  if (live != null) {
    try {
      AuthGrants.check(live, seedRevealIntent(walletId));
      return live;
    } on AuthGrantException {
      // Stale: prompt again below.
    }
  }
  if (!context.mounted) return null;
  return requireFreshAuthGrant(
    context,
    ref,
    intent: seedRevealIntent(walletId),
    reason: context.l10n.stepUpReasonRevealSeed,
  );
}

/// True when [grant] still approves revealing [walletId]'s words.
bool seedRevealGrantCovers(AuthGrant? grant, String walletId) {
  if (grant == null) return false;
  try {
    AuthGrants.check(grant, seedRevealIntent(walletId));
    return true;
  } on AuthGrantException {
    return false;
  }
}

/// The wallet removal intent (D-9). Bound to the wallet only; the grant
/// is consumed right before the wallet is removed.
/// Switching the shown wallet: the person proves it is them before another
/// account's balances and actions come up.
SensitiveIntent walletSwitchIntent(String walletId) => SensitiveIntent(
      action: SensitiveAction.walletSwitch,
      walletId: walletId,
      venue: 'local',
      asset: 'WALLET',
      amountMax: BigInt.zero,
    );

SensitiveIntent walletRemoveIntent(String walletId) => SensitiveIntent(
      action: SensitiveAction.walletRemove,
      walletId: walletId,
      venue: 'local',
      asset: 'WALLET',
      amountMax: BigInt.zero,
    );

/// The biometrics toggle intent (D-9). App wide, so it binds the target
/// state instead of a wallet.
SensitiveIntent biometricsToggleIntent({required bool enable}) =>
    SensitiveIntent(
      action: SensitiveAction.biometricsToggle,
      walletId: 'app',
      venue: 'local',
      asset: 'BIOMETRICS',
      amountMax: BigInt.zero,
      limits: {'enabled': enable},
    );

/// Step-up for a local one-shot action (wallet removal, the biometrics
/// toggle): prompts for [intent] and consumes the grant at once, right
/// before the caller acts. True only when the user approved.
Future<bool> approveLocalAction(
  BuildContext context,
  WidgetRef ref, {
  required SensitiveIntent intent,
  required String reason,
}) async {
  final grant = await requireFreshAuthGrant(
    context,
    ref,
    intent: intent,
    reason: reason,
  );
  if (grant == null) return false;
  try {
    AuthGrants.consume(grant, intent);
    return true;
  } on AuthGrantException catch (e) {
    if (context.mounted) {
      await handleGrantFailure(context, e, action: intent.action);
    }
    return false;
  }
}

/// For UI callers of executors that take a grant. When [error] is a grant
/// failure thrown by the executor, handles it and returns true: drift shows
/// C8 (`ReauthRequired`), an expired, revoked or used grant emits
/// `step_up_auth_denied` quietly. Returns false for any other error, which
/// the caller keeps handling as before. Nothing was submitted in either
/// grant case.
Future<bool> handleGrantFailure(
  BuildContext context,
  Object error, {
  required SensitiveAction action,
}) async {
  if (error is ReauthRequired && context.mounted) {
    await showStepUpReviewAgain(context,
        action: action, field: error.primaryFieldClass);
    return true;
  }
  return trackGrantFailure(error, action: action);
}

/// The events [handleGrantFailure] emits, without showing anything, for
/// places that cannot show a sheet (a Builder leg row, an autofire, a
/// disposed sheet). Returns true when [error] was a grant failure; nothing
/// was signed then.
bool trackGrantFailure(Object error, {required SensitiveAction action}) {
  if (error is ReauthRequired) {
    TrackingService.track('step_up_reauth_required', params: {
      'action_type': action.name,
      'field_class': error.primaryFieldClass.name,
    });
    return true;
  }
  if (error is AuthGrantException) {
    _trackDenied(
      action.name,
      switch (error) {
        GrantRevoked() => 'grant_revoked',
        GrantExpired() => 'grant_expired',
        GrantConsumed() => 'grant_consumed',
        ReauthRequired() => 'reauth_required',
      },
    );
    return true;
  }
  return false;
}

// ── Prompt policy ────────────────────────────────────────────────────

enum _BioResult {
  approved,
  failed,
  cancelled,
  lockout,
  unavailable,
  noCredentials,
  error,
}

/// Returns how the user approved, or null when denied. Emits the
/// fallback and denial events; the caller emits `step_up_auth`.
Future<AuthGrantMethod?> _runPromptPolicy(
  BuildContext context,
  WidgetRef ref, {
  required String reason,
  required String? actionType,
}) async {
  final l10n = context.l10n;
  final biometricsOn = ref.read(settingsProvider).biometricsEnabled;
  final localAuth = LocalAuthentication();

  // Same enrolled-not-just-hardware gate as open_pin
  // (`canCheckBiometrics` lies on iOS when Face ID is disabled).
  var biometricUsable = false;
  String? skippedReasonClass;
  if (biometricsOn) {
    try {
      final supported = await localAuth.isDeviceSupported();
      final enrolled = supported
          ? await localAuth.getAvailableBiometrics()
          : const <BiometricType>[];
      biometricUsable = supported && enrolled.isNotEmpty;
      if (!biometricUsable) {
        skippedReasonClass = supported ? 'not_enrolled' : 'no_hardware';
      }
    } catch (_) {
      skippedReasonClass = 'error';
    }
  }

  // D-14 (iOS). Unknown on either side means no change is detected.
  String? currentHash;
  String? changedHash;
  if (biometricUsable) {
    currentHash = await BiometryDomainState.currentHash();
    if (currentHash != null) {
      final stored = await BiometryDomainState.storedHash();
      if (stored != null && stored != currentHash) changedHash = currentHash;
    }
  }

  if (changedHash != null) {
    BiometryDomainState.reportChangedOnce(changedHash);
    _trackPinFallback(actionType, 'bio_domain_changed');
    if (!context.mounted) {
      _trackDenied(actionType, 'unmounted');
      return null;
    }
    final pinOk = await _kutePin(
      context,
      ref,
      title: reason,
      subtitle: l10n.stepUpBiometricChanged,
      actionType: actionType,
    );
    if (!pinOk) return null;
    final second = await _authenticateBiometric(localAuth, reason);
    if (second == _BioResult.approved) {
      await BiometryDomainState.store(changedHash);
      return AuthGrantMethod.pinThenBiometric;
    }
    // Approved on the PIN. The stored hash stays old, so the next step-up
    // asks for the PIN first again.
    return AuthGrantMethod.pin;
  }

  String? subtitle;
  if (biometricUsable) {
    final result = await _authenticateBiometric(localAuth, reason);
    if (result == _BioResult.approved) {
      if (currentHash != null) await BiometryDomainState.store(currentHash);
      return AuthGrantMethod.biometric;
    }
    if (result == _BioResult.lockout || result == _BioResult.unavailable) {
      subtitle = Platform.isAndroid
          ? l10n.stepUpBiometricUnavailableAndroid
          : l10n.stepUpBiometricUnavailable;
    }
    _trackPinFallback(actionType, _reasonClass(result));
  } else if (skippedReasonClass != null) {
    _trackPinFallback(actionType, skippedReasonClass);
  }

  if (!context.mounted) {
    _trackDenied(actionType, 'unmounted');
    return null;
  }
  final pinOk = await _kutePin(
    context,
    ref,
    title: reason,
    subtitle: subtitle,
    actionType: actionType,
  );
  return pinOk ? AuthGrantMethod.pin : null;
}

Future<_BioResult> _authenticateBiometric(
  LocalAuthentication localAuth,
  String reason,
) async {
  try {
    // Step-up prompts fire over a live confirmation sheet. Scoping the
    // call keeps the app-switcher privacy cover down for the scan, so
    // the user approves against the screen they were on instead of a
    // blank cover thrown up by the `inactive` the prompt itself causes.
    final ok = await runBiometricPrompt(
      () => localAuth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        sensitiveTransaction: true,
        persistAcrossBackgrounding: true,
      ),
    );
    return ok ? _BioResult.approved : _BioResult.failed;
  } on LocalAuthException catch (e) {
    switch (e.code) {
      case LocalAuthExceptionCode.userCanceled:
      case LocalAuthExceptionCode.systemCanceled:
      case LocalAuthExceptionCode.timeout:
      case LocalAuthExceptionCode.userRequestedFallback:
        return _BioResult.cancelled;
      case LocalAuthExceptionCode.biometricLockout:
      case LocalAuthExceptionCode.temporaryLockout:
        return _BioResult.lockout;
      case LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable:
      case LocalAuthExceptionCode.noBiometricsEnrolled:
      case LocalAuthExceptionCode.noBiometricHardware:
        return _BioResult.unavailable;
      case LocalAuthExceptionCode.noCredentialsSet:
        return _BioResult.noCredentials;
      default:
        return _BioResult.error;
    }
  } catch (_) {
    return _BioResult.error;
  }
}

String _reasonClass(_BioResult result) => switch (result) {
      _BioResult.approved => 'approved',
      _BioResult.failed => 'failed',
      _BioResult.cancelled => 'cancelled',
      _BioResult.lockout => 'lockout',
      _BioResult.unavailable => 'unavailable',
      _BioResult.noCredentials => 'no_credentials',
      _BioResult.error => 'error',
    };

/// The Kute PIN sheet. Phase 1a makes it counted; at the D-13 threshold it
/// locks the app and dismisses itself, which reads here as a denial.
Future<bool> _kutePin(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  required String? subtitle,
  required String? actionType,
}) async {
  var verified = false;
  var cancelled = false;
  await PinGateSheet.show(
    context,
    title: title,
    subtitle: subtitle,
    onVerified: () => verified = true,
    analyticsSurface: 'step_up',
    onCancelled: () => cancelled = true,
  );
  if (verified) return true;
  var locked = false;
  if (context.mounted) {
    try {
      locked = ref.read(appLockedProvider);
    } catch (_) {}
  }
  _trackDenied(
    actionType,
    locked
        ? 'locked'
        : cancelled
            ? 'pin_cancelled'
            : 'dismissed',
  );
  return false;
}

// ── Events ───────────────────────────────────────────────────────────

void _trackAuth(
  AuthGrantMethod method, {
  required String? actionType,
  required double? amountUsd,
}) {
  TrackingService.track('step_up_auth', params: {
    'method': method.name,
    if (actionType != null) 'action_type': actionType,
    if (amountUsd != null)
      'amount_bucket': TrackingService.usdBucket(amountUsd),
  });
}

void _trackDenied(String? actionType, String reason) {
  TrackingService.track('step_up_auth_denied', params: {
    if (actionType != null) 'action_type': actionType,
    'reason': reason,
  });
}

void _trackPinFallback(String? actionType, String reasonClass) {
  TrackingService.track('step_up_pin_fallback', params: {
    if (actionType != null) 'action_type': actionType,
    'reason_class': reasonClass,
  });
}
