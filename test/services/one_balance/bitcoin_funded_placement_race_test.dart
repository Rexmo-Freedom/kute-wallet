// An Investing order funded from Dollars is queued (`awaitingBalance`)
// BEFORE its move is sent, so the auto-fire may place it while the move
// is still being awaited (a long `SettlementFundingUnknown` while the
// credit lands): placed, reported done and cleared before the ticket
// followed it. The funded record must say placed, never "failed" for an
// order that was placed (the founder's "placed, then an error").

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/auth_grant_registry.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/pending_hyperliquid_order_provider.dart';
import 'package:kute/services/one_balance/bitcoin_funded_order.dart';
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/order_funding.dart';
import 'package:kute/services/one_balance/venue_funder.dart';

const _market = HlMarket(
  coin: 'BTC',
  wireCoin: 'BTC',
  assetId: 0,
  kind: HlMarketKind.perp,
  szDecimals: 5,
  maxLeverage: 40,
  onlyIsolated: false,
  markPx: 60000,
  midPx: 60000,
  prevDayPx: 60000,
  dayNtlVlm: 0,
);

const _order = FundedOrderLabel(
  venue: OneBalanceVenue.investing,
  orderUsd: 20,
  side: 'Long',
  market: 'BTC',
  marketKey: 'BTC',
);

/// A funding move the test answers when it says so.
class _Controller implements OrderFundingController {
  final answer = Completer<OrderFundingOutcome>();

  @override
  Future<OrderFundingOutcome> fundAndQueue({
    required OneBalanceVenue venue,
    required double orderUsd,
    required double requiredUsd,
    required double readyUsd,
    required MoveAuthorization auth,
    void Function(OrderFundingStage)? onStage,
    double? fundUsd,
    String? entrySource,
    String purpose = 'order_funding',
    bool keepUnconfirmed = false,
    bool continueJourney = false,
    String? marketKind,
  }) =>
      answer.future;

  @override
  OrderFundingController withDollars(double Function() dollarsUsd) => this;
}

PendingHlOrderIntent _intent() => PendingHlOrderIntent(
      coin: 'BTC',
      kind: HlMarketKind.perp,
      isLong: true,
      marginUsd: 20,
      leverage: 1,
      slippagePct: 1,
      expectedPx: 60000,
      marketLabel: 'BTC · Perp',
      market: _market,
      placement: PendingHlOrderPlacement(
        intentAt: (m) => HlIntents.openPosition(
          walletId: 'w1',
          market: _market,
          isLong: true,
          marginUsd: m,
          leverage: 1,
          slippagePct: 1,
        ),
        placeAt: (g, m) => throw UnimplementedError(),
        resizable: true,
      ),
      fundUsd: 20.03,
      requiredUsd: 20.26,
      arrivingUsd: 20.26,
    );

const _funded = OrderFundingFunded(VenueMoveResult(
    quoteId: 'q1', orderId: 'o1', sentUsd: 20.03, arrivingUsdEstimate: 20));

