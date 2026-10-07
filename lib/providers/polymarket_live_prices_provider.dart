// lib/providers/polymarket_live_prices_provider.dart
//
// Streams real-time price updates from Polymarket's CLOB WebSocket.
// Subscribes visible market token IDs and pushes price changes
// as a Map<tokenId, latestPrice>.

import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/services/device_performance.dart';
import 'package:kute/providers/active_shell_tab_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/services/polymarket_clob_websocket.dart';
import 'package:kute/services/polymarket/book_seed.dart';
import 'package:kute/services/polymarket/shown_price.dart';

/// Holds the latest live prices keyed by token ID.
/// Also tracks the previous price for each token to enable flash animations.
class LivePriceState {
  final Map<String, double> prices;
  final Map<String, double> previousPrices;

  /// Wall-clock ms of the last accepted price write per token. Lets a
  /// consumer with its own fallback source (the 5-min banner's 10s
  /// Gamma poll) detect a silently stalled feed — socket open, `live`
  /// still true, but no frames for this token — and stop trusting a
  /// frozen price. Stamped by [copyWithPrice].
  final Map<String, int> updatedAtMs;

  /// True while the CLOB stream is actually flowing. While the feed is
  /// suspended (tab hidden / app backgrounded) the last prices are KEPT
  /// so the Predictions tab repaints instantly on return, but consumers
  /// with their own fresh data source (gamma prices on the Home feed,
  /// REST best-ask in the autofire pricer) must prefer that source over
  /// a frozen snapshot — gate on this flag.
  final bool live;

  /// Tokens whose book is wider than 10¢ and that have not traded since
  /// the feed began following them: Polymarket shows no chance for those
  /// ([polyShownPrice]), so a list writes "—". A price written for a
  /// token takes it out.
  final Set<String> unpriced;

  const LivePriceState({
    this.prices = const {},
    this.previousPrices = const {},
    this.updatedAtMs = const {},
    this.live = false,
    this.unpriced = const {},
  });

  /// This state with [tokens] marked [unpriced].
  LivePriceState copyWithUnpriced(Set<String> tokens) {
    if (tokens.isEmpty || unpriced.containsAll(tokens)) return this;
    return LivePriceState(
      prices: prices,
      previousPrices: previousPrices,
      updatedAtMs: updatedAtMs,
      live: live,
      unpriced: {...unpriced, ...tokens},
    );
  }

  LivePriceState copyWithPrice(String tokenId, double newPrice) {
    final prev = Map<String, double>.from(previousPrices);
    final current = prices[tokenId];
    if (current != null) prev[tokenId] = current;

    final updated = Map<String, double>.from(prices);
    updated[tokenId] = newPrice;

    final at = Map<String, int>.from(updatedAtMs);
    at[tokenId] = DateTime.now().millisecondsSinceEpoch;

    // A price write means data is flowing — the feed is live again.
    return LivePriceState(
      prices: updated,
      previousPrices: prev,
      updatedAtMs: at,
      live: true,
      unpriced: unpriced.contains(tokenId)
          ? ({...unpriced}..remove(tokenId))
          : unpriced,
    );
  }

  /// [copyWithPrice] for many tokens in one copy: a socket's opening dump
  /// carries a book for every subscribed token (311 on a big game), and
  /// copying the three maps once per token was quadratic.
  LivePriceState copyWithPrices(Map<String, double> updates) {
    if (updates.isEmpty) return this;
    final prev = Map<String, double>.from(previousPrices);
    final updated = Map<String, double>.from(prices);
    final at = Map<String, int>.from(updatedAtMs);
    final now = DateTime.now().millisecondsSinceEpoch;
    updates.forEach((tokenId, newPrice) {
      final current = prices[tokenId];
      if (current != null) prev[tokenId] = current;
      updated[tokenId] = newPrice;
      at[tokenId] = now;
    });
    return LivePriceState(
      prices: updated,
      previousPrices: prev,
      updatedAtMs: at,
      live: true,
      unpriced: unpriced.any(updates.containsKey)
          ? unpriced.where((t) => !updates.containsKey(t)).toSet()
          : unpriced,
    );
  }

  /// Returns 1 if price went up, -1 if down, 0 if unchanged or no data.
  int priceDirection(String tokenId) {
    final current = prices[tokenId];
    final prev = previousPrices[tokenId];
    if (current == null || prev == null) return 0;
    if (current > prev) return 1;
    if (current < prev) return -1;
    return 0;
  }
}

class LivePriceNotifier extends AutoDisposeNotifier<LivePriceState> {
  /// Subscription to the underlying ClobWebSocket [messages] stream. We
  /// listen to the merged firehose (`book`, `price_change`, `last_trade_price`)
  /// instead of a per-channel stream because the *displayed* odds on
  /// polymarket.com are derived from the order-book midpoint
  /// `(bestBid + bestAsk) / 2` — `price_change` alone yields whatever
  /// level moved last (commonly a deep level), which is why our odds
  /// drifted from polymarket.com's by 1-5¢. See the README at the top
  /// of [_connectAndSubscribe] for the source-of-truth priority.
  StreamSubscription? _subscription;
  Timer? _throttleTimer;
  /// Live filter set for the WS message listener. Extended by
  /// `addTokens` when new tokens come online without tearing the
  /// WS down — keeps the existing token stream uninterrupted while
  /// new tokens start ticking on the next server frame.
  Set<String>? _activeTokenSet;
  Timer? _reconnectTimer;
  LivePriceState _pendingState = const LivePriceState();

  /// Prices written since the last flush, applied to [_pendingState] in
  /// one copy when the throttle fires ([_flushStaged]).
  final Map<String, double> _staged = {};

  void _stage(String tokenId, double price) {
    _staged[tokenId] = price;
    _stagedUnpriced.remove(tokenId);
  }

