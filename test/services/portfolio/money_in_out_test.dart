// The Bitcoin home's In & out tab: every kind of bitcoin move lands in the
// right plain-words category on the right side, fees apart from the
// amounts, only settled money, and the month / year periods.

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/swap_activity.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart' show Activity;
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/screens/analytics/components/money_in_out.dart'
    show moneyCategoryLabel;
import 'package:kute/screens/shared/transactions_builder.dart'
    show assembleActivityRows;
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode;
import 'package:kute/services/portfolio/money_in_out.dart';

const _usd = kOrchestraUsdAssetCode;
const _self = 'sp1self';
final _t0 = DateTime(2026, 10, 5, 12);

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

SparkTransaction _spark(String id, int sats, TransactionType direction,
        {bool pending = false, DateTime? at}) =>
    SparkTransaction.fromCache(
      id: id,
      timestamp: at ?? _t0,
      isConfirmed: !pending,
      amountSats: sats,
      sparkType: SparkTransactionType.lightning,
      direction: direction,
      pending: pending,
    );

/// A live Spark payment (the SDK payload carries its fee).
SparkTransaction _live(String id, int sats, int fee, breez.PaymentType type,
    {breez.PaymentStatus status = breez.PaymentStatus.completed,
    breez.PaymentMethod method = breez.PaymentMethod.lightning,
    DateTime? at}) {
  final ts = at ?? _t0;
  return SparkTransaction(
    id: id,
    timestamp: ts,
    isConfirmed: status == breez.PaymentStatus.completed,
    details: breez.Payment(
      id: id,
      paymentType: type,
      status: status,
      amount: BigInt.from(sats),
      fees: BigInt.from(fee),
      timestamp: BigInt.from(ts.millisecondsSinceEpoch ~/ 1000),
      method: method,
    ),
  );
}

