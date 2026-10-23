// lib/providers/one_balance_live_provider.dart
//
// Keeps the Investments header's total moving with the venues, fast,
// driven by what the user actually holds (founder, 2026-10-13: "the
// Investments total must update with the Predictions total balance,
// super fast", then "dynamic, not a flat poll"). The rules are pure, in
// `lib/services/one_balance/live_marks.dart`; this binds them:
//
//   * EVENTS refresh a venue at once, whatever it holds: a funding move
//     into it starting or landing, a sweep or withdrawal out of it landing
//     (the Orchestra rows), a close, claim, sale or cancel
//     (`VenueCashReleased`), a sweep finishing (the sweeper state), and a
//     fill (the held set changing). Each opens the one-minute fast window.
//     Fills themselves are already read by the venues' own sockets
//     (the Polymarket user channel, Hyperliquid userFills).
//   * HELD POSITIONS are marked to market from live prices while the
//     Investments header is on screen with the app in the foreground:
//     Predictions over a market socket of its own subscribed to exactly
//     the held outcome tokens (the browse feed's socket follows the
//     screen's markets and is replaced as the list scrolls, so it cannot
//     be borrowed), Investing from the app's existing `allMids` feed with
//     the held coins added to its watch-set. At most one header update a
//     second. The socket closes and the feed is released when the last
//     position closes, the header leaves the screen or the app goes to
//     the background.
//   * A RECONCILIATION read only while positions are open and the header
//     is up: 45 s (a stream marks them), 10 s without a stream, 10 s for
//     a minute after an event. Nothing held → no periodic read at all.
//
// Nothing here moves money or adds chrome: the header reads
// [oneBalanceLiveProvider] through `oneBalanceProvider`.

import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/hyperliquid_market.dart' show HlPerpPosition;
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/active_shell_tab_provider.dart';
import 'package:kute/providers/auth_provider.dart' show appVisibleProvider;
import 'package:kute/providers/hyperliquid_account_provider.dart'
    show hyperliquidAccountProvider, hyperliquidHeldPositionsProvider;
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/venue_sweeper_provider.dart';
import 'package:kute/services/one_balance/live_marks.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/sweep_rules.dart'
    show venueDepositRowOf, venueWithdrawalRowOf;
import 'package:kute/services/one_balance/venue_cash_released.dart';
import 'package:kute/services/polymarket/shown_price.dart' show polyShownPrice;
import 'package:kute/services/polymarket_clob_websocket.dart';

export 'package:kute/services/one_balance/live_marks.dart'
    show OneBalanceLiveMarks;

/// The Investments header is on screen: the spending account's
/// Investments tab is the shell tab and the app is in the foreground.
final investmentsHeaderLiveProvider = Provider<bool>((ref) =>
    ref.watch(appVisibleProvider) &&
    ref.watch(activeShellTabProvider) == ActiveNavTab.usd &&
    ref.watch(settingsProvider
        .select((s) => s.activeWallet?.isSparkWallet ?? false)));

/// A market socket following exactly [tokens]. The CLOB honours only the
/// subscription that opens a connection, so a new token set is a new
/// socket.
abstract interface class HeldMarketSocket {
  Stream<PolymarketWsMessage> get messages;
  void dispose();
}

class _ClobHeldMarketSocket implements HeldMarketSocket {
  _ClobHeldMarketSocket(List<String> tokens) {
    _ws.subscribeToMarket(tokens);
    unawaited(_ws.connect().catchError((Object _) {}));
  }

  final PolymarketClobWebSocket _ws = PolymarketClobWebSocket();

  @override
  Stream<PolymarketWsMessage> get messages => _ws.messages;

  @override
  void dispose() => _ws.dispose();
}

/// Opens the held-token socket; tests pass a fake.
final heldMarketSocketFactoryProvider =
    Provider<HeldMarketSocket Function(List<String> tokens)>(
        (_) => _ClobHeldMarketSocket.new);

/// Reads [venue] again (cash and positions) through the venue's own
/// provider; tests count the calls.
final oneBalanceVenueRefreshProvider =
    Provider<Future<void> Function(OneBalanceVenue venue)>((ref) {
  return (venue) async {
    switch (venue) {
      case OneBalanceVenue.predictions:
        if (ref.exists(polymarketTradingProvider)) {
          await ref.read(polymarketTradingProvider.notifier).refresh();
        }
      case OneBalanceVenue.investing:
        if (ref.exists(hyperliquidTradingProvider)) {
          await ref.read(hyperliquidTradingProvider.notifier).refresh();
        } else if (ref.exists(hyperliquidAccountProvider)) {
          ref.invalidate(hyperliquidAccountProvider);
        }
    }
  };
});

