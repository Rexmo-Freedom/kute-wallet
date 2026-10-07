// lib/providers/hyperliquid_live_prices_provider.dart
//
// Live mid prices for the Trading tab, from Hyperliquid's `allMids` WS
// channel. This notifier owns THE app-wide allMids socket — one
// subscription streams the mid of EVERY market (~hundreds of coins,
// ticking multiple times a second), so unthrottled fan-out would rebuild
// every visible row on every frame. Two mandatory dampeners (see design
// risk notes):
//
//   1. Consumer-registered WATCH-SET: only coins registered via
//      [HlLivePricesNotifier.watchCoins] are parsed and copied into
//      state; everything else in the frame is skipped at the string map.
//   2. FRAME COALESCING: parsed updates accumulate in a pending buffer
//      and commit to state at most once per 250 ms.
//
// The notifier can also be PAUSED (Trading tab hidden) via
// [HlLivePricesNotifier.pause]/[resume] — socket and timers torn down,
// watch-set and last prices kept. Consumers outside the tab (pro chart
// screen, sheets on the root navigator) hold an [acquire]/[release]
// refcount that defers pause while they're visible. App backgrounding
// goes through [suspendForBackground]/[resumeFromBackground] instead,
// which OVERRIDE the refcount — nothing streams while backgrounded.
//
// Keys: consumers use DISPLAY coins ('BTC', 'TSLA'). allMids frames key
// spot pairs by wireCoin ('@142'); the notifier re-keys them via the
// spot mapping from hyperliquidWireToCoinMapProvider (listened, not
// watched — the markets provider self-invalidates every 30 s and a watch
// here would tear the socket down on every refresh).
//
// CRASH CONTRACT: HyperliquidWebSocket.messages EMITS ERRORS (mid-stream
// socket failures and the terminal "max reconnect attempts exceeded"
// StateError). Every listen here attaches onError; a missing handler
// escapes to the runZonedGuarded in main.dart as a FATAL crash.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/services/device_performance.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/active_shell_tab_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/services/hyperliquid/hyperliquid_websocket.dart';

/// Latest live mids keyed by DISPLAY coin, plus the previous value per
/// coin so rows can flash green/red on ticks.
class HlLivePriceState {
  final Map<String, double> mids;
  final Map<String, double> previousMids;

  /// False once the socket is down and out of internal retries — the
  /// mids above are the LAST KNOWN prices, not live ones. UI shows a
  /// delayed cue off this instead of silently painting stale numbers.
  final bool isLive;

  const HlLivePriceState({
    this.mids = const {},
    this.previousMids = const {},
    this.isLive = true,
  });

  /// Latest mid for [coin], or null before the first frame lands.
  double? mid(String coin) => mids[coin];

  /// 1 if the last tick moved up, -1 down, 0 unchanged/no data — drives
  /// the RollingNumberText flash color.
  int priceDirection(String coin) {
    final current = mids[coin];
    final prev = previousMids[coin];
    if (current == null || prev == null) return 0;
    if (current > prev) return 1;
    if (current < prev) return -1;
    return 0;
  }
}

class HlLivePricesNotifier extends AutoDisposeNotifier<HlLivePriceState> {
  HyperliquidWebSocket? _ws;
  StreamSubscription<HlWsMessage>? _sub;
  StreamSubscription<HlWsState>? _connSub;
  Timer? _frameTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _connecting = false;
  KeepAliveLink? _keepAlive;

  /// Tab wiring asked us to idle — see [pause]/[resume].
  bool _pauseRequested = false;

  /// App left the foreground — see [suspendForBackground]. Unlike a
  /// [pause], this overrides the acquire refcount: nothing may stream
  /// while backgrounded.
  bool _bgSuspended = false;

  /// Visible consumers outside the Trading tab — see [acquire]/[release].
  int _activityRefCount = 0;

  /// A pause only takes effect while nothing holds the refcount; a
  /// background suspension always does. Gates every path that could
  /// (re)open the socket — watch-set growth, reconnect backoff, the
  /// stale-socket check after an in-flight connect.
  bool get _effectivelyPaused =>
      _bgSuspended || (_pauseRequested && _activityRefCount == 0);

