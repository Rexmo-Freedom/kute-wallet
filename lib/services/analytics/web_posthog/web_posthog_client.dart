/// Web only: a small pure-Dart PostHog client.
///
/// `posthog_flutter`'s web side only forwards to `window.posthog`
/// (posthog-js), which Kute never loads: the page holds a wallet and no
/// third-party script runs in its origin. This client posts the same
/// events straight to PostHog's public batch API (`POST {host}/batch/`)
/// with the browser's fetch (through `package:http`), so the web build
/// reports like the phones without any script of PostHog's in the page.
///
/// It is plain Dart: everything the browser provides (user agent, screen
/// size, the current route, page-hide hooks, `sendBeacon`, the plain
/// IndexedDB store) comes in through [WebPosthogEnv], so the tests run in
/// the VM. `web_posthog_platform.dart` plugs it in as `posthog_flutter`'s
/// platform on web; iOS and Android never construct it.
///
/// Collection only: no feature flags, surveys, replay, remote config or
/// anything rendered. Nothing the house rules forbid is added here: the
/// standard properties are the browser and OS family, the screen size, the
/// route path (never a query, fragment or route parameter) and the app
/// version. Event properties arrive already scrubbed by TrackingService and
/// the `beforeSend` hooks the phones use.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// What the browser gives the client. The web binding is in
/// `web_posthog_web.dart`; tests pass a fake.
abstract class WebPosthogEnv {
  String get userAgent;
  int? get screenWidth;
  int? get screenHeight;

  /// `location.href` at the time of the event. Only [analyticsUrl] of it
  /// ever leaves.
  String get locationHref;

  /// Calls [onHidden] when the page goes to the background or is being
  /// unloaded (`visibilitychange` to hidden, `pagehide`), and [onVisible]
  /// when it comes back.
  void listenPageLifecycle({
    required void Function() onHidden,
    required void Function() onVisible,
  });

  /// `navigator.sendBeacon(url, body)` as `text/plain`; false when the
  /// browser refused it (too big, not available).
  bool sendBeacon(String url, String body);

  /// The plain (non-secret) store: IndexedDB on web. Never localStorage.
  Future<String?> readValue(String key);
  Future<void> writeValue(String key, String value);

  /// `version`, `build` of the app, or null when unknown.
  Future<({String version, String build})?> appVersion();
}

/// One queued event, already stamped with its distinct id once known.
class _Queued {
  _Queued(this.body, this.distinctId);
  final Map<String, Object?> body;
  String? distinctId;
  int attempts = 0;
}

class WebPosthogClient {
  WebPosthogClient({
    required this.env,
    http.Client? httpClient,
    DateTime Function()? clock,
    Random? random,
  })  : _http = httpClient ?? http.Client(),
        _clock = clock ?? DateTime.now,
        _random = random ?? Random.secure();

  final WebPosthogEnv env;
  final http.Client _http;
  final DateTime Function() _clock;
  final Random _random;

  // ── Tunables (the mobile SDKs' defaults) ─────────────────────────────

  /// Flush once this many events wait (SDK `flushAt`).
  static const int flushAt = 20;

  /// Flush at least this often while anything waits (SDK flush interval).
  static const Duration flushInterval = Duration(seconds: 30);

  /// Events per request (SDK `maxBatchSize`).
  static const int maxBatchSize = 50;

  /// Oldest events go beyond this (SDK `maxQueueSize`).
  static const int maxQueueSize = 1000;

  /// A batch that failed this many times on the network is dropped.
  static const int maxAttempts = 5;

  /// Backoff after a failed send: 2 s, 4 s, 8 s, ... capped.
  static const Duration backoffBase = Duration(seconds: 2);
  static const Duration backoffCap = Duration(minutes: 2);

  /// Session rotation after this long without an event (the SDKs' 30 min).
  static const Duration sessionIdle = Duration(minutes: 30);

  /// `sendBeacon` refuses bodies above 64 KiB; stay well under.
  static const int beaconMaxBytes = 60 * 1024;

  /// Persisted identity: anonymous id, current distinct id, identified.
  static const String identityKey = 'analytics_posthog_identity';

  static const String libName = 'kute-web';
  static const String libVersion = '1.0.0';

  // ── Config ───────────────────────────────────────────────────────────

