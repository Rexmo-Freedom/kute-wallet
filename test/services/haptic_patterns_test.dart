// The app's named haptic moments on the native engine: each routed
// through the bridge with its own shape (Instagram's structure, our
// values), the gates still in front of them, the money-success family
// shared with the rubber band's release, and today's beats as the
// fallback.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/continuous_haptics.dart';
import 'package:kute/services/haptic_patterns.dart';
import 'package:kute/services/kute_haptics.dart';
import 'package:kute/services/success_feedback.dart';

List<HapticEvent> _transients(HapticPattern p) => [
      for (final e in p.events)
        if (e.kind == HapticEventKind.transient) e
    ];

List<HapticEvent> _continuous(HapticPattern p) => [
      for (final e in p.events)
        if (e.kind == HapticEventKind.continuous) e
    ];

/// The intensity curve's value at [ms] (1 without one).
double _control(HapticPattern p, int ms) {
  for (final c in p.curves) {
    if (c.parameter == HapticCurveParameter.intensity) return c.valueAt(ms);
  }
  return 1;
}

/// What an event actually plays at [ms], under the intensity curve.
double _felt(HapticPattern p, HapticEvent e, int ms) =>
    e.intensity * _control(p, ms);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<ContinuousHapticsCall> log;
  late DateTime now;
  var foreground = true;

  setUp(() {
    KuteHaptics.debugReset();
    ContinuousHaptics.debugReset();
    log = ContinuousHaptics.debugLog = [];
    now = DateTime(2026, 10, 14, 12);
    foreground = true;
    KuteHaptics.debugNow = () => now;
    KuteHaptics.debugForeground = () => foreground;
  });
  tearDown(() {
    KuteHaptics.debugReset();
    ContinuousHaptics.debugLog = null;
  });

  void advance(int ms) => now = now.add(Duration(milliseconds: ms));

  group('the shapes', () {
    test(
        'success: a whoosh swelling up, then a double snap, the second '
        'the full one', () {
      const p = HapticPatterns.success;
      expect(p.events.first.kind, HapticEventKind.continuous);
      final swell = p.events.first;
      expect(_felt(p, swell, 0), lessThan(0.2));
      expect(_felt(p, swell, 90), greaterThan(_felt(p, swell, 0) * 4));
      final snaps = _transients(p);
      expect(snaps, hasLength(2));
      expect(snaps.first.atMs, greaterThanOrEqualTo(swell.endMs));
      expect(snaps.last.atMs - snaps.first.atMs, inInclusiveRange(70, 110));
      expect(_felt(p, snaps.last, snaps.last.atMs), 1);
      expect(snaps.last.sharpness, 1);
      expect(_felt(p, snaps.first, snaps.first.atMs),
          lessThan(_felt(p, snaps.last, snaps.last.atMs)));
      expect(p.duration, lessThan(const Duration(milliseconds: 300)));
    });

    test('moneyIn: a soft rising swell, one clean snap, ~0.4 s', () {
      const p = HapticPatterns.moneyIn;
      final swell = _continuous(p).first;
      expect(p.events.first, same(swell));
      expect(_felt(p, swell, 0), lessThan(0.1));
      expect(_felt(p, swell, 250), greaterThan(0.5));
      final snaps = _transients(p);
      expect(snaps, hasLength(1));
      expect(snaps.single.atMs, greaterThanOrEqualTo(swell.endMs));
      expect(_felt(p, snaps.single, snaps.single.atMs), greaterThan(0.8));
      expect(snaps.single.sharpness, greaterThan(0.6));
      final tail = _continuous(p).last;
      expect(_felt(p, tail, tail.endMs), lessThan(_felt(p, tail, tail.atMs)),
          reason: 'it fades');
      expect(p.duration.inMilliseconds, inInclusiveRange(350, 450));
    });

    test('oddsTick: one very light, very sharp tick', () {
      const p = HapticPatterns.oddsTick;
      expect(p.events, hasLength(1));
      expect(p.events.single.kind, HapticEventKind.transient);
      expect(p.events.single.intensity, lessThanOrEqualTo(0.35));
      expect(p.events.single.sharpness, greaterThanOrEqualTo(0.9));
    });

    test('heartbeat: lub-dub, soft and dull, with a tiny tail', () {
      const p = HapticPatterns.heartbeat;
      final beats = _transients(p);
      expect(beats, hasLength(2));
      expect(beats.first.intensity, greaterThan(beats.last.intensity));
      for (final b in beats) {
        expect(b.sharpness, lessThanOrEqualTo(0.2));
        expect(b.intensity, lessThanOrEqualTo(0.65));
      }
      final tail = _continuous(p).single;
      expect(tail.atMs, greaterThanOrEqualTo(beats.last.atMs));
      expect(tail.durationMs, lessThanOrEqualTo(120));
      expect(_felt(p, tail, tail.endMs), lessThan(0.05), reason: 'fades');
    });

    test('legWon: two bright ticks and a shimmer that fades', () {
      const p = HapticPatterns.legWon;
      final ticks = _transients(p);
      expect(ticks, hasLength(2));
      expect(ticks.last.intensity, greaterThanOrEqualTo(ticks.first.intensity));
      for (final t in ticks) {
        expect(t.sharpness, greaterThanOrEqualTo(0.85));
      }
      final shimmer = _continuous(p).single;
      expect(shimmer.atMs, greaterThanOrEqualTo(ticks.last.atMs));
      expect(shimmer.sharpness, greaterThanOrEqualTo(0.8));
      expect(_felt(p, shimmer, shimmer.endMs), lessThan(0.05));
    });

    test('legLost: one soft, dull thud that fades', () {
      const p = HapticPatterns.legLost;
      expect(_transients(p), hasLength(1));
      expect(_transients(p).single.sharpness, lessThanOrEqualTo(0.1));
      expect(_transients(p).single.intensity, lessThanOrEqualTo(0.55));
      final fade = _continuous(p).single;
      expect(_felt(p, fade, fade.endMs), lessThan(_felt(p, fade, 0)));
      expect(fade.sharpness, lessThanOrEqualTo(0.1));
    });

    test('fill: a brief whoosh, then a firm snap', () {
      const p = HapticPatterns.fill;
      final whoosh = p.events.first;
      expect(whoosh.kind, HapticEventKind.continuous);
      expect(_felt(p, whoosh, 100), greaterThan(_felt(p, whoosh, 0) * 4));
      final snap = _transients(p).single;
      expect(snap.atMs, greaterThanOrEqualTo(whoosh.endMs));
      expect(_felt(p, snap, snap.atMs), greaterThanOrEqualTo(0.9));
      expect(p.duration, lessThan(const Duration(milliseconds: 200)));
    });

    test(
        'notice: one light tap; warning: three hard sharp hits, closer and '
        'firmer', () {
      const notice = HapticPatterns.notice;
      const warning = HapticPatterns.warning;
      expect(notice.events, hasLength(1));
      expect(notice.events.single.kind, HapticEventKind.transient);
      final hits = _transients(warning);
      expect(warning.events, hasLength(3));
      expect(hits, hasLength(3));
      for (final h in hits) {
        expect(h.intensity, 1);
        expect(h.intensity, greaterThan(notice.events.single.intensity));
        expect(h.sharpness, greaterThanOrEqualTo(0.85));
      }
      expect(hits[1].atMs - hits[0].atMs, lessThan(90),
          reason: 'closer than before');
      expect(hits[2].atMs - hits[1].atMs, hits[1].atMs - hits[0].atMs);
    });

    test('every moment has its own shape', () {
      final maps = {
        for (final k in KuteHaptic.values) k: k.pattern.toMap().toString(),
      };
      expect(maps.values.toSet(), hasLength(KuteHaptic.values.length));
      expect(maps.values,
          isNot(contains(HapticPatterns.success.toMap().toString())));
    });

    test('Android renders the same events: a swell rises, the snap peaks', () {
      for (final p in [
        HapticPatterns.success,
        HapticPatterns.softRelease,
        for (final k in KuteHaptic.values) k.pattern,
      ]) {
        final w = p.androidWaveform;
        expect(w.timings.length, w.amplitudes.length, reason: p.name);
        expect(w.timings.fold<int>(0, (a, b) => a + b),
            closeTo(p.duration.inMilliseconds, HapticPattern.stepMs),
            reason: p.name);
        for (final a in w.amplitudes) {
          expect(a, inInclusiveRange(0, 255), reason: p.name);
        }
      }
      final w = HapticPatterns.success.androidWaveform;
      // The swell's first segments rise, and the last hit is full.
      final swell = <int>[];
      var t = 0;
      for (var i = 0; i < w.timings.length && t < 95; i++) {
        swell.add(w.amplitudes[i]);
        t += w.timings[i];
      }
      for (var i = 1; i < swell.length; i++) {
        expect(swell[i], greaterThanOrEqualTo(swell[i - 1]));
      }
      expect(swell.first, lessThan(40));
      expect(w.amplitudes.reduce((a, b) => a > b ? a : b), 255);
      // The warning's three hits are three separate bursts.
      final warn = HapticPatterns.warning.androidWaveform.amplitudes;
      expect(warn.where((a) => a == 255), hasLength(3));
    });
  });

  group('routed through the bridge', () {
    test('each named moment plays its own pattern', () async {
      for (final k in KuteHaptic.values) {
        log.clear();
        advance(10000);
        expect(await KuteHaptics.play(k), isTrue, reason: k.name);
        expect(log.single.method, 'pattern', reason: k.name);
        expect(log.single.pattern, same(k.pattern), reason: k.name);
      }
    });

    test('the gates still work: background, minimum gap, one at a time',
        () async {
      foreground = false;
      expect(await KuteHaptics.play(KuteHaptic.fill), isFalse);
      expect(log, isEmpty);
      foreground = true;

      expect(await KuteHaptics.play(KuteHaptic.oddsTick), isTrue);
      advance(KuteHaptic.oddsTick.minGapMs - 1);
      expect(await KuteHaptics.play(KuteHaptic.oddsTick), isFalse);

      // Held while it plays: another pattern asked for then is dropped.
      final warning = KuteHaptics.play(KuteHaptic.warning);
      expect(await KuteHaptics.play(KuteHaptic.notice), isFalse);
      expect(await warning, isTrue);
      expect([for (final c in log) c.pattern!.name], ['oddsTick', 'warning']);
    });

    test('the money-success beat is the success pattern', () async {
      await moneySuccessFeedback();
      expect(log.single.pattern, same(HapticPatterns.success));
    });

    test(
        "a band's success release is the money-success moment: the beat "
        'right after it and money arriving stay quiet', () async {
      KuteHaptics.noteSuccessRelease();
      advance(500);
      await moneySuccessFeedback();
      expect(log, isEmpty, reason: 'one success, not two');
      expect(await KuteHaptics.play(KuteHaptic.moneyIn), isFalse);
      advance(KuteHaptics.successAfterRelease.inMilliseconds);
      await moneySuccessFeedback();
      expect(log.single.pattern, same(HapticPatterns.success));
    });

    test('money arriving and the success beat still de-dupe', () async {
      expect(await KuteHaptics.play(KuteHaptic.moneyIn), isTrue);
      advance(1000);
      await moneySuccessFeedback();
      expect([for (final c in log) c.pattern!.name], ['moneyIn']);
    });
  });

  group('without the native engine', () {
    late List<MethodCall> system;
    setUp(() {
      ContinuousHaptics.debugLog = null;
      system = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        system.add(call);
        return null;
      });
    });
    tearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    List<Object?> impacts() => [
          for (final c in system)
            if (c.method == 'HapticFeedback.vibrate') c.arguments,
        ];

    test("a moment falls back to today's beat", () async {
      expect(await KuteHaptics.play(KuteHaptic.notice), isTrue);
      expect(impacts(), ['HapticFeedbackType.lightImpact']);
    });

    test("the money-success beat falls back to today's two beats", () async {
      await moneySuccessFeedback();
      expect(impacts(), [
        'HapticFeedbackType.mediumImpact',
        'HapticFeedbackType.heavyImpact',
      ]);
    });

    test('a device that answers no plays the fallback too', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ContinuousHaptics.channel, (call) async {
        return call.method == 'pattern' ? false : null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ContinuousHaptics.channel, null));
      expect(await KuteHaptics.play(KuteHaptic.fill), isTrue);
      expect(impacts(), ['HapticFeedbackType.mediumImpact']);
    });

    test('a device that plays it sends the events and the waveform', () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ContinuousHaptics.channel, (call) async {
        calls.add(call);
        return true;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ContinuousHaptics.channel, null));
      expect(await KuteHaptics.play(KuteHaptic.moneyIn), isTrue);
      expect(impacts(), isEmpty);
      final args = calls.single.arguments as Map;
      expect(calls.single.method, 'pattern');
      expect((args['events'] as List).first['type'], 'continuous');
      expect((args['curves'] as List), isNotEmpty);
      expect(args['timings'], isA<List>());
      expect((args['timings'] as List).length,
          (args['amplitudes'] as List).length);
    });
  });
}
