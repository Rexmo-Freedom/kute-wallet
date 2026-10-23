// The Investments header follows the venues fast and only as much as the
// holdings ask: events refresh a venue at once, held outcomes are marked
// to market over a socket of exactly their tokens (at most once a
// second), a slow read reconciles while positions are open on screen,
// and an account holding nothing is never read on a timer.

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/active_shell_tab_provider.dart';
import 'package:kute/providers/auth_provider.dart' show appVisibleProvider;
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/one_balance_live_provider.dart';
import 'package:kute/providers/one_balance_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/usd_account_provider.dart';
import 'package:kute/providers/venue_sweeper_provider.dart';
import 'package:kute/services/one_balance/live_marks.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/venue_cash_released.dart';
import 'package:kute/services/polymarket_clob_websocket.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show Position;

import '../helpers/fake_swap_orders.dart';

class _UninitializedHl extends HyperliquidTradingNotifier {
  @override
  Future<HyperliquidTradingState> build() async =>
      const HyperliquidTradingState();
}

class _Pm extends PolymarketTradingNotifier {
  _Pm(this._initial);

  final PolymarketTradingState _initial;

  @override
  Future<PolymarketTradingState> build() async => _initial;

  void set(PolymarketTradingState next) => state = AsyncData(next);

  /// How many times the 30 s cached balance was dropped.
  int balanceCacheDropped = 0;

  @override
  void invalidateBalanceCache() => balanceCacheDropped++;
}

class _FixedSweeper extends VenueSweeperNotifier {
  @override
  VenueSweeperState build() => const VenueSweeperState();

  @override
  Future<void> trigger(String reason, {OneBalanceVenue? venue}) async {}
}

class _FakeSocket implements HeldMarketSocket {
  _FakeSocket(this.tokens);

  final List<String> tokens;
  final controller = StreamController<PolymarketWsMessage>.broadcast();
  bool disposed = false;

  @override
  Stream<PolymarketWsMessage> get messages => controller.stream;

  @override
  void dispose() {
    disposed = true;
    controller.close();
  }

  void book(String token, double bid, double ask) =>
      controller.add(PolymarketBookMessage(
        assetId: token,
        market: 'm',
        timestamp: 0,
        bids: [PolymarketOrderSummary(price: bid, size: 100)],
        asks: [PolymarketOrderSummary(price: ask, size: 100)],
        hash: 'h',
      ));
}

Position _position(String token, {double size = 10, double price = 0.5}) =>
    Position(
      proxyWallet: '0xproxy',
      asset: token,
      conditionId: '0xc-$token',
      size: size,
      avgPrice: 0.5,
      initialValue: size * 0.5,
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
      outcome: 'Yes',
      outcomeIndex: 0,
      oppositeOutcome: 'No',
      oppositeAsset: 'opp-$token',
    );

PolymarketTradingState _pm(List<Position> positions) => PolymarketTradingState(
    isAuthenticated: true,
    balanceKnown: true,
    usdcBalance: 0,
    openPositions: positions);

SwapOrder _fundingRow(String status) => poolDepositRow(
    id: 'ord_fund', network: 'POLYGON', usd: 5, status: status);

class _Rig {
  _Rig(FakeAsync async,
      {List<Position> positions = const [],
      Duration readFor = Duration.zero}) {
    final clock = async.getClock(DateTime(2026, 10, 13, 12));
    rows = FakeSwapOrders();
    container = ProviderContainer(overrides: [
      settingsProvider.overrideWith((_) => SettingsModel(Settings(
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
          ))),
      hyperliquidTradingProvider.overrideWith(_UninitializedHl.new),
      polymarketTradingProvider.overrideWith(() => _Pm(_pm(positions))),
      swapOrdersProvider.overrideWith((_) => rows),
      venueSweeperProvider.overrideWith(_FixedSweeper.new),
      usdBalanceProvider.overrideWith((_) => 100),
      heldMarketSocketFactoryProvider.overrideWithValue((tokens) {
        final s = _FakeSocket(tokens);
        sockets.add(s);
        return s;
      }),
      oneBalanceVenueRefreshProvider.overrideWithValue((venue) async {
        refreshes.add(venue);
        if (readFor > Duration.zero) await Future<void>.delayed(readFor);
      }),
      liveMarksClockProvider.overrideWithValue(clock.now),
    ]);
    container.read(activeShellTabProvider.notifier).state = ActiveNavTab.usd;
    container.listen(oneBalanceProvider, (_, __) {});
    async.flushMicrotasks();
    async.elapse(Duration.zero);
  }

