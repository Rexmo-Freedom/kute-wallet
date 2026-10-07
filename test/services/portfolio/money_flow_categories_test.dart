// The Breakdown donut's categories on Home (bitcoin, in sats) and Dollars
// (in dollars): every kind of money out and in, receives never counted as
// sent and sends never as received, only settled money, all time, and the
// top five + Other grouping the card draws.

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/swap_activity.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart' show Activity;
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/screens/analytics/components/money_flow_breakdown.dart'
    show moneyFlowCategoryLabel;
import 'package:kute/screens/portfolio/portfolio_category_donut.dart'
    show categorySlices, CategorySliceKind;
import 'package:kute/screens/shared/transactions_builder.dart'
    show assembleActivityRows;
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode;
import 'package:kute/services/portfolio/money_flow_categories.dart';

const _usd = kOrchestraUsdAssetCode;
const _self = 'sp1self';
final _t0 = DateTime.utc(2026, 10, 5, 12);

SwapOrderTransaction _swap(
  String id, {
  required String coinFrom,
  required String networkFrom,
  required String coinTo,
  required String networkTo,
  required String deposit,
  required String withdrawal,
  String status = 'success',
  String? purchaseSource,
  DateTime? at,
}) {
  final ts = at ?? _t0;
  return SwapOrderTransaction(
    id: id,
    timestamp: ts,
    isConfirmed: true,
    details: SwapOrder(
      id: id,
      coinFrom: coinFrom,
      networkFrom: networkFrom,
      coinTo: coinTo,
      networkTo: networkTo,
      depositAddress: 'deposit-$id',
      depositAmount: deposit,
      withdrawalAmount: withdrawal,
      status: status,
      timestamp: ts.millisecondsSinceEpoch,
      withdrawalAddress: networkTo == 'SPARK' ? _self : '0xelsewhere',
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: '',
      provider: 'Orchestra',
      walletId: 'spending',
      purchaseSource: purchaseSource,
    ),
  );
}

SparkTransaction _spark(String id, int sats, SparkTransactionType rail,
        TransactionType direction,
        {bool pending = false, DateTime? at}) =>
    SparkTransaction.fromCache(
      id: id,
      timestamp: at ?? _t0,
      isConfirmed: !pending,
      amountSats: sats,
      sparkType: rail,
      direction: direction,
      pending: pending,
    );

UsdbTokenTransaction _dollars(String id, double usd, breez.PaymentType type,
    {breez.PaymentStatus status = breez.PaymentStatus.completed,
    DateTime? at}) {
  final ts = at ?? _t0;
  return UsdbTokenTransaction(
    id: id,
    timestamp: ts,
    isConfirmed: true,
    details: breez.Payment(
      id: id,
      paymentType: type,
      status: status,
      amount: BigInt.from((usd * 1e6).round()),
      fees: BigInt.zero,
      timestamp: BigInt.from(ts.millisecondsSinceEpoch ~/ 1000),
      method: breez.PaymentMethod.token,
      details: breez.PaymentDetails.token(
        metadata: breez.TokenMetadata(
          identifier: 'btkn1usdb',
          issuerPublicKey: 'issuer',
          name: 'USDB',
          ticker: 'USDB',
          decimals: 6,
          maxSupply: BigInt.zero,
          isFreezable: false,
        ),
        txHash: 'tx-$id',
        txType: breez.TokenTransactionType.transfer,
      ),
    ),
  );
}

const _sent = TransactionType.sent;
const _received = TransactionType.received;
const _ln = SparkTransactionType.lightning;
const _sp = SparkTransactionType.spark;
const _chain = SparkTransactionType.bitcoin;

/// The conversions' intent by id; anything else reads as a plain swap.
const _kinds = {
  'btc_inv': SwapActivityKind.investingDeposit,
  'btc_pm': SwapActivityKind.predictionsDeposit,
  'btc_usd': SwapActivityKind.dollarDeposit,
  'btc_eth': SwapActivityKind.send,
  'inv_btc': SwapActivityKind.investingWithdrawal,
  'pm_btc': SwapActivityKind.predictionsWithdrawal,
  'usd_btc': SwapActivityKind.dollarWithdrawal,
  'sol_btc': SwapActivityKind.receive,
  'usd_inv': SwapActivityKind.investingDeposit,
  'usd_pm': SwapActivityKind.predictionsDeposit,
  'usd_ln': SwapActivityKind.send,
  'usd_chain': SwapActivityKind.send,
  'usd_eth': SwapActivityKind.send,
  'inv_usd': SwapActivityKind.investingWithdrawal,
  'pm_usd': SwapActivityKind.predictionsWithdrawal,
  'usdc_usd': SwapActivityKind.receive,
};

