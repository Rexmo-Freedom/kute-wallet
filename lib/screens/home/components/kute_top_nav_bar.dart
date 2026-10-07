// lib/screens/home/components/kute_top_nav_bar.dart
//
// Integrated top navigation bar: the account / Dollars / Investing /
// Predictions tab chips on the left, filling most of the row, with ONE
// button on the RIGHT that opens the Financial hub: the wallet list, switch
// wallet and Add wallet, Notifications in its header and a Settings row.
// Its glyph is a rounded "+" with a small gear badge at its lower right
// (owner decision October 2026: one glyph for "add" and "settings", the two
// jobs behind it; it is the only door to the hub on the shell, and a pushed
// wallet screen opens the hub from its name).
// Mounted at the TOP of the shell so the tabs are always visible and
// consistent across screens; the bottom is the dock.
//
// The bar is now mounted ONCE in the persistent nav shell (see
// lib/screens/app_shell.dart), so it auto-hides via the shared
// [navBarHiddenProvider] instead of a per-screen scroll controller: whichever
// tab page is on screen drives that provider from its own scroll listener,
// and this bar WATCHES it, sliding up off the top edge when hidden.

import 'dart:async';
import 'dart:math' as math;

import 'package:kute/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/providers/nav_bar_visibility_provider.dart';
import 'package:kute/screens/home/components/action_pill.dart';
import 'package:kute/screens/shared/wallet_money_actions.dart';
import 'package:kute/theme/app_theme.dart';

class KuteTopNavBar extends ConsumerWidget {
  final ActiveNavTab activeTab;

  /// Called when a DIFFERENT tab is tapped — the shell switches its
  /// go_router branch (see AppShell._selectTab). Tapping the ACTIVE tab is
  /// handled inside the pill itself (its deposit-menu affordances), so this
  /// only ever fires for a tab change.
  final void Function(ActiveNavTab)? onSelectTab;

  const KuteTopNavBar({
    super.key,
    required this.activeTab,
    this.onSelectTab,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Shared hide state, written by whichever tab page is on screen from its
    // own scroll listener (reverse = hide, forward / near-top = show).
    final hidden = ref.watch(navBarHiddenProvider);
    // Honor Reduce Motion (2027 accessibility principle): slide the bar
    // instantly for users who opt out of non-essential animation.
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    final bar = SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12.w, 6.h, 12.w, 6.h),
        // No enclosing band: the tab strip floats (it owns a bounded width
        // via Expanded so it can never grow under / collide with the hub
        // button), only the active tab carries a pill, and the hub button
        // is its own standalone chip on the right. The strip SPREADS its
        // tabs to fill the full available width (see FloatingActionPill).
        child: Row(
          children: [
            // Bounded region — the strip fills the space left after the
            // fixed hub button and gap, spreading its tabs evenly across it.
            Expanded(
              child: FloatingActionPill(
                activeTab: activeTab,
                onSelectTab: onSelectTab,
              ),
            ),
            // Balanced breathing room between the strip and the button.
            SizedBox(width: 12.w),
            // The ONE trailing button: the +-and-gear into the Financial
            // hub.
            _FinancialHubButton(activeTab: activeTab),
          ],
        ),
      ),
    );

    // Slide up off the top edge when hidden (content scrolls underneath).
    return AnimatedSlide(
      offset: hidden ? const Offset(0, -1) : Offset.zero,
      duration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      child: IgnorePointer(ignoring: hidden, child: bar),
    );
  }
}

/// The Financial hub door: the "+"-with-a-gear glyph ([HubPlusGearGlyph])
/// in the standalone chip the Settings gear wore (44pt chrome, right of the
/// tab strip). It opens the hub sheet: wallets and Add wallet, with
/// Settings and Notifications side by side in its header. The
/// `wallet_actions_opened` source names the tab it was opened on:
/// home_plus | usd_plus | trading_plus | predictions_plus | bank_plus.
class _FinancialHubButton extends StatefulWidget {
  const _FinancialHubButton({required this.activeTab});

  final ActiveNavTab activeTab;

  @override
  State<_FinancialHubButton> createState() => _FinancialHubButtonState();
}

class _FinancialHubButtonState extends State<_FinancialHubButton> {
  /// Pinged on each press, so the glyph's gear turns a quick tooth.
  final _pressed = _Ping();

  @override
  void dispose() {
    _pressed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Semantics(
      button: true,
      label: context.l10n.financialHubAndSettings,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _pressed.ping(),
        onTap: () {
          HapticFeedback.selectionClick();
          showWalletMoneyActions(context, source: switch (widget.activeTab) {
            ActiveNavTab.home => 'home_plus',
            ActiveNavTab.usd => 'usd_plus',
            ActiveNavTab.trading => 'trading_plus',
            ActiveNavTab.predictions => 'predictions_plus',
            ActiveNavTab.bank => 'bank_plus',
          });
        },
        // The same neutral square chip the dock's button and the header
        // shortcuts wear: rounded square, the light-mode white fill with
        // its soft lift, a hairline rather than a full-weight rim.
        child: Container(
          width: 46.w,
          height: 46.w,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isLight ? Colors.white : c.surface,
            borderRadius: AppRadius.buttonBorder,
            border: Border.all(
              color: isLight ? c.border : c.borderSubtle,
              width: isLight ? 1.0 : 0.5,
            ),
            boxShadow: isLight
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: HubPlusGearGlyph(
              color: c.textPrimary, size: 24.sp, pressed: _pressed),
        ),
      ),
    );
  }
}

