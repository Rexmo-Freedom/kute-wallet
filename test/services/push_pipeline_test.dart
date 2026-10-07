import 'dart:async';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as spark;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/breez/deposit_update.dart';
import 'package:kute/models/breez/sdk_instance.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/services/mempool_address_service.dart';
import 'package:kute/services/sync/push_pipeline.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:mocktail/mocktail.dart';

class _Sdk extends Mock implements spark.BreezSdk {}

class _Request extends Fake implements spark.ConnectRequest {}

class _Settings extends StateNotifier<Settings> implements SettingsModel {
  _Settings()
      : super(Settings(
          currency: 'USD',
          language: 'en',
          btcFormat: 'sats',
          backup: false,
          biometricsEnabled: false,
          bitcoinElectrumNode: '',
          nodeType: 'default',
          reviewDone: true,
          wallets: [WalletConfig(id: 'spending', name: 'Spending')],
        ));

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() {
    registerFallbackValue(const spark.ListUnclaimedDepositsRequest());
    registerFallbackValue(const spark.ListPaymentsRequest());
    registerFallbackValue(const spark.GetInfoRequest());
    registerFallbackValue(const spark.SyncWalletRequest());
  });

  Future<void> flush() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  spark.DepositInfo deposit(String txid) => spark.DepositInfo(
        txid: txid.padRight(64, '0'),
        vout: 0,
        amountSats: BigInt.from(10000),
        isMature: true,
      );

  _Sdk sdkWith(
      Stream<spark.SdkEvent> events, List<spark.DepositInfo> deposits) {
    final sdk = _Sdk();
    when(() => sdk.addEventListener()).thenAnswer((_) => events);
    when(() => sdk.disconnect()).thenAnswer((_) async {});
    when(() => sdk.getInfo(request: any(named: 'request'))).thenAnswer(
        (_) async => spark.GetInfoResponse(
            identityPubkey: 'id', balanceSats: BigInt.one, tokenBalances: {}));
    when(() => sdk.listPayments(request: any(named: 'request'))).thenAnswer(
        (_) async => const spark.ListPaymentsResponse(payments: []));
    when(() => sdk.listUnclaimedDeposits(request: any(named: 'request')))
        .thenAnswer((_) async =>
            spark.ListUnclaimedDepositsResponse(deposits: deposits));
    return sdk;
  }

  Future<({ProviderContainer container, PushPipeline pipeline})> attach(
      BreezSdkSpark wrapper,
      {Transaction? seed}) async {
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith((ref) => _Settings()),
      breezSDKProvider.overrideWith((ref) async => wrapper),
    ]);
    container.read(walletTransactionCacheProvider.notifier).setForWallet(
        'spending',
        seed ??
            Transaction(
                bitcoinTransactions: [],
                sparkTransactions: [],
                sparkUnclaimedDeposits: []));
    final pipeline = PushPipeline(onSyncRequested: () {});
    addTearDown(() {
      pipeline.stop();
      container.dispose();
      wrapper.disconnect();
    });
    pipeline.start(container);
    await flush();
    return (container: container, pipeline: pipeline);
  }

  List<String> rows(ProviderContainer container) => container
      .read(walletTransactionCacheProvider)['spending']!
      .sparkUnclaimedDeposits
      .map((d) => d.txid)
      .toList();

  test('follows an SDK reconnect it did not start and re-reads after sync',
      () async {
    final firstEvents = StreamController<spark.SdkEvent>.broadcast();
    final secondEvents = StreamController<spark.SdkEvent>.broadcast();
    addTearDown(firstEvents.close);
    addTearDown(secondEvents.close);
    final first = sdkWith(firstEvents.stream, [deposit('a')]);
    final second = sdkWith(secondEvents.stream, [deposit('b')]);
    final queue = [first, second];
    final wrapper =
        BreezSdkSpark.forTesting(connectSdk: (_) async => queue.removeAt(0));
    await wrapper.connect(req: _Request());
    final harness = await attach(wrapper);
    expect(rows(harness.container), [deposit('a').txid]);

    wrapper.disconnect();
    await wrapper.connect(req: _Request());
    await flush();
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await flush();
    expect(rows(harness.container), [deposit('b').txid]);

    // A sync can claim a deposit without emitting a deposit event.
    when(() => second.listUnclaimedDeposits(request: any(named: 'request')))
        .thenAnswer((_) async =>
            const spark.ListUnclaimedDepositsResponse(deposits: []));
    secondEvents.add(const spark.SdkEvent.synced());
    await flush();
    expect(rows(harness.container), isEmpty);
    verify(() => first.listUnclaimedDeposits(request: any(named: 'request')))
        .called(1);
  });

  test('sync signals during an in-flight deposit read coalesce into one rerun',
      () async {
    final events = StreamController<spark.SdkEvent>.broadcast();
    addTearDown(events.close);
    final sdk = sdkWith(events.stream, const []);
    final firstRead = Completer<spark.ListUnclaimedDepositsResponse>();
    var reads = 0;
    when(() => sdk.listUnclaimedDeposits(request: any(named: 'request')))
        .thenAnswer((_) => ++reads == 1
            ? firstRead.future
            : Future.value(
                spark.ListUnclaimedDepositsResponse(deposits: [deposit('c')])));
    final wrapper = BreezSdkSpark.forTesting(connectSdk: (_) async => sdk);
    await wrapper.connect(req: _Request());
    final harness = await attach(wrapper);
    events
      ..add(const spark.SdkEvent.synced())
      ..add(const spark.SdkEvent.synced());
    await flush();
    expect(reads, 1);
    firstRead.complete(
        spark.ListUnclaimedDepositsResponse(deposits: [deposit('a')]));
    await flush();
    expect(reads, 2);
    expect(rows(harness.container), [deposit('c').txid]);
  });

  test('snapshots skip credited and mempool deposits and unchanged re-reads',
      () async {
    final events = StreamController<spark.SdkEvent>.broadcast();
    addTearDown(events.close);
    final sdk =
        sdkWith(events.stream, [deposit('a'), deposit('b'), deposit('c')]);
    final credited = spark.Payment(
      id: 'claim-a',
      paymentType: spark.PaymentType.receive,
      status: spark.PaymentStatus.pending,
      amount: BigInt.from(9000),
      fees: BigInt.zero,
      timestamp: BigInt.one,
      method: spark.PaymentMethod.deposit,
      details: spark.PaymentDetails.deposit(
          txId: deposit('a').txid.toUpperCase(), vout: 0),
    );
    when(() => sdk.listPayments(request: any(named: 'request'))).thenAnswer(
        (_) async => spark.ListPaymentsResponse(payments: [credited]));
    final wrapper = BreezSdkSpark.forTesting(connectSdk: (_) async => sdk);
    await wrapper.connect(req: _Request());
    final seenAt = DateTime.utc(2026, 9, 15);
    final harness = await attach(wrapper,
        seed: Transaction(
          bitcoinTransactions: [],
          sparkTransactions: [
            SparkTransaction(
                id: 'claim-a',
                timestamp: seenAt,
                isConfirmed: false,
                details: credited),
          ],
          sparkUnclaimedDeposits: [],
          sparkPendingDeposits: [
            SparkPendingDeposit(
              id: 'b',
              timestamp: seenAt,
              confirmations: 2,
              mempoolTx: MempoolTransaction(
                  txid: deposit('b').txid.toUpperCase(),
                  confirmed: false,
                  fee: 0,
                  balanceChange: 10000),
            ),
          ],
        ));
    expect(rows(harness.container), [deposit('c').txid]);

    List<SparkUnclaimedDeposit> cached() => harness.container
        .read(walletTransactionCacheProvider)['spending']!
        .sparkUnclaimedDeposits;
    final before = cached();
    events.add(const spark.SdkEvent.synced());
    await flush();
    verify(() => sdk.listUnclaimedDeposits(request: any(named: 'request')))
        .called(2);
    expect(identical(cached(), before), isTrue);
  });

  spark.Payment received(String id, int sats) => spark.Payment(
        id: id,
        paymentType: spark.PaymentType.receive,
        status: spark.PaymentStatus.completed,
        amount: BigInt.from(sats),
        fees: BigInt.zero,
        timestamp: BigInt.from(DateTime.now().millisecondsSinceEpoch ~/ 1000),
        method: spark.PaymentMethod.lightning,
      );

  void listReceive(ProviderContainer container, spark.Payment payment) {
    container.read(walletTransactionCacheProvider.notifier).mergeForWallet(
        'spending',
        (current) => current.copyWith(sparkTransactions: [
              ...current.sparkTransactions,
              SparkTransaction(
                id: payment.id,
                timestamp: DateTime.fromMillisecondsSinceEpoch(
                    payment.timestamp.toInt() * 1000),
                details: payment,
                isConfirmed: true,
              ),
            ]));
  }

  test('a receive that settles while a send is held shows at once', () async {
    final events = StreamController<spark.SdkEvent>.broadcast();
    addTearDown(events.close);
    final sdk = sdkWith(events.stream, const []);
    final wrapper = BreezSdkSpark.forTesting(connectSdk: (_) async => sdk);
    await wrapper.connect(req: _Request());
    final harness = await attach(wrapper);
    final cache = harness.container.read(walletBalanceCacheProvider.notifier);
    cache.updateSparkBitcoinbalance('spending', 10000,
        source: BalanceSource.stream);
    cache.holdOutgoingSparkSend('spending',
        key: 'send', balanceBeforeSats: 10000, debitSats: 10000, feeSats: 500);
    expect(cache.shownSparkSats('spending'), 0);
    // The SDK refreshes on the incoming payment: the send out, 4,000 in.
    cache.updateSparkBitcoinbalance('spending', 4000,
        source: BalanceSource.stream);
    listReceive(harness.container, received('incoming', 4000));
    expect(cache.shownSparkSats('spending'), 4000);
    expect(cache.hasSparkSendHold('spending'), isFalse);
  });

  spark.GetInfoResponse infoWith(int sats) => spark.GetInfoResponse(
      identityPubkey: 'id', balanceSats: BigInt.from(sats), tokenBalances: {});

  test('each SDK sync re-reads the bitcoin balance, once per burst',
      () async {
    final events = StreamController<spark.SdkEvent>.broadcast();
    addTearDown(events.close);
    final sdk = sdkWith(events.stream, const []);
    final wrapper = BreezSdkSpark.forTesting(connectSdk: (_) async => sdk);
    await wrapper.connect(req: _Request());
    final harness = await attach(wrapper);
    final cache = harness.container.read(walletBalanceCacheProvider.notifier);
    clearInteractions(sdk);
    // A receive arrived through the SDK's own sync: no payment event,
    // only Synced, and its cached figure now counts it.
    when(() => sdk.getInfo(request: any(named: 'request')))
        .thenAnswer((_) async => infoWith(25000));
    events
      ..add(const spark.SdkEvent.synced())
      ..add(const spark.SdkEvent.synced())
      ..add(const spark.SdkEvent.synced());
    await flush();
    expect(cache.shownSparkSats('spending'), 1);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await flush();
    expect(cache.shownSparkSats('spending'), 25000);
    verify(() => sdk.getInfo(request: any(named: 'request'))).called(1);
  });

  test('a sync re-read due after the pipeline stopped writes nothing',
      () async {
    final events = StreamController<spark.SdkEvent>.broadcast();
    addTearDown(events.close);
    final sdk = sdkWith(events.stream, const []);
    final wrapper = BreezSdkSpark.forTesting(connectSdk: (_) async => sdk);
    await wrapper.connect(req: _Request());
    final harness = await attach(wrapper);
    when(() => sdk.getInfo(request: any(named: 'request')))
        .thenAnswer((_) async => infoWith(25000));
    events.add(const spark.SdkEvent.synced());
    await flush();
    harness.pipeline.stop();
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await flush();
    expect(
        harness.container
            .read(walletBalanceCacheProvider.notifier)
            .shownSparkSats('spending'),
        1);
  });

  test('a listed receive the cached balance missed is caught up by a sync',
      () async {
    final events = StreamController<spark.SdkEvent>.broadcast();
    addTearDown(events.close);
    final sdk = sdkWith(events.stream, const []);
    var sdkSats = 0;
    var syncs = 0;
    when(() => sdk.getInfo(request: any(named: 'request')))
        .thenAnswer((_) async => infoWith(sdkSats));
    when(() => sdk.syncWallet(request: any(named: 'request')))
        .thenAnswer((_) async {
      syncs++;
      sdkSats = 4000;
      return const spark.SyncWalletResponse();
    });
    final wrapper = BreezSdkSpark.forTesting(connectSdk: (_) async => sdk);
    await wrapper.connect(req: _Request());
    final harness = await attach(wrapper);
    final cache = harness.container.read(walletBalanceCacheProvider.notifier);
    // The periodic listPayments lists the receive; getInfo() still
    // answers the figure from before it.
    listReceive(harness.container, received('incoming', 4000));
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    await flush();
    expect(syncs, 1);
    expect(cache.shownSparkSats('spending'), 4000);
  });

  test('a receive the balance already counted forces no sync', () async {
    final events = StreamController<spark.SdkEvent>.broadcast();
    addTearDown(events.close);
    final sdk = sdkWith(events.stream, const []);
    when(() => sdk.syncWallet(request: any(named: 'request')))
        .thenAnswer((_) async => const spark.SyncWalletResponse());
    final wrapper = BreezSdkSpark.forTesting(connectSdk: (_) async => sdk);
    await wrapper.connect(req: _Request());
    final harness = await attach(wrapper);
    final cache = harness.container.read(walletBalanceCacheProvider.notifier);
    // The payment event's getInfo() lands just before its payments list.
    cache.updateSparkBitcoinbalance('spending', 4001,
        source: BalanceSource.stream);
    listReceive(harness.container, received('incoming', 4000));
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    await flush();
    verifyNever(() => sdk.syncWallet(request: any(named: 'request')));
    expect(cache.shownSparkSats('spending'), 4001);
  });

  group('SparkBalanceCatchUp', () {
    late List<int> answers;
    late int reads;
    late int syncs;
    late int current;
    late DateTime? raisedAt;
    late List<int> published;
    late SparkBalanceCatchUp catchUp;

    setUp(() {
      reads = 0;
      syncs = 0;
      current = 1000;
      raisedAt = null;
      published = [];
      catchUp = SparkBalanceCatchUp(
        readSats: () async {
          final i = reads < answers.length ? reads : answers.length - 1;
          reads++;
          return answers[i];
        },
        syncWallet: () async => syncs++,
        currentSats: () => current,
        raisedAt: () => raisedAt,
        publish: published.add,
        delay: Duration.zero,
      );
      addTearDown(catchUp.dispose);
    });

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 20));

    test('the first receives are only a baseline', () async {
      answers = [1000];
      catchUp.onReceives('a');
      await settle();
      expect(reads, 0);
    });

    test('a figure that went up with the receive is left alone', () async {
      answers = [1000];
      catchUp.onReceives('a');
      raisedAt = DateTime.now();
      catchUp.onReceives('a,b');
      await settle();
      expect(reads, 0);
      expect(syncs, 0);
    });

    test('a re-read that moved is published without a sync', () async {
      answers = [3000];
      catchUp.onReceives('a');
      catchUp.onReceives('a,b');
      await settle();
      expect(published, [3000]);
      expect(syncs, 0);
    });

    test('an unchanged figure forces one sync, then the fresh one shows',
        () async {
      answers = [1000, 3000];
      catchUp.onReceives('a');
      catchUp.onReceives('a,b');
      await settle();
      expect(syncs, 1);
      expect(reads, 2);
      expect(published, [3000]);
    });

    test('a failed sync still publishes what the cache holds, once',
        () async {
      final failing = SparkBalanceCatchUp(
        readSats: () async {
          reads++;
          return 1000;
        },
        syncWallet: () => Future<void>.error(TimeoutException('offline')),
        currentSats: () => current,
        raisedAt: () => null,
        publish: published.add,
        delay: Duration.zero,
      );
      addTearDown(failing.dispose);
      failing.onReceives('a');
      failing.onReceives('a,b');
      await settle();
      expect(reads, 2);
      expect(published, [1000]);
    });

    test('nothing runs after dispose', () async {
      answers = [3000];
      catchUp.onReceives('a');
      catchUp.onReceives('a,b');
      catchUp.dispose();
      await settle();
      expect(reads, 0);
      expect(published, isEmpty);
    });
  });

  group('auto-claim analytics', () {
    final events = <(String, Map<String, Object>?)>[];
    setUp(() {
      events.clear();
      PushPipeline.resetAutoClaimTrackingForTest();
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    });
    tearDown(() => TrackingService.debugTrackObserver = null);

    spark.DepositInfo dep(String txid, {spark.DepositClaimError? error}) =>
        spark.DepositInfo(
          txid: txid,
          vout: 0,
          amountSats: BigInt.from(1000),
          isMature: true,
          claimError: error,
        );

    test('claimed event fires once per deposit and never sends the id', () {
      final update =
          SparkDepositUpdate(SparkDepositUpdateKind.claimed, [dep('aa' * 32)]);
      PushPipeline.trackAutoClaimEvent(update);
      PushPipeline.trackAutoClaimEvent(update);
      expect(events.map((e) => e.$1), ['spark_deposit_auto_claimed']);
      expect(events.single.$2, {'outcome': 'claimed'});
    });

    test('claim error upsert emits auto_claim_failed with a fixed reason', () {
      final update = SparkDepositUpdate(SparkDepositUpdateKind.upsert, [
        dep('bb' * 32,
            error: spark.DepositClaimError.maxDepositClaimFeeExceeded(
              tx: 'bb' * 32,
              vout: 0,
              requiredFeeSats: BigInt.from(500),
              requiredFeeRateSatPerVbyte: BigInt.from(5),
            )),
        dep('cc' * 32),
      ]);
      PushPipeline.trackAutoClaimEvent(update);
      PushPipeline.trackAutoClaimEvent(update);
      expect(events.map((e) => e.$1), ['auto_claim_failed']);
      expect(events.single.$2, {'reason': 'fee_exceeded'});
    });

    test('snapshots never emit', () {
      PushPipeline.trackAutoClaimEvent(SparkDepositUpdate(
          SparkDepositUpdateKind.snapshot, [
        dep('dd' * 32,
            error: const spark.DepositClaimError.generic(message: 'x'))
      ]));
      expect(events, isEmpty);
    });
  });
}
