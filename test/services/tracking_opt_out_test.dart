import 'dart:io';

import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/app_router.dart';
import 'package:kute/services/appsflyer_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

/// The analytics opt-out end to end, against the PostHog platform channel:
/// what reaches the SDK, what persists, and what a restart applies.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const posthog = MethodChannel('posthog_flutter');
  final calls = <MethodCall>[];
  late Directory hiveDir;

  List<String> sent() => calls.map((c) => c.method).toList();

  /// Calls that would put something on the wire (events or identity).
  List<String> outbound() => sent()
      .where(
          (m) => const {'capture', 'screen', 'identify', 'alias'}.contains(m))
      .toList();

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('kute_optout_');
    Hive.init(hiveDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await Hive.openBox('settings');
    await Hive.box('settings').clear();
    calls.clear();
    messenger.setMockMethodCallHandler(posthog, (call) async {
      calls.add(call);
      return null;
    });
    TrackingService.debugResetOptOut();
    // Behave like a release build: tests run with kDebugMode on.
    TrackingService.setDisabled(false);
  });

  tearDown(() {
    TrackingService.debugResetOptOut();
    TrackingService.setDisabled(true);
    messenger.setMockMethodCallHandler(posthog, null);
  });

  test('opted out: track, screen, identify and alias send nothing', () async {
    await TrackingService.disableTracking();
    expect(sent(), containsAllInOrder(['reset', 'disable']));
    calls.clear();

    TrackingService.track('swap_started', params: {'venue': 'spark'});
    TrackingService.screenView('home');
    TrackingService.identify('someone');
    await TrackingService.identifyWithAffiliate('ABCD1234');
    TrackingService.setUserProperty('theme', 'dark');
    await Future<void>.delayed(const Duration(milliseconds: 700));

    expect(outbound(), isEmpty);
    expect(TrackingService.isDisabled, isTrue);
    expect(TrackingService.isOptedIn, isFalse);
    expect(Hive.box('settings').get('analytics_opt_in'), isFalse);
  });

  test('opted out: the beforeSend backstop drops Dart-captured events',
      () async {
    final event = PostHogEvent(event: r'$screen', properties: {});
    expect(TrackingService.dropWhenMuted(event), same(event));
    await TrackingService.disableTracking();
    expect(TrackingService.dropWhenMuted(event), isNull);
  });

  test('a person-property batch pending at opt-out is dropped, not sent later',
      () async {
    TrackingService.setUserProperty('wallet_count', '2');
    await TrackingService.disableTracking();
    expect(TrackingService.debugPendingUserProperties, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(outbound(), isEmpty);

    await TrackingService.enableTracking();
    calls.clear();
    TrackingService.setUserProperty('theme', 'dark');
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final set = calls.singleWhere((c) => c.method == 'capture');
    expect(jsonSafe(set)['eventName'], r'$set');
    expect(jsonSafe(set).toString(), isNot(contains('wallet_count')));
  });

  test('the choice survives a restart and applies before any event', () async {
    await TrackingService.disableTracking();

    // Simulate a cold start: in-memory state gone, Hive still on disk.
    TrackingService.debugResetOptOut();
    await Hive.close();
    await Hive.openBox('settings');
    calls.clear();

    TrackingService.applyStoredOptOut();
    TrackingService.track('app_opened');
    await pumpEventQueue();

    expect(TrackingService.isDisabled, isTrue);
    expect(outbound(), isEmpty);
    expect(sent(), contains('disable'));
  });

  test('opting back in resumes tracking and identity', () async {
    await TrackingService.disableTracking();
    calls.clear();

    await TrackingService.enableTracking();
    expect(sent(), contains('enable'));
    expect(TrackingService.isDisabled, isFalse);
    expect(Hive.box('settings').get('analytics_opt_in'), isTrue);

    TrackingService.track('swap_started');
    TrackingService.identify('someone');
    await pumpEventQueue();
    expect(outbound(), containsAll(['capture', 'identify']));

    // A restart keeps the opt-in.
    TrackingService.debugResetOptOut();
    TrackingService.applyStoredOptOut();
    expect(TrackingService.isDisabled, isFalse);
  });

  test('opting back in re-identifies with the last affiliate code', () async {
    await TrackingService.disableTracking();
    await TrackingService.identifyWithAffiliate('ABCD1234');
    expect(outbound(), isEmpty);

    await TrackingService.enableTracking();
    await pumpEventQueue();
    final identify = calls.lastWhere((c) => c.method == 'identify');
    expect(identify.arguments.toString(), contains('ABCD1234'));
  });

  test('opting in never un-mutes a debug build', () async {
    TrackingService.setDisabled(true);
    await TrackingService.enableTracking();
    TrackingService.track('swap_started');
    await pumpEventQueue();
    expect(TrackingService.isDisabled, isTrue);
    expect(sent(), isNot(contains('enable')));
    expect(outbound(), isEmpty);
  });

  group('UTM capture', () {
    test('a deep link sets only the utm_* person properties', () async {
      TrackingService.captureUtmFromUri(
          Uri.parse('https://kute.onelink.me/AbCd/REFCODE1?utm_source=twitter'
              '&utm_medium=social&utm_campaign=launch&utm_content=%20v2%20'
              '&deep_link_value=REFCODE1&af_sub1=bc1qxy2kgdygjrsqtzq2n0yrf2493p'
              '83kkfjhx0wlh&pid=x'));

      expect(TrackingService.debugPendingUserProperties, {
        'utm_source': 'twitter',
        'utm_medium': 'social',
        'utm_campaign': 'launch',
        'utm_content': 'v2',
      });

      await Future<void>.delayed(const Duration(milliseconds: 700));
      final set = calls.singleWhere((c) => c.method == 'capture');
      final text = set.arguments.toString();
      expect(text, contains('utm_source'));
      for (final leak in ['REFCODE1', 'bc1q', 'onelink', 'deep_link_value']) {
        expect(text, isNot(contains(leak)));
      }
    });

    test(
        'the router: one link open is one deep_link_opened plus the utm_* '
        'properties', () {
      final events = <String>[];
      TrackingService.debugTrackObserver = (e, _) => events.add(e);
      addTearDown(() => TrackingService.debugTrackObserver = null);
      final link =
          Uri.parse('kute://open?deep_link_value=ROUTER01&utm_source=podcast'
              '&utm_medium=audio&utm_campaign=ep42');

      // go_router may evaluate the redirect more than once for one link.
      AppRouter.handleIncomingLink(link);
      AppRouter.handleIncomingLink(link);

      expect(events.where((e) => e == 'deep_link_opened'), hasLength(1));
      expect(TrackingService.debugPendingUserProperties, {
        'utm_source': 'podcast',
        'utm_medium': 'audio',
        'utm_campaign': 'ep42',
      });
    });

    test('a link without utm_* parameters sets nothing', () {
      TrackingService.captureUtmFromUri(
          Uri.parse('kute://open?deep_link_value=REFCODE1'));
      expect(TrackingService.debugPendingUserProperties, isEmpty);
    });

    test('the AppsFlyer deep-link handler passes only utm_* values', () {
      AppsFlyerService.handleDeepLinkForTest(DeepLinkResult(
        status: DeepLinkStatus.found,
        deepLink: DeepLink(const {
          'deep_link_value': 'REFCODE1',
          'utm_source': 'newsletter',
          'utm_campaign': 'october',
          'media_source': 'af_app_invites',
          'click_http_referrer': 'https://example.com/path',
        }),
      ));
      expect(TrackingService.debugPendingUserProperties, {
        'utm_source': 'newsletter',
        'utm_campaign': 'october',
      });
    });

    test('opted out: a deep link sets nothing', () async {
      await TrackingService.disableTracking();
      TrackingService.captureUtmFromUri(
          Uri.parse('https://kute.app/x?utm_source=twitter'));
      expect(TrackingService.debugPendingUserProperties, isEmpty);
    });
  });
}

Map<Object?, Object?> jsonSafe(MethodCall call) =>
    (call.arguments as Map).cast<Object?, Object?>();