/// The clock the cadence reads; tests pass their own.
final liveMarksClockProvider =
    Provider<DateTime Function()>((_) => DateTime.now);

/// What Predictions holds, as its venue last read it: the listed
/// positions and the fills the positions read has not listed yet (counted
/// at their fill price, so the socket marks them from the first tick).
@visibleForTesting
List<HeldOutcome> heldOutcomesOf(PolymarketTradingState? pm) => [
      if (pm != null)
        for (final p in pm.openPositions)
          if (!p.redeemable && p.size > 0 && p.asset.isNotEmpty)
            HeldOutcome(token: p.asset, size: p.size, readPrice: p.curPrice),
      if (pm != null)
        for (final f in pm.pendingFills)
          if (!f.indexed && f.shares > 0 && f.price > 0)
            HeldOutcome(token: f.tokenId, size: f.shares, readPrice: f.price),
    ];

bool _sameOutcomes(List<HeldOutcome> a, List<HeldOutcome> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].token != b[i].token ||
        a[i].size != b[i].size ||
        a[i].readPrice != b[i].readPrice) {
      return false;
    }
  }
  return true;
}

class OneBalanceLiveNotifier extends Notifier<OneBalanceLiveMarks> {
  bool _visible = false;
  List<HeldOutcome> _outcomes = const [];
  List<HeldPerp> _perps = const [];

  HeldMarketSocket? _socket;
  StreamSubscription<PolymarketWsMessage>? _socketSub;
  Set<String> _socketTokens = const {};
  final Map<String, ({double? bid, double? ask})> _books = {};
  final Map<String, double> _lastTrades = {};
  final Map<String, double> _outcomePrices = {};

  bool _hlHeld = false;
  HlLivePricesNotifier? _feed;
  ProviderSubscription<HlLivePriceState>? _midsSub;
  Map<String, double> _mids = const {};

  final Map<OneBalanceVenue, DateTime> _lastEventAt = {};
  final Map<OneBalanceVenue, Timer> _reconcile = {};
  final Map<OneBalanceVenue, Future<void>> _refreshing = {};

  /// Venues an event asked to read while their read was already running:
  /// that read may have started before the change, so one more follows it.
  final Set<OneBalanceVenue> _readAgain = {};

  Timer? _throttle;
  DateTime? _lastCommit;
  bool _disposed = false;

  DateTime _now() => ref.read(liveMarksClockProvider)();

  @override
  OneBalanceLiveMarks build() {
    _disposed = false;
    ref.onDispose(_teardown);
    // Only the spending account owns venues: a Ledger, watch-only or
    // Bitcoin-only wallet never starts a venue read from here.
    final spending = ref.watch(
        settingsProvider.select((s) => s.activeWallet?.isSparkWallet ?? false));
    if (!spending) return OneBalanceLiveMarks.zero;

    _visible = ref.read(investmentsHeaderLiveProvider);
    ref.listen<bool>(investmentsHeaderLiveProvider, (_, next) {
      final was = _visible;
      _visible = next;
      _apply();
      // Back on screen: re-read what is held (prices may have moved
      // while away). Nothing held, nothing read.
      if (next && !was) {
        if (_outcomes.isNotEmpty) _refresh(OneBalanceVenue.predictions);
        if (_perps.isNotEmpty) _refresh(OneBalanceVenue.investing);
      }
    });

    _outcomes = heldOutcomesOf(ref.read(polymarketTradingProvider).valueOrNull);
    ref.listen<AsyncValue<PolymarketTradingState>>(polymarketTradingProvider,
        (prev, next) {
      final held = heldOutcomesOf(next.valueOrNull);
      if (_sameOutcomes(held, _outcomes)) return;
      final tokensChanged =
          !_sameTokens(held.map((h) => h.token), _outcomes.map((h) => h.token));
      _outcomes = held;
      // A new or closed position is a fill: read fast for a minute. The
      // account's first read is not one.
      if (tokensChanged && prev?.valueOrNull != null) {
        _lastEventAt[OneBalanceVenue.predictions] = _now();
      }
      _apply();
      _commit(force: true);
    });

    _perps = _heldPerps(ref.read(hyperliquidHeldPositionsProvider));
    ref.listen(hyperliquidHeldPositionsProvider, (_, next) {
      final held = _heldPerps(next);
      final coinsChanged =
          !_sameTokens(held.map((h) => h.coin), _perps.map((h) => h.coin));
      _perps = held;
      if (coinsChanged) _lastEventAt[OneBalanceVenue.investing] = _now();
      _apply();
      _commit(force: true);
    });

    ref.listen<List<SwapOrder>>(swapOrdersProvider, _onRows);

    ref.listen<VenueSweeperState>(venueSweeperProvider, (prev, next) {
      for (final venue in prev?.sweeping ?? const <OneBalanceVenue>{}) {
        if (!next.sweeping.contains(venue)) _event(venue);
      }
    });

    final released = VenueCashReleased.stream.listen((e) => _event(e.$1));
    ref.onDispose(released.cancel);

    // After build returns: the first subscription and schedule.
    Future.microtask(() {
      if (!_disposed) _apply();
    });
    return OneBalanceLiveMarks.zero;
  }

