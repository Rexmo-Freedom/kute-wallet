import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/privacy_cover_bridge.dart';
import 'package:kute/screens/shared/rubber_band_progress.dart';
import 'package:kute/services/continuous_haptics.dart';
import 'package:kute/services/haptic_patterns.dart';
import 'package:kute/services/kute_haptics.dart';

Widget _host(double progress,
    {RubberBandOutcome outcome = RubberBandOutcome.none,
    bool reduceMotion = false,
    bool haptic = true,
    VoidCallback? onReleased}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RubberBandProgress(
          progress: progress,
          haptic: haptic,
          outcome: outcome,
          onReleased: onReleased,
          child: const SizedBox(width: 200, height: 100, child: Text('Busy')),
        ),
      ),
    ),
  );
}

RubberBandProgressState _state(WidgetTester tester) =>
    tester.state<RubberBandProgressState>(find.byType(RubberBandProgress));

/// A [RubberBandBusy] on a 100 px block, as the slips' CTA wears it.
Widget _busyHost(
  bool busy, {
  double? progress,
  RubberBandOutcome? outcome,
  bool reduceMotion = false,
  Duration expected = const Duration(milliseconds: 1500),
}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RubberBandBusy(
          busy: busy,
          progress: progress,
          outcome: outcome,
          expected: expected,
          child: const SizedBox(width: 200, height: 100, child: Text('Sell')),
        ),
      ),
    ),
  );
}

RubberBandBusyState _busyState(WidgetTester tester) =>
    tester.state<RubberBandBusyState>(find.byType(RubberBandBusy));

/// Whether anything in a [RubberBandBusy] ticks: its build's clock or
/// the band.
bool _busyTicking(WidgetTester tester) =>
    _busyState(tester).easing || _state(tester).ticking;

/// Pumps [ms] in 16 ms frames, recording the band's offset.
Future<List<double>> _record(WidgetTester tester, int ms) async {
  final out = <double>[];
  for (var t = 0; t < ms; t += 16) {
    await tester.pump(const Duration(milliseconds: 16));
    out.add(_state(tester).stretch);
  }
  return out;
}

