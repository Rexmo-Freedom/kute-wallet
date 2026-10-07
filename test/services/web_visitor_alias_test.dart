import 'dart:io';

import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/app_router.dart';
import 'package:kute/services/appsflyer_service.dart';
import 'package:kute/services/tracking_service.dart';

/// The website → app identity link: the visitor's PostHog distinct id
/// arrives as `af_sub2` and is aliased onto this install exactly once.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const posthog = MethodChannel('posthog_flutter');
  final calls = <MethodCall>[];
  late Directory hiveDir;

  const webId = '0199a7c2-5b1e-7c3a-9d2f-4e5f6a7b8c9d';

  List<MethodCall> aliases() =>
      calls.where((c) => c.method == 'alias').toList();

  Map<String, Object> conversion(Map<String, Object> payload) => {
        'status': 'success',
        'payload': {'is_first_launch': true, 'af_status': 'Non-organic'}
          ..addAll(payload),
      };

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('kute_webalias_');
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
    AppsFlyerService.clearCapturedReferrer();
    AppsFlyerService.onReferrerCaptured = null;
    TrackingService.debugResetOptOut();
    TrackingService.setDisabled(false);
  });

  tearDown(() {
    TrackingService.debugResetOptOut();
    TrackingService.setDisabled(true);
    messenger.setMockMethodCallHandler(posthog, null);
  });

  test('conversion data with af_sub2 aliases the web visitor once', () async {
    AppsFlyerService.handleConversionDataForTest(
        conversion({'af_sub2': webId}));
    await pumpEventQueue();

    expect(aliases(), hasLength(1));
    expect(aliases().single.arguments, {'alias': webId});
    expect(TrackingService.debugPendingUserProperties,
        {'web_visitor_linked': true});
    // Identity only: never a referral code.
    expect(AppsFlyerService.capturedReferrer, isNull);
  });

  test('a second launch does not alias again', () async {
    AppsFlyerService.handleConversionDataForTest(
        conversion({'af_sub2': webId}));
    await pumpEventQueue();
    expect(aliases(), hasLength(1));

    // The same install data comes back on the next boot, plus a direct
    // link tap and the router's own copy of the link.
    AppsFlyerService.handleConversionDataForTest(
        conversion({'af_sub2': webId}));
    AppsFlyerService.handleDeepLinkForTest(DeepLinkResult(
      status: DeepLinkStatus.found,
      deepLink: DeepLink(const {'af_sub2': webId}),
    ));
    AppRouter.handleIncomingLink(
        Uri.parse('https://kute.onelink.me/AbCd?af_sub2=$webId'));
    await pumpEventQueue();

    expect(aliases(), hasLength(1));
  });

  test('opted out: af_sub2 never reaches PostHog', () async {
    await TrackingService.disableTracking();
    calls.clear();

    AppsFlyerService.handleConversionDataForTest(
        conversion({'af_sub2': webId}));
    await TrackingService.aliasWebVisitor(webId);
    await pumpEventQueue();

    expect(aliases(), isEmpty);
    expect(TrackingService.debugPendingUserProperties, isEmpty);
  });

  test('af_sub2 never reaches the referral-code path', () async {
    String? persisted;
    AppsFlyerService.onReferrerCaptured = (c) async => persisted = c;

    // An aliased affiliate code on the web side is still not a referrer.
    AppsFlyerService.handleConversionDataForTest(
        conversion({'af_sub2': 'PARTNER7'}));
    AppsFlyerService.handleDeepLinkForTest(DeepLinkResult(
      status: DeepLinkStatus.found,
      deepLink: DeepLink(const {'af_sub2': 'PARTNER7'}),
    ));
    AppRouter.handleIncomingLink(
        Uri.parse('kute://open?af_sub2=PARTNER7&utm_source=x'));
    await pumpEventQueue();

    expect(AppsFlyerService.capturedReferrer, isNull);
    expect(persisted, isNull);
    expect(aliases(), hasLength(1));
    expect(aliases().single.arguments, {'alias': 'PARTNER7'});
  });

  test('af_sub1 / deep_link_value still bind the referrer, not an alias',
      () async {
    AppsFlyerService.handleConversionDataForTest(
        conversion({'af_sub1': 'friend7'}));
    await pumpEventQueue();

    expect(AppsFlyerService.capturedReferrer, 'FRIEND7');
    expect(aliases(), isEmpty);
  });

  test('the Play install referrer string carries af_sub2 too', () {
    expect(
        AppsFlyerService.webVisitorIdFrom({
          'install_referrer': 'utm_source=kute&af_sub2=$webId&af_sub1=ABCD',
        }),
        webId);
    expect(
        AppsFlyerService.webVisitorIdFrom({
          'referrer': Uri.encodeComponent('af_sub2=$webId&x=1'),
        }),
        webId);
    expect(AppsFlyerService.webVisitorIdFrom({'af_sub1': 'ABCD'}), isNull);
  });

  test('only a UUID or an affiliate code looks like a web visitor id', () {
    expect(TrackingService.looksLikeWebVisitorId(webId), isTrue);
    expect(TrackingService.looksLikeWebVisitorId('PARTNER7'), isTrue);
    expect(TrackingService.looksLikeWebVisitorId(''), isFalse);
    expect(TrackingService.looksLikeWebVisitorId('ab'), isFalse);
    expect(TrackingService.looksLikeWebVisitorId('a@b.com'), isFalse);
    expect(TrackingService.looksLikeWebVisitorId('lowercase7'), isFalse);
    expect(
        TrackingService.looksLikeWebVisitorId(
            '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa'),
        isFalse);
    expect(TrackingService.looksLikeWebVisitorId('https://kute.app'), isFalse);
    expect(
        TrackingService.looksLikeWebVisitorId(
            'bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh'),
        isFalse);
  });

  test('junk in af_sub2 is ignored', () async {
    AppsFlyerService.handleConversionDataForTest(
        conversion({'af_sub2': 'not a visitor id'}));
    await pumpEventQueue();
    expect(aliases(), isEmpty);
  });
}
