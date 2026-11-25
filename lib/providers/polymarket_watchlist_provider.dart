import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import 'package:kute/models/polymarket_model.dart';
import 'package:kute/services/polymarket/event_trading_over.dart';

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

/// The starred slugs in [asked] that a successful read ([returned]) shows
/// are no longer on offer: their event's trading is over (closed, ended,
/// inactive, every market closed) or the read did not return it at all (a
/// settled event the feed leaves out, or a slug that is gone). The
/// Watchlist never lists those, so they must not count either.
Set<String> polyWatchlistOver(
    List<String> asked, List<PolymarketEvent> returned) {
  final bySlug = {for (final e in returned) e.slug: e};
  return {
    for (final s in asked)
      if (bySlug[s] == null || polyTradingOver(bySlug[s]!, inPlay: bySlug[s]!.isInPlay))
        s
  };
}

class PolyWatchlistNotifier extends Notifier<List<String>> {
  static const boxName = 'polymarket_watchlist';
  static const _key = 'slugs';

  /// A list read in one Gamma call; more than this is not offered.
  static const maxEntries = 100;

  /// The stored list's first read (done at once when the box is open).
  Future<void> _loaded = Future<void>.value();

  /// The saves, one after another in the order they were asked: a later
  /// toggle's list never lands before an earlier one's.
  Future<void> _saving = Future<void>.value();

  /// Completes once the stored list has been read into the state.
  @visibleForTesting
  Future<void> get loaded => _loaded;

  /// Completes once every toggle so far is on disk.
  @visibleForTesting
  Future<void> get saved => _saving;

  /// Reads the starred events (one Gamma call); tests replace it.
  @visibleForTesting
  static Future<List<PolymarketEvent>> Function(List<String> slugs) reader =
      (slugs) async => (await PolymarketModel.readGammaEventsPage(
            const {},
            multi: {'slug': slugs},
            limit: slugs.length,
          ))
              .events;

  /// When the list was last checked for markets that are over: at most
  /// once every [checkEvery], across the app's session.
  static DateTime? _checkedAt;
  static const checkEvery = Duration(minutes: 10);

  @visibleForTesting
  static void resetCheck() => _checkedAt = null;

  /// The check started when the stored list loaded, for tests.
  Future<void> _check = Future<void>.value();
  @visibleForTesting
  Future<void> get checked => _check;

  @override
  List<String> build() {
    if (Hive.isBoxOpen(boxName)) {
      final stored = _read(Hive.box<String>(boxName));
      if (stored.isNotEmpty) Future.microtask(_startCheck);
      return stored;
    }
    _loaded = Hive.openBox<String>(boxName).then((box) {
      final stored = _read(box);
      if (stored.isNotEmpty) {
        state = [
          ...state,
          for (final s in stored)
            if (!state.contains(s)) s
        ];
        _startCheck();
      }
    }).catchError((_) {});
    return const [];
  }

  /// Drops the stars on markets that are over, so the count shown next to
  /// "Watchlist" is the number of markets the Watchlist lists, before it
  /// is opened. A read that fails changes nothing.
  void _startCheck() {
    final now = DateTime.now();
    final last = _checkedAt;
    if (last != null && now.difference(last) < checkEvery) return;
    _checkedAt = now;
    final asked = List<String>.of(state);
    if (asked.isEmpty) return;
    _check = reader(asked)
        .then((events) => forgetOver(asked, events))
        .catchError((_) {});
  }

  /// After a successful read of [asked] that returned [returned]: removes
  /// the slugs whose markets are over ([polyWatchlistOver]). Stars added
  /// since the read began are kept.
  void forgetOver(List<String> asked, List<PolymarketEvent> returned) {
    final over = polyWatchlistOver(asked, returned);
    if (over.isEmpty) return;
    final next = [
      for (final s in state)
        if (!over.contains(s)) s
    ];
    if (next.length == state.length) return;
    state = next;
    _saving = _saving.then((_) => _save(next));
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
    _saving = _saving.then((_) => _save(next));
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
