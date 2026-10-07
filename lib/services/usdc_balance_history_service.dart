import 'dart:convert';
import 'package:hive_ce/hive.dart';

/// Persists USDC balance snapshots to Hive for charting over time.
/// Key format: 'YYYY-MM-DD' → JSON '{"balance": 11.46, "ts": 1711814400}'
/// One entry per day (latest snapshot wins).
class UsdcBalanceHistoryService {
  static const _boxName = 'usdc_balance_history';

  static Box<String> get _box => Hive.box<String>(_boxName);

  /// Record a balance snapshot. Only updates once per day (or if balance changed).
  static void record(double balance) {
    final now = DateTime.now();
    final key = _dayKey(now);
    final json = jsonEncode({'balance': balance, 'ts': now.millisecondsSinceEpoch});
    _box.put(key, json);
  }

  /// Get all historical balance snapshots as {DateTime → double}.
  static Map<DateTime, double> getHistory() {
    final result = <DateTime, double>{};
    for (final key in _box.keys) {
      try {
        final parts = (key as String).split('-');
        final date = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
        final data = jsonDecode(_box.get(key)!);
        result[date] = (data['balance'] as num).toDouble();
      } catch (_) {}
    }
    return Map.fromEntries(
      result.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
