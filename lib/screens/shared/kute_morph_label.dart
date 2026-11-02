// lib/screens/shared/kute_morph_label.dart
//
// THE BAR'S MORPH, ONE PIECE (founder, 1 November 2026): the primary
// button (kute_shell_bar.dart, KuteBarPrimaryButton) and the floating Sal
// pill (kute_bottom_action_bar.dart, KuteSalPill; "Search investments or
// manage with AI" ↔ "Search predictions or manage with AI" on the Dollars
// tab) change what they say with the SAME motion, from these three
// widgets:
//
//   * [KuteMorphLabel]: the words. The old ones slide up and out over
//     [kMorphWordsOut] on the settle, the new ones rise from below on the
//     chip spring ([KuteMotion.chip] over [KuteMotion.chipDuration]), both
//     fading, 0.6 of their height. Only the current words size the
//     control: the leaving ones overflow it as they go, so the width heads
//     straight for the new words instead of waiting on the old.
//   * [KuteMorphSize]: the width springs on [KuteMotion.chip] (an
//     AnimatedSize over [KuteMotion.chipDuration]).
//   * [KuteMorphFace]: Sal's clip crossfades over [kMorphFaceDuration].
//
// Reduce Motion: all three switch at once (a zero-length AnimatedSize
// re-dirties itself in layout, a Flutter assertion, so [KuteMorphSize] is
// then no AnimatedSize at all).

import 'package:flutter/widgets.dart';
import 'package:kute/screens/shared/kute_motion.dart'
    show kuteMotion, kuteReduceMotion;
import 'package:kute/theme/kute_motion.dart';

/// How long the old words take to slide out: quicker than the new ones
/// arrive, so a tap is felt at once (the busy label alone within 300 ms).
const Duration kMorphWordsOut = Duration(milliseconds: 200);

/// Sal's clip crossfade.
const Duration kMorphFaceDuration = Duration(milliseconds: 150);

/// How far the words travel, as a share of their own height: the new ones
/// start this far below, the old ones end this far above.
const double kMorphWordsTravel = 0.6;

/// THE WORDS' CROSS-SLIDE (see the file header). [child] is keyed by what
/// it says: a new key slides, the same key stays put (only its style
/// changes, as a busy button under the same label).
class KuteMorphLabel extends StatelessWidget {
  const KuteMorphLabel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduce = kuteReduceMotion(context);
    final currentKey = child.key;
    return AnimatedSwitcher(
      duration: reduce ? Duration.zero : KuteMotion.chipDuration,
      reverseDuration: reduce ? Duration.zero : kMorphWordsOut,
      switchInCurve: reduce ? Curves.linear : KuteMotion.chip,
      switchOutCurve: reduce ? Curves.linear : KuteMotion.settle,
      // Only the current words size the control; the leaving ones overflow
      // it from its start, centred on its height (a two-line label leaving
      // a one-line one, or the words leaving a folded pill's empty box).
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.centerLeft,
        clipBehavior: Clip.none,
        children: [
          for (final p in previous)
            Positioned.fill(
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                maxWidth: double.infinity,
                minHeight: 0,
                maxHeight: double.infinity,
                child: p,
              ),
            ),
          if (current != null) current,
        ],
      ),
      transitionBuilder: (child, animation) {
        final incoming = child.key == currentKey;
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset(
                  0, incoming ? kMorphWordsTravel : -kMorphWordsTravel),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// THE WIDTH ON THE CHIP SPRING (see the file header): [child]'s size
/// change springs on [KuteMotion.chip], held at [alignment]. At once under
/// Reduce Motion.
class KuteMorphSize extends StatelessWidget {
  const KuteMorphSize(
      {super.key, required this.child, this.alignment = Alignment.center});

  final Widget child;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) => kuteReduceMotion(context)
      ? child
      : AnimatedSize(
          duration: KuteMotion.chipDuration,
          curve: KuteMotion.chip,
          alignment: alignment,
          child: child,
        );
}

/// SAL'S CLIP CROSSFADE (see the file header): [child] keyed by the clip
/// it plays. At once under Reduce Motion.
class KuteMorphFace extends StatelessWidget {
  const KuteMorphFace({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: kuteMotion(context, kMorphFaceDuration),
        child: child,
      );
}