  /// Display coins some consumer currently cares about.
  final Set<String> _watchedCoins = {};

  /// display coin → wire coin for the watched set (identity for perps;
  /// spot resolved via the markets mapping). Rebuilt whenever the
  /// watch-set or the spot mapping changes.
  final Map<String, String> _displayToWire = {};

  /// wire coin → display coin (spot pairs only), from the markets
  /// provider. Perp keys are identity and never enter this map.
  Map<String, String> _wireToCoin = const {};

  /// display → wire aliases handed in by callers that KNOW their
  /// market's wire name ('QQQ' → '@142' / 'xyz:QQQ'). Authoritative
  /// over the spot-meta map: the browse catalog carries assets the
  /// direct spot meta never lists (HIP-3 dexes, backend-tagged spot).
  final Map<String, String> _explicitWire = {};

  /// HIP-3 dexes the CURRENT socket has an allMids subscription for.
  /// Cleared whenever the socket is torn down (subscriptions are
  /// re-registered on the fresh socket in _ensureConnected).
  final Set<String> _subscribedDexes = {};

  /// Coalescing buffer — committed to state at most every 250 ms.
  final Map<String, double> _pendingMids = {};
  final Map<String, double> _pendingPrev = {};
  bool _dirty = false;

  /// Set once [_cleanup] ran so a deferred suspension (see [release])
  /// never touches a provider that was torn down or rebuilt meanwhile.
  bool _disposed = false;

  @override
  HlLivePriceState build() {
    _disposed = false;
    ref.onDispose(_cleanup);

    // Born on a non-owning tab (e.g. an order sheet reached from Home's
    // global search before the Trading tab ever ran): start
    // pause-requested, exactly as if the shell policy had already run.
    // Otherwise the sheet's release() would suspend nothing (release
    // only re-suspends when a pause is pending) and the allMids
    // firehose would keep streaming with zero listeners. Creation ON
    // the Trading tab reads as not-paused; the shell policy re-stamps
    // this on every tab switch and foreground resume either way.
    _pauseRequested = ref.read(activeShellTabProvider) != ActiveNavTab.trading;

    // LISTEN (not watch): hyperliquidSpotMarketsProvider invalidates
    // itself every 30 s; watching would rebuild this notifier — tearing
    // down the socket — on every refresh.
    ref.listen(hyperliquidSpotMarketsProvider, (_, next) {
      final spots = next.valueOrNull;
      if (spots != null) _updateSpotMapping(spots);
    }, fireImmediately: true);

    return const HlLivePriceState();
  }

  void _cleanup() {
    _disposed = true;
    _sub?.cancel();
    _sub = null;
    _connSub?.cancel();
    _connSub = null;
    _frameTimer?.cancel();
    _frameTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _ws?.dispose();
    _ws = null;
    _watchedCoins.clear();
    _displayToWire.clear();
    _explicitWire.clear();
    _subscribedDexes.clear();
    _bboSubscribed.clear();
    _pendingMids.clear();
    _pendingPrev.clear();
    _dirty = false;
    _pauseRequested = false;
    _bgSuspended = false;
    _activityRefCount = 0;
    _keepAlive?.close();
    _keepAlive = null;
  }

  void _updateSpotMapping(List<HlMarket> spots) {
    _wireToCoin = {
      for (final m in spots)
        if (m.wireCoin != m.coin) m.wireCoin: m.coin,
    };
    _rebuildWireIndex();
  }

  /// Display coins that get the fast best-bid/ask feed on top of the
  /// slow allMids frame: the market whose sheet is open. allMids stays
  /// the source for everything else (list rows), and is ignored for a
  /// focused coin so a stale frame can never step on a fresh quote.
  final Set<String> _focused = {};
  final Set<String> _bboSubscribed = {};

