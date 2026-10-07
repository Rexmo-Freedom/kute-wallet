// lib/screens/shared/kute_dog_rig.dart
//
// Sal, rigged.
//
// The mascot in `lib/assets/kute_dog.svg` is pixel art: every part of him
// is one axis-aligned `<rect>` with a flat fill on a `viewBox="0 0 16 16"`
// grid. That is a picture, not an animation, and flutter_svg has no SMIL
// support, so an "animated SVG" file would render exactly one still frame.
// The GIF is no better: `kute_dog.gif` and `kute_dog_dark.gif` are byte
// identical, so the dark variant was never a variant at all, and a raster
// loop cannot follow the theme or stay sharp at 220 logical pixels.
//
// So Sal is redrawn here as a CustomPainter over the same 16x16 grid, rect
// for rect, and then split into parts that move independently: ears, head,
// muzzle, eyes, nose, bandana, torso, paws, plus a tail he never had. One
// [KuteDogPose] describes a single frame; a loop function maps elapsed
// milliseconds to a pose; [KuteDogLoop] drives that with one controller and
// repaints nothing but the dog.
//
// Everything painted around him (ground, dust, blocks, shadow) takes its
// colour from AppColorsExtension. His own fur does not: the light theme's
// accent is blue and a blue Sal is not Sal, so the character keeps the
// artwork palette in [KuteDogPalette], which mirrors the SVG fills exactly.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:kute/helpers/accessibility.dart';

// ─────────────────────────────────────────────────────────────────────
// Palette
// ─────────────────────────────────────────────────────────────────────

/// Sal's own colours, one for one with the fills in `kute_dog.svg`.
///
/// These are the character's identity rather than UI chrome, which is why
/// they are not theme tokens. Both baked SVGs already resolve to the same
/// values (the "dark" file only spells `white` as `#FFFFFF`), so light and
/// dark share one rig. [of] stays as the single seam if that ever changes.
@immutable
class KuteDogPalette {
  /// Head, ear-side and torso fill (`#F7931A` in the asset).
  final Color fur;

  /// Ears, a step darker than the fur (`#CC7A15`).
  final Color furDark;

  /// Muzzle, chest and paws (`#FDB64E`).
  final Color furLight;

  /// Nose and the lash line of a shut eye (`#3D2B1F`).
  final Color ink;

  final Color sclera;
  final Color pupil;

  /// Bandana band and knot (`#E8342E`) and its shaded underside (`#CC2A24`).
  final Color bandana;
  final Color bandanaShade;

  /// The tongue. The bandana sits directly under the nose, so there is no
  /// bare muzzle for a mouth to live on: the tongue lolls out over the
  /// collar instead, which is why it is much lighter than the band.
  final Color tongue;

  const KuteDogPalette({
    required this.fur,
    required this.furDark,
    required this.furLight,
    required this.ink,
    required this.sclera,
    required this.pupil,
    required this.bandana,
    required this.bandanaShade,
    required this.tongue,
  });

  static const KuteDogPalette mascot = KuteDogPalette(
    fur: Color(0xFFF7931A),
    furDark: Color(0xFFCC7A15),
    furLight: Color(0xFFFDB64E),
    ink: Color(0xFF3D2B1F),
    sclera: Color(0xFFFFFFFF),
    pupil: Color(0xFF000000),
    bandana: Color(0xFFE8342E),
    bandanaShade: Color(0xFFCC2A24),
    tongue: Color(0xFFFF8FA3),
  );

  /// The palette for [context]'s brightness. One palette today, matching
  /// both baked assets; kept as a lookup so a future dark Sal has a home.
  static KuteDogPalette of(BuildContext context) => mascot;
}

// ─────────────────────────────────────────────────────────────────────
// Pose
// ─────────────────────────────────────────────────────────────────────

/// One frame of Sal. Every value is in 16x16 grid units (so `1.0` is one
/// pixel of the original artwork) except the rotations, which are radians.
@immutable
class KuteDogPose {
  /// Head rotation about the neck. Positive tilts the head to his left.
  final double headTilt;

  /// Head movement independent of the body. Positive [headBob] is down,
  /// positive [headLean] is right.
  final double headBob;
  final double headLean;

  /// Ear rotation. Positive flops the ear outward and down on both sides;
  /// negative perks it up.
  final double earLeft;
  final double earRight;

  /// Tail rotation. Positive lifts the tail.
  final double tail;

