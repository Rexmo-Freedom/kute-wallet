// lib/screens/shared/kute_dog_scenes.dart
//
// Three more places Sal shows up, each a small scene around the rig in
// kute_dog_rig.dart so the whole picture is one painter and one repaint.
//
//  - [KuteDogSearching]: nose down, following a trail of pawprints that
//    scroll under him. For screens where the app is about to find
//    something of the user's (recovering an account).
//  - [KuteDogNotHere]: sitting beside a striped barrier, a slow shake of
//    the head, then a look up at the user. For every "not available here"
//    wall and sheet, so a refusal has the same face everywhere.
//  - [KuteDogCelebration]: the cheer, with one burst of confetti thrown
//    up as he lands. For the confirmation overlays, beside the check mark,
//    which stays exactly as it is.
//  - [KuteDogMagnifier]: a magnifying glass whose lens is Sal's face, his
//    ears over the rim, the dock's search-or-ask-Sal glyph. The glass scans
//    a little left and right with his eyes following, an ear flicks and he
//    blinks, when the dock appears and then every few seconds, never
//    continuously.
//  - [KuteDogBitcoin]: Sal holding a bitcoin, the wallet home's Bitcoin
//    tab while it is selected; he tosses and catches it now and then.
//  - [KuteDogGlance]: Sal at glyph size, the face of every Ask Sal entry
//    point. A glance across with a little head tilt and a blink, when he
//    appears and then every several seconds, never continuously.
//
// Reduce Motion paints one calm frame of each rather than a hole.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import 'package:kute/helpers/accessibility.dart';
import 'package:kute/screens/shared/kute_dog_rig.dart';

double _noise(int seed) {
  final x = math.sin(seed * 12.9898) * 43758.5453;
  return x - x.floorToDouble();
}

/// One controller, one painter, the shared plumbing of the scenes below.
class _SceneLoop extends StatefulWidget {
  final Size size;
  final int periodMs;

  /// Times the period plays before resting on the still frame. Every scene
  /// here is bounded: a screen left open should settle, and widget tests
  /// wait for the tree to settle.
  final int cycles;
  final Duration delay;
  final CustomPainter Function(double ms, bool still, KuteDogPalette palette)
      painter;

  const _SceneLoop({
    required this.size,
    required this.periodMs,
    required this.painter,
    this.cycles = 1,
    this.delay = Duration.zero,
  });

  @override
  State<_SceneLoop> createState() => _SceneLoopState();
}

