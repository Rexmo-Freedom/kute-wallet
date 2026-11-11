// A funded Investing order: queued behind its Dollars move, placed by the
// auto-fire once the venue holds the money (polled every second at first,
// or at once on the rail's credit), resized down only when it is a market
// order and the money visibly landed short, never when it is a limit
// order; and gone with its grant when the move was refused.

import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:hive_ce/hive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/auth_grant_registry.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart'
    show hyperliquidTradingModelProvider;
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/auth_provider.dart' show sessionUnlockedProvider;
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/pending_hyperliquid_order_provider.dart';
import 'package:kute/providers/placing_hyperliquid_order_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';
import 'package:kute/services/one_balance/committed_funds.dart';
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/money_steps.dart' show MoneyPlace;
import 'package:kute/services/one_balance/hyperliquid_move_rail.dart';
import 'package:kute/services/one_balance/hyperliquid_venue_funder.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/order_funding.dart';
import 'package:kute/services/one_balance/venue_cash_released.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/tracking_service.dart';

import '../helpers/fake_hyperliquid_move_rail.dart';

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

HlAccountSnapshot _snapshot(double withdrawable) => HlAccountSnapshot(
      accountValue: withdrawable,
      withdrawable: withdrawable,
      totalMarginUsed: 0,
      positions: const [],
      spotBalances: const [],
    );

/// The Investing account, answering the test's figure on every read.
class _Account extends HlAccountNotifier {
  _Account(this.read);
  final double Function() read;
  @override
  Future<HlAccountSnapshot> build() async => _snapshot(read());
}

/// The venue as the real account notifier reads it: counts every read,
/// each answering after [latency]; [fail] throws a 429.
class _Venue extends HyperliquidModel {
  _Venue(this.figure);
  final double Function() figure;
  final reads = <String>[];
  Duration latency = Duration.zero;
  bool fail = false;

  Future<HlAccountSnapshot> _read(String kind) async {
    reads.add(kind);
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (fail) {
      throw HyperliquidInfoException('info clearinghouseState failed',
          statusCode: 429);
    }
    return _snapshot(figure());
  }

  @override
  Future<HlAccountSnapshot> getPortfolioSnapshot(String address) =>
      _read('full');

  @override
  Future<HlAccountSnapshot> getCreditSnapshot(String address) =>
      _read('credit');
}

/// A controller that answers what the test says, after recording the ask.
class _Controller implements OrderFundingController {
  _Controller(this.answer);
  final Future<OrderFundingOutcome> Function() answer;
  final asks = <({double orderUsd, double requiredUsd, double readyUsd})>[];
  final fundUsds = <double?>[];
  final keptUnconfirmed = <bool>[];
  MoveAuthorization? auth;

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
  }) {
    expect(venue, OneBalanceVenue.investing);
    fundUsds.add(fundUsd);
    keptUnconfirmed.add(keepUnconfirmed);
    expect(purpose, 'order_funding');
    asks.add((orderUsd: orderUsd, requiredUsd: requiredUsd, readyUsd: readyUsd));
    this.auth = auth;
    onStage?.call(OrderFundingStage.quote);
    onStage?.call(OrderFundingStage.fund);
    return answer();
  }

  @override
  OrderFundingController withDollars(double Function() dollarsUsd) => this;
}

const _funded = OrderFundingFunded(VenueMoveResult(
    quoteId: 'q1', orderId: 'o1', sentUsd: 20.03, arrivingUsdEstimate: 20));

Settings _settings() => Settings(
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: false,
      biometricsEnabled: false,
      bitcoinElectrumNode: 'x',
      nodeType: 'x',
      reviewDone: true,
      activeWalletId: 'w1',
      wallets: [WalletConfig(id: 'w1', name: 'Hot')],
    );

/// The slip's handover: the order the auto-fire places at a margin, with
/// the margins it was placed at recorded.
class _Placement {
  _Placement({required this.resizable, this.result});
  final bool resizable;
  final HlOrderResult? result;
  final placed = <double>[];
  AuthGrant? grant;

  SensitiveIntent intentAt(double margin) => HlIntents.openPosition(
        walletId: 'w1',
        market: _market,
        isLong: true,
        marginUsd: margin,
        leverage: 1,
        slippagePct: 1,
      );

  PendingHlOrderPlacement get placement => PendingHlOrderPlacement(
        intentAt: intentAt,
        placeAt: (g, margin) async {
          grant = g;
          placed.add(margin);
          // The notifier consumes the grant against the exact order.
          GrantGuard.consume(g, intentAt(margin),
              allowed: const {SensitiveAction.hlOrder});
          return result ??
              HlOrderResult(
                  kind: HlOrderResultKind.filled,
                  oid: 7,
                  filledSz: margin / 60000,
                  avgPx: 60000);
        },
        resizable: resizable,
        cloid: 'c1',
      );
}

PendingHlOrderIntent _intent(_Placement placement,
        {double marginUsd = 20, String orderKind = 'market'}) =>
    PendingHlOrderIntent(
      coin: 'BTC',
      kind: HlMarketKind.perp,
      isLong: true,
      marginUsd: marginUsd,
      leverage: 1,
      slippagePct: 1,
      expectedPx: 60000,
      marketLabel: 'BTC · Perp',
      market: _market,
      placement: placement.placement,
      fundUsd: 20.03,
      // margin × 1.01 (slippage) × 1.0019 (fees)
      requiredUsd: marginUsd * 1.01 * 1.0019,
      readyAtQueueUsd: 0,
      arrivingUsd: marginUsd * 1.01 * 1.0019,
      orderKind: orderKind,
      quoteMs: 120,
    );