  /// Tokens found since the last flush to have a book wider than 10¢ and
  /// no trade: no price to show ([LivePriceState.unpriced]).
  final Set<String> _stagedUnpriced = {};

  void _stageUnpriced(String tokenId) {
    _staged.remove(tokenId);
    _stagedUnpriced.add(tokenId);
  }

  LivePriceState _flushStaged() {
    if (_staged.isNotEmpty) {
      _pendingState = _pendingState.copyWithPrices(_staged);
      _staged.clear();
    }
    if (_stagedUnpriced.isNotEmpty) {
      _pendingState = _pendingState.copyWithUnpriced({..._stagedUnpriced});
      _stagedUnpriced.clear();
    }
    return _pendingState;
  }

  /// When each token was last asked of the REST seed (epoch ms), so a
  /// token whose book is empty is not asked again on every rotation.
  final Map<String, int> _seedAskedAt = {};
  static const int _kSeedRetryMs = 60 * 1000;
  final Set<String> _subscribedTokens = {};
  KeepAliveLink? _keepAlive;
  int _reconnectAttempts = 0;

  // Currently promoted socket — the one whose opening subscribe the
  // server honored. Replaced wholesale by [_connectAndSubscribe]'s
  // make-before-break rotation whenever the token set changes.
  PolymarketClobWebSocket? _ws;
  /// Replacement socket being built by an in-flight rotation. Nulled
  /// by pause/suspend so the post-connect swap knows to abandon it.
  PolymarketClobWebSocket? _pendingWs;
  Timer? _debounceTimer;
  Set<String>? _pendingTokens;

  /// Tokens added by non-card surfaces (open positions, bet slip,
  /// detail sheets) via the default [addTokens] path. Never dropped by
  /// card unregistration or LRU eviction — those surfaces have no
  /// dispose-side unregister and must keep streaming.
  final Set<String> _pinnedTokens = {};

  /// LRU refcounts for tokens registered by visible market cards
  /// ([registerCardTokens]). Insertion order == registration age:
  /// re-registering moves a token to the newest slot. Bounded by
  /// [_kMaxCardTokens]; overflow evicts the oldest-registered entry.
  final LinkedHashMap<String, int> _cardTokenRefs =
      LinkedHashMap<String, int>();

  /// Debounce for socket rotation ([_scheduleRotate]). The CLOB server
  /// honors ONLY the subscribe payload that opens a connection —
  /// verified against the live endpoint: a `market` subscribe frame
  /// sent later on the same socket is silently ignored, the added
  /// tokens never stream. So EVERY token-set change (a 5-min window
  /// rolling to new token ids, feed cards scrolling in/out, a removal)
  /// is applied by connecting a replacement socket with the full set
  /// and swapping it in. The debounce coalesces the rollover's
  /// unregister+register burst — and a scroll's card churn — into one
  /// rotation.
  Timer? _rotateTimer;

  /// Hard cap on the card-registered live set. Feed cards register on
  /// mount and unregister on dispose, so the working set tracks the
  /// viewport (sliver lists dispose far-offscreen children) — the cap
  /// is a safety net against pathological layouts, not the primary
  /// bound.
  static const int _kMaxCardTokens = 120;

  @override
  LivePriceState build() {
    ref.onDispose(_cleanup);
    _disposed = false;
    // Born on a non-owning tab (e.g. a bet slip reached from the Home
    // feed before the Predictions tab ever ran): start pause-requested,
    // exactly as if the shell policy had already run. Otherwise the
    // sheet's release() would suspend nothing (release only re-suspends
    // when a pause is pending) and the CLOB socket would keep streaming
    // with zero listeners. Creation ON the Predictions tab reads as
    // not-paused; the shell policy re-stamps this on every tab switch
    // and foreground resume either way.
    _pauseRequested =
        ref.read(activeShellTabProvider) != ActiveNavTab.predictions;
    return const LivePriceState();
  }

  void _cleanup() {
    _disposed = true;
    _subscription?.cancel();
    _subscription = null;
    _throttleTimer?.cancel();
    _reconnectTimer?.cancel();
    _debounceTimer?.cancel();
    _rotateTimer?.cancel();
    _pinnedTokens.clear();
    _cardTokenRefs.clear();
    _subscribedTokens.clear();
    _activeTokenSet = null;
    _lastMidByToken.clear();
    _lastTradeByToken.clear();
    _lastPriceChangeByToken.clear();
    _staged.clear();
    _stagedUnpriced.clear();
    _lastMidAt.clear();
    _lastTradeAt.clear();
    _lastPriceChangeAt.clear();
    _pauseRequested = false;
    _bgSuspended = false;
    _activityRefCount = 0;
    _keepAlive?.close();
    _keepAlive = null;
    _ws?.dispose();
    _ws = null;
    _pendingWs?.dispose();
    _pendingWs = null;
  }

  bool _connecting = false;
  bool _resolutionDebouncing = false;

  /// Set by [_cleanup] (provider disposed or rebuilt) so the deferred
  /// suspends scheduled by [release] and [removeTokens] never touch a
  /// torn-down notifier.
  bool _disposed = false;
  /// Tab wiring asked us to idle — see [pause]/[resume].
  bool _pauseRequested = false;

  /// App left the foreground — see [suspendForBackground]. Unlike a
  /// [pause], this overrides the acquire refcount: nothing may stream
  /// while backgrounded.
  bool _bgSuspended = false;

  /// Visible interactive Polymarket surfaces OUTSIDE the Predictions
  /// tab (bet slip from the Home feed, market detail sheet from global
  /// search, advisor invest cards) — see [acquire]/[release].
  int _activityRefCount = 0;

  /// True while the stream is effectively idled: a pause request only
  /// takes effect while nothing holds the refcount; a background
  /// suspension always does. Gates every path that could re-open the
  /// socket (debounced subscribes, reconnect backoff, in-flight
  /// connects) until [resume]/[acquire]/[resumeFromBackground] lifts it.
  bool get _paused =>
      _bgSuspended || (_pauseRequested && _activityRefCount == 0);

