// lib/helpers/privacy_cover_bridge.dart
//
// Tells the app-switcher privacy cover the two things it cannot work
// out on its own: what Kute looks like right now, and whether the app
// resigned active because the USER left or because WE put a system
// biometric sheet on screen.
//
// Both platforms report `AppLifecycleState.inactive` while a Face ID,
// Touch ID or fingerprint sheet is up, and that is the same signal the
// app switcher gives. The cover keyed off that signal alone, so every
// face scan raised a full-screen cover behind the system prompt. A
// sheet the app itself opened is not the app leaving the screen, and
// only the code that opened it can tell the two apart: wrap the call in
// [runBiometricPrompt] and the cover skips the `inactive` edge for as
// long as the sheet is up. Leaving for real still reaches `paused` and
// `hidden` on the Flutter side and `didEnterBackground` on iOS, none of
// which a biometric sheet ever fires, so the switcher snapshot stays
// covered exactly as before.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:kute/services/secure/keychain_local.dart';
import 'package:kute/theme/app_theme.dart';

/// Shared state between the Flutter cover (`PrivacyCover`, Android) and
/// the native iOS cover (`AppDelegate.addPrivacyCover`).
class PrivacyCoverBridge {
  const PrivacyCoverBridge._();

  static const MethodChannel _channel = KeychainLocal.channel;

  /// True while at least one biometric sheet this app opened is on
  /// screen. Watched by the lifecycle handler in `app_widget.dart`.
  static final ValueNotifier<bool> promptActive = ValueNotifier<bool>(false);

  static int _depth = 0;
  static int _generation = 0;
  static bool? _lastIsDark;

  /// Overrides the platform in tests.
  @visibleForTesting
  static TargetPlatform? debugPlatform;

  @visibleForTesting
  static void debugReset() {
    _depth = 0;
    _generation++;
    _lastIsDark = null;
    promptActive.value = false;
  }

  /// The sheet's own lifecycle events land AFTER the `authenticate`
  /// future completes, so clearing the flag on the same microtask would
  /// let a trailing `inactive` raise the cover over the screen the user
  /// just approved from.
  static const Duration _settle = Duration(milliseconds: 700);

  static bool get _isIOS =>
      (debugPlatform ?? defaultTargetPlatform) == TargetPlatform.iOS;

  /// Runs [body] with the privacy cover told to sit out the `inactive`
  /// edge the system biometric sheet causes. Rethrows whatever [body]
  /// throws, and always clears the flag.
  static Future<T> run<T>(Future<T> Function() body) async {
    _depth++;
    _generation++;
    promptActive.value = true;
    await _send(true);
    try {
      return await body();
    } finally {
      _release();
    }
  }

  static void _release() {
    if (_depth > 0) _depth--;
    if (_depth != 0) return;
    final generation = ++_generation;
    Future<void>.delayed(_settle, () {
      if (_depth != 0 || generation != _generation) return;
      promptActive.value = false;
      unawaited(_send(false));
    });
  }

  /// Hands the native iOS cover the app's own background colour and
  /// mode. `UIColor.systemBackground` follows the DEVICE appearance, so
  /// a charcoal Kute on a light-mode phone covered itself in white.
  /// Cheap to call from `build`: it only crosses the channel when the
  /// resolved mode actually changes.
  static void syncTheme({required bool isDark}) {
    if (_lastIsDark == isDark) return;
    _lastIsDark = isDark;
    if (!_isIOS) return;
    final colors =
        isDark ? AppColorsExtension.dark() : AppColorsExtension.light();
    unawaited(_invoke('setPrivacyCoverStyle', {
      'background': colors.background.toARGB32(),
      'dark': isDark,
    }));
  }

  static Future<void> _send(bool active) async {
    if (!_isIOS) return;
    await _invoke('setBiometricPromptActive', {'active': active});
  }

  static Future<void> _invoke(String method, Map<String, Object?> args) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } catch (_) {
      // An older native build without these methods just keeps the
      // previous behaviour; it must never break an unlock.
    }
  }
}

/// Marks [body] as a biometric prompt this app opened, so the privacy
/// cover stays down while the system sheet is on screen.
Future<T> runBiometricPrompt<T>(Future<T> Function() body) =>
    PrivacyCoverBridge.run(body);
