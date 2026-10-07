// lib/services/persistence/hive_schema.dart
//
// Schema versioning + migration runner for the JSON-blob Hive
// caches we keep at the edges of the app's persistence layer
// (API response caches, the per-wallet `Transaction` snapshot,
// etc.). Each cache stores values shaped roughly like:
//
//   { "v": <int>, "savedAt": <epoch>, ...payload }
//
// When the payload shape changes incompatibly we want two things:
//
//   1. Existing entries don't crash the decode path.
//   2. Where possible, old entries are upgraded forward instead of
//      silently dropped — so users don't lose their cold-start data
//      across an update.
//
// This file provides a tiny framework for both. Cache services
// declare their `currentVersion` plus a list of [HiveMigration]s
// (each one taking a payload of version N → N+1) and call
// [HiveSchema.upgradeOrDrop] at decode time. Returns the upgraded
// payload if the migration chain succeeds, or `null` if the entry
// can't be brought to the current version (caller treats `null`
// as "cache miss" and refetches).
//
// The framework is intentionally minimal: no async, no Hive-box
// bulk migration, no on-write transformations. Migrations run on
// the read path only, lazily, per entry. That keeps boot fast
// (migrations only fire when a stale entry is actually accessed)
// and keeps the framework cheap enough to be worth using even
// for caches with simple shapes.

import 'package:flutter/foundation.dart';

/// Transformation from one schema version to the next. Returns the
/// upgraded payload (still a `Map<String, dynamic>`) or throws if
/// the input is malformed beyond repair — in which case the entry
/// is dropped on read.
typedef HiveMigration = Map<String, dynamic> Function(
    Map<String, dynamic> payload);

class HiveSchema {
  HiveSchema._();

  /// Walk [payload] forward through [migrations] until it reaches
  /// [currentVersion]. Returns the upgraded map on success, or
  /// `null` if:
  ///   - The payload's `v` field is missing / not an int.
  ///   - Its version is higher than [currentVersion] (downgraded
  ///     code reading newer cache from an older app — bail rather
  ///     than guess).
  ///   - A migration is missing for some intermediate step.
  ///   - A migration throws.
  ///
  /// `null` means "treat as cache miss and refetch". No partial
  /// upgrades are returned — either the chain reaches current or
  /// the entry is discarded.
  static Map<String, dynamic>? upgradeOrDrop(
    Map<String, dynamic> payload, {
    required int currentVersion,
    required List<HiveMigration> migrations,
  }) {
    final raw = payload['v'];
    if (raw is! int) return null;
    int v = raw;
    if (v == currentVersion) return payload;
    if (v > currentVersion) {
      // Newer cache than this code knows how to read — refuse to
      // touch it. The next write from current code will
      // overwrite anyway.
      if (kDebugMode) {
        // ignore: avoid_print
        print('[HiveSchema] entry v=$v > current=$currentVersion, dropping');
      }
      return null;
    }
    var current = payload;
    while (v < currentVersion) {
      final stepIndex = v - 1; // migrations[0] handles 1 → 2, etc.
      if (stepIndex < 0 || stepIndex >= migrations.length) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('[HiveSchema] no migration from v=$v to v=${v + 1}');
        }
        return null;
      }
      try {
        current = migrations[stepIndex](current);
      } catch (e) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('[HiveSchema] migration $v→${v + 1} failed: $e');
        }
        return null;
      }
      v++;
      // Migration must update the version stamp itself; defend
      // against forgetful migration authors.
      if ((current['v'] as int?) != v) {
        current = {...current, 'v': v};
      }
    }
    return current;
  }
}
