// The Bitcoin hero follows the SDK, whatever else is running.
//
// Founder report (October 2026): a "Withdraw · from Investments" to
// Bitcoin landed on the wallet's own Spark balance, but the Bitcoin
// balance on screen did not move. The SDK did its part: it raises
// `paymentSucceeded` for the incoming transfer after refreshing its cached
// balance, and the wrapper re-read and published it. The reading only
// reached the hero through the background sync's push pipeline, which is
// torn down and re-attached on wallet switches, resumes and reconnects,
// attached only while the active wallet is a Spark wallet, and drops the
// reading that reveals a reconnect. These tests pin the one rule that
// replaced it: every reading the wrapper publishes lands in the spending
// wallet's slot of `walletBalanceCacheProvider`, the one source every
// Bitcoin balance reads, with no pipeline, poll or route involved.

import 'dart:async';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as spark;
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/breez/sdk_instance.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/services/orchestra/own_spark_arrivals.dart';
import 'package:mocktail/mocktail.dart';

class _Sdk extends Mock implements spark.BreezSdk {}

class _Request extends Fake implements spark.ConnectRequest {}

class _Settings extends StateNotifier<Settings> implements SettingsModel {
  _Settings({String active = 'spending'})
      : super(Settings(
          currency: 'USD',
          language: 'en',
          btcFormat: 'sats',
          backup: false,
          biometricsEnabled: false,
          bitcoinElectrumNode: '',
          nodeType: 'default',
          reviewDone: true,
          activeWalletId: active,
          wallets: [
            WalletConfig(id: 'spending', name: 'Spending'),
            WalletConfig(id: 'savings', name: 'Savings', sparkEnabled: false),
          ],
        ));

  void park(String walletId) =>
      state = state.copyWith(activeWalletId: walletId);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// A fake SDK whose cached balance the test moves, and the real wrapper
/// around it.
class _Wallet {
  _Wallet() {
    when(() => sdk.addEventListener()).thenAnswer((_) => events.stream);
    when(() => sdk.disconnect()).thenAnswer((_) async {});
    when(() => sdk.getInfo(request: any(named: 'request'))).thenAnswer(
        (_) async {
      reads++;
      final gate = nextReadGate;
      final reading = sats;
      nextReadGate = null;
      if (gate != null) await gate.future;
      return spark.GetInfoResponse(
          identityPubkey: 'id',
          balanceSats: BigInt.from(reading),
          tokenBalances: {});
    });
    when(() => sdk.listPayments(request: any(named: 'request'))).thenAnswer(
        (_) async => const spark.ListPaymentsResponse(payments: []));
    when(() => sdk.syncWallet(request: any(named: 'request')))
        .thenAnswer((_) async {
      syncs++;
      onSync?.call();
      return const spark.SyncWalletResponse();
    });
  }

  final sdk = _Sdk();
  final events = StreamController<spark.SdkEvent>.broadcast();
  late final wrapper = BreezSdkSpark.forTesting(connectSdk: (_) async => sdk);

  /// What the SDK's cached balance holds now.
  int sats = 10000;
  int reads = 0;
  int syncs = 0;
  void Function()? onSync;

  /// Holds the next `getInfo` answer (taken at the call) until completed.
  Completer<void>? nextReadGate;

  Future<void> connect() => wrapper.connect(req: _Request());

  void close() {
    wrapper.disconnect();
    events.close();
  }

