import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/services/milestone_service.dart';

/// Notifier that broadcasts freshly-unlocked milestones to the UI.
///
/// Producer side (any provider / service): call `notifier.unlock(key)`
/// — wraps `MilestoneService.claim(key)` and, on a successful claim,
/// publishes the [MilestoneInfo] onto state. Subsequent claims on the
/// same key are no-ops (one-shot per device).
///
/// Consumer side (home screen): `ref.listen(pendingMilestoneProvider,
/// ...)` shows the unlock-card overlay and immediately calls
/// `notifier.consume()` so the same milestone doesn't replay on the
/// next rebuild.
class PendingMilestoneNotifier extends Notifier<MilestoneInfo?> {
  @override
  MilestoneInfo? build() => null;

  /// Attempt to claim [key]. On first-ever claim, sets state to the
  /// matching `MilestoneInfo` so listeners can render the unlock UI.
  /// Returns the unlocked info, or `null` if the key is unknown /
  /// already claimed.
  MilestoneInfo? unlock(String key) {
    final info = MilestoneService.claim(key);
    if (info != null) {
      state = info;
    }
    return info;
  }

  /// Consume the current pending milestone — called by the UI right
  /// after it mounts the unlock card so the same milestone doesn't
  /// re-trigger on the next rebuild.
  void consume() {
    state = null;
  }
}

final pendingMilestoneProvider =
    NotifierProvider<PendingMilestoneNotifier, MilestoneInfo?>(
        PendingMilestoneNotifier.new);
