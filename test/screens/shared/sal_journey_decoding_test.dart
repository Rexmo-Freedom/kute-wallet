// The money journey's Sal while his sheets are read (money_steps_view.dart,
// `_paintSalSprite`, [SalJourneyDraw]; founder, 9 November 2026: "the last
// send screen should have our Sal 3D one, not the SVG Sal"). The journey
// is what the Dollars send shows under Review after Send (StepsReveal →
// MoveStepsSection → MoneyStepsView). Before this change it drew the
// pixel rig (`paintKuteDog`) on every frame until `_warmSalClips` had
// decoded every sheet; now a read still out leaves his box empty, or
// puts a decoded clip's first frame there, and the rig is the last
// resort, only once a read came back empty (no manifest, no sheet).
//
// Synthetic clips (a solid brown cell), staged in the test body so the
// view's warm-up runs on the test's pumps.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
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

/// Every clip the journey can ask for (money_steps_view.dart's pools).
const List<String> _clips = [
  'body_idle',
  'body_walk',
  'body_sit_down',
  'body_sit',
  'body_wag',
  'body_sad',
  'body_sniff',
  'body_jump',
  'body_shake_no',
  'body_pace',
  'body_sniff_trail',
  'body_dig',
  'body_think',
  'body_point',
];

SalClip _sheet() {
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
      loop: true,
      body: true);
}

int _density() => SalSpriteCache.densityFor(
    WidgetsBinding.instance.platformDispatcher.implicitView?.devicePixelRatio ??
        2.0);

void _manifest() => SalSpriteCache.debugSetManifest({
      for (final c in _clips)
        c: {
          'framing': 'body',
          'fps': 20,
          'frames': 40,
          'columns': 8,
          'loop': true,
          'group': 'waiting',
        },
    });

