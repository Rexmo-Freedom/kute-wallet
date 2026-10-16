// The Dollars balance reads the SDK's `tokenBalances`. An answer with no
// dollar entry means the SDK's token store has not caught up (its Spark
// sync kept failing), not that the account is empty: the settled ledger
// decides until it does. A dollar entry, even a zero one, always wins.
// Only the dollar token ever counts as dollars.

import 'dart:async';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/breez/sdk_instance.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/auth_provider.dart' show sessionUnlockedProvider;
import 'package:kute/providers/refresh_everything_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/providers/usd_account_provider.dart';
import 'package:kute/providers/usdb_provider.dart';
import 'package:kute/services/kute_haptics.dart';

const _otherToken = 'btkn1othertoken';

breez.TokenMetadata _meta(String identifier, String ticker) =>
    breez.TokenMetadata(
      identifier: identifier,
      issuerPublicKey: 'issuer',
      name: ticker,
      ticker: ticker,
      decimals: 6,
      maxSupply: BigInt.zero,
      isFreezable: false,
    );

breez.GetInfoResponse _info(Map<String, (String ticker, int units)> tokens) =>
    breez.GetInfoResponse(
      identityPubkey: 'id',
      balanceSats: BigInt.zero,
      tokenBalances: {
        for (final e in tokens.entries)
          e.key: breez.TokenBalance(
            balance: BigInt.from(e.value.$2),
            tokenMetadata: _meta(e.key, e.value.$1),
          ),
      },
    );

breez.Payment _tokenPayment(
  String id, {
  required int units,
  String identifier = usdbTokenIdentifier,
  String ticker = 'USDB',
  breez.PaymentType type = breez.PaymentType.receive,
  breez.PaymentStatus status = breez.PaymentStatus.completed,
  int timestampSeconds = 1700000000,
}) =>
    breez.Payment(
      id: id,
      paymentType: type,
      status: status,
      amount: BigInt.from(units),
      fees: BigInt.zero,
      timestamp: BigInt.from(timestampSeconds),
      method: breez.PaymentMethod.token,
      details: breez.PaymentDetails.token(
        metadata: _meta(identifier, ticker),
        txHash: 'tx-$id',
        txType: breez.TokenTransactionType.transfer,
      ),
    );

UsdbTokenTransaction _row(breez.Payment p) => UsdbTokenTransaction(
      id: p.id,
      timestamp:
          DateTime.fromMillisecondsSinceEpoch(p.timestamp.toInt() * 1000),
      details: p,
      isConfirmed: p.status == breez.PaymentStatus.completed,
    );

class _Cache extends WalletTransactionCacheNotifier {
  _Cache(Map<String, Transaction> seed) {
    state = seed;
  }

  void setLedger(List<breez.Payment> ledger) => state = {
        'spending': Transaction(
          bitcoinTransactions: const [],
          sparkTransactions: const [],
          sparkUnclaimedDeposits: const [],
          usdbTokenTransactions: [for (final p in ledger) _row(p)],
        ),
      };
}

class _Sdk extends Mock implements breez.BreezSdk {}

class _Wrapper extends Mock implements BreezSdkSpark {}

class _Request extends Fake implements breez.ConnectRequest {}

class _Checks extends UsdBalanceCheck {
  final requests = <String>[];

  @override
  void request(String source) => requests.add(source);
}

ProviderContainer _container({
  required double? sdkReading,
  List<breez.Payment> ledger = const [],
}) {
  final settings = Settings(
    currency: 'USD',
    language: 'en',
    btcFormat: 'sats',
    backup: false,
    biometricsEnabled: false,
    bitcoinElectrumNode: '',
    nodeType: 'Blockstream',
    reviewDone: true,
    activeWalletId: 'spending',
    wallets: [WalletConfig(id: 'spending', name: 'Spending')],
  );
  final container = ProviderContainer(overrides: [
    settingsProvider.overrideWith((_) => SettingsModel(settings)),
    usdSdkBalanceProvider.overrideWith((_) => Stream.value(sdkReading)),
    walletTransactionCacheProvider.overrideWith((_) => _Cache({
          'spending': Transaction(
            bitcoinTransactions: const [],
            sparkTransactions: const [],
            sparkUnclaimedDeposits: const [],
            usdbTokenTransactions: [for (final p in ledger) _row(p)],
          ),
        })),
  ]);
  addTearDown(container.dispose);
  return container;
}

Future<double> _balance(ProviderContainer container) async {
  container.listen(usdBalanceProvider, (_, __) {});
  await container.read(usdSdkBalanceProvider.future);
  return container.read(usdBalanceProvider);
}

