// lib/providers/hl_price_lines_provider.dart
//
// The person's price lines (models/hl_price_line.dart). Local only: one
// Hive box ('hl_price_lines'), one JSON list per market, no backend.
//
// Nothing here opens a feed. HlLivePricesNotifier hands over each frame's
// fresh ticks ([applyLiveTicks]), so a line is only checked while its market
// is live for some other reason, and only against a price that just arrived,
// never against a remembered one.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import 'package:kute/models/hl_price_line.dart';
import 'package:kute/models/hyperliquid_market.dart';

class HlPriceLinesNotifier extends Notifier<List<HlPriceLine>> {
  static const kBoxName = 'hl_price_lines';

  late Future<void> _initialLoad;
  Future<void> _writes = Future.value();
  bool _disposed = false;

  @override
  List<HlPriceLine> build() {
    ref.onDispose(() => _disposed = true);
    _initialLoad = _load();
    return const [];
  }

  /// Tests: done when everything so far is on disk.
  @visibleForTesting
  Future<void> get debugWrites => _writes;

  Future<Box<String>> _box() => Hive.openBox<String>(kBoxName);

  Future<void> _load() async {
    try {
      final box = await _box();
      final loaded = <HlPriceLine>[];
      for (final raw in box.values) {
        loaded.addAll(_decode(raw));
      }
      if (_disposed || loaded.isEmpty) return;
      final ids = {for (final line in state) line.id};
      state = List.unmodifiable([
        ...loaded.where((line) => !ids.contains(line.id)),
        ...state,
      ]);
    } catch (_) {/* local-only: must not block the chart */}
  }

  /// One market's stored list. A corrupt one costs only that market.
  static List<HlPriceLine> _decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final e in decoded)
          if (e is Map) HlPriceLine.fromJson(Map<String, dynamic>.from(e)),
      ].whereType<HlPriceLine>().toList();
    } catch (_) {
      return const [];
    }
  }

  /// Sets a line on [market] at [level], its direction from [reference]
  /// (the price now). Returns why it was refused, or null when it was set.
  HlPriceLineRefusal? add({
    required HlMarket market,
    required String marketKey,
    required double level,
    required double? reference,
  }) {
    final refusal = hlPriceLineRefusal(
        level: level, reference: reference, count: state.length);
    if (refusal != null) return refusal;
    final now = DateTime.now();
    state = List.unmodifiable([
      ...state,
      HlPriceLine(
        id: now.microsecondsSinceEpoch.toString(),
        marketKey: marketKey,
        coin: market.coin,
        wireCoin: market.wireCoin,
        kind: market.kind,
        level: level,
        direction: level > reference!
            ? HlPriceLineDirection.above
            : HlPriceLineDirection.below,
        createdAtMs: now.millisecondsSinceEpoch,
      ),
    ]);
    _persist(marketKey);
    return null;
  }

  void remove(String id) {
    final gone = state.where((line) => line.id == id).toList();
    if (gone.isEmpty) return;
    state = List.unmodifiable(state.where((line) => line.id != id));
    _persist(gone.first.marketKey);
  }

  /// A frame of fresh [ticks] (display coin to price): marks every waiting
  /// line it reached, once. [wireOf] says which market a display coin's
  /// price came from.
  void applyLiveTicks(
    Map<String, double> ticks,
    String Function(String coin) wireOf,
  ) {
    if (_disposed || state.isEmpty) return;
    List<HlPriceLine>? next;
    final touched = <String>{};
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < state.length; i++) {
      final line = state[i];
      if (line.isReached) continue;
      final price = ticks[line.coin];
      if (price == null || wireOf(line.coin) != line.wireCoin) continue;
      if (!line.reachedBy(price)) continue;
      (next ??= List.of(state))[i] = line.reachedAt(now);
      touched.add(line.marketKey);
    }
    if (next == null) return;
    state = List.unmodifiable(next);
    touched.forEach(_persist);
  }

  void _persist(String marketKey) {
    final encoded = jsonEncode([
      for (final line in state)
        if (line.marketKey == marketKey) line.toJson(),
    ]);
    // After the load, so a line set during boot is not overwritten by it;
    // in order, so a slow write cannot undo a later one.
    _writes = _writes.then((_) => _initialLoad).then((_) async {
      try {
        final box = await _box();
        await box.put(marketKey, encoded);
      } catch (_) {/* local-only: must not interrupt the UI */}
    });
  }
}

final hlPriceLinesProvider =
    NotifierProvider<HlPriceLinesNotifier, List<HlPriceLine>>(
  HlPriceLinesNotifier.new,
);

/// One market's lines (hlChartDrawingMarketKey), waiting ones first, then
/// the newest first.
final hlPriceLinesForMarketProvider =
    Provider.family<List<HlPriceLine>, String>((ref, marketKey) {
  final lines = ref
      .watch(hlPriceLinesProvider)
      .where((line) => line.marketKey == marketKey)
      .toList()
    ..sort((a, b) {
      if (a.isReached != b.isReached) return a.isReached ? 1 : -1;
      return b.createdAtMs.compareTo(a.createdAtMs);
    });
  return List.unmodifiable(lines);
});