UsdbTokenTransaction _dollars(String id, double usd, breez.PaymentType type) {
  return UsdbTokenTransaction(
    id: id,
    timestamp: _t0,
    isConfirmed: true,
    details: breez.Payment(
      id: id,
      paymentType: type,
      status: breez.PaymentStatus.completed,
      amount: BigInt.from((usd * 1e6).round()),
      fees: BigInt.zero,
      timestamp: BigInt.from(_t0.millisecondsSinceEpoch ~/ 1000),
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

/// The conversions' intent by id; anything else reads as the classifier
/// reads it.
const _kinds = {
  'btc_inv': SwapActivityKind.investingDeposit,
  'btc_pm': SwapActivityKind.predictionsDeposit,
  'btc_usd': SwapActivityKind.dollarDeposit,
  'btc_eth': SwapActivityKind.send,
  'inv_btc': SwapActivityKind.investingWithdrawal,
  'pm_btc': SwapActivityKind.predictionsWithdrawal,
  'usd_btc': SwapActivityKind.dollarWithdrawal,
  'sol_btc': SwapActivityKind.receive,
};

SwapActivityKind _classify(SwapOrder o) =>
    _kinds[o.id] ?? classifySwapActivity(o);

List<MoneyMove> _moves(List<BaseTransaction> rows,
        {List<BaseTransaction>? everyRow}) =>
    moneyMoves(rows, everyRow: everyRow, classify: _classify);

/// Side → category → sats, over every move.
Map<MoneySide, Map<MoneyCategory, int>> _split(List<MoneyMove> moves) {
  final out = <MoneySide, Map<MoneyCategory, int>>{};
  for (final m in moves) {
    final side = out.putIfAbsent(m.side, () => {});
    side[m.category] = (side[m.category] ?? 0) + m.sats;
  }
  return out;
}

void main() {
  group('categories', () {
    test('Spark payments: out is Sent to people, in is From people', () {
      final split = _split(_moves([
        _spark('ln_out', 1000, _sent),
        _spark('ln_in', 400, _received),
      ]));
      expect(split, {
        MoneySide.moneyOut: {MoneyCategory.people: 1000},
        MoneySide.moneyIn: {MoneyCategory.people: 400},
      });
    });

    test('every rail is one category: Lightning, Spark and on-chain', () {
      final split = _split(_moves([
        _live('ln', 100, 0, breez.PaymentType.send),
        _live('sp', 200, 0, breez.PaymentType.send,
            method: breez.PaymentMethod.spark),
        _live('chain', 300, 0, breez.PaymentType.send,
            method: breez.PaymentMethod.withdraw),
        _live('chain_in', 50, 0, breez.PaymentType.receive,
            method: breez.PaymentMethod.deposit),
      ]));
      expect(split[MoneySide.moneyOut], {MoneyCategory.people: 600});
      expect(split[MoneySide.moneyIn], {MoneyCategory.people: 50});
    });

    test('fees are their own category, never inside the amount', () {
      final split = _split(_moves([
        _live('out', 10000, 25, breez.PaymentType.send),
        _live('in', 3000, 0, breez.PaymentType.receive),
      ]));
      expect(split[MoneySide.moneyOut],
          {MoneyCategory.people: 10000, MoneyCategory.fees: 25});
      expect(split[MoneySide.moneyIn], {MoneyCategory.people: 3000});
    });

    test(
        'a funding leg folded behind its conversion still pays its fee: '
        'fees read every row, the amounts only the listed ones', () {
      final move = _swap('btc_inv',
          coinFrom: 'BTC',
          networkFrom: 'SPARK',
          coinTo: 'USDC',
          networkTo: 'HYPERCORE',
          deposit: '0.0004',
          withdrawal: '40');
      final funding = _live('fund', 40000, 12, breez.PaymentType.send);
      final split =
          _split(_moves([move], everyRow: [move, funding]));
      expect(split[MoneySide.moneyOut], {
        MoneyCategory.investments: closeTo(40000, 1),
        MoneyCategory.fees: 12,
      });
    });

    test('venue moves: into and from Investing and Predictions', () {
      final split = _split(_moves([
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
      ]));
      expect(split[MoneySide.moneyOut],
          {MoneyCategory.investments: closeTo(90000, 1)});
      expect(split[MoneySide.moneyIn],
          {MoneyCategory.investments: closeTo(30000, 1)});
    });

    test('conversions both ways: Into Dollars and From Dollars', () {
      final split = _split(_moves([
        _swap('btc_usd',
            coinFrom: 'BTC',
            networkFrom: 'SPARK',
            coinTo: _usd,
            networkTo: 'SPARK',
            deposit: '0.0006',
            withdrawal: '60'),
        _swap('usd_btc',
            coinFrom: _usd,
            networkFrom: 'SPARK',
            coinTo: 'BTC',
            networkTo: 'SPARK',
            deposit: '30',
            withdrawal: '0.0003'),
      ]));
      expect(split[MoneySide.moneyOut],
          {MoneyCategory.dollars: closeTo(60000, 1)});
      expect(split[MoneySide.moneyIn],
          {MoneyCategory.dollars: closeTo(30000, 1)});
    });

    test(
        'a plain Spark-to-Spark conversion with no recorded intent reads '
        'its dollar end as Dollars', () {
      final split = _split(moneyMoves([
        _swap('plain',
            coinFrom: 'BTC',
            networkFrom: 'SPARK',
            coinTo: _usd,
            networkTo: 'SPARK',
            deposit: '0.0001',
            withdrawal: '10'),
      ]));
      expect(split[MoneySide.moneyOut],
          {MoneyCategory.dollars: closeTo(10000, 1)});
    });

    test('on-ramp: a Cash App purchase is Bought, never money out', () {
      final split = _split(_moves([
        _swap('cashapp',
            coinFrom: 'BTC',
            networkFrom: 'LIGHTNING',
            coinTo: 'BTC',
            networkTo: 'SPARK',
            deposit: '0.0008',
            withdrawal: '0.0008',
            purchaseSource: 'cashapp'),
      ]));
      expect(split, {
        MoneySide.moneyIn: {MoneyCategory.bought: closeTo(80000, 1)},
      });
    });

    test(
        'a send in another coin is Sent to people; a coin received from '
        'outside is From people; neither counts on the other side', () {
      final split = _split(_moves([
        _swap('btc_eth',
            coinFrom: 'BTC',
            networkFrom: 'SPARK',
            coinTo: 'ETH',
            networkTo: 'ETHEREUM',
            deposit: '0.0007',
            withdrawal: '0.02'),
        _swap('sol_btc',
            coinFrom: 'SOL',
            networkFrom: 'SOLANA',
            coinTo: 'BTC',
            networkTo: 'SPARK',
            deposit: '1',
            withdrawal: '0.00015'),
      ]));
      expect(split, {
        MoneySide.moneyOut: {MoneyCategory.people: closeTo(70000, 1)},
        MoneySide.moneyIn: {MoneyCategory.people: closeTo(15000, 1)},
      });
    });

    test('a bitcoin send over Lightning through a conversion counts once',
        () {
      final split = _split(moneyMoves([
        _swap('btc_ln',
            coinFrom: 'BTC',
            networkFrom: 'SPARK',
            coinTo: 'BTC',
            networkTo: 'LIGHTNING',
            deposit: '0.0002',
            withdrawal: '0.000199'),
      ]));
      expect(split, {
        MoneySide.moneyOut: {MoneyCategory.people: closeTo(20000, 1)},
      });
    });

    test(
        'only settled money: pending, failed, in-flight or refunded moves '
        'count nowhere; dollar transfers are not bitcoin', () {
      final moves = _moves([
        _spark('pending', 5000, _sent, pending: true),
        _live('failed', 7000, 30, breez.PaymentType.send,
            status: breez.PaymentStatus.failed),
        _live('flying', 7000, 30, breez.PaymentType.send,
            status: breez.PaymentStatus.pending),
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
      ]);
      expect(moves, isEmpty);
    });

    test(
        'a Predictions move counts its conversion once, beside the venue '
        'row and behind its funding send', () {
      final move = _swap('btc_pm',
          coinFrom: 'BTC',
          networkFrom: 'SPARK',
          coinTo: 'USDC.E',
          networkTo: 'POLYGON',
          deposit: '0.0005',
          withdrawal: '50');
      final funding =
          _spark('fund', 50000, _sent, at: _t0.add(const Duration(minutes: 1)));
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
          classify: _classify);
      expect(rows.map((r) => r.id), isNot(contains('fund')));
      expect(_split(_moves(rows, everyRow: sorted)), {
        MoneySide.moneyOut: {MoneyCategory.investments: closeTo(50000, 1)},
      });
    });

    test('every category reads in plain words, never a rail', () {
      final en = lookupAppLocalizations(const Locale('en'));
      final labels = {
        for (final side in MoneySide.values)
          for (final c in moneyCategoriesOf(side))
            moneyCategoryLabel(en, side, c),
      };
      expect(labels, {
        'Sent to people',
        'Into Investments',
        'Into Dollars',
        'Fees',
        'From people',
        'From Investments',
        'From Dollars',
        'Bought',
      });
      for (final l in labels) {
        expect(l, isNot(matches(RegExp('Lightning|Spark|On-chain|Cash App'))));
      }
    });
  });

  group('periods', () {
    final now = DateTime(2026, 10, 28, 9);

    test('a month runs from its first day to the next month\'s', () {
      final oct = MoneyPeriod.back(MoneyPeriodKind.month, now, 0);
      expect(oct.start, DateTime(2026, 10));
      expect(oct.end, DateTime(2026, 11));
      expect(oct.contains(DateTime(2026, 10, 31, 23, 59)), isTrue);
      expect(oct.contains(DateTime(2026, 11)), isFalse);
      // Back across the new year.
      expect(MoneyPeriod.back(MoneyPeriodKind.month, now, 10).start,
          DateTime(2025, 12));
      expect(MoneyPeriod.back(MoneyPeriodKind.year, now, 1).start,
          DateTime(2025));
    });

    test('totals sum a period\'s moves, largest category first', () {
      final moves = _moves([
        _live('a', 1000, 10, breez.PaymentType.send, at: DateTime(2026, 10, 2)),
        _live('b', 9000, 0, breez.PaymentType.receive,
            at: DateTime(2026, 10, 3)),
        _swap('btc_usd',
            coinFrom: 'BTC',
            networkFrom: 'SPARK',
            coinTo: _usd,
            networkTo: 'SPARK',
            deposit: '0.00005',
            withdrawal: '5',
            at: DateTime(2026, 10, 4)),
        _live('sept', 4000, 0, breez.PaymentType.send,
            at: DateTime(2026, 9, 30)),
      ]);
      final oct =
          moneyTotals(moves, MoneyPeriod.back(MoneyPeriodKind.month, now, 0));
      expect(oct.totalIn, 9000);
      expect(oct.totalOut, 6010);
      expect(oct.rowsOf(MoneySide.moneyOut).map((e) => e.key), [
        MoneyCategory.dollars,
        MoneyCategory.people,
        MoneyCategory.fees,
      ]);
      final sept =
          moneyTotals(moves, MoneyPeriod.back(MoneyPeriodKind.month, now, 1));
      expect(sept.totalOut, 4000);
      expect(sept.totalIn, 0);
      final year =
          moneyTotals(moves, MoneyPeriod.back(MoneyPeriodKind.year, now, 0));
      expect(year.totalOut, 10010);
      expect(
          moneyTotals(moves, MoneyPeriod.back(MoneyPeriodKind.month, now, 2))
              .isEmpty,
          isTrue);
    });

    test('six months; each year since the first move, five at most', () {
      MoneyMove at(int year) => MoneyMove(
          at: DateTime(year, 6),
          side: MoneySide.moneyIn,
          category: MoneyCategory.people,
          sats: 1);
      expect(moneyPeriodCount(MoneyPeriodKind.month, now, const []), 6);
      expect(moneyPeriodCount(MoneyPeriodKind.year, now, const []), 1);
      expect(moneyPeriodCount(MoneyPeriodKind.year, now, [at(2026)]), 1);
      expect(moneyPeriodCount(MoneyPeriodKind.year, now, [at(2025)]), 2);
      expect(moneyPeriodCount(MoneyPeriodKind.year, now, [at(2023)]), 4);
      expect(moneyPeriodCount(MoneyPeriodKind.year, now, [at(2015)]), 5);
    });
  });
}
