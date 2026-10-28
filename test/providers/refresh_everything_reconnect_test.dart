// Pull-to-refresh refreshes the Bitcoin and Dollars balances as a hot
// restart does (refresh_everything_provider, `bitcoin` step).
//
// Founder report (October 2026): pulling down on the Bitcoin home did not
// update the Bitcoin balance; a hot restart did. `getInfo` only reads the
// SDK's cached account figure, which a wallet sync, a payment event or the
// SDK's start refreshes. The pull's one sync on the live handle joined the
// sync already outstanding (one native `syncWallet` per handle, held until
// the SDK answers), and the SDK's sync can return without refreshing the
// figure. A hot restart connects a new handle, whose start refreshes it.
// These pin the pull doing the same, without the unlock:
//   * a stale cached figure: the pull connects again and the new handle's
//     `getInfo` reaches the Bitcoin hero, while a young sync still runs;
//   * nothing blanks while it reconnects: the last figure stays until the
//     new one lands;
//   * a send in flight (running, listed as pending by the app or by the
//     SDK), a quote being created, a prepared send under review, a
//     settlement run or a settlement record before its funds are
//     confirmed: no reconnect, one sync instead;
//   * at most one reconnect per cooldown: pulling twice in a row
//     reconnects the first time and syncs the second;
//   * a connect that fails is tried again from the same request, never by
//     rebuilding the connection provider (that would unlock again);
//   * an old handle whose shutdown hangs or fails: the new handle never
//     connects beside it, the last figure stays, and the reconnect keeps
//     retrying until the shutdown is confirmed: never dead for good;
//   * a send hold whose send is no longer pending (in memory only, so a
//     restart drops it) never caps the figure through a pull;
//   * `pull_to_refresh_executed` carries `refresh_mode`.
// Fakes only: nothing is signed or sent.
import 'dart:async';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as spark;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/balance_model.dart';
import 'package:kute/models/breez/sdk_instance.dart';
import 'package:kute/models/breez/sdk_operation_guard.dart';
import 'package:kute/models/breez/shared_sync.dart';
import 'package:kute/models/evm_derivation_version.dart';
import 'package:kute/models/orchestra_routes_model.dart' show RouteKey;
import 'package:kute/models/settlement_operation.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/providers/refresh_everything_provider.dart';
import 'package:kute/providers/breez_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/services/sync/push_pipeline.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:kute/services/funding/settlement_stage.dart';
import 'package:kute/services/funding/settlement_store.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:hive_ce/hive.dart';
import 'dart:io';
import 'package:mocktail/mocktail.dart';

class _Sdk extends Mock implements spark.BreezSdk {}

class _Request extends Fake implements spark.ConnectRequest {}

class _BitcoinAddress extends Mock implements spark.BitcoinAddressDetails {}

Settings _settings() => Settings(
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: false,
      biometricsEnabled: false,
      bitcoinElectrumNode: 'x',
      nodeType: 'x',
      reviewDone: true,
      activeWalletId: 'spend',
      wallets: [
        WalletConfig(
          id: 'spend',
          name: 'Spending Wallet',
          sparkEnabled: true,
          evmDerivationVersion: EvmDerivationVersion.standardBip39,
        ),
      ],
    );

/// One native SDK handle whose cached figure the test sets.
class _Handle {
  _Handle(this.sats) {
    when(() => sdk.addEventListener()).thenAnswer((_) => events.stream);
    when(() => sdk.disconnect()).thenAnswer((_) async {
      disconnects++;
      await Future<void>.delayed(disconnectDelay);
    });
    when(() => sdk.getInfo(request: any(named: 'request'))).thenAnswer(
        (_) async {
      final gate = readGate;
      if (gate != null) await gate.future;
      return spark.GetInfoResponse(
          identityPubkey: 'id',
          balanceSats: BigInt.from(sats),
          tokenBalances: {});
    });
    when(() => sdk.listPayments(request: any(named: 'request'))).thenAnswer(
        (_) async => spark.ListPaymentsResponse(payments: payments));
    when(() => sdk.syncWallet(request: any(named: 'request')))
        .thenAnswer((_) {
      syncs++;
      return sync?.future ??
          Future.delayed(syncDelay, () => const spark.SyncWalletResponse());
    });
  }

  final sdk = _Sdk();
  final events = StreamController<spark.SdkEvent>.broadcast();

  /// The handle's cached balance: what `getInfo` answers.
  int sats;
  List<spark.Payment> payments = [];

  /// Holds every `getInfo` answer while set.
  Completer<void>? readGate;

  /// A native sync that has not answered (a dead connection), when set.
  Completer<spark.SyncWalletResponse>? sync;
  Duration syncDelay = Duration.zero;
  Duration disconnectDelay = Duration.zero;
  int syncs = 0;
  int disconnects = 0;
}

spark.Payment _lightningReceive(String id, int sats) => spark.Payment(
      id: id,
      paymentType: spark.PaymentType.receive,
      status: spark.PaymentStatus.completed,
      amount: BigInt.from(sats),
      fees: BigInt.zero,
      timestamp: BigInt.from(DateTime.now().millisecondsSinceEpoch ~/ 1000),
      method: spark.PaymentMethod.lightning,
    );

spark.Payment _pendingSend() => spark.Payment(
      id: 'out',
      paymentType: spark.PaymentType.send,
      status: spark.PaymentStatus.pending,
      amount: BigInt.from(1000),
      fees: BigInt.zero,
      timestamp: BigInt.from(DateTime.now().millisecondsSinceEpoch ~/ 1000),
      method: spark.PaymentMethod.spark,
    );

