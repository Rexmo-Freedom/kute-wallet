// lib/providers/polymarket_resting_fills_provider.dart
//
// A resting limit order that fills (all of it or part) while the person
// is elsewhere, said once with the app's Sal toast (polymarket_screen.dart
// listens). Three ways a fill is seen, whichever comes first:
//
//   * the authenticated user channel's order update (its size matched
//     grew) for an order this account has resting;
//   * the open-orders list read on a refresh: an order's size matched
//     grew since the last list;
//   * an order that left the list: its record is read once (GET
//     /data/order/{id}) and a size matched past the last one seen is a
//     fill. An order this app cancelled is not read; one that ended with
//     nothing matched says nothing.
//
// Each order's matched size is remembered, so the three never say the
// same fill twice. The first list an account reads only primes it.
// Reads only; nothing here places, cancels or moves anything.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart' show Order;

import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/polymarket_user_channel_provider.dart';
import 'package:kute/services/polymarket_clob_websocket.dart'
    show PolymarketOrderWsMessage;

/// One fill of a resting order: [filledShares] matched now, of
/// [originalShares], [matchedShares] matched in all.
@immutable
class PolymarketRestingFill {
  const PolymarketRestingFill({
    required this.orderId,
    required this.tokenId,
    required this.isBuy,
    required this.price,
    required this.outcome,
    required this.filledShares,
    required this.matchedShares,
    required this.originalShares,
  });

  final String orderId;
  final String tokenId;
  final bool isBuy;
  final double price;
  final String outcome;
  final double filledShares;
  final double matchedShares;
  final double originalShares;

  /// Nothing of the order is left resting.
  bool get complete => matchedShares >= originalShares - 0.005;

  /// What is still resting at the order's price.
  double get remainingShares =>
      (originalShares - matchedShares).clamp(0.0, double.infinity);
}

double _num(Object? v) => double.tryParse('${v ?? ''}') ?? 0;

/// The memory behind [polymarketRestingFillsProvider]: what each resting
/// order had matched when last seen.
class PolymarketRestingFillTracker {
  final Map<String, Order> _orders = {};
  final Map<String, double> _matched = {};
  final Set<String> _cancelled = {};
  bool _primed = false;

  /// Forget everything (another account).
  void reset() {
    _orders.clear();
    _matched.clear();
    _cancelled.clear();
    _primed = false;
  }

  /// An order this app cancelled: its leaving the list is not a fill.
  void noteCancelled(Iterable<String> orderIds) => _cancelled.addAll(orderIds);

  PolymarketRestingFill _fill(Order o, double matched, double before) =>
      PolymarketRestingFill(
        orderId: o.id,
        tokenId: o.assetId,
        isBuy: o.side.toUpperCase() == 'BUY',
        price: _num(o.price),
        outcome: o.outcome,
        filledShares: matched - before,
        matchedShares: matched,
        originalShares: _num(o.originalSize),
      );

  /// A fresh open-orders list: the fills since the last one, and the ids
  /// of orders that left it ([gone]) to be read once.
  ({List<PolymarketRestingFill> fills, List<Order> gone}) onOrders(
      List<Order> orders) {
    final fills = <PolymarketRestingFill>[];
    final gone = <Order>[];
    final ids = {for (final o in orders) o.id};
    if (_primed) {
      for (final o in orders) {
        final before = _matched[o.id];
        final now = _num(o.sizeMatched);
        if (before != null && now > before + 1e-6) {
          fills.add(_fill(o, now, before));
        }
      }
      for (final o in _orders.values) {
        if (!ids.contains(o.id) && !_cancelled.contains(o.id)) gone.add(o);
      }
    }
    // Gone orders stay known until their record is read ([onGone]).
    final kept = {for (final o in gone) o.id: o};
    _orders
      ..clear()
      ..addAll(kept)
      ..addAll({for (final o in orders) o.id: o});
    for (final o in orders) {
      final now = _num(o.sizeMatched);
      if ((_matched[o.id] ?? -1) < now) _matched[o.id] = now;
    }
    _matched.removeWhere((id, _) => !_orders.containsKey(id));
    _cancelled.removeWhere((id) => !_orders.containsKey(id));
    _primed = true;
    return (fills: fills, gone: gone);
  }