void main() {
  test('an old SDK read cannot overwrite a replacement stream reading',
      () async {
    final first = _Sdk(), second = _Sdk();
    final wrapper = _Wrapper();
    breez.BreezSdk current = first;
    final delayed = Completer<breez.GetInfoResponse>();
    final readings = StreamController<breez.GetInfoResponse>.broadcast();
    when(() => wrapper.instance).thenAnswer((_) => current);
    when(() => wrapper.walletInfoStream).thenAnswer((_) => readings.stream);
    when(() => first.getInfo(request: const breez.GetInfoRequest()))
        .thenAnswer((_) => delayed.future);
    final container = ProviderContainer(overrides: [
      breezSDKProvider.overrideWith((_) async => wrapper),
      usdSettledTransfersProvider.overrideWithValue([]),
    ]);
    container.listen(usdSdkBalanceProvider, (_, __) {});
    await pumpEventQueue();
    current = second;
    readings.add(_info({usdbTokenIdentifier: ('USDB', 15000000)}));
    await pumpEventQueue();
    expect(container.read(usdSdkBalanceProvider).valueOrNull, 15);
    delayed.complete(_info({usdbTokenIdentifier: ('USDB', 0)}));
    await pumpEventQueue();
    expect(container.read(usdSdkBalanceProvider).valueOrNull, 15);
    container.dispose();
    await readings.close();
  });

  group('usdDollarsFromNodeInfo', () {
    test('a dollar entry reads as dollars at its decimals', () {
      expect(
          usdDollarsFromNodeInfo(
              _info({usdbTokenIdentifier: ('USDB', 12340000)})),
          12.34);
    });

    test('a zero dollar entry is a real zero', () {
      expect(
          usdDollarsFromNodeInfo(_info({usdbTokenIdentifier: ('USDB', 0)})), 0);
    });

    test('no dollar entry is no answer, not zero', () {
      expect(usdDollarsFromNodeInfo(_info({})), isNull);
      expect(usdDollarsFromNodeInfo(_info({_otherToken: ('ABC', 5000000)})),
          isNull);
    });
  });

  group('usdBalanceProvider', () {
    test('an SDK answer with no dollar entry falls back to the settled ledger',
        () async {
      final container = _container(sdkReading: null, ledger: [
        _tokenPayment('in', units: 20000000),
        _tokenPayment('out', units: 5000000, type: breez.PaymentType.send),
        // Pending money has not arrived yet.
        _tokenPayment('pending',
            units: 9000000, status: breez.PaymentStatus.pending),
      ]);
      expect(await _balance(container), 15);
    });

    test('a dollar entry from the SDK wins over the ledger, zero included',
        () async {
      final container = _container(
          sdkReading: 0, ledger: [_tokenPayment('in', units: 20000000)]);
      expect(await _balance(container), 0);
    });

    test('another token never counts as dollars', () async {
      final container = _container(sdkReading: null, ledger: [
        _tokenPayment('usd', units: 3000000),
        _tokenPayment('abc',
            units: 50000000, identifier: _otherToken, ticker: 'ABC'),
      ]);
      expect(await _balance(container), 3);
    });
  });

  group('isUsdbTokenPayment', () {
    test('matches the dollar token by identifier or ticker', () {
      expect(isUsdbTokenPayment(_tokenPayment('a', units: 1)), isTrue);
      expect(
          isUsdbTokenPayment(_tokenPayment('b',
              units: 1, identifier: 'btkn1reissued', ticker: 'usdb')),
          isTrue);
    });

    test('refuses another token and a bitcoin payment', () {
      expect(
          isUsdbTokenPayment(_tokenPayment('c',
              units: 1, identifier: _otherToken, ticker: 'ABC')),
          isFalse);
      expect(
          isUsdbTokenPayment(breez.Payment(
            id: 'sats',
            paymentType: breez.PaymentType.receive,
            status: breez.PaymentStatus.completed,
            amount: BigInt.one,
            fees: BigInt.zero,
            timestamp: BigInt.zero,
            method: breez.PaymentMethod.spark,
          )),
          isFalse);
    });
  });

  group('UsdLedgerCatchUp', () {
    late List<breez.GetInfoResponse> answers;
    late int reads;
    late int syncs;
    late List<double?> published;
    late UsdLedgerCatchUp catchUp;

    setUp(() {
      reads = 0;
      syncs = 0;
      published = [];
      catchUp = UsdLedgerCatchUp(
        readInfo: (_) async {
          final i = reads < answers.length ? reads : answers.length - 1;
          reads++;
          return answers[i];
        },
        syncWallet: () async => syncs++,
        publish: (reading, _) => published.add(reading),
        debounce: Duration.zero,
      );
      addTearDown(catchUp.dispose);
    });

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 20));

    test('the first ledger is only a baseline', () async {
      answers = [
        _info({usdbTokenIdentifier: ('USDB', 5000000)})
      ];
      catchUp.recordReading(5);
      catchUp.onLedger('a');
      await settle();
      expect(reads, 0);
      expect(published, isEmpty);
    });

    test('a settled receive the SDK already counted is read without a sync',
        () async {
      answers = [
        _info({usdbTokenIdentifier: ('USDB', 15000000)})
      ];
      catchUp.recordReading(5);
      catchUp.onLedger('a');
      catchUp.onLedger('a,b');
      await settle();
      expect(published, [15]);
      expect(syncs, 0);
    });

    test('a stale cached figure forces a sync, then the fresh one shows',
        () async {
      answers = [
        _info({usdbTokenIdentifier: ('USDB', 5000000)}),
        _info({usdbTokenIdentifier: ('USDB', 15000000)}),
      ];
      catchUp.recordReading(5);
      catchUp.onLedger('a');
      catchUp.onLedger('a,b');
      await settle();
      expect(syncs, 1);
      expect(published.last, 15);
    });

    test('a first receive with no dollar entry yet also forces a sync',
        () async {
      answers = [
        _info({}),
        _info({usdbTokenIdentifier: ('USDB', 10000000)}),
      ];
      catchUp.recordReading(null);
      catchUp.onLedger('');
      catchUp.onLedger('a');
      await settle();
      expect(syncs, 1);
      expect(published.last, 10);
    });

    test('a failed sync still publishes what the cache holds', () async {
      final failing = UsdLedgerCatchUp(
        readInfo: (_) async => _info({usdbTokenIdentifier: ('USDB', 5000000)}),
        syncWallet: () => Future<void>.error(TimeoutException('offline')),
        publish: (reading, _) => published.add(reading),
        debounce: Duration.zero,
      );
      addTearDown(failing.dispose);
      failing.recordReading(5);
      failing.onLedger('a');
      failing.onLedger('a,b');
      await settle();
      expect(published, [5]);
    });

    test('nothing runs after dispose', () async {
      answers = [
        _info({usdbTokenIdentifier: ('USDB', 15000000)})
      ];
      catchUp.onLedger('a');
      catchUp.onLedger('a,b');
      catchUp.dispose();
      await settle();
      expect(reads, 0);
      expect(published, isEmpty);
    });
  });

  group('an existing dollar entry that never catches up', () {
    test(
        'historical ledger hydration retries but never reconnects a numeric balance',
        () {
      fakeAsync((async) {
        var syncs = 0, recoveries = 0;
        final c = UsdLedgerCatchUp(
          readInfo: (_) async =>
              _info({usdbTokenIdentifier: ('USDB', 15000000)}),
          syncWallet: () async {
            syncs++;
          },
          recoverTokenStore: (_) async {
            recoveries++;
            return true;
          },
          publish: (_, __) {},
          debounce: Duration.zero,
          retryDelays: const [Duration(seconds: 1)],
        );
        c.recordReading(15);
        c.onLedger('recent', holdsDollars: true, settledDollars: 5);
        c.onLedger('recent,old',
            holdsDollars: true, settledDollars: 15, recoveryEligible: false);
        async.elapse(const Duration(minutes: 5));
        expect(syncs, 2);
        expect(recoveries, 0);
        expect(c.retryPending, isFalse);
        c.dispose();
      });
    });

    test(
        'SDK stream before ledger already proves arrival; no sync or reconnect',
        () {
      fakeAsync((async) {
        var syncs = 0, recoveries = 0;
        final c = UsdLedgerCatchUp(
          readInfo: (_) async =>
              _info({usdbTokenIdentifier: ('USDB', 15000000)}),
          syncWallet: () async {
            syncs++;
          },
          recoverTokenStore: (_) async {
            recoveries++;
            return true;
          },
          publish: (_, __) {},
          debounce: Duration.zero,
        );
        c.recordReading(5);
        c.onLedger('old', holdsDollars: true, settledDollars: 5);
        c.recordReading(15); // SDK event wins the race against listPayments.
        c.onLedger('old,arrival',
            holdsDollars: true, settledDollars: 15, recoveryEligible: true);
        async.elapse(const Duration(minutes: 5));
        expect(syncs, 0);
        expect(recoveries, 0);
        expect(c.retryPending, isFalse);
        c.dispose();
      });
    });

    test('stale zero keeps retrying after a failed sync, until the entry moves',
        () {
      fakeAsync((async) {
        var units = 0;
        var syncs = 0;
        final readings = <double?>[];
        final c = UsdLedgerCatchUp(
          readInfo: (_) async => _info({usdbTokenIdentifier: ('USDB', units)}),
          syncWallet: () async {
            syncs++;
            throw StateError('leaf refresh failed');
          },
          publish: (value, _) => readings.add(value),
          debounce: Duration.zero,
          retryDelays: const [Duration(seconds: 1), Duration(seconds: 2)],
        );
        c.recordReading(0);
        c.onLedger('old', holdsDollars: true);
        c.onLedger('old,arrival', holdsDollars: true);
        async.elapse(Duration.zero);
        async.flushMicrotasks();
        expect(syncs, 1);
        expect(c.retryPending, isTrue,
            reason: 'an existing zero entry can be stale');
        async.elapse(const Duration(seconds: 1));
        expect(syncs, 2);
        units = 10740000;
        async.elapse(const Duration(seconds: 2));
        expect(readings.last, 10.74);
        expect(c.retryPending, isFalse);
        c.dispose();
      });
    });

    test('unchanged numeric stream readings cannot cancel a pending arrival',
        () {
      fakeAsync((async) {
        final c = UsdLedgerCatchUp(
          readInfo: (_) async =>
              _info({usdbTokenIdentifier: ('USDB', 4000000)}),
          syncWallet: () async {},
          publish: (_, __) {},
          debounce: Duration.zero,
        );
        c.recordReading(4);
        c.onLedger('old', holdsDollars: true);
        c.onLedger('old,arrival', holdsDollars: true);
        async.elapse(Duration.zero);
        async.flushMicrotasks();
        c.recordReading(4);
        expect(c.retryPending, isTrue);
        c.recordReading(14);
        expect(c.retryPending, isFalse);
        c.dispose();
      });
    });

    test('one guarded reconnect per ledger change; busy recovery is retried',
        () {
      fakeAsync((async) {
        var attempts = 0;
        final c = UsdLedgerCatchUp(
          readInfo: (_) async => _info({usdbTokenIdentifier: ('USDB', 0)}),
          syncWallet: () async {},
          recoverTokenStore: (_) async => ++attempts > 1,
          publish: (_, __) {},
          debounce: Duration.zero,
          retryDelays: const [Duration(seconds: 1), Duration(seconds: 2)],
        );
        c.recordReading(0);
        c.onLedger('old', holdsDollars: true, settledDollars: 0);
        c.onLedger('old,arrival',
            holdsDollars: true, settledDollars: 10, recoveryEligible: true);
        async.elapse(Duration.zero);
        async.flushMicrotasks();
        expect(attempts, 1);
        async.elapse(const Duration(seconds: 1));
        expect(attempts, 2);
        async.elapse(const Duration(minutes: 1));
        expect(attempts, 2, reason: 'successful recovery is never looped');
        c.dispose();
      });
    });
  });

  test('a failed native recovery re-enters the provider connection lifecycle',
      () async {
    KuteHaptics.debugForeground = () => false;
    addTearDown(KuteHaptics.debugReset);
    final first = _Sdk(), second = _Sdk();
    for (final sdk in [first, second]) {
      when(() => sdk.addEventListener())
          .thenAnswer((_) => const Stream.empty());
      when(() => sdk.disconnect()).thenAnswer((_) async {});
      when(() => sdk.listPayments(request: const breez.ListPaymentsRequest()))
          .thenAnswer(
              (_) async => const breez.ListPaymentsResponse(payments: []));
    }
    when(() => first.getInfo(request: const breez.GetInfoRequest()))
        .thenAnswer((_) async => _info({usdbTokenIdentifier: ('USDB', 0)}));
    when(() => first.syncWallet(request: const breez.SyncWalletRequest()))
        .thenThrow(StateError('Bitcoin leaf refresh failed'));
    when(() => second.getInfo(request: const breez.GetInfoRequest()))
        .thenAnswer(
            (_) async => _info({usdbTokenIdentifier: ('USDB', 12000000)}));
    var nativeConnects = 0;
    final wrapper = BreezSdkSpark.forTesting(connectSdk: (_) async {
      if (++nativeConnects > 1) throw StateError('network offline');
      return first;
    });
    await wrapper.connect(req: _Request());
    final replacement = _Wrapper();
    when(() => replacement.instance).thenReturn(second);
    when(() => replacement.walletInfoStream)
        .thenAnswer((_) => const Stream.empty());
    when(() => replacement.recoveryStream)
        .thenAnswer((_) => const Stream.empty());
    final cache = _Cache({});
    cache.setLedger([]);
    var providerBuilds = 0;
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith((_) => SettingsModel(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: 'Blockstream',
            reviewDone: true,
            activeWalletId: 'spending',
            wallets: [WalletConfig(id: 'spending', name: 'Spending')],
          ))),
      breezSDKProvider.overrideWith((ref) async {
        final current = ++providerBuilds == 1 ? wrapper : replacement;
        bindSparkRecoveryLifecycle(ref, current);
        return current;
      }),
      walletTransactionCacheProvider.overrideWith((_) => cache),
    ]);
    container.listen(usdBalanceProvider, (_, __) {});
    await container.read(usdSdkBalanceProvider.future);
    expect(container.read(usdBalanceProvider), 0);
    cache.setLedger([
      _tokenPayment('arrival',
          units: 12000000,
          timestampSeconds: DateTime.now().millisecondsSinceEpoch ~/ 1000)
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    expect(nativeConnects, 2);
    expect(wrapper.instance, isNull);
    expect(providerBuilds, 2, reason: 'disconnected wrapper was invalidated');
    expect(container.read(usdBalanceProvider), 12);
    container.dispose();
  });

  // The device log behind these (hot restarts on iOS): a session's first
  // `getInfo` had no dollar entry (`tokens=0`) while the wallet held
  // dollars, and the figure arrived only ~20 s later, when the catch-up's
  // sync timed out and it read again. The SDK writes its cached row in
  // the sync's WalletState step, long before the sync answers or raises
  // Synced, so the row is read every second while the sync runs.
  group('a token map that is behind', () {
    late breez.GetInfoResponse info;
    late List<(double?, String)> published;
    late int syncs;

    UsdLedgerCatchUp catchUp({
      required Future<void> Function() sync,
      List<Duration> retryDelays = kUsdCatchUpRetryDelays,
    }) {
      final c = UsdLedgerCatchUp(
        readInfo: (_) async => info,
        syncWallet: () {
          syncs++;
          return sync();
        },
        publish: (reading, source) => published.add((reading, source)),
        debounce: Duration.zero,
        retryDelays: retryDelays,
      );
      addTearDown(c.dispose);
      return c;
    }

    setUp(() {
      info = _info({});
      published = [];
      syncs = 0;
    });

    test(
        'no dollar entry at first, still none while the sync runs: the poll '
        'publishes the figure the moment the row has it, before the sync '
        'answers', () {
      fakeAsync((async) {
        final syncDone = Completer<void>();
        final c = catchUp(sync: () => syncDone.future);
        c.onLedger('a', holdsDollars: true);
        c.check('seed');
        async.flushMicrotasks();
        expect(published, [(null, 'seed')], reason: 'the seed: unknown');
        expect(syncs, 1);

        async.elapse(const Duration(seconds: 3));
        expect(published, hasLength(1), reason: 'still behind, still polling');

        // The sync's WalletState step writes the row.
        info = _info({usdbTokenIdentifier: ('USDB', 12000000)});
        async.elapse(const Duration(seconds: 1));
        expect(published.last, (12.0, 'seed-poll'));
        expect(syncDone.isCompleted, isFalse);
        expect(c.retryPending, isFalse);
        syncDone.complete();
        async.flushMicrotasks();
      });
    });

    test(
        'still no entry after the sync answers: tried again on the backoff, '
        'and the figure publishes when a retry finds it', () {
      fakeAsync((async) {
        final c = catchUp(sync: () async {});
        c.onLedger('a', holdsDollars: true);
        c.check('seed');
        async.flushMicrotasks();
        expect(syncs, 1);
        expect(published.last, (null, 'seed-sync'));
        expect(c.retryPending, isTrue);

        async.elapse(kUsdCatchUpRetryDelays[0]);
        expect(syncs, 2, reason: 'the first retry syncs again');
        expect(c.retryPending, isTrue);

        info = _info({usdbTokenIdentifier: ('USDB', 7000000)});
        async.elapse(kUsdCatchUpRetryDelays[1]);
        expect(published.last, (7.0, 'retry'));
        expect(syncs, 2, reason: 'an entry needs no sync');
        expect(c.retryPending, isFalse);
      });
    });

    test(
        'the retries are bounded, and a new trigger (resume, a pull) starts '
        'them again', () {
      fakeAsync((async) {
        final c = catchUp(
            sync: () async {},
            retryDelays: const [Duration(seconds: 1), Duration(seconds: 2)]);
        c.onLedger('a', holdsDollars: true);
        c.check('seed');
        async.elapse(const Duration(minutes: 5));
        expect(syncs, 3, reason: 'the seed and two retries, then it stops');
        expect(c.retryPending, isFalse);

        c.check('resume');
        async.flushMicrotasks();
        expect(syncs, 4);
        expect(c.retryPending, isTrue);
      });
    });

    test('a feed reading with the entry (a Synced re-read) ends the retries',
        () {
      fakeAsync((async) {
        final c = catchUp(sync: () async {});
        c.onLedger('a', holdsDollars: true);
        c.check('seed');
        async.flushMicrotasks();
        expect(c.retryPending, isTrue);
        c.recordReading(12);
        expect(c.retryPending, isFalse);
        async.elapse(const Duration(minutes: 5));
        expect(syncs, 1);
      });
    });

    test('no entry while the ledger holds no dollars is a known zero: no sync',
        () {
      fakeAsync((async) {
        final c = catchUp(sync: () async {});
        c.onLedger('', holdsDollars: false);
        c.check('seed');
        async.elapse(const Duration(minutes: 5));
        expect(published, [(null, 'seed')]);
        expect(syncs, 0);
        expect(c.retryPending, isFalse);
      });
    });

    test('overlapping triggers share one run, then one more', () {
      fakeAsync((async) {
        final syncDone = Completer<void>();
        final c = catchUp(sync: () => syncDone.future);
        c.onLedger('a', holdsDollars: true);
        c.check('seed');
        c.check('resume');
        c.check('refresh');
        async.flushMicrotasks();
        expect(syncs, 1);
        info = _info({usdbTokenIdentifier: ('USDB', 3000000)});
        async.elapse(const Duration(seconds: 1));
        expect(published.last, (3.0, 'seed-poll'));
        // The queued check reads once; the figure is unchanged and there,
        // so it neither publishes nor syncs.
        expect(published, hasLength(2));
        expect(syncs, 1);
        syncDone.complete();
        async.flushMicrotasks();
      });
    });
  });

  group('usdBalanceUnknownProvider', () {
    test('no SDK entry while the settled ledger holds dollars: unknown',
        () async {
      final container = _container(
          sdkReading: null, ledger: [_tokenPayment('in', units: 12000000)]);
      await container.read(usdSdkBalanceProvider.future);
      expect(container.read(usdBalanceUnknownProvider), isTrue);
      expect(container.read(usdBalanceProvider), 12,
          reason: 'the ledger figure, shown dimmed');
    });

    test('an SDK entry, zero included, is known', () async {
      final container = _container(
          sdkReading: 0, ledger: [_tokenPayment('in', units: 12000000)]);
      await container.read(usdSdkBalanceProvider.future);
      expect(container.read(usdBalanceUnknownProvider), isFalse);
    });

    test('no SDK entry and no dollars in the ledger agree: a known zero',
        () async {
      final container = _container(sdkReading: null, ledger: [
        _tokenPayment('in', units: 5000000),
        _tokenPayment('out', units: 5000000, type: breez.PaymentType.send),
      ]);
      await container.read(usdSdkBalanceProvider.future);
      expect(container.read(usdBalanceUnknownProvider), isFalse);
    });
  });

  test(
      'a session whose first getInfo has no dollar entry: unknown at once, '
      'and the SDK figure lands from the poll while the sync still runs', () {
    fakeAsync((async) {
      registerFallbackValue(const breez.SyncWalletRequest());
      registerFallbackValue(const breez.GetInfoRequest());
      final sdk = _Sdk();
      final wrapper = _Wrapper();
      var tokens = <String, (String, int)>{};
      var syncs = 0;
      when(() => wrapper.instance).thenReturn(sdk);
      when(() => wrapper.walletInfoStream)
          .thenAnswer((_) => const Stream.empty());
      when(() => sdk.getInfo(request: any(named: 'request')))
          .thenAnswer((_) async => _info(tokens));
      // A sync that has not answered yet (its deposits step is slow).
      when(() => sdk.syncWallet(request: any(named: 'request')))
          .thenAnswer((_) {
        syncs++;
        return Completer<breez.SyncWalletResponse>().future;
      });
      final cache = _Cache({});
      cache.setLedger([_tokenPayment('a', units: 12000000)]);
      final container = ProviderContainer(overrides: [
        settingsProvider.overrideWith((_) => SettingsModel(Settings(
              currency: 'USD',
              language: 'en',
              btcFormat: 'sats',
              backup: false,
              biometricsEnabled: false,
              bitcoinElectrumNode: '',
              nodeType: 'Blockstream',
              reviewDone: true,
              activeWalletId: 'spending',
              wallets: [WalletConfig(id: 'spending', name: 'Spending')],
            ))),
        breezSDKProvider.overrideWith((_) async => wrapper),
        walletTransactionCacheProvider.overrideWith((_) => cache),
      ]);
      addTearDown(container.dispose);
      container.listen(usdBalanceProvider, (_, __) {});
      container.listen(usdBalanceUnknownProvider, (_, __) {});
      async.flushMicrotasks();
      expect(container.read(usdBalanceUnknownProvider), isTrue);
      expect(container.read(usdBalanceProvider), 12);
      expect(syncs, 1);

      // The sync's WalletState step writes the row: $15 by the SDK.
      tokens = {usdbTokenIdentifier: ('USDB', 15000000)};
      async.elapse(const Duration(seconds: 1));
      expect(container.read(usdBalanceUnknownProvider), isFalse);
      expect(container.read(usdBalanceProvider), 15);
      expect(syncs, 1);
    });
  });

  test(
      'pull-to-refresh asks the Dollars reading to check itself beside the '
      'shared sync', () async {
    final sdk = _Sdk();
    final wrapper = _Wrapper();
    when(() => wrapper.instance).thenReturn(sdk);
    when(() => wrapper.syncAndReread()).thenAnswer((_) async {});
    final checks = _Checks();
    final container = ProviderContainer(overrides: [
      sessionUnlockedProvider.overrideWith((_) => true),
      breezSDKProvider.overrideWith((_) async => wrapper),
      usdBalanceCheckProvider.overrideWithValue(checks),
    ]);
    addTearDown(container.dispose);
    await container.read(breezSDKProvider.future);
    await container.read(refreshEverythingProvider).steps['bitcoin']!();
    expect(checks.requests, ['refresh']);
    verify(() => wrapper.syncAndReread()).called(1);
  });

  test('a check with no live Dollars reading is a no-op', () {
    expect(() => UsdBalanceCheck().request('resume'), returnsNormally);
  });

  test('usdLedgerSignature ignores order', () {
    final a = _row(_tokenPayment('a', units: 1));
    final b = _row(_tokenPayment('b', units: 1));
    expect(usdLedgerSignature([a, b]), usdLedgerSignature([b, a]));
  });

  test(
      'a settled dollar receive with no SDK event reaches the balance '
      'within seconds', () async {
    registerFallbackValue(const breez.SyncWalletRequest());
    registerFallbackValue(const breez.GetInfoRequest());
    final sdk = _Sdk();
    final wrapper = _Wrapper();
    var units = 5000000;
    var syncs = 0;
    when(() => wrapper.instance).thenReturn(sdk);
    // Neither feed ever fires: the case the ledger catch-up exists for.
    when(() => wrapper.walletInfoStream)
        .thenAnswer((_) => const Stream.empty());
    when(() => wrapper.syncedStream).thenAnswer((_) => const Stream.empty());
    when(() => sdk.getInfo(request: any(named: 'request')))
        .thenAnswer((_) async => _info({usdbTokenIdentifier: ('USDB', units)}));
    when(() => sdk.syncWallet(request: any(named: 'request')))
        .thenAnswer((_) async {
      syncs++;
      units = 15000000; // the sync refreshes the token outputs
      return const breez.SyncWalletResponse();
    });
    final cache = _Cache({});
    cache.setLedger([_tokenPayment('a', units: 5000000)]);
    final settings = Settings(
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: false,
      biometricsEnabled: false,
      bitcoinElectrumNode: '',
      nodeType: 'Blockstream',
      reviewDone: true,
      activeWalletId: 'spending',
      wallets: [WalletConfig(id: 'spending', name: 'Spending')],
    );
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith((_) => SettingsModel(settings)),
      breezSDKProvider.overrideWith((_) async => wrapper),
      walletTransactionCacheProvider.overrideWith((_) => cache),
    ]);
    addTearDown(container.dispose);
    container.listen(usdBalanceProvider, (_, __) {});
    await container.read(usdSdkBalanceProvider.future);
    expect(container.read(usdBalanceProvider), 5);

    // Activity polls listPayments and gains the settled receive.
    cache.setLedger([
      _tokenPayment('a', units: 5000000),
      _tokenPayment('b', units: 10000000),
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    expect(syncs, 1);
    expect(container.read(usdBalanceProvider), 15);
  });

  test('a 100% dollar move reads the cached balance and never waits for a sync',
      () async {
    registerFallbackValue(const breez.SyncWalletRequest());
    registerFallbackValue(const breez.GetInfoRequest());
    final sdk = _Sdk();
    when(() => sdk.getInfo(request: any(named: 'request'))).thenAnswer(
        (_) async => _info({usdbTokenIdentifier: ('USDB', 7250000)}));
    // A sync that never answers (a step that keeps failing).
    when(() => sdk.syncWallet(request: any(named: 'request')))
        .thenAnswer((_) => Completer<breez.SyncWalletResponse>().future);
    expect(await usdDrainBaseUnits(sdk), BigInt.from(7250000));
    verifyNever(() => sdk.syncWallet(request: any(named: 'request')));
  });

  test(
      'a dollar transfer that arrives through a sync shows at the Synced '
      'event: the SDK wrapper publishes it, two reads per burst', () {
    fakeAsync((async) {
      registerFallbackValue(const breez.GetInfoRequest());
      registerFallbackValue(const breez.ListPaymentsRequest());
      final sdk = _Sdk();
      final events = StreamController<breez.SdkEvent>.broadcast();
      addTearDown(events.close);
      var units = 5000000;
      var reads = 0;
      when(() => sdk.addEventListener()).thenAnswer((_) => events.stream);
      when(() => sdk.disconnect()).thenAnswer((_) async {});
      when(() => sdk.listPayments(request: any(named: 'request'))).thenAnswer(
          (_) async => const breez.ListPaymentsResponse(payments: []));
      when(() => sdk.getInfo(request: any(named: 'request')))
          .thenAnswer((_) async {
        reads++;
        return _info({usdbTokenIdentifier: ('USDB', units)});
      });
      final wrapper = BreezSdkSpark.forTesting(connectSdk: (_) async => sdk);
      wrapper.connect(req: _Request());
      async.flushMicrotasks();
      final settings = Settings(
        currency: 'USD',
        language: 'en',
        btcFormat: 'sats',
        backup: false,
        biometricsEnabled: false,
        bitcoinElectrumNode: '',
        nodeType: 'Blockstream',
        reviewDone: true,
        activeWalletId: 'spending',
        wallets: [WalletConfig(id: 'spending', name: 'Spending')],
      );
      final container = ProviderContainer(overrides: [
        settingsProvider.overrideWith((_) => SettingsModel(settings)),
        breezSDKProvider.overrideWith((_) async => wrapper),
        walletTransactionCacheProvider.overrideWith((_) => _Cache({})),
      ]);
      addTearDown(container.dispose);
      container.listen(usdBalanceProvider, (_, __) {});
      async.flushMicrotasks();
      expect(container.read(usdBalanceProvider), 5);
      final seeded = reads;

      // The sync wrote the new token balance, then raised Synced.
      units = 15000000;
      events.add(const breez.SdkEvent.synced());
      async.flushMicrotasks();
      expect(container.read(usdBalanceProvider), 15,
          reason: 'read at the event itself');
      expect(async.elapsed, Duration.zero);

      // A burst of Synced events costs two reads in all, not one each,
      // and the Dollars balance adds none of its own.
      events
        ..add(const breez.SdkEvent.synced())
        ..add(const breez.SdkEvent.synced());
      async.elapse(kSyncedRereadSettle);
      expect(reads, seeded + 2);
      async.elapse(const Duration(seconds: 2));
      expect(reads, seeded + 2);
      wrapper.disconnect();
      async.flushMicrotasks();
    });
  });

  test('an incoming dollar payment event updates the balance at once', () {
    fakeAsync((async) {
      registerFallbackValue(const breez.GetInfoRequest());
      registerFallbackValue(const breez.ListPaymentsRequest());
      final sdk = _Sdk();
      final events = StreamController<breez.SdkEvent>.broadcast();
      addTearDown(events.close);
      var units = 5000000;
      when(() => sdk.addEventListener()).thenAnswer((_) => events.stream);
      when(() => sdk.disconnect()).thenAnswer((_) async {});
      when(() => sdk.listPayments(request: any(named: 'request'))).thenAnswer(
          (_) async => const breez.ListPaymentsResponse(payments: []));
      when(() => sdk.getInfo(request: any(named: 'request'))).thenAnswer(
          (_) async => _info({usdbTokenIdentifier: ('USDB', units)}));
      final wrapper = BreezSdkSpark.forTesting(connectSdk: (_) async => sdk);
      wrapper.connect(req: _Request());
      async.flushMicrotasks();
      final container = ProviderContainer(overrides: [
        settingsProvider.overrideWith((_) => SettingsModel(Settings(
              currency: 'USD',
              language: 'en',
              btcFormat: 'sats',
              backup: false,
              biometricsEnabled: false,
              bitcoinElectrumNode: '',
              nodeType: 'Blockstream',
              reviewDone: true,
              activeWalletId: 'spending',
              wallets: [WalletConfig(id: 'spending', name: 'Spending')],
            ))),
        breezSDKProvider.overrideWith((_) async => wrapper),
        walletTransactionCacheProvider.overrideWith((_) => _Cache({})),
      ]);
      addTearDown(container.dispose);
      container.listen(usdBalanceProvider, (_, __) {});
      async.flushMicrotasks();
      expect(container.read(usdBalanceProvider), 5);

      units = 11000000;
      events.add(breez.SdkEvent.paymentSucceeded(
          payment: _tokenPayment('rx', units: 6000000)));
      async.flushMicrotasks();
      expect(container.read(usdBalanceProvider), 11);
      expect(async.elapsed, Duration.zero);
      wrapper.disconnect();
      async.flushMicrotasks();
    });
  });
}
