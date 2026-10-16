import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/auth_grant_registry.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/pending_polymarket_bet_provider.dart';
import 'package:kute/providers/pending_bet_autofire.dart'
    show kPendingBetAutofireId;
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/spark_address_provider.dart';
import 'package:kute/providers/usd_account_provider.dart';
import 'package:kute/services/one_balance/bitcoin_funded_order.dart';
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/order_funding.dart';
import 'package:kute/services/one_balance/predictions_prefund_transfer.dart';
import 'package:kute/services/one_balance/predictions_venue_funder.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/polymarket/venue_collateral.dart';
import 'package:kute/services/polymarket/crypto_round.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/funding/settlement_runner.dart'
    show SettlementFundingUnknown;

const _pm = '0x1111111111111111111111111111111111111111';
const _spark = 'spark1own';
BigInt _micro(double usd) => BigInt.from((usd * 1e6).round());
PolyBuyReads _reads(double pusd,
        {double usdce = 0, double? venue, bool setup = true}) =>
    (
      pusd: _micro(pusd),
      usdce: _micro(usdce),
      setupDone: setup,
      venue: PolyVenueCount(balance: _micro(venue ?? pusd)),
    );

class _Trading extends PolymarketTradingNotifier {
  PolyBuyReads? reads = _reads(0);
  Completer<PolyBuyReads?>? deferred;
  int generation = 0;
  int wraps = 0;
  bool wrap = true;
  @override
  Future<PolymarketTradingState> build() async => const PolymarketTradingState(
      usdcBalance: 0, proxyWalletAddress: _pm, walletAddress: _pm);
  @override
  int get accountGeneration => generation;
  @override
  String? get signingWalletId => 'w';
  @override
  Future<PolyBuyReads?> readBuyReadiness({bool refreshVenue = false}) async =>
      deferred == null ? reads : await deferred!.future;
  @override
  void nudgeConversion() {
    wraps++;
    final r = reads;
    if (wrap && r != null) reads = _reads((r.pusd + r.usdce).toDouble() / 1e6);
  }
}

class _Funder implements VenueFunder {
  _Funder(this.trading);
  final _Trading trading;
  final sent = <double>[];
  bool acceptedUnknown = false;
  @override
  Future<VenueMoveResult> fund(
      {required double usd,
      required MoveAuthorization auth,
      String purpose = 'order_funding'}) async {
    expect(
        PredictionPrefundGrants.isTransfer(
            (auth as UserGrantAuthorization).grant),
        isTrue);
    expect(purpose, 'predictions_prefund');
    sent.add(usd);
    if (acceptedUnknown)
      throw const SettlementFundingUnknown(
          'operation_local', 'result_unavailable');
    trading.reads = _reads(0, usdce: usd);
    return VenueMoveResult(
        quoteId: 'q_dollars',
        orderId: 'ord_dollars',
        sentUsd: usd,
        arrivingUsdEstimate: usd);
  }

  @override
  Future<VenueMoveQuote> estimate(double usd) async => VenueMoveQuote(
      arrivingUsd: usd, feeUsd: 0, fixedCostUsd: 0, minUsd: 1, maxUsd: 1000);
  @override
  Future<double> minimumUsd() async => 1;
  @override
  Future<double> idleUsd() async => 0;
}

class _Wallet {
  late final _Trading trading = _Trading();
  late final _Funder funder = _Funder(trading);
  late final ProviderContainer c = ProviderContainer(overrides: [
    settingsProvider.overrideWith((_) => SettingsModel(Settings(
        currency: 'USD',
        language: 'en',
        btcFormat: 'sats',
        backup: false,
        biometricsEnabled: false,
        bitcoinElectrumNode: '',
        nodeType: '',
        reviewDone: true,
        wallets: [WalletConfig(id: 'w', name: 'Spending')],
        activeWalletId: 'w'))),
    polymarketTradingProvider.overrideWith(() => trading),
    sparkSelfAddressProvider.overrideWith((_) async => _spark),
    usdBalanceProvider.overrideWithValue(20),
    venueCashPullerProvider.overrideWithValue(VenueCashPuller(
        sources: const [], readDollars: () => 20, minimumUsd: (_) async => 1)),
    orderFundingControllerProvider.overrideWithValue(
        OrderFundingController(funderFor: (_) => funder, dollarsUsd: () => 20)),
    bitcoinLegEnvProvider.overrideWithValue(BitcoinLegEnv(
      ownSpark: () async => _spark,
      send: (
              {required sparkAddress,
              required plan,
              required stepUp,
              required onSending}) =>
          throw StateError('no BTC requested'),
      watcher: ({required since}) => throw StateError('no BTC requested'),
      dollarsNow: () => 20,
      freshDollars: () async => 20,
      legStatus: (_) async => 'completed',
      legPollEvery: const Duration(milliseconds: 1),
    )),
  ]);
  Future<PredictionsPrefundTransfer> init() async {
    await c.read(polymarketTradingProvider.future);
    addTearDown(c.dispose);
    return c.read(predictionsPrefundTransferProvider);
  }
}