  /// Idempotent. Drops the WS + all timers while the Predictions
  /// surface is off-screen or the app is backgrounded, but KEEPS
  /// `_subscribedTokens` so [resume] can re-establish the exact same
  /// stream. Without this the CLOB socket, the 80ms throttle loop and
  /// the 5-attempt reconnect burn all keep running for a UI nobody is
  /// looking at. Called by the app-shell visibility wiring; safe to
  /// call when nothing is connected. Deferred while any [acquire]d
  /// consumer is active — the request is remembered and applied when
  /// the refcount reaches zero. No early `_paused` return: the resume
  /// lifecycle runs the shell policy while [suspendForBackground]'s flag
  /// is still up, and the pause request must be recorded even then.
  void pause() {
    _pauseRequested = true;
    if (_activityRefCount > 0) return;
    _suspendSocket();
  }

  /// Idempotent counterpart of [pause] — reconnects and re-subscribes
  /// the token set kept across the pause. No-op when not paused, when
  /// nothing was subscribed, or when an [acquire] already lifted the
  /// pause and the socket is live.
  void resume() {
    if (!_pauseRequested) return;
    _pauseRequested = false;
    if (_subscribedTokens.isEmpty) return;
    if (_ws != null) return;
    _connectAndSubscribe(_subscribedTokens.toList());
  }

  /// Hold the feed alive from an interactive Polymarket surface OUTSIDE
  /// the Predictions tab (bet slip from the Home feed, market detail
  /// sheet from global search, advisor invest cards): while any acquire
  /// is outstanding, [pause] requests from the shell-tab wiring are
  /// deferred. Acquiring while paused lifts the pause immediately — the
  /// socket opens and the REST seed fires for tokens recorded while
  /// paused. Pair with exactly one [release].
  void acquire() {
    _activityRefCount++;
    // Lifting a deferred pause (or landing after the reconnect backoff
    // gave up): re-establish the kept token set. `_connectAndSubscribe`
    // runs the REST seed for tokens that never got a mid.
    if (_ws == null && _subscribedTokens.isNotEmpty) {
      _connectAndSubscribe(_subscribedTokens.toList());
    }
  }

  /// Releases one [acquire]. When the count reaches zero with a pause
  /// pending, the stream suspends on the next microtask.
  ///
  /// Deferred on purpose. Every caller is a sheet's `dispose()`, which
  /// the framework runs while the widget tree is locked (finalizeTree).
  /// [_suspendSocket] writes `state`, and Riverpod notifies the still
  /// mounted consumers synchronously (the Home feed tiles select on
  /// `live`), so suspending synchronously from a dispose trips Flutter's
  /// "markNeedsBuild() called when widget tree was locked" assertion
  /// inside the listener. The condition is re-checked when the microtask
  /// runs, so an acquire() that lands in the same frame keeps the feed.
  void release() {
    if (_activityRefCount > 0) _activityRefCount--;
    if (!_paused) return;
    scheduleMicrotask(() {
      if (_disposed) return;
      if (_paused) _suspendSocket();
    });
  }

  /// App left the foreground: suspend the stream IMMEDIATELY, even while
  /// [acquire]d consumers are outstanding — a backgrounded app must not
  /// keep the CLOB firehose and its 80ms commit loop alive just because
  /// a bet slip was open when the user switched away. Leaves the
  /// pause/acquire bookkeeping untouched so [resumeFromBackground] can
  /// restore exactly the state the foreground left behind. Idempotent.
  void suspendForBackground() {
    if (_bgSuspended) return;
    _bgSuspended = true;
    _suspendSocket();
  }

  /// Undo [suspendForBackground]. Reconnects only if the stream is
  /// still wanted — an [acquire]d consumer is outstanding OR no pause is
  /// pending (Predictions is the active tab) — and tokens are
  /// subscribed. Runs AFTER the shell policy re-stamped pause/resume on
  /// foreground resume, so an acquired sheet gets its prices back even
  /// when its owning tab is not the active one. Idempotent.
  void resumeFromBackground() {
    if (!_bgSuspended) return;
    _bgSuspended = false;
    if ((_activityRefCount > 0 || !_pauseRequested) &&
        _subscribedTokens.isNotEmpty &&
        _ws == null) {
      _connectAndSubscribe(_subscribedTokens.toList());
    }
  }

  /// Socket + timer teardown shared by [pause], [release] and
  /// [suspendForBackground] — keeps
  /// `_subscribedTokens` so the connect path can re-establish the
  /// exact same stream.
  void _suspendSocket() {
    // Flush the subscribe debounce into the kept token set so tokens
    // requested just before pausing aren't lost across the gap. The
    // debounced path (`_doSubscribe`) REPLACES the subscribed set, so
    // the flush must replace too — `_pendingTokens` was seeded from
    // the set it's replacing, and adding instead would make resume()
    // subscribe old ∪ new, growing the set forever.
    _debounceTimer?.cancel();
    final pending = _pendingTokens;
    _pendingTokens = null;
    if (pending != null) {
      _subscribedTokens
        ..clear()
        ..addAll(pending);
    }
    _subscription?.cancel();
    _subscription = null;
    _throttleTimer?.cancel();
    _throttleTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _rotateTimer?.cancel();
    _rotateTimer = null;
    _reconnectAttempts = 0;
    _ws?.disconnect().catchError((_) {});
    _ws?.dispose();
    _ws = null;
    // An in-flight rotation's replacement socket dies with the feed —
    // its post-connect swap guard sees _pendingWs cleared and bails.
    _pendingWs?.dispose();
    _pendingWs = null;
    // Keep the frozen prices (instant repaint on return) but drop the
    // live flag so consumers with fresher sources stop preferring them.
    if (state.live) {
      state = LivePriceState(
        prices: state.prices,
        previousPrices: state.previousPrices,
        updatedAtMs: state.updatedAtMs,
        live: false,
        unpriced: state.unpriced,
      );
    }
    _pendingState = state;
    _staged.clear();
    _stagedUnpriced.clear();
  }