/// Pumps until the band's level settles (the breathing keeps ticking).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  // Every haptic the band asks for, through the bridge's test seam.
  late List<ContinuousHapticsCall> log;
  setUp(() {
    PrivacyCoverBridge.debugReset();
    ContinuousHaptics.debugReset();
    log = ContinuousHaptics.debugLog = [];
  });
  tearDown(() {
    PrivacyCoverBridge.debugReset();
    ContinuousHaptics.debugLog = null;
  });
  int snaps() => log.where((c) => c.method == 'snap').length;

  test('the tension is monotonic, and full tension is 12–14% of the block', () {
    final values = [for (var i = 0; i <= 10; i++) rubberBandStretchFor(i / 10)];
    for (var i = 1; i < values.length; i++) {
      expect(values[i], greaterThan(values[i - 1]));
    }
    expect(values.first, 0);
    expect(values.last, closeTo(RubberBandProgress.defaultMaxStretch, 1e-9));
    expect(values.last, inInclusiveRange(0.12, 0.14));
    // The first pull is 35–40% of full tension.
    expect(RubberBandProgress.firstPull, inInclusiveRange(0.35, 0.40));
  });

  test('the time build: monotonic, toward the ceiling, never past it', () {
    const expected = Duration(milliseconds: 1500);
    var last = 0.0;
    for (var ms = 0; ms <= 20000; ms += 100) {
      final p = rubberBandEasedProgress(
          RubberBandProgress.firstPull, Duration(milliseconds: ms),
          expected: expected);
      expect(p, greaterThanOrEqualTo(last));
      expect(p, lessThan(RubberBandBusy.defaultCeiling));
      last = p;
    }
    expect(
        rubberBandEasedProgress(RubberBandProgress.firstPull, Duration.zero,
            expected: expected),
        RubberBandProgress.firstPull);
    // Two thirds of the way by the expected duration.
    final atExpected = rubberBandEasedProgress(
        RubberBandProgress.firstPull, expected,
        expected: expected);
    expect(
        (atExpected - RubberBandProgress.firstPull) /
            (RubberBandBusy.defaultCeiling - RubberBandProgress.firstPull),
        closeTo(2 / 3, 0.01));
    // A phase past the ceiling holds.
    expect(
        rubberBandEasedProgress(0.9, const Duration(seconds: 5),
            expected: expected),
        0.9);
  });

  testWidgets('the stretch grows as the steps advance', (tester) async {
    double? last;
    for (final p in [0.2, 0.5, 0.85]) {
      await tester.pumpWidget(_host(p));
      await _settle(tester);
      final s = _state(tester).stretch;
      // Within the breathing of the level the step asks for.
      expect(s, closeTo(rubberBandStretchFor(p), RubberBandProgress.breath));
      if (last != null) {
        expect(rubberBandStretchFor(p), greaterThan(last));
      }
      last = rubberBandStretchFor(p);
      // A waiting step breathes: it is never frozen.
      expect(_state(tester).ticking, isTrue);
    }
  });

  testWidgets('success snaps past rest, settles, and stops ticking',
      (tester) async {
    var released = 0;
    await tester.pumpWidget(_host(0.85, onReleased: () => released++));
    await _settle(tester);
    await tester.pumpWidget(_host(0.85,
        outcome: RubberBandOutcome.success, onReleased: () => released++));
    var min = double.infinity;
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final s = _state(tester).stretch;
      if (s < min) min = s;
    }
    expect(min, lessThan(0), reason: 'the snap overshoots past rest');
    await _settle(tester);
    expect(_state(tester).stretch, 0);
    expect(_state(tester).ticking, isFalse);
    expect(released, 1);
    expect(snaps(), 1);
  });

  testWidgets('failure releases softly with no overshoot', (tester) async {
    var released = 0;
    await tester.pumpWidget(_host(0.85, onReleased: () => released++));
    await _settle(tester);
    await tester.pumpWidget(_host(0.85,
        outcome: RubberBandOutcome.failure, onReleased: () => released++));
    var previous = _state(tester).stretch;
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final s = _state(tester).stretch;
      expect(s, greaterThanOrEqualTo(-1e-9), reason: 'never past rest');
      expect(s, lessThanOrEqualTo(previous + 1e-9), reason: 'only toward rest');
      previous = s;
    }
    await _settle(tester);
    expect(_state(tester).stretch, 0);
    expect(_state(tester).ticking, isFalse);
    expect(released, 1);
  });

  testWidgets('Reduce Motion: nothing moves, nothing ticks', (tester) async {
    await tester.pumpWidget(_host(0.85, reduceMotion: true));
    await tester.pump(const Duration(milliseconds: 500));
    expect(_state(tester).stretch, 0);
    expect(_state(tester).ticking, isFalse);
    expect(find.byType(FractionalTranslation), findsNothing);
    var released = 0;
    await tester.pumpWidget(_host(0.85,
        reduceMotion: true,
        outcome: RubberBandOutcome.success,
        onReleased: () => released++));
    await tester.pump();
    expect(_state(tester).ticking, isFalse);
    expect(released, 1);
  });

  testWidgets('at rest nothing ticks', (tester) async {
    await tester.pumpWidget(_host(0));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_state(tester).ticking, isFalse);
    expect(_state(tester).stretch, 0);
  });

  testWidgets('tickers off (covered): still, and moving again after',
      (tester) async {
    await tester.pumpWidget(TickerMode(enabled: false, child: _host(0.85)));
    await tester.pump(const Duration(milliseconds: 200));
    expect(_state(tester).ticking, isFalse);
    expect(_state(tester).stretch, 0);
    await tester.pumpWidget(TickerMode(enabled: true, child: _host(0.85)));
    await _settle(tester);
    expect(_state(tester).stretch,
        closeTo(rubberBandStretchFor(0.85), RubberBandProgress.breath));
  });

  testWidgets('in the background: still', (tester) async {
    await tester.pumpWidget(_host(0.85));
    await _settle(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(_state(tester).ticking, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(_state(tester).ticking, isTrue);
  });

  testWidgets('Face ID inactive keeps progress feedback through completion',
      (tester) async {
    final scan = Completer<bool>();
    final prompt = runBiometricPrompt(() => scan.future);
    await tester.pumpWidget(_host(0.5));
    await tester.pump(const Duration(milliseconds: 100));
    final starts = log.where((c) => c.method == 'start').length;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(milliseconds: 100));
    expect(_state(tester).feeling, isTrue);
    expect(KuteHaptics.isForeground, isTrue);
    expect(ContinuousHaptics.isRunning(_state(tester)), isTrue);
    expect(log.where((c) => c.method == 'stop'), isEmpty);
    expect(log.where((c) => c.method == 'start').length, starts);

    await tester.pumpWidget(_host(0.5, outcome: RubberBandOutcome.success));
    await tester.pump(const Duration(seconds: 1));
    expect(_state(tester).feeling, isFalse);
    expect(ContinuousHaptics.isRunning(), isFalse);
    expect(snaps(), 1);

    scan.complete(true);
    await prompt;
    await tester.pump(const Duration(milliseconds: 800));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(_state(tester).feeling, isFalse);
    expect(snaps(), 1);
  });

  testWidgets('cancelled prompt stops inactive feedback after lifecycle settle',
      (tester) async {
    final scan = Completer<bool>();
    final prompt = runBiometricPrompt(() => scan.future);
    await tester.pumpWidget(_host(0.5));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(_state(tester).feeling, isTrue);
    scan.complete(false);
    await prompt;
    await tester.pump(const Duration(milliseconds: 800));
    expect(_state(tester).feeling, isFalse);
    expect(ContinuousHaptics.isRunning(), isFalse);
    expect(KuteHaptics.isForeground, isFalse);
    expect(log.last.method, 'stop');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(_state(tester).feeling, isTrue);
  });

  testWidgets('ordinary inactive and real background still stop feedback',
      (tester) async {
    await tester.pumpWidget(_host(0.5));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(_state(tester).feeling, isFalse);
    expect(KuteHaptics.isForeground, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    final scan = Completer<bool>();
    final prompt = runBiometricPrompt(() => scan.future);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(_state(tester).feeling, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    expect(_state(tester).feeling, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(ContinuousHaptics.isRunning(), isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
    expect(_state(tester).feeling, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(_state(tester).feeling, isFalse,
        reason: 'backgrounded authentication must really resume first');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(_state(tester).feeling, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(ContinuousHaptics.isRunning(), isFalse);
    scan.complete(false);
    await prompt;
    await tester.pump(const Duration(milliseconds: 800));
  });

  testWidgets('Face ID does not enable disabled or reduced-motion haptics',
      (tester) async {
    final scan = Completer<bool>();
    final prompt = runBiometricPrompt(() => scan.future);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpWidget(_host(0.5, haptic: false));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_state(tester).feeling, isFalse);
    expect(log, isEmpty);
    await tester.pumpWidget(_host(0.5, reduceMotion: true));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_state(tester).feeling, isFalse);
    expect(log, isEmpty);
    scan.complete(true);
    await prompt;
    await tester.pump(const Duration(milliseconds: 800));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('the text is translated, never scaled', (tester) async {
    await tester.pumpWidget(_host(0.85));
    await _settle(tester);
    expect(find.byType(Transform), findsNothing);
    final y = tester.getTopLeft(find.text('Busy')).dy;
    await tester.pumpWidget(_host(0));
    await _settle(tester);
    final rest = tester.getTopLeft(find.text('Busy')).dy;
    expect(y, lessThan(rest));
    // At most full tension (13% of the 100 px block) and a breath.
    expect(
        rest - y,
        lessThanOrEqualTo(100 *
            (RubberBandProgress.defaultMaxStretch +
                RubberBandProgress.breath)));
  });

  group('RubberBandBusy', () {
    testWidgets('the tap pulls at least 4% of the block within 300 ms',
        (tester) async {
      await tester.pumpWidget(_busyHost(false));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_state(tester).stretch, 0);
      await tester.pumpWidget(_busyHost(true));
      final frames = await _record(tester, 300);
      expect(frames.last, greaterThanOrEqualTo(0.04));
      // Eased in, not a jump: the first frame has barely moved.
      expect(frames.first, lessThan(0.02));
      // And already most of the first pull by 250 ms.
      expect(
          frames[(250 / 16).floor() - 1],
          greaterThan(
              0.8 * rubberBandStretchFor(RubberBandProgress.firstPull)));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('it keeps building with time, with no phase signal',
        (tester) async {
      await tester.pumpWidget(_busyHost(true));
      var last = 0.0;
      final samples = <double>[];
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        final p = _busyState(tester).progress;
        expect(p, greaterThanOrEqualTo(last), reason: 'never goes back');
        last = p;
        samples.add(_state(tester).stretch);
      }
      // 250 ms, 1 s, 5 s: the band is pulled further each time.
      expect(samples[3], greaterThan(samples[0]));
      expect(samples[19], greaterThan(samples[3]));
      expect(samples[19],
          greaterThan(rubberBandStretchFor(0.8) - RubberBandProgress.breath));
      expect(
          samples[19],
          lessThanOrEqualTo(RubberBandProgress.defaultMaxStretch +
              RubberBandProgress.breath));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a phase jumps it forward, and it builds on from there',
        (tester) async {
      await tester.pumpWidget(_busyHost(true));
      await tester.pump(const Duration(milliseconds: 300));
      final before = _busyState(tester).progress;
      expect(before, lessThan(0.7));
      await tester.pumpWidget(_busyHost(true, progress: 0.7));
      expect(_busyState(tester).progress, 0.7);
      await tester.pump(const Duration(milliseconds: 1000));
      expect(_busyState(tester).progress, greaterThan(0.7));
      // A phase behind the build never pulls it back.
      final now = _busyState(tester).progress;
      await tester.pumpWidget(_busyHost(true, progress: 0.5));
      expect(_busyState(tester).progress, greaterThanOrEqualTo(now));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('success snaps while still busy, and settles within the wait',
        (tester) async {
      await tester.pumpWidget(_busyHost(true));
      await _record(tester, 1500);
      final pulled = _state(tester).stretch;
      expect(pulled, greaterThan(0.06));
      // The caller sets the outcome and keeps busy up while it waits.
      await tester
          .pumpWidget(_busyHost(true, outcome: RubberBandOutcome.success));
      expect(_busyState(tester).easing, isFalse);
      final frames =
          await _record(tester, RubberBand.snapSettle.inMilliseconds);
      final min = frames.reduce(math.min);
      expect(min, lessThan(-0.01), reason: 'a felt bounce past rest');
      // By the end of the wait it has all but settled: under a pixel on
      // a 56 px button.
      expect(frames.last.abs() * 56, lessThan(1));
      expect(snaps(), 1);
      // Then the caller lets go of busy: nothing more happens.
      await tester
          .pumpWidget(_busyHost(false, outcome: RubberBandOutcome.success));
      await tester.pump(const Duration(seconds: 1));
      expect(_state(tester).stretch, 0);
      expect(_busyTicking(tester), isFalse);
      expect(snaps(), 1);
    });

    testWidgets('failure releases softly: never past rest', (tester) async {
      await tester.pumpWidget(_busyHost(true));
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pumpWidget(_busyHost(false));
      final frames = await _record(tester, 800);
      var previous = double.infinity;
      for (final s in frames) {
        expect(s, greaterThanOrEqualTo(-1e-9), reason: 'no overshoot');
        expect(s, lessThanOrEqualTo(previous + 1e-9));
        previous = s;
      }
      await tester.pump(const Duration(seconds: 1));
      expect(_state(tester).stretch, 0);
      expect(_busyTicking(tester), isFalse);
    });

    testWidgets('Reduce Motion: no motion, no clock', (tester) async {
      await tester.pumpWidget(_busyHost(true, reduceMotion: true));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(_state(tester).stretch, 0);
        expect(_busyTicking(tester), isFalse);
      }
      await tester.pumpWidget(_busyHost(true,
          reduceMotion: true, outcome: RubberBandOutcome.success));
      await tester.pump();
      expect(_state(tester).stretch, 0);
      expect(_busyTicking(tester), isFalse);
    });

    testWidgets('at rest, before and after: nothing ticks', (tester) async {
      await tester.pumpWidget(_busyHost(false));
      await tester.pump(const Duration(milliseconds: 200));
      expect(_busyTicking(tester), isFalse);
      await tester.pumpWidget(_busyHost(true));
      await tester.pump(const Duration(milliseconds: 500));
      expect(_busyTicking(tester), isTrue);
      await tester.pumpWidget(_busyHost(false));
      await tester.pump(const Duration(seconds: 2));
      expect(_busyTicking(tester), isFalse);
      expect(_state(tester).stretch, 0);
    });

    testWidgets('covered by a route: nothing ticks', (tester) async {
      await tester
          .pumpWidget(TickerMode(enabled: false, child: _busyHost(true)));
      await tester.pump(const Duration(milliseconds: 500));
      expect(_state(tester).stretch, 0);
      expect(_state(tester).ticking, isFalse);
      // The build's clock is muted with the route's tickers.
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('RubberBand.settle', () {
    Future<Duration> timeSettle(WidgetTester tester, Widget host,
        {RubberBandOutcome outcome = RubberBandOutcome.success}) async {
      await tester.pumpWidget(host);
      final context = tester.element(find.text('Sell'));
      var done = false;
      unawaited(RubberBand.settle(context, outcome: outcome)
          .then((_) => done = true));
      var waited = Duration.zero;
      while (!done && waited < const Duration(seconds: 2)) {
        await tester.pump(const Duration(milliseconds: 10));
        waited += const Duration(milliseconds: 10);
      }
      expect(done, isTrue);
      return waited;
    }

    testWidgets('a success waits for the snap, bounded', (tester) async {
      final waited = await timeSettle(tester, _busyHost(false));
      expect(waited, greaterThanOrEqualTo(const Duration(milliseconds: 300)));
      expect(waited, lessThanOrEqualTo(const Duration(milliseconds: 410)));
    });

    testWidgets('Reduce Motion: no wait', (tester) async {
      final waited =
          await timeSettle(tester, _busyHost(false, reduceMotion: true));
      expect(waited, lessThanOrEqualTo(const Duration(milliseconds: 10)));
    });

    testWidgets('covered by a route: no wait', (tester) async {
      final waited = await timeSettle(
          tester, TickerMode(enabled: false, child: _busyHost(false)));
      expect(waited, lessThanOrEqualTo(const Duration(milliseconds: 10)));
    });
  });

  group('the felt pull (continuous haptic)', () {
    List<String> methods() => [for (final c in log) c.method];
    List<double> updates() => [
          for (final c in log)
            if (c.method == 'update') c.intensity!,
        ];
    int count(String method, [int from = 0]) =>
        log.skip(from).where((c) => c.method == method).length;

    Future<void> frames(WidgetTester tester, Duration total,
        {Duration frame = const Duration(milliseconds: 16)}) async {
      for (var t = Duration.zero; t < total; t += frame) {
        await tester.pump(frame);
      }
    }

    testWidgets(
        'starts low but felt the moment the action starts, rises with the '
        'band, keeps going while it holds, and ends in one stop and the '
        'snap', (tester) async {
      await tester.pumpWidget(_busyHost(false));
      await tester.pump(const Duration(milliseconds: 200));
      expect(log, isEmpty, reason: 'nothing before the tap');

      await tester.pumpWidget(_busyHost(true));
      expect(log.first.method, 'start');
      expect(
          log.first.intensity, closeTo(RubberBandHaptics.startIntensity, 0.02));
      expect(log[1].method, 'tick', reason: 'the tap clicks at once');
      expect(_state(tester).feeling, isTrue);

      await frames(tester, const Duration(seconds: 3));
      final up = updates();
      expect(up.length, greaterThan(60), reason: 'live, about 30 a second');
      expect(up.length, lessThanOrEqualTo(3 * 31),
          reason: 'never above ~30 Hz');
      for (var i = 1; i < up.length; i++) {
        expect(up[i], greaterThanOrEqualTo(up[i - 1]), reason: 'never softer');
      }
      expect(up.last, greaterThan(up.first + 0.2));
      expect(count('stop'), 0, reason: 'continuous while it runs');

      // It worked: the rumble stops, then the whoosh and the snap, once.
      final before = log.length;
      await tester
          .pumpWidget(_busyHost(true, outcome: RubberBandOutcome.success));
      await frames(tester, const Duration(seconds: 1));
      expect(methods().sublist(before), ['stop', 'snap']);
      // The money-success family: the whoosh into the double snap.
      expect(log.last.pattern, same(HapticPatterns.success));
      expect(_state(tester).feeling, isFalse);
      await tester
          .pumpWidget(_busyHost(false, outcome: RubberBandOutcome.success));
      await frames(tester, const Duration(seconds: 1));
      expect(methods().sublist(before), ['stop', 'snap']);
      expect(_busyTicking(tester), isFalse, reason: 'no ticker at rest');
    });

    testWidgets('the rumble follows the steps up, and the ratchet tightens',
        (tester) async {
      await tester.pumpWidget(_host(0.3));
      await frames(tester, const Duration(seconds: 2));
      final low = log.length;
      await frames(tester, const Duration(seconds: 2));
      final lowTicks = count('tick', low);
      final lowLevel = updates().last;

      await tester.pumpWidget(_host(0.95));
      await frames(tester, const Duration(seconds: 2));
      final high = log.length;
      await frames(tester, const Duration(seconds: 2));
      final highTicks = count('tick', high);
      final highLevel = updates().last;

      expect(lowLevel, closeTo(RubberBandHaptics.intensityFor(0.3), 0.03));
      expect(highLevel, closeTo(RubberBandHaptics.intensityFor(0.95), 0.03));
      expect(highLevel, greaterThan(0.9), reason: 'about full near placement');
      expect(highTicks, greaterThan(lowTicks * 2),
          reason: 'the ratchet clicks faster as it tightens');
      final up = updates();
      for (var i = 1; i < up.length; i++) {
        expect(up[i], greaterThanOrEqualTo(up[i - 1]));
      }
      final sharp = [
        for (final c in log)
          if (c.method == 'update') c.sharpness!,
      ];
      expect(sharp.last, greaterThan(sharp.first), reason: 'sharper too');
      // Holding at one step: still felt, never stopped.
      expect(count('stop'), 0);
      expect(count('update', high), greaterThan(30));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'a long wait drops to a heartbeat after 20 s, and the next step '
        'brings the rumble back; a failure stops it with a soft tap',
        (tester) async {
      const frame = Duration(milliseconds: 50);
      await tester.pumpWidget(_host(0.3));
      await frames(tester, const Duration(seconds: 19), frame: frame);
      expect(count('stop'), 0);
      expect(_state(tester).heartbeat, isFalse);

      await frames(tester, const Duration(seconds: 2), frame: frame);
      expect(_state(tester).heartbeat, isTrue);
      final stopAt = methods().indexOf('stop');
      expect(stopAt, greaterThan(0));

      await frames(tester, const Duration(seconds: 5), frame: frame);
      final after = log.sublist(stopAt + 1);
      expect(after.map((c) => c.method).toSet(), {'pulse'},
          reason: 'no rumble, no ratchet: only the heartbeat');
      expect(after.length, inInclusiveRange(5, 7), reason: 'one a second');
      expect(after.first.intensity,
          closeTo(RubberBandHaptics.intensityFor(0.3), 0.03),
          reason: 'at the current level');

      // The next step: the rumble and the ratchet come back.
      final next = log.length;
      await tester.pumpWidget(_host(0.6));
      await frames(tester, const Duration(seconds: 1));
      expect(methods()[next], 'start');
      expect(_state(tester).heartbeat, isFalse);
      expect(count('update', next), greaterThan(10));
      expect(count('tick', next), greaterThan(3));
      expect(count('pulse', next), 0);
      // And the long wait counts again from that step.
      await frames(tester, const Duration(seconds: 15), frame: frame);
      expect(_state(tester).heartbeat, isFalse);
      expect(count('stop', next), 0);

      // It failed: the rumble stops, one soft tap.
      final end = log.length;
      await tester.pumpWidget(_host(0.6, outcome: RubberBandOutcome.failure));
      await frames(tester, const Duration(seconds: 1));
      expect(methods().sublist(end), ['stop', 'softTap']);
      expect(log.last.pattern, same(HapticPatterns.softRelease));
      expect(_state(tester).ticking, isFalse);
    });

    testWidgets('Reduce Motion: no haptic at all', (tester) async {
      await tester.pumpWidget(_busyHost(true, reduceMotion: true));
      await frames(tester, const Duration(seconds: 1));
      await tester.pumpWidget(_busyHost(true,
          reduceMotion: true, outcome: RubberBandOutcome.success));
      await frames(tester, const Duration(milliseconds: 500));
      expect(log, isEmpty);
    });

    testWidgets('covered by a route or in the background: stopped at once',
        (tester) async {
      await tester.pumpWidget(TickerMode(enabled: true, child: _host(0.5)));
      await frames(tester, const Duration(milliseconds: 500));
      expect(_state(tester).feeling, isTrue);

      await tester.pumpWidget(TickerMode(enabled: false, child: _host(0.5)));
      expect(log.last.method, 'stop');
      expect(_state(tester).feeling, isFalse);
      final covered = log.length;
      await tester.pump(const Duration(seconds: 1));
      expect(log.length, covered, reason: 'nothing while covered');

      await tester.pumpWidget(TickerMode(enabled: true, child: _host(0.5)));
      expect(log[covered].method, 'start');
      await frames(tester, const Duration(milliseconds: 300));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(log.last.method, 'stop');
      expect(_state(tester).feeling, isFalse);
      final paused = log.length;
      await tester.pump(const Duration(seconds: 1));
      expect(log.length, paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(log[paused].method, 'start');

      // Gone: stopped.
      await tester.pumpWidget(const SizedBox.shrink());
      expect(log.last.method, 'stop');
    });
  });
}
