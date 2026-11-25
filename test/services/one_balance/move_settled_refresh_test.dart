// A move's end refreshes exactly the accounts it touched, once per burst,
// never inside the caller's stack. Pure: no provider scope is bound.
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/settlement_operation.dart' show SettlementFlow;
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/services/one_balance/money_movement_route.dart';
import 'package:kute/services/one_balance/move_settled_refresh.dart';

const _b = MoneyMovementAccount.bitcoin;
const _d = MoneyMovementAccount.dollars;
const _i = MoneyMovementAccount.investing;
const _p = MoneyMovementAccount.predictions;

SwapOrder _row({
  required String fromNet,
  required String fromCoin,
  required String toNet,
  required String toCoin,
}) =>
    SwapOrder(
      id: 'ord_1',
      coinFrom: fromCoin,
      networkFrom: fromNet,
      coinTo: toCoin,
      networkTo: toNet,
      depositAddress: 'dep',
      depositAmount: '5',
      withdrawalAmount: '4.9',
      status: 'success',
      timestamp: 0,
      withdrawalAddress: 'to',
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: 'from',
      provider: 'Orchestra',
    );

void main() {
  setUp(MoveSettledRefresh.debugReset);
  tearDown(MoveSettledRefresh.debugReset);

  test('a leg names its cash account; anything else names none', () {
    expect(MoveSettledRefresh.accountOf(network: 'SPARK', asset: 'BTC'), _b);
    expect(MoveSettledRefresh.accountOf(network: 'spark', asset: 'USDB'), _d);
    expect(
        MoveSettledRefresh.accountOf(network: 'HYPERCORE', asset: 'USDC'), _i);
    expect(
        MoveSettledRefresh.accountOf(network: 'POLYGON', asset: 'USDC.e'), _p);
    expect(MoveSettledRefresh.accountOf(network: 'POLYGON', asset: 'USDC'), _p);
    expect(MoveSettledRefresh.accountOf(network: 'POLYGON', asset: 'pUSD'), _p);
    expect(MoveSettledRefresh.accountOf(network: 'TRON', asset: 'USDT'),
        isNull);
    expect(MoveSettledRefresh.accountOf(network: 'POLYGON', asset: 'MATIC'),
        isNull);
  });

  test('a row names both of its ends', () {
    expect(
        MoveSettledRefresh.accountsOfRow(_row(
            fromNet: 'POLYGON',
            fromCoin: 'USDC.e',
            toNet: 'SPARK',
            toCoin: 'BTC')),
        {_p, _b});
    expect(
        MoveSettledRefresh.accountsOfRow(_row(
            fromNet: 'HYPERCORE',
            fromCoin: 'USDC',
            toNet: 'POLYGON',
            toCoin: 'USDC.e')),
        {_i, _p});
    expect(
        MoveSettledRefresh.accountsOfRow(_row(
            fromNet: 'SPARK', fromCoin: 'USDB', toNet: 'SPARK', toCoin: 'BTC')),
        {_d, _b});
    // An external destination: only the spending side reads again.
    expect(
        MoveSettledRefresh.accountsOfRow(_row(
            fromNet: 'SPARK', fromCoin: 'BTC', toNet: 'TRON', toCoin: 'USDT')),
        {_b});
  });

  test('every move flow between the four accounts names both ends', () {
    final expected = <SettlementFlow, Set<MoneyMovementAccount>>{
      SettlementFlow.moveUsdToBtc: {_p, _b},
      SettlementFlow.moveBtcToPredictions: {_b, _p},
      SettlementFlow.moveBtcToInvesting: {_b, _i},
      SettlementFlow.sparkToInvestingDirect: {_b, _d, _i},
      SettlementFlow.moveInvestingToBtc: {_i, _b},
      SettlementFlow.investingToSparkDirect: {_i, _b},
      SettlementFlow.investingToBtcCctp: {_i, _b},
      SettlementFlow.moveBtcToUsdc: {_b, _d},
      SettlementFlow.moveDollarsToBtc: {_d, _b},
      SettlementFlow.moveUsdToPredictions: {_d, _p},
      SettlementFlow.moveUsdToInvesting: {_d, _i},
      SettlementFlow.movePredictionsToDollars: {_p, _d},
      SettlementFlow.investingToSparkUsdDirect: {_i, _d},
      SettlementFlow.investingToDollarsCctp: {_i, _d},
      SettlementFlow.movePredictionsToInvesting: {_p, _i},
      SettlementFlow.investingToPredictionsDirect: {_i, _p},
      SettlementFlow.investingToPredictionsCctp: {_i, _p},
      SettlementFlow.predictionsDeposit: {_b, _p},
      SettlementFlow.predictionsWithdraw: {_p, _b},
      SettlementFlow.predictionsBtcRoute: {_b, _p},
    };
    for (final entry in expected.entries) {
      expect(MoveSettledRefresh.accountsOfFlow(entry.key), entry.value,
          reason: entry.key.name);
    }
    for (final flow in [
      SettlementFlow.sendExternal,
      SettlementFlow.ledgerBtcToInvesting,
      SettlementFlow.predictionsToLedgerBtc,
      SettlementFlow.unknown,
    ]) {
      expect(MoveSettledRefresh.accountsOfFlow(flow), isEmpty,
          reason: flow.name);
    }
    // Every pair the sheet plans has both of its ends named.
    for (final route in MoneyMovementRoute.all) {
      final flow = moneyMovementPlanFor(route).flow;
      expect(MoveSettledRefresh.accountsOfFlow(flow),
          containsAll({route.from, route.to}),
          reason: route.code);
    }
  });

  test('calls landing together run one deferred pass over their union',
      () async {
    MoveSettledRefresh.debounce = const Duration(milliseconds: 20);
    final runs = <Set<MoneyMovementAccount>>[];
    MoveSettledRefresh.debugRunner = (accounts) async => runs.add(accounts);
    final seen = <(Set<MoneyMovementAccount>, String)>[];
    MoveSettledRefresh.debugObserver = (a, s) => seen.add((a, s));

    MoveSettledRefresh.settled({_p, _b}, source: 'orchestra_row');
    MoveSettledRefresh.settledFlow(SettlementFlow.moveUsdToInvesting,
        source: 'reconciler');
    MoveSettledRefresh.settled(const {}, source: 'nothing');
    // Nothing runs on the caller's stack.
    expect(runs, isEmpty);
    expect(seen.map((e) => e.$2), ['orchestra_row', 'reconciler']);

    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(runs, [
      {_p, _b, _d, _i}
    ]);

    // A later call is its own pass.
    MoveSettledRefresh.settled({_i}, source: 'cctp');
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(runs, hasLength(2));
    expect(runs.last, {_i});
  });

  test('without a bound scope a call only records: nothing throws', () async {
    MoveSettledRefresh.debounce = const Duration(milliseconds: 10);
    MoveSettledRefresh.settled({_p}, source: 'unbound');
    await Future<void>.delayed(const Duration(milliseconds: 40));
  });
}
