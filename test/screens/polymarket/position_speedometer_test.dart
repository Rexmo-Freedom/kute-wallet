// The open-position speedometer (position_speedometer.dart): an elastic
// needle on a calm 0–100% dial, the price paid a dot on its track, a tap
// each time the live chance shown changes, drag to explore.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/polymarket/components/position_speedometer.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/services/kute_haptics.dart';
import 'package:kute/theme/app_theme.dart';

/// Steps [m] by [seconds] in 1/120 s frames, returning every position.
List<double> _run(PolyNeedleMotion m, double seconds) {
  final xs = <double>[];
  for (var t = 0.0; t < seconds; t += 1 / 120) {
    m.advance(1 / 120);
    xs.add(m.position);
  }
  return xs;
}

class _Host extends StatefulWidget {
  const _Host(
      {required this.chance,
      this.entry = 0.19,
      this.sweep = true,
      this.hint = false});
  final double chance;
  final double? entry;
  final bool sweep;
  final bool hint;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late double chance = widget.chance;
  final explored = <double>[];
  final ended = <double>[];
  int starts = 0;
  @override
  Widget build(BuildContext context) => Center(
        child: SizedBox(
          width: 350,
          child: PolyPositionSpeedometer(
            chance: chance,
            entry: widget.entry,
            side: 'No',
            sweepOnOpen: widget.sweep,
            hintDrag: widget.hint,
            onExploreStart: () => starts++,
            onExplore: explored.add,
            onExploreEnd: ended.add,
          ),
        ),
      );
}

Future<_HostState> _pump(WidgetTester tester,
    {double chance = 0.66,
    double? entry = 0.19,
    bool sweep = true,
    bool reduceMotion = false,
    bool hint = false,
    bool dark = false}) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(430, 932),
    builder: (_, __) => MaterialApp(
      theme: ThemeData(
        brightness: dark ? Brightness.dark : Brightness.light,
        extensions: [
          dark ? AppColorsExtension.dark() : AppColorsExtension.light()
        ],
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
            size: const Size(390, 900), disableAnimations: reduceMotion),
        child: Scaffold(
            body: _Host(
                chance: chance, entry: entry, sweep: sweep, hint: hint)),
      ),
    ),
  ));
  return tester.state<_HostState>(find.byType(_Host));
}

PolyPositionSpeedometerState _state(WidgetTester tester) =>
    tester.state<PolyPositionSpeedometerState>(
        find.byType(PolyPositionSpeedometer));

Future<void> _setChance(WidgetTester tester, double chance) async {
  final host = tester.state<_HostState>(find.byType(_Host));
  // ignore: invalid_use_of_protected_member
  host.setState(() => host.chance = chance);
  await tester.pump();
}

