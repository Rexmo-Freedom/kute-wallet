import 'dart:convert';

import 'package:hive_ce/hive.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show Activity;

/// Stores optimistic "I just sold/bought this" activity records so the home
/// Activity feed shows the user's most recent action immediately, instead
/// of waiting the seconds-to-minutes the Polymarket Data API takes to
/// reflect the on-chain settlement.
///
/// Each entry is keyed by [optimisticTradeKey]: a chain hash when the CLOB
/// answer carries one, else `clob-trade:<id>` / `clob-order:<id>`. When the
/// Data API returns the same hash, or a fill of the same shape, the
/// optimistic copy is dropped (handled in the read path).
class PolymarketOptimisticActivityService {
  static const _boxName = 'polymarket_optimistic_activity';
  static const Duration retentionWindow = Duration(minutes: 30);

  static Box<String> get _box => Hive.box<String>(_boxName);

  static void record(Activity activity) {
    if (activity.transactionHash.isEmpty) return;
    _box.put(
      activity.transactionHash.toLowerCase(),
      jsonEncode({
        'json': activity.toJson(),
        'recordedAt': DateTime.now().millisecondsSinceEpoch,
      }),
    );
  }

  /// All optimistic activities that haven't aged past [retentionWindow]
  /// and aren't already present in [confirmedHashes] (the API result).
  /// Side-effect: garbage-collects stale + confirmed entries.
  ///
  /// [confirmed] enables the FUZZY eviction the hash match can't do:
  /// rows are recorded under a CLOB trade or order id (the order
  /// response carries no chain hash), while the Data API reports the
  /// on-chain transaction hash — the two never match, so without this
  /// the user sees the bet twice for the full retention window. An
  /// optimistic row is considered confirmed when a server row matches
  /// its trade shape: same market + side, close in time, close in size.
  static List<Activity> snapshot({
    Set<String> confirmedHashes = const {},
    List<Activity> confirmed = const [],
  }) {
    final result = <Activity>[];
    final stale = <String>[];
    final now = DateTime.now().millisecondsSinceEpoch;
    final confirmedLower = confirmedHashes.map((h) => h.toLowerCase()).toSet();
    for (final key in _box.keys) {
      final raw = _box.get(key);
      if (raw == null) continue;
      try {
        final wrapper = jsonDecode(raw) as Map<String, dynamic>;
        final recordedAt = wrapper['recordedAt'] as int? ?? 0;
        if (now - recordedAt > retentionWindow.inMilliseconds) {
          stale.add(key as String);
          continue;
        }
        if (confirmedLower.contains((key as String).toLowerCase())) {
          stale.add(key);
          continue;
        }
        final activity = Activity.fromJson(
          (wrapper['json'] as Map<String, dynamic>),
        );
        if (confirmed.any((c) => _sameTrade(activity, c)) ||
            _sameMultiFillTrade(activity, confirmed)) {
          stale.add(key);
          continue;
        }
        result.add(activity);
      } catch (_) {
        stale.add(key as String);
      }
    }
    for (final k in stale) {
      _box.delete(k);
    }
    return result;
  }

  /// True when [server] is plausibly the settled form of optimistic [a]:
  /// same asset (or same market+side when the asset id is missing), a
  /// timestamp within 10 minutes, and a USDC size within 2% or 2 cents
  /// (price can move between order acceptance and settlement).
  static bool _sameTrade(Activity a, Activity server) {
    final sameAsset = a.asset != null &&
        a.asset!.isNotEmpty &&
        a.asset == server.asset;
    final sameMarketSide = a.conditionId.isNotEmpty &&
        a.conditionId == server.conditionId &&
        (a.side ?? '') == (server.side ?? '');
    if (!sameAsset && !sameMarketSide) return false;
    if (a.type != server.type) return false;
    if ((a.timestamp - server.timestamp).abs() > 600) return false;
    final sizeDelta = (a.usdcSize - server.usdcSize).abs();
    return sizeDelta <= 0.02 || sizeDelta <= a.usdcSize.abs() * 0.02;
  }

  /// One taker order matched against several makers settles in one
  /// transaction, and the Data API lists one row per fill: none of them is
  /// the order's full size, so [_sameTrade] matches none. Summed per
  /// transaction they are the order — the optimistic row is confirmed.
  static bool _sameMultiFillTrade(Activity a, List<Activity> confirmed) {
    final byTx = <String, double>{};
    for (final c in confirmed) {
      final hash = c.transactionHash.toLowerCase();
      if (hash.isEmpty) continue;
      if (c.type != a.type || (c.side ?? '') != (a.side ?? '')) continue;
      final sameAsset =
          a.asset != null && a.asset!.isNotEmpty && a.asset == c.asset;
      final sameMarket =
          a.conditionId.isNotEmpty && a.conditionId == c.conditionId;
      if (!sameAsset && !sameMarket) continue;
      if ((a.timestamp - c.timestamp).abs() > 600) continue;
      byTx[hash] = (byTx[hash] ?? 0) + c.usdcSize;
    }
    for (final total in byTx.values) {
      final sizeDelta = (a.usdcSize - total).abs();
      if (sizeDelta <= 0.02 || sizeDelta <= a.usdcSize.abs() * 0.02) {
        return true;
      }
    }
    return false;
  }

  /// Whether [hash] is an on-chain transaction hash (`0x` + 64 hex). An
  /// optimistic row recorded under a CLOB trade or order id
  /// ([optimisticTradeKey]) is not one, so nothing links it to an explorer.
  static bool isChainTxHash(String hash) =>
      RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(hash);

  /// The key an optimistic BUY or SELL row is recorded under, from the
  /// CLOB `POST /order` [response]: the first on-chain hash when the response
  /// still carries `transactionsHashes`; otherwise the first of
  /// `tradeIDs` (what the CLOB returns since 2026-07-24) as
  /// `clob-trade:<id>`, else the order id as `clob-order:<id>`. Trade and
  /// order ids are not transaction hashes, so they are kept recognisably
  /// apart ([isChainTxHash] is false for them). The row is evicted by the
  /// fuzzy trade match in [snapshot] once the Data API lists the fill.
  /// Null when the response names none of them.
  static String? optimisticTradeKey(Map<String, dynamic> response) {
    String? first(Object? list) {
      if (list is! List) return null;
      for (final v in list) {
        final s = v?.toString().trim() ?? '';
        if (s.isNotEmpty) return s;
      }
      return null;
    }

    final hash = first(response['transactionsHashes']);
    if (hash != null && isChainTxHash(hash)) return hash;
    final trade = first(response['tradeIDs']);
    if (trade != null) return 'clob-trade:$trade';
    final order =
        (response['orderID'] ?? response['order_id'] ?? response['orderId'])
                ?.toString()
                .trim() ??
            '';
    if (order.isNotEmpty) return 'clob-order:$order';
    return null;
  }

  static void clear(String transactionHash) {
    if (transactionHash.isEmpty) return;
    _box.delete(transactionHash.toLowerCase());
  }
}
