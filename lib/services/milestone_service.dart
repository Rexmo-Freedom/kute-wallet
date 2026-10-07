import 'package:hive_ce/hive.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/services/once_flags_service.dart';

/// Milestone identifiers. Each fires exactly once per device via
/// `OnceFlagsService`. The matching display copy lives in the
/// `MilestoneRegistry.byKey` table below so adding a new milestone is
/// a one-line change.
class MilestoneKeys {
  static const firstSatReceived = 'milestone_first_sat_received';
  static const hundredKSats = 'milestone_100k_sats';
  static const oneMSats = 'milestone_1m_sats';
  static const firstLightning = 'milestone_first_lightning';
  static const firstSavingsDeposit = 'milestone_first_savings_deposit';
  static const firstPrediction = 'milestone_first_prediction';
  static const firstRedeemProfit = 'milestone_first_redeem_profit';

  /// Order in which milestones appear in Settings → Milestones.
  static const all = [
    firstSatReceived,
    hundredKSats,
    oneMSats,
    firstLightning,
    firstSavingsDeposit,
    firstPrediction,
    firstRedeemProfit,
  ];
}

/// Display metadata for a single milestone. Used by the unlock-card
/// and the Settings → Milestones list.
///
/// [title] and [subtitle] are the English fallbacks; UI should resolve
/// copy through [titleFor] / [subtitleFor] so PT users see localized
/// text.
class MilestoneInfo {
  final String key;
  final String title;
  final String subtitle;
  final String emoji;
  /// `true` → the unlock card plays confetti + the mascot's
  /// `milestone` pose. `false` → quieter card with no particles
  /// (used for "first prediction" — we celebrate the OUTCOME not
  /// the ACT of betting).
  final bool confetti;

  const MilestoneInfo({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.emoji,
    required this.confetti,
  });

  /// Localized title. Falls back to the English [title] for keys the
  /// l10n table does not know (should not happen for registry entries).
  String titleFor(AppLocalizations l10n) => switch (key) {
        MilestoneKeys.firstSatReceived => l10n.milestoneFirstSatTitle,
        MilestoneKeys.hundredKSats => l10n.milestoneHundredKSatsTitle,
        MilestoneKeys.oneMSats => l10n.milestoneOneMSatsTitle,
        MilestoneKeys.firstLightning => l10n.milestoneFirstLightningTitle,
        MilestoneKeys.firstSavingsDeposit =>
          l10n.milestoneFirstSavingsDepositTitle,
        MilestoneKeys.firstPrediction => l10n.milestoneFirstPredictionTitle,
        MilestoneKeys.firstRedeemProfit => l10n.milestoneFirstWinTitle,
        _ => title,
      };

  /// Localized subtitle. See [titleFor].
  String subtitleFor(AppLocalizations l10n) => switch (key) {
        MilestoneKeys.firstSatReceived => l10n.milestoneFirstSatSubtitle,
        MilestoneKeys.hundredKSats => l10n.milestoneHundredKSatsSubtitle,
        MilestoneKeys.oneMSats => l10n.milestoneOneMSatsSubtitle,
        MilestoneKeys.firstLightning => l10n.milestoneFirstLightningSubtitle,
        MilestoneKeys.firstSavingsDeposit =>
          l10n.milestoneFirstSavingsDepositSubtitle,
        MilestoneKeys.firstPrediction =>
          l10n.milestoneFirstPredictionSubtitle,
        MilestoneKeys.firstRedeemProfit => l10n.milestoneFirstWinSubtitle,
        _ => subtitle,
      };
}