  /// Follow [coin] on the fast feed. Idempotent; pair with [unfocus].
  void focus(String coin, {String? wire}) {
    if (coin.isEmpty) return;
    if (wire != null && wire.isNotEmpty && wire != coin) {
      _explicitWire[coin] = wire;
    }
    if (!_watchedCoins.contains(coin)) {
      watchCoins([coin], wire: wire == null ? null : {coin: wire});
    }
    if (!_focused.add(coin)) return;
    _rebuildWireIndex();
    _ensureBboSubs();
  }

  void unfocus(String coin) {
    if (!_focused.remove(coin)) return;
    final wire = _displayToWire[coin] ?? coin;
    if (_bboSubscribed.remove(wire)) _ws?.unsubscribeBbo(wire);
  }

  void _ensureBboSubs() {
    final ws = _ws;
    if (ws == null) return;
    for (final coin in _focused) {
      final wire = _displayToWire[coin] ?? coin;
      if (_bboSubscribed.add(wire)) ws.subscribeBbo(wire);
    }
  }

  void _rebuildWireIndex() {
    _displayToWire.clear();
    final coinToWire = <String, String>{
      for (final e in _wireToCoin.entries) e.value: e.key,
    };
    for (final coin in _watchedCoins) {
      _displayToWire[coin] = _explicitWire[coin] ?? coinToWire[coin] ?? coin;
    }
  }

  /// HIP-3 dex prefixes needed by the current watch-set ('xyz:QQQ' →
  /// 'xyz'). Spot '@N' and main-dex names need no extra subscription.
  Set<String> _neededDexes() => {
        for (final wire in _displayToWire.values)
          if (wire.contains(':')) wire.substring(0, wire.indexOf(':')),
      };

  /// Subscribe any newly-needed builder dexes on the live socket.
  void _ensureDexSubs() {
    final ws = _ws;
    if (ws == null) return;
    for (final dex in _neededDexes()) {
      if (_subscribedDexes.add(dex)) ws.subscribeAllMids(dex: dex);
    }
  }

  /// Register the display coins currently on screen. Additive — rows
  /// scrolling into view extend the set; call [unwatchAll] on screen
  /// dispose to release everything. Connects the socket lazily on the
  /// first call and keeps this notifier alive while anything is watched.
  /// [wire] carries display → wire aliases for coins whose allMids key
  /// differs from the display name (spot '@N', HIP-3 'dex:COIN') — pass
  /// it whenever the caller holds the HlMarket; identity pairs are
  /// ignored.
  void watchCoins(List<String> coins, {Map<String, String>? wire}) {
    if (wire != null) {
      for (final e in wire.entries) {
        if (e.key.isNotEmpty && e.value.isNotEmpty && e.key != e.value) {
          _explicitWire[e.key] = e.value;
        }
      }
    }
    final added = coins.where((c) => c.isNotEmpty).toSet()
      ..removeAll(_watchedCoins);
    if (added.isEmpty && wire == null) return;
    _watchedCoins.addAll(added);
    _rebuildWireIndex();
    _ensureDexSubs();
    _keepAlive ??= ref.keepAlive();
    // While paused only the watch-set grows; [resume]/[acquire] connect.
    if (!_effectivelyPaused) unawaited(_ensureConnected());
  }

  /// Drop the entire watch-set and tear the socket down (screen
  /// dispose). The last committed prices stay readable in state so a
  /// remount paints instantly while the socket re-establishes.
  void unwatchAll() {
    _sub?.cancel();
    _sub = null;
    _connSub?.cancel();
    _connSub = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _frameTimer?.cancel();
    _frameTimer = null;
    _ws?.dispose();
    _ws = null;
    _watchedCoins.clear();
    _displayToWire.clear();
    _explicitWire.clear();
    _subscribedDexes.clear();
    _bboSubscribed.clear();
    _pendingMids.clear();
    _pendingPrev.clear();
    _dirty = false;
    _reconnectAttempts = 0;
    _keepAlive?.close();
    _keepAlive = null;
  }

