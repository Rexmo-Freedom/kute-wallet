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

import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';

import 'package:kute/l10n/l10n.dart';

/// "Apple account" or "Google account", already localized.
String passkeyAccountName(BuildContext context) => Platform.isIOS
    ? context.l10n.passkeyChoiceAppleAccount
    : context.l10n.passkeyChoiceGoogleAccount;