  /// The SDK delivers an incoming Spark transfer of [amount] sats: its
  /// cached balance is refreshed first, then `paymentSucceeded` is raised.
  void receive(int amount, {String id = 'rx'}) {
    sats += amount;
    events.add(spark.SdkEvent.paymentSucceeded(payment: _receive(id, amount)));
  }
}

spark.Payment _receive(String id, int amount,
        {spark.PaymentStatus status = spark.PaymentStatus.completed}) =>
    spark.Payment(
      id: id,
      paymentType: spark.PaymentType.receive,
      status: status,
      amount: BigInt.from(amount),
      fees: BigInt.zero,
      timestamp:
          BigInt.from(DateTime.now().millisecondsSinceEpoch ~/ 1000),
      method: spark.PaymentMethod.spark,
    );

SwapOrder _row(
  String id, {
  required String status,
  String from = 'USDC',
  String fromNet = 'POLYGON',
  required DateTime createdAt,
}) =>
    SwapOrder(
      id: id,
      coinFrom: from,
      networkFrom: fromNet,
      coinTo: 'BTC',
      networkTo: 'SPARK',
      depositAddress: 'dep',
      depositAmount: '7.78',
      withdrawalAmount: '0.00009300',
      status: status,
      timestamp: createdAt.millisecondsSinceEpoch,
      withdrawalAddress: 'sp1self',
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: '',
      provider: 'Orchestra',
      walletId: 'spending',
    );

ProviderContainer _container(_Wallet wallet, _Settings settings) {
  final container = ProviderContainer(overrides: [
    settingsProvider.overrideWith((_) => settings),
    sparkWalletInfoFeedProvider
        .overrideWithValue(wallet.wrapper.walletInfoStream),
  ]);
  // The hero's read: the active wallet's slot.
  container.listen(balanceNotifierProvider, (_, __) {});
  return container;
}

int _hero(ProviderContainer c) =>
    c.read(balanceNotifierProvider).sparkBitcoinbalance;

int _spending(ProviderContainer c) =>
    c.read(walletBalanceCacheProvider)['spending']?.sparkBitcoinbalance ?? 0;

void main() {
  setUpAll(() {
    registerFallbackValue(const spark.GetInfoRequest());
    registerFallbackValue(const spark.ListPaymentsRequest());
    registerFallbackValue(const spark.SyncWalletRequest());
  });

  setUp(OwnSparkArrivals.reset);
  tearDown(OwnSparkArrivals.reset);

  testWidgets(
      'an incoming spark:BTC paymentSucceeded shows on the Bitcoin hero '
      'within one frame', (tester) async {
    final wallet = _Wallet();
    addTearDown(wallet.close);
    final settings = _Settings();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith((_) => settings),
        sparkWalletInfoFeedProvider
            .overrideWithValue(wallet.wrapper.walletInfoStream),
      ],
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Consumer(
          builder: (_, ref, __) {
            final b = ref.watch(balanceNotifierProvider);
            return Text('${b.sparkBitcoinbalance + b.onChainBtcBalance}');
          },
        ),
      ),
    ));
    await wallet.connect();
    await tester.idle();
    await tester.pump();
    expect(find.text('10000'), findsOneWidget);

    // The event is delivered (no frame), then exactly one frame.
    wallet.receive(9300);
    await tester.idle();
    expect(find.text('10000'), findsOneWidget, reason: 'not drawn yet');
    await tester.pump();
    expect(find.text('19300'), findsOneWidget,
        reason: 'the event, its read and the cache write all land before '
            'the next frame: no timer, poll or pipeline in between');
  });

  test(
      'parked on another wallet with no sync pipeline running, the spending '
      'balance still follows the event, and shows at once on return', () {
    fakeAsync((async) {
      final wallet = _Wallet();
      final settings = _Settings(active: 'savings');
      final c = _container(wallet, settings);
      wallet.connect();
      async.flushMicrotasks();
      expect(_spending(c), 10000);

      wallet.receive(9300);
      async.flushMicrotasks();
      expect(_spending(c), 19300);
      expect(_hero(c), 0, reason: 'the parked wallet holds no Spark sats');
      expect(async.elapsed, Duration.zero);

      settings.park('spending');
      async.flushMicrotasks();
      expect(_hero(c), 19300, reason: 'no read, no sync on the way back');
      c.dispose();
      wallet.close();
      async.flushMicrotasks();
    });
  });

  test(
      'after an SDK reconnect the first reading lands at once (the push '
      'pipeline used to drop it and re-attach a second later)', () async {
    final wallet = _Wallet();
    final c = _container(wallet, _Settings());
    addTearDown(() {
      c.dispose();
      wallet.close();
    });
    Future<void> flush() async {
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    await wallet.connect();
    await flush();
    expect(_hero(c), 10000);
    wallet.wrapper.disconnect();
    wallet.sats = 17000;
    final reconnected = Stopwatch()..start();
    await wallet.connect();
    await flush();
    expect(_hero(c), 17000);
    expect(reconnected.elapsed, lessThan(const Duration(milliseconds: 500)));
    wallet.receive(3000);
    await flush();
    expect(_hero(c), 20000);
  });

  test('a delivery with no swap row updates through the SDK event alone', () {
    fakeAsync((async) {
      final wallet = _Wallet();
      final c = _container(wallet, _Settings());
      wallet.connect();
      async.flushMicrotasks();
      // Pending first (the claim starts): the SDK has not counted it yet.
      wallet.events.add(spark.SdkEvent.paymentPending(
          payment: _receive('rx', 5000, status: spark.PaymentStatus.pending)));
      async.flushMicrotasks();
      expect(_hero(c), 10000);
      wallet.receive(5000);
      async.flushMicrotasks();
      expect(_hero(c), 15000);
      expect(wallet.syncs, 0);
      expect(async.elapsed, Duration.zero);
      c.dispose();
      wallet.close();
      async.flushMicrotasks();
    });
  });

  test(
      'a transfer a sync recorded raises only synced: read at the event, '
      'once more after the burst', () {
    fakeAsync((async) {
      final wallet = _Wallet();
      final c = _container(wallet, _Settings());
      wallet.connect();
      async.flushMicrotasks();
      final before = wallet.reads;
      wallet.sats = 24000;
      wallet.events
        ..add(const spark.SdkEvent.synced())
        ..add(const spark.SdkEvent.synced());
      async.flushMicrotasks();
      expect(_hero(c), 24000);
      async.elapse(kSyncedRereadSettle);
      expect(wallet.reads, before + 2);
      c.dispose();
      wallet.close();
      async.flushMicrotasks();
    });
  });

  test('a claimed deposit updates the balance at once', () {
    fakeAsync((async) {
      final wallet = _Wallet();
      final c = _container(wallet, _Settings());
      wallet.connect();
      async.flushMicrotasks();
      wallet.sats = 60000;
      wallet.events.add(spark.SdkEvent.claimedDeposits(claimedDeposits: [
        spark.DepositInfo(
          txid: 'a' * 64,
          vout: 0,
          amountSats: BigInt.from(50000),
          isMature: true,
        ),
      ]));
      async.flushMicrotasks();
      expect(_hero(c), 60000);
      c.dispose();
      wallet.close();
      async.flushMicrotasks();
    });
  });

  test(
      'a read that started before the transfer landed never overwrites the '
      'one after it', () {
    fakeAsync((async) {
      final wallet = _Wallet();
      final c = _container(wallet, _Settings());
      wallet.connect();
      async.flushMicrotasks();
      // A pending event's read is slow to answer, with the old figure.
      final slow = Completer<void>();
      wallet.nextReadGate = slow;
      wallet.events.add(spark.SdkEvent.paymentPending(
          payment: _receive('rx', 5000, status: spark.PaymentStatus.pending)));
      async.flushMicrotasks();
      wallet.receive(5000);
      async.flushMicrotasks();
      expect(_hero(c), 15000);
      slow.complete();
      async.flushMicrotasks();
      expect(_hero(c), 15000, reason: 'the stale 10,000 is not published');
      c.dispose();
      wallet.close();
      async.flushMicrotasks();
    });
  });

  test(
      "a multi-source withdraw's legs each update it: the Orchestra row and "
      'the CCTP arrival', () {
    fakeAsync((async) {
      final wallet = _Wallet();
      final c = _container(wallet, _Settings());
      OwnSparkArrivals.refresh = (arrival) => wallet.wrapper
          .syncAndRefresh(asset: arrival.asset, since: arrival.since);
      wallet.connect();
      async.flushMicrotasks();
      final placed = DateTime.now().subtract(const Duration(seconds: 1));

      // Leg 1, Predictions through Orchestra: its sats reach the SDK's cache
      // without a payment event reaching the app (a sync recorded it), and
      // the status poll then marks the row done.
      final pending =
          _row('pm-leg', status: 'exchanging', createdAt: placed);
      wallet.sats = 19300;
      OwnSparkArrivals.rowsChanged(
          [pending], [_row('pm-leg', status: 'success', createdAt: placed)]);
      async.flushMicrotasks();
      expect(_hero(c), 19300);
      expect(wallet.syncs, 0, reason: 'the first read showed the rise');

      // Leg 2, Investing through Circle CCTP to the own-Spark standing
      // instruction, minutes later: its order is adopted already done
      // before its sats reach the SDK (the row's refresh measures from
      // the move's start, so leg 1's rise ends it), and the sats then
      // land through a sync with no payment event at all: the wrapper's
      // Synced read carries them.
      async.elapse(const Duration(minutes: 3));
      final cctp = _row('cctp-leg',
          status: 'success',
          from: 'USDC',
          fromNet: 'ARBITRUM',
          createdAt: placed);
      OwnSparkArrivals.rowsChanged(const [], [cctp]);
      async.flushMicrotasks();
      expect(_hero(c), 19300);
      wallet.sats = 28600;
      wallet.events.add(const spark.SdkEvent.synced());
      async.flushMicrotasks();
      expect(_hero(c), 28600);

      // A third leg the SDK delivers with its own event, no row at all.
      wallet.receive(1400, id: 'rx-3');
      async.flushMicrotasks();
      expect(_hero(c), 30000);
      expect(wallet.syncs, 0);
      c.dispose();
      wallet.close();
      async.flushMicrotasks();
    });
  });

  test(
      'no double counting: a pending row bound for Spark adds nothing, and '
      'its arrival refresh republishes the same figure', () {
    fakeAsync((async) {
      final wallet = _Wallet();
      final c = _container(wallet, _Settings());
      OwnSparkArrivals.refresh = (arrival) => wallet.wrapper
          .syncAndRefresh(asset: arrival.asset, since: arrival.since);
      wallet.connect();
      async.flushMicrotasks();
      final placed = DateTime.now().subtract(const Duration(seconds: 1));
      final pending =
          _row('leg', status: 'exchanging', createdAt: placed);
      OwnSparkArrivals.rowsChanged(const [], [pending]);
      async.flushMicrotasks();
      expect(_hero(c), 10000, reason: 'an in-flight row is not balance');

      // The SDK's event counts the transfer before Orchestra says done.
      wallet.receive(9300);
      async.flushMicrotasks();
      expect(_hero(c), 19300);

      OwnSparkArrivals.rowsChanged(
          [pending], [_row('leg', status: 'success', createdAt: placed)]);
      async.flushMicrotasks();
      expect(_hero(c), 19300, reason: 'counted once');
      expect(wallet.syncs, 0);
      expect(OwnSparkArrivals.awaitingCredit('leg'), isFalse);
      async.elapse(const Duration(minutes: 1));
      expect(_hero(c), 19300);
      c.dispose();
      wallet.close();
      async.flushMicrotasks();
    });
  });

  test('a send hold still caps the figure until the SDK shows the send', () {
    fakeAsync((async) {
      final wallet = _Wallet();
      final c = _container(wallet, _Settings());
      wallet.connect();
      async.flushMicrotasks();
      c.read(walletBalanceCacheProvider.notifier).holdOutgoingSparkSend(
          'spending',
          key: 'send',
          balanceBeforeSats: 10000,
          debitSats: 4000,
          feeSats: 10);
      expect(_hero(c), 6000);
      // A stale re-read of the pre-send figure keeps the hold.
      wallet.events.add(const spark.SdkEvent.synced());
      async.flushMicrotasks();
      expect(_hero(c), 6000);
      // The SDK shows the send: its own figure again.
      wallet.sats = 5995;
      wallet.events.add(const spark.SdkEvent.synced());
      async.elapse(kSyncedRereadSettle);
      expect(_hero(c), 5995);
      c.dispose();
      wallet.close();
      async.flushMicrotasks();
    });
  });
}