  /// Suspend the socket WITHOUT dropping the watch-set (tab hidden / app
  /// backgrounded). Idempotent. The last committed prices stay in state
  /// so remounts paint instantly; [resume] reconnects and re-subscribes.
  /// Deferred while any [acquire]d consumer is active — the request is
  /// remembered and applied when the refcount reaches zero.
  void pause() {
    _pauseRequested = true;
    if (_activityRefCount > 0) return;
    _suspendSocket();
  }

  /// Undo [pause] and reconnect if anything is watched. Idempotent.
  void resume() {
    if (!_pauseRequested) return;
    _pauseRequested = false;
    if (_watchedCoins.isNotEmpty) unawaited(_ensureConnected());
  }

  /// Hold the feed alive from a visible consumer OUTSIDE the Trading tab
  /// (pro chart screen, order/position sheets on the root navigator):
  /// while any acquire is outstanding, [pause] requests from
  /// tab/lifecycle wiring are deferred. Pair with exactly one [release].
  void acquire() {
    _activityRefCount++;
    // No reconnect while backgrounded — [resumeFromBackground] picks
    // this acquire up via the refcount when the app comes back.
    if (!_bgSuspended && _watchedCoins.isNotEmpty) {
      unawaited(_ensureConnected());
    }
  }

  /// Releases one [acquire]. When the count reaches zero with a pause
  /// pending, the socket suspends on the next microtask, never inline:
  /// callers release from dispose() while the widget tree is locked, and
  /// suspending commits a frame that writes state, which would mark
  /// defunct or locked elements for rebuild (the same teardown fault the
  /// Predictions feed had). Re-checked so an acquire() landing in the
  /// same frame keeps the feed up.
  void release() {
    if (_activityRefCount > 0) _activityRefCount--;
    if (!_effectivelyPaused) return;
    scheduleMicrotask(() {
      if (_disposed) return;
      if (_effectivelyPaused) _suspendSocket();
    });
  }

  /// App left the foreground: suspend the socket IMMEDIATELY, even while
  /// [acquire]d consumers are outstanding — a backgrounded app must not
  /// keep the ~400-coin allMids firehose alive just because an order
  /// slip or pro chart was open when the user switched away. Leaves the
  /// pause/acquire bookkeeping untouched so [resumeFromBackground] can
  /// restore exactly the state the foreground left behind. Idempotent.
  void suspendForBackground() {
    if (_bgSuspended) return;
    _bgSuspended = true;
    _suspendSocket();
  }

  /// Undo [suspendForBackground]. Reconnects only if the feed is still
  /// wanted — an [acquire]d consumer is outstanding OR no pause is
  /// pending (the Trading tab is the active one) — and something is
  /// watched. Runs AFTER the shell policy re-stamped pause/resume on
  /// foreground resume, so an acquired sheet gets its prices back even
  /// when its owning tab is not the active one. Idempotent.
  void resumeFromBackground() {
    if (!_bgSuspended) return;
    _bgSuspended = false;
    if ((_activityRefCount > 0 || !_pauseRequested) &&
        _watchedCoins.isNotEmpty) {
      unawaited(_ensureConnected());
    }
  }

  /// Socket + timer teardown shared by [pause], [release] and
  /// [suspendForBackground] — keeps
  /// watch-set, wire index, committed prices and the keep-alive link.
  void _suspendSocket() {
    _sub?.cancel();
    _sub = null;
    _connSub?.cancel();
    _connSub = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _frameTimer?.cancel();
    _frameTimer = null;
    // Flush sub-frame ticks so the frozen price is the last received.
    _commitFrame();
    _ws?.dispose();
    _ws = null;
    _subscribedDexes.clear();
    _bboSubscribed.clear();
    _reconnectAttempts = 0;
  }

