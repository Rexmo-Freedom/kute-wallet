import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import 'package:kute/models/hyperliquid_market.dart';

/// The Investing markets starred on this device, newest first, as their
/// public market keys (nothing about the person or their positions). Kept
/// in their own Hive box so a cache wipe never drops them. Mirrors the
/// Predictions watchlist (`polyWatchlistProvider`).
final hlWatchlistProvider =
    NotifierProvider<HlWatchlistNotifier, List<String>>(
        HlWatchlistNotifier.new);

/// The watchlist key of [m]: its kind and wire coin ('perp:BTC',
/// 'perp:xyz:TSLA', 'spot:@142'), so a perp and the spot token of the
/// same symbol are starred apart.
String hlWatchlistKey(HlMarket m) => '${m.kind.name}:${m.wireCoin}';

/// The starred markets of [universe], in the order they were starred
/// (newest first). A starred market the venue no longer lists is left out.
List<HlMarket> hlWatchlistMarkets(
    List<String> watchlist, List<HlMarket> universe) {
  if (watchlist.isEmpty) return const [];
  final byKey = {for (final m in universe) hlWatchlistKey(m): m};
  return [
    for (final k in watchlist)
      if (byKey[k] != null) byKey[k]!
  ];
}

class HlWatchlistNotifier extends Notifier<List<String>> {
  static const boxName = 'hyperliquid_watchlist';
  static const _key = 'keys';

  /// The box of the Favourites this list replaces. Its stars (the same
  /// keys) are carried over the first time the watchlist is read.
  static const legacyBoxName = 'hyperliquid_favourites';

  static const maxEntries = 100;

  @override
  List<String> build() {
    unawaited(_load());
    return Hive.isBoxOpen(boxName)
        ? _read(Hive.box<String>(boxName))
        : const [];
  }

  Future<void> _load() async {
    try {
      final box = Hive.isBoxOpen(boxName)
          ? Hive.box<String>(boxName)
          : await Hive.openBox<String>(boxName);
      var stored = _read(box);
      // Stars made as Favourites, once: the old box is emptied after.
      if (await Hive.boxExists(legacyBoxName)) {
        final legacy = await Hive.openBox<String>(legacyBoxName);
        final old = _read(legacy);
        if (old.isNotEmpty) {
          stored = hlMergeWatchlists(stored, old);
          await box.put(_key, jsonEncode(stored));
          await legacy.delete(_key);
        }
      }
      final merged = hlMergeWatchlists(state, stored);
      if (merged.length != state.length) state = merged;
    } catch (_) {
      // The watchlist works for the session without its box.
    }
  }

  static List<String> _read(Box<String> box) {
    try {
      final raw = box.get(_key);
      if (raw == null) return const [];
      final decoded = jsonDecode(raw);
      return decoded is List ? [for (final k in decoded) '$k'] : const [];
    } catch (_) {
      return const [];
    }
  }

  bool contains(HlMarket m) => state.contains(hlWatchlistKey(m));

  /// Stars or unstars [m]; returns true when it is now on the list.
  bool toggle(HlMarket m) {
    final key = hlWatchlistKey(m);
    final added = !state.contains(key);
    final next = added
        ? [key, ...state].take(maxEntries).toList()
        : [
            for (final s in state)
              if (s != key) s
          ];
    state = next;
    unawaited(_save(next));
    return added;
  }

  Future<void> _save(List<String> keys) async {
    try {
      final box = Hive.isBoxOpen(boxName)
          ? Hive.box<String>(boxName)
          : await Hive.openBox<String>(boxName);
      await box.put(_key, jsonEncode(keys));
    } catch (_) {}
  }
}

/// [first] followed by the keys of [second] it does not already hold,
/// capped at [HlWatchlistNotifier.maxEntries].
List<String> hlMergeWatchlists(List<String> first, List<String> second) => [
      ...first,
      for (final k in second)
        if (!first.contains(k)) k
    ].take(HlWatchlistNotifier.maxEntries).toList();
