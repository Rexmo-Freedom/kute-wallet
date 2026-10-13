// The sweeper as the app binds it, in a region whose policy withholds
// browsing, trading and new funding at both venues (the UK today) while
// leaving the exits on: the venues' money is still read, shown and sent
// home, with no Investing surface ever opened.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/auth_provider.dart'
    show sessionUnlockedProvider;
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/one_balance_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/usd_account_provider.dart';
import 'package:kute/providers/venue_sweeper_provider.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/services/one_balance/hyperliquid_move_rail.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/route_minimums.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/one_balance/venue_sweeper.dart'
    show SweepableVenueFunder;
import 'package:kute/providers/pending_polymarket_bet_provider.dart';
import 'package:kute/services/funding/settlement_stage.dart';
import 'package:kute/services/one_balance/prediction_funding_ledger.dart';
import 'package:kute/services/one_balance/sweep_rules.dart'
    show kVenueIdleSweepAfter;
import 'package:kute/services/one_balance/venue_activity.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show Position;

import '../helpers/fake_swap_orders.dart';
import '../helpers/runtime_policy_fixture.dart';

/// What the UK policy withholds today; `….withdraw` and `….close` stay on.
const _withheld = {
  'hyperliquid.browse',
  'hyperliquid.trade',
  'hyperliquid.deposit',
  'polymarket.browse',
  'polymarket.trade',
  'polymarket.deposit',
};

/// The badge poll for a wallet that traded: provisioned, $6.54 free.
class _Badge extends HlOpenPositionsCountNotifier {
  static int builds = 0;

  @override
  int build() {
    builds++;
    Future<void>.microtask(() {
      ref.read(hyperliquidProvisionedProvider.notifier).state = true;
      ref.read(hyperliquidFreeUsdcProvider.notifier).state = 6.54;
    });
    return 0;
  }
}

class _NoHl extends HyperliquidTradingNotifier {
  @override
  Future<HyperliquidTradingState> build() async =>
      const HyperliquidTradingState();
}

class _Pm extends PolymarketTradingNotifier {
  _Pm(this._state);

  final PolymarketTradingState _state;

  @override
  Future<PolymarketTradingState> build() async => _state;
}

class _Rail implements HyperliquidMoveRail {
  Object? error;
  final calls = <String>[];

  @override
  Future<double> withdrawableUsd() async => 6.54;

  @override
  Future<void> ensureGasFloat() async {}

