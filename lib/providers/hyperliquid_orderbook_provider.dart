// lib/providers/hyperliquid_orderbook_provider.dart
//
// L2 order book + recent-trades tape for ONE Hyperliquid market, family-
// keyed by WIRE coin (HlMarket.wireCoin — perp name or '@<index>' pair
// name; a spot DISPLAY symbol like 'TSLA' silently yields no frames).
// REST seed first so the
// depth ladder paints within a few hundred ms, then a dedicated WS
// subscription keeps it live; book frames coalesce at 250 ms, trades
// stream unthrottled (each match surfaces its own tape row). onDispose
// unsubscribes and tears the socket down.
//
// CRASH CONTRACT: the WS `messages` stream emits errors (terminal
// reconnect exhaustion included) — the listener below attaches onError
// and degrades to the static REST snapshot (LIVE dot off) instead of
// letting the error escape to the zone guard as a fatal crash.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/services/hyperliquid/hyperliquid_websocket.dart';

class HlOrderBookState {
  /// Best-first (exchange ordering) — bids[0]/asks[0] are top of book.
  final List<HlL2Level> bids;
  final List<HlL2Level> asks;

  /// Newest-first tape, capped at 30 rows.
  final List<HlTrade> recentTrades;
  final bool isConnected;

  const HlOrderBookState({
    this.bids = const [],
    this.asks = const [],
    this.recentTrades = const [],
    this.isConnected = false,
  });

  double? get bestBid => bids.isEmpty ? null : bids.first.px;
  double? get bestAsk => asks.isEmpty ? null : asks.first.px;

  double? get midPx {
    final b = bestBid, a = bestAsk;
    if (b == null || a == null || b <= 0 || a <= 0) return null;
    return (b + a) / 2;
  }

  /// Bid/ask spread as a percentage of the mid (0.05 == 0.05%).
  double? get spreadPct {
    final b = bestBid, a = bestAsk, m = midPx;
    if (b == null || a == null || m == null || m <= 0) return null;
    return (a - b) / m * 100;
  }

  HlOrderBookState copyWith({
    List<HlL2Level>? bids,
    List<HlL2Level>? asks,
    List<HlTrade>? recentTrades,
    bool? isConnected,
  }) {
    return HlOrderBookState(
      bids: bids ?? this.bids,
      asks: asks ?? this.asks,
      recentTrades: recentTrades ?? this.recentTrades,
      isConnected: isConnected ?? this.isConnected,
    );
  }
}

final hyperliquidOrderbookProvider = StreamProvider.autoDispose
    .family<HlOrderBookState, String /*wireCoin*/>((ref, wireCoin) async* {
  // 1. REST seed — best-effort; the WS is the source of truth and will
  //    deliver a full snapshot on subscribe anyway.
  var state = const HlOrderBookState();
  try {
    final book =
        await ref.read(hyperliquidTradingModelProvider).getL2Book(wireCoin);
    state = state.copyWith(bids: book.bids, asks: book.asks);
  } catch (_) {
    // Empty ladder until the WS lands.
  }
  yield state;

  // 2. Live updates over a dedicated socket for this market.
  final ws = HyperliquidWebSocket();
  ref.onDispose(() {
    ws.unsubscribeL2Book(wireCoin);
    ws.unsubscribeTrades(wireCoin);
    ws.dispose();
  });

  try {
    await ws.connect();
    state = state.copyWith(isConnected: true);
    yield state;
    ws.subscribeL2Book(wireCoin);
    ws.subscribeTrades(wireCoin);

    HlL2Book? pendingBook;
    Timer? throttle;
    Timer? retryTimer;
    ref.onDispose(() => retryTimer?.cancel());
    final controller = StreamController<HlOrderBookState>();

    final msgSub = ws.messages.listen((msg) {
      if (msg is HlTradesMessage) {
        // Tape rows stream unthrottled — each match should surface.
        final mine =
            msg.trades.where((t) => t.coin == wireCoin).toList().reversed;
        if (mine.isEmpty) return;
        final updated = <HlTrade>[...mine, ...state.recentTrades];
        if (updated.length > 30) updated.removeRange(30, updated.length);
        state = state.copyWith(recentTrades: updated);
        if (!controller.isClosed) controller.add(state);
        return;
      }
      if (msg is! HlL2BookMessage) return;
      if (msg.coin != wireCoin) return;
      pendingBook = msg.book;
      // Coalesce book snapshots to 250 ms — HL re-sends the full book
      // on every change and the depth ladder doesn't need more.
      throttle ??= Timer(const Duration(milliseconds: 250), () {
        throttle = null;
        final book = pendingBook;
        if (book == null) return;
        pendingBook = null;
        state = state.copyWith(
          bids: book.bids,
          asks: book.asks,
          isConnected: true,
        );
        if (!controller.isClosed) controller.add(state);
      });
    }, onError: (Object err, StackTrace st) {
      // Socket errored mid-stream or exhausted its reconnects. Without
      // this handler the broadcast-stream error escapes to main.dart's
      // zone guard as a FATAL crash. Degrade: keep the last snapshot on
      // screen with the LIVE indicator off — then SELF-HEAL: the socket
      // has burned its 10 internal attempts, so without this the book
      // stayed frozen until the sheet was reopened. A provider rebuild
      // gets a fresh socket + REST seed; `.when` keeps the previous
      // data painted through the refresh.
      if (!controller.isClosed && state.isConnected) {
        state = state.copyWith(isConnected: false);
        controller.add(state);
      }
      retryTimer ??= Timer(const Duration(seconds: 30), () {
        ref.invalidateSelf();
      });
    });

    final connSub = ws.connectionState.listen((s) {
      final connected = s == HlWsState.connected;
      if (state.isConnected != connected) {
        state = state.copyWith(isConnected: connected);
        if (!controller.isClosed) controller.add(state);
      }
    });

    ref.onDispose(() {
      msgSub.cancel();
      connSub.cancel();
      throttle?.cancel();
      controller.close();
    });

    yield* controller.stream;
  } catch (_) {
    // WebSocket failed — keep the static REST snapshot (no LIVE dot).
  }
});

/// Recent-trades tape only, derived from the orderbook stream (same
/// socket — no extra subscription). Family-keyed by WIRE coin.
final hyperliquidRecentTradesProvider =
    Provider.autoDispose.family<List<HlTrade>, String>((ref, wireCoin) {
  return ref.watch(hyperliquidOrderbookProvider(wireCoin)).valueOrNull
          ?.recentTrades ??
      const [];
});
