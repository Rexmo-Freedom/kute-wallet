import 'package:kute/screens/shared/custom_keypad.dart';
import 'package:kute/screens/shared/kute_pin_scaffold.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/recovery/restore_secrets_screen.dart'
    show restoreSecretsReturnProvider;
import 'package:kute/services/once_flags_service.dart';
import 'package:kute/services/tracking_service.dart';

final pinProvider = StateProvider<String>((ref) => '');

final recoveryModeProvider = StateProvider<bool>((ref) => false);

/// Onboarding funnel step (`onboarding_step {step, path}`) plus the crash
/// breadcrumb. Fires only until the install finished onboarding (the same
/// once-flag `onboarding_completed` claims), so a later add-wallet or PIN
/// visit never re-enters the first-run funnel. [path] is `create`,
/// `restore` or `restore_secrets`; categorical only.
/// [breadcrumb] false leaves the crash flow context to a more specific
/// flow already running on that screen (the wallet_restore funnel).
void trackOnboardingStep(String step, {String? path, bool breadcrumb = true}) {
  if (OnceFlagsService.isClaimed('onboarding_completed')) return;
  if (breadcrumb) TrackingService.setFlowContext(flow: 'onboarding', step: step);
  TrackingService.track('onboarding_step', params: {
    'step': step,
    if (path != null) 'path': path,
  });
}

/// The onboarding path the PIN screens are on, read from the providers
/// that route them.
String onboardingPath(WidgetRef ref) {
  if (ref.read(restoreSecretsReturnProvider) != null) return 'restore_secrets';
  return ref.read(recoveryModeProvider) ? 'restore' : 'create';
}

String _timeBucket(Duration d) {
  final s = d.inSeconds;
  if (s < 10) return '<10s';
  if (s < 30) return '10-30s';
  if (s < 120) return '30s-2m';
  if (s < 600) return '2-10m';
  return '10m+';
}

class SetPin extends ConsumerStatefulWidget {
  const SetPin({super.key});

  @override
  _SetPinState createState() => _SetPinState();
}

class _SetPinState extends ConsumerState<SetPin> {
  String pin = '';
  final Stopwatch _elapsed = Stopwatch()..start();

  /// True while the confirm screen is on top with this PIN, and after the
  /// PIN was saved: leaving then is not an abandoned entry.
  bool _advanced = false;
  late final String _path;

  @override
  void initState() {
    super.initState();
    TrackingService.pinEntryStarted();
    _path = onboardingPath(ref);
    trackOnboardingStep('pin_create', path: _path);
  }

  @override
  void dispose() {
    // Left the PIN screen (back to Start) without handing a PIN to the
    // confirm step. Every successful path clears pinProvider, so a
    // confirm screen popped back to here re-arms this below.
    if (!_advanced) {
      TrackingService.track('pin_entry_abandoned', params: {
        'step': 'create',
        'path': _path,
        'had_digits': pin.isNotEmpty,
        'time_in_flow_bucket': _timeBucket(_elapsed.elapsed),
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    // Just the title and the dots (user decision, September 2026): no step
    // counter, no subtitle, no reminder chip on the first PIN screen.
    return KutePinScaffold(
      leading: const KuteBackButton(fallbackRoute: '/start'),
      title: context.l10n.createAPin,
      dots: PinProgressIndicator(currentLength: pin.length),
      keypad: CustomKeypad(
        chromed: true,
        onDigitPressed: (digit) {
          if (pin.length < 6) {
            HapticFeedback.lightImpact();
            setState(() => pin += digit);
          }
        },
        onBackspacePressed: () {
          if (pin.isNotEmpty) {
            HapticFeedback.lightImpact();
            setState(() => pin = pin.substring(0, pin.length - 1));
          }
        },
      ),
      footer: AnimatedOpacity(
        opacity: pin.length == 6 ? 1.0 : 0.0,
        duration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        child: IgnorePointer(
          ignoring: pin.length != 6,
          child: AppButton(
            text: context.l10n.next,
            color: context.ctaFill,
            onPressed: () {
              if (pin.length == 6) {
                HapticFeedback.mediumImpact();
                ref.read(pinProvider.notifier).state = pin;
                _advanced = true;
                context.push('/confirm_pin').then((_) {
                  // Back from confirm with the PIN still pending: the entry
                  // is open again. A saved PIN cleared pinProvider.
                  if (mounted && ref.read(pinProvider).isNotEmpty) {
                    _advanced = false;
                  }
                });
              }
            },
          ),
        ),
      ),
    );
  }
}