void main() {
  late FakeHyperliquidMoveRail rail;
  late double withdrawable;
  late List<(String, Map<String, Object?>?)> events;
  // Every state the pending order went through: a finished order is
  // reported, then cleared.
  late List<PendingHlOrderIntent?> history;
  PendingHlOrderIntent terminal() => history.lastWhere((s) =>
      s != null &&
      (s.status == PendingHlOrderStatus.done ||
          s.status == PendingHlOrderStatus.failed))!;

  setUp(() {
    rail = FakeHyperliquidMoveRail();
    withdrawable = 0;
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    AuthGrantRegistry.instance.cancelAutofire(kPendingHlOrderAutofireId);
  });

  tearDown(() {
    TrackingService.debugTrackObserver = null;
    AuthGrantRegistry.instance.cancelAutofire(kPendingHlOrderAutofireId);
    rail.creditedController.close();
  });

  ProviderContainer container(_Controller controller) {
    final c = ProviderContainer(overrides: [
      settingsProvider.overrideWith((_) => SettingsModel(_settings())),
      sessionUnlockedProvider.overrideWith((_) => true),
      hyperliquidAccountProvider
          .overrideWith(() => _Account(() => withdrawable)),
      hyperliquidMoveRailProvider.overrideWithValue(rail),
      orderFundingControllerProvider.overrideWithValue(controller),
    ]);
    addTearDown(c.dispose);
    // The slip bootstraps the watcher before it queues; so does the test.
    c.read(pendingHlOrderAutoFireProvider);
    history = [];
    c.listen(pendingHyperliquidOrderProvider, (_, n) => history.add(n));
    return c;
  }

  /// The confirm-time approval the slip stores: the order plus its funding.
  AuthGrant approve(PendingHlOrderIntent intent) =>
      AuthGrantRegistry.instance.issueAutofire(
        kPendingHlOrderAutofireId,
        pendingHlOrderAutofireIntent(intent, _market, walletId: 'w1'),
        method: AuthGrantMethod.pin,
      );

  test('the approval carries the dollars allowed to leave, the order does not',
      () {
    final placement = _Placement(resizable: true);
    final intent = _intent(placement);
    final approved =
        pendingHlOrderAutofireIntent(intent, _market, walletId: 'w1');
    expect(approved.limits[kFundUsdLimit], dollarsBaseUnits(20.03));
    expect(approved.limits[kFundVenueLimit], kFundVenueInvesting);
    final placed =
        pendingHlOrderPlacementIntent(intent, _market, walletId: 'w1');
    expect(placed.limits.containsKey(kFundUsdLimit), isFalse);
    // A smaller placement still sits under the approval.
    expect(
        AuthGrants.driftBetween(
            approved,
            pendingHlOrderAutofireIntent(intent, _market,
                walletId: 'w1', marginUsd: 15)),
        isEmpty);
  });

  test('queued, then placed with the full margin once the venue covers it',
      () {
    fakeAsync((async) {
      final controller = _Controller(() async => _funded);
      final c = container(controller);
      final placement = _Placement(resizable: true);
      final intent = _intent(placement);
      final grant = approve(intent);
      final notifier = c.read(pendingHyperliquidOrderProvider.notifier);
      OrderFundingOutcome? outcome;
      notifier
          .fundAndQueue(intent,
              grant: grant,
              controller: controller,
              orderUsd: 20,
              requiredUsd: intent.requiredUsd,
              readyUsd: 0)
          .then((o) => outcome = o);
      async.flushMicrotasks();
      expect(outcome, same(_funded));
      expect(controller.asks.single.orderUsd, 20);
      expect((controller.auth as UserGrantAuthorization).grant, same(grant));
      final queued = c.read(pendingHyperliquidOrderProvider)!;
      expect(queued.status, PendingHlOrderStatus.awaitingBalance);
      expect(queued.fundQuoteId, 'q1');
      expect(queued.fundOrderId, 'o1');
      expect(queued.fundedAt, isNotNull);
      expect(placement.placed, isEmpty);

      // Two seconds of nothing: still waiting, polled every second.
      async.elapse(const Duration(seconds: 2));
      expect(placement.placed, isEmpty);
      expect(c.read(pendingHyperliquidOrderProvider)!.status,
          PendingHlOrderStatus.awaitingBalance);

      // The money lands: the next tick places exactly the approved order.
      withdrawable = 20.5;
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(placement.placed, [20]);
      final done = terminal();
      expect(c.read(pendingHyperliquidOrderProvider), isNull);
      expect(done.status, PendingHlOrderStatus.done);
      expect(done.result?.oid, 7);
      expect(done.placedMarginUsd, 20);
      expect(AuthGrantRegistry.instance.hasAutofireGrant(kPendingHlOrderAutofireId),
          isFalse);
      expect(c.read(placingHyperliquidOrderProvider).single.cloid, 'c1');
      final completed =
          events.singleWhere((e) => e.$1 == 'order_funding_completed').$2!;
      expect(completed['venue'], 'hyperliquid');
      expect(completed['fund_usd'], 20.03);
      expect(completed['amount_usd'], 20);
      expect(completed['resized'], false);
      expect(completed['ms_quote'], 120);
      expect(completed['order_kind'], 'market');
      expect(events.any((e) => e.$1 == 'order_funding_failed'), isFalse);
    });
  });

  test('a market order whose money landed short goes out smaller', () {
    fakeAsync((async) {
      final controller = _Controller(() async => _funded);
      final c = container(controller);
      final placement = _Placement(resizable: true);
      final intent = _intent(placement);
      final grant = approve(intent);
      c
          .read(pendingHyperliquidOrderProvider.notifier)
          .fundAndQueue(intent,
              grant: grant,
              controller: controller,
              orderUsd: 20,
              requiredUsd: intent.requiredUsd,
              readyUsd: 0);
      async.flushMicrotasks();
      // $19.99 arrived for a $20.24 need: enough to tell it landed, not
      // enough for the order as typed.
      withdrawable = 19.99;
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(placement.placed, hasLength(1));
      final margin = placement.placed.single;
      expect(margin, lessThan(20));
      expect(margin, closeTo(19.99 / (1.01 * 1.0019), 0.011));
      expect(margin, greaterThanOrEqualTo(10));
      final done = terminal();
      expect(c.read(pendingHyperliquidOrderProvider), isNull);
      expect(done.status, PendingHlOrderStatus.done);
      expect(done.placedMarginUsd, margin);
      final completed =
          events.singleWhere((e) => e.$1 == 'order_funding_completed').$2!;
      expect(completed['resized'], true);
      expect(completed['amount_usd'], margin);
    });
  });

  test('placeableMargin: the approved margin, a resize, or nothing', () {
    final market = _intent(_Placement(resizable: true));
    expect(PendingHlOrderAutoFire.placeableMargin(market, 0), isNull);
    // Landed (≥ 90% of what was sized for) but short: resized.
    expect(PendingHlOrderAutoFire.placeableMargin(market, 19.99),
        closeTo(19.99 / (1.01 * 1.0019), 0.011));
    // Covers the need: the approved margin, never more.
    expect(PendingHlOrderAutoFire.placeableMargin(market, 25), 20);
    // A snapshot that has not caught up with the credit: nothing yet.
    expect(PendingHlOrderAutoFire.placeableMargin(market, 5), isNull);
    // Landed short of the venue minimum: nothing (the sweeper takes it).
    final small = _intent(_Placement(resizable: true), marginUsd: 10.5);
    expect(PendingHlOrderAutoFire.placeableMargin(small, 9.9), isNull);
    // A limit order is placed as approved or not at all.
    final limit = _intent(_Placement(resizable: false), orderKind: 'limit');
    expect(PendingHlOrderAutoFire.placeableMargin(limit, 19.99), isNull);
    expect(PendingHlOrderAutoFire.placeableMargin(limit, 20.3), 20);
  });

  test('a limit order that landed short keeps waiting, never resized', () {
    fakeAsync((async) {
      final controller = _Controller(() async => _funded);
      final c = container(controller);
      final placement = _Placement(
          resizable: false,
          result: const HlOrderResult(kind: HlOrderResultKind.resting, oid: 9));
      final intent = _intent(placement, orderKind: 'limit');
      final grant = approve(intent);
      c.read(pendingHyperliquidOrderProvider.notifier).fundAndQueue(intent,
          grant: grant,
          controller: controller,
          orderUsd: 20,
          requiredUsd: intent.requiredUsd,
          readyUsd: 0);
      async.flushMicrotasks();
      withdrawable = 19.99;
      async.elapse(const Duration(seconds: 5));
      async.flushMicrotasks();
      expect(placement.placed, isEmpty);
      expect(c.read(pendingHyperliquidOrderProvider)!.status,
          PendingHlOrderStatus.awaitingBalance);
      // The rest arrives: placed exactly as approved, resting.
      withdrawable = 20.3;
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(placement.placed, [20]);
      final done = terminal();
      expect(c.read(pendingHyperliquidOrderProvider), isNull);
      expect(done.status, PendingHlOrderStatus.done);
      expect(done.result?.kind, HlOrderResultKind.resting);
      expect(events.singleWhere((e) => e.$1 == 'order_funding_completed').$2![
          'order_kind'], 'limit');
    });
  });

  test('the rail\'s credit places the order at once, before the next tick',
      () {
    fakeAsync((async) {
      final controller = _Controller(() async => _funded);
      final c = container(controller);
      final placement = _Placement(resizable: true);
      final intent = _intent(placement);
      final grant = approve(intent);
      c.read(pendingHyperliquidOrderProvider.notifier).fundAndQueue(intent,
          grant: grant,
          controller: controller,
          orderUsd: 20,
          requiredUsd: intent.requiredUsd,
          readyUsd: 0);
      async.flushMicrotasks();
      expect(placement.placed, isEmpty);
      withdrawable = 21;
      rail.creditedController.add(null);
      async.flushMicrotasks();
      expect(placement.placed, [20]);
      expect(terminal().status, PendingHlOrderStatus.done);
      expect(c.read(pendingHyperliquidOrderProvider), isNull);
    });
  });

  group('a credit signal reads the account again now', () {
    // The header keeps the account alive: the 1 s tick reads its last
    // snapshot, not the venue, so the credit must ask for a fresh read.
    ProviderContainer held(_Controller controller) {
      final c = container(controller);
      c.listen(hyperliquidAccountProvider, (_, __) {});
      return c;
    }

    void queue(ProviderContainer c, _Controller controller,
        _Placement placement) {
      final intent = _intent(placement);
      c.read(pendingHyperliquidOrderProvider.notifier).fundAndQueue(intent,
          grant: approve(intent),
          controller: controller,
          orderUsd: 20,
          requiredUsd: intent.requiredUsd,
          readyUsd: 0);
    }

    test('Orchestra\'s delivery places the order on a fresh read at once',
        () {
      fakeAsync((async) {
        final controller = _Controller(() async => _funded);
        final c = held(controller);
        final placement = _Placement(resizable: true);
        queue(c, controller, placement);
        async.elapse(const Duration(seconds: 3));
        // The money landed; the snapshot on screen is from before it.
        withdrawable = 21;
        async.elapse(const Duration(seconds: 2));
        expect(placement.placed, isEmpty);
        c.read(pendingHlOrderAutoFireProvider).creditLanded();
        async.flushMicrotasks();
        expect(placement.placed, [20]);
        expect(terminal().status, PendingHlOrderStatus.done);
      });
    });

    test('a venue read that lags the credit is read again 1, 2 and 4 s on',
        () {
      fakeAsync((async) {
        final controller = _Controller(() async => _funded);
        final c = held(controller);
        final placement = _Placement(resizable: true);
        var built = 0;
        c.listen(hyperliquidAccountProvider, (_, n) {
          if (n.hasValue && !n.isLoading) built++;
        });
        queue(c, controller, placement);
        async.flushMicrotasks();
        c.read(pendingHlOrderAutoFireProvider).creditLanded();
        async.flushMicrotasks();
        expect(placement.placed, isEmpty);
        final afterCredit = built;
        // The venue shows the money 2.5 s after Orchestra said delivered:
        // the read 3 s on (1 s + 2 s) places it.
        async.elapse(const Duration(milliseconds: 2500));
        withdrawable = 21;
        expect(placement.placed, isEmpty);
        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();
        expect(placement.placed, [20]);
        expect(built, greaterThan(afterCredit));
        // Placed: no read is left pending.
        final settled = built;
        async.elapse(const Duration(seconds: 10));
        expect(built, settled);
      });
    });

    test('a ledger update on the venue\'s socket reads the account too', () {
      fakeAsync((async) {
        final controller = _Controller(() async => _funded);
        final c = held(controller);
        final placement = _Placement(resizable: true);
        queue(c, controller, placement);
        async.elapse(const Duration(seconds: 2));
        withdrawable = 21;
        async.elapse(const Duration(seconds: 1));
        expect(placement.placed, isEmpty);
        c.read(pendingHlOrderAutoFireProvider).accountMoved();
        async.flushMicrotasks();
        expect(placement.placed, [20]);
      });
    });

    test(
        'a ledger CREDIT whose account read lags places within 1 s, not on '
        'the 4 s tick', () {
      fakeAsync((async) {
        final controller = _Controller(() async => _funded);
        final c = held(controller);
        final placement = _Placement(resizable: true);
        queue(c, controller, placement);
        // Past the first 30 s the poll runs every 4 s: a credit the
        // socket reports between ticks used to wait for the next one.
        async.elapse(const Duration(seconds: 31));
        expect(placement.placed, isEmpty);
        final creditAt = async.elapsed;
        // The venue's ledger credits the deposit; its account read shows
        // the money 600 ms later.
        c.read(pendingHlOrderAutoFireProvider).accountMoved(credited: true);
        async.flushMicrotasks();
        expect(placement.placed, isEmpty, reason: 'the first read lagged');
        expect(c.read(pendingHyperliquidOrderProvider)!.readiness,
            HlReadiness.crediting,
            reason: 'a credit is a credit: the order is crediting, not '
                'waiting for funds');
        async.elapse(const Duration(milliseconds: 600));
        withdrawable = 21;
        async.elapse(const Duration(milliseconds: 400));
        async.flushMicrotasks();
        expect(placement.placed, [20]);
        final placedAfter = async.elapsed - creditAt;
        expect(placedAfter, const Duration(seconds: 1),
            reason: 'the follow-up read 1 s after the credit placed it; '
                'the next poll tick was 3 s further on');
        expect(
            placedAfter, lessThan(PendingHlOrderAutoFire.kAwaitSlowInterval));
        expect(terminal().status, PendingHlOrderStatus.done);
      });
    });

    test('a ledger update that credits nothing is one read, no follow-ups',
        () {
      fakeAsync((async) {
        final controller = _Controller(() async => _funded);
        final c = held(controller);
        final placement = _Placement(resizable: true);
        var built = 0;
        c.listen(hyperliquidAccountProvider, (_, n) {
          if (n.hasValue && !n.isLoading) built++;
        });
        queue(c, controller, placement);
        async.elapse(const Duration(seconds: 31));
        final before = built;
        c.read(pendingHlOrderAutoFireProvider).accountMoved();
        async.flushMicrotasks();
        expect(built, before + 1);
        expect(c.read(pendingHyperliquidOrderProvider)!.readiness,
            HlReadiness.waitingFunds);
        // Nothing before the next 4 s tick but that tick itself.
        async.elapse(const Duration(milliseconds: 3500));
        expect(built, before + 1);
      });
    });
  });

  test('a refused move clears the order and its grant; Dollars untouched',
      () {
    fakeAsync((async) {
      final controller = _Controller(
          () async => const OrderFundingRefused('route unavailable'));
      final c = container(controller);
      final placement = _Placement(resizable: true);
      final intent = _intent(placement);
      final grant = approve(intent);
      OrderFundingOutcome? outcome;
      c
          .read(pendingHyperliquidOrderProvider.notifier)
          .fundAndQueue(intent,
              grant: grant,
              controller: controller,
              orderUsd: 20,
              requiredUsd: intent.requiredUsd,
              readyUsd: 0)
          .then((o) => outcome = o);
      async.flushMicrotasks();
      expect(outcome, isA<OrderFundingRefused>());
      expect(c.read(pendingHyperliquidOrderProvider), isNull);
      expect(AuthGrantRegistry.instance.hasAutofireGrant(kPendingHlOrderAutofireId),
          isFalse);
      withdrawable = 50;
      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();
      expect(placement.placed, isEmpty);
    });
  });

  test('Dollars short of the move clears the order too', () {
    fakeAsync((async) {
      final controller =
          _Controller(() async => const OrderFundingNeedsDollars(4.5));
      final c = container(controller);
      final placement = _Placement(resizable: true);
      final intent = _intent(placement);
      final grant = approve(intent);
      c.read(pendingHyperliquidOrderProvider.notifier).fundAndQueue(intent,
          grant: grant,
          controller: controller,
          orderUsd: 20,
          requiredUsd: intent.requiredUsd,
          readyUsd: 0);
      async.flushMicrotasks();
      expect(c.read(pendingHyperliquidOrderProvider), isNull);
      expect(placement.placed, isEmpty);
    });
  });

  test('a controller error clears the order and reaches the caller', () {
    fakeAsync((async) {
      final controller = _Controller(() async => throw StateError('down'));
      final c = container(controller);
      final placement = _Placement(resizable: true);
      final intent = _intent(placement);
      final grant = approve(intent);
      Object? error;
      c
          .read(pendingHyperliquidOrderProvider.notifier)
          .fundAndQueue(intent,
              grant: grant,
              controller: controller,
              orderUsd: 20,
              requiredUsd: intent.requiredUsd,
              readyUsd: 0)
          .catchError((Object e) {
        error = e;
        return const OrderFundingNotNeeded();
      });
      async.flushMicrotasks();
      expect(error, isA<StateError>());
      expect(c.read(pendingHyperliquidOrderProvider), isNull);
      expect(AuthGrantRegistry.instance.hasAutofireGrant(kPendingHlOrderAutofireId),
          isFalse);
    });
  });

  test('the venue already covering it places the order straight away', () {
    fakeAsync((async) {
      final controller =
          _Controller(() async => const OrderFundingNotNeeded());
      final c = container(controller);
      final placement = _Placement(resizable: true);
      final intent = _intent(placement);
      final grant = approve(intent);
      withdrawable = 30;
      c.read(pendingHyperliquidOrderProvider.notifier).fundAndQueue(intent,
          grant: grant,
          controller: controller,
          orderUsd: 20,
          requiredUsd: intent.requiredUsd,
          readyUsd: 30);
      async.flushMicrotasks();
      expect(placement.placed, [20]);
      expect(terminal().status, PendingHlOrderStatus.done);
      expect(c.read(pendingHyperliquidOrderProvider), isNull);
    });
  });

  test('a failed placement reports the stage and keeps the money where it is',
      () {
    fakeAsync((async) {
      final controller = _Controller(() async => _funded);
      final c = container(controller);
      final placement = _Placement(resizable: true);
      final failing = PendingHlOrderPlacement(
        intentAt: placement.intentAt,
        placeAt: (g, m) async => throw StateError('Insufficient margin'),
        resizable: true,
        cloid: 'c1',
      );
      final intent = PendingHlOrderIntent(
        coin: 'BTC',
        kind: HlMarketKind.perp,
        isLong: true,
        marginUsd: 20,
        leverage: 1,
        slippagePct: 1,
        expectedPx: 60000,
        marketLabel: 'BTC · Perp',
        market: _market,
        placement: failing,
        fundUsd: 20.03,
        requiredUsd: 20.24,
        arrivingUsd: 20.24,
      );
      final grant = approve(intent);
      c.read(pendingHyperliquidOrderProvider.notifier).fundAndQueue(intent,
          grant: grant,
          controller: controller,
          orderUsd: 20,
          requiredUsd: 20.24,
          readyUsd: 0);
      async.flushMicrotasks();
      withdrawable = 25;
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      final failed = terminal();
      expect(c.read(pendingHyperliquidOrderProvider), isNull);
      expect(failed.status, PendingHlOrderStatus.failed);
      expect(failed.errorMessage, isNotEmpty);
      final event =
          events.singleWhere((e) => e.$1 == 'order_funding_failed').$2!;
      expect(event['stage'], 'order');
      expect(event['error_category'], 'insufficient_funds');
    });
  });

  test('the controller sends exactly the approved amount, never a re-plan',
      () {
    fakeAsync((async) {
      final controller = _Controller(() async => _funded);
      final c = container(controller);
      final intent = _intent(_Placement(resizable: true));
      c.read(pendingHyperliquidOrderProvider.notifier).fundAndQueue(intent,
          grant: approve(intent),
          controller: controller,
          orderUsd: 20,
          requiredUsd: intent.requiredUsd,
          readyUsd: 0.5);
      async.flushMicrotasks();
      expect(controller.fundUsds.single, 20.03);
      expect(controller.keptUnconfirmed.single, isTrue);
    });
  });

  test('a move the rail cannot confirm keeps the order queued and placed on '
      'arrival', () {
    fakeAsync((async) {
      final controller =
          _Controller(() async => const OrderFundingUnconfirmed());
      final c = container(controller);
      final placement = _Placement(resizable: true);
      final intent = _intent(placement);
      OrderFundingOutcome? outcome;
      c
          .read(pendingHyperliquidOrderProvider.notifier)
          .fundAndQueue(intent,
              grant: approve(intent),
              controller: controller,
              orderUsd: 20,
              requiredUsd: intent.requiredUsd,
              readyUsd: 0)
          .then((o) => outcome = o);
      async.flushMicrotasks();
      expect(outcome, isA<OrderFundingUnconfirmed>());
      final queued = c.read(pendingHyperliquidOrderProvider)!;
      expect(queued.status, PendingHlOrderStatus.awaitingBalance);
      expect(queued.fundedAt, isNotNull);
      expect(AuthGrantRegistry.instance.hasAutofireGrant(kPendingHlOrderAutofireId),
          isTrue);
      // A retry while it is queued is refused: nothing funds twice.
      final retry = _intent(_Placement(resizable: true));
      OrderFundingOutcome? second;
      c
          .read(pendingHyperliquidOrderProvider.notifier)
          .fundAndQueue(retry,
              grant: approve(intent),
              controller: controller,
              orderUsd: 20,
              requiredUsd: retry.requiredUsd,
              readyUsd: 0)
          .then((o) => second = o);
      async.flushMicrotasks();
      expect((second as OrderFundingRefused).reason, kHlOrderQueuedReason);
      expect(controller.asks, hasLength(1));
      // The money did move: it lands and the order goes out.
      withdrawable = 21;
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(placement.placed, [20]);
      expect(terminal().status, PendingHlOrderStatus.done);
    });
  });

  test('a finished order no longer holds the venue; a failure releases its '
      'cash', () {
    fakeAsync((async) {
      final released = <(OneBalanceVenue, String)>[];
      final sub = VenueCashReleased.stream.listen(released.add);
      addTearDown(sub.cancel);
      final controller = _Controller(() async => _funded);
      final c = container(controller);
      final failing = PendingHlOrderPlacement(
        intentAt: _Placement(resizable: true).intentAt,
        placeAt: (g, m) async => throw StateError('rejected'),
        resizable: true,
      );
      final intent = PendingHlOrderIntent(
        coin: 'BTC',
        kind: HlMarketKind.perp,
        isLong: true,
        marginUsd: 20,
        leverage: 1,
        slippagePct: 1,
        expectedPx: 60000,
        marketLabel: 'BTC · Perp',
        market: _market,
        placement: failing,
        fundUsd: 20.03,
        requiredUsd: 20.24,
        arrivingUsd: 20.24,
      );
      c.read(pendingHyperliquidOrderProvider.notifier).fundAndQueue(intent,
          grant: approve(intent),
          controller: controller,
          orderUsd: 20,
          requiredUsd: 20.24,
          readyUsd: 0);
      async.flushMicrotasks();
      expect(
          PendingHyperliquidOrderNotifier.isActive(
              c.read(pendingHyperliquidOrderProvider)),
          isTrue);
      withdrawable = 25;
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(c.read(pendingHyperliquidOrderProvider), isNull);
      expect(PendingHyperliquidOrderNotifier.isActive(null), isFalse);
      expect(released, [(OneBalanceVenue.investing, 'order_failed')]);
    });
  });

  test('a first order on a new account signs the builder approval after the '
      'money lands, before placing', () {
    fakeAsync((async) {
      final controller = _Controller(() async => _funded);
      final calls = <String>[];
      final c = ProviderContainer(overrides: [
        settingsProvider.overrideWith((_) => SettingsModel(_settings())),
        sessionUnlockedProvider.overrideWith((_) => true),
        hyperliquidAccountProvider
            .overrideWith(() => _Account(() => withdrawable)),
        hyperliquidMoveRailProvider.overrideWithValue(rail),
        orderFundingControllerProvider.overrideWithValue(controller),
        hlBuilderApprovalAfterFundingProvider.overrideWithValue(() async {
          calls.add('approve');
          return true;
        }),
      ]);
      addTearDown(c.dispose);
      c.read(pendingHlOrderAutoFireProvider);
      final placement = _Placement(resizable: true);
      final base = _intent(placement);
      final intent = PendingHlOrderIntent(
        coin: base.coin,
        kind: base.kind,
        isLong: base.isLong,
        marginUsd: base.marginUsd,
        leverage: base.leverage,
        slippagePct: base.slippagePct,
        expectedPx: base.expectedPx,
        marketLabel: base.marketLabel,
        market: _market,
        placement: PendingHlOrderPlacement(
          intentAt: placement.intentAt,
          placeAt: (g, m) {
            calls.add('place');
            return placement.placement.placeAt(g, m);
          },
          resizable: true,
        ),
        fundUsd: base.fundUsd,
        requiredUsd: base.requiredUsd,
        arrivingUsd: base.arrivingUsd,
        needsBuilderApproval: true,
      );
      c.read(pendingHyperliquidOrderProvider.notifier).fundAndQueue(intent,
          grant: approve(intent),
          controller: controller,
          orderUsd: 20,
          requiredUsd: intent.requiredUsd,
          readyUsd: 0);
      async.flushMicrotasks();
      expect(calls, isEmpty);
      withdrawable = 21;
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(calls, ['approve', 'place']);
      expect(
          events.singleWhere((e) => e.$1 == 'hl_builder_fee_after_funding').$2,
          {'approved': true});
    });
  });

  test(
      'an order held while its venue-cash legs run (awaitingDeposit) is never '
      'overwritten: a second funded order is refused before anything moves',
      () {
    fakeAsync((async) {
      FundedOrdersNotifier.persist = false;
      addTearDown(() => FundedOrdersNotifier.persist = true);
      final controller = _Controller(() async => _funded);
      final c = container(controller);
      final first = _intent(_Placement(resizable: true));
      final notifier = c.read(pendingHyperliquidOrderProvider.notifier);
      // The venue-cash path: held, never fired, while its legs run.
      notifier.setIntent(first);
      final run = c.read(fundedOrdersProvider.notifier).start(
          const FundedOrderLabel(
              venue: OneBalanceVenue.investing,
              orderUsd: 20,
              side: 'Long',
              market: 'BTC',
              marketKey: 'BTC'),
          stage: FundedOrderStage.preparing);
      // The guard every other state answers to said nothing here.
      expect(PendingHyperliquidOrderNotifier.isActive(first), isFalse);
      expect(
          PendingHyperliquidOrderNotifier.blocksNewOrder(
              c.read(pendingHyperliquidOrderProvider),
              c.read(fundedOrdersProvider)),
          isTrue);
      final second = _intent(_Placement(resizable: true), marginUsd: 10);
      OrderFundingOutcome? outcome;
      notifier
          .fundAndQueue(second,
              grant: approve(second),
              controller: controller,
              orderUsd: 10,
              requiredUsd: second.requiredUsd,
              readyUsd: 0)
          .then((o) => outcome = o);
      async.flushMicrotasks();
      expect((outcome as OrderFundingRefused).reason, kHlOrderQueuedReason);
      expect(controller.asks, isEmpty);
      expect(identical(c.read(pendingHyperliquidOrderProvider), first), isTrue);
      // Its own queue (the chain's Dollars share) still goes.
      notifier
          .fundAndQueue(first,
              grant: approve(first),
              controller: controller,
              orderUsd: 20,
              requiredUsd: first.requiredUsd,
              readyUsd: 0)
          .then((o) => outcome = o);
      async.flushMicrotasks();
      expect(outcome, same(_funded));
      // Once its run is over, a held order no longer blocks.
      c
          .read(fundedOrdersProvider.notifier)
          .setStage(run, FundedOrderStage.failed);
      notifier.clear();
      notifier.setIntent(first);
      expect(
          PendingHyperliquidOrderNotifier.blocksNewOrder(
              c.read(pendingHyperliquidOrderProvider),
              c.read(fundedOrdersProvider)),
          isFalse);
    });
  });

  group('fresh account reads while an order waits for its credit', () {
    late _Venue venue;
    late Directory hiveDir;
    setUpAll(() {
      hiveDir = Directory.systemTemp.createTempSync('hl_fresh_read_test');
      Hive.init(hiveDir.path);
    });
    tearDownAll(() async {
      await Hive.close();
      hiveDir.deleteSync(recursive: true);
    });

    ProviderContainer live(_Controller controller) {
      venue = _Venue(() => withdrawable);
      final c = ProviderContainer(overrides: [
        settingsProvider.overrideWith((_) => SettingsModel(_settings())),
        sessionUnlockedProvider.overrideWith((_) => true),
        hyperliquidAddressProvider.overrideWith(
            (_) async => '0x1111111111111111111111111111111111111111'),
        hyperliquidTradingModelProvider.overrideWithValue(venue),
        hyperliquidMoveRailProvider.overrideWithValue(rail),
        orderFundingControllerProvider.overrideWithValue(controller),
      ]);
      addTearDown(c.dispose);
      c.read(pendingHlOrderAutoFireProvider);
      history = [];
      c.listen(pendingHyperliquidOrderProvider, (_, n) => history.add(n));
      // On screen: the account stays alive between reads.
      c.listen(hyperliquidAccountProvider, (_, __) {});
      return c;
    }

    void queue(ProviderContainer c, _Controller controller,
        _Placement placement) {
      OrderFundingJourney.reset();
      OrderFundingJourney.instance.start(OneBalanceVenue.investing,
          orderUsd: 20, fundUsd: 20.03, readyUsd: 0, dollarsUsd: 20.03);
      final intent = _intent(placement);
      c.read(pendingHyperliquidOrderProvider.notifier).fundAndQueue(intent,
          grant: approve(intent),
          controller: controller,
          orderUsd: 20,
          requiredUsd: intent.requiredUsd,
          readyUsd: 0);
    }

    test(
        'every 1 s tick reads the venue (not the cached snapshot); the '
        'credit places within a second, credited_by fresh_read', () {
      fakeAsync((async) {
        final controller = _Controller(() async => _funded);
        final c = live(controller);
        async.flushMicrotasks();
        final placement = _Placement(resizable: true);
        queue(c, controller, placement);
        async.flushMicrotasks();
        final start = venue.reads.length;
        async.elapse(const Duration(seconds: 5));
        // One light read a second, never two in the same second.
        final reads = venue.reads.length - start;
        expect(reads, inInclusiveRange(4, 5));
        expect(venue.reads.skip(start).every((k) => k == 'credit'), isTrue);
        expect(placement.placed, isEmpty);
        withdrawable = 21;
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(placement.placed, [20]);
        final done = events
            .lastWhere((e) => e.$1 == 'order_funding_completed')
            .$2!;
        expect(done['credited_by'], 'fresh_read');
        expect(done['ms_funded_to_account_shows'], isA<int>());
        expect(done['account_reads'] as int, greaterThanOrEqualTo(5));
        expect(done['account_read_errors'], 0);
      });
    });

    test(
        'one read in flight: the ledger push sends no second one beside the '
        'tick\'s read (its own goes behind it)', () {
      fakeAsync((async) {
        final controller = _Controller(() async => _funded);
        final c = live(controller);
        async.flushMicrotasks();
        final placement = _Placement(resizable: true);
        queue(c, controller, placement);
        async.flushMicrotasks();
        venue.latency = const Duration(milliseconds: 600);
        async.elapse(const Duration(milliseconds: 1100));
        // The 1 s tick's read is out (until 1.6 s).
        final before = venue.reads.length;
        withdrawable = 21;
        c.read(pendingHlOrderAutoFireProvider).accountMoved(credited: true);
        async.elapse(const Duration(milliseconds: 100));
        expect(venue.reads.length, before,
            reason: 'no second request while one is in flight');
        async.elapse(const Duration(milliseconds: 600));
        async.flushMicrotasks();
        final done = events
            .lastWhere((e) => e.$1 == 'order_funding_completed')
            .$2!;
        expect(done['ms_funded_to_ledger_push'], isA<int>());
        // The tick's read showed the money and placed; the push's own
        // read (sent behind it) finds the order gone: placed once, never
        // a second placement that finds the approval spent.
        expect(placement.placed, [20]);
        expect(events.where((e) => e.$1 == 'order_funding_failed'), isEmpty);
      });
    });

    test('a 429 backs the fresh reads off (1, 2, 4, 8 s), the order waits',
        () {
      fakeAsync((async) {
        final controller = _Controller(() async => _funded);
        final c = live(controller);
        async.flushMicrotasks();
        final placement = _Placement(resizable: true);
        queue(c, controller, placement);
        async.flushMicrotasks();
        venue.fail = true;
        final start = venue.reads.length;
        async.elapse(const Duration(seconds: 16));
        // Without backoff: 16 reads. With it: ticks at 1, 2 (after 1 s),
        // 4 (after 2 s), 8 (after 4 s), 16 (after 8 s).
        expect(venue.reads.length - start, lessThanOrEqualTo(6));
        expect(placement.placed, isEmpty);
        venue.fail = false;
        withdrawable = 21;
        async.elapse(const Duration(seconds: 16));
        async.flushMicrotasks();
        expect(placement.placed, [20]);
        final done = events
            .lastWhere((e) => e.$1 == 'order_funding_completed')
            .$2!;
        expect(done['account_read_errors'] as int, greaterThan(0));
      });
    });
  });

  group('one order, one outcome', () {
    late _Venue venue;
    late Directory hiveDir;
    setUpAll(() {
      hiveDir = Directory.systemTemp.createTempSync('hl_one_outcome_test');
      Hive.init(hiveDir.path);
    });
    tearDownAll(() async {
      await Hive.close();
      hiveDir.deleteSync(recursive: true);
    });

    ProviderContainer live(_Controller controller) {
      venue = _Venue(() => withdrawable);
      final c = ProviderContainer(overrides: [
        settingsProvider.overrideWith((_) => SettingsModel(_settings())),
        sessionUnlockedProvider.overrideWith((_) => true),
        hyperliquidAddressProvider.overrideWith(
            (_) async => '0x1111111111111111111111111111111111111111'),
        hyperliquidTradingModelProvider.overrideWithValue(venue),
        hyperliquidMoveRailProvider.overrideWithValue(rail),
        orderFundingControllerProvider.overrideWithValue(controller),
      ]);
      addTearDown(c.dispose);
      c.read(pendingHlOrderAutoFireProvider);
      history = [];
      c.listen(pendingHyperliquidOrderProvider, (_, n) => history.add(n));
      c.listen(hyperliquidAccountProvider, (_, __) {});
      return c;
    }

    PendingHlOrderIntent queue(ProviderContainer c, _Controller controller,
        _Placement placement) {
      OrderFundingJourney.reset();
      OrderFundingJourney.instance.start(OneBalanceVenue.investing,
          orderUsd: 20, fundUsd: 20.03, readyUsd: 0, dollarsUsd: 20.03);
      final intent = _intent(placement);
      c.read(pendingHyperliquidOrderProvider.notifier).fundAndQueue(intent,
          grant: approve(intent),
          controller: controller,
          orderUsd: 20,
          requiredUsd: intent.requiredUsd,
          readyUsd: 0);
      return intent;
    }

    test(
        'Investing cash a prediction accepted meanwhile is about to pull is '
        'never this order\'s: it waits for its own money', () {
      fakeAsync((async) {
        final controller = _Controller(() async => _funded);
        final c = container(controller);
        // Investing holds 30; a bet accepted a moment ago pulls 15 of it
        // (committed_funds.dart). The slip sized this order's move on the
        // 15 left, so 5.24 more is on its way from Dollars.
        withdrawable = 30;
        final commitments = c.read(committedFundsProvider.notifier);
        commitments.hold(MoneyPlace.investing, OneBalanceVenue.predictions,
            usd: 15);
        final placement = _Placement(resizable: true);
        final intent = _intent(placement);
        c.read(pendingHyperliquidOrderProvider.notifier).fundAndQueue(intent,
            grant: approve(intent),
            controller: controller,
            orderUsd: 20,
            requiredUsd: intent.requiredUsd,
            readyUsd: 15);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 3));
        expect(placement.placed, isEmpty,
            reason: 'the 30 on the account is not all this order\'s: placing '
                'now takes the cash the bet is about to move');
        expect(c.read(pendingHyperliquidOrderProvider)!.status,
            PendingHlOrderStatus.awaitingBalance);
        // The bet's leg left (15 gone) and this order's money landed.
        commitments.venueCashSent(OneBalanceVenue.investing);
        withdrawable = 15 + 5.5;
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(placement.placed, [20]);
        expect(terminal().status, PendingHlOrderStatus.done);
      });
    });

    test(
        'what the queued order gained while its account read was out (its '
        'standing order, its move\'s id) is on the order that is placed', () {
      fakeAsync((async) {
        final controller = _Controller(() async => _funded);
        final c = live(controller);
        async.flushMicrotasks();
        final placement = _Placement(resizable: true);
        queue(c, controller, placement);
        async.flushMicrotasks();
        venue.latency = const Duration(milliseconds: 600);
        withdrawable = 21;
        async.elapse(const Duration(milliseconds: 1100));
        // The 1 s tick's read is out (until 1.6 s) and will show the money.
        expect(placement.placed, isEmpty);
        final notifier = c.read(pendingHyperliquidOrderProvider.notifier);
        notifier.setIntent(c
            .read(pendingHyperliquidOrderProvider)!
            .copyWith(standingOrderId: 'so_late', fundOrderId: 'o_late'));
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(placement.placed, [20]);
        final placing = history.firstWhere(
            (s) => s != null && s.status == PendingHlOrderStatus.placing)!;
        expect(placing.standingOrderId, 'so_late',
            reason: 'placed from a copy read before the wait, the order '
                'lost its standing order: that one stayed "Placing" and '
                'was queued again after a restart');
        expect(placing.fundOrderId, 'o_late');
        expect(terminal().standingOrderId, 'so_late');
      });
    });
  });
}
