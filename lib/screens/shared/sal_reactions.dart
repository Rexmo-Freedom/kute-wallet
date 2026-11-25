// lib/screens/shared/sal_reactions.dart
//
// SAL REACTS IN THE BAR (founder, 31 October 2026: "attention to the
// animations on everything"). The bar's Sal (the pill on Home and Dollars,
// the shell bar everywhere else, the primary button) wears the context's
// clip; when something happens he plays ONE face one-shot over it and
// comes back. The same sprite switches clips in place (sal_sprite.dart,
// "one continuous performance"): the reaction cuts in as the context's
// loop comes round to frame 0, both cells dissolve for 120 ms, the loop
// resumes at frame 0 once the reaction has played through, and the
// `reaction` group is decoded once on mount so no cut waits on a read.
// Under Reduce Motion there is no switching: a reaction is skipped.
//
//   * a deposit or payment arrived (Bitcoin or Dollars, the moment the
//     money-in haptic plays)                               → `cheer`
//   * an order filled, a bet placed (the venues' result paths) → `wink`
//   * a load that has lasted 2 s (the search)               → `think`
//
// An error no longer shakes the bar's head: the failure toast's own Sal
// shrugs (sal_moments.dart, founder 12 November 2026: one Sal at a time).
// The hooks only call [SalReactions.play]; the bar only subscribes
// ([SalReactions.current]). A missing clip is skipped (the sprite says so
// through onUnavailable and the bar goes back to its clip). Reactions
// never queue: a new one replaces the one playing.
//
// ONE SAL AT A TIME: while another Sal holds the spotlight (a toast, a
// result sheet, the money journey; SalSpotlight, sal_sprite.dart) a
// reaction is not played, one asked for and not on screen yet is dropped,
// and the bar's Sal plays out the pass it is in and holds its last frame
// until the spotlight is free.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:kute/screens/shared/sal_sprite.dart';

/// The face one-shots of the manifest's `reaction` group.
enum SalReaction {
  wink('wink'),
  yawn('yawn'),
  nod('nod'),
  shakeNo('shake_no'),
  think('think'),
  cheer('cheer');

  const SalReaction(this.clip);

  /// The clip's name in the manifest.
  final String clip;
}

/// One reaction asked for, numbered so the same reaction twice plays
/// twice.
@immutable
class SalReactionEvent {
  const SalReactionEvent(this.reaction, this.seq);

  final SalReaction reaction;
  final int seq;

  String get clip => reaction.clip;

  @override
  bool operator ==(Object other) =>
      other is SalReactionEvent && other.reaction == reaction && other.seq == seq;

  @override
  int get hashCode => Object.hash(reaction, seq);
}

abstract final class SalReactions {
  /// The reaction to play now; null once the bar has played it ([clear]).
  static final ValueNotifier<SalReactionEvent?> current =
      ValueNotifier<SalReactionEvent?>(null);

  static int _seq = 0;

  /// How long a load runs before Sal thinks.
  static const Duration thinkAfter = Duration(seconds: 2);

  static final Map<Object, Timer> _loads = {};

  /// Asks the bar to play [reaction] once; nothing while another Sal is
  /// performing ([SalSpotlight]).
  static void play(SalReaction reaction) {
    if (SalSpotlight.held) return;
    current.value = SalReactionEvent(reaction, ++_seq);
  }

  /// The bar has played (or skipped) [event].
  static void clear(SalReactionEvent event) {
    if (current.value == event) current.value = null;
  }

  /// A load under [key] began ([busy] true) or ended: one that lasts
  /// [thinkAfter] plays `think`.
  static void loading(Object key, bool busy) {
    final running = _loads.remove(key);
    running?.cancel();
    if (!busy) return;
    _loads[key] = Timer(thinkAfter, () {
      _loads.remove(key);
      play(SalReaction.think);
    });
  }

  @visibleForTesting
  static void debugReset() {
    for (final t in _loads.values) {
      t.cancel();
    }
    _loads.clear();
    current.value = null;
    _seq = 0;
  }
}

/// A face [SalSprite] wearing [clip] that plays each reaction once over it
/// and comes back, in place (the switch at the loop's boundary, a 120 ms
/// dissolve, the loop again at frame 0; none of it under Reduce Motion):
/// the primary button's Sal. The pill has its own glyph with the same
/// subscription (kute_bottom_action_bar.dart).
class SalReactionSprite extends StatefulWidget {
  const SalReactionSprite({
    super.key,
    required this.clip,
    required this.size,
    this.speed = 1.0,
    required this.fallback,
  });

  final String clip;
  final double size;
  final double speed;
  final Widget fallback;

  @override
  State<SalReactionSprite> createState() => _SalReactionSpriteState();
}

class _SalReactionSpriteState extends State<SalReactionSprite> {
  SalReactionEvent? _reaction;
  bool _reduce = false;
  bool _warmed = false;

  /// Another Sal is performing: the pass on screen plays out and holds.
  bool _yield = false;

  @override
  void initState() {
    super.initState();
    SalReactions.current.addListener(_onReaction);
    SalSpotlight.changes.addListener(_onSpotlight);
    _reaction = SalReactions.current.value;
    _yield = SalSpotlight.held;
  }

  void _onSpotlight() {
    final held = SalSpotlight.held;
    if (!mounted || held == _yield) return;
    final reaction = _reaction;
    setState(() {
      _yield = held;
      // A reaction not on screen yet gives way (one already playing
      // plays out: the switch back waits for its end).
      if (held && reaction != null) _reaction = null;
    });
    if (held && reaction != null) SalReactions.clear(reaction);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final reaction = _reaction;
    if (_reduce && reaction != null) {
      // No switching under Reduce Motion: the reaction is skipped.
      _reaction = null;
      SalReactions.clear(reaction);
    }
    if (!_warmed) {
      _warmed = true;
      // The whole reaction group decoded once, so no cut waits on a read.
      final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
      unawaited(SalSpriteCache.warmGroup('reaction',
          defaults: [for (final r in SalReaction.values) r.clip],
          density: SalSpriteCache.densityFor(dpr)));
    }
  }

  void _onReaction() {
    final event = SalReactions.current.value;
    if (event == null || event == _reaction) return;
    if (_reduce) {
      SalReactions.clear(event);
      return;
    }
    setState(() => _reaction = event);
  }

  void _done(SalReactionEvent event) {
    SalReactions.clear(event);
    if (mounted && _reaction == event) setState(() => _reaction = null);
  }

  @override
  void dispose() {
    SalReactions.current.removeListener(_onReaction);
    SalSpotlight.changes.removeListener(_onSpotlight);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reaction = _reaction;
    // One sprite: the reaction's clip (numbered, so the same one twice
    // plays twice) switches in at the loop's boundary with a dissolve,
    // and the context's clip switches back the same way once it is
    // through. A reaction that cannot be read leaves the loop on screen.
    return SalSprite(
      clip: reaction?.clip ?? widget.clip,
      cue: reaction?.seq ?? 0,
      size: widget.size,
      speed: reaction == null ? widget.speed : 1.0,
      // Yielding, the context's loop plays out its pass and holds.
      loop: reaction == null && !_yield ? null : false,
      onComplete: reaction == null ? null : () => _done(reaction),
      onUnavailable: reaction == null ? null : () => _done(reaction),
      fallback: widget.fallback,
    );
  }
}
