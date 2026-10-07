// lib/services/polymarket/combos/combo_feed.dart
//
// Combo rows for the Activity feed. The feed renders Polymarket activity
// as polybrainz `Activity` rows; combos have their own Data API feed
// (`/v2/activity/combos`) whose amounts are share counts, not what the
// user paid. So the rows are built from what is exact and kept locally,
// per deposit wallet, so they outlive the held-positions listing:
//
//   bought  — TRADE / BUY at the combo's first entry, the fee-inclusive
//             stake (`gross_entry_cost_usdc`) and its shares;
//   closed  — TRADE / SELL with the exact SELL-quote proceeds, recorded
//             when an early close fills;
//   claimed — REDEEM with the Data API's `payout_usdc`.
//
// Every row's `outcome` is the "Combo · N legs" label (the chip on the
// row) and its title names the legs. A combo's condition id is 31 bytes
// starting 0x03, which is how the feed tells combo rows apart.

import 'dart:convert';

import 'package:hive_ce/hive.dart';
import 'package:kute/services/polymarket/combos/combo_models.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show Activity;

abstract final class ComboActivityFeed {
  static const _boxName = 'polymarket_combo_feed';

  /// True for a combo condition id (31 bytes, module 0x03).
  static bool isComboCondition(String? conditionId) {
    final c = (conditionId ?? '').toLowerCase();
    return c.length == 64 && c.startsWith('0x03');
  }

  static Future<Box<String>> _box() => Hive.openBox<String>(_boxName);

  static String _title(List<ComboLeg> legs) {
    final names = [
      for (final l in legs)
        if (l.title.isNotEmpty) l.title,
    ];
    final joined = names.join(' + ');
    return joined.length > 160 ? '${joined.substring(0, 157)}...' : joined;
  }

  static String? _icon(List<ComboLeg> legs) {
    for (final l in legs) {
      if (l.imageUrl != null) return l.imageUrl;
    }
    return null;
  }

  /// Records what the latest positions and activity prove. [label] builds
  /// the "Combo · N legs" chip for a leg count.
  static Future<void> sync({
    required String wallet,
    required List<ComboPosition> positions,
    required List<ComboActivity> activity,
    required String Function(int legs) label,
  }) async {
    final w = wallet.toLowerCase();
    final box = await _box();
    final writes = <String, String>{};
    String? hashFor(String condition, Set<String> types) {
      for (final a in activity) {
        if (a.conditionId == condition &&
            types.contains(a.type) &&
            (a.transactionHash ?? '').isNotEmpty) {
          return a.transactionHash;
        }
      }
      return null;
    }

    for (final p in positions) {
      if (p.stakeUsd <= 0 || p.firstEntryAt == null) continue;
      final key = '$w:buy:${p.conditionId}';
      writes[key] = jsonEncode(_row(
        wallet: w,
        conditionId: p.conditionId,
        type: 'TRADE',
        side: 'BUY',
        usd: p.stakeUsd,
        shares: p.shares,
        at: p.firstEntryAt!,
        hash: hashFor(p.conditionId, const {'SPLIT', 'CONVERT', 'WRAP'}) ??
            'combo-buy-${p.conditionId}',
        legs: p.legs,
        label: label(p.legsTotal),
      ));
    }
    for (final a in activity) {
      if (!a.isRedeem) continue;
      final key = '$w:claim:${a.conditionId}:${a.timestamp.millisecondsSinceEpoch}';
      writes[key] = jsonEncode(_row(
        wallet: w,
        conditionId: a.conditionId,
        type: 'REDEEM',
        usd: a.payoutUsd ?? 0,
        shares: a.amountUsd ?? 0,
        at: a.timestamp,
        hash: a.transactionHash ??
            'combo-claim-${a.conditionId}-${a.timestamp.millisecondsSinceEpoch}',
        legs: a.legs,
        label: label(a.legs.length),
      ));
    }
    if (writes.isNotEmpty) await box.putAll(writes);
  }

  /// Records an early close with its exact proceeds.
  static Future<void> recordClose({
    required String wallet,
    required ComboPosition position,
    required double proceedsUsd,
    required double shares,
    required String label,
    String? txHash,
  }) async {
    final w = wallet.toLowerCase();
    final at = DateTime.now().toUtc();
    final box = await _box();
    await box.put(
        '$w:close:${position.conditionId}:${at.millisecondsSinceEpoch}',
        jsonEncode(_row(
          wallet: w,
          conditionId: position.conditionId,
          type: 'TRADE',
          side: 'SELL',
          usd: proceedsUsd,
          shares: shares,
          at: at,
          hash: txHash ??
              'combo-close-${position.conditionId}-${at.millisecondsSinceEpoch}',
          legs: position.legs,
          label: label,
        )));
  }

  static Map<String, dynamic> _row({
    required String wallet,
    required String conditionId,
    required String type,
    String? side,
    required double usd,
    required double shares,
    required DateTime at,
    required String hash,
    required List<ComboLeg> legs,
    required String label,
  }) =>
      {
        'proxy_wallet': wallet,
        'timestamp': at.millisecondsSinceEpoch ~/ 1000,
        'condition_id': conditionId,
        'type': type,
        'size': shares,
        'usdc_size': usd,
        'transaction_hash': hash,
        'price': shares > 0 ? usd / shares : null,
        'side': side,
        'title': _title(legs),
        'outcome': label,
        'icon': _icon(legs),
      };

  /// The combo rows of [wallet] as feed activity, newest first.
  static Future<List<Activity>> rowsFor(String wallet) async {
    try {
      final w = wallet.toLowerCase();
      final box = await _box();
      final out = <Activity>[];
      for (final k in box.keys) {
        if (!k.toString().startsWith('$w:')) continue;
        final raw = box.get(k);
        if (raw == null) continue;
        try {
          out.add(Activity.fromJson(jsonDecode(raw) as Map<String, dynamic>));
        } catch (_) {}
      }
      out.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return out;
    } catch (_) {
      return const [];
    }
  }
}
