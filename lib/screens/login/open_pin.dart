import 'dart:async';
import 'package:kute/services/secure/storage_bootstrap.dart';
import 'package:kute/screens/recovery/restore_secrets_screen.dart';
import 'package:kute/services/secure/recovery_check.dart';
import 'package:kute/services/secure/recovery_evm_format.dart';
import 'package:kute/models/evm_derivation_version.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart'
    show hyperliquidAddressProvider;
import 'package:kute/providers/hyperliquid_trading_provider.dart'
    show hyperliquidTradingProvider;
import 'package:kute/services/hyperliquid/hyperliquid_onboarding_service.dart';
import 'package:kute/services/venue_total_cache_service.dart';
import 'package:kute/helpers/pin_attempt_guard.dart';
import 'package:kute/helpers/privacy_cover_bridge.dart';
import 'package:kute/helpers/session_auth.dart';
import 'package:kute/helpers/session_unlock.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/providers/address_provider.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/bitcoin_config_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/send_tx_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/restart_widget.dart';
import 'package:kute/screens/shared/custom_alert_dialog.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/custom_keypad.dart';
import 'package:kute/screens/shared/kute_pin_scaffold.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/helpers/user_error_copy.dart';
import 'package:kute/services/background_sync_service.dart';
import 'package:kute/services/passkey_service.dart'
    show resolveBip39MnemonicFor;
import 'package:kute/services/secure/biometric_pin_policy.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:kute/services/tracking_service.dart';

class OpenPin extends ConsumerStatefulWidget {
  const OpenPin({super.key, @visibleForTesting this.localAuth});

  final LocalAuthentication? localAuth;

  @override
  _OpenPinState createState() => _OpenPinState();
}

