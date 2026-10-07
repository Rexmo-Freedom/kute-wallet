import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/services/secure_storage.dart';
import 'package:kute/services/tracking_service.dart';

/// A referral-code rename that reaches the device (through /me or
/// /auth/wallet) aliases the NEW code onto the same PostHog person, so the
/// old and new codes stay one person. The tests run in order: the first
/// one runs before `initialize()` has given this process a device UUID.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const posthog = MethodChannel('posthog_flutter');
  final calls = <MethodCall>[];
  late Directory hiveDir;

  List<Object?> aliases() => [
        for (final c in calls)
          if (c.method == 'alias') (c.arguments as Map)['alias'],
      ];
  List<Object?> identities() => [
        for (final c in calls)
          if (c.method == 'identify') (c.arguments as Map)['userId'],
      ];

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('kute_rename_alias_');
    Hive.init(hiveDir.path);
    await Hive.openBox('settings');
    FlutterSecureStorage.setMockInitialValues({});
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(posthog, (call) async {
      calls.add(call);
      return null;
    });
    TrackingService.debugResetOptOut();
    TrackingService.setDisabled(false);
  });

  tearDown(() {
    TrackingService.setDisabled(true);
    messenger.setMockMethodCallHandler(posthog, null);
  });

  test('without a device UUID the new code is aliased before identify',
      () async {
    expect(TrackingService.deviceId, isNull);
    await TrackingService.identifyWithAffiliate('OLDCODE1');
    expect(aliases(), isEmpty);
    calls.clear();

    await TrackingService.identifyWithAffiliate('NEWCODE1');
    expect(aliases(), ['NEWCODE1']);
    final aliasAt = calls.indexWhere((c) => c.method == 'alias');
    final identifyAt = calls.indexWhere((c) => c.method == 'identify');
    expect(aliasAt, lessThan(identifyAt));
  });

  test('with a device UUID the renamed code joins the same person', () async {
    await TrackingService.initialize();
    final device = TrackingService.deviceId;
    expect(device, isNotNull);

    await TrackingService.identifyWithAffiliate('OLDCODE2');
    await TrackingService.identifyWithAffiliate('NEWCODE2');
    expect(aliases(), ['OLDCODE2', 'NEWCODE2']);
    // The identity never moves off the device UUID.
    expect(identities().toSet(), {device});
    // The last-seen own code is kept in secure storage.
    expect(await secureStorage.read(key: 'kute_aliased_affiliate'), 'NEWCODE2');

    // Once per code: the next boot re-identifies without a new alias.
    calls.clear();
    await TrackingService.identifyWithAffiliate('NEWCODE2');
    expect(aliases(), isEmpty);
  });
}