  Future<void> _ensureConnected() async {
    if (_connecting || _ws != null) return;
    _connecting = true;
    try {
      final ws = HyperliquidWebSocket();
      _ws = ws;
      // Registered before connect() — the socket buffers subscriptions
      // and re-issues them on every (re)connect.
      ws.subscribeAllMids();
      _subscribedDexes.clear();
      _bboSubscribed.clear();
      for (final dex in _neededDexes()) {
        _subscribedDexes.add(dex);
        ws.subscribeAllMids(dex: dex);
      }
      _bboSubscribed.clear();
      _ensureBboSubs();
      // onError is MANDATORY — see the crash contract in the header.
      _sub = ws.messages.listen(
        _onMessage,
        onError: (Object e, StackTrace st) => _tearDownAndReconnect(),
        onDone: _tearDownAndReconnect,
      );
      _connSub?.cancel();
      _connSub = ws.connectionState.listen((s) {
        if (s == HlWsState.connected) _setLive(true);
        if (s == HlWsState.disconnected) _setLive(false);
      });
      await ws.connect();
      if (_ws != ws) {
        // pause()/unwatchAll()/suspendForBackground() landed during the
        // handshake — drop this socket. A fast pause→resume flip can
        // swallow the resume's connect (it saw _connecting); the
        // delayed retry rebuilds it (gated off while backgrounded via
        // _effectivelyPaused).
        ws.dispose();
        if (!_effectivelyPaused && _watchedCoins.isNotEmpty) {
          _tearDownAndReconnect();
        }
        return;
      }
      _reconnectAttempts = 0;
    } catch (_) {
      _tearDownAndReconnect();
    } finally {
      _connecting = false;
    }
  }

  /// Full teardown + delayed fresh-socket retry, capped at 5 attempts.
  /// The socket reconnects internally for transient drops; landing here
  /// means it errored terminally (gave up) — so we rebuild from scratch.
  void _tearDownAndReconnect() {
    _sub?.cancel();
    _sub = null;
    _connSub?.cancel();
    _connSub = null;
    _ws?.dispose();
    _ws = null;
    _subscribedDexes.clear();
    _bboSubscribed.clear();
    if (_watchedCoins.isEmpty || _effectivelyPaused) return;
    if (_reconnectAttempts >= 5) {
      // Terminal give-up: mark the feed stale so the UI can say so
      // instead of painting the last mid forever with no signal.
      _setLive(false);
      return;
    }
    _reconnectTimer?.cancel();
    final delay = Duration(seconds: 3 * (_reconnectAttempts + 1));
    _reconnectTimer = Timer(delay, () {
      if (_watchedCoins.isEmpty || _effectivelyPaused) return;
      _reconnectAttempts++;
      unawaited(_ensureConnected());
    });
  }

  void _onMessage(HlWsMessage msg) {
    if (msg is HlBboMessage) {
      _onBbo(msg);
      return;
    }
    if (msg is! HlAllMidsMessage) return;
    if (_watchedCoins.isEmpty) return;

    var touched = false;
    // Only the watch-set is parsed — the raw frame is never copied and
    // stays untouched for every other coin (the point of the lazy
    // per-key lookup on the message).
    for (final entry in _displayToWire.entries) {
      var raw = msg.mid(entry.value);
      if (raw == null) {
        // Builder-dex frames may key by the bare coin name; fall back
        // to the suffix ONLY when no other watched coin claims it (a
        // watched main-dex 'BTC' must never absorb 'xyz:BTC' frames,
        // and vice versa).
        final wire = entry.value;
        final sep = wire.indexOf(':');
        if (sep > 0) {
          final bare = wire.substring(sep + 1);
          if (!_displayToWire.containsValue(bare)) raw = msg.mid(bare);
        }
      }
      if (raw == null) continue;
      final coin = entry.key;
      // The fast feed owns a focused coin's price.
      if (_focused.contains(coin)) continue;
      final px = double.tryParse(raw);
      if (px == null || px <= 0) continue;
      final prev = _pendingMids[coin] ?? state.mids[coin];
      if (prev == px) continue;
      if (prev != null) _pendingPrev[coin] = prev;
      _pendingMids[coin] = px;
      touched = true;
    }
    if (!touched) return;
    _dirty = true;

    // Coalesce to ≥250 ms frames — allMids ticks far faster than any
    // human can read and each state write rebuilds every watching row.
    _frameTimer ??= Timer(
        DevicePerformance.liveFrame(const Duration(milliseconds: 250)),
        _commitFrame);
  }