class _OpenPinState extends ConsumerState<OpenPin>
    with SingleTickerProviderStateMixin {
  String pin = '';

  /// The sixth digit is in and the PIN is being compared. PBKDF2 runs on
  /// an isolate, so without this the screen sat with six filled dots on
  /// a live keypad and said nothing back.
  bool _verifying = false;
  late final LocalAuthentication _localAuth =
      widget.localAuth ?? LocalAuthentication();
  int _attempts = 0;
  bool _isLocked = false;
  int _lockoutSecondsRemaining = 0;
  Timer? _lockoutTimer;
  AppLifecycleListener? _resumeListener;
  Future<V1Dependency>? _dependency;

  Future<V1Dependency> _v1Dependency() =>
      _dependency ??= evaluateV1Dependency(ref);

  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    // Cold start: the step-up session budget starts from zero (D-11).
    resetStepUpSession();
    _setupAnimations();
    _loadPersistedState();
  }

  PinAttemptGuard get _guard => PinAttemptGuard(AuthModel());

  Future<void> _loadPersistedState() async {
    final guard = _guard;
    try {
      _attempts = await guard.attempts();
      final remaining = await guard.lockoutRemaining();
      if (remaining > Duration.zero && mounted) {
        _startLockoutTimer(remaining.inSeconds);
      }
    } catch (_) {
      // An unreadable counter never blocks the keypad or counts.
    }

    if (mounted) {
      setState(() {});
      if (!_isLocked && ref.read(settingsProvider).biometricsEnabled) {
        final dependency = await _v1Dependency();
        if (!mounted) return;
        // A wallet that still needs the PIN, with no stored copy for
        // biometrics: the PIN is typed instead of prompting first.
        if (dependency.exists &&
            dependency.biometricPin != StoredPinState.present) {
          return;
        }
        _startBiometricsWhenResumed();
      }
    }
  }

  /// A launch in the background (a push) waits for the app to resume
  /// before prompting.
  void _startBiometricsWhenResumed() {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle == null || lifecycle == AppLifecycleState.resumed) {
      // Self-contained (its own try/catch); fire-and-forget so it
      // never blocks the keypad and a biometric failure can't throw
      // into initState.
      unawaited(_checkBiometrics(context, ref, trigger: 'auto'));
      return;
    }
    _resumeListener?.dispose();
    _resumeListener = AppLifecycleListener(onResume: () {
      _resumeListener?.dispose();
      _resumeListener = null;
      if (mounted && !_isLocked) {
        unawaited(_checkBiometrics(context, ref, trigger: 'auto'));
      }
    });
  }

  /// True after a cold start whose storage binding did not match: wrong
  /// PINs keep their delays but never wipe.
  bool get _noWipe =>
      ref.read(storageBootStateProvider) == StorageBootState.bindingMismatch;

  void _setupAnimations() {
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _animation = Tween<double>(begin: 0.0, end: 24.0)
        .chain(CurveTween(curve: Curves.elasticIn))
        .animate(_animationController)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _animationController.reverse();
        }
      });
  }

  void _startLockoutTimer(int seconds) {
    setState(() {
      _isLocked = true;
      _lockoutSecondsRemaining = seconds;
    });

    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_lockoutSecondsRemaining <= 1) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _isLocked = false;
            _lockoutSecondsRemaining = 0;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _lockoutSecondsRemaining--;
          });
        }
      }
    });
  }

  String _formatLockoutTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    if (minutes > 0) {
      return '${minutes}m ${secs.toString().padLeft(2, '0')}s';
    }
    return '${secs}s';
  }

  void _checkPin(BuildContext context, WidgetRef ref) async {
    if (_isLocked) return;

    try {
      final authModel = AuthModel();
      // Async variant runs PBKDF2 on a background isolate so the UI
      // thread isn't blocked between the 6th digit and the home screen.
      final check = await authModel.checkPin(pin);

      if (check == PinCheck.match) {
        final typedPin = pin;
        await _guard.recordSuccess();
        await authModel.recoverPendingPinChange(typedPin);
        final dependency = await _v1Dependency();
        await BiometricPinPolicy()
            .applyAfterUnlock(dependency, typedPin: typedPin);

        if (!context.mounted) return;
        markSessionUnlocked(ref,
            method: UnlockMethod.pin,
            typedPin: typedPin,
            dependency: dependency);
        final container = ProviderScope.containerOf(context, listen: false);
        _unlockApp(context, ref, method: 'pin');
        _scheduleAfterUnlock(container);
      } else if (check == PinCheck.mismatch) {
        await _handleIncorrectPin();
      } else {
        _rejectWithoutCounting(check);
      }
    } catch (e, st) {
      final category = TrackingService.errorCategory(e);
      TrackingService.track('unlock_failed', params: {
        'method': 'pin',
        'error_category': category,
        'surface': 'cold_start',
      });
      TrackingService.recordHandled(category, e, st,
          flow: 'unlock', stage: 'pin_check');
      if (mounted && context.mounted) {
        setState(() => pin = '');
        showMessageSnackBar(
          context: context,
          message:
              userErrorCopy(context, e, fallback: context.l10n.errorCopyUnlock),
          error: true,
        );
      }
    } finally {
      // Every exit clears it: a match replaces the screen anyway, and a
      // mismatch, a rejection and a thrown error all have to hand the
      // keypad back.
      if (mounted) setState(() => _verifying = false);
    }
  }

  void _shakeKeypad() {
    // The shake is decorative feedback (HapticFeedback below already
    // signals the error non-visually), so skip it under Reduce Motion.
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!reduceMotion) {
      _animationController.forward(from: 0.0);
    }
    HapticFeedback.heavyImpact();
  }

  /// A PIN that could not be compared never counts toward the lockout:
  /// missing PIN material opens Restore wallets and unreadable storage
  /// opens the retry screen.
  void _rejectWithoutCounting(PinCheck check) {
    TrackingService.track('pin_check_rejected',
        params: {'result': check.name});
    if (!mounted) return;
    _shakeKeypad();
    setState(() => pin = '');
    if (check == PinCheck.noPinMaterial) {
      context.go('/restore_secrets',
          extra: RestoreSecretsReason.secretsMissing);
    } else {
      context.go('/storage_unavailable',
          extra: const StorageBootResult(StorageBootState.storageUnavailable));
    }
  }

  Future<void> _handleIncorrectPin() async {
    _shakeKeypad();

    final outcome = await _guard.recordFailure(
      surface: PinSurface.lockScreen,
      allowWipe: !_noWipe,
    );
    _attempts = outcome.attempts;
    if (!mounted) return;

    setState(() {
      pin = '';
    });

    if (outcome.action == PinFailureAction.wipe) {
      TrackingService.walletWiped(
          walletCount: ref.read(settingsProvider).wallets.length);
      // walletWiped has no reason param; this names the PIN-limit cause.
      TrackingService.track('wallet_wiped_pin_limit');
      BackgroundSyncService().stop();
      final authModelRef = ref.read(authModelProvider);
      await authModelRef.deleteAuthentication();
      ref.invalidate(bitcoinConfigProvider);
      if (mounted) RestartWidget.restartApp(context);
      return;
    }

    if (outcome.lockout > Duration.zero) {
      _startLockoutTimer(outcome.lockout.inSeconds);
    }
  }

  /// [trigger] is `auto` for the prompt raised on entry and `tap` for the
  /// keypad's biometric key.
  Future<void> _checkBiometrics(BuildContext context, WidgetRef ref,
      {String trigger = 'tap'}) async {
    if (_isLocked) return;

    try {
      // `canCheckBiometrics` only reports that biometric HARDWARE
      // exists — on iOS it stays `true` even when Face ID / Touch ID is
      // turned off or not enrolled. Invoking
      // `authenticate(biometricOnly: true)` in that state is what broke
      // first launch for users with biometrics disabled. Gate on the
      // ENROLLED methods (`getAvailableBiometrics`, empty when disabled)
      // + `isDeviceSupported`, so we only prompt when biometrics can
      // actually succeed; otherwise fall straight through to the PIN
      // keypad (the always-available fallback).
      final supported = await _localAuth.isDeviceSupported();
      final enrolled = await _localAuth.getAvailableBiometrics();
      if (!supported || enrolled.isEmpty) return;
      if (!mounted || !context.mounted) return;

      {
        // Reason read up front: the scope below awaits before the
        // prompt, so no BuildContext is touched across it.
        final reason = context.l10n.pleaseAuthenticateToOpenTheApp;
        // The scope keeps the privacy cover down for the scan, so the
        // user sees this PIN screen behind Face ID, not a blank one.
        // Funnel: shown → app_unlocked {method: biometric} |
        // biometric_prompt_cancelled | biometric_failed, all per surface.
        TrackingService.track('biometric_prompt_shown',
            params: {'surface': 'cold_start', 'trigger': trigger});
        bool authenticated = await runBiometricPrompt(
          () => _localAuth.authenticate(
            localizedReason: reason,
            persistAcrossBackgrounding: true,
            biometricOnly: true,
          ),
        );

        if (authenticated && mounted) {
          final authModel = AuthModel();
          final dependency = await _v1Dependency();

          final String? storedPin;
          switch (await checkBiometricUnlock(authModel, dependency)) {
            case BiometricUnlockRefused(:final reason):
              _trackBiometricFailed(reason);
              return;
            case BiometricUnlockAllowed(storedPin: final verified):
              storedPin = verified;
          }
          await _guard.recordSuccess();
          if (storedPin != null) {
            await authModel.recoverPendingPinChange(storedPin);
          }
          await BiometricPinPolicy().applyAfterUnlock(dependency);
          await recordBiometricUnlockDomainState();

          if (!context.mounted) return;
          markSessionUnlocked(ref,
              method: UnlockMethod.biometric, dependency: dependency);
          final container = ProviderScope.containerOf(context, listen: false);
          _unlockApp(context, ref, method: 'biometric');
          _scheduleAfterUnlock(container);
        } else if (!authenticated) {
          TrackingService.track('biometric_prompt_cancelled',
              params: {'surface': 'cold_start'});
        }
      }
    } catch (e) {
      _trackBiometricFailed(
          e is PlatformException ? e.code : e.runtimeType.toString());
    }
  }

  /// `biometric_failed` with this screen as the surface. [reason] is a
  /// platform error code or a policy refusal name, scrubbed.
  void _trackBiometricFailed(String reason) {
    TrackingService.track('biometric_failed', params: {
      'reason': TrackingService.safeReason(reason) ?? 'unknown',
      'surface': 'cold_start',
    });
  }

  /// Work deferred past the unlock transition: Polymarket provisioning for
  /// the active wallet after 3 s, and the recovery check address for
  /// stored-seed wallets that have none after 6 s. Both read the session
  /// when they run, so nothing resolves if the app locked in between.
  void _scheduleAfterUnlock(ProviderContainer container) {
    final settings = container.read(settingsProvider);
    final wallets = settings.wallets;
    // A phrase recovery whose EVM format check could not finish retries it
    // first, so provisioning below sees the wallet's settled format.
    if (wallets.any((w) => w.evmFormatCheckPending)) {
      Future.delayed(const Duration(seconds: 1), () async {
        try {
          await RecoveryEvmFormat.retryPending(
            settings: container.read(settingsProvider.notifier),
            wallets: wallets,
            readMnemonic: (walletId) => AuthModel().getMnemonic(walletId,
                access: SeedAccess.automatic,
                session: container.read(seedSessionProvider)),
            onAdopted: (walletId, mnemonic, {required hyperliquidActive}) =>
                _afterEvmFormatAdopted(container, walletId, mnemonic,
                    hyperliquidActive: hyperliquidActive),
          );
        } catch (_) {}
      });
    }
    final active = settings.activeWallet;
    if (active != null) {
      Future.delayed(const Duration(seconds: 3), () async {
        try {
          // Re-read: the format retry above may have settled the wallet.
          final wallet =
              container.read(settingsProvider.notifier).walletById(active.id);
          if (wallet == null) return;
          final mnemonic = await resolveBip39MnemonicFor(wallet,
              access: SeedAccess.automatic,
              session: container.read(seedSessionProvider));
          if (mnemonic != null) {
            provisionPolymarketAccount(
                mnemonic: mnemonic,
                walletId: wallet.id,
                evmDerivationVersion: wallet.evmDerivationVersion);
          }
        } catch (_) {}
      });
    }
    if (wallets.any((w) =>
        RecoveryCheck.holdsStoredSeed(w) && w.recoveryCheckAddress == null)) {
      Future.delayed(const Duration(seconds: 6), () async {
        try {
          await RecoveryCheck.backfill(
            settings: container.read(settingsProvider.notifier),
            wallets: wallets,
            auth: AuthModel(),
            session: container.read(seedSessionProvider),
          );
        } catch (_) {}
      });
    }
  }

  /// A recovered wallet just moved to its legacy EVM account: drop the
  /// venue caches built for the old account, rebuild what derived it, and
  /// set Predictions up for the new one.
  static Future<void> _afterEvmFormatAdopted(
    ProviderContainer container,
    String walletId,
    String mnemonic, {
    required bool hyperliquidActive,
  }) async {
    await forgetPolymarketAccountCache(walletId);
    await VenueTotalCacheService.deleteWallet(walletId);
    if (hyperliquidActive) {
      await HyperliquidOnboardingService.markEnabled(walletId);
    }
    container
      ..invalidate(polymarketTradingProvider)
      ..invalidate(hyperliquidTradingProvider)
      ..invalidate(hyperliquidAddressProvider);
    unawaited(provisionPolymarketAccount(
        mnemonic: mnemonic,
        walletId: walletId,
        evmDerivationVersion: EvmDerivationVersion.legacySha256));
  }

  void _unlockApp(BuildContext context, WidgetRef ref,
      {String method = 'pin'}) {
    _attempts = 0;
    // Cold-start-only resets: the resume LockOverlay deliberately does
    // NOT run these (it must leave the live screen's state alone).
    ref.read(sendTxProvider.notifier).resetToDefault();
    ref.read(addressProvider);
    // Shared post-unlock bootstrap (Breez bad-state heal + prime) —
    // one implementation with the resume LockOverlay.
    completeUnlock(ref, method: method);
    context.go('/home');
  }

  Future<void> _forgotPin(BuildContext context, WidgetRef ref) async {
    TrackingService.walletWiped(
        walletCount: ref.read(settingsProvider).wallets.length);
    // walletWiped has no reason param; this names the forgot-PIN cause.
    TrackingService.track('wallet_wiped_forgot_pin');
    BackgroundSyncService().stop();
    final authModel = ref.read(authModelProvider);
    await authModel.deleteAuthentication();
    ref.invalidate(bitcoinConfigProvider);
    if (context.mounted) RestartWidget.restartApp(context);
  }

  /// Forgot PIN: plain words about what happens (the wallet leaves this
  /// phone; the recovery phrase or the account brings it back) and a
  /// button that says so. Same wipe as before.
  Future<void> _showForgotPinConfirmation(
      BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    // showDialog uses the root navigator, so the buttons pop that one.
    final navigator = Navigator.of(context, rootNavigator: true);
    TrackingService.track('forgot_pin_dialog_shown');
    showCustomAlertDialog(
      context: context,
      title: l10n.forgotPinTitle,
      content: l10n.forgotPinBody,
      buttons: [
        CustomAlertAction.destructive(
          text: l10n.forgotPinAction,
          onPressed: () async {
            navigator.pop();
            await _forgotPin(context, ref);
          },
        ),
        CustomAlertAction.secondary(
          text: l10n.cancel,
          onPressed: () {
            TrackingService.track('forgot_pin_dialog_dismissed');
            navigator.pop();
          },
        ),
      ],
    );
  }

  @override
  void dispose() {
    _resumeListener?.dispose();
    _lockoutTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final biometricsEnabled =
        ref.watch(settingsProvider.select((s) => s.biometricsEnabled));
    final noWipe =
        ref.watch(storageBootStateProvider) == StorageBootState.bindingMismatch;

    String attemptsMessage = '';
    if (_isLocked) {
      attemptsMessage = context.l10n
          .lockedForTime(_formatLockoutTime(_lockoutSecondsRemaining));
    } else if (_attempts > 0 && noWipe) {
      attemptsMessage = context.l10n.incorrectPin;
    } else if (_attempts > 0) {
      int remainingAttempts = 6 - _attempts;
      if (remainingAttempts == 1) {
        attemptsMessage = context.l10n.lastAttemptWalletWillBeErased;
      } else {
        attemptsMessage =
            '$remainingAttempts ${context.l10n.attemptsRemaining}';
      }
    }

    // The pad is dead while the wallet is locked out AND while the PIN
    // is being checked. Verification runs PBKDF2 on an isolate, so there
    // was a window where six filled dots sat on a live keypad with
    // nothing happening: the person had finished and the screen had not
    // acknowledged it. Same treatment either way, so the moment after
    // the sixth digit looks deliberate.
    final padInert = _isLocked || _verifying;

    return PopScope(
      canPop: false,
      child: KutePinScaffold(
        title: context.l10n.welcomeBack,
        // Nothing under the title unless something is wrong. Six dots
        // over a number pad do not need a sentence explaining that a
        // PIN goes in them, and the line was only ever taking up the
        // space where the attempts warning has to appear.
        subtitle: (_isLocked || _attempts > 0) ? attemptsMessage : null,
        subtitleIsError: true,
        dots: AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(_animation.value, 0),
              child: child,
            );
          },
          child: PinProgressIndicator(currentLength: pin.length),
        ),
        keypad: IgnorePointer(
          ignoring: padInert,
          child: Opacity(
            opacity: padInert ? 0.4 : 1.0,
            child: CustomKeypad(
              chromed: true,
              onDigitPressed: (digit) {
                if (pin.length < 6) {
                  HapticFeedback.lightImpact();
                  setState(() => pin += digit);
                  if (pin.length == 6) {
                    setState(() => _verifying = true);
                    Future.delayed(const Duration(milliseconds: 100), () {
                      if (!mounted || !context.mounted) return;
                      _checkPin(context, ref);
                    });
                  }
                }
              },
              onBackspacePressed: () {
                if (pin.isNotEmpty) {
                  HapticFeedback.lightImpact();
                  setState(() => pin = pin.substring(0, pin.length - 1));
                }
              },
              onBiometricPressed: biometricsEnabled && !padInert
                  ? () => _checkBiometrics(context, ref)
                  : null,
            ),
          ),
        ),
        footer: noWipe
            ? AppTextButton(
                key: const ValueKey('open-pin-restore'),
                text: context.l10n.restoreWalletsAction,
                onPressed: () {
                  TrackingService.track('open_pin_restore_tapped');
                  context.go(
                    '/restore_secrets',
                    extra: RestoreSecretsReason.bindingMismatch,
                  );
                },
              )
            : AppTextButton(
                text: context.l10n.forgotPin2,
                onPressed: () {
                  HapticFeedback.lightImpact();
                  _showForgotPinConfirmation(context, ref);
                },
              ),
      ),
    );
  }
}