  late final ProviderContainer container;
  late final FakeSwapOrders rows;
  final sockets = <_FakeSocket>[];
  final refreshes = <OneBalanceVenue>[];

  double get total => container.read(oneBalanceProvider).totalUsd;
  _Pm get pm => container.read(polymarketTradingProvider.notifier) as _Pm;
}

void main() {
  group('pure rules', () {
    test('Predictions marks are size × (live − read price)', () {
      const held = [
        HeldOutcome(token: 'a', size: 10, readPrice: 0.5),
        HeldOutcome(token: 'b', size: 4, readPrice: 0.2),
      ];
      expect(predictionsMarkDelta(held, {'a': 0.6}), closeTo(1.0, 1e-9));
      expect(predictionsMarkDelta(held, {'a': 0.6, 'b': 0.1}),
          closeTo(0.6, 1e-9));
      expect(predictionsMarkDelta(held, const {}), 0);
    });

    test('Investing marks are szi × (mid − read mark), long or short', () {
      const held = [
        HeldPerp(coin: 'BTC', szi: 0.1, positionValue: 10000),
        HeldPerp(coin: 'ETH', szi: -2, positionValue: 6000),
      ];
      // BTC read at 100 000, now 101 000: +100. ETH short read at 3 000,
      // now 3 100: −200.
      expect(investingMarkDelta(held, {'BTC': 101000, 'ETH': 3100}),
          closeTo(-100, 1e-6));
    });

    test('the cadence follows the holdings', () {
      final now = DateTime(2026, 10, 13, 12);
      Duration? at(
              {bool holds = true,
              bool visible = true,
              bool streamed = true,
              DateTime? event}) =>
          liveMarksReconcileInterval(
              holds: holds,
              visible: visible,
              streamed: streamed,
              now: now,
              lastEventAt: event);
      expect(at(holds: false), isNull);
      expect(at(visible: false), isNull);
      expect(at(), kLiveMarksReconcileSlow);
      expect(at(streamed: false), kLiveMarksReconcileFast);
      expect(at(event: now.subtract(const Duration(seconds: 30))),
          kLiveMarksReconcileFast);
      expect(at(event: now.subtract(const Duration(minutes: 2))),
          kLiveMarksReconcileSlow);
    });
  });

  test('nothing held: no socket and no read beyond the events', () {
    fakeAsync((async) {
      final rig = _Rig(async);
      addTearDown(rig.container.dispose);
      async.elapse(const Duration(minutes: 10));
      expect(rig.sockets, isEmpty);
      expect(rig.refreshes, isEmpty);

      // A funding move lands at Predictions: one read, at once.
      rig.rows.set([_fundingRow('exchanging')]);
      async.elapse(Duration.zero);
      expect(rig.refreshes, isEmpty, reason: 'nothing has landed yet');
      rig.rows.set([_fundingRow('success')]);
      async.elapse(Duration.zero);
      expect(rig.refreshes, [OneBalanceVenue.predictions]);

      // A claim or a close releases cash: one read, at once.
      VenueCashReleased.emit(OneBalanceVenue.investing, 'position_closed');
      async.elapse(Duration.zero);
      expect(rig.refreshes,
          [OneBalanceVenue.predictions, OneBalanceVenue.investing]);

      // And nothing on a timer afterwards.
      async.elapse(const Duration(minutes: 10));
      expect(rig.refreshes, hasLength(2));
    });
  });

  test('a Predictions event reads the chain, not the 30 s cached balance',
      () {
    fakeAsync((async) {
      final rig = _Rig(async);
      addTearDown(rig.container.dispose);
      expect(rig.pm.balanceCacheDropped, 0);
      rig.rows.set([_fundingRow('exchanging')]);
      async.elapse(Duration.zero);
      rig.rows.set([_fundingRow('success')]);
      async.elapse(Duration.zero);
      expect(rig.refreshes, [OneBalanceVenue.predictions]);
      expect(rig.pm.balanceCacheDropped, 1);
      // An Investing event leaves the Predictions cache alone.
      VenueCashReleased.emit(OneBalanceVenue.investing, 'position_closed');
      async.elapse(Duration.zero);
      expect(rig.pm.balanceCacheDropped, 1);
    });
  });

  test('an event during a running read gets one more read after it', () {
    fakeAsync((async) {
      final rig = _Rig(async, readFor: const Duration(seconds: 2));
      addTearDown(rig.container.dispose);
      VenueCashReleased.emit(OneBalanceVenue.investing, 'position_closed');
      async.elapse(const Duration(milliseconds: 500));
      expect(rig.refreshes, [OneBalanceVenue.investing]);
      // The deposit lands while that read runs: it may have read the
      // account before the money did, so one more read follows it.
      VenueCashReleased.emit(OneBalanceVenue.investing, 'reduce_fill');
      VenueCashReleased.emit(OneBalanceVenue.investing, 'reduce_fill');
      async.elapse(const Duration(milliseconds: 500));
      expect(rig.refreshes, hasLength(1), reason: 'never two at once');
      async.elapse(const Duration(seconds: 1));
      expect(rig.refreshes, hasLength(2));
      async.elapse(const Duration(seconds: 2));
      expect(rig.refreshes, hasLength(2), reason: 'once, however many asked');
    });
  });

  test('a held token\'s price tick moves the header total, once a second',
      () {
    fakeAsync((async) {
      final rig = _Rig(async, positions: [_position('tok', size: 10)]);
      addTearDown(rig.container.dispose);
      expect(rig.sockets, hasLength(1));
      expect(rig.sockets.single.tokens, ['tok']);
      final before = rig.total;
      expect(before, closeTo(105, 1e-9)); // $100 + 10 × 0.50
      // Past the second the account's first read took.
      async.elapse(const Duration(seconds: 2));

      rig.sockets.single.book('tok', 0.59, 0.61); // mid 0.60
      async.elapse(Duration.zero);
      expect(rig.total, closeTo(106, 1e-9));

      // A second tick inside the second waits for it.
      rig.sockets.single.book('tok', 0.69, 0.71); // mid 0.70
      async.elapse(const Duration(milliseconds: 500));
      expect(rig.total, closeTo(106, 1e-9));
      async.elapse(const Duration(milliseconds: 600));
      expect(rig.total, closeTo(107, 1e-9));

      // A fresh read re-bases the mark: nothing counted twice.
      rig.pm.set(_pm([_position('tok', size: 10, price: 0.7)]));
      async.elapse(Duration.zero);
      expect(rig.total, closeTo(107, 1e-9));
    });
  });

  test('closing the position or leaving the screen closes the socket', () {
    fakeAsync((async) {
      final rig = _Rig(async, positions: [_position('tok')]);
      addTearDown(rig.container.dispose);
      final first = rig.sockets.single;

      // Leaving the Investments tab.
      rig.container.read(activeShellTabProvider.notifier).state =
          ActiveNavTab.home;
      async.elapse(Duration.zero);
      expect(first.disposed, isTrue);

      // Back: a new socket for the same tokens and one read.
      rig.container.read(activeShellTabProvider.notifier).state =
          ActiveNavTab.usd;
      async.elapse(Duration.zero);
      expect(rig.sockets, hasLength(2));
      expect(rig.refreshes, [OneBalanceVenue.predictions]);

      // The app goes to the background.
      rig.container.read(appVisibleProvider.notifier).state = false;
      async.elapse(Duration.zero);
      expect(rig.sockets.last.disposed, isTrue);
      rig.container.read(appVisibleProvider.notifier).state = true;
      async.elapse(Duration.zero);
      expect(rig.sockets, hasLength(3));

      // The position closes: the socket goes and no timer is left.
      rig.pm.set(_pm(const []));
      async.elapse(Duration.zero);
      expect(rig.sockets.last.disposed, isTrue);
      final reads = rig.refreshes.length;
      async.elapse(const Duration(minutes: 5));
      expect(rig.refreshes.length, reads);
    });
  });

  test('open positions on screen reconcile slowly, fast after an event', () {
    fakeAsync((async) {
      final rig = _Rig(async, positions: [_position('tok')]);
      addTearDown(rig.container.dispose);
      async.elapse(const Duration(seconds: 44));
      expect(rig.refreshes, isEmpty);
      async.elapse(const Duration(seconds: 1));
      expect(rig.refreshes, [OneBalanceVenue.predictions]);

      // A sale lands: a read now, then every 10 s for a minute.
      rig.refreshes.clear();
      VenueCashReleased.emit(OneBalanceVenue.predictions, 'position_sold');
      async.elapse(Duration.zero);
      expect(rig.refreshes, hasLength(1));
      async.elapse(const Duration(seconds: 10));
      expect(rig.refreshes, hasLength(2));

      // Off screen: no reads at all.
      rig.container.read(activeShellTabProvider.notifier).state =
          ActiveNavTab.home;
      async.elapse(Duration.zero);
      final reads = rig.refreshes.length;
      async.elapse(const Duration(minutes: 5));
      expect(rig.refreshes.length, reads);
    });
  });
}