  String? _apiKey;
  Uri? _batchUrl;
  bool _lifecycleEvents = false;

  // ── State ────────────────────────────────────────────────────────────

  bool _ready = false;
  final Completer<void> _readyCompleter = Completer<void>();
  bool _optedOut = false;
  String? _anonId;
  String? _distinctId;
  bool _identified = false;
  final Map<String, Object> _superProperties = {};
  ({String version, String build})? _appVersion;

  final List<_Queued> _queue = [];
  Timer? _flushTimer;
  Timer? _retryTimer;
  bool _sending = false;
  int _failures = 0;

  String? _sessionId;
  DateTime? _sessionLastSeen;
  bool _hidden = false;

  bool get isOptedOut => _optedOut;
  String? get distinctId => _distinctId;
  bool get isIdentified => _identified;

  @visibleForTesting
  int get queueLength => _queue.length;

  @visibleForTesting
  Map<String, Object> get superProperties => Map.unmodifiable(_superProperties);

  /// Loads the stored identity and starts the page hooks. Captures made
  /// before this completes are kept and sent after it.
  Future<void> setup({
    required String apiKey,
    required String host,
    bool captureLifecycleEvents = false,
  }) async {
    _apiKey = apiKey;
    final base = host.endsWith('/') ? host.substring(0, host.length - 1) : host;
    _batchUrl = Uri.parse('$base/batch/');
    _lifecycleEvents = captureLifecycleEvents;
    try {
      _appVersion = await env.appVersion();
    } catch (_) {}
    await _loadIdentity();
    for (final q in _queue) {
      q.distinctId ??= _distinctId;
      if (_identified) {
        (q.body['properties'] as Map).remove(r'$process_person_profile');
      }
    }
    _ready = true;
    if (!_readyCompleter.isCompleted) _readyCompleter.complete();
    try {
      env.listenPageLifecycle(onHidden: _onHidden, onVisible: _onVisible);
    } catch (_) {}
    if (_lifecycleEvents) {
      await _lifecycle('Application Opened', {'from_background': false});
    }
    _scheduleFlush();
  }

  // ── Identity ─────────────────────────────────────────────────────────

  Future<void> _loadIdentity() async {
    try {
      final raw = await env.readValue(identityKey);
      if (raw != null) {
        final m = jsonDecode(raw);
        if (m is Map &&
            m['anon_id'] is String &&
            m['distinct_id'] is String &&
            (m['anon_id'] as String).isNotEmpty &&
            (m['distinct_id'] as String).isNotEmpty) {
          _anonId = m['anon_id'] as String;
          _distinctId = m['distinct_id'] as String;
          _identified = m['identified'] == true;
          return;
        }
      }
    } catch (_) {}
    _newAnonymousIdentity();
    await _saveIdentity();
  }

  void _newAnonymousIdentity() {
    _anonId = uuidV7();
    _distinctId = _anonId;
    _identified = false;
  }

  Future<void> _saveIdentity() async {
    final anon = _anonId, id = _distinctId;
    if (anon == null || id == null) return;
    try {
      await env.writeValue(
          identityKey,
          jsonEncode(
              {'anon_id': anon, 'distinct_id': id, 'identified': _identified}));
    } catch (_) {/* memory only for this page */}
  }

  /// Like the mobile SDKs: from the anonymous id, an `$identify` that
  /// merges it into [userId]; the same id again only sets properties.
  Future<void> identify(
    String userId, {
    Map<String, Object>? set,
    Map<String, Object>? setOnce,
  }) async {
    if (_optedOut || userId.isEmpty) return;
    await _whenReady();
    if (userId == _distinctId && _identified) {
      if ((set?.isNotEmpty ?? false) || (setOnce?.isNotEmpty ?? false)) {
        capture(r'$set', const {}, set: set, setOnce: setOnce);
      }
      return;
    }
    final previous = _distinctId;
    final wasAnonymous = !_identified;
    _distinctId = userId;
    _identified = true;
    capture(r'$identify', {
      if (wasAnonymous && previous != null && previous != userId)
        r'$anon_distinct_id': previous,
    }, set: set, setOnce: setOnce);
    await _saveIdentity();
  }

