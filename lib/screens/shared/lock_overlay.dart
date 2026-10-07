// lib/screens/shared/lock_overlay.dart
//
// In-place app lock. Rendered as a sibling ABOVE the router's active
// route (see app_widget.dart's overlay Stack), engaged by flipping
// [appLockedProvider] — never by navigation. That is the whole point:
// the old relock (`router.go('/splash')` → PIN → `go('/home')`)
// destroyed the navigation stack, dumping the user on home after every
// background gap. This overlay covers the live stack; unlocking simply
// removes the cover and the user resumes the exact screen, sheet or
// flow they left.
//
// Security notes:
//   * Failed attempts + lockout persist through the SAME AuthModel
//     counters the cold-start PIN screen uses, so the overlay is not a
//     softer brute-force target; max attempts wipes exactly like
//     open_pin.
//   * `sessionAuthProvider` is deliberately NOT cleared while locked.
//     Automatic signers check `sessionUnlockedProvider`, which is false
//     while this overlay is up, so nothing resolves a seed behind it;
//     providers built behind the lock build again once it unlocks.
//   * Money-moving actions require fresh auth regardless of this
//     session lock (see requireFreshAuthGrant). Each lock engagement
//     resets the small-action allowance budget, and a biometric unlock
//     stores the iOS biometry domain state (D-14).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:local_auth/local_auth.dart';

import 'package:kute/screens/shared/kute_pin_scaffold.dart';
import 'package:kute/services/secure/storage_bootstrap.dart';
import 'package:kute/helpers/pin_attempt_guard.dart';
import 'package:kute/helpers/privacy_cover_bridge.dart';
import 'package:kute/helpers/session_auth.dart';
import 'package:kute/helpers/session_unlock.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/bitcoin_config_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/restart_widget.dart';
import 'package:kute/screens/shared/custom_keypad.dart';
import 'package:kute/services/background_sync_service.dart';
import 'package:kute/services/secure/biometric_pin_policy.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

class LockOverlay extends ConsumerStatefulWidget {
  const LockOverlay({super.key});

  @override
  ConsumerState<LockOverlay> createState() => _LockOverlayState();
}

