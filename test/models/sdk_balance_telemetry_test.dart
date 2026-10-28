import 'dart:async';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/breez/sdk_balance_telemetry.dart';
import 'package:kute/providers/usd_account_provider.dart';
import 'package:kute/services/tracking_service.dart';

GetInfoResponse _info(int? units) => GetInfoResponse(
      identityPubkey: 'private identity',
      balanceSats: BigInt.zero,
      tokenBalances: units == null
          ? {}
          : {
              kUsdTokenIdentifier: TokenBalance(
                balance: BigInt.from(units),
                tokenMetadata: TokenMetadata(
                  identifier: kUsdTokenIdentifier,
                  issuerPublicKey: 'private issuer',
                  name: 'USDB',
                  ticker: 'USDB',
                  decimals: 6,
                  maxSupply: BigInt.zero,
                  isFreezable: false,
                ),
              )
            },
    );

void main() {
  test('a failed initial catch-up read reports once without starting a sync',
      () {
    fakeAsync((async) {
      final events = <(String, Map<String, Object>)>[];
      final c = UsdLedgerCatchUp(
        readInfo: (_) async => throw StateError('private native error'),
        syncWallet: () async => fail('a failed read must not start sync'),
        telemetry: SdkBalanceTelemetry(reporter: (e, p) => events.add((e, p))),
        publish: (_, __) {},
        retryDelays: const [],
      );
      c.recordReading(null);
      c.onLedger('private identity', holdsDollars: true);
      c.check('order_leg');
      async.flushMicrotasks();
      expect(events.single.$1, 'usd_balance_catchup');
      expect(events.single.$2['result'], 'read_failed');
      expect(events.single.$2['reason'], 'missing_entry');
      expect(events.single.$2['source'], 'order_leg');
      c.dispose();
    });
  });
  test(
      'typed reporter bounds schemas and untrusted source without unmuting debug',
      () {
    final events = <(String, Map<String, Object>)>[];
    TrackingService.debugTrackObserver =
        (event, properties) => events.add((event, properties!));
    addTearDown(() => TrackingService.debugTrackObserver = null);
    final wasMuted = TrackingService.isDisabled;
    const SdkBalanceTelemetry().recovery(
        source: 'private seed or address',
        result: UsdRecoveryResult.deferred,
        reason: UsdRecoveryReason.mutationInFlight,
        attempted: false,
        durationMs: 127);
    expect(TrackingService.isDisabled, wasMuted);
    expect(events.single.$1, 'usd_token_recovery');
    expect(events.single.$2, {
      'source': 'unknown',
      'result': 'deferred',
      'reason': 'mutation_in_flight',
      'attempted': false,
      'duration_ms': 127,
    });
    final throwing =
        SdkBalanceTelemetry(reporter: (_, __) => throw StateError('offline'));
    expect(
        () => throwing.sync(
            source: 'refresh', result: UsdSyncResult.error, durationMs: 52),
        returnsNormally);
  });

  test('missing entry and unchanged numeric retries emit one outcome per run',
      () {
    for (final missing in [false, true]) {
      fakeAsync((async) {
        final events = <(String, Map<String, Object>)>[];
        final c = UsdLedgerCatchUp(
          readInfo: (_) async => _info(missing ? null : 0),
          syncWallet: () async => throw StateError('private native error'),
          telemetry:
              SdkBalanceTelemetry(reporter: (e, p) => events.add((e, p))),
          publish: (_, __) {},
          debounce: Duration.zero,
          retryDelays: const [],
        );
        c.recordReading(missing ? null : 0);
        c.onLedger('private id', holdsDollars: true, settledDollars: 0);
        c.onLedger('private id,another',
            holdsDollars: true, settledDollars: 1, recoveryEligible: true);
        async.elapse(Duration.zero);
        expect(events.map((e) => e.$1),
            ['usd_balance_sync', 'usd_balance_catchup']);
        expect(events.first.$2['result'], 'error');
        expect(events.last.$2['reason'],
            missing ? 'missing_entry' : 'unchanged_numeric');
        expect(events.last.$2['result'], 'still_behind');
        expect(events.last.$2['source'], 'ledger');
        expect(events.last.$2['retry_index'], 0);
        expect(events.last.$2['duration_ms'], isA<int>());
        expect(
            events.last.$2.keys,
            unorderedEquals(
                ['source', 'reason', 'result', 'duration_ms', 'retry_index']));
        expect(events.toString(), isNot(contains('private')));
        c.dispose();
      });
    }
  });

  test('polls stay quiet; early catch-up and eventual sync each report once',
      () {
    fakeAsync((async) {
      final events = <(String, Map<String, Object>)>[];
      final sync = Completer<void>();
      int? units;
      final c = UsdLedgerCatchUp(
        readInfo: (_) async => _info(units),
        syncWallet: () => sync.future,
        telemetry: SdkBalanceTelemetry(reporter: (e, p) => events.add((e, p))),
        publish: (_, __) {},
        retryDelays: const [],
      );
      c.onLedger('private id', holdsDollars: true);
      c.check('seed');
      async.elapse(const Duration(seconds: 3));
      expect(events, isEmpty);
      units = 1000000;
      async.elapse(const Duration(seconds: 1));
      expect(events.single.$1, 'usd_balance_catchup');
      expect(events.single.$2['result'], 'caught_up');
      sync.complete();
      async.flushMicrotasks();
      expect(
          events.map((e) => e.$1), ['usd_balance_catchup', 'usd_balance_sync']);
      expect(events.last.$2['result'], 'ok');
      c.dispose();
    });
  });

  test('sync timeout reports once and disposed sessions suppress late outcomes',
      () {
    fakeAsync((async) {
      final events = <(String, Map<String, Object>)>[];
      final sync = Completer<void>();
      UsdLedgerCatchUp make() => UsdLedgerCatchUp(
            readInfo: (_) async => _info(null),
            syncWallet: () => sync.future,
            telemetry:
                SdkBalanceTelemetry(reporter: (e, p) => events.add((e, p))),
            publish: (_, __) {},
            syncTimeout: const Duration(seconds: 2),
            retryDelays: const [],
          );
      final first = make()
        ..onLedger('first', holdsDollars: true)
        ..check('seed');
      async.elapse(const Duration(seconds: 2));
      expect(
          events.map((e) => e.$1), ['usd_balance_sync', 'usd_balance_catchup']);
      expect(events.first.$2['result'], 'timeout');
      first.dispose();
      events.clear();
      final second = make()
        ..onLedger('second', holdsDollars: true)
        ..check('seed');
      async.flushMicrotasks();
      second.dispose();
      sync.complete();
      async.elapse(const Duration(seconds: 5));
      expect(events, isEmpty);
    });
  });
}
