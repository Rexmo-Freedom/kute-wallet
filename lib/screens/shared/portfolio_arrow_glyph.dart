// lib/screens/shared/portfolio_arrow_glyph.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The Investments hero's tap affordance, built like the hub's "+ gear"
/// glyph ([HubPlusGearGlyph]) in the top bar: a thick rounded arrow to the
/// right (open) with a small solid pie badge over its lower right (the
/// Portfolio), the pie in a cut-out ring so the two shapes stay apart
/// (founder decision October 2026). On the 24-unit grid of the app's
/// rounded icons; the cut-out is cleared rather than filled, so whatever
/// sits beneath shows through in light and dark.
///
/// Motion is the hub's short beat, not a loop: when it appears and then
/// once every [interval], the two swap prominence: the pie grows in
/// towards the centre, turning, as the arrow shrinks back to the top
/// left; a hold; then they swap back (the pie turning on round to where
/// it began). Each press ([pressed]) plays a quick swap. Nothing ticks in
/// between. No new play starts while another route covers this one (one
/// in flight finishes; coming back into view plays once), and it holds
/// still while the app is in the background, while its tickers are off,
/// and for good under Reduce Motion.
class PortfolioArrowGlyph extends StatefulWidget {
  const PortfolioArrowGlyph({
    super.key,
    required this.color,
    required this.size,
    this.pressed,
    this.interval = const Duration(seconds: 9),
  });

  final Color color;
  final double size;

  /// Notifies on each press of the block around the glyph.
  final Listenable? pressed;

  /// Rest between plays.
  final Duration interval;

  @override
  State<PortfolioArrowGlyph> createState() => _PortfolioArrowGlyphState();
}

/// One play of the swap, the hub's timings: the swap in ends at
/// [_kInEnd], the swap back starts at [_kOutStart], as fractions of the
/// play.
const int _kBeatMs = 1700;
const double _kInEnd = 650 / 1700;
const double _kOutStart = 1050 / 1700;

/// A press: the same swap, quickly.
const int _kPressMs = 500;
const double _kPressInEnd = 190 / 500;
const double _kPressOutStart = 280 / 500;

/// How prominent the pie is at [v] (0..1 through a play): 0 at rest, 1
/// while held, eased in and out between.
double portfolioGlyphSwap(double v, {bool press = false}) {
  final inEnd = press ? _kPressInEnd : _kInEnd;
  final outStart = press ? _kPressOutStart : _kOutStart;
  if (v <= 0 || v >= 1) return 0;
  if (v < inEnd) return Curves.easeInOut.transform(v / inEnd);
  if (v <= outStart) return 1;
  return 1 - Curves.easeInOut.transform((v - outStart) / (1 - outStart));
}

/// The pie's turn at [v], in half turns: one on the way in, one on the
/// way back, so it ends where it began.
double portfolioGlyphTurn(double v, {bool press = false}) {
  final inEnd = press ? _kPressInEnd : _kInEnd;
  final outStart = press ? _kPressOutStart : _kOutStart;
  if (v <= 0 || v >= 1) return 0;
  if (v < inEnd) return Curves.easeInOut.transform(v / inEnd);
  if (v <= outStart) return 1;
  return 1 + Curves.easeInOut.transform((v - outStart) / (1 - outStart));
}

class _PortfolioArrowGlyphState extends State<PortfolioArrowGlyph>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  Timer? _next;
  bool _reduce = false;
  bool _tickerOff = false;
  bool _covered = false;
  bool _foreground = true;

  /// Whether the play in flight is a press (quick).
  bool _press = false;

  bool get _halted => _reduce || _tickerOff || !_foreground;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: _kBeatMs))
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && !_covered && !_halted) {
          _schedule(widget.interval);
        }
      });
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    widget.pressed?.addListener(_onPressed);
  }

  @override
  void didUpdateWidget(PortfolioArrowGlyph old) {
    super.didUpdateWidget(old);
    if (old.pressed != widget.pressed) {
      old.pressed?.removeListener(_onPressed);
      widget.pressed?.addListener(_onPressed);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _tickerOff = !TickerMode.valuesOf(context).enabled;
    _covered = !(ModalRoute.isCurrentOf(context) ?? true);
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
      _cancel();
      if (_controller.isAnimating) _controller.stop();
      _controller.value = 0;
      return;
    }
    if (_covered) {
      _cancel();
      return;
    }
    if (_controller.isAnimating || _next != null) return;
    _play(press: false);
  }

  void _onPressed() {
    if (_halted || _controller.isAnimating) return;
    _cancel();
    _play(press: true);
  }

  void _play({required bool press}) {
    _press = press;
    _controller.duration = Duration(milliseconds: press ? _kPressMs : _kBeatMs);
    _controller.forward(from: 0);
  }

  void _schedule(Duration wait) {
    _cancel();
    _next = Timer(wait, () {
      _next = null;
      if (!mounted || _halted || _covered) return;
      _play(press: false);
    });
  }

  void _cancel() {
    _next?.cancel();
    _next = null;
  }

  @override
  void dispose() {
    widget.pressed?.removeListener(_onPressed);
    WidgetsBinding.instance.removeObserver(this);
    _cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final size = Size.square(widget.size);
    if (_reduce) {
      return CustomPaint(
          size: size, painter: PortfolioGlyphPainter(widget.color, dpr));
    }
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final v = _controller.isAnimating ? _controller.value : 0.0;
          return CustomPaint(
            size: size,
            painter: PortfolioGlyphPainter(widget.color, dpr,
                swap: portfolioGlyphSwap(v, press: _press),
                turn: portfolioGlyphTurn(v, press: _press)),
          );
        },
      ),
    );
  }
}

