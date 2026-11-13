// lib/services/branta/branta_payee_records.dart
//
// THE PAYEE A SEND WENT TO, KEPT WITH THE PAYMENT (founder, 12 November
// 2026: "on Latest in the Bitcoin home we also see the logo there,
// right?"). When the person confirms a send whose payee Branta VERIFIED
// on the very screen they confirmed on (branta_payee_service.dart), the
// payee's name and logo are saved against the payment's own ids, so the
// home's Latest squares and Earlier rows, every activity list and the
// receipt read "Sent to Strike" with the logo, without asking Branta
// again: no lookup, offline, across restarts.
//
// WHAT IS KEPT, per payment id (the Spark payment id, the on-chain txid,
// an Orchestra order id and its operation id): the name, the logo URL
// (Branta's own host, https), when it was verified and the rail it was
// verified on. Nothing else: never the address, never the code, never
// `branta_secret` (not needed once verified). A tampered or unknown
// answer stores nothing. The record is written once and never
// overwritten; a restored wallet (another phone) has none and its rows
// look as they always did.
//
// WHERE: the Hive box [BrantaPayeeRecordStore.boxName], opened at boot
// (hive_boot.dart) and deleted by the device wipe (hive_wipe.dart). The
// logo bytes live on disk in [brantaLogoCacheManager], the image cache
// (cached_network_image's) the Send screens already draw the logo from:
// the Review's load fills it, a list row reads it back, offline too. A
// logo that cannot be drawn falls back to the row's usual mark. Nothing
// goes to analytics.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import 'package:kute/services/branta/branta_payee_service.dart';
import 'package:kute/services/icon_cache/icon_disk_cache.dart'
    show IconCaches;

/// The disk cache payee logos live in: their own, so a feed's many images
/// never push a payee's logo out of the shared default cache, and kept a
/// year, since a payment's row keeps showing it.
final BaseCacheManager brantaLogoCacheManager = CacheManager(Config(
  'brantaPayeeLogos',
  stalePeriod: const Duration(days: 365),
  maxNrOfCacheObjects: 300,
));

/// The payee one send was verified for.
@immutable
class BrantaPayeeRecord {
  const BrantaPayeeRecord({
    required this.name,
    required this.verifiedAt,
    required this.rail,
    this.logoUrl,
  });

  /// "Strike", "Bitfinex".
  final String name;

  /// The payee's logo on Branta's host (https), or null.
  final String? logoUrl;

  /// When the person confirmed the send with the verified payee on
  /// screen.
  final DateTime verifiedAt;

  /// The rail Branta verified the payee on.
  final BrantaRail rail;

  Map<String, Object> toJson() => {
        'name': name,
        if (logoUrl != null) 'logo': logoUrl!,
        'verified_at': verifiedAt.millisecondsSinceEpoch,
        'rail': rail.name,
      };

  /// Null for anything that is not a whole record.
  static BrantaPayeeRecord? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    final at = json['verified_at'];
    final rail =
        BrantaRail.values.where((r) => r.name == json['rail']).firstOrNull;
    if (name is! String || name.trim().isEmpty || at is! int || rail == null) {
      return null;
    }
    final logo = json['logo'];
    return BrantaPayeeRecord(
      name: name.trim(),
      logoUrl: logo is String && logo.startsWith('https://') ? logo : null,
      verifiedAt: DateTime.fromMillisecondsSinceEpoch(at),
      rail: rail,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BrantaPayeeRecord &&
      other.name == name &&
      other.logoUrl == logoUrl &&
      other.verifiedAt == verifiedAt &&
      other.rail == rail;

  @override
  int get hashCode => Object.hash(name, logoUrl, verifiedAt, rail);

  @override
  String toString() => 'BrantaPayeeRecord($name, ${rail.name})';
}

/// The Hive side: one JSON string per payment id.
abstract final class BrantaPayeeRecordStore {
  static const String boxName = 'branta_payees_v1';

  /// The most payment ids kept; the oldest records go first.
  static const int maxEntries = 500;

  static Box<String>? get _box {
    try {
      return Hive.box<String>(boxName);
    } catch (_) {
      // Not open (a widget test, a failed boot open): in memory only.
      return null;
    }
  }

