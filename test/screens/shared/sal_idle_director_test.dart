// The hero loop with a life (SalIdleDirector, sal_sprite.dart): body_hero,
// a `hero` one-shot cut in every 6–12 s and never the same twice in a row,
// sleep after a minute without a pointer anywhere, wake on the next one;
// a clip that cannot be read is skipped and the loop goes on; under Reduce
// Motion the loop alone. The cut waits for the loop's boundary (the loop
// is 2 s here), the one-shot plays through, and the loop is back: the
// timelines below count in those 2 s beats (sal_seamless_switch_test.dart
// checks the frames themselves).

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/shared/sal_sprite.dart';

/// A manifest entry: 48 frames at 24 fps (2 s), in [group].
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

/// Registers [names] as decoded clips (those in [oneShots] as one-shots)
/// under a manifest that lists them (and [missing], which no sheet backs).
void _stage(List<String> names,
    {Set<String> oneShots = const {}, List<String> missing = const []}) {
  SalSpriteCache.debugSetManifest({
    for (final n in names)
      n: _entry(loop: !oneShots.contains(n), group: n == 'body_hero' ? 'loop' : 'hero'),
    for (final n in missing) n: _entry(loop: false),
  });
  for (final n in names) {
    SalSpriteCache.debugPutClip(n, 2, _sheet(loop: !oneShots.contains(n)));
  }
}

String _clip(WidgetTester tester) =>
    tester.widget<SalSprite>(find.byType(SalSprite).first).clip;

Widget _app(Widget child, {bool reduce = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce, devicePixelRatio: 1),
        child: Center(child: child),
      ),
    );

void main() {
  tearDown(SalSpriteCache.debugReset);

  testWidgets('cuts a hero one-shot into the loop, never the same twice',
      (tester) async {
    _stage(['body_hero', 'hero_stretch', 'hero_scratch'],
        oneShots: {'hero_stretch', 'hero_scratch'});
    await tester.pumpWidget(_app(SalIdleDirector(
      size: 120,
      fallback: const SizedBox(),
      minGap: const Duration(seconds: 1),
      maxGap: const Duration(seconds: 1),
      sleepAfter: const Duration(minutes: 5),
      random: math.Random(3),
    )));
    await tester.pump();
    await tester.pump();
    expect(_clip(tester), 'body_hero');

    final seen = <String>[];
    for (var i = 0; i < 4; i++) {
      // Each beat: the loop from 0, the cue at 1 s (the one-shot asked
      // for, the loop still on screen), the cut at the loop's boundary
      // (2 s), the one-shot through (48 frames at 24 fps) at 4 s, the
      // loop again and the next cue a second later.
      await tester.pump(const Duration(milliseconds: 1050));
      final clip = _clip(tester);
      expect(clip, isNot('body_hero'), reason: 'cut $i');
      expect(clip, anyOf('hero_stretch', 'hero_scratch'));
      seen.add(clip);
      await tester.pump(const Duration(milliseconds: 950));
      await tester.pump(const Duration(milliseconds: 2000));
      expect(_clip(tester), 'body_hero', reason: 'back after cut $i');
    }
    for (var i = 1; i < seen.length; i++) {
      expect(seen[i], isNot(seen[i - 1]), reason: 'never twice in a row');
    }
  });

  testWidgets('a clip that cannot be read is skipped; the loop goes on',
      (tester) async {
    _stage(['body_hero'], missing: ['hero_missing']);
    await tester.pumpWidget(_app(SalIdleDirector(
      size: 120,
      fallback: const SizedBox(),
      minGap: const Duration(seconds: 1),
      maxGap: const Duration(seconds: 1),
      sleepAfter: const Duration(minutes: 5),
      random: math.Random(1),
    )));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1050));
    // The read fails (real I/O), and the director is told.
    await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 200)));
    await tester.pump();
    expect(_clip(tester), 'body_hero');
    // Dropped from the pool: the next cue finds nothing to cut in.
    await tester.pump(const Duration(milliseconds: 1050));
    await tester.pump();
    expect(_clip(tester), 'body_hero');
    expect(tester.takeException(), isNull);
  });

  testWidgets('sleeps after a while without a pointer, wakes on the next',
      (tester) async {
    _stage(['body_hero', 'hero_sleep', 'hero_wake'], oneShots: {'hero_wake'});
    await tester.pumpWidget(_app(SalIdleDirector(
      size: 120,
      fallback: const SizedBox(),
      sleepAfter: const Duration(seconds: 3),
      random: math.Random(1),
    )));
    await tester.pump();
    await tester.pump();
    expect(_clip(tester), 'body_hero');
    await tester.pump(const Duration(seconds: 2));
    expect(_clip(tester), 'body_hero');
    await tester.pump(const Duration(milliseconds: 1100));
    expect(_clip(tester), 'hero_sleep');
    // Still asleep until something touches the screen (anywhere).
    await tester.pump(const Duration(seconds: 5));
    expect(_clip(tester), 'hero_sleep');
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    expect(_clip(tester), 'hero_wake');
    // The sleep loop took over at the hero's boundary (4 s) and comes
    // round at 10 s: the wake cuts in there, plays through (2 s), and the
    // hero is back at 12 s.
    await tester.pump(const Duration(milliseconds: 1900));
    expect(_clip(tester), 'hero_wake');
    await tester.pump(const Duration(milliseconds: 2000));
    expect(_clip(tester), 'body_hero');
  });

  testWidgets('Reduce Motion: the loop alone, no cuts, no sleep',
      (tester) async {
    _stage(['body_hero', 'hero_stretch', 'hero_sleep'],
        oneShots: {'hero_stretch'});
    await tester.pumpWidget(_app(
        SalIdleDirector(
          size: 120,
          fallback: const SizedBox(),
          minGap: const Duration(seconds: 1),
          maxGap: const Duration(seconds: 1),
          sleepAfter: const Duration(seconds: 2),
          random: math.Random(1),
        ),
        reduce: true));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(_clip(tester), 'body_hero');
  });
}
