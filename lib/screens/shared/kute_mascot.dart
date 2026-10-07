import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/models/kute_state.dart';
import 'package:kute/providers/kute_state_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/kute_dog_rig.dart';

/// The Kute dog mascot for a [KuteState].
///
/// This used to be the flat SVG under a `Matrix4`: loading spun the whole
/// picture a full turn, refreshing scaled it taller, error rotated it back
/// and forth. A picture being moved around is not a character doing
/// something, and the spin in particular read as a spinner with a logo on
/// it. Every state now drives the rig in `kute_dog_rig.dart` instead, so
/// Sal sniffs, perks his ears, wags, blinks and crouches with his own parts
/// rather than being transformed as a block.
///
/// Two ways to use:
///   * `KuteMascot(state: KuteState.loading, size: 32.sp)` — caller
///     decides the state explicitly.
///   * `KuteMascot.global(size: 32.sp)` — reads `kuteStateProvider` so the
///     global mascot state drives the widget.
///
/// Reduce Motion is handled inside [KuteDogLoop]: the controller never
/// starts and the pose settles to a sensible still frame.
class KuteMascot extends ConsumerWidget {
  /// Explicit state. If null, the widget reads `kuteStateProvider`.
  final KuteState? state;

  /// Edge length in logical pixels (square mascot).
  final double size;

  /// When true, honor the user's "mascot disabled" Settings toggle —
  /// returning an empty box if disabled. False (the default) means the
  /// mascot always renders regardless of the toggle — useful for
  /// context-specific UI like a loading row where hiding the dog would
  /// leave a gap.
  final bool respectUserToggle;

  const KuteMascot({
    super.key,
    this.state,
    required this.size,
    this.respectUserToggle = false,
  });

  /// Reads global state from `kuteStateProvider`. Honors the user's
  /// "mascot disabled" Settings toggle by rendering an empty box.
  const KuteMascot.global({super.key, required this.size})
      : state = null,
        respectUserToggle = true;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (respectUserToggle) {
      final mascotEnabled =
          ref.watch(settingsProvider.select((s) => s.mascotEnabled));
      if (!mascotEnabled) {
        return SizedBox(width: size, height: size);
      }
    }

    final KuteState activeState = state ?? ref.watch(kuteStateProvider);
    return KuteDogLoop(
      size: size,
      period: _periodFor(activeState),
      poseAt: (ms) => _poseFor(activeState, ms),
      restMs: _restMsFor(activeState),
    );
  }
}

Duration _periodFor(KuteState state) {
  switch (state) {
    case KuteState.loading:
      return const Duration(milliseconds: 1700);
    case KuteState.refreshing:
      return const Duration(milliseconds: 1000);
    case KuteState.incoming:
      return const Duration(milliseconds: 760);
    case KuteState.winPrediction:
      return const Duration(milliseconds: 900);
    case KuteState.error:
      return const Duration(milliseconds: 1500);
    case KuteState.milestone:
      return const Duration(milliseconds: 1900);
    case KuteState.outgoing:
      return const Duration(milliseconds: 1100);
    case KuteState.empty:
    case KuteState.tourGuide:
    case KuteState.idle:
      return const Duration(milliseconds: kKuteDogIdleMs);
  }
}

/// The frame each state settles on when animations are disabled. Picked so
/// the still image is the most legible moment of the loop, not a random one.
double _restMsFor(KuteState state) {
  switch (state) {
    case KuteState.loading:
      return 420;
    case KuteState.incoming:
    case KuteState.winPrediction:
      return 0;
    case KuteState.error:
      return 750;
    default:
      return 0;
  }
}