  /// `$create_alias`: [alias] becomes another id of the current person.
  Future<void> alias(String alias) async {
    if (_optedOut || alias.isEmpty) return;
    await _whenReady();
    capture(r'$create_alias', {'alias': alias});
  }

  /// A fresh anonymous identity; unsent events and super properties go.
  Future<void> reset() async {
    _queue.clear();
    _superProperties.clear();
    _sessionId = null;
    _newAnonymousIdentity();
    await _saveIdentity();
  }

  /// identify/alias before setup wait for the stored identity instead of
  /// minting a second one (bounded: a setup that never ran gives up).
  Future<void> _whenReady() => _readyCompleter.future
      .timeout(const Duration(seconds: 5), onTimeout: () {});

  // ── Opt-out and super properties ─────────────────────────────────────

  void disable() {
    _optedOut = true;
    _queue.clear();
    _flushTimer?.cancel();
    _retryTimer?.cancel();
  }

  void enable() => _optedOut = false;

  void register(String key, Object value) => _superProperties[key] = value;
  void unregister(String key) => _superProperties.remove(key);

  // ── Capture ──────────────────────────────────────────────────────────

  /// Queues [event]. Never throws, never blocks.
  void capture(
    String event,
    Map<String, Object> properties, {
    Map<String, Object>? set,
    Map<String, Object>? setOnce,
  }) {
    if (_optedOut) return;
    try {
      final now = _clock().toUtc();
      final props = <String, Object?>{
        ..._standardProperties(now),
        ..._superProperties,
        ...properties,
        if (set != null && set.isNotEmpty) r'$set': set,
        if (setOnce != null && setOnce.isNotEmpty) r'$set_once': setOnce,
      };
      // Before identify the mobile SDKs (person profiles "identified
      // only") keep anonymous events off person profiles; same here.
      // Person-property writes keep their profile (the SDKs do the same).
      if (!_identified &&
          event != r'$identify' &&
          !props.containsKey(r'$set') &&
          !props.containsKey(r'$set_once')) {
        props[r'$process_person_profile'] = false;
      }
      _queue.add(_Queued({
        'uuid': uuidV7(now),
        'event': event,
        'properties': props,
        'timestamp': now.toIso8601String(),
      }, _ready ? _distinctId : null));
      if (_queue.length > maxQueueSize) _queue.removeAt(0);
      if (_queue.length >= flushAt) {
        unawaited(flush());
      } else {
        _scheduleFlush();
      }
    } catch (_) {/* never throw into callers */}
  }

  Map<String, Object?> _standardProperties(DateTime now) {
    final ua = env.userAgent;
    final url = analyticsUrl(env.locationHref);
    final w = env.screenWidth, h = env.screenHeight;
    final v = _appVersion;
    return {
      r'$lib': libName,
      r'$lib_version': libVersion,
      r'$os': osFamily(ua),
      r'$browser': browserFamily(ua),
      r'$device_type': deviceType(ua),
      if (w != null) r'$screen_width': w,
      if (h != null) r'$screen_height': h,
      if (url != null) r'$current_url': url.url,
      if (url != null) r'$host': url.host,
      if (url != null) r'$pathname': url.path,
      if (v != null) r'$app_version': v.version,
      if (v != null) r'$app_build': v.build,
      r'$session_id': _session(now),
      // The phones carry `platform` as a person property; on web every
      // event carries it too, so a `platform = web` event filter works.
      'platform': 'web',
    };
  }

  String _session(DateTime now) {
    final last = _sessionLastSeen;
    if (_sessionId == null ||
        last == null ||
        now.difference(last) > sessionIdle) {
      _sessionId = uuidV7(now);
    }
    _sessionLastSeen = now;
    return _sessionId!;
  }

  // ── Delivery ─────────────────────────────────────────────────────────

  void _scheduleFlush() {
    if (!_ready || _queue.isEmpty || _retryTimer != null) return;
    _flushTimer ??= Timer(flushInterval, () {
      _flushTimer = null;
      unawaited(flush());
    });
  }

  List<Map<String, Object?>> _payload(List<_Queued> items) => [
        for (final q in items)
          {
            ...q.body,
            'distinct_id': q.distinctId,
          }
      ];

  String _encode(List<_Queued> items) => jsonEncode(
        {
          'api_key': _apiKey,
          'batch': _payload(items),
          'sent_at': _clock().toUtc().toIso8601String(),
        },
        toEncodable: (Object? o) => o.toString(),
      );

