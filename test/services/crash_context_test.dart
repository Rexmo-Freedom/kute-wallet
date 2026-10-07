import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/services/exit_reason_service.dart';
import 'package:kute/services/once_flags_service.dart';
import 'package:kute/services/tracking_service.dart';

void main() {
  late Directory dir;
  final events = <String, Map<String, Object>?>{};
  final eventList = <String>[];
  final crashes = <String>[];
  final crashKeys = <String, Object?>{};
  final crashLogs = <String>[];

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('crash_context_test');
    Hive.init(dir.path);
    await Hive.openBox<bool>(OnceFlagsService.boxName);
    TrackingService.debugResetCrashContext();
    TrackingService.debugResetHandled();
    events.clear();
    eventList.clear();
    crashes.clear();
    crashKeys.clear();
    crashLogs.clear();
    TrackingService.debugTrackObserver = (e, p) {
      events[e] = p;
      eventList.add(e);
    };
    TrackingService.debugCrashObserver =
        (error, stack, reason, log) => crashes.add(error.toString());
    TrackingService.debugCrashlyticsObserver = (kind, name, value) {
      if (kind == 'key') crashKeys[name] = value;
      if (kind == 'log') crashLogs.add('$value');
    };
  });

  tearDown(() async {
    TrackingService.debugTrackObserver = null;
    TrackingService.debugCrashObserver = null;
    TrackingService.debugCrashlyticsObserver = null;
    TrackingService.debugCrashExtrasObserver = null;
    TrackingService.debugResetCrashContext();
    await Hive.close();
    await dir.delete(recursive: true);
  });

  group('scrubber additions', () {
    test('UUIDs are redacted everywhere except the identity keys', () {
      const uuid = '3f1c2b9e-1a2b-4c3d-9e8f-001122334455';
      expect(TrackingService.scrubString('order $uuid failed'),
          'order ${TrackingService.redacted} failed');
      expect(TrackingService.scrubValue(uuid, key: 'device_uuid'), uuid);
      expect(TrackingService.scrubValue(uuid, key: 'reason'),
          TrackingService.redacted);
      expect(TrackingService.crashlyticsUserId(uuid), uuid);
    });

    test('URLs keep scheme and host only', () {
      expect(
          TrackingService.scrubString(
              'GET https://api.example.com/v1/users/alice?token=abc failed'),
          'GET https://api.example.com/… failed');
      expect(
          TrackingService.scrubString(
              'socket wss://stream.example.io:443/ws/orders closed.'),
          'socket wss://stream.example.io/… closed.');
      expect(TrackingService.scrubString('see https://kute.app'),
          'see https://kute.app');
      expect(
          TrackingService.scrubString(
              '(https://user:pw@host.example.org/a/b), retry'),
          '(https://host.example.org/…), retry');
    });

    test('amounts and long numbers leave error text only', () {
      final reason =
          TrackingService.safeReason('send of 0.0025 BTC (250000 sats) failed');
      expect(reason, 'send of <amount> BTC (<digits> sats) failed');
      // Analytics money properties are untouched.
      TrackingService.track('probe', params: {
        'amount_usd': 1234.56,
        'amount': 0.0025,
        'amount_sats': 250000,
        'note': 'kept 250000',
      });
      expect(events['probe']!['amount_usd'], 1234.56);
      expect(events['probe']!['amount_sats'], 250000);
      expect(events['probe']!['note'], 'kept 250000');
    });

    test('crash information lines are scrubbed like error text', () {
      List<String>? info;
      bool? fatal;
      TrackingService.debugCrashExtrasObserver = (i, f) {
        info = i;
        fatal = f;
      };
      TrackingService.recordCrash(StateError('x'), null, information: [
        'context: paying 12.50 to https://pay.example.com/i/abc',
        '   ',
      ]);
      expect(info, ['context: paying <amount> to https://pay.example.com/…']);
      expect(fatal, isFalse);
    });
  });

  group('flow context', () {
    test('sets, steps and clears only the current flow', () {
      TrackingService.setFlowContext(
          flow: 'send', step: 'amount', network: 'lightning', walletKind: 'hot');
      TrackingService.setFlowStep('review');
      expect(TrackingService.crashContext['last_flow'], 'send');
      expect(TrackingService.crashContext['last_step'], 'review');
      expect(crashKeys['flow'], 'send');
      expect(crashKeys['step'], 'review');
      expect(crashKeys['network'], 'lightning');

      TrackingService.clearFlowContext('receive'); // not current: no-op
      expect(TrackingService.crashContext['last_flow'], 'send');

      TrackingService.setFlowContext(flow: 'polymarket_bet', venue: 'polymarket');
      expect(crashKeys['network'], ''); // stale value from send dropped
      TrackingService.clearFlowContext('polymarket_bet');
      expect(TrackingService.crashContext['last_flow'], 'none');
      expect(TrackingService.crashContext['last_step'], 'none');
      expect(crashKeys['venue'], '');
    });

    test('screen and shell tab feed route keys', () {
      TrackingService.recordScreen('send');
      TrackingService.setShellTab('predictions');
      expect(TrackingService.crashContext['last_screen'], 'send');
      expect(crashKeys['route'], 'send');
      expect(crashKeys['shell_tab'], 'predictions');
    });

    test('the snapshot survives a process death and is read next launch',
        () async {
      await TrackingService.initCrashContext(appVersion: '1.4.0+88');
      expect(TrackingService.previousSessionSnapshot, isNull);
      TrackingService.recordScreen('hyperliquid_order');
      TrackingService.setFlowContext(
          flow: 'hl_order', step: 'review', venue: 'hyperliquid');
      await TrackingService.debugFlushCrashContext();

      // "Crash": the process dies with nothing else written.
      TrackingService.debugResetCrashContext();
      await Hive.close();
      Hive.init(dir.path);

      await TrackingService.initCrashContext(appVersion: '1.4.1+89');
      final prev = TrackingService.previousSessionSnapshot!;
      expect(prev['last_screen'], 'hyperliquid_order');
      expect(prev['last_flow'], 'hl_order');
      expect(prev['last_step'], 'review');
      expect(prev['venue'], 'hyperliquid');
      expect(prev['app_version'], '1.4.0+88');
      // This session's snapshot has replaced it on disk.
      expect(TrackingService.crashContext['app_version'], '1.4.1+89');
      expect(TrackingService.crashContext['last_flow'], 'none');
    });

    test('track() leaves categorical breadcrumbs, never amounts', () {
      TrackingService.track('send_failed', params: {
        'flow': 'lightning',
        'stage': 'broadcast',
        'error_category': 'no_route',
        'amount_usd': 42.0,
        'asset': 'btc',
        'reason': 'secret detail',
      });
      expect(crashLogs.single,
          'send_failed flow=lightning stage=broadcast error_category=no_route asset=btc');
    });
  });

  group('crash markers', () {
    test('unhandled_exception_caught carries the crash context', () async {
      await TrackingService.initCrashContext(appVersion: '2.0.0+1');
      TrackingService.recordScreen('receive');
      TrackingService.setFlowContext(flow: 'receive', step: 'quote');
      TrackingService.unhandledExceptionCaught(
          errorClass: 'StateError', crashType: 'dart_nonfatal');
      final p = events['unhandled_exception_caught']!;
      expect(p['crash_type'], 'dart_nonfatal');
      expect(p['error_class'], 'StateError');
      expect(p['last_screen'], 'receive');
      expect(p['last_flow'], 'receive');
      expect(p['last_step'], 'quote');
      expect(p['app_version'], '2.0.0+1');
    });

    test('every marker field is present even with no context', () {
      TrackingService.unhandledExceptionCaught(errorClass: 'TypeError');
      final p = events['unhandled_exception_caught']!;
      expect(p['crash_type'], 'dart_fatal');
      expect(p['last_screen'], 'unknown');
      expect(p['last_flow'], 'none');
      expect(p['last_step'], 'none');
      expect(p['app_version'], 'unknown');
    });

    test('exit records report the previous snapshot without double-counting',
        () async {
      await TrackingService.initCrashContext(appVersion: '3.0.0+5');
      final snapshot = <String, Object?>{
        'last_screen': 'polymarket_market',
        'last_flow': 'polymarket_bet',
        'last_step': 'slip',
        'app_version': '2.9.0+4',
      };
      ExitReasonService.handleExitRecords([
        {
          'timestamp': 111,
          'reasonName': 'crash_native',
          'importance': 100,
          'rssKb': 700 * 1024,
        },
        {
          'timestamp': 110,
          'reasonName': 'low_memory',
          'importance': 400,
          'rssKb': 300 * 1024,
        },
      ], snapshot);

      final exits = eventList.where((e) => e == 'app_previous_exit_abnormal');
      expect(exits.length, 2);
      // Only the newest death gets app_crash_detected (the background LMK
      // kill of a cached process is not a crash) and the snapshot.
      expect(eventList.where((e) => e == 'app_crash_detected').length, 1);
      final p = events['app_crash_detected']!;
      expect(p['crash_type'], 'native_crash');
      expect(p['error_class'], 'crash_native');
      expect(p['last_screen'], 'polymarket_market');
      expect(p['last_flow'], 'polymarket_bet');
      expect(p['last_step'], 'slip');
      expect(p['app_version'], '3.0.0+5');
      expect(p['crashed_app_version'], '2.9.0+4');
      expect(p['rss_mb'], '512-1024');
      expect(p['in_foreground'], isTrue);

      // The older low_memory record: bucketed rss, no snapshot.
      final older = events['app_previous_exit_abnormal']!;
      expect(older['crash_type'], 'oom');
      expect(older['rss_mb'], '256-512');
      expect(older.containsKey('rss_kb'), isFalse);
      expect(older['last_flow'], 'none');
      expect(older['snapshot_available'], isFalse);

      // Crashlytics: the native crash is already captured natively; only
      // the low-memory death is recorded, under its own type.
      expect(crashes.length, 1);
      expect(crashes.single, startsWith('LowMemoryExit'));

      // Same records next launch: nothing is reported twice.
      eventList.clear();
      ExitReasonService.handleExitRecords([
        {'timestamp': 111, 'reasonName': 'crash_native', 'importance': 100},
      ], snapshot);
      expect(eventList, isEmpty);
    });

    test('crash types and rss buckets', () {
      expect(ExitReasonService.crashTypeFor('anr'), 'anr');
      expect(ExitReasonService.crashTypeFor('low_memory'), 'oom');
      expect(ExitReasonService.crashTypeFor('crash'), 'native_crash');
      expect(ExitReasonService.rssMbBucket(null), 'unknown');
      expect(ExitReasonService.rssMbBucket(3 * 1024 * 1024), '2048+');
      expect(ExitReasonService.rssMbBucket('65536'), '<128');
    });
  });

  group('recordHandled', () {
    test('records non-user categories once per session', () {
      expect(
          TrackingService.recordHandled('no_route', 'no path found', null,
              flow: 'send', stage: 'broadcast'),
          isTrue);
      expect(
          TrackingService.recordHandled('no_route', 'no path found again', null,
              flow: 'send', stage: 'broadcast'),
          isFalse);
      expect(crashes.single, startsWith('HandledFailure: no_route'));
    });

    test('skips user categories', () {
      for (final c in [
        'user_cancelled',
        'insufficient_funds',
        'below_minimum',
        'invalid_destination',
        'network',
        'timeout',
      ]) {
        expect(TrackingService.recordHandled(c, 'x', null, flow: 'send'),
            isFalse);
      }
      expect(crashes, isEmpty);
    });

    test('is capped at 20 per session', () {
      var recorded = 0;
      for (var i = 0; i < 30; i++) {
        if (TrackingService.recordHandled('unknown', 'x', null,
            flow: 'f$i')) {
          recorded++;
        }
      }
      expect(recorded, 20);
    });

    test('failure helpers route through it', () {
      TrackingService.sendFailed(
        flow: 'onchain',
        network: 'bitcoin',
        asset: 'btc',
        error: 'settlement stalled',
        stage: 'settle',
      );
      TrackingService.sendFailed(
        flow: 'onchain',
        network: 'bitcoin',
        asset: 'btc',
        error: 'insufficient funds',
        stage: 'validate',
      );
      expect(crashes.length, 1);
      expect(crashes.single, contains('settlement'));
    });
  });

  test('the recovery phrase event never carries a word count', () {
    TrackingService.recoveryPhraseDisplayed();
    expect(events.containsKey('recovery_phrase_displayed'), isTrue);
    expect(events['recovery_phrase_displayed'], isNull);
  });
}
