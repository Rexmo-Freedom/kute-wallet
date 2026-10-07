import 'dart:async';
import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as spark;
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/breez/deposit_update.dart';
import 'package:kute/models/breez/sdk_instance.dart';
import 'package:mocktail/mocktail.dart';

class _Sdk extends Mock implements spark.BreezSdk {}

class _Request extends Fake implements spark.ConnectRequest {}

void main() {
  final request = _Request();
  Future<void> flush() => Future<void>.delayed(Duration.zero);
  spark.GetInfoResponse info(String identity) => spark.GetInfoResponse(
        identityPubkey: identity,
        balanceSats: BigInt.one,
        tokenBalances: {},
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
    when(() => sdk.getInfo(request: const spark.GetInfoRequest()))
        .thenAnswer((_) async => info(identity));
    when(() => sdk.listPayments(request: const spark.ListPaymentsRequest()))
        .thenAnswer(
            (_) async => const spark.ListPaymentsResponse(payments: []));
  }

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
    when(() => first.getInfo(request: const spark.GetInfoRequest()))
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

  test('failed native teardown blocks another signer session', () async {
    final sdk = _Sdk();
    stub(sdk, const Stream.empty(), 'first');
    when(() => sdk.disconnect()).thenThrow(StateError('native shutdown failed'));
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

  test('late payments read is discarded after replacing the SDK', () async {
    final first = _Sdk(), second = _Sdk();
    stub(first, const Stream.empty(), 'first');
    stub(second, const Stream.empty(), 'second');
    final delayed = Completer<spark.ListPaymentsResponse>();
    when(() => first.listPayments(request: const spark.ListPaymentsRequest()))
        .thenAnswer((_) => delayed.future);
    final queue = [first, second];
    final wrapper = BreezSdkSpark.forTesting(
        connectSdk: (_) async => queue.removeAt(0));
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
