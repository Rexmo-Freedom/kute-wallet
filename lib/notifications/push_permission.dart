// lib/notifications/push_permission.dart
//
// The one place the app asks for push permission.
//
// Rules:
//   * The OS prompt is shown ONCE, automatically, the first time Home is
//     on screen after onboarding finished (wallet created or restored).
//     Never at cold start, never on the welcome or PIN screens, and never
//     a second time on its own: the `push_permission_prompted_v1` once-flag
//     records that the install already had its turn. Installs that
//     predate the flag get theirs on the first unlocked Home after the
//     update (push never worked for them either).
//   * No custom pre-prompt: the system sheet is the whole UI.
//   * Settings > Notifications shows the live status and re-asks only when
//     the OS still allows it (`notDetermined`); otherwise it opens the OS
//     app settings, and a grant made there is picked up on resume.
//   * After any grant the app subscribes to its FCM topics and hands the
//     push token to AppsFlyer for uninstall measurement — both idempotent,
//     so the two grant paths cannot double-register.
//   * Analytics: `push_permission_requested {surface}` right before the
//     prompt and `push_permission_result {status}` after it. No token, no
//     per-setting detail.
import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:kute/notifications/firebase.dart';
import 'package:kute/services/once_flags_service.dart';
import 'package:kute/services/tracking/appsflyer_uninstall_token.dart';
import 'package:kute/services/tracking_service.dart';

/// Coarse push-permission state, the same three buckets the analytics
/// `status` property uses.
enum PushPermissionStatus { granted, provisional, denied, notDetermined }

/// Platform pieces [PushPermission] touches, injectable so the gating
/// logic is testable without Firebase or the AppsFlyer plugin.
class PushPermissionPorts {
  const PushPermissionPorts({
    required this.currentStatus,
    required this.requestPermission,
    required this.subscribeToTopics,
    required this.registerUninstallToken,
  });

  final Future<AuthorizationStatus> Function() currentStatus;
  final Future<AuthorizationStatus> Function() requestPermission;
  /// True when the topic subscription went through.
  final Future<bool> Function() subscribeToTopics;
  final Future<void> Function() registerUninstallToken;

  /// Production wiring: firebase_messaging + the existing topic and
  /// AppsFlyer helpers.
  factory PushPermissionPorts.production() => PushPermissionPorts(
        currentStatus: () async => (await FirebaseMessaging.instance
                .getNotificationSettings())
            .authorizationStatus,
        requestPermission: () async =>
            (await FirebaseMessaging.instance.requestPermission())
                .authorizationStatus,
        subscribeToTopics: FirebaseService.subscribeToTopics,
        registerUninstallToken: AppsFlyerUninstallToken.register,
      );
}

abstract final class PushPermission {
  /// Once-flag: the install already had its automatic prompt.
  static const String promptedFlag = 'push_permission_prompted_v1';

  /// The surface stamped on the automatic first-Home prompt.
  static const String homeSurface = 'onboarding_home';

  /// The surface stamped on a prompt started from Settings.
  static const String settingsSurface = 'settings';

  /// Test-only replacement for the production ports.
  @visibleForTesting
  static PushPermissionPorts? debugPorts;

  static PushPermissionPorts get _ports =>
      debugPorts ?? PushPermissionPorts.production();

  /// Ask once per install, the first time Home is shown after onboarding.
  /// Every later call is a no-op, so Home can call this on every mount.
  /// Returns the outcome when a prompt ran, null when it was skipped.
  static Future<PushPermissionStatus?> requestOnceFromHome() async {
    if (!OnceFlagsService.claimOnce(promptedFlag)) return null;
    final status = await _request(surface: homeSurface);
    if (status == null) {
      // The platform never showed a sheet (no Firebase app yet, plugin
      // missing): the install has not had its turn, so let a later
      // launch try again.
      await OnceFlagsService.resetKey(promptedFlag);
      return PushPermissionStatus.denied;
    }
    return status;
  }

  /// Show the OS prompt now (or, once the OS has an answer, just read it
  /// back) and wire the grant. Never throws.
  static Future<PushPermissionStatus> request(
          {required String surface}) async =>
      await _request(surface: surface) ?? PushPermissionStatus.denied;

  /// Null when the platform call itself failed; that is still reported as
  /// a denied result so the funnel always closes.
  static Future<PushPermissionStatus?> _request(
      {required String surface}) async {
    TrackingService.pushPermissionRequested(surface: surface);
    PushPermissionStatus? status;
    try {
      status = _bucket(await _ports.requestPermission());
    } catch (_) {
      status = null;
    }
    TrackingService.pushPermissionResult(
        status: (status ?? PushPermissionStatus.denied).analyticsValue);
    if (status != null && status.isEnabled) await _onGranted();
    return status;
  }

  /// The OS-side status right now, without prompting.
  static Future<PushPermissionStatus> currentStatus() async {
    try {
      return _bucket(await _ports.currentStatus());
    } catch (_) {
      return PushPermissionStatus.notDetermined;
    }
  }

  /// Re-reads the status and, when the user turned notifications on
  /// outside the app (the OS settings page), finishes the grant wiring.
  /// Returns the status it saw.
  static Future<PushPermissionStatus> syncAfterExternalChange() async {
    final status = await currentStatus();
    if (status.isEnabled) await _onGranted();
    return status;
  }

  static Future<void> _onGranted() async {
    final ports = _ports;
    // Topic subscriptions live server-side per token, so once per install
    // is enough; the flag is only claimed after the subscribe succeeded,
    // so an offline grant retries on the next sync.
    if (!OnceFlagsService.isClaimed(_subscribedFlag)) {
      var subscribed = false;
      try {
        subscribed = await ports.subscribeToTopics();
      } catch (_) {/* retried on the next grant or resume sync */}
      if (subscribed) OnceFlagsService.claimOnce(_subscribedFlag);
    }
    // Coalesces and skips an unchanged token, so calling it here and at
    // AppsFlyer boot cannot send the token twice.
    try {
      await ports.registerUninstallToken();
    } catch (_) {/* best-effort */}
  }

  static const String _subscribedFlag = 'push_topics_subscribed_v1';

  static PushPermissionStatus _bucket(AuthorizationStatus status) {
    switch (status) {
      case AuthorizationStatus.authorized:
        return PushPermissionStatus.granted;
      case AuthorizationStatus.provisional:
        return PushPermissionStatus.provisional;
      case AuthorizationStatus.denied:
      case AuthorizationStatus.deniedPermanently:
        return PushPermissionStatus.denied;
      case AuthorizationStatus.notDetermined:
        return PushPermissionStatus.notDetermined;
    }
  }
}

extension PushPermissionStatusX on PushPermissionStatus {
  /// Authorized or provisional: the device can receive pushes.
  bool get isEnabled =>
      this == PushPermissionStatus.granted ||
      this == PushPermissionStatus.provisional;

  /// The `status` value on `push_permission_result`.
  String get analyticsValue {
    switch (this) {
      case PushPermissionStatus.granted:
        return 'granted';
      case PushPermissionStatus.provisional:
        return 'provisional';
      case PushPermissionStatus.denied:
      case PushPermissionStatus.notDetermined:
        return 'denied';
    }
  }
}
