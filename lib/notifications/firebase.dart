import 'dart:convert';
import 'package:kute/notifications/push_permission.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:kute/services/secure_storage.dart';


class FirebaseService {
  static final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  static const _storage = secureStorage;

  static Future<void> initialize() async {
    await getAndRefreshFCMToken();
    _attachMessageListeners();
  }

  /// Wire foreground + tap handlers so push retention shows up in
  /// Analytics. Topics include `prices` and `errors` today; the
  /// payload `type` field (if the backend sets it) makes the event
  /// segmentable. No body text is recorded — those can carry user
  /// PII (recipient names, addresses).
  static bool _listenersAttached = false;

  static void _attachMessageListeners() {
    // Attach once per process: a second attach would double every
    // received/opened event (and re-read the same initial message).
    if (_listenersAttached) return;
    _listenersAttached = true;
    FirebaseMessaging.onMessage.listen((message) {
      TrackingService.pushNotificationReceived(
          notificationType: _notificationType(message));
    });
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      TrackingService.pushNotificationOpened(
          notificationType: _notificationType(message));
    });
    // The very first launch from a notification tap lands here —
    // onMessageOpenedApp only fires for warm/cold app-to-foreground.
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message == null) return;
      TrackingService.pushNotificationOpened(
          notificationType: _notificationType(message));
    }).catchError((_) {});
  }

  static final RegExp _categoricalType = RegExp(r'^[a-z][a-z0-9_]{0,39}$');

  /// Categorical push kind for analytics. Only a short snake_case payload
  /// `type` key passes through; anything else (free text, ids, URLs) is
  /// bucketed as 'other', and a missing type falls back to the topic the
  /// message came from ('prices' / 'errors') or 'direct'. Never the title,
  /// body or any other payload field.
  static String _notificationType(RemoteMessage message) {
    final raw = message.data['type']?.toString().trim().toLowerCase();
    if (raw != null && raw.isNotEmpty) {
      return _categoricalType.hasMatch(raw) ? raw : 'other';
    }
    final from = message.from ?? '';
    if (from.startsWith('/topics/')) {
      final topic = from.substring('/topics/'.length).toLowerCase();
      return _categoricalType.hasMatch(topic) ? 'topic_$topic' : 'topic_other';
    }
    return 'direct';
  }

  /// Shows the OS push prompt and wires a grant (topics + AppsFlyer
  /// uninstall token). The automatic once-per-install ask lives in
  /// [PushPermission.requestOnceFromHome]; this is the manual entry.
  static Future<void> requestNotificationPermissions(
      {String surface = PushPermission.settingsSurface}) async {
    await PushPermission.request(surface: surface);
  }

  static Future<void> storeTokenOnbackend() async {
    try {
      String? jwt = await _storage.read(key: 'backendJwt');
      if (jwt == null || jwt.isEmpty) return;

      String? token = await _firebaseMessaging.getToken();

      if (token != null && token.isNotEmpty) {
        await sendTokenToBackend(jwt, token);
        await storeFCMToken(token);
      }
    } catch (_) {
      // intentionally empty
    }
  }

  static Future<void> getAndRefreshFCMToken() async {
    try {
      String? jwt = await _storage.read(key: 'backendJwt');
      if (jwt == null || jwt.isEmpty) return;

      _firebaseMessaging.onTokenRefresh.listen((newToken) async {
        if (jwt.isNotEmpty) {
          await sendTokenToBackend(jwt, newToken);
          await storeFCMToken(newToken);
        }
      });
    } catch (_) {
      // intentionally empty
    }
  }

  static Future<void> storeFCMToken(String token) async {
    await _storage.write(key: 'fcmToken', value: token);
  }

  static Future<void> sendTokenToBackend(String jwt, String token) async {
    try {
      await http.post(
        Uri.parse('${dotenv.env['BACKEND']!}/users/store_fcm_token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwt',
        },
        body: jsonEncode({
          'user': {
            'fcm_token': token,
          }
        }),
      );
    } catch (_) {
      // intentionally empty
    }
  }

  /// Subscribes to the app's FCM topics. Returns false (never throws)
  /// when the subscribe did not go through, so the caller can retry
  /// later instead of recording a subscription that never happened.
  static Future<bool> subscribeToTopics() async {
    try {
      await _firebaseMessaging.subscribeToTopic('prices');
      await _firebaseMessaging.subscribeToTopic('errors');
    } catch (_) {
      return false;
    }
    TrackingService.notificationSubscribed(type: 'prices');
    TrackingService.notificationSubscribed(type: 'errors');
    return true;
  }

}