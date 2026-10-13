// The Investments header's arithmetic end to end: Dollars, venue cash
// (held / dust / waiting), positions, reserved order cash, pending fills
// and live marks, through the real venue and one-balance providers.
//
// Founder report (2026-10-13, real device): "$3.55 in Predictions, placed
// a bet from it, and the total went to $6.65"; Available did not drop on
// the fill. Before the bet: $6.20 Dollars + $0.06 Investing dust + $3.55
// Predictions cash = $9.81. After a $3.55 bet at ~$0.50 (7.1 shares) the
// total stays ≈ $9.81 (the position at its mark), Available is $6.26.
//
// Founder decision (same day): venue cash is ALWAYS Available, dust
// included. Dust (below the route minimum) only keeps the sweeper away;
// it is spendable at its venue and the engine can pull it. Invested is
// positions (marked), reserved order cash and pending fills, nothing else.
// So before the bet Available is the whole $9.81, and after a $3.55 bet
// that filled at $3.16 it is $6.20 + $0.06 + $0.39 = $6.65.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart'
    show hyperliquidFreeUsdcProvider, hyperliquidProvisionedProvider;
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/one_balance_live_provider.dart';
import 'package:kute/providers/one_balance_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/unified_balances_provider.dart';
import 'package:kute/providers/usd_account_provider.dart';
import 'package:kute/providers/venue_sweeper_provider.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/polymarket/pending_fills.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show Order, Position;

import '../helpers/fake_swap_orders.dart';

class _Hl extends HyperliquidTradingNotifier {
  _Hl(this._state);

  final HyperliquidTradingState _state;

  @override
  Future<HyperliquidTradingState> build() async => _state;
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

  @override
  Future<void> trigger(String reason, {OneBalanceVenue? venue}) async {}
}

class _Marks extends OneBalanceLiveNotifier {
  _Marks(this._fixed);

  final OneBalanceLiveMarks _fixed;

  @override
  OneBalanceLiveMarks build() => _fixed;
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
      activeWalletId: 'spend',
      wallets: [WalletConfig(id: 'spend', name: 'Spending Wallet')],
    );

const _token = 'tok-up';

/// Dollars on the spending account in every case.
const _dollars = 6.20;

Position _position({
  String asset = _token,
  required double size,
  required double price,
}) =>
    Position(
      proxyWallet: '0xproxy',
      asset: asset,
      conditionId: '0xc-$asset',
      size: size,
      avgPrice: price,
      initialValue: size * price,
      currentValue: size * price,
      cashPnl: 0,
      percentPnl: 0,
      totalBought: size,
      realizedPnl: 0,
      percentRealizedPnl: 0,
      curPrice: price,
      redeemable: false,
      title: 'm',
      slug: 'm',
      eventSlug: 'e',
      outcome: 'Up',
      outcomeIndex: 0,
      oppositeOutcome: 'Down',
      oppositeAsset: 'tok-down',
    );

Order _restingBuy({required String size, required String price}) => Order(
    id: 'o1',
    market: 'm',
    assetId: _token,
    owner: 'u',
    side: 'BUY',
    price: price,
    originalSize: size,
    sizeMatched: '0',
    outcome: 'Up');

final _at = DateTime(2026, 10, 13, 18);

PolymarketPendingFill _fill({
  required double shares,
  required double price,
  double expected = 0,
  double cashBefore = 3.55,
  bool indexed = false,
  bool cashSettled = false,
}) =>
    PolymarketPendingFill(
      key: 'order-1',
      tokenId: _token,
      shares: shares,
      price: price,
      costUsd: shares * price,
      expectedShares: expected == 0 ? shares : expected,
      cashBeforeUsd: cashBefore,
      at: _at,
      indexed: indexed,
      cashSettled: cashSettled,
    );

PolymarketTradingState _pm({
  required double cash,
  List<Position> positions = const [],
  List<Order> orders = const [],
  List<PolymarketPendingFill> fills = const [],
}) =>
    PolymarketTradingState(
      isAuthenticated: true,
      balanceKnown: true,
      usdcBalance: cash,
      openPositions: positions,
      openOrders: orders,
      proxyWalletAddress: '0xproxy',
      pendingFills: fills,
    );

class _Case {
  const _Case(
    this.name, {
    required this.pm,
    this.hl,
    this.hlFreeUsdc = 0.06,
    this.sweeper = const VenueSweeperState(),
    this.marks = OneBalanceLiveMarks.zero,
    required this.total,
    required this.available,
    required this.invested,
  });

  final String name;
  final PolymarketTradingState pm;
  final HyperliquidTradingState? hl;
  final double hlFreeUsdc;
  final VenueSweeperState sweeper;
  final OneBalanceLiveMarks marks;
  final double total;
  final double available;
  final double invested;
}

