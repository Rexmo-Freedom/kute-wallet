/// Mascot states the Kute dog can render. Single source of truth for
/// every animated pose; the `KuteMascot` widget renders the visual,
/// and `kuteStateProvider` decides which state is active based on app
/// signals (incoming receives, syncs, milestones, prediction wins).
///
/// IMPORTANT: there is no `lossPrediction` state. Prediction losses
/// are SILENT — see `lib/docs/delight_hard_rules.md` (rule 1) and the
/// inline comment at the redeem-stream listener in
/// `kute_state_provider.dart`. Do not add one.
enum KuteState {
  /// Default — calm, optional gentle breathing. Renders when nothing
  /// else is happening.
  idle,

  /// Incoming payment confirmed. Wag + eyes-light-up for ~1.6s.
  incoming,

  /// Outgoing send in progress. Head-turn watching the money leave.
  outgoing,

  /// Generic loading / spinner replacement (e.g. `KuteLoadingOverlay`).
  /// Rotates the dog.
  loading,

  /// Pull-to-refresh in flight. Stretch / yawn pose.
  refreshing,

  /// Empty wallet / empty activity feed. Sleeping pose with z's.
  empty,

  /// Milestone unlocked — first sat, 100k stack, etc. Tiny crown.
  milestone,

  /// Unexpected error. Confused head-tilt.
  error,

  /// Prediction win (payoutUsdc > 0 only — never on losses). Jump
  /// pose with confetti behind.
  winPrediction,

  /// Phase B onboarding tour active. Friendly guide pose; mascot
  /// moves between anchor points narrating each stop. Pinned by the
  /// tour controller; normal state arbitration is suspended.
  tourGuide,
}
