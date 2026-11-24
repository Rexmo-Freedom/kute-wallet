import 'package:kute/screens/shared/custom_keypad.dart';
import 'package:kute/screens/shared/kute_pin_scaffold.dart';
import 'package:kute/screens/shared/kute_password_field.dart';
import 'package:kute/screens/shared/password_copy.dart';
import 'package:kute/platform/unlock_secret.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
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

class _SetPinState extends ConsumerState<SetPin> with PinSalMoodMixin {
  String pin = '';
  final Stopwatch _elapsed = Stopwatch()..start();

  /// True while the confirm screen is on top with this PIN, and after the
  /// PIN was saved: leaving then is not an abandoned entry.
  bool _advanced = false;
  late final String _path;

  /// A laptop browser creates a password instead (unlock_secret.dart).
  final bool _password =
      UnlockSecret.deviceKind == VaultSecretKind.password;
  final TextEditingController _field = TextEditingController();

  bool get _ready =>
      _password ? UnlockSecret.meetsRule(pin) : pin.length == 6;

  void _next() {
    if (!_ready) return;
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
        'time_in_flow_ms': _elapsed.elapsed.inMilliseconds,
        'time_in_flow_bucket': _timeBucket(_elapsed.elapsed),
      });
    }
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final ready = _ready;

    // Just the title and the dots (user decision, September 2026): no step
    // counter, no subtitle, no reminder chip on the first PIN screen.
    return KutePinScaffold(
      leading: const KuteBackButton(fallbackRoute: '/start'),
      title: _password ? PasswordCopy.create : context.l10n.createAPin,
      // Happy once the six digits are in, before Next is tapped.
      salMood: ready ? 'happy' : salMoodFor(pin.length),
      dots: _password
          ? KutePasswordField(
              controller: _field,
              isNew: true,
              showRule: true,
              onChanged: (value) => setState(() => pin = value),
              onSubmitted: (_) => _next(),
            )
          : PinProgressIndicator(currentLength: pin.length),
      keypad: _password
          ? const SizedBox.shrink()
          : CustomKeypad(
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
        opacity: ready || _password ? 1.0 : 0.0,
        duration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        child: IgnorePointer(
          ignoring: !ready,
          // THE BAR IS THE BUTTON (kute_bar_context.dart): Next is the
          // floating Sal bar's primary action, on with six digits.
          child: KuteBarContextScope(
            barContext: KuteBarContext.primary(
            label: context.l10n.next,
            enabled: ready,
            source: 'set_pin',
            onPrimary: _next,
            disabledLabel:
                _password ? PasswordCopy.rule : context.l10n.barNeedPin,
            ),
            child: SizedBox(height: kuteBarScrollClearance.h),
          ),
        ),
      ),
    );
  }
}
