// The money-failure haptic (founder decision, 15 October 2026): the soft
// tap a bet's or an order's rubber band plays when it lets go without
// also plays when a send, a Move or a receive request fails. Once per
// failure, only in the foreground, never doubled by a band that already
// released, and on a send only after the Send block's band has let go.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/shared/rubber_band_progress.dart';
import 'package:kute/services/continuous_haptics.dart';
import 'package:kute/services/haptic_patterns.dart';
import 'package:kute/services/kute_haptics.dart';
import 'package:kute/services/success_feedback.dart';

List<ContinuousHapticsCall> _log() {
  ContinuousHaptics.debugReset();
  KuteHaptics.debugReset();
  final log = <ContinuousHapticsCall>[];
  ContinuousHaptics.debugLog = log;
  addTearDown(() {
    ContinuousHaptics.debugLog = null;
    ContinuousHaptics.debugReset();
    KuteHaptics.debugReset();
  });
  return log;
}

int _softTaps(List<ContinuousHapticsCall> log) =>
    log.where((c) => c.method == 'softTap').length;

Widget _band(RubberBandOutcome outcome,
        {bool failureTap = true, double progress = 0.6}) =>
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: RubberBandProgress(
            progress: progress,
            outcome: outcome,
            failureTap: failureTap,
            child: const SizedBox(width: 200, height: 80),
          ),
        ),
      ),
    );

Future<void> _frames(WidgetTester tester, Duration total) async {
  const frame = Duration(milliseconds: 16);
  for (var t = Duration.zero; t < total; t += frame) {
    await tester.pump(frame);
  }
}

void main() {
  group('moneyFailureFeedback', () {
    test('plays the soft release once, through the band\'s own path', () async {
      final log = _log();
      await moneyFailureFeedback();
      expect(log.map((c) => c.method), ['softTap']);
      expect(log.single.pattern, same(HapticPatterns.softRelease));
    });

    test('one failure, one tap: a second path reporting it stays quiet',
        () async {
      final log = _log();
      var now = DateTime(2026, 10, 15, 12);
      KuteHaptics.debugNow = () => now;
      await moneyFailureFeedback();
      await moneyFailureFeedback();
      expect(_softTaps(log), 1);
      // A new failure later taps again.
      now = now.add(KuteHaptics.failureAfterRelease);
      await moneyFailureFeedback();
      expect(_softTaps(log), 2);
    });

    test('never in the background', () async {
      final log = _log();
      KuteHaptics.debugForeground = () => false;
      await moneyFailureFeedback();
      expect(log, isEmpty);
    });

    test('a band that just released the soft tap is not doubled', () async {
      final log = _log();
      KuteHaptics.noteFailureRelease();
      await moneyFailureFeedback();
      expect(log, isEmpty);
    });
  });

  group('the rubber band', () {
    testWidgets('a release without taps once and marks the moment',
        (tester) async {
      final log = _log();
      await tester.pumpWidget(_band(RubberBandOutcome.none));
      await _frames(tester, const Duration(milliseconds: 600));
      await tester.pumpWidget(_band(RubberBandOutcome.failure));
      await _frames(tester, const Duration(milliseconds: 600));
      expect(_softTaps(log), 1);
      // The screen reporting the same failure right after: no second tap.
      await moneyFailureFeedback();
      expect(_softTaps(log), 1);
    });

    testWidgets('failureTap: false lets go with no tap (the send\'s band)',
        (tester) async {
      final log = _log();
      await tester.pumpWidget(_band(RubberBandOutcome.none, failureTap: false));
      await _frames(tester, const Duration(milliseconds: 600));
      expect(log.map((c) => c.method), contains('start'));
      await tester
          .pumpWidget(_band(RubberBandOutcome.failure, failureTap: false));
      await _frames(tester, const Duration(milliseconds: 600));
      expect(_softTaps(log), 0);
      expect(log.last.method, 'stop', reason: 'the rumble still stops');
    });
  });

  group('moneyFailureFeedbackAfterBand', () {
    testWidgets(
        'waits while the send is busy, then taps once, after the band has '
        'let go and its rumble stopped', (tester) async {
      final log = _log();
      var busy = true;
      late StateSetter set;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(builder: (context, setState) {
            set = setState;
            return RubberBandProgress(
              progress: busy ? 0.6 : 0,
              outcome:
                  busy ? RubberBandOutcome.none : RubberBandOutcome.failure,
              failureTap: false,
              child: const SizedBox(width: 200, height: 80),
            );
          }),
        ),
      ));
      await _frames(tester, const Duration(milliseconds: 600));

      // The failure is known while busy is still up.
      moneyFailureFeedbackAfterBand(() => busy);
      await _frames(tester, const Duration(milliseconds: 300));
      expect(_softTaps(log), 0, reason: 'not under the rumble');

      set(() => busy = false);
      await _frames(tester, const Duration(milliseconds: 300));
      expect(_softTaps(log), 1);
      final methods = log.map((c) => c.method).toList();
      expect(methods.lastIndexOf('stop'), lessThan(methods.indexOf('softTap')),
          reason: 'the rumble stops first');
      await _frames(tester, const Duration(seconds: 1));
      expect(_softTaps(log), 1);
    });

    testWidgets('not busy: taps after the next frame', (tester) async {
      final log = _log();
      await tester.pumpWidget(const SizedBox());
      moneyFailureFeedbackAfterBand(() => false);
      expect(log, isEmpty);
      await tester.pump();
      expect(_softTaps(log), 1);
    });
  });
}
