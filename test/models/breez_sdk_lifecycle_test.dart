import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as spark;
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/breez/deposit_update.dart';
import 'package:kute/models/breez/sdk_instance.dart';
import 'package:kute/services/tracking/latency_tracker.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:mocktail/mocktail.dart';

class _Sdk extends Mock implements spark.BreezSdk {}

class _Request extends Fake implements spark.ConnectRequest {}

void main() {
  final request = _Request();
  Future<void> flush() => Future<void>.delayed(Duration.zero);
  spark.GetInfoResponse info(String identity, {int sats = 1, int usdb = 0}) =>
      spark.GetInfoResponse(
        identityPubkey: identity,
        balanceSats: BigInt.from(sats),
        tokenBalances: {
          if (usdb > 0)
            'usdb': spark.TokenBalance(
                balance: BigInt.from(usdb),
                tokenMetadata: spark.TokenMetadata(
                    identifier: 'usdb',
                    issuerPublicKey: 'issuer',
                    name: 'USDB',
                    ticker: 'USDB',
                    decimals: 6,
                    maxSupply: BigInt.zero,
                    isFreezable: false)),
        },
      );
  spark.DepositInfo deposit(String txid) => spark.DepositInfo(
        txid: txid.padRight(64, '0'),
        vout: 0,
        amountSats: BigInt.from(10000),
        isMature: true,
      );
  void stub(_Sdk sdk, Stream<spark.SdkEvent> events, String identity) {
    when(() => sdk.addEventListener()).thenAnswer((_) => events);
    when(() => sdk.disconnect()).thenAnswer((_) async {});
    when(() => sdk.getInfo(
            request: const spark.GetInfoRequest(ensureSynced: false)))
        .thenAnswer((_) async => info(identity));
    when(() => sdk.listPayments(request: const spark.ListPaymentsRequest()))
        .thenAnswer(
            (_) async => const spark.ListPaymentsResponse(payments: []));
  }

  spark.Payment payment(String id) => spark.Payment(
      id: id,
      paymentType: spark.PaymentType.receive,
      status: spark.PaymentStatus.completed,
      amount: BigInt.from(2000),
      fees: BigInt.zero,
      timestamp: BigInt.one,
      method: spark.PaymentMethod.spark);

  test('Synced publishes Bitcoin, USDB and payments without a payment event',
      () async {
    final sdk = _Sdk();
    final events = StreamController<spark.SdkEvent>.broadcast();
    stub(sdk, events.stream, 'wallet');
    final wrapper = BreezSdkSpark.forTesting(connectSdk: (_) async => sdk);
    await wrapper.connect(req: request);
    await flush();
    final balances = <spark.GetInfoResponse>[];
    final payments = <List<spark.Payment>>[];
    final balanceSub = wrapper.walletInfoStream.listen(balances.add);
    final paymentSub = wrapper.paymentsStream.listen(payments.add);
    final next = spark.GetInfoResponse(
        identityPubkey: 'wallet',
        balanceSats: BigInt.from(2000),
        tokenBalances: {
          'usdb': spark.TokenBalance(
              balance: BigInt.from(3000000),
              tokenMetadata: spark.TokenMetadata(
                  identifier: 'usdb',
                  issuerPublicKey: 'issuer',
                  name: 'USDB',
                  ticker: 'USDB',
                  decimals: 6,
                  maxSupply: BigInt.zero,
                  isFreezable: false)),
        });
    when(() => sdk.getInfo(
            request: const spark.GetInfoRequest(ensureSynced: false)))
        .thenAnswer((_) async => next);
    when(() => sdk.listPayments(request: const spark.ListPaymentsRequest()))
        .thenAnswer((_) async =>
            spark.ListPaymentsResponse(payments: [payment('received')]));
    events.add(const spark.SdkEvent.synced());
    await flush();
    expect(balances.single.balanceSats, BigInt.from(2000));
    expect(
        balances.single.tokenBalances['usdb']!.balance, BigInt.from(3000000));
    expect(payments.last.single.id, 'received');
    await balanceSub.cancel();
    await paymentSub.cancel();
    wrapper.disconnect();
    await flush();
    await events.close();
  });

  for (final stalledBalance in [true, false]) {
    test(
        'Synced publishes ${stalledBalance ? 'payments' : 'balance'} '
        'while the other cached read stalls and fails', () async {
      final sdk = _Sdk();
      final events = StreamController<spark.SdkEvent>.broadcast();
      stub(sdk, events.stream, 'wallet');
      final wrapper = BreezSdkSpark.forTesting(connectSdk: (_) async => sdk);
      await wrapper.connect(req: request);
      await flush();
      final balances = <spark.GetInfoResponse>[];
      final payments = <List<spark.Payment>>[];
      final balanceSub = wrapper.walletInfoStream.listen(balances.add);
      final paymentSub = wrapper.paymentsStream.listen(payments.add);
      final stalledInfo = Completer<spark.GetInfoResponse>();
      final stalledPayments = Completer<spark.ListPaymentsResponse>();
      if (stalledBalance) {
        when(() => sdk.getInfo(
                request: const spark.GetInfoRequest(ensureSynced: false)))
            .thenAnswer((_) => stalledInfo.future);
      } else {
        when(() => sdk.listPayments(request: const spark.ListPaymentsRequest()))
            .thenAnswer((_) => stalledPayments.future);
      }
      events.add(const spark.SdkEvent.synced());
      await flush();
      expect(balances, stalledBalance ? isEmpty : hasLength(1));
      expect(payments, stalledBalance ? hasLength(1) : isEmpty);
      if (stalledBalance) {
        stalledInfo.completeError(StateError('balance unavailable'));
      } else {
        stalledPayments.completeError(StateError('payments unavailable'));
      }
      await flush();
      await balanceSub.cancel();
      await paymentSub.cancel();
      wrapper.disconnect();
      await flush();
      await events.close();
    });
  }

  test('payment metadata update refreshes rows without a second payment result',
      () async {
    final sdk = _Sdk();
    final events = StreamController<spark.SdkEvent>.broadcast();
    stub(sdk, events.stream, 'wallet');
    final wrapper = BreezSdkSpark.forTesting(connectSdk: (_) async => sdk);
    await wrapper.connect(req: request);
    await flush();
    final payments = <List<spark.Payment>>[];
    final results = <spark.Payment>[];
    final paymentSub = wrapper.paymentsStream.listen(payments.add);
    final resultSub = wrapper.paymentResultStream.listen(results.add);
    final row = payment('enriched');
    when(() => sdk.listPayments(request: const spark.ListPaymentsRequest()))
        .thenAnswer((_) async => spark.ListPaymentsResponse(payments: [row]));
    events.add(spark.SdkEvent.paymentMetadataUpdated(payment: row));
    await flush();
    expect(payments.single.single.id, row.id);
    expect(results, isEmpty);
    await paymentSub.cancel();
    await resultSub.cancel();
    wrapper.disconnect();
    await flush();
    await events.close();
  });

  test('pull refresh still publishes payments when getInfo fails', () async {
    final sdk = _Sdk();
    stub(sdk, const Stream.empty(), 'wallet');
    final wrapper = BreezSdkSpark.forTesting(connectSdk: (_) async => sdk);
    await wrapper.connect(req: request);
    await flush();
    when(() => sdk.syncWallet(request: const spark.SyncWalletRequest()))
        .thenAnswer((_) async => const spark.SyncWalletResponse());
    when(() => sdk.getInfo(
            request: const spark.GetInfoRequest(ensureSynced: false)))
        .thenThrow(StateError('balance unavailable'));
    when(() => sdk.listPayments(request: const spark.ListPaymentsRequest()))
        .thenAnswer((_) async =>
            spark.ListPaymentsResponse(payments: [payment('received')]));
    final payments = <List<spark.Payment>>[];
    final sub = wrapper.paymentsStream.listen(payments.add);
    await wrapper.syncAndReread();
    await flush();
    expect(payments, hasLength(2), reason: 'immediate and post-sync snapshots');
    expect(payments.every((rows) => rows.single.id == 'received'), isTrue);
    await sub.cancel();
    wrapper.disconnect();
  });

  test(
      'pull publishes cached balances/history during blocked sync and after '
      'late native completion without Synced', () {
    fakeAsync((async) {
      final sdk = _Sdk();
      stub(sdk, const Stream.empty(), 'wallet');
      final native = Completer<spark.SyncWalletResponse>();
      when(() => sdk.syncWallet(request: const spark.SyncWalletRequest()))
          .thenAnswer((_) => native.future);
      final wrapper = BreezSdkSpark.forTesting(connectSdk: (_) async => sdk);
      final balances = <spark.GetInfoResponse>[];
      final payments = <List<spark.Payment>>[];
      wrapper.walletInfoStream.listen(balances.add);
      wrapper.paymentsStream.listen(payments.add);
      wrapper.connect(req: request);
      async.flushMicrotasks();
      balances.clear();
      payments.clear();
      var cached = info('wallet', sats: 2000, usdb: 3000000);
      var paymentId = 'cached-receive';
      when(() => sdk.getInfo(
              request: const spark.GetInfoRequest(ensureSynced: false)))
          .thenAnswer((_) async => cached);
      when(() => sdk.listPayments(request: const spark.ListPaymentsRequest()))
          .thenAnswer((_) async =>
              spark.ListPaymentsResponse(payments: [payment(paymentId)]));
      var completed = 0;
      wrapper.syncAndReread().then((_) => completed++);
      wrapper.syncAndReread().then((_) => completed++);
      async.flushMicrotasks();
      expect(completed, 0);
      expect(balances.last.balanceSats, BigInt.from(2000));
      expect(
          balances.last.tokenBalances['usdb']!.balance, BigInt.from(3000000));
      expect(payments.last.single.id, 'cached-receive');
      verify(() => sdk.syncWallet(request: const spark.SyncWalletRequest()))
          .called(1);
      async.elapse(const Duration(seconds: 21));
      async.flushMicrotasks();
      expect(completed, 2, reason: 'UI timeout leaves native sync running');

      cached = info('wallet', sats: 4000, usdb: 5000000);
      paymentId = 'late-receive';
      final before = payments.length;
      native.complete(const spark.SyncWalletResponse());
      async.flushMicrotasks();
      expect(balances.last.balanceSats, BigInt.from(4000));
      expect(
          balances.last.tokenBalances['usdb']!.balance, BigInt.from(5000000));
      expect(payments.last.single.id, 'late-receive');
      expect(payments.length, before + 1,
          reason: 'one final readback per shared native sync');
      wrapper.disconnect();
      async.flushMicrotasks();
    });
  });

  test('feed diagnostics show stages and changes without wallet/payment data',
      () async {
    final lines = <String>[];
    final previous = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message?.startsWith('[sdk-feed]') ?? false) lines.add(message!);
    };
    addTearDown(() => debugPrint = previous);
    final sdk = _Sdk();
    final events = StreamController<spark.SdkEvent>.broadcast();
    stub(sdk, events.stream, 'private-wallet-identity');
    final wrapper = BreezSdkSpark.forTesting(connectSdk: (_) async => sdk);
    await wrapper.connect(req: request);
    await flush();
    final cached =
        info('private-wallet-identity', sats: 123456789, usdb: 987654321);
    when(() => sdk.getInfo(
            request: const spark.GetInfoRequest(ensureSynced: false)))
        .thenAnswer((_) async => cached);
    when(() => sdk.listPayments(request: const spark.ListPaymentsRequest()))
        .thenAnswer((_) async => spark.ListPaymentsResponse(
            payments: [payment('private-payment-id')]));
    events.add(spark.SdkEvent.paymentSucceeded(
        payment: payment('private-payment-id')));
    await flush();
    events.add(const spark.SdkEvent.synced());
    await flush();
    events.addError(StateError('private-native-error'));
    await flush();
    events.add(spark.SdkEvent.paymentMetadataUpdated(
        payment: payment('private-payment-id')));
    await flush();
    await events.close();
    expect(lines, contains('[sdk-feed] event=payment_succeeded'));
    expect(lines, contains('[sdk-feed] event=synced'));
    expect(lines,
        contains('[sdk-feed] read=balance result=published changed=true'));
    expect(lines,
        contains('[sdk-feed] read=balance result=published changed=false'));
    expect(lines,
        contains('[sdk-feed] read=payments result=published changed=true'));
    expect(lines, contains('[sdk-feed] event_stream=error'));
    expect(lines, contains('[sdk-feed] event_stream=done'));
    expect(lines, contains('[sdk-feed] event=payment_metadata_updated'));
    final output = lines.join('\n');
    for (final secret in [
      'private-wallet-identity',
      'private-payment-id',
      '123456789',
      '987654321',
      'issuer',
      'private-native-error',
    ]) {
      expect(output, isNot(contains(secret)));
    }
    wrapper.disconnect();
    await flush();
  });

  test('boot timers: connect and sync are measured once, without overlap',
      () async {
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    addTearDown(() => TrackingService.debugTrackObserver = null);
    LatencyTracker.debugReset();
    final first = _Sdk(), second = _Sdk();
    final firstEvents = StreamController<spark.SdkEvent>.broadcast();
    final secondEvents = StreamController<spark.SdkEvent>.broadcast();
    stub(first, firstEvents.stream, 'first');
    stub(second, secondEvents.stream, 'second');
    final queue = [first, second];
    var connected = false;
    final wrapper = BreezSdkSpark.forTesting(connectSdk: (_) async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      connected = true;
      return queue.removeAt(0);
    });
    final connecting = wrapper.connect(req: request);
    expect(LatencyTracker.isRunning(LatencyKeys.sparkSync), isFalse,
        reason: 'sync is timed from the connected handle, not the call');
    await connecting;
    expect(connected, isTrue);
    expect(events.map((e) => e.$1), ['spark_connect_latency']);
    final (_, connectParams) = events.single;
    expect(connectParams!['result'], 'ok');
    expect(connectParams['duration_ms'], greaterThanOrEqualTo(15));
    expect(LatencyTracker.isRunning(LatencyKeys.sparkSync), isTrue);
    firstEvents.add(const spark.SdkEvent.synced());
    await flush();
    expect(events.map((e) => e.$1),
        ['spark_connect_latency', 'spark_sync_latency']);
    // A second synced event and a wallet switch measure nothing more.
    firstEvents.add(const spark.SdkEvent.synced());
    await flush();
    wrapper.disconnect();
    await wrapper.connect(req: request);
    secondEvents.add(const spark.SdkEvent.synced());
    await flush();
    expect(events, hasLength(2));
    wrapper.disconnect();
    await flush();
    await firstEvents.close();
    await secondEvents.close();
  });

  test('a failed boot connect is measured as an error, sync not started',
      () async {
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    addTearDown(() => TrackingService.debugTrackObserver = null);
    LatencyTracker.debugReset();
    final sdk = _Sdk();
    stub(sdk, const Stream.empty(), 'only');
    var attempts = 0;
    final wrapper = BreezSdkSpark.forTesting(connectSdk: (_) async {
      if (attempts++ == 0) throw StateError('no network');
      return sdk;
    });
    await expectLater(wrapper.connect(req: request), throwsStateError);
    expect(events.single.$1, 'spark_connect_latency');
    expect(events.single.$2!['result'], 'error');
    expect(LatencyTracker.isRunning(LatencyKeys.sparkSync), isFalse);
    // The retry connects without a second connect measurement and starts
    // the sync timer.
    await wrapper.connect(req: request);
    expect(events, hasLength(1));
    expect(LatencyTracker.isRunning(LatencyKeys.sparkSync), isTrue);
    wrapper.disconnect();
    await flush();
  });

  test('reconnect attaches new native events and never replays old deposits',
      () async {
    final first = _Sdk(), second = _Sdk();
    final firstEvents = StreamController<spark.SdkEvent>.broadcast();
    final secondEvents = StreamController<spark.SdkEvent>.broadcast();
    stub(first, firstEvents.stream, 'first');
    stub(second, secondEvents.stream, 'second');
    final queue = [first, second];
    final wrapper =
        BreezSdkSpark.forTesting(connectSdk: (_) async => queue.removeAt(0));
    await wrapper.connect(req: request);
    final updates = <SparkDepositUpdate>[];
    final oldSub = wrapper.depositsStream.listen(updates.add);
    firstEvents.add(spark.SdkEvent.newDeposits(newDeposits: [deposit('a')]));
    await flush();
    expect(updates, hasLength(1));
    await oldSub.cancel();
    wrapper.disconnect();
    await wrapper.connect(req: request);
    updates.clear();
    final sub = wrapper.depositsStream.listen(updates.add);
    await flush();
    expect(updates, isEmpty);
    firstEvents
        .add(spark.SdkEvent.claimedDeposits(claimedDeposits: [deposit('a')]));
    secondEvents.add(spark.SdkEvent.newDeposits(newDeposits: [deposit('b')]));
    await flush();
    expect(updates.single.deposits.single.txid, deposit('b').txid);
    verify(() => first.disconnect()).called(1);
    verify(() => second.addEventListener()).called(1);
    await sub.cancel();
    wrapper.disconnect();
    await flush();
    await firstEvents.close();
    await secondEvents.close();
  });

  test('old in-flight balance reads cannot publish into new wallet', () async {
    final first = _Sdk(), second = _Sdk();
    stub(first, const Stream.empty(), 'first');
    stub(second, const Stream.empty(), 'second');
    final delayed = Completer<spark.GetInfoResponse>();
    when(() => first.getInfo(
            request: const spark.GetInfoRequest(ensureSynced: false)))
        .thenAnswer((_) => delayed.future);
    final queue = [first, second];
    final wrapper =
        BreezSdkSpark.forTesting(connectSdk: (_) async => queue.removeAt(0));
    final identities = <String>[];
    final sub = wrapper.walletInfoStream
        .listen((event) => identities.add(event.identityPubkey));
    await wrapper.connect(req: request);
    wrapper.disconnect();
    await wrapper.connect(req: request);
    await flush();
    delayed.complete(info('first'));
    await flush();
    expect(identities, ['second']);
    await sub.cancel();
    wrapper.disconnect();
  });

  for (final explicitDisconnect in [false, true]) {
    test(
        'native shutdown releases pending stream cancellation '
        '(${explicitDisconnect ? 'disconnect then connect' : 'replacement'})',
        () {
      fakeAsync((async) {
        final first = _Sdk(), second = _Sdk();
        final listenerClosed = Completer<void>();
        final nativeClosed = Completer<void>();
        final events = StreamController<spark.SdkEvent>(
          onCancel: () => listenerClosed.future,
        );
        stub(first, events.stream, 'first');
        stub(second, const Stream.empty(), 'second');
        var disconnects = 0;
        when(() => first.disconnect()).thenAnswer((_) {
          disconnects++;
          // Native disconnect owns and closes the FRB event listener.
          listenerClosed.complete();
          return nativeClosed.future;
        });
        var connects = 0;
        final wrapper = BreezSdkSpark.forTesting(
            connectSdk: (_) async => ++connects == 1 ? first : second);
        wrapper.connect(req: request);
        async.flushMicrotasks();
        if (explicitDisconnect) wrapper.disconnect();
        var replaced = false;
        wrapper.connect(req: request).then((_) => replaced = true);
        async.flushMicrotasks();
        expect(disconnects, 1,
            reason: 'Stream cancellation must not prevent native shutdown');
        expect(connects, 1);
        expect(replaced, isFalse);
        expect(wrapper.instance, isNull);
        nativeClosed.complete();
        async.flushMicrotasks();
        expect(replaced, isTrue);
        expect(wrapper.instance, same(second));
        wrapper.disconnect();
        async.flushMicrotasks();
        events.close();
        async.flushMicrotasks();
      });
    });
  }

  test('native teardown finishes before next connect starts', () async {
    final first = _Sdk(), second = _Sdk();
    stub(first, const Stream.empty(), 'first');
    stub(second, const Stream.empty(), 'second');
    final teardown = Completer<void>();
    when(() => first.disconnect()).thenAnswer((_) => teardown.future);
    var connects = 0;
    final wrapper = BreezSdkSpark.forTesting(
        connectSdk: (_) async => ++connects == 1 ? first : second);
    await wrapper.connect(req: request);
    wrapper.disconnect();
    final next = wrapper.connect(req: request);
    await flush();
    expect(connects, 1);
    expect(wrapper.instance, isNull);
    teardown.complete();
    await next;
    expect(wrapper.instance, same(second));
    wrapper.disconnect();
  });

  test('replacement also waits for Dart stream cancellation', () async {
    final first = _Sdk(), second = _Sdk();
    final cancelled = Completer<void>();
    final events =
        StreamController<spark.SdkEvent>(onCancel: () => cancelled.future);
    stub(first, events.stream, 'first');
    stub(second, const Stream.empty(), 'second');
    var connects = 0;
    final wrapper = BreezSdkSpark.forTesting(
        connectSdk: (_) async => ++connects == 1 ? first : second);
    await wrapper.connect(req: request);
    final next = wrapper.connect(req: request);
    await flush();
    verify(() => first.disconnect()).called(1);
    expect(connects, 1);
    cancelled.complete();
    await next;
    expect(wrapper.instance, same(second));
    wrapper.disconnect();
    await events.close();
  });

  test('failed native teardown surfaces despite pending stream cancellation',
      () async {
    final sdk = _Sdk();
    final cancelled = Completer<void>();
    final events =
        StreamController<spark.SdkEvent>(onCancel: () => cancelled.future);
    stub(sdk, events.stream, 'first');
    when(() => sdk.disconnect())
        .thenThrow(StateError('native shutdown failed'));
    var connects = 0;
    final wrapper = BreezSdkSpark.forTesting(connectSdk: (_) async {
      connects++;
      return sdk;
    });
    await wrapper.connect(req: request);
    await expectLater(wrapper.connect(req: request), throwsStateError);
    await expectLater(wrapper.connect(req: request), throwsStateError);
    expect(connects, 1);
    expect(wrapper.instance, isNull);
    cancelled.complete();
    await events.close();
  });

  test('failed native teardown blocks another signer session', () async {
    final sdk = _Sdk();
    stub(sdk, const Stream.empty(), 'first');
    when(() => sdk.disconnect())
        .thenThrow(StateError('native shutdown failed'));
    var connects = 0;
    final wrapper = BreezSdkSpark.forTesting(connectSdk: (_) async {
      connects++;
      return sdk;
    });
    await wrapper.connect(req: request);
    wrapper.disconnect();
    await expectLater(wrapper.connect(req: request), throwsStateError);
    expect(connects, 1);
    expect(wrapper.instance, isNull);
  });

  test('cancellation failure cannot overlap an unfinished native shutdown',
      () async {
    final sdk = _Sdk();
    final cancelled = Completer<void>();
    final nativeClosed = Completer<void>();
    final events =
        StreamController<spark.SdkEvent>(onCancel: () => cancelled.future);
    stub(sdk, events.stream, 'first');
    when(() => sdk.disconnect()).thenAnswer((_) => nativeClosed.future);
    var connects = 0;
    final wrapper = BreezSdkSpark.forTesting(connectSdk: (_) async {
      connects++;
      return sdk;
    });
    await wrapper.connect(req: request);
    final failed = expectLater(wrapper.connect(req: request), throwsStateError);
    await flush();
    cancelled.completeError(StateError('stream cancellation failed'));
    await failed;
    await expectLater(wrapper.connect(req: request), throwsStateError);
    expect(connects, 1);
    expect(wrapper.instance, isNull);
    nativeClosed.complete();
    await events.close();
  });

  test('late payments read is discarded after replacing the SDK', () async {
    final first = _Sdk(), second = _Sdk();
    stub(first, const Stream.empty(), 'first');
    stub(second, const Stream.empty(), 'second');
    final delayed = Completer<spark.ListPaymentsResponse>();
    when(() => first.listPayments(request: const spark.ListPaymentsRequest()))
        .thenAnswer((_) => delayed.future);
    final queue = [first, second];
    final wrapper =
        BreezSdkSpark.forTesting(connectSdk: (_) async => queue.removeAt(0));
    final updates = <List<spark.Payment>>[];
    final sub = wrapper.paymentsStream.listen(updates.add);
    await wrapper.connect(req: request);
    await flush();
    verify(() => first.listPayments(request: const spark.ListPaymentsRequest()))
        .called(1);
    wrapper.disconnect();
    await wrapper.connect(req: request);
    await flush();
    expect(updates, hasLength(1));
    delayed.complete(const spark.ListPaymentsResponse(payments: []));
    await flush();
    expect(updates, hasLength(1));
    await sub.cancel();
    wrapper.disconnect();
  });

  test('disconnect during native connection retires unpublished handle',
      () async {
    final sdk = _Sdk();
    stub(sdk, const Stream.empty(), 'cancelled');
    final connecting = Completer<spark.BreezSdk>();
    final wrapper =
        BreezSdkSpark.forTesting(connectSdk: (_) => connecting.future);
    final result = wrapper.connect(req: request);
    final rejected = expectLater(result, throwsStateError);
    await flush();
    wrapper.disconnect();
    connecting.complete(sdk);
    await rejected;
    expect(wrapper.instance, isNull);
    verify(() => sdk.disconnect()).called(1);
    verifyNever(() => sdk.addEventListener());
  });

  test('synced signal follows only the current native SDK', () async {
    final first = _Sdk(), second = _Sdk();
    final firstEvents = StreamController<spark.SdkEvent>.broadcast();
    final secondEvents = StreamController<spark.SdkEvent>.broadcast();
    stub(first, firstEvents.stream, 'first');
    stub(second, secondEvents.stream, 'second');
    final queue = [first, second];
    final wrapper =
        BreezSdkSpark.forTesting(connectSdk: (_) async => queue.removeAt(0));
    var synced = 0;
    final sub = wrapper.syncedStream.listen((_) => synced++);
    await wrapper.connect(req: request);
    firstEvents.add(const spark.SdkEvent.synced());
    await flush();
    expect(synced, 1);
    wrapper.disconnect();
    await wrapper.connect(req: request);
    firstEvents.add(const spark.SdkEvent.synced());
    await flush();
    expect(synced, 1);
    secondEvents.add(const spark.SdkEvent.synced());
    await flush();
    expect(synced, 2);
    await sub.cancel();
    wrapper.disconnect();
    await flush();
    await firstEvents.close();
    await secondEvents.close();
  });
}