  static List<HeldPerp> _heldPerps(List<HlPerpPosition> positions) => [
        for (final p in positions)
          if (p.szi != 0)
            HeldPerp(coin: p.coin, szi: p.szi, positionValue: p.positionValue),
      ];

  static bool _sameTokens(Iterable<String> a, Iterable<String> b) {
    final sa = a.toSet();
    final sb = b.toSet();
    return sa.length == sb.length && sa.containsAll(sb);
  }

  void _onRows(List<SwapOrder>? prev, List<SwapOrder> next) {
    if (prev == null) return; // the first read is history
    final before = {for (final r in prev) r.id: r};
    final wallet = ref.read(settingsProvider).activeWalletId;
    for (final row in next) {
      final was = before[row.id];
      final venue = venueDepositRowOf(row, walletId: wallet) ??
          venueWithdrawalRowOf(row, walletId: wallet);
      if (venue == null) continue;
      final started = was == null && row.isPending;
      final landed = row.isComplete && (was == null || !was.isComplete);
      if (started) {
        // An order being funded: no read yet (nothing has landed), but
        // the fast window opens for what follows.
        _lastEventAt[venue] = _now();
        _reschedule(venue);
      } else if (landed) {
        _event(venue);
      }
    }
  }

  /// Something changed at [venue]: read it now and fast for a minute.
  void _event(OneBalanceVenue venue) {
    if (_disposed) return;
    _lastEventAt[venue] = _now();
    // The venue's cash just moved: its read goes to the chain, not to the
    // balance Predictions keeps for 30 s between reads (which showed the
    // cash from before a deposit, a cash-out or a claim for up to that).
    if (venue == OneBalanceVenue.predictions) {
      try {
        if (ref.exists(polymarketTradingProvider)) {
          ref.read(polymarketTradingProvider.notifier).invalidateBalanceCache();
        }
      } catch (_) {}
    }
    _refresh(venue, again: true);
  }

  /// Reads [venue] now. A read already running is not doubled; with
  /// [again] (an event: the change may have come after that read began)
  /// one more read follows it.
  void _refresh(OneBalanceVenue venue, {bool again = false}) {
    if (_disposed) return;
    if (_refreshing.containsKey(venue)) {
      if (again) _readAgain.add(venue);
      return;
    }
    final run = ref.read(oneBalanceVenueRefreshProvider)(venue);
    _refreshing[venue] = run;
    run.catchError((Object _) {}).whenComplete(() {
      _refreshing.remove(venue);
      if (_disposed) return;
      if (_readAgain.remove(venue)) return _refresh(venue);
      _reschedule(venue);
    });
  }

  /// Brings the streams and the reconciliation timers in line with what
  /// is held and whether the header is up.
  void _apply() {
    if (_disposed) return;
    _applyPredictionsSocket();
    _applyInvestingFeed();
    for (final venue in OneBalanceVenue.values) {
      _reschedule(venue);
    }
  }