void main() {
  late ProviderContainer c;
  late BitcoinFundedOrderRunner runner;
  late PendingHyperliquidOrderNotifier pending;
  late AuthGrant grant;

  setUp(() {
    FundedOrdersNotifier.persist = false;
    c = ProviderContainer();
    runner = c.read(bitcoinFundedOrderRunnerProvider);
    pending = c.read(pendingHyperliquidOrderProvider.notifier);
    grant = AuthGrantRegistry.instance.issueAutofire(
      kPendingHlOrderAutofireId,
      pendingHlOrderAutofireIntent(_intent(), _market, walletId: 'w1'),
      method: AuthGrantMethod.pin,
    );
  });
  tearDown(() {
    AuthGrantRegistry.instance.cancelAutofire(kPendingHlOrderAutofireId);
    c.dispose();
    FundedOrdersNotifier.persist = true;
  });

  FundedOrderRecord rec(String id) =>
      c.read(fundedOrdersProvider.notifier).byId(id)!;

  /// The auto-fire's placement, while the move is still awaited.
  void placedMeanwhile() {
    expect(pending.state?.status, PendingHlOrderStatus.awaitingBalance);
    pending.updateStatus(PendingHlOrderStatus.placing);
    pending.updateStatus(PendingHlOrderStatus.done);
    // A finished order is reported, then cleared.
    expect(c.read(pendingHyperliquidOrderProvider), isNull);
  }

  Future<OrderFundingOutcome> queue(_Controller controller, String? id) =>
      pending.fundAndQueue(_intent(),
          grant: grant,
          controller: controller,
          orderUsd: 20,
          requiredUsd: 20.26,
          readyUsd: 0,
          fundedRunId: id);

  group('placed and cleared before the ticket followed it', () {
    for (final (name, answer) in [
      ('the move unconfirmed', const OrderFundingUnconfirmed()),
      ('the move funded', _funded),
      ('nothing had to move', const OrderFundingNotNeeded()),
    ]) {
      test('$name: followed late, the record is done, never failed', () async {
        final controller = _Controller();
        final id = runner.beginFunded(_order);
        final outcome = queue(controller, id);
        placedMeanwhile();
        controller.answer.complete(answer);
        final got = await outcome;
        runner.followFunded(id,
            move: got is OrderFundingFunded ? got.move : null);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        final r = rec(id);
        expect(r.reason, isNot('placement'));
        expect(r.stage, FundedOrderStage.done);
      });
    }

    test(
        'an order queued without its run\'s id (another chain): its own '
        'outcome on the market since the run began, done', () async {
      final controller = _Controller();
      final id = runner.beginFunded(_order);
      final outcome = queue(controller, null);
      placedMeanwhile();
      controller.answer.complete(const OrderFundingUnconfirmed());
      await outcome;
      runner.followFunded(id);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(rec(id).stage, FundedOrderStage.done);
    });

    test('the ticket\'s wait attached before the move: done', () async {
      final controller = _Controller();
      final id = runner.beginFunded(_order);
      final watch = runner.watchPlacement(id);
      final outcome = queue(controller, id);
      placedMeanwhile();
      controller.answer.complete(const OrderFundingUnconfirmed());
      await outcome;
      runner.followFunded(id, watch: watch);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(rec(id).stage, FundedOrderStage.done);
    });
  });

  test('refused while the move was awaited: still failed, with its words',
      () async {
    final controller = _Controller();
    final id = runner.beginFunded(_order);
    final watch = runner.watchPlacement(id);
    final outcome = queue(controller, id);
    pending.updateStatus(PendingHlOrderStatus.placing);
    pending.updateStatus(PendingHlOrderStatus.failed,
        errorMessage: 'Order rejected.');
    controller.answer.complete(_funded);
    await outcome;
    runner.followFunded(id, move: _funded.move, watch: watch);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    final r = rec(id);
    expect(r.stage, FundedOrderStage.failed);
    expect(r.reason, 'placement');
    expect(r.message, 'Order rejected.');
  });

  test('dropped without a verdict (the move refused): not placed', () async {
    final controller = _Controller();
    final id = runner.beginFunded(_order);
    final outcome = queue(controller, id);
    controller.answer.complete(const OrderFundingRefused('no_route'));
    await outcome;
    expect(c.read(pendingHyperliquidOrderProvider), isNull);
    // Followed anyway: nothing was placed, so it does not say placed.
    runner.followFunded(id);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(rec(id).stage, FundedOrderStage.failed);
  });

  test('another run\'s placed order is never taken for this one', () async {
    final first = _Controller();
    final old = runner.beginFunded(_order);
    final firstOutcome = queue(first, old);
    placedMeanwhile();
    first.answer.complete(const OrderFundingUnconfirmed());
    await firstOutcome;
    // A new order on the same market, its intent dropped unplaced.
    final second = _Controller();
    final id = runner.beginFunded(_order);
    final outcome = queue(second, id);
    second.answer.complete(const OrderFundingRefused('no_route'));
    await outcome;
    runner.followFunded(id);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(rec(id).stage, FundedOrderStage.failed);
  });

  test('a watch the ticket let go never ends the record', () async {
    final id = runner.beginFunded(_order);
    final watch = runner.watchPlacement(id);
    watch.cancel();
    expect(await watch.placed, isFalse);
    expect(rec(id).stage, FundedOrderStage.preparing);
  });
}
