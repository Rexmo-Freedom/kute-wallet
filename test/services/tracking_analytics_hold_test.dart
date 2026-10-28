import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/services/tracking_service.dart';

/// PostHog's Dart `setup` runs off the first-frame path (`lib/main.dart`).
/// Until it completes, captures are held in order and released together,
/// so nothing fired during boot is lost and nothing reaches the SDK
/// before its config.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const posthog = MethodChannel('posthog_flutter');
  final calls = <MethodCall>[];
  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('kute_track_hold_');
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
    TrackingService.setDisabled(false);
  });

  tearDown(() {
    TrackingService.markAnalyticsReady();
    TrackingService.debugResetOptOut();
    TrackingService.setDisabled(true);
    messenger.setMockMethodCallHandler(posthog, null);
  });

  List<String> captured() => calls
      .where((c) => c.method == 'capture')
      .map((c) => (c.arguments as Map)['eventName'] as String)
      .toList();

  test('without a hold, captures go straight to the SDK', () async {
    TrackingService.track('app_unlocked', params: {'method': 'pin'});
    await pumpEventQueue();
    expect(captured(), ['app_unlocked']);
    expect(TrackingService.debugHeldUntilReadyCount, 0);
    expect(TrackingService.analyticsReady, completes);
  });

  test('captures made during the hold are released in order, none lost',
      () async {
    TrackingService.holdAnalyticsUntilReady();
    var ready = false;
    final readyFuture = TrackingService.analyticsReady.then((_) => ready = true);
    TrackingService.track('app_time_to_first_frame',
        params: {'duration_ms': 320});
    TrackingService.track('spark_sdk_connect', params: {'result': 'ok'});
    TrackingService.screenView('splash');
    await pumpEventQueue();
    expect(captured(), isEmpty, reason: 'held until the SDK is set up');
    expect(calls.where((c) => c.method == 'screen'), isEmpty);
    expect(TrackingService.debugHeldUntilReadyCount, 3);
    expect(ready, isFalse);

    TrackingService.markAnalyticsReady();
    await readyFuture;
    await pumpEventQueue();
    expect(captured(), ['app_time_to_first_frame', 'spark_sdk_connect']);
    expect(calls.map((c) => c.method).toList(),
        ['capture', 'capture', 'screen']);
    expect(TrackingService.debugHeldUntilReadyCount, 0);
    expect(ready, isTrue);

    // After the release everything flows at once, and a second mark is a
    // no-op.
    TrackingService.track('app_backgrounded');
    TrackingService.markAnalyticsReady();
    await pumpEventQueue();
    expect(captured().last, 'app_backgrounded');
  });

  test('the hold never keeps a muted capture', () async {
    TrackingService.holdAnalyticsUntilReady();
    TrackingService.setDisabled(true);
    TrackingService.track('app_unlocked');
    expect(TrackingService.debugHeldUntilReadyCount, 0);
    TrackingService.markAnalyticsReady();
    await pumpEventQueue();
    expect(captured(), isEmpty);
  });
}
