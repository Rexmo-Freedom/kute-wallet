// The momentum graph's axis: period names that would run into each other
// are left out, the first and the latest kept.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/polymarket_game_momentum_provider.dart';
import 'package:kute/screens/polymarket/components/momentum_strip.dart';
import 'package:kute/services/polymarket/live_game/game_momentum.dart';
import 'package:kute/theme/app_theme.dart';

const _min = 60000;

class _Fixed extends PolyGameMomentumNotifier {
  @override
  PolyGameMomentum build(PolyMomentumKey arg) => PolyGameMomentum(
        strip: buildMomentum(
          a: [
            for (var i = 0; i <= 60; i++)
              (tMs: i * _min, p: 0.5 + ((i % 7) - 3) / 50),
          ],
          startMs: 0,
          endMs: 60 * _min,
        ),
        loaded: true,
      );
}

/// A read that a test can move on: [bump] lands a fresh strip, as a live
/// tick does.
class _Ticking extends PolyGameMomentumNotifier {
  int _n = 0;
  @override
  PolyGameMomentum build(PolyMomentumKey arg) => _read();

  PolyGameMomentum _read() => PolyGameMomentum(
        strip: buildMomentum(
          a: [
            for (var i = 0; i <= 60; i++)
              (tMs: i * _min, p: 0.5 + (((i + _n) % 7) - 3) / 50),
          ],
          startMs: 0,
          endMs: 60 * _min,
        ),
        loaded: true,
      );

  void bump() {
    _n++;
    state = _read();
  }
}

const PolyMomentumKey _growKey = (
  gameId: '3',
  tokenA: 'a',
  tokenB: 'b',
  startMs: 0,
  endMs: 60 * _min,
  axisMs: null,
);

Future<void> _pumpStrip(WidgetTester tester, {bool reduceMotion = false}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [polyGameMomentumProvider.overrideWith(_Ticking.new)],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(extensions: [AppColorsExtension.light()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: reduceMotion),
            child: const Scaffold(
              body: PolyMomentumStrip(
                momentumKey: _growKey,
                nameA: 'Home',
                nameB: 'Away',
                colorA: Color(0xFF4FC3F7),
                colorB: Color(0xFFCE93D8),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
}

/// How far the wave has grown out of the centre line (0..1).
double _grown(WidgetTester tester) {
  final paint = tester
      .widgetList<CustomPaint>(find.descendant(
          of: find.byType(PolyMomentumStrip),
          matching: find.byType(CustomPaint)))
      .firstWhere(
          (p) => p.painter.runtimeType.toString() == '_MomentumPainter');
  return ((paint.painter as dynamic).grow as Animation<double>).value;
}

void main() {
  testWidgets('the wave grows out of the centre line once, not on every '
      'read', (tester) async {
    await _pumpStrip(tester);
    expect(_grown(tester), 0);
    await tester.pump(const Duration(milliseconds: 120));
    final mid = _grown(tester);
    expect(mid, greaterThan(0));
    expect(mid, lessThan(1));
    await tester.pumpAndSettle();
    expect(_grown(tester), 1);

    // A live read redraws the wave in place: no second grow.
    final container = ProviderScope.containerOf(
        tester.element(find.byType(PolyMomentumStrip)));
    (container.read(polyGameMomentumProvider(_growKey).notifier) as _Ticking)
        .bump();
    await tester.pump();
    expect(_grown(tester), 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('under Reduce Motion the wave is whole from the first frame',
      (tester) async {
    await _pumpStrip(tester, reduceMotion: true);
    expect(_grown(tester), 1);
  });

  testWidgets('crowded period names thin out; the ends stay', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const PolyMomentumKey key = (
      gameId: '1',
      tokenA: 'a',
      tokenB: 'b',
      startMs: 0,
      endMs: 60 * _min,
      axisMs: null,
    );
    // An inning every three minutes: far more names than the axis holds.
    final notches = <MomentumNotch>[
      for (var i = 1; i <= 18; i++)
        (tMs: i * 3 * _min, color: Colors.grey, divider: true, label: '$i'),
    ];
    await tester.pumpWidget(ProviderScope(
      overrides: [polyGameMomentumProvider.overrideWith(_Fixed.new)],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: ThemeData(extensions: [AppColorsExtension.light()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: PolyMomentumStrip(
                momentumKey: key,
                nameA: 'San Diego Padres',
                nameB: 'Milwaukee Brewers',
                colorA: const Color(0xFFCE93D8),
                colorB: const Color(0xFF4FC3F7),
                notches: notches,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('San Diego Padres'), findsOneWidget);
    // The first inning named and the latest one are there.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('18'), findsOneWidget);
    // No two names touch.
    final rects = [
      for (var i = 1; i <= 18; i++)
        if (find.text('$i').evaluate().isNotEmpty) tester.getRect(find.text('$i')),
    ]..sort((a, b) => a.left.compareTo(b.left));
    expect(rects.length, greaterThan(2));
    for (var i = 1; i < rects.length; i++) {
      expect(rects[i].left, greaterThan(rects[i - 1].right));
    }
  });

  // The names were measured with no font family (the system face on a
  // phone, the test binding's block face here) and drawn in the app's
  // own: "HT" measured too wide and pushed "Q3" off the axis of a real
  // NFL game (Broncos at 49ers, 2026-10-04: half-time 14 minutes long).
  testWidgets('names are measured in the face they are drawn in',
      (tester) async {
    final loader = FontLoader('Inter')
      ..addFont(rootBundle.load('lib/assets/fonts/Inter-Regular.ttf'))
      ..addFont(rootBundle.load('lib/assets/fonts/Inter-SemiBold.ttf'));
    await loader.load();
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const PolyMomentumKey key = (
      gameId: '2',
      tokenA: 'a',
      tokenB: 'b',
      startMs: 0,
      endMs: 60 * _min,
      axisMs: null,
    );
    // Where that game's periods fell on its axis, as fractions of it.
    MomentumNotch at(double fraction, String label) => (
          tMs: (fraction * 60 * _min).round(),
          color: Colors.grey,
          divider: true,
          label: label,
        );
    await tester.pumpWidget(ProviderScope(
      overrides: [polyGameMomentumProvider.overrideWith(_Fixed.new)],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: ThemeData(
            fontFamily: 'Inter',
            extensions: [AppColorsExtension.light()],
          ),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: PolyMomentumStrip(
                momentumKey: key,
                nameA: 'Broncos',
                nameB: '49ers',
                colorA: const Color(0xFF4FC3F7),
                colorB: const Color(0xFFCE93D8),
                startLabel: 'Q1',
                notches: [
                  at(0.206, 'Q2'),
                  at(0.514, 'HT'),
                  at(0.588, 'Q3'),
                  at(0.775, 'Q4'),
                ],
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    for (final name in ['Q1', 'Q2', 'HT', 'Q3', 'Q4']) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    expect(tester.getRect(find.text('Q3')).left,
        greaterThan(tester.getRect(find.text('HT')).right));
  });
}