void main() {
  setUpAll(() {
    registerFallbackValue(const spark.GetInfoRequest());
    registerFallbackValue(const spark.ListPaymentsRequest());
    registerFallbackValue(const spark.SyncWalletRequest());
    registerFallbackValue(spark.PrepareSendPaymentRequest(
        paymentRequest: const spark.PaymentRequest.input(input: 'x')));
  });

  final events = <(String, Map<String, Object>?)>[];
  setUp(() {
    events.clear();
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    RefreshEverything.spinnerCap = const Duration(milliseconds: 200);
    RefreshEverything.stepLimit = const Duration(seconds: 30);
    // The cooldown has its own test; elsewhere a just-connected handle
    // may reconnect at once.
    BreezSdkSpark.pullReconnectCooldown = Duration.zero;
    debugResetSparkFlows();
  });
  tearDown(() {
    TrackingService.debugTrackObserver = null;
    RefreshEverything.spinnerCap = const Duration(seconds: 4);
    RefreshEverything.stepLimit = const Duration(seconds: 30);
    BreezSdkSpark.pullRetryDelays = const [
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 15),
      Duration(seconds: 30),
    ];
    BreezSdkSpark.reconnectSlowRetry = const Duration(seconds: 60);
    BreezSdkSpark.teardownTimeout = const Duration(seconds: 15);
    BreezSdkSpark.pullReconnectCooldown = const Duration(seconds: 25);
    BreezSdkSpark.connectTimeout = const Duration(seconds: 30);
    BreezSdkSpark.offlineSyncFailureWindow = const Duration(seconds: 30);
    BreezSdkSpark.teardownPendingRetryLimit = 5;
    debugResetSparkFlows();
  });

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  /// The spending wallet connected to the first of [handles] (each later
  /// connect takes the next; a null one fails to connect; a
  /// `Completer<spark.BreezSdk>` is a native connect that hangs until the
  /// test completes it), the Bitcoin hero followed, and only the real
  /// `bitcoin` step in the pull.
  Future<
      ({
        ProviderContainer c,
        BreezSdkSpark wrapper,
        List<int> hero,
        int Function() providerBuilds,
      })> setUpWallet(List<Object?> handles,
      {Duration connectDelay = Duration.zero,
      Duration syncWaitTimeout = const Duration(milliseconds: 300),
      Map<String, RefreshStep>? otherSteps,
      List<Override> overrides = const []}) async {
    final queue = [...handles];
    var firstConnect = true;
    final wrapper = BreezSdkSpark.forTesting(
      syncWaitTimeout: syncWaitTimeout,
      connectSdk: (_) async {
        if (!firstConnect) await Future<void>.delayed(connectDelay);
        firstConnect = false;
        final next = queue.removeAt(0);
        if (next == null) throw StateError('offline');
        if (next is Completer<spark.BreezSdk>) return next.future;
        return (next as _Handle).sdk;
      },
    );
    var builds = 0;
    final c = ProviderContainer(overrides: [
      settingsProvider.overrideWith((ref) => SettingsModel(_settings())),
      sessionUnlockedProvider.overrideWith((ref) => true),
      breezSDKProvider.overrideWith((ref) async {
        builds++;
        return wrapper;
      }),
      sparkWalletInfoFeedProvider.overrideWithValue(wrapper.walletInfoStream),
      refreshEverythingProvider.overrideWith((ref) =>
          RefreshEverything(ref, only: {'bitcoin'}, steps: otherSteps)),
      ...overrides,
    ]);
    addTearDown(() {
      wrapper.disconnect();
      c.dispose();
    });
    final hero = <int>[];
    c.listen<WalletBalance>(balanceNotifierProvider,
        (_, next) => hero.add(next.sparkBitcoinbalance),
        fireImmediately: true);
    // The request built again for a reconnect, as the provider does (the
    // seed read again, never kept).
    await wrapper.connect(
        req: _Request(),
        walletId: 'spend',
        reconnectRequest: () async => _Request());
    await c.read(breezSDKProvider.future);
    await flush();
    // From here on: every figure the hero shows.
    hero.clear();
    return (c: c, wrapper: wrapper, hero: hero, providerBuilds: () => builds);
  }

  int shown(ProviderContainer c) =>
      c.read(balanceNotifierProvider).sparkBitcoinbalance;

  Map<String, Object>? pullEvent() =>
      events.singleWhere((e) => e.$1 == 'pull_to_refresh_executed').$2;

  /// One pull, waited for to the end of its run (the pull joins it).
  Future<void> pull(ProviderContainer c) async {
    final refresh = c.read(refreshEverythingProvider);
    final running = refresh.run();
    await refresh(RefreshTrigger.home);
    await running;
  }

  test(
      'a stale cached figure: the pull connects again and the new '
      "handle's getInfo reaches the Bitcoin hero, as a hot restart does",
      () async {
    final first = _Handle(10000), second = _Handle(25000);
    final w = await setUpWallet([first, second]);
    expect(shown(w.c), 10000);

    // 15 000 sats landed. The live handle's cache never shows them: its
    // sync is outstanding (a dead connection after a network change) and
    // every read answers the cached 10 000.
    first.sync = Completer<spark.SyncWalletResponse>();
    final stuck = sharedSyncWallet(first.sdk);
    expect(sharedSyncInFlight(first.sdk), isTrue);

    await pull(w.c);

    expect(shown(w.c), 25000,
        reason: "the new handle's start reads the true figure");
    expect(w.wrapper.instance, same(second.sdk));
    expect(first.disconnects, 1);
    expect(second.syncs, greaterThanOrEqualTo(1),
        reason: 'one sync on the new handle, read again when it answers');
    expect(w.providerBuilds(), 1,
        reason: 'the connection provider is not rebuilt: no unlock');
    expect(pullEvent(), {'screen': 'home', 'refresh_mode': 'reconnect'});
    first.sync!.complete(const spark.SyncWalletResponse());
    await stuck;
  });

  test(
      'nothing blanks while it reconnects: the last figure stays until the '
      'new one lands', () async {
    final first = _Handle(10000), second = _Handle(25000)
      ..readGate = Completer<void>();
    final w = await setUpWallet([first, second]);
    final refresh = w.c.read(refreshEverythingProvider);
    final running = refresh.run();
    final pulling = refresh(RefreshTrigger.home);
    for (var i = 0;
        i < 50 && !identical(w.wrapper.instance, second.sdk);
        i++) {
      await flush();
    }
    expect(w.wrapper.instance, same(second.sdk));
    expect(shown(w.c), 10000,
        reason: 'reconnected, no reading yet: the last figure stays');
    second.readGate!.complete();
    await pulling;
    await running;
    expect(shown(w.c), 25000);
    expect(w.hero, [25000],
        reason: 'from 10 000 straight to 25 000: never 0 or anything else '
            'in between');
  });

  test('a send running on the handle: no reconnect, one sync instead',
      () async {
    final first = _Handle(10000), second = _Handle(25000);
    final w = await setUpWallet([first, second]);
    final sending = Completer<void>();
    final send = runSparkMutation(first.sdk, () => sending.future);

    await pull(w.c);

    expect(first.disconnects, 0);
    expect(w.wrapper.instance, same(first.sdk));
    expect(first.syncs, 1, reason: 'the sync-only refresh');
    expect(pullEvent(), {'screen': 'home', 'refresh_mode': 'sync'});
    sending.complete();
    await send;
  });

  test(
      'a send the app holds as pending (the payments stream, or an accepted '
      'send hold): no reconnect', () async {
    final first = _Handle(10000), second = _Handle(25000);
    final w = await setUpWallet([first, second]);
    w.c
        .read(walletBalanceCacheProvider.notifier)
        .setPendingOutgoingSparkSend('spend', true);

    await pull(w.c);

    expect(first.disconnects, 0);
    expect(w.wrapper.instance, same(first.sdk));
    expect(pullEvent()?['refresh_mode'], 'sync');
  });

  test(
      'a send only the SDK lists as pending: the reconnect is refused at the '
      'last check and the pull syncs', () async {
    final first = _Handle(10000)..payments = [_pendingSend()];
    final second = _Handle(25000);
    final w = await setUpWallet([first, second]);

    await pull(w.c);

    expect(first.disconnects, 0);
    expect(w.wrapper.instance, same(first.sdk));
    expect(first.syncs, 1);
    final recovery =
        events.singleWhere((e) => e.$1 == 'usd_token_recovery').$2;
    expect(recovery, containsPair('source', 'pull'));
    expect(recovery, containsPair('reason', 'pending_send'));
  });

  test(
      'a quote being created: no reconnect; the sync-only pull leaves the '
      'stale figure (what the old pull did)', () async {
    final first = _Handle(10000), second = _Handle(25000);
    final w = await setUpWallet([first, second]);
    final quoting = Completer<void>();
    final quote = runSparkQuote(() => quoting.future);

    await pull(w.c);

    expect(first.disconnects, 0);
    expect(w.wrapper.instance, same(first.sdk));
    expect(shown(w.c), 10000,
        reason: "the live handle's cache is all a sync-only pull can read");
    expect(pullEvent()?['refresh_mode'], 'sync');
    quoting.complete();
    await quote;
  });

  test(
      'a connect that fails is tried again from the same request, never '
      'by rebuilding the connection provider', () async {
    BreezSdkSpark.pullRetryDelays = const [Duration(milliseconds: 20)];
    final first = _Handle(10000), second = _Handle(25000);
    final w = await setUpWallet([first, null, second]);
    var lifecycle = 0;
    final sub = w.wrapper.recoveryStream.listen((_) => lifecycle++);
    addTearDown(sub.cancel);

    await pull(w.c);

    expect(first.disconnects, 1);
    expect(w.wrapper.instance, isNull, reason: 'offline: no handle yet');
    expect(lifecycle, 0,
        reason: 'no recovery event: the provider would unlock again');
    expect(shown(w.c), 10000, reason: 'the last figure stays meanwhile');

    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(w.wrapper.instance, same(second.sdk));
    expect(shown(w.c), 25000);
    expect(w.providerBuilds(), 1);
  });

  group('send holds on a pull', () {
    late DateTime now;
    late WalletBalanceCacheNotifier cache;
    setUp(() {
      now = DateTime(2026, 10, 19, 12);
      cache = WalletBalanceCacheNotifier(clock: () => now);
      cache.updateSparkBitcoinbalance('spend', 10000,
          source: BalanceSource.stream);
      // A 3 000 sat send the SDK's figure never shows (its release never
      // came: the payment row never matched the hold).
      cache.holdOutgoingSparkSend('spend',
          key: 'out', balanceBeforeSats: 10000, debitSats: 3000, feeSats: 0);
    });
    tearDown(() => cache.dispose());

    int shownSats() => cache.state['spend']!.sparkBitcoinbalance;

    test('a hold past the grace whose send is not pending ends on a pull',
        () {
      expect(shownSats(), 7000);
      now = now.add(const Duration(seconds: 31));
      cache.releaseSettledSendHolds('spend');
      expect(shownSats(), 10000, reason: "the SDK's own figure, as a restart");
    });

    test('a send still pending, or one just accepted, keeps its hold', () {
      cache.releaseSettledSendHolds('spend');
      expect(shownSats(), 7000, reason: 'just accepted');
      cache.setPendingOutgoingSparkSend('spend', true);
      now = now.add(const Duration(minutes: 2));
      cache.releaseSettledSendHolds('spend');
      expect(shownSats(), 7000, reason: 'the SDK lists it as pending');
      expect(cache.hasOutgoingSparkSendInFlight('spend'), isTrue);
    });
  });

  group('an old handle whose shutdown hangs or fails', () {
    test(
        'the new handle never connects beside it; the reconnect retries with '
        'backoff and connects once the shutdown is confirmed', () async {
      BreezSdkSpark.teardownTimeout = const Duration(milliseconds: 30);
      BreezSdkSpark.pullRetryDelays = const [Duration(milliseconds: 20)];
      BreezSdkSpark.reconnectSlowRetry = const Duration(milliseconds: 40);
      final first = _Handle(10000), second = _Handle(25000);
      final shutdown = Completer<void>();
      when(() => first.sdk.disconnect()).thenAnswer((_) => shutdown.future);
      final w = await setUpWallet([first, second]);
      var lifecycle = 0;
      final sub = w.wrapper.recoveryStream.listen((_) => lifecycle++);
      addTearDown(sub.cancel);

      await pull(w.c);

      expect(w.wrapper.instance, isNull, reason: 'the old one is not down');
      expect(w.wrapper.teardownPending, isTrue);
      expect(shown(w.c), 10000, reason: 'the last figure stays meanwhile');
      expect(lifecycle, 0, reason: 'no provider rebuild (no unlock)');
      final teardowns = [
        for (final e in events)
          if (e.$1 == 'spark_sdk_teardown') e.$2
      ];
      expect(teardowns.first, containsPair('result', 'timeout'));
      expect(teardowns.first, containsPair('attempt', 1));

      // The backoff, then the slow retry: still hanging, still no second
      // handle (the queue's next handle is never taken).
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(w.wrapper.instance, isNull);
      expect(
          events.where((e) =>
              e.$1 == 'spark_sdk_teardown' && e.$2?['result'] == 'timeout'),
          hasLength(greaterThan(1)),
          reason: 'it keeps trying');
      verify(() => first.sdk.disconnect()).called(1);

      // The old runtime finally stops: the next retry connects.
      shutdown.complete();
      for (var i = 0; i < 50 && w.wrapper.instance == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(w.wrapper.instance, same(second.sdk));
      expect(w.wrapper.teardownPending, isFalse);
      for (var i = 0; i < 20 && shown(w.c) != 25000; i++) {
        await flush();
      }
      expect(shown(w.c), 25000);
      expect(w.providerBuilds(), 1);
      expect(
          events.where((e) =>
              e.$1 == 'spark_sdk_teardown' &&
              e.$2?['result'] == 'confirmed_late'),
          hasLength(1));
    });

    test('a shutdown that failed is asked again, and the retry connects',
        () async {
      BreezSdkSpark.pullRetryDelays = const [Duration(milliseconds: 20)];
      final first = _Handle(10000), second = _Handle(25000);
      var calls = 0;
      when(() => first.sdk.disconnect()).thenAnswer((_) async {
        if (++calls == 1) throw StateError('bridge failure');
      });
      final w = await setUpWallet([first, second]);

      await pull(w.c);
      expect(w.wrapper.instance, isNull);
      expect(
          events.firstWhere((e) => e.$1 == 'spark_sdk_teardown').$2,
          containsPair('result', 'error'));

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(calls, 2, reason: 'asked again, answered at once');
      expect(w.wrapper.instance, same(second.sdk));
    });

    test('an app resume or network change tries at once', () async {
      BreezSdkSpark.teardownTimeout = const Duration(milliseconds: 30);
      BreezSdkSpark.pullRetryDelays = const [Duration(minutes: 5)];
      final first = _Handle(10000), second = _Handle(25000);
      final shutdown = Completer<void>();
      when(() => first.sdk.disconnect()).thenAnswer((_) => shutdown.future);
      final w = await setUpWallet([first, second]);
      await pull(w.c);
      expect(w.wrapper.instance, isNull);
      shutdown.complete();
      await flush();
      expect(await w.wrapper.reconnectIfDown(), isTrue);
      expect(w.wrapper.instance, same(second.sdk));
    });
  });

  test(
      'the cooldown: pulling twice in a row reconnects the first time and '
      'syncs the second', () async {
    BreezSdkSpark.pullReconnectCooldown = const Duration(milliseconds: 300);
    final first = _Handle(10000), second = _Handle(25000);
    final third = _Handle(30000);
    final w = await setUpWallet([first, second, third]);

    // Just connected: as fresh as a restart.
    await pull(w.c);
    expect(pullEvent()?['refresh_mode'], 'sync');
    expect(w.wrapper.instance, same(first.sdk));
    events.clear();

    await Future<void>.delayed(const Duration(milliseconds: 350));
    await pull(w.c);
    expect(pullEvent()?['refresh_mode'], 'reconnect');
    expect(w.wrapper.instance, same(second.sdk));
    expect(shown(w.c), 25000);
    events.clear();

    await pull(w.c);
    expect(pullEvent()?['refresh_mode'], 'sync',
        reason: 'the second pull in a row');
    expect(w.wrapper.instance, same(second.sdk));
    events.clear();

    await Future<void>.delayed(const Duration(milliseconds: 350));
    await pull(w.c);
    expect(pullEvent()?['refresh_mode'], 'reconnect');
    expect(w.wrapper.instance, same(third.sdk));
  });

  group('a money flow between its steps: no reconnect, one sync', () {
    Future<void> expectSyncOnly(_Handle first, ProviderContainer c,
        BreezSdkSpark wrapper) async {
      await pull(c);
      expect(first.disconnects, 0);
      expect(wrapper.instance, same(first.sdk));
      expect(pullEvent()?['refresh_mode'], 'sync');
    }

    test('a prepared send held for review (a confirm screen or slip)',
        () async {
      final first = _Handle(10000), second = _Handle(25000);
      final w = await setUpWallet([first, second]);
      final hold = holdSparkFlow();
      await expectSyncOnly(first, w.c, w.wrapper);
      hold.release();
      events.clear();
      await pull(w.c);
      expect(pullEvent()?['refresh_mode'], 'reconnect',
          reason: 'released: the review ended');
    });

    test(
        'a settlement run or a send tap (quote, review, prepare, biometric '
        'prompt, broadcast)', () async {
      final first = _Handle(10000), second = _Handle(25000);
      final w = await setUpWallet([first, second]);
      final reviewing = Completer<void>();
      final flow = runSparkFlow(() => reviewing.future);
      await expectSyncOnly(first, w.c, w.wrapper);
      reviewing.complete();
      await flow;
    });

    test(
        'a settlement record before its funds are confirmed (a quote '
        'waiting for its confirm tap), until it ends or ages out', () async {
      final temporary =
          await Directory.systemTemp.createTemp('pull-settlement');
      Hive.init(temporary.path);
      addTearDown(() async {
        await Hive.deleteFromDisk();
        await temporary.delete(recursive: true);
      });
      final store = SettlementStore(
        box: await Hive.openBox<String>('operations'),
        quarantine: await Hive.openBox<String>('quarantine'),
      );
      final now = DateTime.now();
      final op = await store.create(SettlementOperation(
        operationId: 'op-1',
        walletId: 'spend',
        accountKind: SettlementAccountKind.sparkHot,
        flow: SettlementFlow.predictionsDeposit,
        routeVersion: 'v1',
        route: RouteKey(
            fromChain: 'spark',
            fromAsset: 'BTC',
            toChain: 'polygon',
            toAsset: 'USDC.e'),
        amountInBaseUnits: '1000',
        recipient: const SettlementAddressRef(
            address: '0xrecipient',
            kind: OwnedAddressKind.polymarketDepositWallet),
        refund: const SettlementAddressRef(
            address: 'spark1self', kind: OwnedAddressKind.sparkSelf),
        stage: SettlementStage.created,
        createdAt: now,
        updatedAt: now,
      ));
      expect(sparkMoneyFlowInFlight, isTrue);
      final first = _Handle(10000), second = _Handle(25000);
      final w = await setUpWallet([first, second]);
      await expectSyncOnly(first, w.c, w.wrapper);

      // Abandoned: no longer between steps.
      await store.transition(op.operationId, SettlementStage.abandoned,
          from: SettlementStage.created);
      expect(sparkMoneyFlowInFlight, isFalse);

      // A record left behind ages out.
      final later = await store.create(SettlementOperation(
        operationId: 'op-2',
        walletId: 'spend',
        accountKind: SettlementAccountKind.sparkHot,
        flow: SettlementFlow.predictionsDeposit,
        routeVersion: 'v1',
        route: op.route,
        amountInBaseUnits: '1000',
        recipient: op.recipient,
        refund: op.refund,
        stage: SettlementStage.created,
        createdAt: now,
        updatedAt: now,
      ));
      expect(later.stage, SettlementStage.created);
      expect(sparkMoneyFlowInFlight, isTrue);
      sparkFlowClock = () => DateTime.now().add(const Duration(minutes: 11));
      expect(sparkMoneyFlowInFlight, isFalse);
    });

    test(
        'a prepare provider holds its prepared send while a screen keeps '
        'it, and lets go when the screen does', () async {
      final sdk = _Sdk();
      when(() => sdk.parse(input: any(named: 'input'))).thenAnswer(
          (_) async => spark.InputType.bitcoinAddress(_BitcoinAddress()));
      when(() => sdk.prepareSendPayment(request: any(named: 'request')))
          .thenAnswer((_) async => spark.PrepareSendPaymentResponse(
                paymentMethod: spark.SendPaymentMethod.sparkAddress(
                    address: 'spark1dest', fee: BigInt.zero),
                amount: BigInt.from(1000),
                feePolicy: spark.FeePolicy.feesExcluded,
              ));
      final h = _Handle(10000);
      final wrapper = BreezSdkSpark.forTesting(connectSdk: (_) async => sdk);
      when(() => sdk.addEventListener()).thenAnswer((_) => h.events.stream);
      when(() => sdk.disconnect()).thenAnswer((_) async {});
      when(() => sdk.getInfo(request: any(named: 'request'))).thenAnswer(
          (_) async => spark.GetInfoResponse(
              identityPubkey: 'id',
              balanceSats: BigInt.from(10000),
              tokenBalances: {}));
      when(() => sdk.listPayments(request: any(named: 'request'))).thenAnswer(
          (_) async => const spark.ListPaymentsResponse(payments: []));
      await wrapper.connect(req: _Request(), walletId: 'spend', reconnectRequest: () async => _Request());
      addTearDown(wrapper.disconnect);
      final c = ProviderContainer(overrides: [
        settingsProvider.overrideWith((ref) => SettingsModel(_settings())),
        breezSDKProvider.overrideWith((ref) async => wrapper),
      ]);
      addTearDown(c.dispose);
      final params = (
        destination: 'spark1dest',
        amountSats: 1000,
        isDraining: false,
      );
      final screen = c.listen(prepareGenericPaymentProvider(params), (_, __) {});
      await c.read(prepareGenericPaymentProvider(params).future);
      expect(sparkMoneyFlowInFlight, isTrue, reason: 'under review');
      screen.close();
      await flush();
      await flush();
      expect(sparkMoneyFlowInFlight, isFalse, reason: 'the screen let go');
    });
  });

  group('speed: the spinner never waits on the reconnect or the sync', () {
    // A slow day: the native connect takes 300 ms, the old handle's
    // shutdown 100 ms, a wallet sync 1.5 s; every other part of the pull
    // (region, history sync, Predictions, Investing, Portfolio) 800 ms.
    Future<({int spinnerMs, int runMs, int lastStartMs, int shownAtSpinner})>
        measure({required bool reconnect}) async {
      final first = _Handle(10000)
        ..syncDelay = const Duration(milliseconds: 1500)
        ..disconnectDelay = const Duration(milliseconds: 100);
      final second = _Handle(25000)
        ..syncDelay = const Duration(milliseconds: 1500);
      final clock = Stopwatch();
      final starts = <String, int>{};
      RefreshStep other(String name) => () async {
            starts[name] = clock.elapsedMilliseconds;
            await Future<void>.delayed(const Duration(milliseconds: 800));
          };
      final w = await setUpWallet([first, second],
          connectDelay: const Duration(milliseconds: 300),
          syncWaitTimeout: const Duration(seconds: 3),
          otherSteps: {
            for (final n in [
              'region',
              'sync',
              'predictions',
              'investing',
              'portfolio'
            ])
              n: other(n),
          });
      // The production cap.
      RefreshEverything.spinnerCap = const Duration(seconds: 4);
      final hold = reconnect ? null : holdSparkFlow();
      final refresh = w.c.read(refreshEverythingProvider);
      clock.start();
      await refresh(RefreshTrigger.home);
      final spinnerMs = clock.elapsedMilliseconds;
      final shownAtSpinner = shown(w.c);
      await refresh.run();
      final runMs = clock.elapsedMilliseconds;
      hold?.release();
      expect(pullEvent()?['refresh_mode'], reconnect ? 'reconnect' : 'sync');
      expect(starts.keys, hasLength(5));
      events.clear();
      return (
        spinnerMs: spinnerMs,
        runMs: runMs,
        lastStartMs: starts.values.reduce((a, b) => a > b ? a : b),
        shownAtSpinner: shownAtSpinner,
      );
    }

    test(
        'reconnect: the spinner ends at the new handle\'s first read, every '
        'other part started at once', () async {
      final m = await measure(reconnect: true);
      // Before (1598333) the spinner waited for the whole run, capped at
      // 4 s: the reconnect, then the sync on the new handle.
      final before = m.runMs < 4000 ? m.runMs : 4000;
      debugPrint('[pull-speed] reconnect: spinner ${m.spinnerMs} ms '
          '(before: $before ms), run ${m.runMs} ms, '
          'last part started at ${m.lastStartMs} ms');
      expect(m.lastStartMs, lessThan(50),
          reason: 'nothing waits on the reconnect: all in parallel');
      expect(m.spinnerMs, lessThan(800));
      expect(before, greaterThanOrEqualTo(1900));
      expect(m.shownAtSpinner, 25000,
          reason: "the read that ends the spinner is already on screen");
    });

    test('sync: the spinner ends at the live handle\'s first read', () async {
      final m = await measure(reconnect: false);
      final before = m.runMs < 4000 ? m.runMs : 4000;
      debugPrint('[pull-speed] sync: spinner ${m.spinnerMs} ms '
          '(before: $before ms), run ${m.runMs} ms, '
          'last part started at ${m.lastStartMs} ms');
      expect(m.lastStartMs, lessThan(50));
      expect(m.spinnerMs, lessThan(200));
      expect(before, greaterThanOrEqualTo(1500));
    });
  });

  group('the reconnect path hardened', () {
    List<Map<String, Object>> recoveries({String? source}) => [
          for (final e in events)
            if (e.$1 == 'usd_token_recovery' &&
                (source == null || e.$2?['source'] == source))
              e.$2!
        ];

    test(
        'a native connect that hangs: the pull gives up after the timeout '
        'and retries; the handle the hung call produces later is shut down, '
        'never adopted, and no handle connects beside it meanwhile',
        () async {
      BreezSdkSpark.connectTimeout = const Duration(milliseconds: 40);
      BreezSdkSpark.teardownTimeout = const Duration(milliseconds: 20);
      BreezSdkSpark.pullRetryDelays = const [Duration(milliseconds: 10)];
      BreezSdkSpark.reconnectSlowRetry = const Duration(milliseconds: 10);
      BreezSdkSpark.teardownPendingRetryLimit = 1000;
      final first = _Handle(10000), late = _Handle(99999);
      final second = _Handle(25000);
      final hung = Completer<spark.BreezSdk>();
      final w = await setUpWallet([first, hung, second]);

      await pull(w.c);

      expect(first.disconnects, 1);
      expect(w.wrapper.instance, isNull);
      expect(w.wrapper.isConnecting, isFalse,
          reason: 'released: nothing waits on the hung call for good');
      expect(w.wrapper.teardownPending, isTrue,
          reason: 'the hung connect is a handle not confirmed down');
      expect(recoveries(source: 'pull').single,
          containsPair('reason', 'connect_failed'));
      expect(shown(w.c), 10000, reason: 'the last figure stays meanwhile');

      // The retries wait on the hung call: no second handle beside it.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(w.wrapper.instance, isNull);
      verifyNever(() => second.sdk.addEventListener());
      expect(recoveries(source: 'retry'), isNotEmpty);
      expect(recoveries(source: 'retry').last,
          containsPair('reason', 'teardown_failed'));

      // The hung call answers at last: its handle is shut down the moment
      // it exists and never adopted; the next retry connects.
      hung.complete(late.sdk);
      for (var i = 0;
          i < 50 && !identical(w.wrapper.instance, second.sdk);
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(late.disconnects, 1);
      verifyNever(() => late.sdk.addEventListener());
      expect(w.wrapper.instance, same(second.sdk));
      expect(w.wrapper.teardownPending, isFalse);
      for (var i = 0; i < 20 && shown(w.c) != 25000; i++) {
        await flush();
      }
      expect(shown(w.c), 25000);
      expect(w.providerBuilds(), 1);
    });

    test(
        'offline (a wallet sync on the live handle failed just now): the '
        'pull syncs and never retires the working cached handle; a resume '
        'or network change lets the next pull reconnect', () async {
      BreezSdkSpark.offlineSyncFailureWindow =
          const Duration(milliseconds: 300);
      final first = _Handle(10000), second = _Handle(25000);
      final w = await setUpWallet([first, second]);
      when(() => first.sdk.syncWallet(request: any(named: 'request')))
          .thenAnswer((_) async {
        first.syncs++;
        throw StateError('offline');
      });
      // A background sync failed: the network is down.
      await w.wrapper.syncAndReread();
      expect(w.wrapper.recentlyOffline, isTrue);
      expect(w.wrapper.canReconnectForPull, isFalse);

      await pull(w.c);

      expect(first.disconnects, 0);
      expect(w.wrapper.instance, same(first.sdk));
      expect(pullEvent()?['refresh_mode'], 'sync');
      expect(shown(w.c), 10000);
      events.clear();

      // The network back: the signal clears the mark, the pull reconnects.
      when(() => first.sdk.syncWallet(request: any(named: 'request')))
          .thenAnswer((_) async => const spark.SyncWalletResponse());
      expect(await w.wrapper.reconnectIfDown(), isFalse,
          reason: 'a handle is there: nothing to connect');
      expect(w.wrapper.recentlyOffline, isFalse);
      await pull(w.c);
      expect(pullEvent()?['refresh_mode'], 'reconnect');
      expect(w.wrapper.instance, same(second.sdk));
      expect(shown(w.c), 25000);
    });

    test('the offline mark lapses on its own after the window', () async {
      BreezSdkSpark.offlineSyncFailureWindow =
          const Duration(milliseconds: 60);
      final first = _Handle(10000), second = _Handle(25000);
      final w = await setUpWallet([first, second]);
      when(() => first.sdk.syncWallet(request: any(named: 'request')))
          .thenAnswer((_) async => throw StateError('offline'));
      await w.wrapper.syncAndReread();
      expect(w.wrapper.recentlyOffline, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(w.wrapper.recentlyOffline, isFalse);
      expect(w.wrapper.canReconnectForPull, isTrue);
    });

    test(
        'an old handle whose shutdown never answers: after five tries in a '
        'row the retry timer stops; a resume or network change asks again',
        () async {
      BreezSdkSpark.teardownTimeout = const Duration(milliseconds: 10);
      BreezSdkSpark.pullRetryDelays = const [Duration(milliseconds: 10)];
      BreezSdkSpark.reconnectSlowRetry = const Duration(milliseconds: 10);
      final first = _Handle(10000), second = _Handle(25000);
      final never = Completer<void>();
      when(() => first.sdk.disconnect()).thenAnswer((_) => never.future);
      final w = await setUpWallet([first, second]);

      await pull(w.c);
      expect(w.wrapper.instance, isNull);
      expect(recoveries(source: 'pull').single,
          containsPair('reason', 'teardown_failed'));

      await Future<void>.delayed(const Duration(milliseconds: 300));
      final retries = recoveries(source: 'retry');
      expect(retries, hasLength(4),
          reason: 'the pull and four retries: five in a row, then it stops');
      expect(retries.every((r) => r['reason'] == 'teardown_failed'), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(recoveries(source: 'retry'), hasLength(4),
          reason: 'stopped: nothing to wait on but the same hung shutdown');
      expect(w.wrapper.instance, isNull);
      verifyNever(() => second.sdk.addEventListener());

      // A resume or network change: asked again, retries starting over.
      expect(await w.wrapper.reconnectIfDown(), isFalse);
      expect(recoveries(source: 'resume').single,
          containsPair('reason', 'teardown_failed'));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(recoveries(source: 'retry'), hasLength(greaterThan(4)));
      expect(w.providerBuilds(), 1);
    });

    test(
        'the race: a send that starts while the pull reads the pending list '
        'runs (never "The wallet is reconnecting"), and the pull defers',
        () async {
      final first = _Handle(10000), second = _Handle(25000);
      final w = await setUpWallet([first, second]);
      final checking = Completer<spark.ListPaymentsResponse>();
      when(() => first.sdk.listPayments(request: any(named: 'request')))
          .thenAnswer((_) => checking.future);
      final refresh = w.c.read(refreshEverythingProvider);
      final running = refresh.run();
      final pulling = refresh(RefreshTrigger.home);
      await flush();
      expect(pullEvent()?['refresh_mode'], 'reconnect');

      final sending = Completer<void>();
      var sent = false;
      final send = runSparkMutation(first.sdk, () async {
        sent = true;
        await sending.future;
      });
      await flush();
      expect(sent, isTrue, reason: 'nothing is reserved during the check');

      checking.complete(const spark.ListPaymentsResponse(payments: []));
      when(() => first.sdk.listPayments(request: any(named: 'request')))
          .thenAnswer(
              (_) async => const spark.ListPaymentsResponse(payments: []));
      for (var i = 0; i < 10; i++) {
        await flush();
      }
      sending.complete();
      await send;
      await pulling;
      await running;

      expect(first.disconnects, 0);
      expect(w.wrapper.instance, same(first.sdk));
      expect(recoveries(source: 'pull').single,
          containsPair('reason', 'mutation_in_flight'));
      expect(first.syncs, greaterThanOrEqualTo(1), reason: 'synced instead');
    });

    test(
        'locked: no retry and no resume reconnect; the unlock connects again',
        () async {
      BreezSdkSpark.pullRetryDelays = const [Duration(milliseconds: 30)];
      var unlocked = true;
      final first = _Handle(10000), second = _Handle(25000);
      final w = await setUpWallet([first, null, second]);
      w.wrapper.sessionUnlocked = () => unlocked;

      await pull(w.c);
      expect(w.wrapper.instance, isNull);
      // The lock engages before the retry fires.
      unlocked = false;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(w.wrapper.instance, isNull, reason: 'nothing behind the lock');
      verifyNever(() => second.sdk.addEventListener());
      expect(await w.wrapper.reconnectIfDown(), isFalse);
      expect(w.wrapper.instance, isNull);
      expect(recoveries(source: 'retry'), isEmpty);
      expect(recoveries(source: 'resume'), isEmpty);

      // What completeUnlock asks once the session is unlocked.
      unlocked = true;
      expect(await w.wrapper.reconnectIfDown(), isTrue);
      expect(w.wrapper.instance, same(second.sdk));
      expect(recoveries(source: 'resume').single,
          containsPair('reason', 'reconnected'));
      expect(w.providerBuilds(), 1);
    });

    test(
        'a stale send hold (past the grace, no pending send) is released '
        'before the mode is decided: the same pull reconnects', () async {
      var now = DateTime(2026, 10, 19, 12);
      final first = _Handle(10000), second = _Handle(25000);
      final w = await setUpWallet([first, second], overrides: [
        walletBalanceCacheProvider.overrideWith(
            (ref) => WalletBalanceCacheNotifier(clock: () => now)),
      ]);
      final cache = w.c.read(walletBalanceCacheProvider.notifier);
      cache.updateSparkBitcoinbalance('spend', 10000,
          source: BalanceSource.stream);
      cache.holdOutgoingSparkSend('spend',
          key: 'out', balanceBeforeSats: 10000, debitSats: 3000, feeSats: 0);
      expect(cache.hasOutgoingSparkSendInFlight('spend'), isTrue);
      now = now.add(const Duration(seconds: 31));

      await pull(w.c);

      expect(pullEvent()?['refresh_mode'], 'reconnect');
      expect(w.wrapper.instance, same(second.sdk));
      expect(cache.hasOutgoingSparkSendInFlight('spend'), isFalse);
    });
  });

  group('an incoming Lightning payment around the reconnect', () {
    Future<PushPipeline> activity(ProviderContainer c) async {
      c.read(walletTransactionCacheProvider.notifier).setForWallet(
          'spend',
          Transaction(
              bitcoinTransactions: [],
              sparkTransactions: [],
              sparkUnclaimedDeposits: []));
      final pipeline = PushPipeline(onSyncRequested: () {});
      addTearDown(pipeline.stop);
      pipeline.start(c);
      for (var i = 0; i < 20; i++) {
        await flush();
      }
      return pipeline;
    }

    List<String> rows(ProviderContainer c) => [
          for (final tx in c
                  .read(walletTransactionCacheProvider)['spend']
                  ?.sparkTransactions ??
              const <SparkTransaction>[])
            tx.id
        ];

    test(
        'one that arrived while the old handle was going down, and one the '
        'new handle claims on start: both land in Activity and the balance '
        'at once', () async {
      final first = _Handle(10000);
      final second = _Handle(10000);
      final shutdown = Completer<void>();
      when(() => first.sdk.disconnect()).thenAnswer((_) => shutdown.future);
      final w = await setUpWallet([first, second]);
      await activity(w.c);
      expect(rows(w.c), isEmpty);

      final refresh = w.c.read(refreshEverythingProvider);
      final running = refresh.run();
      final pulling = refresh(RefreshTrigger.home);
      await flush();
      // 2 100 sats arrive while the old handle shuts down: it never
      // reports them; the operators hold them for the wallet.
      second
        ..sats = 12100
        ..payments = [_lightningReceive('ln-1', 2100)];
      shutdown.complete();
      for (var i = 0; i < 50 && w.wrapper.instance == null; i++) {
        await flush();
      }
      expect(w.wrapper.instance, same(second.sdk));
      // The new handle's start claims another one and says so at once.
      second
        ..sats = 13100
        ..payments = [
          _lightningReceive('ln-1', 2100),
          _lightningReceive('ln-2', 1000)
        ];
      second.events.add(spark.SdkEvent.paymentSucceeded(
          payment: _lightningReceive('ln-2', 1000)));
      await pulling;
      await running;
      for (var i = 0; i < 20; i++) {
        await flush();
      }
      expect(rows(w.c), containsAll(['ln-1', 'ln-2']),
          reason: 'in Activity with no backoff in between');
      expect(shown(w.c), 13100);
    });

    test(
        'a connect that fails and retries never leaves Activity unbound: '
        'the new handle is followed the moment it connects', () async {
      BreezSdkSpark.pullRetryDelays = const [Duration(milliseconds: 20)];
      final first = _Handle(10000);
      final second = _Handle(12100)
        ..payments = [_lightningReceive('ln-1', 2100)];
      final w = await setUpWallet([first, null, second]);
      await activity(w.c);

      final clock = Stopwatch()..start();
      await pull(w.c);
      expect(w.wrapper.instance, isNull);
      for (var i = 0; i < 40 && !rows(w.c).contains('ln-1'); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(rows(w.c), contains('ln-1'));
      expect(clock.elapsedMilliseconds, lessThan(400),
          reason: 'not the pipeline\'s 1 to 32 s backoff');
      expect(shown(w.c), 12100);
      // And it follows the new handle's events from then on.
      second
        ..payments = [
          _lightningReceive('ln-1', 2100),
          _lightningReceive('ln-2', 500)
        ]
        ..sats = 12600;
      second.events.add(spark.SdkEvent.paymentSucceeded(
          payment: _lightningReceive('ln-2', 500)));
      for (var i = 0; i < 20; i++) {
        await flush();
      }
      expect(rows(w.c), contains('ln-2'));
      expect(shown(w.c), 12600);
    });
  });
}
