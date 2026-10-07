import 'package:hive_ce/hive.dart';

/// Once-only event gates backed by a Hive box. Powers analytics
/// milestones that should fire exactly one time per device:
/// `first_app_launch`, `first_swap_completed`, `first_deposit_received`,
/// `polymarket_first_bet_placed`, `polymarket_first_profitable_redeem`.
///
/// Lookup is sync and cheap. Setting the flag persists to Hive on the
/// next event-loop tick (Hive batches small writes). All operations
/// are no-ops if the box isn't open — boot-order safe.
class OnceFlagsService {
  OnceFlagsService._();

  static const String boxName = 'once_flags';

  /// Returns true once and only once per device for the given key —
  /// subsequent calls return false. Use to gate `track('first_X')`
  /// emissions:
  ///
  /// ```dart
  /// if (OnceFlagsService.claimOnce('first_swap_completed')) {
  ///   TrackingService.track('first_swap_completed');
  /// }
  /// ```
  static bool claimOnce(String key) {
    try {
      if (!Hive.isBoxOpen(boxName)) return false;
      final box = Hive.box<bool>(boxName);
      if (box.get(key) == true) return false;
      box.put(key, true);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Read-only check — useful when the event has already fired via
  /// claimOnce elsewhere and we just want to gate UI (e.g. hide an
  /// onboarding hint once the user has placed their first bet).
  static bool isClaimed(String key) {
    try {
      if (!Hive.isBoxOpen(boxName)) return false;
      return Hive.box<bool>(boxName).get(key) == true;
    } catch (_) {
      return false;
    }
  }

  /// Clear a single flag — e.g. revoking a one-time consent so its gate
  /// re-prompts on the next attempt.
  static Future<void> resetKey(String key) async {
    try {
      if (Hive.isBoxOpen(boxName)) {
        await Hive.box<bool>(boxName).delete(key);
      }
    } catch (_) {}
  }

  /// Manual reset — used by the wallet-wipe flow so a fresh re-import
  /// gets a fresh set of "first X" milestones.
  static Future<void> resetAll() async {
    try {
      if (Hive.isBoxOpen(boxName)) {
        await Hive.box<bool>(boxName).clear();
      }
    } catch (_) {}
  }
}