/// Paints the arrow and the pie badge. Public so a test can read the
/// frame it is asked for.
class PortfolioGlyphPainter extends CustomPainter {
  const PortfolioGlyphPainter(this.color, this.dpr,
      {this.swap = 0, this.turn = 0});

  final Color color;
  final double dpr;

  /// How prominent the pie is: 0 the rest frame (big arrow, pie badge),
  /// 1 the swap held (big pie, small arrow at the top left).
  final double swap;

  /// How many half turns the pie has made.
  final double turn;

  // On the 24-unit grid, at rest: the arrow's tip at (13.5, 10), its arms
  // reaching 5.8 back and up/down, 2.4-unit strokes (clear of the pie's
  // cut-out, so the arrow stays whole); the pie badge about
  // (18.5, 18.5), radius 5.2, in its cut-out. Held: the arrow's tip at
  // (5.5, 4.5) with 2.4-unit arms and 1.6-unit strokes, and the pie about
  // (13.5, 13.5) at [_pieBig] times its size, its cut-out clear of the
  // arrow, so neither covers the other.
  static const double _tipX = 13.5, _tipY = 10, _reach = 5.8;
  static const double _stroke = 2.4;
  static const double _tipXSmall = 5.5, _tipYSmall = 4.5, _reachSmall = 2.4;
  static const double _strokeSmall = 1.6;
  static const double _pie = 18.5;
  static const double _pieIn = 13.5;
  static const double _radius = 5.2;
  static const double _pieBig = 8.6 / 5.2;
  static const double _gap = 1.5;

  /// The slice pulled out of the pie (a quarter) and how far it sits off
  /// the rest, in grid units at badge size.
  static const double _slice = math.pi / 2;
  static const double _sliceOff = 0.9;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(1 / dpr);
    // Device pixels per grid unit; the grid centred in the square.
    final side = size.shortestSide * dpr;
    final k = side / 24;
    canvas.translate(((size.width * dpr - side) / 2).roundToDouble(),
        ((size.height * dpr - side) / 2).roundToDouble());

    // A layer, so the pie's cut-out clears the arrow to what is beneath.
    canvas.saveLayer(Rect.fromLTWH(-k, -k, 26 * k, 26 * k), Paint());

    double lerp(double a, double b) => a + (b - a) * swap;

    // The arrow: a rounded chevron pointing right.
    final reach = lerp(_reach, _reachSmall) * k;
    final tip =
        Offset(lerp(_tipX, _tipXSmall) * k, lerp(_tipY, _tipYSmall) * k);
    final arrow = Path()
      ..moveTo(tip.dx - reach, tip.dy - reach)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(tip.dx - reach, tip.dy + reach);
    canvas.drawPath(
        arrow,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = lerp(_stroke, _strokeSmall) * k
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true);

    // The pie in its cut-out (a fixed-width ring at every size): three
    // quarters whole and one quarter pulled out a touch, turned [turn]
    // half turns.
    final c = lerp(_pie, _pieIn) * k;
    final centre = Offset(c, c);
    final pk = k * lerp(1, _pieBig);
    final r = _radius * pk;
    canvas.drawCircle(centre, r + _sliceOff * pk + _gap * k,
        Paint()..blendMode = BlendMode.clear);
    final start = -math.pi / 2 + turn * math.pi;
    final fill = Paint()
      ..color = color
      ..isAntiAlias = true;
    final rest = Path()
      ..moveTo(centre.dx, centre.dy)
      ..arcTo(Rect.fromCircle(center: centre, radius: r), start + _slice,
          2 * math.pi - _slice, false)
      ..close();
    canvas.drawPath(rest, fill);
    final mid = start + _slice / 2;
    final off = Offset(math.cos(mid), math.sin(mid)) * (_sliceOff * pk);
    final slice = Path()
      ..moveTo(centre.dx + off.dx, centre.dy + off.dy)
      ..arcTo(Rect.fromCircle(center: centre + off, radius: r), start, _slice,
          false)
      ..close();
    canvas.drawPath(slice, fill);

    canvas.restore(); // layer
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant PortfolioGlyphPainter old) =>
      old.color != color ||
      old.dpr != dpr ||
      old.swap != swap ||
      old.turn != turn;
}