Map<String, double> _flows(List<BaseTransaction> rows, MoneyFlowLedger ledger,
        MoneyFlowDirection direction) =>
    moneyFlowCategories(rows,
        ledger: ledger,
        direction: direction,
        classify: (o) => _kinds[o.id] ?? classifySwapActivity(o));

/// The spending wallet's history: one of every bitcoin move.
final _bitcoinRows = <BaseTransaction>[
  _spark('ln_out', 1000, _ln, _sent),
  _spark('sp_out', 2000, _sp, _sent),
  _spark('chain_out', 3000, _chain, _sent),
  _spark('ln_in', 400, _ln, _received),
  _spark('sp_in', 500, _sp, _received),
  _spark('chain_in', 600, _chain, _received),
  _swap('btc_inv',
      coinFrom: 'BTC',
      networkFrom: 'SPARK',
      coinTo: 'USDC',
      networkTo: 'HYPERCORE',
      deposit: '0.0004',
      withdrawal: '40'),
  _swap('btc_pm',
      coinFrom: 'BTC',
      networkFrom: 'SPARK',
      coinTo: 'USDC.E',
      networkTo: 'POLYGON',
      deposit: '0.0005',
      withdrawal: '50'),
  _swap('btc_usd',
      coinFrom: 'BTC',
      networkFrom: 'SPARK',
      coinTo: _usd,
      networkTo: 'SPARK',
      deposit: '0.0006',
      withdrawal: '60'),
  _swap('btc_eth',
      coinFrom: 'BTC',
      networkFrom: 'SPARK',
      coinTo: 'ETH',
      networkTo: 'ETHEREUM',
      deposit: '0.0007',
      withdrawal: '0.02'),
  _swap('inv_btc',
      coinFrom: 'USDC',
      networkFrom: 'HYPERCORE',
      coinTo: 'BTC',
      networkTo: 'SPARK',
      deposit: '10',
      withdrawal: '0.0001'),
  _swap('pm_btc',
      coinFrom: 'USDC.E',
      networkFrom: 'POLYGON',
      coinTo: 'BTC',
      networkTo: 'SPARK',
      deposit: '20',
      withdrawal: '0.0002'),
  _swap('usd_btc',
      coinFrom: _usd,
      networkFrom: 'SPARK',
      coinTo: 'BTC',
      networkTo: 'SPARK',
      deposit: '30',
      withdrawal: '0.0003'),
  _swap('sol_btc',
      coinFrom: 'SOL',
      networkFrom: 'SOLANA',
      coinTo: 'BTC',
      networkTo: 'SPARK',
      deposit: '1',
      withdrawal: '0.00015'),
  _swap('cashapp',
      coinFrom: 'BTC',
      networkFrom: 'LIGHTNING',
      coinTo: 'BTC',
      networkTo: 'SPARK',
      deposit: '0.0008',
      withdrawal: '0.0008',
      purchaseSource: 'cashapp'),
];

