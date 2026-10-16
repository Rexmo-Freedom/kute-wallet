// A bet funded from Dollars on a fast market (a five-minute round, a game
// in play) used to be signed at the odds the slip showed at the tap, once
// the money had landed tens of seconds later: the book had moved and the
// fill-and-kill was killed. Now the book is read after the money lands,
// the order is priced from it under the one approval, a price refusal is
// re-read and re-priced once (no second funding), and a final failure
// releases the move's cash: it stays as available Predictions cash.
// Fakes only: nothing is signed or sent.

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
import 'package:kute/providers/polymarket_cost_basis_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/venue_sweeper_provider.dart'
    show pendingBetHoldsCash;
import 'package:kute/services/one_balance/prediction_funding_ledger.dart';
import 'package:kute/services/polymarket/market_buy_quote.dart';
import 'package:kute/services/polymarket/venue_collateral.dart';
import 'package:kute/services/polymarket/sell_settlement.dart';
import 'package:kute/screens/shared/slip_shortfall.dart' show fundedStopLine;
import 'package:kute/services/one_balance/bitcoin_funded_order.dart'
    show bitcoinFundedOrderRunnerProvider;
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/one_balance_state.dart'
    show OneBalanceVenue;
import 'package:kute/services/polymarket_backend_service.dart'
    show PolymarketOrderNotAcceptedException;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/venue_analytics.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show OrderBook, OrderSide, OrderType;

const _token = '9001';
const _noMatch = 'no orders found to match with FAK order. FAK orders are '
    'partially filled or killed if no match is found.';

class _Order {
  _Order(this.price, this.size, this.analytics);
  final double price, size;
  final Map<String, Object>? analytics;
}

class _Trading extends PolymarketTradingNotifier {
  _Trading(this.refusals);

  /// Thrown by the next orders, in turn; then the venue accepts.
  final List<Object> refusals;

  /// The venue's answer once it accepts (no verified fill by default).
  Map<String, dynamic> accepted = {
    'success': true,
    'status': 'live',
    'orderID': '0xorder'
  };
  final orders = <_Order>[];
  var readies = 0;

  @override
  Future<PolymarketTradingState> build() async => const PolymarketTradingState(
      isAuthenticated: true,
      usdcBalance: 0,
      proxyWalletAddress: '0xdeposit');

  /// The funding move lands: the venue holds [usd].
  void land(double usd) =>
      state = AsyncData(state.value!.copyWith(usdcBalance: usd));

  @override
  String? get signingWalletId => 'spending';

  @override
  Future<PolyBuyReads?> readBuyReadiness({bool refreshVenue = false}) async {
    final usd = state.valueOrNull?.usdcBalance ?? 0;
    final micros = BigInt.from((usd * 1e6).round());
    return (
      pusd: micros,
      usdce: BigInt.zero,
      venue: PolyVenueCount(balance: micros),
      setupDone: true
    );
  }

  @override
  Future<void> readyCollateralForBuy(double costUsd) async => readies++;

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
    AuthGrants.consume(
        grant,
        PmGrants.executedOrder(grant,
                walletId: 'spending',
                tokenId: tokenId,
                isBuy: true,
                size: size,
                price: price,
                orderType: orderType.name)
            .copyWith(limits: {
          ...PmGrants.executedOrder(grant,
                  walletId: 'spending',
                  tokenId: tokenId,
                  isBuy: true,
                  size: size,
                  price: price,
                  orderType: orderType.name)
              .limits,
          ...PmGrants.fundingLimits(fundUsd: 10, venue: IntentVenue.polymarket),
        }));
    onStep?.call('ready');
    orders.add(_Order(price, size, analytics));
    if (refusals.isNotEmpty) throw refusals.removeAt(0);
    // Accepted; the match is confirmed later (no verified fill here).
    return accepted;
  }
}

OrderBook _book(String ask) => parsePolymarketOrderBook({
      'market': 'm',
      'asset_id': _token,
      'tick_size': '0.01',
      'neg_risk': false,
      'min_order_size': '1',
      'asks': [
        {'price': ask, 'size': '1000'}
      ],
      'bids': const [],
    });

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

/// The bet as the slip queues it once its $10 move has left Dollars:
/// $10 at the 50¢ the ticket showed, 5% tolerance.
PendingBetIntent _queued() => PendingBetIntent(
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
    );

