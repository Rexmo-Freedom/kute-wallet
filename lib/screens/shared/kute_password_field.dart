// lib/screens/shared/kute_password_field.dart
//
// The password field of a laptop browser's lock (unlock_secret.dart): the
// app's own text field (AppTextField) obscured, with a show/hide toggle,
// autofocused, Enter submitting. It takes the dots' place on every PIN
// page and sheet when the secret is a password; the page's shake wraps it
// as it wraps the dots.
//
// A browser password manager can save and fill it: `new-password` on
// create and confirm, `current-password` everywhere it is checked. The
// value goes to nothing but the vault: no analytics, no logs (the field
// is masked for any session replay too).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

import 'package:kute/screens/shared/app_text_field.dart';
import 'package:kute/screens/shared/password_copy.dart';
import 'package:kute/theme/app_theme.dart';

class KutePasswordField extends StatefulWidget {
  const KutePasswordField({
    super.key,
    required this.controller,
    required this.onSubmitted,
    this.onChanged,
    this.focusNode,
    this.isNew = false,
    this.showRule = false,
    this.enabled = true,
    this.autofocus = true,
  });

  final TextEditingController controller;

  /// Enter. The page decides whether the text is ready.
  final ValueChanged<String> onSubmitted;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;

  /// A password being created or confirmed (`new-password`), not checked
  /// (`current-password`).
  final bool isNew;

  /// The quiet rule line under the field ("At least 10 characters").
  final bool showRule;

  /// False while the page checks or saves: the text stays, nothing types.
  final bool enabled;
  final bool autofocus;

  /// Tells the browser's password manager the form is done, so it offers
  /// to save a new password. Call after a password was accepted.
  static void finishAutofill({bool save = true}) {
    try {
      TextInput.finishAutofillContext(shouldSave: save);
    } catch (_) {}
  }

  @override
  State<KutePasswordField> createState() => _KutePasswordFieldState();
}

class _KutePasswordFieldState extends State<KutePasswordField> {
  bool _visible = false;
  FocusNode? _own;
  FocusNode get _focus => widget.focusNode ?? (_own ??= FocusNode());

  @override
  void initState() {
    super.initState();
    // Focus asked for outright, not only `autofocus`: above the Navigator
    // (the lock overlay) the route's scope already holds focus, and
    // `autofocus` gives way to it.
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.enabled) _focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final field = AppTextField(
      key: const ValueKey('kute-password-field'),
      controller: widget.controller,
      focusNode: _focus,
      hintText: PasswordCopy.hint,
      obscureText: !_visible,
      autofocus: widget.autofocus,
      readOnly: !widget.enabled,
      keyboardType: TextInputType.visiblePassword,
      textInputAction: TextInputAction.done,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: [
        widget.isNew ? AutofillHints.newPassword : AutofillHints.password,
      ],
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      // Enter keeps the focus: a wrong or mismatched entry is typed again
      // without reaching for the mouse.
      onEditingComplete: () {},
      suffixIcon: Padding(
        padding: EdgeInsets.only(right: 4.w),
        child: IconButton(
          key: const ValueKey('kute-password-visibility'),
          tooltip: _visible ? PasswordCopy.hide : PasswordCopy.show,
          onPressed: () => setState(() => _visible = !_visible),
          icon: Icon(
            _visible ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            color: c.textTertiary,
            size: 20,
          ),
        ),
      ),
    );
    return PostHogMaskWidget(
      child: AutofillGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            field,
            if (widget.showRule) ...[
              SizedBox(height: 10.h),
              Text(
                PasswordCopy.rule,
                key: const ValueKey('kute-password-rule'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: c.textTertiary,
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// An [Overlay] of its own for a text field drawn above the app's
/// Navigator (the lock overlay, app_widget.dart's Stack): the field's
/// tooltip, selection handles and context menu need one, and the
/// Navigator's is under the lock.
class KuteOverlayHost extends StatefulWidget {
  const KuteOverlayHost({super.key, required this.child});

  final Widget child;

  @override
  State<KuteOverlayHost> createState() => _KuteOverlayHostState();
}

class _KuteOverlayHostState extends State<KuteOverlayHost> {
  late final OverlayEntry _entry =
      OverlayEntry(builder: (_) => widget.child, opaque: true);

  @override
  void didUpdateWidget(covariant KuteOverlayHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The entry is below this widget: rebuilt in this same frame.
    _entry.markNeedsBuild();
  }

  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [_entry]);
}
