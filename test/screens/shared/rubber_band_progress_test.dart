import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/shared/rubber_band_progress.dart';

Widget _host(double progress,
    {RubberBandOutcome outcome = RubberBandOutcome.none,
    bool reduceMotion = false,
    VoidCallback? onReleased}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RubberBandProgress(
          progress: progress,
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

/// Two seconds of 60 fps frames, as a phone draws them.
Future<void> _frames60(WidgetTester tester) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
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
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
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
    expect(
        calls.where((c) =>
            c.method == 'HapticFeedback.vibrate' &&
            c.arguments == 'HapticFeedbackType.heavyImpact'),
        hasLength(1));
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
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call);
        return null;
      });
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
      expect(
          calls.where((c) =>
              c.method == 'HapticFeedback.vibrate' &&
              c.arguments == 'HapticFeedbackType.heavyImpact'),
          hasLength(1));
      // Then the caller lets go of busy: nothing more happens.
      await tester
          .pumpWidget(_busyHost(false, outcome: RubberBandOutcome.success));
      await tester.pump(const Duration(seconds: 1));
      expect(_state(tester).stretch, 0);
      expect(_busyTicking(tester), isFalse);
      expect(
          calls.where((c) =>
              c.method == 'HapticFeedback.vibrate' &&
              c.arguments == 'HapticFeedbackType.heavyImpact'),
          hasLength(1));
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

  testWidgets(
      'the pull is felt as a continuous stream of taps that grows stronger '
      'as it tightens, goes quiet while it holds, and ends in one heavy '
      'thud', (tester) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    List<String> taps() => [
          for (final c in calls)
            if (c.method == 'HapticFeedback.vibrate') c.arguments as String,
        ];
    const rank = {
      'HapticFeedbackType.selectionClick': 0,
      'HapticFeedbackType.lightImpact': 1,
      'HapticFeedbackType.mediumImpact': 2,
    };

    await tester.pumpWidget(_host(0.3));
    await _frames60(tester);
    final early = taps().length;
    expect(early, greaterThan(3), reason: 'a stream, not a single tap');
    expect(
        taps().every((t) => t == 'HapticFeedbackType.selectionClick'), isTrue,
        reason: 'low tension: the lightest taps');

    await tester.pumpWidget(_host(0.95));
    await _frames60(tester);
    final all = taps();
    expect(all.length, greaterThan(early + 5));
    // Never weaker than the tap before it.
    for (var i = 1; i < all.length; i++) {
      expect(rank[all[i]]!, greaterThanOrEqualTo(rank[all[i - 1]]!));
    }
    expect(all.last, 'HapticFeedbackType.mediumImpact',
        reason: 'near full tension: the strongest pull taps');

    // Holding: quiet.
    final held = taps().length;
    await tester.pump(const Duration(seconds: 2));
    expect(taps().length, held);

    // Success: one heavy thud and nothing else.
    await tester.pumpWidget(_host(0.95, outcome: RubberBandOutcome.success));
    await _frames60(tester);
    final after = taps().sublist(held);
    expect(after, ['HapticFeedbackType.heavyImpact']);
  });
}