/// The dollar ledger: one of every dollar move.
final _dollarRows = <BaseTransaction>[
  _dollars('tok_out', 5, breez.PaymentType.send),
  _dollars('tok_in', 7, breez.PaymentType.receive),
  _swap('usd_inv',
      coinFrom: _usd,
      networkFrom: 'SPARK',
      coinTo: 'USDC',
      networkTo: 'HYPERCORE',
      deposit: '11',
      withdrawal: '11'),
  _swap('usd_pm',
      coinFrom: _usd,
      networkFrom: 'SPARK',
      coinTo: 'USDC.E',
      networkTo: 'POLYGON',
      deposit: '12',
      withdrawal: '12'),
  _swap('usd_btc',
      coinFrom: _usd,
      networkFrom: 'SPARK',
      coinTo: 'BTC',
      networkTo: 'SPARK',
      deposit: '13',
      withdrawal: '0.00013'),
  _swap('usd_ln',
      coinFrom: _usd,
      networkFrom: 'SPARK',
      coinTo: 'BTC',
      networkTo: 'LIGHTNING',
      deposit: '14',
      withdrawal: '0.00014'),
  _swap('usd_chain',
      coinFrom: _usd,
      networkFrom: 'SPARK',
      coinTo: 'BTC',
      networkTo: 'BITCOIN',
      deposit: '15',
      withdrawal: '0.00015'),
  _swap('usd_eth',
      coinFrom: _usd,
      networkFrom: 'SPARK',
      coinTo: 'USDC',
      networkTo: 'ETHEREUM',
      deposit: '16',
      withdrawal: '16'),
  _swap('btc_usd',
      coinFrom: 'BTC',
      networkFrom: 'SPARK',
      coinTo: _usd,
      networkTo: 'SPARK',
      deposit: '0.0002',
      withdrawal: '21'),
  _swap('inv_usd',
      coinFrom: 'USDC',
      networkFrom: 'HYPERCORE',
      coinTo: _usd,
      networkTo: 'SPARK',
      deposit: '22',
      withdrawal: '22'),
  _swap('pm_usd',
      coinFrom: 'USDC.E',
      networkFrom: 'POLYGON',
      coinTo: _usd,
      networkTo: 'SPARK',
      deposit: '23',
      withdrawal: '23'),
  _swap('usdc_usd',
      coinFrom: 'USDC',
      networkFrom: 'BASE',
      coinTo: _usd,
      networkTo: 'SPARK',
      deposit: '24',
      withdrawal: '24'),
  _swap('cashapp_usd',
      coinFrom: 'BTC',
      networkFrom: 'LIGHTNING',
      coinTo: _usd,
      networkTo: 'SPARK',
      deposit: '0.0003',
      withdrawal: '25',
      purchaseSource: 'cashapp'),
];