class _LockOverlayState extends ConsumerState<LockOverlay>
    with SingleTickerProviderStateMixin {
  final LocalAuthentication _localAuth = LocalAuthentication();
  String _pin = '';
  bool _verifying = false;
  bool _biometricInFlight = false;
  bool _lockedOut = false;
  int _lockoutRemaining = 0;
  Future<V1Dependency>? _dependency;

  Future<V1Dependency> _v1Dependency() =>
      _dependency ??= evaluateV1Dependency(ref);

  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );
  late final Animation<double> _shakeAnim = Tween<double>(begin: 0, end: 24)
      .chain(CurveTween(curve: Curves.elasticIn))
      .animate(_shake)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _shake.reverse();
    });

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  /// Fired once per lock engagement (see the ref.listen in build):
  /// restore the persisted attempt/lockout state, then auto-prompt
  /// biometrics exactly like the cold-start PIN screen does.
  Future<void> _onLockEngaged() async {
    _pin = '';
    // Once per lock engagement (the listener in build fires on the
    // false → true edge only), so never per rebuild.
    TrackingService.track('lock_overlay_shown', params: {
      'biometrics_enabled': ref.read(settingsProvider).biometricsEnabled,
      // The background grace expiring, or a confirmation sheet that hit
      // its wrong-PIN threshold.
      'reason': ref.read(pinSheetLockedProvider)
          ? 'pin_sheet_lockout'
          : 'auto_lock',
    });
    resetStepUpSession();
    final guard = PinAttemptGuard(AuthModel());
    try {
      final remaining = await guard.lockoutRemaining();
      if (remaining > Duration.zero) {
        _startLockoutCountdown(DateTime.now().add(remaining));
      }
    } catch (_) {
      // An unreadable counter never blocks the keypad or counts.
    }
    if (mounted) setState(() {});
    _dependency = null;
    _tryBiometrics(auto: true);
  }

  void _startLockoutCountdown(DateTime until) {
    _lockedOut = true;
    void tick() {
      if (!mounted || !ref.read(appLockedProvider)) return;
      final remaining = until.difference(DateTime.now()).inSeconds;
      if (remaining <= 0) {
        setState(() => _lockedOut = false);
        return;
      }
      setState(() => _lockoutRemaining = remaining);
      Future.delayed(const Duration(seconds: 1), tick);
    }

    tick();
  }

  Future<void> _tryBiometrics({bool auto = false}) async {
    if (_biometricInFlight || _lockedOut) return;
    if (!ref.read(settingsProvider).biometricsEnabled) return;
    _biometricInFlight = true;
    try {
      final dependency = await _v1Dependency();
      // A wallet that still needs the PIN, with no stored copy for
      // biometrics: the PIN is typed instead of prompting first.
      if (auto &&
          dependency.exists &&
          dependency.biometricPin != StoredPinState.present) {
        return;
      }
      // Gate on ENROLLED biometrics, not just hardware presence —
      // same rule as open_pin (`canCheckBiometrics` lies on iOS when
      // Face ID is disabled).
      final supported = await _localAuth.isDeviceSupported();
      final enrolled = await _localAuth.getAvailableBiometrics();
      if (!supported || enrolled.isEmpty || !mounted) return;
      // Read the reason BEFORE the prompt so no BuildContext is touched
      // across the await inside the scope below.
      final reason = context.l10n.pleaseAuthenticateToOpenTheApp;
      TrackingService.track('biometric_prompt_shown', params: {
        'surface': 'lock_overlay',
        'trigger': auto ? 'auto' : 'tap',
      });
      // Inside the scope the privacy cover stays down, so the user reads
      // this lock screen behind Face ID instead of a blank rectangle.
      final ok = await runBiometricPrompt(
        () => _localAuth.authenticate(
          localizedReason: reason,
          persistAcrossBackgrounding: true,
          biometricOnly: true,
        ),
      );
      if (!ok) {
        TrackingService.track('biometric_prompt_cancelled',
            params: {'surface': 'lock_overlay'});
      }
      if (!ok || !mounted) return;
      final auth = AuthModel();
      final String? storedPin;
      switch (await checkBiometricUnlock(auth, dependency)) {
        case BiometricUnlockRefused(:final reason):
          _trackBiometricFailed(reason);
          return;
        case BiometricUnlockAllowed(storedPin: final verified):
          storedPin = verified;
      }
      await PinAttemptGuard(auth).recordSuccess();
      if (storedPin != null) await auth.recoverPendingPinChange(storedPin);
      await BiometricPinPolicy().applyAfterUnlock(dependency);
      await recordBiometricUnlockDomainState();
      if (!mounted) return;
      markSessionUnlocked(ref,
          method: UnlockMethod.biometric, dependency: dependency);
      _finishUnlock(method: 'biometric');
    } catch (e) {
      _trackBiometricFailed(
          e is PlatformException ? e.code : e.runtimeType.toString());
    } finally {
      _biometricInFlight = false;
    }
  }

  /// `biometric_failed` with this overlay as the surface. [reason] is a
  /// platform error code or a policy refusal name, scrubbed.
  void _trackBiometricFailed(String reason) {
    TrackingService.track('biometric_failed', params: {
      'reason': TrackingService.safeReason(reason) ?? 'unknown',
      'surface': 'lock_overlay',
    });
  }

  Future<void> _verifyPin() async {
    if (_pin.length != 6 || _verifying || _lockedOut) return;
    setState(() => _verifying = true);
    try {
      final auth = AuthModel();
      final check = await auth.checkPin(_pin);
      if (!mounted) return;
      if (check == PinCheck.match) {
        final typedPin = _pin;
        await PinAttemptGuard(auth).recordSuccess();
        await auth.recoverPendingPinChange(typedPin);
        final dependency = await _v1Dependency();
        await BiometricPinPolicy()
            .applyAfterUnlock(dependency, typedPin: typedPin);
        if (!mounted) return;
        markSessionUnlocked(ref,
            method: UnlockMethod.pin,
            typedPin: typedPin,
            dependency: dependency);
        _finishUnlock(method: 'pin');
        return;
      }
      if (check == PinCheck.mismatch) {
        await _handleWrongPin(auth);
        return;
      }
      TrackingService.track('pin_check_rejected',
          params: {'result': check.name});
      _shake.forward(from: 0);
      HapticFeedback.heavyImpact();
      setState(() {
        _pin = '';
        _verifying = false;
      });
    } catch (e, st) {
      final category = TrackingService.errorCategory(e);
      TrackingService.track('unlock_failed', params: {
        'method': 'pin',
        'error_category': category,
        'surface': 'resume',
      });
      TrackingService.recordHandled(category, e, st,
          flow: 'unlock', stage: 'pin_check');
      if (mounted) {
        setState(() {
          _pin = '';
          _verifying = false;
        });
      }
    }
  }

  /// Mirrors open_pin's escalation exactly: persisted attempt counter,
  /// escalating lockouts, wallet wipe at the maximum — the overlay must
  /// not be a softer target than the cold-start screen.
  Future<void> _handleWrongPin(AuthModel auth) async {
    _shake.forward(from: 0);
    HapticFeedback.heavyImpact();
    final outcome = await PinAttemptGuard(auth).recordFailure(
      surface: PinSurface.lockScreen,
      allowWipe: ref.read(storageBootStateProvider) !=
          StorageBootState.bindingMismatch,
    );
    if (!mounted) return;
    setState(() {
      _pin = '';
      _verifying = false;
    });

    if (outcome.action == PinFailureAction.wipe) {
      TrackingService.walletWiped(
          walletCount: ref.read(settingsProvider).wallets.length);
      // walletWiped has no reason param; this names the PIN-limit cause.
      TrackingService.track('wallet_wiped_pin_limit');
      BackgroundSyncService().stop();
      await ref.read(authModelProvider).deleteAuthentication();
      ref.invalidate(bitcoinConfigProvider);
      if (mounted) RestartWidget.restartApp(context);
      return;
    }
    if (outcome.lockout > Duration.zero) {
      _startLockoutCountdown(DateTime.now().add(outcome.lockout));
    }
  }

  void _finishUnlock({required String method}) {
    // app_unlocked {method} fires in completeUnlock for both surfaces;
    // this one names the resume overlay.
    TrackingService.track('lock_overlay_unlocked', params: {'method': method});
    setState(() {
      _pin = '';
      _verifying = false;
    });
    // Drop the cover FIRST so the user's screen is instantly back,
    // then run the shared bootstrap + sync kick after the frame. NO
    // navigation and NO send/input state resets here — the covered
    // screen's state must survive exactly as the user left it.
    ref.read(pinSheetLockedProvider.notifier).state = false;
    ref.read(appLockedProvider.notifier).state = false;
    completeUnlock(ref, method: method);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      BackgroundSyncService().start(context);
      // ignore: unawaited_futures
      BackgroundSyncService().forceRefreshAll();
    });
  }

  String _formatLockout(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m > 0) return '${m}m ${s.toString().padLeft(2, '0')}s';
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final locked = ref.watch(appLockedProvider);
    // Auto-prompt biometrics each time the lock ENGAGES (not on every
    // rebuild) — mirrors the cold-start screen's auto-prompt.
    ref.listen<bool>(appLockedProvider, (prev, next) {
      if (next && !(prev ?? false)) _onLockEngaged();
    });
    if (!locked) return const SizedBox.shrink();

    final biometricsEnabled =
        ref.watch(settingsProvider.select((s) => s.biometricsEnabled));
    final padInert = _lockedOut || _verifying;
    // The same scaffold, title, dots and keypad as the cold-start PIN
    // screen, so a relock after backgrounding looks like Welcome back
    // and nothing else.
    return Positioned.fill(
      child: KutePinScaffold(
        title: context.l10n.welcomeBack,
        subtitle: _lockedOut
            ? (ref.watch(pinSheetLockedProvider)
                ? '${context.l10n.pinSheetLocked}\n'
                    '${context.l10n.lockedForTime(_formatLockout(_lockoutRemaining))}'
                : context.l10n.lockedForTime(_formatLockout(_lockoutRemaining)))
            : null,
        subtitleIsError: true,
        dots: AnimatedBuilder(
          animation: _shakeAnim,
          builder: (context, child) => Transform.translate(
            offset: Offset(_shakeAnim.value, 0),
            child: child,
          ),
          child: PinProgressIndicator(currentLength: _pin.length),
        ),
        keypad: IgnorePointer(
          ignoring: padInert,
          child: Opacity(
            opacity: padInert ? 0.4 : 1.0,
            child: CustomKeypad(
              chromed: true,
              onDigitPressed: (d) {
                if (_lockedOut || _verifying) return;
                if (_pin.length < 6) {
                  HapticFeedback.lightImpact();
                  setState(() => _pin += d);
                  if (_pin.length == 6) {
                    Future.delayed(
                        const Duration(milliseconds: 100), _verifyPin);
                  }
                }
              },
              onBackspacePressed: () {
                if (_pin.isNotEmpty) {
                  HapticFeedback.lightImpact();
                  setState(() => _pin = _pin.substring(0, _pin.length - 1));
                }
              },
              onBiometricPressed:
                  biometricsEnabled && !padInert && !_biometricInFlight
                      ? _tryBiometrics
                      : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// Opaque privacy cover shown the instant the app resigns active —
/// balances are never readable in the OS app switcher, which is what
/// makes skipping the lock inside the grace window safe. Opaque mark on
/// the app's own background instead of a blur: blur leaks amount
/// silhouettes and has Android OEM edge cases.
class PrivacyCover extends ConsumerWidget {
  const PrivacyCover({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Android ONLY. On iOS the Flutter cover was the thing that flashed the
    // "splash" on every reopen; the native cover in AppDelegate owns iOS,
    // where it can paint before the snapshot with no Flutter frame. On
    // Android this is the recents snapshot, so it carries the Kute mark on
    // the themed background rather than a bare rectangle. It no longer
    // appears during a biometric prompt (see privacy_cover_bridge.dart), so
    // it is not in the user's face on every fingerprint scan.
    if (!Platform.isAndroid) return const SizedBox.shrink();
    final visible = ref.watch(appVisibleProvider);
    if (visible) return const SizedBox.shrink();
    final c = context.colors;
    return Positioned.fill(
      child: ColoredBox(
        color: c.background,
        child: Center(
          child: Image.asset(
            'lib/assets/kute_logo.png',
            width: 88.w,
            height: 88.w,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
