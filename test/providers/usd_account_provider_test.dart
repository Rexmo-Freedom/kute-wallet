// The Dollars balance reads the SDK's `tokenBalances`. An answer with no
// dollar entry means the SDK's token store has not caught up (its Spark
// sync kept failing), not that the account is empty: the settled ledger
// decides until it does. A dollar entry, even a zero one, always wins.
// Only the dollar token ever counts as dollars.

import 'dart:async';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/breez/sdk_instance.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/providers/usd_account_provider.dart';
import 'package:kute/providers/usdb_provider.dart';

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
}) =>
    breez.Payment(
      id: id,
      paymentType: type,
      status: status,
      amount: BigInt.from(units),
      fees: BigInt.zero,
      timestamp: BigInt.from(1700000000),
      method: breez.PaymentMethod.token,
      details: breez.PaymentDetails.token(
        metadata: _meta(identifier, ticker),
        txHash: 'tx-$id',
        txType: breez.TokenTransactionType.transfer,
      ),
    );

UsdbTokenTransaction _row(breez.Payment p) => UsdbTokenTransaction(
      id: p.id,
      timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
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
        readInfo: () async {
          final i = reads < answers.length ? reads : answers.length - 1;
          reads++;
          return answers[i];
        },
        syncWallet: () async => syncs++,
        publish: published.add,
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
        readInfo: () async => _info({usdbTokenIdentifier: ('USDB', 5000000)}),
        syncWallet: () => Future<void>.error(TimeoutException('offline')),
        publish: published.add,
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
}
