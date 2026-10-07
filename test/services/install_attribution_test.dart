import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/services/appsflyer_service.dart';
import 'package:kute/services/secure_storage.dart';
import 'package:kute/services/tracking_service.dart';

/// AppsFlyer first-launch attribution: campaign names become `$set_once`
/// person properties, and the same fields go once to the backend's
/// POST /api/v1/affiliate/attribution with the wallet session.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const posthog = MethodChannel('posthog_flutter');
  final calls = <MethodCall>[];
  final requests = <http.Request>[];
  late Directory hiveDir;

  const payload = {
    'is_first_launch': true,
    'af_status': 'Non-organic',
    'media_source': 'Facebook Ads',
    'campaign': 'launch_eu_oct',
    'campaign_id': '238471923847',
    'adset': 'lookalike_1pct',
    'adset_id': '238471923999',
    'adgroup': 'video_15s',
    'ad_id': '238471924000',
    'af_channel': 'Instagram',
    'install_time': '2026-10-01 12:34:56.789',
  };

  /// `$set_once` maps sent to PostHog.
  List<Map> setOnce() => [
        for (final c in calls)
          if (c.method == 'capture' &&
              (c.arguments as Map)['eventName'] == r'$set')
            if ((c.arguments as Map)['userPropertiesSetOnce'] case final Map m)
              m,
      ];

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('kute_attribution_');
    Hive.init(hiveDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  setUp(() async {
    dotenv.loadFromString(envString: 'BACKEND=https://backend.test');
    FlutterSecureStorage.setMockInitialValues({});
    await Hive.openBox('settings');
    await Hive.box('settings').clear();
    calls.clear();
    requests.clear();
    messenger.setMockMethodCallHandler(posthog, (call) async {
      calls.add(call);
      return null;
    });
    AppsFlyerService.clearCapturedReferrer();
    AppsFlyerService.onReferrerCaptured = null;
    AppsFlyerService.onInstallAttributionCaptured = null;
    AffiliateService.debugSessionToken = null;
    TrackingService.debugResetOptOut();
    TrackingService.setDisabled(false);
  });

  tearDown(() {
    AppsFlyerService.onInstallAttributionCaptured = null;
    AffiliateService.debugSessionToken = null;
    TrackingService.debugResetOptOut();
    TrackingService.setDisabled(true);
    messenger.setMockMethodCallHandler(posthog, null);
  });

  Future<T> withBackend<T>(Future<T> Function() body, {int status = 200}) =>
      http.runWithClient(
        body,
        () => MockClient((req) async {
          requests.add(req);
          return http.Response('{}', status);
        }),
      );

  test('maps the AppsFlyer conversion keys, names only, no ids', () {
    final a = AppsFlyerService.installAttributionFrom(payload);
    expect(a, {
      'af_media_source': 'Facebook Ads',
      'af_campaign': 'launch_eu_oct',
      'af_adset': 'lookalike_1pct',
      'af_ad': 'video_15s',
      'af_channel': 'Instagram',
      'af_status': 'Non-organic',
      'af_install_at': '2026-10-01T12:34:56.789Z',
    });
    // af_adset / af_ad win over Meta's adset / adgroup when both exist.
    expect(
        AppsFlyerService.installAttributionFrom(
            {'af_adset': 'a', 'adset': 'b', 'af_ad': 'c', 'adgroup': 'd'}),
        {'af_adset': 'a', 'af_ad': 'c'});
    // Organic installs carry only the status; empty / null values drop.
    expect(
        AppsFlyerService.installAttributionFrom(
            {'af_status': 'Organic', 'media_source': '', 'campaign': 'null'}),
        {'af_status': 'Organic'});
  });

  test('first launch sets the person properties with \$set_once', () async {
    AppsFlyerService.handleConversionDataForTest(
        {'status': 'success', 'payload': payload});
    await pumpEventQueue();

    expect(setOnce(), [
      {
        'af_media_source': 'Facebook Ads',
        'af_campaign': 'launch_eu_oct',
        'af_adset': 'lookalike_1pct',
        'af_ad': 'video_15s',
        'af_channel': 'Instagram',
        'af_status': 'Non-organic',
      }
    ]);
  });

  test('a later launch sets nothing', () async {
    AppsFlyerService.handleConversionDataForTest({
      'status': 'success',
      'payload': {...payload, 'is_first_launch': false},
    });
    await pumpEventQueue();
    expect(setOnce(), isEmpty);
  });

  test('opted out: nothing reaches PostHog or the backend', () async {
    await TrackingService.disableTracking();
    calls.clear();
    AppsFlyerService.onInstallAttributionCaptured =
        AffiliateService.queueInstallAttribution;
    AffiliateService.debugSessionToken = 'session';

    await withBackend(() async {
      AppsFlyerService.handleConversionDataForTest(
          {'status': 'success', 'payload': payload});
      await pumpEventQueue();
    });

    expect(setOnce(), isEmpty);
    expect(requests, isEmpty);
  });

  test('sent once with the session; retried after a failure', () async {
    // No session yet: queued only.
    await withBackend(() => AffiliateService.queueInstallAttribution(
        AppsFlyerService.installAttributionFrom(payload)));
    expect(requests, isEmpty);

    // A session exists, the backend fails: kept for the next session.
    AffiliateService.debugSessionToken = 'session';
    await withBackend(AffiliateService.flushInstallAttribution, status: 503);
    expect(requests, hasLength(1));

    // Next session: sent and settled.
    await withBackend(AffiliateService.flushInstallAttribution);
    expect(requests, hasLength(2));
    final req = requests.last;
    expect(req.method, 'POST');
    expect(req.url.toString(),
        'https://backend.test/api/v1/affiliate/attribution');
    expect(req.headers['Authorization'], 'Bearer session');
    expect(jsonDecode(req.body), {
      'af_media_source': 'Facebook Ads',
      'af_campaign': 'launch_eu_oct',
      'af_adset': 'lookalike_1pct',
      'af_ad': 'video_15s',
      'af_channel': 'Instagram',
      'af_status': 'Non-organic',
      'af_install_at': '2026-10-01T12:34:56.789Z',
    });

    // Never again, even if AppsFlyer delivers attribution a second time.
    await withBackend(() async {
      await AffiliateService.flushInstallAttribution();
      await AffiliateService.queueInstallAttribution({'af_status': 'Organic'});
    });
    expect(requests, hasLength(2));
    expect(await secureStorage.read(key: 'kute_install_attribution_pending'),
        isNull);
  });

  test('the first queued value wins', () async {
    await AffiliateService.queueInstallAttribution(
        {'af_status': 'Non-organic', 'af_campaign': 'first'});
    await AffiliateService.queueInstallAttribution(
        {'af_status': 'Non-organic', 'af_campaign': 'second'});
    AffiliateService.debugSessionToken = 'session';
    await withBackend(AffiliateService.flushInstallAttribution);
    expect(jsonDecode(requests.single.body),
        {'af_status': 'Non-organic', 'af_campaign': 'first'});
  });

  test('nothing is queued without af_status or af_media_source', () async {
    AffiliateService.debugSessionToken = 'session';
    await withBackend(() =>
        AffiliateService.queueInstallAttribution({'af_campaign': 'only'}));
    expect(requests, isEmpty);
    expect(await secureStorage.read(key: 'kute_install_attribution_pending'),
        isNull);
  });

  test('which responses end the retries', () {
    for (final s in [200, 201, 204, 400, 409, 422]) {
      expect(AffiliateService.installAttributionSettled(s), isTrue,
          reason: '$s');
    }
    for (final s in [401, 403, 408, 429, 500, 503]) {
      expect(AffiliateService.installAttributionSettled(s), isFalse,
          reason: '$s');
    }
  });
}