  /// Every stored record by payment id.
  static Map<String, BrantaPayeeRecord> readAll() {
    final box = _box;
    if (box == null) return {};
    final out = <String, BrantaPayeeRecord>{};
    for (final key in box.keys) {
      if (key is! String) continue;
      try {
        final r = BrantaPayeeRecord.fromJson(jsonDecode(box.get(key) ?? ''));
        if (r != null) out[key] = r;
      } catch (_) {}
    }
    return out;
  }

  /// Writes [record] under each of [ids]; drops the oldest past
  /// [maxEntries].
  static Future<void> write(
      Iterable<String> ids, BrantaPayeeRecord record) async {
    final box = _box;
    if (box == null) return;
    try {
      final json = jsonEncode(record.toJson());
      await box.putAll({for (final id in ids) id: json});
      if (box.length > maxEntries) {
        final all = readAll().entries.toList()
          ..sort((a, b) => a.value.verifiedAt.compareTo(b.value.verifiedAt));
        await box
            .deleteAll(all.take(box.length - maxEntries).map((e) => e.key));
      }
    } catch (_) {
      // A full disk costs only the logo on this row next launch.
    }
  }
}

/// The stored payees by payment id. Read from disk once; a verified send
/// adds to it ([record]).
class BrantaPayeeRecords extends Notifier<Map<String, BrantaPayeeRecord>> {
  /// Puts a logo into [brantaLogoCacheManager], so a row shows it even
  /// when the Review had not finished loading it. Off where background
  /// fetches are off (widget and provider tests: [IconCaches]); tests may
  /// install their own.
  @visibleForTesting
  static Future<void> Function(String url)? debugPrefetchLogo;

  static Future<void> _prefetchLogo(String url) async {
    final fake = debugPrefetchLogo;
    if (fake != null) return fake(url);
    if (!IconCaches.prefetchEnabled) return;
    await brantaLogoCacheManager.getSingleFile(url);
  }

  @override
  Map<String, BrantaPayeeRecord> build() => BrantaPayeeRecordStore.readAll();

  /// Saves [payee] for the payment known by [paymentIds] (null and empty
  /// ids are skipped), when Branta verified it on [rail]. Anything but a
  /// verified payee with a name stores nothing; an id that already has a
  /// record keeps it. Returns whether anything was stored.
  Future<bool> record({
    required Iterable<String?> paymentIds,
    required BrantaPayee? payee,
    required BrantaRail? rail,
    DateTime? at,
  }) async {
    final name = payee?.name?.trim() ?? '';
    if (payee == null || !payee.verified || name.isEmpty || rail == null) {
      return false;
    }
    final ids = {
      for (final id in paymentIds)
        if (id != null && id.trim().isNotEmpty) id.trim()
    }.where((id) => !state.containsKey(id)).toList();
    if (ids.isEmpty) return false;
    final record = BrantaPayeeRecord(
      name: name,
      logoUrl: payee.logoUrl,
      verifiedAt: at ?? DateTime.now(),
      rail: rail,
    );
    state = {...state, for (final id in ids) id: record};
    final logo = record.logoUrl;
    if (logo != null) {
      unawaited(_prefetchLogo(logo).then((_) {}, onError: (_) {}));
    }
    await BrantaPayeeRecordStore.write(ids, record);
    return true;
  }
}

final brantaPayeeRecordsProvider =
    NotifierProvider<BrantaPayeeRecords, Map<String, BrantaPayeeRecord>>(
        BrantaPayeeRecords.new);

/// The payee stored for the payment known by any of [ids], watched (the
/// row redraws when a send stores one). Never a lookup.
BrantaPayeeRecord? watchBrantaPayeeRecord(
    WidgetRef ref, Iterable<String?> ids) {
  final keys = [
    for (final id in ids)
      if (id != null && id.trim().isNotEmpty) id.trim()
  ];
  if (keys.isEmpty) return null;
  return ref.watch(brantaPayeeRecordsProvider.select((all) {
    for (final k in keys) {
      final r = all[k];
      if (r != null) return r;
    }
    return null;
  }));
}
