// Sal's moments (sal_moments.dart; founder, 12 November 2026: "Sal
// animations — do it"): each moment picks its clip (a win cheers, a
// success nods, a failure shrugs, a wait thinks and searches), a one-shot
// plays once and keeps still, the waiting passes switch only as a pass
// ends, an outcome cuts in at once, a Sal in the background yields to the
// one performing, and Reduce Motion is a still frame. The toast and the
// result sheet wear them; the toast holds the spotlight, so no bar
// reaction plays over it.
//
// Synthetic face clips, drawn here: 40 frames at 20 fps (2 s), so a 50 ms
// pump is exactly one frame.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/screens/shared/sal_moments.dart';
import 'package:kute/screens/shared/sal_reactions.dart';
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/screens/shared/sal_toast.dart';
import 'package:kute/screens/shared/trade_notification_receipt.dart';
import 'package:kute/services/trade_notification_store.dart';
import 'package:kute/theme/app_theme.dart';

/// Every face clip a moment shows, with whether the manifest loops it.
const Map<String, bool> _faces = {
  'cheer': false,
  'happy': true,
  'nod': false,
  'shake_no': false,
  'think': true,
  'search': true,
  'blink': true,
  'idle': true,
  'wink': false,
};

SalClip _sheet(bool loop) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 64, 40), Paint()..color = Colors.brown);
  return SalClip(
      image: recorder.endRecording().toImageSync(64, 40),
      fps: 20,
      frames: 40,
      columns: 8,
      cellWidth: 8,
      cellHeight: 8,
      loop: loop,
      body: false);
}

void _stage() {
  SalSpriteCache.debugSetManifest({
    for (final e in _faces.entries)
      e.key: {
        'framing': 'face',
        'fps': 20,
        'frames': 40,
        'columns': 8,
        'loop': e.value,
        'group': 'reaction',
        'files': {
          '2x': {'file': 'none@2x.webp'},
          '3x': {'file': 'none@3x.webp'},
        },
      },
  });
  for (final e in _faces.entries) {
    SalSpriteCache.debugPutClip(e.key, 2, _sheet(e.value));
  }
}

Widget _app(Widget child, {bool reduce = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce, devicePixelRatio: 1),
        child: Center(child: child),
      ),
    );

/// The moment's sprite, at [moment].
Widget _moment(SalMoment moment, {bool yieldToSpotlight = false}) =>
    SalMomentSprite(
      moment: moment,
      size: 40,
      yieldToSpotlight: yieldToSpotlight,
      fallback: const SizedBox(),
    );

/// What the sprite draws now.
SalSpriteFrame? _drawn(WidgetTester tester) =>
    // ignore: avoid_dynamic_calls
    (tester.state(find.byType(SalSprite)) as dynamic).debugFrame
        as SalSpriteFrame?;

/// Pumps one 50 ms frame at a time for [ms] and returns what was drawn.
Future<List<SalSpriteFrame>> _play(WidgetTester tester, int ms) async {
  final out = <SalSpriteFrame>[];
  for (var t = 50; t <= ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
    out.add(_drawn(tester)!);
  }
  return out;
}

