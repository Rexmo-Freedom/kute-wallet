import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/models/kute_state.dart';

/// Single source of truth for the Kute mascot's current pose. The
/// `KuteMascot` widget renders whatever state this notifier publishes;
/// every signal that wants to influence the mascot routes through here.
///
/// State priority (highest wins when multiple signals fire in the
/// same frame, except `tourGuide` which is a hard pin):
///   tourGuide > error > winPrediction > milestone > incoming >
///   outgoing > refreshing > loading > empty > idle.
///
/// Hard rules (see `lib/docs/delight_hard_rules.md`):
///   * Losses are silent. There is no `lossPrediction` state, and the
///     `redeemEvent` listener early-returns on `payoutUsdc <= 0`.
///   * No streak / leaderboard / random-reward states. The mascot
///     never reacts to "you opened the app" or "you placed a bet."
class KuteStateNotifier extends Notifier<KuteState> {
  /// When non-null, normal state arbitration is suspended — the
  /// mascot stays pinned to this pose. Used by the Phase B
  /// onboarding tour to keep the dog in `tourGuide` while it narrates.
  KuteState? _pinned;

  /// Timers for time-bounded states (incoming wag, win celebration,
  /// etc.). Cancelled and replaced on re-entry so back-to-back signals
  /// don't accumulate.
  Timer? _holdTimer;

  @override
  KuteState build() {
    ref.onDispose(() {
      _holdTimer?.cancel();
    });
    return KuteState.idle;
  }

  /// Pin to a state (used by the onboarding tour). While pinned, all
  /// other transitions are ignored — they're still logged for
  /// telemetry but the mascot doesn't visually change.
  void pin(KuteState pose) {
    _pinned = pose;
    state = pose;
  }

  /// Release the pin. Returns to `idle` unless a higher-priority
  /// state is still pending (which today only happens if the pin
  /// was held while a hold-timer was running — we keep this simple
  /// and just return to idle).
  void unpin() {
    _pinned = null;
    state = KuteState.idle;
  }

  /// Fire when a new receive lands. Holds `incoming` for [duration]
  /// and then returns to idle (or to whatever state was higher
  /// priority and is still active).
  void onReceive({Duration duration = const Duration(milliseconds: 1600)}) {
    if (_pinned != null) return;
    _enterTimed(KuteState.incoming, duration);
  }

  /// Fire when a send is dispatched. Holds `outgoing` for [duration].
  void onSend({Duration duration = const Duration(milliseconds: 1200)}) {
    if (_pinned != null) return;
    _enterTimed(KuteState.outgoing, duration);
  }

  /// Fire on a winning Polymarket redeem. HARD RULE: never call with
  /// `payoutUsdc <= 0`. The caller must check first — this method
  /// asserts the invariant for safety, but the canonical guard lives
  /// at the call site in `polymarket_trading_provider.dart`.
  void onPredictionWin({
    required double payoutUsdc,
    Duration duration = const Duration(milliseconds: 3000),
  }) {
    // HARD RULE: no celebration on a loss. Losses are silent. If you
    // are tempted to change this, read `lib/docs/delight_hard_rules.md`
    // first. Adding any kind of mascot reaction to a loss makes Kute
    // feel like a gambling app — that is the line we will not cross.
    if (payoutUsdc <= 0) return;
    if (_pinned != null) return;
    _enterTimed(KuteState.winPrediction, duration);
  }

  /// Fire when a milestone unlocks. Holds for [duration] so the
  /// crown is visible while the milestone card animates in.
  void onMilestone({Duration duration = const Duration(milliseconds: 4000)}) {
    if (_pinned != null) return;
    _enterTimed(KuteState.milestone, duration);
  }

  /// Fire on an unexpected error. Brief head-tilt.
  void onError({Duration duration = const Duration(milliseconds: 1400)}) {
    if (_pinned != null) return;
    _enterTimed(KuteState.error, duration);
  }

  /// Continuous states — caller is responsible for clearing them
  /// when the corresponding work ends.
  void setLoading(bool active) {
    if (_pinned != null) return;
    if (active) {
      _cancelHold();
      state = KuteState.loading;
    } else if (state == KuteState.loading) {
      state = KuteState.idle;
    }
  }

  void setRefreshing(bool active) {
    if (_pinned != null) return;
    if (active) {
      _cancelHold();
      state = KuteState.refreshing;
    } else if (state == KuteState.refreshing) {
      state = KuteState.idle;
    }
  }

  void setEmpty(bool active) {
    if (_pinned != null) return;
    if (active && state == KuteState.idle) {
      state = KuteState.empty;
    } else if (!active && state == KuteState.empty) {
      state = KuteState.idle;
    }
  }

  void _enterTimed(KuteState pose, Duration duration) {
    _cancelHold();
    state = pose;
    _holdTimer = Timer(duration, () {
      if (_pinned != null) return;
      // Only revert if we're still in this pose. If a higher-priority
      // transition landed during the hold, leave it alone.
      if (state == pose) state = KuteState.idle;
    });
  }

  void _cancelHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
  }
}

final kuteStateProvider =
    NotifierProvider<KuteStateNotifier, KuteState>(KuteStateNotifier.new);
