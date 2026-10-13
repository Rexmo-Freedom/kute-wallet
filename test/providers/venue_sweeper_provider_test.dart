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
import 'package:kute/services/runtime_capabilities_service.dart';
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
}
