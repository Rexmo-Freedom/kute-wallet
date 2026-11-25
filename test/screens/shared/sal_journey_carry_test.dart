// The coin in the render (money_steps_view.dart, [_salCarries]; founder:
// "Sal moving around and taking the actual thing and putting it in
// another place"): with the coin clips decoded and their anchors read,
// Sal takes the coin up at the station it leaves (body_pickup, standing
// still for it), carries it along the line (body_carry instead of
// body_walk, at a walking pace), sets it down where he stops at the
// destination (body_drop) and hops after; the balance's mark is drawn on
// the rendered coin at the frame's anchor (none lying flat), and the
// painted coin gives way. Reduce Motion: no pick-up or drop, the held
// pose at once.
//
// Synthetic clips (a solid brown cell) and anchors placed well away from
// where the painted coin would sit (his muzzle), so whatever is drawn at
// the anchor is the mark.

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

const List<String> _loops = [
  'body_idle',
  'body_walk',
  'body_carry',
  'body_sit',
  'body_wag',
  'body_sad',
  'body_sniff',
  'body_pace',
  'body_sniff_trail',
  'body_dig',
  'body_think',
  'body_point',
];
const List<String> _oneShots = [
  'body_pickup',
  'body_drop',
  'body_jump',
  'body_shake_no',
  'body_sit_down',
];

/// 40 frames at 20 fps: each clip 2 s.
SalClip _sheet({bool loop = true}) {
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

int _density() => SalSpriteCache.densityFor(
    WidgetsBinding.instance.platformDispatcher.implicitView?.devicePixelRatio ??
        2.0);

// Held: high on the right of the cell (12.5 and 3.75 of his 16 units),
// facing the camera; on the floor: lying flat (a third round).
const _held = SalCoinAnchor(Offset(100, 30), 8, 8);
const _floor = SalCoinAnchor(Offset(100, 110), 8, 2.6);

/// The clips decoded, their manifest, and their anchors: the pick-up on
/// the floor for its first half, the drop on the floor from a quarter in.
void _stage({bool anchors = true}) {
  SalSpriteCache.debugSetManifest({
    for (final c in [..._loops, ..._oneShots])
      c: {
        'framing': 'body',
        'fps': 20,
        'frames': 40,
        'columns': 8,
        'loop': _loops.contains(c),
        'group': 'waiting',
      },
  });
  final density = _density();
  for (final c in _loops) {
    SalSpriteCache.debugPutClip(c, density, _sheet());
  }
  for (final c in _oneShots) {
    SalSpriteCache.debugPutClip(c, density, _sheet(loop: false));
  }
  if (!anchors) return;
  SalCoinAnchors.debugSet({
    'body_carry': List.filled(40, _held),
    'body_pickup': [for (var f = 0; f < 40; f++) f < 20 ? _floor : _held],
    'body_drop': [for (var f = 0; f < 40; f++) f < 10 ? _held : _floor],
  });
}

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

MoneyStepGraph get _placed =>
    _order(bitcoin: _done, convert: _done, credit: _done, place: _done);

Widget _app(MoneyStepGraph g, {bool still = false}) => ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: still),
            child: child!),
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

/// The journey layer as drawn (its own coordinates, the map's), one
/// logical pixel a pixel.
Future<(ByteData, int)> _render(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find
      .ancestor(of: _journeyPaint(), matching: find.byType(RepaintBoundary))
      .first);
  final image = (await tester.runAsync(() => boundary.toImage(pixelRatio: 1)))!;
  final bytes = (await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
  return (bytes, image.width);
}

bool _brownAt(ByteData bytes, int width, Offset at) {
  final i = (at.dy.round() * width + at.dx.round()) * 4;
  final r = bytes.getUint8(i), g = bytes.getUint8(i + 1);
  final b = bytes.getUint8(i + 2);
  return (r - 0x79).abs() < 20 && (g - 0x55).abs() < 20 && (b - 0x48).abs() < 20;
}

/// Pumps in [step]s for [total], noting every clip he wore.
Future<Set<String?>> _watch(WidgetTester tester, Duration total,
    {Duration step = const Duration(milliseconds: 50)}) async {
  final seen = <String?>{};
  for (var t = Duration.zero; t < total; t += step) {
    await tester.pump(step);
    seen.add(_motion(tester).salClip);
  }
  return seen;
}

