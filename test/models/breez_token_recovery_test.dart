import 'dart:async';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as spark;
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/breez/sdk_instance.dart';
import 'package:kute/models/breez/sdk_operation_guard.dart';
import 'package:kute/models/breez/shared_sync.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:mocktail/mocktail.dart';

class _Sdk extends Mock implements spark.BreezSdk {}

class _Request extends Fake implements spark.ConnectRequest {}

void main() {
  late List<Map<String, Object>> outcomes;
  setUp(() {
    outcomes = [];
    TrackingService.debugTrackObserver = (event, properties) {
      if (event == 'usd_token_recovery') outcomes.add(properties!);
    };
  });
  tearDown(() => TrackingService.debugTrackObserver = null);
  final request = _Request();
  Future<void> flush() => Future<void>.delayed(Duration.zero);
  spark.GetInfoResponse info(String identity) => spark.GetInfoResponse(
        identityPubkey: identity,
        balanceSats: BigInt.one,
        tokenBalances: {},
      );
  void stub(_Sdk sdk, Stream<spark.SdkEvent> events, String identity) {
    when(() => sdk.addEventListener()).thenAnswer((_) => events);
    when(() => sdk.disconnect()).thenAnswer((_) async {});
    when(() => sdk.getInfo(request: const spark.GetInfoRequest()))
        .thenAnswer((_) async => info(identity));
    when(() => sdk.listPayments(request: const spark.ListPaymentsRequest()))
        .thenAnswer(
            (_) async => const spark.ListPaymentsResponse(payments: []));
    when(() => sdk.syncWallet(request: const spark.SyncWalletRequest()))
        .thenAnswer((_) async => const spark.SyncWalletResponse());
  }

  test('recovery is single-flight, re-subscribes, and rejects old native sends',
      () async {
    final first = _Sdk(), second = _Sdk();
    final oldEvents = StreamController<spark.SdkEvent>.broadcast();
    final newEvents = StreamController<spark.SdkEvent>.broadcast();
    stub(first, oldEvents.stream, 'first');
    stub(second, newEvents.stream, 'second');
    final queue = [first, second];
    final wrapper =
        BreezSdkSpark.forTesting(connectSdk: (_) async => queue.removeAt(0));
    await wrapper.connect(req: request);
    await flush();
    final checking = Completer<spark.ListPaymentsResponse>();
    when(() => first.listPayments(request: const spark.ListPaymentsRequest()))
        .thenAnswer((_) => checking.future);
    final identities = <String>[];
    final sub = wrapper.walletInfoStream
        .listen((i) => identities.add(i.identityPubkey));
    final recovering = wrapper.recoverStaleTokenBalance(first);
    expect(wrapper.recoverStaleTokenBalance(first), same(recovering));
    var sent = false;
    await expectLater(
        runSparkMutation(first, () async => sent = true), throwsStateError);
    expect(sent, isFalse);
    checking.complete(const spark.ListPaymentsResponse(payments: []));
    expect(await recovering, isTrue);
    expect(outcomes, hasLength(1), reason: 'joined callers share one outcome');
    expect(outcomes.single, containsPair('result', 'ok'));
    expect(outcomes.single, containsPair('attempted', true));
    expect(wrapper.instance, same(second));
    verify(() => first.disconnect()).called(1);
    verify(() => second.addEventListener()).called(1);
    identities.clear();
    oldEvents.add(const spark.SdkEvent.synced());
    newEvents.add(const spark.SdkEvent.synced());
    await flush();
    expect(identities, isNotEmpty);
    expect(identities, everyElement('second'));
    await expectLater(
        runSparkMutation(first, () async => sent = true), throwsStateError);
    expect(sent, isFalse);
    await sub.cancel();
    wrapper.disconnect();
    await flush();
    await oldEvents.close();
    await newEvents.close();
  });

  test('a running payment/prepare/claim defers recovery without disconnecting',
      () async {
    final sdk = _Sdk();
    stub(sdk, const Stream.empty(), 'wallet');
    final wrapper = BreezSdkSpark.forTesting(connectSdk: (_) async => sdk);
    await wrapper.connect(req: request);
    final sending = Completer<void>();
    final operation = runSparkMutation(sdk, () => sending.future);
    expect(await wrapper.recoverStaleTokenBalance(sdk), isFalse);
    expect(outcomes.single, containsPair('reason', 'mutation_in_flight'));
    verifyNever(() => sdk.disconnect());
    sending.complete();
    await operation;
    wrapper.disconnect();
  });

  test('a shared sync still running after UI timeout defers recovery',
      () async {
    final sdk = _Sdk();
    stub(sdk, const Stream.empty(), 'wallet');
    final sync = Completer<spark.SyncWalletResponse>();
    when(() => sdk.syncWallet(request: const spark.SyncWalletRequest()))
        .thenAnswer((_) => sync.future);
    final wrapper = BreezSdkSpark.forTesting(connectSdk: (_) async => sdk);
    await wrapper.connect(req: request);
    final syncing = sharedSyncWallet(sdk);
    expect(await wrapper.recoverStaleTokenBalance(sdk), isFalse);
    expect(outcomes.single, containsPair('reason', 'sync_in_flight'));
    verifyNever(() => sdk.disconnect());
    sync.complete(const spark.SyncWalletResponse());
    await syncing;
    wrapper.disconnect();
  });

  test(
      'pending outgoing payment defers recovery and releases the mutation guard',
      () async {
    final sdk = _Sdk();
    stub(sdk, const Stream.empty(), 'wallet');
    final wrapper = BreezSdkSpark.forTesting(connectSdk: (_) async => sdk);
    await wrapper.connect(req: request);
    await flush();
    when(() => sdk.listPayments(request: const spark.ListPaymentsRequest()))
        .thenAnswer((_) async => spark.ListPaymentsResponse(payments: [
              spark.Payment(
                id: 'pending',
                paymentType: spark.PaymentType.send,
                status: spark.PaymentStatus.pending,
                amount: BigInt.one,
                fees: BigInt.zero,
                timestamp: BigInt.zero,
                method: spark.PaymentMethod.spark,
              )
            ]));
    expect(await wrapper.recoverStaleTokenBalance(sdk), isFalse);
    expect(outcomes.single, containsPair('reason', 'pending_send'));
    verifyNever(() => sdk.disconnect());
    expect(await runSparkMutation(sdk, () async => true), isTrue);
    wrapper.disconnect();
  });

  test('wallet switch during the pending-payment check cancels recovery',
      () async {
    final first = _Sdk(), second = _Sdk();
    stub(first, const Stream.empty(), 'first');
    stub(second, const Stream.empty(), 'second');
    final queue = [first, second];
    final wrapper =
        BreezSdkSpark.forTesting(connectSdk: (_) async => queue.removeAt(0));
    await wrapper.connect(req: request);
    await flush();
    final checking = Completer<spark.ListPaymentsResponse>();
    when(() => first.listPayments(request: const spark.ListPaymentsRequest()))
        .thenAnswer((_) => checking.future);
    final recovering = wrapper.recoverStaleTokenBalance(first);
    wrapper.disconnect();
    await wrapper.connect(req: request);
    checking.complete(const spark.ListPaymentsResponse(payments: []));
    expect(await recovering, isFalse);
    expect(outcomes.single, containsPair('reason', 'wallet_changed'));
    expect(wrapper.instance, same(second));
    expect(queue, isEmpty);
    wrapper.disconnect();
  });

  test('an active SDK optimization defers recovery', () async {
    final sdk = _Sdk();
    final events = StreamController<spark.SdkEvent>.broadcast();
    stub(sdk, events.stream, 'wallet');
    final wrapper = BreezSdkSpark.forTesting(connectSdk: (_) async => sdk);
    await wrapper.connect(req: request);
    events.add(const spark.SdkEvent.autoOptimization(
        optimizationEvent:
            spark.AutoOptimizationEvent.started(totalRounds: 1)));
    await flush();
    expect(await wrapper.recoverStaleTokenBalance(sdk), isFalse);
    expect(outcomes.single, containsPair('reason', 'optimization_in_flight'));
    verifyNever(() => sdk.disconnect());
    wrapper.disconnect();
    await flush();
    await events.close();
  });

  test(
      'a synchronous payment-list failure releases recovery without retiring SDK',
      () async {
    final sdk = _Sdk();
    stub(sdk, const Stream.empty(), 'wallet');
    final wrapper = BreezSdkSpark.forTesting(connectSdk: (_) async => sdk);
    await wrapper.connect(req: request);
    await flush();
    when(() => sdk.listPayments(request: const spark.ListPaymentsRequest()))
        .thenThrow(StateError('offline'));
    expect(await wrapper.recoverStaleTokenBalance(sdk), isFalse);
    expect(outcomes.single, containsPair('reason', 'lookup_failed'));
    expect(await runSparkMutation(sdk, () async => true), isTrue);
    verifyNever(() => sdk.disconnect());
    wrapper.disconnect();
  });

  test('reconnect and teardown failures have distinct fixed outcomes',
      () async {
    for (final teardownFails in [false, true]) {
      outcomes.clear();
      final sdk = _Sdk();
      stub(sdk, const Stream.empty(), 'wallet');
      var connects = 0;
      final wrapper = BreezSdkSpark.forTesting(connectSdk: (_) async {
        if (++connects > 1) throw StateError('private native error');
        return sdk;
      });
      await wrapper.connect(req: request);
      await flush();
      if (teardownFails) {
        when(() => sdk.disconnect())
            .thenThrow(StateError('private native error'));
      }
      expect(await wrapper.recoverStaleTokenBalance(sdk, source: 'ledger'),
          isFalse);
      expect(outcomes.single, containsPair('result', 'failed'));
      expect(outcomes.single, containsPair('attempted', true));
      expect(outcomes.single['reason'],
          teardownFails ? 'teardown_failed' : 'connect_failed');
      expect(
          outcomes.single.keys,
          unorderedEquals(
              ['source', 'result', 'reason', 'attempted', 'duration_ms']));
      expect(outcomes.single.toString(), isNot(contains('private')));
      expect(outcomes.single['duration_ms'], isA<int>());
      expect(wrapper.instance, isNull);
    }
  });

  test(
      'a native lookup timeout reports its fixed reason without attempting reconnect',
      () async {
    final sdk = _Sdk();
    stub(sdk, const Stream.empty(), 'wallet');
    final wrapper = BreezSdkSpark.forTesting(connectSdk: (_) async => sdk);
    await wrapper.connect(req: request);
    await flush();
    when(() => sdk.listPayments(request: const spark.ListPaymentsRequest()))
        .thenThrow(TimeoutException('private native error'));
    expect(await wrapper.recoverStaleTokenBalance(sdk), isFalse);
    expect(outcomes.single, containsPair('reason', 'lookup_timeout'));
    expect(outcomes.single, containsPair('attempted', false));
    verifyNever(() => sdk.disconnect());
    wrapper.disconnect();
  });

  test('a superseded session never receives the old recovery success',
      () async {
    final first = _Sdk(), second = _Sdk(), third = _Sdk();
    stub(first, const Stream.empty(), 'first');
    stub(second, const Stream.empty(), 'second');
    stub(third, const Stream.empty(), 'third');
    final delayed = Completer<spark.GetInfoResponse>();
    when(() => second.getInfo(request: const spark.GetInfoRequest()))
        .thenAnswer((_) => delayed.future);
    final queue = [first, second, third];
    final wrapper =
        BreezSdkSpark.forTesting(connectSdk: (_) async => queue.removeAt(0));
    await wrapper.connect(req: request);
    await flush();
    final recovering = wrapper.recoverStaleTokenBalance(first);
    await pumpEventQueue();
    expect(wrapper.instance, same(second));
    wrapper.disconnect();
    await wrapper.connect(req: request);
    delayed.complete(info('second'));
    await recovering;
    expect(wrapper.instance, same(third));
    expect(outcomes, isEmpty);
    wrapper.disconnect();
  });
}
