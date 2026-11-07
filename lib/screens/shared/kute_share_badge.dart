// lib/screens/shared/kute_share_badge.dart
//
// THE SHARE BADGE (founder, 5 November 2026, on the round share button's
// 3D clip: "this button share still not clear, kinda hides behind Sal"):
// share is said by a crisp vector badge over the button's bottom right,
// like an app badge, and Sal's own face sits whole inside the circle.
//
//   * [KuteShareBadge]: a solid ink disc ([kShareBadgeInk], #1D2024)
//     [kShareBadgeDisc] across inside a [kShareBadgeRing] ring of the
//     button's own white, so it cuts cleanly out of the circle and Sal,
//     and outlines it on the dark page; [kShareBadgeSize] in all;
//   * [KuteShareGlyphPainter]: the iOS share symbol drawn in code, a
//     rounded tray open at the top (two short stubs) and an up arrow, round
//     caps, in white; [lift] raises the arrow out of the tray (0..1, at most
//     7% of the disc), repainting without a rebuild;
//   * [kuteShareBadgeLift]: the lift on Sal's beat, a tiny up-bob as he
//     blinks in his `idle` clip (frames 36-42 of 48); nothing on any other
//     clip, and nothing under Reduce Motion (he holds frame 0 there).

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kute/screens/shared/sal_sprite.dart' show SalSpriteFrame;

/// The badge's disc colour: Kute's ink, in both modes (the button it sits
/// on is white in both).
const Color kShareBadgeInk = Color(0xFF1D2024);

/// The ink disc's side.
const double kShareBadgeDisc = 22;

/// The ring around the disc, in the button's white.
const double kShareBadgeRing = 2;

/// The badge's side, ring included.
const double kShareBadgeSize = kShareBadgeDisc + 2 * kShareBadgeRing;

/// The Sal clip the badge's arrow keeps time with, and the frames (1-based,
/// exclusive) of his blink in it (body_clips.py, pose_idle_edgy: the slow
/// blink over frames 35-43, shut at 39).
const String kShareBadgeBeatClip = 'idle';
const int _kBlinkFrom = 35;
const int _kBlinkTo = 43;

/// How far the arrow is up out of the tray on [frame]: 0 at rest, 1 as
/// Sal's lids close on his blink, eased both ways.
double kuteShareBadgeLift(SalSpriteFrame frame) {
  if (frame.name != kShareBadgeBeatClip || frame.dissolving) return 0;
  final f = frame.frame + 1;
  if (f <= _kBlinkFrom || f >= _kBlinkTo) return 0;
  const mid = (_kBlinkFrom + _kBlinkTo) / 2;
  final t = f <= mid
      ? (f - _kBlinkFrom) / (mid - _kBlinkFrom)
      : (_kBlinkTo - f) / (_kBlinkTo - mid);
  return t * t * (3 - 2 * t);
}

/// The share badge (see the file header): the ink disc in its white ring,
/// the white share glyph on it, the arrow raised by [lift].
class KuteShareBadge extends StatelessWidget {
  const KuteShareBadge({
    super.key,
    this.lift,
    this.ringColor = const Color(0xFFFFFFFF),
  });

  final ValueListenable<double>? lift;
  final Color ringColor;

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('kute-share-badge'),
        width: kShareBadgeSize,
        height: kShareBadgeSize,
        padding: const EdgeInsets.all(kShareBadgeRing),
        decoration: BoxDecoration(color: ringColor, shape: BoxShape.circle),
        child: DecoratedBox(
          decoration: const BoxDecoration(
              color: kShareBadgeInk, shape: BoxShape.circle),
          child: CustomPaint(
            size: const Size.square(kShareBadgeDisc),
            painter: KuteShareGlyphPainter(
                color: const Color(0xFFFFFFFF), lift: lift),
          ),
        ),
      );
}

/// The iOS share symbol in [color], centred in the paint area and sized
/// to it (the glyph is 58% of the side tall, its strokes 8.2%; the arrow
/// stands well clear of the tray, as Apple's does); the arrow up by
/// [lift] × 7% of the side.
class KuteShareGlyphPainter extends CustomPainter {
  KuteShareGlyphPainter({required this.color, this.lift})
      : super(repaint: lift);

  final Color color;
  final ValueListenable<double>? lift;

  @override
  void paint(Canvas canvas, Size size) {
    final d = math.min(size.width, size.height);
    final c = size.center(Offset.zero);
    final sw = 0.082 * d;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    // The tray: its stroke's centre line, open across the middle of its top.
    final half = 0.24 * d;
    final r = 0.075 * d;
    final bottom = c.dy + 0.27 * d - sw / 2;
    final top = bottom - 0.26 * d;
    final gap = 0.13 * d;
    final tray = Path()
      ..moveTo(c.dx - gap, top)
      ..lineTo(c.dx - half + r, top)
      ..arcToPoint(Offset(c.dx - half, top + r),
          radius: Radius.circular(r), clockwise: false)
      ..lineTo(c.dx - half, bottom - r)
      ..arcToPoint(Offset(c.dx - half + r, bottom),
          radius: Radius.circular(r), clockwise: false)
      ..lineTo(c.dx + half - r, bottom)
      ..arcToPoint(Offset(c.dx + half, bottom - r),
          radius: Radius.circular(r), clockwise: false)
      ..lineTo(c.dx + half, top + r)
      ..arcToPoint(Offset(c.dx + half - r, top),
          radius: Radius.circular(r), clockwise: false)
      ..lineTo(c.dx + gap, top);
    canvas.drawPath(tray, paint);

    // The arrow: a shaft from inside the tray to the tip, a 45° chevron.
    final up = (lift?.value ?? 0).clamp(0.0, 1.0) * 0.07 * d;
    final tip = c.dy - 0.31 * d + sw / 2 - up;
    final foot = top + 0.45 * (bottom - top) - up;
    final arm = 0.17 * d / math.sqrt2;
    final arrow = Path()
      ..moveTo(c.dx, foot)
      ..lineTo(c.dx, tip)
      ..moveTo(c.dx - arm, tip + arm)
      ..lineTo(c.dx, tip)
      ..lineTo(c.dx + arm, tip + arm);
    canvas.drawPath(arrow, paint);
  }

  @override
  bool shouldRepaint(covariant KuteShareGlyphPainter old) =>
      old.color != color || old.lift != lift;
}
