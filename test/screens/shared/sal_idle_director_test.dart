// The empty states' Sal (SalIdleDirector, sal_sprite.dart; founder, 12
// November 2026: "an occasional blink/stretch on a slow random cadence,
// not constant motion"): still in the hero pose, one beat every 8–15 s
// (a pass of body_hero, his blink; a look around; a stretch), played once
// and held, never the same twice in a row; nothing moves between beats;
// the beats stop off screen, in the background and once he is gone; sleep
// after a minute without a pointer, wake on the next one; a clip that
// cannot be read is skipped; under Reduce Motion the hero's first frame
// alone. The clock is the test's fake one: every beat is timed by it.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/shared/sal_sprite.dart';

/// A manifest entry: 48 frames at 24 fps (2 s).
Map<String, dynamic> _entry({bool loop = true, String group = 'hero'}) => {
      'framing': 'body',
      'fps': 24,
      'frames': 48,
      'columns': 8,
      'rows': 6,
      'loop': loop,
      'group': group,
      'files': {
        '2x': {'file': 'none@2x.webp'},
        '3x': {'file': 'none@3x.webp'},
      },
    };

/// A sheet of that shape, drawn here (no asset read; tests never decode).
SalClip _sheet({bool loop = true}) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 64, 48), Paint()..color = Colors.brown);
  final image = recorder.endRecording().toImageSync(64, 48);
  return SalClip(
      image: image,
      fps: 24,
      frames: 48,
      columns: 8,
      cellWidth: 8,
      cellHeight: 8,
      loop: loop,
      body: true);
}

/// The beats, the sleep and the wake, decoded (the hero loop and the
/// sleep loop; the rest one-shots), plus [missing], which no sheet backs.
void _stage(
    {List<String> names = const [
      'body_hero',
      'hero_look_around',
      'hero_stretch',
    ],
    List<String> missing = const []}) {
  const oneShots = {'hero_stretch', 'hero_wake'};
  SalSpriteCache.debugSetManifest({
    for (final n in names) n: _entry(loop: !oneShots.contains(n)),
    for (final n in missing) n: _entry(loop: false),
  });
  for (final n in names) {
    SalSpriteCache.debugPutClip(n, 2, _sheet(loop: !oneShots.contains(n)));
  }
}

String _clip(WidgetTester tester) =>
    tester.widget<SalSprite>(find.byType(SalSprite).first).clip;

/// What the sprite draws now.
SalSpriteFrame? _drawn(WidgetTester tester) =>
    // ignore: avoid_dynamic_calls
    (tester.state(find.byType(SalSprite)) as dynamic).debugFrame
        as SalSpriteFrame?;

Widget _app(Widget child, {bool reduce = false, bool ticking = true}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce, devicePixelRatio: 1),
        child: TickerMode(enabled: ticking, child: Center(child: child)),
      ),
    );

SalIdleDirector _director({
  Duration minGap = const Duration(seconds: 8),
  Duration maxGap = const Duration(seconds: 15),
  Duration sleepAfter = const Duration(minutes: 5),
  int seed = 3,
}) =>
    SalIdleDirector(
      size: 120,
      fallback: const SizedBox(),
      minGap: minGap,
      maxGap: maxGap,
      sleepAfter: sleepAfter,
      random: math.Random(seed),
    );

/// Pumps 100 ms at a time for [span]; returns when (ms from the start)
/// each new beat began (a new cue: the clip asked for from frame 0).
Future<List<(int, String)>> _watch(WidgetTester tester, Duration span) async {
  final beats = <(int, String)>[];
  var cue = tester.widget<SalSprite>(find.byType(SalSprite)).cue;
  for (var ms = 100; ms <= span.inMilliseconds; ms += 100) {
    await tester.pump(const Duration(milliseconds: 100));
    final sprite = tester.widget<SalSprite>(find.byType(SalSprite));
    if (sprite.cue != cue) {
      cue = sprite.cue;
      beats.add((ms, sprite.clip));
    }
  }
  return beats;
}

