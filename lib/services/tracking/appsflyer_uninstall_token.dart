// lib/services/tracking/appsflyer_uninstall_token.dart
//
// AppsFlyer uninstall measurement: hands the device's push token to the
// AppsFlyer SDK (`updateServerUninstallToken`) so an uninstall shows up
// against the install's campaign. iOS wants the APNs device token as hex,
// Android the FCM registration token; both come from the firebase_messaging
// plumbing the app already has.
//
// Rules:
//   * Only when notification permission is already granted (authorized or
//     provisional). Nothing here ever prompts: a missing permission means a
//     silent no-op, and the same goes for a missing token.
//   * Only while AppsFlyer may run at all (release build, analytics not
//     disabled, user opted in) — the same gate as every other AppsFlyer
//     call, so an opted-out user's token never leaves the device.
//   * Fire-and-forget, offline-safe: every failure is swallowed, the token
//     is never logged or tracked, and the same token is not re-sent.
import 'dart:async';
import 'dart:io';

import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:kute/services/tracking_service.dart';

/// The platform pieces [AppsFlyerUninstallToken] touches, injectable so the
/// gating logic is testable without Firebase or the AppsFlyer plugin.
class AppsFlyerUninstallTokenPorts {
  const AppsFlyerUninstallTokenPorts({
    required this.isIOS,
    required this.canTrack,
    required this.notificationSettings,
    required this.apnsToken,
    required this.fcmToken,
    required this.updateServerUninstallToken,
    required this.tokenRefresh,
  });

  final bool isIOS;
  final bool Function() canTrack;
  final Future<NotificationSettings> Function() notificationSettings;
  final Future<String?> Function() apnsToken;
  final Future<String?> Function() fcmToken;
  final Future<void> Function(String token) updateServerUninstallToken;
  final Stream<String> Function() tokenRefresh;

  /// Production wiring: firebase_messaging + the AppsFlyer v7 singleton.
  /// [AppsFlyerSdk.instance] is a process singleton; callers only invoke
  /// this after `AppsFlyerService.init` has set it up.
  factory AppsFlyerUninstallTokenPorts.production() =>
      AppsFlyerUninstallTokenPorts(
        isIOS: Platform.isIOS,
        canTrack: () =>
            !kDebugMode &&
            !TrackingService.isDisabled &&
            TrackingService.isOptedIn,
        notificationSettings: () =>
            FirebaseMessaging.instance.getNotificationSettings(),
        apnsToken: () => FirebaseMessaging.instance.getAPNSToken(),
        fcmToken: () => FirebaseMessaging.instance.getToken(),
        updateServerUninstallToken: (token) =>
            AppsFlyerSdk.instance.updateServerUninstallToken(token),
        tokenRefresh: () => FirebaseMessaging.instance.onTokenRefresh,
      );
}

abstract final class AppsFlyerUninstallToken {
  static String? _lastSent;
  static StreamSubscription<String>? _refreshSubscription;
  static Future<void>? _inFlight;

  /// Test-only replacement for the production ports.
  @visibleForTesting
  static AppsFlyerUninstallTokenPorts? debugPorts;

  /// The token most recently handed to AppsFlyer this process, or null.
  @visibleForTesting
  static String? get debugLastSent => _lastSent;

  /// Registers the current push token with AppsFlyer when permission is
  /// granted and a token exists. Safe to call on every boot and after a
  /// permission grant; repeated calls coalesce and an unchanged token is
  /// not re-sent. Never throws, never prompts.
  static Future<void> register() {
    final pending = _inFlight;
    if (pending != null) return pending;
    final run = _register().catchError((Object _) {}).whenComplete(() {
      _inFlight = null;
    });
    _inFlight = run;
    return run;
  }

  static Future<void> _register() async {
    final ports = debugPorts ?? AppsFlyerUninstallTokenPorts.production();
    if (!ports.canTrack()) return;
    if (!await _permissionGranted(ports)) return;
    final token = await _currentToken(ports);
    if (token == null) return;
    await _send(ports, token);
    _listenForRefresh(ports);
  }

  static Future<bool> _permissionGranted(
      AppsFlyerUninstallTokenPorts ports) async {
    try {
      final status = (await ports.notificationSettings()).authorizationStatus;
      return status == AuthorizationStatus.authorized ||
          status == AuthorizationStatus.provisional;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> _currentToken(
      AppsFlyerUninstallTokenPorts ports) async {
    try {
      final raw =
          ports.isIOS ? await ports.apnsToken() : await ports.fcmToken();
      final token = raw?.trim() ?? '';
      return token.isEmpty ? null : token;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _send(
      AppsFlyerUninstallTokenPorts ports, String token) async {
    if (token == _lastSent || !ports.canTrack()) return;
    try {
      await ports.updateServerUninstallToken(token);
      _lastSent = token;
    } catch (_) {/* best-effort; the next boot retries */}
  }

  /// Android FCM tokens rotate; keep AppsFlyer on the current one. iOS
  /// refreshes carry the FCM token, not the APNs one, so only Android
  /// forwards them.
  static void _listenForRefresh(AppsFlyerUninstallTokenPorts ports) {
    if (ports.isIOS || _refreshSubscription != null) return;
    try {
      _refreshSubscription = ports.tokenRefresh().listen((token) {
        final t = token.trim();
        if (t.isEmpty) return;
        unawaited(_send(ports, t));
      }, onError: (Object _) {});
    } catch (_) {/* no refresh tracking this session */}
  }

  /// Test-only: forget the sent token and the refresh listener.
  @visibleForTesting
  static Future<void> debugReset() async {
    _lastSent = null;
    await _refreshSubscription?.cancel();
    _refreshSubscription = null;
    _inFlight = null;
    debugPorts = null;
  }
}
