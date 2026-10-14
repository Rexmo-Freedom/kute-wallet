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

/// Pumps until the band's level settles (the breathing keeps ticking).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  test('the tension is monotonic and steepest at the end', () {
    final values = [for (var i = 0; i <= 10; i++) rubberBandStretchFor(i / 10)];
    for (var i = 1; i < values.length; i++) {
      expect(values[i], greaterThan(values[i - 1]));
    }
    // The last step pulls harder than the first.
    expect(values[10] - values[9], greaterThan(values[1] - values[0]));
    expect(values.first, 0);
    expect(values.last, closeTo(RubberBandProgress.defaultMaxStretch, 1e-9));
    expect(values.last, inInclusiveRange(0.06, 0.10));
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
            c.arguments == 'HapticFeedbackType.lightImpact'),
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
    // At most ~8% of the 100 px block.
    expect(rest - y, lessThanOrEqualTo(8 + 100 * RubberBandProgress.breath));
  });
}