void main() {
  tearDown(SalSpriteCache.debugReset);

  testWidgets(
      'still in the hero pose: nothing moves until the first beat, 8–15 s '
      'in', (tester) async {
    _stage();
    SalSprite.debugPaintLog = [];
    addTearDown(() => SalSprite.debugPaintLog = null);
    await tester.pumpWidget(_app(_director()));
    await tester.pump();
    expect(_clip(tester), 'body_hero');
    for (var i = 0; i < 7; i++) {
      await tester.pump(const Duration(seconds: 1));
      expect(tester.hasRunningAnimations, isFalse,
          reason: 'no ticker between beats (${i + 1} s)');
    }
    expect(SalSprite.debugPaintLog!.map((f) => (f.name, f.frame)).toSet(),
        {('body_hero', 0)},
        reason: 'one still frame, the hero pose');
    final beats = await _watch(tester, const Duration(seconds: 9));
    expect(beats, isNotEmpty, reason: 'a beat by 15 s');
    expect(beats.first.$1 + 7000, inInclusiveRange(8000, 15200));
  });

  testWidgets(
      'the cadence on the fake clock: every beat 8–15 s after the last one '
      'came to rest, played once and held, never the same twice in a row',
      (tester) async {
    _stage();
    await tester.pumpWidget(_app(_director(seed: 7)));
    await tester.pump();
    final beats = await _watch(tester, const Duration(seconds: 90));
    expect(beats.length, greaterThanOrEqualTo(5));
    // Each beat plays 2 s and rests; the next comes 8–15 s after that.
    var restAt = 0;
    for (final (at, clip) in beats) {
      expect(at - restAt, inInclusiveRange(7800, 15200),
          reason: '$clip at $at ms, rest from $restAt ms');
      restAt = at + 2000;
    }
    for (var i = 1; i < beats.length; i++) {
      expect(beats[i].$2, isNot(beats[i - 1].$2), reason: 'never twice');
    }
    expect({for (final b in beats) b.$2},
        everyElement(anyOf('body_hero', 'hero_look_around', 'hero_stretch')));
  });

  testWidgets(
      'a beat plays once and holds its last frame: nothing moves after it',
      (tester) async {
    _stage();
    await tester.pumpWidget(_app(_director(
        minGap: const Duration(seconds: 8),
        maxGap: const Duration(seconds: 8))));
    await tester.pump();
    await tester.pump(const Duration(seconds: 8));
    await tester.pump();
    expect(tester.hasRunningAnimations, isTrue, reason: 'the beat plays');
    final clip = _clip(tester);
    expect(SalSpotlight.held, isTrue, reason: 'his beat holds the spotlight');
    await tester.pump(const Duration(milliseconds: 2100));
    await tester.pump();
    expect(_clip(tester), clip);
    expect(_drawn(tester)?.frame, 47, reason: 'the last frame, held');
    expect(tester.hasRunningAnimations, isFalse);
    expect(SalSpotlight.held, isFalse, reason: 'given back at rest');
    await tester.pump(const Duration(seconds: 5));
    expect(_drawn(tester)?.frame, 47);
  });

  testWidgets('another Sal performing: the beat waits for its next turn',
      (tester) async {
    _stage();
    final toast = Object();
    SalSpotlight.hold(toast);
    await tester.pumpWidget(_app(_director()));
    await tester.pump();
    final beats = await _watch(tester, const Duration(seconds: 40));
    expect(beats, isEmpty);
    SalSpotlight.release(toast);
    final after = await _watch(tester, const Duration(seconds: 16));
    expect(after, isNotEmpty, reason: 'free again: the next turn plays');
  });

  testWidgets(
      'off screen (TickerMode off) and in the background nothing is timed; '
      'back, the beats come again', (tester) async {
    _stage();
    final director = _director();
    await tester.pumpWidget(_app(director, ticking: false));
    await tester.pump();
    expect(await _watch(tester, const Duration(seconds: 40)), isEmpty,
        reason: 'off screen');

    await tester.pumpWidget(_app(director));
    expect(await _watch(tester, const Duration(seconds: 16)), isNotEmpty,
        reason: 'on screen again');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 3));
    expect(await _watch(tester, const Duration(seconds: 40)), isEmpty,
        reason: 'in the background');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(await _watch(tester, const Duration(seconds: 16)), isNotEmpty,
        reason: 'in front again');
  });

  testWidgets('gone: no timer outlives him, the spotlight is free',
      (tester) async {
    _stage();
    await tester.pumpWidget(_app(_director(
        minGap: const Duration(seconds: 8),
        maxGap: const Duration(seconds: 8))));
    await tester.pump();
    await tester.pump(const Duration(seconds: 8));
    await tester.pump();
    expect(SalSpotlight.held, isTrue, reason: 'mid-beat');
    await tester.pumpWidget(_app(const SizedBox()));
    await tester.pump();
    expect(SalSpotlight.held, isFalse);
    // The fake clock runs on: nothing fires (a pending timer would fail
    // the test at its end).
    await tester.pump(const Duration(minutes: 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a clip that cannot be read is skipped; he stays still',
      (tester) async {
    _stage(names: ['body_hero'], missing: ['hero_look_around']);
    await tester.pumpWidget(_app(_director(seed: 1)));
    await tester.pump();
    // The warm-up's read fails (real I/O), and the director is told.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    final beats = await _watch(tester, const Duration(seconds: 40));
    expect(beats.map((b) => b.$2), everyElement('body_hero'));
    expect(_clip(tester), 'body_hero');
    expect(tester.takeException(), isNull);
  });

  testWidgets('sleeps after a while without a pointer, wakes on the next',
      (tester) async {
    _stage(names: ['body_hero', 'hero_sleep', 'hero_wake']);
    await tester.pumpWidget(_app(_director(
        minGap: const Duration(minutes: 5),
        maxGap: const Duration(minutes: 5),
        sleepAfter: const Duration(seconds: 3))));
    await tester.pump();
    await tester.pump();
    expect(_clip(tester), 'body_hero');
    await tester.pump(const Duration(seconds: 2));
    expect(_clip(tester), 'body_hero');
    await tester.pump(const Duration(milliseconds: 1100));
    expect(_clip(tester), 'hero_sleep');
    // Still asleep until something touches the screen (anywhere).
    await _watch(tester, const Duration(seconds: 2));
    expect(_clip(tester), 'hero_sleep');
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    expect(_clip(tester), 'hero_wake');
    // The sleep loop comes round (its 2 s beat), the wake plays through
    // (2 s) and he holds its last frame, still.
    await _watch(tester, const Duration(milliseconds: 2900));
    expect(_clip(tester), 'hero_wake');
    expect(_drawn(tester)?.frame, 47);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('Reduce Motion: the hero\'s first frame, no beats, no sleep',
      (tester) async {
    _stage(names: ['body_hero', 'hero_stretch', 'hero_sleep']);
    await tester.pumpWidget(_app(
        _director(
            minGap: const Duration(seconds: 1),
            maxGap: const Duration(seconds: 1),
            sleepAfter: const Duration(seconds: 2)),
        reduce: true));
    await tester.pump();
    await tester.pump();
    final beats = await _watch(tester, const Duration(seconds: 20));
    expect(beats, isEmpty);
    expect(_clip(tester), 'body_hero');
    expect(_drawn(tester)?.frame, 0);
    expect(tester.hasRunningAnimations, isFalse);
  });
}
