/// One place that says which platform features exist where.
///
/// Platforms: iOS, Android, macOS, Windows and web. Linux is dropped; it
/// answers like Windows (desktop, no mobile-only plugins).
///
/// [PlatformCaps] decides with `kIsWeb` and `defaultTargetPlatform` only,
/// never `dart:io`'s `Platform`, which throws on web. A call site asks the
/// cap before touching a plugin, so a platform without that plugin never
/// raises MissingPluginException. iOS and Android answer true for
/// everything they had before, so the phones behave exactly as they did.
///
/// [PlatformOs] replaces `dart:io` `Platform.isIOS` / `Platform.isAndroid`
/// / `Platform.environment` reads: on native it returns `Platform`'s own
/// answer (byte-for-byte the old behaviour, tests included), on web it
/// returns false without touching `dart:io`.
library;

import 'dart:io' as io show Platform;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import 'web_biometrics.dart';

/// The platforms Kute builds for.
enum KutePlatform { ios, android, macos, windows, web }

abstract final class PlatformCaps {
  /// The platform this build runs on.
  static KutePlatform get current {
    if (kIsWeb) return KutePlatform.web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return KutePlatform.ios;
      case TargetPlatform.android:
        return KutePlatform.android;
      case TargetPlatform.macOS:
        return KutePlatform.macos;
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return KutePlatform.windows;
    }
  }

  static bool get isWeb => kIsWeb;
  static bool get _ios => current == KutePlatform.ios;
  static bool get _android => current == KutePlatform.android;
  static bool get _macos => current == KutePlatform.macos;
  static bool get _windows => current == KutePlatform.windows;
  static bool get _mobile => _ios || _android;

  /// `vibration` (Android waveform patterns). iOS and Android only.
  /// Flutter's own HapticFeedback stays everywhere (a no-op off-phone).
  static bool get hasVibration => _mobile;

  /// `in_app_review`: the store's review sheet. iOS, Android, macOS.
  /// Elsewhere "Rate the app" opens the App Store page in a new tab.
  static bool get hasInAppReview => _mobile || _macos;

  /// `appsflyer_sdk`: install attribution. iOS and Android only.
  static bool get hasAppsFlyer => _mobile;

  /// `firebase_crashlytics`: iOS, Android, macOS. Off on web and Windows.
  static bool get hasCrashlytics => _mobile || _macos;

  /// `firebase_messaging` push: iOS, Android, macOS, web. Needs a Firebase
  /// app at runtime too (see [firebaseConfigured] in main.dart): on web
  /// that only exists once web options are added to firebase_options.dart.
  static bool get hasPushNotifications => _mobile || _macos || kIsWeb;

  /// Biometric unlock. Native: `local_auth` (Face ID / Touch ID /
  /// fingerprint / Windows Hello), as before. Web: the browser's platform
  /// authenticator through WebAuthn ([WebBiometrics], a PRF key for the seed vault), only
  /// when [WebBiometrics.prime] found one at boot; otherwise the PIN is
  /// the only lock there.
  static bool get hasBiometrics => !kIsWeb || WebBiometrics.available;

  /// `webview_flutter` (in-app browser, livestream players). iOS,
  /// Android, macOS. Elsewhere links open in a new browser tab.
  static bool get hasWebView => _mobile || _macos;

  /// `flutter_contacts` (Send's contact picker). iOS, Android, macOS.
  static bool get hasContacts => _mobile || _macos;

  /// `mobile_scanner` camera QR scanning. iOS, Android, macOS, web.
  static bool get hasCamera => !_windows;

  /// `mobile_scanner`'s `analyzeImage` (a QR read from a picked photo).
  /// iOS, Android, macOS; web has no image analysis and no file path.
  static bool get hasImageQrDecode => _mobile || _macos;

  /// Bluetooth hardware wallets (Ledger, Jade) through `universal_ble`.
  /// iOS and Android as before, and web (Web Bluetooth, Chrome/Edge).
  /// macOS and Windows stay off, as they were.
  static bool get hasBluetoothHardwareWallet => _mobile || kIsWeb;

  /// Ledger over USB. Android only, as before.
  static bool get hasLedgerUsb => _android;

  /// `permission_handler`. iOS, Android, Windows, web (camera,
  /// notifications). No macOS implementation.
  static bool get hasPermissionHandler => !_macos;

  /// `path_provider` app directories. Everywhere but web (Hive uses
  /// IndexedDB there; files are handed over through share/download).
  static bool get hasFileSystem => !kIsWeb;

  /// The app's own native method channels (exit reasons, device RAM,
  /// iOS Live Activities and similar). iOS and Android only.
  static bool get hasNativeChannels => _mobile;
}

/// Web-safe stand-ins for `dart:io` `Platform` reads. On native these are
/// exactly `Platform.isIOS` and friends; on web they are false and never
/// touch `dart:io`.
abstract final class PlatformOs {
  /// The NATIVE platform, for code that talks to a native channel or
  /// the Keychain / Keystore: null in a browser, whatever the phone. On
  /// the web `defaultTargetPlatform` follows the browser (iOS in Safari
  /// on an iPhone, Android in Chrome on an Android phone), and a check
  /// against it there would call native code that does not exist (a PIN
  /// that could not be saved in a phone's browser, 24 November 2026).
  /// Styling by platform may keep reading `defaultTargetPlatform`.
  static TargetPlatform? get nativeTarget =>
      kIsWeb ? null : defaultTargetPlatform;

  static bool get isIOS => !kIsWeb && io.Platform.isIOS;
  static bool get isAndroid => !kIsWeb && io.Platform.isAndroid;
  static bool get isMacOS => !kIsWeb && io.Platform.isMacOS;
  static bool get isWindows => !kIsWeb && io.Platform.isWindows;

  /// True under `flutter test` (never on web).
  static bool get isFlutterTest =>
      !kIsWeb && io.Platform.environment.containsKey('FLUTTER_TEST');

  /// The `ios` / `android` label analytics and the backend have always
  /// received, with `web` for the browser. Native keeps the old rule
  /// (anything not iOS says android).
  static String get iosOrAndroid =>
      kIsWeb ? 'web' : (io.Platform.isIOS ? 'ios' : 'android');
}