  /// Eyelid: 0 is wide open, 1 is shut.
  final double blink;

  /// Vertical scale about the paws. Below 1 is a crouch, above 1 a stretch;
  /// the width compensates so the volume reads as constant.
  final double squash;

  /// Whole-dog vertical offset. [bodyBob] is down, [lift] is up.
  final double bodyBob;
  final double lift;

  /// Individual paw offsets, positive down, for digging and stepping.
  final double pawLeft;
  final double pawRight;

  /// Pupil offset. The asset's gaze is already down and to his left, so the
  /// useful ranges are [-2, 0] horizontally and [-1, 0] vertically.
  final double lookX;
  final double lookY;

  /// How far the tongue hangs out, 0 to 1.
  final double tongue;

  const KuteDogPose({
    this.headTilt = 0,
    this.headBob = 0,
    this.headLean = 0,
    this.earLeft = 0,
    this.earRight = 0,
    this.tail = 0,
    this.blink = 0,
    this.squash = 1,
    this.bodyBob = 0,
    this.lift = 0,
    this.pawLeft = 0,
    this.pawRight = 0,
    this.lookX = 0,
    this.lookY = 0,
    this.tongue = 0,
  });

  /// Exactly the pose the SVG is drawn in.
  static const KuteDogPose neutral = KuteDogPose();
}

// ─────────────────────────────────────────────────────────────────────
// The painter
// ─────────────────────────────────────────────────────────────────────

