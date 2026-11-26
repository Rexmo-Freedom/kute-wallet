// lib/helpers/passkey_account_name.dart
//
// What to call the thing holding the user's passkey, on this platform.
//
// A passkey is not kept by Kute. On iOS it lives in iCloud Keychain,
// which belongs to the Apple account; on Android it goes to Google
// Password Manager, which is built into Play Services and is the
// default credential provider on every certified device. Naming the
// account is the difference between a person knowing where to look and
// being told to keep access to "your device's passkey provider", which
// names nothing they have ever seen.
//
// Android since 14 lets another installed provider take the passkey
// instead, and nothing here can detect or force that. Google is the
// default and covers the great majority, which is the deliberate call:
// say the common case plainly rather than say something vague that is
// technically true for everyone and useful to no one.


import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/platform/browser_agent.dart';
import 'package:kute/platform/platform_caps.dart';

/// Who keeps the passkey here: Apple (iCloud Keychain / Apple Passwords),
/// Google (Google Password Manager) or, in a browser that is neither,
/// nobody the app can name.
enum PasskeyKeeper { apple, google, other }

/// The phones: iOS is Apple, Android is Google, as before. The web follows
/// the browser and its system, since the page's platform says nothing
/// about who stores the passkey: Chrome (any system but iOS) and Android
/// save to Google Password Manager; Safari, and every browser on an
/// iPhone or iPad (they all use the system's passkeys), save to Apple's;
/// anything else (Firefox or Edge off Apple systems) is [other].
PasskeyKeeper passkeyKeeper(
    {bool? web, String? userAgent, bool? ios}) {
  if (!(web ?? kIsWeb)) {
    return (ios ?? PlatformOs.isIOS) ? PasskeyKeeper.apple : PasskeyKeeper.google;
  }
  final ua = (userAgent ?? browserUserAgent() ?? '').toLowerCase();
  final appleMobile = ua.contains('iphone') ||
      ua.contains('ipad') ||
      ua.contains('ipod');
  if (appleMobile) return PasskeyKeeper.apple;
  if (ua.contains('android')) return PasskeyKeeper.google;
  final edge = ua.contains('edg/');
  final chrome = !edge &&
      (ua.contains('chrome/') || ua.contains('chromium/') || ua.contains('crios/'));
  if (chrome) return PasskeyKeeper.google;
  final mac = ua.contains('macintosh') || ua.contains('mac os x');
  if (mac && ua.contains('safari/')) return PasskeyKeeper.apple;
  return PasskeyKeeper.other;
}

/// "Apple account" or "Google account", already localized. A browser that
/// is neither ([PasskeyKeeper.other]) gets the Google wording, the app's
/// only other one (no neutral account name exists in its strings); the
/// "Works with" line is left out there instead ([passkeyWorksWith]).
String passkeyAccountName(BuildContext context) =>
    passkeyKeeper() == PasskeyKeeper.apple
        ? context.l10n.passkeyChoiceAppleAccount
        : context.l10n.passkeyChoiceGoogleAccount;

/// "Works with Apple Passwords" / "Works with Google Password Manager",
/// or null where the keeper cannot be named.
/// The phones keep the line as it was (the framework's target platform).
String? passkeyWorksWith(BuildContext context) => switch (kIsWeb
        ? passkeyKeeper()
        : defaultTargetPlatform == TargetPlatform.iOS
            ? PasskeyKeeper.apple
            : PasskeyKeeper.google) {
      PasskeyKeeper.apple => context.l10n.passkeyChoiceWorksWithApple,
      PasskeyKeeper.google => context.l10n.passkeyChoiceWorksWithGoogle,
      PasskeyKeeper.other => null,
    };

/// Web: the system's own name for the unlock method where the app has one
/// (Face ID on an iPhone or iPad, Touch ID on a Mac), else null.
String? webBiometricMethodName(BuildContext context, {String? userAgent}) {
  if (!kIsWeb && userAgent == null) return null;
  final ua = (userAgent ?? browserUserAgent() ?? '').toLowerCase();
  if (ua.contains('iphone') || ua.contains('ipad') || ua.contains('ipod')) {
    return context.l10n.biometricFaceId;
  }
  if (ua.contains('macintosh') || ua.contains('mac os x')) {
    return context.l10n.biometricTouchId;
  }
  return null;
}
