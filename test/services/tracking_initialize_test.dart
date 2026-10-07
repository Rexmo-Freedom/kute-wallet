import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/services/tracking_service.dart';

/// Boot-time `TrackingService.initialize()` against the PostHog platform
/// channel: nothing in the app reads feature flags, so boot must not
/// spend a network round-trip fetching them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const posthog = MethodChannel('posthog_flutter');
  final calls = <MethodCall>[];
  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('kute_track_init_');
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
    TrackingService.debugResetOptOut();
    TrackingService.setDisabled(true);
    messenger.setMockMethodCallHandler(posthog, null);
  });

  test('initialize() never asks PostHog to reload feature flags', () async {
    await TrackingService.initialize();
    await pumpEventQueue();

    final methods = calls.map((c) => c.method).toList();
    expect(methods, isNot(contains('reloadFeatureFlags')));
    expect(methods, isNot(contains('getFeatureFlag')));
    expect(methods, isNot(contains('isFeatureEnabled')));
  });
}