  /// Subscribe to price changes for the given token IDs.
  /// Debounced — rapid calls are coalesced into a single subscribe.
  void subscribeTokens(List<String> tokenIds) {
    final newTokens = tokenIds.where((t) => t.isNotEmpty).toSet();
    if (newTokens.isEmpty) return;

    // Skip if already subscribed to these exact tokens
    if (_subscribedTokens.length == newTokens.length &&
        _subscribedTokens.containsAll(newTokens)) {
      return;
    }

    // Accumulate tokens and debounce — build() may call this multiple times
    _pendingTokens = (_pendingTokens ?? {..._subscribedTokens})..addAll(newTokens);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 100), () {
      final tokens = _pendingTokens;
      _pendingTokens = null;
      if (tokens == null || tokens.isEmpty) return;
      _doSubscribe(tokens);
    });
  }

  void _doSubscribe(Set<String> newTokens) {
    // Skip if already subscribed to these exact tokens
    if (_subscribedTokens.length == newTokens.length &&
        _subscribedTokens.containsAll(newTokens)) {
      return;
    }

    // Keep the provider alive while we have active subscriptions
    _keepAlive?.close();
    _keepAlive = ref.keepAlive();

    // Paused (surface off-screen / app backgrounded): just record the
    // requested token set — `resume()` runs the connect path with it.
    if (_paused) {
      _subscribedTokens
        ..clear()
        ..addAll(newTokens);
      return;
    }

    _reconnectTimer?.cancel();
    _reconnectAttempts = 0;
    _subscribedTokens
      ..clear()
      ..addAll(newTokens);
    // Replace the listener filter NOW: frames the still-connected old
    // socket keeps emitting for dropped tokens must stop applying
    // immediately, while kept tokens stream through the swap gap.
    _activeTokenSet = newTokens.toSet();
    _pendingState = state;
    _staged.clear();
    _stagedUnpriced.clear();

    // NO teardown here — `_connectAndSubscribe` rotates
    // make-before-break: the old socket keeps streaming until the
    // replacement (subscribed to the new set) is live.
    _connectAndSubscribe(newTokens.toList());
  }

  /// Per-token snapshot of the most recent book midpoint and last-trade
  /// price. Used to decide which value to push as the canonical "live
  /// price" on each update — the book midpoint is preferred (matches
  /// the polymarket.com display), with `last_trade_price` as a faster
  /// fallback before the first book frame for a token lands.
  final Map<String, double> _lastMidByToken = {};
  final Map<String, double> _lastTradeByToken = {};
  /// Per-token snapshot of the most recent `price_change` event price.
  /// Low-liquidity 5-min Up/Down markets often go many seconds between
  /// `book` and `last_trade_price` frames — the only signal that ticks
  /// in those windows is `price_change`. Treated equally with book/trade
  /// when fresher (see [_canonicalFor]).
  final Map<String, double> _lastPriceChangeByToken = {};
  /// Per-token monotonic timestamps (ms since epoch) recording when each
  /// signal source last produced a valid price. Used by [_canonicalFor]
  /// so that a fresh `price_change` event wins over a stale `book` mid
  /// — without timestamps, the REST seed (or an early WS book frame)
  /// would pin `_lastMidByToken` and dominate forever even when the
  /// orderbook has since shifted. That was the freeze cause for the
  /// 5-min Up/Down banner: REST seeded a mid, `price_change` events
  /// fired (only signal a thin book emits), but `_canonicalFor`
  /// returned the stale REST mid because mid > trade > price_change
  /// was a strict priority instead of a freshness contest.
  final Map<String, int> _lastMidAt = {};
  final Map<String, int> _lastTradeAt = {};
  final Map<String, int> _lastPriceChangeAt = {};

  /// Picks the canonical live price for `tokenId` — the FRESHEST signal
  /// across `book` midpoint, `last_trade_price`, and `price_change`.
  /// Book midpoint is still preferred when timestamps tie (matches
  /// polymarket.com's displayed odds), but a more-recent `price_change`
  /// (the only signal thin 5-min books emit between rare book frames)
  /// will now propagate to the UI instead of being suppressed by a
  /// stale cached mid.
  double? _canonicalFor(String tokenId) {
    final mid = _lastMidByToken[tokenId];
    final last = _lastTradeByToken[tokenId];
    final pc = _lastPriceChangeByToken[tokenId];
    final midAt = _lastMidAt[tokenId] ?? -1;
    final midValid = mid != null && mid > 0 && mid < 1;
    final lastValid = last != null && last > 0 && last < 1;
    final pcValid = pc != null && pc > 0 && pc < 1;

    // Source-of-truth priority for the displayed price:
    //
    // Book mid (`_lastMidByToken`) is the only signal that's a TRUE
    // midpoint of best-bid + best-ask. `price_change` reports any
    // single-level mutation (a defensive ask placed at 0.999 on a
    // long-shot token whose true mid is 0.0015 — this is what made
    // Tunisia "lead" the World Cup card at 99%). `last_trade_price`
    // may have crossed deeply into the book.
    //
    // Rules:
    //   1. If we have a recent (<60s) book mid, USE IT — never let a
    //      single-level mutation override a fresh midpoint.
    //   2. If the book mid is stale (>60s) we accept price_change /
    //      last_trade as a tick BUT only if it's within ±25% of the
    //      last known book mid (clamp band). That way thin 5-min
    //      markets that only emit price_change still update, but a
    //      99% defensive ask on a 0.001 token can't flip the canonical.
    //   3. If we've NEVER seen a book mid for this token, fall back
    //      to the freshest of last_trade / price_change without
    //      banding (no reference to clamp against).
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    const freshMs = 60 * 1000;

    // Book mid is canonical when fresh. Single source of truth that
    // matches polymarket.com's displayed odds.
    if (midValid && (nowMs - midAt) < freshMs) {
      return mid;
    }

    // Last-trade is the second-best signal — trades clear at or
    // through the book and are tightly bounded by it.
    if (lastValid) {
      if (midValid) {
        // Clamp last-trade to ±25% of the last known mid. Stops a
        // through-the-book trade from anchoring the canonical at a
        // misleading level.
        final lo = mid * 0.75;
        final hi = mid * 1.25;
        if (last >= lo && last <= hi) return last;
        return mid;
      }
      return last;
    }

    // `price_change` events report individual level mutations at
    // ANY price — a defensive ask at 0.999 on a 0.005 token, a
    // deep bid at 0.001 on a 50¢ token, anything. They are NEVER
    // canonical on their own. They can only NUDGE an existing
    // mid (must be within ±25%); without an existing mid they're
    // ignored entirely and we fall back to the gamma snapshot
    // (`outcome.price`) at the consumer layer.
    if (pcValid && midValid) {
      final lo = mid * 0.75;
      final hi = mid * 1.25;
      if (pc >= lo && pc <= hi) return pc;
      return mid;
    }
    if (midValid) return mid;
    return null;
  }

  Future<void> _connectAndSubscribe(List<String> tokenIds) async {
    if (_connecting || _paused) return;
    _connecting = true;
    try {
      // ALWAYS a fresh socket, even when one is already connected. The
      // CLOB server honors ONLY the subscribe payload that opens a
      // connection — a `market` subscribe frame sent later on the same
      // socket is silently ignored (verified against the live endpoint:
      // a union re-subscribe never started the added tokens streaming;
      // this froze the 5-min Up/Down odds on every window rollover). So
      // every token-set change funnels here and is applied
      // make-before-break: build the replacement, connect it with the
      // full set, then swap — the previous socket keeps streaming until
      // the swap so visible odds never gap.
      final ws = PolymarketClobWebSocket();
      _pendingWs = ws;

      // Seed the active filter BEFORE awaiting `connect()` — an
      // `addTokens` landing during the handshake union-merges into it,
      // and the convergence check after the swap picks up the set
      // difference.
      _activeTokenSet ??= <String>{};
      _activeTokenSet!.addAll(tokenIds);

      // Buffered by the service and sent as the connection's opening
      // payload — the only subscribe the server honors.
      ws.subscribeToMarket(tokenIds);

      await ws.connect();

      // `pause()`/`suspendForBackground()` landed while `connect()` was
      // in flight (they null `_pendingWs`): this replacement is stale.
      // Bail quietly; the promoted `_ws` (if any) was never touched.
      // When not paused, re-schedule so the kept tokens still converge.
      if (_pendingWs != ws || _paused) {
        if (_pendingWs == ws) _pendingWs = null;
        ws.dispose();
        if (!_paused && _subscribedTokens.isNotEmpty) {
          _scheduleRotate();
        }
        return;
      }
      _pendingWs = null;

      // Swap: retire the old socket only now that the replacement is
      // live. Cancel the old messages subscription BEFORE disposing the
      // old socket — dispose closes its stream, and the onDone handler
      // below would read that as a socket death and tear the fresh
      // socket down.
      _subscription?.cancel();
      _subscription = null;
      if (_ws != null) {
        _ws!.disconnect().catchError((_) {});
        _ws!.dispose();
      }
      _ws = ws;
      _reconnectAttempts = 0;

      // Listen to the merged firehose so we can fuse `book` (midpoint),
      // `last_trade_price`, and `price_change` into one canonical price
      // per token — see [_onWsMessage].
      _subscription = ws.messages.listen(
        _onWsMessage,
        onError: (e) {
          _tearDownAndReconnect();
        },
        onDone: () {
          _tearDownAndReconnect();
        },
      );

      // Token set changed while the handshake was in flight (an
      // addTokens/removeTokens raced it): rotate again so the
      // server-side set converges on `_subscribedTokens`.
      if (_subscribedTokens.length != tokenIds.length ||
          !_subscribedTokens.containsAll(tokenIds)) {
        _scheduleRotate();
      }

      // The CLOB WS sends the current book on subscribe, but only as a
      // single 'book' frame — until that lands we have no canonical
      // price for these tokens. Kick a REST orderbook fetch in parallel
      // so the first paint of the bet slip has the correct mid within
      // a few hundred ms instead of waiting for the next book frame.
      // Per-token to keep the model API simple; failures are silent —
      // the WS will eventually deliver.
      // Tokens with a mid already (warm reconnect) are skipped.
      _seedFromRest(tokenIds);
    } catch (e) {
      _pendingWs?.dispose();
      _pendingWs = null;
      if (_ws != null) {
        // The rotation failed but the promoted socket is still
        // streaming its (stale) set — retry the rotation on a timer
        // instead of killing the live feed with a full teardown.
        _reconnectTimer?.cancel();
        _reconnectTimer = Timer(const Duration(seconds: 3), () {
          if (_paused || _subscribedTokens.isEmpty) return;
          _connectAndSubscribe(_subscribedTokens.toList());
        });
      } else {
        _tearDownAndReconnect();
      }
    } finally {
      _connecting = false;
    }
  }

  /// Fuses `book` (midpoint), `last_trade_price`, and `price_change`
  /// frames into one canonical price per token. The book midpoint is
  /// preferred (it matches polymarket.com's displayed odds);
  /// `last_trade_price` is used before the first book frame arrives;
  /// `price_change` is the third-tier fallback for low-liquidity 5-min
  /// markets where the server rarely emits book/trade frames but does
  /// emit price_change on every level mutation.
  void _onWsMessage(PolymarketWsMessage msg) {
    bool possibleResolution = false;
    bool anyChange = false;
    final tokenSet = _activeTokenSet ?? const <String>{};
    if (msg is PolymarketBookMessage) {
      final assetId = msg.assetId;
      if (assetId == null || !tokenSet.contains(assetId)) return;
      final bid = msg.bestBid;
      final ask = msg.bestAsk;
      if ((bid != null || ask != null) && polySpreadIsWide(bid, ask)) {
        // Wider than 10¢: Polymarket shows the last trade, not the
        // midpoint (an ask alone at 74¢ is no 37% chance). The mid is
        // dropped so the last trade is canonical; with none, the token
        // has no price to show.
        _lastMidByToken.remove(assetId);
        _lastMidAt.remove(assetId);
        final last = _lastTradeByToken[assetId];
        if (last != null && last > 0 && last < 1) {
          _stage(assetId, last);
        } else {
          _stageUnpriced(assetId);
        }
        anyChange = true;
      } else if (bid != null && ask != null && bid > 0 && ask > 0) {
        final mid = (bid + ask) / 2.0;
        if (mid > 0 && mid < 1) {
          _lastMidByToken[assetId] = mid;
          _lastMidAt[assetId] = DateTime.now().millisecondsSinceEpoch;
          final canonical = _canonicalFor(assetId);
          if (canonical != null) {
            _stage(assetId, canonical);
            anyChange = true;
            if (canonical >= 0.95 || canonical <= 0.05) {
              possibleResolution = true;
            }
          }
        }
      }
    } else if (msg is PolymarketLastTradePriceMessage) {
      final assetId = msg.assetId;
      if (assetId == null || !tokenSet.contains(assetId)) return;
      final p = msg.price;
      if (p > 0 && p < 1) {
        _lastTradeByToken[assetId] = p;
        _lastTradeAt[assetId] = DateTime.now().millisecondsSinceEpoch;
        final canonical = _canonicalFor(assetId);
        if (canonical != null) {
          _stage(assetId, canonical);
          anyChange = true;
          if (canonical >= 0.95 || canonical <= 0.05) {
            possibleResolution = true;
          }
        }
      }
    } else if (msg is PolymarketPriceChangeMessage) {
      // `price_change` reports each mutated book level's NEW price.
      // We can't derive the true midpoint from it without the
      // side+size of every level (the package strips `side` from
      // its `PriceChange` model), so book frames remain the
      // preferred source — but for low-liquidity 5-min markets
      // we may see ONLY price_change events for many seconds at
      // a time. Recording the latest reported price per token
      // gives the banner a live tick to render in that gap,
      // overridden the moment a real `book` frame arrives.
      for (final change in msg.priceChanges) {
        if (!tokenSet.contains(change.assetId)) continue;
        final p = change.price;
        if (p > 0 && p < 1) {
          _lastPriceChangeByToken[change.assetId] = p;
          _lastPriceChangeAt[change.assetId] =
              DateTime.now().millisecondsSinceEpoch;
          // `_canonicalFor` is now freshness-weighted — a recent
          // price_change overrides a stale book mid (the freeze
          // cause for thin 5-min markets). Book mid still wins on
          // ties so liquid markets keep matching polymarket.com.
          final canonical = _canonicalFor(change.assetId);
          if (canonical != null) {
            _stage(change.assetId, canonical);
            anyChange = true;
          }
        }
        if (change.price >= 0.95 || change.price <= 0.05) {
          possibleResolution = true;
        }
      }
    }
    if (anyChange) {
      // Throttle window keeps Riverpod state churn manageable
      // while preserving sub-second feel. 250ms was visibly
      // laggier than polymarket.com web; 80ms reads as
      // continuous to the eye while still coalescing the
      // dozens of book frames the CLOB emits per second.
      _throttleTimer ??= Timer(
          DevicePerformance.liveFrame(const Duration(milliseconds: 80)), () {
        _throttleTimer = null;
        state = _flushStaged();
      });
    }
    if (possibleResolution && !_resolutionDebouncing) {
      _resolutionDebouncing = true;
      Future.delayed(const Duration(seconds: 1), () {
        _resolutionDebouncing = false;
        try {
          // Public and Ledger views must not initialize a hot account.
          if (ref.exists(polymarketTradingProvider)) {
            ref.read(polymarketTradingProvider.notifier).refresh();
          }
        } catch (_) {}
      });
    }
  }

  /// Seeds `_lastMidByToken` from REST for those of [tokenIds] that have
  /// no mid yet, so the first canonical price is there before the socket's
  /// `book` frame. One batch request per hundred tokens
  /// ([fetchClobBookMids]); a token is asked at most once a minute, so an
  /// empty book is not read again on every rotation. Silent on failure —
  /// the WS is the source of truth.
  void _seedFromRest(Iterable<String> tokenIds) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final wanted = <String>[
      for (final t in tokenIds)
        if (!_lastMidByToken.containsKey(t) &&
            now - (_seedAskedAt[t] ?? -_kSeedRetryMs) >= _kSeedRetryMs)
          t,
    ];
    if (wanted.isEmpty) return;
    for (final t in wanted) {
      _seedAskedAt[t] = now;
    }
    if (_seedAskedAt.length > 4096) {
      _seedAskedAt.removeWhere((_, at) => now - at >= _kSeedRetryMs);
    }
    unawaited(_applySeed(wanted));
  }

  Future<void> _applySeed(List<String> tokens) async {
    final seeds = await fetchClobBookSeeds(tokens);
    final mids = seeds.mids;
    // Paused mid-flight — don't commit state or re-arm the throttle.
    if (_paused || (mids.isEmpty && seeds.wide.isEmpty)) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    var any = false;
    // A book wider than 10¢ shows its last trade, or nothing
    // ([polyShownPrice]) — unless the socket got there first.
    for (final tokenId in seeds.wide) {
      if (_lastMidByToken.containsKey(tokenId) ||
          _lastTradeByToken.containsKey(tokenId)) {
        continue;
      }
      final last = seeds.lastTrades[tokenId];
      if (last != null) {
        _lastTradeByToken[tokenId] = last;
        _lastTradeAt[tokenId] = now;
        _stage(tokenId, last);
      } else {
        _stageUnpriced(tokenId);
      }
      any = true;
    }
    mids.forEach((tokenId, mid) {
      // Don't stomp a fresher WS-derived mid that may have landed
      // while the REST call was in flight.
      if (_lastMidByToken.containsKey(tokenId)) return;
      _lastMidByToken[tokenId] = mid;
      _lastMidAt[tokenId] = now;
      _stage(tokenId, mid);
      any = true;
    });
    if (!any) return;
    _throttleTimer ??= Timer(
        DevicePerformance.liveFrame(const Duration(milliseconds: 250)), () {
      _throttleTimer = null;
      state = _flushStaged();
    });
  }

  /// Tear down current connection fully and schedule a reconnect with fresh ws.
  void _tearDownAndReconnect() {
    _subscription?.cancel();
    _subscription = null;
    _throttleTimer?.cancel();
    _throttleTimer = null;
    // Disconnect + null out so next attempt creates fresh ws
    _ws?.disconnect().catchError((_) {});
    _ws?.dispose();
    _ws = null;

    // The stream is demonstrably down: drop the `live` flag (keeping
    // the last prices for instant repaint) so consumers with their own
    // fresh source — the 5-min banner's 10s Gamma poll — stop
    // preferring a frozen snapshot while the backoff runs, or forever
    // after it gives up.
    if (state.live) {
      state = LivePriceState(
        prices: state.prices,
        previousPrices: state.previousPrices,
        updatedAtMs: state.updatedAtMs,
        live: false,
        unpriced: state.unpriced,
      );
    }
    _pendingState = state;
    _staged.clear();
    _stagedUnpriced.clear();

    if (_paused) return; // resume() will reconnect with the kept tokens
    if (_subscribedTokens.isEmpty) return;
    if (_reconnectAttempts >= 5) {
      return;
    }
    _reconnectTimer?.cancel();
    final delay = Duration(seconds: 3 * (_reconnectAttempts + 1));
    _reconnectTimer = Timer(delay, () {
      if (_subscribedTokens.isEmpty) return;
      _reconnectAttempts++;
      _connectAndSubscribe(_subscribedTokens.toList());
    });
  }

  /// Add tokens to the live subscription. The server only honors the
  /// subscribe payload that OPENS a connection (see [_rotateTimer]), so
  /// additions are applied by [_scheduleRotate]'s make-before-break
  /// socket swap; a REST seed covers the new tokens during the ~300ms
  /// debounce + handshake so their first odds paint immediately. An
  /// earlier version sent an additional `subscribeToMarket` frame on
  /// the live socket — the server silently ignored it, which is what
  /// froze the 5-min Up/Down banner's odds on every window rollover
  /// (new window = new token ids that never started streaming).
  ///
  /// [pin] (default true) marks the tokens as belonging to a non-card
  /// surface (positions, bet slip, detail sheet): pinned tokens are
  /// never dropped by [removeTokens] / card eviction. Card surfaces go
  /// through [registerCardTokens], which passes `pin: false`.
  void addTokens(List<String> tokenIds, {bool pin = true}) {
    final newTokens = tokenIds.where((t) => t.isNotEmpty).toSet();
    if (newTokens.isEmpty) return;
    if (pin) _pinnedTokens.addAll(newTokens);
    final actuallyNew =
        newTokens.where((t) => !_subscribedTokens.contains(t)).toSet();
    if (actuallyNew.isEmpty) return;

    // Paused: record the tokens for `resume()` and skip the socket
    // work entirely — there is no live WS to extend right now.
    if (_paused) {
      _subscribedTokens.addAll(actuallyNew);
      return;
    }

    // No live connection yet — fall through to the full subscribe
    // path which establishes the WS for the first time.
    if (_ws == null || _subscribedTokens.isEmpty) {
      final allTokens = {..._subscribedTokens, ...newTokens};
      subscribeTokens(allTokens.toList());
      return;
    }

    // Existing connection: extend the local set and the `tokenSet` the
    // message-listener filters by, then rotate to a replacement socket
    // subscribed to the union. Re-sending a subscribe frame on the
    // live socket does nothing — the server ignores every subscribe
    // after a connection's first — so the rotation is the only way the
    // new tokens actually start streaming. The current socket keeps
    // the existing tokens flowing until the swap.
    _subscribedTokens.addAll(actuallyNew);
    _activeTokenSet?.addAll(actuallyNew);
    _scheduleRotate();
    // Warm-path tokens skipped the initial REST seed that
    // `_connectAndSubscribe` does on cold start. Without it, a banner
    // mounted on a freshly-rolled 5-min market window had nothing to
    // render until the rotation lands and the first WS `book` frame
    // arrives — which on a low-liquidity market can be 30+ seconds.
    // Seed each new token here too so the banner has live odds within
    // ~250ms even before the WS catches up.
    _seedFromRest(actuallyNew);
  }

  /// Debounced make-before-break socket rotation — the ONLY way a
  /// token-set change reaches the server (see [_rotateTimer]). The
  /// debounce coalesces a 5-min rollover's unregister+register pair
  /// (and a scroll burst of card registrations) into one replacement
  /// connection; `_connectAndSubscribe` re-schedules itself when the
  /// set moves again mid-handshake, so the server set always converges
  /// on `_subscribedTokens`.
  void _scheduleRotate() {
    _rotateTimer?.cancel();
    _rotateTimer = Timer(const Duration(milliseconds: 300), () {
      _rotateTimer = null;
      if (_paused) return; // resume() reconnects with the kept set
      if (_subscribedTokens.isEmpty) return;
      _connectAndSubscribe(_subscribedTokens.toList());
    });
  }

  /// Register the outcome tokens of a VISIBLE market card. Card
  /// registrations are refcounted (two sections can surface the same
  /// event) and LRU-ordered; when the card-registered set exceeds
  /// [_kMaxCardTokens] the oldest-registered tokens are evicted from
  /// the live subscription. Pair each call with one
  /// [unregisterCardTokens] from the card's dispose.
  ///
  /// This is the growth fix for `addTokens`: the pinned path only ever
  /// accrues tokens, which is fine for the handful of positions/slips
  /// but not for an infinite feed where every card subscribes.
  void registerCardTokens(List<String> tokenIds) {
    final cleaned =
        tokenIds.where((t) => t.isNotEmpty).toList(growable: false);
    if (cleaned.isEmpty) return;
    for (final t in cleaned) {
      final prev = _cardTokenRefs.remove(t);
      // Re-insert so the token lands in the newest LRU slot.
      _cardTokenRefs[t] = (prev ?? 0) + 1;
    }
    final evicted = <String>[];
    while (_cardTokenRefs.length > _kMaxCardTokens) {
      final oldest = _cardTokenRefs.keys.first;
      _cardTokenRefs.remove(oldest);
      evicted.add(oldest);
    }
    addTokens(cleaned, pin: false);
    if (evicted.isNotEmpty) removeTokens(evicted);
  }

  /// Release one [registerCardTokens] registration. Tokens whose
  /// refcount reaches zero are dropped from the live subscription
  /// (unless another surface pinned them).
  void unregisterCardTokens(List<String> tokenIds) {
    final toRemove = <String>[];
    for (final t in tokenIds) {
      final n = _cardTokenRefs[t];
      if (n == null) continue;
      if (n <= 1) {
        _cardTokenRefs.remove(t);
        toRemove.add(t);
      } else {
        // In-place update keeps the LRU position (LinkedHashMap only
        // reorders on remove+insert).
        _cardTokenRefs[t] = n - 1;
      }
    }
    if (toRemove.isNotEmpty) removeTokens(toRemove);
  }

  /// Drop tokens from the live subscription. Pinned tokens and tokens
  /// still referenced by a registered card are silently skipped, so
  /// existing subscribers (positions, bet slip, detail sheet) are never
  /// broken by a card scrolling away. The server can't be told to stop
  /// mid-connection (it ignores unsubscribe-style frames the same way
  /// it ignores late subscribes), so a removal prunes the local filter
  /// immediately and rides the next [_scheduleRotate] — the rotated
  /// socket is born without the dropped tokens.
  void removeTokens(List<String> tokenIds) {
    final toDrop = tokenIds
        .where((t) =>
            t.isNotEmpty &&
            !_pinnedTokens.contains(t) &&
            !_cardTokenRefs.containsKey(t))
        .where((t) =>
            _subscribedTokens.contains(t) ||
            (_pendingTokens?.contains(t) ?? false))
        .toSet();
    if (toDrop.isEmpty) return;
    _subscribedTokens.removeAll(toDrop);
    _pendingTokens?.removeAll(toDrop);
    _activeTokenSet?.removeAll(toDrop);
    // Prune the per-token signal caches so a long browse session's
    // memory tracks the live set, not everything ever seen.
    for (final t in toDrop) {
      _lastMidByToken.remove(t);
      _lastTradeByToken.remove(t);
      _lastPriceChangeByToken.remove(t);
      _lastMidAt.remove(t);
      _lastTradeAt.remove(t);
      _lastPriceChangeAt.remove(t);
    }
    // Paused / suspended: the kept set is already pruned — resume()
    // will subscribe exactly the remainder.
    if (_paused || _ws == null) return;
    if (_subscribedTokens.isEmpty && (_pendingTokens?.isEmpty ?? true)) {
      // Nothing left to stream: drop the socket and release the
      // keepAlive so the provider can auto-dispose. Prices are kept
      // for instant repaint if a new subscriber shows up. Deferred for
      // the same reason as [release]: the last card scope unregisters
      // from its dispose(), and the state write inside _suspendSocket
      // must not run while the widget tree is locked. Re-checked at run
      // time so a token added in the same frame keeps the socket.
      scheduleMicrotask(() {
        if (_disposed || _paused || _ws == null) return;
        if (_subscribedTokens.isNotEmpty ||
            !(_pendingTokens?.isEmpty ?? true)) {
          return;
        }
        _suspendSocket();
        _keepAlive?.close();
        _keepAlive = null;
      });
      return;
    }
    // The local `_activeTokenSet` prune above already stops the dropped
    // tokens from applying; the rotation swaps in a socket that no
    // longer receives them (a 5-min rollover pairs this removal with an
    // addTokens for the new window, so the debounce folds both into a
    // single replacement connection).
    _scheduleRotate();
  }

  /// Unsubscribe all tokens.
  void unsubscribeAll() {
    _subscription?.cancel();
    _subscription = null;
    _reconnectTimer?.cancel();
    _rotateTimer?.cancel();
    _subscribedTokens.clear();
    _pinnedTokens.clear();
    _cardTokenRefs.clear();
    _activeTokenSet = null;
    _ws?.disconnect().catchError((_) {});
    _ws?.dispose();
    _ws = null;
    _pendingWs?.dispose();
    _pendingWs = null;
    _keepAlive?.close();
    _keepAlive = null;
  }
}

final livePriceProvider =
    NotifierProvider.autoDispose<LivePriceNotifier, LivePriceState>(
  LivePriceNotifier.new,
);