void main() {
  late List<String> taps;

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    taps = [];
    PolyPositionSpeedometer.debugSelectionTick = () => taps.add('tap');
    KuteHaptics.debugForeground = () => true;
  });

  tearDown(() {
    PolyPositionSpeedometer.debugSelectionTick = null;
    KuteHaptics.debugReset();
  });

  group('the needle\'s spring', () {
    test('slightly under-damped: a gentle overshoot, settled in under 0.9 s',
        () {
      final s = kPolyNeedleSpring;
      final ratio = s.damping / (2 * math.sqrt(s.stiffness * s.mass));
      expect(ratio, closeTo(0.70, 0.01));
      final m = PolyNeedleMotion(position: 0)..retarget(0.66);
      final xs = _run(m, 0.9);
      final peak = xs.reduce((a, b) => a > b ? a : b);
      // A few percent of the move past it, no more.
      expect(peak, greaterThan(0.66 + 0.66 * 0.02));
      expect(peak, lessThan(0.66 + 0.66 * 0.07));
      // Within half a point by 0.9 s.
      expect(xs.last, closeTo(0.66, 0.005));
      // It accelerates: the first 100 ms cover less than the next 100.
      expect(xs[11], lessThan(xs[23] - xs[11]));
    });

    test('a new target mid-motion starts from where the needle is and how '
        'fast it moves: no jump, no restart', () {
      final m = PolyNeedleMotion(position: 0.2)..retarget(0.8);
      _run(m, 0.15);
      final x0 = m.position;
      final v0 = m.velocity;
      expect(v0, greaterThan(0.5));
      m.retarget(0.3);
      // Same place, same speed, the moment it is retargeted.
      expect(m.position, x0);
      expect(m.velocity, v0);
      m.advance(0.004);
      // Still carried on the way it was going, a hair further.
      expect(m.position, greaterThan(x0));
      expect(m.position - x0, closeTo(v0 * 0.004, 0.0005));
      // And it gets there.
      _run(m, 1.5);
      expect(m.position, closeTo(0.3, 0.001));
    });

    test('never leaves 0–100, even overshooting a stop', () {
      final up = PolyNeedleMotion(position: 0.5)..retarget(1.0);
      expect(_run(up, 1.2).every((x) => x >= 0 && x <= 1), isTrue);
      expect(up.position, 1.0);
      final down = PolyNeedleMotion(position: 0.6)
        ..retarget(0.0, velocity: -4);
      expect(_run(down, 1.2).every((x) => x >= 0 && x <= 1), isTrue);
      expect(down.position, 0.0);
      // A retarget from the stop starts still, never through it.
      final m = PolyNeedleMotion(position: 0.9)..retarget(1.0, velocity: 3);
      _run(m, 0.08);
      expect(m.position, 1.0);
      expect(m.velocity, 0);
    });

    test('Reduce Motion: a short ease, no overshoot', () {
      final m = PolyNeedleMotion(position: 0.2)
        ..retarget(0.7, reduceMotion: true);
      final xs = _run(m, 0.3);
      expect(xs.every((x) => x <= 0.7 + 1e-9), isTrue);
      final done = xs.indexWhere((x) => x == 0.7);
      expect(done, isNonNegative);
      expect(done / 120, lessThanOrEqualTo(0.15));
    });
  });

  group('the dial', () {
    test('the needle stops short of the chance at every angle', () {
      for (final w in [320.0, 350.0, 390.0, 600.0]) {
        final g = polySpeedometerGeometry(w);
        // Under half the track's radius, so its highest reach (at 50%)
        // stays below the chance's baseline.
        expect(g.needle, lessThan(g.radius * 0.5));
        expect(g.stroke, 4);
      }
    });

    test('a 5% mark crossed', () {
      expect(polyNeedleCrossesMark(0.61, 0.64), isFalse);
      expect(polyNeedleCrossesMark(0.64, 0.66), isTrue);
      expect(polyNeedleCrossesMark(0.66, 0.64), isTrue);
      expect(polyNeedleCrossesMark(0.649, 0.65), isTrue);
    });

    test('the figure and the caption, cut from one sentence', () {
      expect(polyGaugeChanceParts('75.8% chance', '75.8'),
          (figure: '75.8%', caption: 'chance'));
      expect(polyGaugeChanceParts('Szansa 66%', '66'),
          (figure: '66%', caption: 'Szansa'));
      expect(polyGaugeChanceParts('66 % de chances', '66'),
          (figure: '66 %', caption: 'de chances'));
    });

    testWidgets('calm: a thin neutral track, ticks at 0, 50 and 100 only, '
        'the price paid a dot on the track; no figures, no zones, no tag',
        (tester) async {
      await _pump(tester, sweep: false);
      final dial = tester
          .widget<CustomPaint>(find.byKey(PolyPositionSpeedometer.dialPaintKey))
          .painter! as PolySpeedometerDialPainter;
      expect(PolySpeedometerDialPainter.ticks, [0.0, 0.5, 1.0]);
      expect(dial.trackColor, AppColorsExtension.light().border);
      expect(dial.entryColor, AppColorsExtension.light().textSecondary);
      expect(dial.entry, 0.19);
      // On the track, at 19% of the way round.
      final g = dial.geometry;
      final dot = dial.entryDot!;
      expect((dot - g.center).distance, closeTo(g.radius, 1e-6));
      expect((dot - g.center).direction, closeTo(polyGaugeAngle(0.19) - 2 * 3.141592653589793, 1e-6));
      for (final gone in ['You · 19%', 'chance · live', '0', '25', '50', '75',
          '100']) {
        expect(find.text(gone), findsNothing, reason: gone);
      }
      expect(_state(tester).debugNeedle, closeTo(0.66, 1e-9));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the needle never crosses the digits: at 20, 50, 66 and 85% '
        'its tip, knob and ring, stays below the chance', (tester) async {
      for (final c in [0.20, 0.50, 0.66, 0.85]) {
        await _pump(tester, chance: c, sweep: false);
        final box =
            tester.getRect(find.byKey(PolyPositionSpeedometer.dialKey));
        final needle = tester
            .widget<CustomPaint>(
                find.byKey(PolyPositionSpeedometer.needlePaintKey))
            .painter! as PolySpeedometerNeedlePainter;
        final tip = box.topLeft + needle.tip;
        final figure =
            tester.getRect(find.byKey(PolyPositionSpeedometer.figureKey));
        expect(tip.dy - kPolySpeedometerKnobRing, greaterThan(figure.bottom),
            reason: '$c');
      }
    });

    testWidgets('a grab knob at the needle\'s tip: larger than the hub, in '
        'the needle\'s colour, inside a faint ring', (tester) async {
      await _pump(tester, sweep: false, dark: true);
      final needle = tester
          .widget<CustomPaint>(
              find.byKey(PolyPositionSpeedometer.needlePaintKey))
          .painter! as PolySpeedometerNeedlePainter;
      expect(needle.color, AppColorsExtension.dark().textPrimary);
      expect(needle.ringColor, AppColorsExtension.dark().background);
      expect(kPolySpeedometerKnob, greaterThan(kPolySpeedometerHub));
      expect(kPolySpeedometerKnobRing, greaterThan(kPolySpeedometerKnob * 1.5));
      // The knob sits at the tip, on the needle's line.
      final g = needle.geometry;
      expect((needle.tip - g.center).distance, closeTo(g.needle, 1e-6));
      // And grabs it: a touch on the knob takes the needle at once.
      final box = tester.getRect(find.byKey(PolyPositionSpeedometer.dialKey));
      final host = tester.state<_HostState>(find.byType(_Host));
      final touch = await tester.startGesture(
          box.topLeft + needle.tip + const Offset(kPolySpeedometerKnob, 0));
      await tester.pump();
      expect(host.starts, 1);
      await touch.up();
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('no price paid: no dot', (tester) async {
      await _pump(tester, entry: null, sweep: false);
      final dial = tester
          .widget<CustomPaint>(find.byKey(PolyPositionSpeedometer.dialPaintKey))
          .painter! as PolySpeedometerDialPainter;
      expect(dial.entry, isNull);
      expect(dial.entryDot, isNull);
    });
  });

  group('motion on screen', () {
    testWidgets('on open the needle sweeps up from 0 with the spring, '
        'silently', (tester) async {
      await _pump(tester, chance: 0.66);
      final s = _state(tester);
      expect(s.debugNeedle, 0);
      await tester.pump();
      expect(s.debugSweeping, isTrue);
      var peak = 0.0;
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (s.debugNeedle > peak) peak = s.debugNeedle;
      }
      expect(peak, greaterThan(0.67));
      expect(peak, lessThan(0.66 * 1.07));
      expect(s.debugNeedle, closeTo(0.66, 0.006));
      // A price moving during the sweep: still no tap.
      await _setChance(tester, 0.67);
      await tester.pump(const Duration(milliseconds: 600));
      expect(taps, isEmpty);
    });

    testWidgets('Reduce Motion: no sweep; a new price eases in 120 ms with no '
        'overshoot', (tester) async {
      await _pump(tester, chance: 0.4, reduceMotion: true);
      final s = _state(tester);
      expect(s.debugNeedle, closeTo(0.4, 1e-9));
      expect(s.debugSweeping, isFalse);
      await _setChance(tester, 0.6);
      var max = 0.0;
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (s.debugNeedle > max) max = s.debugNeedle;
      }
      expect(max, lessThanOrEqualTo(0.6 + 1e-9));
      expect(s.debugNeedle, closeTo(0.6, 1e-9));
    });

    testWidgets('a new price mid-motion: the needle carries on from where it '
        'is, no jump', (tester) async {
      await _pump(tester, chance: 0.3, sweep: false);
      final s = _state(tester);
      await _setChance(tester, 0.8);
      await tester.pump(const Duration(milliseconds: 150));
      final x0 = s.debugNeedle;
      final v0 = s.debugNeedleVelocity;
      expect(v0, greaterThan(0));
      await _setChance(tester, 0.4);
      expect(s.debugNeedle, x0);
      await tester.pump(const Duration(milliseconds: 8));
      // A small step on, the way it was going: no jump to either price.
      expect((s.debugNeedle - x0).abs(), lessThan(0.02));
      await tester.pump(const Duration(seconds: 2));
      expect(s.debugNeedle, closeTo(0.4, 0.002));
    });
  });

  group('taps as the chance moves', () {
    testWidgets('one tap per new chance shown, none for a move the figure '
        'does not show', (tester) async {
      await _pump(tester, chance: 0.661, sweep: false);
      await _setChance(tester, 0.663);
      expect(taps, hasLength(1));
      await tester.pump(const Duration(milliseconds: 200));
      // 66.3% both: nothing new on screen, no tap.
      await _setChance(tester, 0.6631);
      expect(taps, hasLength(1));
      await tester.pump(const Duration(milliseconds: 200));
      await _setChance(tester, 0.64);
      expect(taps, hasLength(2));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a burst inside 120 ms is one more tap at its end, not one '
        'each', (tester) async {
      await _pump(tester, chance: 0.50, sweep: false);
      await _setChance(tester, 0.51);
      expect(taps, hasLength(1));
      for (final c in [0.52, 0.53, 0.54, 0.55]) {
        await tester.pump(const Duration(milliseconds: 20));
        await _setChance(tester, c);
      }
      expect(taps, hasLength(1));
      await tester.pump(const Duration(milliseconds: 60));
      expect(taps, hasLength(2));
      await tester.pump(const Duration(milliseconds: 300));
      expect(taps, hasLength(2));
    });

    testWidgets('none in the background', (tester) async {
      await _pump(tester, chance: 0.50, sweep: false);
      KuteHaptics.debugForeground = () => false;
      await _setChance(tester, 0.58);
      expect(taps, isEmpty);
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('the drag hint', () {
    testWidgets('never dragged: once the opening sweep has settled, the '
        'needle leans a few degrees and springs back, silently, once',
        (tester) async {
      await _pump(tester, chance: 0.30, hint: true);
      final s = _state(tester);
      // The sweep, then the wait.
      await tester.pump();
      for (var i = 0; i < 200 && s.debugSweeping; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(s.debugSweeping, isFalse);
      expect(s.debugNudged, isFalse);
      var far = 0.0;
      for (var i = 0; i < 120; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        far = math.max(far, s.debugNeedle - 0.30);
      }
      expect(s.debugNudged, isTrue);
      // Toward the roomier side (up from 30%), a few degrees.
      expect(far, greaterThan(kPolyNeedleNudge * 0.6));
      expect(far, lessThan(kPolyNeedleNudge * 1.3));
      // Back on the live chance, still, and never again.
      expect(s.debugNudging, isFalse);
      expect(s.debugNeedle, closeTo(0.30, 0.003));
      expect(taps, isEmpty);
      await tester.pump(const Duration(seconds: 3));
      expect(s.debugNeedle, closeTo(0.30, 1e-6));
    });

    testWidgets('above 50% it leans down', (tester) async {
      await _pump(tester, chance: 0.80, sweep: false, hint: true);
      final s = _state(tester);
      var low = 1.0;
      for (var i = 0; i < 120; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        low = math.min(low, s.debugNeedle);
      }
      expect(s.debugNudged, isTrue);
      expect(low, lessThan(0.80 - kPolyNeedleNudge * 0.6));
      expect(s.debugNeedle, closeTo(0.80, 0.003));
    });

    testWidgets('already dragged (no hint) or Reduce Motion: no lean',
        (tester) async {
      await _pump(tester, chance: 0.30, sweep: false);
      await tester.pump(const Duration(seconds: 2));
      expect(_state(tester).debugNudged, isFalse);
      await _pump(tester, chance: 0.30, hint: true, reduceMotion: true);
      await tester.pump(const Duration(seconds: 2));
      expect(_state(tester).debugNudged, isFalse);
      expect(_state(tester).debugNeedle, closeTo(0.30, 1e-9));
    });

    testWidgets('a drag before the lean cancels it', (tester) async {
      final host = await _pump(tester, chance: 0.30, sweep: false, hint: true);
      final box = tester.getRect(find.byKey(PolyPositionSpeedometer.dialKey));
      final g = await tester.startGesture(box.bottomCenter - const Offset(0, 16));
      await tester.pump();
      expect(host.starts, 1);
      await g.up();
      for (var i = 0; i < 150; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(_state(tester).debugNudging, isFalse);
      expect(_state(tester).debugNeedle, closeTo(0.30, 0.003));
    });
  });

  group('drag to explore', () {
    testWidgets('the needle follows the finger, "If No reaches" over the '
        'chance, a tap every 5% at most every 80 ms; on release it springs '
        'back to live', (tester) async {
      final host = await _pump(tester, chance: 0.66, sweep: false);
      final s = _state(tester);
      final box = tester.getRect(find.byKey(PolyPositionSpeedometer.dialKey));
      final paint = tester
          .widget<CustomPaint>(find.byKey(PolyPositionSpeedometer.dialPaintKey))
          .painter! as PolySpeedometerDialPainter;
      final center = box.topLeft + paint.geometry.center;
      // On the hub: grabbed at once.
      final g = await tester.startGesture(center + const Offset(0, -10));
      await tester.pump();
      expect(host.starts, 1);
      expect(find.text('If No reaches'), findsOneWidget);
      // Sweep to the left end in a few big steps, inside one frame each.
      final r = paint.geometry.radius * 0.7;
      for (final f in [0.6, 0.45, 0.30, 0.15]) {
        final a = polyGaugeAngle(f);
        await g.moveTo(center + Offset(r * math.cos(a), r * math.sin(a)));
      }
      await tester.pump();
      expect(s.debugNeedle, closeTo(0.15, 0.01));
      expect(host.explored.last, closeTo(0.15, 0.011));
      // Several 5% marks crossed in no time: one tap, the rest inside the
      // 80 ms gap.
      expect(taps, hasLength(1));
      await tester.pump(const Duration(milliseconds: 100));
      final a = polyGaugeAngle(0.05);
      await g.moveTo(center + Offset(r * math.cos(a), r * math.sin(a)));
      await tester.pump();
      expect(taps, hasLength(2));
      expect(
          find.byWidgetPredicate(
              (w) => w is RollingNumberText && w.text == '5%'),
          findsOneWidget);
      await g.up();
      await tester.pump();
      expect(host.ended, [closeTo(0.05, 1e-9)]);
      expect(find.text('If No reaches'), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      expect(s.debugNeedle, closeTo(0.66, 0.003));
      // The spring back is silent.
      expect(taps, hasLength(2));
    });
  });
}