  /// Sends what waits, a batch at a time. Never throws.
  Future<void> flush() => _flush(fromRetry: false);

  Future<void> _flush({required bool fromRetry}) async {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (!_ready || _sending || _optedOut || _apiKey == null) return;
    // While backing off, only the retry timer sends.
    if (_retryTimer != null && !fromRetry) return;
    _sending = true;
    try {
      while (_queue.isNotEmpty && !_optedOut) {
        final batch = _queue.take(maxBatchSize).toList();
        final ok = await _post(batch);
        if (ok == null) {
          // Network or server error: keep the batch, back off.
          for (final q in batch) {
            q.attempts++;
          }
          _queue.removeWhere((q) => q.attempts >= maxAttempts);
          _failures++;
          _scheduleRetry();
          return;
        }
        // Sent, or refused for good (4xx): either way it leaves the queue.
        _queue.removeWhere(batch.contains);
        _failures = 0;
      }
      _scheduleFlush();
    } catch (_) {
    } finally {
      _sending = false;
    }
  }

  /// true sent, false refused for good, null retry later.
  Future<bool?> _post(List<_Queued> batch) async {
    try {
      // text/plain keeps the request "simple" (no CORS preflight); PostHog
      // parses the JSON body whatever the content type.
      final res = await _http
          .post(_batchUrl!,
              headers: const {'Content-Type': 'text/plain'},
              body: _encode(batch))
          .timeout(const Duration(seconds: 15));
      final s = res.statusCode;
      if (s >= 200 && s < 300) return true;
      if (s == 408 || s == 429 || s >= 500) return null;
      return false;
    } catch (_) {
      return null;
    }
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    final exp = backoffBase * pow(2, max(0, _failures - 1)).toInt();
    final delay = exp > backoffCap ? backoffCap : exp;
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      unawaited(_flush(fromRetry: true));
    });
  }

  @visibleForTesting
  Duration? get debugNextRetryDelay {
    if (_retryTimer == null) return null;
    final exp = backoffBase * pow(2, max(0, _failures - 1)).toInt();
    return exp > backoffCap ? backoffCap : exp;
  }

  // ── Page lifecycle ───────────────────────────────────────────────────

  void _onHidden() {
    if (_hidden) return;
    _hidden = true;
    flushWithBeacon();
    if (_lifecycleEvents) {
      // The sink's hooks settle in microtasks, which still run inside
      // this page-hide task: the beacon below carries the event.
      unawaited(_lifecycle('Application Backgrounded', const {})
          .whenComplete(flushWithBeacon));
    }
  }

  void _onVisible() {
    if (!_hidden) return;
    _hidden = false;
    if (_lifecycleEvents) {
      unawaited(_lifecycle('Application Opened', {'from_background': true}));
    }
  }

  /// The lifecycle events the mobile SDKs send by themselves
  /// (`captureApplicationLifecycleEvents`). They go through [lifecycleSink]
  /// when set (the platform's `beforeSend` hooks, so a muted app drops
  /// them like any other event), else straight to [capture].
  Future<void> Function(String event, Map<String, Object> properties)?
      lifecycleSink;

  Future<void> _lifecycle(String event, Map<String, Object> props) async {
    final sink = lifecycleSink;
    if (sink == null) return capture(event, props);
    try {
      await sink(event, props);
    } catch (_) {}
  }

  /// The page may be gone in a moment: hand everything to `sendBeacon`,
  /// which the browser delivers after unload. What it refuses stays queued.
  void flushWithBeacon() {
    if (!_ready || _optedOut || _apiKey == null || _queue.isEmpty) return;
    _flushTimer?.cancel();
    _flushTimer = null;
    try {
      var start = 0;
      while (start < _queue.length) {
        var end = min(start + maxBatchSize, _queue.length);
        var body = _encode(_queue.sublist(start, end));
        while (utf8.encode(body).length > beaconMaxBytes && end - start > 1) {
          end = start + (end - start) ~/ 2;
          body = _encode(_queue.sublist(start, end));
        }
        if (!env.sendBeacon(_batchUrl.toString(), body)) break;
        start = end;
      }
      _queue.removeRange(0, start);
    } catch (_) {}
    _scheduleFlush();
  }

  // ── Ids ──────────────────────────────────────────────────────────────

  /// UUID v7 (time-ordered), as posthog-js uses for ids.
  String uuidV7([DateTime? at]) {
    final ms = (at ?? _clock()).millisecondsSinceEpoch;
    final b = List<int>.generate(16, (_) => _random.nextInt(256));
    for (var i = 0; i < 6; i++) {
      b[i] = (ms >> (8 * (5 - i))) & 0xff;
    }
    b[6] = 0x70 | (b[6] & 0x0f);
    b[8] = 0x80 | (b[8] & 0x3f);
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }
}

