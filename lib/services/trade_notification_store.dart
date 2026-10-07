import 'dart:convert';
import 'package:hive_ce/hive.dart';

/// A durable, account-scoped result receipt. No keys or credentials are stored.
class TradeNotification {
  final String id, account, product, title, subtitle;
  final Map<String, String> rows;
  final String? assetCode, imageUrl, walletId, walletName;
  final int time;
  final bool positive, read;
  const TradeNotification(
      {required this.id,
      required this.account,
      required this.product,
      required this.title,
      required this.subtitle,
      required this.rows,
      required this.time,
      this.walletId,
      this.walletName,
      this.assetCode,
      this.imageUrl,
      this.positive = false,
      this.read = false});

  Map<String, dynamic> toJson() => {
        'id': id,
        'account': account,
        'product': product,
        'title': title,
        'subtitle': subtitle,
        'rows': rows,
        'time': time,
        'walletId': walletId,
        'walletName': walletName,
        'assetCode': assetCode,
        'imageUrl': imageUrl,
        'positive': positive,
        'read': read
      };
  factory TradeNotification.fromJson(Map<String, dynamic> j) =>
      TradeNotification(
          id: j['id'] as String,
          account: j['account'] as String,
          product: j['product'] as String,
          title: j['title'] as String,
          subtitle: j['subtitle'] as String,
          rows: Map<String, String>.from(j['rows'] as Map),
          time: j['time'] as int,
          walletId: j['walletId'] as String?,
          walletName: j['walletName'] as String?,
          assetCode: j['assetCode'] as String?,
          imageUrl: j['imageUrl'] as String?,
          positive: j['positive'] == true,
          read: j['read'] == true);
}

class TradeNotificationStore {
  static Future<Box<String>>? _opening;
  static Future<Box<String>> get _box async {
    try {
      final box = await (_opening ??= Hive.openBox<String>('trade_results_v1'));
      if (box.isOpen) return box;
      _opening = Hive.openBox<String>('trade_results_v1');
      return await _opening!;
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  static Future<void> add(TradeNotification item) async {
    final box = await _box;
    // Hive put updates memory synchronously; duplicates never reset read status.
    final existing = box.get(item.id);
    if (existing == null) {
      await box.put(item.id, jsonEncode(item.toJson()));
    } else if (item.assetCode != null || item.imageUrl != null) {
      final saved = TradeNotification.fromJson(
          jsonDecode(existing) as Map<String, dynamic>);
      await box.put(
          item.id,
          jsonEncode({
            ...saved.toJson(),
            if (item.assetCode != null) 'assetCode': item.assetCode,
            if (item.imageUrl != null) 'imageUrl': item.imageUrl,
          }));
    }
  }

  /// Reconcile a provisional receipt without replaying an already read result.
  static Future<void> reconcile(TradeNotification item) async {
    final box = await _box;
    final existing = box.get(item.id);
    var read = item.read;
    if (existing != null) {
      read = TradeNotification.fromJson(
              jsonDecode(existing) as Map<String, dynamic>)
          .read;
    }
    final encoded = jsonEncode({...item.toJson(), 'read': read});
    if (encoded != existing) await box.put(item.id, encoded);
  }

  static Future<List<TradeNotification>> read(Set<String> accounts) async {
    final box = await _box;
    final results = <TradeNotification>[];
    for (final value in box.values) {
      try {
        final item = TradeNotification.fromJson(
            jsonDecode(value) as Map<String, dynamic>);
        if (accounts.contains(item.account)) results.add(item);
      } catch (_) {/* A damaged entry must not hide the remaining receipts. */}
    }
    return results..sort((a, b) => b.time.compareTo(a.time));
  }

  static Future<void> markRead(TradeNotification item) async {
    final box = await _box;
    await box.put(item.id, jsonEncode({...item.toJson(), 'read': true}));
  }

  /// Marks every listed receipt read, as opening the notifications sheet
  /// does: what the person has seen stops counting toward the hub's badge,
  /// and stays seen across restarts. Already read receipts are left alone.
  static Future<void> markAllRead(Iterable<TradeNotification> items) async {
    final unread = items.where((n) => !n.read).toList();
    if (unread.isEmpty) return;
    final box = await _box;
    await box.putAll({
      for (final n in unread) n.id: jsonEncode({...n.toJson(), 'read': true}),
    });
  }
}

/// How many receipts the hub's Notifications badge counts: only those not
/// yet read. Zero hides the badge.
int unreadTradeNotificationCount(Iterable<TradeNotification> items) =>
    items.where((n) => !n.read).length;
