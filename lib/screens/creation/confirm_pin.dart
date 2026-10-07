import 'package:kute/services/secure/storage_bootstrap.dart';
import 'package:kute/helpers/session_auth.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/services/secure/biometric_pin_policy.dart';
import 'package:kute/providers/words_provider.dart';
import 'package:kute/screens/creation/set_pin.dart'; // Contains pinProvider & PinProgressIndicator
import 'package:kute/screens/recovery/restore_secrets_screen.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/custom_keypad.dart';
import 'package:kute/screens/shared/kute_pin_scaffold.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/helpers/user_error_copy.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kute/services/tracking_service.dart';

final confirmPinLoadingProvider = StateProvider<bool>((ref) => false);

class ConfirmPin extends ConsumerStatefulWidget {
  const ConfirmPin({super.key});

  @override
  _ConfirmPinState createState() => _ConfirmPinState();
}

class _ConfirmPinState extends ConsumerState<ConfirmPin>
    with SingleTickerProviderStateMixin {
  String confirmPin = '';

  /// The last attempt did not match. Clears on the next key, so the
  /// error is about what just happened rather than a state to escape.
  bool _mismatched = false;
  late AnimationController _animationController;
  late Animation<double> _animation;

  /// Onboarding path (create | restore | restore_secrets), read once.
  late final String _path;

  @override
  void initState() {
    super.initState();
    _path = onboardingPath(ref);
    trackOnboardingStep('pin_confirm', path: _path);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(confirmPinLoadingProvider.notifier).state = false;
    });
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

  Future<void> _handleSetPin(String originalPin) async {
    ref.read(confirmPinLoadingProvider.notifier).state = true;
    try {
      final authModel = ref.read(authModelProvider);
      final isRecovery = ref.read(recoveryModeProvider);

      await authModel.setPinAsync(originalPin);
      try {
        await StorageBootstrap().writeNewBinding();
        ref.read(storageBootStateProvider.notifier).state = StorageBootState.ok;
      } catch (_) {
        // The next cold start writes the binding (preBinding).
      }
      // pin_confirmed fired here too, for the same action; pin_set alone
      // carries it.
      TrackingService.pinSet();

      final policy = BiometricPinPolicy();
      final dependency = await evaluateV1Dependency(ref, policy: policy);
      await policy.applyAfterUnlock(dependency, typedPin: originalPin);
      if (!mounted) return;
      markSessionUnlocked(ref,
          method: UnlockMethod.pin,
          typedPin: originalPin,
          dependency: dependency);

      final restoreReason = ref.read(restoreSecretsReturnProvider);
      if (restoreReason != null) {
        ref.read(restoreSecretsReturnProvider.notifier).state = null;
        ref.read(pinProvider.notifier).state = '';
        ref.read(confirmPinLoadingProvider.notifier).state = false;
        if (mounted) context.go('/restore_secrets', extra: restoreReason);
        return;
      }

      if (isRecovery) {
        // Preload BIP39 word list while the overlay is showing so
        // recover_wallet has it ready immediately.
        await ref.read(wordsProvider.notifier).loadWords();

        ref.read(pinProvider.notifier).state = '';
        ref.read(confirmPinLoadingProvider.notifier).state = false;
        if (mounted) {
          context.go('/recover_wallet');
        }
        return;
      }

      // New-wallet path: defer wallet CREATION until the user picks
      // passkey-vs-BIP39 on `/passkey_choice`. That screen calls
      // `authModel.setMnemonic` + `addWallet` (BIP39) or runs the
      // PasskeyService.registerCredential flow (passkey), then
      // navigates onward. We just hand off the next route.
      ref.read(pinProvider.notifier).state = '';
      ref.read(confirmPinLoadingProvider.notifier).state = false;
      if (mounted) {
        context.go('/passkey_choice', extra: '/beta_survey');
      }
    } catch (e, st) {
      final category = TrackingService.errorCategory(e);
      TrackingService.track('pin_set_failed', params: {
        'error_category': category,
        'path': _path,
      });
      TrackingService.recordHandled(category, e, st,
          flow: 'onboarding', stage: 'pin_set');
      if (mounted) {
        showMessageSnackBar(
          message:
              userErrorCopy(context, e, fallback: context.l10n.errorCopySetPin),
          error: true,
          context: context,
        );
        ref.read(confirmPinLoadingProvider.notifier).state = false;
      }
    }
  }

  void _handlePinMismatch() {
    TrackingService.track('pin_confirm_mismatch');
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!reduceMotion) {
      _animationController.forward(from: 0.0);
    }
    HapticFeedback.heavyImpact();
    // No snackbar. A mismatch is about the screen the person is on, so
    // it belongs on that screen, in the line that was telling them what
    // to do. A toast sliding over the bottom of a keypad said it in the
    // one place they were not looking.
    setState(() {
      confirmPin = '';
      _mismatched = true;
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final originalPin = ref.watch(pinProvider);
    final isLoading = ref.watch(confirmPinLoadingProvider);

    return Stack(
      children: [
        KutePinScaffold(
          leading: const KuteBackButton(fallbackRoute: '/set_pin'),
          // Just the title and the dots (user decision, September 2026).
          // A mismatch still says so here, in red, in place of nothing,
          // instead of arriving as a snackbar over a screen that reads as
          // if nothing went wrong.
          title: context.l10n.confirmYourPin,
          subtitle: _mismatched ? context.l10n.pinsDoNotMatchRetry : null,
          subtitleIsError: _mismatched,
          dots: AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(_animation.value, 0),
                child: child,
              );
            },
            child: PinProgressIndicator(currentLength: confirmPin.length),
          ),
          keypad: IgnorePointer(
            ignoring: isLoading,
            child: CustomKeypad(
              chromed: true,
              onDigitPressed: (digit) {
                if (confirmPin.length < 6) {
                  HapticFeedback.lightImpact();
                  setState(() {
                    confirmPin += digit;
                    _mismatched = false;
                  });
                }
              },
              onBackspacePressed: () {
                if (confirmPin.isNotEmpty) {
                  HapticFeedback.lightImpact();
                  setState(() {
                    confirmPin = confirmPin.substring(0, confirmPin.length - 1);
                    _mismatched = false;
                  });
                }
              },
            ),
          ),
          footer: AnimatedOpacity(
            opacity: confirmPin.length == 6 ? 1.0 : 0.0,
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            child: IgnorePointer(
              ignoring: confirmPin.length != 6 || isLoading,
              child: AppButton(
                text: isLoading
                    ? context.l10n.creatingWallet
                    : context.l10n.setPin,
                color: context.ctaFill,
                // The wait is on the button, the way the bet slip waits
                // (user decision): no full-screen overlay after the PIN.
                isLoading: isLoading,
                onPressed: () {
                  if (confirmPin.length == 6) {
                    if (confirmPin == originalPin) {
                      _handleSetPin(originalPin);
                    } else {
                      _handlePinMismatch();
                    }
                  }
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
