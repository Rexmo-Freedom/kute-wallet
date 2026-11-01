// The arrow track (founder, 1 November 2026): the journey's track ends
// in a solid arrowhead at the destination station's edge, pointing into
// its mark; in the track's quiet grey while the leg runs (the fill held
// short of it), in the accent orange once the fill reaches it.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/screens/shared/money_steps_view.dart';
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/theme/app_theme.dart';

const _run = MoneyStepStatus.running;
const _wait = MoneyStepStatus.waiting;
const _done = MoneyStepStatus.done;
const _key = ValueKey('arrow-shot');

String _usd(double v) => '\$${v.toStringAsFixed(2)}';
late AppLocalizations _en;

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
      const MoneyStep(id: 'place', kind: MoneyStepKind.place, usd: 9.18),
    ]);

/// The journey at the design size (every `.r` is 1), on white.
Widget _app(MoneyStepGraph g) => ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: _key,
              child: ColoredBox(
                color: Colors.white,
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
      ),
    );

/// The pixel at [at] (in the shot's coordinates) as (r, g, b).
Future<(int, int, int)> _pixel(WidgetTester tester, Offset at) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_key));
  final image = (await tester.runAsync(() => boundary.toImage()))!;
  final bytes = (await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
  final i = (at.dy.round() * image.width + at.dx.round()) * 4;
  return (bytes.getUint8(i), bytes.getUint8(i + 1), bytes.getUint8(i + 2));
}

bool _orange((int, int, int) p) => p.$1 > 200 && p.$2 > 120 && p.$2 < 180 && p.$3 < 90;
bool _grey((int, int, int) p) =>
    (p.$1 - p.$2).abs() < 12 && (p.$2 - p.$3).abs() < 12 && p.$1 < 245 && p.$1 > 170;
bool _white((int, int, int) p) => p.$1 > 250 && p.$2 > 250 && p.$3 > 250;

void main() {
  setUpAll(() async {
    _en = await AppLocalizations.delegate.load(const Locale('en'));
  });

  testWidgets(
      'the track ends in an arrowhead at the destination: grey while the '
      'fill is short of it, orange once it reaches it', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(_order()));
    // The fill's approach over, held short of the station.
    await tester.pump(const Duration(milliseconds: 2500));
    final shot = tester.getTopLeft(find.byKey(_key));
    final dest = tester.getCenter(
            find.byKey(const ValueKey('money-steps-station-investing'))) -
        shot;
    final r = tester
            .getSize(find.byKey(const ValueKey('money-steps-station-investing')))
            .width /
        2;
    expect(r, 22, reason: 'the 44 px mark at the design size');
    // The head: its tip 3 short of the mark's edge, 14 long, 10 either
    // side of the centre line at its base.
    final tip = Offset(dest.dx - r - 3, dest.dy);
    final head = tip.translate(-5, 0);
    final base = tip.translate(-13, 0);
    // Above the head, short of its tip (and clear of the destination's
    // ring, 5 past its edge, while it works).
    final overTip = tip.translate(-4, -12);
    expect(_grey(await _pixel(tester, head)), isTrue,
        reason: 'the head is grey while the leg runs (${await _pixel(tester, head)})');
    expect(_grey(await _pixel(tester, base.translate(0, 8))), isTrue,
        reason: 'the head is wider than the track at its base');
    expect(_white(await _pixel(tester, overTip)), isTrue,
        reason: 'it narrows to its tip: nothing above the tip');
    expect(_white(await _pixel(tester, tip.translate(1.5, 0))), isTrue,
        reason: 'the tip stops short of the mark');
    // The shaft before the head is still orange where the fill got, and
    // the orange stops short of the head.
    expect(_orange(await _pixel(tester, Offset(dest.dx - r - 120, dest.dy))),
        isTrue, reason: 'the fill on its way');
    expect(_grey(await _pixel(tester, base.translate(-6, 0))), isTrue,
        reason: 'the end of the shaft before the head waits grey');

    // The leg lands: the fill reaches the head and it turns orange.
    await tester.pumpWidget(_app(_order(bitcoin: _done, convert: _run)));
    await tester.pump(const Duration(milliseconds: 1500));
    expect(_orange(await _pixel(tester, head)), isTrue,
        reason: 'the head is orange once the fill reached it');
    expect(_orange(await _pixel(tester, base.translate(-6, 0))), isTrue);
    expect(_white(await _pixel(tester, overTip)), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}
