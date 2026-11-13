// lib/services/search_recent_store.dart
//
// The search sheet's "Recent" (founder, 31 October 2026): the last five
// things opened from search or typed as queries (an Investing market, a
// prediction event, a query), newest first, each with its ✕ and a Clear
// for all of them. Persisted in the app's Hive store (box `search_recent`,
// one JSON string per entry, opened on first use); no analytics.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';

enum SearchRecentKind { investing, prediction, query }

class SearchRecentEntry {
  const SearchRecentEntry({
    required this.kind,
    required this.id,
    required this.label,
    this.image,
  });

  final SearchRecentKind kind;

  /// The coin (investing), the event slug (prediction) or the query text.
  final String id;
  final String label;

  /// A logo or event image URL, when the row has one.
  final String? image;

  String get key => '${kind.name}:$id';

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'id': id,
        'label': label,
        if (image != null) 'image': image,
      };

  static SearchRecentEntry? fromJson(Map<String, dynamic> json) {
    final kind = SearchRecentKind.values
        .where((k) => k.name == json['kind'])
        .firstOrNull;
    final id = json['id'];
    final label = json['label'];
    if (kind == null || id is! String || label is! String) return null;
    return SearchRecentEntry(
        kind: kind, id: id, label: label, image: json['image'] as String?);
  }
}

abstract final class SearchRecentStore {
  static const String _box = 'search_recent';
  static const int max = 5;

  /// The entries, newest first; the sheet listens to it.
  static final ValueNotifier<List<SearchRecentEntry>> entries =
      ValueNotifier<List<SearchRecentEntry>>(const []);

  static Future<Box<String>>? _opening;
  static bool _loaded = false;

  static Future<Box<String>> _open() =>
      _opening ??= Hive.openBox<String>(_box);

  /// Reads the stored entries once; safe to call every time.
  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final box = await _open();
      final read = <SearchRecentEntry>[];
      for (final raw in box.values) {
        try {
          final e = SearchRecentEntry.fromJson(
              jsonDecode(raw) as Map<String, dynamic>);
          if (e != null) read.add(e);
        } catch (_) {}
      }
      entries.value = read.take(max).toList();
    } catch (_) {
      // No store (a test, a read failure): the list stays in memory.
    }
  }

  static Future<void> _save() async {
    try {
      final box = await _open();
      await box.clear();
      for (final (i, e) in entries.value.indexed) {
        await box.put(i.toString().padLeft(2, '0'), jsonEncode(e.toJson()));
      }
    } catch (_) {}
  }

  /// Puts [entry] first (replacing an older copy), keeping [max].
  static Future<void> record(SearchRecentEntry entry) async {
    await load();
    entries.value = [
      entry,
      for (final e in entries.value)
        if (e.key != entry.key) e,
    ].take(max).toList();
    await _save();
  }

  static Future<void> remove(SearchRecentEntry entry) async {
    entries.value = [
      for (final e in entries.value)
        if (e.key != entry.key) e,
    ];
    await _save();
  }

  static Future<void> clear() async {
    entries.value = const [];
    await _save();
  }
}