class _SceneLoopState extends State<_SceneLoop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduce = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: widget.periodMs * widget.cycles));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = reduceMotion(context);
    if (_reduce) {
      if (_controller.isAnimating) _controller.stop();
      return;
    }
    if (_started) return;
    _started = true;
    Future<void>.delayed(widget.delay, () {
      if (!mounted || _reduce) return;
      _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = KuteDogPalette.of(context);
    if (_reduce) {
      return CustomPaint(
          size: widget.size, painter: widget.painter(0, true, palette));
    }
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          size: widget.size,
          painter: _controller.isCompleted
              ? widget.painter(0, true, palette)
              : widget.painter(
                  (_controller.value * widget.periodMs * widget.cycles) %
                      widget.periodMs,
                  false,
                  palette),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Searching: nose to the ground, following a trail
// ─────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────
// Not here: beside a barrier
// ─────────────────────────────────────────────────────────────────────

const int _kNotHereMs = 5600;

KuteDogPose _notHerePose(double ms) {
  // A slow shake of the head, then a beat later a look up at the user
  // with a tilt: not cross, just sorry about it.
  final shake = kutePulse(ms, 900, 2300);
  final look = kutePulse(ms, 3300, 4700);
  final breathe = kuteWave(ms, 2600);
  return KuteDogPose(
    squash: 1 + 0.018 * breathe,
    bodyBob: -0.08 * breathe,
    headBob: 0.10 - 0.18 * look,
    headLean: 0.42 * shake * kuteWave(ms, 460),
    headTilt: 0.20 * look,
    earLeft: 0.42 - 0.28 * look,
    earRight: 0.46 - 0.30 * look,
    tail: 0.10 * kuteWave(ms, 1500) + 0.18 * look * kuteWave(ms, 420),
    blink: kuteBlink(ms, 700) + kuteBlink(ms, 2900) + kuteBlink(ms, 5000),
    lookY: -0.6 * look,
    lookX: -0.4 * shake * kuteWave(ms, 460),
    tongue: 0.12 * look,
  );
}

class _NotHerePainter extends CustomPainter {
  final double ms;
  final bool still;
  final KuteDogPalette palette;
  final Color ink;
  final Color accent;

  const _NotHerePainter({
    required this.ms,
    required this.still,
    required this.palette,
    required this.ink,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final dogSize = w * 0.40;
    final u = dogSize / 16.0;
    final groundY = size.height * 0.78;
    final dogLeft = w * 0.52;

    canvas.drawLine(
      Offset(w * 0.02, groundY),
      Offset(w * 0.98, groundY),
      Paint()
        ..color = ink.withValues(alpha: 0.30)
        ..strokeWidth = math.max(1.0, u * 0.24)
        ..strokeCap = StrokeCap.round,
    );

    // The barrier: two posts and a striped bar, to his left.
    final postPaint = Paint()..color = ink.withValues(alpha: 0.75);
    final postW = u * 0.9;
    final postH = u * 6.5;
    final left = w * 0.08;
    final right = w * 0.40;
    for (final x in [left, right]) {
      canvas.drawRect(
          Rect.fromLTWH(x - postW / 2, groundY - postH, postW, postH),
          postPaint);
      canvas.drawRect(
          Rect.fromLTWH(
              x - postW * 1.3, groundY - u * 0.6, postW * 2.6, u * 0.6),
          postPaint);
    }
    final barTop = groundY - postH + u * 0.6;
    final barH = u * 1.9;
    final bar =
        Rect.fromLTWH(left - postW / 2, barTop, right - left + postW, barH);
    canvas.drawRect(bar, Paint()..color = accent);
    canvas.save();
    canvas.clipRect(bar);
    final stripe = Paint()..color = ink.withValues(alpha: 0.85);
    final stripeW = u * 1.4;
    for (var x = bar.left - barH; x < bar.right + barH; x += stripeW * 2) {
      canvas.drawPath(
          Path()
            ..moveTo(x, bar.bottom)
            ..lineTo(x + barH, bar.top)
            ..lineTo(x + barH + stripeW, bar.top)
            ..lineTo(x + stripeW, bar.bottom)
            ..close(),
          stripe);
    }
    canvas.restore();

    paintKuteDog(
      canvas,
      origin: Offset(dogLeft, groundY - 15 * u),
      unit: u,
      pose: still
          ? const KuteDogPose(
              headTilt: 0.16,
              earLeft: 0.3,
              earRight: 0.32,
              lookY: -0.4,
              tail: 0.1)
          : _notHerePose(ms),
      palette: palette,
      shadow: ink.withValues(alpha: 0.16),
    );
  }

  @override
  bool shouldRepaint(covariant _NotHerePainter old) => true;
}

/// Sal beside a barrier. The one face every "not available here" wears.
class KuteDogNotHere extends StatelessWidget {
  final double width;
  final Color ink;
  final Color accent;

  const KuteDogNotHere(
      {super.key,
      required this.width,
      required this.ink,
      required this.accent});

  @override
  Widget build(BuildContext context) => _SceneLoop(
        size: Size(width, width * 0.58),
        periodMs: _kNotHereMs,
        cycles: 3,
        painter: (ms, still, palette) => _NotHerePainter(
            ms: ms, still: still, palette: palette, ink: ink, accent: accent),
      );
}

// ─────────────────────────────────────────────────────────────────────
// Celebration: the cheer plus one burst of confetti
// ─────────────────────────────────────────────────────────────────────

const int _kBurstMs = 1500;
const int _kPieces = 14;

class _ConfettiPainter extends CustomPainter {
  final double ms;
  final bool still;
  final Color ink;
  final Color accent;

  const _ConfettiPainter(
      {required this.ms,
      required this.still,
      required this.ink,
      required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    if (still || ms <= 0) return;
    final w = size.width;
    final u = w / 40;
    final origin = Offset(w / 2, size.height * 0.72);
    for (var i = 0; i < _kPieces; i++) {
      // Each piece leaves on its own beat, so the burst reads as thrown
      // rather than fired.
      final start = _noise(i) * 220;
      final age = ms - start;
      if (age < 0) continue;
      final life = (age / (_kBurstMs - 220)).clamp(0.0, 1.0);
      if (life >= 1) continue;
      final angle = (35 + _noise(i + 7) * 110) * math.pi / 180;
      final speed = (5.5 + _noise(i + 19) * 4.5) * u;
      final t = age / 260;
      final x = origin.dx + math.cos(angle) * speed * t;
      final y = origin.dy - math.sin(angle) * speed * t + 1.9 * u * t * t;
      final s = u * (1.1 + _noise(i + 3) * 0.8);
      final spin = t * (2 + _noise(i + 11) * 4);
      final color = i.isEven ? accent : ink;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(spin);
      canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: s, height: s * 0.6),
          Paint()..color = color.withValues(alpha: (1 - life) * 0.95));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => true;
}

/// Sal cheering, with confetti thrown up once as he lands. Sits under or
/// beside a check mark; it never replaces one.
class KuteDogCelebration extends StatelessWidget {
  final double size;
  final Color ink;
  final Color accent;

  /// How long to wait before the burst, so it lands after the check has
  /// finished drawing rather than over it.
  final Duration delay;

  const KuteDogCelebration({
    super.key,
    required this.size,
    required this.ink,
    required this.accent,
    this.delay = Duration.zero,
  });

  @override
  Widget build(BuildContext context) {
    final scene = Size(size * 2.2, size * 1.5);
    return SizedBox(
      width: scene.width,
      height: scene.height,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned.fill(
            child: _SceneLoop(
              size: scene,
              periodMs: _kBurstMs,
              delay: delay,
              painter: (ms, still, _) => _ConfettiPainter(
                  ms: ms, still: still, ink: ink, accent: accent),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(bottom: size * 0.08),
            child: KuteDogCheer(
                size: size,
                cycles: 3,
                shadowColor: ink.withValues(alpha: 0.14)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Magnifier: Sal's face in the lens, his ears over the rim
// ─────────────────────────────────────────────────────────────────────

/// Sal's face filling the 12x12 lens (clipped to its circle), one char a
/// cell: F fur, L muzzle, W sclera, K pupil, N nose (and the lash line of
/// a shut eye), R bandana, S its shade. His skull runs edge to edge, eyes
/// just above the centre line, the bandana across and his chest under it.
/// His pupils keep the artwork's lean to his left, which is his look.
const List<String> _kLensFace = [
  'FFFFFFFFFFFF',
  'FFFFFFFFFFFF',
  'FFFFFFFFFFFF',
  'FFFWWWFWWWFF',
  'FFFWWKFWWKFF',
  'FFFWWKFWWKFF',
  'FFFLLNNLLFFF',
  'RRRRRRRRRRRR',
  'RSSSSSSSSSSR',
  'FFFFLLLLFFFF',
  'FFFFLLLLFFFF',
  'FFFFLLLLFFFF',
];

/// One play: the glass scans slowly left, across and home with his eyes
/// following it and an ear flicking, then he blinks and flicks it again.
const int _kMagnifierMs = 2000;

/// The scan (left, through the middle, right, home) takes this long.
const double _kScanMs = 1400;

/// The blink starts here.
const double _kMagnifierBlinkAt = 1500;

/// The glyph's proportions are set at this square, the dock's: there the
/// lens cell is [_kLensCell] and the ring [_kLensRing] logical px, and the
/// scan reaches [_kScanReach] either way. Other sizes scale with it.
const double _kMagnifierRefSize = 46;
const double _kLensCell = 5 / 3;
const double _kLensRing = 2.34;
const double _kScanReach = 2.0;

/// The handle's round tip reaches this many outer radii from the lens
/// centre, at 45° down and right.
const double _kHandleReach = 2.2;

/// The scan, -1 (left) .. 1 (right); 0 at rest.
double _magnifierScan(double ms) =>
    ms <= 0 || ms >= _kScanMs ? 0 : -math.sin(2 * math.pi * ms / _kScanMs);

/// The face for one frame: pupils [look] cells to his left (0..2), eyes
/// half shut past 0.35 of [blink] and shut (a lash line) past 0.7.
List<String> _lensFace({required int look, required double blink}) {
  if (look == 0 && blink < 0.35) return _kLensFace;
  String eyes(String eye) => 'FFF${eye}F${eye}FF';
  final open = switch (look) { 2 => 'KWW', 1 => 'WKW', _ => 'WWK' };
  final rows = [..._kLensFace];
  if (blink >= 0.7) {
    rows[3] = eyes('FFF');
    rows[4] = eyes('FFF');
    rows[5] = eyes('NNN');
  } else {
    if (blink >= 0.35) rows[3] = eyes('FFF');
    rows[4] = eyes(open);
    rows[5] = eyes(open);
  }
  return rows;
}

Color? _lensColor(String c, KuteDogPalette p) => switch (c) {
      'F' => p.fur,
      'L' => p.furLight,
      'W' => p.sclera,
      'K' => p.pupil,
      'N' => p.ink,
      'R' => p.bandana,
      'S' => p.bandanaShade,
      _ => null,
    };

class _MagnifierPainter extends CustomPainter {
  final double ms;
  final bool still;
  final KuteDogPalette palette;

  /// Ring and handle: the theme's foreground, the colour the plain
  /// magnifier icon wears, so the glass reads in light and dark alike.
  final Color lens;
  final double dpr;

  const _MagnifierPainter({
    required this.ms,
    required this.still,
    required this.palette,
    required this.lens,
    required this.dpr,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Everything below is in device pixels, so every cell, the ring and
    // the scan's steps land on whole device pixels at 1x, 2x and 3x.
    canvas.save();
    canvas.scale(1 / dpr);
    final scale = size.shortestSide / _kMagnifierRefSize;
    final u = math.max(1, (_kLensCell * scale * dpr).round()).toDouble();
    final w = math.max(2, (_kLensRing * scale * dpr).round()).toDouble();
    final inner = 6 * u;
    final outer = inner + w;
    final ringR = inner + w / 2;
    final tip = _kHandleReach * outer;

    final t = still ? 0.0 : ms;
    final scan = _magnifierScan(t);
    final look = scan < -0.75 ? 2 : (scan < -0.3 ? 1 : 0);
    final blink = still ? 0.0 : kuteBlink(t, _kMagnifierBlinkAt);
    // A flick of his tall ear as the scan sets off and after the blink,
    // and his small ear perking as the glass swings right: a cell each.
    final earDip = kutePulse(t, 380, 560) > 0.5 || kutePulse(t, 1780, 1940) > 0.5;
    final earPerk = kutePulse(t, 980, 1180) > 0.5;

    // The glyph (lens, handle and the ears above) centred in the square,
    // then moved by the scan, all on whole device pixels.
    final reach = tip / math.sqrt2;
    final glyph = outer + reach;
    final shift = (scan * _kScanReach * scale * dpr).roundToDouble();
    final c = Offset(
      ((size.width * dpr - glyph) / 2 + outer).roundToDouble() + shift,
      ((size.height * dpr - glyph) / 2 + outer).roundToDouble() + u,
    );
    Offset rim(double deg) {
      final a = deg * math.pi / 180;
      return c + Offset(math.cos(a), math.sin(a)) * ringR;
    }

    Rect snapped(double l, double t, double r, double b) => Rect.fromLTRB(
        l.roundToDouble(), t.roundToDouble(), r.roundToDouble(), b.roundToDouble());

    // His ears behind the rim, so the ring cuts across their roots: the
    // small square one at ten o'clock, the tall one at one o'clock.
    final ears = Paint()
      ..color = palette.furDark
      ..isAntiAlias = false;
    final l = rim(-138);
    final lTop = l.dy - 2 * u - (earPerk ? u : 0);
    canvas.drawRect(snapped(l.dx - 2 * u, lTop, l.dx + u, l.dy + u), ears);
    final r = rim(-58);
    final rTop = r.dy - 3.5 * u + (earDip ? u : 0);
    canvas.drawRect(snapped(r.dx - u, rTop, r.dx + 1.5 * u, r.dy + 0.5 * u), ears);

    // His face, clipped half a ring out so no hairline of the background
    // shows between it and the ring.
    canvas.save();
    canvas.clipPath(Path()
      ..addOval(Rect.fromCircle(center: c, radius: inner + w / 2)));
    final rows = _lensFace(look: look, blink: blink);
    final o = c - Offset(inner, inner);
    for (var y = 0; y < rows.length; y++) {
      final row = rows[y];
      var x = 0;
      while (x < row.length) {
        final ch = row[x];
        var end = x + 1;
        while (end < row.length && row[end] == ch) {
          end++;
        }
        final color = _lensColor(ch, palette);
        if (color != null) {
          canvas.drawRect(
            Rect.fromLTWH(o.dx + x * u, o.dy + y * u, (end - x) * u, u),
            Paint()
              ..color = color
              ..isAntiAlias = false,
          );
        }
        x = end;
      }
    }
    canvas.restore();

    // The ring, and the handle down and right with a round tip.
    final pen = Paint()
      ..color = lens
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawCircle(c, ringR, pen);
    const d = Offset(math.sqrt1_2, math.sqrt1_2);
    canvas.drawLine(c + d * ringR, c + d * (tip - w / 2), pen);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MagnifierPainter old) =>
      old.ms != ms ||
      old.still != still ||
      old.lens != lens ||
      old.dpr != dpr ||
      old.palette != palette;
}

/// The dock's search-or-ask-Sal glyph: a magnifying glass whose lens is
/// Sal's face, his two ears standing up behind the rim, so the silhouette
/// says "search" and "dog" at once. The ring and handle wear the theme's
/// foreground, so it reads in light and dark alike.
///
/// Motion is a short beat, not a loop ([_kMagnifierMs]): the glass scans
/// a couple of pixels left and right and back with his eyes following
/// it, an ear flicks, and he blinks, when the glyph appears and then once
/// every [interval]. Nothing ticks in between. It holds still while the
/// app is in the background, while another route covers this one, while
/// its tickers are off (a shell tab out of view), and for good under
/// Reduce Motion, where the rest frame is all there is.
///
/// Every cell, the ring and each step of the scan are whole device
/// pixels, so he stays sharp at 1x, 2x and 3x.
class KuteDogMagnifier extends StatefulWidget {
  /// Edge length of the glyph's square in logical pixels.
  final double size;

  /// Ring and handle colour; the theme's foreground at the call site.
  final Color lensColor;

  /// Rest between plays.
  final Duration interval;

  const KuteDogMagnifier({
    super.key,
    required this.size,
    required this.lensColor,
    this.interval = const Duration(seconds: 7),
  });

  @override
  State<KuteDogMagnifier> createState() => _KuteDogMagnifierState();
}

class _KuteDogMagnifierState extends _KuteDogBeatState<KuteDogMagnifier> {
  @override
  int get playMs => _kMagnifierMs;

  @override
  Duration get firstDelay => Duration.zero;

  @override
  Duration get rest => widget.interval;

  @override
  bool get pauseWithTickerMode => true;

  @override
  Widget build(BuildContext context) {
    final palette = KuteDogPalette.of(context);
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final size = Size.square(widget.size);

    _MagnifierPainter painter(double ms, bool still) => _MagnifierPainter(
          ms: ms,
          still: still,
          palette: palette,
          lens: widget.lensColor,
          dpr: dpr,
        );

    if (still) return CustomPaint(size: size, painter: painter(0, true));
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => CustomPaint(
          size: size,
          painter: painter(
              controller.value * _kMagnifierMs, !controller.isAnimating),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Bitcoin: Sal holding a coin, and tossing it now and then
// ─────────────────────────────────────────────────────────────────────

/// One play: the toss, the catch and a blink.
const double _kBitcoinMs = 1500;

/// The coin is in the air over this long.
const double _kTossMs = 1050;

/// How high the coin goes, in rig units.
const double _kTossHeight = 5.0;

/// The coin's centre at rest, held up at his side by his paw (over the
/// bandana's knot), in rig units.
const double _kCoinX = 13.0;
const double _kCoinY = 10.8;

/// The coin, 7 rig units across: rows of a pixel disc, each centred.
const List<int> _kCoinRows = [3, 5, 7, 7, 7, 5, 3];

/// The ₿ in the coin's face: a 3x5 pixel B (columns 0..2), with the two
/// strokes through its top and bottom that make it bitcoin's.
const List<String> _kCoinB = ['XX.', 'X.X', 'XX.', 'X.X', 'XX.'];

/// Bitcoin's orange, the coin's face.
const Color _kCoinFace = Color(0xFFF7931A);

/// The coin's rim, a step darker than his fur so it reads over his chest.
const Color _kCoinRim = Color(0xFFA85A06);

double _tossLift(double ms) {
  if (ms <= 0 || ms >= _kTossMs) return 0;
  return math.sin(math.pi * ms / _kTossMs);
}

KuteDogPose _bitcoinPose(double ms) {
  final up = _tossLift(ms);
  final land = kutePulse(ms, _kTossMs - 40, _kTossMs + 220);
  return KuteDogPose(
    // He watches it go up and come down, ears up, then a little bob as
    // he catches it.
    lookY: (-1.0 * up).roundToDouble(),
    headBob: -0.25 * up + 0.2 * land,
    squash: 1 - 0.035 * land,
    earLeft: -0.12 * up,
    earRight: -0.16 * up,
    tongue: 0.3 * kutePulse(ms, _kTossMs, _kBitcoinMs),
    blink: kuteBlink(ms, 1300),
  );
}

void _paintCoin(Canvas canvas, Offset centre, double u, double spin) {
  // Spin: the face narrows to its edge and back; a coin on its edge is a
  // line of rim.
  final width = spin.abs();
  canvas.save();
  canvas.translate(centre.dx, centre.dy);
  canvas.scale(math.max(width, 0.16), 1);
  canvas.translate(-centre.dx, -centre.dy);
  final rim = Paint()..color = _kCoinRim;
  final face = Paint()..color = _kCoinFace;
  final white = Paint()..color = Colors.white;
  final top = centre.dy - _kCoinRows.length / 2 * u;
  for (var r = 0; r < _kCoinRows.length; r++) {
    final w = _kCoinRows[r];
    canvas.drawRect(
        Rect.fromLTWH(centre.dx - w / 2 * u, top + r * u, w * u, u), rim);
  }
  // The face: the disc one unit in from the rim.
  const inner = [3, 5, 5, 5, 3];
  for (var r = 0; r < inner.length; r++) {
    final w = inner[r];
    canvas.drawRect(
        Rect.fromLTWH(centre.dx - w / 2 * u, top + (r + 1) * u, w * u, u),
        face);
  }
  if (width > 0.45) {
    // The ₿, a pixel B centred in the face, with its two strokes.
    final left = centre.dx - 1.5 * u;
    final bTop = top + 1 * u;
    for (var r = 0; r < _kCoinB.length; r++) {
      for (var col = 0; col < 3; col++) {
        if (_kCoinB[r][col] != 'X') continue;
        canvas.drawRect(
            Rect.fromLTWH(left + col * u, bTop + r * u, u, u), white);
      }
    }
    // The strokes through the top and bottom: half-unit ticks on the rim.
    canvas.drawRect(
        Rect.fromLTWH(left + 0.5 * u, bTop - 0.5 * u, 0.5 * u, 0.5 * u),
        white);
    canvas.drawRect(
        Rect.fromLTWH(left + 0.5 * u, bTop + 5 * u, 0.5 * u, 0.5 * u), white);
  }
  canvas.restore();
}

class _BitcoinPainter extends CustomPainter {
  final double ms;
  final bool still;
  final KuteDogPalette palette;
  final double unit;
  final Offset origin;

  const _BitcoinPainter({
    required this.ms,
    required this.still,
    required this.palette,
    required this.unit,
    required this.origin,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final u = unit;
    final pose = still ? KuteDogPose.neutral : _bitcoinPose(ms);
    paintKuteDog(canvas,
        origin: origin, unit: u, pose: pose, palette: palette, withTail: false);
    final lift = still ? 0.0 : _tossLift(ms);
    // Two turns in the air, landing face on.
    final spin = still
        ? 1.0
        : math.cos(2 * math.pi * 2 * (ms / _kTossMs).clamp(0.0, 1.0));
    final centre = origin +
        Offset(_kCoinX * u, (_kCoinY - _kTossHeight * lift) * u);
    _paintCoin(canvas, centre, u, spin);
    // His paw under the coin while he holds it.
    if (lift < 0.15) {
      canvas.drawRect(
          Rect.fromLTWH(
              origin.dx + 10.0 * u, origin.dy + 12.6 * u, 2 * u, 1.2 * u),
          Paint()..color = palette.furLight);
    }
  }

  @override
  bool shouldRepaint(covariant _BitcoinPainter old) =>
      old.ms != ms ||
      old.still != still ||
      old.unit != unit ||
      old.origin != origin ||
      old.palette != palette;
}

/// Sal holding a bitcoin, for the wallet home's Bitcoin tab while it is
/// selected: a pixel coin in bitcoin's orange with a white ₿, held at his
/// chest. When the tab becomes selected, and then every [interval], he
/// tosses it up, it spins twice, he watches it and catches it, then
/// blinks ([_kBitcoinMs]). Nothing ticks between plays; still (holding
/// the coin) while covered or backgrounded, and for good under Reduce
/// Motion. At glyph size his rig pixel is a whole number of device pixels
/// on a whole-pixel origin, as the dock's glyph is.
class KuteDogBitcoin extends StatefulWidget {
  /// Edge length of the glyph's square in logical pixels.
  final double size;

  /// Rest between plays.
  final Duration interval;

  const KuteDogBitcoin({
    super.key,
    required this.size,
    this.interval = const Duration(seconds: 10),
  });

  @override
  State<KuteDogBitcoin> createState() => _KuteDogBitcoinState();
}

class _KuteDogBitcoinState extends _KuteDogBeatState<KuteDogBitcoin> {
  @override
  int get playMs => _kBitcoinMs.toInt();

  @override
  Duration get firstDelay => Duration.zero;

  @override
  Duration get rest => widget.interval;

  @override
  Widget build(BuildContext context) {
    final palette = KuteDogPalette.of(context);
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final size = Size.square(widget.size);
    // His grid and the coin's reach past it (16.7 units wide), centred.
    final unit = math.max(1, (widget.size / 16.7 * dpr).floor()) / dpr;
    double snap(double v) => (v * dpr).round() / dpr;
    final origin = Offset(snap((widget.size - 16.7 * unit) / 2),
        snap((widget.size - 16 * unit) / 2));

    _BitcoinPainter painter(double ms, bool still) => _BitcoinPainter(
        ms: ms, still: still, palette: palette, unit: unit, origin: origin);

    if (still) return CustomPaint(size: size, painter: painter(0, true));
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => CustomPaint(
          size: size,
          painter: painter(
              controller.value * _kBitcoinMs, !controller.isAnimating),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// The beat: play on appearing, rest, play again
// ─────────────────────────────────────────────────────────────────────

/// A short scene that plays when it appears and then once every [rest],
/// with nothing ticking in between (no frames, only one timer). It holds
/// still while the app is in the background, while another route covers
/// this one, and for good under Reduce Motion, where the rest frame is all
/// there is. Coming back into view plays it once.
abstract class _KuteDogBeatState<T extends StatefulWidget> extends State<T>
    with SingleTickerProviderStateMixin<T>, WidgetsBindingObserver {
  /// One play, in milliseconds.
  int get playMs;

  /// The wait before the first play.
  Duration get firstDelay;

  /// The rest after each play; asked afresh each time.
  Duration get rest;

  /// Whether to hold still (rest frame, no timer) while an ancestor
  /// [TickerMode] turns tickers off, as a shell tab out of view does.
  bool get pauseWithTickerMode => false;

  late final AnimationController controller;
  Timer? _next;
  bool _reduce = false;
  bool _covered = false;
  bool _tickerOff = false;
  bool _foreground = true;
  bool _played = false;

  /// Whether to draw the rest frame without a controller at all.
  bool get still => _reduce;

  bool get _halted => _reduce || _covered || _tickerOff || !_foreground;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
        vsync: this, duration: Duration(milliseconds: playMs))
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _schedule(rest);
      });
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _covered = !(ModalRoute.isCurrentOf(context) ?? true);
    _tickerOff = pauseWithTickerMode && !TickerMode.valuesOf(context).enabled;
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  /// Plays on appearing (and on coming back into view), rests otherwise.
  void _sync() {
    if (_halted) {
      _next?.cancel();
      _next = null;
      if (controller.isAnimating) controller.stop();
      controller.value = 0;
      return;
    }
    if (controller.isAnimating || _next != null) return;
    if (_played) {
      controller.forward(from: 0);
    } else {
      _played = true;
      _schedule(firstDelay);
    }
  }

  void _schedule(Duration wait) {
    _next?.cancel();
    if (wait == Duration.zero) {
      _next = null;
      if (!_halted) controller.forward(from: 0);
      return;
    }
    _next = Timer(wait, () {
      _next = null;
      if (!mounted || _halted) return;
      controller.forward(from: 0);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _next?.cancel();
    controller.dispose();
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────
// Glance: Sal at glyph size, for the Ask Sal entry points
// ─────────────────────────────────────────────────────────────────────

/// One play of the glance: eyes across and back with a little head tilt
/// and an ear flick, then a blink.
const int kKuteDogGlanceMs = 1200;

KuteDogPose kuteDogGlancePose(double ms) {
  final look = kutePulse(ms, 0, 900);
  return KuteDogPose(
    // Whole rig pixels: at glyph size a pupil between pixels is a smudge.
    lookX: (-1.6 * look).roundToDouble(),
    headTilt: 0.10 * look,
    earLeft: 0.10 * look,
    earRight: -0.24 * kutePulse(ms, 260, 540),
    blink: kuteBlink(ms, 960),
  );
}

class _GlancePainter extends CustomPainter {
  final double ms;
  final bool still;
  final KuteDogPalette palette;
  final double unit;
  final Offset origin;

  const _GlancePainter({
    required this.ms,
    required this.still,
    required this.palette,
    required this.unit,
    required this.origin,
  });

  @override
  void paint(Canvas canvas, Size size) {
    paintKuteDog(
      canvas,
      origin: origin,
      unit: unit,
      pose: still ? KuteDogPose.neutral : kuteDogGlancePose(ms),
      palette: palette,
      withTail: false,
    );
  }

  @override
  bool shouldRepaint(covariant _GlancePainter old) =>
      old.ms != ms ||
      old.still != still ||
      old.unit != unit ||
      old.origin != origin ||
      old.palette != palette;
}

/// Sal at glyph size, the face of every Ask Sal entry point (the round
/// buttons, the market header capsule, the question capsule). At rest he
/// is exactly `kute_dog.svg`; he glances across with a little head tilt
/// and blinks ([kKuteDogGlanceMs]) when he appears, after a small random
/// beat so two on one screen never move together, and then once every
/// [interval] give or take [jitter]. Nothing ticks between plays; still
/// while covered or backgrounded, and for good under Reduce Motion.
///
/// His rig pixel is a whole number of device pixels and his square sits on
/// whole device pixels inside the box, so he stays sharp at 1x, 2x and 3x.
class KuteDogGlance extends StatefulWidget {
  /// Edge length of the glyph's square in logical pixels.
  final double size;

  /// Typical rest between plays.
  final Duration interval;

  /// How far each rest may stray either side of [interval].
  final Duration jitter;

  /// The longest random wait before the first play.
  final Duration firstDelayMax;

  const KuteDogGlance({
    super.key,
    required this.size,
    this.interval = const Duration(seconds: 7),
    this.jitter = const Duration(seconds: 1),
    this.firstDelayMax = const Duration(milliseconds: 600),
  });

  @override
  State<KuteDogGlance> createState() => _KuteDogGlanceState();
}

final math.Random _beatRandom = math.Random();

Duration _randomUpTo(Duration max) => max <= Duration.zero
    ? Duration.zero
    : Duration(microseconds: _beatRandom.nextInt(max.inMicroseconds + 1));

class _KuteDogGlanceState extends _KuteDogBeatState<KuteDogGlance> {
  @override
  int get playMs => kKuteDogGlanceMs;

  @override
  Duration get firstDelay => _randomUpTo(widget.firstDelayMax);

  @override
  Duration get rest =>
      widget.interval - widget.jitter + _randomUpTo(widget.jitter * 2);

  @override
  Widget build(BuildContext context) {
    final palette = KuteDogPalette.of(context);
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final size = Size.square(widget.size);
    final unit = math.max(1, (widget.size / 16 * dpr).floor()) / dpr;
    final inset = ((widget.size - 16 * unit) / 2 * dpr).round() / dpr;
    final origin = Offset(inset, inset);

    _GlancePainter painter(double ms, bool still) => _GlancePainter(
        ms: ms, still: still, palette: palette, unit: unit, origin: origin);

    if (still) return CustomPaint(size: size, painter: painter(0, true));
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => CustomPaint(
          size: size,
          painter: painter(
              controller.value * kKuteDogGlanceMs, !controller.isAnimating),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Sal's AI mark: a gradient ring and a sparkle around his circle
// ─────────────────────────────────────────────────────────────────────

/// One play of the mark: the ring's sweep turns once, the sparkle
/// twinkles at its start.
const int kSalAiRingMs = 1600;

/// The sparkle's twinkle, at the start of a play.
const double _kTwinkleMs = 700;

class _SalAiRingPainter extends CustomPainter {
  final double ms;
  final bool still;
  final List<Color> hues;
  final double stroke;
  final double sparkle;
  final double opacity;

  const _SalAiRingPainter({
    required this.ms,
    required this.still,
    required this.hues,
    required this.stroke,
    required this.sparkle,
    required this.opacity,
  });

  /// A four-point star (✦) of outer radius [r] at [c].
  static Path _star(Offset c, double r) {
    final inner = r * 0.30;
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final a = -math.pi / 2 + i * math.pi / 4;
      final d = i.isEven ? r : inner;
      final p = c + Offset(math.cos(a) * d, math.sin(a) * d);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - stroke / 2;
    final t = still ? 0.0 : (ms / kSalAiRingMs).clamp(0.0, 1.0);
    // One slow turn, eased in and out, from where it rests.
    final turn = Curves.easeInOutCubic.transform(t) * 2 * math.pi;
    final colors = [
      for (final h in [...hues, hues.first]) h.withValues(alpha: opacity),
    ];
    final rect = Rect.fromCircle(center: centre, radius: radius);
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..isAntiAlias = true
        ..shader = SweepGradient(
          colors: colors,
          transform: GradientRotation(-math.pi / 4 + turn),
        ).createShader(rect),
    );

    // The sparkle sits on the ring at the top right; it swells, turns
    // a quarter and settles once per play, a second small one blinking
    // beside it.
    final tw = still ? 0.0 : kutePulse(ms, 0, _kTwinkleMs);
    final at = centre + Offset(radius * 0.74, -radius * 0.74);
    final r = sparkle * (1 + 0.45 * tw);
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(math.pi / 4 * tw);
    canvas.translate(-at.dx, -at.dy);
    canvas.drawPath(
        _star(at, r), Paint()..color = hues.first.withValues(alpha: opacity));
    canvas.restore();
    final small = kutePulse(ms, 180, _kTwinkleMs + 120);
    if (!still && small > 0) {
      canvas.drawPath(
        _star(at + Offset(-sparkle * 1.5, -sparkle * 0.9), sparkle * 0.5 * small),
        Paint()
          ..color = hues[1 % hues.length].withValues(alpha: opacity * small),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SalAiRingPainter old) =>
      old.ms != ms ||
      old.still != still ||
      old.stroke != stroke ||
      old.sparkle != sparkle ||
      old.opacity != opacity ||
      !listEquals(old.hues, hues);
}

/// Sal's "AI" mark around his round dog: a thin ring in a soft sweep of
/// [hues] (the chart palette's violet, cyan and pink at the call sites)
/// and a small vector sparkle (✦) on it at the top right. The ring turns
/// once and the sparkle twinkles ([kSalAiRingMs]) when it appears, after
/// a small random beat, and then once every [interval] give or take
/// [jitter]; nothing ticks in between. Still while covered or
/// backgrounded, and for good under Reduce Motion (the ring and sparkle
/// at rest). Paint only: [child]'s size, tap target and semantics are its
/// own; the sparkle may reach a little past the box.
class SalAiRing extends StatefulWidget {
  final Widget child;

  /// Colours of the ring's sweep, the first also the sparkle's.
  final List<Color> hues;

  /// Ring width in logical px.
  final double stroke;

  /// The sparkle's outer radius in logical px.
  final double sparkle;

  /// How strongly the ring and sparkle show, 0 to 1.
  final double opacity;

  final Duration interval;
  final Duration jitter;
  final Duration firstDelayMax;

  const SalAiRing({
    super.key,
    required this.child,
    required this.hues,
    this.stroke = 1.5,
    this.sparkle = 4.5,
    this.opacity = 0.9,
    this.interval = const Duration(seconds: 7),
    this.jitter = const Duration(seconds: 1),
    this.firstDelayMax = const Duration(milliseconds: 600),
  });

  @override
  State<SalAiRing> createState() => _SalAiRingState();
}

class _SalAiRingState extends _KuteDogBeatState<SalAiRing> {
  @override
  int get playMs => kSalAiRingMs;

  @override
  Duration get firstDelay => _randomUpTo(widget.firstDelayMax);

  @override
  Duration get rest =>
      widget.interval - widget.jitter + _randomUpTo(widget.jitter * 2);

  _SalAiRingPainter _painter(double ms, bool still) => _SalAiRingPainter(
        ms: ms,
        still: still,
        hues: widget.hues,
        stroke: widget.stroke,
        sparkle: widget.sparkle,
        opacity: widget.opacity,
      );

  @override
  Widget build(BuildContext context) {
    if (still) {
      return CustomPaint(
          foregroundPainter: _painter(0, true), child: widget.child);
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) => CustomPaint(
        foregroundPainter: _painter(
            controller.value * kSalAiRingMs, !controller.isAnimating),
        child: child,
      ),
      child: RepaintBoundary(child: widget.child),
    );
  }
}
