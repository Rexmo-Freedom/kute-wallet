import 'dart:convert';

import 'package:hive_ce/hive.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/hyperliquid_market.dart';

/// Match fills to the actual builder fee signed on Kute orders. Shared by
/// phone and Ledger signers; the accounting owner is always the Kute identity.
/// Persist before POST by cloid, and attach exchange oids after acceptance.
class HyperliquidRevenue {
  static Future<Box<String>> _box() =>
      Hive.openBox<String>('hyperliquid_revenue_orders_v1');
  static String _key(String address, String kind, Object id) =>
      '$kind:${address.toLowerCase()}:$id';

  static Future<String?> remember(String address, Map<String, dynamic> action,
      {Map<String, dynamic>? response, String? accountingIdentity}) async {
    try {
      final identity = accountingIdentity ?? AffiliateService.revenueIdentity;
      if (identity == null || action['type'] != 'order') return null;
      final builder = action['builder'];
      if (builder is! Map ||
          !RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch('${builder['b']}') ||
          builder['f'] is! int ||
          builder['f'] < 0 ||
          builder['f'] > 100) {
        return null;
      }
      final orders = action['orders'];
      if (orders is! List) return null;
      final data = response?['response'];
      final statuses =
          data is Map && data['data'] is Map ? data['data']['statuses'] : null;
      final box = await _box();
      for (var i = 0; i < orders.length; i++) {
        final order = orders[i];
        if (order is! Map) continue;
        final assetId = order['a'] as num;
        // HIP-3 perps start at 100000; they are not spot buys.
        final owner = jsonEncode({
          'identity': identity,
          'builderAddress': builder['b'],
          'builderFeeTenthsBp': builder['f'],
          'policyRevision':
              RuntimeCapabilitiesService.instance.snapshot?.revision,
          'spot': assetId >= 10000 && assetId < 100000,
        });
        final cloid = order['c'];
        if (cloid is String && cloid.isNotEmpty) {
          await box.put(_key(address, 'cloid', cloid), owner);
        }
        if (statuses is List && i < statuses.length && statuses[i] is Map) {
          final status = statuses[i] as Map;
          final accepted = status['filled'] ?? status['resting'];
          if (accepted is Map && accepted['oid'] is num) {
            await box.put(_key(address, 'oid', accepted['oid']), owner);
          }
        }
      }
      await box.flush();
      return identity;
    } catch (_) {
      // Accounting must never convert a successfully signed trade into a retry.
      return null;
    }
  }

  static Future<void> linkOrder(String address, String cloid, int oid) async {
    try {
      final box = await _box();
      final owner = box.get(_key(address, 'cloid', cloid));
      if (owner != null) {
        await box.put(_key(address, 'oid', oid), owner);
        await box.flush();
      }
    } catch (_) {}
  }

  /// No longer reports fills. The backend reads each linked account's fills
  /// and builder fees from Hyperliquid itself and books revenue only from the
  /// official builder export, so the app's own `hl_fill` report is retired
  /// for new builds (older builds' reports are still accepted, labelled
  /// app_reported, never revenue). Kept so existing call sites stay valid.
  static Future<void> recordFills(String address, List<HlFill> fills) async {}
}