/// Draws Sal at [pose] into a 16x16 grid whose top-left is [origin] and
/// whose pixel is [unit] wide. Nothing is clipped, so a wagging tail or a
/// digging paw may reach a little outside the nominal square.
///
/// Callers that paint a scene around him (ground, dust, blocks) use this
/// directly so the whole scene stays one painter and one repaint.
///
/// [withTail] false leaves out the tail the artwork never had, so a glyph
/// standing in for `kute_dog.svg` keeps exactly its silhouette.
void paintKuteDog(
  Canvas canvas, {
  required Offset origin,
  required double unit,
  required KuteDogPose pose,
  required KuteDogPalette palette,
  Color? shadow,
  bool withTail = true,
}) {
  final u = unit;

  void px(Paint paint, double x, double y, double w, double h) {
    canvas.drawRect(
      Rect.fromLTWH(origin.dx + x * u, origin.dy + y * u, w * u, h * u),
      paint,
    );
  }

  final fur = Paint()..color = palette.fur;
  final furDark = Paint()..color = palette.furDark;
  final furLight = Paint()..color = palette.furLight;
  final ink = Paint()..color = palette.ink;
  final sclera = Paint()..color = palette.sclera;
  final pupil = Paint()..color = palette.pupil;
  final band = Paint()..color = palette.bandana;
  final bandShade = Paint()..color = palette.bandanaShade;

  // Contact shadow first, on the ground, so a hop lifts away from it.
  if (shadow != null) {
    final shrink = (1 - pose.lift * 0.10).clamp(0.45, 1.0);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(origin.dx + 8 * u, origin.dy + 15.1 * u),
        width: 8.6 * u * shrink,
        height: 1.0 * u * shrink,
      ),
      Paint()
        ..color = shadow.withValues(
          alpha: (shadow.a * shrink).clamp(0.0, 1.0),
        ),
    );
  }

  canvas.save();

  // Whole-dog bob and hop, then squash about the paws at y = 15.
  canvas.translate(0, (pose.bodyBob - pose.lift) * u);
  final sx = 1 + (1 - pose.squash) * 0.55;
  canvas.translate(origin.dx + 8 * u, origin.dy + 15 * u);
  canvas.scale(sx, pose.squash);
  canvas.translate(-(origin.dx + 8 * u), -(origin.dy + 15 * u));

  // ── Tail, behind everything ──
  if (withTail) {
    canvas.save();
    canvas.translate(origin.dx + 4 * u, origin.dy + 12.8 * u);
    canvas.rotate(pose.tail);
    canvas.translate(-(origin.dx + 4 * u), -(origin.dy + 12.8 * u));
    px(fur, 2.6, 11.8, 1.5, 1.4);
    px(fur, 1.7, 10.8, 1.4, 1.4);
    px(furDark, 1.0, 9.8, 1.3, 1.4);
    canvas.restore();
  }

  // ── Torso, chest, paws ──
  px(fur, 4, 10, 8, 4);
  px(furLight, 6, 10, 4, 3);
  px(furLight, 4, 14 + pose.pawLeft, 2, 1);
  px(furLight, 10, 14 + pose.pawRight, 2, 1);

  // ── Head group ──
  // Applied twice: once for the head itself and once for the tongue, which
  // has to be painted after the collar to be visible but still has to ride
  // along when the head tilts.
  void headTransform() {
    canvas.translate(pose.headLean * u, pose.headBob * u);
    canvas.translate(origin.dx + 8 * u, origin.dy + 9 * u);
    canvas.rotate(pose.headTilt);
    canvas.translate(-(origin.dx + 8 * u), -(origin.dy + 9 * u));
  }

  canvas.save();
  headTransform();

  // Ears rotate about where they meet the skull. Positive flops outward,
  // which means clockwise on his right and anticlockwise on his left.
  canvas.save();
  canvas.translate(origin.dx + 4 * u, origin.dy + 4 * u);
  canvas.rotate(-pose.earLeft);
  canvas.translate(-(origin.dx + 4 * u), -(origin.dy + 4 * u));
  px(furDark, 2, 3, 2, 2);
  canvas.restore();

  canvas.save();
  canvas.translate(origin.dx + 12 * u, origin.dy + 5 * u);
  canvas.rotate(pose.earRight);
  canvas.translate(-(origin.dx + 12 * u), -(origin.dy + 5 * u));
  px(furDark, 12, 1, 2, 4);
  canvas.restore();

  // Skull and cheeks.
  px(fur, 4, 3, 8, 6);
  px(fur, 3, 4, 1, 4);
  px(fur, 12, 4, 1, 4);
  // Jaw. At rest this is entirely hidden behind the muzzle and under the
  // bandana; it exists so a tilted head stays joined to the collar instead
  // of opening a notch of background at the jawline.
  px(fur, 3, 7, 10, 3);

  // Muzzle.
  px(furLight, 5, 7, 6, 3);

  // Eyes: 3x3 sclera, 1x2 pupil, and a lid that drops from the brow.
  final lx = pose.lookX.clamp(-2.0, 0.0);
  final ly = pose.lookY.clamp(-1.0, 0.0);
  px(sclera, 5, 4, 3, 3);
  px(sclera, 9, 4, 3, 3);
  px(pupil, 7 + lx, 5 + ly, 1, 2);
  px(pupil, 11 + lx, 5 + ly, 1, 2);
  final blink = pose.blink.clamp(0.0, 1.0);
  if (blink > 0) {
    final lid = 3.0 * blink;
    px(fur, 5, 4, 3, lid);
    px(fur, 9, 4, 3, lid);
    if (blink > 0.55) {
      // Without a lash line a shut eye reads as a blank patch of head.
      px(ink, 5, 4 + lid - 0.45, 3, 0.45);
      px(ink, 9, 4 + lid - 0.45, 3, 0.45);
    }
  }

  // Nose.
  px(ink, 7, 7, 2, 1);
  canvas.restore();

  // ── Bandana, worn over the jaw like a collar ──
  canvas.save();
  px(band, 3, 8, 10, 2);
  px(bandShade, 4, 9, 8, 1);
  canvas.save();
  canvas.translate(origin.dx + 13 * u, origin.dy + 9.5 * u);
  canvas.rotate(pose.tail * 0.35);
  canvas.translate(-(origin.dx + 13 * u), -(origin.dy + 9.5 * u));
  px(band, 13, 9, 2, 1);
  px(band, 14, 10, 1, 1);
  px(bandShade, 13, 10, 1, 1);
  canvas.restore();
  canvas.restore();

  // ── Tongue, lolling over the collar ──
  if (pose.tongue > 0) {
    canvas.save();
    headTransform();
    px(Paint()..color = palette.tongue, 8.3, 7.9, 1.5, 1.7 * pose.tongue);
    canvas.restore();
  }

  canvas.restore();
}

/// A painter for Sal on his own, with no scene around him.
class KuteDogPainter extends CustomPainter {
  final KuteDogPose pose;
  final KuteDogPalette palette;
  final Color? shadow;

