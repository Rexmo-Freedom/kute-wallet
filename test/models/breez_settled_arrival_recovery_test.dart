import 'dart:async';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as spark;
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/breez/sdk_instance.dart';
import 'package:kute/models/breez/sdk_operation_guard.dart';
import 'package:kute/models/breez/shared_sync.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/services/one_balance/bitcoin_to_dollars_leg.dart';
import 'package:kute/services/security/address_guard.dart';
import 'package:mocktail/mocktail.dart';

class _Sdk extends Mock implements spark.BreezSdk {}

class _Request extends Fake implements spark.ConnectRequest {}

const _address =
    'sp1pgssy7d7vel0nh9m4326qc54e6rskpczn07dktww9rv4nu5ptvt0s9ucez8h3s';
SwapOrder row(
        {String id = 'arrival',
        String wallet = 'wallet',
        String status = 'success',
        String toNet = 'SPARK',
        String to = 'BTC',
        Duration age = const Duration(minutes: 1)}) =>
    SwapOrder(
        id: id,
        coinFrom: 'USDC',
        networkFrom: 'POLYGON',
        coinTo: to,
        networkTo: toNet,
        depositAddress: 'source',
        depositAmount: '1',
        withdrawalAmount: '0.000001',
        status: status,
        timestamp: DateTime.now().subtract(age).millisecondsSinceEpoch,
        withdrawalAddress: _address,
        depositMin: '0',
        depositMax: '0',
        rate: '0',
        refundAddress: '',
        provider: 'Orchestra',
        walletId: wallet);

