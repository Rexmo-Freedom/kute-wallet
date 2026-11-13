// A bet funded from Dollars fires only once its money is usable by the
// order book, not when it is merely delivered (founder, 15 October 2026:
// "$3.68 on Yes" failed with "This action did not complete" because the
// deposit was still USDC.e / not counted by the book when the order went
// out). The bet waits while the deposit converts and the book catches up,
// moves to `placing` only once ready, and a venue refusal that only says
// "not usable yet" is sent again under the same approval, a few times at
// most. A real failure still shows. Fakes only: nothing is signed or sent.

import 'dart:io';
import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/polymarket/usdce_wrap_gate.dart'
    show FundedConversionHold, UsdceWrapGate;
import 'package:kute/services/polymarket_onboarding_service.dart'
    show PolygonPollReadFailed;
import 'package:hive_ce/hive.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/auth_grant_registry.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/l10n/l10n.dart' show l10nForLanguage;
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/auth_provider.dart' show sessionUnlockedProvider;
import 'package:kute/providers/pending_bet_autofire.dart';
import 'package:kute/providers/pending_polymarket_bet_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/polymarket_cost_basis_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/polymarket/components/bet_slip_sheet.dart'
    show betSlipRetriesNextRound, betSlipStopAction;
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/order_funding.dart';
import 'package:kute/services/one_balance/prediction_funding_ledger.dart';
import 'package:kute/services/polymarket/market_buy_quote.dart';
import 'package:kute/services/polymarket/order_refusal.dart'
    show PolymarketBalanceRefused;
import 'package:kute/services/polymarket/placement_waits.dart'
    show PolymarketFundsConverting, PolymarketSetupIncomplete, PolymarketCollateralPending;
import 'package:kute/services/polymarket/venue_collateral.dart';
import 'package:kute/services/polymarket_backend_service.dart'
    show PolymarketOrderNotAcceptedException;
import 'package:kute/services/tracking_service.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show OrderSide, OrderType;

const _token = '9001';
const _noMatch = 'no orders found to match with FAK order. FAK orders are '
    'partially filled or killed if no match is found.';
const _balance = 'not enough balance / allowance: the balance is not enough';

BigInt _usd(double usd) => BigInt.from((usd * 1e6).round());

/// The deposit wallet as the readiness check reads it.
PolyBuyReads _reads({
  double pusd = 0,
  double usdce = 0,
  double? counted,
  bool setupDone = true,
}) =>
    (
      pusd: _usd(pusd),
      usdce: _usd(usdce),
      venue: counted == null ? null : PolyVenueCount(balance: _usd(counted)),
      setupDone: setupDone,
    );

class _Trading extends PolymarketTradingNotifier {
  _Trading(this.refusals);

  /// Thrown by the next orders, in turn; then the venue accepts.
  final List<Object> refusals;

  /// Asked after [refusals] ran out: what the next order throws (null:
  /// the venue accepts it). The placement's own pre-sign check as time
  /// passes (an approval being mined, the book's count catching up).
  Object? Function()? refuseWith;

  /// What the readiness read answers; null = nothing to read.
  PolyBuyReads? reads;
  Future<PolyBuyReads?>? deferredRead;
  Future<Map<String, dynamic>>? deferredPost;
  final deliveries = StreamController<void>.broadcast();
  @override
  Stream<void> get depositSettled => deliveries.stream;
  final refreshAsks = <bool>[];
  var nudges = 0;
  final orders = <double>[];
  final orderCosts = <double>[];
  void Function()? onRefused;

  @override
  Future<PolymarketTradingState> build() async => const PolymarketTradingState(
      isAuthenticated: true,
      usdcBalance: 0,
      proxyWalletAddress: '0xdeposit');

  /// The deposit is delivered: the summed cash shows [usd].
  void land(double usd) =>
      state = AsyncData(state.value!.copyWith(usdcBalance: usd));

  @override
  String? get signingWalletId => 'spending';

  @override
  Future<PolyBuyReads?> readBuyReadiness({bool refreshVenue = false}) async {
    refreshAsks.add(refreshVenue);
    final pendingRead = deferredRead;
    if (pendingRead != null) return pendingRead;
    return reads;
  }

  /// What the funded bet's chain watch reads; null = nothing to read.
  ({BigInt pusd, BigInt usdce, int endpoint, int rpcErrors})? chain;
  Object? chainError;
  var chainReads = 0;

  @override
  Future<({BigInt pusd, BigInt usdce, int endpoint, int rpcErrors})?>
      readCollateralNow() async {
    chainReads++;
    final e = chainError;
    if (e != null) throw e;
    return chain;
  }

  /// When set, every nudge converts through the real single-flight gate.
  UsdceWrapGate? gate;
  var wraps = 0;

  /// How many readiness reads had gone out at the first nudge.
  int? firstNudgeAtReads;

  @override
  void nudgeConversion() {
    nudges++;
    firstNudgeAtReads ??= refreshAsks.length;
    final g = gate;
    if (g != null) {
      unawaited(g.run('0xdeposit', () async {
        wraps++;
        await Future<void>.delayed(const Duration(milliseconds: 60));
        return BigInt.one;
      }));
    }
  }

  @override
  Future<bool> readyCollateralForBuy(double costUsd) async => false;

  @override
  Future<void> refresh() async {}

  @override
  void invalidateBalanceCache() {}

  @override
  void setPendingBetWaiting(bool waiting) {}

  @override
  Future<Map<String, dynamic>> placeOrder({
    required String tokenId,
    required OrderSide side,
    required double size,
    required double price,
    bool negRisk = false,
    PolymarketMarketBuyQuote? marketQuote,
    OrderType orderType = OrderType.fok,
    double? spendUsd,
    String? marketTitle,
    String? marketImage,
    String? marketOutcome,
    String? conditionId,
    String? eventSlug,
    String? endDate,
    String? marketCategory,
    String? source,
    String? entrySource,
    Map<String, Object>? analytics,
    required AuthGrant grant,
    void Function(String step)? onStep,
  }) async {
    // The grant covers exactly this order: the real executor's own check.
    PmGrants.consumeOrder(grant,
        walletId: signingWalletId!,
        tokenId: tokenId,
        isBuy: side == OrderSide.buy,
        size: size,
        price: price,
        orderType: orderType.name,
        spendUsd: side == OrderSide.buy &&
                (orderType == OrderType.fok || orderType == OrderType.fak)
            ? spendUsd
            : null);
    orders.add(price);
    orderCosts.add(marketQuote?.allInMax ?? size * price);
    if (refusals.isNotEmpty) {
      final refusal = refusals.removeAt(0);
      onRefused?.call();
      throw refusal;
    }
    final late = refuseWith?.call();
    if (late != null) {
      onRefused?.call();
      throw late;
    }
    onStep?.call('ready');
    if (deferredPost != null) return deferredPost!;
    return {'success': true, 'status': 'live', 'orderID': '0xorder'};
  }
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
      activeWalletId: 'spending',
      wallets: [WalletConfig(id: 'spending', name: 'Spending Wallet')],
    );

/// The bet as the slip queues it once its $10 move has left Dollars.
PendingBetIntent _queued(
        {DateTime? endAt,
        String? slug,
        String? roundWindow,
        String question = 'Bitcoin Up or Down - October 13, 2:00PM-2:05PM ET',
        Map<String, Object?>? btcLeg,
        Map<String, Object?>? directLegs}) =>
    PendingBetIntent(
      tokenId: _token,
      amount: 10,
      slippagePct: 5,
      marketQuestion: question,
      outcomeName: 'Up',
      expectedPrice: 0.5,
      status: PendingBetStatus.awaitingBalance,
      fundUsd: 10,
      fundQuoteRef: 'ref_move',
      fundReadyUsd: 0,
      fundArrivingUsd: 9.9,
      queuedAt: DateTime.now(),
      marketEndAt: endAt,
      btcLeg: btcLeg,
      directLegs: directLegs,
      eventSlug: slug,
      roundWindow: roundWindow,
    );

