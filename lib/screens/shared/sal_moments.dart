// lib/screens/shared/sal_moments.dart
//
// SAL'S MOMENTS (founder, 12 November 2026: "Sal animations — do it":
// more, different Sal animations, tied to moments, not decoration, Sal
// kept special and calm). No Sal is added anywhere: the Sals already on
// screen play a clip that fits what just happened, once, and then keep
// still. Face framing (the Sal toast, the result sheet, the bar's button)
// uses the face clips; body framing (the money journey, the empty states)
// the body clips, chosen on the renders' frames:
//
//   * WIN (a prediction won, winnings claimed: the result sheet's
//     celebrate tone): `cheer` once (eyes squeezed happy, a head bob),
//     then `happy`.
//   * DONE (an order or a prediction placed: the success toast, the
//     result sheet's success): `nod` once (a deep "done" nod), held still
//     on its last frame.
//   * SHRUG (a failure toast, a failed order, a lost prediction's
//     receipt): `shake_no` once (a calm head shake, no tears), held
//     still; the money journey's body Sal shakes it off
//     (`body_shake_off`, [SalMoments.shrugBody]) and stands. Never `sad`
//     for money: `sad` stays where it is a deliberate empty state.
//   * WAITING (the placing toast, a pending result, the bar's button
//     while it runs): `think`, then `search`, one pass each in turn,
//     switching only as a pass ends ([SalMoments.waitingFace]); the money
//     journey keeps its own waiting pools (body_pace, body_sniff_trail,
//     body_dig, body_think).
//   * CALM (information, a result read again): the `blink` loop, as
//     before.
//
// The idle beats of an empty state live with their director
// (SalIdleDirector, sal_sprite.dart). Every clip of a moment is decoded
// once when its Sal mounts (the shared cache, sal_sprite.dart), so no
// switch waits on a read. Reduce Motion: the moment's first clip at its
// first frame, nothing plays (a win shows `happy`'s). A moment's sprite
// that yields ([SalMomentSprite.yieldToSpotlight]) starts no new pass
// while another Sal is performing ([SalSpotlight]).

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:kute/screens/shared/sal_sprite.dart';

/// What happened, for the Sal on screen (see the file header).
enum SalMoment { win, done, shrug, waiting, calm }

abstract final class SalMoments {
  /// WIN: once, then [winRest].
  static const String winFace = 'cheer';
  static const String winRest = 'happy';

  /// DONE: once, held.
  static const String doneFace = 'nod';

  /// SHRUG: once, held.
  static const String shrugFace = 'shake_no';

  /// The money journey's shrug (body framing): once, then he stands.
  static const String shrugBody = 'body_shake_off';

  /// WAITING: one pass each, in turn.
  static const List<String> waitingFace = ['think', 'search'];

  /// CALM: the blink loop.
  static const String calmFace = 'blink';

  /// The clip [moment] opens on (its still under Reduce Motion, but a
  /// win's, which is [winRest]).
  static String firstClip(SalMoment moment) => switch (moment) {
        SalMoment.win => winFace,
        SalMoment.done => doneFace,
        SalMoment.shrug => shrugFace,
        SalMoment.waiting => waitingFace.first,
        SalMoment.calm => calmFace,
      };

  /// Every clip [moment] can show, decoded together.
  static List<String> clipsOf(SalMoment moment) => switch (moment) {
        SalMoment.win => const [winFace, winRest],
        SalMoment.done => const [doneFace],
        SalMoment.shrug => const [shrugFace],
        SalMoment.waiting => waitingFace,
        SalMoment.calm => const [calmFace],
      };

  /// Every face clip any moment shows.
  static const List<String> faceClips = [
    winFace,
    winRest,
    doneFace,
    shrugFace,
    ...waitingFace,
    calmFace,
  ];
}

/// A face Sal playing [moment] (see the file header): one [SalSprite]
/// that switches in place. A new moment cuts in at once with the 120 ms
/// dissolve (the outcome lands as it happens); the waiting passes give
/// way only as a pass ends.
class SalMomentSprite extends StatefulWidget {
  const SalMomentSprite({
    super.key,
    required this.moment,
    required this.size,
    required this.fallback,
    this.spriteKey,
    this.yieldToSpotlight = false,
    this.onUnavailable,
  });

  final SalMoment moment;
  final double size;

  /// What [SalSprite] draws when no sheet can be read.
  final Widget fallback;

  /// The inner [SalSprite]'s key (a test finds the clip by it).
  final Key? spriteKey;

  /// A Sal in the background of another's moment (the bar's busy
  /// button): while any Sal holds [SalSpotlight] it starts no new pass
  /// (it holds the last frame of the one on screen, or its first frame
  /// when nothing has played yet).
  final bool yieldToSpotlight;