class _Ping extends ChangeNotifier {
  void ping() => notifyListeners();
}

/// One play of the hub glyph, a swap of prominence: the gear grows and
/// moves in towards the centre (turning a tooth) while the "+" shrinks
/// back to the top left, it holds there, then they swap back (the gear
/// turning another tooth) to the rest frame. As fractions of the play:
/// the swap in ends at [_kHubInEnd], the swap back starts at
/// [_kHubOutStart].
const int _kHubBeatMs = 1700;
const double _kHubInEnd = 650 / 1700;
const double _kHubOutStart = 1050 / 1700;

/// A press: the same swap, quickly.
const int _kHubPressMs = 500;
const double _kHubPressInEnd = 190 / 500;
const double _kHubPressOutStart = 280 / 500;

/// How prominent the gear is at [v] (0..1 through a play): 0 at rest, 1
/// while held, eased in and out between.
double _hubSwap(double v, double inEnd, double outStart) {
  if (v <= 0 || v >= 1) return 0;
  if (v < inEnd) return Curves.easeInOut.transform(v / inEnd);
  if (v <= outStart) return 1;
  return 1 - Curves.easeInOut.transform((v - outStart) / (1 - outStart));
}

/// The gear's turn at [v], in teeth: one on the way in, one on the way
/// back, so it ends where it began (six teeth, 60° a tooth).
double _hubTurn(double v, double inEnd, double outStart) {
  if (v <= 0 || v >= 1) return 0;
  if (v < inEnd) return Curves.easeInOut.transform(v / inEnd);
  if (v <= outStart) return 1;
  return 1 + Curves.easeInOut.transform((v - outStart) / (1 - outStart));
}

/// One glyph for the hub's two jobs: a thick rounded "+" (add) with a
/// small solid gear badge over its lower-right (settings), the gear in a
/// cut-out ring so the two shapes stay apart. On the 24-unit grid of the
/// app's rounded header icons with 2-unit strokes; painted in device
/// pixels so the plus lands on whole pixels, and the cut-out is cleared
/// rather than filled, so the chip's own colour shows through in light
/// and dark. Takes [color] straight from the theme.
///
/// Motion is a short beat, not a loop: when it appears and then once every
/// [interval], the two swap prominence ([_kHubBeatMs]): the gear grows in
/// towards the centre, turning, as the "+" shrinks back to the top left;
/// a hold; then they swap back. Each press plays a quick swap
/// ([_kHubPressMs], via [pressed]). The gear keeps its cut-out ring at
/// every frame, so the two never merge. Nothing ticks in between. No new play
/// starts while another route covers this one (one in flight finishes;
/// coming back into view plays once), and it holds still while the app is
/// in the background, while its tickers are off, and for good under
/// Reduce Motion.
class HubPlusGearGlyph extends StatefulWidget {
  const HubPlusGearGlyph({
    super.key,
    required this.color,
    this.size = 24,
    this.pressed,
    this.interval = const Duration(seconds: 9),
  });

  final Color color;
  final double size;

  /// Notifies on each press of the button around the glyph.
  final Listenable? pressed;

  /// Rest between plays.
  final Duration interval;

  @override
  State<HubPlusGearGlyph> createState() => _HubPlusGearGlyphState();
}

class _HubPlusGearGlyphState extends State<HubPlusGearGlyph>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  Timer? _next;
  bool _reduce = false;
  bool _tickerOff = false;
  bool _covered = false;
  bool _foreground = true;

  /// Whether the play in flight is a press (gear only, quick).
  bool _press = false;

  bool get _halted => _reduce || _tickerOff || !_foreground;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: _kHubBeatMs))
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
  void didUpdateWidget(HubPlusGearGlyph old) {
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
    _controller.duration =
        Duration(milliseconds: press ? _kHubPressMs : _kHubBeatMs);
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
          size: size, painter: _HubPlusGearPainter(widget.color, dpr));
    }
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          var swap = 0.0, turn = 0.0;
          if (_controller.isAnimating) {
            final v = _controller.value;
            final inEnd = _press ? _kHubPressInEnd : _kHubInEnd;
            final outStart = _press ? _kHubPressOutStart : _kHubOutStart;
            swap = _hubSwap(v, inEnd, outStart);
            turn = _hubTurn(v, inEnd, outStart);
          }
          return CustomPaint(
            size: size,
            painter: _HubPlusGearPainter(widget.color, dpr,
                swap: swap, turn: turn),
          );
        },
      ),
    );
  }
}

class _HubPlusGearPainter extends CustomPainter {
  const _HubPlusGearPainter(this.color, this.dpr,
      {this.swap = 0, this.turn = 0});

