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
  static const String _parkedChallengeKey = '__parked_claim_challenge';

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
      if (entry.key == _parkedClaimKey || entry.key == _parkedChallengeKey) {
        continue;
      }
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

  /// The payment id for [claim], written the moment it is known: the one
  /// record that says this link is paid, whatever fails next. Answers
  /// whether this call is the one that recorded it (a second call with the
  /// same id, from the sheet after the funding runner, changes nothing).
  static bool recordPaid(ClaimedShareLink claim, String paymentId) {
    final local = byId(claim.id);
    if (local?.paymentId == paymentId) return false;
    put((local ??
            PendingShareLink(
              id: claim.id,
              kind: claim.kind,
              amountMinor: claim.amountMinor,
              marketSlug: claim.marketSlug,
              url: '',
              createdAt: DateTime.now(),
              status: ShareLinkStatus.paid,
            ))
        .copyWith(status: ShareLinkStatus.paid, paymentId: paymentId));
    return true;
  }

  /// [record] as [claim]'s funding, its row created if this device has
  /// none yet (a link made on another one).
  static void setFunding(ClaimedShareLink claim, GiftFundingRecord record) =>
      put((byId(claim.id) ??
              PendingShareLink(
                id: claim.id,
                kind: claim.kind,
                amountMinor: claim.amountMinor,
                marketSlug: claim.marketSlug,
                url: '',
                createdAt: DateTime.now(),
                status: ShareLinkStatus.claimed,
              ))
          .copyWith(funding: record));

  /// Changes link [id]'s funding record, if it has one.
  static void updateFunding(
      String id, GiftFundingRecord Function(GiftFundingRecord) change) {
    final row = byId(id);
    final funding = row?.funding;
    if (row == null || funding == null) return;
    put(row.copyWith(funding: change(funding)));
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

  /// Whether the parked claim's link is a challenge (`?challenge=1`).
  static bool get parkedClaimChallenge =>
      _backing()?[_parkedChallengeKey] == '1';

  static void parkClaim(String id, {bool challenge = false}) {
    final box = _backing();
    if (box == null) return;
    box[_parkedClaimKey] = id;
    if (challenge) {
      box[_parkedChallengeKey] = '1';
    } else {
      box.remove(_parkedChallengeKey);
    }
    revision.value++;
  }

  /// Reads and clears the parked claim in one step.
  static String? takeParkedClaim() {
    final id = parkedClaimId;
    if (id == null) return null;
    _backing()
      ?..remove(_parkedClaimKey)
      ..remove(_parkedChallengeKey);
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
