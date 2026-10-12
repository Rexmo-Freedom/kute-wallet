// lib/services/polymarket_usdc_cache_service.dart
//
// What the device remembers of the Predictions account between app runs
// and across `polymarketTradingProvider` rebuilds:
//
//   * [PolymarketUsdcCacheService]: the last-known USDC balance, one
//     figure for the whole device. The trading provider goes through
//     `AsyncLoading` every time the active wallet changes, which used to
//     flash $0.00 in the wallet picker, send sheet and home card; the
//     display layer reads this whenever the provider is between reads.
//   * [PolymarketAccountCache]: the last-known account per spending
//     wallet (deposit address and whether it is a legacy wallet, balance,
//     positions, open orders, settled positions, P&L). The trading provider
//     shows it the moment it starts, marked as refreshing, and the deposit
//     sheet reads the address from it without waiting for the account to
//     wake up. Public figures and the wallet's own public address only;
//     never a key or a credential.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show ClosedPosition, Order, Position;

class PolymarketUsdcCacheService {
  static const _boxName = 'polymarket_usdc_cache';
  static const _key = 'usdc_balance';

  static Box<double>? get _box {
    try {
      if (!Hive.isBoxOpen(_boxName)) return null;
      return Hive.box<double>(_boxName);
    } catch (_) {
      return null;
    }
  }

  /// Last-known USDC balance in dollars. Returns 0 when nothing is
  /// cached or when the box failed to open (best-effort: never throw).
  static double read() {
    final box = _box;
    if (box == null) return 0;
    try {
      return box.get(_key, defaultValue: 0.0) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Persist [value] as the new last-known balance. Idempotent — the
  /// caller can call this on every successful trading-state read; we
  /// only actually hit disk if the value changed.
  static void write(double value) {
    final box = _box;
    if (box == null) return;
    try {
      final current = box.get(_key, defaultValue: 0.0) ?? 0;
      if (current == value) return;
      box.put(_key, value);
    } catch (_) {
      // Disk full / locked box / etc. The caller's in-memory state
      // is unaffected — caching is best-effort observability.
    }
  }
}

/// One spending wallet's last-known Predictions account.
class PolymarketAccountSnapshot {
  const PolymarketAccountSnapshot({
    required this.depositAddress,
    required this.legacyWallet,
    required this.usdcBalance,
    this.balanceKnown = true,
    this.openPositions = const [],
    this.openOrders = const [],
    this.closedPositions = const [],
    this.totalPnl = 0,
    this.totalPnlPercent = 0,
    required this.updatedAt,
  });

  /// The deposit wallet orders are made from and deposits go to.
  final String depositAddress;

  /// Whether it is a legacy (UUPS) wallet. False means the wallet lives
  /// on the factory's current variant, which can never change back, so
  /// the legacy checks are skipped on later resolves.
  final bool legacyWallet;
  final double usdcBalance;
  final bool balanceKnown;
  final List<Position> openPositions;
  final List<Order> openOrders;
  final List<ClosedPosition> closedPositions;
  final double totalPnl;
  final double totalPnlPercent;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
        'v': 1,
        'depositAddress': depositAddress,
        'legacyWallet': legacyWallet,
        'usdcBalance': usdcBalance,
        'balanceKnown': balanceKnown,
        'openPositions': [for (final p in openPositions) p.toJson()],
        'openOrders': [for (final o in openOrders) o.toJson()],
        'closedPositions': [for (final c in closedPositions) c.toJson()],
        'totalPnl': totalPnl,
        'totalPnlPercent': totalPnlPercent,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  static PolymarketAccountSnapshot? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final address = raw['depositAddress'];
    if (address is! String || address.isEmpty) return null;
    List<T> rows<T>(Object? list, T Function(Map<String, dynamic>) parse) {
      if (list is! List) return const [];
      final out = <T>[];
      for (final row in list) {
        if (row is! Map) continue;
        try {
          out.add(parse(Map<String, dynamic>.from(row)));
        } catch (_) {
          // A row from an older shape is dropped, not the whole snapshot.
        }
      }
      return out;
    }

    return PolymarketAccountSnapshot(
      depositAddress: address,
      legacyWallet: raw['legacyWallet'] == true,
      usdcBalance: (raw['usdcBalance'] as num?)?.toDouble() ?? 0,
      balanceKnown: raw['balanceKnown'] != false,
      openPositions: rows(raw['openPositions'], Position.fromJson),
      openOrders: rows(raw['openOrders'], Order.fromJson),
      closedPositions: rows(raw['closedPositions'], ClosedPosition.fromJson),
      totalPnl: (raw['totalPnl'] as num?)?.toDouble() ?? 0,
      totalPnlPercent: (raw['totalPnlPercent'] as num?)?.toDouble() ?? 0,
      updatedAt: DateTime.tryParse('${raw['updatedAt']}') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}

/// The per-wallet account memory, one Hive box opened on first use (no
/// slot in main()'s boot batch). Best-effort both ways: a box that cannot
/// be opened reads as "nothing known" and writes are dropped. An
/// in-memory mirror answers synchronous reads once [open] has run.
class PolymarketAccountCache {
  PolymarketAccountCache._();

  static const _boxName = 'polymarket_account_cache';
  static Future<Box<String>>? _opening;
  static final Map<String, PolymarketAccountSnapshot> _memory = {};

  /// Test seam: in-memory only, no Hive.
  @visibleForTesting
  static bool memoryOnly = false;

  @visibleForTesting
  static void debugReset() {
    _memory.clear();
    memoryOnly = false;
  }

  static Future<Box<String>?> _box() async {
    if (memoryOnly) return null;
    try {
      if (Hive.isBoxOpen(_boxName)) return Hive.box<String>(_boxName);
      return await (_opening ??=
          Hive.openBox<String>(_boxName).whenComplete(() => _opening = null));
    } catch (_) {
      return null;
    }
  }

  /// Loads [walletId]'s snapshot from disk into memory. Fast and local;
  /// the trading provider awaits it before its first state.
  static Future<PolymarketAccountSnapshot?> open(String walletId) async {
    final held = _memory[walletId];
    if (held != null) return held;
    try {
      final raw = (await _box())?.get(walletId);
      if (raw == null) return null;
      final parsed = PolymarketAccountSnapshot.fromJson(jsonDecode(raw));
      if (parsed != null) _memory[walletId] = parsed;
      return parsed;
    } catch (_) {
      return null;
    }
  }

  /// The snapshot already in memory (after [open] or a [write]), else null.
  static PolymarketAccountSnapshot? read(String walletId) => _memory[walletId];

  static Future<void> write(
      String walletId, PolymarketAccountSnapshot snapshot) async {
    _memory[walletId] = snapshot;
    try {
      await (await _box())?.put(walletId, jsonEncode(snapshot.toJson()));
    } catch (_) {
      // The in-memory copy still serves this run.
    }
  }

  static Future<void> forget(String walletId) async {
    _memory.remove(walletId);
    try {
      await (await _box())?.delete(walletId);
    } catch (_) {}
  }
}
