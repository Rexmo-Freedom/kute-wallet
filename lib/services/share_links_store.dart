// lib/services/share_links_store.dart
//
// The sender's own share links, kept on the device (Hive box
// `share_links`, one JSON row per link, opened in hive_boot.dart with the
// other cache-tier boxes). The backend is the record; this is what lets
// the receipt row ("Link sent, waiting for Ana to claim") and Cancel work
// at once and offline, and what the pay-on-open pass marks paid.
//
// Also holds the one PARKED CLAIM: a `/c/{id}` link opened before a wallet
// exists (a fresh install, mid-onboarding) or while the session is locked.
// The id waits here until the session is unlocked and the Claim screen can
// open (app_widget.dart listens for that).
//
// Boot-order safe: every call is a no-op (or empty) while the box is not
// open, the same contract as OnceFlagsService. Tests can point it at an
// in-memory map with [debugMemory].

import 'dart:collection' show MapBase;
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import 'package:kute/models/share_link_model.dart';

abstract final class ShareLinksStore {
  static const String boxName = 'share_links';
  static const String _parkedClaimKey = '__parked_claim';

  /// Bumps on every write, so a provider can rebuild.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Test seam: an in-memory backing map instead of the Hive box.
  @visibleForTesting
  static Map<String, String>? debugMemory;

  static Map<String, String>? _backing() {
    final mem = debugMemory;
    if (mem != null) return mem;
    try {
      if (!Hive.isBoxOpen(boxName)) return null;
      return _HiveMap(Hive.box<String>(boxName));
    } catch (_) {
      return null;
    }
  }

  /// Every link this wallet created, newest first.
  static List<PendingShareLink> all() {
    final box = _backing();
    if (box == null) return const [];
    final rows = <PendingShareLink>[];
    for (final entry in box.entries) {
      if (entry.key == _parkedClaimKey) continue;
      try {
        final row = PendingShareLink.fromJson(jsonDecode(entry.value));
        if (row != null) rows.add(row);
      } catch (_) {/* a row this build cannot read is skipped */}
    }
    rows.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return rows;
  }

  /// Links still waiting on the recipient or on this wallet's payment.
  static List<PendingShareLink> pending() => [
        for (final row in all())
          if (row.status == ShareLinkStatus.open ||
              row.status == ShareLinkStatus.claimed)
            row,
      ];

  static PendingShareLink? byId(String id) {
    final box = _backing();
    final raw = box?[id];
    if (raw == null) return null;
    try {
      return PendingShareLink.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  static void put(PendingShareLink row) {
    final box = _backing();
    if (box == null) return;
    box[row.id] = jsonEncode(row.toJson());
    revision.value++;
  }

  static void setStatus(String id, ShareLinkStatus status) {
    final row = byId(id);
    if (row == null) return;
    put(row.withStatus(status));
  }

  static void remove(String id) {
    final box = _backing();
    if (box == null) return;
    box.remove(id);
    revision.value++;
  }

  // ── The parked claim ──

  static String? get parkedClaimId {
    final raw = _backing()?[_parkedClaimKey];
    return raw == null || raw.isEmpty ? null : raw;
  }

  static void parkClaim(String id) {
    final box = _backing();
    if (box == null) return;
    box[_parkedClaimKey] = id;
    revision.value++;
  }

  /// Reads and clears the parked claim in one step.
  static String? takeParkedClaim() {
    final id = parkedClaimId;
    if (id == null) return null;
    _backing()?.remove(_parkedClaimKey);
    revision.value++;
    return id;
  }
}

/// A `Map<String, String>` view over a Hive box of strings, so the store
/// has one code path for the box and the test map.
class _HiveMap extends MapBase<String, String> {
  _HiveMap(this._box);
  final Box<String> _box;

  @override
  String? operator [](Object? key) => key is String ? _box.get(key) : null;

  @override
  void operator []=(String key, String value) => _box.put(key, value);

  @override
  void clear() => _box.clear();

  @override
  Iterable<String> get keys => _box.keys.whereType<String>();

  @override
  String? remove(Object? key) {
    if (key is! String) return null;
    final prior = _box.get(key);
    _box.delete(key);
    return prior;
  }
}

/// The pending links, rebuilt on every store write.
final pendingShareLinksProvider = Provider<List<PendingShareLink>>((ref) {
  void bump() => ref.invalidateSelf();
  ShareLinksStore.revision.addListener(bump);
  ref.onDispose(() => ShareLinksStore.revision.removeListener(bump));
  return ShareLinksStore.pending();
});
