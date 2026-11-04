// An on-chain receive still confirming stays in Activity when a sync's
// mempool read fails: an empty list from a timeout is not the deposit
// leaving. It used to vanish on whichever sync the read failed, such as
// the one a Lightning receive starts.
import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'dart:io';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/services/mempool_address_service.dart';

SparkPendingDeposit _pending(String txid, int confirmations) =>
    SparkPendingDeposit(
      id: 'spark_pending_$txid',
      timestamp: DateTime.utc(2026, 11, 4),
      confirmations: confirmations,
      mempoolTx: MempoolTransaction(
          txid: txid, confirmed: confirmations > 0, fee: 0, balanceChange: 50000),
    );

RawTransactionData _raw(
        {List<SparkPendingDeposit> pending = const [],
        bool failed = false,
        List<breez.DepositInfo> unclaimed = const []}) =>
    RawTransactionData(
      bitcoinTxs: const [],
      lightningPayments: const [],
      sparkOnChainPayments: const [],
      sparkInternalPayments: const [],
      unclaimedDeposits: unclaimed,
      sparkPendingDeposits: pending,
      sparkPendingDepositsFetchFailed: failed,
    );

void main() {
  late Directory dir;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('pending_deposit');
    Hive.init(dir.path);
    await Hive.openBox<String>('polymarket_optimistic_activity');
  });
  tearDownAll(() => dir.delete(recursive: true));

  test('a failed mempool read keeps the receive that is confirming',
      () async {
    final c = ProviderContainer(overrides: [
      settingsProvider.overrideWith((_) => SettingsModel(Settings(
            wallets: [WalletConfig(id: 'w1', name: 'Spending')],
            activeWalletId: 'w1',
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: true,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: '',
            reviewDone: true,
          ))),
    ]);
    addTearDown(c.dispose);
    final notifier = c.read(transactionNotifierProvider.notifier);
    List<String> shown() => [
          for (final d in c.read(walletTransactionCacheProvider)['w1']
                  ?.sparkPendingDeposits ??
              const <SparkPendingDeposit>[])
            d.mempoolTx.txid
        ];

    await notifier.updateTransactionsFor('w1', _raw(pending: [_pending('aa', 1)]));
    expect(shown(), ['aa']);
    // The next sync could not read mempool: the row stays.
    await notifier.updateTransactionsFor('w1', _raw(failed: true));
    expect(shown(), ['aa']);
    // The SDK submitted an instant claim for it: the row says it is
    // being added, not "1 of 3".
    bool claiming() => c
        .read(walletTransactionCacheProvider)['w1']!
        .sparkPendingDeposits
        .single
        .claimInProgress;
    await notifier.updateTransactionsFor(
        'w1',
        _raw(pending: [
          _pending('aa', 1)
        ], unclaimed: [
          breez.DepositInfo(
              txid: 'aa',
              vout: 0,
              amountSats: BigInt.from(50000),
              isMature: false,
              instantClaimStatus:
                  const breez.InstantClaimStatus.submitted(claimId: 'c1')),
        ]));
    expect(claiming(), isTrue);
    // Without the claim it counts confirmations again.
    await notifier.updateTransactionsFor('w1', _raw(pending: [_pending('aa', 1)]));
    expect(claiming(), isFalse);
    // A read that worked and no longer sees it: it goes.
    await notifier.updateTransactionsFor('w1', _raw());
    expect(shown(), isEmpty);
  });
}
