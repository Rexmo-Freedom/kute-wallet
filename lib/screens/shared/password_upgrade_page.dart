// lib/screens/shared/password_upgrade_page.dart
//
// A PIN vault opened in a laptop browser (unlock_secret.dart,
// [UnlockSecret.needsPasswordUpgrade]): before the app goes on, the person
// creates a password once, typed twice, and the vault key is re-wrapped
// under it (AuthModel.upgradeToPassword, the way a PIN change re-wraps
// it). Until that write lands the PIN still opens the vault: closing the
// tab here only means the PIN is asked again, and this page after it.
//
// The cold-start unlock (open_pin.dart) and the lock overlay show it in
// place of their own page, inside the same split screen, and run the
// rest of their unlock in [onUpgraded].

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/platform/unlock_secret.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/kute_password_field.dart';
import 'package:kute/screens/shared/kute_pin_scaffold.dart';
import 'package:kute/screens/shared/password_copy.dart';
import 'package:kute/services/secure/web_vault/seed_vault.dart'
    show normalizeVaultSecret;

class PasswordUpgradePage extends StatefulWidget {
  const PasswordUpgradePage({
    super.key,
    required this.onUpgraded,
    this.upgrade,
  });

  /// Runs once the vault is password-kind: the host's own unlock.
  final VoidCallback onUpgraded;

  /// Tests: the re-wrap. Defaults to [AuthModel.upgradeToPassword].
  final Future<void> Function(String password)? upgrade;

  @override
  State<PasswordUpgradePage> createState() => _PasswordUpgradePageState();
}

class _PasswordUpgradePageState extends State<PasswordUpgradePage>
    with SingleTickerProviderStateMixin, PinSalMoodMixin {
  final TextEditingController _field = TextEditingController();
  String _first = '';
  String _text = '';
  bool _confirming = false;
  bool _saving = false;
  String? _error;

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
    _field.dispose();
    _shake.dispose();
    super.dispose();
  }

  bool get _ready => UnlockSecret.meetsRule(_text) && !_saving;

  void _wrong(String message) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!reduceMotion) _shake.forward(from: 0);
    salSad();
    HapticFeedback.heavyImpact();
    _field.clear();
    setState(() {
      _text = '';
      _error = message;
    });
  }

  Future<void> _submit() async {
    if (!_ready) return;
    if (!_confirming) {
      HapticFeedback.mediumImpact();
      _first = _text;
      _field.clear();
      setState(() {
        _text = '';
        _confirming = true;
        _error = null;
      });
      return;
    }
    if (normalizeVaultSecret(_text) != normalizeVaultSecret(_first)) {
      // Back to the first step: whatever was typed first is not known to
      // match anything the person remembers.
      _first = '';
      setState(() => _confirming = false);
      _wrong(PasswordCopy.mismatch);
      return;
    }
    setState(() => _saving = true);
    try {
      await (widget.upgrade ?? AuthModel().upgradeToPassword)(_text);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _wrong(PasswordCopy.saveFailed);
      return;
    }
    _first = '';
    KutePasswordField.finishAutofill();
    if (!mounted) return;
    salHappy();
    widget.onUpgraded();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _ready;
    return PopScope(
      canPop: false,
      child: KutePinScaffold(
        title: _confirming ? PasswordCopy.confirm : PasswordCopy.create,
        salMood: ready ? 'happy' : salMoodFor(_text.length),
        subtitle: _error ?? (_confirming ? null : PasswordCopy.upgradeNotice),
        subtitleIsError: _error != null,
        dots: AnimatedBuilder(
          animation: _shakeAnim,
          builder: (context, child) => Transform.translate(
            offset: Offset(_shakeAnim.value, 0),
            child: child,
          ),
          child: KutePasswordField(
            // A fresh field per step, so autofocus lands in it again.
            key: ValueKey('upgrade-${_confirming ? 'confirm' : 'create'}'),
            controller: _field,
            isNew: true,
            showRule: !_confirming,
            enabled: !_saving,
            onChanged: (value) => setState(() {
              _text = value;
              _error = null;
            }),
            onSubmitted: (_) => _submit(),
          ),
        ),
        keypad: const SizedBox.shrink(),
        footer: KuteBarContextScope(
          barContext: KuteBarContext.primary(
            label: _confirming ? PasswordCopy.setPassword : context.l10n.next,
            busy: _saving,
            enabled: ready,
            source: _confirming ? 'confirm_pin' : 'set_pin',
            onPrimary: _submit,
            disabledLabel:
                _confirming ? PasswordCopy.typeAgain : PasswordCopy.needPassword,
          ),
          child: SizedBox(height: kuteBarScrollClearance.h),
        ),
      ),
    );
  }
}
