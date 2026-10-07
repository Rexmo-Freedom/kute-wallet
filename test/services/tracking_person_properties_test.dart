import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/services/tracking_service.dart';

/// The segmentation person properties: what the set contains, that it is
/// typed (booleans and counters), throttled, and how the money-action
/// once-stamp and counter behave.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const posthog = MethodChannel('posthog_flutter');
  final calls = <MethodCall>[];
  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('kute_personprops_');
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
    TrackingService.debugResetPersonProperties();
    TrackingService.setDisabled(false);
  });

  tearDown(() {
    TrackingService.debugResetOptOut();
    TrackingService.debugResetPersonProperties();
    TrackingService.setDisabled(true);
    messenger.setMockMethodCallHandler(posthog, null);
  });

  void refresh({int walletCount = 2, bool backedUp = true}) =>
      TrackingService.refreshPersonProperties(
        walletCount: walletCount,
        hardwareWalletKinds: const ['ledger', 'Ledger ', 'jade'],
        backedUp: backedUp,
        hasPasskey: false,
        biometricsEnabled: true,
        pinSet: true,
        hasReferrer: false,
      );

  test('publishes typed booleans, counters and kinds only', () {
    refresh();
    final props = TrackingService.debugPendingUserProperties;
    expect(props, {
      'platform': anyOf('ios', 'android'),
      'wallet_count': 2,
      'has_hardware_wallet': true,
      'hardware_wallet_kinds': ['jade', 'ledger'],
      'has_referrer': false,
      'backed_up': true,
      'has_passkey': false,
      'pin_set': true,
      'biometrics_enabled': true,
      'lifetime_money_actions': 0,
    });
    // Nothing that looks like an amount, an id or a location.
    expect(props.keys, isNot(contains('country')));
    expect(props.keys, isNot(contains('first_money_action_at')));
  });

  test('country is only ever the backend answer; absent means skipped', () {
    TrackingService.refreshPersonProperties(
      walletCount: 1,
      hardwareWalletKinds: const [],
      backedUp: false,
      hasPasskey: true,
      biometricsEnabled: false,
      country: 'PT',
    );
    final props = TrackingService.debugPendingUserProperties;
    expect(props['country'], 'PT');
    expect(props['has_hardware_wallet'], false);
    expect(props['hardware_wallet_kinds'], isEmpty);
    // Unknown PIN / referrer state leaves those properties untouched.
    expect(props.keys, isNot(contains('pin_set')));
    expect(props.keys, isNot(contains('has_referrer')));
  });

  test('an unchanged set is throttled; a change goes out at once', () async {
    refresh();
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(calls.where((c) => c.method == 'capture'), hasLength(1));

    refresh();
    expect(TrackingService.debugPendingUserProperties, isEmpty);

    refresh(walletCount: 3);
    expect(TrackingService.debugPendingUserProperties['wallet_count'], 3);
  });

  test('opted out: nothing is published or recorded', () async {
    await TrackingService.disableTracking();
    calls.clear();
    refresh();
    TrackingService.track('send_completed', params: {'amount_usd': 5.0});
    await Future<void>.delayed(const Duration(milliseconds: 700));

    expect(TrackingService.debugPendingUserProperties, isEmpty);
    expect(calls.where((c) => c.method == 'capture'), isEmpty);
    expect(TrackingService.lifetimeMoneyActions, 0);
    expect(TrackingService.firstMoneyActionAt, isNull);
  });

  group('money actions', () {
    test('the first completed money event stamps the date once', () {
      expect(TrackingService.firstMoneyActionAt, isNull);
      TrackingService.track('swap_completed', params: {'venue': 'spark'});
      final first = TrackingService.firstMoneyActionAt;
      expect(first, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
      expect(TrackingService.debugPendingUserProperties, {
        'lifetime_money_actions': 1,
        'first_money_action_at': first,
      });

      // A later action never moves the stamp.
      Hive.box('settings')
          .put('analytics_first_money_action_at', '2026-01-02');
      TrackingService.track('send_completed');
      expect(TrackingService.firstMoneyActionAt, '2026-01-02');
      expect(TrackingService.debugPendingUserProperties['first_money_action_at'],
          '2026-01-02');
    });

    test('the counter increments once per completed money action', () {
      TrackingService.track('send_completed');
      TrackingService.track('polymarket_bet_placed', params: {'amount': 5.0});
      TrackingService.track('hyperliquid_order_placed');
      expect(TrackingService.lifetimeMoneyActions, 3);
      expect(TrackingService.debugPendingUserProperties['lifetime_money_actions'],
          3);
    });

    test('intermediate, failed and wrapper events do not count', () {
      for (final event in [
        'send_started',
        'send_step',
        'send_failed',
        'first_send_completed',
        'move_completed',
        'onboarding_completed',
        'backup_completed',
        'app_cold_start_completed',
      ]) {
        TrackingService.track(event);
      }
      TrackingService.track('hyperliquid_order_failed');
      expect(TrackingService.lifetimeMoneyActions, 0);
      expect(TrackingService.firstMoneyActionAt, isNull);
    });

    test('the persisted values ride the next refresh', () {
      TrackingService.track('buy_completed');
      TrackingService.track('sell_completed');
      TrackingService.debugResetPersonProperties();
      refresh();
      final props = TrackingService.debugPendingUserProperties;
      expect(props['lifetime_money_actions'], 2);
      expect(props['first_money_action_at'],
          TrackingService.firstMoneyActionAt);
    });
  });
}
