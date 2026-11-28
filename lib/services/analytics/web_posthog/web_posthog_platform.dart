/// Web only: [WebPosthogClient] as `posthog_flutter`'s platform.
///
/// Installed in place of the plugin's own web implementation (which only
/// forwards to a posthog-js the app never loads), so every existing caller
/// keeps working unchanged: TrackingService's `Posthog()` calls, the
/// router's `PosthogObserver` screen views, the opt-out's disable/reset.
/// `beforeSend` runs here exactly as the plugin's mobile side runs it
/// before the platform channel (TrackingService.dropWhenMuted, then
/// TrackingService.sanitizeExceptionEvent).
///
/// Collection only: feature flags answer "off", surveys, replay, push and
/// exception capture are no-ops (exception capture is off on the phones
/// too; Crashlytics is the crash sink).
library;

import 'dart:async';

import 'package:posthog_flutter/posthog_flutter.dart';
// The plugin's documented extension point for a platform implementation
// (its own web side registers through it); not exported by the package.
// ignore: implementation_imports
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';

import 'package:kute/services/analytics/web_posthog/web_posthog_client.dart';

class WebPosthogPlatform extends PosthogFlutterPlatformInterface {
  WebPosthogPlatform(this.client) {
    client.lifecycleSink = (event, props) => _capture(event, props);
  }

  final WebPosthogClient client;
  List<BeforeSendCallback> _beforeSend = const [];

  /// Runs the config's `beforeSend` hooks in order; null drops the event,
  /// a throwing hook drops it too (the plugin's policy).
  Future<PostHogEvent?> _applyBeforeSend(PostHogEvent event) async {
    var current = event;
    for (final hook in _beforeSend) {
      try {
        final out = await hook(current);
        if (out == null) return null;
        current = out;
      } catch (_) {
        return null;
      }
    }
    return current;
  }

  Future<void> _capture(
    String eventName,
    Map<String, Object>? properties, {
    Map<String, Object>? set,
    Map<String, Object>? setOnce,
  }) async {
    try {
      final event = await _applyBeforeSend(PostHogEvent(
        event: eventName,
        properties: properties == null ? <String, Object>{} : {...properties},
        userProperties: set,
        userPropertiesSetOnce: setOnce,
      ));
      if (event == null) return;
      client.capture(
        event.event,
        event.properties ?? const {},
        set: event.userProperties,
        setOnce: event.userPropertiesSetOnce,
      );
    } catch (_) {/* never throw into callers */}
  }

  @override
  Future<void> setup(PostHogConfig config) async {
    _beforeSend = List.of(config.beforeSend);
    await client.setup(
      apiKey: config.projectToken,
      host: config.host,
      captureLifecycleEvents: config.captureApplicationLifecycleEvents,
    );
  }

  @override
  Future<void> capture({
    required String eventName,
    Map<String, Object>? properties,
    Map<String, Object>? userProperties,
    Map<String, Object>? userPropertiesSetOnce,
  }) =>
      _capture(eventName, properties,
          set: userProperties, setOnce: userPropertiesSetOnce);

  @override
  Future<void> screen({
    required String screenName,
    Map<String, Object>? properties,
  }) =>
      _capture(r'$screen', {...?properties, r'$screen_name': screenName});

  @override
  Future<void> identify({
    required String userId,
    Map<String, Object>? userProperties,
    Map<String, Object>? userPropertiesSetOnce,
  }) =>
      client.identify(userId,
          set: userProperties, setOnce: userPropertiesSetOnce);

  @override
  Future<void> setPersonProperties({
    Map<String, Object>? userPropertiesToSet,
    Map<String, Object>? userPropertiesToSetOnce,
  }) =>
      _capture(r'$set', const {},
          set: userPropertiesToSet, setOnce: userPropertiesToSetOnce);

  @override
  Future<void> alias({required String alias}) => client.alias(alias);

  @override
  Future<String> getDistinctId() async => client.distinctId ?? '';

  @override
  Future<void> reset() => client.reset();

  @override
  Future<void> disable() async => client.disable();

  @override
  Future<void> enable() async => client.enable();

  @override
  Future<bool> isOptOut() async => client.isOptedOut;

  @override
  Future<void> debug(bool enabled) async {}

  @override
  Future<void> register(String key, Object value) async =>
      client.register(key, value);

  @override
  Future<void> unregister(String key) async => client.unregister(key);

  @override
  Future<void> flush() => client.flush();

  @override
  Future<void> close() => client.flush();

  // ── Not on web (collection only) ─────────────────────────────────────

  @override
  Future<void> captureLog({
    required String body,
    PostHogLogSeverity level = PostHogLogSeverity.info,
    Map<String, Object>? attributes,
    String? traceId,
    String? spanId,
    int? traceFlags,
  }) async {}

  @override
  Future<void> openUrl(String url) async {}

  @override
  Future<void> registerPushNotificationToken(String deviceToken,
      {String? appId}) async {}

  @override
  Future<void> unregisterPushNotificationToken() async {}

  @override
  Future<void> capturePushNotificationOpened({
    String? title,
    String? subtitle,
    String? body,
    Map<String, Object?>? payload,
    String? action,
  }) async {}

  @override
  Future<bool> isFeatureEnabled(String key) async => false;

  @override
  Future<void> reloadFeatureFlags() async {}

  @override
  Future<void> setPersonPropertiesForFlags(
      Map<String, Object> userProperties) async {}

  @override
  Future<void> resetPersonPropertiesForFlags() async {}

  @override
  Future<void> setGroupPropertiesForFlags(
      String groupType, Map<String, Object> groupProperties) async {}

  @override
  Future<void> resetGroupPropertiesForFlags({String? groupType}) async {}

  @override
  Future<void> showSurvey(Map<String, dynamic> survey) async {}

  @override
  Future<void> group({
    required String groupType,
    required String groupKey,
    Map<String, Object>? groupProperties,
  }) async {}

  @override
  Future<Object?> getFeatureFlag({required String key}) async => null;

  @override
  Future<Object?> getFeatureFlagPayload({required String key}) async => null;

  @override
  Future<PostHogFeatureFlagResult?> getFeatureFlagResult({
    required String key,
    bool sendEvent = true,
  }) async =>
      null;

  @override
  Future<void> captureException({
    required Object error,
    StackTrace? stackTrace,
    Map<String, Object>? properties,
  }) async {}

  @override
  Future<void> addExceptionStep(String message,
      {Map<String, Object>? properties}) async {}

  @override
  Future<String?> getSessionId() async => null;

  @override
  Future<void> startSessionRecording({bool resumeCurrent = true}) async {}

  @override
  Future<void> stopSessionRecording() async {}

  @override
  Future<bool> isSessionReplayActive() async => false;

  @override
  Future<void> setCaptureNativeScreens(bool enabled) async {}
}
