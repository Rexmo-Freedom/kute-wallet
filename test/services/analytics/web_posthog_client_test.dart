import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/services/analytics/web_posthog/web_posthog_client.dart';
import 'package:kute/services/analytics/web_posthog/web_posthog_platform.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
// ignore: implementation_imports
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';

const _chromeMac =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
const _safariIphone =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1';
const _firefoxWin =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:133.0) Gecko/20100101 Firefox/133.0';
const _edge =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like '
    'Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0';
const _androidChrome =
    'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like '
    'Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

class _FakeEnv implements WebPosthogEnv {
  final Map<String, String> store = {};
  final List<String> beacons = [];
  bool beaconAccepts = true;
  void Function()? hidden;
  void Function()? visible;
  String href = 'https://wallet.example/#/home';

  @override
  String get userAgent => _chromeMac;
  @override
  int? get screenWidth => 1440;
  @override
  int? get screenHeight => 900;
  @override
  String get locationHref => href;

  @override
  void listenPageLifecycle({
    required void Function() onHidden,
    required void Function() onVisible,
  }) {
    hidden = onHidden;
    visible = onVisible;
  }

  @override
  bool sendBeacon(String url, String body) {
    if (!beaconAccepts) return false;
    beacons.add(body);
    return true;
  }

  @override
  Future<String?> readValue(String key) async => store[key];
  @override
  Future<void> writeValue(String key, String value) async =>
      store[key] = value;
  @override
  Future<({String version, String build})?> appVersion() async =>
      (version: '2.2.0', build: '95');
}

/// Records every POST; [respond] decides the status (or throws).
class _Server {
  final List<Map<String, dynamic>> bodies = [];
  final List<Uri> urls = [];
  FutureOr<http.Response> Function(int n) respond =
      (_) => http.Response('{"status":1}', 200);

  late final MockClient client = MockClient((req) async {
    urls.add(req.url);
    bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
    return respond(bodies.length);
  });

  List<Map<String, dynamic>> get events => [
        for (final b in bodies)
          for (final e in b['batch'] as List) e as Map<String, dynamic>
      ];
}

WebPosthogClient _client(_FakeEnv env, _Server server) =>
    WebPosthogClient(env: env, httpClient: server.client);