void main() {
  setUp(() {
    FundedOrdersNotifier.persist = false;
    OrderFundingJourney.reset();
    PredictionsVenueFunder.debugRouteShare = (_) async => 0;
    debugOwnVenueDeposit = (_) async => _pm;
    PredictionsPrefundTransfer.pollEvery = const Duration(milliseconds: 1);
  });
  tearDown(() {
    FundedOrdersNotifier.persist = true;
    PredictionsVenueFunder.debugRouteShare = null;
    debugOwnVenueDeposit = null;
    PredictionsPrefundTransfer.pollEvery = const Duration(seconds: 1);
    PredictionsPrefundTransfer.maxWait = const Duration(minutes: 12);
    TrackingService.debugTrackObserver = null;
  });

  test('only exact Bitcoin five-minute series requires prefunding', () {
    for (final slug in [
      'btc-updown-5m-1792152000',
      'bitcoin-updown-5m-1792152000'
    ]) {
      expect(polyRequiresPrefundedBitcoinFiveMinute(slug), isTrue);
    }
    for (final slug in [
      null,
      'btc-updown-15m-1792152000',
      'eth-updown-5m-1792152000',
      'bitcoin-up-or-down-october-16-2026-4pm-et',
      'btc-updown-5m',
      'bitcoin-5-minute-price'
    ]) {
      expect(polyRequiresPrefundedBitcoinFiveMinute(slug), isFalse);
    }
  });

  test(
      'readiness requires full pUSD and venue amount, excludes reservations and USDC.e',
      () {
    expect(predictionsPrefundSpendable(null, reservedUsd: 0), isNull);
    expect(predictionsPrefundSpendable(_reads(2, usdce: 8), reservedUsd: 0), 2);
    expect(
        predictionsPrefundSpendable(_reads(12, venue: 3), reservedUsd: 0), 3);
    expect(predictionsPrefundSpendable(_reads(12), reservedUsd: 4), 8);
    expect(
        predictionsPrefundSpendable(_reads(12, setup: false), reservedUsd: 0),
        0);
  });

  test(
      'mixed collateral converts, completes transfer graph, never queues or places a bet',
      () async {
    final w = _Wallet();
    final transfer = await w.init();
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    final plan = await transfer.prepare(10.21);
    var approvals = 0;
    await transfer.start(plan, approve: (intent) async {
      approvals++;
      expect(intent.action, SensitiveAction.moveTransfer);
      return AuthGrants.issue(intent, method: AuthGrantMethod.biometric);
    });
    expect(approvals, 1);
    expect(w.funder.sent, hasLength(1));
    expect(transfer.failure, isNull,
        reason:
            w.c.read(fundedOrdersProvider).map((r) => r.toJson()).toString());
    expect(w.trading.wraps, 1);
    expect(transfer.spendableUsd, greaterThanOrEqualTo(10.21));
    expect(w.c.read(pendingPolymarketBetProvider), isNull);
    expect(AuthGrantRegistry.instance.hasAutofireGrant(kPendingBetAutofireId),
        isFalse);
    final record = w.c.read(fundedOrdersProvider).single;
    expect(record.label.kind, FundedOrderKind.transfer);
    expect(record.stage, FundedOrderStage.done);
    expect(record.steps.byId(FundedStepId.place), isNull);
    expect(record.steps.allDone, isTrue);
    final ends =
        events.where((e) => e.$1 == 'order_funding_completed').toList();
    expect(ends, hasLength(1));
    expect(ends.single.$2!['funding_purpose'], 'predictions_prefund');
    expect(ends.single.$2!['amount_usd'], 10.21);
    expect(ends.single.$2!['fund_usd'], w.funder.sent.single);
    expect(ends.single.$2!['outcome'], 'funds_ready');
    expect(ends.single.$2!.containsKey('ms_order'), isFalse);
    expect(
        events.where((e) =>
            e.$1 == 'polymarket_bet_submitted' ||
            e.$1 == 'polymarket_bet_placed'),
        isEmpty);
    // A stale second transfer plan cannot fund again once the money is ready.
    await transfer.start(plan, approve: (_) async {
      approvals++;
      return null;
    });
    expect(approvals, 1);
    expect(w.funder.sent, hasLength(1));
  });

  test(
      'existing destination USDC.e only readies; no source transfer or approval',
      () async {
    final w = _Wallet();
    final transfer = await w.init();
    w.trading.reads = _reads(0, usdce: 12);
    final plan = await transfer.prepare(10.21);
    expect(plan.funding.fundUsd, 0);
    await transfer.start(plan,
        approve: (_) async => throw StateError('no source approval needed'));
    expect(w.funder.sent, isEmpty);
    expect(w.trading.wraps, 1);
    expect(transfer.spendableUsd, 12);
    expect(w.c.read(fundedOrdersProvider).single.steps.byId(FundedStepId.place),
        isNull);
    expect(w.c.read(pendingPolymarketBetProvider), isNull);
  });

  test('read from retired same-wallet account generation never publishes ready',
      () async {
    final w = _Wallet();
    final transfer = await w.init();
    w.trading.deferred = Completer<PolyBuyReads?>();
    final read = transfer.refresh();
    w.trading.generation++;
    w.trading.deferred!.complete(_reads(100));
    expect(await read, isNull);
    expect(transfer.spendableUsd, isNull);
  });

  test('account generation changed after planning cannot prompt or send',
      () async {
    final w = _Wallet();
    final transfer = await w.init();
    final plan = await transfer.prepare(10.21);
    w.trading.generation++;
    await transfer.start(plan,
        approve: (_) async => throw StateError('stale plan cannot prompt'));
    expect(w.funder.sent, isEmpty);
    expect(w.c.read(pendingPolymarketBetProvider), isNull);
  });

  test('PIN session renewal preserves same-account transfer approval',
      () async {
    final w = _Wallet();
    w.c.read(sessionAuthProvider.notifier).state =
        SessionAuth(method: UnlockMethod.pin, unlockedAt: DateTime(2026));
    final transfer = await w.init();
    final plan = await transfer.prepare(10.21);
    await transfer.start(plan, approve: (intent) async {
      w.c.read(sessionAuthProvider.notifier).state =
          SessionAuth(method: UnlockMethod.pin, unlockedAt: DateTime(2026, 10));
      return AuthGrants.issue(intent, method: AuthGrantMethod.pin);
    });
    expect(w.funder.sent, hasLength(1));
    expect(transfer.failure, isNull);
    expect(transfer.spendableUsd, greaterThanOrEqualTo(10.21));
  });

  test('account generation change clears previously ready cash immediately',
      () async {
    final w = _Wallet();
    final transfer = await w.init();
    w.trading.reads = _reads(20);
    expect(await transfer.refresh(), 20);
    w.trading.generation++;
    expect(transfer.spendableUsd, isNull);
  });

  test('concurrent prepare is refused before another source plan starts',
      () async {
    final w = _Wallet();
    final transfer = await w.init();
    w.trading.deferred = Completer<PolyBuyReads?>();
    final first = transfer.prepare(10.21);
    await expectLater(transfer.prepare(10.21),
        throwsA(isA<PredictionsTransferUnavailable>()));
    w.trading.deferred!.complete(_reads(0));
    await first;
  });

  test(
      'accepted unknown source with no receipt ref never authorizes a repeated transfer',
      () async {
    final w = _Wallet();
    final transfer = await w.init();
    w.funder.acceptedUnknown = true;
    PredictionsPrefundTransfer.maxWait = const Duration(milliseconds: 15);
    final plan = await transfer.prepare(10.21);
    await transfer.start(plan,
        approve: (intent) async =>
            AuthGrants.issue(intent, method: AuthGrantMethod.biometric));
    expect(transfer.failure, isNotNull);
    expect(transfer.needsTransferReview, isTrue);
    expect(
        w.c
            .read(fundedOrdersProvider)
            .single
            .steps
            .legs
            .every((leg) => leg.ref == null),
        isTrue);
    expect(w.funder.sent, hasLength(1));
    await expectLater(transfer.prepare(10.21),
        throwsA(isA<PredictionsTransferUnavailable>()));
    await transfer.start(plan,
        approve: (_) async => throw StateError('unknown send cannot repeat'));
    expect(w.funder.sent, hasLength(1));
    expect(w.c.read(pendingPolymarketBetProvider), isNull);
  });

  test('unknown collateral times out without order or repeated source transfer',
      () async {
    final w = _Wallet();
    final transfer = await w.init();
    final plan = await transfer.prepare(10.21);
    PredictionsPrefundTransfer.maxWait = const Duration(milliseconds: 15);
    w.trading.wrap = false;
    await transfer.start(plan,
        approve: (intent) async =>
            AuthGrants.issue(intent, method: AuthGrantMethod.biometric));
    expect(transfer.failure, isNotNull);
    expect(transfer.needsTransferReview, isTrue);
    expect(w.funder.sent, hasLength(1));
    await transfer.start(plan,
        approve: (_) async =>
            throw StateError('cannot repeat an uncertain transfer'));
    expect(w.funder.sent, hasLength(1));
    expect(w.c.read(pendingPolymarketBetProvider), isNull);
  });
}
