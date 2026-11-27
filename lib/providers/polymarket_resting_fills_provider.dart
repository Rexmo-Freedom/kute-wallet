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

/// Whether a venue order record says the order still rests (`LIVE`): a
/// list that did not carry it was read before it was placed, or is stale.
bool _recordRests(Map<String, dynamic> record) =>
    '${record['status'] ?? ''}'.toUpperCase() == 'LIVE' ||
    '${record['status'] ?? ''}'.toUpperCase() == 'ORDER_STATUS_LIVE';

/// The memory behind [polymarketRestingFillsProvider]: what each resting
/// order had matched when last seen.
///
/// An order missing from a list is read once ([onGone]; never twice at a
/// time, [_reading]); a record that says it still rests (`LIVE`) keeps it
/// tracked (the list was stale, or read before the order was placed) and
/// is read again no sooner than [recheckAfter]; only a record that says it
/// ended, or none at all, lets it go.
class PolymarketRestingFillTracker {
  PolymarketRestingFillTracker({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;
  final DateTime Function() _clock;

  final Map<String, Order> _orders = {};
  final Map<String, double> _matched = {};
  final Set<String> _cancelled = {};

  /// Records being read now: one read per order at a time.
  final Set<String> _reading = {};

  /// Orders whose record said they still rest though a list missed them:
  /// read again from this time on.
  final Map<String, DateTime> _recheckAt = {};
  static const recheckAfter = Duration(seconds: 20);

  /// Orders whose record could not be read, with the reads tried: read
  /// again with the next list, at most [maxGoneReads] times.
  final Map<String, int> _unreadTries = {};
  static const maxGoneReads = 3;

  /// Forget everything (another account).
  void reset() {
    _orders.clear();
    _matched.clear();
    _cancelled.clear();
    _reading.clear();
    _recheckAt.clear();
    _unreadTries.clear();
  }

  /// Orders known here that no list carried yet (placed here, or a
  /// record said they still rest): the notifier checks on them.
  bool get hasUnlisted => _orders.keys.any(
      (id) => _recheckAt.containsKey(id) || _unreadTries.containsKey(id));

  /// An order this app cancelled (the venue confirmed it): its leaving the
  /// list is not a fill.
  void noteCancelled(Iterable<String> orderIds) => _cancelled.addAll(orderIds);

  /// An order this app just placed that rests ([order]'s size matched: the
  /// shares its receipt already told the person): known at once, so a
  /// fill before the next list read is still said, and kept until a list
  /// carries it or its record says it ended.
  void register(Order order) {
    _orders[order.id] = order;
    final now = _num(order.sizeMatched);
    if ((_matched[order.id] ?? -1) < now) _matched[order.id] = now;
    // Not in any list yet: read when one misses it, from now.
    _recheckAt[order.id] = _clock();
  }

  /// [order]'s record could not be read: try again with the next list.
  void readLater(Order order) {
    _reading.remove(order.id);
    final tries = (_unreadTries[order.id] ?? 0) + 1;
    if (tries >= maxGoneReads) {
      _forget(order.id);
      return;
    }
    _unreadTries[order.id] = tries;
  }

  void _forget(String id) {
    _orders.remove(id);
    _matched.remove(id);
    _reading.remove(id);
    _recheckAt.remove(id);
    _unreadTries.remove(id);
  }

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

  /// A fresh open-orders list: the fills since the last one, and the
  /// orders missing from it to read now ([gone]).
  ({List<PolymarketRestingFill> fills, List<Order> gone}) onOrders(
      List<Order> orders) {
    final fills = <PolymarketRestingFill>[];
    final gone = <Order>[];
    final now = _clock();
    final ids = {for (final o in orders) o.id};
    for (final o in orders) {
      final before = _matched[o.id];
      final matched = _num(o.sizeMatched);
      // Before the first list only orders placed here are known.
      if (before != null && matched > before + 1e-6) {
        fills.add(_fill(o, matched, before));
      }
      // Listed: whatever kept it pending is settled.
      _recheckAt.remove(o.id);
      _unreadTries.remove(o.id);
    }
    // Orders known here (listed before, or placed here) missing from it:
    // read, one read at a time, a resting one no sooner than its recheck.
    final missing = <String, Order>{};
    for (final o in _orders.values) {
      if (ids.contains(o.id) || _cancelled.contains(o.id)) continue;
      missing[o.id] = o;
      if (_reading.contains(o.id)) continue;
      final at = _recheckAt[o.id];
      if (at != null && now.isBefore(at)) continue;
      _reading.add(o.id);
      gone.add(o);
    }
    _orders
      ..clear()
      ..addAll(missing)
      ..addAll({for (final o in orders) o.id: o});
    for (final o in orders) {
      final matched = _num(o.sizeMatched);
      if ((_matched[o.id] ?? -1) < matched) _matched[o.id] = matched;
    }
    _matched.removeWhere((id, _) => !_orders.containsKey(id));
    _cancelled.removeWhere((id) => !_orders.containsKey(id));
    _recheckAt.removeWhere((id, _) => !_orders.containsKey(id));
    _unreadTries.removeWhere((id, _) => !_orders.containsKey(id));
    return (fills: fills, gone: gone);
  }

  /// The venue's record of an order a list missed ([record]: null when the
  /// venue has none): a fill past what was seen. A record that says it
  /// still rests keeps it tracked, read again after [recheckAfter].
  PolymarketRestingFill? onGone(Order order, Map<String, dynamic>? record) {
    _reading.remove(order.id);
    _unreadTries.remove(order.id);
    final before = _matched[order.id];
    if (record == null || before == null) {
      _forget(order.id);
      return null;
    }
    final matched = _num(record['size_matched']);
    final fill = matched > before + 1e-6 ? _fill(order, matched, before) : null;
    if (fill != null) _matched[order.id] = matched;
    if (_recordRests(record) &&
        matched < _num(order.originalSize) - 0.005) {
      _recheckAt[order.id] = _clock().add(recheckAfter);
    } else {
      _forget(order.id);
    }
    return fill;
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
/// Lives as long as something listens (the Predictions screen, as the user
/// channel always did): it never keeps the channel open on its own.
class PolymarketRestingFillsNotifier
    extends AutoDisposeNotifier<PolymarketRestingFill?> {
  late final PolymarketRestingFillTracker _tracker =
      PolymarketRestingFillTracker(clock: clock);
  String? _account;
  Timer? _recheck;

  /// Reads one order's record; tests replace it.
  @visibleForTesting
  static Future<Map<String, dynamic>?> Function(Ref ref, String orderId)
      lookup = (ref, orderId) async {
    final backend = ref.read(polymarketTradingProvider.notifier).backendService;
    if (backend == null) return null;
    return backend.getOrderById(orderId);
  };

  /// The tracker's clock and how often orders no list carried yet are
  /// checked on; tests replace them.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;
  @visibleForTesting
  static Duration recheckEvery = const Duration(seconds: 30);

  @override
  PolymarketRestingFill? build() {
    ref.onDispose(() => _recheck?.cancel());
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

  /// Orders this app cancelled, once the venue confirmed it ([PolyOrderRow],
  /// Cancel all).
  void noteCancelled(Iterable<String> orderIds) =>
      _tracker.noteCancelled(orderIds);

  /// An order this app just placed that rests, on [account] (the deposit
  /// wallet it was placed from): known at once. Dropped when the account
  /// changed meanwhile (a wallet switch while it settled).
  void noteOrder(Order order, {required String? account}) {
    if (account == null || account.toLowerCase() != _account) return;
    _tracker.register(order);
    _armRecheck();
  }

  /// While some order no list carried yet is known, the last list is
  /// checked again on a timer: an account whose list does not change (the
  /// order filled whole before any read listed it) still gets its record
  /// read.
  void _armRecheck() {
    if (_recheck != null) return;
    _recheck = Timer.periodic(recheckEvery, (_) {
      if (!_tracker.hasUnlisted) {
        _recheck?.cancel();
        _recheck = null;
        return;
      }
      _onTrading(ref.read(polymarketTradingProvider).valueOrNull);
    });
  }

  void _onTrading(PolymarketTradingState? s) {
    if (s == null || !s.isAuthenticated) return;
    final account = s.proxyWalletAddress?.toLowerCase();
    if (account != _account) {
      _account = account;
      _tracker.reset();
    }
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
      // Not read: tried again with the next list, never dropped silently.
      if (account == _account) {
        _tracker.readLater(order);
        _armRecheck();
      }
      return;
    }
    if (account != _account) return;
    final fill = _tracker.onGone(order, record);
    if (fill != null) state = fill;
    if (_tracker.hasUnlisted) _armRecheck();
  }
}

final polymarketRestingFillsProvider = NotifierProvider.autoDispose<
    PolymarketRestingFillsNotifier,
    PolymarketRestingFill?>(PolymarketRestingFillsNotifier.new);


/// The tokens with a resting order: the user channel follows them on top
/// of the positions, so a resting buy on a token not held yet is heard
/// when it fills.
List<String> polymarketRestingOrderAssets(PolymarketTradingState state) => {
      for (final o in state.openOrders)
        if (o.assetId.isNotEmpty) o.assetId,
    }.toList();
