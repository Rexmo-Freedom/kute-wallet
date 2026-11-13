// The Dollars hero's figures (founder, 4 November 2026: "Balance wrong in
// dollars. It should show invested and available in a good way at the
// bottom"):
//
//   * a bet funded from Dollars fires the moment its venue is credited,
//     while the move's Orchestra row can still read pending: once the
//     order is placed its money is the position (Invested), never in
//     flight as well (the total read the bet twice until Orchestra caught
//     up);
//   * a Bitcoin leg straight into a venue is in flight at the dollars it
//     delivers, never at its bitcoin figure;
//   * "Invested $X · Available $Y" under the total adds up to the total
//     printed, to the cent, in the currency on screen, less what the
//     in-flight lines under it name.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/one_balance_provider.dart';
import 'package:kute/providers/unified_balances_provider.dart';
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/venue_sweeper.dart'
    show VenueSweeperState;

final _now = DateTime.now();

SwapOrder _row({
  required String id,
  String coinFrom = 'USDB',
  String networkFrom = 'SPARK',
  String coinTo = 'USDC.e',
  String networkTo = 'POLYGON',
  String depositAmount = '5',
  String withdrawalAmount = '4.98',
  String status = 'exchanging',
}) =>
    SwapOrder(
      id: id,
      coinFrom: coinFrom,
      networkFrom: networkFrom,
      coinTo: coinTo,
      networkTo: networkTo,
      depositAddress: 'd',
      depositAmount: depositAmount,
      withdrawalAmount: withdrawalAmount,
      status: status,
      timestamp:
          _now.subtract(const Duration(seconds: 40)).millisecondsSinceEpoch,
      withdrawalAddress: 'r',
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: 'f',
      provider: 'Orchestra',
    );

FundedOrderRecord _record(FundedOrderStage stage,
        {Set<String> venueRows = const {'move'},
        Set<String> btcRows = const {},
        bool cleared = false}) =>
    FundedOrderRecord(
      id: 'fo_1',
      label: const FundedOrderLabel(
          venue: OneBalanceVenue.predictions,
          orderUsd: 5,
          side: 'Yes',
          market: 'Lakers',
          marketKey: 'tok'),
      stage: stage,
      createdAt: _now,
      updatedAt: _now,
      venueRowIds: venueRows,
      btcRowIds: btcRows,
      cleared: cleared,
    );

List<InFlightMove> _moves(List<SwapOrder> rows,
        List<FundedOrderRecord> records) =>
    inFlightMovesFrom(
      rows,
      walletId: null,
      nowMs: _now.millisecondsSinceEpoch,
      orderOf: (id) =>
          FundedOrdersNotifier.liveOwnerOf(records, id)?.toInFlightOrder(),
      placedOrderRow: (id) =>
          FundedOrdersNotifier.placedOrderOwns(records, id),
    );

