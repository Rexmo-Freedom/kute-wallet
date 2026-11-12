// One continuous performance (sal_sprite.dart; founder, 31 October 2026:
// "the animation should loop, not stop and load a new one"). The sprite
// switches clips in place, on one ticker: every tick draws a cell (never
// an empty frame), a one-shot cuts in only as the loop comes back to
// frame 0, the two cells dissolve for 120 ms, the loop resumes at frame 0
// once the one-shot is through; the bar's reactions follow the same
// rules (the same reaction twice plays twice, each from frame 0); a clip
// still decoding leaves the one on screen playing, and one that cannot
// be read is skipped without a gap; Reduce Motion switches nothing.
//
// Synthetic clips, drawn here: 40 frames at 20 fps (2 s), so a 50 ms
// pump is exactly one frame and the frames drawn can be read like a
// score.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/shared/sal_reactions.dart';
import 'package:kute/screens/shared/sal_sprite.dart';

const int _fps = 20;

Map<String, dynamic> _entry(
        {int frames = 40, bool loop = true, String group = 'hero'}) =>
    {
      'framing': 'body',
      'fps': _fps,
      'frames': frames,
      'columns': 8,
      'loop': loop,
      'group': group,
      'files': {
        '2x': {'file': 'none@2x.webp'},
        '3x': {'file': 'none@3x.webp'},
      },
    };

/// A sheet of [frames] 8 px cells, 8 to a row (no asset read).
SalClip _sheet({int frames = 40, bool loop = true}) {
  final rows = (frames / 8).ceil();
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
      Rect.fromLTWH(0, 0, 64, 8.0 * rows), Paint()..color = Colors.brown);
  final image = recorder.endRecording().toImageSync(64, 8 * rows);
  return SalClip(
      image: image,
      fps: _fps.toDouble(),
      frames: frames,
      columns: 8,
      cellWidth: 8,
      cellHeight: 8,
      loop: loop,
      body: true);
}

/// Registers [clips] (name → frames, loop, group) as decoded under a
/// manifest that lists them and [missing] (which no sheet backs).
void _stage(Map<String, ({int frames, bool loop, String group})> clips,
    {List<String> missing = const []}) {
  SalSpriteCache.debugSetManifest({
    for (final e in clips.entries)
      e.key: _entry(
          frames: e.value.frames, loop: e.value.loop, group: e.value.group),
    for (final n in missing) n: _entry(loop: false),
  });
  for (final e in clips.entries) {
    SalSpriteCache.debugPutClip(
        e.key, 2, _sheet(frames: e.value.frames, loop: e.value.loop));
  }
}

/// What the sprite's painter draws now (null: nothing decoded).
SalSpriteFrame? _drawn(WidgetTester tester) =>
    // ignore: avoid_dynamic_calls
    (tester.state(find.byType(SalSprite)) as dynamic).debugFrame
        as SalSpriteFrame?;

/// The clip the sprite was asked for and has not put on yet.
String? _pending(WidgetTester tester) =>
    // ignore: avoid_dynamic_calls
    (tester.state(find.byType(SalSprite)) as dynamic).debugPending
        as String?;

/// One frame of the score: when, what was drawn, what waited.
typedef _Beat = ({int ms, SalSpriteFrame frame, String? pending});

/// Pumps one 50 ms frame at a time from [from] (exclusive) to [to]
/// (inclusive), checking a cell is drawn on every one, and scores them.
Future<List<_Beat>> _play(WidgetTester tester, int from, int to,
    {void Function(int ms)? at}) async {
  final beats = <_Beat>[];
  for (var ms = from + 50; ms <= to; ms += 50) {
    at?.call(ms);
    await tester.pump(const Duration(milliseconds: 50));
    final frame = _drawn(tester);
    expect(frame, isNotNull, reason: 'a cell is drawn at $ms ms');
    expect(
        find.descendant(
            of: find.byType(SalSprite), matching: find.byType(CustomPaint)),
        findsOneWidget,
        reason: 'the painter is on screen at $ms ms');
    beats.add((ms: ms, frame: frame!, pending: _pending(tester)));
  }
  return beats;
}

_Beat _at(List<_Beat> beats, int ms) => beats.singleWhere((b) => b.ms == ms);

/// Checks that from [from] to [to] the beats draw [clip] one frame after
/// another, frame 0 at [start].
void _expectRun(List<_Beat> beats, String clip,
    {required int from, required int to, required int start, int frames = 40}) {
  for (final b in beats.where((b) => b.ms >= from && b.ms <= to)) {
    expect(b.frame.name, clip, reason: 'at ${b.ms} ms');
    expect(b.frame.frame, ((b.ms - start) ~/ 50) % frames,
        reason: 'frame at ${b.ms} ms');
  }
}

