// lib/services/runtime_policy_snapshot_store.dart
//
// The last runtime policies this device fetched, kept on disk so a boot
// with a bad connection starts from what the backend last said instead of
// from nothing. `RuntimeCapabilitiesService` writes them after every
// successful fetch and reads them once at start; the offline grace rules
// live there. Two slots: the public policy (`/config/policy`, no session,
// evaluated for country, platform and app version) and the session policy
// (`/config/capabilities`, evaluated for the signed-in wallet too).
//
// Nothing secret is stored: a policy body is the public, non-secret
// capability metadata the backend publishes (decisions, fee display
// settings, quotas, the small-action allowance, the Polymarket builder
// code), and the owner is the wallet's affiliate id (`affiliates.id`,
// shown in Settings → Advanced) or the word `public`, never the session
// token, the wallet key or an address.

import 'dart:convert';

import 'package:hive_ce/hive.dart';

/// Which policy a stored record is.
enum RuntimePolicySlot {
  /// `/config/policy`: no session, country/platform/version rules only.
  public,

  /// `/config/capabilities`: the signed-in wallet's full policy.
  session,
}

/// The owner recorded for the public policy.
const kPublicPolicyOwner = 'public';

/// One saved policy: who it was fetched for, when (device clock, UTC) and
/// the raw response body it was parsed from.
class StoredRuntimePolicy {
  const StoredRuntimePolicy({
    required this.owner,
    required this.fetchedAt,
    required this.policy,
  });

  /// The session owner the policy was evaluated for (the affiliate id), or
  /// [kPublicPolicyOwner].
  final String owner;

  /// When the device received it, by its own clock.
  final DateTime fetchedAt;

  /// The decoded response body.
  final Map<String, dynamic> policy;

  Map<String, dynamic> toJson() => {
        'v': 1,
        'owner': owner,
        'fetchedAt': fetchedAt.toUtc().toIso8601String(),
        'policy': policy,
      };

  /// Null for anything that is not a complete v1 record.
  static StoredRuntimePolicy? fromJson(Object? json) {
    if (json is! Map) return null;
    if (json['v'] != 1) return null;
    final owner = json['owner'];
    final fetchedAt = json['fetchedAt'];
    final policy = json['policy'];
    if (owner is! String || owner.isEmpty) return null;
    if (fetchedAt is! String || policy is! Map) return null;
    final at = DateTime.tryParse(fetchedAt);
    if (at == null) return null;
    return StoredRuntimePolicy(
      owner: owner,
      fetchedAt: at.toUtc(),
      policy: Map<String, dynamic>.from(policy),
    );
  }
}

/// Where the last policies live between launches.
abstract class RuntimePolicySnapshotStore {
  /// The saved policy in [slot], or null when there is none or it is
  /// unreadable.
  StoredRuntimePolicy? read(RuntimePolicySlot slot);

  /// Replaces the saved policy in [slot]. Best effort: a failed write is
  /// not an error, the in-memory policy is unaffected.
  void write(RuntimePolicySlot slot, StoredRuntimePolicy value);

  /// Forgets the saved policy in [slot].
  void clear(RuntimePolicySlot slot);
}

/// Hive-backed store. The box is opened by `main.dart` in the boot fan-out;
/// when it is not open (a failed open, a test without Hive) every call is
/// a no-op, so the policy service behaves exactly as it did without a disk
/// copy.
class HiveRuntimePolicySnapshotStore implements RuntimePolicySnapshotStore {
  const HiveRuntimePolicySnapshotStore();

  static const boxName = 'runtime_policy_cache';

  static String _key(RuntimePolicySlot slot) => switch (slot) {
        RuntimePolicySlot.public => 'public',
        // The session slot predates the public one and keeps its key.
        RuntimePolicySlot.session => 'last',
      };

  Box<String>? get _box {
    try {
      if (!Hive.isBoxOpen(boxName)) return null;
      return Hive.box<String>(boxName);
    } catch (_) {
      return null;
    }
  }

  @override
  StoredRuntimePolicy? read(RuntimePolicySlot slot) {
    final box = _box;
    if (box == null) return null;
    try {
      final raw = box.get(_key(slot));
      if (raw == null || raw.isEmpty) return null;
      return StoredRuntimePolicy.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  @override
  void write(RuntimePolicySlot slot, StoredRuntimePolicy value) {
    final box = _box;
    if (box == null) return;
    try {
      // `put` updates the in-memory copy at once and flushes to disk on its
      // own; nothing here waits on the file.
      box.put(_key(slot), jsonEncode(value.toJson()));
    } catch (_) {/* disk full or locked: the next fetch tries again */}
  }

  @override
  void clear(RuntimePolicySlot slot) {
    final box = _box;
    if (box == null) return;
    try {
      box.delete(_key(slot));
    } catch (_) {}
  }
}

/// In-memory store for tests and for callers that want no disk copy.
class MemoryRuntimePolicySnapshotStore implements RuntimePolicySnapshotStore {
  MemoryRuntimePolicySnapshotStore();

  final Map<RuntimePolicySlot, StoredRuntimePolicy> values = {};

  @override
  StoredRuntimePolicy? read(RuntimePolicySlot slot) => values[slot];

  @override
  void write(RuntimePolicySlot slot, StoredRuntimePolicy value) =>
      values[slot] = value;

  @override
  void clear(RuntimePolicySlot slot) => values.remove(slot);
}
