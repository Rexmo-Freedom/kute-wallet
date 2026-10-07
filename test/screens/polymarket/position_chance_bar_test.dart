// The open-position screen's chance bar (position_chance_bar.dart): a
// Yes / No or Up / Down market's green and red split at the Yes / Up
// chance, an outcome with its own line colour filling from the left, and
// a tick at the price paid, measured from the held side's end, under the
// chart's "Bought · X¢" tag kept inside the bar.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/screens/polymarket/components/game_chart_section.dart'
    show kGameSideColors;
import 'package:kute/screens/polymarket/components/position_chance_bar.dart';
import 'package:kute/theme/app_theme.dart';

const _w = 300.0;

Future<void> _pump(WidgetTester tester, PolyChanceBarSpec spec,
    {String? label = 'Bought · 54¢', bool reduceMotion = false}) async {
  tester.view.physicalSize = const Size(390, 400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(extensions: [AppColorsExtension.light()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(
              size: const Size(390, 400), disableAnimations: reduceMotion),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: _w,
                child: PolyPositionChanceBar(spec: spec, tickLabel: label),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

Rect _rect(WidgetTester tester, Key key) => tester.getRect(find.byKey(key));

double _fillFraction(WidgetTester tester) =>
    _rect(tester, PolyPositionChanceBar.fillKey).width /
    _rect(tester, PolyPositionChanceBar.trackKey).width;

double _tickFraction(WidgetTester tester) {
  final track = _rect(tester, PolyPositionChanceBar.trackKey);
  return (_rect(tester, PolyPositionChanceBar.tickKey).center.dx -
          track.left) /
      track.width;
}

Color _fillColor(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(find.descendant(
      of: find.byKey(PolyPositionChanceBar.fillKey),
      matching: find.byType(DecoratedBox)));
  return (box.decoration as BoxDecoration).color!;
}

Color _trackColor(WidgetTester tester) => tester
    .widget<ColoredBox>(find.descendant(
        of: find.byKey(PolyPositionChanceBar.trackKey),
        matching: find.byType(ColoredBox)))
    .color;

PolymarketPosition _position(
        {String outcome = 'Yes',
        bool resolved = false,
        bool? won,
        double price = 0.5}) =>
    PolymarketPosition(
      marketId: 'c1',
      marketQuestion: 'Q',
      outcome: outcome,
      size: 10,
      avgPrice: 0.4,
      currentPrice: price,
      pnl: 0,
      pnlPercent: 0,
      isResolved: resolved,
      won: won,
    );

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('what the bar draws', () {
    test('Yes at 62% bought at 40¢: green to 62%, red after, tick at 40% '
        'from the left', () {
      final s = polyPositionChanceBarSpec(
          outcome: 'Yes',
          chance: 0.62,
          bought: 0.40,
          fallbackColor: Colors.black);
      expect(s.value, closeTo(0.62, 1e-9));
      expect(s.left, AppColors.marketUp);
      expect(s.right, AppColors.marketDown);
      expect(s.tick, closeTo(0.40, 1e-9));
      expect(s.held, AppColors.marketUp);
    });

    test('Down at 7.5% bought at 54¢: the split at Up\'s 92.5%, the tick '
        '54% in from the right', () {
      final s = polyPositionChanceBarSpec(
          outcome: 'Down',
          chance: 0.075,
          bought: 0.54,
          fallbackColor: Colors.black);
      expect(s.value, closeTo(0.925, 1e-9));
      expect(s.left, AppColors.marketUp);
      expect(s.right, AppColors.marketDown);
      expect(s.tick, closeTo(0.46, 1e-9));
      expect(s.held, AppColors.marketDown);
    });

    test('Up and No split the same way', () {
      expect(
          polyPositionChanceBarSpec(
                  outcome: 'up', chance: 0.3, fallbackColor: Colors.black)
              .value,
          closeTo(0.3, 1e-9));
      expect(
          polyPositionChanceBarSpec(
                  outcome: 'NO', chance: 0.3, fallbackColor: Colors.black)
              .value,
          closeTo(0.7, 1e-9));
    });

    test('an outcome with its own line colour fills from the left on the '
        'neutral track, ticked from the left', () {
      final s = polyPositionChanceBarSpec(
          outcome: 'Yes',
          chance: 0.31,
          bought: 0.25,
          lineColor: kGameSideColors[0],
          fallbackColor: Colors.black);
      expect(s.value, closeTo(0.31, 1e-9));
      expect(s.left, kGameSideColors[0]);
      expect(s.right, isNull);
      expect(s.tick, closeTo(0.25, 1e-9));
      expect(s.held, kGameSideColors[0]);
    });

    test('any other outcome fills in the fallback colour', () {
      final s = polyPositionChanceBarSpec(
          outcome: 'Over', chance: 0.6, fallbackColor: Colors.teal);
      expect(s.left, Colors.teal);
      expect(s.right, isNull);
      expect(s.tick, isNull);
    });

    test('no price paid on record: no tick', () {
      for (final b in [null, 0.0, 1.5]) {
        expect(
            polyPositionChanceBarSpec(
                    outcome: 'Yes',
                    chance: 0.5,
                    bought: b,
                    fallbackColor: Colors.black)
                .tick,
            isNull);
      }
    });

    test('resolved: all or nothing by the result, the live price while '
        'open', () {
      expect(polyPositionBarChance(_position(), 0.37), closeTo(0.37, 1e-9));
      expect(
          polyPositionBarChance(_position(resolved: true, won: true), 0.2),
          1.0);
      expect(
          polyPositionBarChance(_position(resolved: true, won: false), 0.9),
          0.0);
      expect(polyPositionBarChance(_position(resolved: true), 0.999), 1.0);
      expect(polyPositionBarChance(_position(resolved: true), 0.001), 0.0);
    });
  });

  group('the bar', () {
    testWidgets('Down at 7.5% bought 54¢: the split at 92.5%, green then '
        'red, the tick at 46%, its tag over it', (tester) async {
      await _pump(
          tester,
          polyPositionChanceBarSpec(
              outcome: 'Down',
              chance: 0.075,
              bought: 0.54,
              fallbackColor: Colors.black));
      expect(_fillFraction(tester), closeTo(0.925, 0.01));
      expect(_fillColor(tester), AppColors.marketUp);
      expect(_trackColor(tester), AppColors.marketDown);
      expect(_tickFraction(tester), closeTo(0.46, 0.01));
      expect(find.text('Bought · 54¢'), findsOneWidget);
      final tag = _rect(tester, PolyPositionChanceBar.labelKey);
      expect(tag.center.dx,
          closeTo(_rect(tester, PolyPositionChanceBar.tickKey).center.dx, 0.5));
      expect(tag.bottom,
          lessThanOrEqualTo(_rect(tester, PolyPositionChanceBar.tickKey).top));
      // The tag is written in the held side's colour.
      expect(tester.widget<Text>(find.text('Bought · 54¢')).style?.color,
          AppColors.marketDown);
      // The chance is not written again.
      expect(find.textContaining('%'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a team\'s outcome: its colour on the neutral track',
        (tester) async {
      await _pump(
          tester,
          polyPositionChanceBarSpec(
              outcome: '49ers',
              chance: 0.64,
              bought: 0.42,
              lineColor: kGameSideColors[0],
              fallbackColor: Colors.black),
          label: 'Bought · 42¢');
      expect(_fillFraction(tester), closeTo(0.64, 0.01));
      expect(_fillColor(tester), kGameSideColors[0]);
      expect(_trackColor(tester), AppColorsExtension.light().border);
      expect(_tickFraction(tester), closeTo(0.42, 0.01));
    });

    testWidgets('a tag near either end stays inside the bar', (tester) async {
      for (final (b, text) in [(0.02, 'Bought · 2.0¢'), (0.98, 'Bought · 98¢')]) {
        await _pump(
            tester,
            polyPositionChanceBarSpec(
                outcome: 'Yes',
                chance: 0.5,
                bought: b,
                fallbackColor: Colors.black),
            label: text);
        final track = _rect(tester, PolyPositionChanceBar.trackKey);
        final tag = _rect(tester, PolyPositionChanceBar.labelKey);
        final tick = _rect(tester, PolyPositionChanceBar.tickKey);
        expect(tag.left, greaterThanOrEqualTo(track.left - 0.01), reason: text);
        expect(tag.right, lessThanOrEqualTo(track.right + 0.01), reason: text);
        if (b < 0.5) {
          expect(tag.left, closeTo(track.left, 0.01));
        } else {
          expect(tag.right, closeTo(track.right, 0.01));
        }
        // The tick itself stays at the price, inside the bar.
        expect(tick.left, greaterThanOrEqualTo(track.left));
        expect(tick.right, lessThanOrEqualTo(track.right));
        expect(_tickFraction(tester), closeTo(b, 0.01));
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('won: the bar full, the tick still at the price paid',
        (tester) async {
      await _pump(
          tester,
          polyPositionChanceBarSpec(
              outcome: 'Yes',
              chance: polyPositionBarChance(
                  _position(resolved: true, won: true), 1),
              bought: 0.4,
              fallbackColor: Colors.black),
          label: 'Bought · 40¢');
      expect(_fillFraction(tester), closeTo(1, 0.001));
      expect(_tickFraction(tester), closeTo(0.4, 0.01));
    });

    testWidgets('lost on Yes: no green left', (tester) async {
      await _pump(
          tester,
          polyPositionChanceBarSpec(
              outcome: 'Yes',
              chance: polyPositionBarChance(
                  _position(resolved: true, won: false), 0),
              bought: 0.4,
              fallbackColor: Colors.black),
          label: 'Bought · 40¢');
      expect(_fillFraction(tester), closeTo(0, 0.001));
    });

    testWidgets('a new price eases the split over 300 ms', (tester) async {
      PolyChanceBarSpec at(double p) => polyPositionChanceBarSpec(
          outcome: 'Yes', chance: p, bought: 0.4, fallbackColor: Colors.black);
      await _pump(tester, at(0.2));
      // No grow-in on open.
      expect(_fillFraction(tester), closeTo(0.2, 0.01));
      await _pump(tester, at(0.8));
      await tester.pump(const Duration(milliseconds: 100));
      final mid = _fillFraction(tester);
      expect(mid, greaterThan(0.21));
      expect(mid, lessThan(0.79));
      await tester.pump(const Duration(milliseconds: 250));
      expect(_fillFraction(tester), closeTo(0.8, 0.01));
    });

    testWidgets('reduced motion: the split jumps to the new price',
        (tester) async {
      PolyChanceBarSpec at(double p) => polyPositionChanceBarSpec(
          outcome: 'Yes', chance: p, bought: 0.4, fallbackColor: Colors.black);
      await _pump(tester, at(0.2), reduceMotion: true);
      await _pump(tester, at(0.8), reduceMotion: true);
      expect(_fillFraction(tester), closeTo(0.8, 0.01));
      expect(
          tester
              .widget<TweenAnimationBuilder<double>>(
                  find.byType(TweenAnimationBuilder<double>))
              .duration,
          Duration.zero);
    });

    testWidgets('no price paid: no tick and no tag', (tester) async {
      await _pump(
          tester,
          polyPositionChanceBarSpec(
              outcome: 'Yes', chance: 0.5, fallbackColor: Colors.black));
      expect(find.byKey(PolyPositionChanceBar.tickKey), findsNothing);
      expect(find.byKey(PolyPositionChanceBar.labelKey), findsNothing);
    });
  });
}