KuteDogPose _poseFor(KuteState state, double ms) {
  switch (state) {
    case KuteState.loading:
      // Working the problem: he sniffs left, sniffs right, ears swinging
      // with the head, tail ticking over. Reads as thinking, not spinning.
      final sweep = kuteWave(ms, 1700);
      final sniff = kutePulse(ms, 0, 340) + kutePulse(ms, 850, 1190);
      return KuteDogPose(
        headTilt: 0.20 * sweep,
        headLean: 0.7 * sweep,
        headBob: 0.45 * sniff,
        earLeft: 0.26 * sweep,
        earRight: -0.26 * sweep,
        tail: 0.24 * kuteWave(ms, 560),
        squash: 1 - 0.035 * sniff,
        lookX: -1.0 + 1.0 * (sweep * 0.5 + 0.5),
        blink: kuteBlink(ms, 1400),
        tongue: 0.16,
      );

    case KuteState.refreshing:
      // A dog shaking itself off: a quick side-to-side shudder that rolls
      // from the head down, then a stretch.
      final shake = kutePulse(ms, 0, 520);
      return KuteDogPose(
        headTilt: 0.22 * shake * kuteWave(ms, 130),
        earLeft: 0.5 * shake * kuteWave(ms, 130),
        earRight: 0.5 * shake * kuteWave(ms, 130 + 20),
        squash: 1 + 0.10 * kutePulse(ms, 560, 1000) - 0.05 * shake,
        headBob: -0.5 * kutePulse(ms, 560, 1000),
        tail: 0.38 * kuteWave(ms, 260),
        tongue: 0.24,
      );

    case KuteState.incoming:
      // Ears up, front end lifting: something is arriving.
      final up = kutePulse(ms, 0, 760);
      return KuteDogPose(
        lift: 0.9 * up,
        squash: 1 + 0.05 * up,
        headBob: -0.5 * up,
        earLeft: -0.30 * up,
        earRight: -0.22 * up,
        tail: 0.42 * kuteWave(ms, 250),
        lookY: -0.8 * up,
        tongue: 0.30 * up,
      );

    case KuteState.winPrediction:
      // Full hop with the tail going.
      final hop = kutePulse(ms, 0, 480);
      return KuteDogPose(
        lift: 1.8 * hop,
        squash: 1 + 0.10 * hop - 0.16 * kutePulse(ms, 460, 600),
        headBob: -0.4 * hop,
        earLeft: 0.6 * hop,
        earRight: 0.7 * hop,
        pawLeft: -0.5 * hop,
        pawRight: -0.5 * hop,
        tail: 0.48 * kuteWave(ms, 220),
        tongue: 0.38,
        lookY: -0.7 * hop,
      );

    case KuteState.error:
      // The confused head-tilt, held rather than vibrated: ears drop, one
      // eye half closes, the tail stops.
      final hold = kutePulse(ms, 150, 1350);
      return KuteDogPose(
        headTilt: 0.30 * hold,
        headLean: -0.5 * hold,
        earLeft: 0.45 * hold,
        earRight: 0.30 * hold,
        tail: -0.24 * hold,
        blink: 0.30 * hold,
        squash: 1 - 0.03 * hold,
      );

    case KuteState.milestone:
      // Slow, proud, chest out.
      final swell = kuteWave(ms, 1900);
      return KuteDogPose(
        squash: 1 + 0.045 * swell,
        bodyBob: -0.18 * swell,
        headBob: -0.22 - 0.10 * swell,
        headTilt: 0.05 * kuteWave(ms, 1900 * 0.5),
        earLeft: -0.14,
        earRight: -0.10,
        tail: 0.34 * kuteWave(ms, 470),
        lookY: -0.5,
        blink: kuteBlink(ms, 1500),
      );

    case KuteState.outgoing:
      // Leaning after something that just left, ears trailing behind.
      final lean = kutePulse(ms, 0, 1100);
      return KuteDogPose(
        headTilt: -0.16 * lean,
        headLean: 1.0 * lean,
        earLeft: -0.20 * lean,
        earRight: 0.26 * lean,
        squash: 1 - 0.04 * lean,
        tail: 0.30 * kuteWave(ms, 420),
        lookX: -1.4 * lean,
      );

    case KuteState.empty:
    case KuteState.tourGuide:
    case KuteState.idle:
      return kuteDogIdlePose(ms);
  }
}
