// Money an accepted order has spoken for (committed_funds.dart): a bet
// and an Investing order accepted at nearly the same time never both count
// the same Dollars. With Dollars for only one, the second is refused
// before anything of it moves (the Dollars door); with Dollars for both,
// both go and every commitment is released once its money has left (or
// its order is over), so Available never stays understated.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/services/one_balance/committed_funds.dart';
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/money_steps.dart' show MoneyPlace;
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/order_funding.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/tracking_service.dart';

/// A venue funder whose move waits for the test ([release]) once asked:
/// two orders' moves can be in flight at once.
class _GatedFunder implements VenueFunder {
  _GatedFunder(this.onSent);

  /// What a sent move does to Dollars (the test's balance).
  final void Function(double usd) onSent;
  final asked = <double>[];
  final sent = <double>[];
  Completer<void>? _gate;
  Object? error;

  void hold() => _gate = Completer<void>();
  void release() => _gate?.complete();

  @override
  Future<VenueMoveResult> fund({
    required double usd,
    required MoveAuthorization auth,
    String purpose = 'order_funding',
  }) async {
    asked.add(usd);
    final gate = _gate;
    if (gate != null) await gate.future;
    final e = error;
    if (e != null) throw e;
    sent.add(usd);
    onSent(usd);
    return VenueMoveResult(
        quoteId: 'q', orderId: 'o', sentUsd: usd, arrivingUsdEstimate: usd);
  }

  @override
  Future<VenueMoveQuote> estimate(double usd) async => VenueMoveQuote(
      arrivingUsd: usd,
      feeUsd: 0,
      fixedCostUsd: 0,
      minUsd: 1,
      maxUsd: double.infinity);

  @override
  Future<double> idleUsd() async => 0;

  @override
  Future<double> minimumUsd() async => 1;
}

AuthGrant _grant() => AuthGrants.issue(
      PmGrants.fundedBetReview(
        PmGrants.betReview(
          walletId: 'w',
          tokenId: 't',
          maxCostUsd: 10.2,
          worstPrice: 0.6,
          orderType: 'fak',
        ),
        fundUsd: 6,
        venue: IntentVenue.polymarket,
      ),
      method: AuthGrantMethod.biometric,
    );

const _bet = FundedOrderLabel(
  venue: OneBalanceVenue.predictions,
  orderUsd: 6,
  side: 'Yes',
  market: 'Will it rain?',
  marketKey: 'yes-token',
);

const _order = FundedOrderLabel(
  venue: OneBalanceVenue.investing,
  orderUsd: 6,
  side: 'Long',
  market: 'BTC',
  marketKey: 'BTC',
);

class _World {
  _World(double dollars) {
    this.dollars = StateProvider<double>((_) => dollars);
    c = ProviderContainer(overrides: [
      usdBalanceProvider.overrideWith((ref) => ref.watch(this.dollars)),
    ]);
    predictions = _GatedFunder((usd) => set(read - usd));
    investing = _GatedFunder((usd) => set(read - usd));
    controller = OrderFundingController(
      funderFor: (venue) => switch (venue) {
        OneBalanceVenue.predictions => predictions,
        OneBalanceVenue.investing => investing,
      },
      dollarsUsd: () => c.read(usdBalanceProvider),
      commitments: () => c.read(committedFundsProvider.notifier),
    );
  }

  late final StateProvider<double> dollars;
  late final ProviderContainer c;
  late final _GatedFunder predictions;
  late final _GatedFunder investing;
  late final OrderFundingController controller;

  double get read => c.read(dollars);
  void set(double usd) => c.read(dollars.notifier).state = usd;

  CommittedFundsNotifier get ledger => c.read(committedFundsProvider.notifier);
  FundedOrdersNotifier get runs => c.read(fundedOrdersProvider.notifier);

  /// What a NEW order sees of Dollars.
  double get forNewOrder => c.read(orderDollarsProvider);