Future<void> _setup(WebPosthogClient c, {bool lifecycle = false}) => c.setup(
    apiKey: 'phc_test', host: 'https://m.example', captureLifecycleEvents: lifecycle);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('batching', () {
    test('waits for 20 events or 30 s, then posts one batch', () {
      fakeAsync((async) {
        final env = _FakeEnv(), server = _Server();
        final c = _client(env, server);
        _setup(c);
        async.flushMicrotasks();
        for (var i = 0; i < 5; i++) {
          c.capture('wallet_opened', {'n': i});
        }
        async.elapse(const Duration(seconds: 29));
        expect(server.bodies, isEmpty);
        async.elapse(const Duration(seconds: 2));
        expect(server.bodies, hasLength(1));
        expect(server.urls.single.toString(), 'https://m.example/batch/');
        final body = server.bodies.single;
        expect(body['api_key'], 'phc_test');
        expect(body['sent_at'], isA<String>());
        final batch = body['batch'] as List;
        expect(batch, hasLength(5));
        final first = batch.first as Map<String, dynamic>;
        expect(first['event'], 'wallet_opened');
        expect(first['uuid'], isA<String>());
        expect(first['distinct_id'], c.distinctId);
        final props = first['properties'] as Map<String, dynamic>;
        expect(props[r'$lib'], 'kute-web');
        expect(props[r'$os'], 'Mac OS X');
        expect(props[r'$browser'], 'Chrome');
        expect(props[r'$screen_width'], 1440);
        expect(props[r'$current_url'], 'https://wallet.example/#/home');
        expect(props[r'$app_version'], '2.2.0');
        expect(props['platform'], 'web');
        expect(props.containsKey(r'$referrer'), isFalse);
        expect(c.queueLength, 0);

        for (var i = 0; i < 20; i++) {
          c.capture('e', const {});
        }
        async.flushMicrotasks();
        expect(server.bodies, hasLength(2), reason: '20 events flush at once');
      });
    });

    test('splits a long queue into batches of 50', () {
      fakeAsync((async) {
        final env = _FakeEnv(), server = _Server();
        final c = _client(env, server);
        // Captured before setup: kept, then sent once the identity is known.
        for (var i = 0; i < 120; i++) {
          c.capture('e', const {});
        }
        _setup(c);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 31));
        expect(server.bodies.map((b) => (b['batch'] as List).length).toList(),
            [50, 50, 20]);
        expect(server.events.every((e) => e['distinct_id'] == c.distinctId),
            isTrue);
      });
    });

    test('captures never throw, even with odd property values', () {
      final c = _client(_FakeEnv(), _Server());
      expect(() => c.capture('e', {'when': DateTime(2026)}), returnsNormally);
    });
  });

  group('flush on hide', () {
    test('page hidden hands the queue to sendBeacon', () {
      fakeAsync((async) {
        final env = _FakeEnv(), server = _Server();
        final c = _client(env, server);
        _setup(c, lifecycle: true);
        async.flushMicrotasks();
        c.capture('screen_like', const {});
        env.hidden!();
        async.flushMicrotasks();
        expect(server.bodies, isEmpty);
        expect(env.beacons, isNotEmpty);
        final sent = [
          for (final b in env.beacons)
            for (final e in jsonDecode(b)['batch'] as List) e['event']
        ];
        expect(sent, ['Application Opened', 'screen_like', 'Application Backgrounded']);
        expect(c.queueLength, 0);
        // Back to the foreground: Application Opened, from background.
        env.visible!();
        expect(c.queueLength, 1);
      });
    });

    test('a refused beacon keeps the events for the next flush', () {
      fakeAsync((async) {
        final env = _FakeEnv()..beaconAccepts = false;
        final server = _Server();
        final c = _client(env, server);
        _setup(c);
        async.flushMicrotasks();
        c.capture('e', const {});
        env.hidden!();
        expect(c.queueLength, 1);
        async.elapse(const Duration(seconds: 31));
        expect(server.events, hasLength(1));
      });
    });
  });

  group('retry', () {
    test('backs off on 5xx and network errors, then delivers', () {
      fakeAsync((async) {
        final env = _FakeEnv(), server = _Server();
        server.respond = (n) {
          if (n == 1) return http.Response('', 503);
          if (n == 2) throw http.ClientException('offline');
          return http.Response('{"status":1}', 200);
        };
        final c = _client(env, server);
        _setup(c);
        async.flushMicrotasks();
        c.capture('e', const {});
        unawaited(c.flush());
        async.flushMicrotasks();
        expect(server.bodies, hasLength(1));
        expect(c.debugNextRetryDelay, const Duration(seconds: 2));
        // A capture storm while backing off does not jump the timer.
        for (var i = 0; i < 25; i++) {
          c.capture('e', const {});
        }
        async.flushMicrotasks();
        expect(server.bodies, hasLength(1));
        async.elapse(const Duration(seconds: 2));
        expect(server.bodies, hasLength(2));
        expect(c.debugNextRetryDelay, const Duration(seconds: 4));
        async.elapse(const Duration(seconds: 4));
        expect(c.queueLength, 0);
        // The same event uuid went each time: PostHog dedupes the retry.
        final uuids = server.bodies
            .map((b) => ((b['batch'] as List).first as Map)['uuid'])
            .toSet();
        expect(uuids, hasLength(1));
      });
    });

    test('drops a batch after the attempt cap', () {
      fakeAsync((async) {
        final env = _FakeEnv(), server = _Server();
        server.respond = (_) => throw http.ClientException('offline');
        final c = _client(env, server);
        _setup(c);
        async.flushMicrotasks();
        c.capture('e', const {});
        unawaited(c.flush());
        async.elapse(const Duration(minutes: 10));
        expect(server.bodies, hasLength(WebPosthogClient.maxAttempts));
        expect(c.queueLength, 0);
      });
    });

    test('a 4xx is final: no retry', () {
      fakeAsync((async) {
        final env = _FakeEnv(), server = _Server();
        server.respond = (_) => http.Response('bad', 400);
        final c = _client(env, server);
        _setup(c);
        async.flushMicrotasks();
        c.capture('e', const {});
        unawaited(c.flush());
        async.elapse(const Duration(minutes: 5));
        expect(server.bodies, hasLength(1));
        expect(c.queueLength, 0);
      });
    });
  });

  group('identity', () {
    test('anonymous id persisted in the plain store, identify merges it', () {
      fakeAsync((async) {
        final env = _FakeEnv(), server = _Server();
        final c = _client(env, server);
        _setup(c);
        async.flushMicrotasks();
        final anon = c.distinctId!;
        expect(env.store.keys, [WebPosthogClient.identityKey]);
        expect(jsonDecode(env.store.values.single)['identified'], isFalse);

        c.capture('before', const {});
        unawaited(c.identify('device-uuid', set: {'affiliate_status': 'unknown'}));
        async.flushMicrotasks();
        c.capture('after', const {});
        unawaited(c.alias('ABC123'));
        async.flushMicrotasks();
        unawaited(c.flush());
        async.flushMicrotasks();

        final ev = {for (final e in server.events) e['event']: e};
        expect(ev['before']!['distinct_id'], anon);
        expect(ev['before']!['properties'][r'$process_person_profile'], false);
        expect(ev[r'$identify']!['distinct_id'], 'device-uuid');
        expect(ev[r'$identify']!['properties'][r'$anon_distinct_id'], anon);
        expect(ev[r'$identify']!['properties'][r'$set'],
            {'affiliate_status': 'unknown'});
        expect(ev['after']!['distinct_id'], 'device-uuid');
        expect(ev['after']!['properties']
            .containsKey(r'$process_person_profile'), isFalse);
        expect(ev[r'$create_alias']!['distinct_id'], 'device-uuid');
        expect(ev[r'$create_alias']!['properties']['alias'], 'ABC123');

        // A reload keeps the identity.
        final again = _client(env, server);
        _setup(again);
        async.flushMicrotasks();
        expect(again.distinctId, 'device-uuid');
        expect(again.isIdentified, isTrue);

        // Same id again: only a $set, no second $identify.
        final before = server.events.length;
        unawaited(again.identify('device-uuid', set: {'x': 1}));
        async.flushMicrotasks();
        unawaited(again.flush());
        async.flushMicrotasks();
        expect(server.events.skip(before).map((e) => e['event']), [r'$set']);
      });
    });

    test('reset: fresh anonymous id, queue and super properties gone', () {
      fakeAsync((async) {
        final env = _FakeEnv(), server = _Server();
        final c = _client(env, server);
        _setup(c);
        async.flushMicrotasks();
        unawaited(c.identify('device-uuid'));
        async.flushMicrotasks();
        c.register('app_language', 'pt');
        c.capture('e', const {});
        unawaited(c.reset());
        async.flushMicrotasks();
        expect(c.queueLength, 0);
        expect(c.superProperties, isEmpty);
        expect(c.isIdentified, isFalse);
        expect(c.distinctId, isNot('device-uuid'));
        expect(jsonDecode(env.store.values.single)['distinct_id'], c.distinctId);
      });
    });

    test('opt-out: queue dropped, nothing sent until enabled', () {
      fakeAsync((async) {
        final env = _FakeEnv(), server = _Server();
        final c = _client(env, server);
        c.disable(); // before setup, as applyStoredOptOut can be
        _setup(c, lifecycle: true);
        async.flushMicrotasks();
        c.capture('e', const {});
        env.hidden!();
        async.elapse(const Duration(minutes: 1));
        expect(server.bodies, isEmpty);
        expect(env.beacons, isEmpty);
        c.enable();
        c.capture('e', const {});
        async.elapse(const Duration(seconds: 31));
        expect(server.events.map((e) => e['event']), ['e']);
      });
    });

    test('super properties ride on every event', () {
      fakeAsync((async) {
        final env = _FakeEnv(), server = _Server();
        final c = _client(env, server);
        _setup(c);
        async.flushMicrotasks();
        c.register('app_language', 'de');
        c.capture('e', const {});
        unawaited(c.flush());
        async.flushMicrotasks();
        expect(server.events.single['properties']['app_language'], 'de');
      });
    });
  });

  group('URL scrubbing', () {
    test('route parameters, queries and fragments never leave', () {
      expect(scrubRoutePath('/claim/AbC123xyz'), '/claim/:id');
      expect(scrubRoutePath('/claim/giftcode'), '/claim/:id');
      expect(scrubRoutePath('/wallet/abcdef/settings'), '/wallet/:id/settings');
      expect(scrubRoutePath('/ledger/w1/investing-setup'),
          '/ledger/:id/investing-setup');
      expect(scrubRoutePath('/home?ref=ABC#k=secret'), '/home');
      expect(scrubRoutePath('/tx/0x742d35cc6634c0532925a3b844bc454e4438f44e'),
          '/tx/:id');
      expect(scrubRoutePath('/'), '/');
    });

    test(r'$current_url is origin + scrubbed route only', () {
      final hash = analyticsUrl(
          'https://wallet.example/#/claim/s3cr3t?k=abandon%20ability');
      expect(hash!.url, 'https://wallet.example/#/claim/:id');
      expect(hash.path, '/claim/:id');
      expect(hash.host, 'wallet.example');
      final path = analyticsUrl(
          'http://localhost:8911/settings/security?x=1#seed=abandon');
      expect(path!.url, 'http://localhost:8911/settings/security');
      expect(analyticsUrl('not a url'), isNull);
    });
  });

  group('user agent families', () {
    test('browser, OS and device type, no versions', () {
      expect(browserFamily(_chromeMac), 'Chrome');
      expect(browserFamily(_safariIphone), 'Mobile Safari');
      expect(browserFamily(_firefoxWin), 'Firefox');
      expect(browserFamily(_edge), 'Microsoft Edge');
      expect(osFamily(_safariIphone), 'iOS');
      expect(osFamily(_androidChrome), 'Android');
      expect(osFamily(_firefoxWin), 'Windows');
      expect(deviceType(_androidChrome), 'Mobile');
      expect(deviceType(_chromeMac), 'Desktop');
    });
  });

  group('through posthog_flutter, like the app', () {
    // Published test vectors only; none controls funds (same set as
    // tracking_scrubber_test.dart).
    const phrase = 'abandon ability able about above absent absorb abstract '
        'absurd abuse access accident';
    const forbidden = <String, String>{
      'xpub':
          'xpub661MyMwAqRbcFtXgS5sYJABqqG9YLmC4Q1Rdap9gSE8NqtwybGhePY2gZ29ESFjqJoCu1Rupje8YtGqsefD265TMg7usUDFdp6W1EGMcet8',
      'bc1': 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq',
      'evm': '0x742d35Cc6634C0532925a3b844Bc454e4438f44e',
      'spark':
          'sp1pgssyxmf9ayh6fm3wj7xhwqsn5dmxz5uyycrv82j97u3mrctxunjsxdzzudm2d',
      'phrase': phrase,
    };

    late PosthogFlutterPlatformInterface previous;
    setUp(() {
      previous = PosthogFlutterPlatformInterface.instance;
      TrackingService.debugSetSeedWordlist(phrase.split(' ').toSet());
      TrackingService.setDisabled(false);
    });
    tearDown(() {
      PosthogFlutterPlatformInterface.instance = previous;
      TrackingService.debugSetSeedWordlist(null);
      TrackingService.setDisabled(true);
    });

    test('no mnemonic, xpub, address or Spark address reaches the wire',
        () async {
      final env = _FakeEnv(), server = _Server();
      final client = _client(env, server);
      PosthogFlutterPlatformInterface.instance = WebPosthogPlatform(client);
      // The same hooks main.dart configures.
      final config = PostHogConfig('phc_test')
        ..host = 'https://m.example'
        ..beforeSend = [
          TrackingService.dropWhenMuted,
          TrackingService.sanitizeExceptionEvent,
        ];
      await Posthog().setup(config);

      // The app's door, then the raw plugin (a caller that forgot to scrub),
      // then a screen view: every path lands scrubbed.
      TrackingService.track('send_failed', params: {
        for (final e in forbidden.entries) 'reason_${e.key}': 'x ${e.value} y',
      });
      await Posthog().capture(eventName: 'raw_capture', properties: {
        for (final e in forbidden.entries) e.key: e.value,
      });
      await Posthog().screen(screenName: 'home');
      await pumpEventQueue();
      await client.flush();

      final wire = server.bodies.map(jsonEncode).join('\n');
      expect(server.events.map((e) => e['event']),
          containsAll(['send_failed', 'raw_capture', r'$screen']));
      for (final e in forbidden.entries) {
        expect(wire, isNot(contains(e.value)), reason: e.key);
      }
      // Shape checks, so a new kind of leak fails here too.
      expect(RegExp(r'\b[xyz](pub|prv)[1-9A-HJ-NP-Za-km-z]{100,}').hasMatch(wire),
          isFalse);
      expect(RegExp(r'\b(bc1|tb1|sp1|spt1)[02-9ac-hj-np-z]{20,}').hasMatch(wire),
          isFalse);
      expect(RegExp(r'0x[0-9a-fA-F]{40}').hasMatch(wire), isFalse);
      expect(RegExp(r'([a-z]{3,8} ){11}[a-z]{3,8}').hasMatch(wire), isFalse);
      final screen =
          server.events.firstWhere((e) => e['event'] == r'$screen');
      expect(screen['properties'][r'$screen_name'], 'home');
    });

    test('muted (debug build or opt-out): dropped by beforeSend', () async {
      final env = _FakeEnv(), server = _Server();
      final client = _client(env, server);
      PosthogFlutterPlatformInterface.instance = WebPosthogPlatform(client);
      TrackingService.setDisabled(true);
      await Posthog().setup(PostHogConfig('phc_test')
        ..host = 'https://m.example'
        ..beforeSend = [TrackingService.dropWhenMuted]);
      await Posthog().screen(screenName: 'home');
      await Posthog().capture(eventName: 'e');
      await client.flush();
      expect(server.bodies, isEmpty);
    });
  });
}
