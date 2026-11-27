// lib/providers/polymarket_user_channel_provider.dart
//
// Authenticated CLOB user channel — streams the active wallet's own
// order + trade lifecycle events. Drops new updates into a small
// in-memory ring of recent events and triggers a trading-provider
// refresh on every trade so positions follow the on-chain state.
//
// Uses our direct `PolymarketClobWebSocket` (no polybrainz). Auth
// headers are computed via `PolymarketBackendService.userChannelAuth
// Headers()` — the same HMAC bundle used by REST. They're re-issued
// on every WS reconnect because POLY_TIMESTAMP is short-lived.

import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/services/polymarket_clob_websocket.dart';

class UserChannelState {
  final List<PolymarketOrderWsMessage> recentOrders;
  final List<PolymarketTradeWsMessage> recentTrades;

  const UserChannelState({
    this.recentOrders = const [],
    this.recentTrades = const [],
  });
}

class UserChannelNotifier extends AutoDisposeNotifier<UserChannelState> {
  PolymarketClobWebSocket? _ws;
  StreamSubscription? _msgSub;
  final Set<String> _subscribedAssets = {};

  /// Tokens with a resting order, followed on top of the positions
  /// ([follow]): added to the open subscription, never a reconnect.
  final Set<String> _followed = {};
  bool _connecting = false;

  /// The socket; tests hand in a fake.
  @visibleForTesting
  static PolymarketClobWebSocket Function() socketFactory =
      PolymarketClobWebSocket.new;

  @override
  UserChannelState build() {
    ref.onDispose(_cleanup);
    return const UserChannelState();
  }

  void _cleanup() {
    _msgSub?.cancel();
    _ws?.dispose();
    _ws = null;
    _subscribedAssets.clear();
    _followed.clear();
  }

  /// Also follow [assetIds] (tokens with a resting order), so a resting
  /// buy on a token not held yet is heard when it fills. Added to the
  /// open subscription as one more `user` frame (the same frame
  /// [subscribe] sends), never a teardown: no update can fall in a gap.
  /// With no socket yet the tokens ride on the next connect, or start one
  /// when nothing else will. The open-orders list read on every refresh
  /// backs the socket up either way (polymarket_resting_fills_provider).
  void follow(List<String> assetIds) {
    final added = assetIds
        .where((a) =>
            a.isNotEmpty &&
            !_followed.contains(a) &&
            !_subscribedAssets.contains(a))
        .toSet();
    if (added.isEmpty) return;
    _followed.addAll(added);
    final ws = _ws;
    if (ws != null && _msgSub != null) {
      final backend =
          ref.read(polymarketTradingProvider.notifier).backendService;
      if (backend == null) return;
      ws.subscribeToUser(
        assetIds: added.toList(),
        authHeadersFactory: backend.userChannelAuthHeaders,
      );
      return;
    }
    // No socket and no positions to open one: these tokens open it.
    if (_msgSub == null && !_connecting && _subscribedAssets.isEmpty) {
      _connectAndSubscribe(_followed.toList());
    }
  }

  void subscribe(List<String> assetIds) {
    final newAssets = assetIds.where((a) => a.isNotEmpty).toSet();
    if (newAssets.isEmpty) return;

    if (_subscribedAssets.length == newAssets.length &&
        _subscribedAssets.containsAll(newAssets)) {
      return;
    }

    _msgSub?.cancel();
    _subscribedAssets
      ..clear()
      ..addAll(newAssets);
    _connectAndSubscribe(newAssets.toList());
  }

  Future<void> _connectAndSubscribe(List<String> assetIds) async {
    if (_connecting) return;
    _connecting = true;
    try {
      final tradingState = ref.read(polymarketTradingProvider).valueOrNull;
      if (tradingState == null || !tradingState.isAuthenticated) {
        _subscribedAssets.clear();
        return;
      }
      final backend =
          ref.read(polymarketTradingProvider.notifier).backendService;
      if (backend == null) {
        // Credentials not derived yet — bail silently. The caller
        // (polymarket_screen) re-fires this once trading state flips
        // to authenticated.
        return;
      }

      _ws ??= socketFactory();
      await _ws!.connect();

      _ws!.subscribeToUser(
        assetIds: {...assetIds, ..._followed}.toList(),
        // Factory closure so headers are re-computed on every
        // reconnect (timestamps are short-lived).
        authHeadersFactory: backend.userChannelAuthHeaders,
      );

      _msgSub = _ws!.messages.listen((msg) {
        if (msg is PolymarketOrderWsMessage) {
          final updated = [...state.recentOrders, msg];
          if (updated.length > 50) {
            updated.removeRange(0, updated.length - 50);
          }
          state = UserChannelState(
            recentOrders: updated,
            recentTrades: state.recentTrades,
          );
        } else if (msg is PolymarketTradeWsMessage) {
          final updated = [...state.recentTrades, msg];
          if (updated.length > 50) {
            updated.removeRange(0, updated.length - 50);
          }
          state = UserChannelState(
            recentOrders: state.recentOrders,
            recentTrades: updated,
          );

          // Refresh immediately on trade confirmation, then again
          // shortly after for position data to propagate through
          // the Data API.
          try {
            ref.read(polymarketTradingProvider.notifier).refresh();
          } catch (_) {}
          Future.delayed(const Duration(seconds: 2), () {
            try {
              ref.read(polymarketTradingProvider.notifier).refresh();
            } catch (_) {}
          });
        }
      }, onError: (Object err, StackTrace st) {
        // The user-channel socket errored mid-stream or gave up
        // reconnecting ("max reconnect attempts exceeded"). It surfaces
        // as an error on the broadcast `messages` stream; with no handler
        // here it escapes to the zone guard in main.dart and is recorded
        // as a FATAL crash. Tear the dead socket down and clear our
        // subscription state so the next `subscribe` call re-establishes
        // a fresh connection.
        _msgSub?.cancel();
        _msgSub = null;
        _ws?.dispose();
        _ws = null;
        _subscribedAssets.clear();
      });
    } catch (_) {
      _subscribedAssets.clear();
    } finally {
      _connecting = false;
    }
  }

  void unsubscribeAll() {
    _msgSub?.cancel();
    _subscribedAssets.clear();
  }
}

final userChannelProvider =
    NotifierProvider.autoDispose<UserChannelNotifier, UserChannelState>(
  UserChannelNotifier.new,
);