  final Color color;
  final double dpr;

  /// How prominent the gear is: 0 the rest frame (big "+", gear badge),
  /// 1 the swap held (big gear, small "+" at the top left).
  final double swap;

  /// How many teeth (60° each) the gear has turned.
  final double turn;

  // On the 24-unit grid, at rest: the plus about (11, 11), arms 7 either
  // way, 2-unit strokes; the gear badge about (18.5, 18.5), six teeth,
  // its cut-out and its hole. Held: the plus about (4, 4), arms 2.8,
  // 1.6-unit strokes, and the gear about (13.5, 13.5) at [_gearBig] times
  // its size, its cut-out clear of the plus, so neither covers the other.
  static const double _plus = 11;
  static const double _arm = 7;
  static const double _stroke = 2;
  static const double _plusSmall = 4;
  static const double _armSmall = 2.8;
  static const double _strokeSmall = 1.6;
  static const double _gear = 18.5;
  static const double _gearIn = 13.5;
  static const double _gearBig = 9 / 5.4;
  static const int _teeth = 6;
  static const double _tip = 5.4;
  static const double _root = 4.1;
  static const double _tipHalf = 0.26; // radians either side of a tooth
  static const double _rootHalf = 0.3;
  static const double _gap = 1.5;
  static const double _hole = 1.7;

  /// The filled gear, centred on [centre], [k] device px a unit, turned
  /// [rotation] radians.
  static Path _gearPath(Offset centre, double k, double rotation) {
    final rTip = _tip * k, rRoot = _root * k;
    Offset polar(double r, double a) =>
        centre + Offset(r * math.cos(a), r * math.sin(a));
    const pitch = 2 * math.pi / _teeth;
    // Half a pitch off vertical: a gap at the top, as the candidate sat.
    final start = -math.pi / 2 + pitch / 2 + rotation;
    final tipRect = Rect.fromCircle(center: centre, radius: rTip);
    final rootRect = Rect.fromCircle(center: centre, radius: rRoot);
    final gear = Path();
    for (var i = 0; i < _teeth; i++) {
      final a = start + i * pitch;
      if (i == 0) {
        final p0 = polar(rRoot, a - _rootHalf);
        gear.moveTo(p0.dx, p0.dy);
      } else {
        gear.arcTo(
            rootRect, a - pitch + _rootHalf, pitch - 2 * _rootHalf, false);
      }
      final up = polar(rTip, a - _tipHalf);
      gear.lineTo(up.dx, up.dy);
      gear.arcTo(tipRect, a - _tipHalf, 2 * _tipHalf, false);
      final down = polar(rRoot, a + _rootHalf);
      gear.lineTo(down.dx, down.dy);
    }
    gear.arcTo(rootRect, start + (_teeth - 1) * pitch + _rootHalf,
        pitch - 2 * _rootHalf, false);
    gear.close();
    return gear;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(1 / dpr);
    // Device pixels per grid unit; the grid centred in the square.
    final side = size.shortestSide * dpr;
    final k = side / 24;
    canvas.translate(((size.width * dpr - side) / 2).roundToDouble(),
        ((size.height * dpr - side) / 2).roundToDouble());

    // A layer, so the gear's cut-out clears the plus to the chip beneath.
    canvas.saveLayer(Rect.fromLTWH(-k, -k, 26 * k, 26 * k), Paint());

    double lerp(double a, double b) => a + (b - a) * swap;

    // The plus: a whole number of device pixels wide, centred so both
    // strokes' edges land on pixel boundaries, at every frame.
    final w =
        math.max(1, (lerp(_stroke, _strokeSmall) * k).round()).toDouble();
    double onGrid(double v) => w % 2 == 0
        ? v.roundToDouble()
        : (v - 0.5).roundToDouble() + 0.5;
    final at = lerp(_plus, _plusSmall) * k;
    final pc = Offset(onGrid(at), onGrid(at));
    final arm = (lerp(_arm, _armSmall) * k).roundToDouble();
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawLine(pc - Offset(arm, 0), pc + Offset(arm, 0), pen);
    canvas.drawLine(pc - Offset(0, arm), pc + Offset(0, arm), pen);

    // The gear in its cut-out (a fixed-width ring at every size), and its
    // hole.
    final g = lerp(_gear, _gearIn) * k;
    final gc = Offset(g, g);
    final gk = k * lerp(1, _gearBig);
    final badge = _gearPath(gc, gk, turn * 2 * math.pi / _teeth);
    final clear = Paint()..blendMode = BlendMode.clear;
    canvas.drawPath(badge, clear);
    canvas.drawPath(
        badge,
        Paint()
          ..blendMode = BlendMode.clear
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = _gap * 2 * k);
    canvas.drawPath(badge, Paint()..color = color);
    canvas.drawCircle(gc, _hole * gk, clear);

    canvas.restore(); // layer
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HubPlusGearPainter old) =>
      old.color != color ||
      old.dpr != dpr ||
      old.swap != swap ||
      old.turn != turn;
}