  const KuteDogPainter({
    required this.pose,
    required this.palette,
    this.shadow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    paintKuteDog(
      canvas,
      origin: Offset.zero,
      unit: size.width / 16.0,
      pose: pose,
      palette: palette,
      shadow: shadow,
    );
  }

  // The pose is rebuilt every frame by design, so there is nothing to
  // compare that would ever let us skip a paint.
  @override
  bool shouldRepaint(covariant KuteDogPainter oldDelegate) => true;
}

// ─────────────────────────────────────────────────────────────────────
// Timing helpers
// ─────────────────────────────────────────────────────────────────────

/// A sine wave of unit amplitude with period [periodMs].
double kuteWave(double ms, double periodMs) =>
    math.sin(2 * math.pi * ms / periodMs);

/// A smooth 0 to 1 to 0 hump across [start]..[end], and 0 outside it.
double kutePulse(double ms, double start, double end) {
  if (ms <= start || ms >= end) return 0;
  return math.sin(math.pi * (ms - start) / (end - start));
}

/// A blink centred on [at]: shuts in 70ms, opens over the next 110ms.
double kuteBlink(double ms, double at) {
  final d = ms - at;
  if (d < 0 || d > 180) return 0;
  return d < 70 ? d / 70 : 1 - (d - 70) / 110;
}

/// Deterministic 0..1 noise. Dust that re-rolled every frame would boil.
double _noise(int seed) {
  final x = math.sin(seed * 12.9898) * 43758.5453;
  return x - x.floorToDouble();
}

// ─────────────────────────────────────────────────────────────────────
// The loop driver
// ─────────────────────────────────────────────────────────────────────

/// Repeats [poseAt] over [period] and repaints nothing but the dog.
///
/// Reduce Motion stops the controller outright and paints the single frame
/// at [restMs], so the surface still shows Sal rather than a hole.
class KuteDogLoop extends StatefulWidget {
  /// Edge length of the 16x16 grid in logical pixels.
  final double size;

  final Duration period;

  /// Maps elapsed milliseconds within [period] to a frame.
  final KuteDogPose Function(double elapsedMs) poseAt;

  /// The frame shown when animations are disabled, and where a bounded
  /// loop comes to rest.
  final double restMs;

  final Color? shadowColor;

  /// How many times to play [period] before resting on [restMs]. Null
  /// loops forever. Surfaces a person may leave open, and widget tests
  /// that wait for the tree to settle, use a bound.
  final int? cycles;

  const KuteDogLoop({
    super.key,
    required this.size,
    required this.period,
    required this.poseAt,
    this.restMs = 0,
    this.shadowColor,
    this.cycles,
  });

  @override
  State<KuteDogLoop> createState() => _KuteDogLoopState();
}

class _KuteDogLoopState extends State<KuteDogLoop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduce = false;