void main() {
  late Directory hiveDir;

  setUpAll(() {
    hiveDir = Directory.systemTemp.createTempSync('bet_readiness_test');
    Hive.init(hiveDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    hiveDir.deleteSync(recursive: true);
  });

  late List<(String, Map<String, Object>?)> events;

  setUp(() {
    FundedOrdersNotifier.persist = false;
    PredictionFundingLedger.reset();
    OrderFundingJourney.reset();
    PendingBetAutoFire.readyPollInterval = const Duration(milliseconds: 10);
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });

  tearDown(() {
    TrackingService.debugTrackObserver = null;
    AuthGrants.clock = DateTime.now;
    PendingBetAutoFire.readyPollInterval = const Duration(seconds: 1);
    PendingBetAutoFire.awaitPollInterval = const Duration(seconds: 15);
    PendingBetAutoFire.fundsTimeout = kFundsTimeout;
    AuthGrantRegistry.instance.cancelAutofire(kPendingBetAutofireId);
  });

  group('autofireReadiness', () {
    final cost = _usd(10.2);
    final spenders = ['0xexchange'];
    PredictionsReadiness at(PolyBuyReads r) => autofireReadiness(
        pusd: r.pusd,
        usdce: r.usdce,
        costMicros: cost,
        venue: r.venue,
        spenders: spenders,
        setupDone: r.setupDone);

    test('delivered as USDC.e: converting, whatever the summed cash says', () {
      expect(
          at(_reads(usdce: 10.6, counted: 0)), PredictionsReadiness.converting);
      // Part converted: still converting.
      expect(at(_reads(pusd: 5, usdce: 5.4, counted: 5)),
          PredictionsReadiness.converting);
    });

    test('nothing usable yet: waiting for the funds', () {
      expect(at(_reads(counted: 0)), PredictionsReadiness.waitingFunds);
    });

    test('setup running or an allowance short: approving', () {
      expect(at(_reads(pusd: 10.6, counted: 10.6, setupDone: false)),
          PredictionsReadiness.approving);
      final short = PolyVenueCount(
          balance: _usd(10.6), allowances: {'0xexchange': BigInt.zero});
      expect(
          autofireReadiness(
              pusd: _usd(10.6),
              usdce: BigInt.zero,
              costMicros: cost,
              venue: short,
              spenders: spenders,
              setupDone: true),
          PredictionsReadiness.approving);
    });

    test('pUSD there but the book counts the old balance: confirming', () {
      expect(
          at(_reads(pusd: 10.6, counted: 0)), PredictionsReadiness.confirming);
    });

    test('pUSD there and counted: ready; an unread book keeps confirming', () {
      expect(at(_reads(pusd: 10.6, counted: 10.6)), PredictionsReadiness.ready);
      expect(at(_reads(pusd: 10.6)), PredictionsReadiness.confirming);
    });

    test('partial pUSD is not proof of the full executable cost', () {
      expect(at(_reads(pusd: 9.6, counted: 9.6)),
          PredictionsReadiness.waitingFunds);
      expect(
          at(_reads(pusd: 9.6, counted: 0)), PredictionsReadiness.waitingFunds);
    });

    test('only "not usable yet" refusals wait', () {
      expect(autofireNotReadyYet(const PolymarketBalanceRefused(_balance)),
          isTrue);
      expect(
          autofireNotReadyYet(
              const PolymarketOrderNotAcceptedException(_balance)),
          isTrue);
      expect(autofireNotReadyYet(const PolymarketFundsConverting()), isTrue);
      expect(
          autofireNotReadyYet(
              const PolymarketOrderNotAcceptedException(_noMatch)),
          isFalse);
      expect(autofireNotReadyYet(StateError('x')), isFalse);
      // The relayer still busy with another action, or its nonce moved:
      // nothing was accepted.
      expect(
          autofireNotReadyYet(Exception('Relayer submit failed: 400 '
              '{"error":"wallet busy: active action exists"}')),
          isTrue);
      expect(
          autofireNotReadyYet(Exception('400 {"error":"batch nonce 16 does '
              'not match on-chain nonce 17"}')),
          isTrue);
    });
  });

  /// Queues the funded bet with its one approval and wires the fakes.
  Future<
      ({
        ProviderContainer c,
        _Trading trading,
        List<PredictionsReadiness?> atPlacing
      })> start(
      {List<Object> refusals = const [],
      DateTime? endAt,
      Map<String, Object?>? btcLeg,
      Map<String, Object?>? directLegs,
      String? slug,
      String? roundWindow,
      String Function()? ask}) async {
    final askNow = ask ?? () => '0.48';
    final trading = _Trading([...refusals])
      ..reads = _reads(pusd: 10.6, counted: 10.6);
    addTearDown(trading.deliveries.close);
    final c = ProviderContainer(overrides: [
      polymarketTradingProvider.overrideWith(() => trading),
      settingsProvider.overrideWith((_) => SettingsModel(_settings())),
      sessionUnlockedProvider.overrideWithValue(true),
      autofireBookReaderProvider.overrideWithValue((tokenId) async =>
          parsePolymarketOrderBook({
            'market': 'm',
            'asset_id': _token,
            'tick_size': '0.01',
            'neg_risk': false,
            'min_order_size': '1',
            'asks': [
              {'price': askNow(), 'size': '1000'}
            ],
            'bids': const [],
          })),
    ]);
    addTearDown(c.dispose);
    c.listen(polymarketTradingProvider, (_, __) {});
    await c.read(polymarketTradingProvider.future);
    c.read(pendingBetAutoFireProvider);
    // The readiness the bet carried the first time it went to `placing`.
    final atPlacing = <PredictionsReadiness?>[];
    PendingBetStatus? last;
    c.listen<PendingBetIntent?>(pendingPolymarketBetProvider, (_, next) {
      if (next?.status == PendingBetStatus.placing &&
          last != PendingBetStatus.placing) {
        atPlacing.add(next!.readiness);
      }
      last = next?.status;
    });

    final intent = _queued(
        endAt: endAt,
        slug: slug,
        roundWindow: roundWindow,
        btcLeg: btcLeg,
        directLegs: directLegs);
    final review = PmGrants.betReview(
      walletId: 'spending',
      tokenId: _token,
      maxCostUsd: 10.5,
      worstPrice: polymarketFundedWorstPrice(intent),
      orderType: OrderType.fak.name,
    );
    AuthGrantRegistry.instance.issueAutofire(
        kPendingBetAutofireId,
        PmGrants.fundedBetReview(
            review.copyWith(limits: {
              ...review.limits,
              IntentLimit.maxSlippageBps: IntentUnits.bps(5),
            }),
            fundUsd: 10,
            venue: IntentVenue.polymarket,
            directLegs: directLegs,
            btcLeg: btcLeg),
        method: AuthGrantMethod.biometric);
    PredictionFundingLedger.instance.sent('ref_move', usd: 10);
    c.read(pendingPolymarketBetProvider.notifier).setIntent(intent);
    return (c: c, trading: trading, atPlacing: atPlacing);
  }

  /// [start] for a bet the slip opened on the next window.
  Future<
      ({
        ProviderContainer c,
        _Trading trading,
        List<PredictionsReadiness?> atPlacing
      })> start_(DateTime windowStart,
          {required String slug,
          String Function()? ask,
          required DateTime endAt}) =>
      start(slug: slug, ask: ask, endAt: endAt, roundWindow: 'next');

  Future<void> settle(ProviderContainer c) async {
    for (var i = 0; i < 300; i++) {
      final s = c.read(pendingPolymarketBetProvider)?.status;
      if (s != PendingBetStatus.awaitingBalance &&
          s != PendingBetStatus.placing) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  String graph(ProviderContainer c, List<MoneyStep> legs) {
    final notifier = c.read(fundedOrdersProvider.notifier);
    final id = notifier.start(
        const FundedOrderLabel(
            venue: OneBalanceVenue.predictions,
            orderUsd: 10,
            side: 'Up',
            market: 'Question',
            marketKey: _token),
        stage: FundedOrderStage.preparing);
    notifier.setSteps(id, MoneyStepGraph(legs));
    return id;
  }

  test(
      'staggered mixed sources: a first delivery certifies nothing and '
      'converts nothing; ONE conversion once every leg\'s money is there',
      () async {
    final r = await start();
    final id = graph(r.c, const [
      MoneyStep(
          id: 'leg:bitcoin',
          kind: MoneyStepKind.leg,
          from: MoneyPlace.bitcoin,
          usd: 4,
          status: MoneyStepStatus.done),
      MoneyStep(
          id: 'leg:investing',
          kind: MoneyStepKind.leg,
          from: MoneyPlace.investing,
          usd: 6.6,
          status: MoneyStepStatus.running),
    ]);
    final notifier = r.c.read(pendingPolymarketBetProvider.notifier);
    notifier.setIntent(r.c
        .read(pendingPolymarketBetProvider)!
        .copyWith(fundedRunId: id, fundArrivingUsd: 10.6));
    r.trading.reads = _reads(usdce: 4, counted: 0);
    r.trading.land(10.6); // The summed app cache is ahead of the actual read.
    r.trading.deliveries.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(r.trading.orders, isEmpty);
    expect(PredictionFundingLedger.instance.record('ref_move')!.stage,
        PredictionFundingStage.sent);
    // Founder, 25 October 2026: nothing at Predictions runs before all
    // the money is there. The first leg's USDC.e is not converted: no
    // conversion is asked for, every trigger is held, the bet waits.
    expect(r.trading.nudges, 0);
    expect(FundedConversionHold.held, isTrue);
    expect(r.c.read(pendingPolymarketBetProvider)!.readiness,
        PredictionsReadiness.waitingFunds);

    // Every leg landed and the wallet's own balances show all of it.
    r.trading.reads = _reads(usdce: 10.6, counted: 0);
    r.c.read(fundedOrdersProvider.notifier).setSteps(
        id,
        const MoneyStepGraph([
          MoneyStep(
              id: 'leg:bitcoin',
              kind: MoneyStepKind.leg,
              from: MoneyPlace.bitcoin,
              usd: 4,
              status: MoneyStepStatus.done),
          MoneyStep(
              id: 'leg:investing',
              kind: MoneyStepKind.leg,
              from: MoneyPlace.investing,
              usd: 6.6,
              status: MoneyStepStatus.done),
        ]));
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(r.trading.orders, isEmpty);
    // Released: the one conversion for the whole delivered amount.
    expect(FundedConversionHold.held, isFalse);
    expect(r.trading.nudges, greaterThan(0));
    expect(r.c.read(pendingPolymarketBetProvider)!.readiness,
        PredictionsReadiness.converting);
    r.trading.reads = _reads(pusd: 10.6, counted: 4);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(r.trading.orders, isEmpty);
    r.trading.reads = _reads(pusd: 10.6, counted: 10.6);
    await settle(r.c);
    expect(r.trading.orders, hasLength(1));
    expect(r.trading.orderCosts.single, lessThanOrEqualTo(10.6));
  });

  group('the funded bet\'s own chain watch', () {
    ({BigInt pusd, BigInt usdce, int endpoint, int rpcErrors}) chain(
            {double pusd = 0, double usdce = 0, int endpoint = 2}) =>
        (pusd: _usd(pusd), usdce: _usd(usdce), endpoint: endpoint, rpcErrors: 0);

    void journey() => OrderFundingJourney.instance.start(
        OneBalanceVenue.predictions,
        orderUsd: 10,
        fundUsd: 10,
        readyUsd: 0,
        dollarsUsd: 10);

    test(
        'sees every leg\'s money on chain before any other read: the hold '
        'released, the conversion started at once, detected_by chain_poll',
        () async {
      journey();
      final r = await start();
      r.trading.chain = chain(usdce: 10.6);
      final watch = r.c.read(pendingBetAutoFireProvider).chainWatch;
      expect(watch.active, isTrue);
      await settle(r.c);
      expect(r.trading.orders, hasLength(1));
      // The conversion was asked for before the readiness look read the
      // wallet: straight from the chain read that saw the money.
      expect(r.trading.firstNudgeAtReads, 0);
      expect(r.trading.chainReads, 1);
      expect(FundedConversionHold.held, isFalse);
      expect(watch.active, isFalse);
      final done =
          events.singleWhere((e) => e.$1 == 'order_funding_completed').$2!;
      expect(done['detected_by'], 'chain_poll');
      expect(done['chain_reads'], 1);
      expect(done['chain_rpc_errors'], 0);
      expect(done['chain_rpc_endpoint'], 2);
      expect(done['ms_funded_to_onchain_seen'], isA<int>());
      expect(done['ms_funded_to_onchain_seen'] as int, greaterThanOrEqualTo(0));
    });

    test('part of the money on chain: still held; all of it: released',
        () async {
      journey();
      final r = await start();
      r.trading.chain = chain(usdce: 4);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(FundedConversionHold.held, isTrue);
      expect(r.trading.nudges, 0);
      expect(r.trading.orders, isEmpty);
      // The next tick (1 s) sees all of it.
      r.trading.chain = chain(pusd: 4, usdce: 6.6);
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      expect(FundedConversionHold.held, isFalse);
      expect(r.trading.nudges, greaterThan(0));
      await settle(r.c);
      expect(r.trading.orders, hasLength(1));
      expect(r.trading.chainReads, 2);
    });

    test('the release and the readiness look both ask: one conversion',
        () async {
      journey();
      final r = await start();
      r.trading.gate = UsdceWrapGate();
      // The readiness look still sees USDC.e: it asks again (converting).
      r.trading.reads = _reads(usdce: 10.6, counted: 0);
      r.trading.chain = chain(usdce: 10.6);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(r.trading.nudges, greaterThanOrEqualTo(2));
      expect(r.trading.wraps, 1);
      r.trading.reads = _reads(pusd: 10.6, counted: 10.6);
      await settle(r.c);
      expect(r.trading.orders, hasLength(1));
      expect(r.trading.wraps, 1);
    });

    test('an RPC failure is counted and backed off, never taken for empty',
        () async {
      journey();
      final r = await start();
      r.trading.chainError = const PolygonPollReadFailed(2);
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      // 0 s, then the 1 s backoff: two tries, nothing released.
      expect(r.trading.chainReads, 2);
      expect(FundedConversionHold.held, isTrue);
      r.trading.chainError = null;
      r.trading.chain = chain(usdce: 10.6);
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      await settle(r.c);
      expect(r.trading.orders, hasLength(1));
      final done =
          events.singleWhere((e) => e.$1 == 'order_funding_completed').$2!;
      expect(done['detected_by'], 'chain_poll');
      expect(done['chain_rpc_errors'], 4);
      expect(done['chain_reads'], 3);
    });

    test('stops when the bet is cancelled or fails', () async {
      journey();
      final r = await start();
      final watch = r.c.read(pendingBetAutoFireProvider).chainWatch;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(watch.active, isTrue);
      r.c.read(pendingPolymarketBetProvider.notifier).updateStatus(
          PendingBetStatus.failed,
          errorMessage: 'x',
          failureCode: 'funds_timeout');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(watch.active, isFalse);
      final reads = r.trading.chainReads;
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(r.trading.chainReads, reads);
    });

    test('stops once the bet is done', () async {
      final r = await start();
      r.c.read(pendingPolymarketBetProvider.notifier).setIntent(r.c
          .read(pendingPolymarketBetProvider)!
          .copyWith(status: PendingBetStatus.done));
      final watch = r.c.read(pendingBetAutoFireProvider).chainWatch;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(watch.active, isFalse);
    });
  });

  for (final fallback in [false, true]) {
    test(
        'proved ${fallback ? 'via Dollars' : 'direct'} mixed delivery, no '
        'Dollars funding ref: sizes a short order from confirmed pUSD',
        () async {
      final r = await start();
      final id = graph(r.c, [
        if (fallback)
          const MoneyStep(
              id: 'leg:bitcoin',
              kind: MoneyStepKind.leg,
              status: MoneyStepStatus.fellBack),
        MoneyStep(
            id: fallback ? 'leg:bitcoin>dollars' : 'leg:bitcoin',
            kind: MoneyStepKind.leg,
            from: MoneyPlace.bitcoin,
            usd: 4,
            status: MoneyStepStatus.done),
        if (fallback)
          const MoneyStep(
              id: 'leg:dollars:onward',
              kind: MoneyStepKind.leg,
              from: MoneyPlace.dollars,
              usd: 4,
              status: MoneyStepStatus.done),
        const MoneyStep(
            id: 'leg:investing',
            kind: MoneyStepKind.leg,
            from: MoneyPlace.investing,
            usd: 5.9,
            status: MoneyStepStatus.done),
      ]);
      final old = r.c.read(pendingPolymarketBetProvider)!;
      // Pure venue/direct Bitcoin funding need not have a Dollars quote ref.
      r.c.read(pendingPolymarketBetProvider.notifier).setIntent(
          PendingBetIntent(
              tokenId: old.tokenId,
              amount: old.amount,
              slippagePct: old.slippagePct,
              marketQuestion: old.marketQuestion,
              outcomeName: old.outcomeName,
              expectedPrice: old.expectedPrice,
              status: PendingBetStatus.awaitingBalance,
              fundUsd: 10,
              fundedRunId: id,
              queuedAt: old.queuedAt,
              fundReadyUsd: 0,
              fundArrivingUsd: 10.6));
      r.trading.reads = _reads(pusd: 8, counted: 8);
      r.trading.land(8); // A proved net shortfall must not wait for the old quote.
      await settle(r.c);
      expect(r.trading.orders, hasLength(1));
      expect(r.trading.orderCosts.single, lessThanOrEqualTo(8 + 1e-6));
      expect(r.trading.orderCosts.single, lessThan(10));
    });
  }

  test('a tight completed landing covers fees at the fresh best ask and '
      'rounding headroom, not only the higher signed price', () async {
    final r = await start();
    final id = graph(r.c, const [
      MoneyStep(id: 'leg:investing', kind: MoneyStepKind.leg,
          from: MoneyPlace.investing, usd: 10.45, status: MoneyStepStatus.done),
    ]);
    r.c.read(pendingPolymarketBetProvider.notifier).setIntent(
        r.c.read(pendingPolymarketBetProvider)!.copyWith(
            fundedRunId: id, fundArrivingUsd: 10.6));
    r.trading.reads = _reads(pusd: 10.45, counted: 10.45);
    r.trading.land(10.6);
    await settle(r.c);
    expect(r.trading.orders, hasLength(1));
    expect(r.trading.orderCosts.single, lessThanOrEqualTo(10.45 + 1e-6));
  });

  group('a short reading is not a short landing until it holds (founder, 11 '
      'November 2026: "we place the bet, then an error comes saying that '
      'there is no money")', () {
    // The wallet's pUSD and USDC.e are two separate chain reads, answered
    // by whichever endpoint is first. Around the block a conversion is
    // mined in (or right after Orchestra says "delivered"), one can show
    // the wallet before and the other after: pUSD not yet there, USDC.e
    // already gone. With every leg reported done that read used to be
    // taken for a short landing: "Add funds to predict" with the money
    // there, or a smaller bet than the one accepted.
    Future<({ProviderContainer c, _Trading trading})> delivered(
        {required double held, required double arriving}) async {
      final r = await start();
      final id = graph(r.c, [
        MoneyStep(
            id: 'leg:dollars',
            kind: MoneyStepKind.leg,
            from: MoneyPlace.dollars,
            usd: arriving,
            status: MoneyStepStatus.done),
      ]);
      r.c.read(pendingPolymarketBetProvider.notifier).setIntent(r.c
          .read(pendingPolymarketBetProvider)!
          .copyWith(
              fundedRunId: id,
              fundReadyUsd: held,
              fundArrivingUsd: arriving));
      return (c: r.c, trading: r.trading);
    }

    setUp(() => PendingBetAutoFire.debugShortLandingGrace =
        const Duration(milliseconds: 300));
    tearDown(() => PendingBetAutoFire.debugShortLandingGrace = null);

    test(
        'cents of pUSD in the wallet, the conversion read torn: never "Add '
        'funds", the bet waits and is placed in full', () async {
      final r = await delivered(held: 0.3, arriving: 10.3);
      // Landed as USDC.e, every leg done: the one conversion starts.
      r.trading.reads = _reads(pusd: 0.3, usdce: 10.3, counted: 0.3);
      r.trading.land(10.6);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(r.trading.nudges, greaterThan(0));
      // The torn read: USDC.e already converted, pUSD not shown yet.
      r.trading.reads = _reads(pusd: 0.3, counted: 0.3);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final waiting = r.c.read(pendingPolymarketBetProvider)!;
      expect(waiting.status, PendingBetStatus.awaitingBalance,
          reason: waiting.failureCode);
      expect(r.trading.orders, isEmpty);
      // The next reads show the converted money.
      r.trading.reads = _reads(pusd: 10.6, counted: 10.6);
      await settle(r.c);
      expect(r.trading.orders, hasLength(1));
      expect(r.trading.orderCosts.single, greaterThan(10));
      expect(r.c.read(pendingPolymarketBetProvider)?.status,
          isNot(PendingBetStatus.failed));
    });

    test(
        'delivered by its status before our read shows it: waits for the '
        'chain, never "Add funds" on the cents that were there', () async {
      final r = await delivered(held: 0.3, arriving: 10.3);
      r.trading.reads = _reads(pusd: 0.3, counted: 0.3);
      r.trading.land(0.3);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final waiting = r.c.read(pendingPolymarketBetProvider)!;
      expect(waiting.status, PendingBetStatus.awaitingBalance,
          reason: waiting.failureCode);
      r.trading.reads = _reads(usdce: 10.3, pusd: 0.3, counted: 0.3);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      r.trading.reads = _reads(pusd: 10.6, counted: 10.6);
      await settle(r.c);
      expect(r.trading.orders, hasLength(1));
      expect(r.trading.orderCosts.single, greaterThan(10));
    });

    test(
        'dollars already in Predictions, the conversion read torn: the bet '
        'accepted is the bet placed, never a smaller one on the old cash',
        () async {
      final r = await delivered(held: 3, arriving: 7.6);
      r.trading.reads = _reads(pusd: 3, usdce: 7.6, counted: 3);
      r.trading.land(10.6);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      r.trading.reads = _reads(pusd: 3, counted: 3);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(r.trading.orders, isEmpty);
      expect(r.c.read(pendingPolymarketBetProvider)!.status,
          PendingBetStatus.awaitingBalance);
      r.trading.reads = _reads(pusd: 10.6, counted: 10.6);
      await settle(r.c);
      expect(r.trading.orders, hasLength(1));
      expect(r.trading.orderCosts.single, greaterThan(10));
    });

    test(
        'a landing that stays short is still what it was: sized from what '
        'landed once the reading has held, "Add funds" under the minimum',
        () async {
      PendingBetAutoFire.debugShortLandingGrace =
          const Duration(milliseconds: 250);
      final r = await delivered(held: 0, arriving: 10.6);
      r.trading.reads = _reads(pusd: 8, counted: 8);
      r.trading.land(8);
      await settle(r.c);
      expect(r.trading.orders, hasLength(1));
      expect(r.trading.orderCosts.single, lessThanOrEqualTo(8 + 1e-6));

      final s = await delivered(held: 0, arriving: 10.6);
      s.trading.reads = _reads(pusd: 0.4, counted: 0.4);
      s.trading.land(0.4);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(s.c.read(pendingPolymarketBetProvider)!.status,
          PendingBetStatus.awaitingBalance);
      await settle(s.c);
      final stopped = s.c.read(pendingPolymarketBetProvider)!;
      expect(stopped.status, PendingBetStatus.failed);
      expect(stopped.failureCode, 'insufficient_usdc');
      expect(s.trading.orders, isEmpty);
    });
  });

  test('skipped or previous legs alone cannot certify a short landing',
      () async {
    final r = await start();
    final id = graph(r.c, const [
      MoneyStep(
          id: 'prev:leg:bitcoin',
          kind: MoneyStepKind.leg,
          from: MoneyPlace.bitcoin,
          usd: 3.96,
          status: MoneyStepStatus.done),
      MoneyStep(
          id: 'leg:investing',
          kind: MoneyStepKind.leg,
          from: MoneyPlace.investing,
          status: MoneyStepStatus.skipped),
    ]);
    r.c.read(pendingPolymarketBetProvider.notifier).setIntent(r.c
        .read(pendingPolymarketBetProvider)!
        .copyWith(fundedRunId: id, fundArrivingUsd: 10.6));
    r.trading.reads = _reads(pusd: 9.9, counted: 9.9);
    r.trading.land(10.6);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(r.trading.orders, isEmpty);
    expect(r.c.read(pendingPolymarketBetProvider)!.readiness,
        PredictionsReadiness.waitingFunds);
  });

  test(
      'unknown book waits; an old async read cannot mutate a replacement '
      'same-token attempt', () async {
    final r = await start();
    r.trading.reads = _reads(pusd: 10.6);
    r.trading.land(10.6);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(r.trading.orders, isEmpty);
    expect(r.c.read(pendingPolymarketBetProvider)!.readiness,
        PredictionsReadiness.confirming);
    final read = Completer<PolyBuyReads?>();
    r.trading.deferredRead = read.future;
    await Future<void>.delayed(const Duration(milliseconds: 40));
    final replacement =
        _queued().copyWith(status: PendingBetStatus.awaitingDeposit);
    r.c.read(pendingPolymarketBetProvider.notifier).setIntent(replacement);
    read.complete(_reads(pusd: 10.6, counted: 10.6));
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(
        identical(r.c.read(pendingPolymarketBetProvider), replacement), isTrue);
    expect(r.trading.orders, isEmpty);
  });

  test('late accepted outcome preserves the replacement same-token intent',
      () async {
    final costBox = await Hive.openBox<double>('polymarket_cost_basis');
    await costBox.delete(_token);
    final r = await start();
    final posted = Completer<Map<String, dynamic>>();
    r.trading.deferredPost = posted.future;
    r.trading.land(10.6);
    for (var i = 0; i < 100 && r.trading.orders.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(r.trading.orders, hasLength(1));
    final oldCostObserver = r.c.read(polymarketCostBasisProvider.notifier);
    r.c.invalidate(polymarketCostBasisProvider);
    expect(oldCostObserver.mounted, isFalse);
    final replacement =
        _queued().copyWith(status: PendingBetStatus.awaitingDeposit);
    r.c.read(pendingPolymarketBetProvider.notifier).setIntent(replacement);
    posted.complete({
      'success': true,
      'status': 'matched',
      'orderID': 'old_order',
      'makingAmount': '3',
      'takingAmount': '6'
    });
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(
        identical(r.c.read(pendingPolymarketBetProvider), replacement), isTrue);
    expect(r.c.read(pendingPolymarketBetProvider)!.filledCost, isNull);
    expect(r.trading.orders, hasLength(1));
    expect(costBox.get(_token), 3, reason: 'the retired observer still persists the accepted fill');
  });

  test('an unread funded trading balance times out with a reason and no post',
      () async {
    PendingBetAutoFire.awaitPollInterval = const Duration(milliseconds: 10);
    PendingBetAutoFire.fundsTimeout = const Duration(milliseconds: 80);
    final r = await start();
    r.trading.reads = _reads(pusd: 10.6);
    r.trading.land(10.6);
    await settle(r.c);
    final stopped = r.c.read(pendingPolymarketBetProvider)!;
    expect(stopped.status, PendingBetStatus.failed);
    expect(stopped.failureCode, 'funds_timeout');
    expect(stopped.errorMessage, l10nForLanguage('en').betAutofireFundsTimeout);
    expect(r.trading.orders, isEmpty);
  });

  test('final collateral preflight pending remains a credit-stage stop', () async {
    final r = await start(refusals: List.filled(
        kAutofireNotReadyRetries + 1, const PolymarketCollateralPending()));
    OrderFundingJourney.instance.start(OneBalanceVenue.predictions,
        orderUsd: 10, fundUsd: 10, readyUsd: 0, dollarsUsd: 0);
    r.trading.land(10.6);
    await settle(r.c);
    final stopped = r.c.read(pendingPolymarketBetProvider)!;
    expect(stopped.failureCode, 'balance_confirmation_timeout');
    final failure = events.singleWhere((e) => e.$1 == 'order_funding_failed').$2!;
    expect(failure['stage'], 'credit');
    expect(failure['error_category'], 'timeout');
  });

  test(
      'delivered but still USDC.e: waits, nudges the conversion, then fires '
      'once converted and counted', () async {
    final r = await start();
    r.trading.reads = _reads(usdce: 10.6, counted: 0);
    r.trading.land(10.6);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    var pending = r.c.read(pendingPolymarketBetProvider)!;
    expect(r.trading.orders, isEmpty, reason: 'nothing signed before usable');
    expect(pending.status, PendingBetStatus.awaitingBalance);
    expect(pending.readiness, PredictionsReadiness.converting);
    expect(pending.convertSeen, isTrue);
    expect(r.trading.nudges, greaterThan(0));
    expect(r.trading.refreshAsks.length, greaterThan(2),
        reason: 'read again every poll');

    // Converted; the book still counts the old balance: confirming, and
    // the book is asked to re-read.
    r.trading.reads = _reads(pusd: 10.6, counted: 0);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    pending = r.c.read(pendingPolymarketBetProvider)!;
    expect(r.trading.orders, isEmpty);
    expect(pending.readiness, PredictionsReadiness.confirming);
    expect(r.trading.refreshAsks.last, isTrue);

    r.trading.reads = _reads(pusd: 10.6, counted: 10.6);
    await settle(r.c);
    expect(r.trading.orders, hasLength(1));
    expect(r.atPlacing, [PredictionsReadiness.confirming]);
    final done = r.c.read(pendingPolymarketBetProvider)!;
    expect(done.status, PendingBetStatus.awaitingConfirmation);
    expect(done.convertSeen, isTrue);
    expect(done.approveSeen, isFalse);
    expect(events.where((e) => e.$1 == 'polymarket_bet_failed'), isEmpty);
  });

  test('the book says not enough balance once: waits for it, then the '
      'automatic send again goes through under the same approval', () async {
    final r = await start(refusals: [const PolymarketBalanceRefused(_balance)]);
    r.trading.reads = _reads(pusd: 10.6, counted: 10.6);
    // The refusal: the book has not counted the money after all.
    r.trading.onRefused =
        () => r.trading.reads = _reads(pusd: 10.6, counted: 0);
    r.trading.land(10.6);
    for (var i = 0; i < 100 && r.trading.orders.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final waiting = r.c.read(pendingPolymarketBetProvider)!;
    expect(r.trading.orders, hasLength(1));
    expect(waiting.status, PendingBetStatus.placing,
        reason: 'not a failure while the money is not counted yet');
    expect(waiting.readiness, PredictionsReadiness.confirming);

    r.trading.reads = _reads(pusd: 10.6, counted: 10.6);
    await settle(r.c);
    expect(r.trading.orders, hasLength(2));
    final pending = r.c.read(pendingPolymarketBetProvider)!;
    expect(pending.status, PendingBetStatus.awaitingConfirmation);
    expect(pending.fundUsd, 10, reason: 'the same move, nothing funded again');
    expect(events.where((e) => e.$1 == 'polymarket_bet_failed'), isEmpty);
    expect(PredictionFundingLedger.instance.record('ref_move')!.releaseReason,
        'placed');
  });

  test(
      'refused for balance and the wallet reads short for good: the next '
      'order is sized to what is there, never the whole funds wait', () async {
    PendingBetAutoFire.debugShortLandingGrace =
        const Duration(milliseconds: 60);
    addTearDown(() => PendingBetAutoFire.debugShortLandingGrace = null);
    final r = await start(refusals: [const PolymarketBalanceRefused(_balance)]);
    r.trading.reads = _reads(pusd: 10.6, counted: 10.6);
    // By the post the wallet holds less than the order costs (another
    // order of the person's took part of it): the venue refuses it.
    r.trading.onRefused = () => r.trading.reads = _reads(pusd: 8, counted: 8);
    r.trading.land(10.6);
    await settle(r.c);
    expect(r.trading.orders, hasLength(2),
        reason: 'sent again for what is there, in seconds');
    expect(r.trading.orderCosts.last, lessThanOrEqualTo(8));
    expect(r.trading.orderCosts.last, greaterThan(7));
    expect(r.c.read(pendingPolymarketBetProvider)!.status,
        PendingBetStatus.awaitingConfirmation);
    expect(events.where((e) => e.$1 == 'polymarket_bet_failed'), isEmpty);
  });

  group('funded from Bitcoin: the executor\'s own grant check', () {
    // Founder, 19 October 2026: "Moved \$5.30 from Bitcoin", then
    // `[pm-autofire] failed: ReauthRequired(other)` at placeOrder's
    // GrantGuard.consume. The chained order grant bound the funding leg
    // (fundingUsd, fundingVenue, fundBtc, directLegs); the order placeOrder
    // rebuilt did not carry them, so each read as drifted.
    final btcLeg = BitcoinLegGrants.limit(maxSats: 6000, ownSpark: 'spark1own');
    final directLegs = <String, Object?>{
      'to': IntentVenue.polymarket,
      'legs': {'hyperliquid': '300000'},
      'total': '300000',
    };

    test('the money landed: placed once, no ReauthRequired', () async {
      final r = await start(btcLeg: btcLeg, directLegs: directLegs);
      r.trading.land(10.6);
      await settle(r.c);
      expect(r.trading.orders, hasLength(1));
      final pending = r.c.read(pendingPolymarketBetProvider)!;
      expect(pending.status, PendingBetStatus.awaitingConfirmation,
          reason: pending.errorMessage);
      expect(events.where((e) => e.$1 == 'polymarket_bet_failed'), isEmpty);
    });

    test('a "not usable yet" refusal: the send again (autofireRetryGrant) '
        'passes the same check, placed once more, never twice', () async {
      final r = await start(
          btcLeg: btcLeg,
          directLegs: directLegs,
          refusals: [const PolymarketBalanceRefused(_balance)]);
      r.trading.land(10.6);
      await settle(r.c);
      expect(r.trading.orders, hasLength(2));
      final pending = r.c.read(pendingPolymarketBetProvider)!;
      expect(pending.status, PendingBetStatus.awaitingConfirmation,
          reason: pending.errorMessage);
      expect(events.where((e) => e.$1 == 'polymarket_bet_failed'), isEmpty);
    });

    test('a grant refusal at the executor is never sent again: approval '
        'copy, approval_drift, the money stays in Predictions', () async {
      final r = await start(
          btcLeg: btcLeg,
          directLegs: directLegs,
          refusals: [
            ReauthRequired(const {DriftField.price}),
            const PolymarketBalanceRefused(_balance),
          ]);
      r.trading.land(10.6);
      await settle(r.c);
      expect(r.trading.orders, hasLength(1), reason: 'no send again');
      final pending = r.c.read(pendingPolymarketBetProvider)!;
      expect(pending.status, PendingBetStatus.failed);
      expect(pending.errorMessage,
          l10nForLanguage('en').stepUpDetailsChanged);
      final failed =
          events.where((e) => e.$1 == 'polymarket_bet_failed').single.$2!;
      expect(failed['reason'], 'approval_drift');
      expect(PredictionFundingLedger.instance.record('ref_move')!.releaseReason,
          'failed');
    });
  });

  test('the order\'s setup met the deposit wallet busy (a conversion still '
      'confirming): waited out, then the bet is placed', () async {
    const busy = 'Relayer submit failed: 400 '
        '{"error":"wallet busy: active action exists"}';
    final r = await start(refusals: [
      PolymarketSetupIncomplete(cause: Exception(busy)),
      // Raw, as a setup that does not wrap it would throw.
      Exception('Relayer submit failed: 400 {"error":"batch nonce 16 does '
          'not match on-chain nonce 17"}'),
    ]);
    r.trading.reads = _reads(pusd: 10.6, counted: 10.6);
    r.trading.land(10.6);
    await settle(r.c);
    expect(r.trading.orders, hasLength(3));
    final pending = r.c.read(pendingPolymarketBetProvider)!;
    expect(pending.status, PendingBetStatus.awaitingConfirmation);
    expect(events.where((e) => e.$1 == 'polymarket_bet_failed'), isEmpty);
  });

  test('a real failure still shows, and the debug log names its cause',
      () async {
    final logged = <String>[];
    final previous = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => logged.add(m ?? '');
    addTearDown(() => debugPrint = previous);
    final r = await start(refusals: [StateError('the venue said no')]);
    r.trading.reads = _reads(pusd: 10.6, counted: 10.6);
    r.trading.land(10.6);
    await settle(r.c);
    final pending = r.c.read(pendingPolymarketBetProvider)!;
    expect(pending.status, PendingBetStatus.failed);
    expect(pending.errorMessage, l10nForLanguage('en').betActionNotCompleted);
    expect(
        logged.any((l) =>
            l.startsWith('[pm-autofire] failed: Bad state: the venue said no')),
        isTrue);
    expect(logged.any((l) => l.contains('[pm-autofire] generic failure copy')),
        isTrue);
  });

  test('bounded: after the most sends again the failure shows', () async {
    final r = await start(
        refusals: List.filled(kAutofireNotReadyRetries + 1,
            const PolymarketBalanceRefused(_balance)));
    r.trading.land(10.6);
    await settle(r.c);
    expect(r.trading.orders, hasLength(1 + kAutofireNotReadyRetries));
    final pending = r.c.read(pendingPolymarketBetProvider)!;
    expect(pending.status, PendingBetStatus.failed);
    expect(PredictionFundingLedger.instance.record('ref_move')!.releaseReason,
        'failed');
  });

  test('a price that moved is a real failure: shown, never waited on',
      () async {
    final r = await start(refusals: [
      const PolymarketOrderNotAcceptedException(_noMatch),
      const PolymarketOrderNotAcceptedException(_noMatch),
    ]);
    r.trading.land(10.6);
    await settle(r.c);
    expect(r.trading.orders, hasLength(2), reason: 'the one re-priced order');
    final pending = r.c.read(pendingPolymarketBetProvider)!;
    expect(pending.status, PendingBetStatus.failed);
    expect(pending.errorMessage,
        l10nForLanguage('en').betBuyLiquidityUnavailable);
  });

  test('a round that closed while the money converted: market closed, '
      'nothing signed', () async {
    final r = await start(
        endAt: DateTime.now().add(const Duration(milliseconds: 150)));
    r.trading.reads = _reads(usdce: 10.6, counted: 0);
    r.trading.land(10.6);
    await settle(r.c);
    expect(r.trading.orders, isEmpty);
    final pending = r.c.read(pendingPolymarketBetProvider)!;
    expect(pending.status, PendingBetStatus.failed);
    expect(pending.failureCode, 'market_closed');
    expect(pending.errorMessage, l10nForLanguage('en').slipFundingRoundClosed);
  });

  group('a 5-minute crypto round (founder, 19 October 2026)', () {
    // A Bitcoin-funded bet takes 20 to 40 s to move and wrap; a 5-minute
    // round's price swings meanwhile. Past the approval: said plainly with
    // the price now, and the slip's one tap approves again at it. Ended:
    // said plainly, the money in Predictions. Other markets unchanged.
    const slug = 'btc-updown-5m-1791152100';
    Map<String, Object> failedEvent() =>
        events.where((e) => e.$1 == 'polymarket_bet_failed').single.$2!;

    test('the book past the approval once the money landed: the price now, '
        'a retry at it, never placed by itself', () async {
      final r = await start(
          slug: slug,
          ask: () => '0.70',
          endAt: DateTime.now().add(const Duration(minutes: 3)));
      r.trading.land(10.6);
      await settle(r.c);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(r.trading.orders, isEmpty, reason: 'nothing auto-placed');
      final pending = r.c.read(pendingPolymarketBetProvider)!;
      expect(pending.status, PendingBetStatus.failed);
      expect(pending.failureCode, 'round_price_moved');
      expect(pending.movedToPrice, closeTo(0.70, 1e-9));
      expect(pending.retryMaxPrice, isNotNull);
      expect(pending.errorMessage,
          'Price changed to 70% while your money was moving.');
      // The round not started yet: the retry is on it, at the price now.
      final before = DateTime.fromMillisecondsSinceEpoch(
          (1791152100 - 60) * 1000,
          isUtc: true);
      expect(betSlipStopAction(l10nForLanguage('en'), pending, now: before),
          (label: 'Retry at 70%', nextRound: false));
      // In play by now: never on it (founder, 12 November 2026), the retry
      // opens the series' next round.
      expect(betSlipStopAction(l10nForLanguage('en'), pending),
          (label: 'Retry', nextRound: true));
      // Once it has ended, the retry opens the series' round in play.
      expect(
          betSlipStopAction(l10nForLanguage('en'), pending,
              now: DateTime.now().add(const Duration(hours: 1))),
          (label: 'Retry', nextRound: true));
      // The confirm-time approval does not cover the new price: the retry
      // has to approve again.
      final review = PmGrants.betReview(
          walletId: 'spending',
          tokenId: _token,
          maxCostUsd: 10.5,
          worstPrice: polymarketFundedWorstPrice(pending),
          orderType: OrderType.fak.name);
      final atNewPrice = PmIntents.order(
          walletId: 'spending',
          tokenId: _token,
          isBuy: true,
          amountMax: PmGrants.buyCostMicros(14, pending.retryMaxPrice!),
          limitPrice: pending.retryMaxPrice!,
          orderType: OrderType.fak.name);
      expect(AuthGrants.driftBetween(review, atNewPrice),
          contains(DriftField.price));
      final failed = failedEvent();
      expect(failed['reason'], 'price_moved');
      expect(failed['market_kind'], 'crypto_updown_5m');
      expect(PredictionFundingLedger.instance.record('ref_move')!.releaseReason,
          'failed');
    });

    test('killed for its price twice and the book moved past the approval: '
        'the same', () async {
      var ask = '0.48';
      final r = await start(
          slug: slug,
          ask: () => ask,
          refusals: [
            const PolymarketOrderNotAcceptedException(_noMatch),
            const PolymarketOrderNotAcceptedException(_noMatch),
          ]);
      var refused = 0;
      r.trading.onRefused = () {
        if (++refused == 2) ask = '0.66';
      };
      r.trading.land(10.6);
      await settle(r.c);
      expect(r.trading.orders, hasLength(2), reason: 'the one re-priced order');
      final pending = r.c.read(pendingPolymarketBetProvider)!;
      expect(pending.failureCode, 'round_price_moved');
      expect(pending.errorMessage,
          'Price changed to 66% while your money was moving.');
      expect(failedEvent()['reason'], 'price_moved');
    });

    test('killed twice with the book still inside the approval: the '
        'venue\'s own words, as before', () async {
      final r = await start(slug: slug, refusals: [
        const PolymarketOrderNotAcceptedException(_noMatch),
        const PolymarketOrderNotAcceptedException(_noMatch),
      ]);
      r.trading.land(10.6);
      await settle(r.c);
      final pending = r.c.read(pendingPolymarketBetProvider)!;
      expect(pending.errorMessage,
          l10nForLanguage('en').betBuyLiquidityUnavailable);
      expect(pending.movedToPrice, isNull);
      expect(failedEvent()['market_kind'], 'crypto_updown_5m');
    });

    test('the round ended while the money was moving: said so, the money '
        'kept, Retry on the round in play', () async {
      final r = await start(
          slug: slug,
          endAt: DateTime.now().add(const Duration(milliseconds: 150)));
      r.trading.reads = _reads(usdce: 10.6, counted: 0);
      r.trading.land(10.6);
      await settle(r.c);
      expect(r.trading.orders, isEmpty);
      final pending = r.c.read(pendingPolymarketBetProvider)!;
      expect(pending.status, PendingBetStatus.failed);
      expect(pending.failureCode, 'round_ended');
      expect(
          pending.errorMessage,
          r'This round ended while your money was moving. Your $10.00 is in '
          'Predictions.');
      expect(betSlipStopAction(l10nForLanguage('en'), pending),
          (label: 'Retry', nextRound: true));
      final failed = failedEvent();
      expect(failed['reason'], 'round_ended');
      expect(failed['market_kind'], 'crypto_updown_5m');
      // Nothing placed: the money is released as Predictions cash.
      expect(PredictionFundingLedger.instance.record('ref_move')!.releaseReason,
          'failed');
    });

    test('the round ended before the money landed: funded anyway, waits '
        'for it, then nothing placed and Retry on the round in play',
        () async {
      final r = await start(
          slug: slug,
          endAt: DateTime.now().subtract(const Duration(seconds: 5)));
      await Future<void>.delayed(const Duration(milliseconds: 120));
      // Still waiting for its money: not failed early, so a Retry finds
      // the money in Predictions and moves nothing twice.
      expect(r.c.read(pendingPolymarketBetProvider)!.status,
          PendingBetStatus.awaitingBalance);
      expect(r.trading.orders, isEmpty);
      r.trading.land(10.6);
      await settle(r.c);
      expect(r.trading.orders, isEmpty, reason: 'nothing auto-placed');
      final pending = r.c.read(pendingPolymarketBetProvider)!;
      expect(pending.status, PendingBetStatus.failed);
      expect(pending.failureCode, 'round_ended');
      expect(
          pending.errorMessage,
          r'This round ended while your money was moving. Your $10.00 is in '
          'Predictions.');
      expect(betSlipStopAction(l10nForLanguage('en'), pending),
          (label: 'Retry', nextRound: true));
      expect(betSlipRetriesNextRound(pending), isTrue);
      expect(PredictionFundingLedger.instance.record('ref_move')!.releaseReason,
          'failed');
    });

    test('landed inside the approval on an open round: placed as before',
        () async {
      final r = await start(
          slug: slug, endAt: DateTime.now().add(const Duration(minutes: 3)));
      r.trading.land(10.6);
      await settle(r.c);
      expect(r.trading.orders, hasLength(1));
      expect(r.c.read(pendingPolymarketBetProvider)!.failureCode, isNull);
    });

    test('any other market whose price moved: unchanged', () async {
      final r = await start(ask: () => '0.70');
      r.trading.land(10.6);
      await settle(r.c);
      expect(r.trading.orders, isEmpty);
      final pending = r.c.read(pendingPolymarketBetProvider)!;
      expect(pending.failureCode, 'price_moved');
      expect(pending.movedToPrice, isNull);
      expect(pending.retryMaxPrice, isNotNull);
      expect(pending.errorMessage, isNot(contains('while your money')));
      expect(betSlipStopAction(l10nForLanguage('en'), pending).label,
          startsWith('Retry at '));
      expect(betSlipStopAction(l10nForLanguage('en'), pending).label,
          endsWith('¢'));
      final failed = failedEvent();
      expect(failed['reason'], 'liquidity_unavailable');
      expect(failed.containsKey('market_kind'), isFalse);
    });
  });

  test('the approval running out while it waits asks for a new confirm',
      () async {
    final r = await start(refusals: [const PolymarketBalanceRefused(_balance)]);
    r.trading.onRefused = () {
      r.trading.reads = _reads(pusd: 10.6, counted: 0);
      AuthGrants.clock = () => DateTime.now().add(const Duration(hours: 1));
    };
    r.trading.land(10.6);
    await settle(r.c);
    expect(r.trading.orders, hasLength(1));
    final pending = r.c.read(pendingPolymarketBetProvider)!;
    expect(pending.status, PendingBetStatus.failed);
    expect(pending.failureCode, 'approval_expired');
    expect(pending.errorMessage, l10nForLanguage('en').pendingIntentExpired);
  });
  // Founder, 19 October 2026: a bet funded from Bitcoin showed "Moved
  // $4.73 from Bitcoin ✓", then "Confirming balance" failed with "This
  // action did not complete. ... Your $4.43 is in Predictions." The money
  // had landed; the order's own pre-sign step (the spend approval it sets,
  // the book's count of the new pUSD) was not through yet, and the five
  // sends again were spent within seconds because the readiness read
  // looked ready at once. The waits below take well past those five
  // sends' worth of time; the fix waits them out, spaced, bounded by time.
  group('a bet for the next window whose money lands late (founder, 8 '
      'November 2026)', () {
    // The card's buttons roll to the next window partway through this one,
    // so a funded bet can land before that window starts or after. The
    // existing rules apply unchanged: on the tokens it was approved for,
    // from a fresh book, under the approved worst price, or not at all.
    String nextSlug(DateTime start) =>
        'btc-updown-5m-${start.millisecondsSinceEpoch ~/ 1000}';
    Map<String, Object> failedEvent() =>
        events.where((e) => e.$1 == 'polymarket_bet_failed').single.$2!;

    test('landed before it starts: placed on its own tokens under the '
        'approval, reported as the next window', () async {
      final start = DateTime.now().add(const Duration(minutes: 2));
      final r = await start_(
          start, slug: nextSlug(start), ask: () => '0.48',
          endAt: start.add(const Duration(minutes: 5)));
      r.trading.land(10.6);
      await settle(r.c);
      expect(r.trading.orders, hasLength(1));
      expect(r.trading.orders.single, lessThanOrEqualTo(0.55 + 1e-9));
      expect(r.c.read(pendingPolymarketBetProvider)!.failureCode, isNull);
    });

    test('landed after it started, the price inside the approval: placed '
        'as any open round', () async {
      final start = DateTime.now().subtract(const Duration(seconds: 40));
      final r = await start_(
          start, slug: nextSlug(start), ask: () => '0.50',
          endAt: start.add(const Duration(minutes: 5)));
      r.trading.land(10.6);
      await settle(r.c);
      expect(r.trading.orders, hasLength(1));
      expect(r.c.read(pendingPolymarketBetProvider)!.failureCode, isNull);
    });

    test('landed after it started, the price moved past the approval: '
        'nothing placed, the price now said, the retry asks again', () async {
      final start = DateTime.now().subtract(const Duration(seconds: 40));
      final r = await start_(
          start, slug: nextSlug(start), ask: () => '0.81',
          endAt: start.add(const Duration(minutes: 5)));
      r.trading.land(10.6);
      await settle(r.c);
      expect(r.trading.orders, isEmpty, reason: 'never at a price not seen');
      final pending = r.c.read(pendingPolymarketBetProvider)!;
      expect(pending.failureCode, 'round_price_moved');
      expect(pending.errorMessage,
          'Price changed to 81% while your money was moving.');
      // The round is in play by now, still before its two-minute cutoff
      // (founder, 12 November 2026: the round in play is bet until then):
      // the retry asks again on this round, at the price now.
      expect(betSlipStopAction(l10nForLanguage('en'), pending),
          (label: 'Retry at 81%', nextRound: false));
      final failed = failedEvent();
      expect(failed['window'], 'next',
          reason: 'still the window the slip opened on');
      expect(failed['seconds_to_window_end'], isA<int>());
      expect(failed['seconds_to_window_end'] as int, inInclusiveRange(200, 260));
    });

    test('landed after that window ended: nothing placed, the money in '
        'Predictions, Retry on the round in play', () async {
      final start = DateTime.now().subtract(const Duration(minutes: 6));
      final r = await start_(
          start, slug: nextSlug(start),
          endAt: start.add(const Duration(minutes: 5)));
      r.trading.land(10.6);
      await settle(r.c);
      expect(r.trading.orders, isEmpty);
      final pending = r.c.read(pendingPolymarketBetProvider)!;
      expect(pending.failureCode, 'round_ended');
      expect(betSlipStopAction(l10nForLanguage('en'), pending),
          (label: 'Retry', nextRound: true));
      expect(failedEvent()['window'], 'next');
    });

    test('a round is known by its slug, whatever the question reads', () {
      final ended = _queued(
          endAt: DateTime.now().subtract(const Duration(seconds: 1)),
          slug: 'btc-updown-5m-1791152100',
          question: 'BTC hoch oder runter · 7:20–7:25');
      expect(autofireRoundClosed(ended), isTrue);
    });
  });

  group('confirming late, after the money landed', () {
    test(
        'the spend approval mined late: waited out under the same approval, '
        'then placed once, no retry by hand', () async {
      final r = await start();
      r.trading.reads = _reads(pusd: 10.6, counted: 10.6);
      var refused = 0;
      r.trading.onRefused = () => refused++;
      final minedAt = DateTime.now().add(const Duration(milliseconds: 600));
      r.trading.refuseWith = () => DateTime.now().isBefore(minedAt)
          ? const PolymarketSetupIncomplete(timedOut: true)
          : null;
      r.trading.land(10.6);
      await settle(r.c);
      final pending = r.c.read(pendingPolymarketBetProvider)!;
      expect(pending.status, PendingBetStatus.awaitingConfirmation,
          reason: 'placed without the person retrying');
      expect(refused, greaterThan(5),
          reason: 'more sends than the old budget allowed');
      expect(r.trading.orders.length - refused, 1,
          reason: 'exactly one order accepted: never placed twice');
      expect(pending.readiness, PredictionsReadiness.ready);
      // Every send priced from a fresh book, never past what was approved.
      final worst = polymarketFundedWorstPrice(_queued());
      expect(r.trading.orders.every((p) => p <= worst + 1e-9), isTrue);
      expect(pending.fundUsd, 10, reason: 'the same move, nothing funded again');
      // Each look while waiting asked the book to re-read.
      expect(r.trading.refreshAsks, contains(true));
      expect(events.where((e) => e.$1 == 'polymarket_bet_failed'), isEmpty);
      expect(PredictionFundingLedger.instance.record('ref_move')!.releaseReason,
          'placed');
    });

    test(
        'the book counts the deposit late, though the readiness read looks '
        'ready: waited out, then placed', () async {
      final r = await start();
      r.trading.reads = _reads(pusd: 10.6, counted: 10.6);
      var refused = 0;
      r.trading.onRefused = () => refused++;
      final countedAt = DateTime.now().add(const Duration(milliseconds: 600));
      r.trading.refuseWith = () => DateTime.now().isBefore(countedAt)
          ? const PolymarketCollateralPending()
          : null;
      r.trading.land(10.6);
      await settle(r.c);
      final pending = r.c.read(pendingPolymarketBetProvider)!;
      expect(pending.status, PendingBetStatus.awaitingConfirmation);
      expect(refused, greaterThan(5));
      expect(r.trading.orders.length - refused, 1);
      expect(r.trading.refreshAsks, contains(true));
      expect(events.where((e) => e.$1 == 'polymarket_bet_failed'), isEmpty);
    });

    test(
        'never confirmed within the wait: today\'s safe copy, the step that '
        'did not clear named, nothing placed', () async {
      PendingBetAutoFire.fundsTimeout = const Duration(milliseconds: 250);
      final r = await start();
      OrderFundingJourney.instance.start(OneBalanceVenue.predictions,
          orderUsd: 10, fundUsd: 10, readyUsd: 0, dollarsUsd: 0);
      r.trading.reads = _reads(pusd: 10.6, counted: 10.6);
      var refused = 0;
      r.trading.onRefused = () => refused++;
      r.trading.refuseWith =
          () => const PolymarketSetupIncomplete(timedOut: true);
      r.trading.land(10.6);
      await settle(r.c);
      final stopped = r.c.read(pendingPolymarketBetProvider)!;
      expect(stopped.status, PendingBetStatus.failed);
      expect(stopped.errorMessage, l10nForLanguage('en').betActionNotCompleted);
      expect(stopped.failureCode, 'approval_timeout');
      expect(r.trading.orders.length, refused, reason: 'nothing accepted');
      expect(refused, lessThanOrEqualTo(1 + kAutofireNotReadyRetries));
      final failed =
          events.singleWhere((e) => e.$1 == 'polymarket_bet_failed').$2!;
      expect(failed['reason'], 'approval_timeout');
      final funding =
          events.singleWhere((e) => e.$1 == 'order_funding_failed').$2!;
      expect(funding['stage'], 'credit');
      expect(funding['error_category'], 'timeout');
      expect(PredictionFundingLedger.instance.record('ref_move')!.releaseReason,
          'failed');
    });
  });
}