void main() {
  final request = _Request();
  Future<void> flush() =>
      Future<void>.delayed(const Duration(milliseconds: 10));
  spark.GetInfoResponse info(int sats, {String? identity}) =>
      spark.GetInfoResponse(
          identityPubkey: identity ?? sparkIdentityPubkeyHex(_address)!,
          balanceSats: BigInt.from(sats),
          tokenBalances: {});
  void stub(_Sdk sdk, int sats) {
    when(() => sdk.addEventListener()).thenAnswer((_) => const Stream.empty());
    when(() => sdk.disconnect()).thenAnswer((_) async {});
    when(() => sdk.getInfo(
            request: const spark.GetInfoRequest(ensureSynced: false)))
        .thenAnswer((_) async => info(sats));
    when(() => sdk.listPayments(request: const spark.ListPaymentsRequest()))
        .thenAnswer(
            (_) async => const spark.ListPaymentsResponse(payments: []));
    when(() => sdk.syncWallet(request: const spark.SyncWalletRequest()))
        .thenAnswer((_) async => const spark.SyncWalletResponse());
  }

  test(
      'completed own delivery bypasses young sync once and joins duplicate reports',
      () async {
    final first = _Sdk(), second = _Sdk();
    stub(first, 0);
    stub(second, 100);
    final nativeSync = Completer<spark.SyncWalletResponse>();
    when(() => first.syncWallet(request: const spark.SyncWalletRequest()))
        .thenAnswer((_) => nativeSync.future);
    var connects = 0;
    final wrapper = BreezSdkSpark.forTesting(
        settlementObservation: Duration.zero,
        connectSdk: (_) async => ++connects == 1 ? first : second);
    await wrapper.connect(req: request, walletId: 'wallet', reconnectRequest: () async => request);
    await flush();
    final syncing = sharedSyncWallet(first);
    final arrival = row();
    await Future.wait([
      wrapper.refreshCompletedSparkOrder(arrival),
      wrapper.refreshCompletedSparkOrder(arrival)
    ]);
    expect(wrapper.instance, same(second));
    expect(connects, 2);
    await wrapper.refreshCompletedSparkOrder(arrival);
    expect(connects, 2,
        reason: 'same order cannot reconnect again after replacement');
    verify(() => first.disconnect()).called(1);
    nativeSync.complete(const spark.SyncWalletResponse());
    await syncing;
    wrapper.disconnect();
    await flush();
  });

  test(
      'already reflected balance avoids recovery even before its payment list event',
      () async {
    final sdk = _Sdk();
    stub(sdk, 0);
    final wrapper = BreezSdkSpark.forTesting(
        settlementObservation: Duration.zero, connectSdk: (_) async => sdk);
    await wrapper.connect(req: request, walletId: 'wallet', reconnectRequest: () async => request);
    await flush();
    when(() => sdk.getInfo(
            request: const spark.GetInfoRequest(ensureSynced: false)))
        .thenAnswer((_) async => info(100));
    await wrapper.refreshCompletedSparkOrder(row());
    verifyNever(() => sdk.disconnect());
    wrapper.disconnect();
    await flush();
  });

  test(
      'unrelated wallet, destination, status, history and external recipient never recover',
      () async {
    final sdk = _Sdk();
    stub(sdk, 0);
    final wrapper = BreezSdkSpark.forTesting(
        settlementObservation: Duration.zero, connectSdk: (_) async => sdk);
    await wrapper.connect(req: request, walletId: 'wallet', reconnectRequest: () async => request);
    await flush();
    for (final invalid in [
      row(wallet: 'other'),
      row(toNet: 'POLYGON'),
      row(status: 'exchanging'),
      row(status: 'refunded'),
      row(to: 'OTHER'),
      row(age: const Duration(days: 2))
    ]) {
      await wrapper.refreshCompletedSparkOrder(invalid);
    }
    when(() => sdk.getInfo(
            request: const spark.GetInfoRequest(ensureSynced: false)))
        .thenAnswer((_) async => info(0, identity: 'different'));
    await wrapper.refreshCompletedSparkOrder(row(id: 'external'));
    verifyNever(() => sdk.disconnect());
    wrapper.disconnect();
    await flush();
  });

  test('payment mutation defers settlement repair until actual native idle',
      () async {
    final first = _Sdk(), second = _Sdk();
    stub(first, 0);
    stub(second, 100);
    var connects = 0;
    final wrapper = BreezSdkSpark.forTesting(
        settlementObservation: Duration.zero,
        connectSdk: (_) async => ++connects == 1 ? first : second);
    await wrapper.connect(req: request, walletId: 'wallet', reconnectRequest: () async => request);
    await flush();
    final sending = Completer<void>();
    final operation = runSparkMutation(first, () => sending.future);
    await wrapper.refreshCompletedSparkOrder(row());
    expect(connects, 1);
    verifyNever(() => first.disconnect());
    sending.complete();
    await operation;
    await flush();
    expect(wrapper.instance, same(second));
    wrapper.disconnect();
    await flush();
  });

  test(
      'USDB recovery feeds a waiting funded-order landing on the replacement SDK',
      () async {
    final first = _Sdk(), second = _Sdk();
    stub(first, 0);
    stub(second, 0);
    final meta = spark.TokenMetadata(
        identifier: 'usdb',
        issuerPublicKey: 'issuer',
        name: 'Dollars',
        ticker: 'USDB',
        decimals: 6,
        maxSupply: BigInt.zero,
        isFreezable: false);
    when(() => second.getInfo(
            request: const spark.GetInfoRequest(ensureSynced: false)))
        .thenAnswer((_) async => spark.GetInfoResponse(
                identityPubkey: sparkIdentityPubkeyHex(_address)!,
                balanceSats: BigInt.zero,
                tokenBalances: {
                  'usdb': spark.TokenBalance(
                      balance: BigInt.from(4000000), tokenMetadata: meta)
                }));
    var connects = 0;
    final wrapper = BreezSdkSpark.forTesting(
        settlementObservation: Duration.zero,
        connectSdk: (_) async => ++connects == 1 ? first : second);
    await wrapper.connect(req: request, walletId: 'wallet', reconnectRequest: () async => request);
    await flush();
    final arrival = row().copyWith(coinTo: 'USDB', withdrawalAmount: '4');
    final watching = DollarsLandingWatcher(
      statusOf: (_) async => 'completed',
      dollarsNow: () => 0,
      freshDollars: () async {
        final current = wrapper.instance;
        if (current == null) return null;
        final reading = await current.getInfo(
            request: const spark.GetInfoRequest(ensureSynced: false));
        return reading.tokenBalances['usdb']?.balance.toDouble() == 4000000
            ? 4
            : 0;
      },
      kickSync: () =>
          unawaited(wrapper.syncAndRefresh(asset: ArrivalAsset.dollars)),
      pollEvery: const Duration(milliseconds: 1),
      freshEvery: const Duration(milliseconds: 1),
      freshFor: const Duration(milliseconds: 200),
      maxWait: const Duration(seconds: 1),
    ).watch(id: () => arrival.id, baselineUsd: 0, minRiseUsd: 4, enoughUsd: 4);
    await wrapper.refreshCompletedSparkOrder(arrival);
    final outcome = await watching;
    expect(outcome, isA<DollarsLanded>());
    expect((outcome as DollarsLanded).freshDollarsUsd, 4);
    expect(wrapper.instance, same(second));
    wrapper.disconnect();
    await flush();
  });

  for (final otherToken in [false, true]) {
    test(
        otherToken
            ? 'another token cannot satisfy a USDB settlement'
            : 'a fresh USDB entry avoids settlement recovery', () async {
      final first = _Sdk(), second = _Sdk();
      stub(first, 0);
      stub(second, 0);
      var connects = 0;
      final wrapper = BreezSdkSpark.forTesting(
          settlementObservation: Duration.zero,
          connectSdk: (_) async => ++connects == 1 ? first : second);
      await wrapper.connect(req: request, walletId: 'wallet', reconnectRequest: () async => request);
      await flush();
      final meta = spark.TokenMetadata(
          identifier: 'token',
          issuerPublicKey: 'issuer',
          name: 'Token',
          ticker: otherToken ? 'OTHER' : 'USDB',
          decimals: 6,
          maxSupply: BigInt.zero,
          isFreezable: false);
      when(() => first.getInfo(
              request: const spark.GetInfoRequest(ensureSynced: false)))
          .thenAnswer((_) async => spark.GetInfoResponse(
                  identityPubkey: sparkIdentityPubkeyHex(_address)!,
                  balanceSats: BigInt.zero,
                  tokenBalances: {
                    'token': spark.TokenBalance(
                        balance: BigInt.from(4000000), tokenMetadata: meta)
                  }));
      await wrapper.refreshCompletedSparkOrder(
          row().copyWith(coinTo: 'USDB', withdrawalAmount: '4'));
      expect(connects, otherToken ? 2 : 1);
      wrapper.disconnect();
      await flush();
    });
  }

  test('pending-send event bursts do not exhaust eventual settlement recovery',
      () async {
    final first = _Sdk(), second = _Sdk();
    stub(first, 0);
    stub(second, 100);
    final events = StreamController<spark.SdkEvent>.broadcast();
    when(() => first.addEventListener()).thenAnswer((_) => events.stream);
    var connects = 0;
    final wrapper = BreezSdkSpark.forTesting(
        settlementObservation: Duration.zero,
        connectSdk: (_) async => ++connects == 1 ? first : second);
    await wrapper.connect(req: request, walletId: 'wallet', reconnectRequest: () async => request);
    await flush();
    final outgoing = spark.Payment(
        id: 'outgoing',
        paymentType: spark.PaymentType.send,
        status: spark.PaymentStatus.pending,
        amount: BigInt.one,
        fees: BigInt.zero,
        timestamp: BigInt.zero,
        method: spark.PaymentMethod.spark);
    var pending = true;
    when(() => first.listPayments(request: const spark.ListPaymentsRequest()))
        .thenAnswer((_) async =>
            spark.ListPaymentsResponse(payments: pending ? [outgoing] : []));
    await wrapper.refreshCompletedSparkOrder(row());
    for (var i = 0; i < 6; i++) {
      events.add(spark.SdkEvent.paymentSucceeded(payment: outgoing));
      await flush();
    }
    expect(connects, 1);
    verifyNever(() => first.disconnect());
    pending = false;
    events.add(spark.SdkEvent.paymentSucceeded(payment: outgoing));
    await flush();
    expect(wrapper.instance, same(second));
    wrapper.disconnect();
    await flush();
    await events.close();
  });

  test('durable pending outgoing payment still blocks young-sync exemption',
      () async {
    final sdk = _Sdk();
    stub(sdk, 0);
    final wrapper = BreezSdkSpark.forTesting(
        settlementObservation: Duration.zero, connectSdk: (_) async => sdk);
    await wrapper.connect(req: request, walletId: 'wallet', reconnectRequest: () async => request);
    await flush();
    when(() => sdk.listPayments(request: const spark.ListPaymentsRequest()))
        .thenAnswer((_) async => spark.ListPaymentsResponse(payments: [
              spark.Payment(
                  id: 'outgoing',
                  paymentType: spark.PaymentType.send,
                  status: spark.PaymentStatus.pending,
                  amount: BigInt.one,
                  fees: BigInt.zero,
                  timestamp: BigInt.zero,
                  method: spark.PaymentMethod.spark)
            ]));
    await wrapper.refreshCompletedSparkOrder(row());
    verifyNever(() => sdk.disconnect());
    wrapper.disconnect();
    await flush();
  });
}