  void _applyPredictionsSocket() {
    final want =
        _visible ? _outcomes.map((h) => h.token).toSet() : const <String>{};
    if (_sameTokens(want, _socketTokens) &&
        (_socket != null) == want.isNotEmpty) {
      return;
    }
    _closeSocket();
    if (want.isEmpty) return;
    _socketTokens = want;
    final socket = ref.read(heldMarketSocketFactoryProvider)(want.toList());
    _socket = socket;
    _socketSub = socket.messages.listen(_onMarket, onError: (Object _) {});
  }

  void _closeSocket() {
    _socketSub?.cancel();
    _socketSub = null;
    _socket?.dispose();
    _socket = null;
    _socketTokens = const {};
    _books.clear();
    _lastTrades.clear();
    _outcomePrices.clear();
  }

  void _onMarket(PolymarketWsMessage msg) {
    final token = msg.assetId;
    if (token == null || !_socketTokens.contains(token)) return;
    if (msg is PolymarketBookMessage) {
      _books[token] = (bid: msg.bestBid, ask: msg.bestAsk);
    } else if (msg is PolymarketLastTradePriceMessage) {
      if (msg.price > 0 && msg.price < 1) _lastTrades[token] = msg.price;
    } else {
      return;
    }
    final book = _books[token];
    final price = polyShownPrice(
        bid: book?.bid, ask: book?.ask, lastTrade: _lastTrades[token]);
    if (price == null || _outcomePrices[token] == price) return;
    _outcomePrices[token] = price;
    _commit();
  }

  void _applyInvestingFeed() {
    final want = _visible && _perps.isNotEmpty;
    if (want == _hlHeld) {
      if (want) {
        ref
            .read(hyperliquidLivePricesProvider.notifier)
            .watchCoins([for (final p in _perps) p.coin]);
      }
      return;
    }
    if (want) {
      final feed = ref.read(hyperliquidLivePricesProvider.notifier);
      feed.watchCoins([for (final p in _perps) p.coin]);
      feed.acquire();
      _feed = feed;
      _hlHeld = true;
      _midsSub = ref.listen<HlLivePriceState>(hyperliquidLivePricesProvider,
          (_, next) {
        _mids = next.mids;
        _commit();
      }, fireImmediately: true);
    } else {
      _releaseFeed();
    }
  }

  void _releaseFeed() {
    _midsSub?.close();
    _midsSub = null;
    _mids = const {};
    if (_hlHeld) {
      _hlHeld = false;
      try {
        _feed?.release();
      } catch (_) {}
      _feed = null;
    }
  }

  void _reschedule(OneBalanceVenue venue) {
    _reconcile.remove(venue)?.cancel();
    if (_disposed) return;
    final interval = liveMarksReconcileInterval(
      holds: venue == OneBalanceVenue.predictions
          ? _outcomes.isNotEmpty
          : _perps.isNotEmpty,
      visible: _visible,
      streamed:
          venue == OneBalanceVenue.predictions ? _socket != null : _hlHeld,
      now: _now(),
      lastEventAt: _lastEventAt[venue],
    );
    if (interval == null) return;
    _reconcile[venue] = Timer(interval, () {
      _reconcile.remove(venue);
      _refresh(venue);
    });
  }

  /// Publishes the marks, at most once per [kLiveMarksThrottle] unless
  /// [force] (a fresh read re-bases them at once).
  void _commit({bool force = false}) {
    if (_disposed) return;
    final now = _now();
    final last = _lastCommit;
    if (!force && last != null && now.difference(last) < kLiveMarksThrottle) {
      _throttle ??= Timer(kLiveMarksThrottle - now.difference(last), () {
        _throttle = null;
        _commit(force: true);
      });
      return;
    }
    _throttle?.cancel();
    _throttle = null;
    _lastCommit = now;
    final next = OneBalanceLiveMarks(
      predictionsDeltaUsd:
          _socket == null ? 0 : predictionsMarkDelta(_outcomes, _outcomePrices),
      investingDeltaUsd: _hlHeld ? investingMarkDelta(_perps, _mids) : 0,
    );
    if (next != state) state = next;
  }

  void _teardown() {
    _disposed = true;
    _readAgain.clear();
    _throttle?.cancel();
    for (final t in _reconcile.values) {
      t.cancel();
    }
    _reconcile.clear();
    _closeSocket();
    _releaseFeed();
  }
}

/// The live marks the header adds to the venues' last reads.
final oneBalanceLiveProvider =
    NotifierProvider<OneBalanceLiveNotifier, OneBalanceLiveMarks>(
        OneBalanceLiveNotifier.new);
