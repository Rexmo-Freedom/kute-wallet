// A funded Investing order fires on the account the order draws on, not on
// the rail saying the move was delivered: while the credit is said but the
// account does not show it, the order waits (`crediting`) and moves to
// `placing` only once ready. A market order the venue still refuses for
// margin right after the credit waits for the account again and is sent
// again under the same approval, a few times at most; a limit order is
// never sent twice. Fakes only: nothing is signed or sent.

import 'package:fake_async/fake_async.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/auth_grant_registry.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/auth_provider.dart' show sessionUnlockedProvider;
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/pending_hyperliquid_order_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';
import 'package:kute/services/hyperliquid/hypercore_dex_cash.dart';
import 'package:kute/services/one_balance/hyperliquid_move_rail.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/order_funding.dart';
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

/// The Investing account: perp cash and spot USDC, read fresh each time.
class _Account extends HlAccountNotifier {
  _Account(this.perp, this.spot);
  final double Function() perp;
  final double Function() spot;
  @override
  Future<HlAccountSnapshot> build() async => HlAccountSnapshot(
        accountValue: perp(),
        withdrawable: perp(),
        totalMarginUsed: 0,
        positions: const [],
        spotBalances: [HlSpotBalance(coin: 'USDC', total: spot(), hold: 0)],
      );
}

class _Controller implements OrderFundingController {
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
  }) async =>
      fundUsd == 0
          ? const OrderFundingNotNeeded()
          : const OrderFundingFunded(VenueMoveResult(
              quoteId: 'q1',
              orderId: 'o1',
              sentUsd: 20.03,
              arrivingUsdEstimate: 20));

  @override
  OrderFundingController withDollars(double Function() dollarsUsd) => this;
}

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

/// The slip's handover; [refusals] are thrown by the next sends in turn.
class _Placement {
  _Placement(
      {required this.resizable,
      this.refusals = const [],
      this.market = _market,
      this.targetCredit});
  final bool resizable;
  final List<Object> refusals;
  final HlMarket market;
  final Future<void>? targetCredit;
  final placed = <double>[];

  /// The cloid each send went out under, as the slip's call reads it.
  final cloids = <String>[];

  SensitiveIntent intentAt(double margin) => HlIntents.openPosition(
        walletId: 'w1',
        market: market,
        isLong: true,
        marginUsd: margin,
        leverage: 1,
        slippagePct: 1,
      );

