// lib/services/security/address_history.dart
//
// Append-only record of receive addresses the app has handed out and
// later retired, so a rotation or compromise review can list every
// address that may still receive funds. Public data only: no amounts,
// keys or balances.

import 'dart:convert';

import 'package:hive_ce/hive.dart';

enum AddressRetireReason { rotation, compromise, catalog, reverify, policy }

class AddressHistoryEntry {
  const AddressHistoryEntry({
    this.walletId,
    required this.venue,
    required this.role,
    required this.chain,
    required this.asset,
    required this.address,
    this.createdAt,
    this.retiredAt,
    this.reason,
    this.replacedBy,
  });

  final String? walletId;
  final String venue;
  final String role;
  final String chain;
  final String asset;
  final String address;
  final String? createdAt;
  final DateTime? retiredAt;
  final AddressRetireReason? reason;
  final String? replacedBy;

  Map<String, dynamic> toJson() => {
        if (walletId != null) 'walletId': walletId,
        'venue': venue,
        'role': role,
        'chain': chain,
        'asset': asset,
        'address': address,
        if (createdAt != null) 'createdAt': createdAt,
        if (retiredAt != null) 'retiredAt': retiredAt!.toUtc().toIso8601String(),
        if (reason != null) 'reason': reason!.name,
        if (replacedBy != null) 'replacedBy': replacedBy,
      };

  factory AddressHistoryEntry.fromJson(Map<String, dynamic> json) {
    final reasonName = json['reason'] as String?;
    return AddressHistoryEntry(
      walletId: json['walletId'] as String?,
      venue: json['venue'] as String? ?? '',
      role: json['role'] as String? ?? '',
      chain: json['chain'] as String? ?? '',
      asset: json['asset'] as String? ?? '',
      address: json['address'] as String? ?? '',
      createdAt: json['createdAt'] as String?,
      retiredAt: DateTime.tryParse(json['retiredAt'] as String? ?? ''),
      reason: AddressRetireReason.values
          .where((r) => r.name == reasonName)
          .firstOrNull,
      replacedBy: json['replacedBy'] as String?,
    );
  }
}

class AddressHistory {
  AddressHistory._();

  static const String boxName = 'address_history';

  static Future<void> open() async {
    if (!Hive.isBoxOpen(boxName)) {
      await Hive.openBox<String>(boxName);
    }
  }

  /// Appends [entry]. A closed box (early startup, tests without Hive)
  /// drops the row rather than failing the retirement it describes.
  static Future<void> record(AddressHistoryEntry entry) async {
    if (!Hive.isBoxOpen(boxName)) return;
    try {
      await Hive.box<String>(boxName).add(jsonEncode(entry.toJson()));
    } catch (_) {}
  }

  /// Every recorded row, oldest first. Corrupt rows are skipped.
  static List<AddressHistoryEntry> all() {
    if (!Hive.isBoxOpen(boxName)) return const [];
    final out = <AddressHistoryEntry>[];
    for (final raw in Hive.box<String>(boxName).values) {
      try {
        out.add(AddressHistoryEntry.fromJson(
            jsonDecode(raw) as Map<String, dynamic>));
      } catch (_) {}
    }
    return out;
  }
}