  void _onBbo(HlBboMessage msg) {
    final px = msg.mid;
    if (px == null || px <= 0) return;
    // Wire coin → every focused display coin that maps to it.
    for (final coin in _focused) {
      if ((_displayToWire[coin] ?? coin) != msg.coin) continue;
      final prev = _pendingMids[coin] ?? state.mids[coin];
      if (prev == px) continue;
      if (prev != null) _pendingPrev[coin] = prev;
      _pendingMids[coin] = px;
      _dirty = true;
    }
    if (!_dirty) return;
    // A focused market paints at ~8 frames a second: fast enough to read
    // as live, slow enough that the header and chart never strobe.
    _frameTimer ??= Timer(
        DevicePerformance.liveFrame(const Duration(milliseconds: 120)),
        _commitFrame);
  }

  void _commitFrame() {
    _frameTimer = null;
    if (!_dirty) return;
    _dirty = false;
    state = HlLivePriceState(
      mids: {...state.mids, ..._pendingMids},
      previousMids: {...state.previousMids, ..._pendingPrev},
      isLive: state.isLive,
    );
    _pendingMids.clear();
    _pendingPrev.clear();
  }

  /// Immediate (uncoalesced) liveness flip — a stale cue must not wait
  /// behind the 250 ms price frame timer.
  void _setLive(bool v) {
    if (state.isLive == v) return;
    state = HlLivePriceState(
      mids: state.mids,
      previousMids: state.previousMids,
      isLive: v,
    );
  }
}

final hyperliquidLivePricesProvider =
    NotifierProvider.autoDispose<HlLivePricesNotifier, HlLivePriceState>(
  HlLivePricesNotifier.new,
);

/// Ergonomic per-coin mid selector — rebuilds only when THIS coin's mid
/// changes, not on every committed frame.
final hyperliquidLiveMidProvider =
    Provider.autoDispose.family<double?, String>((ref, coin) {
  return ref.watch(hyperliquidLivePricesProvider.select((s) => s.mids[coin]));
});

/// Live context (mark, previous-day price, 24h volume, funding, open
/// interest) of ONE market, keyed by wire coin, from the `activeAssetCtx`
/// channel. Watched by the open market detail sheet only: the browse
/// lists refresh builder-dex stats from cached metas (up to 5 minutes
/// old, to stay inside Hyperliquid's rate limit), so the sheet takes the
/// live numbers instead. One small socket per open sheet; closed with it.
/// Null until the first frame (the snapshot numbers show meanwhile).
final hyperliquidActiveAssetCtxProvider =
    StreamProvider.autoDispose.family<HlAssetCtx, String>((ref, wire) {
  final ws = HyperliquidWebSocket();
  final controller = StreamController<HlAssetCtx>();
  ws.subscribeActiveAssetCtx(wire);
  // onError is MANDATORY (crash contract in the header): a socket that
  // gives up just leaves the snapshot numbers on screen.
  final sub = ws.messages.listen(
    (msg) {
      if (msg is HlActiveAssetCtxMessage && msg.coin == wire) {
        controller.add(msg.ctx);
      }
    },
    onError: (Object _, StackTrace __) {},
  );
  unawaited(ws.connect().catchError((Object _) {}));
  ref.onDispose(() {
    sub.cancel();
    ws.dispose();
    controller.close();
  });
  return controller.stream;
});

/// [market] with its live context applied, when the open sheet has one.
HlMarket hlMarketWithLiveCtx(HlMarket market, HlAssetCtx? ctx) => ctx == null
    ? market
    : market.withLiveCtx(
        markPx: ctx.markPx,
        midPx: ctx.midPx,
        prevDayPx: ctx.prevDayPx,
        dayNtlVlm: ctx.dayNtlVlm,
        funding: ctx.funding,
        openInterest: ctx.openInterest,
      );
