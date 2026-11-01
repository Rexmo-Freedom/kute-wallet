// The money journey's 3D Sal (money_steps_view.dart, `_paintSalSprite`)
// and the coin he carries: the journey around him is painted as ever
// when a clip draws him (the sprite path once returned before the coin
// was painted: no coin on the 3D Sal at all), the coin sits on him (at
// his mouth: the body faces the viewer), and a view whose clock is not
// running still puts the render on once the sheets are decoded.
//
// Synthetic clips (a solid brown cell), so the coin's orange on him is
// the coin.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

/// Staged inside the test body (the test's own zone), so the view's
/// warm-up, which awaits the manifest, runs on the test's pumps.
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

Finder _journeyPaint() => find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is MoneyJourneyPainter);

MoneyJourneyPainter _motion(WidgetTester tester) =>
    (tester.widget<CustomPaint>(_journeyPaint()).painter as MoneyJourneyPainter);

/// The journey layer as drawn, in logical pixels.
Future<ui.Image> _render(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find
      .ancestor(of: _journeyPaint(), matching: find.byType(RepaintBoundary))
      .first);
  return (await tester.runAsync(() => boundary.toImage(pixelRatio: 1)))!;
}

bool _orange(int r, int g, int b) =>
    r > 180 && g > 90 && g < 200 && b < 130 && r - b > 80;
bool _brown(int r, int g, int b) =>
    (r - 0x79).abs() < 20 && (g - 0x55).abs() < 20 && (b - 0x48).abs() < 20;

void main() {
  setUp(() {
    KuteHaptics.debugReset();
    KuteHaptics.debugForeground = () => true;
    ContinuousHaptics.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  });

  tearDown(() {
    KuteHaptics.debugReset();
    SalSpriteCache.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  // First in the file: the view's warm-up runs once for the process.
  testWidgets(
      'a finished record (clock at rest) puts the render on once the '
      'sheets decode', (tester) async {
    _manifest();
    final density = _density();
    final loading = Completer<SalClip?>();
    for (final c in _clips) {
      SalSpriteCache.debugPutLoading(c, density, loading.future);
    }
    await tester.pumpWidget(_app(_order(
        bitcoin: _done, convert: _done, credit: _done, place: _done)));
    await tester.pump(const Duration(seconds: 4));
    expect(_motion(tester).salSprite, isFalse, reason: 'the rig, decoding');
    loading.complete(_sheet());
    // The decode lands and asks for a frame; the next one draws it.
    await tester.pump();
    await tester.pump();
    expect(_motion(tester).salSprite, isTrue,
        reason: 'the render, without anything else repainting the view');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the 3D Sal carries the coin, drawn on him at his mouth',
      (tester) async {
    // The design size, so the look is at its real scale (the coin about
    // 12.6 px across in his mouth, on a 64 px Sal).
    tester.view.physicalSize = const Size(430 * 3, 932 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    _manifest();
    final density = _density();
    for (final c in _clips) {
      SalSpriteCache.debugPutClip(c, density, _sheet());
    }
    await tester.pumpWidget(_app(_order()));
    // He walks up to the parked coin and takes it; the pick-up over.
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (_motion(tester).carrying) break;
    }
    final m = _motion(tester);
    expect(m.carrying, isTrue, reason: 'he took the coin');
    await tester.pump(const Duration(milliseconds: 600));
    expect(m.salSprite, isTrue, reason: 'a clip draws him');
    final coin = m.coin!;
    final sal = m.travellerAt!;
    // In his mouth: on his body (not beside it), above his feet (which
    // stand on the track's top edge, 5 above its centre line at
    // [sal.dy]); the muzzle about 4.8 of his 16 units (~21 px) up.
    expect((coin.at.dx - sal.dx).abs(), lessThan(3));
    expect(coin.at.dy, lessThan(sal.dy - 5));
    expect(coin.at.dy, greaterThan(sal.dy - 40));

    final image = await _render(tester);
    final bytes = (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
    // The coin (its orange, or its mark's white) covers the clip's brown
    // where it sits, and its orange is there round it.
    int orange = 0, brown = 0;
    final cx = coin.at.dx.round();
    final cy = coin.at.dy.round();
    for (var y = cy - 3; y <= cy + 3; y++) {
      for (var x = cx - 3; x <= cx + 3; x++) {
        final i = (y * image.width + x) * 4;
        final r = bytes.getUint8(i), g = bytes.getUint8(i + 1);
        final b = bytes.getUint8(i + 2);
        if (_orange(r, g, b)) orange++;
        if (_brown(r, g, b) && (y - cy).abs() <= 1 && (x - cx).abs() <= 1) {
          brown++;
        }
      }
    }
    expect(orange, greaterThan(0), reason: 'the coin is painted on him');
    expect(brown, 0,
        reason: 'the coin is painted over the clip, not under it '
            '(orange $orange, brown $brown)');
    expect(tester.takeException(), isNull);
  });
}