void main() {
  setUpAll(() => initializeDateFormatting('en'));
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    _stage();
  });
  tearDown(() {
    SalReactions.debugReset();
    SalToast.debugReset();
    SalSpriteCache.debugReset();
  });

  test('each moment picks its clip', () {
    // The toast: success nods, failure shrugs, pending waits, info blinks.
    expect(SalToast.clipFor(SalToastTone.success), 'nod');
    expect(SalToast.clipFor(SalToastTone.failure), 'shake_no');
    expect(SalToast.clipFor(SalToastTone.pending), 'think');
    expect(SalToast.clipFor(SalToastTone.info), 'blink');
    // The result sheet: a win cheers, then happy.
    expect(KuteConfirmation.momentFor(KuteConfirmationTone.celebrate),
        SalMoment.win);
    expect(SalMoments.firstClip(SalMoment.win), 'cheer');
    expect(SalMoments.clipsOf(SalMoment.win), ['cheer', 'happy']);
    expect(KuteConfirmation.momentFor(KuteConfirmationTone.success),
        SalMoment.done);
    expect(KuteConfirmation.momentFor(KuteConfirmationTone.failure),
        SalMoment.shrug);
    expect(KuteConfirmation.momentFor(KuteConfirmationTone.pending),
        SalMoment.waiting);
    expect(KuteConfirmation.momentFor(KuteConfirmationTone.neutral),
        SalMoment.calm);
    // Never sad for money: no moment shows `sad`.
    expect(SalMoments.faceClips, isNot(contains('sad')));
    expect(SalMoments.shrugBody, 'body_shake_off');
    // The sheet warms every clip it can show.
    expect(KuteConfirmation.salClips, containsAll(SalMoments.faceClips));
  });

  test('a lost prediction\'s receipt shrugs; a won one cheers', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    TradeNotification item(String title, {bool positive = false, bool read = false}) =>
        TradeNotification(
            id: 'pm:x:$title',
            account: 'x',
            product: 'predictions',
            title: title,
            subtitle: 'Will it rain? · Yes',
            rows: const {'Settlement payout': r'$0.00'},
            time: 0,
            positive: positive,
            read: read);
    KuteConfirmation sheet(TradeNotification n) =>
        tradeNotificationConfirmation(l10n, n,
            showWallet: false, onList: () {});
    final lost = sheet(item('Prediction lost'));
    expect(lost.resolvedTone, KuteConfirmationTone.neutral,
        reason: 'no failure mark for a lost bet');
    expect(lost.resolvedSalMoment, SalMoment.shrug);
    expect(sheet(item('Prediction lost', read: true)).resolvedSalMoment,
        SalMoment.calm, reason: 'read again later: calm');
    expect(sheet(item('Prediction won', positive: true)).resolvedSalMoment,
        SalMoment.win);
  });

  testWidgets('done: the nod once, then still on its last frame',
      (tester) async {
    await tester.pumpWidget(_app(_moment(SalMoment.done)));
    await tester.pump();
    final frames = await _play(tester, 3000);
    expect(frames.every((f) => f.name == 'nod'), isTrue);
    expect(frames[10].frame, 11, reason: 'it plays');
    expect(frames.last.frame, 39, reason: 'held on its last frame');
    expect(tester.hasRunningAnimations, isFalse, reason: 'then still');
  });

  testWidgets('shrug: the head shake once, then still; never sad',
      (tester) async {
    await tester.pumpWidget(_app(_moment(SalMoment.shrug)));
    await tester.pump();
    final frames = await _play(tester, 3000);
    expect(frames.map((f) => f.name).toSet(), {'shake_no'});
    expect(frames.last.frame, 39);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('win: the cheer once, then it settles into happy',
      (tester) async {
    await tester.pumpWidget(_app(_moment(SalMoment.win)));
    await tester.pump();
    final frames = await _play(tester, 4000);
    final cheer = frames.takeWhile((f) => f.name == 'cheer').toList();
    expect(cheer.length, 39, reason: 'the whole cheer, once');
    expect(cheer.last.frame, 39);
    final settle = frames[cheer.length];
    expect(settle.name, 'happy');
    expect(settle.frame, 0);
    expect(settle.outgoingName, 'cheer', reason: 'dissolving from it');
    expect(frames.skip(cheer.length).every((f) => f.name == 'happy'), isTrue);
  });

  testWidgets(
      'waiting: think, then search, a pass each, switching only as a pass '
      'ends (never mid-cycle)', (tester) async {
    await tester.pumpWidget(_app(_moment(SalMoment.waiting)));
    await tester.pump();
    final frames = await _play(tester, 8000);
    // 50 ms a frame: the pass boundaries are at 2 s, 4 s, 6 s, 8 s.
    for (var i = 0; i < frames.length; i++) {
      final ms = (i + 1) * 50;
      final pass = ms ~/ 2000;
      expect(frames[i].name, pass.isEven ? 'think' : 'search',
          reason: 'at $ms ms');
      expect(frames[i].frame, (ms % 2000) ~/ 50, reason: 'frame at $ms ms');
    }
    expect(tester.hasRunningAnimations, isTrue, reason: 'it keeps waiting');
  });

  testWidgets('an outcome cuts into a wait at once, with the dissolve',
      (tester) async {
    final moment = ValueNotifier(SalMoment.waiting);
    await tester.pumpWidget(_app(ValueListenableBuilder<SalMoment>(
        valueListenable: moment, builder: (_, m, __) => _moment(m))));
    await tester.pump();
    await _play(tester, 700);
    moment.value = SalMoment.done;
    await tester.pump();
    final f = _drawn(tester)!;
    expect(f.name, 'nod');
    expect(f.frame, 0);
    expect(f.outgoingName, 'think');
    expect(f.dissolving, isTrue);
  });

  testWidgets(
      'yielding (the bar\'s busy button): while another Sal performs the '
      'pass plays out and holds; free again, the next pass', (tester) async {
    await tester.pumpWidget(
        _app(_moment(SalMoment.waiting, yieldToSpotlight: true)));
    await tester.pump();
    await _play(tester, 500);
    final toast = Object();
    SalSpotlight.hold(toast);
    await tester.pump();
    final held = await _play(tester, 4000);
    // The pass on screen runs to its end (2 s), then holds there.
    expect(held.where((f) => f.name == 'think').last.frame, 39);
    expect(held.map((f) => f.name).toSet(), {'think'});
    expect(tester.hasRunningAnimations, isFalse);
    SalSpotlight.release(toast);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(_drawn(tester)!.name, 'search', reason: 'the next pass');
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('Reduce Motion: every moment is a still frame', (tester) async {
    for (final (moment, still) in [
      (SalMoment.win, 'happy'),
      (SalMoment.done, 'nod'),
      (SalMoment.shrug, 'shake_no'),
      (SalMoment.waiting, 'think'),
      (SalMoment.calm, 'blink'),
    ]) {
      await tester.pumpWidget(_app(_moment(moment), reduce: true));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(_drawn(tester)?.name, still, reason: '$moment');
      expect(_drawn(tester)?.frame, 0, reason: '$moment');
      expect(tester.hasRunningAnimations, isFalse, reason: '$moment');
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets(
      'the placing toast waits, then nods as it turns into "placed"; while '
      'a toast is up the bar plays no reaction and its Sal keeps still',
      (tester) async {
    SalToast.debugSuccessFeedbackOverride = () async {};
    addTearDown(() => SalToast.debugSuccessFeedbackOverride = null);
    late BuildContext page;
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: buildLightTheme(),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(devicePixelRatio: 1),
            child: child!),
        home: Scaffold(
          body: Builder(builder: (c) {
            page = c;
            return const Align(
              alignment: Alignment.bottomCenter,
              child: SalReactionSprite(
                  key: ValueKey('bar-sal'),
                  clip: 'idle',
                  size: 28,
                  fallback: SizedBox()),
            );
          }),
        ),
      ),
    ));
    await tester.pump();
    String toastClip() => tester
        .widget<SalSprite>(find.byKey(const ValueKey('sal-toast-sal')))
        .clip;
    SalSprite barSprite() => tester.widget<SalSprite>(find.descendant(
        of: find.byKey(const ValueKey('bar-sal')),
        matching: find.byType(SalSprite)));

    SalToast.show(page,
        tag: 'order',
        message: 'Placing your prediction',
        tone: SalToastTone.info,
        salMoment: SalMoment.waiting,
        sticky: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(toastClip(), 'think');
    expect(SalSpotlight.held, isTrue);
    expect(barSprite().loop, isFalse,
        reason: 'the bar\'s loop plays out its pass and holds');
    SalReactions.play(SalReaction.wink);
    expect(SalReactions.current.value, isNull,
        reason: 'no reaction over the toast');

    SalToast.show(page,
        tag: 'order', message: 'Prediction placed', tone: SalToastTone.success);
    await tester.pump();
    expect(toastClip(), 'nod');

    // Gone: the bar's Sal loops again.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.byKey(const ValueKey('sal-toast-sal')), findsNothing);
    expect(SalSpotlight.held, isFalse);
    expect(barSprite().loop, isNull);
  });
}
