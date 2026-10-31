// Sal reacts in the bar (sal_reactions.dart): a hook asks for one face
// one-shot, the bar's sprite plays it over its clip and comes back; a load
// that lasts 2 s asks for `think`; a reaction whose clip cannot be read is
// skipped; an error toast asks for `shake_no`.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/screens/shared/sal_reactions.dart';
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/theme/app_theme.dart';

/// A face clip drawn here (no asset read): [frames] at 24 fps.
void _put(String name, {required int frames, required bool loop}) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 64, 48), Paint()..color = Colors.brown);
  SalSpriteCache.debugPutClip(
      name,
      2,
      SalClip(
          image: recorder.endRecording().toImageSync(64, 48),
          fps: 24,
          frames: frames,
          columns: 8,
          cellWidth: 8,
          cellHeight: 8,
          loop: loop,
          body: false));
}

Map<String, dynamic> _entry(int frames, bool loop) => {
      'framing': 'face',
      'fps': 24,
      'frames': frames,
      'columns': 8,
      'loop': loop,
      'files': {
        '2x': {'file': 'none@2x.webp'},
        '3x': {'file': 'none@3x.webp'},
      },
    };

String _clip(WidgetTester tester) =>
    tester.widget<SalSprite>(find.byType(SalSprite).first).clip;

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  tearDown(() {
    SalReactions.debugReset();
    SalSpriteCache.debugReset();
  });

  testWidgets('play hands the bar one numbered event; clear takes it back',
      (tester) async {
    expect(SalReactions.current.value, isNull);
    SalReactions.play(SalReaction.wink);
    final first = SalReactions.current.value!;
    expect(first.clip, 'wink');
    SalReactions.play(SalReaction.wink);
    final second = SalReactions.current.value!;
    expect(second, isNot(first), reason: 'the same reaction twice plays twice');
    SalReactions.clear(first);
    expect(SalReactions.current.value, second, reason: 'only the one playing');
    SalReactions.clear(second);
    expect(SalReactions.current.value, isNull);
  });

  testWidgets('a load that lasts 2 s asks for think; a shorter one does not',
      (tester) async {
    SalReactions.loading('a', true);
    await tester.pump(const Duration(milliseconds: 1500));
    SalReactions.loading('a', false);
    await tester.pump(const Duration(seconds: 1));
    expect(SalReactions.current.value, isNull);

    SalReactions.loading('b', true);
    await tester.pump(const Duration(milliseconds: 2050));
    expect(SalReactions.current.value?.reaction, SalReaction.think);
  });

  testWidgets('the sprite plays the reaction once over its clip and comes back',
      (tester) async {
    SalSpriteCache.debugSetManifest(
        {'idle': _entry(48, true), 'wink': _entry(36, false)});
    _put('idle', frames: 48, loop: true);
    _put('wink', frames: 36, loop: false);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 1),
        child: Center(
          child: SalReactionSprite(
              clip: 'idle', size: 28, fallback: const SizedBox()),
        ),
      ),
    ));
    await tester.pump();
    expect(_clip(tester), 'idle');

    SalReactions.play(SalReaction.wink);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(_clip(tester), 'wink');
    // 36 frames at 24 fps, then the crossfade back (and the frame that
    // lets the outgoing sprite go).
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(_clip(tester), 'idle');
    expect(SalReactions.current.value, isNull, reason: 'played, cleared');
  });

  testWidgets('a reaction whose clip is not there is skipped', (tester) async {
    SalSpriteCache.debugSetManifest({'idle': _entry(48, true)});
    _put('idle', frames: 48, loop: true);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 1),
        child: Center(
          child: SalReactionSprite(
              clip: 'idle', size: 28, fallback: const SizedBox()),
        ),
      ),
    ));
    await tester.pump();
    SalReactions.play(SalReaction.cheer);
    await tester.pump();
    // The read fails (no entry), the sprite says so, the crossfade back.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(_clip(tester), 'idle');
    expect(SalReactions.current.value, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an error toast asks for shake_no; success and info do not',
      (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: buildLightTheme(),
        home: Scaffold(body: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        })),
      ),
    ));
    showMessageSnackBar(context: ctx, message: 'Saved', error: false);
    await tester.pump();
    expect(SalReactions.current.value, isNull);
    showMessageSnackBar(context: ctx, message: 'Note', error: false, info: true);
    await tester.pump();
    expect(SalReactions.current.value, isNull);
    showMessageSnackBar(context: ctx, message: 'Failed', error: true);
    await tester.pump();
    expect(SalReactions.current.value?.reaction, SalReaction.shakeNo);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