  PendingHlOrderPlacement get placement => PendingHlOrderPlacement(
        intentAt: intentAt,
        placeAt: (g, margin) async {
          // The notifier consumes the grant against the exact order.
          GrantGuard.consume(g, intentAt(margin),
              allowed: const {SensitiveAction.hlOrder});
          if (targetCredit != null) {
            OwnDexReadiness.waiting();
            await targetCredit;
            OwnDexReadiness.ready();
          }
          placed.add(margin);
          cloids.add(HlResendCloids.current('c1'));
          if (refusals.isNotEmpty) throw refusals.removeAt(0);
          return HlOrderResult(
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
        {String orderKind = 'market', double fundUsd = 20.03}) =>
    PendingHlOrderIntent(
      coin: placement.market.coin,
      kind: HlMarketKind.perp,
      isLong: true,
      marginUsd: 20,
      leverage: 1,
      slippagePct: 1,
      expectedPx: 60000,
      marketLabel: 'BTC · Perp',
      market: placement.market,
      placement: placement.placement,
      fundUsd: fundUsd,
      requiredUsd: 20 * 1.01 * 1.0019,
      readyAtQueueUsd: 0,
      arrivingUsd: 20 * 1.01 * 1.0019,
      orderKind: orderKind,
    );

const _margin = HyperliquidInsufficientMarginException(
    'Insufficient margin to place order.');

void main() {
  late FakeHyperliquidMoveRail rail;
  late double perp;
  late double spot;
  late List<(String, Map<String, Object?>?)> events;
  late List<PendingHlOrderIntent?> history;
  PendingHlOrderIntent terminal() => history.lastWhere((s) =>
      s != null &&
      (s.status == PendingHlOrderStatus.done ||
          s.status == PendingHlOrderStatus.failed))!;

  setUp(() {
    rail = FakeHyperliquidMoveRail();
    perp = 0;
    spot = 0;
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    AuthGrantRegistry.instance.cancelAutofire(kPendingHlOrderAutofireId);
    HlResendCloids.reset();
    OrderFundingJourney.reset();
    OrderFundingJourney.clock = DateTime.now;
  });

  tearDown(() {
    TrackingService.debugTrackObserver = null;
    OrderFundingJourney.clock = DateTime.now;
    AuthGrantRegistry.instance.cancelAutofire(kPendingHlOrderAutofireId);
    rail.creditedController.close();
  });

  /// Queues [placement]'s order behind its funding, with its approval.
  ProviderContainer queue(_Placement placement,
      {String orderKind = 'market',
      String? route,
      double pendingFundUsd = 20.03,
      HlSentOrderTrace Function(List<String> cloids)? trace}) {
    final c = ProviderContainer(overrides: [
      // The earlier sends looked up before any send again: nowhere, unless
      // the test says otherwise.
      hlSentOrderTraceProvider.overrideWithValue((cloids, market) async =>
          trace?.call(cloids) ?? const HlSentOrderTrace.none()),
      settingsProvider.overrideWith((_) => SettingsModel(_settings())),
      sessionUnlockedProvider.overrideWith((_) => true),
      hyperliquidAccountProvider
          .overrideWith(() => _Account(() => perp, () => spot)),
      hyperliquidMoveRailProvider.overrideWithValue(rail),
    ]);
    addTearDown(c.dispose);
    c.read(pendingHlOrderAutoFireProvider);
    history = [];
    c.listen(pendingHyperliquidOrderProvider, (_, n) => history.add(n));
    final intent =
        _intent(placement, orderKind: orderKind, fundUsd: pendingFundUsd);
    final grant = AuthGrantRegistry.instance.issueAutofire(
      kPendingHlOrderAutofireId,
      pendingHlOrderAutofireIntent(intent, placement.market, walletId: 'w1'),
      method: AuthGrantMethod.pin,
    );
    if (route != null) {
      final journey = OrderFundingJourney.instance;
      journey.start(OneBalanceVenue.investing,
          orderUsd: 20,
          fundUsd: 20.03,
          readyUsd: 0,
          dollarsUsd: 0,
          fundingSource: 'bitcoin',
          otherVenueUsed: false);
      journey.setRoute(OneBalanceVenue.investing, route,
          reason: route == 'via_dollars' ? 'costlier' : null);
      journey.legLanded(OneBalanceVenue.investing, 'bitcoin', 1234);
      if (pendingFundUsd > 0)
        journey.funded(
            OneBalanceVenue.investing,
            const VenueMoveResult(
                quoteId: 'q_private_quote',
                orderId: 'ord_private_order',
                sentUsd: 20.03,
                arrivingUsdEstimate: 20.03),
            orderUsd: 20);
    }
    c.read(pendingHyperliquidOrderProvider.notifier).fundAndQueue(intent,
        grant: grant,
        controller: _Controller(),
        fundUsd: pendingFundUsd,
        orderUsd: 20,
        requiredUsd: intent.requiredUsd,
        readyUsd: 0);
    return c;
  }

  for (final route in ['direct', 'via_dollars']) {
    for (final failed in [false, true]) {
      test('$route HL terminal outcome carries journey once (failed=$failed)',
          () {
        fakeAsync((async) {
          final placement = _Placement(
              resizable: true,
              refusals: failed ? [const OwnDexCreditPending()] : []);
          queue(placement, route: route);
          async.flushMicrotasks();
          OrderFundingJourney.instance.setRoute(
              OneBalanceVenue.investing, route,
              reason: route == 'via_dollars' ? 'costlier' : null);
          final selected = events
              .singleWhere((e) => e.$1 == 'order_funding_route_selected')
              .$2!;
          expect(selected['route'], route);
          expect(selected['duration_ms'], greaterThanOrEqualTo(0));
          if (route == 'via_dollars')
            expect(selected['route_reason'], 'costlier');
          final submitted =
              events.singleWhere((e) => e.$1 == 'order_funding_submitted').$2!;
          expect(submitted['quote_id'],
              TrackingService.orderRef('q_private_quote'));
          expect(submitted['order_id'],
              TrackingService.orderRef('ord_private_order'));
          perp = 20.5;
          async.elapse(const Duration(seconds: 1));
          async.flushMicrotasks();
          final outcomes = events.where((e) =>
              e.$1 == 'order_funding_completed' ||
              e.$1 == 'order_funding_failed');
          expect(outcomes, hasLength(1));
          final outcome = outcomes.single;
          expect(outcome.$1,
              failed ? 'order_funding_failed' : 'order_funding_completed');
          expect(outcome.$2!['route'], route);
          expect(outcome.$2!['ms_leg_bitcoin'], 1234);
          if (route == 'via_dollars')
            expect(outcome.$2!['route_reason'], 'costlier');
          if (failed) {
            expect(outcome.$2!['stage'], 'credit');
            expect(outcome.$2!['error_category'], 'dex_credit_pending');
          }
          expect(
              OrderFundingJourney.instance.isRunning(OneBalanceVenue.investing),
              isFalse);
          OrderFundingJourney.instance.abandoned(OneBalanceVenue.investing);
          expect(
              events.where((e) => e.$1 == 'order_funding_abandoned'), isEmpty);
        });
      });
    }
  }

  for (final failed in [false, true]) {
    test(
        'pure direct Bitcoin with zero Dollars emits one outcome (failed=$failed)',
        () {
      fakeAsync((async) {
        queue(
            _Placement(
                resizable: true,
                refusals: failed ? [const OwnDexCreditPending()] : []),
            route: 'direct',
            pendingFundUsd: 0);
        async.flushMicrotasks();
        expect(events.where((e) => e.$1 == 'order_funding_submitted'), isEmpty);
        perp = 20.5;
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        final outcomes = events.where((e) =>
            e.$1 == 'order_funding_completed' ||
            e.$1 == 'order_funding_failed');
        expect(outcomes, hasLength(1));
        final p = outcomes.single.$2!;
        expect(p['route'], 'direct');
        expect(p['fund_usd'], 20.03);
        expect(p['ms_leg_bitcoin'], 1234);
        expect(
            OrderFundingJourney.instance.isRunning(OneBalanceVenue.investing),
            isFalse);
      });
    });
  }

  test('an old placement callback cannot consume a newer journey', () {
    final old = DateTime.now();
    OrderFundingJourney.clock = () => old.add(const Duration(seconds: 2));
    final journey = OrderFundingJourney.instance;
    journey.start(OneBalanceVenue.investing,
        orderUsd: 20, fundUsd: 20.03, readyUsd: 0, dollarsUsd: 0);
    journey.setRoute(OneBalanceVenue.investing, 'direct');
    expect(journey.takeOutcomeParams(OneBalanceVenue.investing, startedBy: old),
        isEmpty);
    expect(journey.isRunning(OneBalanceVenue.investing), isTrue);
    expect(
        journey.takeOutcomeParams(OneBalanceVenue.investing,
            startedBy: old.add(const Duration(seconds: 3)))['route'],
        'direct');
  });

  test(
      'HIP-3 credit step stays active until its target clearinghouse is usable',
      () {
    fakeAsync((async) {
      OrderFundingJourney.clock = async.getClock(DateTime.now()).now;
      final credited = Completer<void>();
      final placement = _Placement(
          resizable: true,
          market: HlMarket.fromCacheJson({
            ..._market.toCacheJson(),
            'coin': 'TSLA',
            'wireCoin': 'xyz:TSLA',
            'assetId': 110001,
            'dex': 'xyz',
            'isHip3': true,
          })!,
          targetCredit: credited.future);
      final c = queue(placement);
      async.flushMicrotasks();
      perp = 20.5;
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      final moving = c.read(pendingHyperliquidOrderProvider)!;
      expect(moving.status, PendingHlOrderStatus.placing);
      expect(moving.readiness, HlReadiness.crediting);
      expect(placement.placed, isEmpty);
      expect(history.where((s) => s?.readiness == HlReadiness.ready), isEmpty);
      async.elapse(const Duration(seconds: 3));
      credited.complete();
      async.flushMicrotasks();
      expect(placement.placed, [20]);
      expect(
          history.any((s) =>
              s?.status == PendingHlOrderStatus.placing &&
              s?.readiness == HlReadiness.ready),
          isTrue);
      expect(terminal().status, PendingHlOrderStatus.done);
      final completed =
          events.singleWhere((e) => e.$1 == 'order_funding_completed').$2!;
      expect(completed['ms_dex_credit'], 3000);
      expect(completed['ms_order'], 0);
    });
  });

  test('abandoned funding retains its selected route and completed leg timings',
      () {
    fakeAsync((async) {
      queue(_Placement(resizable: true), route: 'via_dollars');
      async.flushMicrotasks();
      OrderFundingJourney.instance.abandoned(OneBalanceVenue.investing);
      final abandoned =
          events.singleWhere((e) => e.$1 == 'order_funding_abandoned').$2!;
      expect(abandoned['route'], 'via_dollars');
      expect(abandoned['route_reason'], 'costlier');
      expect(abandoned['ms_leg_bitcoin'], 1234);
    });
  });

  test(
      'credited by the rail but not showing in the account: waits '
      '(crediting), then places once the account covers it', () {
    fakeAsync((async) {
      final placement = _Placement(resizable: true);
      final c = queue(placement);
      async.flushMicrotasks();
      expect(c.read(pendingHyperliquidOrderProvider)!.readiness,
          HlReadiness.waitingFunds);

      // Orchestra says delivered; the account still shows nothing.
      rail.creditedController.add(null);
      async.elapse(const Duration(seconds: 3));
      expect(placement.placed, isEmpty);
      final waiting = c.read(pendingHyperliquidOrderProvider)!;
      expect(waiting.status, PendingHlOrderStatus.awaitingBalance);
      expect(waiting.readiness, HlReadiness.crediting);

      perp = 20.5;
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(placement.placed, [20]);
      final placing =
          history.firstWhere((s) => s?.status == PendingHlOrderStatus.placing)!;
      expect(placing.readiness, HlReadiness.ready);
      expect(terminal().status, PendingHlOrderStatus.done);
    });
  });

  test('target collateral credit timeout never retries the funding action', () {
    fakeAsync((async) {
      final placement = _Placement(
          resizable: true, refusals: [const OwnDexCreditPending()]);
      queue(placement);
      async.flushMicrotasks();
      perp = 20.5;
      async.elapse(const Duration(seconds: 30));
      async.flushMicrotasks();
      expect(placement.placed, [20]);
      expect(terminal().status, PendingHlOrderStatus.failed);
    });
  });

  test(
      'cash credited to spot for a perp order is usable: the order moves '
      'it under its own grant', () {
    fakeAsync((async) {
      final placement = _Placement(resizable: true);
      queue(placement);
      async.flushMicrotasks();
      spot = 20.5;
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(placement.placed, [20]);
      expect(terminal().status, PendingHlOrderStatus.done);
    });
  });

  test(
      'refused for margin right after the credit: waits for the account, '
      'then the send again goes through under the same approval', () {
    fakeAsync((async) {
      final placement = _Placement(resizable: true, refusals: [_margin]);
      final c = queue(placement);
      async.flushMicrotasks();
      perp = 20.5;
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(placement.placed, hasLength(1));
      // Not a failure: still placing, waiting for the account.
      final waiting = c.read(pendingHyperliquidOrderProvider)!;
      expect(waiting.status, PendingHlOrderStatus.placing);
      expect(waiting.readiness, HlReadiness.crediting);

      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(placement.placed, [20, 20]);
      expect(terminal().status, PendingHlOrderStatus.done);
      expect(events.where((e) => e.$1 == 'order_funding_failed'), isEmpty);
      expect(
          events.where((e) => e.$1 == 'hyperliquid_autofire_failed'), isEmpty);
    });
  });

  test('bounded: after five sends again the failure shows', () {
    fakeAsync((async) {
      final placement = _Placement(
          resizable: true, refusals: List.filled(6, _margin, growable: true));
      queue(placement);
      async.flushMicrotasks();
      perp = 20.5;
      async.elapse(const Duration(seconds: 10));
      async.flushMicrotasks();
      expect(placement.placed, hasLength(1 + kHlNotReadyRetries));
      expect(terminal().status, PendingHlOrderStatus.failed);
    });
  });

  test(
      'a limit order refused for margin is a real failure: never sent '
      'twice', () {
    fakeAsync((async) {
      final placement = _Placement(resizable: false, refusals: [_margin]);
      queue(placement, orderKind: 'limit');
      async.flushMicrotasks();
      perp = 20.5;
      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();
      expect(placement.placed, [20]);
      expect(terminal().status, PendingHlOrderStatus.failed);
    });
  });

  test('another venue refusal is a real failure: shown at once', () {
    fakeAsync((async) {
      final placement = _Placement(resizable: true, refusals: [
        const HyperliquidRejectedException('Order could not immediately match')
      ]);
      queue(placement);
      async.flushMicrotasks();
      perp = 20.5;
      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();
      expect(placement.placed, [20]);
      expect(terminal().status, PendingHlOrderStatus.failed);
    });
  });

  test(
      'a send again goes under a FRESH cloid, never the first one twice; '
      'the earlier one is looked up first', () {
    fakeAsync((async) {
      final looked = <List<String>>[];
      final placement = _Placement(resizable: true, refusals: [_margin]);
      queue(placement, trace: (cloids) {
        looked.add(cloids);
        return const HlSentOrderTrace.none();
      });
      async.flushMicrotasks();
      perp = 20.5;
      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();
      expect(placement.cloids, hasLength(2));
      expect(placement.cloids.first, 'c1');
      expect(placement.cloids.last, isNot('c1'));
      expect(HlResendCloids.owns('c1', placement.cloids.last), isTrue);
      expect(looked.single, ['c1']);
      expect(terminal().status, PendingHlOrderStatus.done);
    });
  });

  test(
      'the first order rested or filled after all: it is followed, never '
      'sent again', () {
    fakeAsync((async) {
      final placement = _Placement(resizable: true, refusals: [_margin]);
      queue(placement,
          trace: (_) => const HlSentOrderTrace.found(HlOrderResult(
              kind: HlOrderResultKind.filled,
              oid: 9,
              cloid: 'c1',
              filledSz: 0.0003,
              avgPx: 60000)));
      async.flushMicrotasks();
      perp = 20.5;
      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();
      expect(placement.placed, [20]);
      final done = terminal();
      expect(done.status, PendingHlOrderStatus.done);
      expect(done.result!.oid, 9);
    });
  });

  test(
      'the earlier send cannot be read: never sent again, the failure '
      'shows', () {
    fakeAsync((async) {
      final placement = _Placement(resizable: true, refusals: [_margin]);
      queue(placement, trace: (_) => const HlSentOrderTrace.unknown());
      async.flushMicrotasks();
      perp = 20.5;
      async.elapse(const Duration(seconds: 6));
      async.flushMicrotasks();
      expect(placement.placed, [20]);
      expect(terminal().status, PendingHlOrderStatus.failed);
    });
  });

  test(
      'the lookup reads open orders and fills by every cloid the order '
      'went under', () {
    HlOpenOrder open(String cloid) => HlOpenOrder.fromJson({
          'coin': 'BTC',
          'oid': 3,
          'side': 'B',
          'limitPx': '60000',
          'sz': '0.001',
          'origSz': '0.001',
          'timestamp': 1,
          'cloid': cloid,
        });
    expect(
        hlTraceOf(['0xa'], open: [open('0xb')], fills: const []).found, isNull);
    final resting =
        hlTraceOf(['0xa', '0xB'], open: [open('0xb')], fills: const []).found!;
    expect(resting.kind, HlOrderResultKind.resting);
    expect(resting.oid, 3);
  });
}