// ── Standard properties, without fingerprinting ──────────────────────────

/// Route path segments that are a route's own words: lower-case letters,
/// `-` and `_`. Everything else (ids, codes, numbers) is a parameter.
final RegExp _routeWord = RegExp(r'^[a-z][a-z_-]{0,39}$');

/// Route segments whose NEXT segment is always a parameter, even when it
/// happens to be all letters (`/claim/:id`, `/wallet/:walletId`,
/// `/ledger/:walletId/...`).
const Set<String> _paramParents = {'claim', 'wallet', 'ledger'};

/// The app route of [path] with every parameter replaced by `:id`, no
/// query and no fragment.
String scrubRoutePath(String path) {
  var p = path;
  final cut = p.indexOf(RegExp(r'[?#]'));
  if (cut >= 0) p = p.substring(0, cut);
  final out = <String>[];
  String? prev;
  for (final seg in p.split('/')) {
    if (seg.isEmpty) continue;
    final keep = _routeWord.hasMatch(seg) && !_paramParents.contains(prev);
    out.add(keep ? seg : ':id');
    prev = seg;
  }
  return '/${out.join('/')}';
}

/// `$current_url` / `$host` / `$pathname` for [href]: the origin plus the
/// scrubbed app route (from the `#/...` fragment of the default hash URL
/// strategy, or the path). Never a query, a fragment secret, a claim id or
/// any other route parameter.
({String url, String host, String path})? analyticsUrl(String href) {
  final uri = Uri.tryParse(href);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
  final frag = uri.fragment;
  final hashRoute = frag.startsWith('/');
  final route = scrubRoutePath(hashRoute ? frag : uri.path);
  final origin =
      '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
  return (
    url: hashRoute ? '$origin/#$route' : '$origin$route',
    host: uri.host,
    path: route,
  );
}

/// OS family from the user agent (no version).
String osFamily(String ua) {
  if (RegExp(r'iPhone|iPad|iPod').hasMatch(ua)) return 'iOS';
  if (ua.contains('Android')) return 'Android';
  if (ua.contains('CrOS')) return 'Chrome OS';
  if (ua.contains('Windows')) return 'Windows';
  if (ua.contains('Mac OS X') || ua.contains('Macintosh')) return 'Mac OS X';
  if (ua.contains('Linux')) return 'Linux';
  return 'Other';
}

/// Browser family from the user agent (no version). Order matters: most
/// browsers also claim "Chrome" and "Safari".
String browserFamily(String ua) {
  if (ua.contains('Edg/') || ua.contains('EdgiOS') || ua.contains('EdgA')) {
    return 'Microsoft Edge';
  }
  if (ua.contains('OPR/') || ua.contains('Opera')) return 'Opera';
  if (ua.contains('SamsungBrowser')) return 'Samsung Internet';
  if (ua.contains('FxiOS') || ua.contains('Firefox')) return 'Firefox';
  if (ua.contains('CriOS')) return 'Chrome iOS';
  if (ua.contains('Chrome') || ua.contains('Chromium')) return 'Chrome';
  if (ua.contains('Safari')) {
    return RegExp(r'iPhone|iPad|iPod').hasMatch(ua) ? 'Mobile Safari' : 'Safari';
  }
  return 'Other';
}

/// `Mobile`, `Tablet` or `Desktop` from the user agent.
String deviceType(String ua) {
  if (ua.contains('iPad') || (ua.contains('Android') && !ua.contains('Mobile'))) {
    return 'Tablet';
  }
  if (ua.contains('Mobi') || ua.contains('iPhone') || ua.contains('Android')) {
    return 'Mobile';
  }
  return 'Desktop';
}
