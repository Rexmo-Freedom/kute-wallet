// The money journey's 3D Sal (money_steps_view.dart, `_paintSalSprite` /
// `_salClipRun`) as one continuous performance (sal_sprite.dart's rule,
// founder 31 October 2026): while the money waits, the clips he rotates
// through, and the mood changes (fetch → sniff at 8 s, → settle at 25 s),
// only ever switch at a loop's boundary (a one-shot through), never
// mid-cycle; and every clip he can wear is decoded ahead of use.
//
// Synthetic clips, drawn here: 40 frames at 20 fps (2 s), so every
// boundary is 2 s from the clip's start.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/screens/shared/money_steps_view.dart';
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/services/continuous_haptics.dart';
import 'package:kute/services/kute_haptics.dart';
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/theme/app_theme.dart';

const _run = MoneyStepStatus.running;
const _wait = MoneyStepStatus.waiting;
const _done = MoneyStepStatus.done;

final AppLocalizations _en = lookupAppLocalizations(const Locale('en'));
String _usd(double v) => '\$${v.toStringAsFixed(2)}';

/// The clips he can wear on the journey, one-shots marked.
const Map<String, bool> _clips = {
  'body_idle': true,
  'body_walk': true,
  'body_sit_down': false,
  'body_sit': true,
  'body_wag': true,
  'body_sad': true,
  'body_sniff': true,
  'body_jump': false,
  'body_shake_no': false,
  'body_pace': true,
  'body_sniff_trail': true,
  'body_dig': true,
  'body_think': true,
  'body_point': false,
};

const Set<String> _fetch = {'body_pace', 'body_sniff_trail', 'body_dig'};

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
      body: true);
}

void _stage() {
  SalSpriteCache.debugSetManifest({
    for (final e in _clips.entries)
      e.key: {
        'framing': 'body',
        'fps': 20,
        'frames': 40,
        'columns': 8,
        'loop': e.value,
        'group': 'waiting',
        'files': {
          '2x': {'file': 'none@2x.webp'},
          '3x': {'file': 'none@3x.webp'},
        },
      },
  });
  final density = SalSpriteCache.densityFor(WidgetsBinding
          .instance.platformDispatcher.implicitView?.devicePixelRatio ??
      2.0);
  for (final e in _clips.entries) {
    SalSpriteCache.debugPutClip(e.key, density, _sheet(e.value));
  }
}

MoneyStepGraph _order({
  MoneyStepStatus bitcoin = _run,
  MoneyStepStatus convert = _wait,
}) =>
    MoneyStepGraph([
      MoneyStep(
          id: 'leg:bitcoin',
          kind: MoneyStepKind.leg,
          from: MoneyPlace.bitcoin,
          usd: 9.18,
          status: bitcoin),
      MoneyStep(
          id: 'ready:convert',
          kind: MoneyStepKind.convert,
          status: convert,
          ref: convert == _wait ? null : 'seen'),
      MoneyStep(id: 'ready:credit', kind: MoneyStepKind.credit, status: _wait),
      MoneyStep(id: 'place', kind: MoneyStepKind.place, usd: 9.18, status: _wait),
    ]);

Widget _app(MoneyStepGraph g) => ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: MoneyStepsView(
                  lines: moneyStepLines(_en, g, _usd,
                      readyLabel: 'Getting your order ready',
                      placeLine: 'Opening \$9.18 Long BTC'),
                  graph: g,
                  to: MoneyPlace.investing,
                  money: _usd),
            ),
          ),
        ),
      ),
    );

MoneyJourneyPainter _motion(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((w) => w.painter)
    .whereType<MoneyJourneyPainter>()
    .single;

void main() {
  setUp(() {
    KuteHaptics.debugReset();
    KuteHaptics.debugForeground = () => true;
    ContinuousHaptics.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
    _stage();
  });

  tearDown(() {
    KuteHaptics.debugReset();
    SalSpriteCache.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets(
      'while the money waits, his clips and moods switch only at a loop '
      'boundary, never mid-cycle', (tester) async {
    await tester.pumpWidget(_app(_order()));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpWidget(_app(_order(bitcoin: _done, convert: _run)));

    // Every 100 ms for 30 s of waiting: how long he has waited and the
    // clip he wears (the render, not the rig: the clips are decoded).
    final samples = <(int waited, String? clip, SalMood mood)>[];
    for (var i = 0; i < 360; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      final m = _motion(tester);
      samples.add((m.waited?.inMilliseconds ?? -1, m.salClip, m.mood));
      if ((m.waited?.inMilliseconds ?? 0) >= 30000) break;
    }
    expect(samples.last.$1, greaterThanOrEqualTo(30000),
        reason: 'he waited the whole way through');

    // From the first parked clip on: every change lands 2 s (a cycle) on
    // from the one before it, the moods included (sniff at 8 s and settle
    // at 25 s are not on the beat; the switch waits for it).
    final parked = samples.indexWhere(
        (s) => s.$3 == SalMood.fetch && s.$2 != null && _fetch.contains(s.$2));
    expect(parked, isNonNegative, reason: 'he fetches in a waiting clip');
    final t0 = samples[parked].$1;
    final changes = <int>[];
    for (var i = parked + 1; i < samples.length; i++) {
      if (samples[i].$2 != samples[i - 1].$2) changes.add(samples[i].$1);
    }
    expect(changes.length, greaterThanOrEqualTo(3),
        reason: 'the rotation and the moods move him on');
    for (final t in changes) {
      final onBeat = (t - t0) % 2000;
      expect(onBeat == 0 || onBeat == 100, isTrue,
          reason: 'a switch at $t ms (from $t0) is $onBeat ms off the beat');
    }
    // The moods themselves still turn on time (the clip waits, not the
    // mood).
    expect(samples.firstWhere((s) => s.$1 >= 8100).$3, SalMood.sniff);
    expect(samples.firstWhere((s) => s.$1 >= 25100).$3, SalMood.settle);
    // Settled, he sat down and sits or points: one of the settle clips.
    expect(samples.last.$2, anyOf('body_sit', 'body_point', 'body_sit_down'));
    expect(tester.takeException(), isNull);
  });
}