  /// Called with a clip that cannot be read.
  final ValueChanged<String>? onUnavailable;

  @override
  State<SalMomentSprite> createState() => SalMomentSpriteState();
}

class SalMomentSpriteState extends State<SalMomentSprite> {
  /// Win: 0 the cheer, 1 the happy loop after it. Waiting: the passes
  /// played.
  int _step = 0;
  int _cue = 0;
  bool _reduce = false;
  bool _warmed = false;

  /// Another Sal is performing ([SalMomentSprite.yieldToSpotlight]).
  bool _yield = false;

  /// A waiting pass is through and the next one waits for the spotlight.
  bool _held = false;

  /// Whether a waiting pass has started at all.
  bool _played = false;

  final Set<String> _missing = {};

  @override
  void initState() {
    super.initState();
    if (widget.yieldToSpotlight) {
      SalSpotlight.changes.addListener(_onSpotlight);
      _yield = SalSpotlight.held;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!_warmed) {
      _warmed = true;
      _warm(widget.moment);
    }
  }

  void _warm(SalMoment moment) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    unawaited(SalSpriteCache.warm(
        SalMoments.clipsOf(moment), SalSpriteCache.densityFor(dpr)));
  }

  @override
  void didUpdateWidget(covariant SalMomentSprite oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.moment != widget.moment) {
      _step = 0;
      _cue++;
      _held = false;
      _played = false;
      _warm(widget.moment);
    }
    if (oldWidget.yieldToSpotlight != widget.yieldToSpotlight) {
      if (widget.yieldToSpotlight) {
        SalSpotlight.changes.addListener(_onSpotlight);
        _yield = SalSpotlight.held;
      } else {
        SalSpotlight.changes.removeListener(_onSpotlight);
        _yield = false;
      }
    }
  }

  @override
  void dispose() {
    SalSpotlight.changes.removeListener(_onSpotlight);
    super.dispose();
  }

  void _onSpotlight() {
    final y = SalSpotlight.held;
    if (!mounted || y == _yield) return;
    setState(() {
      _yield = y;
      // Free again: the next pass from the frame held.
      if (!y && _held) _nextPass();
    });
  }

  /// The clip the waiting rotation is on.
  String get _waitingClip {
    final pool = [
      for (final c in SalMoments.waitingFace)
        if (!_missing.contains(c)) c
    ];
    if (pool.isEmpty) return SalMoments.waitingFace.first;
    return pool[_step % pool.length];
  }

  void _nextPass() {
    _held = false;
    _step++;
    _cue++;
  }

  void _passDone() {
    if (!mounted) return;
    setState(() {
      if (_yield) {
        _held = true;
      } else {
        _nextPass();
      }
    });
  }

  void _unavailable(String clip) {
    widget.onUnavailable?.call(clip);
    if (!mounted || !_missing.add(clip)) return;
    switch (widget.moment) {
      case SalMoment.win when clip == SalMoments.winFace:
        setState(() => _step = 1);
      case SalMoment.waiting:
        setState(() {});
      default:
        break;
    }
  }

  /// The clip on screen now (tests).
  String get clip => _clipNow;

  String get _clipNow => switch (widget.moment) {
        SalMoment.win => _step == 0 && !_reduce
            ? SalMoments.winFace
            : SalMoments.winRest,
        SalMoment.waiting => _waitingClip,
        final m => SalMoments.firstClip(m),
      };

  @override
  Widget build(BuildContext context) {
    final moment = widget.moment;
    final clip = _clipNow;
    final bool? loop;
    VoidCallback? onComplete;
    var paused = false;
    var atBoundary = false;
    switch (moment) {
      case SalMoment.win:
        loop = _step == 0 ? false : null;
        // The cheer's last frame has its time before happy takes over.
        atBoundary = _step == 1;
        if (_step == 0) {
          onComplete = () {
            if (mounted) setState(() => _step = 1);
          };
        }
      case SalMoment.done || SalMoment.shrug:
        // Once, then still on its last frame.
        loop = false;
      case SalMoment.waiting:
        atBoundary = true;
        if (_reduce) {
          // Still: the first frame, no rotation.
          loop = null;
        } else {
          loop = false;
          onComplete = _passDone;
          // Yielding before anything played: his first frame, still.
          paused = _yield && !_played;
          if (!paused) _played = true;
        }
      case SalMoment.calm:
        loop = null;
    }
    return SalSprite(
      key: widget.spriteKey,
      clip: clip,
      cue: _cue,
      size: widget.size,
      loop: loop,
      paused: paused,
      switchAtBoundary: atBoundary,
      onComplete: onComplete,
      onUnavailable: () => _unavailable(clip),
      fallback: widget.fallback,
    );
  }
}
