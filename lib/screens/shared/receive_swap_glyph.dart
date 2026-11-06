// lib/screens/shared/receive_swap_glyph.dart
import 'package:flutter/material.dart';

/// The Receive button's glyph on the Bitcoin and Dollars action rows
/// (founder, 6 November 2026): the receive arrow (↙, the row's
/// `Icons.south_west_rounded` drawn again) with a small solid swap badge
/// (⇄) at its lower right, because the sheet behind the button is "Receive
/// or swap": money in from another wallet, or moved in from your own other
/// balance. The label stays "Receive". Built like the hub's "+ with a
/// gear" ([HubPlusGearGlyph]): one glyph for two jobs, on the 24-unit grid
/// of the app's rounded icons, the arrow in the icons' 2-unit stroke, the
/// badge a solid disc with the two arrows knocked out, in a cut-out ring
/// (cleared, not filled, so the square's own colour shows through in light
/// and dark). Takes [color] straight from the theme and is sized like an
/// [Icon]. Still: no motion.
class ReceiveSwapGlyph extends StatelessWidget {
  const ReceiveSwapGlyph({super.key, required this.color, this.size = 24});

  final Color color;
  final double size;

  /// Sized and centred as an [Icon] is: a box [size] square (or the
  /// space a tight parent gives), the glyph [size] square in its centre.
  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: Center(
          child: CustomPaint(
              size: Size.square(size),
              painter: ReceiveSwapGlyphPainter(color)),
        ),
      );
}

/// [ReceiveSwapGlyph] as a [KuteDockAction.glyph].
Widget receiveSwapGlyph(Color color, double size) =>
    ReceiveSwapGlyph(color: color, size: size);

class ReceiveSwapGlyphPainter extends CustomPainter {
  const ReceiveSwapGlyphPainter(this.color);

  final Color color;

  // On the 24-unit grid. The arrow: its corner at (5, 15.5), the arms 6.8
  // up and right, the shaft to (16, 4.5), 2-unit strokes with round ends
  // (the rounded icon's own), up and left of the icon's place so the
  // badge has the lower right. The badge: a disc about (19, 19), radius 5,
  // in a 1.5 cut-out ring that stays clear of the arrow; knocked out of
  // it, two 1.3-unit lines, the upper pointing right and the lower left,
  // each with a half head.
  static const double _cornerX = 5, _cornerY = 15.5;
  static const double _arm = 6.8;
  static const double _shaftX = 16, _shaftY = 4.5;
  static const double _stroke = 2;
  static const Offset _disc = Offset(19, 19);
  static const double _radius = 5;
  static const double _gap = 1.5;
  static const double _swapLeft = 16.1, _swapRight = 21.9;
  static const double _swapTop = 17.6, _swapBottom = 20.4;
  static const double _head = 1.9;
  static const double _swapStroke = 1.3;

  /// The arrow (↙), in grid units.
  static Path arrowPath() => Path()
    ..moveTo(_cornerX, _cornerY - _arm)
    ..lineTo(_cornerX, _cornerY)
    ..lineTo(_cornerX + _arm, _cornerY)
    ..moveTo(_cornerX, _cornerY)
    ..lineTo(_shaftX, _shaftY);

  /// The swap (⇄) knocked out of the badge, in grid units.
  static Path swapPath() => Path()
    // Upper line, pointing right, its half head above.
    ..moveTo(_swapLeft, _swapTop)
    ..lineTo(_swapRight, _swapTop)
    ..lineTo(_swapRight - _head, _swapTop - _head)
    // Lower line, pointing left, its half head below.
    ..moveTo(_swapRight, _swapBottom)
    ..lineTo(_swapLeft, _swapBottom)
    ..lineTo(_swapLeft + _head, _swapBottom + _head);

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    canvas.save();
    canvas.translate((size.width - side) / 2, (size.height - side) / 2);
    canvas.scale(side / 24);
    // A layer, so the badge's ring and its arrows clear to the square.
    canvas.saveLayer(const Rect.fromLTWH(-1, -1, 26, 26), Paint());
    Paint pen(double width) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    final clear = Paint()..blendMode = BlendMode.clear;
    canvas.drawPath(arrowPath(), pen(_stroke));
    canvas.drawCircle(_disc, _radius + _gap, clear);
    canvas.drawCircle(
        _disc,
        _radius,
        Paint()
          ..color = color
          ..isAntiAlias = true);
    canvas.drawPath(swapPath(), pen(_swapStroke)..blendMode = BlendMode.clear);
    canvas.restore(); // layer
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ReceiveSwapGlyphPainter old) =>
      old.color != color;
}