  Future<OrderFundingOutcome> fund(OneBalanceVenue venue, double usd) =>
      controller.fundAndQueue(
        venue: venue,
        orderUsd: usd,
        requiredUsd: usd,
        readyUsd: 0,
        auth: UserGrantAuthorization(_grant()),
        fundUsd: usd,
      );
}

Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late DateTime now;

  setUp(() {
    FundedOrdersNotifier.persist = false;
    OrderFundingJourney.reset();
    now = DateTime.utc(2026, 11, 10, 12);
    CommittedFundsNotifier.clock = () => now;
    TrackingService.debugTrackObserver = (_, __) {};
  });

  tearDown(() {
    FundedOrdersNotifier.persist = true;
    CommittedFundsNotifier.resetClock();
    TrackingService.debugTrackObserver = null;
  });

  group('Dollars for only one of them', () {
    test(
        'a bet accepted first holds its \$6: the Investing order accepted '
        'next is refused before any send, and sees only the rest', () async {
      final w = _World(10);
      addTearDown(w.c.dispose);
      // The bet's accept: its Dollars are its own from now.
      final betRun = w.runs.start(_bet, stage: FundedOrderStage.preparing);
      expect(
          w.ledger.commitDollars(OneBalanceVenue.predictions,
              usd: 6, runId: betRun),
          isTrue);
      // What the Investing slip shows and sizes on: the rest, not $10.
      expect(w.forNewOrder, closeTo(4, 1e-9));
      // The order's accept: refused, nothing held, nothing sent.
      expect(
          w.ledger.commitDollars(OneBalanceVenue.investing, usd: 6), isFalse);
      expect(w.ledger.dollarsShortUsd(OneBalanceVenue.investing, 6), 2);
      // Even reaching the controller it is refused before its funder.
      final order = await w.fund(OneBalanceVenue.investing, 6);
      expect(order, isA<OrderFundingNeedsDollars>());
      expect((order as OrderFundingNeedsDollars).shortfallUsd, 2);
      expect(w.investing.asked, isEmpty);
      // The bet's own move goes through: its share is its own.
      final bet = await w.fund(OneBalanceVenue.predictions, 6);
      expect(bet, isA<OrderFundingFunded>());
      expect(w.predictions.sent, [6]);
      expect(w.read, 4);
      // The reading shows the debit: nothing is held any more.
      expect(w.ledger.heldUsd(MoneyPlace.dollars), 0);
      expect(w.forNewOrder, 4);
    });

    test(
        'two moves in flight at the same moment: the second to check is '
        'refused before its funder is asked, never both sent', () async {
      final w = _World(10);
      addTearDown(w.c.dispose);
      w.predictions.hold();
      w.investing.hold();
      final bet = w.fund(OneBalanceVenue.predictions, 6);
      final order = w.fund(OneBalanceVenue.investing, 6);
      await _settle();
      // The first past its check holds its share; Dollars have not moved.
      expect(w.predictions.asked, [6]);
      expect(w.investing.asked, isEmpty);
      expect(await order, isA<OrderFundingNeedsDollars>());
      expect(w.forNewOrder, closeTo(4, 1e-9));
      w.predictions.release();
      w.investing.release();
      expect(await bet, isA<OrderFundingFunded>());
      expect(w.investing.sent, isEmpty);
      expect(w.read, 4);
      expect(w.forNewOrder, 4);
    });
  });

  test(
      'Dollars for both: both proceed, and every commitment is released '
      'once the reading shows its money left', () async {
    final w = _World(20);
    addTearDown(w.c.dispose);
    final betRun = w.runs.start(_bet, stage: FundedOrderStage.preparing);
    final orderRun = w.runs.start(_order, stage: FundedOrderStage.preparing);
    expect(
        w.ledger
            .commitDollars(OneBalanceVenue.predictions, usd: 6, runId: betRun),
        isTrue);
    expect(
        w.ledger
            .commitDollars(OneBalanceVenue.investing, usd: 6, runId: orderRun),
        isTrue);
    expect(w.forNewOrder, closeTo(8, 1e-9));
    // Both held as money into their orders, not Available.
    final inFlight = committedDollarsInFlight(w.c.read(committedFundsProvider),
        now: now, runs: w.c.read(fundedOrdersProvider));
    expect([
      for (final m in inFlight) (m.venue, m.usd, m.order?.id)
    ], [
      (OneBalanceVenue.predictions, 6.0, betRun),
      (OneBalanceVenue.investing, 6.0, orderRun),
    ]);
    w.predictions.hold();
    w.investing.hold();
    final bet = w.fund(OneBalanceVenue.predictions, 6);
    final order = w.fund(OneBalanceVenue.investing, 6);
    await _settle();
    expect(w.predictions.asked, [6]);
    expect(w.investing.asked, [6]);
    w.predictions.release();
    w.investing.release();
    expect(await bet, isA<OrderFundingFunded>());
    expect(await order, isA<OrderFundingFunded>());
    expect(w.read, 8);
    expect(w.ledger.heldUsd(MoneyPlace.dollars), 0);
    expect(w.forNewOrder, 8);
    w.ledger.refresh();
    expect(w.c.read(committedFundsProvider), isEmpty);
  });

  group('released on every end', () {
    test('a refused move (nothing left Dollars) releases at once', () async {
      final w = _World(10);
      addTearDown(w.c.dispose);
      expect(
          w.ledger.commitDollars(OneBalanceVenue.predictions, usd: 6), isTrue);
      w.predictions.error = const RouteUnavailable('no_route');
      final out = await w.fund(OneBalanceVenue.predictions, 6);
      expect(out, isA<OrderFundingRefused>());
      expect(w.forNewOrder, 10);
    });

    test('nothing needed from Dollars releases the accept-time hold', () async {
      final w = _World(10);
      addTearDown(w.c.dispose);
      w.ledger.commitDollars(OneBalanceVenue.investing, usd: 6);
      final out = await w.controller.fundAndQueue(
        venue: OneBalanceVenue.investing,
        orderUsd: 6,
        requiredUsd: 6,
        readyUsd: 6,
        auth: UserGrantAuthorization(_grant()),
      );
      expect(out, isA<OrderFundingNotNeeded>());
      expect(w.forNewOrder, 10);
    });

    test('the order placed, failed or stopped: its hold goes with its run', () {
      final w = _World(10);
      addTearDown(w.c.dispose);
      for (final end in [
        FundedOrderStage.done,
        FundedOrderStage.failed,
        FundedOrderStage.ready,
      ]) {
        final run = w.runs.start(_bet, stage: FundedOrderStage.preparing);
        w.ledger.commitDollars(OneBalanceVenue.predictions, usd: 6, runId: run);
        expect(w.forNewOrder, closeTo(4, 1e-9), reason: end.name);
        w.runs.setStage(run, end);
        expect(w.forNewOrder, 10, reason: end.name);
      }
      // Dropped outright (declined at the rail's own prompt).
      final run = w.runs.start(_bet, stage: FundedOrderStage.preparing);
      w.ledger.commitDollars(OneBalanceVenue.predictions, usd: 6, runId: run);
      w.runs.remove(run);
      expect(w.forNewOrder, 10);
    });

    test('a venue leg or a Bitcoin leg sent: its source is no longer held', () {
      final w = _World(10);
      addTearDown(w.c.dispose);
      w.ledger.hold(MoneyPlace.investing, OneBalanceVenue.predictions, usd: 4);
      w.ledger.hold(MoneyPlace.bitcoin, OneBalanceVenue.predictions, usd: 3);
      // The bet's own share is its own; another order sees it taken.
      expect(
          w.ledger.heldUsd(MoneyPlace.investing,
              exceptHeldOn: OneBalanceVenue.predictions),
          0);
      expect(
          w.ledger.heldUsd(MoneyPlace.investing,
              exceptHeldOn: OneBalanceVenue.investing),
          4);
      w.ledger.venueCashSent(OneBalanceVenue.investing);
      w.ledger.sourceSent(MoneyPlace.bitcoin);
      expect(w.ledger.heldUsd(MoneyPlace.investing), 0);
      expect(w.ledger.heldUsd(MoneyPlace.bitcoin), 0);
    });

    test(
        'Dollars that left but a reading that never moves: held at most '
        'the send hold', () async {
      final w = _World(10);
      addTearDown(w.c.dispose);
      // The rail sends without the test's balance moving.
      final funder = _GatedFunder((_) {});
      final controller = OrderFundingController(
        funderFor: (_) => funder,
        dollarsUsd: () => w.c.read(usdBalanceProvider),
        commitments: () => w.ledger,
      );
      await controller.fundAndQueue(
        venue: OneBalanceVenue.predictions,
        orderUsd: 6,
        requiredUsd: 6,
        readyUsd: 0,
        auth: UserGrantAuthorization(_grant()),
        fundUsd: 6,
      );
      expect(w.forNewOrder, closeTo(4, 1e-9));
      now = now.add(CommittedFundsNotifier.sentHold);
      w.ledger.refresh();
      expect(w.forNewOrder, 10);
    });

    test('nothing outlives the longest wait, bound or not', () {
      final w = _World(10);
      addTearDown(w.c.dispose);
      final run = w.runs.start(_order, stage: FundedOrderStage.preparing);
      w.ledger.commitDollars(OneBalanceVenue.investing, usd: 6, runId: run);
      w.ledger.commitDollars(OneBalanceVenue.predictions, usd: 2);
      expect(w.forNewOrder, closeTo(2, 1e-9));
      now = now.add(CommittedFundsNotifier.maxAge);
      w.ledger.refresh();
      expect(w.forNewOrder, 10);
    });

    test('a restart starts with nothing held', () {
      final w = _World(10);
      w.ledger.commitDollars(OneBalanceVenue.investing, usd: 6);
      w.c.dispose();
      final again = _World(10);
      addTearDown(again.c.dispose);
      expect(again.c.read(committedFundsProvider), isEmpty);
      expect(again.forNewOrder, 10);
    });
  });
}
