// A standing prediction (signed at the accept, posted by the autofire once
// its money is counted) from the delivery of its money to the post.
//
// Founder report, 12 November 2026, on 2.2.0 (111): a $5.00 Up pick for
// "BTC up or down · 11:35–11:40", funded with $3.08 straight from Bitcoin
// at 11:31, sat on "Confirming balance" and "was placed instantly after
// the 5 min market went live". The post was held back here until the
// round's start; the venue takes and matches orders on a round before it
// starts. Fakes only: nothing is signed or sent.

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/constants/polymarket_constants.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/auth_grant_registry.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/auth_provider.dart' show sessionUnlockedProvider;
import 'package:kute/providers/pending_bet_autofire.dart';
import 'package:kute/providers/pending_polymarket_bet_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/l10n/l10n.dart' show l10nForLanguage;
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/order_funding.dart';
import 'package:kute/services/one_balance/prediction_funding_ledger.dart';
import 'package:kute/services/polymarket/placement_waits.dart'
    show PolymarketCollateralPending, PolymarketCollateralWait;
import 'package:kute/services/polymarket/venue_collateral.dart';
import 'package:kute/services/polymarket_order_v2.dart';
import 'package:kute/services/standing_orders/polymarket_signed_order.dart';
import 'package:kute/services/standing_orders/standing_order_store.dart';
import 'package:kute/services/standing_orders/standing_orders_provider.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show OrderType;

import '../services/standing_orders/fake_secret_store.dart';

const _token = '9001';

BigInt _usd(double usd) => BigInt.from((usd * 1e6).round());

PolyBuyReads _reads({double pusd = 0, double usdce = 0, double? counted}) => (
      pusd: _usd(pusd),
      usdce: _usd(usdce),
      venue: counted == null ? null : PolyVenueCount(balance: _usd(counted)),
      setupDone: true,
    );

/// Signs the standing order as the trading notifier does, one per call.
class _Signer {
  int calls = 0;
  final spends = <double>[];
  final prices = <double>[];

  Future<StandingSignedOrder?> call({
    required String tokenId,
    required double size,
    required double price,
    required double spendUsd,
    required bool negRisk,
    required OrderType orderType,
    required AuthGrant grant,
  }) async {
    calls++;
    spends.add(spendUsd);
    prices.add(price);
    // The executor's own check: the grant covers exactly this order.
    PmGrants.consumeOrder(grant,
        walletId: 'spending',
        tokenId: tokenId,
        isBuy: true,
        size: size,
        price: price,
        orderType: orderType.name,
        spendUsd: orderType == OrderType.fak ? spendUsd : null);
    final order = OrderStructV2(
      salt: BigInt.from(calls),
      maker: '0x${'ab' * 20}',
      signer: '0x${'ab' * 20}',
      tokenId: tokenId,
      makerAmount: BigInt.from((spendUsd * 1e6).round()),
      takerAmount: BigInt.from((size * 1e6).round()),
      side: 0,
      signatureType: 3,
      timestamp: BigInt.from(calls),
      metadata: PolymarketConstants.bytes32Zero,
      builder: PolymarketConstants.bytes32Zero,
    );
    return StandingSignedOrder(
      signed: SignedOrderV2(order: order, signature: '0x${'cd' * 65}'),
      exchange: PolymarketConstants.exchangeAddress,
      orderType: orderType,
      negRisk: negRisk,
      orderHash:
          polymarketOrderHash(order, PolymarketConstants.exchangeAddress),
    );
  }
}

class _Trading extends PolymarketTradingNotifier {
  /// What the readiness read answers now.
  PolyBuyReads? Function() reads = () => null;

  final deliveries = StreamController<void>.broadcast();
  @override
  Stream<void> get depositSettled => deliveries.stream;

  /// The standing orders handed to the venue, and when.
  final posts = <StandingSignedOrder>[];
  final postedAt = <DateTime>[];
  var nudges = 0;
  var readinessReads = 0;

  @override
  Future<PolymarketTradingState> build() async => const PolymarketTradingState(
      isAuthenticated: true, usdcBalance: 0, proxyWalletAddress: '0xdeposit');

  /// The summed cash the app shows.
  void land(double usd) =>
      state = AsyncData(state.value!.copyWith(usdcBalance: usd));

  @override
  String? get signingWalletId => 'spending';

