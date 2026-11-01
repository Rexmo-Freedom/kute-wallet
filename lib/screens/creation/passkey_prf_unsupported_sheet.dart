// lib/screens/creation/passkey_prf_unsupported_sheet.dart
//
// The sheet for a password manager that cannot hold a Kute passkey
// wallet. Every passkey wallet's seed is derived from the passkey's WebAuthn
// PRF output (seed = f(PRF, label)). Apple Passwords and Google Password
// Manager return it; Microsoft Authenticator and some other third-party
// credential providers make a passkey but return no PRF, so no wallet can
// come from it (PasskeyService.isPrfUnsupportedError).
//
// Three variants, one look (the shared sheet: drag handle, 28sp title,
// the body as its subtitle, THE BAR IS THE BUTTON for the primary, the
// other actions as a secondary button and a text button above the bar):
//
//  * create:  creating a wallet. Primary "Use Apple Passwords" / "Use
//             Google Password Manager" re-runs the passkey ceremony (the
//             system sheet is where the user picks the manager, so the
//             line under it says which to pick), secondary "Use a recovery
//             phrase instead", text button "Try again".
//  * signIn:  an existing wallet's key ceremony came back without the key
//             (a manager that drops it, or another manager picked at
//             sign-in). Primary "Try again", secondary "Restore with your
//             recovery phrase". Nothing is wiped.
//  * restore: the restore flow found the passkey in a manager without the
//             key. Primary "Restore with your recovery phrase", text
//             button "Try again".
//
// Analytics: `passkey_prf_unsupported {platform, stage}` when the sheet
// opens and `passkey_prf_unsupported_action {stage, action}` when it
// closes. Categorical values only: never a provider name, a label or an id.

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

enum PasskeyPrfSheetVariant { create, signIn, restore }

/// What the user chose on the sheet. Null (a dismissed sheet) means
/// nothing: the caller resets and creates nothing.
enum PasskeyPrfSheetAction {
  /// Re-run the passkey ceremony and pick Apple Passwords / Google
  /// Password Manager in the system sheet.
  useDefaultManager('use_default_manager'),

  /// Create a recovery-phrase wallet instead.
  usePhrase('use_phrase'),

  /// Restore from a recovery phrase instead.
  restoreWithPhrase('restore_with_phrase'),

  /// Re-run the same ceremony.
  tryAgain('try_again');

  const PasskeyPrfSheetAction(this.analyticsValue);
  final String analyticsValue;
}

bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

/// Shows the sheet for [variant] and resolves to the user's choice (null
/// when dismissed). [stage] names where the key went missing (`create`,
/// `sign_in`, `restore_lookup`, `restore_confirm`, `legacy_probe`) for
/// analytics.
Future<PasskeyPrfSheetAction?> showPasskeyPrfUnsupportedSheet(
  BuildContext context, {
  required PasskeyPrfSheetVariant variant,
  required String stage,
}) async {
  TrackingService.track('passkey_prf_unsupported', params: {
    'platform': _isIOS ? 'ios' : 'android',
    'stage': stage,
  });
  final action = await showAppBottomSheet<PasskeyPrfSheetAction>(
    context: context,
    builder: (_) => PasskeyPrfUnsupportedSheet(variant: variant),
  );
  TrackingService.track('passkey_prf_unsupported_action', params: {
    'stage': stage,
    'action': action?.analyticsValue ?? 'dismissed',
  });
  return action;
}

class PasskeyPrfUnsupportedSheet extends StatelessWidget {
  const PasskeyPrfUnsupportedSheet({super.key, required this.variant});

  final PasskeyPrfSheetVariant variant;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    void pick(PasskeyPrfSheetAction a) => Navigator.of(context).pop(a);

    final String title;
    final String body;
    final String primaryLabel;
    final PasskeyPrfSheetAction primary;
    final List<Widget> others;
    switch (variant) {
      case PasskeyPrfSheetVariant.create:
        title = l10n.passkeyPrfUnsupportedTitle;
        body = l10n.passkeyPrfUnsupportedBody;
        primaryLabel = _isIOS
            ? l10n.passkeyPrfUseApplePasswords
            : l10n.passkeyPrfUseGooglePasswordManager;
        primary = PasskeyPrfSheetAction.useDefaultManager;
        others = [
          AppButton(
            text: l10n.passkeyPrfUsePhraseInstead,
            variant: AppButtonVariant.secondary,
            onPressed: () => pick(PasskeyPrfSheetAction.usePhrase),
          ),
          SizedBox(height: 4.h),
          AppTextButton(
            text: l10n.passkeyPrfTryAgain,
            onPressed: () => pick(PasskeyPrfSheetAction.tryAgain),
          ),
        ];
      case PasskeyPrfSheetVariant.signIn:
        title = l10n.passkeyPrfSignInTitle;
        body = l10n.passkeyPrfSignInBody;
        primaryLabel = l10n.passkeyPrfTryAgain;
        primary = PasskeyPrfSheetAction.tryAgain;
        others = [
          AppButton(
            text: l10n.passkeyPrfRestoreWithPhrase,
            variant: AppButtonVariant.secondary,
            onPressed: () => pick(PasskeyPrfSheetAction.restoreWithPhrase),
          ),
        ];
      case PasskeyPrfSheetVariant.restore:
        title = l10n.passkeyPrfSignInTitle;
        body = l10n.passkeyPrfRestoreBody;
        primaryLabel = l10n.passkeyPrfRestoreWithPhrase;
        primary = PasskeyPrfSheetAction.restoreWithPhrase;
        others = [
          AppTextButton(
            text: l10n.passkeyPrfTryAgain,
            onPressed: () => pick(PasskeyPrfSheetAction.tryAgain),
          ),
        ];
    }

    return AppBottomSheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBottomSheetHeader(title: title, subtitle: body),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...others,
                SizedBox(height: 12.h),
                // The one hint that makes a re-run work: the system sheet
                // is where the manager is picked.
                Text(
                  _isIOS
                      ? l10n.passkeyPrfPickApplePasswords
                      : l10n.passkeyPrfPickGooglePasswordManager,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodySmall(context)
                      .copyWith(color: c.textTertiary),
                ),
              ],
            ),
          ),
          SizedBox(height: 8.h),
          // THE BAR IS THE BUTTON (kute_bar_context.dart): the primary is
          // the floating Sal bar's action; the sheet keeps room for it.
          KuteBarContextScope(
            barContext: KuteBarContext.primary(
              label: primaryLabel,
              onPrimary: () => pick(primary),
              source: 'passkey_prf_unsupported',
            ),
            child: SizedBox(height: kuteBarScrollClearance.h),
          ),
        ],
      ),
    );
  }
}