  @override
  Future<VenueMoveResult> withdrawToDollars({
    required double usd,
    required MoveAuthorization auth,
    String purpose = 'sweep',
  }) async {
    calls.add('$purpose:$usd');
    expect(auth, SweepAuthorization.automatic);
    final failure = error;
    if (failure != null) throw failure;
    return VenueMoveResult(
        quoteId: 'q_hl',
        orderId: 'ord_hl',
        sentUsd: usd,
        arrivingUsdEstimate: usd - 0.1);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PmFunder implements SweepableVenueFunder {
  final calls = <String>[];

  @override
  Future<VenueMoveResult> sweepToDollars({
    required double usd,
    required MoveAuthorization auth,
    String purpose = 'sweep',
  }) async {
    calls.add('$purpose:$usd');
    return VenueMoveResult(
        quoteId: 'q_pm',
        orderId: 'ord_pm',
        sentUsd: usd,
        arrivingUsdEstimate: usd - 0.1);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Position _position(double value) => Position(
      proxyWallet: '0xproxy',
      asset: '1',
      conditionId: '0xc0',
      size: 10,
      avgPrice: 0.5,
      initialValue: 5,
      currentValue: value,
      cashPnl: 0,
      percentPnl: 0,
      totalBought: 10,
      realizedPnl: 0,
      percentRealizedPnl: 0,
      curPrice: 0.5,
      redeemable: false,
      title: 'm',
      slug: 'm',
      eventSlug: 'e',
      outcome: 'Yes',
      outcomeIndex: 0,
      oppositeOutcome: 'No',
      oppositeAsset: '2',
    );

Settings _settings() => Settings(
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: false,
      biometricsEnabled: false,
      bitcoinElectrumNode: 'x',
      nodeType: 'x',
      reviewDone: true,
      activeWalletId: 'spend',
      wallets: [WalletConfig(id: 'spend', name: 'Spending Wallet')],
    );

void main() {
  late RuntimeCapabilitiesService policy;
  late Directory hiveDir;

  setUpAll(() {
    // The sweeper reads the settlement store before it sends.
    hiveDir = Directory.systemTemp.createTempSync('sweeper_provider_test');
    Hive.init(hiveDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    hiveDir.deleteSync(recursive: true);
  });

  setUp(() async {
    AffiliateService.debugSessionToken = 'test-session';
    policy = runtimePolicyFixture(
        blocked: _withheld,
        also: const {'hyperliquid.browse', 'polymarket.browse'});
    expect(await policy.refresh(), isTrue);
    RuntimeCapabilitiesService.debugInstance = policy;
    _Badge.builds = 0;
    VenueActivity.reset();
    VenueActivity.clock = DateTime.now;
    PredictionFundingLedger.reset();
  });

  tearDown(() {
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
    policy.dispose();
  });

  ({ProviderContainer c, _Rail rail, _PmFunder pm}) bind(
      PolymarketTradingState pmState) {
    final rail = _Rail();
    final pm = _PmFunder();
    final c = ProviderContainer(overrides: [
      runtimeCapabilitiesProvider.overrideWithValue(policy),
      settingsProvider.overrideWith((_) => SettingsModel(_settings())),
      sessionUnlockedProvider.overrideWithValue(true),
      hyperliquidOpenPositionsCountProvider.overrideWith(_Badge.new),
      hyperliquidTradingProvider.overrideWith(_NoHl.new),
      polymarketTradingProvider.overrideWith(() => _Pm(pmState)),
      swapOrdersProvider.overrideWith((_) => FakeSwapOrders()),
      usdBalanceProvider.overrideWith((_) => 0),
      routeMinimumsProvider
          .overrideWithValue(RouteMinimums(fetch: (_) async => null)),
      hyperliquidMoveRailProvider.overrideWithValue(rail),
      predictionsSweepFunderProvider.overrideWithValue(pm),
    ]);
    addTearDown(c.dispose);
    return (c: c, rail: rail, pm: pm);
  }

  test('the policy under test withholds browse, trade and deposit only', () {
    for (final id in _withheld) {
      expect(policy.allows(id), isFalse, reason: id);
    }
    expect(policy.allows('hyperliquid.withdraw'), isTrue);
    expect(policy.allows('polymarket.withdraw'), isTrue);
    expect(policy.allows('polymarket.close'), isTrue);
  });

  test('Investing cash comes home with no Investing surface ever opened',
      () async {
    final b = bind(const PolymarketTradingState());
    b.c.read(venueSweeperProvider);
    // The sweeper keeps the badge poll alive: it is what knows the cash.
    expect(b.c.exists(hyperliquidOpenPositionsCountProvider), isTrue);
    expect(_Badge.builds, 1);
    await Future<void>.delayed(Duration.zero);
    expect(b.c.read(hyperliquidFreeUsdcProvider), 6.54);

    await b.c.read(venueSweeperProvider.notifier).trigger('resume');
    expect(b.rail.calls, ['sweep:6.54']);
    expect(b.c.exists(hyperliquidTradingProvider), isFalse,
        reason: 'the trading stack is not needed to read or sweep the cash');
  });

  test('cash the rail cannot carry yet stays in the header total and line',
      () async {
    final b = bind(const PolymarketTradingState());
    b.c.read(venueSweeperProvider);
    await Future<void>.delayed(Duration.zero);
    b.rail.error = const RouteUnavailable('cctp_fee_terms_unavailable');
    await b.c.read(venueSweeperProvider.notifier).trigger('resume');
    expect(b.rail.calls, ['sweep:6.54']);
    final state = b.c.read(oneBalanceProvider);
    expect(state.waiting, {OneBalanceVenue.investing: 6.54});
    expect(state.totalUsd, closeTo(6.54, 1e-9));
  });

  test('Predictions: positions stay counted and idle cash comes home',
      () async {
    final b = bind(PolymarketTradingState(
      isAuthenticated: true,
      balanceKnown: true,
      usdcBalance: 7.5,
      openPositions: [_position(30)],
    ));
    b.c.read(venueSweeperProvider);
    await b.c.read(polymarketTradingProvider.future);
    await Future<void>.delayed(Duration.zero);
    await b.c.read(venueSweeperProvider.notifier).trigger('resume');
    expect(b.pm.calls, ['sweep:7.5']);
    final state = b.c.read(oneBalanceProvider);
    expect(state.investedUsd, 30, reason: 'the open position stays visible');
    expect(state.predictionsKnown, isTrue);
  });

  group('Predictions cash after a funded bet that failed', () {
    PendingBetIntent failedBet() => const PendingBetIntent(
          tokenId: '1',
          amount: 10,
          slippagePct: 5,
          marketQuestion: 'Bitcoin Up or Down',
          outcomeName: 'Up',
          expectedPrice: 0.5,
          status: PendingBetStatus.failed,
          fundUsd: 10,
          fundQuoteRef: 'ref_move',
        );

    Future<({ProviderContainer c, _PmFunder pm})> landed() async {
      final b = bind(const PolymarketTradingState(
          isAuthenticated: true, balanceKnown: true, usdcBalance: 10.4));
      b.c.read(venueSweeperProvider);
      await b.c.read(polymarketTradingProvider.future);
      await Future<void>.delayed(Duration.zero);
      return (c: b.c, pm: b.pm);
    }

    test('funded, failed, landed: the cash stays, available, while the '
        'venue is in use', () async {
      // The move left, landed, its order failed and released it now.
      final ledger = PredictionFundingLedger.instance;
      ledger.sent('ref_move', usd: 10);
      ledger.landed('ref_move');
      ledger.release('ref_move', reason: 'failed');
      final b = await landed();
      b.c.read(pendingPolymarketBetProvider.notifier).setIntent(failedBet());
      await b.c.read(venueSweeperProvider.notifier).trigger('resume');
      expect(b.pm.calls, isEmpty, reason: 'no sweep within a day of use');
      expect(b.c.read(venueSweeperProvider).waiting, isEmpty,
          reason: 'never shown as waiting or unavailable');
      // Still the person's money in the total meanwhile.
      expect(b.c.read(venueSweeperProvider).dust,
          {OneBalanceVenue.predictions: 10.4});
      expect(b.c.read(oneBalanceProvider).totalUsd, closeTo(10.4, 1e-9));
    });

    test('a day idle: swept back to Dollars with no action, although the '
        'failed bet is still on the slip', () async {
      final events = <(String, Map<String, Object>?)>[];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      addTearDown(() => TrackingService.debugTrackObserver = null);
      final ledger = PredictionFundingLedger.instance;
      final dayAgo = DateTime.now()
          .subtract(kVenueIdleSweepAfter + const Duration(minutes: 1));
      VenueActivity.clock = () => dayAgo;
      PredictionFundingLedger.clock = () => dayAgo;
      addTearDown(() => PredictionFundingLedger.clock = DateTime.now);
      ledger.sent('ref_move', usd: 10);
      ledger.landed('ref_move');
      ledger.release('ref_move', reason: 'failed');
      VenueActivity.clock = DateTime.now;
      final b = await landed();
      // Before: any intent on the provider held every sweep for good.
      b.c.read(pendingPolymarketBetProvider.notifier).setIntent(failedBet());
      await b.c.read(venueSweeperProvider.notifier).trigger('timer');
      expect(b.pm.calls, ['sweep:10.4']);
      final started =
          events.firstWhere((e) => e.$1 == 'venue_sweep_started').$2!;
      expect(started['trigger'], 'predictions_idle_24h');
    });

    test('a bet still waiting for its money holds the cash, idle or not',
        () async {
      final b = await landed();
      b.c.read(pendingPolymarketBetProvider.notifier).setIntent(
          failedBet().copyWith(status: PendingBetStatus.awaitingBalance));
      await b.c.read(venueSweeperProvider.notifier).trigger('timer');
      expect(b.pm.calls, isEmpty);
    });

    test('open orders keep the venue in use', () {
      final now = DateTime.now();
      expect(predictionsLastActivity(openOrders: true, now: now), now);
      expect(predictionsLastActivity(openOrders: false, now: now),
          DateTime.fromMillisecondsSinceEpoch(0));
    });
  });

  test('only a recent move on its way holds a sweep, not a stuck record',
      () {
    final now = DateTime.now();
    final recent = now.subtract(const Duration(minutes: 5));
    final old = now.subtract(const Duration(days: 3));
    expect(settlementHoldsVenueCash(SettlementStage.processing, recent,
        now: now), isTrue);
    expect(settlementHoldsVenueCash(SettlementStage.broadcasting, recent,
        now: now), isTrue);
    expect(settlementHoldsVenueCash(SettlementStage.processing, old, now: now),
        isFalse);
    for (final stuck in [
      SettlementStage.failed,
      SettlementStage.needsAttention,
      SettlementStage.fundingUnknown,
      SettlementStage.lateDeposit,
      SettlementStage.notFunded,
    ]) {
      expect(settlementHoldsVenueCash(stuck, recent, now: now), isFalse,
          reason: stuck.name);
    }
  });

  test('only a bet waiting, placing or awaiting its answer holds the cash',
      () {
    PendingBetIntent at(PendingBetStatus s) => PendingBetIntent(
        tokenId: '1',
        amount: 1,
        slippagePct: 5,
        marketQuestion: 'q',
        outcomeName: 'o',
        expectedPrice: 0.5,
        status: s);
    expect(pendingBetHoldsCash(null), isFalse);
    for (final s in PendingBetStatus.values) {
      expect(
          pendingBetHoldsCash(at(s)),
          const {
            PendingBetStatus.converting,
            PendingBetStatus.awaitingBalance,
            PendingBetStatus.placing,
            PendingBetStatus.awaitingConfirmation,
          }.contains(s),
          reason: s.name);
    }
  });
}