/// The slip's record for the queued bet, followed to its end as the slip
/// does at Confirm.
String _follow(ProviderContainer c) {
  final runner = c.read(bitcoinFundedOrderRunnerProvider);
  final id = runner.beginFunded(const FundedOrderLabel(
    venue: OneBalanceVenue.predictions,
    orderUsd: 10,
    side: 'Up',
    market: 'Bitcoin Up or Down',
    marketKey: _token,
  ));
  runner.followFunded(id, rowIds: {'q1'});
  return id;
}

void main() {
  late Directory hiveDir;

  setUpAll(() {
    hiveDir = Directory.systemTemp.createTempSync('fast_fill_test');
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
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });

  tearDown(() {
    TrackingService.debugTrackObserver = null;
    AuthGrantRegistry.instance.cancelAutofire(kPendingBetAutofireId);
  });

  /// Queues the funded bet with its one approval, lands the money and
  /// lets the autofire run. [books] are read in turn (the last repeats).
  Future<({ProviderContainer c, _Trading trading, int reads})> run(
      List<String> books,
      {List<Object> refusals = const [],
      Map<String, dynamic>? accepted,
      AutofireSettle? settle,
      void Function(ProviderContainer c)? onReady,
      void Function(ProviderContainer c)? onQueued}) async {
    final trading = _Trading([...refusals]);
    if (accepted != null) trading.accepted = accepted;
    var reads = 0;
    var landed = false;
    var readBeforeLanding = false;
    final c = ProviderContainer(overrides: [
      polymarketTradingProvider.overrideWith(() => trading),
      settingsProvider.overrideWith((_) => SettingsModel(_settings())),
      sessionUnlockedProvider.overrideWithValue(true),
      autofireBookReaderProvider.overrideWithValue((tokenId) async {
        if (!landed) readBeforeLanding = true;
        final ask = books[reads < books.length ? reads : books.length - 1];
        reads++;
        return _book(ask);
      }),
      if (settle != null) autofireSettlementProvider.overrideWithValue(settle),
    ]);
    addTearDown(c.dispose);
    onReady?.call(c);
    c.listen(polymarketTradingProvider, (_, __) {});
    await c.read(polymarketTradingProvider.future);
    c.read(pendingBetAutoFireProvider);

    // The one approval the slip asks for: the bet's cap, the funded worst
    // price (50¢ + 5% = 52.5¢), its tolerance and the funding leg.
    final intent = _queued();
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
    onQueued?.call(c);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    // Nothing is read or placed while the money is on its way.
    expect(trading.orders, isEmpty);
    expect(reads, 0);

    landed = true;
    trading.land(10.6);
    for (var i = 0;
        i < 100 &&
            c.read(pendingPolymarketBetProvider)?.status ==
                PendingBetStatus.awaitingBalance;
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    for (var i = 0;
        i < 100 &&
            c.read(pendingPolymarketBetProvider)?.status ==
                PendingBetStatus.placing;
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(readBeforeLanding, isFalse);
    return (c: c, trading: trading, reads: reads);
  }

  test('priced from the book read after the money landed, not the tap\'s '
      'odds', () async {
    // The tap showed 50¢; the book after landing asks 48¢: cap 50¢ (48¢ +
    // 5%, on the increment), not the 52.5¢ the old rule signed.
    final r = await run(['0.48']);
    expect(r.trading.readies, 1, reason: 'collateral readied before the read');
    expect(r.reads, 1);
    expect(r.trading.orders.map((o) => o.price), [0.50]);
    expect(r.trading.orders.single.analytics?['retried'], false);
    expect(r.trading.orders.single.analytics?['quoted_price'], 0.48);
    expect(r.trading.orders.single.analytics?['slippage_bps'],
        VenueAnalytics.bps(5));
    final record = PredictionFundingLedger.instance.record('ref_move')!;
    expect(record.stage, PredictionFundingStage.released);
    expect(record.releaseReason, 'placed');
  });

  test('a price refusal re-reads the book and sends one re-priced order, '
      'with no second funding', () async {
    final r = await run(['0.48', '0.51'],
        refusals: [const PolymarketOrderNotAcceptedException(_noMatch)]);
    expect(r.reads, 2);
    // 51¢ + 5% = 53.55¢, held under the approved 52.5¢ → 52¢.
    expect(r.trading.orders.map((o) => o.price), [0.50, 0.52]);
    expect(r.trading.orders.map((o) => o.analytics?['retried']),
        [false, true]);
    expect(r.trading.orders.last.analytics?['quoted_price'], 0.51);
    final pending = r.c.read(pendingPolymarketBetProvider)!;
    expect(pending.status, PendingBetStatus.awaitingConfirmation);
    expect(pending.fundUsd, 10, reason: 'the same move, nothing funded again');
    expect(PredictionFundingLedger.instance.record('ref_move')!.releaseReason,
        'placed');
    expect(events.where((e) => e.$1 == 'order_funding_started'), isEmpty);
    expect(events.where((e) => e.$1 == 'polymarket_bet_failed'), isEmpty);
  });

  test('refused again: the existing failure copy, the cash released and '
      'left as available Predictions cash', () async {
    final r = await run(['0.48', '0.51'], refusals: [
      const PolymarketOrderNotAcceptedException(_noMatch),
      const PolymarketOrderNotAcceptedException(_noMatch),
    ]);
    expect(r.trading.orders, hasLength(2), reason: 'one retry, never more');
    final pending = r.c.read(pendingPolymarketBetProvider)!;
    expect(pending.status, PendingBetStatus.failed);
    expect(pending.errorMessage,
        l10nForLanguage('en').betBuyLiquidityUnavailable);
    // The failed bet no longer holds the venue's cash.
    expect(pendingBetHoldsCash(pending), isFalse);
    final record = PredictionFundingLedger.instance.record('ref_move')!;
    expect(record.stage, PredictionFundingStage.released);
    expect(record.releaseReason, 'failed');
    expect(PredictionFundingLedger.instance.hasReserved, isFalse);
    expect(PredictionFundingLedger.instance.hasInFlight, isFalse);
    final failed =
        events.lastWhere((e) => e.$1 == 'polymarket_bet_failed').$2!;
    expect(failed['retried'], true);
    expect(failed['slippage_bps'], VenueAnalytics.bps(5));
    expect(failed['reason'], 'price_moved');
    expect(failed['refusal_class'], 'fak_no_match');
  });

  test('a book already past the approval signs nothing and names the retry',
      () async {
    final r = await run(['0.70']);
    expect(r.trading.orders, isEmpty);
    final pending = r.c.read(pendingPolymarketBetProvider)!;
    expect(pending.status, PendingBetStatus.failed);
    expect(pending.errorMessage,
        l10nForLanguage('en').betBuyPriceMoved('70¢', '52.5¢'));
    expect(pending.retryMaxPrice, 0.73);
    expect(PredictionFundingLedger.instance.record('ref_move')!.releaseReason,
        'failed');
  });

  group('the re-priced order stays inside the one approval', () {
    final approval = AuthGrants.issue(
        PmGrants.betReview(
          walletId: 'spending',
          tokenId: _token,
          maxCostUsd: 10.5,
          worstPrice: 0.525,
          orderType: OrderType.fak.name,
        ),
        method: AuthGrantMethod.biometric);

    SensitiveIntent order(double price, double cost) => PmIntents.order(
          walletId: 'spending',
          tokenId: _token,
          isBuy: true,
          amountMax: IntentUnits.usd(cost),
          limitPrice: price,
          orderType: OrderType.fak.name,
        );

    test('a better or equal price within the cap: a child grant', () {
      final child = autofireRetryGrant(approval, order(0.52, 10));
      expect(child.boundIntent.limits[IntentLimit.limitPrice], 0.52);
      expect(child.boundIntent.amountMax, IntentUnits.usd(10));
      expect(child.consumed, isFalse);
    });

    test('a worse price or a larger amount: re-approval, nothing signed', () {
      expect(() => autofireRetryGrant(approval, order(0.53, 10)),
          throwsA(isA<ReauthRequired>()));
      expect(() => autofireRetryGrant(approval, order(0.50, 11)),
          throwsA(isA<ReauthRequired>()));
    });
  });

  group('a game in play holds the order for its delay', () {
    // Founder, 14 October 2026 (LASK Linz vs Liverpool, live): the venue
    // answers `delayed` for a game in play and matches (or kills) the
    // order a second later. The autofire ended the bet on "check your
    // positions" at once; the slip never showed the receipt, and a killed
    // order never said so.
    const delayed = {
      'success': true,
      'status': 'delayed',
      'orderID': '0xorder'
    };

    PmSellSettlement settled(PmSellResult result,
            {double shares = 0, double? proceeds}) =>
        PmSellSettlement(
          result: result,
          offeredShares: 20,
          soldShares: shares,
          proceeds: proceeds,
          firstStatus: 'delayed',
          confirmedBy: shares > 0 ? 'mined' : 'none',
          timeToMatch: const Duration(seconds: 1),
          delayed: true,
        );

    test('matched after the hold: placed, the receipt\'s figures, the fill '
        'reported from the venue\'s own cost', () async {
      final stages = <PendingBetStage>[];
      final statuses = <PendingBetStatus>[];
      String? funded;
      final r = await run(['0.48'],
          accepted: delayed,
          onQueued: (c) => funded = _follow(c),
          onReady: (c) {
            // Loaded up front: the fill's cost is added to it.
            c.read(polymarketCostBasisProvider);
            c.listen<PendingBetIntent?>(pendingPolymarketBetProvider,
                (_, next) {
              if (next == null) return;
              stages.add(next.stage);
              statuses.add(next.status);
            });
          },
          settle: (response,
              {required tokenId, required orderedShares, onStage}) async {
            expect(response['status'], 'delayed');
            onStage?.call(PmSellStage.delayed, 0);
            await Future<void>.delayed(const Duration(milliseconds: 5));
            onStage?.call(PmSellStage.matched, 20);
            return settled(PmSellResult.filled, shares: 20, proceeds: 9.6);
          });
      // Held, then placed: never "awaiting confirmation", never failed.
      expect(stages, contains(PendingBetStage.delayed));
      expect(statuses, contains(PendingBetStatus.done));
      expect(statuses, isNot(contains(PendingBetStatus.awaitingConfirmation)));
      expect(statuses, isNot(contains(PendingBetStatus.failed)));
      expect(PredictionFundingLedger.instance.record('ref_move')!.releaseReason,
          'placed');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final placed =
          events.where((e) => e.$1 == 'polymarket_bet_placed').toList();
      expect(placed, hasLength(1));
      expect(placed.single.$2!['live_delay'], true);
      expect(placed.single.$2!['entry_source'], 'autofire');
      expect(events.where((e) => e.$1 == 'polymarket_bet_failed'), isEmpty);
      // The slip's steps follow the real outcome: placed, never a stop.
      final record = r.c.read(fundedOrdersProvider.notifier).byId(funded!)!;
      expect(record.stage, FundedOrderStage.done);
      expect(record.stoppedAt, isNull);
    });

    test('killed when the hold ended: says the price moved, nothing bought, '
        'the cash stays as Predictions cash', () async {
      String? funded;
      final r = await run(['0.48'],
          accepted: delayed,
          onQueued: (c) => funded = _follow(c),
          settle: (response,
                  {required tokenId, required orderedShares, onStage}) async =>
              settled(PmSellResult.notFilled));
      final pending = r.c.read(pendingPolymarketBetProvider)!;
      expect(pending.status, PendingBetStatus.failed);
      expect(pending.failureCode, 'price_moved');
      expect(pending.errorMessage, l10nForLanguage('en').betBuyNotMatched);
      expect(PredictionFundingLedger.instance.record('ref_move')!.releaseReason,
          'failed');
      final failed =
          events.lastWhere((e) => e.$1 == 'polymarket_bet_failed').$2!;
      expect(failed['reason'], 'not_filled');
      expect(failed['live_delay'], true);
      // The steps say the real reason, with the 90c2b0950 stop line.
      final record = r.c.read(fundedOrdersProvider.notifier).byId(funded!)!;
      expect(record.stage, FundedOrderStage.failed);
      expect(record.stoppedAt, FundedOrderStage.placing);
      expect(
          fundedStopLine(l10nForLanguage('en'), record,
              (usd) => '\$${usd.toStringAsFixed(2)}'),
          r'Price moved too fast. Your $10.00 is in Predictions. '
          'Tap to try again.');
    });

    test('not said in time: waits for its confirmation, never failed yet',
        () async {
      final r = await run(['0.48'],
          accepted: delayed,
          settle: (response,
                  {required tokenId, required orderedShares, onStage}) async =>
              settled(PmSellResult.unknown));
      final pending = r.c.read(pendingPolymarketBetProvider)!;
      expect(pending.status, PendingBetStatus.awaitingConfirmation);
      expect(events.where((e) => e.$1 == 'polymarket_bet_failed'), isEmpty);
    });
  });

  test('a funded bet fires on its own move landing, not on cash already '
      'there', () {
    final queued = _queued().copyWith(fundReadyUsd: 4, fundArrivingUsd: 6.2);
    // $10 stake with $4 already there and $6.20 on its way: 99% of the
    // stake is not enough, the move itself must have landed.
    expect(autofireFireAt(queued), closeTo(4 + 6.2 * 0.99, 1e-9));
    expect(autofireFireAt(_queued().copyWith(fundArrivingUsd: 2)),
        closeTo(9.9, 1e-9));
  });
}
