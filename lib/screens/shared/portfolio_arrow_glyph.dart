// lib/screens/shared/portfolio_arrow_glyph.dart
import 'dart:async';

import 'package:flutter/material.dart';

/// The Investments hero's tap affordance: a rising trend arrow (it opens
/// the Portfolio, so the arrow climbs rather than pointing flat right;
/// founder decision October 2026).
///
/// Motion follows the hub's "+ gear" glyph ([HubPlusGearGlyph]): a short
/// beat, not a loop. When it appears and then once every [interval] the
/// line wipes away to the right and draws itself again from the left;
/// each press ([pressed]) plays the same, quickly. Nothing ticks in
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

/// One play: the line wipes out to the right until [_kWipeOutEnd], stays
/// gone until [_kDrawStart], then draws back in from the left. As
/// fractions of the play, the same for the beat and for a press.
const int _kBeatMs = 1400;
const int _kPressMs = 600;
const double _kWipeOutEnd = 0.36;
const double _kDrawStart = 0.44;

/// The visible span of the glyph at [v] (0..1 through a play), as left
/// and right edges in fractions of its width.
({double left, double right}) portfolioArrowSpan(double v) {
  if (v <= 0 || v >= 1) return (left: 0, right: 1);
  if (v < _kWipeOutEnd) {
    return (left: Curves.easeIn.transform(v / _kWipeOutEnd), right: 1);
  }
  if (v < _kDrawStart) return (left: 1, right: 1);
  return (
    left: 0,
    right: Curves.easeOutCubic.transform((v - _kDrawStart) / (1 - _kDrawStart)),
  );
}

class _PortfolioArrowGlyphState extends State<PortfolioArrowGlyph>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  Timer? _next;
  bool _reduce = false;
  bool _tickerOff = false;
  bool _covered = false;
  bool _foreground = true;

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
    final icon =
        Icon(Icons.trending_up_rounded, color: widget.color, size: widget.size);
    if (_reduce) return icon;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        child: icon,
        builder: (context, child) {
          final span = _controller.isAnimating
              ? portfolioArrowSpan(_controller.value)
              : (left: 0.0, right: 1.0);
          return ClipRect(
            clipper: _SpanClipper(span.left, span.right),
            child: child,
          );
        },
      ),
    );
  }
}

class _SpanClipper extends CustomClipper<Rect> {
  const _SpanClipper(this.left, this.right);

  final double left, right;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(size.width * left, 0, size.width * right, size.height);

  @override
  bool shouldReclip(_SpanClipper old) => old.left != left || old.right != right;
}