Widget _app(Widget child, {bool reduce = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce, devicePixelRatio: 1),
        child: Center(child: child),
      ),
    );

void main() {
  setUp(() => SalSprite.debugPaintLog = []);
  tearDown(() {
    SalSprite.debugPaintLog = null;
    SalReactions.debugReset();
    SalSpriteCache.debugReset();
  });

  testWidgets(
      'the empty state\'s Sal is one performance: still, a beat from the '
      'held pose, played once and held on its last frame, the next beat '
      'dissolving in from there; a cell on every tick', (tester) async {
    _stage({
      'body_hero': (frames: 40, loop: true, group: 'loop'),
      'hero_stretch': (frames: 40, loop: false, group: 'hero'),
    });
    await tester.pumpWidget(_app(SalIdleDirector(
      size: 120,
      fallback: const SizedBox(),
      minGap: const Duration(seconds: 1),
      maxGap: const Duration(seconds: 1),
      sleepAfter: const Duration(minutes: 5),
      random: math.Random(1),
    )));
    // A cached clip is on from the very first frame: no empty frame.
    expect(_drawn(tester)?.name, 'body_hero');
    expect(_drawn(tester)?.frame, 0);
    await tester.pump();

    final beats = await _play(tester, 0, 7000);

    // Still until the first beat (1 s): the hero pose, frame 0.
    for (final b in beats.where((b) => b.ms < 1000)) {
      expect((b.frame.name, b.frame.frame), ('body_hero', 0),
          reason: 'still at ${b.ms} ms');
    }
    // The beat: from frame 0, a frame a tick, through its 40 frames.
    final start = beats.firstWhere((b) => b.frame.frame > 0).ms - 50;
    expect(start, inInclusiveRange(1000, 1100));
    final first = _at(beats, start + 50).frame.name;
    _expectRun(beats, first, from: start + 50, to: start + 1950, start: start);
    // Held on its last frame for the gap (1 s), nothing else drawn.
    for (final b in beats.where((b) => b.ms >= start + 1950 && b.ms <= start + 2900)) {
      expect((b.frame.name, b.frame.frame), (first, 39),
          reason: 'held at ${b.ms} ms');
      expect(b.frame.dissolving, isFalse);
    }
    // The next beat takes the screen from the held frame: its frame 0
    // dissolving over the last one's frame 39 for 120 ms.
    final next = beats.firstWhere((b) => b.ms > start + 2000 && b.frame.dissolving);
    expect(next.frame.frame, 0);
    expect(next.frame.outgoingName, first);
    expect(next.frame.outgoingFrame, 39);
    expect(next.frame.name, isNot(first), reason: 'never twice in a row');

    // Every frame the painter drew was a cell of its clip.
    final log = SalSprite.debugPaintLog!;
    expect(log, isNotEmpty);
    for (final f in log) {
      expect(f.frame, inInclusiveRange(0, f.clip.frames - 1));
      if (f.outgoing != null) {
        expect(f.outgoingFrame, inInclusiveRange(0, f.outgoing!.frames - 1));
      }
    }
    expect(log.any((f) => f.dissolving), isTrue, reason: 'the dissolve drew');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a reaction cuts in at the loop boundary, the same one twice plays '
      'twice from frame 0, and the loop resumes at frame 0',
      (tester) async {
    _stage({
      'idle': (frames: 40, loop: true, group: 'pill'),
      'wink': (frames: 20, loop: false, group: 'reaction'),
    });
    await tester.pumpWidget(_app(
        SalReactionSprite(clip: 'idle', size: 28, fallback: const SizedBox())));
    expect(_drawn(tester)?.name, 'idle');
    await tester.pump();

    final beats = await _play(tester, 0, 4000, at: (ms) {
      if (ms == 500 || ms == 2500) SalReactions.play(SalReaction.wink);
    });

    // Asked for at 0.5 s, the wink waits for the idle loop's boundary.
    _expectRun(beats, 'idle', from: 50, to: 1950, start: 0);
    expect(_at(beats, 1000).pending, 'wink');
    final first = beats.firstWhere((b) => b.frame.name == 'wink');
    expect(first.ms, 2000);
    expect(first.frame.frame, 0);
    expect(first.frame.outgoingName, 'idle');
    expect(first.frame.outgoingFrame, 0);
    _expectRun(beats, 'wink', from: 2000, to: 2950, start: 2000, frames: 20);

    // The same reaction again at 2.5 s: once this one is through (3 s),
    // from frame 0 again.
    expect(_at(beats, 2700).pending, 'wink');
    final again = _at(beats, 3000);
    expect(again.frame.name, 'wink');
    expect(again.frame.frame, 0);
    expect(again.frame.dissolving, isTrue);
    expect(again.frame.outgoingName, 'wink');
    expect(again.frame.outgoingFrame, 19);
    _expectRun(beats, 'wink', from: 3000, to: 3950, start: 3000, frames: 20);

    // Through: the loop at frame 0, the reaction cleared.
    final back = _at(beats, 4000);
    expect(back.frame.name, 'idle');
    expect(back.frame.frame, 0);
    expect(back.frame.outgoingName, 'wink');
    expect(SalReactions.current.value, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Reduce Motion: no switching; a reaction is skipped',
      (tester) async {
    _stage({
      'idle': (frames: 40, loop: true, group: 'pill'),
      'wink': (frames: 20, loop: false, group: 'reaction'),
    });
    await tester.pumpWidget(_app(
        SalReactionSprite(clip: 'idle', size: 28, fallback: const SizedBox()),
        reduce: true));
    await tester.pump();
    SalReactions.play(SalReaction.wink);
    await tester.pump();
    expect(SalReactions.current.value, isNull, reason: 'skipped at once');
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 300));
      final f = _drawn(tester);
      expect(f?.name, 'idle');
      expect(f?.frame, 0, reason: 'the still pose');
      expect(f?.dissolving, isFalse);
    }
    expect(_pending(tester), isNull);
  });

  testWidgets(
      'a clip still decoding leaves the one on screen playing and cuts in '
      'at the first boundary after it lands; one that cannot be read is '
      'skipped with no gap', (tester) async {
    // `slow` reads for as long as the test says; `ghost` has no sheet.
    SalSpriteCache.debugSetManifest({
      'body_hero': _entry(group: 'loop'),
      'slow': _entry(loop: false),
      'ghost': _entry(loop: false),
    });
    SalSpriteCache.debugPutClip('body_hero', 2, _sheet());
    final slow = Completer<SalClip?>();
    SalSpriteCache.debugPutLoading('slow', 2, slow.future);

    final clip = ValueNotifier<String>('body_hero');
    var unavailable = 0;
    await tester.pumpWidget(_app(ValueListenableBuilder<String>(
      valueListenable: clip,
      builder: (_, name, __) => SalSprite(
        clip: name,
        size: 120,
        loop: name == 'body_hero' ? null : false,
        onUnavailable: () => unavailable++,
        fallback: const SizedBox(),
      ),
    )));
    await tester.pump();
    final before = await _play(tester, 0, 500);
    _expectRun(before, 'body_hero', from: 50, to: 500, start: 0);

    // Asked for at 0.5 s and still decoding past the loop's boundary
    // (2 s): the hero plays on, round again.
    clip.value = 'slow';
    final waiting = await _play(tester, 500, 2500);
    _expectRun(waiting, 'body_hero', from: 550, to: 2500, start: 0);
    expect(_at(waiting, 2200).pending, 'slow');

    // Decoded at 2.5 s: it cuts in at the next boundary (4 s), frame 0.
    slow.complete(_sheet(loop: false));
    final landed = await _play(tester, 2500, 4500);
    _expectRun(landed, 'body_hero', from: 2550, to: 3950, start: 0);
    expect(_at(landed, 3000).pending, 'slow');
    final cut = _at(landed, 4000);
    expect(cut.frame.name, 'slow');
    expect(cut.frame.frame, 0);
    expect(cut.frame.outgoingName, 'body_hero');
    expect(cut.frame.outgoingFrame, 0);
    _expectRun(landed, 'slow', from: 4000, to: 4500, start: 4000);

    // A clip that cannot be read (no sheet behind its manifest entry):
    // the one-shot on screen stays, said so once, no gap.
    clip.value = 'ghost';
    await tester.pump();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(unavailable, 1, reason: 'said once');
    expect(_pending(tester), isNull);
    expect(_drawn(tester)?.name, 'slow', reason: 'never a gap');
    final after = await _play(tester, 4500, 5000);
    _expectRun(after, 'slow', from: 4550, to: 5000, start: 4000);
    expect(tester.takeException(), isNull);
    clip.dispose();
  });
}
