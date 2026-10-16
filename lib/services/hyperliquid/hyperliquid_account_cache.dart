// Display-only account memory. Execution always reads the live account/model.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/hyperliquid_market.dart';

class HlCachedAccount {
  const HlCachedAccount({required this.address, required this.snapshot});
  final String address;
  final HlAccountSnapshot snapshot;

  Map<String, dynamic> toJson() => {
        'v': 1,
        'address': address,
        'accountValue': snapshot.accountValue,
        'withdrawable': snapshot.withdrawable,
        'totalMarginUsed': snapshot.totalMarginUsed,
        'crossMaintenanceMarginUsed': snapshot.crossMaintenanceMarginUsed,
        'activeDexes': snapshot.activeDexes.toList(),
        'positions': [
          for (final p in snapshot.positions)
            {
              'coin': p.coin,
              'szi': p.szi,
              'entryPx': p.entryPx,
              'positionValue': p.positionValue,
              'unrealizedPnl': p.unrealizedPnl,
              'returnOnEquity': p.returnOnEquity,
              'liquidationPx': p.liquidationPx,
              'marginUsed': p.marginUsed,
              'leverage': {'type': p.leverageType, 'value': p.leverageValue},
              'maxLeverage': p.maxLeverage,
              'cumFunding': {'sinceOpen': p.fundingSinceOpen},
            },
        ],
        'spotBalances': [
          for (final b in snapshot.spotBalances)
            {
              'coin': b.coin,
              'total': b.total,
              'hold': b.hold,
              'entryNtl': b.entryNtl
            },
        ],
      };

  static HlCachedAccount? fromJson(Object? raw) {
    if (raw is! Map || raw['v'] != 1) return null;
    final address = raw['address'];
    if (address is! String || address.isEmpty) return null;
    double number(String key) {
      final value = raw[key];
      if (value is! num || !value.isFinite) throw const FormatException();
      return value.toDouble();
    }

    try {
      return HlCachedAccount(
        address: address,
        snapshot: HlAccountSnapshot(
          accountValue: number('accountValue'),
          withdrawable: number('withdrawable'),
          totalMarginUsed: number('totalMarginUsed'),
          crossMaintenanceMarginUsed: number('crossMaintenanceMarginUsed'),
          positions: [
            for (final row in raw['positions'] as List)
              HlPerpPosition.fromJson(Map<String, dynamic>.from(row as Map)),
          ],
          spotBalances: [
            for (final row in raw['spotBalances'] as List)
              HlSpotBalance.fromJson(Map<String, dynamic>.from(row as Map)),
          ],
          activeDexes: Set<String>.from(raw['activeDexes'] as List),
        ),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Keys contain both the wallet ID and its EVM derivation format. Public
/// account figures only; no signer, grant, credential or execution state.
class HyperliquidAccountCache {
  HyperliquidAccountCache._();
  static const boxName = 'hyperliquid_account_display_cache';
  static final Map<String, HlCachedAccount> _memory = {};
  static final Set<String> _deletedWallets = {};
  static Future<Box<String>>? _opening;

  @visibleForTesting
  static bool memoryOnly = false;

  @visibleForTesting
  static void debugReset() {
    _memory.clear();
    _deletedWallets.clear();
    memoryOnly = false;
  }

  static Future<Box<String>?> _box() async {
    if (memoryOnly) return null;
    try {
      if (Hive.isBoxOpen(boxName)) return Hive.box<String>(boxName);
      return await (_opening ??=
          Hive.openBox<String>(boxName).whenComplete(() => _opening = null));
    } catch (_) {
      return null;
    }
  }

  static Future<HlCachedAccount?> open(String key) async {
    if (_deletedWallets.any((wallet) => key.startsWith('$wallet:'))) return null;
    final held = _memory[key];
    if (held != null) return held;
    try {
      final raw = (await _box())?.get(key);
      if (_deletedWallets.any((wallet) => key.startsWith('$wallet:'))) return null;
      if (raw == null) return null;
      final parsed = HlCachedAccount.fromJson(jsonDecode(raw));
      // A network response may have arrived while the disk was opening.
      if (_memory.containsKey(key)) return _memory[key];
      if (parsed != null) _memory[key] = parsed;
      return parsed;
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String key, HlCachedAccount account) async {
    if (_deletedWallets.any((wallet) => key.startsWith('$wallet:'))) return;
    _memory[key] = account;
    try {
      final box = await _box();
      // Concurrent successful reads persist the newest published snapshot.
      final latest = _memory[key];
      if (latest != null) await box?.put(key, jsonEncode(latest.toJson()));
    } catch (_) {
      // Best effort: the in-memory copy remains available this session.
    }
  }

  static Future<void> deleteWallet(String walletId) async {
    _deletedWallets.add(walletId);
    bool belongs(Object? key) => key.toString().startsWith('$walletId:');
    _memory.removeWhere((key, _) => belongs(key));
    try {
      final box = await _box();
      if (box != null) {
        await box.deleteAll(box.keys.where(belongs).toList());
      }
    } catch (_) {}
  }
}
