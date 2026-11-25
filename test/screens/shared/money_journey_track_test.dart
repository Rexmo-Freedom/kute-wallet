// The journey's track (founder, 1 November 2026: "not fintech like; make
// it fintech with Blender", "must be 2026 fintech like with Sal"): one
// thin rounded line in a hairline grey, its travelled part in the
// surface's ink, simply ending at the destination's dot (no arrowhead);
// small matte station dots (a hairline ring until the money is there, a
// solid dot once it is); the big 3D Sal box walking it.

import 'dart:typed_data' show ByteData;
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
const _key = ValueKey('track-shot');

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

MoneyJourneyPainter _motion(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((w) => w.painter)
    .whereType<MoneyJourneyPainter>()
    .single;

/// The shot's pixels now.
Future<_Shot> _shot(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_key));
  final image = (await tester.runAsync(() => boundary.toImage()))!;
  final bytes = (await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
  return _Shot(bytes, image.width);
}

class _Shot {
  _Shot(this._bytes, this.width);
  final ByteData _bytes;
  final int width;

  /// The pixel at [at] (in the shot's coordinates) as (r, g, b).
  (int, int, int) at(Offset at) {
    final i = (at.dy.round() * width + at.dx.round()) * 4;
    return (_bytes.getUint8(i), _bytes.getUint8(i + 1), _bytes.getUint8(i + 2));
  }
}

// The light theme's ink (textPrimary, #1D2024), give or take antialiasing.
bool _ink((int, int, int) p) => p.$1 < 70 && p.$2 < 70 && p.$3 < 75;
// The hairline grey on white: neutral and light, never a tint.
bool _hairline((int, int, int) p) =>
    (p.$1 - p.$2).abs() < 8 &&
    (p.$2 - p.$3).abs() < 8 &&
    p.$1 > 200 &&
    p.$1 < 248;
bool _white((int, int, int) p) => p.$1 > 250 && p.$2 > 250 && p.$3 > 250;
// Within a little of [c] (antialiasing, the PNG's rounding).
bool _near((int, int, int) p, (int, int, int) c) =>
    (p.$1 - c.$1).abs() < 24 && (p.$2 - c.$2).abs() < 24 && (p.$3 - c.$3).abs() < 24;
// The Hyperliquid logo's dark green at 40% on white.
bool _quietDark((int, int, int) p) =>
    p.$1 > 130 && p.$1 < 190 && p.$2 > 140 && p.$2 < 200 && p.$3 > 140 && p.$3 < 200;

void main() {
  setUpAll(() async {
    _en = await AppLocalizations.delegate.load(const Locale('en'));
  });

  testWidgets(
      'a thin neutral line, its travelled part in the ink as far as the '
      'money got, ending at the destination\'s dot with no arrowhead',
      (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(precacheMoneyJourneyMarks);
    await tester.pumpWidget(_app(_order()));
    // The fill's approach over, held short of the station.
    await tester.pump(const Duration(milliseconds: 2500));
    final origin = tester.getTopLeft(find.byKey(_key));
    final dest = tester.getCenter(
            find.byKey(const ValueKey('money-steps-station-investing'))) -
        origin;
    final src = tester.getCenter(
            find.byKey(const ValueKey('money-steps-station-bitcoin'))) -
        origin;
    final size = tester
        .getSize(find.byKey(const ValueKey('money-steps-station-investing')));
    final r = size.width / 2;
    expect(r, 14, reason: 'a 28 px logo disc at the design size');
    expect(size.height, size.width);
    expect(src.dy, dest.dy, reason: 'one straight row');

    // The big 3D Sal: never shrunk below ~60 px.
    expect(_motion(tester).salSize, 64);
    expect(_motion(tester).salSize, greaterThanOrEqualTo(60));

    // The line runs from the source's dot to the destination's.
    final x0 = src.dx + r;
    final x1 = dest.dx - r;
    final len = x1 - x0;
    final f = _motion(tester).litOf('leg:bitcoin');
    expect(f, inExclusiveRange(0.5, 1), reason: 'held short while it runs');
    final y = dest.dy;

    final shot = await _shot(tester);
    // Travelled: in the ink, from the source to where the money got.
    final travelled = Offset(x0 + len * f * 0.4, y);
    expect(_ink(shot.at(travelled)), isTrue,
        reason: 'the travelled part (${shot.at(travelled)})');
    // Untravelled: the hairline grey between there and the destination
    // (clear of Sal, who walks behind the coin, and of the pulse).
    final ahead = Offset(x0 + len * (f + (1 - f) * 0.55), y);
    expect(_hairline(shot.at(ahead)), isTrue,
        reason: 'the untravelled part (${shot.at(ahead)})');
    // Where the ink ends is where the money got (within a few px).
    final tipX = x0 + len * f;
    expect(_ink(shot.at(Offset(tipX - 3, y))), isTrue);
    expect(_ink(shot.at(Offset(tipX + 4, y))), isFalse);

    // Thin: about 2.5 px, nothing 3 px off its centre line.
    for (final at in [travelled, ahead]) {
      expect(_white(shot.at(at.translate(0, -3))), isTrue,
          reason: 'thin above ${shot.at(at.translate(0, -3))}');
      expect(_white(shot.at(at.translate(0, 3))), isTrue,
          reason: 'thin below ${shot.at(at.translate(0, 3))}');
    }

    // No arrowhead: just before the destination's dot (outside its
    // pulse) the line is as thin as anywhere.
    final before = Offset(dest.dx - r - 12, y);
    expect(_hairline(shot.at(before)), isTrue, reason: '${shot.at(before)}');
    for (final dy in [-4.0, -6.0, 4.0, 6.0]) {
      expect(_white(shot.at(before.translate(0, dy))), isTrue,
          reason: 'no head ${dy}px off the line: ${shot.at(before.translate(0, dy))}');
    }

    // Stations: 28 px logo discs. The source (the money is there) in the
    // Bitcoin mark's full orange; the destination's Hyperliquid logo
    // quiet (part see-through) until the money is there.
    final srcTop = shot.at(src.translate(0, -0.8 * r));
    expect(_near(srcTop, (247, 147, 26)), isTrue, reason: 'the source: $srcTop');
    final destTop = shot.at(dest.translate(0, -0.8 * r));
    expect(_quietDark(destTop), isTrue,
        reason: 'the destination waits: $destTop');

    // The leg lands: the line is travelled to the destination's dot, the
    // dot fills in, the source takes its check.
    await tester.pumpWidget(_app(_order(bitcoin: _done, convert: _run)));
    await tester.pump(const Duration(milliseconds: 1500));
    expect(_motion(tester).litOf('leg:bitcoin'), 1);
    final landed = await _shot(tester);
    expect(_ink(landed.at(Offset(x1 - 3, y))), isTrue,
        reason: 'travelled all the way: ${landed.at(Offset(x1 - 3, y))}');
    final destLanded = landed.at(dest.translate(0, -0.8 * r));
    expect(_near(destLanded, (14, 36, 34)), isTrue,
        reason: 'the destination at full colour: $destLanded');
    for (final dy in [-4.0, 4.0]) {
      expect(_white(landed.at(Offset(dest.dx - r - 12, y + dy))), isTrue,
          reason: 'still no head');
    }
    expect(find.byKey(const ValueKey('money-steps-station-done-bitcoin')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}