class MilestoneRegistry {
  static const byKey = <String, MilestoneInfo>{
    MilestoneKeys.firstSatReceived: MilestoneInfo(
      key: MilestoneKeys.firstSatReceived,
      title: 'Your first sat',
      subtitle: 'You received your first bitcoin.',
      emoji: '🎉',
      confetti: true,
    ),
    MilestoneKeys.hundredKSats: MilestoneInfo(
      key: MilestoneKeys.hundredKSats,
      title: '100k sats',
      subtitle: 'Your balance passed 100,000 sats.',
      emoji: '⚡',
      confetti: true,
    ),
    MilestoneKeys.oneMSats: MilestoneInfo(
      key: MilestoneKeys.oneMSats,
      title: '1M sats',
      subtitle: 'Your balance passed 1,000,000 sats.',
      emoji: '👑',
      confetti: true,
    ),
    MilestoneKeys.firstLightning: MilestoneInfo(
      key: MilestoneKeys.firstLightning,
      title: 'First Lightning payment',
      subtitle: 'You paid over Lightning for the first time.',
      emoji: '⚡',
      confetti: true,
    ),
    MilestoneKeys.firstSavingsDeposit: MilestoneInfo(
      key: MilestoneKeys.firstSavingsDeposit,
      title: 'First savings deposit',
      subtitle: 'You made your first savings deposit.',
      emoji: '🏦',
      confetti: true,
    ),
    MilestoneKeys.firstPrediction: MilestoneInfo(
      key: MilestoneKeys.firstPrediction,
      title: 'First prediction',
      subtitle: 'You made your first prediction.',
      emoji: '📈',
      // Quieter — see HARD RULE in delight_hard_rules.md. We don't
      // celebrate the act of betting, only outcomes.
      confetti: false,
    ),
    MilestoneKeys.firstRedeemProfit: MilestoneInfo(
      key: MilestoneKeys.firstRedeemProfit,
      title: 'First winning prediction',
      subtitle: 'Your first prediction paid out.',
      emoji: '🏆',
      confetti: true,
    ),
  };
}

/// A persisted record of a single milestone unlock — used to populate
/// the Settings → Milestones screen so the user can revisit them.
class MilestoneRecord {
  final String key;
  final DateTime unlockedAt;
  const MilestoneRecord({required this.key, required this.unlockedAt});

  Map<String, dynamic> toMap() => {
        'key': key,
        'unlockedAt': unlockedAt.toIso8601String(),
      };

  static MilestoneRecord? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    final key = raw['key'];
    final ts = raw['unlockedAt'];
    if (key is! String || ts is! String) return null;
    final dt = DateTime.tryParse(ts);
    if (dt == null) return null;
    return MilestoneRecord(key: key, unlockedAt: dt);
  }
}

/// Lightweight static helper around the milestone gate +
/// chronological log. Mirrors `OnceFlagsService`'s shape so callers
/// don't have to learn a new pattern.
class MilestoneService {
  MilestoneService._();

  static const String logBoxName = 'milestones_log';

  /// Try to claim a milestone. Returns the unlocked [MilestoneInfo]
  /// if this is the first call for [key] (and the key is a known
  /// milestone), `null` otherwise.
  ///
  /// Appends a [MilestoneRecord] to the persistent log on first
  /// claim so the Settings → Milestones screen can render the
  /// chronology.
  static MilestoneInfo? claim(String key) {
    final info = MilestoneRegistry.byKey[key];
    if (info == null) return null;
    if (!OnceFlagsService.claimOnce(key)) return null;
    _appendLog(key);
    return info;
  }

  /// Read-only: has this milestone been claimed?
  static bool isClaimed(String key) => OnceFlagsService.isClaimed(key);

  /// Full chronological log of claimed milestones. Empty if the box
  /// isn't open yet (boot-order safe).
  static List<MilestoneRecord> log() {
    try {
      if (!Hive.isBoxOpen(logBoxName)) return const [];
      final box = Hive.box(logBoxName);
      final raw = box.get('entries', defaultValue: []);
      if (raw is! List) return const [];
      return raw
          .map((e) => MilestoneRecord.fromMap(e))
          .whereType<MilestoneRecord>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static void _appendLog(String key) {
    try {
      if (!Hive.isBoxOpen(logBoxName)) return;
      final box = Hive.box(logBoxName);
      final existing = box.get('entries', defaultValue: []);
      final list = (existing is List) ? List<dynamic>.from(existing) : <dynamic>[];
      list.add(MilestoneRecord(
        key: key,
        unlockedAt: DateTime.now(),
      ).toMap());
      box.put('entries', list);
    } catch (_) {}
  }

  /// Clears the log. Called from the wallet-wipe path alongside
  /// `OnceFlagsService.resetAll()` so a fresh re-import sees a fresh
  /// set of milestones to earn.
  static Future<void> resetLog() async {
    try {
      if (Hive.isBoxOpen(logBoxName)) {
        await Hive.box(logBoxName).clear();
      }
    } catch (_) {}
  }
}
