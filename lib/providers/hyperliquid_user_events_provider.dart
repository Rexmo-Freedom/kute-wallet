// lib/providers/hyperliquid_user_events_provider.dart
//
// The user's own order lifecycle + fills over the Hyperliquid WS
// (orderUpdates + userFills channels — address-keyed, NO auth, unlike
// Polymarket's HMAC user channel). Once hyperliquidAddressProvider
// resolves, this notifier subscribes and:
//
//   * on live userFills (isSnapshot == false ONLY — the subscribe-time
//     backfill frame must never fire success paths):
//       - markSucceededByFill on matching placing tiles (cloid-matched
//         when available, coin otherwise),
//       - invalidates hyperliquidAccountProvider so the fresh position
//         lands within one fetch instead of a poll tick,
//       - pushes each fill onto the broadcast [fills] stream the order
//         slip listens to for the fill overlay;
//   * on orderUpdates: patches the trading notifier's openOrders in
//     place so cancels/fills reflect immediately (30 s poll remains the
//     reconciliation backstop).
//
// CRASH CONTRACT: the WS `messages` stream emits errors (terminal
// reconnect exhaustion included) — the listener attaches onError and
// rebuilds the socket on a capped backoff instead of letting the error
// escape to main.dart's zone guard as a fatal crash.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/placing_hyperliquid_order_provider.dart';
import 'package:kute/services/hyperliquid/hyperliquid_websocket.dart';

class HlUserEventsState {
  /// Newest-last ring of recent order lifecycle events, capped at 50. The
  /// open orders sheet reads it for orders the venue ended (with the
  /// reason), and the trade alerts for venue cancels and triggers.
  final List<HlOrderUpdate> recentOrderUpdates;

  /// The latest batch of LIVE fills (never the subscribe-time snapshot),
  /// numbered by [fillsSeq] so a listener can tell a new batch apart.
  final List<HlFill> lastLiveFills;
  final int fillsSeq;

  const HlUserEventsState({
    this.recentOrderUpdates = const [],
    this.lastLiveFills = const [],
    this.fillsSeq = 0,
  });
}

class HlUserEventsNotifier extends AutoDisposeNotifier<HlUserEventsState> {
  HyperliquidWebSocket? _ws;
  StreamSubscription<HlWsMessage>? _sub;
  Timer? _retryTimer;
  int _retryAttempts = 0;
  bool _connecting = false;
  String? _address;

  /// Live fills for overlay/UX listeners (the order slip's "filled!"
  /// transition). Broadcast; recreated per build so a wallet switch
  /// starts a clean stream.
  StreamController<HlFill>? _fillsCtrl;

  Stream<HlFill> get fills =>
      (_fillsCtrl ??= StreamController<HlFill>.broadcast()).stream;

  @override
  HlUserEventsState build() {
    ref.onDispose(_cleanup);
    // Rebuilds when the address future resolves (or the wallet
    // switches) — that's the trigger to (re)subscribe.
    final address = ref.watch(hyperliquidAddressProvider).valueOrNull;
    if (address != null) {
      _address = address;
      unawaited(_connect(address));
    }
    return const HlUserEventsState();
  }

  void _cleanup() {
    _sub?.cancel();
    _sub = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _ws?.dispose();
    _ws = null;
    _fillsCtrl?.close();
    _fillsCtrl = null;
    _address = null;
    _retryAttempts = 0;
  }

  Future<void> _connect(String address) async {
    if (_connecting || _ws != null) return;
    _connecting = true;
    try {
      final ws = HyperliquidWebSocket();
      _ws = ws;
      // Buffered until the socket opens; re-issued on every reconnect.
      ws.subscribeUser(address);
      // onError is MANDATORY — see the crash contract in the header.
      _sub = ws.messages.listen(
        _onMessage,
        onError: (Object e, StackTrace st) => _tearDownAndRetry(),
        onDone: _tearDownAndRetry,
      );
      await ws.connect();
      _retryAttempts = 0;
    } catch (_) {
      _tearDownAndRetry();
    } finally {
      _connecting = false;
    }
  }

  /// The socket reconnects internally for transient drops; landing here
  /// means it gave up — rebuild from scratch on a capped backoff.
  void _tearDownAndRetry() {
    _sub?.cancel();
    _sub = null;
    _ws?.dispose();
    _ws = null;
    final address = _address;
    if (address == null) return;
    if (_retryAttempts >= 5) return;
    _retryTimer?.cancel();
    final delay = Duration(seconds: 5 * (_retryAttempts + 1));
    _retryTimer = Timer(delay, () {
      _retryAttempts++;
      final addr = _address;
      if (addr != null) unawaited(_connect(addr));
    });
  }

  void _onMessage(HlWsMessage msg) {
    if (msg is HlUserFillsMessage) {
      // The subscribe-time snapshot is history, not news: reacting to it
      // would re-fire success overlays for every past trade.
      if (msg.isSnapshot || msg.fills.isEmpty) return;
      _handleLiveFills(msg.fills);
    } else if (msg is HlOrderUpdatesMessage) {
      _handleOrderUpdates(msg.updates);
    }
  }

  void _handleLiveFills(List<HlFill> fillsIn) {
    // 1. Clear matching placing tiles (cloid preferred, coin fallback).
    try {
      final placing = ref.read(placingHyperliquidOrderProvider.notifier);
      for (final f in fillsIn) {
        placing.markSucceededByFill(coin: f.coin, cloid: f.cloid);
      }
    } catch (_) {}

    // 2. Fresh account snapshot — the position/balance moved.
    ref.invalidate(hyperliquidAccountProvider);

    // 3. Patch the trading notifier's fills ring without a REST
    //    roundtrip — only when it's already alive; instantiating it
    //    from here would trigger a mnemonic derivation as a side
    //    effect of a WS frame.
    if (ref.exists(hyperliquidTradingProvider)) {
      try {
        ref.read(hyperliquidTradingProvider.notifier).recordFills(fillsIn);
      } catch (_) {}
    }

    // 4. Surface to state listeners (trade alerts) and overlay listeners.
    state = HlUserEventsState(
      recentOrderUpdates: state.recentOrderUpdates,
      lastLiveFills: List.unmodifiable(fillsIn),
      fillsSeq: state.fillsSeq + 1,
    );
    final ctrl = _fillsCtrl;
    if (ctrl != null && !ctrl.isClosed) {
      for (final f in fillsIn) {
        ctrl.add(f);
      }
    }
  }

  void _handleOrderUpdates(List<HlOrderUpdate> updates) {
    if (updates.isEmpty) return;

    // Ring buffer for surfaces that render recent lifecycle events.
    final ring = [...state.recentOrderUpdates, ...updates];
    if (ring.length > 50) ring.removeRange(0, ring.length - 50);
    state = HlUserEventsState(
      recentOrderUpdates: ring,
      lastLiveFills: state.lastLiveFills,
      fillsSeq: state.fillsSeq,
    );

    // Reconcile open orders in place — no poll wait for cancels/fills.
    if (ref.exists(hyperliquidTradingProvider)) {
      try {
        ref
            .read(hyperliquidTradingProvider.notifier)
            .applyOrderUpdates(updates);
      } catch (_) {}
    }
  }
}

final hyperliquidUserEventsProvider =
    NotifierProvider.autoDispose<HlUserEventsNotifier, HlUserEventsState>(
  HlUserEventsNotifier.new,
);