  Duration get _run =>
      widget.cycles == null ? widget.period : widget.period * widget.cycles!;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _run);
    // Reduce Motion is read in didChangeDependencies: MediaQuery is not
    // available during initState.
  }

  void _play() {
    if (widget.cycles == null) {
      _controller.repeat();
    } else if (!_controller.isCompleted) {
      _controller.forward();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = reduceMotion(context);
    if (_reduce) {
      if (_controller.isAnimating) _controller.stop();
    } else if (!_controller.isAnimating) {
      _play();
    }
  }

  @override
  void didUpdateWidget(covariant KuteDogLoop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.period != oldWidget.period ||
        widget.cycles != oldWidget.cycles) {
      _controller.duration = _run;
      if (!_reduce) _play();
    }
  }

  double _elapsedMs() {
    if (widget.cycles == null) {
      return _controller.value * widget.period.inMilliseconds;
    }
    if (_controller.isCompleted) return widget.restMs;
    return (_controller.value * _run.inMilliseconds) %
        widget.period.inMilliseconds;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = KuteDogPalette.of(context);
    final size = Size.square(widget.size);

    if (_reduce) {
      return CustomPaint(
        size: size,
        painter: KuteDogPainter(
          pose: widget.poseAt(widget.restMs),
          palette: palette,
          shadow: widget.shadowColor,
        ),
      );
    }

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          size: size,
          painter: KuteDogPainter(
            pose: widget.poseAt(_elapsedMs()),
            palette: palette,
            shadow: widget.shadowColor,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Idle: the ambient loop
// ─────────────────────────────────────────────────────────────────────

/// The idle loop is long on purpose. A two second cycle is a tic; ten
/// seconds is long enough that the breathing, the blinks, the ear flick and
/// the glance around never land on the same beat twice in a row.
const int kKuteDogIdleMs = 9600;

/// Sal sitting there being a dog: breathing, wagging, blinking three times,
/// flicking an ear, glancing left, looking up, and panting once.
KuteDogPose kuteDogIdlePose(double ms) {
  final breathe = kuteWave(ms, 2400);
  final wagBurst = kutePulse(ms, 4600, 5900);
  return KuteDogPose(
    squash: 1 + 0.022 * breathe,
    bodyBob: -0.10 * breathe,
    headBob: -0.06 * breathe,
    headTilt: 0.045 * kuteWave(ms, 3700) + 0.16 * kutePulse(ms, 6000, 7300),
    earLeft: 0.09 * kuteWave(ms, 2400),
    earRight:
        -0.34 * kutePulse(ms, 3000, 3260) - 0.28 * kutePulse(ms, 7400, 7640),
    tail: (0.20 + 0.26 * wagBurst) * kuteWave(ms, wagBurst > 0.1 ? 380 : 1100),
    blink: kuteBlink(ms, 1500) + kuteBlink(ms, 4700) + kuteBlink(ms, 8200),
    lookX: -1.5 * kutePulse(ms, 2000, 3200),
    lookY: -0.7 * kutePulse(ms, 5600, 6600),
    tongue: 0.38 * kutePulse(ms, 7600, 8800),
  );
}

/// Sal idling. Drop-in replacement for a static SVG or the old GIF.
class KuteDogIdle extends StatelessWidget {
  final double size;

  /// Optional contact shadow, for surfaces where he needs grounding.
  final Color? shadowColor;

  /// See [KuteDogLoop.cycles].
  final int? cycles;

  const KuteDogIdle(
      {super.key, required this.size, this.shadowColor, this.cycles});

  @override
  Widget build(BuildContext context) => KuteDogLoop(
        size: size,
        period: const Duration(milliseconds: kKuteDogIdleMs),
        poseAt: kuteDogIdlePose,
        shadowColor: shadowColor,
        cycles: cycles,
      );
}

// ─────────────────────────────────────────────────────────────────────
// Cheer: a short celebratory bounce
// ─────────────────────────────────────────────────────────────────────

const int _kCheerMs = 1600;

KuteDogPose _cheerPose(double ms) {
  // Two hops, then a beat of panting so it never looks frantic.
  final hop = kutePulse(ms, 40, 400) + kutePulse(ms, 470, 830);
  final land = kutePulse(ms, 380, 500) + kutePulse(ms, 810, 930);
  return KuteDogPose(
    lift: 1.7 * hop,
    squash: 1 + 0.10 * hop - 0.16 * land,
    headBob: -0.35 * hop,
    earLeft: 0.55 * hop,
    earRight: 0.65 * hop,
    pawLeft: -0.5 * hop,
    pawRight: -0.5 * hop,
    tail: 0.46 * kuteWave(ms, 240),
    tongue: 0.30 + 0.22 * kuteWave(ms, 520),
    blink: kuteBlink(ms, 1180),
    lookY: -0.6 * hop,
  );
}

/// Sal celebrating. For surfaces that are genuinely good news and are not
/// asking the user to check a number.
class KuteDogCheer extends StatelessWidget {
  final double size;
  final Color? shadowColor;

  /// See [KuteDogLoop.cycles].
  final int? cycles;

  const KuteDogCheer(
      {super.key, required this.size, this.shadowColor, this.cycles});

  @override
  Widget build(BuildContext context) => KuteDogLoop(
        size: size,
        period: const Duration(milliseconds: _kCheerMs),
        poseAt: _cheerPose,
        restMs: 1450,
        shadowColor: shadowColor,
        cycles: cycles,
      );
}

// ─────────────────────────────────────────────────────────────────────
// At work: the creating-wallet scene
// ─────────────────────────────────────────────────────────────────────

const int _kDigMs = 420;
const int _kBlocks = 6;
const int _kBuildMs = _kDigMs * _kBlocks; // 2520
const int _kGlintMs = 380;
const int _kFadeMs = 300;
const int _kWorkLoopMs = _kBuildMs + _kGlintMs + _kFadeMs; // 3200
const double _kFlightMs = 520;
const double _kImpactAt = 0.38;

/// Sal digging: crouch, drive a paw down, dirt out, block up.
KuteDogPose _workPose(double ms) {
  if (ms < _kBuildMs) {
    final index = (ms ~/ _kDigMs).clamp(0, _kBlocks - 1);
    final t = (ms % _kDigMs) / _kDigMs;
    // Fast down into the strike, slower back up: the weight is in the dig.
    final drive = t < _kImpactAt
        ? Curves.easeInCubic.transform(t / _kImpactAt)
        : 1 -
            Curves.easeOutCubic.transform((t - _kImpactAt) / (1 - _kImpactAt));
    final left = index.isEven;
    return KuteDogPose(
      squash: 1 - 0.13 * drive,
      bodyBob: 0.45 * drive,
      headBob: 0.85 * drive,
      headTilt: (left ? 0.10 : -0.10) * drive,
      headLean: (left ? -0.25 : 0.25) * drive,
      pawLeft: left ? 0.85 * drive : -0.25 * drive,
      pawRight: left ? -0.25 * drive : 0.85 * drive,
      earLeft: 0.40 * drive,
      earRight: 0.50 * drive,
      tail: 0.34 * kuteWave(ms, 300),
      tongue: 0.30 + 0.20 * kuteWave(ms, 620),
      blink: kuteBlink(ms, 1880),
    );
  }
  // The wall is up: one hop, then a proud pant while it glints. Everything
  // eases back toward the first digging frame over the last 200ms so the
  // loop restarts without a pop.
  final f = ms - _kBuildMs;
  final settle = 1 - ((f - 480) / 200).clamp(0.0, 1.0);
  return KuteDogPose(
    lift: 1.2 * kutePulse(f, 0, 300),
    squash:
        1 + (0.035 * kuteWave(f, 540) - 0.10 * kutePulse(f, 290, 410)) * settle,
    headBob: -0.20 * settle,
    headTilt: 0.06 * kuteWave(f, 700) * settle,
    earLeft: -0.14 * settle,
    earRight: -0.10 * settle,
    tail: 0.48 * kuteWave(f, 230) * settle,
    tongue: 0.30 + 0.15 * settle,
    lookY: -0.4 * settle,
  );
}

class _AtWorkPainter extends CustomPainter {
  /// Elapsed milliseconds in the loop.
  final double ms;

  /// True when animations are off: one calm, finished frame instead.
  final bool still;

  final KuteDogPalette palette;

  /// Ground, dust and shadow.
  final Color ink;

  /// The blocks Sal stacks.
  final Color accent;

  const _AtWorkPainter({
    required this.ms,
    required this.still,
    required this.palette,
    required this.ink,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final dogSize = w * 0.42;
    final u = dogSize / 16.0;
    final groundY = size.height * 0.75;
    final dogLeft = w * 0.06;
    final holeX = dogLeft + 8 * u;

    final progress = still ? 1.0 : (ms / _kBuildMs).clamp(0.0, 1.0);

    // ── Ground, with a hole that deepens as he works ──
    final holeHalf = 3.4 * u;
    final depth = u * (0.45 + 1.25 * progress);
    final ground = Paint()
      ..color = ink.withValues(alpha: 0.30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, u * 0.24)
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.02, groundY)
        ..lineTo(holeX - holeHalf, groundY)
        ..cubicTo(
          holeX - holeHalf * 0.4,
          groundY + depth,
          holeX + holeHalf * 0.4,
          groundY + depth,
          holeX + holeHalf,
          groundY,
        )
        ..lineTo(w * 0.98, groundY),
      ground,
    );

    // ── Blocks: one per dig, arcing out of the hole onto the stack ──
    final blockSize = u * 2.2;
    final gap = u * 0.34;
    final stackLeft = w - (3 * blockSize + 2 * gap) - w * 0.10;
    Offset slot(int i) => Offset(
          stackLeft + blockSize * 0.5 + (i % 3) * (blockSize + gap),
          groundY - (i ~/ 3) * (blockSize + gap * 0.5),
        );

    final blockPaint = Paint()..color = accent;
    for (int i = 0; i < _kBlocks; i++) {
      final target = slot(i);
      double cx = target.dx;
      double bottom = target.dy;
      double sx = 1;
      double sy = 1;
      double alpha = 1;

      if (!still) {
        final spawn = i * _kDigMs + _kImpactAt * _kDigMs;
        final age = ms - spawn;
        if (age < 0) continue;
        if (age < _kFlightMs) {
          final p = age / _kFlightMs;
          final e = Curves.easeInOut.transform(p);
          cx = holeX + (target.dx - holeX) * e;
          bottom = groundY +
              (target.dy - groundY) * e -
              blockSize * 3.2 * math.sin(math.pi * p);
        } else {
          // Land with a squash so each block has weight.
          final land = ((age - _kFlightMs) / 140).clamp(0.0, 1.0);
          sx = 1 + 0.30 * (1 - land);
          sy = 1 - 0.30 * (1 - land);
        }
        if (ms >= _kBuildMs) {
          final g = ms - _kBuildMs;
          final pop = kutePulse(g, i * 45.0, i * 45.0 + 220);
          sx *= 1 + 0.18 * pop;
          sy *= 1 + 0.18 * pop;
          if (g > _kGlintMs) {
            final fade = ((g - _kGlintMs) / _kFadeMs).clamp(0.0, 1.0);
            alpha = 1 - fade;
            bottom += blockSize * 0.6 * fade;
          }
        }
      }

      final bw = blockSize * sx;
      final bh = blockSize * sy;
      canvas.drawRect(
        Rect.fromLTWH(cx - bw / 2, bottom - bh, bw, bh),
        alpha >= 1
            ? blockPaint
            : (Paint()..color = accent.withValues(alpha: accent.a * alpha)),
      );
    }

    // ── Dirt thrown out of the hole on every strike ──
    if (!still) {
      for (int i = 0; i < _kBlocks; i++) {
        final age = ms - (i * _kDigMs + _kImpactAt * _kDigMs);
        if (age < 0 || age > 340) continue;
        final life = age / 340;
        for (int k = 0; k < 5; k++) {
          final seed = i * 13 + k;
          // A fan up and back over his shoulder, away from the stack.
          final angle = (96 + _noise(seed) * 78) * math.pi / 180;
          final speed = 1.7 + _noise(seed + 31) * 1.3;
          final tt = age / 140.0;
          final px = holeX + math.cos(angle) * speed * u * tt;
          final py = groundY -
              math.sin(angle) * (speed + 0.5) * u * tt +
              0.62 * u * tt * tt;
          final s = u * 0.46;
          canvas.drawRect(
            Rect.fromLTWH(px - s / 2, py - s / 2, s, s),
            Paint()..color = ink.withValues(alpha: 0.40 * (1 - life)),
          );
        }
      }
    }

    // ── Sal ──
    paintKuteDog(
      canvas,
      origin: Offset(dogLeft, groundY - 15 * u),
      unit: u,
      pose: still
          ? const KuteDogPose(tail: 0.14, tongue: 0.26, lookY: -0.3)
          : _workPose(ms),
      palette: palette,
      shadow: ink.withValues(alpha: 0.16),
    );
  }

  @override
  bool shouldRepaint(covariant _AtWorkPainter oldDelegate) => true;
}

/// The long-wait scene: Sal digs, and every dig throws a block onto a wall
/// that builds itself six blocks high, glints, and starts again.
///
/// Used wherever the app is doing several seconds of work for the user
/// (creating a wallet, restoring one). The wall is the point: it gives the
/// wait a shape, so the screen reads as something being built rather than
/// something being waited on.
class KuteDogAtWork extends StatefulWidget {
  /// Scene width. The height is derived from it.
  final double width;

  /// Ground, dust and shadow colour. Surfaces pass their own foreground so
  /// the scene works on a scrim as readily as on a themed background.
  final Color ink;

  /// The blocks.
  final Color accent;

  const KuteDogAtWork({
    super.key,
    required this.width,
    required this.ink,
    required this.accent,
  });

  @override
  State<KuteDogAtWork> createState() => _KuteDogAtWorkState();
}

class _KuteDogAtWorkState extends State<KuteDogAtWork>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduce = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _kWorkLoopMs),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = reduceMotion(context);
    if (_reduce) {
      if (_controller.isAnimating) _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = Size(widget.width, widget.width * 0.62);
    final palette = KuteDogPalette.of(context);

    if (_reduce) {
      // The finished wall, standing still. Reduce Motion should not mean
      // an empty box where the illustration was.
      return CustomPaint(
        size: size,
        painter: _AtWorkPainter(
          ms: 0,
          still: true,
          palette: palette,
          ink: widget.ink,
          accent: widget.accent,
        ),
      );
    }

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          size: size,
          painter: _AtWorkPainter(
            ms: _controller.value * _kWorkLoopMs,
            still: false,
            palette: palette,
            ink: widget.ink,
            accent: widget.accent,
          ),
        ),
      ),
    );
  }
}
