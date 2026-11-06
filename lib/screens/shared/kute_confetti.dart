// lib/screens/shared/kute_confetti.dart
//
// A short confetti burst (founder, 6 November 2026: "use confetti", for a
// balance milestone). In house, no package: one AnimationController and
// one CustomPainter over a fixed set of pieces, so a burst costs one
// repaint a frame inside its own repaint boundary and nothing around it
// rebuilds.
//
//   * 1.8 s, once per [KuteConfettiBurst.cue]: about forty small pieces
//     (strips and dots) thrown up from [origin] in a fan, falling back on
//     gravity with a little drag, turning as they go, fading out over the
//     last third;
//   * the app's palette only: the bitcoin orange (AppColors.accent), the
//     market green, and white (a light neutral on a light surface, where
//     white would not show);
//   * deterministic: the pieces come from a fixed seed, so a burst looks
//     the same every time and a golden test is stable;
//   * Reduce Motion: nothing at all (helpers/accessibility.dart: confetti
//     is suppressed entirely). It never takes a touch (IgnorePointer).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:kute/theme/app_theme.dart';
import 'package:kute/theme/kute_motion.dart';

/// One burst's length.
const Duration kKuteConfettiDuration = Duration(milliseconds: 1800);

/// Pieces in a burst.
const int kKuteConfettiPieces = 40;

/// The burst's colours on [brightness]: orange, green, white (a light
/// neutral on light surfaces).
List<Color> kuteConfettiPalette(Brightness brightness) => [
      AppColors.accent,
      AppColors.marketUp,
      brightness == Brightness.dark ? Colors.white : const Color(0xFFD1D1D6),
    ];

class _Piece {
  const _Piece({
    required this.angle,
    required this.speed,
    required this.spin,
    required this.turn,
    required this.width,
    required this.height,
    required this.colorIndex,
    required this.round,
    required this.delay,
  });

  /// Launch direction (radians, 0 = right, -π/2 = straight up).
  final double angle;

  /// Launch speed, logical px a second.
  final double speed;

  /// Rotation speed, turns a second.
  final double spin;

  /// Starting rotation.
  final double turn;
  final double width;
  final double height;
  final int colorIndex;

  /// A dot, not a strip.
  final bool round;

  /// Seconds after the start this piece leaves.
  final double delay;
}

List<_Piece> _pieces(int seed) {
  final r = math.Random(seed);
  return [
    for (var i = 0; i < kKuteConfettiPieces; i++)
      _Piece(
        // A fan from 135° to 45° above the horizontal.
        angle: -math.pi * (0.25 + 0.5 * r.nextDouble()),
        speed: 560 + 440 * r.nextDouble(),
        spin: (r.nextBool() ? 1 : -1) * (0.6 + 1.6 * r.nextDouble()),
        turn: r.nextDouble(),
        width: 3 + 2.5 * r.nextDouble(),
        height: 6 + 4 * r.nextDouble(),
        colorIndex: i % 3,
        round: i % 5 == 0,
        delay: 0.12 * r.nextDouble(),
      ),
  ];
}

/// A confetti burst over its box (stack it [Positioned.fill] over the
/// part that celebrates). A new [cue] plays it again; cue 0 never plays.
class KuteConfettiBurst extends StatefulWidget {
  const KuteConfettiBurst({
    super.key,
    required this.cue,
    this.origin = const Alignment(0, 0.85),
    this.seed = 7,
  });

  /// Bumped to play; 0 is "never".
  final int cue;

  /// Where the pieces leave from, in the box.
  final Alignment origin;

  /// The pieces' seed.
  final int seed;

  @override
  State<KuteConfettiBurst> createState() => _KuteConfettiBurstState();
}

class _KuteConfettiBurstState extends State<KuteConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t =
      AnimationController(vsync: this, duration: kKuteConfettiDuration);
  late final List<_Piece> _set = _pieces(widget.seed);
  bool _reduce = false;
  int _played = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = KuteMotion.reduce(context);
    _maybePlay();
  }

  @override
  void didUpdateWidget(covariant KuteConfettiBurst old) {
    super.didUpdateWidget(old);
    _maybePlay();
  }

  void _maybePlay() {
    if (widget.cue == 0 || widget.cue == _played) return;
    _played = widget.cue;
    if (_reduce) return;
    _t.forward(from: 0);
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reduce) return const SizedBox.shrink();
    final palette = kuteConfettiPalette(Theme.of(context).brightness);
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _t,
          builder: (context, _) => _t.isAnimating
              ? CustomPaint(
                  key: const ValueKey('kute-confetti'),
                  size: Size.infinite,
                  painter: _ConfettiPainter(
                    pieces: _set,
                    t: _t.value,
                    origin: widget.origin,
                    palette: palette,
                  ),
                )
              : const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({
    required this.pieces,
    required this.t,
    required this.origin,
    required this.palette,
  });

  final List<_Piece> pieces;

  /// 0 to 1 over the burst.
  final double t;
  final Alignment origin;
  final List<Color> palette;

  static const double _gravity = 1200;
  static const double _drag = 1.4;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final start = origin.alongSize(size);
    final total = kKuteConfettiDuration.inMilliseconds / 1000;
    final paint = Paint();
    for (final p in pieces) {
      final s = t * total - p.delay;
      if (s <= 0) continue;
      // Velocity with linear drag: x = v/k (1 - e^-ks); y adds gravity.
      final decay = (1 - math.exp(-_drag * s)) / _drag;
      final vx = math.cos(p.angle) * p.speed;
      final vy = math.sin(p.angle) * p.speed;
      final x = start.dx + vx * decay;
      final y = start.dy + vy * decay + _gravity / _drag * (s - decay);
      // Fade over the last third.
      final fade = t < 0.66 ? 1.0 : (1 - (t - 0.66) / 0.34).clamp(0.0, 1.0);
      if (fade <= 0) continue;
      paint.color =
          palette[p.colorIndex % palette.length].withValues(alpha: fade);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate((p.turn + p.spin * s) * 2 * math.pi);
      if (p.round) {
        canvas.drawCircle(Offset.zero, p.width * 0.6, paint);
      } else {
        // A strip seen turning: its height breathes with the spin.
        final flip = math.cos((p.turn + p.spin * s * 1.7) * 2 * math.pi);
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(
                    center: Offset.zero,
                    width: p.width,
                    height: p.height * (0.35 + 0.65 * flip.abs())),
                const Radius.circular(1)),
            paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) =>
      old.t != t || old.origin != origin || old.palette != palette;
}