MoneyStepGraph _order({
  MoneyStepStatus bitcoin = _run,
  MoneyStepStatus convert = _wait,
  MoneyStepStatus credit = _wait,
  MoneyStepStatus place = _wait,
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
      MoneyStep(id: 'ready:credit', kind: MoneyStepKind.credit, status: credit),
      MoneyStep(id: 'place', kind: MoneyStepKind.place, usd: 9.18, status: place),
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

/// What drew him on each of [frames] pumps of 100 ms.
Future<Set<SalJourneyDraw>> _sample(WidgetTester tester, int frames) async {
  final seen = <SalJourneyDraw>{};
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    seen.add(_motion(tester).salDraw);
  }
  return seen;
}

void main() {
  setUp(() {
    KuteHaptics.debugReset();
    KuteHaptics.debugForeground = () => true;
    ContinuousHaptics.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
    // Every test's view warms the clips itself (once for the process
    // otherwise), so each sees the read as it stands.
    debugResetSalJourneyWarm();
  });

  tearDown(() {
    KuteHaptics.debugReset();
    SalSpriteCache.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets(
      'sheets not warmed (a fresh cache, every read still out): his box '
      'stays empty, never the pixel rig; the clip draws him once the read '
      'lands', (tester) async {
    _manifest();
    final density = _density();
    final loading = Completer<SalClip?>();
    for (final c in _clips) {
      SalSpriteCache.debugPutLoading(c, density, loading.future);
    }
    await tester.pumpWidget(_app(_order()));
    // Four seconds of a running leg: he walks, fetches, waits.
    final seen = await _sample(tester, 40);
    expect(seen, {SalJourneyDraw.none},
        reason: 'nothing in his box while the sheets are read: $seen');
    expect(_motion(tester).salSprite, isFalse);

    // The sheets land: the clip draws him, and the rig never did.
    loading.complete(_sheet());
    await tester.pump();
    await tester.pump();
    final after = await _sample(tester, 10);
    expect(after, {SalJourneyDraw.clip}, reason: 'the render: $after');
    expect(_motion(tester).salSprite, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'one clip decoded while the one he should wear is read: its first '
      'frame stands in his box, still; never the rig', (tester) async {
    _manifest();
    final density = _density();
    final loading = Completer<SalClip?>();
    for (final c in _clips) {
      if (c == 'body_idle') {
        SalSpriteCache.debugPutClip(c, density, _sheet());
      } else {
        SalSpriteCache.debugPutLoading(c, density, loading.future);
      }
    }
    await tester.pumpWidget(_app(_order()));
    final seen = await _sample(tester, 60);
    expect(seen, contains(SalJourneyDraw.still),
        reason: 'walking, fetching: body_idle\'s first frame stands in');
    expect(seen, isNot(contains(SalJourneyDraw.rig)));
    // A still is a decoded clip drawing him (its first frame).
    loading.complete(_sheet());
    await tester.pump();
    await tester.pump();
    expect(_motion(tester).salDraw, SalJourneyDraw.clip);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'sheets warmed before the view mounts (the send flow opened): the '
      'clip draws him from the first frame', (tester) async {
    _manifest();
    final density = _density();
    for (final c in _clips) {
      SalSpriteCache.debugPutClip(c, density, _sheet());
    }
    await MoneyStepsView.warmSal();
    await tester.pumpWidget(_app(_order()));
    await tester.pump();
    expect(_motion(tester).salDraw, SalJourneyDraw.clip);
    // A clip given up and read again holds a decoded frame meanwhile.
    final seen = await _sample(tester, 20);
    expect(seen.difference({SalJourneyDraw.clip, SalJourneyDraw.still}),
        isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'no sheets at all (no manifest): the read comes back empty and the '
      'rig is the last resort, on the first frame after it', (tester) async {
    SalSpriteCache.debugSetManifest(null);
    await tester.pumpWidget(_app(_order()));
    // The first paint asks for the clip; the read lands a microtask on.
    expect(_motion(tester).salDraw,
        anyOf(SalJourneyDraw.none, SalJourneyDraw.rig));
    await tester.pump();
    final seen = await _sample(tester, 20);
    expect(seen, {SalJourneyDraw.rig}, reason: 'the rig, and only it: $seen');
    expect(_motion(tester).salSprite, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a manifest whose sheets cannot be read: the rig once each read has '
      'come back empty, nothing before', (tester) async {
    _manifest();
    final density = _density();
    for (final c in _clips) {
      SalSpriteCache.debugPutLoading(c, density, Future.value(null));
    }
    await tester.pumpWidget(_app(_order(
        bitcoin: _done, convert: _done, credit: _done, place: _done)));
    await tester.pump();
    await tester.pump();
    final seen = await _sample(tester, 10);
    expect(seen, {SalJourneyDraw.rig});
    expect(SalSpriteCache.failed('body_idle', density), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Reduce Motion: the clip\'s first frame, or nothing, never the rig',
      (tester) async {
    _manifest();
    final density = _density();
    final loading = Completer<SalClip?>();
    for (final c in _clips) {
      SalSpriteCache.debugPutLoading(c, density, loading.future);
    }
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures.allOn;
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(_app(_order()));
    await tester.pump();
    expect(_motion(tester).salDraw, SalJourneyDraw.none);
    loading.complete(_sheet());
    await tester.pump();
    await tester.pump();
    expect(_motion(tester).salDraw, SalJourneyDraw.clip);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the cap: the journey reads its first clip and one ahead, never all '
      'at once; it gives up the clips it has passed, holds at most four, '
      'and while a later clip is read keeps a decoded frame, never the rig',
      (tester) async {
    _manifest();
    // Every read takes 150 ms; each sheet is 64 x 40 (10 240 bytes), and
    // the cap holds four and a half.
    final reads = <String>[];
    SalSpriteCache.debugLoader = (name, density) async {
      reads.add(name);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      return _sheet();
    };
    const one = 64 * 40 * 4;
    SalSpriteCache.maxBytes = one * 9 ~/ 2;
    // The send flow opens: the first clip only.
    await tester.runAsync(() async {});
    unawaited(MoneyStepsView.warmSal());
    await tester.pump(const Duration(milliseconds: 200));
    expect(reads, [kSalJourneyFirstClip]);

    await tester.pumpWidget(_app(_order()));
    await tester.pump();
    expect(_motion(tester).salDraw, SalJourneyDraw.clip,
        reason: 'warmed on open: the 3D Sal from the first frame');
    expect(reads.length, lessThanOrEqualTo(2),
        reason: 'the first clip and one ahead: $reads');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpWidget(_app(_order(bitcoin: _done, convert: _run)));

    final draws = <SalJourneyDraw>{};
    var held = 0;
    for (var i = 0; i < 320; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      draws.add(_motion(tester).salDraw);
      expect(SalSpriteCache.residentBytes,
          lessThanOrEqualTo(SalSpriteCache.maxBytes));
      held = math.max(held, SalSpriteCache.residentAt(_density()).length);
    }
    expect(draws.difference({SalJourneyDraw.clip, SalJourneyDraw.still}),
        isEmpty,
        reason: 'a clip or a held frame, never nothing or the rig: $draws');
    expect(held, lessThanOrEqualTo(4));
    // He went through fetch, sniff and settle: several clips were read,
    // each once it was next, and the passed ones were given up.
    expect(reads.toSet().length, greaterThanOrEqualTo(6), reason: '$reads');
    expect(SalSpriteCache.residentAt(_density()).length, lessThan(reads.toSet().length));
    expect(tester.takeException(), isNull);
  });

  test(
      'a 3x device reads the @3x sheets, and every clip the send flows show '
      'has one in the bundle, at both densities', () {
    expect(SalSpriteCache.densityFor(2.0), 2);
    expect(SalSpriteCache.densityFor(2.625), 3, reason: 'a Pixel');
    expect(SalSpriteCache.densityFor(3.0), 3);
    final dir = Directory('lib/assets/sal');
    final manifest = jsonDecode(File('${dir.path}/manifest.json')
        .readAsStringSync()) as Map<String, dynamic>;
    final names = <String>{
      ...KuteConfirmation.salClips,
      ..._clips,
      'body_pickup',
      'body_carry',
      'body_drop',
      for (final e in manifest.entries)
        if (e.value is Map && (e.value as Map)['group'] == 'waiting') e.key,
    };
    for (final name in names) {
      final entry = manifest[name];
      expect(entry, isA<Map>(), reason: '$name is in the manifest');
      final files = (entry as Map)['files'] as Map?;
      for (final density in const ['2x', '3x']) {
        final file = (files?[density] as Map?)?['file'] as String? ??
            '$name@$density.png';
        expect(File('${dir.path}/$file').existsSync(), isTrue,
            reason: '$name has its $density sheet, $file');
      }
    }
    // The assets ship: the folder is declared whole.
    expect(File('pubspec.yaml').readAsStringSync(),
        contains('- lib/assets/sal/'));
  });
}
