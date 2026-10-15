// A bet funded from Dollars fires only once its money is usable by the
// order book, not when it is merely delivered (founder, 15 October 2026:
// "$3.68 on Yes" failed with "This action did not complete" because the
// deposit was still USDC.e / not counted by the book when the order went
// out). The bet waits while the deposit converts and the book catches up,
// moves to `placing` only once ready, and a venue refusal that only says
// "not usable yet" is sent again under the same approval, a few times at
// most. A real failure still shows. Fakes only: nothing is signed or sent.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/prediction_funding_ledger.dart';
import 'package:kute/services/polymarket/market_buy_quote.dart';
import 'package:kute/services/polymarket/order_refusal.dart'
    show PolymarketBalanceRefused;
import 'package:kute/services/polymarket/placement_waits.dart'
    show PolymarketFundsConverting;
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

  /// What the readiness read answers; null = nothing to read.
  PolyBuyReads? reads;
  final refreshAsks = <bool>[];
  var nudges = 0;
  final orders = <double>[];
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
    return reads;
  }

  @override
  void nudgeConversion() => nudges++;

  @override
  Future<void> readyCollateralForBuy(double costUsd) async {}

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
    // The grant covers exactly this order, as the real executor checks.
    final order = PmGrants.executedOrder(grant,
        walletId: 'spending',
        tokenId: tokenId,
        isBuy: true,
        size: size,
        price: price,
        orderType: orderType.name);
    AuthGrants.consume(
        grant,
        order.copyWith(limits: {
          ...order.limits,
          ...PmGrants.fundingLimits(fundUsd: 10, venue: IntentVenue.polymarket),
        }));
    orders.add(price);
    if (refusals.isNotEmpty) {
      final refusal = refusals.removeAt(0);
      onRefused?.call();
      throw refusal;
    }
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
PendingBetIntent _queued({DateTime? endAt}) => PendingBetIntent(
      tokenId: _token,
      amount: 10,
      slippagePct: 5,
      marketQuestion: 'Bitcoin Up or Down - October 13, 2:00PM-2:05PM ET',
      outcomeName: 'Up',
      expectedPrice: 0.5,
      status: PendingBetStatus.awaitingBalance,
      fundUsd: 10,
      fundQuoteRef: 'ref_move',
      fundReadyUsd: 0,
      fundArrivingUsd: 9.9,
      queuedAt: DateTime.now(),
      marketEndAt: endAt,
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
    PendingBetAutoFire.readyPollInterval = const Duration(milliseconds: 10);
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });

  tearDown(() {
    TrackingService.debugTrackObserver = null;
    AuthGrants.clock = DateTime.now;
    PendingBetAutoFire.readyPollInterval = const Duration(seconds: 1);
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

    test('delivered as USDC.e: converting, whatever the summed cash says',
        () {
      expect(at(_reads(usdce: 10.4, counted: 0)),
          PredictionsReadiness.converting);
      // Part converted: still converting.
      expect(at(_reads(pusd: 5, usdce: 5.4, counted: 5)),
          PredictionsReadiness.converting);
    });

    test('nothing usable yet: waiting for the funds', () {
      expect(at(_reads(counted: 0)), PredictionsReadiness.waitingFunds);
    });

    test('setup running or an allowance short: approving', () {
      expect(at(_reads(pusd: 10.4, counted: 10.4, setupDone: false)),
          PredictionsReadiness.approving);
      final short = PolyVenueCount(
          balance: _usd(10.4), allowances: {'0xexchange': BigInt.zero});
      expect(
          autofireReadiness(
              pusd: _usd(10.4),
              usdce: BigInt.zero,
              costMicros: cost,
              venue: short,
              spenders: spenders,
              setupDone: true),
          PredictionsReadiness.approving);
    });

    test('pUSD there but the book counts the old balance: confirming', () {
      expect(at(_reads(pusd: 10.4, counted: 0)),
          PredictionsReadiness.confirming);
    });

    test('pUSD there and counted: ready; a book that cannot be read is not '
        'waited on', () {
      expect(at(_reads(pusd: 10.4, counted: 10.4)), PredictionsReadiness.ready);
      expect(at(_reads(pusd: 10.4)), PredictionsReadiness.ready);
    });

    test('landed short: ready on what landed, once counted', () {
      expect(at(_reads(pusd: 9.6, counted: 9.6)), PredictionsReadiness.ready);
      expect(at(_reads(pusd: 9.6, counted: 0)),
          PredictionsReadiness.confirming);
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
    });
  });

  /// Queues the funded bet with its one approval and wires the fakes.
  Future<({ProviderContainer c, _Trading trading, List<PredictionsReadiness?> atPlacing})>
      start({List<Object> refusals = const [], DateTime? endAt}) async {
    final trading = _Trading([...refusals]);
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
              {'price': '0.48', 'size': '1000'}
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

    final intent = _queued(endAt: endAt);
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
            venue: IntentVenue.polymarket),
        method: AuthGrantMethod.biometric);
    PredictionFundingLedger.instance.sent('ref_move', usd: 10);
    c.read(pendingPolymarketBetProvider.notifier).setIntent(intent);
    return (c: c, trading: trading, atPlacing: atPlacing);
  }

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

  test('delivered but still USDC.e: waits, nudges the conversion, then fires '
      'once converted and counted', () async {
    final r = await start();
    r.trading.reads = _reads(usdce: 10.4, counted: 0);
    r.trading.land(10.4);
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
    r.trading.reads = _reads(pusd: 10.4, counted: 0);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    pending = r.c.read(pendingPolymarketBetProvider)!;
    expect(r.trading.orders, isEmpty);
    expect(pending.readiness, PredictionsReadiness.confirming);
    expect(r.trading.refreshAsks.last, isTrue);

    r.trading.reads = _reads(pusd: 10.4, counted: 10.4);
    await settle(r.c);
    expect(r.trading.orders, hasLength(1));
    expect(r.atPlacing, [PredictionsReadiness.ready]);
    final done = r.c.read(pendingPolymarketBetProvider)!;
    expect(done.status, PendingBetStatus.awaitingConfirmation);
    expect(done.convertSeen, isTrue);
    expect(done.approveSeen, isFalse);
    expect(events.where((e) => e.$1 == 'polymarket_bet_failed'), isEmpty);
  });

  test('the book says not enough balance once: waits for it, then the '
      'automatic send again goes through under the same approval', () async {
    final r = await start(refusals: [const PolymarketBalanceRefused(_balance)]);
    r.trading.reads = _reads(pusd: 10.4, counted: 10.4);
    // The refusal: the book has not counted the money after all.
    r.trading.onRefused = () => r.trading.reads = _reads(pusd: 10.4, counted: 0);
    r.trading.land(10.4);
    for (var i = 0; i < 100 && r.trading.orders.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final waiting = r.c.read(pendingPolymarketBetProvider)!;
    expect(r.trading.orders, hasLength(1));
    expect(waiting.status, PendingBetStatus.placing,
        reason: 'not a failure while the money is not counted yet');
    expect(waiting.readiness, PredictionsReadiness.confirming);

    r.trading.reads = _reads(pusd: 10.4, counted: 10.4);
    await settle(r.c);
    expect(r.trading.orders, hasLength(2));
    final pending = r.c.read(pendingPolymarketBetProvider)!;
    expect(pending.status, PendingBetStatus.awaitingConfirmation);
    expect(pending.fundUsd, 10, reason: 'the same move, nothing funded again');
    expect(events.where((e) => e.$1 == 'polymarket_bet_failed'), isEmpty);
    expect(PredictionFundingLedger.instance.record('ref_move')!.releaseReason,
        'placed');
  });

  test('bounded: after five sends again the failure shows', () async {
    final r = await start(
        refusals: List.filled(6, const PolymarketBalanceRefused(_balance)));
    r.trading.land(10.4);
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
    r.trading.land(10.4);
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
    r.trading.reads = _reads(usdce: 10.4, counted: 0);
    r.trading.land(10.4);
    await settle(r.c);
    expect(r.trading.orders, isEmpty);
    final pending = r.c.read(pendingPolymarketBetProvider)!;
    expect(pending.status, PendingBetStatus.failed);
    expect(pending.failureCode, 'market_closed');
    expect(pending.errorMessage, l10nForLanguage('en').slipFundingRoundClosed);
  });

  test('the approval running out while it waits asks for a new confirm',
      () async {
    final r = await start(refusals: [const PolymarketBalanceRefused(_balance)]);
    r.trading.onRefused = () {
      r.trading.reads = _reads(pusd: 10.4, counted: 0);
      AuthGrants.clock = () => DateTime.now().add(const Duration(hours: 1));
    };
    r.trading.land(10.4);
    await settle(r.c);
    expect(r.trading.orders, hasLength(1));
    final pending = r.c.read(pendingPolymarketBetProvider)!;
    expect(pending.status, PendingBetStatus.failed);
    expect(pending.failureCode, 'approval_expired');
    expect(pending.errorMessage, l10nForLanguage('en').pendingIntentExpired);
  });
}
