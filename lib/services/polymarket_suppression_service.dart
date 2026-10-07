import 'package:hive_ce/hive.dart';

/// Polymarket position suppression is **disabled**. Always-show
/// architecture: every position the Data API returns is surfaced to
/// the user. No transient "just sold" hide, no permanent settle
/// marker.
///
/// Background: prior versions hid positions for 30 minutes after a
/// sell (to mask Data API lag) and *permanently* after a settle/claim
/// (sentinel "PERMANENT" marker). The permanent path masked a real
/// bug — a broken cross-contract redeem would mark the position
/// settled while the funds were still sitting unclaimed in the Safe,
/// leaving the user unable to re-claim. The fix landed alongside this
/// neutering of the suppression layer: positions remain visible until
/// the Data API itself removes them.
///
/// The class is kept (rather than deleted) so existing callsites
/// still compile and so the Hive box can be wiped of historical
/// markers on next launch via [migrateClearAllOnce]. All
/// mark/check methods are intentional no-ops.
class PolymarketSuppressionService {
  static const _boxName = 'polymarket_suppressed_positions';

  /// Retained for callsite compatibility — the in-memory mirror in
  /// `polymarket_trading_provider.dart` references it.
  static const Duration suppressionWindow = Duration(minutes: 30);

  static Box<String> get _box => Hive.box<String>(_boxName);

  /// No-op. Suppression is disabled.
  static void mark(String conditionId) {}

  /// No-op. Permanent suppression is disabled — see file header.
  static void markSettled(String conditionId) {}

  /// Always false. No position is ever permanently suppressed.
  static bool isPermanentlySettled(String conditionId) => false;

  /// Always false. No position is ever suppressed.
  static bool isSuppressed(String conditionId) => false;

  /// Empty snapshot — the in-memory map seeds to nothing on launch.
  static Map<String, DateTime> snapshot() => const {};

  /// No-op. Nothing to clear.
  static void clear(String conditionId) {}

  /// One-shot wipe of every historical suppression entry (transient
  /// 30-min markers AND legacy PERMANENT markers). Runs on next
  /// launch via the trading provider's init path; subsequent runs
  /// are no-ops via the `migrated_v2026_05_20_clear_all` Hive flag.
  static Future<void> migrateClearPermanentSettledOnce() async {
    const flagKey = 'migrated_v2026_05_20_clear_all'; // gitleaks:allow (feature-flag name)
    if (_box.get(flagKey) == 'done') return;
    final keysToDelete = <String>[];
    for (final key in _box.keys) {
      final k = key as String;
      if (k == flagKey) continue;
      keysToDelete.add(k);
    }
    for (final k in keysToDelete) {
      await _box.delete(k);
    }
    await _box.put(flagKey, 'done');
  }
}