void _designSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(430 * 3, 932 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

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

  testWidgets(
      'he takes the coin up at the source first, standing still, then '
      'carries it along the line in the carry clip at a walking pace',
      (tester) async {
    _designSize(tester);
    _stage();
    await tester.pumpWidget(_app(_order()));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    // Past the 120 ms dissolve into it.
    await tester.pump(const Duration(milliseconds: 150));
    final m = _motion(tester);
    expect(m.salClip, 'body_pickup', reason: 'the pick-up plays first');
    expect(m.carrying, isTrue);
    expect(m.coinInRender, isTrue, reason: 'the coin is the render\'s');
    final at = m.travellerAt!;
    // He stands still for it while the clip plays (2 s here).
    final seen = await _watch(tester, const Duration(milliseconds: 1500));
    expect(seen, {'body_pickup'});
    expect(m.travellerAt, at, reason: 'standing still for the pick-up');
    expect(m.walking, isFalse);

    // Then he walks the line with it in his mouth: the carry clip, never
    // the plain walk, the coin the render's all along.
    await tester.pump(const Duration(milliseconds: 450));
    expect(m.salClip, 'body_carry');
    expect(m.walking, isTrue);
    expect(m.coinInRender, isTrue);
    expect(m.coin!.at, m.renderedCoinAt,
        reason: 'the coin is where the render draws it');
    // At a walking pace (0.12 px a ms for a 64 px Sal), never a dash.
    final x0 = m.travellerAt!.dx;
    await tester.pump(const Duration(milliseconds: 100));
    final dx = m.travellerAt!.dx - x0;
    expect(dx, greaterThan(0));
    expect(dx, lessThanOrEqualTo(0.12 * m.salSize / 64 * 100 + 0.5));
    final walked = await _watch(tester, const Duration(milliseconds: 800));
    expect(walked, isNot(contains('body_walk')));
    expect(walked, contains('body_carry'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets(
      'the mark is drawn on the rendered coin at the frame\'s anchor, none '
      'while it lies flat, and the painted coin gives way', (tester) async {
    _designSize(tester);
    _stage();
    await tester.pumpWidget(_app(_order()));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 300));
    final m = _motion(tester);
    final sal = m.travellerAt!;
    final su = m.salSize / 16;
    // The pick-up's first half: the coin on the floor, a third round:
    // in the render, no mark on it.
    expect(m.salClip, 'body_pickup');
    expect(m.coinInRender, isTrue);
    final flat = m.renderedCoinAt!;
    expect(flat.dx, closeTo(sal.dx + (100 / 128 * 16 - 8) * su, 0.01));
    var (bytes, width) = await _render(tester);
    expect(_brownAt(bytes, width, flat), isTrue,
        reason: 'no mark on a coin lying flat');

    // Held, facing the camera: the mark at the anchor (12.5 and 3.75 of
    // his 16 units in the cell), and nothing painted at his muzzle where
    // the painted coin sat.
    await tester.pump(const Duration(milliseconds: 1200));
    expect(m.salClip, 'body_pickup');
    final held = m.renderedCoinAt!;
    final s2 = m.travellerAt!;
    expect(held.dx, closeTo(s2.dx + (12.5 - 8) * su, 0.01));
    expect(held.dy, closeTo(s2.dy - (15 - 3.75) * su, 3),
        reason: 'his feet on the line, the anchor 11.25 units above them');
    (bytes, width) = await _render(tester);
    expect(_brownAt(bytes, width, held), isFalse,
        reason: 'the mark is drawn at the anchor');
    expect(_brownAt(bytes, width, held.translate(-9 * su, 0)), isTrue,
        reason: 'the clip elsewhere at that height');
    final muzzle = Offset(s2.dx + (7.5 - 8) * su, s2.dy - (15 - 10.2) * su);
    expect(_brownAt(bytes, width, muzzle), isTrue,
        reason: 'no painted coin at his muzzle: the render has it');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets(
      'at the destination he sets the coin down where he stops (the drop), '
      'then hops; the coin is gone after', (tester) async {
    _designSize(tester);
    _stage();
    await tester.pumpWidget(_app(_order()));
    await _watch(tester, const Duration(seconds: 3));
    // The leg lands, the destination works: he carries it on and waits
    // beside it.
    await tester.pumpWidget(_app(_order(bitcoin: _done, convert: _run)));
    await _watch(tester, const Duration(seconds: 4));
    final m = _motion(tester);
    expect(m.carrying, isTrue);
    expect(m.walking, isFalse);
    final beside = m.travellerAt!;

    // Placed: he sets it down there, standing still, before any hop.
    await tester.pumpWidget(_app(_placed));
    await tester.pump(const Duration(milliseconds: 50));
    expect(m.salClip, 'body_drop', reason: 'the drop plays on arrival');
    expect(m.carrying, isFalse);
    expect(m.hopping, isFalse, reason: 'the hop waits for the coin to be down');
    await tester.pump(const Duration(milliseconds: 150));
    expect(m.coinInRender, isTrue, reason: 'past the dissolve into the drop');
    final dropping = await _watch(tester, const Duration(milliseconds: 1650));
    expect(dropping, {'body_drop'});
    expect(m.travellerAt, beside);
    // Down: the hop and the cheer, the coin gone with the drop.
    await tester.pump(const Duration(milliseconds: 250));
    expect(m.salClip, 'body_jump');
    expect(m.hopping, isTrue);
    expect(m.coin, isNull);
    // Past the dissolve out of the drop.
    await tester.pump(const Duration(milliseconds: 150));
    expect(m.coinInRender, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets(
      'Reduce Motion: no pick-up and no drop, the held pose at once, the '
      'plain pose once the coin is in', (tester) async {
    _designSize(tester);
    _stage();
    await tester.pumpWidget(_app(_order(), still: true));
    await tester.pump();
    await tester.pump();
    final m = _motion(tester);
    expect(m.carrying, isTrue);
    expect(m.salClip, 'body_carry', reason: 'the held pose');
    expect(m.coinInRender, isTrue);
    expect(m.walking, isFalse);
    await tester.pumpWidget(_app(_placed, still: true));
    await tester.pump();
    await tester.pump();
    expect(m.salClip, 'body_idle', reason: 'no drop: the final pose');
    expect(m.carrying, isFalse);
    expect(m.coinInRender, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'without the anchors the coin is painted and glides on its own, and '
      'he fetches it as before', (tester) async {
    _designSize(tester);
    _stage(anchors: false);
    await tester.pumpWidget(_app(_order()));
    final seen = await _watch(tester, const Duration(milliseconds: 1500));
    final m = _motion(tester);
    expect(seen, isNot(contains('body_pickup')));
    expect(seen, isNot(contains('body_carry')));
    expect(m.coinInRender, isFalse);
    expect(m.carrying, isFalse);
    expect(m.travellerAt!.dx, lessThan(m.coin!.at.dx),
        reason: 'Sal walks behind the gliding coin');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
  });
}
