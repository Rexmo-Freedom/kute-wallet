import 'dart:async';
import 'dart:io';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as spark;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/background_sync_provider.dart';
import 'package:kute/providers/breez_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/providers/usd_account_provider.dart';
import 'package:kute/providers/usdb_provider.dart';

import '../helpers/fake_swap_orders.dart';

spark.Payment _receive(String id, int dollars) => spark.Payment(
    id: id,
    paymentType: spark.PaymentType.receive,
    status: spark.PaymentStatus.completed,
    amount: BigInt.from(dollars * 1000000),
    fees: BigInt.zero,
    timestamp: BigInt.from(1792160000),
    method: spark.PaymentMethod.token,
    details: spark.PaymentDetails.token(
        metadata: spark.TokenMetadata(
            identifier: usdbTokenIdentifier,
            issuerPublicKey: 'issuer',
            name: 'USDB',
            ticker: 'USDB',
            decimals: 6,
            maxSupply: BigInt.zero,
            isFreezable: false),
        txHash: 'tx-$id',
        txType: spark.TokenTransactionType.transfer));

class _Trading extends PolymarketTradingNotifier {
  @override
  Future<PolymarketTradingState> build() async =>
      const PolymarketTradingState();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('usdb-history-failure');
    Hive.init(dir.path);
    await Hive.openBox<String>('polymarket_optimistic_activity');
    await Hive.openBox<String>('outlogicOrders');
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  for (final error in [
    StateError('query failed'),
    TimeoutException('query timeout')
  ]) {
    test(
        'failed token history preserves rows and recovery baseline: ${error.runtimeType}',
        () async {
      FlutterSecureStorage.setMockInitialValues({});
      Object? fail;
      var payments = [_receive('received_first', 5)];
      final settings = Settings(
          currency: 'USD',
          language: 'en',
          btcFormat: 'sats',
          backup: false,
          biometricsEnabled: false,
          bitcoinElectrumNode: '',
          nodeType: '',
          reviewDone: true,
          activeWalletId: 'spending',
          wallets: [WalletConfig(id: 'spending', name: 'Spending')]);
      final c = ProviderContainer(overrides: [
        settingsProvider.overrideWith((_) => SettingsModel(settings)),
        initialSettingsProvider.overrideWith((_) async => settings),
        polymarketTradingProvider.overrideWith(_Trading.new),
        swapOrdersProvider.overrideWith((_) => FakeSwapOrders()),
        listSparkBitcoinPaymentsProvider.overrideWith((_, request) async {
          if (request.assetFilter == null) return [];
          if (fail != null) throw fail;
          return payments;
        }),
        listSparkUnclaimedDepositsProvider.overrideWith((_) async => []),
        getSparkBitcoinAddressProvider
            .overrideWith((_) async => throw StateError('no address')),
      ]);
      addTearDown(c.dispose);
      final sync = c.read(backgroundSyncNotifierProvider.notifier);
      await sync.gatherTransactionsOnly();
      final baseline = c.read(usdSettledTransfersProvider);
      expect(usdLedgerSignature(baseline), 'received_first');
      expect(usdLedgerSumDollars(baseline), 5);
      final signatures = <String>[];
      c.listen(usdSettledTransfersProvider,
          (_, rows) => signatures.add(usdLedgerSignature(rows)));

      fail = error;
      await sync.gatherTransactionsOnly();
      expect(
          c.read(rawTransactionDataProvider)!.usdbPaymentsFetchFailed, isTrue);
      expect(usdLedgerSignature(c.read(usdSettledTransfersProvider)),
          'received_first');
      expect(usdLedgerSumDollars(c.read(usdSettledTransfersProvider)), 5);
      expect(signatures, everyElement('received_first'),
          reason: 'no fabricated ledger pruning on failed reads');

      fail = null;
      payments = [...payments, _receive('received_later', 2)];
      await sync.gatherTransactionsOnly();
      expect(usdLedgerSignature(c.read(usdSettledTransfersProvider)),
          'received_first,received_later');
      expect(usdLedgerSumDollars(c.read(usdSettledTransfersProvider)), 7);
      expect(
          c.read(rawTransactionDataProvider)!.usdbPaymentsFetchFailed, isFalse);

      // A genuine successful empty result remains authoritative.
      payments = [];
      await sync.gatherTransactionsOnly();
      expect(
          c.read(rawTransactionDataProvider)!.usdbPaymentsFetchFailed, isFalse);
      expect(c.read(usdSettledTransfersProvider), isEmpty);
    });
  }
}
