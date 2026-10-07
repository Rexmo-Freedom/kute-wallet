import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/services/tracking/latency_tracker.dart';
import 'package:kute/services/tracking/order_ack_latency.dart';
import 'package:kute/services/tracking_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const posthog = MethodChannel('posthog_flutter');
  final calls = <MethodCall>[];
  final events = <(String, Map<String, Object>?)>[];
  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('kute_latency_');
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
    events.clear();
    messenger.setMockMethodCallHandler(posthog, (call) async {
      calls.add(call);
      return null;
    });
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    TrackingService.debugResetOptOut();
    TrackingService.setDisabled(false);
    LatencyTracker.debugReset();
  });

  tearDown(() {
    TrackingService.debugTrackObserver = null;
    TrackingService.debugResetOptOut();
    TrackingService.setDisabled(true);
    LatencyTracker.debugReset();
    messenger.setMockMethodCallHandler(posthog, null);
  });

  group('LatencyTracker', () {
    test('start/stop emits exactly one event named after the key', () async {
      LatencyTracker.start('spark_sync_latency');
      expect(LatencyTracker.isRunning('spark_sync_latency'), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final ms = LatencyTracker.stop('spark_sync_latency');

      expect(ms, isNotNull);
      expect(ms, greaterThanOrEqualTo(15));
      expect(LatencyTracker.isRunning('spark_sync_latency'), isFalse);
      expect(events, hasLength(1));
      final (name, params) = events.single;
      expect(name, 'spark_sync_latency');
      expect(params!['duration_ms'], ms);
      expect(params['duration_bucket'], '<500ms');
      expect(params.keys, unorderedEquals(['duration_ms', 'duration_bucket']));
    });

    test('stop without a start emits nothing and returns null', () {
      expect(LatencyTracker.stop('balance_loaded_latency'), isNull);
      expect(events, isEmpty);
    });

    test('a second stop is a no-op (one event per measurement)', () {
      LatencyTracker.start('app_time_to_first_frame');
      LatencyTracker.stop('app_time_to_first_frame');
      LatencyTracker.stop('app_time_to_first_frame');
      expect(events, hasLength(1));
    });

    test('cancel drops the measurement silently', () {
      LatencyTracker.start('spark_sync_latency');
      LatencyTracker.cancel('spark_sync_latency');
      expect(LatencyTracker.stop('spark_sync_latency'), isNull);
      expect(events, isEmpty);
    });

    test('stop params ride along beside the duration', () {
      LatencyTracker.start(LatencyKeys.balanceLoaded);
      LatencyTracker.stop(LatencyKeys.balanceLoaded,
          params: {'source': 'cache'});
      final (name, params) = events.single;
      expect(name, 'balance_loaded_latency');
      expect(params!['source'], 'cache');
      expect(params.containsKey('duration_ms'), isTrue);
    });

    test('record emits exact ms plus the bucket', () {
      LatencyTracker.record(LatencyKeys.quoteRoundtrip, 2400, params: {
        'source_chain': 'spark',
        'source_asset': 'BTC',
        'destination_chain': 'polygon',
        'destination_asset': 'USDC.e',
        'outcome': 'ok',
      });
      final (name, params) = events.single;
      expect(name, 'quote_roundtrip_latency');
      expect(params!['duration_ms'], 2400);
      expect(params['duration_bucket'], '1-3s');
      expect(params['outcome'], 'ok');
    });

    test('record ignores a negative duration', () {
      LatencyTracker.record('x', -1);
      expect(events, isEmpty);
    });

    test('bucket boundaries', () {
      expect(LatencyTracker.bucket(0), '<500ms');
      expect(LatencyTracker.bucket(499), '<500ms');
      expect(LatencyTracker.bucket(500), '500ms-1s');
      expect(LatencyTracker.bucket(999), '500ms-1s');
      expect(LatencyTracker.bucket(1000), '1-3s');
      expect(LatencyTracker.bucket(2999), '1-3s');
      expect(LatencyTracker.bucket(3000), '3-10s');
      expect(LatencyTracker.bucket(9999), '3-10s');
      expect(LatencyTracker.bucket(10000), '>10s');
    });

    test('reaches PostHog when tracking is on', () async {
      LatencyTracker.record(LatencyKeys.appTimeToFirstFrame, 800);
      await pumpEventQueue();
      final capture = calls.where((c) => c.method == 'capture');
      expect(capture, hasLength(1));
      final args = Map<String, dynamic>.from(capture.single.arguments as Map);
      expect(args['eventName'], 'app_time_to_first_frame');
    });

    test('respects the analytics opt-out: nothing leaves the device',
        () async {
      await TrackingService.disableTracking();
      calls.clear();

      LatencyTracker.start(LatencyKeys.sparkSync);
      LatencyTracker.stop(LatencyKeys.sparkSync);
      LatencyTracker.record(LatencyKeys.orderSubmitAck, 120,
          params: {'venue': 'polymarket'});
      await pumpEventQueue();

      expect(calls.where((c) => c.method == 'capture'), isEmpty);
    });
  });

  group('OrderAckLatency', () {
    test('record emits venue, order kind and outcome only', () {
      OrderAckLatency.record(
        venue: 'hyperliquid',
        orderKind: 'market',
        durationMs: 340,
        outcome: 'ok',
      );
      final (name, params) = events.single;
      expect(name, 'order_submit_ack_latency');
      expect(
          params!.keys,
          unorderedEquals([
            'duration_ms',
            'duration_bucket',
            'venue',
            'order_kind',
            'outcome',
          ]));
      expect(params['venue'], 'hyperliquid');
      expect(params['order_kind'], 'market');
      expect(params['outcome'], 'ok');
    });

    Map<String, dynamic> order(List<Map<String, dynamic>> orders,
            {String grouping = 'na'}) =>
        {'type': 'order', 'orders': orders, 'grouping': grouping};

    Map<String, dynamic> limit(String tif) => {
          'a': 1,
          'b': true,
          'p': '1',
          's': '1',
          'r': false,
          't': {
            'limit': {'tif': tif}
          },
        };

    test('hyperliquidOrderKind classifies order actions', () {
      expect(OrderAckLatency.hyperliquidOrderKind(order([limit('Ioc')])),
          'market');
      expect(OrderAckLatency.hyperliquidOrderKind(order([limit('Gtc')])),
          'limit');
      expect(OrderAckLatency.hyperliquidOrderKind(order([limit('Alo')])),
          'limit');
      expect(
          OrderAckLatency.hyperliquidOrderKind(order([
            {
              't': {
                'trigger': {'isMarket': true, 'triggerPx': '1', 'tpsl': 'sl'}
              }
            }
          ])),
          'trigger');
      expect(
          OrderAckLatency.hyperliquidOrderKind(
              order([limit('Ioc'), limit('Gtc')], grouping: 'normalTpsl')),
          'tpsl');
      expect(
          OrderAckLatency.hyperliquidOrderKind(
              order([limit('Gtc'), limit('Gtc'), limit('Gtc')])),
          'scale');
      expect(OrderAckLatency.hyperliquidOrderKind({'type': 'twapOrder'}),
          'twap');
      expect(OrderAckLatency.hyperliquidOrderKind({'type': 'trailingStop'}),
          'trailing_stop');
      expect(OrderAckLatency.hyperliquidOrderKind({'type': 'modify'}),
          'modify');
    });

    test('hyperliquidOrderKind skips non-order actions', () {
      for (final type in [
        'cancel',
        'cancelByCloid',
        'updateLeverage',
        'updateIsolatedMargin',
        'vaultTransfer',
        'usdSend',
        'withdraw3',
        'twapCancel',
        'approveBuilderFee',
      ]) {
        expect(OrderAckLatency.hyperliquidOrderKind({'type': type}), isNull,
            reason: type);
      }
    });
  });
}