ProviderContainer _container(_Case c) => ProviderContainer(overrides: [
      settingsProvider.overrideWith((_) => SettingsModel(_settings())),
      hyperliquidProvisionedProvider.overrideWith((_) => c.hl != null),
      hyperliquidFreeUsdcProvider.overrideWith((_) => c.hlFreeUsdc),
      hyperliquidTradingProvider
          .overrideWith(() => _Hl(c.hl ?? const HyperliquidTradingState())),
      polymarketTradingProvider.overrideWith(() => _Pm(c.pm)),
      swapOrdersProvider.overrideWith((_) => FakeSwapOrders(const [])),
      venueSweeperProvider.overrideWith(() => _FixedSweeper(c.sweeper)),
      oneBalanceLiveProvider.overrideWith(() => _Marks(c.marks)),
      usdBalanceProvider.overrideWith((_) => _dollars),
    ]);

Future<OneBalanceState> _header(ProviderContainer c) async {
  await c.read(polymarketTradingProvider.future);
  await c.read(hyperliquidTradingProvider.future);
  return c.read(oneBalanceProvider);
}

const _hlDust = {OneBalanceVenue.investing: 0.06};

void main() {
  group('the header adds up', () {
    final cases = <_Case>[
      _Case(
        'before the bet: Dollars + Investing dust + Predictions cash kept',
        pm: _pm(cash: 3.55),
        sweeper: const VenueSweeperState(
            dust: _hlDust, held: {OneBalanceVenue.predictions: 3.55}),
        total: 9.81,
        available: 9.81,
        invested: 0,
      ),
      _Case(
        'the fill, before any read: cash off at once, the shares counted, '
        'the sweeper\'s stale held capped',
        pm: _pm(cash: 0, fills: [_fill(shares: 7.1, price: 0.50)]),
        sweeper: const VenueSweeperState(
            dust: _hlDust, held: {OneBalanceVenue.predictions: 3.55}),
        total: 9.81,
        available: 6.26,
        invested: 3.55,
      ),
      _Case(
        'the founder\'s \$6.65: a \$3.16 fill left \$0.39, the sweeper made '
        'it dust, the positions read had not listed the shares',
        pm: _pm(
            cash: 0.39,
            fills: [_fill(shares: 6.32, price: 0.50, cashSettled: true)]),
        sweeper: const VenueSweeperState(dust: {
          OneBalanceVenue.investing: 0.06,
          OneBalanceVenue.predictions: 0.39,
        }),
        // Was 6.20 + 0.06 + 0.39 = 6.65 in all with the shares dropped.
        // Now the leftover and the dust are Available, the shares Invested.
        total: 9.81,
        available: 6.65,
        invested: 3.16,
      ),
      _Case(
        'the positions read caught up; the sweeper still says 3.55 held',
        pm: _pm(cash: 0, positions: [_position(size: 7.1, price: 0.50)]),
        sweeper: const VenueSweeperState(
            dust: _hlDust, held: {OneBalanceVenue.predictions: 3.55}),
        total: 9.81,
        available: 6.26,
        invested: 3.55,
      ),
      _Case(
        'marked at the bid between reads (0.48)',
        pm: _pm(cash: 0, positions: [_position(size: 7.1, price: 0.50)]),
        sweeper: const VenueSweeperState(dust: _hlDust),
        marks: const OneBalanceLiveMarks(predictionsDeltaUsd: 7.1 * -0.02),
        total: 9.81 - 0.142,
        available: 6.26,
        invested: 3.55 - 0.142,
      ),
      _Case(
        'a pending fill is marked from the first tick too',
        pm: _pm(cash: 0, fills: [_fill(shares: 7.1, price: 0.50)]),
        sweeper: const VenueSweeperState(dust: _hlDust),
        marks: const OneBalanceLiveMarks(predictionsDeltaUsd: 7.1 * -0.02),
        total: 9.81 - 0.142,
        available: 6.26,
        invested: 3.55 - 0.142,
      ),
      _Case(
        'partial cash use: a \$2 bet, \$1.55 stays Available (with the dust)',
        pm: _pm(cash: 1.55, positions: [_position(size: 4, price: 0.50)]),
        sweeper: const VenueSweeperState(
            dust: _hlDust, held: {OneBalanceVenue.predictions: 3.55}),
        total: 9.81,
        available: 7.81,
        invested: 2,
      ),
      _Case(
        'a resting buy reserves \$2 of the \$3.55: Invested, not Available',
        pm: _pm(cash: 3.55, orders: [_restingBuy(size: '4', price: '0.5')]),
        sweeper: const VenueSweeperState(
            dust: _hlDust, held: {OneBalanceVenue.predictions: 3.55}),
        total: 9.81,
        available: 7.81,
        invested: 2,
      ),
      _Case(
        'an Investing position with its cash',
        pm: _pm(cash: 0),
        hl: const HyperliquidTradingState(
            isInitialized: true, perpEquity: 10, withdrawable: 4),
        hlFreeUsdc: 0,
        sweeper: const VenueSweeperState(held: {OneBalanceVenue.investing: 4}),
        total: 16.20,
        available: 10.20,
        invested: 6,
      ),
      _Case(
        'Investing cash the sweeper last saw higher is capped by the read',
        pm: _pm(cash: 0),
        hl: const HyperliquidTradingState(
            isInitialized: true, perpEquity: 10, withdrawable: 4),
        hlFreeUsdc: 0,
        sweeper: const VenueSweeperState(held: {OneBalanceVenue.investing: 9}),
        total: 16.20,
        available: 10.20,
        invested: 6,
      ),
      _Case(
        'both venues: positions and cash, each once',
        pm: _pm(cash: 1, positions: [_position(size: 7.1, price: 0.50)]),
        hl: const HyperliquidTradingState(
            isInitialized: true, perpEquity: 10, withdrawable: 4),
        hlFreeUsdc: 0,
        sweeper: const VenueSweeperState(held: {
          OneBalanceVenue.investing: 4,
          OneBalanceVenue.predictions: 1,
        }),
        total: 6.20 + 10 + 3.55 + 1,
        available: 6.20 + 4 + 1,
        invested: 6 + 3.55,
      ),
      _Case(
        'Investing dust is counted once, in Available',
        pm: _pm(cash: 0),
        sweeper: const VenueSweeperState(
            dust: _hlDust, held: {OneBalanceVenue.investing: 0.06}),
        total: 6.26,
        available: 6.26,
        invested: 0,
      ),
      _Case(
        'Predictions dust at a venue in use: Available, never Invested',
        pm: _pm(cash: 3.55),
        hlFreeUsdc: 0,
        sweeper: const VenueSweeperState(
            dust: {OneBalanceVenue.predictions: 3.55}),
        total: 9.75,
        available: 9.75,
        invested: 0,
      ),
    ];

    for (final c in cases) {
      test(c.name, () async {
        final container = _container(c);
        addTearDown(container.dispose);
        final s = await _header(container);
        expect(s.totalUsd, closeTo(c.total, 1e-6), reason: 'total');
        expect(s.availableUsd, closeTo(c.available, 1e-6), reason: 'available');
        expect(s.investedUsd, closeTo(c.invested, 1e-6), reason: 'invested');
        // Nothing in flight or waiting in these: the split is the total.
        expect(s.availableUsd + s.investedUsd, closeTo(s.totalUsd, 1e-6));
      });
    }
  });

  group('the bet filling', () {
    test('Available drops by the spent cash the moment the bet fills',
        () async {
      final container = _container(_Case('fill',
          pm: _pm(cash: 3.55),
          sweeper: const VenueSweeperState(
              dust: _hlDust, held: {OneBalanceVenue.predictions: 3.55}),
          total: 0,
          available: 0,
          invested: 0));
      addTearDown(container.dispose);
      final before = await _header(container);
      expect(before.totalUsd, closeTo(9.81, 1e-6));
      expect(before.availableUsd, closeTo(9.81, 1e-6));
      expect(before.investedUsd, 0);

      container.read(polymarketTradingProvider.notifier).notePendingFill(
          key: 'order-1', tokenId: _token, shares: 7.1, costUsd: 3.55);
      final after = container.read(oneBalanceProvider);
      expect(after.availableUsd, closeTo(6.26, 1e-6));
      expect(after.investedUsd, closeTo(3.55, 1e-6));
      expect(after.totalUsd, closeTo(9.81, 1e-6));

      // The same order again (the controller after the POST's echo):
      // nothing counted twice.
      container.read(polymarketTradingProvider.notifier).notePendingFill(
          key: 'order-1', tokenId: _token, shares: 7.1, costUsd: 3.55);
      expect(container.read(oneBalanceProvider).totalUsd, closeTo(9.81, 1e-6));
      final venues = container.read(unifiedVenueBalancesProvider);
      expect(venues.readyInPredictionsUsd, 0);
      expect(venues.investedInPredictionsUsd, closeTo(3.55, 1e-6));
    });

    test(
        'the founder\'s case: a \$3.55 bet that fills at \$3.16 leaves '
        '\$0.39 Available with the Dollars and the dust', () async {
      final container = _container(_Case('founder',
          pm: _pm(cash: 3.55),
          sweeper: const VenueSweeperState(
              dust: _hlDust, held: {OneBalanceVenue.predictions: 3.55}),
          total: 0,
          available: 0,
          invested: 0));
      addTearDown(container.dispose);
      final before = await _header(container);
      expect(before.availableUsd, closeTo(9.81, 1e-6));
      expect(before.investedUsd, 0);
      expect(before.totalUsd, closeTo(9.81, 1e-6));

      container.read(polymarketTradingProvider.notifier).notePendingFill(
          key: 'order-1', tokenId: _token, shares: 6.32, costUsd: 3.16);
      final after = container.read(oneBalanceProvider);
      expect(after.availableUsd, closeTo(6.20 + 0.06 + 0.39, 1e-6));
      expect(after.investedUsd, closeTo(3.16, 1e-6));
      expect(after.totalUsd, closeTo(9.81, 1e-6));
      expect(after.waiting, isEmpty);
    });
  });

  group('pending fills', () {
    test('a new fill expects what the read lists plus earlier fills', () {
      final first = newPendingFill(
          key: 'a',
          tokenId: _token,
          shares: 4,
          costUsd: 2,
          listedShares: 10,
          stateCashUsd: 5,
          pending: const [],
          now: _at)!;
      expect(first.expectedShares, 14);
      expect(first.price, 0.5);
      expect(first.cashBeforeUsd, 5);
      final second = newPendingFill(
          key: 'b',
          tokenId: _token,
          shares: 2,
          costUsd: 1,
          listedShares: 10,
          stateCashUsd: 3,
          pending: [first],
          now: _at)!;
      expect(second.expectedShares, 16);
      expect(
          newPendingFill(
              key: 'c',
              tokenId: _token,
              shares: 0,
              costUsd: 1,
              listedShares: 0,
              stateCashUsd: 0,
              pending: const [],
              now: _at),
          isNull);
    });

    test('the positions read listing the shares indexes the fill', () {
      final f = _fill(shares: 7.1, price: 0.5);
      expect(reconcilePendingFills([f], const {}, _at).single.valueUsd,
          closeTo(3.55, 1e-9));
      final partly = reconcilePendingFills([f], {_token: 3.1}, _at).single;
      expect(partly.shares, closeTo(4, 1e-9));
      expect(partly.valueUsd, closeTo(2, 1e-9));
      expect(partly.costUsd, closeTo(3.55, 1e-9),
          reason: 'the cash spent is the whole fill');
      final listed = reconcilePendingFills([f], {_token: 7.1}, _at).single;
      expect(listed.indexed, isTrue);
      expect(listed.valueUsd, 0);
      // Indexed and settled: gone.
      expect(
          reconcilePendingFills(
              [f.copyWith(cashSettled: true)], {_token: 7.1}, _at),
          isEmpty);
      // Never held for good.
      expect(
          reconcilePendingFills([f], const {},
              _at.add(kPendingFillTtl + const Duration(seconds: 1))),
          isEmpty);
    });

    test('the cash read is net of the spend until it shows it', () {
      final f = _fill(shares: 7.1, price: 0.5, cashBefore: 3.55);
      // Read before the chain settled (or the cached balance): 3.55 still.
      final (stale, f1) = netCashOfPendingFills(3.55, [f]);
      expect(stale, closeTo(0, 1e-9));
      expect(f1.single.cashSettled, isFalse);
      // The read shows the spend: settled, the read stands.
      final (fresh, f2) = netCashOfPendingFills(0, f1);
      expect(fresh, 0);
      expect(f2.single.cashSettled, isTrue);
      // A leftover after a smaller fill.
      final small = _fill(shares: 6.32, price: 0.5, cashBefore: 3.55);
      final (left, f3) = netCashOfPendingFills(0.39, [small]);
      expect(left, closeTo(0.39, 1e-9));
      expect(f3.single.cashSettled, isTrue);
    });

    test('two fills settle in order', () {
      final a = PolymarketPendingFill(
          key: 'a',
          tokenId: _token,
          shares: 4,
          price: 0.5,
          costUsd: 2,
          expectedShares: 4,
          cashBeforeUsd: 5,
          at: _at);
      final b = PolymarketPendingFill(
          key: 'b',
          tokenId: _token,
          shares: 2,
          price: 0.5,
          costUsd: 1,
          expectedShares: 6,
          cashBeforeUsd: 3,
          at: _at.add(const Duration(seconds: 1)));
      expect(netCashOfPendingFills(5, [a, b]).$1, closeTo(2, 1e-9));
      final (afterA, flags) = netCashOfPendingFills(3, [a, b]);
      expect(afterA, closeTo(2, 1e-9));
      expect(flags.map((f) => f.cashSettled), [true, false]);
      final (afterBoth, both) = netCashOfPendingFills(2, flags);
      expect(afterBoth, closeTo(2, 1e-9));
      expect(both.every((f) => f.cashSettled), isTrue);
    });

    test('live marks see a pending fill at its fill price', () {
      final held =
          heldOutcomesOf(_pm(cash: 0, fills: [_fill(shares: 7.1, price: 0.5)]));
      expect(held.single.token, _token);
      expect(held.single.size, 7.1);
      expect(held.single.readPrice, 0.5);
    });
  });
}