  @override
  Future<PolyBuyReads?> readBuyReadiness({bool refreshVenue = false}) async {
    readinessReads++;
    return reads();
  }

  @override
  Future<({BigInt pusd, BigInt usdce, int endpoint, int rpcErrors})?>
      readCollateralNow() async {
    final r = reads();
    return r == null
        ? null
        : (pusd: r.pusd, usdce: r.usdce, endpoint: 0, rpcErrors: 0);
  }

  @override
  void nudgeConversion() => nudges++;

  @override
  Future<bool> readyCollateralForBuy(double costUsd) async => false;

  @override
  Future<void> refresh() async {}

  @override
  void invalidateBalanceCache() {}

  @override
  void setPendingBetWaiting(bool waiting) {}

  /// The placement's own collateral check, then the venue's answer: a
  /// buy the wallet's pUSD does not hold is never posted.
  @override
  Future<Map<String, dynamic>> postStandingOrder({
    required StandingSignedOrder standing,
    String? marketTitle,
    String? marketImage,
    String? marketOutcome,
    String? marketCategory,
    String? source,
    String? entrySource,
    Map<String, Object>? analytics,
    void Function(String step)? onStep,
  }) async {
    final r = reads();
    final spend = _usd(standing.spendUsd);
    if (r == null || r.pusd < spend) {
      throw const PolymarketCollateralPending(PolymarketCollateralWait.short);
    }
    if (r.venue == null || r.venue!.balance < spend) {
      throw const PolymarketCollateralPending(
          PolymarketCollateralWait.notCounted);
    }
    onStep?.call('ready');
    posts.add(standing);
    postedAt.add(DateTime.now());
    return {
      'success': true,
      'status': 'matched',
      'orderID': standing.orderHash,
      'makingAmount': '${standing.spendUsd}',
      'takingAmount': '${standing.shares}',
    };
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

/// The start of a 5-minute round that is still at least five minutes away.
DateTime _roundNotStarted() {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return DateTime.fromMillisecondsSinceEpoch(((now ~/ 300) + 2) * 300 * 1000,
      isUtc: true);
}

/// The founder's bet: $5.00 Up on the next round, $2.41 on Predictions,
/// $3.08 straight from Bitcoin.
PendingBetIntent _bet(DateTime roundStart) => PendingBetIntent(
      tokenId: _token,
      amount: 5,
      slippagePct: 5,
      marketQuestion: 'Bitcoin Up or Down - November 12, 11:35AM-11:40AM ET',
      outcomeName: 'Up',
      expectedPrice: 0.51,
      status: PendingBetStatus.awaitingBalance,
      fundUsd: 3.08,
      fundQuoteRef: 'ref_move',
      fundReadyUsd: 2.41,
      fundArrivingUsd: 3.08,
      queuedAt: DateTime.now(),
      marketEndAt: roundStart.add(const Duration(minutes: 5)),
      eventSlug:
          'btc-updown-5m-${roundStart.millisecondsSinceEpoch ~/ 1000}',
      roundWindow: 'next',
      btcLeg: const {'route': 'direct'},
    );

void main() {
  late Directory hiveDir;
  late FakeSecretStore secrets;
  late _Signer signer;

  setUpAll(() {
    hiveDir = Directory.systemTemp.createTempSync('standing_post_test');
    Hive.init(hiveDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    hiveDir.deleteSync(recursive: true);
  });

  setUp(() async {
    FundedOrdersNotifier.persist = false;
    PredictionFundingLedger.reset();
    OrderFundingJourney.reset();
    TrackingService.debugTrackObserver = (_, __) {};
    secrets = FakeSecretStore();
    signer = _Signer();
    await (await Hive.openBox<String>('standing_post')).clear();
  });

  tearDown(() {
    TrackingService.debugTrackObserver = null;
    PendingBetAutoFire.readyPollInterval = const Duration(seconds: 1);
    PendingBetAutoFire.debugShortLandingGrace = null;
    AuthGrantRegistry.instance.cancelAutofire(kPendingBetAutofireId);
  });

  /// Queues [intent] under its one approval: the standing order is signed
  /// and the autofire watches for its money.
  Future<({ProviderContainer c, _Trading trading})> accept(
      PendingBetIntent bet,
      {bool delivered = false}) async {
    var intent = bet;
    final trading = _Trading();
    addTearDown(trading.deliveries.close);
    final c = ProviderContainer(overrides: [
      polymarketTradingProvider.overrideWith(() => trading),
      settingsProvider.overrideWith((_) => SettingsModel(_settings())),
      sessionUnlockedProvider.overrideWithValue(true),
      standingOrderStoreProvider.overrideWithValue(
          StandingOrderStore(secrets: secrets, boxName: 'standing_post')),
      standingPredictionSignerProvider.overrideWithValue(signer.call),
      standingOrderLookupProvider.overrideWithValue((hash) async => null),
      standingPmTradesProvider.overrideWithValue((token, since) async => []),
      standingOrderWatchersProvider.overrideWithValue(StandingOrderWatchers(
          wakePredictions: () {}, wakeInvesting: () {})),
    ]);
    addTearDown(c.dispose);
    c.listen(polymarketTradingProvider, (_, __) {});
    await c.read(polymarketTradingProvider.future);
    c.read(standingOrdersProvider);
    c.read(pendingBetAutoFireProvider);
    AuthGrantRegistry.instance.issueAutofire(
      kPendingBetAutofireId,
      PmGrants.fundedBetReview(
        PmGrants.betReview(
            walletId: 'spending',
            tokenId: intent.tokenId,
            maxCostUsd: intent.amount + 0.02,
            worstPrice: polymarketFundedWorstPrice(intent),
            orderType: OrderType.fak.name),
        fundUsd: intent.fundUsd!,
        venue: IntentVenue.polymarket,
        btcLeg: intent.btcLeg,
      ),
      method: AuthGrantMethod.biometric,
    );
    PredictionFundingLedger.instance.sent('ref_move', usd: intent.fundUsd!);
    if (delivered) {
      // The bet's own funding run, its one leg reported delivered.
      final runs = c.read(fundedOrdersProvider.notifier);
      final id = runs.start(
          FundedOrderLabel(
              venue: OneBalanceVenue.predictions,
              orderUsd: intent.amount,
              side: 'Up',
              market: 'Question',
              marketKey: _token),
          stage: FundedOrderStage.preparing);
      runs.setSteps(
          id,
          MoneyStepGraph([
            MoneyStep(
                id: 'leg:bitcoin',
                kind: MoneyStepKind.leg,
                from: MoneyPlace.bitcoin,
                to: MoneyPlace.predictions,
                usd: intent.fundUsd!,
                status: MoneyStepStatus.done),
          ]));
      intent = intent.copyWith(fundedRunId: id);
    }
    c.read(pendingPolymarketBetProvider.notifier).setIntent(intent);
    // The signature and its secret are written between the accept and
    // the first look.
    for (var i = 0; i < 100 && signer.calls == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(signer.calls, 1, reason: 'signed once at the accept');
    expect(c.read(pendingPolymarketBetProvider)!.standingOrderId, isNotNull);
    return (c: c, trading: trading);
  }

  Future<void> until(bool Function() done,
      {Duration within = const Duration(seconds: 3)}) async {
    final end = DateTime.now().add(within);
    while (!done() && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test(
      'a pick for a round that has not started yet is posted the moment its '
      'money is counted, never held back for the round to open', () async {
    PendingBetAutoFire.readyPollInterval = const Duration(milliseconds: 20);
    final start = _roundNotStarted();
    expect(start.difference(DateTime.now()), greaterThan(const Duration(minutes: 4)));
    final r = await accept(_bet(start));

    // The Bitcoin leg delivered and converted: $5.49 pUSD, counted.
    r.trading.reads = () => _reads(pusd: 5.49, counted: 5.49);
    r.trading.land(5.49);
    await until(() => r.trading.posts.isNotEmpty);

    expect(r.trading.posts, hasLength(1),
        reason: 'posted before the round opens: the venue takes orders on '
            'a round that has not started');
    expect(DateTime.now().isBefore(start), isTrue);
    // The order signed at the accept, as is: the whole stake at the
    // approved worst price.
    expect(r.trading.posts.single.spendUsd, 5);
    expect(signer.calls, 1);
    await until(() =>
        r.c.read(pendingPolymarketBetProvider)?.status ==
            PendingBetStatus.done ||
        r.c.read(pendingPolymarketBetProvider) == null);
    final ended = r.c.read(pendingPolymarketBetProvider);
    expect(ended == null || ended.status == PendingBetStatus.done, isTrue);
  });

  group('a landing short of the stake', () {
    // What the reviewer flagged on d4003555: the order signed at the accept
    // is for the whole stake, so a landing short of it could not be placed
    // and sat in `placing` until the 12-minute funds wait, then failed
    // with the generic copy.
    setUp(() {
      PendingBetAutoFire.readyPollInterval = const Duration(milliseconds: 20);
      PendingBetAutoFire.debugShortLandingGrace =
          const Duration(milliseconds: 100);
    });

    test(
        'a few cents short: signed again smaller at the same price under '
        'the same approval and placed, in seconds', () async {
      final r = await accept(_bet(_roundNotStarted()), delivered: true);
      final first = signer.prices.single;

      // Every leg delivered; the wallet holds $4.97 where the $5.00 stake
      // and its fees need $5.24.
      r.trading.reads = () => _reads(pusd: 4.97, counted: 4.97);
      r.trading.land(4.97);
      await until(() => r.trading.posts.isNotEmpty);

      expect(r.trading.posts, hasLength(1),
          reason: 'placed for what landed, never a 12-minute wait');
      final posted = r.trading.posts.single;
      expect(posted.spendUsd, lessThan(5));
      expect(posted.spendUsd, greaterThan(4.5));
      // Never larger, never a worse price than the one approved.
      expect(signer.calls, 2);
      expect(signer.spends.last, posted.spendUsd);
      expect(signer.prices.last, first);
      // One order at the venue, the smaller one; the first was never sent.
      expect(r.trading.posts.map((p) => p.orderHash).toSet(), hasLength(1));
      await until(() =>
          r.c.read(pendingPolymarketBetProvider)?.status ==
              PendingBetStatus.done ||
          r.c.read(pendingPolymarketBetProvider) == null);
      final ended = r.c.read(pendingPolymarketBetProvider);
      expect(ended == null || ended.status == PendingBetStatus.done, isTrue);
    });

    test(
        'no approval left to sign a smaller order (a restart): it stops at '
        'once with "Add funds to predict", the money in Predictions',
        () async {
      final r = await accept(_bet(_roundNotStarted()), delivered: true);
      // The session's approval is gone: nothing new may be signed.
      AuthGrantRegistry.instance.cancelAutofire(kPendingBetAutofireId);

      r.trading.reads = () => _reads(pusd: 4.97, counted: 4.97);
      r.trading.land(4.97);
      await until(() =>
          r.c.read(pendingPolymarketBetProvider)?.status ==
          PendingBetStatus.failed);

      final ended = r.c.read(pendingPolymarketBetProvider)!;
      expect(ended.status, PendingBetStatus.failed,
          reason: 'said at once, never after the 12-minute funds wait');
      expect(ended.failureCode, 'insufficient_usdc');
      expect(ended.errorMessage, l10nForLanguage('en').betAddFundsToPredict);
      expect(r.trading.posts, isEmpty);
      expect(signer.calls, 1);
    });

    test(
        'the cash went short after the look that released the order: the '
        'refusal is met by a smaller order, not by the funds wait', () async {
      final r = await accept(_bet(_roundNotStarted()), delivered: true);
      // Counted in full at the readiness look; by the post the wallet
      // holds less (another order of the person's took part of it).
      var looks = 0;
      r.trading.reads = () => looks++ < 1
          ? _reads(pusd: 5.49, counted: 5.49)
          : _reads(pusd: 4.2, counted: 4.2);
      r.trading.land(5.49);
      await until(() => r.trading.posts.isNotEmpty);

      expect(r.trading.posts, hasLength(1));
      expect(r.trading.posts.single.spendUsd, lessThan(4.2));
      expect(r.trading.posts.single.spendUsd, greaterThan(3.8));
      expect(signer.prices.toSet(), hasLength(1));
    });

    test('a landing under the venue\'s minimum stops at once too', () async {
      final r = await accept(_bet(_roundNotStarted()), delivered: true);
      r.trading.reads = () => _reads(pusd: 0.6, counted: 0.6);
      r.trading.land(0.6);
      await until(() =>
          r.c.read(pendingPolymarketBetProvider)?.status ==
          PendingBetStatus.failed);
      final ended = r.c.read(pendingPolymarketBetProvider)!;
      expect(ended.status, PendingBetStatus.failed);
      expect(ended.failureCode, 'insufficient_usdc');
      expect(r.trading.posts, isEmpty);
    });
  });
}
