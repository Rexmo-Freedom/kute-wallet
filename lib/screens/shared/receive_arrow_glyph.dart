// lib/screens/shared/receive_arrow_glyph.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The Receive button's glyph on the Bitcoin and Dollars action rows and
/// the docks: the plain receive arrow (↙, `Icons.south_west_rounded`, the
/// Send arrow's twin), moving the way the hub's "+ with a gear"
/// (`HubPlusGearGlyph`, kute_top_nav_bar.dart) moves (founder, 7 November
/// 2026: "Receive should move and animate like the settings"; the swap
/// badge it wore on 6 November went with the word swap).
///
/// Motion is the hub's short beat, not a loop: when it appears and then
/// once every [interval], the arrow travels in along its own line, down
/// and to the left, the way money comes in ([kReceiveArrowBeatMs]: in,
/// a hold, back); each press of the button around it plays the same
/// nudge quickly ([kReceiveArrowPressMs]), through [pressed] or the
/// nearest [GlyphPressScope]. Nothing ticks in between. No new play starts
/// while another route covers this one (one in flight finishes; coming
/// back into view plays once), and it holds still while the app is in the
/// background, while its tickers are off, and for good under Reduce
/// Motion. Takes [color] straight from the theme and is sized like an
/// [Icon]: at rest it is exactly the arrow icon.
class ReceiveArrowGlyph extends StatefulWidget {
  const ReceiveArrowGlyph({
    super.key,
    required this.color,
    this.size = 24,
    this.pressed,
    this.interval = const Duration(seconds: 9),
  });

  final Color color;
  final double size;

  /// Notifies on each press of the button around the glyph; null listens
  /// to the nearest [GlyphPressScope], when there is one.
  final Listenable? pressed;

  /// Rest between plays.
  final Duration interval;

  @override
  State<ReceiveArrowGlyph> createState() => _ReceiveArrowGlyphState();
}

/// [ReceiveArrowGlyph] as a `KuteDockAction.glyph`.
Widget receiveArrowGlyph(Color color, double size) =>
    ReceiveArrowGlyph(color: color, size: size);

/// One play: the arrow travels in over the first [kReceiveArrowInEnd] of
/// it, holds, and comes back from [kReceiveArrowOutStart] (the hub's
/// beat, kute_top_nav_bar.dart).
const int kReceiveArrowBeatMs = 1700;
const double kReceiveArrowInEnd = 650 / 1700;
const double kReceiveArrowOutStart = 1050 / 1700;

/// A press: the same nudge, quickly.
const int kReceiveArrowPressMs = 500;
const double kReceiveArrowPressInEnd = 190 / 500;
const double kReceiveArrowPressOutStart = 280 / 500;

/// How far the arrow travels at the top of a play, in units of the
/// 24-unit icon grid, along its own diagonal.
const double kReceiveArrowTravel = 3;

/// How far in the arrow is at [v] (0..1 through a play): 0 at rest, 1
/// while held, eased in and out between.
@visibleForTesting
double receiveArrowNudge(double v, double inEnd, double outStart) {
  if (v <= 0 || v >= 1) return 0;
  if (v < inEnd) return Curves.easeInOut.transform(v / inEnd);
  if (v <= outStart) return 1;
  return 1 - Curves.easeInOut.transform((v - outStart) / (1 - outStart));
}

/// The arrow's offset at [nudge] (0..1) for a glyph [size] wide: down and
/// to the left, along the arrow's line.
@visibleForTesting
Offset receiveArrowOffset(double nudge, double size) {
  final d = nudge * kReceiveArrowTravel * size / 24 / math.sqrt2;
  return Offset(-d, d);
}

class _ReceiveArrowGlyphState extends State<ReceiveArrowGlyph>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  Timer? _next;
  bool _reduce = false;
  bool _tickerOff = false;
  bool _covered = false;
  bool _foreground = true;
  Listenable? _listening;

  /// Whether the play in flight is a press (quick).
  bool _press = false;

  bool get _halted => _reduce || _tickerOff || !_foreground;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: kReceiveArrowBeatMs))
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && !_covered && !_halted) {
          _schedule(widget.interval);
        }
      });
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  /// Listens to [ReceiveArrowGlyph.pressed], else the nearest scope.
  void _listen() {
    final next = widget.pressed ?? GlyphPressScope.maybeOf(context);
    if (identical(next, _listening)) return;
    _listening?.removeListener(_onPressed);
    _listening = next?..addListener(_onPressed);
  }

  @override
  void didUpdateWidget(ReceiveArrowGlyph old) {
    super.didUpdateWidget(old);
    if (old.pressed != widget.pressed) _listen();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _listen();
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
    _controller.duration = Duration(
        milliseconds: press ? kReceiveArrowPressMs : kReceiveArrowBeatMs);
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
    _listening?.removeListener(_onPressed);
    WidgetsBinding.instance.removeObserver(this);
    _cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final arrow =
        Icon(Icons.south_west_rounded, size: widget.size, color: widget.color);
    if (_reduce) return arrow;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        child: arrow,
        builder: (context, child) {
          var nudge = 0.0;
          if (_controller.isAnimating) {
            nudge = receiveArrowNudge(
                _controller.value,
                _press ? kReceiveArrowPressInEnd : kReceiveArrowInEnd,
                _press ? kReceiveArrowPressOutStart : kReceiveArrowOutStart);
          }
          return Transform.translate(
            offset: receiveArrowOffset(nudge, widget.size),
            child: child,
          );
        },
      ),
    );
  }
}

/// Pings the glyphs under it (a [ReceiveArrowGlyph]) on each press of
/// [child], so a whole button, not only the glyph's own box, plays the
/// press: the hub button pings its gear the same way on tap-down. Off
/// while not [enabled].
class GlyphPressScope extends StatefulWidget {
  const GlyphPressScope({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  /// The press signal of the nearest scope, or null.
  static Listenable? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_GlyphPressInherited>()
      ?.pressed;

  @override
  State<GlyphPressScope> createState() => _GlyphPressScopeState();
}

class _GlyphPress extends ChangeNotifier {
  void ping() => notifyListeners();
}

class _GlyphPressScopeState extends State<GlyphPressScope> {
  final _pressed = _GlyphPress();

  @override
  void dispose() {
    _pressed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: widget.enabled ? (_) => _pressed.ping() : null,
        child: _GlyphPressInherited(pressed: _pressed, child: widget.child),
      );
}

class _GlyphPressInherited extends InheritedWidget {
  const _GlyphPressInherited({required this.pressed, required super.child});

  final Listenable pressed;

  @override
  bool updateShouldNotify(_GlyphPressInherited old) => pressed != old.pressed;
}