  /// The venue's record of an order that left the list ([record]: its
  /// `size_matched`, null when it has none): a fill past what was seen.
  PolymarketRestingFill? onGone(Order order, Map<String, dynamic>? record) {
    final before = _matched[order.id];
    _orders.remove(order.id);
    _matched.remove(order.id);
    if (record == null || before == null) return null;
    final now = _num(record['size_matched']);
    if (now <= before + 1e-6) return null;
    return _fill(order, now, before);
  }

  /// A user-channel order update: a fill of an order resting here.
  PolymarketRestingFill? onOrderMessage(PolymarketOrderWsMessage m) {
    final o = _orders[m.orderId];
    if (o == null) return null;
    final before = _matched[m.orderId] ?? 0;
    if (m.sizeMatched <= before + 1e-6) return null;
    _matched[m.orderId] = m.sizeMatched;
    return _fill(o, m.sizeMatched, before);
  }
}

/// The last resting fill seen (null until one); each fill is a new value.
class PolymarketRestingFillsNotifier
    extends Notifier<PolymarketRestingFill?> {
  final PolymarketRestingFillTracker _tracker = PolymarketRestingFillTracker();
  String? _account;

  /// Reads one order's record; tests replace it.
  @visibleForTesting
  static Future<Map<String, dynamic>?> Function(Ref ref, String orderId)
      lookup = (ref, orderId) async {
    final backend = ref.read(polymarketTradingProvider.notifier).backendService;
    if (backend == null) return null;
    return backend.getOrderById(orderId);
  };

  @override
  PolymarketRestingFill? build() {
    ref.listen<AsyncValue<PolymarketTradingState>>(polymarketTradingProvider,
        (_, next) => _onTrading(next.valueOrNull),
        fireImmediately: true);
    ref.listen<UserChannelState>(userChannelProvider, (prev, next) {
      for (final m in next.recentOrders) {
        if (prev != null && prev.recentOrders.any((p) => identical(p, m))) {
          continue;
        }
        final fill = _tracker.onOrderMessage(m);
        if (fill != null) state = fill;
      }
    });
    return null;
  }

  /// Orders this app cancelled ([PolyOrderRow], Cancel all).
  void noteCancelled(Iterable<String> orderIds) =>
      _tracker.noteCancelled(orderIds);

  void _onTrading(PolymarketTradingState? s) {
    if (s == null || !s.isAuthenticated) return;
    final account = s.proxyWalletAddress?.toLowerCase();
    if (account != _account) {
      _account = account;
      _tracker.reset();
    }
    if (!s.openOrdersKnown) return;
    final seen = _tracker.onOrders(s.openOrders);
    for (final fill in seen.fills) {
      state = fill;
    }
    for (final order in seen.gone) {
      unawaited(_readGone(order, account));
    }
  }

  Future<void> _readGone(Order order, String? account) async {
    Map<String, dynamic>? record;
    try {
      record = await lookup(ref, order.id);
    } catch (_) {
      record = null;
    }
    if (account != _account) return;
    final fill = _tracker.onGone(order, record);
    if (fill != null) state = fill;
  }
}

final polymarketRestingFillsProvider =
    NotifierProvider<PolymarketRestingFillsNotifier, PolymarketRestingFill?>(
        PolymarketRestingFillsNotifier.new);

/// The tokens the user channel follows: those held and those with a
/// resting order, so a resting buy on a token not held yet is heard when
/// it fills.
List<String> polymarketUserChannelAssets(PolymarketTradingState state) => {
      for (final p in state.openPositions)
        if (p.asset.isNotEmpty) p.asset,
      for (final o in state.openOrders)
        if (o.assetId.isNotEmpty) o.assetId,
    }.toList();
