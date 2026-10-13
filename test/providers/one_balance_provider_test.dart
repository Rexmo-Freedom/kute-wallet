// The one-balance header state: what each input turns into.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/one_balance_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/usd_account_provider.dart';
import 'package:kute/providers/venue_sweeper_provider.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show Order, Position;

import '../helpers/fake_swap_orders.dart';

class _UninitializedHl extends HyperliquidTradingNotifier {
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

class _FixedSweeper extends VenueSweeperNotifier {
  _FixedSweeper(this._fixed);

  final VenueSweeperState _fixed;

  @override
  VenueSweeperState build() => _fixed;

  void set(VenueSweeperState next) => state = next;

  @override
  Future<void> trigger(String reason, {OneBalanceVenue? venue}) async {}
}

// Real time: the provider stamps rows against `DateTime.now()`.
final _now = DateTime.now();

Settings _settings({bool spending = true}) => Settings(
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: false,
      biometricsEnabled: false,
      bitcoinElectrumNode: 'x',
      nodeType: 'x',
      reviewDone: true,
      activeWalletId: spending ? 'spend' : null,
      wallets: [
        if (spending) WalletConfig(id: 'spend', name: 'Spending Wallet'),
      ],
    );

SwapOrder _row({
  required String id,
  required String coinFrom,
  required String networkFrom,
  required String coinTo,
  required String networkTo,
  String status = 'exchanging',
  String depositAmount = '10',
  String withdrawalAmount = '9.9',
  DateTime? at,
  String? walletId,
}) =>
    SwapOrder(
      id: id,
      coinFrom: coinFrom,
      networkFrom: networkFrom,
      coinTo: coinTo,
      networkTo: networkTo,
      depositAddress: 'd',
      depositAmount: depositAmount,
      withdrawalAmount: withdrawalAmount,
      status: status,
      timestamp: (at ?? _now).millisecondsSinceEpoch,
      withdrawalAddress: 'r',
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: 'f',
      provider: 'Orchestra',
      walletId: walletId,
    );

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

Order _buy({String original = '10', String matched = '0', String price = '0.5'}) =>
    Order(
        id: 'o',
        market: 'm',
        assetId: 't',
        owner: 'u',
        side: 'BUY',
        price: price,
        originalSize: original,
        sizeMatched: matched,
        outcome: 'Yes');

void main() {
  group('inFlightMovesFrom', () {
    final nowMs = _now.millisecondsSinceEpoch;

    test('classifies every pending row by direction and venue', () {
      final moves = inFlightMovesFrom([
        _row(id: 'a', coinFrom: 'USDB', networkFrom: 'SPARK', coinTo: 'USDC', networkTo: 'POLYGON', depositAmount: '5'),
        _row(id: 'b', coinFrom: 'USDB', networkFrom: 'SPARK', coinTo: 'USDC', networkTo: 'HYPERCORE', depositAmount: '7'),
        _row(id: 'c', coinFrom: 'USDC.e', networkFrom: 'POLYGON', coinTo: 'USDB', networkTo: 'SPARK', withdrawalAmount: '12.4'),
        _row(id: 'd', coinFrom: 'USDC', networkFrom: 'HYPERCORE', coinTo: 'USDB', networkTo: 'SPARK', withdrawalAmount: '3'),
        _row(id: 'e', coinFrom: 'BTC', networkFrom: 'SPARK', coinTo: 'USDB', networkTo: 'SPARK', withdrawalAmount: '20'),
        _row(id: 'f', coinFrom: 'USD', networkFrom: 'CASHAPP', coinTo: 'USDB', networkTo: 'SPARK', withdrawalAmount: '15'),
      ], walletId: null, nowMs: nowMs);
      expect(moves, const [
        InFlightMove(kind: InFlightKind.toVenue, venue: OneBalanceVenue.predictions, usd: 5),
        InFlightMove(kind: InFlightKind.toVenue, venue: OneBalanceVenue.investing, usd: 7),
        InFlightMove(kind: InFlightKind.fromVenue, venue: OneBalanceVenue.predictions, usd: 12.4),
        InFlightMove(kind: InFlightKind.fromVenue, venue: OneBalanceVenue.investing, usd: 3),
        InFlightMove(kind: InFlightKind.incomingDollars, usd: 35),
      ]);
    });

    test('settled, stale and other-wallet rows are not in flight', () {
      final moves = inFlightMovesFrom([
        _row(id: 'a', coinFrom: 'USDB', networkFrom: 'SPARK', coinTo: 'USDC', networkTo: 'POLYGON', status: 'success'),
        _row(id: 'b', coinFrom: 'USDB', networkFrom: 'SPARK', coinTo: 'USDC', networkTo: 'POLYGON', at: _now.subtract(const Duration(minutes: 31))),
        _row(id: 'c', coinFrom: 'BTC', networkFrom: 'SPARK', coinTo: 'USDB', networkTo: 'SPARK', walletId: 'other'),
        _row(id: 'd', coinFrom: 'BTC', networkFrom: 'SPARK', coinTo: 'USDB', networkTo: 'SPARK', at: _now.subtract(const Duration(minutes: 31))),
      ], walletId: 'mine', nowMs: nowMs);
      expect(moves, isEmpty);
    });
  });

  group('oneBalanceProvider', () {
    ProviderContainer container({
      required PolymarketTradingState pm,
      List<SwapOrder> rows = const [],
      VenueSweeperState sweeper = const VenueSweeperState(),
      double dollars = 0,
      bool spending = true,
    }) =>
        ProviderContainer(overrides: [
          settingsProvider.overrideWith(
              (_) => SettingsModel(_settings(spending: spending))),
          hyperliquidTradingProvider.overrideWith(_UninitializedHl.new),
          polymarketTradingProvider.overrideWith(() => _Pm(pm)),
          swapOrdersProvider.overrideWith((_) => FakeSwapOrders(rows)),
          venueSweeperProvider.overrideWith(() => _FixedSweeper(sweeper)),
          usdBalanceProvider.overrideWith((_) => dollars),
        ]);

    test('unknown venues count as zero and say so', () async {
      final c = container(pm: const PolymarketTradingState());
      addTearDown(c.dispose);
      await c.read(polymarketTradingProvider.future);
      final s = c.read(oneBalanceProvider);
      expect(s.investedUsd, 0);
      expect(s.predictionsKnown, isFalse, reason: 'not authenticated yet');
      expect(s.investingKnown, isTrue,
          reason: 'never provisioned Hyperliquid: known to hold nothing');
      expect(s.inFlight, isEmpty);
      expect(s.waiting, isEmpty);
    });

    test('without a spending wallet nothing is known about the venues',
        () async {
      final c = container(
        spending: false,
        pm: const PolymarketTradingState(
            isAuthenticated: true, balanceKnown: true, usdcBalance: 20),
      );
      addTearDown(c.dispose);
      await c.read(polymarketTradingProvider.future);
      final s = c.read(oneBalanceProvider);
      expect(s.investedUsd, 0);
      expect(s.predictionsKnown, isFalse);
      expect(s.investingKnown, isFalse);
    });

    test('invested is positions plus committed cash, never idle cash',
        () async {
      final c = container(
        dollars: 100,
        pm: PolymarketTradingState(
          isAuthenticated: true,
          balanceKnown: true,
          usdcBalance: 20,
          openPositions: [_position(30)],
          openOrders: [_buy(original: '10', price: '0.5')],
        ),
      );
      addTearDown(c.dispose);
      await c.read(polymarketTradingProvider.future);
      final s = c.read(oneBalanceProvider);
      expect(s.dollarsUsd, 100);
      // 30 in positions + 5 reserved by the resting BUY; the other 15 of
      // venue cash is the sweeper's, not "invested".
      expect(s.investedUsd, 35);
      expect(s.predictionsKnown, isTrue);
      expect(s.availableUsd, 100);
    });

    test('in flight and waiting come from the rows and the sweeper',
        () async {
      final c = container(
        dollars: 50,
        pm: const PolymarketTradingState(
            isAuthenticated: true, balanceKnown: true, usdcBalance: 0),
        rows: [
          _row(id: 'a', coinFrom: 'USDB', networkFrom: 'SPARK', coinTo: 'USDC', networkTo: 'POLYGON', depositAmount: '5'),
          _row(id: 'b', coinFrom: 'BTC', networkFrom: 'SPARK', coinTo: 'USDB', networkTo: 'SPARK', withdrawalAmount: '20'),
        ],
        sweeper: const VenueSweeperState(
            waiting: {OneBalanceVenue.investing: 0.6},
            sweeping: {OneBalanceVenue.investing}),
      );
      addTearDown(c.dispose);
      await c.read(polymarketTradingProvider.future);
      final s = c.read(oneBalanceProvider);
      expect(s.inFlight, const [
        InFlightMove(kind: InFlightKind.toVenue, venue: OneBalanceVenue.predictions, usd: 5),
        InFlightMove(kind: InFlightKind.incomingDollars, usd: 20),
      ]);
      expect(s.waiting, {OneBalanceVenue.investing: 0.6});
      expect(s.totalUsd, closeTo(75.6, 1e-9));
    });

    test('dust counts in the total as invested, never as waiting', () async {
      // The founder's screenshot: $6.20 home, $0.06 left on HyperCore.
      final c = container(
        dollars: 6.20,
        pm: const PolymarketTradingState(
            isAuthenticated: true, balanceKnown: true, usdcBalance: 0),
        sweeper: const VenueSweeperState(
            dust: {OneBalanceVenue.investing: 0.06}),
      );
      addTearDown(c.dispose);
      await c.read(polymarketTradingProvider.future);
      final s = c.read(oneBalanceProvider);
      expect(s.waiting, isEmpty);
      expect(s.waitingUsd, 0);
      expect(s.inFlight, isEmpty);
      expect(s.investedUsd, closeTo(0.06, 1e-9));
      expect(s.totalUsd, closeTo(6.26, 1e-9));
    });

    test('investedWithDust adds every venue\'s dust', () {
      expect(
          investedWithDust(10, const {
            OneBalanceVenue.investing: 0.06,
            OneBalanceVenue.predictions: 0.3,
          }),
          closeTo(10.36, 1e-9));
      expect(investedWithDust(double.nan, const {}), 0);
    });

    test('the sweeper state reaching the header is one provider tick',
        () async {
      final c = container(
        pm: const PolymarketTradingState(
            isAuthenticated: true, balanceKnown: true, usdcBalance: 0),
      );
      addTearDown(c.dispose);
      await c.read(polymarketTradingProvider.future);
      final seen = <OneBalanceState>[];
      c.listen(oneBalanceProvider, (_, next) => seen.add(next));
      (c.read(venueSweeperProvider.notifier) as _FixedSweeper).set(
          const VenueSweeperState(waiting: {OneBalanceVenue.predictions: 0.4}));
      await c.pump();
      expect(seen.single.waiting, {OneBalanceVenue.predictions: 0.4});
    });
  });
}
