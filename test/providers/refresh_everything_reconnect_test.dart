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
//     SDK) or a quote being created: no reconnect, one sync instead;
//   * a connect that fails is tried again from the same request, never by
//     rebuilding the connection provider (that would unlock again);
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
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/providers/refresh_everything_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:mocktail/mocktail.dart';

class _Sdk extends Mock implements spark.BreezSdk {}

class _Request extends Fake implements spark.ConnectRequest {}

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
    when(() => sdk.disconnect()).thenAnswer((_) async => disconnects++);
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
      return sync?.future ?? Future.value(const spark.SyncWalletResponse());
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
  int syncs = 0;
  int disconnects = 0;
}

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
  });

  final events = <(String, Map<String, Object>?)>[];
  setUp(() {
    events.clear();
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    RefreshEverything.spinnerCap = const Duration(milliseconds: 200);
    RefreshEverything.stepLimit = const Duration(seconds: 30);
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
  });

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  /// The spending wallet connected to the first of [handles] (each later
  /// connect takes the next; a null one fails to connect), the Bitcoin
  /// hero followed, and only the real `bitcoin` step in the pull.
  Future<
      ({
        ProviderContainer c,
        BreezSdkSpark wrapper,
        List<int> hero,
        int Function() providerBuilds,
      })> setUpWallet(List<_Handle?> handles) async {
    final queue = [...handles];
    final wrapper = BreezSdkSpark.forTesting(
      syncWaitTimeout: const Duration(milliseconds: 300),
      connectSdk: (_) async {
        final next = queue.removeAt(0);
        if (next == null) throw StateError('offline');
        return next.sdk;
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
      refreshEverythingProvider
          .overrideWith((ref) => RefreshEverything(ref, only: {'bitcoin'})),
    ]);
    addTearDown(() {
      wrapper.disconnect();
      c.dispose();
    });
    final hero = <int>[];
    c.listen<WalletBalance>(balanceNotifierProvider,
        (_, next) => hero.add(next.sparkBitcoinbalance),
        fireImmediately: true);
    await wrapper.connect(req: _Request(), walletId: 'spend');
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
}