void main() {
  group('Bitcoin (Home, spending wallet)', () {
    test('sent: each rail and each destination, in sats', () {
      final out = _flows(
          _bitcoinRows, MoneyFlowLedger.bitcoin, MoneyFlowDirection.sent);
      expect(out.keys.toSet(), {
        'lightning',
        'spark',
        'onchain',
        'investing',
        'predictions',
        'dollars',
        'other_crypto',
      });
      expect(out['lightning'], 1000);
      expect(out['spark'], 2000);
      expect(out['onchain'], 3000);
      expect(out['investing'], closeTo(40000, 0.5));
      expect(out['predictions'], closeTo(50000, 0.5));
      expect(out['dollars'], closeTo(60000, 0.5));
      expect(out['other_crypto'], closeTo(70000, 0.5));
    });

    test('received: each rail and each source, in sats', () {
      final out = _flows(
          _bitcoinRows, MoneyFlowLedger.bitcoin, MoneyFlowDirection.received);
      expect(out.keys.toSet(), {
        'lightning',
        'spark',
        'onchain',
        'investing',
        'predictions',
        'dollars',
        'other_crypto',
        'cash_app',
      });
      expect(out['lightning'], 400);
      expect(out['spark'], 500);
      expect(out['onchain'], 600);
      expect(out['investing'], closeTo(10000, 0.5));
      expect(out['predictions'], closeTo(20000, 0.5));
      expect(out['dollars'], closeTo(30000, 0.5));
      expect(out['other_crypto'], closeTo(15000, 0.5));
      expect(out['cash_app'], closeTo(80000, 0.5));
    });

    test('a receive is never sent and a send never received', () {
      final receives = [
        _spark('a', 900, _ln, _received),
        _swap('inv_btc',
            coinFrom: 'USDC',
            networkFrom: 'HYPERCORE',
            coinTo: 'BTC',
            networkTo: 'SPARK',
            deposit: '10',
            withdrawal: '0.0001'),
      ];
      expect(_flows(receives, MoneyFlowLedger.bitcoin, MoneyFlowDirection.sent),
          isEmpty);
      final sends = [
        _spark('b', 900, _ln, _sent),
        // A send that delivers bitcoin pays someone else's bitcoin.
        _swap('btc_eth',
            coinFrom: 'BTC',
            networkFrom: 'SPARK',
            coinTo: 'BTC',
            networkTo: 'LIGHTNING',
            deposit: '0.0001',
            withdrawal: '0.0001'),
      ];
      expect(
          _flows(sends, MoneyFlowLedger.bitcoin, MoneyFlowDirection.received),
          isEmpty);
    });

    test('only settled money counts; dollar transfers are not bitcoin', () {
      final rows = <BaseTransaction>[
        _spark('pending', 5000, _ln, _sent, pending: true),
        _swap('btc_inv',
            coinFrom: 'BTC',
            networkFrom: 'SPARK',
            coinTo: 'USDC',
            networkTo: 'HYPERCORE',
            deposit: '0.001',
            withdrawal: '100',
            status: 'exchanging'),
        _swap('btc_pm',
            coinFrom: 'BTC',
            networkFrom: 'SPARK',
            coinTo: 'USDC.E',
            networkTo: 'POLYGON',
            deposit: '0.001',
            withdrawal: '100',
            status: 'refunded'),
        _dollars('tok', 50, breez.PaymentType.send),
      ];
      expect(_flows(rows, MoneyFlowLedger.bitcoin, MoneyFlowDirection.sent),
          isEmpty);
    });

    test('all time: a payment from years ago counts like today\'s', () {
      final rows = [
        _spark('old', 100, _sp, _sent, at: DateTime.utc(2021, 1, 1)),
        _spark('new', 100, _sp, _sent),
      ];
      expect(_flows(rows, MoneyFlowLedger.bitcoin, MoneyFlowDirection.sent),
          {'spark': 200});
    });

    test(
        'a Predictions move counts its conversion once, in sats, beside the '
        'venue row and behind its funding send', () {
      final move = _swap('btc_pm',
          coinFrom: 'BTC',
          networkFrom: 'SPARK',
          coinTo: 'USDC.E',
          networkTo: 'POLYGON',
          deposit: '0.0005',
          withdrawal: '50');
      // The Spark payment that funded it, to the order's deposit address
      // (a cache shell: no destination, so the amount/time match folds it).
      final funding = _spark('fund', 50000, _sp, _sent,
          at: _t0.add(const Duration(minutes: 1)));
      final venueRow = PolymarketTransaction(
        id: '0xdeposit',
        timestamp: _t0.add(const Duration(minutes: 4)),
        activity: Activity(
          proxyWallet: '0xsafe',
          timestamp: _t0.millisecondsSinceEpoch ~/ 1000,
          conditionId: '',
          type: 'DEPOSIT',
          size: 50,
          usdcSize: 50,
          transactionHash: '0xdeposit',
        ),
      );
      final sorted = <BaseTransaction>[venueRow, funding, move];
      final rows = assembleActivityRows(sorted,
          ownAddresses: {_self},
          isHardwareOrWatchOnly: false,
          onlyUsdb: false,
          keepVenueMoves: true,
          classify: (o) => _kinds[o.id] ?? classifySwapActivity(o));
      expect(rows.map((r) => r.id), isNot(contains('fund')));
      expect(
          moneyFlowCategories(rows,
              ledger: MoneyFlowLedger.bitcoin,
              direction: MoneyFlowDirection.sent,
              classify: (o) => _kinds[o.id] ?? classifySwapActivity(o)),
          {'predictions': closeTo(50000, 0.5)});
    });
  });

  group('Dollars', () {
    test('sent: transfers, venues, bitcoin and each send rail, in dollars', () {
      final out =
          _flows(_dollarRows, MoneyFlowLedger.dollars, MoneyFlowDirection.sent);
      expect(out, {
        'spark': closeTo(5, 1e-9),
        'investing': closeTo(11, 1e-9),
        'predictions': closeTo(12, 1e-9),
        'bitcoin': closeTo(13, 1e-9),
        'lightning': closeTo(14, 1e-9),
        'onchain': closeTo(15, 1e-9),
        'other_crypto': closeTo(16, 1e-9),
      });
    });

    test('received: transfers, venues, bitcoin, coins and Cash App', () {
      final out = _flows(
          _dollarRows, MoneyFlowLedger.dollars, MoneyFlowDirection.received);
      expect(out, {
        'spark': closeTo(7, 1e-9),
        'bitcoin': closeTo(21, 1e-9),
        'investing': closeTo(22, 1e-9),
        'predictions': closeTo(23, 1e-9),
        'other_crypto': closeTo(24, 1e-9),
        'cash_app': closeTo(25, 1e-9),
      });
    });

    test('a failed dollar transfer and bitcoin payments do not count', () {
      final rows = <BaseTransaction>[
        _dollars('failed', 9, breez.PaymentType.send,
            status: breez.PaymentStatus.failed),
        _spark('sats', 1000, _sp, _sent),
      ];
      expect(_flows(rows, MoneyFlowLedger.dollars, MoneyFlowDirection.sent),
          isEmpty);
    });
  });

  test('more than five kinds: the five largest keep a slice, the rest Other',
      () {
    final out =
        _flows(_bitcoinRows, MoneyFlowLedger.bitcoin, MoneyFlowDirection.sent);
    final slices = categorySlices(out);
    expect(slices.length, 6);
    expect([for (final s in slices.take(5)) s.key],
        ['other_crypto', 'dollars', 'predictions', 'investing', 'onchain']);
    expect(slices.last.kind, CategorySliceKind.other);
    // Spark and Lightning together.
    expect(slices.last.value, 3000);
    expect(slices.fold<int>(0, (a, s) => a + s.percent), 100);
  });

  group('one slice per name', () {
    final en = lookupAppLocalizations(const Locale('en'));
    String label(String key) => moneyFlowCategoryLabel(en, key);

    test('every Spark payment is one Spark category, on both ledgers', () {
      // Bitcoin over Spark, bitcoin sent to a Spark address, a dollar
      // transfer, and dollars sent to a Spark address as bitcoin or as
      // dollars: one "spark" key each side.
      final bitcoin = moneyFlowCategories([
        _spark('sp', 1000, _sp, _sent),
        _swap('btc_to_spark',
            coinFrom: 'BTC',
            networkFrom: 'SPARK',
            coinTo: 'BTC',
            networkTo: 'SPARK',
            deposit: '0.00002',
            withdrawal: '0.00002'),
      ],
          ledger: MoneyFlowLedger.bitcoin,
          direction: MoneyFlowDirection.sent,
          classify: (_) => SwapActivityKind.send);
      expect(bitcoin.keys, ['spark']);
      expect(bitcoin['spark'], closeTo(3000, 0.5));

      final dollars = moneyFlowCategories([
        _dollars('tok', 5, breez.PaymentType.send),
        _swap('usd_to_spark_btc',
            coinFrom: _usd,
            networkFrom: 'SPARK',
            coinTo: 'BTC',
            networkTo: 'SPARK',
            deposit: '6',
            withdrawal: '0.00006'),
        _swap('usd_to_spark_usd',
            coinFrom: _usd,
            networkFrom: 'SPARK',
            coinTo: _usd,
            networkTo: 'SPARK',
            deposit: '7',
            withdrawal: '7'),
      ],
          ledger: MoneyFlowLedger.dollars,
          direction: MoneyFlowDirection.sent,
          classify: (_) => SwapActivityKind.send);
      expect(dollars.keys, ['spark']);
      expect(dollars['spark'], closeTo(18, 1e-9));
    });

    test('no two slices share a name, on either screen, either way', () {
      for (final (rows, ledger) in [
        (_bitcoinRows, MoneyFlowLedger.bitcoin),
        (_dollarRows, MoneyFlowLedger.dollars),
      ]) {
        for (final direction in MoneyFlowDirection.values) {
          final slices = categorySlices(_flows(rows, ledger, direction),
              labelOf: label);
          final names = [for (final s in slices) label(s.key)];
          expect(names.toSet().length, names.length,
              reason: '$ledger $direction: $names');
        }
      }
    });

    test('categories that read the same fold into one slice before ranking',
        () {
      // Two keys that both read "Spark" (and an unknown key that reads
      // "Other" beside the grouped Other) are one slice each.
      String reads(String key) => switch (key) {
            'spark' || 'spark_dollars' => 'Spark',
            _ => label(key),
          };
      final slices = categorySlices({
        'spark': 5,
        'spark_dollars': 4,
        'lightning': 6,
        'mystery': 1,
        MoneyFlowCategory.other: 2,
      }, labelOf: reads);
      final names = [for (final s in slices) reads(s.key)];
      expect(names, ['Spark', 'Lightning', 'Other']);
      expect(slices.first.key, 'spark');
      expect(slices.first.value, 9);
      expect(slices.last.kind, CategorySliceKind.other);
      expect(slices.last.value, 3);
      expect(slices.fold<int>(0, (a, s) => a + s.percent), 100);
    });
  });
}