void main() {
  group('placedOrderOwns', () {
    test('only an order its own run placed', () {
      expect(
          FundedOrdersNotifier.placedOrderOwns(
              [_record(FundedOrderStage.done)], 'move'),
          isTrue);
      expect(
          FundedOrdersNotifier.placedOrderOwns(
              [_record(FundedOrderStage.done, btcRows: {'btc'})], 'btc'),
          isTrue);
      for (final stage in [
        FundedOrderStage.adding,
        FundedOrderStage.preparing,
        FundedOrderStage.placing,
        FundedOrderStage.ready,
        FundedOrderStage.failed,
      ]) {
        expect(
            FundedOrdersNotifier.placedOrderOwns([_record(stage)], 'move'),
            isFalse,
            reason: '$stage');
      }
      // A "Tap to place" note a newer try closed is not a placed order.
      expect(
          FundedOrdersNotifier.placedOrderOwns(
              [_record(FundedOrderStage.done, cleared: true)], 'move'),
          isFalse);
      expect(
          FundedOrdersNotifier.placedOrderOwns(
              [_record(FundedOrderStage.done)], 'other'),
          isFalse);
    });
  });

  group('inFlightMovesFrom', () {
    test('the move of an order still on its way is in flight, named', () {
      final moves =
          _moves([_row(id: 'move')], [_record(FundedOrderStage.placing)]);
      expect(moves, hasLength(1));
      expect(moves.single.kind, InFlightKind.toVenue);
      expect(moves.single.usd, 5);
      expect(moves.single.order?.id, 'fo_1');
    });

    test('the move of an order already placed is not in flight any more',
        () {
      expect(_moves([_row(id: 'move')], [_record(FundedOrderStage.done)]),
          isEmpty);
    });

    test('a stopped order\'s money on its way to the venue stays in flight',
        () {
      // Not placed: its money stays at the venue as cash, which the venue
      // read does not count while the move is pending.
      final moves =
          _moves([_row(id: 'move')], [_record(FundedOrderStage.ready)]);
      expect(moves.single.usd, 5);
      expect(moves.single.order, isNull);
    });

    test('a sweep home is never dropped by a placed order', () {
      final moves = _moves([
        _row(
            id: 'move',
            coinFrom: 'USDC.e',
            networkFrom: 'POLYGON',
            coinTo: 'USDB',
            networkTo: 'SPARK',
            withdrawalAmount: '3'),
      ], [
        _record(FundedOrderStage.done)
      ]);
      expect(moves.single.kind, InFlightKind.fromVenue);
      expect(moves.single.usd, 3);
    });

    test('a Bitcoin leg straight into a venue counts the dollars it delivers',
        () {
      final moves = _moves([
        _row(
            id: 'direct',
            coinFrom: 'BTC',
            depositAmount: '0.00008',
            withdrawalAmount: '7.42'),
      ], const []);
      expect(moves.single.kind, InFlightKind.toVenue);
      expect(moves.single.usd, 7.42,
          reason: 'never the bitcoin figure read as dollars');
    });
  });

  group('the hero total', () {
    OneBalanceState header(List<FundedOrderRecord> records,
            {double investedInPredictions = 0}) =>
        oneBalanceStateFrom(
          dollarsUsd: 20,
          venues: UnifiedVenueBalances(
            investedInPredictionsUsd: investedInPredictions,
            investingKnown: true,
            predictionsKnown: true,
          ),
          inFlight: _moves([_row(id: 'move')], records),
          sweeper: const VenueSweeperState(),
        );

    test('a five dollar bet from Dollars counts once, before and after it fills',
        () {
      // Dollars were 25: $5 left for Predictions.
      final moving = header([_record(FundedOrderStage.preparing)]);
      expect(moving.totalUsd, 25);
      // Placed and filled at $4.98 while Orchestra still says the move is
      // under way: the position, once.
      final placed =
          header([_record(FundedOrderStage.done)], investedInPredictions: 4.98);
      expect(placed.totalUsd, closeTo(24.98, 1e-9),
          reason: 'never 29.98: the bet in flight and held');
      expect(placed.investedUsd, closeTo(4.98, 1e-9));
    });
  });

  group('oneBalanceSplit', () {
    int cents(double usd, [double rate = 1]) => (usd * rate * 100).round();

    test('Invested and Available add up to the total, to the cent', () {
      final split = oneBalanceSplit(totalUsd: 1234.567, investedUsd: 800.004);
      expect(split.investedUsd, 800.00);
      expect(split.availableUsd, closeTo(434.57, 1e-9));
      expect(cents(split.investedUsd) + cents(split.availableUsd),
          cents(1234.567));
    });

    test('the money on the in-flight lines is left out of Available', () {
      final split = oneBalanceSplit(
          totalUsd: 30, investedUsd: 10, onLinesUsd: 5);
      expect(split.investedUsd, 10);
      expect(split.availableUsd, 15);
    });

    test('in another currency the printed figures still add up', () {
      const rate = 0.9271;
      for (final (total, invested) in [
        (100.0, 33.333),
        (19.99, 9.995),
        (1.005, 0.005),
        (12345.678, 9876.543),
      ]) {
        final split = oneBalanceSplit(
            totalUsd: total, investedUsd: invested, rate: rate);
        expect(cents(split.investedUsd, rate) + cents(split.availableUsd, rate),
            cents(total, rate),
            reason: '$total = $invested + the rest');
      }
    });

    test('never negative, never more than the total', () {
      final over = oneBalanceSplit(totalUsd: 10, investedUsd: 12);
      expect(over.investedUsd, 10);
      expect(over.availableUsd, 0);
      final lines = oneBalanceSplit(
          totalUsd: 10, investedUsd: 4, onLinesUsd: 50);
      expect(lines.availableUsd, 0);
      final broken = oneBalanceSplit(
          totalUsd: double.nan, investedUsd: double.infinity);
      expect(broken.investedUsd, 0);
      expect(broken.availableUsd, 0);
    });

    test('money on its way into an order is Invested, never a line', () {
      const state = OneBalanceState(
        dollarsUsd: 10,
        investedUsd: 4,
        inFlight: [
          InFlightMove(
              kind: InFlightKind.toVenue,
              venue: OneBalanceVenue.predictions,
              usd: 5,
              order: InFlightOrder(
                  id: 'fo_bet',
                  venue: OneBalanceVenue.predictions,
                  orderUsd: 5,
                  side: 'Yes',
                  market: 'Lakers')),
        ],
      );
      expect(state.onLinesUsd, 0);
      expect(state.forOrdersUsd, 5);
      final split = oneBalanceSplit(
          totalUsd: state.totalUsd,
          investedUsd: state.investedUsd,
          forOrdersUsd: state.forOrdersUsd,
          onLinesUsd: state.onLinesUsd);
      expect(state.totalUsd, 19);
      expect(split.investedUsd, 9);
      expect(split.availableUsd, 10);
    });

    test('the state names what its lines carry: lined moves and waiting', () {
      const state = OneBalanceState(
        dollarsUsd: 10,
        investedUsd: 4,
        inFlight: [
          // A sweep home: plumbing, no line, stays in Available.
          InFlightMove(
              kind: InFlightKind.fromVenue,
              venue: OneBalanceVenue.investing,
              usd: 3),
          InFlightMove(kind: InFlightKind.incomingDollars, usd: 2),
        ],
        waiting: {OneBalanceVenue.predictions: 1.5},
      );
      expect(state.onLinesUsd, 3.5);
      final split = oneBalanceSplit(
          totalUsd: state.totalUsd,
          investedUsd: state.investedUsd,
          onLinesUsd: state.onLinesUsd);
      expect(state.totalUsd, 20.5);
      expect(split.investedUsd, 4);
      expect(split.availableUsd, 13,
          reason: 'Dollars 10 and the sweep on its way home, 3');
    });
  });
}
