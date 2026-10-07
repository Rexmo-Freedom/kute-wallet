import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import 'package:kute/models/polymarket_model.dart';

/// The Predictions markets starred on this device, newest first, as their
/// public event slugs (nothing about the person or their positions). Kept
/// in their own Hive box so a cache wipe never drops them. Mirrors the
/// Investing favourites (`hlFavouritesProvider`).
final polyWatchlistProvider =
    NotifierProvider<PolyWatchlistNotifier, List<String>>(
        PolyWatchlistNotifier.new);

/// The watchlist key of [event]: its event slug. A drilled-in outcome and a
/// Breaking row carry their parent event's slug, so starring them stars the
/// event. Null when the event has none.
String? polyWatchlistKey(PolymarketEvent event) {
  final slug = event.slug.trim();
  return slug.isEmpty ? null : slug;
}

class PolyWatchlistNotifier extends Notifier<List<String>> {
  static const boxName = 'polymarket_watchlist';
  static const _key = 'slugs';

  /// A list read in one Gamma call; more than this is not offered.
  static const maxEntries = 100;

  @override
  List<String> build() {
    if (Hive.isBoxOpen(boxName)) return _read(Hive.box<String>(boxName));
    unawaited(Hive.openBox<String>(boxName).then((box) {
      final stored = _read(box);
      if (stored.isNotEmpty) {
        state = [
          ...state,
          for (final s in stored)
            if (!state.contains(s)) s
        ];
      }
    }).catchError((_) {}));
    return const [];
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

  bool contains(PolymarketEvent event) {
    final key = polyWatchlistKey(event);
    return key != null && state.contains(key);
  }

  /// Stars or unstars [event]; returns true when it is now on the list.
  bool toggle(PolymarketEvent event) {
    final key = polyWatchlistKey(event);
    if (key == null) return false;
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
